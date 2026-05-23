@tool
extends SceneTree

# Regression test for the "scene large on disk (XX MiB)" warning.
#
# The terrain's ShaderMaterial binds the live splatmap ImageTexture as a
# shader parameter. Because `terrain_material` is @export, packing the scene
# used to embed that material — and with it the full map_size² splatmap Image
# — straight into the .tscn (a 1280² map => ~22 MB of text). The material is
# DERIVED state (rebuilt on load by _setup_default_shader), so it must not be
# stored. This test builds a real terrain (so the material + splatmap exist),
# packs + saves it, and asserts the .tscn stays tiny with no embedded Image.
#
# Pre-fix: FAILS (material + splatmap embedded). Post-fix: PASSES.

const TerrainNode := preload("res://addons/mobile_terrain/mobile_terrain_node.gd")
const SCENE_PATH := "res://test_scene_no_embed.tscn"
const TSCN_MAX_BYTES := 80 * 1024  # the splatmap alone is far bigger than this

var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var ok := _run()
	if FileAccess.file_exists(SCENE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCENE_PATH))
	if ok:
		print("SCENE_NO_EMBED_OK")
		quit(0)
	else:
		print("SCENE_NO_EMBED_FAILED")
		quit(1)
	return true


func _run() -> bool:
	var scene_root := Node3D.new()
	scene_root.name = "Root"
	root.add_child(scene_root)

	var terrain = TerrainNode.new()
	terrain.name = "Terrain"
	terrain.map_size = 256
	terrain.chunk_size = 64
	scene_root.add_child(terrain)  # fires _ready → builds material + splatmap
	terrain.owner = scene_root

	# Precondition: the material AND splatmap must really exist, otherwise the
	# test could pass for the wrong reason (nothing to embed).
	if terrain.terrain_material == null or not (terrain.terrain_material is ShaderMaterial):
		printerr("precondition: terrain_material was not built")
		return false
	if terrain.splatmap_texture_local == null:
		printerr("precondition: splatmap_texture_local was not built")
		return false

	var packed := PackedScene.new()
	var perr := packed.pack(scene_root)
	if perr != OK:
		printerr("pack failed err=%d" % perr)
		return false
	var serr := ResourceSaver.save(packed, SCENE_PATH)
	if serr != OK:
		printerr("save failed err=%d" % serr)
		return false

	var size := FileAccess.get_file_as_bytes(SCENE_PATH).size()
	print("scene .tscn size: %d bytes (%.1f KB)" % [size, size / 1024.0])
	var text := FileAccess.get_file_as_string(SCENE_PATH)
	var passed := true
	if size >= TSCN_MAX_BYTES:
		printerr("FAIL: .tscn %d >= cap %d — material/splatmap embedded" % [size, TSCN_MAX_BYTES])
		passed = false
	if text.contains('sub_resource type="Image"'):
		printerr("FAIL: scene contains an embedded Image sub-resource (the splatmap)")
		passed = false
	return passed
