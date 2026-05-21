@tool
extends SceneTree

# TKT-003 Phase A.3: FoliageSystem extraction regression test.
#
# Locks the orientation-transform and disc-sampling math previously
# duplicated inline in node.gd. compute_orientation_transform was
# written twice (single-instance vs scatter) — both paths now share
# the extracted helper, so any regression on rotation/scale/origin
# semantics fails here once.

const FoliageSystemScript := preload("res://addons/mobile_terrain/systems/foliage_system.gd")

func _init() -> void:
	var failures: Array[String] = []
	_run("transform_origin_matches_pos", _test_origin, failures)
	_run("transform_basis_orthogonal", _test_basis_orthogonal, failures)
	_run("transform_up_aligns_with_normal", _test_up_alignment, failures)
	_run("transform_scale_in_range", _test_scale_range, failures)
	_run("transform_handles_zero_normal", _test_zero_normal, failures)
	_run("transform_vertical_cliff_normal", _test_vertical_normal, failures)
	_run("sample_disc_returns_within_radius", _test_disc_radius, failures)
	_run("sample_disc_respects_min_spacing", _test_disc_spacing, failures)
	_run("sample_disc_zero_count_returns_empty", _test_disc_zero_count, failures)
	_run("sample_disc_invalid_callable_returns_empty", _test_disc_no_callable, failures)
	_run("sample_disc_calls_height_lookup", _test_disc_height_lookup, failures)

	if failures.is_empty():
		print("FOLIAGE_SYSTEM_TEST_OK")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: " + f)
		print("FOLIAGE_SYSTEM_TEST_FAILED count=%d" % failures.size())
		quit(1)

func _run(name: String, fn: Callable, failures: Array[String]) -> void:
	var err: String = fn.call()
	if err != "":
		failures.append("%s — %s" % [name, err])
	else:
		print("OK  %s" % name)

func _test_origin() -> String:
	var pos := Vector3(10.5, 7.2, -3.1)
	var tf: Transform3D = FoliageSystemScript.compute_orientation_transform(pos, Vector3.UP)
	if tf.origin.distance_to(pos) > 0.0001:
		return "origin must equal pos, got %s vs %s" % [str(tf.origin), str(pos)]
	return ""

func _test_basis_orthogonal() -> String:
	# Run several times to cover the random rotation cases.
	for i in range(10):
		var tf: Transform3D = FoliageSystemScript.compute_orientation_transform(Vector3.ZERO, Vector3.UP)
		var x: Vector3 = tf.basis.x.normalized()
		var y: Vector3 = tf.basis.y.normalized()
		var z: Vector3 = tf.basis.z.normalized()
		if absf(x.dot(y)) > 0.01:
			return "basis x.y dot = %f (should be 0)" % x.dot(y)
		if absf(x.dot(z)) > 0.01:
			return "basis x.z dot = %f (should be 0)" % x.dot(z)
		if absf(y.dot(z)) > 0.01:
			return "basis y.z dot = %f (should be 0)" % y.dot(z)
	return ""

func _test_up_alignment() -> String:
	# When normal is Vector3.UP, the rotated basis Y should still be along UP
	# (rotation around UP doesn't change Y).
	var tf: Transform3D = FoliageSystemScript.compute_orientation_transform(Vector3.ZERO, Vector3.UP)
	var y: Vector3 = tf.basis.y.normalized()
	if y.dot(Vector3.UP) < 0.99:
		return "basis y should align with UP, got %s" % str(y)
	return ""

func _test_scale_range() -> String:
	# Scale is uniformly sampled from [0.8, 1.2]; basis vectors lengths should
	# fall in that range across many samples.
	for i in range(20):
		var tf: Transform3D = FoliageSystemScript.compute_orientation_transform(Vector3.ZERO, Vector3.UP)
		var scale: float = tf.basis.x.length()
		if scale < 0.79 or scale > 1.21:
			return "scale %f out of [0.8, 1.2]" % scale
	return ""

func _test_zero_normal() -> String:
	# Degenerate input: zero-length normal must not crash; we fall back to UP.
	var tf: Transform3D = FoliageSystemScript.compute_orientation_transform(Vector3.ZERO, Vector3.ZERO)
	if tf.origin != Vector3.ZERO:
		return "origin should still be at pos for zero normal"
	# Basis Y should be UP (fallback path).
	var y: Vector3 = tf.basis.y.normalized()
	if y.dot(Vector3.UP) < 0.99:
		return "zero-normal fallback should orient up, got y=%s" % str(y)
	return ""

func _test_vertical_normal() -> String:
	# Near-vertical normal: Vector3.UP × normal is degenerate, fallback to
	# Vector3.RIGHT × normal. Basis must remain orthogonal.
	var tf: Transform3D = FoliageSystemScript.compute_orientation_transform(Vector3.ZERO, Vector3(0.0001, 0.0, 1.0).normalized())
	var x: Vector3 = tf.basis.x.normalized()
	var y: Vector3 = tf.basis.y.normalized()
	if absf(x.dot(y)) > 0.01:
		return "cliff normal: basis became non-orthogonal, x.y=%f" % x.dot(y)
	return ""

func _test_disc_radius() -> String:
	# All accepted positions must be within `radius` of the centre.
	var centre := Vector3(50, 0, 50)
	var radius: float = 5.0
	var lookup: Callable = func(_x: float, _z: float) -> float: return 0.0
	var positions: Array[Vector3] = FoliageSystemScript.sample_disc_with_spacing(centre, radius, 20, 0.0, lookup)
	for p in positions:
		var horizontal := Vector2(p.x - centre.x, p.z - centre.z)
		if horizontal.length() > radius + 0.001:
			return "position %s outside radius %f" % [str(p), radius]
	return ""

func _test_disc_spacing() -> String:
	# Min-spacing rejection: all pairs must be at least min_spacing apart.
	var centre := Vector3.ZERO
	var min_spacing: float = 2.0
	var lookup: Callable = func(_x: float, _z: float) -> float: return 0.0
	var positions: Array[Vector3] = FoliageSystemScript.sample_disc_with_spacing(centre, 10.0, 8, min_spacing, lookup)
	for i in range(positions.size()):
		for j in range(i + 1, positions.size()):
			var d: float = positions[i].distance_to(positions[j])
			if d < min_spacing - 0.0001:
				return "positions %d and %d too close: d=%f < %f" % [i, j, d, min_spacing]
	return ""

func _test_disc_zero_count() -> String:
	var lookup: Callable = func(_x: float, _z: float) -> float: return 0.0
	var positions: Array[Vector3] = FoliageSystemScript.sample_disc_with_spacing(Vector3.ZERO, 10.0, 0, 0.0, lookup)
	if not positions.is_empty():
		return "count=0 must return empty array, got %d" % positions.size()
	return ""

func _test_disc_no_callable() -> String:
	# Invalid Callable → return empty without crashing.
	var positions: Array[Vector3] = FoliageSystemScript.sample_disc_with_spacing(Vector3.ZERO, 10.0, 5, 0.0, Callable())
	if not positions.is_empty():
		return "invalid Callable must return empty, got %d" % positions.size()
	return ""

func _test_disc_height_lookup() -> String:
	# The Y of each sample should come from the height_lookup callable.
	var call_count := [0]
	var lookup: Callable = func(_x: float, _z: float) -> float:
		call_count[0] += 1
		return 42.0
	var positions: Array[Vector3] = FoliageSystemScript.sample_disc_with_spacing(Vector3.ZERO, 10.0, 5, 0.0, lookup)
	if positions.is_empty():
		return "expected at least one accepted position"
	if call_count[0] == 0:
		return "height_lookup was never called"
	for p in positions:
		if absf(p.y - 42.0) > 0.001:
			return "expected y=42 from lookup, got %f" % p.y
	return ""
