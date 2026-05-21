@tool
class_name SplatmapSystem
extends RefCounted

## SplatmapSystem — pure splatmap paint math.
##
## TKT-003 Phase A.1: extracted from `mobile_terrain_node.gd._paint_splatmap`
## as the first step of the god-class decomposition. The split keeps the
## node responsible for state (which Image is active, when to flush bytes
## to GPU, when to rebind the shader uniform) while the paint algorithm
## itself — competitive RGBA blending across one of four slots — lives
## here as a static, side-effect-free function. The pure form is unit-
## testable without spinning up a full MobileTerrain3D node.
##
## Competitive blend semantics (preserved from V22): each pixel under the
## brush footprint has its four channels shrunk by (1 - blend_factor),
## then the target slot is boosted by blend_factor. Sum of channels stays
## near 1.0 even as the user paints multiple slots over the same area —
## the terrain shader's per-fragment normalisation handles the small drift.

# Paint into `img` at world position (cx, cz). Returns true on success,
# false on invalid input (caller logs the appropriate MT-* diagnostic).
#
# Inputs:
#   img         — splatmap image to mutate in place. Must be map_size² RGBA8.
#   map_size    — the map's edge length in cells; img must match.
#   cx, cz      — brush centre in local terrain coordinates.
#   radius      — brush radius in cells.
#   strength    — base brush strength in [0..1].
#   paint_slot  — which channel to boost: 0=R, 1=G, 2=B, 3=A.
#   brush       — pre-constructed BrushSystem providing footprint + falloff.
static func paint(
	img: Image,
	map_size: int,
	cx: float,
	cz: float,
	radius: float,
	strength: float,
	paint_slot: int,
	brush: BrushSystem
) -> bool:
	# Slot range — splatmap is RGBA8, only 4 channels. Caller emits MT-* code.
	if paint_slot < 0 or paint_slot >= 4:
		return false
	# Image presence + size match. A mid-resize race can leave img sized
	# to the old map; writing there would corrupt arbitrary pixels.
	if img == null:
		return false
	if img.get_width() != map_size or img.get_height() != map_size:
		return false
	if brush == null:
		return false

	var slot: int = paint_slot
	brush.iterate_footprint(cx, cz, radius, func(x: int, z: int, falloff: float) -> void:
		var color: Color = img.get_pixel(x, z)
		var blend_factor: float = clampf(strength * falloff, 0.0, 1.0)
		var inv: float = 1.0 - blend_factor
		color.r *= inv
		color.g *= inv
		color.b *= inv
		color.a *= inv
		match slot:
			0: color.r += blend_factor
			1: color.g += blend_factor
			2: color.b += blend_factor
			3: color.a += blend_factor
		img.set_pixel(x, z, color)
	)
	return true
