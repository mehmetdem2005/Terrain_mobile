@tool
extends EditorPlugin

const TerrainNode = preload("res://addons/mobile_terrain/mobile_terrain_node.gd")
var selected_node = null
var is_sculpting = false

# UI Elements
var ui_container: MarginContainer
var toolbar: HBoxContainer
var brush_cursor: MeshInstance3D # V21: mesh-based draping cursor, see _create_brush_cursor

var tool_opt: OptionButton
var shape_opt: OptionButton
var texture_opt: OptionButton
var object_opt: OptionButton
var radius_slider: HSlider
var radius_spinbox: SpinBox
var strength_slider: HSlider
var strength_spinbox: SpinBox
# V21: Re-entrancy guard for slider ↔ spinbox sync. When the user drags
# the slider, we copy its value into the spinbox; that triggers
# SpinBox.value_changed which would otherwise feed back into the slider,
# producing a phantom event. Setting this flag around the cross-update
# breaks the loop. SpinBox.set_value_no_signal would also work but the
# semantics get fragile when both signals fire on the same frame.
var _syncing_brush_controls: bool = false

var asset_manager_panel: PanelContainer
var tex_list_vbox: VBoxContainer
var obj_list_vbox: VBoxContainer
# V21: track the "+" button so _refresh_manager_ui can disable it
# when terrain_textures hits the 4-slot splatmap cap (see _add_texture_slot).
var btn_add_tex: Button

# V21: brush mask picker — opened from the toolbar button. The popup
# grid contains a TextureButton per .png in brushes/. Clicking one sets
# selected_node.brush_mask and closes the popup. Built once in
# _enter_tree, re-populated on demand by _populate_brush_mask_grid.
var brush_mask_picker_btn: Button
# V21: master toggle for brush input. When false, _forward_3d_gui_input
# returns PASS for all mouse events so the user can zoom/pan the
# viewport without accidentally sculpting. Default true so the addon
# stays drop-in for existing users.
var brush_enabled: bool = true
# V21: re-save guard. Godot's _save_external_data hook fires AFTER the
# .tscn has already been written, not before — so the textbook approach
# (wipe data, return, let the save happen with empty arrays) doesn't
# work. The actual save sequence is:
#   1. user hits Ctrl+S
#   2. Godot serialises the scene → .tscn written with inline 26 MB
#   3. Godot calls our _save_external_data → too late
# Our workaround: in step 3 we wipe the data, write the .res, then
# trigger a SECOND save_scene programmatically. That second pass writes
# the .tscn with the now-empty inline fields (small file). The flag
# below prevents the recursion: when the second save fires
# _save_external_data again, we just restore and exit.
var _suppress_next_save_hook: bool = false
var brush_toggle_btn: Button
# V21 FIX: cache the most recent editor camera so we can re-raycast on
# brush-toggle-on without depending on the EditorInterface API
# (which had subtle changes between Godot 4.0 / 4.1 / 4.2+ that risked
# parse-time failures on older runtimes). Set on every input event we
# receive; cleared on _make_visible(false) so we don't hold a stale
# reference into a destroyed viewport.
var _cached_camera: Camera3D = null
var _cached_mouse_pos: Vector2 = Vector2.ZERO
var brush_mask_popup: PopupPanel
var brush_mask_grid: GridContainer
var brush_mask_label: Label  # "current: <name>" inside the popup
# Cached list of (filename, Texture2D) tuples discovered in brushes/.
# Refreshing this is the "Yenile" button's job; we don't auto-refresh
# because new masks are rare and rescanning costs disk I/O.
var _brush_mask_cache: Array = []

var undo_redo: EditorUndoRedoManager
var heightmap_backup: PackedFloat32Array
var splatmap_backup: PackedByteArray

# V20 FIX: Per-stroke object placement bookkeeping.
#
# Object placement (tool 8) doesn't touch height_data or splatmap_data —
# it grows MultiMesh.instance_count and writes a Transform3D. The
# property-based undo path used for sculpt/paint can't see those changes,
# so we have to record them out-of-band.
#
# Strategy: while the user holds the mouse down, the node emits
# `foliage_placed` for every placement. We accumulate those into
# `placement_records` and, on mouse release, build a single combined
# undo action covering the entire stroke.
#
# `placement_initial_counts` remembers each MultiMesh's instance_count
# at the moment of its FIRST placement in the stroke. That's what undo
# rewinds back to. Recording it lazily (on first placement, not at
# mouse-down) means we never snapshot multimeshes that aren't touched.
var placement_records: Array = []              # [{mmi, index, transform}, ...]
var placement_initial_counts: Dictionary = {}  # MultiMeshInstance3D -> int

func _get_plugin_name() -> String:
	return "MobileTerrain3D"

func _enter_tree() -> void:
	print("=== [MobileTerrain3D] Plugin _enter_tree() FIRED ===")
	print("[MobileTerrain3D] If you see this, the plugin is loaded.")
	print("[MobileTerrain3D] On scene save, you should see _save_external_data() fire too.")
	undo_redo = get_undo_redo()
	add_custom_type("MobileTerrain3D", "Node3D", TerrainNode, null)
	
	_build_main_ui()
	_build_asset_manager_ui()
	
	# V20 FIX: Brush cursor lifecycle.
	#
	# The previous implementation parented the Decal to
	# `get_editor_main_screen()` which returns a Control. A Decal is a Node3D
	# and only renders when it lives inside a World3D — a Control has no
	# World3D, so the decal was tree-attached but invisible (no error, no
	# warning, just silent failure).
	#
	# Fix: create the Decal here but leave it unparented. It will be attached
	# to the currently-selected terrain in `_edit()` (which guarantees it
	# lives in the edited scene's World3D), and detached when editing stops.
	# See `_attach_brush_cursor_to()` for the attachment policy.
	_create_brush_cursor()

# V20 FIX: Brush cursor lifecycle helpers.
# These keep the Decal in the correct World3D without polluting the saved
# scene or the Scene dock. See the comment in `_enter_tree()` for context.

func _create_brush_cursor() -> void:
	# V21: mask-textured draping grid cursor.
	#
	# Earlier V21 iterations tried a Decal (size.y=1000 → painted whole
	# vertical columns of tall terrain) then a triangle-fan disc (always
	# circular regardless of mask). Both failed the "user should SEE
	# exactly what the brush will affect" test.
	#
	# This iteration: an NxN grid of vertices spanning radius*2 across,
	# each vertex's Y sampled from terrain height (the draping), and the
	# brush MASK texture mapped 1:1 over the grid via UVs. The material
	# uses the mask as the albedo so the visible shape on the terrain
	# matches the falloff that brush_shape_falloff will produce when
	# painting. peak.png shows a tiny dot, ring_thin.png shows a ring,
	# star.png shows a star, etc. No mask set → albedo defaults white
	# (full disc, like the V19 cursor).
	brush_cursor = MeshInstance3D.new()
	brush_cursor.name = "_MobileTerrainBrushCursor"
	brush_cursor.top_level = true
	brush_cursor.mesh = ImmediateMesh.new()
	
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.4, 0.2, 0.5)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# vertex_color_use_as_albedo: lets per-vertex alpha (set when we
	# build the mesh) modulate transparency, useful for soft-edge masks
	# without a texture binding.
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = false
	mat.render_priority = 64
	brush_cursor.material_override = mat
	
	brush_cursor.hide()

# V21: remember the last brush hit so slider changes can rebuild the
# cursor geometry without the user having to move their finger first.
# Vector3.INF = "no hit yet, cursor isn't visible".
var _last_brush_hit: Vector3 = Vector3.INF

func _attach_brush_cursor_to(target: Node) -> void:
	if target == null: return
	# If the cursor was auto-freed because its previous parent was destroyed
	# (e.g. user deleted the terrain without going through deselect first),
	# recreate it transparently.
	if not is_instance_valid(brush_cursor):
		_create_brush_cursor()
	var current_parent := brush_cursor.get_parent()
	if current_parent == target: return
	if current_parent != null:
		current_parent.remove_child(brush_cursor)
	# INTERNAL_MODE_BACK: hides the cursor from the Scene dock so the user
	# doesn't see "_MobileTerrainBrushCursor" mixed in with their scene.
	# We deliberately do NOT set owner — without an owner, the node is not
	# serialized into the .tscn file, so the user's scene stays clean.
	target.add_child(brush_cursor, false, Node.INTERNAL_MODE_BACK)

func _detach_brush_cursor() -> void:
	if not is_instance_valid(brush_cursor): return
	brush_cursor.hide()
	var p := brush_cursor.get_parent()
	if p != null:
		p.remove_child(brush_cursor)
	# V21: cursor is no longer attached to anything — invalidate the
	# saved hit point so the next slider/mask change doesn't try to
	# rebuild geometry against the now-orphaned mesh's stale anchor.
	_last_brush_hit = Vector3.INF

# V21: brush stroke just modified the heightmap. Rebuild the cursor
# geometry so it sits on the NEW terrain, not the pre-stroke shape.
# Cheap (~400 get_pixel-style get_height samples) — called at most
# 25Hz thanks to the rate limit inside apply_brush_stroke_slope.
func _on_brush_applied(hit_point: Vector3) -> void:
	_conform_brush_to_surface(hit_point)

# V20 FIX: Object placement signal handler.
# Called by the node whenever a foliage instance is placed during a stroke.
# We just append; the commit happens on mouse release in _commit_placement_undo.
func _on_foliage_placed(mmi: MultiMeshInstance3D, index: int, tf: Transform3D) -> void:
	if not is_instance_valid(mmi):
		return
	# First time this multimesh is touched in the current stroke: record
	# the count to rewind to. `index` IS the count before this placement,
	# so we don't have to peek into the multimesh — saves one indirection
	# and avoids a race if the multimesh is being modified elsewhere.
	if not placement_initial_counts.has(mmi):
		placement_initial_counts[mmi] = index
	placement_records.append({"mmi": mmi, "index": index, "transform": tf})

# V20 FIX: Build the combined undo action for an object-placement stroke.
# Called from the mouse-up branch of _forward_3d_gui_input.
func _commit_placement_undo() -> void:
	if placement_records.is_empty(): return
	undo_redo.create_action("Terrain Place Objects")
	
	# Phase 1: instance_count delta for every multimesh that was touched.
	# Filter out any multimeshes that have been freed since (e.g. the user
	# removed an asset slot mid-stroke, triggering garbage_collect_multimeshes).
	# Including a freed reference would crash on undo execution.
	for mmi in placement_initial_counts.keys():
		if not is_instance_valid(mmi) or mmi.multimesh == null:
			continue
		var mm: MultiMesh = mmi.multimesh
		var initial: int = placement_initial_counts[mmi]
		var final: int = mm.instance_count
		if final == initial:
			continue # Defensive: nothing actually changed
		# Order: count up first (do), then transforms; count down (undo)
		# alone is enough — transforms past the new count aren't rendered.
		undo_redo.add_do_property(mm, "instance_count", final)
		undo_redo.add_undo_property(mm, "instance_count", initial)
	
	# Phase 2: re-set every transform on redo. MultiMesh may discard data
	# past instance_count when the buffer shrinks, so we cannot trust the
	# new transforms to survive an undo→redo round trip without rewriting.
	# Note: we deliberately don't add undo entries here. The undo path
	# only needs to shrink the count; whatever stale data sits past the
	# count is invisible and harmless.
	for placement in placement_records:
		var mmi: MultiMeshInstance3D = placement.mmi
		if not is_instance_valid(mmi) or mmi.multimesh == null:
			continue
		undo_redo.add_do_method(mmi.multimesh, "set_instance_transform", placement.index, placement.transform)
	
	undo_redo.commit_action(false)
	# Don't clear placement_records here — mouse-down does it for every
	# new stroke. Clearing here would risk wiping data if commit_action
	# triggered a synchronous side-effect that somehow re-emitted (paranoid
	# but cheap to be defensive about).

# V20 FIX (#15): lazy snapshot. Called immediately before each brush
# application within a stroke. Populates the appropriate backup on
# first invocation; subsequent calls are cheap no-ops (just a size
# check).
#
# This replaces the previous eager duplicate-on-mouse-down model. Two
# wins:
#   - Mouse-downs that don't end up modifying terrain (raymarch miss,
#     quick click without drag, or just hovering with mouse down) no
#     longer cost a 256KB array copy.
#   - The mouse-up undo branch checks `backup.size() > 0` to decide
#     whether to record an undo entry. With lazy backup, an empty stroke
#     leaves both backups empty, so no no-op "Terrain Modify" undo entry
#     gets created — keeps the undo history clean.
#
# Object placement (tool 8) deliberately falls through with no action:
# it uses signal-based per-stroke recording (see _on_foliage_placed) and
# has no buffer backup to populate.
func _ensure_backup_for_current_tool() -> void:
	if not selected_node: return
	match selected_node.current_tool:
		7: # Paint
			if splatmap_backup.is_empty():
				splatmap_backup = selected_node.splatmap_data.duplicate()
		8: # Object — signal-based recording handles it
			pass
		_: # All sculpt tools (0..6)
			if heightmap_backup.is_empty():
				heightmap_backup = selected_node.height_data.duplicate()

# V20 FIX: Disconnect signals from a node we're about to stop editing.
# Safe to call with null or an already-freed reference. V21 extended to
# also drop brush_applied — same lifecycle, same need to clean up so
# the connection doesn't leak across scene switches.
func _disconnect_placement_signal(node) -> void:
	if not is_instance_valid(node): return
	if node.foliage_placed.is_connected(_on_foliage_placed):
		node.foliage_placed.disconnect(_on_foliage_placed)
	# V21: same teardown for brush_applied. The `has_signal` check
	# protects against old saved instances created before V21 was
	# loaded — they don't have this signal in their script.
	if node.has_signal("brush_applied") and node.brush_applied.is_connected(_on_brush_applied):
		node.brush_applied.disconnect(_on_brush_applied)

# V21: removed _generate_decal_texture. It generated shape-bitmap
# textures for the old Decal-based cursor. The new mesh cursor doesn't
# use textures (geometry encodes the shape), so this function had no
# callers. ~40 lines of dead pixel-loop code removed.

func _build_main_ui():
	ui_container = MarginContainer.new()
	ui_container.hide()
	ui_container.add_theme_constant_override("margin_left", 10)
	ui_container.add_theme_constant_override("margin_top", 10)
	
	var vbox = VBoxContainer.new()
	ui_container.add_child(vbox)
	
	var scroll = ScrollContainer.new()
	# V21: panel-width strategy. Tried `SIZE_EXPAND_FILL` on the outer
	# MarginContainer to grab parent width — didn't work because
	# CONTAINER_SPATIAL_EDITOR_MENU is an HFlowContainer that lays children
	# at their NATURAL width and wraps to the next row when full; it
	# ignores expand flags on direct children.
	#
	# Final approach: pin a wide structural minimum on the ScrollContainer
	# (1100×45) so the toolbar reserves that much horizontal real estate,
	# then mark the sliders inside the toolbar SIZE_EXPAND_FILL so they
	# absorb the extra width and look proportional. On narrower screens
	# (small tablet portrait) the horizontal scrollbar appears — graceful
	# fallback rather than clipping.
	scroll.custom_minimum_size = Vector2(1100, 45)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	
	toolbar = HBoxContainer.new()
	# Grow to fill the scroll's wider footprint. Without this the toolbar
	# would sit at the sum of its children's min widths (~700px) and the
	# right portion of the scroll would be empty.
	toolbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(toolbar)
	
	# V21: brush master toggle. Positioned FIRST in the toolbar so it's
	# easy to reach on mobile — zoom/pan gestures need the brush off to
	# avoid accidental edits, and reaching across the toolbar to toggle
	# is exactly the friction that makes users disable plugins. With it
	# at the left edge, thumb-toggle stays in flow.
	#
	# Toggle button (not a checkbox) because:
	#   - Visual state is loud (green=on / red=off background)
	#   - One tap = one action — no "did the checkbox flip" ambiguity
	#   - Big tap target on touch screens
	brush_toggle_btn = Button.new()
	brush_toggle_btn.toggle_mode = true
	brush_toggle_btn.button_pressed = brush_enabled
	brush_toggle_btn.custom_minimum_size = Vector2(110, 0)
	brush_toggle_btn.toggled.connect(_on_brush_toggle)
	_apply_brush_toggle_style()
	toolbar.add_child(brush_toggle_btn)
	
	toolbar.add_child(VSeparator.new())
	
	var label = Label.new()
	label.text = " Araç: "
	toolbar.add_child(label)
	
	tool_opt = OptionButton.new()
	tool_opt.add_item("⛰️ Yükselt", 0)
	tool_opt.add_item("🕳️ Alçalt", 1)
	tool_opt.add_item("📏 Düzleştir", 2)
	tool_opt.add_item("💧 Yumuşat", 3)
	tool_opt.add_item("🪨 Pürüzlendir", 4)
	tool_opt.add_item("🪜 Terasla", 5)
	tool_opt.add_item("📉 Erozyon", 6) # V19 PRO TOOL
	tool_opt.add_item("🖌️ Boya", 7)
	tool_opt.add_item("🌳 Obje Ekle", 8)
	tool_opt.item_selected.connect(_on_tool_selected)
	toolbar.add_child(tool_opt)
	
	texture_opt = OptionButton.new()
	texture_opt.name = "TextureOpt"
	# V21: callback resolves index → id, same reason as _on_tool_selected.
	# When a slot is deleted, the remaining slots keep their original IDs
	# (e.g. delete slot 1 → remaining items have IDs 0, 2, 3 at indices
	# 0, 1, 2). Passing the raw idx would set current_paint_slot to the
	# WRONG slot, scrambling subsequent paint strokes.
	texture_opt.item_selected.connect(func(idx):
		if selected_node: selected_node.current_paint_slot = texture_opt.get_item_id(idx))
	texture_opt.hide()
	toolbar.add_child(texture_opt)
	
	object_opt = OptionButton.new()
	object_opt.name = "ObjectOpt"
	# V21: same id-not-index resolution as texture_opt above.
	object_opt.item_selected.connect(func(idx):
		if selected_node: selected_node.current_object_slot = object_opt.get_item_id(idx))
	object_opt.hide()
	toolbar.add_child(object_opt)
	
	var shape_label = Label.new()
	shape_label.text = " Fırça: "
	toolbar.add_child(shape_label)
	
	shape_opt = OptionButton.new()
	shape_opt.add_item("Yumuşak", 0)
	shape_opt.add_item("Keskin", 1)
	shape_opt.add_item("Kare", 2)
	shape_opt.add_item("Elmas", 3)
	shape_opt.add_item("Gürültü", 4)
	shape_opt.item_selected.connect(_on_shape_selected)
	toolbar.add_child(shape_opt)
	
	var r_label = Label.new()
	r_label.text = " Çap:"
	toolbar.add_child(r_label)
	
	radius_slider = HSlider.new()
	# V21: SIZE_EXPAND_FILL with a generous min width. With the toolbar
	# itself now SIZE_EXPAND_FILL inside an 1100-px scroll, the two
	# sliders end up sharing whatever horizontal slack is left over from
	# fixed-width controls (~250-300px each in practice). That's enough
	# drag resolution that single-step changes feel precise.
	radius_slider.custom_minimum_size = Vector2(180, 0)
	radius_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	radius_slider.min_value = 1.0
	radius_slider.max_value = 50.0
	radius_slider.step = 1.0
	radius_slider.value = 8.0
	radius_slider.value_changed.connect(_on_radius_slider_changed)
	toolbar.add_child(radius_slider)
	
	# V21: Numeric input next to the slider. Solves two problems:
	# (a) on touch screens, dragging a slider to a SPECIFIC value (say,
	#     12 exactly) is fiddly — the spinbox lets the user type it.
	# (b) the slider gives no precise readout — users couldn't tell
	#     whether they were at 8 or 9 without zooming in. Spinbox shows
	#     the current value as text and updates live as the slider moves.
	# Two-way bound via _syncing_brush_controls re-entrancy guard.
	radius_spinbox = SpinBox.new()
	radius_spinbox.min_value = 1.0
	radius_spinbox.max_value = 50.0
	radius_spinbox.step = 1.0
	radius_spinbox.value = 8.0
	radius_spinbox.custom_minimum_size = Vector2(80, 0)
	radius_spinbox.value_changed.connect(_on_radius_spinbox_changed)
	toolbar.add_child(radius_spinbox)
	
	var s_label = Label.new()
	s_label.text = " Güç:"
	toolbar.add_child(s_label)
	
	strength_slider = HSlider.new()
	strength_slider.custom_minimum_size = Vector2(180, 0)
	strength_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strength_slider.min_value = 0.1
	# V21 STABILITY FIX: was 5.0. At max=5 with 25Hz rate limit, a
	# stationary tap added 125 height units per second — the "vertical
	# columns" the user reported in early screenshots. 2.0 caps a
	# stationary tap at 50/sec (still aggressive but recoverable with
	# Smooth) while leaving plenty of headroom above the 0.2 default.
	# Range now matches the [0.0, 2.0] convention shared by
	# normal_strength / roughness_multiplier — one mental model for all
	# brush-style sliders.
	strength_slider.max_value = 2.0
	strength_slider.step = 0.05
	strength_slider.value = 0.2
	strength_slider.value_changed.connect(_on_strength_slider_changed)
	toolbar.add_child(strength_slider)
	
	strength_spinbox = SpinBox.new()
	strength_spinbox.min_value = 0.1
	strength_spinbox.max_value = 2.0
	strength_spinbox.step = 0.05
	strength_spinbox.value = 0.2
	strength_spinbox.custom_minimum_size = Vector2(80, 0)
	strength_spinbox.value_changed.connect(_on_strength_spinbox_changed)
	toolbar.add_child(strength_spinbox)
	
	var sep = VSeparator.new()
	toolbar.add_child(sep)
	
	# V21: brush-mask picker button. Opens a popup grid of all PNG masks
	# in addons/mobile_terrain/brushes/ — see _build_brush_mask_picker
	# and _show_brush_mask_picker. Sits between the brush controls and
	# the asset-manager button so it lives with the painting controls,
	# not the asset library.
	brush_mask_picker_btn = Button.new()
	brush_mask_picker_btn.text = "🖌 Maske"
	brush_mask_picker_btn.tooltip_text = "Fırça maskesini seç (şekil, gürültü, ring, splotch...)"
	brush_mask_picker_btn.pressed.connect(_show_brush_mask_picker)
	toolbar.add_child(brush_mask_picker_btn)
	
	var sep2 = VSeparator.new()
	toolbar.add_child(sep2)
	
	var btn_mgr = Button.new()
	btn_mgr.text = "Varlıkları Yönet"
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.4, 0.8)
	btn_mgr.add_theme_stylebox_override("normal", style)
	btn_mgr.pressed.connect(_toggle_asset_manager)
	toolbar.add_child(btn_mgr)
	
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, ui_container)
	
	# V21: brush-mask popup is built lazily on FIRST press of the toolbar
	# button. Why not eagerly here in _enter_tree like the asset manager?
	# Because the editor's filesystem hasn't finished its initial import
	# pass yet at plugin-load time — calling load("res://addons/mobile_terrain/brushes/foo.png")
	# in _enter_tree races the importer and prints "Failed loading
	# resource" errors. By the time the user clicks the 🖌 Maske button,
	# the filesystem is settled, every PNG has a real .ctex sidecar, and
	# load() returns a Texture2D cleanly.

func _on_texture_slot_selected(idx: int):
	if selected_node:
		selected_node.current_paint_slot = idx

func _on_object_slot_selected(idx: int):
	if selected_node:
		selected_node.current_object_slot = idx

# V21: BRUSH MASK PICKER
#
# A popup grid of 64×64 thumbnails — one per .png/.exr in
# addons/mobile_terrain/brushes/. Clicking a thumbnail assigns it to
# selected_node.brush_mask, which the node's get_pixel-based falloff
# sampler uses (see brush_shape_falloff in node.gd). The popup also has
# a "✕ Maske Yok" button to clear the mask and a "↻ Yenile" button to
# re-scan the folder for newly-added files.

const BRUSHES_DIR := "res://addons/mobile_terrain/brushes/"

func _build_brush_mask_picker() -> void:
	brush_mask_popup = PopupPanel.new()
	brush_mask_popup.transient = true
	brush_mask_popup.exclusive = false
	# Anchor as child of the editor base so it lives across scene changes.
	# We can't add directly to ui_container — popups want to be at the top
	# of the tree so they don't get clipped by containers.
	get_editor_interface().get_base_control().add_child(brush_mask_popup)
	
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	brush_mask_popup.add_child(outer)
	
	# Header row: title, refresh button, clear-mask button, close
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Fırça Maskeleri"
	title.add_theme_color_override("font_color", Color(0.85, 0.85, 1.0))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	
	var btn_refresh := Button.new()
	btn_refresh.text = "↻ Yenile"
	btn_refresh.tooltip_text = "brushes/ klasörünü tekrar tara"
	btn_refresh.pressed.connect(_populate_brush_mask_grid)
	header.add_child(btn_refresh)
	
	var btn_clear := Button.new()
	btn_clear.text = "✕ Maske Yok"
	btn_clear.tooltip_text = "Maskeyi kaldır — legacy şekil seçimine (Yumuşak/Keskin/Kare/Elmas/Gürültü) geri dön"
	btn_clear.pressed.connect(_on_brush_mask_cleared)
	header.add_child(btn_clear)
	
	outer.add_child(header)
	
	brush_mask_label = Label.new()
	brush_mask_label.text = "Seçili: (yok)"
	brush_mask_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	outer.add_child(brush_mask_label)
	
	# Scrollable thumbnail grid.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 420)
	outer.add_child(scroll)
	
	brush_mask_grid = GridContainer.new()
	brush_mask_grid.columns = 6
	brush_mask_grid.add_theme_constant_override("h_separation", 6)
	brush_mask_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(brush_mask_grid)
	
	# Initial scan — happens once at plugin load.
	_populate_brush_mask_grid()

func _show_brush_mask_picker() -> void:
	if brush_mask_popup == null:
		_build_brush_mask_picker()
	else:
		# V21: re-scan on every open. _build_brush_mask_picker does an
		# initial scan on first creation; opening the popup later won't
		# pick up newly-added masks unless we refresh. The "↻ Yenile"
		# button is still there for explicit invalidation, but auto-
		# refreshing on open removes the "I added a file, why isn't it
		# showing" stumbling block.
		_populate_brush_mask_grid()
	# Position roughly under the toolbar button.
	var btn_rect := brush_mask_picker_btn.get_global_rect()
	brush_mask_popup.popup(Rect2i(
		int(btn_rect.position.x),
		int(btn_rect.position.y + btn_rect.size.y + 4),
		600,
		500
	))
	_update_brush_mask_label()

# Re-scan the brushes/ folder. Each .png becomes a thumbnail button.
# Stable across calls — clears the grid first so duplicates don't pile up.
func _populate_brush_mask_grid() -> void:
	if brush_mask_grid == null: return
	for child in brush_mask_grid.get_children():
		child.queue_free()
	_brush_mask_cache.clear()
	
	var dir := DirAccess.open(BRUSHES_DIR)
	if dir == null:
		var lbl := Label.new()
		lbl.text = "brushes/ klasörü açılamadı. addons/mobile_terrain/brushes/ var mı?"
		lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		brush_mask_grid.add_child(lbl)
		return
	
	dir.list_dir_begin()
	var files: Array[String] = []
	while true:
		var f := dir.get_next()
		if f.is_empty():
			break
		# Skip directories, .import sidecars, and non-image files.
		if dir.current_is_dir():
			continue
		var lower := f.to_lower()
		if lower.ends_with(".png") or lower.ends_with(".exr") or lower.ends_with(".jpg") or lower.ends_with(".webp"):
			files.append(f)
	dir.list_dir_end()
	files.sort()
	
	if files.is_empty():
		var lbl := Label.new()
		lbl.text = "brushes/ klasörü boş. PNG/EXR maskeleri ekle ve Yenile'ye bas."
		lbl.add_theme_color_override("font_color", Color(0.8, 0.7, 0.4))
		brush_mask_grid.add_child(lbl)
		return
	
	for f in files:
		var path := BRUSHES_DIR + f
		# V21: Pre-check via ResourceLoader.exists. PNGs that were dropped
		# into the project but haven't been imported yet (e.g. the user
		# just extracted the ZIP and the editor's import pass is still
		# running on first launch) would otherwise produce a "Failed
		# loading resource" error and a null return. exists() respects
		# the importer's progress, so we skip racing files silently and
		# the user can re-open the popup once the import settles.
		if not ResourceLoader.exists(path, "Texture2D"):
			continue
		var tex := load(path) as Texture2D
		if tex == null:
			continue  # defensive: belt-and-braces on top of exists()
		_brush_mask_cache.append({"name": f, "texture": tex, "path": path})
		
		# Each thumbnail = a button containing a TextureRect.
		# Wrapping in a Button gives us the press signal and a nice
		# focus ring; the texture goes inside.
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(80, 100)
		btn.tooltip_text = f
		btn.pressed.connect(_on_brush_mask_selected.bind(tex, f))
		
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 2)
		btn.add_child(vb)
		
		var tr := TextureRect.new()
		tr.texture = tex
		tr.custom_minimum_size = Vector2(64, 64)
		tr.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# Disable mouse so the click goes through to the parent Button.
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(tr)
		
		var nm := Label.new()
		# Trim extension and underscores for display.
		var display_name := f.get_basename().replace("_", " ")
		nm.text = display_name
		nm.add_theme_font_size_override("font_size", 9)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(nm)
		
		brush_mask_grid.add_child(btn)
	
	# V21: If files were found on disk but none loaded as Texture2D, the
	# editor is most likely still importing them (first launch after ZIP
	# extract is the common case). Tell the user instead of leaving an
	# empty grid that looks like a failure.
	if _brush_mask_cache.is_empty() and not files.is_empty():
		var lbl := Label.new()
		lbl.text = "%d dosya bulundu ama henüz import edilmediler.\nGodot importer'ı bekle (FileSystem dock'ta progress var), birkaç saniye sonra ↻ Yenile'ye tekrar bas." % files.size()
		lbl.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		lbl.custom_minimum_size = Vector2(520, 0)
		brush_mask_grid.add_child(lbl)

func _on_brush_mask_selected(tex: Texture2D, fname: String) -> void:
	if selected_node:
		selected_node.brush_mask = tex
	_update_brush_mask_label()
	_update_shape_dropdown_state()
	# V21: rebuild the cursor mesh immediately so the new mask's shape
	# (peak, ring, star, splotches...) is visible without requiring the
	# user to move their finger first.
	if _last_brush_hit != Vector3.INF:
		_conform_brush_to_surface(_last_brush_hit)
	if brush_mask_popup:
		brush_mask_popup.hide()

func _on_brush_mask_cleared() -> void:
	if selected_node:
		selected_node.brush_mask = null
	_update_brush_mask_label()
	_update_shape_dropdown_state()
	if _last_brush_hit != Vector3.INF:
		_conform_brush_to_surface(_last_brush_hit)

# V21: Gate the legacy "Fırça" shape dropdown (Yumuşak/Keskin/Kare/Elmas/
# Gürültü) on whether a brush mask is active. When a mask is set,
# brush_shape_falloff samples the mask and completely ignores brush_shape;
# the dropdown still being interactive misled users into thinking they
# were changing the shape. Disabling it (with a tooltip explaining why)
# makes the precedence obvious.
func _update_shape_dropdown_state() -> void:
	if not is_instance_valid(shape_opt): return
	var mask_active: bool = selected_node != null and selected_node.brush_mask != null
	shape_opt.disabled = mask_active
	if mask_active:
		shape_opt.tooltip_text = "Maske aktif olduğu için bu seçim görmezden geliniyor. Maske'yi temizlemek için 🖌 Maske > ✕ Maske Yok."
	else:
		shape_opt.tooltip_text = ""

func _update_brush_mask_label() -> void:
	if brush_mask_label == null: return
	if selected_node == null or selected_node.brush_mask == null:
		brush_mask_label.text = "Seçili: (yok — legacy şekil sistemi aktif)"
		return
	var name: String = selected_node.brush_mask.resource_path.get_file()
	brush_mask_label.text = "Seçili: " + name

func _on_shape_selected(idx: int):
	if selected_node:
		selected_node.brush_shape = idx
		# V21: the brush shape (yumuşak/keskin/kare/elmas/noise) affects
		# how strength FALLOFF is calculated in `brush_shape_falloff`; the
		# cursor visual stays a generic disc. Pre-V21 used to swap the
		# Decal texture to a shape-specific bitmap, but with the new mesh
		# cursor we don't have a texture to swap. If we ever want
		# shape-accurate previews we'd need to rebuild the geometry with
		# the falloff applied to alpha — out of scope for V21.
		_update_brush_visual_properties()

func _on_radius_slider_changed(value: float):
	if _syncing_brush_controls: return
	_syncing_brush_controls = true
	if is_instance_valid(radius_spinbox):
		radius_spinbox.value = value
	_syncing_brush_controls = false
	if selected_node:
		selected_node.brush_radius = value
		_update_brush_visual_properties()

func _on_radius_spinbox_changed(value: float):
	if _syncing_brush_controls: return
	_syncing_brush_controls = true
	if is_instance_valid(radius_slider):
		radius_slider.value = value
	_syncing_brush_controls = false
	if selected_node:
		selected_node.brush_radius = value
		_update_brush_visual_properties()

func _on_strength_slider_changed(value: float):
	if _syncing_brush_controls: return
	_syncing_brush_controls = true
	if is_instance_valid(strength_spinbox):
		strength_spinbox.value = value
	_syncing_brush_controls = false
	if selected_node:
		selected_node.brush_strength = value
		_update_brush_visual_properties()

func _on_strength_spinbox_changed(value: float):
	if _syncing_brush_controls: return
	_syncing_brush_controls = true
	if is_instance_valid(strength_slider):
		strength_slider.value = value
	_syncing_brush_controls = false
	if selected_node:
		selected_node.brush_strength = value
		_update_brush_visual_properties()

func _update_brush_visual_properties():
	# V21: A slider drag (radius, strength) or mask selection should be
	# immediately visible on the cursor — the old code only refreshed
	# material colour, leaving the mesh frozen at the radius/mask it had
	# when the user last MOVED their finger. Now we also rebuild the
	# geometry if there's a last-known hit point. If nothing has been
	# hit yet (Vector3.INF), there's no anchor to rebuild against —
	# the next motion event will pick up the new values.
	if not selected_node or not is_instance_valid(brush_cursor): return
	if _last_brush_hit != Vector3.INF:
		_conform_brush_to_surface(_last_brush_hit)

func _build_asset_manager_ui():
	asset_manager_panel = PanelContainer.new()
	asset_manager_panel.hide()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 0.9)
	style.border_width_left = 2; style.border_width_top = 2; style.border_width_right = 2; style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.3, 0.3)
	asset_manager_panel.add_theme_stylebox_override("panel", style)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10); margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10); margin.add_theme_constant_override("margin_bottom", 10)
	asset_manager_panel.add_child(margin)
	
	var main_vbox = VBoxContainer.new()
	margin.add_child(main_vbox)
	
	var title = Label.new()
	title.text = "Terrain Varlık Yöneticisi"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_vbox.add_child(title)
	main_vbox.add_child(HSeparator.new())
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	main_vbox.add_child(scroll)
	
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(hbox)
	
	var tex_vbox = VBoxContainer.new()
	tex_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(tex_vbox)
	
	var tex_header = HBoxContainer.new()
	var tex_lbl = Label.new()
	tex_lbl.text = "Dokular"
	tex_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tex_header.add_child(tex_lbl)
	var btn_add_tex_local := Button.new()
	btn_add_tex_local.text = "+"
	btn_add_tex_local.pressed.connect(_add_texture_slot)
	tex_header.add_child(btn_add_tex_local)
	btn_add_tex = btn_add_tex_local  # store for cap-disable in _refresh_manager_ui
	tex_vbox.add_child(tex_header)
	
	tex_list_vbox = VBoxContainer.new()
	tex_vbox.add_child(tex_list_vbox)
	
	hbox.add_child(VSeparator.new())
	
	var obj_vbox = VBoxContainer.new()
	obj_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(obj_vbox)
	
	var obj_header = HBoxContainer.new()
	var obj_lbl = Label.new()
	obj_lbl.text = "Objeler"
	obj_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	obj_header.add_child(obj_lbl)
	var btn_add_obj = Button.new()
	btn_add_obj.text = "+"
	btn_add_obj.pressed.connect(_add_object_slot)
	obj_header.add_child(btn_add_obj)
	obj_vbox.add_child(obj_header)
	
	obj_list_vbox = VBoxContainer.new()
	obj_vbox.add_child(obj_list_vbox)
	
	var editor_viewport = get_editor_interface().get_editor_main_screen()
	editor_viewport.add_child(asset_manager_panel)
	asset_manager_panel.position = Vector2(20, 80)
	# V21: bigger height — each slot now has 7 picker rows (Albedo,
	# Normal, Roughness, AO + extra-label + Height, Metallic, Emission)
	# vs the V20 single-row layout. 560×620 keeps two full slots visible
	# at a time on tablets without scrolling.
	asset_manager_panel.custom_minimum_size = Vector2(560, 620)

func _toggle_asset_manager():
	if asset_manager_panel.visible:
		asset_manager_panel.hide()
	else:
		_refresh_manager_ui()
		asset_manager_panel.show()

func _refresh_manager_ui():
	if not selected_node: return
	for child in tex_list_vbox.get_children(): child.queue_free()
	for child in obj_list_vbox.get_children(): child.queue_free()
	
	# V21: Make sure the PBR map arrays match the albedo array length.
	# Old V19/V20 scenes have terrain_normal/roughness/ao empty until
	# _ready() runs; the editor sometimes calls _refresh_manager_ui
	# before the node's _ready completes (when the user clicks the
	# Manage button right after selecting a freshly-loaded scene), so
	# we re-pad defensively here. Idempotent: no-op if already sized.
	_sync_pbr_array_sizes()
	
	for i in range(selected_node.terrain_textures.size()):
		# Each texture slot is a panel with 4 pickers (albedo, normal,
		# roughness, AO) plus header buttons (auto-detect, delete).
		var slot_panel := PanelContainer.new()
		var slot_style := StyleBoxFlat.new()
		slot_style.bg_color = Color(0.13, 0.13, 0.18, 0.5)
		slot_style.set_corner_radius_all(4)
		slot_style.content_margin_left = 8
		slot_style.content_margin_right = 8
		slot_style.content_margin_top = 6
		slot_style.content_margin_bottom = 6
		slot_panel.add_theme_stylebox_override("panel", slot_style)
		
		var slot_vbox := VBoxContainer.new()
		slot_vbox.add_theme_constant_override("separation", 4)
		slot_panel.add_child(slot_vbox)
		
		# Header row: slot index, auto-detect button, delete button
		var header := HBoxContainer.new()
		var slot_label := Label.new()
		slot_label.text = "Slot %d" % i
		slot_label.add_theme_color_override("font_color", Color(0.85, 0.85, 1.0))
		slot_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(slot_label)
		
		var btn_detect := Button.new()
		btn_detect.text = "🔍 Tespit"
		btn_detect.tooltip_text = "Albedo dosyasından kardeş normal/roughness/AO map'lerini otomatik bulup doldur"
		btn_detect.pressed.connect(_auto_detect_maps.bind(i))
		header.add_child(btn_detect)
		
		var btn_del := Button.new()
		btn_del.text = "✕"
		btn_del.tooltip_text = "Bu slot'u sil"
		btn_del.pressed.connect(_remove_texture_slot.bind(i))
		header.add_child(btn_del)
		
		slot_vbox.add_child(header)
		
		# Four picker rows: Albedo, Normal, Roughness, AO
		_build_pbr_picker_row(slot_vbox, "Albedo",    selected_node.terrain_textures,  i, _on_albedo_changed)
		_build_pbr_picker_row(slot_vbox, "Normal",    selected_node.terrain_normal,    i, _on_normal_changed)
		_build_pbr_picker_row(slot_vbox, "Roughness", selected_node.terrain_roughness, i, _on_roughness_changed)
		_build_pbr_picker_row(slot_vbox, "AO",        selected_node.terrain_ao,        i, _on_ao_changed)
		# V21: storage-only slots. The default shader doesn't sample
		# these, so the user pays nothing in rendering cost by leaving
		# them empty. They exist so projects with full PBR sets can
		# park their _disp/_metal/_emit textures here and reference
		# them from a custom shader. Visually separated from the four
		# active maps with a subtle label.
		var extra_label := Label.new()
		extra_label.text = "  ─ Ekstra (Shader'a bağlı değil — saklama için) ─"
		extra_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
		extra_label.add_theme_font_size_override("font_size", 10)
		slot_vbox.add_child(extra_label)
		_build_pbr_picker_row(slot_vbox, "Height",    selected_node.terrain_height,    i, _on_height_changed)
		_build_pbr_picker_row(slot_vbox, "Metallic",  selected_node.terrain_metallic,  i, _on_metallic_changed)
		_build_pbr_picker_row(slot_vbox, "Emission",  selected_node.terrain_emission,  i, _on_emission_changed)
		
		tex_list_vbox.add_child(slot_panel)
		# Small gap between slot panels
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 4)
		tex_list_vbox.add_child(gap)
		
	for i in range(selected_node.asset_meshes.size()):
		var row = HBoxContainer.new()
		var picker = EditorResourcePicker.new()
		picker.base_type = "Mesh"
		picker.edited_resource = selected_node.asset_meshes[i]
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		picker.resource_changed.connect(func(res: Resource): _on_object_changed(i, res))
		
		row.add_child(picker)
		var btn_del = Button.new()
		btn_del.text = "X"
		btn_del.pressed.connect(func(): _remove_object_slot(i))
		row.add_child(btn_del)
		obj_list_vbox.add_child(row)
	_update_dropdowns()
	# V21: gate the "+" button on the 4-slot splatmap cap. Visual feedback
	# AND functional: disabled buttons in Godot ignore press events, so
	# even an over-eager double-click can't push past the limit while the
	# UI is settling.
	if is_instance_valid(btn_add_tex):
		var at_cap: bool = selected_node.terrain_textures.size() >= 4
		btn_add_tex.disabled = at_cap
		btn_add_tex.tooltip_text = "Maks. 4 slot (splatmap RGBA)" if at_cap else "Yeni doku slot'u ekle"

# V21: Build one labelled texture picker row inside a slot panel. The
# picker reads from `array[idx]` (or null if out of bounds) and writes
# back via the supplied callback.
func _build_pbr_picker_row(parent: VBoxContainer, label_text: String, array: Array, idx: int, callback: Callable) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(80, 0)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	row.add_child(lbl)
	var picker := EditorResourcePicker.new()
	picker.base_type = "Texture2D"
	picker.edited_resource = array[idx] if idx < array.size() else null
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.resource_changed.connect(func(res: Resource): callback.call(idx, res))
	row.add_child(picker)
	parent.add_child(row)

# V21: Ensure terrain_normal/roughness/ao arrays match terrain_textures
# length. Called from _refresh_manager_ui and slot mutation handlers.
# Idempotent and cheap; safe to call repeatedly.
func _sync_pbr_array_sizes() -> void:
	if not selected_node: return
	# Explicit `: int` instead of `:=` — selected_node is untyped (declared
	# `var selected_node = null` at top of file) so GDScript can't infer
	# the type of `.terrain_textures.size()` at parse time and rejects
	# the inference operator. Same reason any `:=` against selected_node
	# fields would fail.
	var n: int = selected_node.terrain_textures.size()
	while selected_node.terrain_normal.size() < n: selected_node.terrain_normal.append(null)
	while selected_node.terrain_roughness.size() < n: selected_node.terrain_roughness.append(null)
	while selected_node.terrain_ao.size() < n: selected_node.terrain_ao.append(null)
	# V21: storage-only extra slots — same lockstep treatment.
	while selected_node.terrain_height.size() < n: selected_node.terrain_height.append(null)
	while selected_node.terrain_metallic.size() < n: selected_node.terrain_metallic.append(null)
	while selected_node.terrain_emission.size() < n: selected_node.terrain_emission.append(null)
	selected_node.terrain_normal.resize(n)
	selected_node.terrain_roughness.resize(n)
	selected_node.terrain_ao.resize(n)
	selected_node.terrain_height.resize(n)
	selected_node.terrain_metallic.resize(n)
	selected_node.terrain_emission.resize(n)

func _add_texture_slot():
	if not selected_node: return
	# V21: splatmap is an RGBA texture — 4 paintable channels, period.
	# Adding a 5th texture slot means the user could PICK a texture for
	# it from the asset manager but never PAINT it (paint tool's slot
	# index is gated to 0..3 in _paint_splatmap), which is a confusing
	# silent failure. Cap the array so the "+" button doesn't lie about
	# what's possible. If we ever switch to a higher-channel splatmap
	# (RG + BA stored separately, etc.) this cap becomes the only
	# place to lift.
	const MAX_PAINT_SLOTS := 4
	if selected_node.terrain_textures.size() >= MAX_PAINT_SLOTS:
		print("[MobileTerrain3D] En fazla %d doku slot'u olabilir (splatmap RGBA, 4 kanal). Yeni doku eklemek için önce bir slot'u boşalt ve değiştir." % MAX_PAINT_SLOTS)
		return
	selected_node.terrain_textures.append(null)
	# V21: keep PBR arrays in lockstep with the albedo array.
	selected_node.terrain_normal.append(null)
	selected_node.terrain_roughness.append(null)
	selected_node.terrain_ao.append(null)
	selected_node.terrain_height.append(null)
	selected_node.terrain_metallic.append(null)
	selected_node.terrain_emission.append(null)
	_refresh_manager_ui()
	_save_selected_scene()

func _remove_texture_slot(idx: int):
	if not selected_node: return
	# V21 GUARD: bound-check before remove_at. Same rationale as
	# _remove_object_slot — stale button events can call this with
	# an out-of-range idx if the UI is rebuilt mid-press.
	if idx < 0 or idx >= selected_node.terrain_textures.size(): return
	selected_node.terrain_textures.remove_at(idx)
	# V21: remove from all PBR arrays at the same index so they
	# stay aligned with terrain_textures.
	if idx < selected_node.terrain_normal.size():
		selected_node.terrain_normal.remove_at(idx)
	if idx < selected_node.terrain_roughness.size():
		selected_node.terrain_roughness.remove_at(idx)
	if idx < selected_node.terrain_ao.size():
		selected_node.terrain_ao.remove_at(idx)
	if idx < selected_node.terrain_height.size():
		selected_node.terrain_height.remove_at(idx)
	if idx < selected_node.terrain_metallic.size():
		selected_node.terrain_metallic.remove_at(idx)
	if idx < selected_node.terrain_emission.size():
		selected_node.terrain_emission.remove_at(idx)
	# V20 FIX (bug U3): rebind shader uniforms after the arrays shrink
	# so the removed slot's old textures stop rendering. update_shader_textures
	# rebinds all four map types per slot via the blank-texture fallback.
	selected_node.update_shader_textures()
	_refresh_manager_ui()
	_save_selected_scene()

# V21: Per-map-type change handlers. Each writes back to the right
# array and triggers a shader rebind so the change is visible immediately.
func _on_albedo_changed(idx: int, res: Resource) -> void:
	if not selected_node: return
	_sync_pbr_array_sizes()
	# V21 GUARD: stale-UI bound check. _sync_pbr_array_sizes equalises the
	# PBR arrays to terrain_textures.size(), but doesn't grow terrain_textures
	# itself. If a stale UI callback fires with idx pointing past the
	# current array end (e.g. user deleted slot 2 and a deferred event
	# from slot 3's picker arrives), the unguarded write would crash.
	if idx < 0 or idx >= selected_node.terrain_textures.size(): return
	selected_node.terrain_textures[idx] = res as Texture2D
	selected_node.update_shader_textures()
	_update_dropdowns()
	_save_selected_scene()

func _on_normal_changed(idx: int, res: Resource) -> void:
	if not selected_node: return
	_sync_pbr_array_sizes()
	if idx < 0 or idx >= selected_node.terrain_normal.size(): return
	selected_node.terrain_normal[idx] = res as Texture2D
	selected_node.update_shader_textures()
	_save_selected_scene()

func _on_roughness_changed(idx: int, res: Resource) -> void:
	if not selected_node: return
	_sync_pbr_array_sizes()
	if idx < 0 or idx >= selected_node.terrain_roughness.size(): return
	selected_node.terrain_roughness[idx] = res as Texture2D
	selected_node.update_shader_textures()
	_save_selected_scene()

func _on_ao_changed(idx: int, res: Resource) -> void:
	if not selected_node: return
	_sync_pbr_array_sizes()
	if idx < 0 or idx >= selected_node.terrain_ao.size(): return
	selected_node.terrain_ao[idx] = res as Texture2D
	selected_node.update_shader_textures()
	_save_selected_scene()

# V21: storage-only handlers. These write to the corresponding array but
# DON'T call update_shader_textures because the default shader doesn't
# read them. If the user swaps in a custom shader that does, it'll
# pick the values up on the next material refresh.
func _on_height_changed(idx: int, res: Resource) -> void:
	if not selected_node: return
	_sync_pbr_array_sizes()
	if idx < 0 or idx >= selected_node.terrain_height.size(): return
	selected_node.terrain_height[idx] = res as Texture2D
	_save_selected_scene()

func _on_metallic_changed(idx: int, res: Resource) -> void:
	if not selected_node: return
	_sync_pbr_array_sizes()
	if idx < 0 or idx >= selected_node.terrain_metallic.size(): return
	selected_node.terrain_metallic[idx] = res as Texture2D
	_save_selected_scene()

func _on_emission_changed(idx: int, res: Resource) -> void:
	if not selected_node: return
	_sync_pbr_array_sizes()
	if idx < 0 or idx >= selected_node.terrain_emission.size(): return
	selected_node.terrain_emission[idx] = res as Texture2D
	_save_selected_scene()

# Kept as a thin alias of _on_albedo_changed for backward-compat with
# any other code in the plugin that called this name. The dropdown
# refresh is the only behavioural difference.
func _on_texture_changed(idx: int, res: Resource) -> void:
	_on_albedo_changed(idx, res)

# V21: Auto-detect PBR maps from a sibling-naming convention.
# Workflow: user fills the Albedo picker with e.g.
# `forrest_ground_01_diff_1k.png`, clicks the 🔍 button. We scan the same
# directory for files that share the prefix/suffix but with a different
# map-type marker (`_nor_gl`, `_rough`, `_ao` etc.) and slot them in.
#
# Markers are ordered by preference — `_nor_gl` (OpenGL Y+) is tried
# before `_nor_dx` (DirectX Y-) because Godot expects Y+. Single-letter
# fallbacks (`_n`, `_r`) come last to avoid false positives.
const _DIFFUSE_MARKERS := [
	"_diff", "_diffuse", "_albedo", "_basecolor", "_base_color", "_color", "_col"
]
const _NORMAL_MARKERS := [
	"_nor_gl", "_normal_gl", "_norm_gl",        # OpenGL convention (Y up) — preferred
	"_nor_dx", "_normal_dx", "_norm_dx",        # DirectX convention (Y down)
	"_norm", "_normal", "_nrm", "_normalmap",   # ambiguous (assume OpenGL)
]
const _ROUGHNESS_MARKERS := [
	"_rough", "_roughness", "_rgh"
]
const _AO_MARKERS := [
	"_ao", "_occlusion", "_ambientocclusion", "_ambient_occlusion"
]
# V21: extra slot markers. Auto-detect populates these alongside the
# four active PBR types when their sibling files exist — Height (`_disp`,
# `_height`), Metallic (`_metal`, `_metallic`, `_metalness`), Emission
# (`_emit`, `_emission`, `_emissive`).
const _HEIGHT_MARKERS := [
	"_displacement", "_disp", "_height"
	# Note: `_dis` was considered but rejected — it sub-matches names like
	# `_distance`, `_disable`, `_disco`, which appear in non-PBR contexts.
	# Users with exotic naming can add their own marker in the source.
]
const _METALLIC_MARKERS := [
	"_metallic", "_metalness", "_metal", "_mtl"
]
const _EMISSION_MARKERS := [
	"_emission", "_emissive", "_emit"
]

func _auto_detect_maps(slot_idx: int) -> void:
	if not selected_node: return
	if slot_idx >= selected_node.terrain_textures.size(): return
	var albedo: Texture2D = selected_node.terrain_textures[slot_idx]
	if albedo == null:
		print("[MobileTerrain3D] Slot %d: önce Albedo texture'ını seç, sonra Tespit'e bas." % slot_idx)
		return
	var albedo_path := albedo.resource_path
	if albedo_path.is_empty():
		print("[MobileTerrain3D] Slot %d: Albedo texture'ın bir disk yolu yok (built-in resource olabilir), otomatik tespit atlandı." % slot_idx)
		return
	
	var detected := _detect_sibling_maps(albedo_path)
	_sync_pbr_array_sizes()
	
	var filled: Array[String] = []
	if detected.has("normal") and detected["normal"] != null:
		selected_node.terrain_normal[slot_idx] = detected["normal"]
		filled.append("Normal: " + (detected["normal"] as Texture2D).resource_path)
	if detected.has("roughness") and detected["roughness"] != null:
		selected_node.terrain_roughness[slot_idx] = detected["roughness"]
		filled.append("Roughness: " + (detected["roughness"] as Texture2D).resource_path)
	if detected.has("ao") and detected["ao"] != null:
		selected_node.terrain_ao[slot_idx] = detected["ao"]
		filled.append("AO: " + (detected["ao"] as Texture2D).resource_path)
	# V21: extra storage slots — populate alongside the active maps so
	# users don't have to manually wire _disp / _metal / _emit.
	if detected.has("height") and detected["height"] != null:
		selected_node.terrain_height[slot_idx] = detected["height"]
		filled.append("Height: " + (detected["height"] as Texture2D).resource_path)
	if detected.has("metallic") and detected["metallic"] != null:
		selected_node.terrain_metallic[slot_idx] = detected["metallic"]
		filled.append("Metallic: " + (detected["metallic"] as Texture2D).resource_path)
	if detected.has("emission") and detected["emission"] != null:
		selected_node.terrain_emission[slot_idx] = detected["emission"]
		filled.append("Emission: " + (detected["emission"] as Texture2D).resource_path)
	
	if filled.is_empty():
		print("[MobileTerrain3D] Slot %d: '%s' için kardeş map bulunamadı. Albedo'nun '_diff' / '_albedo' / '_color' gibi bir marker içerdiğinden emin ol." % [slot_idx, albedo_path.get_file()])
		return
	
	print("[MobileTerrain3D] Slot %d için otomatik tespit:" % slot_idx)
	for s in filled:
		print("  ✓ " + s)
	selected_node.update_shader_textures()
	_refresh_manager_ui()
	_save_selected_scene()

# Find sibling textures matching a different map-type marker. Returns
# a dictionary { "normal": Texture2D, "roughness": Texture2D, "ao":
# Texture2D, "height": Texture2D, "metallic": Texture2D, "emission":
# Texture2D } with nulls for misses. V21 expanded to cover storage-only
# extra slots so a single 🔍 Tespit click can fill 6 maps when the
# sibling files exist.
func _detect_sibling_maps(albedo_path: String) -> Dictionary:
	var result := {
		"normal": null, "roughness": null, "ao": null,
		"height": null, "metallic": null, "emission": null,
	}
	var dir_path := albedo_path.get_base_dir()
	var albedo_file := albedo_path.get_file()
	var albedo_lower := albedo_file.to_lower()
	
	# Find which diffuse marker appears and at what index. We need the
	# original case to splice correctly, so we record the lowercase index.
	var diff_marker := ""
	var diff_idx := -1
	for m in _DIFFUSE_MARKERS:
		var idx := albedo_lower.find(m)
		if idx >= 0:
			diff_marker = m
			diff_idx = idx
			break
	if diff_idx < 0:
		return result  # no marker, can't infer siblings
	
	# Splice out the diffuse marker from the original filename and try
	# inserting each candidate marker for each map type.
	var prefix := albedo_file.substr(0, diff_idx)
	var suffix := albedo_file.substr(diff_idx + diff_marker.length())
	
	result["normal"]    = _find_first_existing_texture(dir_path, prefix, _NORMAL_MARKERS, suffix)
	result["roughness"] = _find_first_existing_texture(dir_path, prefix, _ROUGHNESS_MARKERS, suffix)
	result["ao"]        = _find_first_existing_texture(dir_path, prefix, _AO_MARKERS, suffix)
	result["height"]    = _find_first_existing_texture(dir_path, prefix, _HEIGHT_MARKERS, suffix)
	result["metallic"]  = _find_first_existing_texture(dir_path, prefix, _METALLIC_MARKERS, suffix)
	result["emission"]  = _find_first_existing_texture(dir_path, prefix, _EMISSION_MARKERS, suffix)
	
	return result

# Try each marker in order. For each, splice it into prefix+marker+suffix
# and check if the file is in Godot's resource system. Returns the first
# match or null.
func _find_first_existing_texture(dir_path: String, prefix: String, markers: Array, suffix: String) -> Texture2D:
	for m in markers:
		var candidate := dir_path.path_join(prefix + m + suffix)
		if ResourceLoader.exists(candidate, "Texture2D"):
			var res := load(candidate)
			if res is Texture2D:
				return res as Texture2D
	return null

func _add_object_slot():
	if selected_node: 
		selected_node.asset_meshes.append(null)
		_refresh_manager_ui()
		_save_selected_scene()

func _remove_object_slot(idx: int):
	if not selected_node: return
	# V21 GUARD: bound-check before remove_at. Callbacks captured idx via
	# .bind(i) at button-build time; if the UI was rebuilt and an old
	# button event somehow fires (e.g. queue_free hasn't actually freed
	# yet, deferred input), idx could be stale and out of range. remove_at
	# crashes on out-of-range; the bound check makes it a silent no-op.
	if idx < 0 or idx >= selected_node.asset_meshes.size(): return
	selected_node.asset_meshes.remove_at(idx)
	_refresh_manager_ui()
	selected_node.garbage_collect_multimeshes()
	_save_selected_scene()

func _on_object_changed(idx: int, res: Resource):
	if not selected_node: return
	# V21 GUARD: same idx-bound issue as PBR handlers. Stale UI events
	# could write past the array end.
	if idx < 0 or idx >= selected_node.asset_meshes.size(): return
	# V20 FIX: previously, changing a slot's mesh just created a fresh
	# multimesh for the new mesh and left the OLD mesh's multimesh
	# orphaned in the scene — its instances kept rendering forever
	# with no UI access. _remove_object_slot called GC; this path
	# never did. Two-step fix:
	#
	#   1. Try to REPURPOSE the old multimesh to the new mesh. If the
	#      old mesh wasn't referenced by any other slot and there's no
	#      conflict with an existing multimesh for the new mesh, this
	#      preserves all the user's painted placements (they just
	#      switch to rendering the new model). User-friendly path.
	#
	#   2. Always GC afterwards to clean up any multimesh we couldn't
	#      repurpose (slot conflict, empty resource_path, mesh used by
	#      another slot we won't disturb, etc.). Without GC the same
	#      orphan-instance bug returns in the corner cases.
	var old_mesh: Mesh = selected_node.asset_meshes[idx]
	var new_mesh: Mesh = res as Mesh
	selected_node.asset_meshes[idx] = new_mesh
	
	if old_mesh and new_mesh and old_mesh != new_mesh:
		# Only repurpose if the old mesh has truly left the asset list.
		# If another slot still references it, its multimesh has to
		# stay tracking the old mesh — don't disturb it.
		var old_still_used := false
		for m in selected_node.asset_meshes:
			if m == old_mesh:
				old_still_used = true
				break
		if not old_still_used:
			selected_node.repurpose_multimesh_to(old_mesh, new_mesh)
	
	if new_mesh:
		selected_node._get_or_create_multimesh(new_mesh)
	# Catch anything we couldn't repurpose (conflicts, null paths, etc.).
	selected_node.garbage_collect_multimeshes()
	_update_dropdowns()
	_save_selected_scene()

func _save_selected_scene():
	# V21 GUARD: selected_node check. _save_selected_scene is called from
	# every PBR picker change and slot mutation; if the user changes a
	# picker after _make_visible(false) zeroed selected_node (race with
	# Inspector pickers and scene-tab switches) the unguarded call would
	# crash with "Invalid call. Nonexistent function 'notify_property_list_changed'
	# in base 'null instance'".
	if selected_node == null: return
	if get_tree() and get_tree().edited_scene_root: 
		selected_node.notify_property_list_changed()

func _update_dropdowns():
	if not selected_node: return
	# V20 FIX (bug U1): the old code cleared and repopulated each
	# OptionButton but never restored the selection, so the dropdown
	# visually snapped to index 0 after any slot list refresh while the
	# node's `current_paint_slot` / `current_object_slot` kept whatever
	# they were before. Users saw "slot 0 selected" but their paint
	# strokes silently applied to (e.g.) slot 2. The state was internally
	# consistent — only the dropdown lied. Fix: clamp the previous
	# selection into the new list bounds and select() it explicitly.
	# Clamp is needed for the case where the user removed the slot they
	# were on (e.g. delete slot 2 while it was active).
	texture_opt.clear()
	for i in range(selected_node.terrain_textures.size()):
		var tex = selected_node.terrain_textures[i]
		var name = tex.resource_path.get_file() if tex else "Boş Slot"
		texture_opt.add_item("Doku %d: %s" % [i, name], i)
	if texture_opt.item_count > 0:
		# V21: convert the stored slot ID into the dropdown's visual
		# INDEX before calling .select(). Today every slot has id == its
		# position so id and index agree, but if we ever delete a slot
		# in the middle (current_paint_slot=2 stored, remaining IDs
		# 0,1,3 at indices 0,1,2) calling select(2) would highlight the
		# wrong row. _index_for_id returns -1 when the ID no longer
		# exists, in which case we fall back to index 0 and sync the
		# node back to that ID.
		var stored_id: int = clampi(selected_node.current_paint_slot, 0, max(0, texture_opt.item_count - 1))
		var idx_for_id: int = _index_for_id(texture_opt, stored_id)
		if idx_for_id < 0:
			idx_for_id = 0
		texture_opt.select(idx_for_id)
		# Sync the node back in case the lookup moved us. Otherwise
		# the next paint stroke targets a stale invalid ID.
		selected_node.current_paint_slot = texture_opt.get_item_id(idx_for_id)
	
	object_opt.clear()
	for i in range(selected_node.asset_meshes.size()):
		var mesh = selected_node.asset_meshes[i]
		var name = mesh.resource_path.get_file() if mesh else "Boş Obje"
		object_opt.add_item("Obje %d: %s" % [i, name], i)
	if object_opt.item_count > 0:
		var stored_id: int = clampi(selected_node.current_object_slot, 0, max(0, object_opt.item_count - 1))
		var idx_for_id: int = _index_for_id(object_opt, stored_id)
		if idx_for_id < 0:
			idx_for_id = 0
		object_opt.select(idx_for_id)
		selected_node.current_object_slot = object_opt.get_item_id(idx_for_id)

# V21: helper. Returns the visual index of the item whose ID is `id`,
# or -1 if no such item exists. OptionButton has no built-in get_index_for_id.
func _index_for_id(opt: OptionButton, id: int) -> int:
	for i in range(opt.item_count):
		if opt.get_item_id(i) == id:
			return i
	return -1

# V21: Master brush toggle. When off, all sculpt/paint mouse events are
# ignored — the user can zoom and pan freely without worrying about
# stray strokes. The cursor mesh is also hidden so there's no orphaned
# orange disc on the terrain when the brush is "off".
func _on_brush_toggle(pressed: bool) -> void:
	brush_enabled = pressed
	_apply_brush_toggle_style()
	if not brush_enabled:
		# V21: clean up any in-progress stroke. If the user was holding
		# the mouse button when they toggled off, the mouse-up event would
		# be ignored by the brush_enabled gate, leaving is_sculpting=true
		# and node.last_sculpt_pos stale forever — every subsequent stroke
		# would treat itself as a continuation of the orphan one. Funnel
		# through the shared finaliser so the right undo action commits
		# under the current tool.
		if is_sculpting and selected_node != null:
			_finalize_active_stroke()
		is_sculpting = false
		if is_instance_valid(brush_cursor):
			brush_cursor.hide()
		_last_brush_hit = Vector3.INF
	else:
		# V21 FIX: when toggling back ON, the user expects the cursor
		# to appear immediately wherever their mouse last was. Previously
		# the cursor stayed hidden until the user moved the mouse (the
		# next motion event would trigger _conform_brush_to_surface which
		# would re-show it). On a stationary mouse the cursor never came
		# back, making the brush feel "broken" — user thinks toggling
		# didn't work.
		#
		# We don't know the current mouse position from outside an input
		# event handler, but Viewport has get_mouse_position(). Combined
		# with the editor's 3D camera (which the EditorPlugin tracks via
		# its own viewport), we can re-raycast and re-conform.
		_show_cursor_at_current_mouse()

# V21: re-show the brush cursor at the editor viewport's current mouse
# position. Called when brush_enabled goes false → true so the user
# doesn't have to wiggle the mouse to make the cursor reappear.
#
# How it works:
# - EditorInterface.get_editor_viewport_3d(0) is the main 3D viewport.
#   (.get_camera_3d() gives us the active editor camera for raycasting.)
# - Viewport.get_mouse_position() returns the cursor's screen-space
#   position relative to that viewport.
# - We feed both into the existing raymarch and reconform path, same as
#   what an InputEventMouseMotion handler would do.
#
# If any step fails (viewport not ready, no camera, mouse off-terrain)
# we silently bail — the next real motion event will pick it up.
func _show_cursor_at_current_mouse() -> void:
	if selected_node == null: return
	if not is_instance_valid(brush_cursor): return
	# V21: use the cached camera + mouse position from the last input
	# event we received. Avoids the EditorInterface API rabbit hole:
	# different Godot 4 versions expose it differently (singleton vs
	# self.get_editor_interface() vs Engine.get_singleton), and any of
	# those can hard-fail at parse time. The cache is always populated
	# at least once during normal use because mouse motion in the
	# viewport fires _forward_3d_gui_input even when brush is disabled.
	if _cached_camera == null or not is_instance_valid(_cached_camera): return
	var res = selected_node.get_intersection_raymarch_persistent(_cached_camera, _cached_mouse_pos)
	if typeof(res) == TYPE_DICTIONARY and res.pos != Vector3.INF:
		_conform_decal_to_surface(res.pos)

func _apply_brush_toggle_style() -> void:
	if not is_instance_valid(brush_toggle_btn): return
	# Three-style override (normal/hover/pressed) so the colour reads
	# in every interaction state. Without this, only `normal` would be
	# coloured and the button would flash to default-grey on touch.
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	if brush_enabled:
		brush_toggle_btn.text = "🖌 Fırça AÇIK"
		brush_toggle_btn.tooltip_text = "Fırça aktif. Tıkla → kapat (zoom/pan için)."
		style.bg_color = Color(0.2, 0.6, 0.3)  # green
	else:
		brush_toggle_btn.text = "🚫 Fırça KAPALI"
		brush_toggle_btn.tooltip_text = "Fırça pasif. Yanlışlıkla edit olmaz. Tıkla → tekrar aç."
		style.bg_color = Color(0.55, 0.2, 0.2)  # red
	# Apply the same style to all interactive states so the colour sticks.
	brush_toggle_btn.add_theme_stylebox_override("normal", style)
	brush_toggle_btn.add_theme_stylebox_override("hover", style)
	brush_toggle_btn.add_theme_stylebox_override("pressed", style)
	brush_toggle_btn.add_theme_stylebox_override("focus", style)

func _exit_tree() -> void:
	remove_custom_type("MobileTerrain3D")
	# V20 FIX: defensive disconnect in case the plugin is being torn down
	# while a terrain was still selected.
	_disconnect_placement_signal(selected_node)
	if ui_container: 
		remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, ui_container)
		ui_container.queue_free()
	# is_instance_valid guard: the cursor may have been auto-freed if its
	# parent terrain was destroyed before this tear-down runs (rare, but
	# happens on hot-reloading the plugin while editing).
	if is_instance_valid(brush_cursor):
		_detach_brush_cursor()
		brush_cursor.queue_free()
	if asset_manager_panel: 
		asset_manager_panel.queue_free()
	if is_instance_valid(brush_mask_popup):
		brush_mask_popup.queue_free()

func _handles(object: Object) -> bool: 
	return object is TerrainNode

# V21: scene-save hook for auto-externalising large heightmaps.
#
# This is the documented EditorPlugin virtual method the editor calls
# right before serialising scenes. Unlike NOTIFICATION_EDITOR_PRE_SAVE
# (which only fires on Resource-derived objects, not Node instances —
# confirmed by Godot engine source code), _save_external_data on the
# plugin DOES fire on scene save and is exposed for exactly this use
# case: writing companion external files alongside the .tscn.
#
# What we do here: walk every MobileTerrain3D in the currently edited
# scene tree and, if its heightmap is big enough AND not already
# externalised, migrate it to a .res file. The node's _externalize_data
# method handles path resolution, ResourceSaver.save, and the
# notify_property_list_changed call that flips _get_property_list into
# external mode for the imminent .tscn serialisation.
#
# Returns OK regardless of individual node outcomes — a single failed
# externalisation (e.g. unsaved scene) shouldn't block the .tscn save;
# the node just stays inline for that pass.
func _save_external_data() -> void:
	# Debug trace — print to Output is fine (silent unless user opens
	# the panel), push_warning was popping the Debugger on every save
	# even for scenes without our node, which is bad UX.
	print("=== [MobileTerrain3D] _save_external_data() FIRED ===")
	# V21 RE-SAVE GUARD: if this is the second save we triggered ourselves
	# (after wiping the heavy data), don't recurse. Just clear the flag,
	# restore the data, and exit.
	if _suppress_next_save_hook:
		print("[MobileTerrain3D] Suppressed (this is our re-save pass). Skipping externalise; restore queued.")
		_suppress_next_save_hook = false
		return
	var ei := get_editor_interface()
	if ei == null:
		push_warning("[MobileTerrain3D] get_editor_interface() returned null. Cannot externalise.")
		return
	var edited_root: Node = ei.get_edited_scene_root()
	if edited_root == null:
		push_warning("[MobileTerrain3D] edited_scene_root is null. Save before externalising.")
		return
	print("[MobileTerrain3D] Edited root: %s (%s)" % [edited_root.name, edited_root.get_class()])
	# Recursive walk — terrain might be deeply nested inside the scene.
	# We collect terrains first (don't mutate during traversal) so the
	# wipe/restore phases below can iterate the same list deterministically.
	var terrains: Array = []
	_collect_terrains(edited_root, terrains)
	print("[MobileTerrain3D] Found %d MobileTerrain3D node(s) in the scene." % terrains.size())
	if terrains.is_empty():
		# Silent return — this hook fires for EVERY scene save, including
		# ones with no terrain. Pushing a warning here would spam the
		# debugger every time the user saves an unrelated scene.
		return
	# Phase 1: write .res files and figure out which terrains need wipe-and-resave.
	var backups: Array = []
	for terrain in terrains:
		var threshold: int = TerrainNode.AUTO_EXTERNALIZE_THRESHOLD
		var size_qualifies: bool = terrain.height_data.size() >= threshold
		var path_set: bool = terrain.external_data_path != ""
		var res_missing: bool = path_set and not ResourceLoader.exists(terrain.external_data_path)
		print("[MobileTerrain3D] '%s': height_data.size=%d, threshold=%d, qualifies=%s, path='%s', path_set=%s, res_missing=%s" % [
			terrain.name, terrain.height_data.size(), threshold, size_qualifies,
			terrain.external_data_path, path_set, res_missing
		])
		if size_qualifies and (not path_set or res_missing):
			if res_missing:
				print("[MobileTerrain3D] External .res missing for '%s'; re-saving to prevent data loss." % terrain.name)
				# V21: suppress setter cascade — we don't want to trigger
				# a load attempt on the just-cleared empty path. The
				# subsequent _externalize_data call will derive a fresh
				# target_path from the scene file.
				terrain._suppress_external_path_setter = true
				terrain.external_data_path = ""
				terrain._suppress_external_path_setter = false
			else:
				print("[MobileTerrain3D] Auto-externalising '%s' (%d cells) to .res file..." % [terrain.name, terrain.height_data.size()])
			terrain._externalize_data(true)
			print("[MobileTerrain3D] After externalise: external_data_path='%s'" % terrain.external_data_path)
		if terrain.external_data_path != "" and terrain.height_data.size() > 0:
			print("[MobileTerrain3D] '%s': backing up %d cells, clearing in-memory for re-save..." % [terrain.name, terrain.height_data.size()])
			backups.append({
				"node": terrain,
				"height_data": terrain.height_data,
				"splatmap_texture_local": terrain.splatmap_texture_local,
				"scene_file_path": edited_root.scene_file_path,
			})
			terrain.height_data = PackedFloat32Array()
			terrain.splatmap_texture_local = null
		else:
			print("[MobileTerrain3D] '%s': not eligible for in-memory wipe (path='%s', size=%d)." % [
				terrain.name, terrain.external_data_path, terrain.height_data.size()
			])
	# V21 CRITICAL: Godot has ALREADY written the bloated .tscn by the time
	# this hook fires (4.6 behaviour, confirmed empirically: _validate_property
	# is called pre-save with the wrong external_data_path, then we get
	# called post-save with the right value but the .tscn is already on disk).
	#
	# To produce a small .tscn we trigger a second save_scene, this time
	# with the heavy data wiped from the live nodes. Set the suppress flag
	# first so the second save's hook call doesn't re-trigger the dance.
	if not backups.is_empty():
		var scene_path: String = edited_root.scene_file_path
		if scene_path != "":
			print("[MobileTerrain3D] Triggering second save_scene to write small .tscn ('%s')..." % scene_path)
			_suppress_next_save_hook = true
			# call_deferred so this save runs after the current hook returns
			# and Godot finishes its current save flow.
			call_deferred("_perform_resave", scene_path, backups)
		else:
			push_warning("[MobileTerrain3D] Scene has no file path; cannot perform re-save. Inline data WILL remain in .tscn until you save again.")
			# Restore anyway so terrain isn't blank.
			call_deferred("_restore_after_save", backups)
	else:
		print("[MobileTerrain3D] No backups to restore — done.")
	print("=== [MobileTerrain3D] _save_external_data() RETURNING ===")

# V21: helper called via call_deferred from _save_external_data. Saves
# the scene a second time (with heavy data already wiped from the live
# nodes), then queues the data restoration. Split out so the deferred
# call's signature stays simple.
func _perform_resave(scene_path: String, backups: Array) -> void:
	print("=== [MobileTerrain3D] _perform_resave() FIRED for '%s' ===" % scene_path)
	var ei := get_editor_interface()
	if ei == null:
		push_warning("[MobileTerrain3D] No editor interface during re-save. Restoring without re-save.")
		# V21 CRITICAL: clear the suppress flag even on the failure path.
		# Without this, the flag stays true forever and the NEXT user save
		# silently skips externalisation — exact opposite of what we want.
		_suppress_next_save_hook = false
		_restore_after_save(backups)
		return
	# EditorInterface.save_scene saves the currently-edited scene. We
	# could use save_scene_as(scene_path) but save_scene avoids the
	# "save as" overhead and keeps the path stable.
	var save_succeeded := false
	if ei.has_method("save_scene"):
		var err = ei.save_scene()
		print("[MobileTerrain3D] save_scene() returned: %s" % str(err))
		# err could be Error enum or null; treat anything other than OK as fail.
		save_succeeded = (err == OK or err == null)
	else:
		push_warning("[MobileTerrain3D] EditorInterface.save_scene not available; small .tscn won't be written.")
	# V21 SAFETY: If save_scene synchronously triggered _save_external_data
	# (the recursive call we suppressed via the flag), the flag was already
	# cleared inside the suppressed branch. But if save_scene FAILED before
	# reaching that point, the flag never got cleared. Force-clear here as
	# a backstop — at worst this means one redundant clear, never a stuck
	# flag that disables externalisation for the rest of the session.
	_suppress_next_save_hook = false
	# Restore in another deferred call so the second save flushes to disk first.
	call_deferred("_restore_after_save", backups)
	print("=== [MobileTerrain3D] _perform_resave() DONE (save_succeeded=%s) ===" % save_succeeded)

# Helper for the depth-first walk. Pushes every TerrainNode in the tree
# into `out` without mutating the tree.
func _collect_terrains(node: Node, out: Array) -> void:
	if node is TerrainNode:
		out.append(node)
	for child in node.get_children():
		_collect_terrains(child, out)

# Restore the live heavy data we cleared in _save_external_data. Called
# via call_deferred so the .tscn save has finished writing first.
func _restore_after_save(backups: Array) -> void:
	print("=== [MobileTerrain3D] _restore_after_save() FIRED with %d backup(s) ===" % backups.size())
	for entry in backups:
		var terrain = entry["node"]
		if not is_instance_valid(terrain):
			push_warning("[MobileTerrain3D] Restore target no longer valid; skipping.")
			continue
		print("[MobileTerrain3D] Restoring '%s': %d cells back into memory." % [terrain.name, entry["height_data"].size()])
		terrain.height_data = entry["height_data"]
		terrain.splatmap_texture_local = entry["splatmap_texture_local"]
		# Trigger a mesh rebuild so the visual catches up. Without this
		# the terrain would render blank until the next user action that
		# happens to mark chunks dirty.
		if terrain.has_method("force_update_all"):
			terrain.force_update_all()
		if terrain.has_method("force_refresh_splatmap"):
			terrain.force_refresh_splatmap()
	print("=== [MobileTerrain3D] _restore_after_save() DONE ===")

func _edit(object: Object) -> void:
	# V21: finalise any in-progress stroke under the OLD node BEFORE we
	# reassign selected_node. Without this, if the user clicked a
	# different terrain in the Scene dock while still holding the mouse
	# button on terrain A, the mouse-up would commit A's backup data
	# against B — restoring A's height onto B's terrain on undo, which
	# corrupts both. Tool-change / brush-toggle / visibility-loss have
	# similar guards; this closes the last open path.
	if is_sculpting and selected_node != null and selected_node != object:
		_finalize_active_stroke()
		is_sculpting = false
	
	# V20 FIX: disconnect from the previous terrain BEFORE reassigning
	# selected_node, otherwise we'd lose the reference and leak the
	# connection. Done unconditionally — `_disconnect_placement_signal`
	# is safe on null / freed nodes.
	_disconnect_placement_signal(selected_node)
	
	selected_node = object
	if selected_node:
		# V20 FIX: Attach the brush cursor to the terrain so it lives in
		# the same World3D and actually renders.
		_attach_brush_cursor_to(selected_node)
		# V20 FIX: subscribe to placement events so we can build object
		# placement undo actions. Connect once per _edit; the matching
		# disconnect happens above on the next _edit, or in _make_visible(false).
		# V21 BUG FIX: connect was unconditional, but the editor can call
		# _edit(node) twice for the same node (e.g. when re-selecting in
		# the scene tree after a deselect). Duplicate connections meant
		# every foliage_placed.emit fired TWO handlers, which doubled
		# placement_records → undo replayed each instance creation twice,
		# corrupting MultiMesh state on undo→redo. Same is_connected
		# pattern we use for brush_applied below.
		if not selected_node.foliage_placed.is_connected(_on_foliage_placed):
			selected_node.foliage_placed.connect(_on_foliage_placed)
		# V21: re-drape the cursor each time a brush stroke is applied
		# (especially needed for stationary holds where no mouse motion
		# triggers a natural reconform). See brush_applied emit in
		# apply_brush_stroke_slope.
		if not selected_node.brush_applied.is_connected(_on_brush_applied):
			selected_node.brush_applied.connect(_on_brush_applied)
		# V21: Sync both slider AND spinbox to the node's current brush
		# values. Guarded so the .value writes don't trip the change
		# handlers — the node already has these values, no need to write
		# them back. SpinBoxes may not exist on the very first selection
		# if _build_main_ui hasn't run yet (it does in _enter_tree, but
		# defensive checks are cheap).
		_syncing_brush_controls = true
		radius_slider.value = selected_node.brush_radius
		strength_slider.value = selected_node.brush_strength
		if is_instance_valid(radius_spinbox):
			radius_spinbox.value = selected_node.brush_radius
		if is_instance_valid(strength_spinbox):
			strength_spinbox.value = selected_node.brush_strength
		_syncing_brush_controls = false
		# V21: use id-based selection. tool_opt.select(N) means "show
		# item at index N" — when items are added in 0..N order with
		# matching IDs (today's case) it works, but it'd silently break
		# the moment any tool is reordered or hidden. _select_tool_by_id
		# decouples the visual position from the semantic identifier.
		_select_tool_by_id(selected_node.current_tool)
		# shape_opt added items in IDs 0..4 in order too, and is a
		# simpler 5-item list — leaving it as a direct .select() because
		# the chance of reordering is near-zero and brush_shape values
		# happen to map 1:1 to indices today. clampi belt-and-braces
		# against scenes that somehow have a stored brush_shape outside
		# 0..4 (e.g. a future version added shape 5 then it got removed).
		shape_opt.select(clampi(selected_node.brush_shape, 0, shape_opt.item_count - 1))
		_update_dropdowns()
		_update_ui_visibility()
		_update_shape_dropdown_state()  # V21: in case the loaded scene has brush_mask set
		_update_brush_visual_properties()
	else:
		_detach_brush_cursor()

func _make_visible(visible: bool) -> void:
	if visible:
		ui_container.show()
		# Only show if attached. An unparented cursor isn't in any World3D
		# so showing it would be a no-op anyway — but being explicit avoids
		# confusion if someone later changes the attachment policy.
		if is_instance_valid(brush_cursor) and brush_cursor.get_parent() != null:
			brush_cursor.show()
		_update_brush_visual_properties()
	else:
		ui_container.hide()
		# V21: clean up an in-progress stroke before we lose the node
		# reference. Without this, switching scene tabs or deselecting
		# the terrain mid-stroke left _splatmap_stroke_image populated
		# on the node — and splatmap_data stale — until the next
		# start_stroke (which clears the cache) overwrote it. Any undo
		# created in between would restore from a stale snapshot.
		# Route through the shared finaliser so the partial work is
		# committed to undo history instead of silently dropped.
		if is_sculpting and selected_node != null:
			_finalize_active_stroke()
		# V20 FIX: disconnect placement signal before clearing selected_node
		# so we don't leak the connection across editing sessions.
		_disconnect_placement_signal(selected_node)
		# Detach (not just hide). If we only hid here, then a scene change
		# would destroy our parent and auto-free the cursor under us.
		_detach_brush_cursor()
		if asset_manager_panel: asset_manager_panel.hide()
		selected_node = null
		is_sculpting = false
		# V21: belt-and-braces: _finalize_active_stroke already cleared
		# these but if no stroke was active they could still have stale
		# data from a previous selection. Wipe explicitly.
		splatmap_backup = PackedByteArray()
		heightmap_backup = PackedFloat32Array()
		placement_records.clear()

func _on_tool_selected(idx: int):
	# V21: OptionButton.item_selected emits the visual INDEX, not the
	# stored ID. They happen to match today because tool items are added
	# in order 0..8 — but if a future change reorders or hides any tool
	# (e.g. hiding "Obje Ekle" when no asset_meshes are configured),
	# index ≠ id and the wrong tool would silently activate.
	# Convert through get_item_id() so current_tool always matches the
	# semantic ID the rest of the code (and _apply_brush_single's
	# if-ladder) expects.
	if not selected_node: return
	# V21: if a stroke is in progress, commit it under the OLD tool before
	# changing tools. Without this, switching from e.g. Yükselt to Boya
	# mid-stroke would: (1) leave heightmap_backup dangling because the
	# new tool's mouse-up branch checks current_tool == 7 and finds an
	# empty splatmap_backup, so it commits nothing; (2) the sculpt work
	# done before the switch is unrecoverable via Ctrl+Z. Forcing a clean
	# commit here makes tool-change-during-stroke equivalent to mouse-up-
	# then-mouse-down-with-new-tool. Touch UI users hit this often: dropdown
	# selection is a finger tap that can happen while mid-drag.
	if is_sculpting:
		_finalize_active_stroke()
		is_sculpting = false
	selected_node.current_tool = tool_opt.get_item_id(idx)
	_update_ui_visibility()
	_update_brush_visual_properties()

# V21: shared stroke-finalisation logic. Extracted from the mouse-up
# branch so we can call it from any code path that needs to terminate
# an in-progress stroke cleanly: mouse-up (the normal case), brush-
# toggle-off mid-stroke, tool-change mid-stroke, visibility-loss mid-
# stroke. Commits the right undo action for whatever tool is currently
# active and clears the corresponding backup.
func _finalize_active_stroke() -> void:
	if selected_node == null: return
	selected_node.end_stroke()
	if selected_node.current_tool == 7 and splatmap_backup.size() > 0:
		undo_redo.create_action("Terrain Paint")
		undo_redo.add_do_property(selected_node, "splatmap_data", selected_node.splatmap_data.duplicate())
		undo_redo.add_undo_property(selected_node, "splatmap_data", splatmap_backup)
		undo_redo.add_do_method(selected_node, "force_refresh_splatmap")
		undo_redo.add_undo_method(selected_node, "force_refresh_splatmap")
		undo_redo.commit_action(false)
		splatmap_backup = PackedByteArray()
	elif selected_node.current_tool != 7 and selected_node.current_tool != 8 and heightmap_backup.size() > 0:
		undo_redo.create_action("Terrain Sculpt")
		undo_redo.add_do_property(selected_node, "height_data", selected_node.height_data.duplicate())
		undo_redo.add_undo_property(selected_node, "height_data", heightmap_backup)
		undo_redo.add_do_method(selected_node, "force_update_all")
		undo_redo.add_undo_method(selected_node, "force_update_all")
		undo_redo.commit_action(false)
		heightmap_backup = PackedFloat32Array()
	elif selected_node.current_tool == 8 and not placement_records.is_empty():
		_commit_placement_undo()
		# V21: clear records after commit. _commit_placement_undo intentionally
		# doesn't clear so re-entrant commits stay safe, but at the finaliser
		# level (one call per stroke end) it's correct to wipe. Without this,
		# a tool-switch-from-Object would leave stale records, and a later
		# non-Object finalise (e.g. another tool change) would skip the
		# placement_records branch but the records would still be alive in
		# memory until the next mouse_down clears them — minor memory waste,
		# but more importantly a footgun if we ever add a code path that
		# reads `placement_records` outside the stroke lifecycle.
		placement_records.clear()
		placement_initial_counts.clear()

# V21: small helper to mirror selected_node.current_tool back into the
# dropdown's visual selection. OptionButton.select() takes an INDEX, so
# we have to find which item carries the right ID. Used during node-
# attach where we want the dropdown to reflect the loaded scene's tool
# without firing the change handler. No-op if the ID isn't present.
func _select_tool_by_id(id: int) -> void:
	for i in range(tool_opt.item_count):
		if tool_opt.get_item_id(i) == id:
			tool_opt.select(i)
			return

func _update_ui_visibility():
	if not selected_node or not toolbar: return
	texture_opt.hide()
	object_opt.hide()
	if selected_node.current_tool == 7: # Paint V19
		texture_opt.show()
	elif selected_node.current_tool == 8: # Object V19
		object_opt.show()

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not selected_node: return EditorPlugin.AFTER_GUI_INPUT_PASS
	# V21: cache camera + mouse position from every event (BEFORE the
	# brush_enabled gate below) so brush-toggle-on can re-raycast without
	# going through EditorInterface (whose API changed between Godot 4.x
	# versions and risked parse-time failures). We capture even when
	# brush is disabled — the user might be orbiting with brush off,
	# toggling back on should pick up wherever the camera ended up.
	_cached_camera = camera
	if event is InputEventMouse:
		_cached_mouse_pos = (event as InputEventMouse).position
	# V21: master toggle gate. Returning PASS lets the editor's own
	# camera controller see the event, so zoom/pan/orbit work normally.
	# Any input that would normally start a stroke or place an object
	# is dropped. We deliberately don't hide the cursor here — the
	# toggle handler did that — and don't process MouseMotion either,
	# because we don't want the cursor to flicker around when the user
	# is just orbiting.
	if not brush_enabled:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		is_sculpting = true
		# V20 FIX: clear placement records on every stroke start (even
		# non-object strokes) so leftover state from a previously
		# interrupted object stroke can't leak into the new one.
		placement_records.clear()
		placement_initial_counts.clear()
		
		# V20 FIX (#15): clear backups but DON'T duplicate yet. The old code
		# eagerly cloned the full 256KB height_data (or splatmap_data) on
		# every mouse-down — even when the click landed on empty space
		# (raymarch miss) or the user released without dragging. We now
		# snapshot lazily inside `_ensure_backup_for_current_tool()`, which
		# runs immediately before each brush call. Clicks that never
		# actually modify terrain state now cost zero memory AND skip
		# creating the matching no-op undo entry (the mouse-up branch
		# checks `backup.size() > 0` to decide whether to record undo).
		splatmap_backup = PackedByteArray()
		heightmap_backup = PackedFloat32Array()
		
		selected_node.start_stroke()
		
		var result = selected_node.get_intersection_raymarch_persistent(camera, event.position)
		if typeof(result) == TYPE_DICTIONARY and result.pos != Vector3.INF:
			_conform_decal_to_surface(result.pos)
			_ensure_backup_for_current_tool()
			selected_node.apply_brush_stroke_slope(result.pos, result.normal)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
		
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# V21: route through the shared finaliser so all stroke-end paths
		# (mouse-up, brush-toggle-off, tool-change, visibility-loss)
		# behave identically. The finaliser also clears the backup arrays
		# — a bug the old mouse-up branch had silently: the splatmap/
		# heightmap backups stayed non-empty after commit, so the NEXT
		# stroke saw `backup.size() > 0` in _ensure_backup_for_current_tool,
		# skipped snapshotting, and undo would roll back to the PREVIOUS
		# stroke's state. Touch-screen users with rapid tap sequences would
		# see undo "skip" interactively.
		is_sculpting = false
		_finalize_active_stroke()
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	elif event is InputEventMouseMotion:
		var res = selected_node.get_intersection_raymarch_persistent(camera, event.position)
		if typeof(res) == TYPE_DICTIONARY and res.pos != Vector3.INF:
			_conform_decal_to_surface(res.pos)
			if is_sculpting:
				# V20 FIX (#15): snapshot lazily for drags that started off
				# the terrain and only landed on it later in the stroke.
				_ensure_backup_for_current_tool()
				selected_node.apply_brush_stroke_slope(res.pos, res.normal)
		else:
			# V21: cursor leaves the terrain (mouse over sky/UI). Hide it
			# AND invalidate _last_brush_hit. Without the reset, a
			# subsequent slider drag would call _conform_brush_to_surface
			# with the STALE last-known hit and the cursor would
			# resurrect itself at a random earlier location — the
			# "ghost cursor reappearing" symptom.
			if is_instance_valid(brush_cursor):
				brush_cursor.hide()
			_last_brush_hit = Vector3.INF
		if is_sculpting: return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS

# V19 PRO: Conforming Decal replaces rotation math. Just position it and it projects perfectly!
# V21: Build the brush cursor as an NxN grid of vertices draped over the
# terrain. Each vertex carries a vertex-color whose alpha is sampled from
# brush_mask at the matching UV. Result: the visible shape of the cursor
# on the terrain is exactly the mask shape — peak gives a tiny bright
# dot, ring gives a halo, star gives a star, etc. No mask → uniform
# orange disc (matches the legacy hard-coded shapes via brush_shape).
#
# Called from:
#   - Mouse motion events (cursor follows the pointer)
#   - Stationary brush apply (so the cursor re-drapes as terrain changes
#     under a held-finger sculpt; otherwise the cursor mesh keeps the
#     PRE-stroke heights and the user sees it floating above or sunken
#     into the new terrain shape)
#   - Slider changes (preview new radius / mask without moving finger)
func _conform_brush_to_surface(hit_point: Vector3):
	if not is_instance_valid(brush_cursor): return
	if not selected_node: return
	# V21: respect the master brush toggle. Without this guard, any code
	# path that calls _conform_brush_to_surface (slider drag,
	# brush_applied signal, motion event that slipped past the gate)
	# would re-show the cursor even though the user explicitly toggled
	# brush input off. The toggle handler hides it; this guard keeps it
	# hidden across all rebuild trigger points.
	if not brush_enabled:
		brush_cursor.hide()
		return
	_last_brush_hit = hit_point
	brush_cursor.show()
	# Note: do NOT call _update_brush_visual_properties() here — it now
	# calls back into this function (so slider drags repaint), which
	# would create infinite recursion. All visual-property work
	# (per-vertex strength tint, base colour, mask sampling) is done
	# inline below.
	
	var im := brush_cursor.mesh as ImmediateMesh
	if im == null: return
	im.clear_surfaces()
	
	var radius: float = selected_node.brush_radius
	# Grid density. 20×20 = 400 vertices, ~720 triangles. Light enough
	# to rebuild every motion event on mobile; dense enough that the
	# mask's silhouette (especially fine details like ring_thin) reads
	# clearly. Higher than ~32 starts to hitch on low-end Adreno GPUs.
	const GRID := 20
	var lift: float = 0.05 + radius * 0.005
	var origin: Vector3 = selected_node.global_position
	
	# Pre-fetch the mask image once. Sampling brush_mask through GPU is
	# expensive (and would require shader code); sampling the cached CPU
	# Image is array indexing.
	var mask_img: Image = null
	if selected_node.brush_mask != null:
		mask_img = selected_node._brush_mask_image
	var mw: int = 1
	var mh: int = 1
	if mask_img != null:
		mw = mask_img.get_width()
		mh = mask_img.get_height()
	
	# Pre-compute the vertex grid: positions + vertex colors. Positions
	# are world-space; vertex colors carry the mask's red channel as
	# alpha (used by the unshaded vertex_color_use_as_albedo material).
	var positions: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	positions.resize(GRID * GRID)
	colors.resize(GRID * GRID)
	
	# Strength-derived alpha (mirrors what _update_brush_visual_properties
	# does with the material albedo_color). Computed here so per-vertex
	# colours combine mask shape × strength tint in one shot.
	# V21: normalize against the slider range [0.1, 2.0] (was 5.0).
	# clampf belt-and-braces protects against scenes saved with older
	# brush_strength > 2.0 values — see _set_brush_strength setter for
	# the corresponding load-time clamp.
	var norm_strength: float = clampf((selected_node.brush_strength - 0.1) / (2.0 - 0.1), 0.0, 1.0)
	var strength_alpha: float = lerpf(0.35, 0.85, norm_strength)
	
	var base_color: Color = Color(1.0, 0.4, 0.2)
	if selected_node.current_tool == 7:    # Paint
		base_color = Color(0.1, 0.9, 0.4)
	elif selected_node.current_tool == 6:  # Erosion
		base_color = Color(0.2, 0.6, 1.0)
	
	for j in range(GRID):
		for i in range(GRID):
			# UV across the grid, in [0, 1].
			var u: float = float(i) / float(GRID - 1)
			var v: float = float(j) / float(GRID - 1)
			# Map to local offset from hit_point in world XZ.
			var dx: float = (u - 0.5) * 2.0 * radius
			var dz: float = (v - 0.5) * 2.0 * radius
			var wx: float = hit_point.x + dx
			var wz: float = hit_point.z + dz
			# Sample terrain height at this world XZ for the drape.
			var sx: int = int(floor(wx - origin.x))
			var sz: int = int(floor(wz - origin.z))
			var wy: float = selected_node.get_height(sx, sz) + origin.y + lift
			positions[j * GRID + i] = Vector3(wx, wy, wz)
			
			# Sample mask at the same UV. Outside the unit circle the
			# pre-baked black margin returns 0 so corners disappear; the
			# brush cursor is naturally circular even though the mesh is
			# a square grid.
			var mask_alpha: float = 1.0
			if mask_img != null:
				var ix: int = clampi(int(u * mw), 0, mw - 1)
				var iy: int = clampi(int(v * mh), 0, mh - 1)
				mask_alpha = mask_img.get_pixel(ix, iy).r
			else:
				# Legacy mode (no mask): fall back to soft circular falloff
				# so the cursor still LOOKS like a brush footprint and not
				# a solid square.
				var r_norm: float = sqrt((u - 0.5) * (u - 0.5) + (v - 0.5) * (v - 0.5)) * 2.0
				mask_alpha = clampf(1.0 - r_norm * r_norm * (3.0 - 2.0 * r_norm), 0.0, 1.0)
			
			colors[j * GRID + i] = Color(base_color.r, base_color.g, base_color.b, mask_alpha * strength_alpha)
	
	# Build triangle topology: two triangles per grid cell.
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(GRID - 1):
		for i in range(GRID - 1):
			var i00: int = j * GRID + i
			var i10: int = j * GRID + (i + 1)
			var i01: int = (j + 1) * GRID + i
			var i11: int = (j + 1) * GRID + (i + 1)
			# Triangle 1: i00 → i10 → i11
			im.surface_set_color(colors[i00]); im.surface_add_vertex(positions[i00])
			im.surface_set_color(colors[i10]); im.surface_add_vertex(positions[i10])
			im.surface_set_color(colors[i11]); im.surface_add_vertex(positions[i11])
			# Triangle 2: i00 → i11 → i01
			im.surface_set_color(colors[i00]); im.surface_add_vertex(positions[i00])
			im.surface_set_color(colors[i11]); im.surface_add_vertex(positions[i11])
			im.surface_set_color(colors[i01]); im.surface_add_vertex(positions[i01])
	im.surface_end()

# V21 compatibility shim: a few call sites still call the old name. Just
# forwards to the new function.
func _conform_decal_to_surface(hit_point: Vector3):
	_conform_brush_to_surface(hit_point)
