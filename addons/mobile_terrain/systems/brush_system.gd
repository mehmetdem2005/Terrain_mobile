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

# TKT-004 H5: mask falloff lookup table. falloff_at() used to call
# brush_mask_image.get_pixel() per footprint pixel — at a 256px brush
# painting ~100 dabs/sec that's ~25K GDScript->native crossings/sec, an
# 8-15% CPU tax on mobile during a sculpt. We bake the mask's red channel
# into a flat PackedFloat32Array once in _init and index it directly in
# the hot loop (no per-pixel call dispatch, no Color allocation).
var _mask_lut: PackedFloat32Array = PackedFloat32Array()
var _mask_w: int = 0
var _mask_h: int = 0


func _init(
	p_map_size: int,
	p_brush_mask: Texture2D,
	p_brush_mask_image: Image,
	p_brush_shape: int,
	p_noise_gen: FastNoiseLite
) -> void:
	map_size = p_map_size
	brush_mask = p_brush_mask
	brush_mask_image = p_brush_mask_image
	brush_shape = p_brush_shape
	noise_gen = p_noise_gen
	_bake_mask_lut()


# Pre-bake brush_mask_image's red channel into _mask_lut. Leaves _mask_w/h
# at 0 if the mask is absent or its image is unusable (zero-dim) — the
# TKT-002 C4 condition — so falloff_at can fall back safely.
func _bake_mask_lut() -> void:
	_mask_lut = PackedFloat32Array()
	_mask_w = 0
	_mask_h = 0
	if brush_mask == null or brush_mask_image == null:
		return
	var w: int = brush_mask_image.get_width()
	var h: int = brush_mask_image.get_height()
	if w <= 0 or h <= 0:
		return
	_mask_w = w
	_mask_h = h
	_mask_lut.resize(w * h)
	for y in range(h):
		var row: int = y * w
		for x in range(w):
			_mask_lut[row + x] = brush_mask_image.get_pixel(x, y).r


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
		# when an importer hasn't finished yet. _bake_mask_lut leaves
		# _mask_w/h at 0 in that case; without this guard, clampi(int(u*0),
		# 0, -1) would produce undefined behaviour on the first brush dab.
		if _mask_w <= 0 or _mask_h <= 0:
			return 1.0
		# Guard radius == 0 to avoid divide-by-zero when callers pass a
		# degenerate brush (slider at minimum + clamped to zero somewhere).
		if radius <= 0.0:
			return 0.0
		var u: float = (px.x - center.x) / radius * 0.5 + 0.5
		var v: float = (px.y - center.y) / radius * 0.5 + 0.5
		var ix: int = clampi(int(u * _mask_w), 0, _mask_w - 1)
		var iy: int = clampi(int(v * _mask_h), 0, _mask_h - 1)
		# TKT-004 H5: direct LUT index — no get_pixel() dispatch per pixel.
		return _mask_lut[iy * _mask_w + ix]

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
