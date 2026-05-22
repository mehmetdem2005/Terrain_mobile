@tool
extends SceneTree

# TKT-003 Phase A.2: HeightmapIO extraction regression test.
#
# Locks the bulk-byte conversion contract: a Texture2D in (any format)
# becomes a row-major PackedFloat32Array of heights scaled by max_height.
# If a future refactor reverts to the per-pixel get_pixel path it would
# silently re-introduce the 30-50x slowdown on mobile imports — this
# test won't catch a perf regression directly, but the size + scaling
# assertions catch any algorithmic break.

const HeightmapIOScript := preload("res://addons/mobile_terrain/systems/heightmap_io.gd")

func _init() -> void:
	var failures: Array[String] = []
	_run("null_texture_returns_empty", _test_null_texture, failures)
	_run("zero_target_size_returns_empty", _test_zero_size, failures)
	_run("flat_image_uniform_heights", _test_flat_uniform, failures)
	_run("red_gradient_scales_correctly", _test_gradient, failures)
	_run("max_height_scales_output", _test_max_height_scaling, failures)
	_run("resizes_to_target_size", _test_resize, failures)
	_run("output_size_is_target_squared", _test_output_size, failures)
	_run("h6_source_not_mutated_on_fast_path", _test_h6_source_safety, failures)

	if failures.is_empty():
		print("HEIGHTMAP_IO_TEST_OK")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: " + f)
		print("HEIGHTMAP_IO_TEST_FAILED count=%d" % failures.size())
		quit(1)

func _run(name: String, fn: Callable, failures: Array[String]) -> void:
	var err: String = fn.call()
	if err != "":
		failures.append("%s — %s" % [name, err])
	else:
		print("OK  %s" % name)

func _make_red_texture(size: int, red_value: int) -> ImageTexture:
	# Build a square RGBA8 image where every pixel's R channel = red_value
	# (0..255). G/B/A are 0. This is the shape _import_exr expects.
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var c := Color(float(red_value) / 255.0, 0.0, 0.0, 1.0)
	for y in range(size):
		for x in range(size):
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func _test_null_texture() -> String:
	var result: PackedFloat32Array = HeightmapIOScript.convert_texture_to_heights(null, 32, 10.0)
	if not result.is_empty():
		return "null texture must return empty array, got size %d" % result.size()
	return ""

func _test_zero_size() -> String:
	var tex := _make_red_texture(16, 128)
	var result: PackedFloat32Array = HeightmapIOScript.convert_texture_to_heights(tex, 0, 10.0)
	if not result.is_empty():
		return "target_size=0 must return empty array, got size %d" % result.size()
	return ""

func _test_flat_uniform() -> String:
	# Uniform red=128 → all heights should be ~50% of max_height.
	var tex := _make_red_texture(16, 128)
	var result: PackedFloat32Array = HeightmapIOScript.convert_texture_to_heights(tex, 16, 10.0)
	if result.size() != 256:
		return "expected 256 heights for 16x16, got %d" % result.size()
	var expected: float = 128.0 / 255.0 * 10.0  # ~5.02
	for h in result:
		if absf(h - expected) > 0.05:
			return "uniform 128/255 expected ~%f, got %f" % [expected, h]
	return ""

func _test_gradient() -> String:
	# Build a 4x4 with a horizontal red gradient: column 0..3 maps to 0,85,170,255.
	var img := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	var reds: Array[int] = [0, 85, 170, 255]
	for y in range(4):
		for x in range(4):
			img.set_pixel(x, y, Color(float(reds[x]) / 255.0, 0.0, 0.0, 1.0))
	var tex := ImageTexture.create_from_image(img)
	var result: PackedFloat32Array = HeightmapIOScript.convert_texture_to_heights(tex, 4, 1.0)
	if result.size() != 16:
		return "expected 16 heights, got %d" % result.size()
	# Row 0: heights[0..3] should be ~0, ~0.33, ~0.67, ~1.0.
	var expected: Array = [0.0, 85.0/255.0, 170.0/255.0, 1.0]
	for x in range(4):
		if absf(result[x] - expected[x]) > 0.02:
			return "row 0 col %d: expected %f, got %f" % [x, expected[x], result[x]]
	return ""

func _test_max_height_scaling() -> String:
	# Same red=255 image, different max_heights. Output must scale linearly.
	var tex := _make_red_texture(4, 255)
	var r1: PackedFloat32Array = HeightmapIOScript.convert_texture_to_heights(tex, 4, 10.0)
	var r2: PackedFloat32Array = HeightmapIOScript.convert_texture_to_heights(tex, 4, 100.0)
	if absf(r1[0] - 10.0) > 0.1:
		return "max_height=10 with red=255 expected ~10.0, got %f" % r1[0]
	if absf(r2[0] - 100.0) > 0.5:
		return "max_height=100 with red=255 expected ~100.0, got %f" % r2[0]
	return ""

func _test_resize() -> String:
	# Source 32x32, target 16x16 — bilinear resize halves resolution.
	# Size assertion is enough; bilinear math is Godot's responsibility.
	var tex := _make_red_texture(32, 100)
	var result: PackedFloat32Array = HeightmapIOScript.convert_texture_to_heights(tex, 16, 5.0)
	if result.size() != 256:
		return "32->16 resize: expected 256 heights, got %d" % result.size()
	# Bilinear of uniform input stays uniform — every cell should match.
	var expected: float = 100.0 / 255.0 * 5.0  # ~1.96
	if absf(result[0] - expected) > 0.05:
		return "resized uniform should preserve value ~%f, got %f" % [expected, result[0]]
	return ""

func _test_output_size() -> String:
	# Output is always target_size² regardless of source dimensions.
	var tex := _make_red_texture(8, 50)
	for target in [4, 8, 32, 64]:
		var result: PackedFloat32Array = HeightmapIOScript.convert_texture_to_heights(tex, target, 1.0)
		var expected: int = target * target
		if result.size() != expected:
			return "target_size=%d: expected %d, got %d" % [target, expected, result.size()]
	return ""

func _test_h6_source_safety() -> String:
	# TKT-004 H6: on the no-mutation fast path (source already target-size,
	# RGBA8, uncompressed) the duplicate is skipped and we read the shared
	# image directly. That read MUST NOT corrupt the source — a regression
	# that mutates in place (decompress/resize/convert without duplicating)
	# would change the bytes here. _make_red_texture produces exactly that
	# fast-path shape (RGBA8, square), so target == source size hits it.
	var tex := _make_red_texture(8, 200)
	var before: PackedByteArray = tex.get_image().get_data()
	var result: PackedFloat32Array = HeightmapIOScript.convert_texture_to_heights(tex, 8, 10.0)
	var after: PackedByteArray = tex.get_image().get_data()
	if before != after:
		return "source image must not be mutated on the no-duplicate fast path"
	# And the result must still be correct (red=200 -> 200/255 * 10).
	var expected: float = 200.0 / 255.0 * 10.0
	if absf(result[0] - expected) > 0.05:
		return "fast-path heights wrong: expected ~%f, got %f" % [expected, result[0]]
	return ""
