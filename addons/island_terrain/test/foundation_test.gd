extends SceneTree

const Constants = preload("res://addons/island_terrain/core/terrain_constants.gd")
const Manifest = preload("res://addons/island_terrain/core/terrain_manifest.gd")
const Coordinates = preload("res://addons/island_terrain/core/terrain_coordinate_system.gd")
const RegionData = preload("res://addons/island_terrain/core/terrain_region_data.gd")
const MemoryBudget = preload("res://addons/island_terrain/core/terrain_memory_budget.gd")
const MeshBuilder = preload("res://addons/island_terrain/rendering/clipmap_mesh_builder.gd")

var _failures := PackedStringArray()


func _init() -> void:
	_test_constants()
	_test_manifest_and_coordinates()
	_test_sparse_region_channels()
	_test_memory_profiles()
	_test_clipmap_mesh()

	if _failures.is_empty():
		print("IslandTerrain foundation tests: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_constants() -> void:
	_check(Constants.is_valid_sample_count(257), "257 must be a valid 2^n + 1 sample count")
	_check(not Constants.is_valid_sample_count(256), "256 must be rejected as a region sample count")
	_check(Constants.safe_macro_resolution(7000, false) <= 513, "mobile macro resolution hard cap failed")
	_check(Constants.clamp_base_quads(65) % 2 == 0, "base quads must remain even")


func _test_manifest_and_coordinates() -> void:
	var manifest := Manifest.new()
	_check(manifest.validate().is_empty(), "default manifest must validate")
	_check(manifest.region_count_axis() == 16, "4096m / 256m must produce 16 regions per axis")
	var coordinates := Coordinates.new(manifest)
	_check(coordinates.world_to_region(Vector3(-2048.0, 0.0, -2048.0)) == Vector2i.ZERO, "world minimum region mismatch")
	_check(coordinates.world_to_region(Vector3.ZERO) == Vector2i(8, 8), "world centre region mismatch")
	_check(coordinates.world_to_region_clamped(Vector3(9000.0, 0.0, 9000.0)) == Vector2i(15, 15), "region clamp mismatch")
	var world_point: Vector3 = coordinates.region_pixel_to_world(Vector2i(1, 2), Vector2i(128, 128), 12.0)
	_check(is_equal_approx(world_point.y, 12.0), "region pixel height conversion mismatch")


func _test_sparse_region_channels() -> void:
	var region := RegionData.new()
	region.initialize(Vector2i(2, 3), 257)
	var height_only_bytes: int = 257 * 257 * 4
	_check(region.estimated_memory_bytes() == height_only_bytes, "new region must allocate height only")
	_check(region.material_weight_data.is_empty(), "material weights must be lazy")
	region.ensure_channel(&"wetness")
	_check(region.wetness_data.size() == 257 * 257, "wetness lazy allocation failed")
	_check(region.validate_dimensions().is_empty(), "initialized region dimensions must validate")


func _test_memory_profiles() -> void:
	var low := MemoryBudget.create_for_profile(MemoryBudget.DeviceProfile.LOW)
	var high := MemoryBudget.create_for_profile(MemoryBudget.DeviceProfile.HIGH)
	_check(low.macro_height_resolution == 257, "low profile height resolution mismatch")
	_check(low.max_cached_regions < high.max_cached_regions, "profile cache scaling mismatch")
	_check(low.estimated_clipmap_vertices() < high.estimated_clipmap_vertices(), "profile clipmap scaling mismatch")
	_check(low.can_cache_region(1024, 0), "low profile must admit a small region")


func _test_clipmap_mesh() -> void:
	var centre: ArrayMesh = MeshBuilder.build_level(32, 0)
	var ring: ArrayMesh = MeshBuilder.build_level(32, 1)
	_check(centre.get_surface_count() == 1, "centre clipmap mesh surface missing")
	_check(ring.get_surface_count() == 1, "ring clipmap mesh surface missing")
	_check(centre.surface_get_array_len(0) > 0, "centre clipmap mesh has no vertices")
	_check(ring.surface_get_array_index_len(0) > 0, "ring clipmap mesh has no indices")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
