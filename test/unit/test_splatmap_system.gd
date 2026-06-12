@tool
extends SceneTree

# TKT-003 Phase A.1: SplatmapSystem extraction regression test.
#
# Locks the competitive-blend semantics that were previously buried
# in mobile_terrain_node.gd._paint_splatmap. If a future refactor breaks
# the blend math (channel sum normalisation, slot routing, falloff
# multiplication) this test fails before the regression ships.

const SplatmapSystemScript := preload("res://addons/mobile_terrain/systems/splatmap_system.gd")
const BrushSystemScript := preload("res://addons/mobile_terrain/systems/brush_system.gd")

const MAP_SIZE := 32

func _init() -> void:
	var failures: Array[String] = []
	_run("paint_boosts_target_slot", _test_paint_boosts_slot, failures)
	_run("paint_other_slots_shrink", _test_other_slots_shrink, failures)
	_run("paint_slot_out_of_range_returns_false", _test_slot_oob, failures)
	_run("paint_size_mismatch_returns_false", _test_size_mismatch, failures)
	_run("paint_null_image_returns_false", _test_null_image, failures)
	_run("paint_null_brush_returns_false", _test_null_brush, failures)
	_run("paint_all_four_slots_routable", _test_all_slots, failures)
	_run("paint_full_strength_boosts_to_one", _test_full_strength, failures)
	_run("paint_outside_radius_unchanged", _test_outside_radius, failures)
	_run("opaque_single_dab_full_coverage", _test_opaque_full_coverage, failures)
	_run("opaque_edge_keeps_falloff_feather", _test_opaque_edge_feather, failures)

	if failures.is_empty():
		print("SPLATMAP_SYSTEM_TEST_OK")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: " + f)
		print("SPLATMAP_SYSTEM_TEST_FAILED count=%d" % failures.size())
		quit(1)

func _run(name: String, fn: Callable, failures: Array[String]) -> void:
	var err: String = fn.call()
	if err != "":
		failures.append("%s — %s" % [name, err])
	else:
		print("OK  %s" % name)

# Build a 32x32 image with initial channel layout (R=1, G=0, B=0, A=0).
func _make_initial_splatmap() -> Image:
	var img := Image.create_empty(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGBA8)
	for y in range(MAP_SIZE):
		for x in range(MAP_SIZE):
			img.set_pixel(x, y, Color(1.0, 0.0, 0.0, 0.0))
	return img

func _make_brush() -> BrushSystem:
	# No mask, soft circle (shape=0). Pure falloff curve.
	return BrushSystemScript.new(MAP_SIZE, null, null, 0, null)

func _test_paint_boosts_slot() -> String:
	var img := _make_initial_splatmap()
	var brush := _make_brush()
	var ok: bool = SplatmapSystemScript.paint(img, MAP_SIZE, 16.0, 16.0, 4.0, 1.0, 1, brush)
	if not ok:
		return "paint returned false on valid inputs"
	var centre: Color = img.get_pixel(16, 16)
	# At centre with strength=1, slot 1 (G) should jump from 0 to ~1.
	if centre.g < 0.5:
		return "centre G channel should rise above 0.5 after paint, got %f" % centre.g
	return ""

func _test_other_slots_shrink() -> String:
	var img := _make_initial_splatmap()
	var brush := _make_brush()
	SplatmapSystemScript.paint(img, MAP_SIZE, 16.0, 16.0, 4.0, 1.0, 1, brush)
	var centre: Color = img.get_pixel(16, 16)
	# Slot 0 (R) was 1.0; competitive blend should shrink it toward 0.
	if centre.r > 0.5:
		return "centre R should shrink below 0.5 after slot 1 paint, got %f" % centre.r
	return ""

func _test_slot_oob() -> String:
	var img := _make_initial_splatmap()
	var brush := _make_brush()
	if SplatmapSystemScript.paint(img, MAP_SIZE, 16.0, 16.0, 4.0, 1.0, 4, brush):
		return "slot=4 should be rejected (RGBA8 has 4 channels, indices 0-3)"
	if SplatmapSystemScript.paint(img, MAP_SIZE, 16.0, 16.0, 4.0, 1.0, -1, brush):
		return "slot=-1 should be rejected"
	return ""

func _test_size_mismatch() -> String:
	var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	var brush := _make_brush()
	if SplatmapSystemScript.paint(img, MAP_SIZE, 8.0, 8.0, 4.0, 1.0, 0, brush):
		return "16x16 image with map_size=32 should be rejected"
	return ""

func _test_null_image() -> String:
	var brush := _make_brush()
	if SplatmapSystemScript.paint(null, MAP_SIZE, 16.0, 16.0, 4.0, 1.0, 0, brush):
		return "null image should be rejected"
	return ""

func _test_null_brush() -> String:
	var img := _make_initial_splatmap()
	if SplatmapSystemScript.paint(img, MAP_SIZE, 16.0, 16.0, 4.0, 1.0, 0, null):
		return "null brush should be rejected"
	return ""

func _test_all_slots() -> String:
	# Paint into each of the 4 slots; verify the corresponding channel rises.
	var brush := _make_brush()
	var channel_names := ["R", "G", "B", "A"]
	for slot in range(4):
		var img := _make_initial_splatmap()
		# Slot 0 starts at 1.0, so paint slot 0 too as a sanity check.
		SplatmapSystemScript.paint(img, MAP_SIZE, 16.0, 16.0, 4.0, 1.0, slot, brush)
		var centre: Color = img.get_pixel(16, 16)
		var channel_value: float = 0.0
		match slot:
			0: channel_value = centre.r
			1: channel_value = centre.g
			2: channel_value = centre.b
			3: channel_value = centre.a
		if channel_value < 0.5:
			return "slot %d (%s) failed to rise above 0.5, got %f" % [slot, channel_names[slot], channel_value]
	return ""

func _test_full_strength() -> String:
	# At centre of brush with strength=1.0 and falloff=1.0, blend_factor = 1.0,
	# so the target channel should be ~1.0 and all others ~0.0.
	var img := _make_initial_splatmap()
	var brush := _make_brush()
	SplatmapSystemScript.paint(img, MAP_SIZE, 16.0, 16.0, 4.0, 1.0, 2, brush)
	var centre: Color = img.get_pixel(16, 16)
	if centre.b < 0.9:
		return "full-strength slot 2 centre B should be ~1.0, got %f" % centre.b
	if centre.r > 0.1 or centre.g > 0.1 or centre.a > 0.1:
		return "non-target channels should be ~0 at full strength, got (R=%f, G=%f, A=%f)" % [centre.r, centre.g, centre.a]
	return ""

func _test_opaque_full_coverage() -> String:
	# TKT-020 F2 (Dolgu): with opaque=true the blend is falloff alone —
	# strength must be IGNORED. A hard brush (shape=1, falloff=1 across the
	# footprint) with a deliberately tiny strength must still paint the
	# centre to full coverage in ONE dab. Under the old soft semantics this
	# dab would have moved G by only ~0.05.
	var img := _make_initial_splatmap()
	var hard_brush := BrushSystemScript.new(MAP_SIZE, null, null, 1, null)
	var ok: bool = SplatmapSystemScript.paint(
		img, MAP_SIZE, 16.0, 16.0, 4.0, 0.05, 1, hard_brush, true
	)
	if not ok:
		return "opaque paint returned false on valid inputs"
	var centre: Color = img.get_pixel(16, 16)
	if centre.g < 0.99:
		return "opaque centre G should be ~1.0 in one dab regardless of strength, got %f" % centre.g
	if centre.r > 0.01:
		return "opaque centre R should be wiped to ~0, got %f" % centre.r
	return ""


func _test_opaque_edge_feather() -> String:
	# TKT-020 F2: opaque is NOT aliased — a soft-falloff brush still
	# feathers the footprint edge (blend = falloff there), it only
	# guarantees the core reaches full coverage.
	var img := _make_initial_splatmap()
	var soft_brush := _make_brush()  # shape 0, smoothstep falloff
	SplatmapSystemScript.paint(img, MAP_SIZE, 16.0, 16.0, 4.0, 1.0, 1, soft_brush, true)
	# (19, 16) is 3 cells out on a radius of 4 → falloff strictly between
	# 0 and 1 → partial blend.
	var edge: Color = img.get_pixel(19, 16)
	if edge.g <= 0.01 or edge.g >= 0.95:
		return "opaque edge G should be a partial feather (0 < g < 0.95), got %f" % edge.g
	var centre: Color = img.get_pixel(16, 16)
	if centre.g < 0.99:
		return "opaque centre with soft brush should still reach ~1.0, got %f" % centre.g
	return ""


func _test_outside_radius() -> String:
	# Pixels well outside the brush radius should not be touched.
	var img := _make_initial_splatmap()
	var brush := _make_brush()
	SplatmapSystemScript.paint(img, MAP_SIZE, 16.0, 16.0, 4.0, 1.0, 1, brush)
	# Pixel at (0, 0) is ~22 units away from (16, 16) — well outside r=4.
	var far: Color = img.get_pixel(0, 0)
	if absf(far.r - 1.0) > 0.001 or far.g > 0.001:
		return "pixel outside brush radius was modified: %s" % str(far)
	return ""
