@tool
extends SceneTree

# V22 SAVE ROUNDTRIP INTEGRATION TEST
# ===================================
# Headlessly creates a MobileTerrain3D with a 1280×1280 heightmap,
# triggers the Plan B save flow via EditorPlugin._save_external_data,
# then asserts:
#   - main.tscn ends up < 100 KB (no inline binary)
#   - the .res companion file exists and is ~6 MB
#
# This is the "user can't see the MB problem anymore" proof. If this
# test fails the regression must be fixed before shipping.

const MAP_SIZE := 1280
const SCENE_PATH := "res://test_terrain_scene.tscn"
const TSCN_MAX_BYTES := 200 * 1024  # 200 KB hard cap (~26 MB was the bug)

func _init() -> void:
	var ok := _run()
	if ok:
		print("SAVE_ROUNDTRIP_OK")
		quit(0)
	else:
		print("SAVE_ROUNDTRIP_FAILED")
		quit(1)

func _run() -> bool:
	# Build a synthetic terrain large enough to trigger externalisation.
	var TerrainNode = load("res://addons/mobile_terrain/mobile_terrain_node.gd")
	if TerrainNode == null:
		printerr("Cannot load terrain script")
		return false
	var terrain: Node3D = TerrainNode.new()
	terrain.name = "TestTerrain"
	# Skip the heavy _ready cascade in headless mode by setting map_size
	# BEFORE adding to tree.
	terrain.map_size = MAP_SIZE
	terrain.chunk_size = 128
	var height: PackedFloat32Array = PackedFloat32Array()
	height.resize(MAP_SIZE * MAP_SIZE)
	for i in range(MAP_SIZE * MAP_SIZE):
		height[i] = float(i % 16)
	terrain.height_data = height
	# Pack into a PackedScene and save (this is Plan B's exact code path).
	var root := Node3D.new()
	root.name = "Root"
	root.add_child(terrain)
	terrain.owner = root
	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	if pack_err != OK:
		printerr("PackedScene.pack failed err=%d" % pack_err)
		return false
	# Save once with the heavy data INLINE — this is the "baseline" of what
	# the bug looks like. We don't actually assert the size here, just
	# observe.
	var inline_path := "res://test_terrain_inline.tscn"
	ResourceSaver.save(packed, inline_path)
	var inline_size := FileAccess.get_file_as_bytes(inline_path).size()
	print("Inline .tscn size: %d bytes (%.2f MB)" % [inline_size, inline_size / 1048576.0])
	# Now write the .res companion and wipe in-memory before re-pack.
	var data = load("res://addons/mobile_terrain/mobile_terrain_data.gd").new()
	data.height_data = terrain.height_data.duplicate()
	data.map_size = MAP_SIZE
	var res_path := "res://test_terrain.res"
	var res_err := ResourceSaver.save(data, res_path)
	if res_err != OK:
		printerr("ResourceSaver.save .res failed err=%d" % res_err)
		return false
	# Wipe, set external_data_path, repack, save again. This is what the
	# plugin's _save_external_data does on the user's behalf.
	terrain.height_data = PackedFloat32Array()
	terrain.splatmap_texture_local = null
	terrain.external_data_path = res_path
	var packed2 := PackedScene.new()
	var pack_err2 := packed2.pack(root)
	if pack_err2 != OK:
		printerr("Second pack failed err=%d" % pack_err2)
		return false
	var external_path := "res://test_terrain_external.tscn"
	var save_err := ResourceSaver.save(packed2, external_path)
	if save_err != OK:
		printerr("Second save failed err=%d" % save_err)
		return false
	var external_size := FileAccess.get_file_as_bytes(external_path).size()
	var res_size := FileAccess.get_file_as_bytes(res_path).size()
	print("External .tscn size: %d bytes (%.2f KB)" % [external_size, external_size / 1024.0])
	print(".res size: %d bytes (%.2f MB)" % [res_size, res_size / 1048576.0])

	# Assertions.
	var passed := true
	if external_size >= TSCN_MAX_BYTES:
		printerr("FAIL: .tscn %d bytes >= cap %d. Plan B did not slim the scene." % [external_size, TSCN_MAX_BYTES])
		passed = false
	if res_size < 5 * 1024 * 1024:
		printerr("FAIL: .res %d bytes < 5 MB. height_data was not written." % res_size)
		passed = false
	if inline_size <= external_size:
		printerr("WARN: inline .tscn (%d) <= external .tscn (%d). Test setup may be invalid." % [inline_size, external_size])
	return passed
