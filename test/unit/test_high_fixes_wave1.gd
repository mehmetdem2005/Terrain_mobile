@tool
extends SceneTree

# TKT-004 Wave 1 regression tests:
#   H5 — brush mask falloff LUT (perf): the baked PackedFloat32Array must
#        return exactly what the old per-pixel get_pixel() path did, the
#        C4 zero-dim guard must survive, and no-mask falls back to shape.
#   H8 — current_paint_slot setter clamps to [0, 3] (RGBA slot count).

const BrushSystem := preload("res://addons/mobile_terrain/systems/brush_system.gd")
const TerrainNode := preload("res://addons/mobile_terrain/mobile_terrain_node.gd")


func _init() -> void:
	var failures: Array[String] = []
	_run("h5_lut_matches_get_pixel", _test_lut_matches_get_pixel, failures)
	_run("h5_lut_center_value", _test_lut_center_value, failures)
	_run("h5_zero_dim_mask_returns_one", _test_zero_dim_guard, failures)
	_run("h5_no_mask_uses_shape_falloff", _test_no_mask_fallback, failures)
	_run("h8_paint_slot_clamps_high", _test_slot_clamp_high, failures)
	_run("h8_paint_slot_clamps_low", _test_slot_clamp_low, failures)
	_run("h8_paint_slot_valid_unchanged", _test_slot_valid, failures)

	if failures.is_empty():
		print("HIGH_WAVE1_TEST_OK")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: " + f)
		print("HIGH_WAVE1_TEST_FAILED count=%d" % failures.size())
		quit(1)


func _run(name: String, fn: Callable, failures: Array[String]) -> void:
	var err: String = fn.call()
	if err != "":
		failures.append("%s — %s" % [name, err])
	else:
		print("OK  %s" % name)


# 8x8 ramp mask: red channel = (x + y*8) / 63.0 — every pixel distinct so
# any LUT indexing error is detectable.
func _make_ramp_mask() -> Array:
	var w := 8
	var h := 8
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var r := float(x + y * w) / 63.0
			img.set_pixel(x, y, Color(r, 0.0, 0.0, 1.0))
	var tex := ImageTexture.create_from_image(img)
	return [tex, img]


func _test_lut_matches_get_pixel() -> String:
	var m := _make_ramp_mask()
	var bs: BrushSystem = BrushSystem.new(64, m[0], m[1], 0, null)
	var img: Image = m[1]
	# Sample many footprint positions; LUT result must equal what direct
	# get_pixel() would have produced at the same computed (ix, iy).
	var center := Vector2(50, 50)
	var radius := 16.0
	for dy in range(-15, 16, 3):
		for dx in range(-15, 16, 3):
			var px := center + Vector2(dx, dy)
			var got := bs.falloff_at(px, center, radius)
			# Reproduce the old indexing to get the expected pixel.
			var u: float = (px.x - center.x) / radius * 0.5 + 0.5
			var v: float = (px.y - center.y) / radius * 0.5 + 0.5
			var ix: int = clampi(int(u * 8), 0, 7)
			var iy: int = clampi(int(v * 8), 0, 7)
			var expected := img.get_pixel(ix, iy).r
			if absf(got - expected) > 0.0001:
				return "LUT mismatch at px=%s: got %f, expected %f" % [str(px), got, expected]
	return ""


func _test_lut_center_value() -> String:
	var m := _make_ramp_mask()
	var bs: BrushSystem = BrushSystem.new(64, m[0], m[1], 0, null)
	var img: Image = m[1]
	# Center maps to u=v=0.5 -> ix=iy=4. Expected is the 8-bit-quantized
	# stored pixel, not the raw float we wrote (RGBA8 rounds on set_pixel).
	var got := bs.falloff_at(Vector2(50, 50), Vector2(50, 50), 16.0)
	var expected := img.get_pixel(4, 4).r
	if absf(got - expected) > 0.0001:
		return "center falloff got %f, expected %f" % [got, expected]
	return ""


func _test_zero_dim_guard() -> String:
	# C4: a mask Texture assigned but image is zero-dim must yield 1.0,
	# not crash and not fall through to shape falloff.
	var empty_img := Image.new()  # 0x0
	var tex := PlaceholderTexture2D.new()
	var bs: BrushSystem = BrushSystem.new(64, tex, empty_img, 0, null)
	var got := bs.falloff_at(Vector2(10, 10), Vector2(10, 10), 8.0)
	if absf(got - 1.0) > 0.0001:
		return "zero-dim mask should return 1.0, got %f" % got
	return ""


func _test_no_mask_fallback() -> String:
	# No mask -> shape falloff. Shape 1 (hard) returns 1.0 everywhere inside.
	var bs: BrushSystem = BrushSystem.new(64, null, null, 1, null)
	var got := bs.falloff_at(Vector2(12, 10), Vector2(10, 10), 8.0)
	if absf(got - 1.0) > 0.0001:
		return "hard-shape falloff should be 1.0, got %f" % got
	return ""


func _test_slot_clamp_high() -> String:
	var node: Node3D = TerrainNode.new()
	node.current_paint_slot = 5
	var v: int = node.current_paint_slot
	node.free()
	if v != 3:
		return "paint_slot=5 should clamp to 3, got %d" % v
	return ""


func _test_slot_clamp_low() -> String:
	var node: Node3D = TerrainNode.new()
	node.current_paint_slot = -2
	var v: int = node.current_paint_slot
	node.free()
	if v != 0:
		return "paint_slot=-2 should clamp to 0, got %d" % v
	return ""


func _test_slot_valid() -> String:
	var node: Node3D = TerrainNode.new()
	node.current_paint_slot = 2
	var v: int = node.current_paint_slot
	node.free()
	if v != 2:
		return "paint_slot=2 should stay 2, got %d" % v
	return ""
