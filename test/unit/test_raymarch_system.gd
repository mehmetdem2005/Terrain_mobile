@tool
extends SceneTree

# V22 raymarch unit test. Uses TerrainRaymarchSystem.intersect_ray() so
# we avoid the Camera3D projection step that requires a real viewport
# (headless transforms aren't flushed inside SceneTree._init).

func _init() -> void:
	var failures: Array[String] = []
	_run("hit_simple", _test_hit_simple, failures)
	_run("miss_off_terrain", _test_miss_off_terrain, failures)
	_run("camera_below_terrain", _test_camera_below, failures)
	_run("oob_binary_search", _test_oob_binary_search, failures)
	_run("zero_map_size", _test_zero_map_size, failures)
	_run("normal_flat_is_up", _test_normal_flat, failures)
	if failures.is_empty():
		print("RAYMARCH_TEST_OK")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: " + f)
		print("RAYMARCH_TEST_FAILED count=%d" % failures.size())
		quit(1)

func _run(name: String, fn: Callable, failures: Array[String]) -> void:
	var err = fn.call()
	if err != "":
		failures.append("%s — %s" % [name, err])
	else:
		print("OK  %s" % name)

func _make_flat_terrain(size: int, height: float) -> PackedFloat32Array:
	var arr := PackedFloat32Array()
	arr.resize(size * size)
	for i in range(size * size):
		arr[i] = height
	return arr

func _test_hit_simple() -> String:
	# Ray from (64, 100, 64) pointing straight down at flat terrain y=5.
	var heights := _make_flat_terrain(128, 5.0)
	var from := Vector3(64, 100, 64)
	var dir := Vector3(0, -1, 0)
	var result: Dictionary = TerrainRaymarchSystem.intersect_ray(from, dir, heights, 128, Vector3.ZERO)
	if result.pos == Vector3.INF:
		return "expected hit on flat terrain at y=5, got INF"
	if absf(result.pos.y - 5.0) > 1.5:
		return "expected pos.y ~5.0, got %f" % result.pos.y

	# Hit position should be inside the terrain grid.
	if result.pos.x < 0 or result.pos.x >= 128:
		return "hit pos.x %f outside grid" % result.pos.x
	return ""

func _test_miss_off_terrain() -> String:
	# Ray that travels parallel to the terrain plane far below it — never
	# enters the heightfield.
	var heights := _make_flat_terrain(128, 0.0)
	var from := Vector3(-1000, -500, -1000)
	var dir := Vector3(0, 0, -1)
	var result: Dictionary = TerrainRaymarchSystem.intersect_ray(from, dir, heights, 128, Vector3.ZERO)
	if result.pos != Vector3.INF:
		return "expected INF for ray that never enters terrain, got %s" % str(result.pos)
	return ""

func _test_camera_below() -> String:
	# Ray origin below the terrain surface; the i==0 guard must reject
	# the spurious immediate hit and the ray exits straight down → INF.
	var heights := _make_flat_terrain(128, 10.0)
	var from := Vector3(64, 5.0, 64)  # under height 10
	var dir := Vector3(0, -1, 0)
	var result: Dictionary = TerrainRaymarchSystem.intersect_ray(from, dir, heights, 128, Vector3.ZERO)
	if result.pos != Vector3.INF:
		return "camera-below: expected INF, got %s" % str(result.pos)
	return ""

func _test_oob_binary_search() -> String:
	# Tiny 8x8 terrain, ray angled near edge. Just verify no crash.
	var heights := _make_flat_terrain(8, 2.0)
	var from := Vector3(7.5, 50, 7.5)
	var dir := Vector3(0.05, -1, 0.05).normalized()
	var result: Dictionary = TerrainRaymarchSystem.intersect_ray(from, dir, heights, 8, Vector3.ZERO)
	if not result.has("pos") or not result.has("normal"):
		return "result missing pos/normal keys"
	return ""

func _test_zero_map_size() -> String:
	var heights := PackedFloat32Array()
	var result: Dictionary = TerrainRaymarchSystem.intersect_ray(Vector3.ZERO, Vector3(0, -1, 0), heights, 0, Vector3.ZERO)
	if result.pos != Vector3.INF:
		return "map_size=0 should return INF, got %s" % str(result.pos)
	return ""

func _test_normal_flat() -> String:
	# Hit on flat terrain → normal should point straight up.
	var heights := _make_flat_terrain(64, 0.0)
	var from := Vector3(32, 10, 32)
	var dir := Vector3(0, -1, 0)
	var result: Dictionary = TerrainRaymarchSystem.intersect_ray(from, dir, heights, 64, Vector3.ZERO)
	if result.pos == Vector3.INF:
		return "expected hit"
	# Normal Y component should dominate (close to 1.0) on a flat surface.
	if result.normal.y < 0.9:
		return "expected flat normal.y > 0.9, got %s" % str(result.normal)
	return ""
