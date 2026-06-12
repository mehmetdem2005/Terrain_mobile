@tool
class_name HeightmapIO
extends RefCounted

## HeightmapIO — pure heightmap import/export helpers.
##
## TKT-003 Phase A.2: extracted from `mobile_terrain_node.gd._import_exr`
## as the second step of the god-class decomposition. The conversion
## from Texture2D (any format Godot loads) to a PackedFloat32Array of
## heights is pure — it doesn't need to know about chunks, shaders, or
## the scene tree.
##
## Bulk-byte path (V21 PERFORMANCE FIX preserved): one `get_data()` plus
## a flat byte→float loop avoids 1.57M GDScript→native `get_pixel()`
## crossings on a 1254² import. On mobile this is the difference between
## a sub-second import and a multi-second editor hang.


# Convert a Texture2D into a PackedFloat32Array of heights sized to
# (target_size × target_size). Maps the red channel (normalised 0..1)
# through max_height — an 8-bit source's red byte b becomes b/255 *
# max_height, identical to the historical contract.
#
# Returns an empty array on bad input (null texture, null image data).
# Caller decides what to do with empty (e.g. log MT-* diagnostic).
#
# Notes:
#   - The source texture is never mutated; we work on a duplicate so that
#     ImageTexture (which returns a shared reference from get_image) is
#     not corrupted by the in-place decompress/resize/convert chain.
#   - Decompression is performed only if needed.
#   - Bilinear resize is used so terrain features remain smooth across
#     downscaled imports.
static func convert_texture_to_heights(
	src_texture: Texture2D, target_size: int, max_height: float
) -> PackedFloat32Array:
	if src_texture == null or target_size <= 0:
		return PackedFloat32Array()
	var src_img := src_texture.get_image()
	if src_img == null:
		return PackedFloat32Array()
	# TKT-019 H2: pivot the bulk path from FORMAT_RGBA8 to FORMAT_RF.
	# The V21 bulk-byte optimisation converted every source to RGBA8 and
	# read one byte per cell — which silently quantised EXR / 16-bit float
	# heightmaps to 256 levels (visible terracing on smooth slopes; at
	# import_max_height=50 each step is 0.196 units). FORMAT_RF keeps one
	# float32 per cell, so get_data().to_float32_array() is the same bulk
	# read with FULL source precision; 8-bit sources convert to b/255.0
	# floats, preserving the historical scaling exactly. Converting BEFORE
	# the resize also makes the bilinear resample run in float, so
	# downscaled float imports don't quantise mid-pipeline either.
	#
	# TKT-004 H6 (duplicate only when mutating) is preserved: the zero-copy
	# fast path now applies to FORMAT_RF sources at native resolution.
	var needs_mutation: bool = (
		src_img.is_compressed()
		or src_img.get_width() != target_size
		or src_img.get_height() != target_size
		or src_img.get_format() != Image.FORMAT_RF
	)
	var img: Image = src_img
	if needs_mutation:
		# V20 FIX (bug E1): duplicate so the source texture's shared internal
		# Image (ImageTexture returns a shared reference) isn't corrupted by
		# the in-place decompress/resize/convert chain.
		img = src_img.duplicate()
		if img.is_compressed():
			img.decompress()
		if img.get_format() != Image.FORMAT_RF:
			img.convert(Image.FORMAT_RF)
		if img.get_width() != target_size or img.get_height() != target_size:
			img.resize(target_size, target_size, Image.INTERPOLATE_BILINEAR)
	var floats: PackedFloat32Array = img.get_data().to_float32_array()
	var total: int = target_size * target_size
	# Defensive: the buffer must hold one float per cell. If format
	# conversion failed silently (rare but possible on damaged imports),
	# refuse to scan past the end.
	if floats.size() < total:
		return PackedFloat32Array()
	var heights := PackedFloat32Array()
	heights.resize(total)
	for i in range(total):
		heights[i] = floats[i] * max_height
	return heights
