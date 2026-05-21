@tool
extends SceneTree

# V22 Phase 4 sculpt_ops unit test. Verifies each of the 6 height
# operations via direct calls (no Camera3D, no full terrain node).

const MAP_SIZE := 16

func _init() -> void:
	var failures: Array[String] = []
	_run("modify_increases_center", _test_modify, failures)
	_run("flatten_pulls_to_target", _test_flatten, failures)
	_run("smooth_averages_neighbours", _test_smooth, failures)
	_run("noise_is_deterministic", _test_noise_deterministic, failures)
	_run("terrace_quantises", _test_terrace, failures)
	_run("erode_moves_mass_to_lowest", _test_erode, failures)
	_run("erode_marks_destination_chunk", _test_erode_dual_dirty, failures)
	if failures.is_empty():
		print("SCULPT_OPS_TEST_OK")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: " + f)
		print("SCULPT_OPS_TEST_FAILED count=%d" % failures.size())
		quit(1)

func _run(name: String, fn: Callable, failures: Array[String]) -> void:
	var err: String = fn.call()
	if err != "":
		failures.append("%s — %s" % [name, err])
	else:
		print("OK  %s" % name)

func _flat_terrain(h: float) -> PackedFloat32Array:
	var arr := PackedFloat32Array()
	arr.resize(MAP_SIZE * MAP_SIZE)
	arr.fill(h)
	return arr

func _make_brush() -> BrushSystem:
	var noise := FastNoiseLite.new()
	noise.seed = 42
	# brush_shape=1 (hard, falloff=1 everywhere) makes assertions clean.
	return BrushSystem.new(MAP_SIZE, null, null, 1, noise)

func _no_op_mark(x: int, z: int) -> void:
	pass

func _test_modify() -> String:
	var h := _flat_terrain(0.0)
	var brush := _make_brush()
	SculptOps.modify_height(brush, h, MAP_SIZE, _no_op_mark, 8.0, 8.0, 2.0, 1.0)
	# Hard brush, radius 2, strength 1 → centre should be +1.0.
	var centre: float = h[8 * MAP_SIZE + 8]
	if absf(centre - 1.0) > 0.01:
		return "centre expected +1.0, got %f" % centre
	return ""

func _test_flatten() -> String:
	var h := _flat_terrain(10.0)
	# strength=1, target=0, hard brush → centre should reach ~target.
	var brush := _make_brush()
	SculptOps.flatten_height(brush, h, MAP_SIZE, _no_op_mark, 8.0, 8.0, 2.0, 0.0, 1.0)
	var centre: float = h[8 * MAP_SIZE + 8]
	if absf(centre) > 0.01:
		return "centre expected 0.0, got %f" % centre
	return ""

func _test_smooth() -> String:
	# Spike at centre, smooth pass should reduce it.
	var h := _flat_terrain(0.0)
	h[8 * MAP_SIZE + 8] = 10.0
	var brush := _make_brush()
	var smoothed := SculptOps.smooth_height(brush, h, MAP_SIZE, _no_op_mark, 8.0, 8.0, 3.0, 1.0)
	var centre_before: float = h[8 * MAP_SIZE + 8]
	var centre_after: float = smoothed[8 * MAP_SIZE + 8]
	if centre_after >= centre_before:
		return "smooth should reduce spike: before=%f after=%f" % [centre_before, centre_after]
	return ""

func _test_noise_deterministic() -> String:
	# Two calls on identical input should yield identical output.
	var h1 := _flat_terrain(0.0)
	var h2 := _flat_terrain(0.0)
	var brush := _make_brush()
	SculptOps.noise_height(brush, h1, MAP_SIZE, _no_op_mark, 8.0, 8.0, 3.0, 1.0)
	SculptOps.noise_height(brush, h2, MAP_SIZE, _no_op_mark, 8.0, 8.0, 3.0, 1.0)
	for i in range(MAP_SIZE * MAP_SIZE):
		if h1[i] != h2[i]:
			return "noise non-deterministic at i=%d: %f vs %f" % [i, h1[i], h2[i]]
	# Also: noise must actually do something.
	var changed := 0
	for i in range(MAP_SIZE * MAP_SIZE):
		if h1[i] != 0.0:
			changed += 1
	if changed == 0:
		return "noise didn't change any cell"
	return ""

func _test_terrace() -> String:
	# Heights 0.7 should terrace toward 1.0 (step=max(1, strength*5)=1.0).
	var h := _flat_terrain(0.7)
	var brush := _make_brush()
	SculptOps.terrace_height(brush, h, MAP_SIZE, _no_op_mark, 8.0, 8.0, 2.0, 0.1)
	# After one dab, centre cells should have moved toward round(0.7)=1.0.
	var centre: float = h[8 * MAP_SIZE + 8]
	if centre <= 0.7:
		return "terrace should move toward 1.0, got %f" % centre
	return ""

func _test_erode() -> String:
	# Spike at centre with lower neighbour at +1; erosion moves mass to
	# the lowest neighbour, lowering centre & raising neighbour.
	var h := _flat_terrain(5.0)
	h[8 * MAP_SIZE + 8] = 10.0       # centre high
	h[8 * MAP_SIZE + 9] = 2.0        # east low
	var brush := _make_brush()
	var eroded := SculptOps.erode_height(brush, h, MAP_SIZE, _no_op_mark, 8.0, 8.0, 1.5, 2.0)
	if eroded[8 * MAP_SIZE + 8] >= 10.0:
		return "centre should have lost mass, still %f" % eroded[8 * MAP_SIZE + 8]
	if eroded[8 * MAP_SIZE + 9] <= 2.0:
		return "east neighbour should have gained mass, still %f" % eroded[8 * MAP_SIZE + 9]
	return ""

func _test_erode_dual_dirty() -> String:
	# The destination chunk must get marked dirty too — verify by
	# counting mark_dirty callbacks.
	var h := _flat_terrain(5.0)
	h[8 * MAP_SIZE + 8] = 10.0
	h[8 * MAP_SIZE + 9] = 2.0
	var brush := _make_brush()
	var marks: Dictionary = {}
	var cb := func(x: int, z: int) -> void:
		marks[Vector2i(x, z)] = true
	SculptOps.erode_height(brush, h, MAP_SIZE, cb, 8.0, 8.0, 1.5, 2.0)
	# Centre (8,8) and east neighbour (9,8) both expected.
	if not marks.has(Vector2i(8, 8)):
		return "centre cell not marked dirty"
	if not marks.has(Vector2i(9, 8)):
		return "destination cell (9,8) not marked dirty"
	return ""
