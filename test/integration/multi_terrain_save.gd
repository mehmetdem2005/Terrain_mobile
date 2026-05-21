@tool
extends SceneTree

# V22 multi-terrain save test. Creates a scene with TWO MobileTerrain3D
# nodes (both large enough to qualify for externalisation), runs the
# Plan B pack+save flow, and verifies each terrain gets its own .res
# companion + the .tscn stays small.

const MAP_SIZE := 1024
const SCENE_PATH := "res://test_multi_terrain.tscn"

func _init() -> void:
	var ok := _run()
	if ok:
		print("MULTI_TERRAIN_OK")
		quit(0)
	else:
		print("MULTI_TERRAIN_FAILED")
		quit(1)

func _run() -> bool:
	var TerrainNode = load("res://addons/mobile_terrain/mobile_terrain_node.gd")
	var TerrainData = load("res://addons/mobile_terrain/mobile_terrain_data.gd")
	if TerrainNode == null or TerrainData == null:
		printerr("Cannot load terrain scripts")
		return false
	var root := Node3D.new()
	root.name = "Root"

	var t1 = TerrainNode.new()
	t1.name = "AlphaTerrain"
	t1.map_size = MAP_SIZE
	t1.chunk_size = 128
	var h1 := PackedFloat32Array()
	h1.resize(MAP_SIZE * MAP_SIZE)
	for i in range(MAP_SIZE * MAP_SIZE):
		h1[i] = float(i % 8)
	t1.height_data = h1

	var t2 = TerrainNode.new()
	t2.name = "BetaTerrain"
	t2.map_size = MAP_SIZE
	t2.chunk_size = 128
	var h2 := PackedFloat32Array()
	h2.resize(MAP_SIZE * MAP_SIZE)
	for i in range(MAP_SIZE * MAP_SIZE):
		h2[i] = float((i * 3) % 11)
	t2.height_data = h2

	root.add_child(t1)
	root.add_child(t2)
	t1.owner = root
	t2.owner = root

	# Write two .res files (one per terrain) and externalise both.
	var d1 = TerrainData.new()
	d1.height_data = t1.height_data.duplicate()
	d1.map_size = MAP_SIZE
	var res1 := "res://multi_alpha.res"
	if ResourceSaver.save(d1, res1) != OK:
		printerr("save d1 failed")
		return false
	t1.height_data = PackedFloat32Array()
	t1.splatmap_texture_local = null
	t1.external_data_path = res1

	var d2 = TerrainData.new()
	d2.height_data = t2.height_data.duplicate()
	d2.map_size = MAP_SIZE
	var res2 := "res://multi_beta.res"
	if ResourceSaver.save(d2, res2) != OK:
		printerr("save d2 failed")
		return false
	t2.height_data = PackedFloat32Array()
	t2.splatmap_texture_local = null
	t2.external_data_path = res2

	# Pack with both terrains wiped → small .tscn.
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		printerr("pack failed")
		return false
	if ResourceSaver.save(packed, SCENE_PATH) != OK:
		printerr("save tscn failed")
		return false

	var scene_size: int = FileAccess.get_file_as_bytes(SCENE_PATH).size()
	var res1_size: int = FileAccess.get_file_as_bytes(res1).size()
	var res2_size: int = FileAccess.get_file_as_bytes(res2).size()
	print("multi-terrain .tscn: %d bytes" % scene_size)
	print("alpha .res: %d bytes" % res1_size)
	print("beta  .res: %d bytes" % res2_size)

	# Assertions.
	if scene_size > 200 * 1024:
		printerr("FAIL: multi-terrain .tscn %d bytes > 200KB cap" % scene_size)
		return false
	if res1_size < 3 * 1024 * 1024:
		printerr("FAIL: alpha .res too small")
		return false
	if res2_size < 3 * 1024 * 1024:
		printerr("FAIL: beta .res too small")
		return false
	# Each .res must be independent (no overlap of path).
	if res1 == res2:
		printerr("FAIL: both terrains wrote to the same .res path")
		return false
	return true
