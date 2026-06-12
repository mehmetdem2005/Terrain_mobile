@tool
extends SceneTree

# TKT-019 H1 regression test: the node-level BrushSystem cache.
#
# BrushSystem._init bakes the brush-mask LUT — one get_pixel per mask
# texel (65K calls for the shipped 256² masks). The bug:
# _apply_brush_single and _paint_splatmap constructed a fresh BrushSystem
# per dab, re-baking that LUT at up to 25 Hz while sculpting with any
# mask active. The fix caches one instance on the node and rebuilds only
# when an input the system snapshots changes. These assertions pin the
# cache identity AND every invalidation edge (shape, map_size, mask
# set/clear) so a future refactor can't silently revert to per-dab
# construction or, worse, serve a stale snapshot.

const TerrainScript := preload("res://addons/mobile_terrain/mobile_terrain_node.gd")


func _init() -> void:
	var failures: Array[String] = []
	var t = TerrainScript.new()
	t.chunk_size = 8
	t.map_size = 16

	# Same inputs → same instance (the whole point of the cache).
	var b1 = t._get_brush_system()
	var b2 = t._get_brush_system()
	if b1 == null:
		failures.append("cache returned null")
	if b1 != b2:
		failures.append("same inputs must return the cached instance")

	# brush_shape has no setter — direct writes must still invalidate via
	# the per-call key compare.
	t.brush_shape = 3
	var b3 = t._get_brush_system()
	if b3 == b1:
		failures.append("brush_shape change must rebuild the brush system")
	elif b3.brush_shape != 3:
		failures.append("rebuilt system must snapshot the new shape, got %d" % b3.brush_shape)

	# map_size change (setter path) invalidates.
	t.map_size = 32
	var b4 = t._get_brush_system()
	if b4 == b3:
		failures.append("map_size change must rebuild the brush system")
	elif b4.map_size != 32:
		failures.append("rebuilt system must snapshot the new map_size, got %d" % b4.map_size)

	# brush_mask assignment invalidates AND the rebuilt system bakes a LUT.
	var img := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	var tex := ImageTexture.create_from_image(img)
	t.brush_mask = tex
	var b5 = t._get_brush_system()
	if b5 == b4:
		failures.append("brush_mask change must rebuild the brush system")
	elif b5._mask_w != 4 or b5._mask_h != 4:
		failures.append(
			"rebuilt system must bake the mask LUT (got %dx%d)" % [b5._mask_w, b5._mask_h]
		)

	# Clearing the mask invalidates again and drops the LUT.
	t.brush_mask = null
	var b6 = t._get_brush_system()
	if b6 == b5:
		failures.append("clearing brush_mask must rebuild the brush system")
	elif b6._mask_w != 0:
		failures.append("cleared mask must leave no LUT, got width %d" % b6._mask_w)

	t.free()
	if failures.is_empty():
		print("BRUSH_CACHE_TEST_OK")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: " + f)
		print("BRUSH_CACHE_TEST_FAILED count=%d" % failures.size())
		quit(1)
