@tool
extends Node3D

@export_category("Terrain Core")
@export var map_size: int = 256:
	set = _set_map_size
@export var chunk_size: int = 32:
	set = _set_chunk_size
@export var terrain_material: Material:
	set = _set_material
# Path to this terrain's companion .res under res://terrain_data/, bound
# automatically on first save (save_terrain_data). height_data and the splatmap
# are loaded from it; the heavy data is NEVER inlined into the .tscn anymore
# (see the note below), so the .res is the single source of truth.
@export_file("*.res") var external_data_path: String = "":
	set = _set_external_data_path
# Heavy terrain data. These are PLAIN (non-@export) vars, so Godot never
# serializes them into the .tscn — the scene only stores external_data_path and
# the bytes live in the companion .res (save_terrain_data /
# _load_external_data_if_set). The splatmap also rides on terrain_material as a
# shader parameter, which is why terrain_material's STORAGE is stripped in
# _validate_property (otherwise the .tscn would re-embed the splatmap image —
# the 22 MB "scene large on disk" bug).
var height_data: PackedFloat32Array
var splatmap_texture_local: ImageTexture

@export_category("Varlık Yöneticisi")
@export var terrain_textures: Array[Texture2D] = []
# V21: PBR slot extension. Each map array runs in parallel with
# terrain_textures (albedo). terrain_normal[i], terrain_roughness[i],
# terrain_ao[i] correspond to the same slot i. They are kept in sync by
# the plugin UI and on _ready (migration of old V19/V20 scenes).
@export var terrain_normal: Array[Texture2D] = []
@export var terrain_roughness: Array[Texture2D] = []
@export var terrain_ao: Array[Texture2D] = []
# V21: extra map slots. Storage only — the default PBR shader doesn't
# sample these yet (Mobile renderer's texture-unit budget is tight at
# 17 samplers already; adding 3 × 4 = 12 more would risk breaking
# shader compile on lower-end Adreno/Mali). Pickers are in the Asset
# Manager so users can ASSIGN their _disp / _metal / _emit textures
# and reference them from a custom shader; auto-detect populates them
# alongside the other PBR maps if the naming convention matches.
@export var terrain_height: Array[Texture2D] = []
@export var terrain_metallic: Array[Texture2D] = []
@export var terrain_emission: Array[Texture2D] = []
@export var asset_meshes: Array[Mesh] = []

@export_category("Gelişmiş PBR Settings")
@export var texture_scale: float = 1.0:
	set = _set_tex_scale
# V21: New PBR controls. These multiply onto the shader output, so they
# work uniformly across all slots without per-slot UI bloat.
@export_range(0.0, 2.0) var normal_strength: float = 1.0:
	set = _set_normal_strength
@export_range(0.0, 2.0) var roughness_multiplier: float = 1.0:
	set = _set_roughness_multiplier
@export_range(0.0, 1.0) var ao_strength: float = 1.0:
	set = _set_ao_strength
# V21: Anti-tile variation. 0 = old single-sample tile (cheap, grids
# visible on small tiling textures). 1 = full variation, doubles
# albedo texture cost. See _mt_sample_var in TERRAIN_SHADER. Sweet
# spot for grass/dirt is usually around 0.4-0.7.
@export_range(0.0, 1.0) var texture_variation: float = 0.0:
	set = _set_texture_variation
# V21 anti-tile pro: see the matching uniform comments in TERRAIN_SHADER
# for what each parameter does to the look. All three default to "off"-
# adjacent values so existing scenes render unchanged after V21 upgrade.
@export_range(1.0, 50.0) var texture_cell_size: float = 10.0:
	set = _set_texture_cell_size
@export_range(0.0, 1.0) var rotation_jitter: float = 0.0:
	set = _set_rotation_jitter
@export_range(0.0, 1.0) var triplanar_blend: float = 0.0:
	set = _set_triplanar_blend
# slope_rock_factor: kept for backward compat with V19/V20 scenes that
# saved this property. The new PBR shader no longer auto-blends rock by
# slope — that was a single-slot hack. Paint rock onto slot 2 (or any
# slot) yourself via the brush. The setter is a no-op now.
@export var slope_rock_factor: float = 0.7:
	set = _set_slope_rock

@export_category("EXR Heightmap Import")
@export var import_texture: Texture2D
@export var import_max_height: float = 50.0
@export var click_to_import: bool = false:
	set = _import_exr

var current_tool: int = 0:
	set = _set_current_tool
# TKT-004 H8: clamp on assign. The splatmap is RGBA8 (4 slots), so a paint
# slot outside [0, 3] would write to an undefined channel. A runtime guard
# in _paint_splatmap already returns early on OOB, but clamping in the
# setter keeps the value valid no matter where it's written from (UI
# refresh race, script, scene load) rather than silently skipping a dab.
var current_paint_slot: int = 0:
	set = _set_current_paint_slot
var current_object_slot: int = 0:
	set = _set_current_object_slot
var brush_shape: int = 0
var brush_radius: float = 8.0:
	set = _set_brush_radius


# V21: symmetric to brush_strength — clamp on every write so script-set
# or scene-load can't put the node in a state the slider can't reach.
# Range matches the radius slider [1.0, 50.0]. Lower bound > 0 prevents
# the disc-uniform sample (sqrt(randf()) * radius) from collapsing all
# instances to the brush centre, and protects against div-by-zero in
# the brush UV math.
func _set_brush_radius(val: float) -> void:
	brush_radius = clampf(val, 1.0, 50.0)


# V22: switching tools must invalidate the paint stroke cache. Without
# this, a paint stroke that ended via tool-switch (instead of mouse-up)
# left _splatmap_stroke_image pointing at the previous-tool's image; the
# next paint stroke would write through that stale reference and silently
# corrupt splatmap_data on commit.
func _set_current_tool(val: int) -> void:
	if current_tool == val:
		return
	current_tool = val
	_splatmap_stroke_image = null


func _set_current_paint_slot(val: int) -> void:
	current_paint_slot = clampi(val, 0, 3)


func _set_current_object_slot(val: int) -> void:
	# Clamp negatives; the upper bound is dynamic (asset_meshes resizes) and is
	# enforced at the placement call site (apply_brush_stroke_slope).
	current_object_slot = maxi(0, val)


# V21: default lowered from 0.5 to 0.2. With the rate-limit cap at 25 Hz,
# a stationary tap at strength 0.2 raises centre height by ~5 units/sec
# instead of the ~30/sec the old 0.5-default produced. Less surprising
# starting behaviour for new users; advanced users can still crank to 5.0.
# V21: setter clamps to [0.1, 2.0]. Old V20 saved scenes may have
# brush_strength up to 5.0 (the previous slider max). Without clamping,
# loading such a scene would put the node in a state where node.brush_strength
# = 4.5 but slider.value = 2.0 (the new clamp) — a confusing desync
# where dragging the slider seems to do nothing for the first chunk of
# the range, because each write is just re-clamping. Clamp on assign
# fixes this regardless of where the assignment came from (scene load,
# script set, slider change).
var brush_strength: float = 0.2:
	set = _set_brush_strength


func _set_brush_strength(val: float) -> void:
	brush_strength = clampf(val, 0.1, 2.0)


# Object placement controls (TerrainObjectPlacer). Simple "stamp" model:
# with the Object tool active, dragging lays ONE instance per
# `object_spacing` units travelled (a held finger places exactly one).
# Replaces the old random-scatter system.
#   - object_spacing: min distance between consecutive placements.
#   - object_scale:   uniform scale applied to each placed instance — lets a
#                     large source mesh be shrunk so it isn't a "giant cube".
#   - object_align_to_normal: tilt instances to follow the surface slope
#                     (off = always upright / standing straight).
#   - object_random_yaw: random spin around the up axis so repeated objects
#                     don't look identical (off = deterministic).
@export_range(0.1, 50.0) var object_spacing: float = 2.0
@export_range(0.01, 100.0) var object_scale: float = 1.0
@export var object_align_to_normal: bool = false
@export var object_random_yaw: bool = false
# V21: timestamp of last brush application, seconds. Used by
# apply_brush_stroke_slope to throttle stationary strokes.
var _last_brush_apply_time: float = 0.0

# V21: BRUSH MASK SYSTEM — Terrain3D-style alpha-mask library.
#
# Until V20 the brush footprint was one of 5 hard-coded falloffs
# (Yumuşak, Keskin, Kare, Elmas, Gürültü) selected via `brush_shape`.
# V21 keeps `brush_shape` for back-compat but adds an optional
# `brush_mask` texture — any greyscale image. When set, each affected
# terrain pixel samples the mask in unit-disc UV space (centre = (0.5,
# 0.5), edge = unit circle), and the resulting alpha is the falloff
# strength. This lets a single texture-paint or sculpt tool ("Yükselt",
# "Boya", ...) be combined with any of the 20+ shipped masks
# (circles, rings, hills, peaks, noise, splotches, vegetation
# scatter, etc.) or any custom mask the user drops in
# `addons/mobile_terrain/brushes/`. Tool = what action; Mask = how
# the action is distributed across the footprint.
@export var brush_mask: Texture2D = null:
	set = _set_brush_mask

# Cached Image extracted from `brush_mask` for cheap pixel sampling
# during a stroke. We re-extract only when the texture handle changes
# (see _set_brush_mask); within a stroke we hit `_brush_mask_image`
# directly, never the GPU texture. None when no mask is set, in which
# case `brush_shape_falloff` falls back to the legacy hard-coded shapes.
var _brush_mask_image: Image = null

var chunks: Dictionary = {}
var multimesh_instances: Dictionary = {}
var dirty_chunks: Dictionary = {}
var last_sculpt_pos: Vector3 = Vector3.INF
var last_placement_pos: Vector3 = Vector3.INF
var splatmap_data: PackedByteArray

# V20 FIX (#14): cache the splatmap CPU image for the duration of a paint
# stroke. The brush was calling `splatmap_texture_local.get_image()` on
# every dab — each call allocates a fresh 256KB CPU copy of the entire
# splatmap (default 256×256 RGBA8 = 256KB). At 60Hz mouse motion that's
# ~46 MB/s of throwaway allocation, which on mobile shows up as GC
# pressure and frame hitches.
#
# Strategy: copy the image ONCE in start_stroke(), mutate it in place
# across all dabs of the stroke, sync `splatmap_data` (the byte-array
# mirror used by undo) and drop the cache in end_stroke().
#
# Stays null outside a paint stroke so ad-hoc/scripted calls into
# `_paint_splatmap` still work via the fallback path in that function.
var _splatmap_stroke_image: Image = null
# V22 FIX (audit-chunk-resize-during-stroke + audit-paint-init-mid-stroke):
# Stroke lifecycle bookkeeping. `_active_stroke` toggles in start/end so
# destructive setters can defer. `_stroke_revision` increments per stroke
# and is captured into `_splatmap_stroke_revision` when the paint cache
# is taken; end_stroke compares them to detect a stale cache after a
# splatmap rebuild that happened mid-stroke.
var _active_stroke: bool = false
var _stroke_revision: int = 0
var _splatmap_stroke_revision: int = -1
# Pending resize values queued by setters when called during a stroke
# or during initialize_terrain. 0 means "no pending change".
var _deferred_map_size: int = 0
var _deferred_chunk_size: int = 0
# Re-entry guard for initialize_terrain (set true on entry, false on exit).
# Prevents setter cascade -> initialize_terrain -> setter cascade loops.
var _rebuilding_terrain: bool = false

# Emitted whenever TerrainObjectPlacer successfully adds an instance to a
# MultiMesh. The editor plugin listens to this signal to
# build per-stroke undo actions for object placement — without it, plugin
# code has no way to know which MultiMesh got modified or which transform
# was added (placement is internal to the node, and modifying height_data
# / splatmap_data — the only state previously visible through the undo
# system — is not what object placement does).
#
# Arguments:
#   mmi              - the MultiMeshInstance3D that received the new instance.
#   instance_index   - the index of the new instance within mmi.multimesh.
#                      Equals the previous instance_count (i.e. the slot we
#                      just expanded into).
#   placement_transform - the transform that was set on that instance.
signal foliage_placed(
	mmi: MultiMeshInstance3D, instance_index: int, placement_transform: Transform3D
)

# V21: emitted once per actual brush application (after rate-limit
# throttling). The plugin connects to this so the cursor mesh re-drapes
# itself onto the freshly-modified terrain — without this, a held-finger
# Alçalt stroke would let the terrain drop while the cursor stayed at
# the pre-stroke heights, eventually leaving the cursor floating above
# (or sinking inside) the now-changed surface.
signal brush_applied(hit_point: Vector3)

# V19 PRO: Noise generator for advanced brushes
var noise_gen: FastNoiseLite

# V21: auto-externalize threshold in cells. Above this size the data
# is automatically migrated to a .res file on scene save, so the
# .tscn stays small even if the user forgets to click the button.
# 512² = 262144 cells = ~1 MB inline → still small enough to be polite
# to git diff. Above that, externalize unconditionally.
#
# NOTE: the auto-migration trigger lives in the EditorPlugin (see
# mobile_terrain_plugin.gd::_save_external_data). Node3D doesn't
# receive NOTIFICATION_EDITOR_PRE_SAVE — that constant was historically
# proposed but never wired to Node-class instances in any released
# Godot 4 build, confirmed via engine source. _save_external_data on
# EditorPlugin is the documented hook the engine actually calls.
# TKT-011: every terrain always writes its data to a .res under
# res://terrain_data/ (see save_terrain_data); nothing heavy is baked into
# the .tscn because height_data/splatmap are plain (non-@export) vars.

# V21: guard against the external_data_path setter cascading when WE
# (internal code) assign it. Set true around internal assignments to
# skip the reload logic; user-initiated inspector edits keep the flag
# false and trigger a fresh load from the new path.
var _suppress_external_path_setter: bool = false


# V21: setter for external_data_path. Lets the inspector trigger a
# reload when the user manually edits the path, without breaking the
# internal assign sites that just need to record the new path.
#
# Internal sites (save_terrain_data binding it on first save,
# _load_external_data_if_set) set _suppress_external_path_setter = true
# before writing the field, then clear it after. User-driven edits
# (inspector typing, file picker) leave the flag false and trigger the
# reload+initialise path.
func _set_external_data_path(val: String) -> void:
	var was_set := external_data_path != ""
	external_data_path = val
	if _suppress_external_path_setter:
		return
	if val == "" and was_set:
		# User cleared the path. Don't auto-load — they might want to
		# enter a new path, or keep current in-memory data inline.
		# Notify so the inspector reflects the mode change (inline vs
		# external) via _validate_property.
		notify_property_list_changed()
		return
	if val != "":
		# User set or changed to a non-empty path. Load from the new file.
		# _load_external_data_if_set bails safely if the file is missing.
		_suppress_external_path_setter = true
		_load_external_data_if_set()
		_suppress_external_path_setter = false
		notify_property_list_changed()
		# Skip the rebuild while a stroke is in flight: this direct path has no
		# deferral, and re-entering initialize_terrain mid-stroke would corrupt
		# it (the map_size cascade inside _load_external_data_if_set already
		# defers its own rebuild while _active_stroke is set). end_stroke replays
		# any deferred map_size/chunk_size change, restoring a consistent state.
		if Engine.is_editor_hint() and not _active_stroke:
			# Rebuild visuals from the freshly-loaded data.
			initialize_terrain()
			update_shader_textures()


# V21: dynamic property USAGE for the heavy data fields.
#
# `var height_data` and `var splatmap_texture_local` are plain (non-@export)
# script variables, which Godot exposes with PROPERTY_USAGE_SCRIPT_VARIABLE
# by default — settable from script but NOT saved to .tscn. That's the
# safe default; we then OPT IN to serialization via _validate_property
# when external storage isn't being used.
#
# _validate_property is the right hook (not _get_property_list, which
# would ADD a second entry, double-serialising the data and confusing
# the inspector). It receives each property the engine plans to expose
# and lets us mutate the .usage field in place.
#
# When external_data_path is empty → add PROPERTY_USAGE_STORAGE so the
# .tscn embeds the data (inline mode, the original behaviour pre-V21).
func _validate_property(property: Dictionary) -> void:
	# TKT-006: dead V19/V20 property — the V21 PBR shader ignores
	# slope_rock_factor (rock is painted via the splatmap now). Keep STORAGE
	# so old scenes still deserialize it without error, but drop EDITOR so it
	# stops showing a non-functional "Eğim" control.
	# TKT-011: the old height_data/splatmap_texture_local NOSTORE gating is
	# gone — they're plain (non-@export) vars, so the serializer never writes
	# them and there's nothing to gate.
	if property.name == "slope_rock_factor":
		property.usage = PROPERTY_USAGE_STORAGE
	elif property.name == "terrain_material":
		# The ShaderMaterial is DERIVED state: _ready rebuilds it every load
		# via _setup_default_shader + update_shader_textures (textures come
		# from the @export arrays, the splatmap from the .res). Storing it
		# embeds the live map_size² splatmap ImageTexture into the .tscn — a
		# ~22 MB blob at 1280² that triggers Godot's "scene large on disk"
		# warning. Drop STORAGE (keep EDITOR so the inspector still shows it)
		# so the scene never carries the material or its splatmap. Old scenes
		# that already embed it shed the blob on the next save.
		property.usage = property.usage & ~PROPERTY_USAGE_STORAGE


func _ready() -> void:
	noise_gen = FastNoiseLite.new()
	noise_gen.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_gen.frequency = 0.1

	# V21: external storage load. If external_data_path is set, we
	# overwrite the inline height_data and splatmap_texture_local with
	# whatever's in the .res file. This runs BEFORE the height_data
	# initialisation below so the resource's content takes precedence
	# over an empty default. Failures (missing file, wrong format, etc.)
	# leave the inline values intact and print a warning — the user
	# can re-create the link via the Externalize button.
	_load_external_data_if_set()

	if height_data.is_empty():
		height_data.resize(map_size * map_size)
		height_data.fill(0.0)

	while terrain_textures.size() < 4:
		terrain_textures.append(null)

	# V21: PBR array migration. Old V19/V20 scenes only saved
	# `terrain_textures` (albedo); the new normal/roughness/AO arrays
	# load empty. Pad them to match the albedo count so the rest of
	# the codebase can index any slot in any array without bounds checks.
	# Existing slots get `null` entries — the shader handles null via
	# the blank-texture fallback in update_shader_textures.
	while terrain_normal.size() < terrain_textures.size():
		terrain_normal.append(null)
	while terrain_roughness.size() < terrain_textures.size():
		terrain_roughness.append(null)
	while terrain_ao.size() < terrain_textures.size():
		terrain_ao.append(null)
	# V21: same migration for the extra (storage-only) slots.
	while terrain_height.size() < terrain_textures.size():
		terrain_height.append(null)
	while terrain_metallic.size() < terrain_textures.size():
		terrain_metallic.append(null)
	while terrain_emission.size() < terrain_textures.size():
		terrain_emission.append(null)
	# Also trim if somehow longer (shouldn't happen but defensive):
	terrain_normal.resize(terrain_textures.size())
	terrain_roughness.resize(terrain_textures.size())
	terrain_ao.resize(terrain_textures.size())
	terrain_height.resize(terrain_textures.size())
	terrain_metallic.resize(terrain_textures.size())
	terrain_emission.resize(terrain_textures.size())

	_initialize_splatmap()
	_setup_default_shader()

	call_deferred("initialize_terrain")
	call_deferred("restore_multimeshes")


# V20 FIX: Bring splatmap data and texture into a state consistent with
# the current `map_size`, preserving painted content where possible.
#
# Called from _ready() (initial setup) and from _set_map_size() (when the
# user changes map size at edit time). The previous implementation only
# handled the "fresh terrain" case: if you opened a saved scene with a
# painted splatmap and then changed map_size, splatmap_texture_local
# kept its old dimensions while every other piece of state (heightmap,
# chunks, UV mapping) moved to the new size. The result was silently
# broken — painting at x > old_size on the new map would no-op because
# `img.set_pixel(x, z, ...)` was writing into a smaller image; existing
# paint stretched across the larger surface like a smeared poster.
#
# This function now considers all combinations of (texture present /
# data present / size match / size mismatch) and converges to a valid
# state. Branches in order:
#
#   - Texture present, size matches  → sync byte data from texture (no-op visually)
#   - Texture present, size mismatch → bilinear-resize, replace texture
#   - Texture missing, data valid    → build texture from data
#   - Texture missing, data invalid  → fill defaults (R=255, GBA=0), build texture
#
# CALLER NOTE: when this function REPLACES splatmap_texture_local with
# a new ImageTexture (the mismatch and "texture missing" branches), the
# shader's "splatmap" uniform still holds the old handle. Callers must
# follow up with `update_shader_textures()` to rebind. `_set_map_size`
# does this; `_ready` does it transitively via `_setup_default_shader`.
func _initialize_splatmap():
	var expected_bytes := map_size * map_size * 4
	# V21 CRITICAL FIX: drop any in-flight stroke cache. If a paint stroke
	# was active when map_size changed, _splatmap_stroke_image still points
	# at the OLD-sized image. Subsequent paint dabs would write into that
	# stale image; end_stroke would then copy the old-sized bytes back
	# into splatmap_data, corrupting it with a size mismatch. By clearing
	# here we force the caller's stroke to either restart or take the
	# fallback get_image() path in _paint_splatmap (which re-reads from
	# the freshly-resized texture).
	_splatmap_stroke_image = null

	# --- Branch A: there's an existing texture. ---
	if splatmap_texture_local != null:
		var img := splatmap_texture_local.get_image()
		if img != null:
			if img.get_width() == map_size and img.get_height() == map_size:
				# Size matches — just sync byte data from texture. This is
				# the path taken on re-opening a saved scene where the user
				# hasn't changed map_size. Mirrors the original behavior.
				splatmap_data = img.get_data()
				return
			else:
				# Size mismatch — user changed map_size after painting.
				# Resize with bilinear filtering to preserve broad paint
				# distribution. Bilinear may produce blended slot weights
				# at boundaries (e.g. R=128, G=128); that's fine because
				# the shader's per-fragment normalize handles it and the
				# result is a smooth slot transition rather than a hard
				# step, which is usually what you'd want anyway.
				img.resize(map_size, map_size, Image.INTERPOLATE_BILINEAR)
				# Create a fresh ImageTexture because ImageTexture.update()
				# requires same-size and `set_image()` semantics vary across
				# Godot 4 patch versions. A new instance is unambiguous.
				splatmap_texture_local = ImageTexture.create_from_image(img)
				splatmap_data = img.get_data()
				return
		# img somehow null — fall through to rebuild from scratch.
		splatmap_texture_local = null

	# --- Branch B: no texture. Build from byte data or defaults. ---
	if splatmap_data.size() != expected_bytes:
		# Either empty (fresh terrain) or wrong size (e.g. a stale buffer
		# left over from an earlier map_size). Reset to default: slot 0
		# fully active everywhere (R=255, GBA=0). The shader normalizes
		# this to (1,0,0,0) so the terrain renders as a uniform sheet of
		# the first texture, a sensible "blank canvas" starting point.
		splatmap_data.resize(expected_bytes)
		for i in range(map_size * map_size):
			splatmap_data[i * 4] = 255
			splatmap_data[i * 4 + 1] = 0
			splatmap_data[i * 4 + 2] = 0
			splatmap_data[i * 4 + 3] = 0

	var img := Image.create_from_data(map_size, map_size, false, Image.FORMAT_RGBA8, splatmap_data)
	splatmap_texture_local = ImageTexture.create_from_image(img)


## V22: TERRAIN_SHADER moved to shaders/terrain.gdshader. See
## _setup_default_shader for the load path. Kept here as a fallback
## inline string so addons enabled without a full project import (e.g.
## drag-dropped into a fresh project before res:// scan) still get a
## working shader. The .gdshader file is the source of truth — any edit
## must mirror to both.
const TERRAIN_SHADER = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// V21: Full PBR slot system. Each of the 4 splatmap channels controls
// a complete texture bundle: albedo + normal + roughness + AO. All four
// blend by the same splatmap weight so they stay visually coherent.

uniform sampler2D splatmap : filter_linear_mipmap, hint_default_black, repeat_disable;

// Albedo (RGB colour, sRGB encoded). hint_default_black means an empty
// slot contributes nothing to the final colour — so painting a non-zero
// splatmap weight on an empty slot produces black, which is the correct
// "this slot has no texture" appearance.
uniform sampler2D tex_a_0 : source_color, filter_linear_mipmap_anisotropic, hint_default_black;
uniform sampler2D tex_a_1 : source_color, filter_linear_mipmap_anisotropic, hint_default_black;
uniform sampler2D tex_a_2 : source_color, filter_linear_mipmap_anisotropic, hint_default_black;
uniform sampler2D tex_a_3 : source_color, filter_linear_mipmap_anisotropic, hint_default_black;

// Normal maps (tangent-space, RGB encoded with R/G containing X/Y and B
// reconstructed by Godot). hint_normal makes Godot default to a flat
// normal (0.5, 0.5, 1.0 → world (0, 0, 1)) for empty slots, so missing
// normal maps don't tilt the surface.
uniform sampler2D tex_n_0 : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_n_1 : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_n_2 : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_n_3 : hint_normal, filter_linear_mipmap_anisotropic;

// Roughness (single channel, linear, R = roughness). hint_default_white
// = full roughness when empty, which renders as matte (not shiny).
uniform sampler2D tex_r_0 : filter_linear_mipmap_anisotropic, hint_default_white;
uniform sampler2D tex_r_1 : filter_linear_mipmap_anisotropic, hint_default_white;
uniform sampler2D tex_r_2 : filter_linear_mipmap_anisotropic, hint_default_white;
uniform sampler2D tex_r_3 : filter_linear_mipmap_anisotropic, hint_default_white;

// AO (single channel, linear, R = occlusion factor). hint_default_white
// = no occlusion when empty.
uniform sampler2D tex_ao_0 : filter_linear_mipmap_anisotropic, hint_default_white;
uniform sampler2D tex_ao_1 : filter_linear_mipmap_anisotropic, hint_default_white;
uniform sampler2D tex_ao_2 : filter_linear_mipmap_anisotropic, hint_default_white;
uniform sampler2D tex_ao_3 : filter_linear_mipmap_anisotropic, hint_default_white;

uniform float tex_scale = 1.0;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float roughness_multiplier : hint_range(0.0, 2.0) = 1.0;
uniform float ao_strength : hint_range(0.0, 1.0) = 1.0;
// V21: texture_variation breaks up the obvious grid-tiling pattern that
// appears when a small albedo (e.g. 1k grass) gets repeated across a
// 256-unit terrain. At 0.0 the shader does its old single-sample tile
// (cheap, but grids are visible). At 1.0 it blends a second sample
// taken with a per-cell pseudo-random UV offset, hiding the seam.
// One extra texture sample per albedo per fragment — a noticeable hit
// on very low-end Mobile GPUs, so it defaults to 0 and the user can
// dial in.
uniform float texture_variation : hint_range(0.0, 1.0) = 0.0;
// V21 ANTI-TILE PRO controls. These work together to hide tile seams:
//
//   texture_cell_size — world-space units between variation cells. Bigger
//     cells = larger natural patches before the pattern changes. Smaller
//     = more variation, but transitions become noticeable as noise.
//     Default 10 means one "patch" of texture spans ~10×10 world units.
//
//   rotation_jitter — 0..1. At 1.0, each cell rotates its UVs by a random
//     angle in [0, 2π]. Breaks up directional features (grass blades, dirt
//     streaks) so they don't all point the same way.
//
//   triplanar_blend — 0..1. At 0 the shader projects albedo straight down
//     (XZ plane) — fast, but textures stretch on steep slopes. At 1, the
//     shader blends three projections (XY, YZ, XZ) weighted by the surface
//     normal: this is the standard triplanar trick, eliminates stretching
//     and the perceived "texture slide" during sculpting. 3× the texture
//     samples per albedo so default to 0; users with the GPU budget can
//     dial in.
uniform float texture_cell_size : hint_range(1.0, 50.0) = 10.0;
uniform float rotation_jitter : hint_range(0.0, 1.0) = 0.0;
uniform float triplanar_blend : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_world_pos;
// V21: world-space normal varying for triplanar projection. Linear
// interpolation across the triangle (the rasterizer does this automatically)
// gives us a per-fragment normal we then re-normalise in fragment(). The
// raw NORMAL is mesh-local; we transform with the model matrix's upper
// 3×3 so non-uniformly-scaled terrain nodes still get a usable direction.
varying vec3 v_world_normal;

// V21: per-cell hash for the variation sampler. Standard sin-based
// hash — not cryptographic, but plenty random for visual variation.
float _mt_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// V21: rotate a UV around its cell centre by `angle` radians. Used by
// _mt_sample_var when rotation_jitter > 0 to give each cell a random
// orientation, killing the directional repetition that betrays small
// tiles.
vec2 _mt_rotate_uv_around(vec2 uv, vec2 centre, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	vec2 d = uv - centre;
	return centre + vec2(c * d.x - s * d.y, s * d.x + c * d.y);
}

// V21: sample a texture with anti-tile variation: per-cell random UV
// offset (texture_variation) and per-cell random rotation (rotation_jitter).
// Cells are texture_cell_size world units wide (after the tex_scale
// multiplication has already been applied to uv coming in).
//
// Falls through to a single texture() call when both controls are 0 so
// the cost stays close to the old shader for users who opted out.
vec3 _mt_sample_var(sampler2D s, vec2 uv) {
	if (texture_variation < 0.001 && rotation_jitter < 0.001) {
		return texture(s, uv).rgb;
	}
	// Cell index in world space. texture_cell_size is in world units;
	// we recover that by dividing uv by tex_scale (uv came in scaled).
	// The 0.0001 guard handles tex_scale=0 (would otherwise NaN the
	// whole shader).
	vec2 world_uv = uv / max(tex_scale, 0.0001);
	vec2 cell = floor(world_uv / max(texture_cell_size, 0.5));
	float h1 = _mt_hash(cell);
	float h_rot = _mt_hash(cell + vec2(17.0, 31.0));

	vec2 sample_uv = uv;
	if (rotation_jitter > 0.001) {
		// Random angle in [0, 2π], jitter-strength-attenuated. At
		// jitter=0 every cell sits at angle=0 (no rotation, identical
		// to the input). At jitter=1, the full random angle is applied.
		float angle = h_rot * 6.28318 * rotation_jitter;
		// Rotate around the cell centre (in scaled-uv space) so the
		// rotation pivot moves with the cell — otherwise the rotation
		// would have a global pivot at the origin and shift the texture
		// arbitrarily on far-from-origin terrain.
		vec2 cell_centre_uv = (cell + 0.5) * texture_cell_size * tex_scale;
		sample_uv = _mt_rotate_uv_around(sample_uv, cell_centre_uv, angle);
	}

	vec3 base = texture(s, sample_uv).rgb;
	if (texture_variation < 0.001) return base;

	// Big offset so the second sample reads totally different tile data.
	vec2 offset = vec2(h1 * 17.3, fract(h1 * 31.7) * 23.1);
	vec3 alt = texture(s, sample_uv + offset).rgb;
	float h2 = _mt_hash(floor(world_uv / max(texture_cell_size * 1.7, 0.5)));
	float blend = smoothstep(0.3, 0.7, h2) * texture_variation;
	return mix(base, alt, blend);
}

// V21: triplanar projection — sample the texture from three world-axis
// planes and blend by the surface normal's component on each axis. This
// is the standard fix for "texture stretching on cliffs" because a flat-
// projected texture rasterises infinitely along the direction of the
// normal's dominant axis. When the user sculpts a steep face into a
// previously flat patch, the same UVs that worked before suddenly span
// many world units in screen space → visible "texture slide".
//
// Cost: 3 calls to _mt_sample_var instead of 1. Use sparingly via the
// triplanar_blend uniform: 0 = pure XZ projection (cheap), 1 = full
// triplanar (clean). Sweet spot is usually 0.3–0.5 — enough to hide
// vertical-face stretching without paying full triple-sample cost on
// the 99% of the terrain that's nearly flat.
vec3 _mt_triplanar(sampler2D s, vec3 wpos) {
	vec3 n = normalize(v_world_normal);
	// pow ^4 sharpens the blend — small components don't contribute much,
	// so on a nearly-flat surface we essentially just use the XZ sample.
	vec3 w = pow(abs(n), vec3(4.0));
	w /= max(w.x + w.y + w.z, 0.0001);

	vec3 xz = _mt_sample_var(s, wpos.xz * tex_scale);
	vec3 xy = _mt_sample_var(s, wpos.xy * tex_scale);
	vec3 yz = _mt_sample_var(s, wpos.zy * tex_scale);
	return xz * w.y + yz * w.x + xy * w.z;
}

// V21: choose between single-projection and triplanar based on the
// triplanar_blend uniform. When 0 we skip the extra samples entirely,
// when > 0 we lerp between the XZ projection and full triplanar so
// the user gets a smooth dial-in.
vec3 _mt_slot_sample(sampler2D s, vec3 wpos) {
	vec3 xz = _mt_sample_var(s, wpos.xz * tex_scale);
	if (triplanar_blend < 0.001) return xz;
	vec3 tri = _mt_triplanar(s, wpos);
	return mix(xz, tri, triplanar_blend);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// mat3(MODEL_MATRIX) instead of MODEL_NORMAL_MATRIX: see the V20
	// fix in earlier shader history (Mobile renderer compile bug with
	// MODEL_NORMAL_MATRIX). For uniformly-scaled terrains this gives the
	// same result; non-uniform scale tilts the normal slightly.
	v_world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	// Normalise the splatmap so the four channel weights sum to 1.0.
	// Without this, splatmaps painted "additively" (each channel up to
	// 1.0 independently) would blow out the final colour > 1.0.
	vec4 blend = texture(splatmap, UV);
	float total_blend = blend.r + blend.g + blend.b + blend.a;
	if (total_blend > 0.0001) {
		blend /= total_blend;
	} else {
		// Empty splatmap pixel — default to slot 0 so the user sees
		// SOMETHING instead of pitch black.
		blend = vec4(1.0, 0.0, 0.0, 0.0);
	}

	// === All four maps share ONE sampling path (TKT-010) ===
	// albedo, normal, roughness AND ao all call _mt_slot_sample so a slot's
	// maps share variation / rotation jitter / triplanar and stay coherent
	// when tex_scale / texture_variation / rotation_jitter / triplanar_blend
	// change. (Previously roughness/ao sampled flat texture(uv) and desynced
	// from albedo.) Single-channel maps take .r.
	vec3 c0 = _mt_slot_sample(tex_a_0, v_world_pos);
	vec3 c1 = _mt_slot_sample(tex_a_1, v_world_pos);
	vec3 c2 = _mt_slot_sample(tex_a_2, v_world_pos);
	vec3 c3 = _mt_slot_sample(tex_a_3, v_world_pos);
	ALBEDO = c0 * blend.r + c1 * blend.g + c2 * blend.b + c3 * blend.a;

	// Normal: linear tangent-space blend (not strict RNM, but fast and fine
	// for terrain). Same path as albedo so lighting and surface stay in sync
	// on slopes.
	vec3 n0 = _mt_slot_sample(tex_n_0, v_world_pos);
	vec3 n1 = _mt_slot_sample(tex_n_1, v_world_pos);
	vec3 n2 = _mt_slot_sample(tex_n_2, v_world_pos);
	vec3 n3 = _mt_slot_sample(tex_n_3, v_world_pos);
	NORMAL_MAP = n0 * blend.r + n1 * blend.g + n2 * blend.b + n3 * blend.a;
	NORMAL_MAP_DEPTH = normal_strength;

	// Roughness: scalar blend, multiplied by global multiplier.
	float r0 = _mt_slot_sample(tex_r_0, v_world_pos).r;
	float r1 = _mt_slot_sample(tex_r_1, v_world_pos).r;
	float r2 = _mt_slot_sample(tex_r_2, v_world_pos).r;
	float r3 = _mt_slot_sample(tex_r_3, v_world_pos).r;
	ROUGHNESS = clamp((r0 * blend.r + r1 * blend.g + r2 * blend.b + r3 * blend.a) * roughness_multiplier, 0.0, 1.0);

	// AO: scalar blend, lerped against 1.0 by ao_strength.
	float ao0 = _mt_slot_sample(tex_ao_0, v_world_pos).r;
	float ao1 = _mt_slot_sample(tex_ao_1, v_world_pos).r;
	float ao2 = _mt_slot_sample(tex_ao_2, v_world_pos).r;
	float ao3 = _mt_slot_sample(tex_ao_3, v_world_pos).r;
	float ao = ao0 * blend.r + ao1 * blend.g + ao2 * blend.b + ao3 * blend.a;
	AO = mix(1.0, ao, ao_strength);
	AO_LIGHT_AFFECT = 1.0;
}
"""


func _setup_default_shader():
	if terrain_material != null and not (terrain_material is ShaderMaterial):
		return
	if terrain_material == null:
		terrain_material = ShaderMaterial.new()
	var smat = terrain_material as ShaderMaterial
	# V21: detect a stale shader (saved with older addon version) by
	# checking for the existence of one of the new uniforms. If the
	# parameter list doesn't contain `triplanar_blend`, the shader is
	# from V20 or earlier — overwrite its code so the user gets the new
	# features. We don't bother trying to detect a deliberate user
	# customisation; the @export var `terrain_material` lets advanced
	# users assign their own ShaderMaterial without going through this
	# function (the early-return above protects fully custom materials,
	# and the `terrain_material == null` branch protects the auto-built
	# default path).
	var needs_refresh: bool = smat.shader == null
	if not needs_refresh and smat.shader != null:
		var param_list = RenderingServer.get_shader_parameter_list(smat.shader.get_rid())
		var has_new_uniform: bool = false
		for p in param_list:
			if p.name == "triplanar_blend":
				has_new_uniform = true
				break
		needs_refresh = not has_new_uniform
	if needs_refresh:
		# V22: prefer the standalone .gdshader file. Falls back to the
		# inline string if the resource isn't reachable (e.g. addon dropped
		# in before project import had time to register the new file).
		const SHADER_PATH := "res://addons/mobile_terrain/shaders/terrain.gdshader"
		var loaded := load(SHADER_PATH)
		if loaded is Shader:
			smat.shader = loaded
		else:
			var shader = Shader.new()
			shader.code = TERRAIN_SHADER
			smat.shader = shader
	update_shader_textures()
	# V21: removed `slope_rock_factor` shader parameter set — the new
	# shader no longer uses it. The @export property survives for
	# scene-compat (old scenes deserialize it without error) but the
	# value is ignored.


func update_shader_textures():
	if not (terrain_material is ShaderMaterial):
		return
	var smat = terrain_material as ShaderMaterial
	smat.set_shader_parameter("splatmap", splatmap_texture_local)
	smat.set_shader_parameter("tex_scale", texture_scale)
	smat.set_shader_parameter("normal_strength", normal_strength)
	smat.set_shader_parameter("roughness_multiplier", roughness_multiplier)
	smat.set_shader_parameter("ao_strength", ao_strength)
	smat.set_shader_parameter("texture_variation", texture_variation)
	smat.set_shader_parameter("texture_cell_size", texture_cell_size)
	smat.set_shader_parameter("rotation_jitter", rotation_jitter)
	smat.set_shader_parameter("triplanar_blend", triplanar_blend)
	# V21: Bind all four map types per slot. Empty slots get type-correct
	# default textures (transparent for albedo, flat normal for normals,
	# white for roughness/AO) instead of `null`, because Godot 4 silently
	# ignores set_shader_parameter() calls when the value type doesn't
	# match the uniform type — `null` is not a Texture2D, so a null call
	# leaves the previous (potentially stale) binding in place. Binding a
	# concrete blank texture both clears stale state AND respects the
	# shader's hint_default_* fallback semantics on backends where those
	# work.
	for i in range(4):
		var ta: Texture2D = terrain_textures[i] if i < terrain_textures.size() else null
		var tn: Texture2D = terrain_normal[i] if i < terrain_normal.size() else null
		var tr: Texture2D = terrain_roughness[i] if i < terrain_roughness.size() else null
		var tao: Texture2D = terrain_ao[i] if i < terrain_ao.size() else null
		smat.set_shader_parameter(
			"tex_a_%d" % i, ta if ta != null else _get_or_create_blank_texture("albedo")
		)
		smat.set_shader_parameter(
			"tex_n_%d" % i, tn if tn != null else _get_or_create_blank_texture("normal")
		)
		smat.set_shader_parameter(
			"tex_r_%d" % i, tr if tr != null else _get_or_create_blank_texture("white")
		)
		smat.set_shader_parameter(
			"tex_ao_%d" % i, tao if tao != null else _get_or_create_blank_texture("white")
		)


# V21: Per-type blank textures. Each map type needs a different default
# colour for the "empty slot" placeholder:
#   - albedo  → (0,0,0,0): transparent black, no colour contribution
#   - normal  → (0.5,0.5,1,1): flat tangent-space normal (Z-up = no bump)
#   - white   → (1,1,1,1): full roughness, full AO (no occlusion)
# Each is cached once per type, lazily created.
var _blank_textures: Dictionary = {}


func _get_or_create_blank_texture(map_type: String) -> ImageTexture:
	if map_type in _blank_textures:
		return _blank_textures[map_type]
	var img := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	var col := Color(0, 0, 0, 0)
	match map_type:
		"albedo":
			col = Color(0, 0, 0, 0)
		"normal":
			# Tangent-space "flat" normal: X=0, Y=0, Z=1 → encoded (0.5, 0.5, 1.0)
			col = Color(0.5, 0.5, 1.0, 1.0)
		"white":
			col = Color(1, 1, 1, 1)
		_:
			push_warning("[MobileTerrain3D] Unknown blank texture type: " + map_type)
	img.set_pixel(0, 0, col)
	var tex := ImageTexture.create_from_image(img)
	_blank_textures[map_type] = tex
	return tex


func _set_slope_rock(val: float):
	# V21: kept for backward compat with V19/V20 saved scenes. The auto-rock-by-slope
	# feature was removed in V21 in favour of user-painted rock via the splatmap.
	slope_rock_factor = val
	# No shader uniform to push; the shader doesn't reference this any more.


func _set_normal_strength(val: float):
	normal_strength = val
	if terrain_material is ShaderMaterial:
		(terrain_material as ShaderMaterial).set_shader_parameter("normal_strength", val)


func _set_roughness_multiplier(val: float):
	roughness_multiplier = val
	if terrain_material is ShaderMaterial:
		(terrain_material as ShaderMaterial).set_shader_parameter("roughness_multiplier", val)


func _set_ao_strength(val: float):
	ao_strength = val
	if terrain_material is ShaderMaterial:
		(terrain_material as ShaderMaterial).set_shader_parameter("ao_strength", val)


func _set_texture_variation(val: float):
	texture_variation = val
	if terrain_material is ShaderMaterial:
		(terrain_material as ShaderMaterial).set_shader_parameter("texture_variation", val)


func _set_texture_cell_size(val: float):
	texture_cell_size = val
	if terrain_material is ShaderMaterial:
		(terrain_material as ShaderMaterial).set_shader_parameter("texture_cell_size", val)


func _set_rotation_jitter(val: float):
	rotation_jitter = val
	if terrain_material is ShaderMaterial:
		(terrain_material as ShaderMaterial).set_shader_parameter("rotation_jitter", val)


func _set_triplanar_blend(val: float):
	triplanar_blend = val
	if terrain_material is ShaderMaterial:
		(terrain_material as ShaderMaterial).set_shader_parameter("triplanar_blend", val)


# V20 FIX (#12): Snap a candidate map_size to the nearest multiple of
# chunk_size, with a user-visible warning. Auto-rounding instead of
# rejecting keeps the inspector usable: when the user types a custom
# value that doesn't divide evenly, we converge to a workable state
# rather than silently leaving cells outside the chunk grid (which
# would make those cells invisible and un-paintable forever).
#
# Returns the rounded value. If chunk_size is invalid (≤0) we punt and
# return the input unchanged — _set_chunk_size guards that case before
# calling this.
func _align_to_chunks(val: int) -> int:
	# V21: clamp to at least chunk_size — a map_size below chunk_size
	# (or zero) produces a terrain with no cells, which renders nothing
	# and silently breaks brush coordinates. Picking chunk_size as the
	# floor preserves the divisibility invariant the rest of the code
	# assumes (every chunk has its full row of vertices).
	if val < chunk_size:
		push_warning(
			(
				"MobileTerrain3D: map_size %d below chunk_size %d; clamped to %d."
				% [val, chunk_size, chunk_size]
			)
		)
		val = chunk_size
	if chunk_size < 1 or val % chunk_size == 0:
		return val
	var rounded = max(chunk_size, roundi(float(val) / chunk_size) * chunk_size)
	push_warning(
		(
			"MobileTerrain3D: map_size %d is not a multiple of chunk_size %d; rounded to %d so the chunk grid tiles cleanly."
			% [val, chunk_size, rounded]
		)
	)
	return rounded


func _set_map_size(val: int):
	# V22 FIX (audit-chunk-resize-during-stroke + audit-chunk-map-size-mid-rebuild):
	# defer destructive resize while a stroke is active or initialize_terrain
	# is mid-loop. end_stroke / initialize_terrain replay the pending value
	# once it's safe.
	if _active_stroke or _rebuilding_terrain:
		_deferred_map_size = val
		return
	# V20 FIX (#12): see _align_to_chunks. Without this, a non-divisible
	# map_size would leave the modulo cells (e.g. cells 96-99 with
	# map_size=100, chunk_size=32) outside any chunk — un-rendered and
	# un-paintable, no error message, no UI hint.
	#
	# V21 PERFORMANCE: auto-bump chunk_size for very large maps. At
	# map_size=1254 with default chunk_size=32, you end up with ~1500
	# tiny chunks — each adding a draw call and a place to mark dirty.
	# A larger chunk_size (64 or 128) cuts that to a few hundred chunks
	# without hurting sculpt responsiveness (the brush still only marks
	# its footprint dirty). We only auto-adjust when the current
	# chunk_size would produce > 1024 chunks total; otherwise the user's
	# choice stands. Picks the smallest valid divisor of val that brings
	# the chunk count below the threshold, so the divisibility invariant
	# is preserved without further auto-rounding.
	const MAX_CHUNK_COUNT := 1024  # 32×32 grid worst case
	if val > 0 and chunk_size > 0:
		var implied_count: int = int(ceil(float(val) / float(chunk_size)))
		implied_count = implied_count * implied_count
		if implied_count > MAX_CHUNK_COUNT:
			# Candidate chunk sizes in ascending order. Cover up to ~16k
			# map_size at 32×32 chunk grid before we run out of divisors.
			# V21 EXTENSION: original [64, 128, 256] topped out at map_size
			# ~8200. Anything bigger silently fell through and built tens
			# of thousands of chunks → multi-minute freeze or OOM crash.
			# Adding 512 covers map_size up to 16384, and 1024 to 32768.
			var new_chunk_size: int = chunk_size
			for cand in [64, 128, 256, 512, 1024]:
				var new_count: int = int(ceil(float(val) / float(cand)))
				new_count = new_count * new_count
				if new_count <= MAX_CHUNK_COUNT:
					push_warning(
						(
							"MobileTerrain3D: map_size %d × chunk_size %d would produce %d chunks (too many). Auto-bumped chunk_size to %d."
							% [val, chunk_size, implied_count, cand]
						)
					)
					new_chunk_size = cand
					break
			if new_chunk_size == chunk_size:
				# No candidate worked — map is extreme. Cap and warn.
				push_warning(
					(
						"MobileTerrain3D: map_size %d is extreme (>32K cells per side). Performance will be severely degraded. Consider splitting into multiple terrain nodes."
						% val
					)
				)
				new_chunk_size = 1024
			# V21 CRITICAL: bypass the chunk_size setter via flag. Calling
			# the setter here cascades into another initialize_terrain
			# (which we're about to do anyway), AND its own >map_size
			# clamp would reject our chosen value when map_size is
			# currently smaller (the user is GROWING the map). We just
			# want to record the new chunk_size; the _set_map_size code
			# below handles the rebuild in one pass.
			_suppress_chunk_size_setter = true
			chunk_size = new_chunk_size
			_suppress_chunk_size_setter = false
	map_size = _align_to_chunks(val)
	if Engine.is_editor_hint():
		_initialize_splatmap()
		# V20 FIX: rebind shader uniforms. The new _initialize_splatmap
		# replaces splatmap_texture_local with a fresh ImageTexture
		# whenever it had to resize or rebuild — without this rebind, the
		# shader's "splatmap" uniform would still hold the old (now
		# orphaned) handle and the painted texture wouldn't show.
		update_shader_textures()
		initialize_terrain()


# V21: bypass flag for _set_chunk_size. Set true around internal
# writes that need to update the value WITHOUT triggering the cascade
# (initialize_terrain + the >map_size clamp). Used by _set_map_size
# during auto-bump — that path is about to do its own initialize_terrain.
var _suppress_chunk_size_setter: bool = false


func _set_chunk_size(val: int):
	# V22 FIX (audit-chunk-resize-during-stroke + audit-chunk-map-size-mid-rebuild):
	# defer the destructive setter (which would cascade into
	# initialize_terrain) until the active stroke / current rebuild ends.
	# Internal writes use _suppress_chunk_size_setter which bypasses this.
	if not _suppress_chunk_size_setter and (_active_stroke or _rebuilding_terrain):
		_deferred_chunk_size = val
		return
	if _suppress_chunk_size_setter:
		# Just record the new value; the caller is responsible for any
		# downstream rebuild. Clamps below still apply so we never
		# silently store an invalid value.
		if val < 1:
			val = 1
		chunk_size = val
		return
	# V20 FIX (#12): clamp to at least 1 — chunk_size==0 would divide-by-
	# zero in `map_size / chunk_size` and crash the editor hot path.
	if val < 1:
		push_warning("MobileTerrain3D: chunk_size %d invalid; clamped to 1." % val)
		val = 1
	# V21: also clamp the upper bound. Without this, a chunk_size larger
	# than map_size would cascade through the divisibility branch below,
	# rounding map_size UP to match (e.g. chunk=512 against map=256 would
	# auto-grow the terrain to 512×512). That's a destructive surprise:
	# the user changed one number, the terrain doubled and got re-zeroed.
	# Clamping down here keeps the change intent-preserving: chunks just
	# get capped at map_size, no implicit map expansion.
	if val > map_size:
		push_warning(
			(
				"MobileTerrain3D: chunk_size %d > map_size %d; clamped to %d."
				% [val, map_size, map_size]
			)
		)
		val = map_size
	chunk_size = val
	if Engine.is_editor_hint():
		# V20 FIX (#12): if the new chunk_size no longer divides map_size,
		# round map_size to restore the invariant. Setting map_size here
		# triggers _set_map_size, which runs the full re-init cascade —
		# don't duplicate that work in the else branch.
		if map_size % chunk_size != 0:
			var rounded = max(chunk_size, roundi(float(map_size) / chunk_size) * chunk_size)
			push_warning(
				(
					"MobileTerrain3D: chunk_size %d does not divide map_size %d; rounding map_size to %d."
					% [chunk_size, map_size, rounded]
				)
			)
			map_size = rounded  # cascades through _set_map_size → initialize_terrain
		else:
			initialize_terrain()


func _set_material(val: Material):
	terrain_material = val
	# V21: defensive is_instance_valid. Chunks can be queue_free'd by
	# initialize_terrain between when the dict was last touched and now.
	# Setting material_override on a freed node crashes.
	for chunk in chunks.values():
		if is_instance_valid(chunk):
			chunk.material_override = terrain_material
	# V21: rebind shader uniforms onto the new material. Without this,
	# changing terrain_material from the Inspector left the new
	# ShaderMaterial with NO splatmap binding, NO PBR texture bindings,
	# and default tex_scale/normal_strength/etc. — the terrain rendered
	# as solid blank. The user had to manually trigger a refresh by
	# toggling some other property. Calling update_shader_textures
	# directly closes that gap.
	# Guarded by the is-ShaderMaterial check inside update_shader_textures
	# so assigning a StandardMaterial3D or other type is a safe no-op.
	update_shader_textures()


func _set_tex_scale(val: float):
	texture_scale = val
	update_shader_textures()


func bake_collision():
	# V21: chunks aren't owned by the edited scene normally (they're
	# regenerated from height_data on load — saving them doubles the
	# .tscn size). But baked collision lives as StaticBody3D children
	# of each chunk, and giving the child an `owner` without the parent
	# also being owned breaks Godot's serialisation (the child's path
	# reference points to a non-persisted node). So when the user
	# explicitly bakes collision, we promote chunks to scene-owned for
	# the duration — that way both the chunk mesh AND its collision
	# survive the save. Side effect: chunks appear in the Scene dock
	# AFTER baking. The user expects this since they asked for the
	# collision to be persistent.
	var scene_root: Node = null
	if get_tree() and get_tree().edited_scene_root:
		scene_root = get_tree().edited_scene_root
	for chunk in chunks.values():
		for child in chunk.get_children():
			child.queue_free()
		chunk.create_trimesh_collision()
		if scene_root != null:
			chunk.owner = scene_root  # V21: promote chunk so collision persists
		for child in chunk.get_children():
			if child is StaticBody3D:
				if scene_root != null:
					child.owner = scene_root
					for shape in child.get_children():
						shape.owner = scene_root


func _import_exr(val: bool):
	if not val or not import_texture:
		return
	# TKT-003 Phase A.2: byte-bulk image-to-heights conversion extracted
	# into systems/heightmap_io.gd. This function keeps responsibility
	# for the side effects (writing height_data, triggering
	# initialize_terrain, emitting the large-heightmap nudge) while the
	# pure conversion lives in HeightmapIO.
	var heights: PackedFloat32Array = HeightmapIO.convert_texture_to_heights(
		import_texture, map_size, import_max_height
	)
	if heights.is_empty():
		# HeightmapIO returns empty on null/invalid input or buffer mismatch.
		# Silently bail — the caller already validated import_texture.
		return
	height_data = heights
	var total: int = map_size * map_size
	initialize_terrain()
	# Nudge the user toward external storage for big imports. We don't
	# auto-externalize because that would write a .res file as a side
	# effect of an import — surprising, and it'd fail silently if the
	# scene isn't saved yet.
	if total >= 512 * 512 and external_data_path == "":
		TerrainDiagnostics.warn(
			TerrainDiagnostics.W_LARGE_HEIGHTMAP, [total, total * 4.0 / 1048576.0]
		)
	# V21: auto-reset the checkbox so the next import requires another
	# explicit click. Without this, the property stayed `true` in the
	# Inspector, but a second click (true → true) didn't fire the setter
	# at all — leaving the user wondering why nothing happened. Now the
	# checkbox always returns to false after a successful import.
	# call_deferred avoids recursive setter calls if we wrote click_to_import
	# directly inside this function.
	call_deferred("_reset_click_to_import")


func _reset_click_to_import() -> void:
	click_to_import = false
	notify_property_list_changed()


# V21 EXTERNAL STORAGE: helpers for opting into / out of external
# .res storage for height_data and splatmap. The pattern matches
# click_to_import: an inspector boolean fires the action then auto-
# resets so it can be triggered again.

# The custom Resource class that wraps the heavy data. Defined inline
# at the bottom of this file as `class MobileTerrainData extends Resource`.
# Using a single Resource (not two) means one external file per terrain
# rather than two, and one ResourceSaver call per save.


# TKT-011: write this terrain's heavy data (height + splatmap) to its
# companion .res under res://terrain_data/. Scene-INDEPENDENT — works even on
# an unsaved/untitled scene (the old code bailed if scene_file_path was
# empty, which is why "it errored every time"). Creates the directory on
# demand (ResourceSaver does NOT) and binds external_data_path on first save.
# Returns an Error code (OK on success). Object data is added in PR-2.
func save_terrain_data() -> int:
	# Called only from EditorPlugin._save_external_data (editor-time). Kept
	# guard-free so the save core (dir + data + ResourceSaver) is headless-
	# testable; runtime never calls this path.
	# Ensure the data directory exists. make_dir_recursive_absolute returns OK
	# or ERR_ALREADY_EXISTS — both are fine.
	var dir: String = TerrainConstants.TERRAIN_DATA_DIR
	var derr := DirAccess.make_dir_recursive_absolute(dir)
	if derr != OK and derr != ERR_ALREADY_EXISTS:
		TerrainDiagnostics.error(TerrainDiagnostics.E_SAVE_RESOURCE_FAILED, [dir, derr])
		return derr
	# Bind a deterministic, collision-free path on first save (or if the
	# stored one is somehow unsafe). Scene-independent.
	if external_data_path == "" or not _is_safe_external_path(external_data_path):
		_suppress_external_path_setter = true
		external_data_path = _make_data_path(dir)
		_suppress_external_path_setter = false

	# Build the resource. We deliberately COPY the byte arrays via duplicate()
	# rather than passing the live references; otherwise the resource and
	# the inline @export would share the same backing data and any future
	# inline edits would leak across.
	var data := MobileTerrainData.new()
	data.height_data = height_data.duplicate()
	data.map_size = map_size
	# Splatmap: extract the bytes from the GPU texture.
	# V21 CRITICAL FIX: Image.get_data() returns a shared reference to the
	# image's internal byte buffer in some Godot 4 builds. If the splatmap
	# is mutated later (during a paint stroke), the bytes we just handed
	# to MobileTerrainData would silently change too — corrupting the
	# saved .res if ResourceSaver hasn't flushed yet. duplicate() forces
	# an independent copy.
	if splatmap_texture_local != null:
		var img := splatmap_texture_local.get_image()
		if img != null:
			data.splatmap_bytes = img.get_data().duplicate()
			data.splatmap_size = img.get_width()

	# TKT-011 PR-2: persist placed objects (foliage) in the .res too, so they
	# survive save/load instead of relying on MultiMeshInstance3D nodes baked
	# into the .tscn.
	data.object_slots = _collect_object_slots()

	var err := ResourceSaver.save(data, external_data_path)
	if err != OK:
		TerrainDiagnostics.error(
			TerrainDiagnostics.E_SAVE_RESOURCE_FAILED, [external_data_path, err]
		)
		return err
	return OK


# Build a deterministic, collision-free .res path for this terrain under
# `dir`, sanitising the node name for filesystem safety ("My Terrain @1" →
# "terrain_My_Terrain__1.res").
func _make_data_path(dir: String) -> String:
	var name_str: String = String(name)
	var safe_name: String = ""
	for i in range(name_str.length()):
		var ch: String = name_str[i]
		var ok: bool = (
			(ch >= "a" and ch <= "z")
			or (ch >= "A" and ch <= "Z")
			or (ch >= "0" and ch <= "9")
			or ch == "_"
		)
		safe_name += ch if ok else "_"
	if safe_name == "":
		safe_name = "terrain"
	var base: String = dir.path_join("terrain_" + safe_name)
	var candidate: String = base + ".res"
	var collision: int = 0
	while ResourceLoader.exists(candidate):
		collision += 1
		if collision > 256:
			break
		candidate = base + "_" + str(collision) + ".res"
	return candidate


func _load_external_data_if_set() -> void:
	if external_data_path == "":
		return
	# V23 SECURITY (TKT-002 C1): scope-validate path before load().
	# load() executes any GDScript embedded in the .res before our `is`
	# type-check fires, so an unscoped path can be a remote-code-execution
	# vector. We accept only res:// (project-bundled fixtures) or user://
	# (runtime-managed save data) paths and reject anything else, including
	# absolute filesystem paths and `..` traversal.
	if not _is_safe_external_path(external_data_path):
		push_warning(
			(
				"MobileTerrain3D: refusing to load '%s' — external_data_path must live under res:// or user:// (no path traversal). See TKT-002 C1."
				% external_data_path
			)
		)
		return
	if not ResourceLoader.exists(external_data_path):
		push_warning(
			(
				"MobileTerrain3D: external_data_path '%s' not found; using inline data."
				% external_data_path
			)
		)
		return
	var res = load(external_data_path)
	if not (res is MobileTerrainData):
		push_warning(
			"MobileTerrain3D: '%s' is not a MobileTerrainData resource." % external_data_path
		)
		return
	var data: MobileTerrainData = res
	# V23 VALIDATION (TKT-002 gap M14): catch corrupted/truncated .res
	# files before we trust their height_data length downstream.
	if data.map_size <= 0 or data.height_data.size() != data.map_size * data.map_size:
		push_warning(
			(
				"MobileTerrain3D: '%s' fails schema check (map_size=%d, height_data.size()=%d). Refusing to load."
				% [external_data_path, data.map_size, data.height_data.size()]
			)
		)
		return
	# V21 CRITICAL ORDER FIX:
	# Populate height_data BEFORE updating map_size. The _set_map_size
	# setter cascades into initialize_terrain, which checks
	# height_data.size() vs map_size² and runs a migration if they
	# disagree — that migration would zero-fill height_data, destroying
	# the data we just loaded. By assigning height_data first (with the
	# external resource's data, sized to match data.map_size), the
	# subsequent map_size change sees a consistent state.
	height_data = data.height_data.duplicate()
	# Validate the splatmap blob like height_data above — a truncated or corrupt
	# .res must be rejected, not handed to create_from_data (which errors or
	# yields garbage). RGBA8 = 4 bytes per cell.
	var expected_splat: int = data.splatmap_size * data.splatmap_size * 4
	if data.splatmap_size > 0 and data.splatmap_bytes.size() == expected_splat:
		var img := Image.create_from_data(
			data.splatmap_size, data.splatmap_size, false, Image.FORMAT_RGBA8, data.splatmap_bytes
		)
		splatmap_texture_local = ImageTexture.create_from_image(img)
		splatmap_data = data.splatmap_bytes.duplicate()
	elif data.splatmap_bytes.size() > 0:
		push_warning(
			(
				"MobileTerrain3D: '%s' splatmap blob is %d bytes, expected %d; skipping splatmap."
				% [external_data_path, data.splatmap_bytes.size(), expected_splat]
			)
		)
	# Defensive size check: if the user changed map_size in the inspector
	# but the .res holds different dimensions, trust the .res (since it's
	# the canonical store) and update map_size to match.
	if data.map_size != map_size and data.map_size > 0:
		map_size = data.map_size  # cascades through _set_map_size

	# TKT-011 PR-2: rebuild placed objects from the .res. Old .res files
	# without an object_slots field load it as an empty Array → no-op.
	_restore_object_slots(data.object_slots)


# V23 SECURITY (TKT-002 C1): whitelist external_data_path to project-
# bundled (res://) or user-owned (user://) locations. Reject absolute
# filesystem paths, parent-directory traversal, and any other prefix.
# The `is_absolute_path()` check covers Windows drives, Unix absolute
# paths and Godot-localised resource paths uniformly.
static func _is_safe_external_path(p: String) -> bool:
	if p == "":
		return false
	if "/../" in p or p.ends_with("/..") or p.begins_with("../"):
		return false
	if not (p.begins_with("res://") or p.begins_with("user://")):
		return false
	return true


func get_height(x: int, z: int) -> float:
	x = clampi(x, 0, map_size - 1)
	z = clampi(z, 0, map_size - 1)
	return height_data[z * map_size + x]


func _process(_delta: float):
	# V21 CRITICAL FIX: removed the Engine.is_editor_hint() gate.
	# Originally only editor-hint flushed the dirty queue, so at runtime
	# a large map (>256 chunks) would be created via _create_chunk(
	# build_now=false) and the chunks would stay empty FOREVER — terrain
	# renders blank in the running game. The throttle is just as relevant
	# at runtime (we don't want a 1500-chunk freeze on level load), so
	# the queue should drain regardless of editor mode.
	if dirty_chunks.size() > 0:
		# V21 PERFORMANCE: per-frame chunk meshing budget.
		#
		# Previously hard-coded to 4 chunks per frame, tuned for interactive
		# sculpting where the dirty set is small (1-9 chunks around the
		# brush footprint). For BULK rebuilds (EXR import, map resize) the
		# dirty set can be hundreds of chunks and 4/frame means a visible
		# 5-10 second progressive wipe.
		#
		# Adaptive: more budget when there's lots of work waiting AND the
		# user isn't actively sculpting (small dirty sets). The threshold
		# (>16) catches bulk-rebuild scenarios without hurting interactive
		# response. The cap (64) keeps any single frame under ~10ms even
		# on the slowest Mobile GPUs we target.
		# V22 FIX (audit-chunk-budget): linear interpolation eliminates
		# the old "stall zone" between 17..32 dirty chunks where budget
		# stayed at 4 despite a growing queue. Now budget scales with
		# queue depth from MIN to MAX as defined in TerrainConstants.
		var budget: int = mini(
			TerrainConstants.MAX_CHUNK_PER_FRAME,
			max(TerrainConstants.MIN_CHUNK_PER_FRAME, dirty_chunks.size() / 4)
		)
		var process_count = 0
		var keys_to_remove = []
		# TKT-004 H4: time-bound the loop in addition to the count budget.
		# The count cap assumes a roughly fixed per-chunk cost, but meshing
		# a 256-wide chunk is far slower than a 32-wide one, so on large
		# maps `budget` chunks can overrun the frame. Stop once we've spent
		# ~8ms this frame; the remaining dirty chunks drain next frame.
		var start_usec := Time.get_ticks_usec()
		for cpos in dirty_chunks.keys():
			update_chunk_mesh(cpos.x, cpos.y)
			keys_to_remove.append(cpos)
			process_count += 1
			if process_count >= budget:
				break
			if Time.get_ticks_usec() - start_usec > TerrainConstants.MAX_CHUNK_REBUILD_USEC:
				break
		for k in keys_to_remove:
			dirty_chunks.erase(k)


func initialize_terrain():
	# V22 FIX (audit-chunk-map-size-mid-rebuild): re-entrancy guard. If a
	# setter cascades back into us during chunk creation, the second call
	# would clear the half-built `chunks` dict and corrupt the active
	# loop. Treat the re-entry as "queued"; the outer call will replay
	# the resize via _deferred_map_size on exit.
	if _rebuilding_terrain:
		return
	_rebuilding_terrain = true
	# V22: linear adaptive budget (audit-chunk-budget). Old formula had a
	# [17..32] stall zone where budget stayed at 4 despite a growing queue.
	# Drained here in initialize_terrain via the _process loop; see below.
	var expected_size = map_size * map_size
	if height_data.size() != expected_size:
		# V20 FIX (notice #1): preserve existing terrain data through
		# map_size changes instead of nuking it.
		#
		# The old code unconditionally resized and zero-filled whenever
		# height_data.size() didn't match map_size². That was fine for
		# freshly-created nodes (height_data is empty, gets allocated)
		# but it silently destroyed user work in two real scenarios:
		#
		#  1) The V20 chunk-divisibility auto-round (#12). A V19 scene
		#     saved with map_size=100 / chunk_size=32 opens in V20, the
		#     setter rounds 100→96, this branch fires, and the user's
		#     entire sculpted heightmap is wiped without warning.
		#  2) Manual map_size changes from the inspector (256→128, etc.).
		#     Users would lose all height data on every resize attempt.
		#
		# Fix: if the existing data is a valid square layout (size = N²
		# for some integer N), do a cell-by-cell migration that
		# preserves the (0,0)-anchored top-left corner of overlap.
		# Growing pads with 0.0; shrinking discards the cells outside
		# the new bounds. Junk-sized data (non-square) still falls back
		# to the old nuke-and-zero behavior — there's no meaningful
		# layout to migrate from.
		var old_size = int(sqrt(height_data.size()))
		if old_size > 0 and old_size * old_size == height_data.size():
			push_warning(
				(
					"MobileTerrain3D: migrating height_data from %dx%d to %dx%d. Cells inside the overlap region are preserved; the rest are zeroed."
					% [old_size, old_size, map_size, map_size]
				)
			)
			var new_data = PackedFloat32Array()
			new_data.resize(expected_size)  # zeroed by default
			var copy_size = min(old_size, map_size)
			for z in range(copy_size):
				var src_row = z * old_size
				var dst_row = z * map_size
				for x in range(copy_size):
					new_data[dst_row + x] = height_data[src_row + x]
			height_data = new_data
		else:
			height_data.resize(expected_size)
			height_data.fill(0.0)
	# V21: collect-then-free pattern, plus immediate free (not queue_free).
	#
	# queue_free defers cleanup to the next frame, but we're about to add
	# NEW chunks with names like "Chunk_0_0" in this same frame. If the
	# old chunks still exist in the tree when add_child runs, Godot
	# renames the new ones to "Chunk_0_0_2" → ImmediateMesh updates miss
	# them, and the user sees ghost chunks until the next refresh.
	#
	# Using free() (immediate) sidesteps the rename. We also collect
	# refs into a list first so we don't mutate the children array while
	# iterating it.
	var chunks_to_free: Array = []
	for child in get_children():
		if child is MeshInstance3D and child.name.begins_with("Chunk_"):
			chunks_to_free.append(child)
	for c in chunks_to_free:
		c.free()
	chunks.clear()
	dirty_chunks.clear()
	var num_chunks = map_size / chunk_size
	# V21 PERFORMANCE: defer mesh generation when there are a lot of chunks.
	#
	# 1254×1254 map with chunk_size=32 = ~1500 chunks. The old code built
	# every chunk's full mesh SYNCHRONOUSLY here — each chunk involves a
	# ~1000-vertex GDScript loop with 4 get_height neighbour reads per
	# vertex. On mobile that's a 2-5 second freeze when changing map_size
	# or right after EXR import.
	#
	# New behaviour: always create empty MeshInstance3D nodes here (cheap,
	# tens of milliseconds total), then mark them dirty so _process()
	# rebuilds them at the rate it already throttles to (4 chunks/frame).
	# The terrain will pop into existence over the next ~6 seconds at 60fps
	# for a 1500-chunk map, but the editor stays interactive throughout.
	#
	# For small maps (<= 64 chunks, e.g. the 256/32=8×8=64 default), we
	# still build synchronously because the deferred path has visible
	# latency that users notice on common map sizes. Threshold tuned by
	# eye: 256 chunks (16×16) is the largest map that builds in ~1 frame
	# on mid-tier mobile.
	# V22 Phase 4: use centralised constant. Old local const removed.
	var total_chunks: int = num_chunks * num_chunks
	var build_sync: bool = total_chunks <= TerrainConstants.SYNC_BUILD_CHUNK_LIMIT
	for cz in range(num_chunks):
		for cx in range(num_chunks):
			_create_chunk(cx, cz, build_sync)
	# V22 FIX (Phase 4 regression audit #3): keep _rebuilding_terrain true
	# during the deferred replay so a setter cascading inside the pending
	# map_size / chunk_size assignment doesn't enter a second concurrent
	# initialize_terrain. Cleared only after both replays complete.
	if _deferred_map_size != 0 and _deferred_map_size != map_size:
		var pending: int = _deferred_map_size
		_deferred_map_size = 0
		# Setter sees _rebuilding_terrain==true, defers itself; we replay
		# manually with the guard down.
		_rebuilding_terrain = false
		map_size = pending
		_rebuilding_terrain = true
	if _deferred_chunk_size != 0 and _deferred_chunk_size != chunk_size:
		var pending: int = _deferred_chunk_size
		_deferred_chunk_size = 0
		_rebuilding_terrain = false
		chunk_size = pending
		_rebuilding_terrain = true
	_rebuilding_terrain = false


func _create_chunk(cx: int, cz: int, build_now: bool = true):
	var chunk = MeshInstance3D.new()
	chunk.name = "Chunk_%d_%d" % [cx, cz]
	if terrain_material:
		chunk.material_override = terrain_material
	add_child(chunk)
	# V21 SCENE BLOAT FIX: don't set chunk.owner. Chunks are deterministically
	# rebuildable from height_data + chunk_size + map_size in initialize_terrain,
	# so persisting their meshes to the .tscn file doubles the on-disk size
	# (heightmap stored once in `height_data`, again in 64 ArrayMeshes).
	# Without owner, the chunk lives in the scene tree at runtime but is
	# omitted from the saved .tscn. On scene reload, _ready → initialize_terrain
	# regenerates them. Side effect: chunks no longer appear in the editor's
	# Scene dock, which is what we want anyway (they're an implementation
	# detail, not user-editable nodes).
	chunks[Vector2i(cx, cz)] = chunk
	if build_now:
		update_chunk_mesh(cx, cz)
	else:
		# V21: defer to _process. Caller (initialize_terrain for large
		# maps) only wants the empty MeshInstance3D placeholders so the
		# tree structure is in place; meshing happens on subsequent frames
		# at the existing 4-chunk-per-frame throttle.
		dirty_chunks[Vector2i(cx, cz)] = true


func update_chunk_mesh(cx: int, cz: int):
	var chunk = chunks.get(Vector2i(cx, cz))
	if not chunk:
		return
	# TKT-003 Phase A.4: mesh generation extracted into systems/chunk_renderer.gd
	# (pure, headless-testable). This function keeps responsibility for the
	# chunk dictionary lookup, MeshInstance assignment and positioning; the
	# vertex/normal/uv/tangent/index build lives in ChunkRenderer.
	var amesh: ArrayMesh = ChunkRenderer.build_chunk_mesh(height_data, map_size, chunk_size, cx, cz)
	if amesh == null:
		return
	var start_x = cx * chunk_size
	var start_z = cz * chunk_size
	chunk.mesh = amesh
	chunk.position = Vector3(start_x, 0, start_z)


# V20 FIX: Re-mesh every existing chunk from the current height_data.
#
# Live sculpting marks individual chunks dirty via _mark_chunk_dirty(),
# and _process() rebuilds up to 4 of them per frame. That cap is great
# for stroke-by-stroke editing — it keeps the editor responsive while
# the user paints — but it's the wrong policy for bulk swaps where every
# chunk has new data and the user is waiting for the result:
#
#   * undo / redo (the EditorUndoRedoManager swaps height_data wholesale)
#   * EXR heightmap import
#   * any future "regenerate from noise" / "clear" / "load preset" action
#
# In those cases the user wants the new shape *now*, not staggered over
# ~16 frames with a visible wipe. This function rebuilds everything
# immediately and clears the dirty queue so _process() doesn't repeat
# the work next frame.
#
# IMPORTANT: this method is invoked by the EditorUndoRedoManager via
# string-based lookup in mobile_terrain_plugin.gd::_forward_3d_gui_input
# (add_do_method / add_undo_method). If you rename it, that lookup will
# silently no-op — undo will restore height_data but the terrain mesh
# will stay frozen at the post-edit shape, which looks like undo is
# broken. Keep the name in sync with the plugin.
func force_update_all() -> void:
	# Iterate the chunks dictionary directly rather than recomputing
	# (map_size / chunk_size) — if those ever drift out of sync (e.g.
	# during a map resize that hasn't finished), iterating the dict
	# guarantees we only touch chunks that actually exist.
	#
	# V21 PERFORMANCE: defer to _process for large maps (same threshold
	# as initialize_terrain). On a 1500-chunk terrain, undo / redo /
	# heightmap-import used to lock up the editor for several seconds
	# while every chunk's mesh got rebuilt synchronously. With the dirty-
	# queue approach the editor stays interactive during the rebuild;
	# the visual "wipe" finishes within a second for sub-1000-chunk
	# maps and a few seconds for the biggest 1500+ ones.
	const SYNC_REBUILD_CHUNK_LIMIT := 256
	if chunks.size() <= SYNC_REBUILD_CHUNK_LIMIT:
		for chunk_pos in chunks.keys():
			update_chunk_mesh(chunk_pos.x, chunk_pos.y)
		# We just rebuilt everything synchronously; any pending incremental
		# work is now stale, so drop it.
		dirty_chunks.clear()
	else:
		# Mark everything dirty; _process picks it up at the adaptive
		# 64-chunk-per-frame rate (see _process for the budget math).
		# Note we don't clear dirty_chunks first — any chunks already
		# pending also get rebuilt naturally as part of this pass.
		for chunk_pos in chunks.keys():
			dirty_chunks[chunk_pos] = true


# V20 FIX: Re-upload splatmap_data to the GPU texture.
#
# The shader samples `splatmap_texture_local` (a GPU ImageTexture), but
# undo/redo only restores `splatmap_data` (the CPU byte array). Those two
# get out of sync until something else happens to repaint them — meaning
# Ctrl+Z *looks* broken: the byte array is correct, but the terrain keeps
# rendering the post-edit colors because the shader is still sampling the
# stale GPU texture.
#
# This function is the splatmap counterpart of `force_update_all()`. It
# rebuilds the GPU texture from `splatmap_data` and rebinds the shader
# uniform so the visual matches the data immediately.
#
# IMPORTANT: invoked by string-based lookup from
# mobile_terrain_plugin.gd::_forward_3d_gui_input (add_do_method /
# add_undo_method). Renaming this method will silently no-op those undo
# entries — same trap as `force_update_all`, see its comment.
func force_refresh_splatmap() -> void:
	if splatmap_data.is_empty():
		return

	# Defensive size check. The byte array could be from an older map_size
	# if someone resized the terrain while there were still paint actions
	# in the undo history. Image.create_from_data with a mismatched buffer
	# would either error out or produce a garbage texture. Warn and bail
	# instead — an undo no-op is much better UX than a visible corruption.
	var expected_bytes := map_size * map_size * 4
	if splatmap_data.size() != expected_bytes:
		push_warning(
			(
				"MobileTerrain3D: splatmap_data size %d does not match map_size %d (expected %d bytes). Skipping GPU refresh."
				% [splatmap_data.size(), map_size, expected_bytes]
			)
		)
		return

	var img := Image.create_from_data(map_size, map_size, false, Image.FORMAT_RGBA8, splatmap_data)

	if splatmap_texture_local == null:
		# No GPU texture yet — can happen if an undo fires before _ready()
		# has finished initializing the splatmap (e.g. on scene reload with
		# undo history). Create one from scratch.
		splatmap_texture_local = ImageTexture.create_from_image(img)
	else:
		# V21: check texture dimensions match before calling update().
		# ImageTexture.update() requires the new image be the same size
		# as the texture; otherwise Godot 4 either errors out or (worse)
		# silently leaves the GPU side stale. Can happen with undo/redo
		# that crosses a map_size change boundary.
		var tex_img := splatmap_texture_local.get_image()
		var sizes_match: bool = (
			tex_img != null and tex_img.get_width() == map_size and tex_img.get_height() == map_size
		)
		if sizes_match:
			# In-place GPU upload. This keeps the same ImageTexture reference,
			# which is important because the shader uniform already points to
			# it — replacing the reference would force a re-bind on every undo.
			splatmap_texture_local.update(img)
		else:
			# Size mismatch — must replace the texture and re-bind the shader
			# uniform below.
			splatmap_texture_local = ImageTexture.create_from_image(img)

	# Rebind defensively. `update()` preserves the reference so the bind
	# is usually already valid, but if we took the `create_from_image`
	# branch above the shader was still holding the old (or null) handle.
	if terrain_material and terrain_material is ShaderMaterial:
		terrain_material.set_shader_parameter("splatmap", splatmap_texture_local)


# Gather placed objects for persistence into the .res. One entry per active
# MultiMesh: the Mesh resource itself + every instance transform. Storing the
# Mesh (not a path string) lets inspector primitives with no resource_path
# persist too. Empty multimeshes are skipped.
func _collect_object_slots() -> Array:
	var slots: Array = []
	for mesh in multimesh_instances:
		var mmi = multimesh_instances[mesh]
		if not is_instance_valid(mmi) or mmi.multimesh == null:
			continue
		var mm: MultiMesh = mmi.multimesh
		var count: int = mm.instance_count
		if count <= 0:
			continue
		var transforms: Array[Transform3D] = []
		transforms.resize(count)
		for i in range(count):
			transforms[i] = mm.get_instance_transform(i)
		slots.append({"mesh": mesh, "transforms": transforms})
	return slots


# Rebuild MultiMesh instances from .res object data. Skips a slot whose mesh
# can't be resolved with a warning rather than erroring out the whole load.
func _restore_object_slots(slots: Array) -> void:
	if slots == null or slots.is_empty():
		return
	for slot in slots:
		var transforms = slot.get("transforms", [])
		if transforms.is_empty():
			continue
		# New format stores the Mesh resource directly (works for inspector
		# primitives with no resource_path). Old .res files stored a
		# "mesh_path" string instead — load it so existing saves still restore.
		var mesh: Mesh = slot.get("mesh", null)
		if mesh == null:
			var mesh_path: String = slot.get("mesh_path", "")
			if mesh_path == "" or not ResourceLoader.exists(mesh_path):
				TerrainDiagnostics.warn(
					"MT-W16: object mesh '%s' not found; skipping its placements." % mesh_path
				)
				continue
			var res = load(mesh_path)
			if not (res is Mesh):
				continue
			mesh = res
		var mmi = _get_or_create_multimesh(mesh)
		if mmi == null:
			continue
		var mm: MultiMesh = mmi.multimesh
		mm.instance_count = transforms.size()
		for i in range(transforms.size()):
			mm.set_instance_transform(i, transforms[i])


func restore_multimeshes():
	multimesh_instances.clear()
	for child in get_children():
		if child is MultiMeshInstance3D and child.name.begins_with("Assets_"):
			if child.multimesh and child.multimesh.mesh:
				multimesh_instances[child.multimesh.mesh] = child


func garbage_collect_multimeshes():
	# Drop any MultiMesh whose mesh is no longer referenced by an asset slot.
	# keys() returns a fresh Array so erasing inside the loop is safe.
	for mesh in multimesh_instances.keys():
		if mesh in asset_meshes:
			continue
		var child = multimesh_instances[mesh]
		multimesh_instances.erase(mesh)
		if is_instance_valid(child):
			child.queue_free()


# V20 FIX: Re-key an existing MultiMeshInstance3D to a different mesh,
# preserving the instances inside it.
#
# Use case: a user paints 50 trees into slot 0, then realises they meant
# to use a different mesh and swaps slot 0's mesh in the asset manager.
# Without this method, the editor either:
#   a) creates a fresh empty multimesh for the new mesh and leaves the
#      old tree multimesh orphaned in the scene (50 untouchable trees
#      forever rendering, no way to manage them via the UI), or
#   b) hard-GCs the orphan (instance loss — user's painting work wiped).
#
# Repurposing is the user-friendly middle ground: the same multimesh
# stays in the scene, gets its `mesh` property swapped to the new mesh,
# and gets re-keyed in `multimesh_instances` so future lookups find it
# under the new mesh's path. The 50 placements stay in place but now
# render as the new mesh.
#
# Returns true if the swap happened. Returns false (with no side effect)
# when a safe swap isn't possible:
#   - either mesh is null, or old == new (no-op)
#   - the old mesh has no multimesh (nothing to preserve)
#   - the new mesh ALREADY has its own multimesh (conflict — preserving
#     would require merging two transform buffers, which is a UX
#     decision the caller should make explicitly via GC instead).
#
# Called from mobile_terrain_plugin.gd::_on_object_changed.
func repurpose_multimesh_to(old_mesh: Mesh, new_mesh: Mesh) -> bool:
	if old_mesh == null or new_mesh == null or old_mesh == new_mesh:
		return false
	if not multimesh_instances.has(old_mesh):
		return false
	if multimesh_instances.has(new_mesh):
		return false  # Caller should GC instead — see docstring

	var mmi: MultiMeshInstance3D = multimesh_instances[old_mesh]
	if not is_instance_valid(mmi) or mmi.multimesh == null:
		return false

	# Swap the rendered mesh; instance_count and per-instance transforms are
	# unaffected by changing `mesh`, so every placement stays put but now
	# renders as the new model.
	mmi.multimesh.mesh = new_mesh
	mmi.name = "Assets_" + TerrainObjectPlacer.mesh_label(new_mesh)
	# Re-key the registry so future lookups by new_mesh find this mmi.
	multimesh_instances.erase(old_mesh)
	multimesh_instances[new_mesh] = mmi
	return true


func _get_or_create_multimesh(target_mesh: Mesh) -> MultiMeshInstance3D:
	# Delegates to TerrainObjectPlacer. No resource_path requirement now, so
	# inspector primitives (BoxMesh, ...) place correctly; the registry is
	# keyed by the Mesh resource itself (see systems/object_placer.gd).
	return TerrainObjectPlacer.get_or_create_mmi(self, target_mesh, multimesh_instances)


func get_intersection_raymarch_persistent(camera: Camera3D, screen_pos: Vector2) -> Dictionary:
	# V22: delegated to TerrainRaymarchSystem so the algorithm can be
	# unit-tested without spinning up the whole terrain node.
	return TerrainRaymarchSystem.intersect(
		camera, screen_pos, height_data, map_size, global_transform
	)


func start_stroke():
	last_sculpt_pos = Vector3.INF
	# V20 FIX (notice #2): also reset the object-placement gate.
	last_placement_pos = Vector3.INF
	# V22 FIX (audit-chunk-resize-during-stroke): mark active so map_size
	# / chunk_size setters can defer their destructive rebuild until the
	# stroke ends. Bumped on every start so consecutive strokes see a new
	# revision and stale caches detect themselves.
	_active_stroke = true
	_stroke_revision += 1
	if current_tool == 7 and splatmap_texture_local != null:
		_splatmap_stroke_image = splatmap_texture_local.get_image()
		_splatmap_stroke_revision = _stroke_revision
		if terrain_material and terrain_material is ShaderMaterial:
			terrain_material.set_shader_parameter("splatmap", splatmap_texture_local)


func end_stroke():
	last_sculpt_pos = Vector3.INF
	# V22 FIX (audit-paint-init-mid-stroke): if the splatmap was rebuilt
	# during this stroke (revision bumped or current_tool changed), the
	# cached _splatmap_stroke_image points at the now-orphaned old texture.
	# Skip the sync rather than overwriting splatmap_data with stale bytes.
	if _splatmap_stroke_image != null and _splatmap_stroke_revision == _stroke_revision:
		splatmap_data = _splatmap_stroke_image.get_data().duplicate()
	_splatmap_stroke_image = null
	_active_stroke = false
	# V22: if a map_size/chunk_size setter deferred itself during the
	# stroke, replay it now that the stroke is closed.
	if _deferred_map_size != 0 and _deferred_map_size != map_size:
		var pending: int = _deferred_map_size
		_deferred_map_size = 0
		map_size = pending
	if _deferred_chunk_size != 0 and _deferred_chunk_size != chunk_size:
		var pending: int = _deferred_chunk_size
		_deferred_chunk_size = 0
		chunk_size = pending


func apply_brush_stroke_slope(hit_point: Vector3, hit_normal: Vector3):
	if current_tool == 8:  # Object — simple one-per-step stamp
		# Drag lays a spaced trail; a held-still finger places exactly one.
		# Delegated to TerrainObjectPlacer (systems/object_placer.gd).
		if current_object_slot < 0 or current_object_slot >= asset_meshes.size():
			return
		var mesh: Mesh = asset_meshes[current_object_slot]
		if mesh == null:
			return
		if not TerrainObjectPlacer.should_place(last_placement_pos, hit_point, object_spacing):
			return
		var mmi := TerrainObjectPlacer.get_or_create_mmi(self, mesh, multimesh_instances)
		if mmi == null:
			return
		var idx := TerrainObjectPlacer.place_one(
			mmi, hit_point, hit_normal, object_scale, object_align_to_normal, object_random_yaw
		)
		if idx >= 0:
			last_placement_pos = hit_point
			foliage_placed.emit(mmi, idx, mmi.multimesh.get_instance_transform(idx))
		return

	# V21: rate-limit stationary brush application.
	#
	# Mobile touch motion events fire every few ms even when the user
	# is holding their finger still (sub-pixel touch jitter shows up as
	# motion events at the same world position). Without throttling,
	# `_apply_brush_single` ran on every event — at 60+Hz that turned a
	# default-strength brush into a runaway terrain raiser: a 1-second
	# tap raised the centre by ~30 units, producing the "tall orange
	# column" the user reported. Strokes that actually move are still
	# stepped by `step_dist` (below) so dragging fast doesn't skip
	# pixels; the rate limit only kicks in when the finger is stationary.
	#
	# 0.04 s = 25 Hz max — enough to feel responsive on continuous press,
	# slow enough that default-strength taps grow at a few units/sec
	# rather than tens.
	const MIN_STATIONARY_INTERVAL := 0.04
	var now: float = Time.get_ticks_msec() / 1000.0
	var moved: bool = (
		last_sculpt_pos == Vector3.INF
		or last_sculpt_pos.distance_to(hit_point) > max(0.5, brush_radius * 0.1)
	)
	if not moved and (now - _last_brush_apply_time) < MIN_STATIONARY_INTERVAL:
		# Not enough time has passed since the last stationary apply.
		# Skip silently — `last_sculpt_pos` stays put so the next motion
		# event still benefits from the step-distance lerp below.
		return
	_last_brush_apply_time = now

	if last_sculpt_pos != Vector3.INF:
		var dist = last_sculpt_pos.distance_to(hit_point)
		var step_dist = max(0.5, brush_radius * 0.1)
		if dist > step_dist:
			# V21 STABILITY: cap the per-event step count.
			#
			# Without a cap, a large mouse jump (e.g. flick + drag, or
			# touch-released-and-resumed across the viewport) with a
			# small brush could produce hundreds of steps in a single
			# motion event. Each step is a full brush dab — a 400-step
			# event at default radius is ~2 frames of locked-up sculpting
			# on a mid-tier mobile GPU. The cap caps the worst case to
			# 32 steps per event (~6ms even on mobile), which lets a fast
			# drag still get a continuous-looking stroke but never freezes
			# the frame. Skipped pixels become visible only on absurd
			# flicks at tiny brush sizes — acceptable trade.
			var steps: int = mini(int(dist / step_dist), 32)
			for i in range(1, steps + 1):
				_apply_brush_single(last_sculpt_pos.lerp(hit_point, float(i) / steps))
		else:
			_apply_brush_single(hit_point)
	else:
		_apply_brush_single(hit_point)
	last_sculpt_pos = hit_point
	# V21: tell the plugin to re-drape the cursor mesh on the new
	# terrain shape. Cheap signal — only fires AFTER rate limiting
	# (the early return above gates this).
	brush_applied.emit(hit_point)


func _apply_brush_single(hit_point: Vector3):
	# to_local applies the FULL inverse transform (rotation + scale), not just
	# translation, so brush cells stay aligned with the rendered surface even
	# when the terrain node is rotated/scaled. Identity transform → same as the
	# old `hit_point - global_position`.
	var local_pos := to_local(hit_point)
	# V21 STRENGTH SCALING NOTE
	#
	# Each tool below applies its own internal multiplier on top of the
	# user-visible brush_strength. The user sees one slider [0.1, 2.0],
	# but raw 2.0 added directly to a heightmap per dab × 25 dabs/sec is
	# unworkable, while raw 2.0 of splatmap alpha would clip every paint
	# slot to one slot instantly. So the scaling map is:
	#
	#   Yükselt/Alçalt: × 0.5  → 2.0 slider = 1.0 unit/dab (sane sculpt rate)
	#   Boya:           × 0.1  → 2.0 slider = 0.2 alpha/dab (5 dabs to fill)
	#   Yumuşat:        × 0.5  → 2.0 slider = full lerp (was inside _smooth at *0.5)
	#   Pürüzlendir:    × 0.2  → 2.0 slider = ±0.4 noise/dab
	#   Düzleştir:      × 1.0  → 2.0 slider = 100% pull toward target per dab
	#   Terasla:        × 1.0  → 2.0 slider = 10-unit step height (s = strength*5)
	#   Erozyon:        × 0.1  → 2.0 slider = 0.2 max transfer/dab
	#
	# Brush falloff (centre 1.0 → edge 0.0) further scales this per pixel
	# inside each function. The user experience: doubling the slider
	# doubles the per-dab effect, max never feels destructive.
	if current_tool == 7:  # Paint
		_paint_splatmap(local_pos.x, local_pos.z, brush_radius, brush_strength * 0.1)
		return
	# V22 Phase 4: sculpt ops delegated to SculptOps. The brush state +
	# noise generator are wrapped in a per-dab BrushSystem instance, the
	# chunk-dirty callback is bound here so SculptOps doesn't need to
	# know about the node's internals.
	var brush := BrushSystem.new(map_size, brush_mask, _brush_mask_image, brush_shape, noise_gen)
	var mark_dirty := func(x: int, z: int) -> void: _mark_chunk_dirty(x, z)
	match current_tool:
		0, 1:
			var dir: float = 1.0 if current_tool == 0 else -1.0
			SculptOps.modify_height(
				brush,
				height_data,
				map_size,
				mark_dirty,
				local_pos.x,
				local_pos.z,
				brush_radius,
				brush_strength * dir * 0.5
			)
		2:
			SculptOps.flatten_height(
				brush,
				height_data,
				map_size,
				mark_dirty,
				local_pos.x,
				local_pos.z,
				brush_radius,
				local_pos.y,
				brush_strength
			)
		3:
			height_data = SculptOps.smooth_height(
				brush,
				height_data,
				map_size,
				mark_dirty,
				local_pos.x,
				local_pos.z,
				brush_radius,
				brush_strength
			)
		4:
			SculptOps.noise_height(
				brush,
				height_data,
				map_size,
				mark_dirty,
				local_pos.x,
				local_pos.z,
				brush_radius,
				brush_strength
			)
		5:
			SculptOps.terrace_height(
				brush,
				height_data,
				map_size,
				mark_dirty,
				local_pos.x,
				local_pos.z,
				brush_radius,
				brush_strength
			)
		6:  # erosion
			height_data = SculptOps.erode_height(
				brush,
				height_data,
				map_size,
				mark_dirty,
				local_pos.x,
				local_pos.z,
				brush_radius,
				brush_strength
			)


func _paint_splatmap(cx: float, cz: float, radius: float, strength: float):
	# V22: explicit zero-based range guard; warns on slot 5+ instead of
	# silently doing nothing (RGBA8 splatmap only has 4 channels).
	if not (0 <= current_paint_slot and current_paint_slot < 4):
		TerrainDiagnostics.warn(TerrainDiagnostics.E_PAINT_SLOT_OOB, [current_paint_slot])
		return
	# V20 FIX (#14): use the stroke-cached image when available; otherwise
	# fall back to a fresh `get_image()` so scripted/ad-hoc paint calls
	# outside a stroke still work.
	var img: Image = _splatmap_stroke_image
	var in_stroke := img != null
	if not in_stroke:
		# V21: defensive null check. splatmap_texture_local can be null
		# very briefly during initialize_splatmap mid-rebuild (e.g. user
		# changed map_size while the brush was hovering and a stray
		# motion event sneaks in before initialize_terrain finishes).
		# Without this guard the .get_image() call would NPE and the
		# stroke would crash the editor.
		if splatmap_texture_local == null:
			return
		img = splatmap_texture_local.get_image()
		if img == null:
			return
	# V21: defensive size match. If for whatever reason the splatmap image's
	# dimensions don't match map_size (e.g. a partial mid-resize state, or
	# a saved scene that bypassed _initialize_splatmap somehow), paint would
	# silently corrupt arbitrary parts of the image — img.get_pixel(x, z)
	# with x >= img.get_width() returns the wrong pixel without erroring.
	# Bail rather than write garbage.
	if img.get_width() != map_size or img.get_height() != map_size:
		TerrainDiagnostics.error(
			TerrainDiagnostics.E_SPLATMAP_SIZE_DRIFT, [img.get_width(), img.get_height(), map_size]
		)
		return

	# TKT-003 Phase A.1: paint algorithm extracted into systems/splatmap_system.gd
	# (pure, unit-testable). This function keeps responsibility for state —
	# which Image is active, when to flush bytes to GPU, when to rebind
	# the shader uniform — while the per-pixel competitive blend math
	# lives in SplatmapSystem.paint.
	var brush := BrushSystem.new(map_size, brush_mask, _brush_mask_image, brush_shape, noise_gen)
	SplatmapSystem.paint(img, map_size, cx, cz, radius, strength, current_paint_slot, brush)

	# V22: null guard. splatmap_texture_local can be nulled between
	# start_stroke and now in pathological cases (eg user resized map
	# mid-stroke and the rebuild raced ahead of our paint dab).
	if splatmap_texture_local != null:
		splatmap_texture_local.update(img)
	# V20: inside a stroke we leave byte-array sync and shader rebind to
	# end_stroke / start_stroke — both are no-ops per-dab. Out-of-stroke
	# calls (scripts, manual paint) keep eager behaviour.
	if not in_stroke:
		# V22: .duplicate() so callers mutating the returned bytes can't
		# silently corrupt our internal copy via the shared-buffer trap
		# some Godot 4 builds have.
		splatmap_data = img.get_data().duplicate()
		if terrain_material and terrain_material is ShaderMaterial:
			terrain_material.set_shader_parameter("splatmap", splatmap_texture_local)


func _set_brush_mask(val: Texture2D) -> void:
	brush_mask = val
	if val == null:
		_brush_mask_image = null
		return
	# Cache the Image once on assignment. get_image() is reasonably cheap
	# but doing it per-stroke-pixel (hundreds of times per second during
	# painting) is wasteful — and on the Mobile renderer it can stall if
	# the texture isn't yet fully imported. The cached Image stays live
	# in our memory until the user picks a different mask.
	var src_img := val.get_image()
	if src_img == null:
		_brush_mask_image = null
		return
	# V21: defensively duplicate before mutating. Texture2D.get_image()
	# returns a shared reference; the decompress() / convert() calls
	# below mutate in place, which would corrupt the source texture
	# (e.g. the brush thumbnail in the picker turning grey because we
	# silently RGBA8-converted the underlying ImageTexture).
	# Same bug fixed in _import_exr — same pattern here.
	var img: Image = src_img.duplicate()
	# Some textures come in compressed formats (BPTC, ETC2) that can't
	# be sampled with get_pixel() until decompressed. Convert to RGBA8.
	if img.is_compressed():
		img.decompress()
	# Force RGBA8 so get_pixel().r is always defined; some imports give us
	# L8 or RGB which would still work for `.r` but RGBA8 sidesteps quirks.
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	_brush_mask_image = img


# V19 PRO: Advanced Shape detection
func _mark_chunk_dirty(x: int, z: int):
	# V20 FIX (bug M1): symmetric cross-chunk propagation for normal-calc
	# dependencies.
	#
	# Each chunk's mesh depends on vertices it owns DIRECTLY plus the
	# one-cell ring just outside it — because the per-vertex normal
	# computation in update_chunk_mesh() does central differences over
	# global height_data (hL/hR/hD/hU = get_height with ±1 offsets).
	# Chunk M's first vertex at (M*chunk_size) reads its hL from vertex
	# (M*chunk_size - 1), which lives in chunk M-1. And chunk M's last
	# vertex at ((M+1)*chunk_size) reads hR from vertex
	# ((M+1)*chunk_size + 1), which lives in chunk M+1.
	#
	# Old code propagated only THREE of the four resulting edge cases:
	#   - x % cs == 0     → mark cx-1  (shared boundary vertex) ✓
	#   - x % cs == cs-1  → mark cx+1  (RIGHT chunk's first-vertex normal
	#                                   reads this) ✓
	#   - x % cs == 1     → mark cx-1  (LEFT chunk's last-vertex normal
	#                                   reads this) ✗ MISSING
	# Same gap on the Z axis.
	#
	# Symptom: edit a vertex one cell inside a chunk's left/top boundary
	# (e.g. vertex 33 when chunk_size=32). The brush marks chunk 1
	# (the owner). Chunk 0 keeps its stale mesh — and its last vertex
	# (at global x=32) keeps its stale normal computed from the OLD
	# value of vertex 33. Chunks 0 and 1 share that boundary vertex's
	# WORLD position but now disagree on its NORMAL → visible shading
	# seam every chunk_size cells, view-angle dependent. The same effect
	# would explain reports of "stripes appearing in lighting after
	# sculpting" without any visible terrain geometry issue.
	var cx = x / chunk_size
	var cz = z / chunk_size
	var num_chunks_minus_1 = (map_size / chunk_size) - 1
	dirty_chunks[Vector2i(cx, cz)] = true
	if x % chunk_size == 0 and cx > 0:
		dirty_chunks[Vector2i(cx - 1, cz)] = true
	if z % chunk_size == 0 and cz > 0:
		dirty_chunks[Vector2i(cx, cz - 1)] = true
	if x % chunk_size == chunk_size - 1 and cx < num_chunks_minus_1:
		dirty_chunks[Vector2i(cx + 1, cz)] = true
	if z % chunk_size == chunk_size - 1 and cz < num_chunks_minus_1:
		dirty_chunks[Vector2i(cx, cz + 1)] = true
	# V20 FIX (bug M1): the missing symmetric pair. Vertex one cell
	# inside the LEFT/TOP boundary of chunk cx,cz must dirty the
	# previous chunk so its outer-edge normals are recomputed against
	# the new value.
	if x % chunk_size == 1 and cx > 0:
		dirty_chunks[Vector2i(cx - 1, cz)] = true
	if z % chunk_size == 1 and cz > 0:
		dirty_chunks[Vector2i(cx, cz - 1)] = true
