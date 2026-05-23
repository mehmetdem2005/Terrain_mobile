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
	_run("transform_world_pick", _test_transform_world, failures)
	_run("at_surface_start", _test_at_surface_start, failures)
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
	var result: Dictionary = TerrainRaymarchSystem.intersect_ray(
		from, dir, heights, 128, Vector3.ZERO
	)
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
	var result: Dictionary = TerrainRaymarchSystem.intersect_ray(
		from, dir, heights, 128, Vector3.ZERO
	)
	if result.pos != Vector3.INF:
		return "expected INF for ray that never enters terrain, got %s" % str(result.pos)
	return ""


func _test_camera_below() -> String:
	# Ray origin below the terrain surface; the i==0 guard must reject
	# the spurious immediate hit and the ray exits straight down → INF.
	var heights := _make_flat_terrain(128, 10.0)
	var from := Vector3(64, 5.0, 64)  # under height 10
	var dir := Vector3(0, -1, 0)
	var result: Dictionary = TerrainRaymarchSystem.intersect_ray(
		from, dir, heights, 128, Vector3.ZERO
	)
	if result.pos != Vector3.INF:
		return "camera-below: expected INF, got %s" % str(result.pos)
	return ""


func _test_oob_binary_search() -> String:
	# Tiny 8x8 terrain, ray angled near edge. Just verify no crash.
	var heights := _make_flat_terrain(8, 2.0)
	var from := Vector3(7.5, 50, 7.5)
	var dir := Vector3(0.05, -1, 0.05).normalized()
	var result: Dictionary = TerrainRaymarchSystem.intersect_ray(
		from, dir, heights, 8, Vector3.ZERO
	)
	if not result.has("pos") or not result.has("normal"):
		return "result missing pos/normal keys"
	return ""


func _test_zero_map_size() -> String:
	var heights := PackedFloat32Array()
	var result: Dictionary = TerrainRaymarchSystem.intersect_ray(
		Vector3.ZERO, Vector3(0, -1, 0), heights, 0, Vector3.ZERO
	)
	if result.pos != Vector3.INF:
		return "map_size=0 should return INF, got %s" % str(result.pos)
	return ""


func _test_normal_flat() -> String:
	# Hit on flat terrain → normal should point straight up.
	var heights := _make_flat_terrain(64, 0.0)
	var from := Vector3(32, 10, 32)
	var dir := Vector3(0, -1, 0)
	var result: Dictionary = TerrainRaymarchSystem.intersect_ray(
		from, dir, heights, 64, Vector3.ZERO
	)
	if result.pos == Vector3.INF:
		return "expected hit"
	# Normal Y component should dominate (close to 1.0) on a flat surface.
	if result.normal.y < 0.9:
		return "expected flat normal.y > 0.9, got %s" % str(result.normal)
	return ""


func _test_transform_world() -> String:
	# TKT-014 #2: a ROTATED + translated terrain. A straight-down WORLD ray must
	# still hit, and the hit mapped back to local must lie on the surface (y≈0)
	# inside the grid — proving the pick respects the node transform, like the
	# render shader's MODEL_MATRIX does.
	var heights := _make_flat_terrain(64, 0.0)
	var xform := Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3(10, 5, 20))
	var local_surface := Vector3(32, 0, 16)
	var world_pt: Vector3 = xform * local_surface
	var from := Vector3(world_pt.x, world_pt.y + 50.0, world_pt.z)
	var dir := Vector3(0, -1, 0)
	var result: Dictionary = TerrainRaymarchSystem.intersect_ray_world(
		from, dir, heights, 64, xform
	)
	if result.pos == Vector3.INF:
		return "transformed terrain: expected hit, got INF"
	var local_hit: Vector3 = xform.affine_inverse() * result.pos
	if absf(local_hit.y) > 1.5:
		return "transformed hit local.y expected ~0, got %f" % local_hit.y
	if local_hit.x < 0 or local_hit.x >= 64 or local_hit.z < 0 or local_hit.z >= 64:
		return "transformed hit local (%f,%f) outside grid" % [local_hit.x, local_hit.z]
	# Y-rotation keeps up as +Y, so the world normal should still point up.
	if result.normal.y < 0.9:
		return "transformed flat normal.y expected >0.9, got %f" % result.normal.y
	return ""


func _test_at_surface_start() -> String:
	# TKT-014 #6: ray origin sits EXACTLY on the surface (y == height), pointing
	# down. The >= seed must count it as "above" so the crossing registers.
	var heights := _make_flat_terrain(64, 7.0)
	var from := Vector3(32, 7.0, 32)
	var dir := Vector3(0, -1, 0)
	var result: Dictionary = TerrainRaymarchSystem.intersect_ray(
		from, dir, heights, 64, Vector3.ZERO
	)
	if result.pos == Vector3.INF:
		return "ray starting exactly on surface should hit, got INF"
	if absf(result.pos.y - 7.0) > 1.5:
		return "expected hit y~7.0, got %f" % result.pos.y
	return ""
