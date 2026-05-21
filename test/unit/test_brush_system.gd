@tool
extends SceneTree

# TKT-002 C4 regression test.
#
# Locks the contract for BrushSystem.falloff_at degenerate-input handling:
#   - Zero-width or zero-height mask image → return 1.0 (treat as full strength)
#   - Zero or negative radius → return 0.0 (degenerate brush)
#   - Normal mask → returns the sampled red channel
#
# Without these guards, a falloff call with a 0x0 mask image triggers
# clampi(int(u * 0), 0, -1) — undefined behaviour — and the subsequent
# get_pixel(-1, ...) crashes the editor on the first paint dab.

const BrushSystemScript := preload("res://addons/mobile_terrain/systems/brush_system.gd")

func _init() -> void:
	var failures: Array[String] = []
	_run("zero_dim_image_returns_one", _test_zero_dim_image, failures)
	_run("zero_radius_returns_zero", _test_zero_radius, failures)
	_run("negative_radius_returns_zero", _test_negative_radius, failures)
	_run("normal_mask_returns_pixel_r", _test_normal_mask_sample, failures)
	_run("legacy_circle_falloff", _test_legacy_circle_falloff, failures)
	_run("iterate_footprint_calls_callback", _test_iterate_callback, failures)

	if failures.is_empty():
		print("BRUSH_SYSTEM_TEST_OK")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: " + f)
		print("BRUSH_SYSTEM_TEST_FAILED count=%d" % failures.size())
		quit(1)

func _run(name: String, fn: Callable, failures: Array[String]) -> void:
	var err: String = fn.call()
	if err != "":
		failures.append("%s — %s" % [name, err])
	else:
		print("OK  %s" % name)

# A default-constructed Image is 0x0; assigning it to a BrushSystem
# simulates the post-decompress-failure path that crashed the editor
# before C4 landed.
func _test_zero_dim_image() -> String:
	var img := Image.new()
	if img.get_width() != 0 or img.get_height() != 0:
		return "test setup: default Image should be 0x0"
	var mask_tex := ImageTexture.new()
	var brush: BrushSystemScript = BrushSystemScript.new(64, mask_tex, img, 0, null)
	var f: float = brush.falloff_at(Vector2(10, 10), Vector2(10, 10), 5.0)
	if absf(f - 1.0) > 0.001:
		return "zero-dim mask must return 1.0 (full strength fallback), got %f" % f
	return ""

func _test_zero_radius() -> String:
	var img := _make_1x1_mask(1.0)
	var mask_tex := ImageTexture.create_from_image(img)
	var brush: BrushSystemScript = BrushSystemScript.new(64, mask_tex, img, 0, null)
	var f: float = brush.falloff_at(Vector2(5, 5), Vector2(5, 5), 0.0)
	if absf(f - 0.0) > 0.001:
		return "radius=0 must return 0.0 (degenerate brush), got %f" % f
	return ""

func _test_negative_radius() -> String:
	var img := _make_1x1_mask(0.5)
	var mask_tex := ImageTexture.create_from_image(img)
	var brush: BrushSystemScript = BrushSystemScript.new(64, mask_tex, img, 0, null)
	var f: float = brush.falloff_at(Vector2(5, 5), Vector2(5, 5), -3.0)
	if absf(f - 0.0) > 0.001:
		return "radius<0 must return 0.0, got %f" % f
	return ""

func _test_normal_mask_sample() -> String:
	# 4x4 mask with red=0.5 everywhere. Sampling the centre should return
	# ~0.5 (allowing a small tolerance because the lookup quantises to a
	# discrete pixel index).
	var img := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	for y in range(4):
		for x in range(4):
			img.set_pixel(x, y, Color(0.5, 0.0, 0.0, 1.0))
	var mask_tex := ImageTexture.create_from_image(img)
	var brush: BrushSystemScript = BrushSystemScript.new(64, mask_tex, img, 0, null)
	var f: float = brush.falloff_at(Vector2(10, 10), Vector2(10, 10), 5.0)
	if absf(f - 0.5) > 0.05:
		return "normal mask centre must sample ~0.5, got %f" % f
	return ""

func _test_legacy_circle_falloff() -> String:
	# No mask → falls through to legacy shape branches.
	# Soft circle (shape=0) at centre should return ~1.0; at the edge ~0.0.
	var brush: BrushSystemScript = BrushSystemScript.new(64, null, null, 0, null)
	var centre: float = brush.falloff_at(Vector2(10, 10), Vector2(10, 10), 5.0)
	if centre < 0.95:
		return "soft circle centre must be ~1.0, got %f" % centre
	var edge: float = brush.falloff_at(Vector2(15, 10), Vector2(10, 10), 5.0)
	if edge > 0.1:
		return "soft circle edge must be ~0.0, got %f" % edge
	return ""

func _test_iterate_callback() -> String:
	# Iterating a 3-unit radius brush from (10,10) on a 32x32 grid should
	# visit a roughly disc-shaped region. We just count visits — exact
	# shape is validated by the legacy_circle test above.
	# Wrap the counter in an Array so the lambda can mutate it by-reference;
	# GDScript closures capture int by-value, so a plain `var visits := 0`
	# would never increment from inside the callback.
	var brush: BrushSystemScript = BrushSystemScript.new(32, null, null, 0, null)
	var visits := [0]
	var cb := func(_x: int, _z: int, _f: float) -> void:
		visits[0] += 1
	brush.iterate_footprint(10.0, 10.0, 3.0, cb)
	if visits[0] < 5:
		return "iterate_footprint should visit several pixels for r=3, got %d" % visits[0]
	if visits[0] > 100:
		return "iterate_footprint visited too many pixels (loop bounds wrong?), got %d" % visits[0]
	return ""

func _make_1x1_mask(red: float) -> Image:
	var img := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color(red, 0.0, 0.0, 1.0))
	return img
