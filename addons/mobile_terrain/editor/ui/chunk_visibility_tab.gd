@tool
class_name TerrainChunkVisibilityTab
extends VBoxContainer

## TerrainChunkVisibilityTab — the "Chunk'lar" tab of the plugin panel.
##
## TKT-020 F1: editor-only chunk visibility manager. Renders the terrain's
## chunk grid as an N×N board of toggle buttons; pressed = chunk is on the
## whitelist (renders + meshes), unpressed = hidden (mesh dropped, rebuilds
## skipped). All state lives on the MobileTerrain3D node
## (chunk_visibility_enabled / visible_chunks / set_chunk_visible API) — this
## tab is a pure view+controller and holds no authority of its own, so a
## panel rebuild or scene switch can never desync persisted state.
##
## Lives in its own file (not inline in mobile_terrain_plugin.gd) per the
## TKT-002 C5 decomposition direction: new editor surfaces go to editor/ui/.

# Above this many cells the grid widget itself becomes the lag (1024 buttons
# is the auto-bump worst case and still fine; "extreme" maps that blew past
# MAX_CHUNK_COUNT get bulk ops only).
const MAX_GRID_CELLS := 1089  # 33 × 33

# Toggle cell side in px. 26 keeps a 20×20 grid under 560 px wide while
# staying a usable touch target on tablet editors.
const CELL_PX := 26

var _terrain = null  # MobileTerrain3D currently shown; untyped like the plugin's selected_node
var _master_check: CheckButton
var _count_label: Label
var _grid: GridContainer
var _grid_scroll: ScrollContainer
var _notice_label: Label
var _cell_buttons: Dictionary = {}  # Vector2i -> Button
var _style_on: StyleBoxFlat
var _style_off: StyleBoxFlat


func _init() -> void:
	name = "Chunk'lar"
	add_theme_constant_override("separation", 6)

	_style_on = StyleBoxFlat.new()
	_style_on.bg_color = Color(0.22, 0.62, 0.32)  # green = visible
	_style_on.set_corner_radius_all(3)
	_style_off = StyleBoxFlat.new()
	_style_off.bg_color = Color(0.16, 0.16, 0.2)  # dark = hidden
	_style_off.set_corner_radius_all(3)

	_master_check = CheckButton.new()
	_master_check.text = "Görünürlük modu AKTİF"
	_master_check.tooltip_text = (
		"Açıkken SADECE yeşil işaretli chunk'lar editörde görünür ve mesh'lenir;"
		+ " kapalı chunk'lar sıfır maliyet. Oyun ÇALIŞIRKEN her şey görünür"
		+ " (bu mod yalnızca editör içindir)."
	)
	_master_check.toggled.connect(_on_master_toggled)
	add_child(_master_check)

	var bulk := HBoxContainer.new()
	bulk.add_theme_constant_override("separation", 4)
	var btn_all := Button.new()
	btn_all.text = "Tümünü Aç"
	btn_all.pressed.connect(_on_bulk_all.bind(true))
	bulk.add_child(btn_all)
	var btn_none := Button.new()
	btn_none.text = "Tümünü Kapat"
	btn_none.pressed.connect(_on_bulk_all.bind(false))
	bulk.add_child(btn_none)
	var btn_invert := Button.new()
	btn_invert.text = "Tersine Çevir"
	btn_invert.pressed.connect(_on_bulk_invert)
	bulk.add_child(btn_invert)
	add_child(bulk)

	_count_label = Label.new()
	_count_label.add_theme_font_size_override("font_size", 10)
	_count_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	add_child(_count_label)

	_notice_label = Label.new()
	_notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_notice_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
	_notice_label.hide()
	add_child(_notice_label)

	_grid_scroll = ScrollContainer.new()
	_grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid_scroll.custom_minimum_size = Vector2(0, 240)
	add_child(_grid_scroll)

	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 2)
	_grid.add_theme_constant_override("v_separation", 2)
	_grid_scroll.add_child(_grid)


# Rebind to a terrain (or null) and rebuild the board. Called by the plugin
# on panel open, tab switch, and terrain (re)selection — NOT per frame.
func refresh(terrain) -> void:
	_terrain = terrain
	for child in _grid.get_children():
		child.queue_free()
	_cell_buttons.clear()
	_notice_label.hide()
	if _terrain == null or not is_instance_valid(_terrain):
		_master_check.set_pressed_no_signal(false)
		_count_label.text = "Terrain seçili değil."
		return

	_master_check.set_pressed_no_signal(_terrain.chunk_visibility_enabled)

	var num_chunks: int = 0
	if _terrain.chunk_size > 0:
		num_chunks = _terrain.map_size / _terrain.chunk_size
	var total: int = num_chunks * num_chunks
	if total <= 0:
		_count_label.text = "Chunk grid'i henüz oluşmadı."
		return
	if total > MAX_GRID_CELLS:
		_notice_label.text = (
			"%d chunk var — grid bu boyutta gösterilmiyor (panelin kendisi kasardı). Toplu butonları kullan."
			% total
		)
		_notice_label.show()
		_update_count_label()
		return

	_grid.columns = num_chunks
	for cz in range(num_chunks):
		for cx in range(num_chunks):
			var coord := Vector2i(cx, cz)
			var btn := Button.new()
			btn.toggle_mode = true
			btn.custom_minimum_size = Vector2(CELL_PX, CELL_PX)
			btn.focus_mode = Control.FOCUS_NONE
			btn.tooltip_text = "Chunk (%d, %d)" % [cx, cz]
			btn.set_pressed_no_signal(_terrain._visible_chunk_set.has(coord))
			_apply_cell_style(btn)
			btn.toggled.connect(_on_cell_toggled.bind(coord))
			_grid.add_child(btn)
			_cell_buttons[coord] = btn
	_update_count_label()


func _apply_cell_style(btn: Button) -> void:
	var style: StyleBoxFlat = _style_on if btn.button_pressed else _style_off
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_stylebox_override("focus", style)


func _update_count_label() -> void:
	if _terrain == null or not is_instance_valid(_terrain):
		return
	var num_chunks: int = 0
	if _terrain.chunk_size > 0:
		num_chunks = _terrain.map_size / _terrain.chunk_size
	_count_label.text = (
		"%d / %d chunk görünür."
		% [_terrain.visible_chunks.size(), num_chunks * num_chunks]
	)


func _on_master_toggled(pressed: bool) -> void:
	if _terrain == null or not is_instance_valid(_terrain):
		return
	_terrain.chunk_visibility_enabled = pressed


func _on_cell_toggled(pressed: bool, coord: Vector2i) -> void:
	if _terrain == null or not is_instance_valid(_terrain):
		return
	_terrain.set_chunk_visible(coord, pressed)
	var btn: Button = _cell_buttons.get(coord)
	if btn != null:
		_apply_cell_style(btn)
	_update_count_label()


func _on_bulk_all(on: bool) -> void:
	if _terrain == null or not is_instance_valid(_terrain):
		return
	_terrain.set_all_chunks_visible(on)
	_sync_cells_from_terrain()


func _on_bulk_invert() -> void:
	if _terrain == null or not is_instance_valid(_terrain):
		return
	_terrain.invert_chunk_visibility()
	_sync_cells_from_terrain()


# Re-sync every cell's pressed state from the node after a bulk op —
# cheaper than a full rebuild and keeps scroll position.
func _sync_cells_from_terrain() -> void:
	for coord in _cell_buttons:
		var btn: Button = _cell_buttons[coord]
		btn.set_pressed_no_signal(_terrain._visible_chunk_set.has(coord))
		_apply_cell_style(btn)
	_update_count_label()
