@tool
class_name BrushSystem
extends RefCounted

# V22: extracted brush math + footprint iteration.
#
# Owns nothing persistent: the node passes its mask state + noise_gen
# into the constructor and the system exposes pure inspection helpers
# (`is_in_brush`, `falloff_at`) plus a footprint iterator that drives
# each sculpt/paint operation through a Callable.
#
# Why this exists: 6 sculpt ops + 1 paint op all repeated the same
# nested for-loop boilerplate (~80% identical). Extracting the loop +
# the shape/mask sampling into one place collapses ~200 lines of
# duplicate code and makes the brush math unit-testable.

var map_size: int = 0
var brush_mask: Texture2D = null
var brush_mask_image: Image = null
var brush_shape: int = 0
var noise_gen: FastNoiseLite = null

func _init(map_size_: int, brush_mask_: Texture2D, brush_mask_image_: Image, brush_shape_: int, noise_gen_: FastNoiseLite) -> void:
	map_size = map_size_
	brush_mask = brush_mask_
	brush_mask_image = brush_mask_image_
	brush_shape = brush_shape_
	noise_gen = noise_gen_

# Whether (px) falls inside the brush footprint. Mask-based brushes
# treat the inscribed circle as the bound and let the mask itself
# zero-out the corners. Legacy shapes keep their original geometry.
func is_in_brush(px: Vector2, center: Vector2, radius: float) -> bool:
	if brush_mask != null and brush_mask_image != null:
		return px.distance_to(center) <= radius
	match brush_shape:
		2:  # square
			var dx := absf(px.x - center.x)
			var dy := absf(px.y - center.y)
			return dx <= radius and dy <= radius
		3:  # diamond
			var dx := absf(px.x - center.x)
			var dy := absf(px.y - center.y)
			return (dx + dy) <= radius
		_:  # circle or noise
			return px.distance_to(center) <= radius

# Per-pixel brush strength multiplier (0..1).
func falloff_at(px: Vector2, center: Vector2, radius: float) -> float:
	if brush_mask != null and brush_mask_image != null:
		# V23 GUARD (TKT-002 C4): a brush_mask Texture2D can be assigned
		# while its CPU-side Image has zero dimensions — e.g. when
		# Image.decompress() silently failed during _set_brush_mask, or
		# when an importer hasn't finished yet. Without this guard,
		# clampi(int(u * 0), 0, -1) produces undefined behaviour and the
		# subsequent get_pixel() crashes the editor on the first brush dab.
		var w: int = brush_mask_image.get_width()
		var h: int = brush_mask_image.get_height()
		if w <= 0 or h <= 0:
			return 1.0
		# Guard radius == 0 to avoid divide-by-zero when callers pass a
		# degenerate brush (slider at minimum + clamped to zero somewhere).
		if radius <= 0.0:
			return 0.0
		var u: float = (px.x - center.x) / radius * 0.5 + 0.5
		var v: float = (px.y - center.y) / radius * 0.5 + 0.5
		var ix: int = clampi(int(u * w), 0, w - 1)
		var iy: int = clampi(int(v * h), 0, h - 1)
		return brush_mask_image.get_pixel(ix, iy).r

	var dist: float = px.distance_to(center)
	var norm_dist: float = clampf(dist / radius, 0.0, 1.0)
	match brush_shape:
		0:  # soft
			return norm_dist * norm_dist * (3.0 - 2.0 * norm_dist) * -1.0 + 1.0
		1:  # hard
			return 1.0
		2:  # square soft edges
			var dx := absf(px.x - center.x)
			var dy := absf(px.y - center.y)
			var max_d := maxf(dx, dy)
			return 1.0 - clampf(max_d / radius, 0.0, 1.0)
		3:  # diamond soft edges
			var dx := absf(px.x - center.x)
			var dy := absf(px.y - center.y)
			return 1.0 - clampf((dx + dy) / radius, 0.0, 1.0)
		4:  # noise-modulated soft
			var base := norm_dist * norm_dist * (3.0 - 2.0 * norm_dist) * -1.0 + 1.0
			if noise_gen == null:
				return base
			var n := (noise_gen.get_noise_2d(px.x, px.y) + 1.0) * 0.5
			return base * n
		_:
			return 1.0

# Iterate every pixel under the brush footprint and invoke
# `callback(x: int, z: int, falloff: float)`. The caller is responsible
# for mutating heightmap / splatmap state and for marking chunks dirty.
func iterate_footprint(cx: float, cz: float, radius: float, callback: Callable) -> void:
	var min_x: int = max(0, int(cx - radius))
	var max_x: int = min(map_size, int(cx + radius) + 1)
	var min_z: int = max(0, int(cz - radius))
	var max_z: int = min(map_size, int(cz + radius) + 1)
	var center := Vector2(cx, cz)
	for z in range(min_z, max_z):
		for x in range(min_x, max_x):
			var px := Vector2(x, z)
			if is_in_brush(px, center, radius):
				var f := falloff_at(px, center, radius)
				callback.call(x, z, f)
