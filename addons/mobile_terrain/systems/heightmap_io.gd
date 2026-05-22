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
# (target_size × target_size). Maps the red channel through max_height/255.
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
	# TKT-004 H6: only duplicate when we're actually going to MUTATE the
	# image (decompress / resize / convert). The audit flagged ~3 full
	# buffers + GC churn on a 1254² import; the dominant one is this
	# duplicate (E1's source-protection copy, source-sized before resize).
	# get_data() below is read-only, so when the source is already the
	# target size, uncompressed, and RGBA8 we can read it directly and skip
	# the copy entirely — eliminating the largest allocation in the common
	# "import at native resolution" path. (The audit's 256²-streaming idea
	# isn't expressible with Godot's Image API: resize() and get_data()
	# both operate on the whole buffer, so there's no per-tile scratch.)
	var needs_mutation: bool = (
		src_img.is_compressed()
		or src_img.get_width() != target_size
		or src_img.get_height() != target_size
		or src_img.get_format() != Image.FORMAT_RGBA8
	)
	var img: Image = src_img
	if needs_mutation:
		# V20 FIX (bug E1): duplicate so the source texture's shared internal
		# Image (ImageTexture returns a shared reference) isn't corrupted by
		# the in-place decompress/resize/convert chain.
		img = src_img.duplicate()
		if img.is_compressed():
			img.decompress()
		if img.get_width() != target_size or img.get_height() != target_size:
			img.resize(target_size, target_size, Image.INTERPOLATE_BILINEAR)
		# V21 PERFORMANCE FIX: bulk byte read instead of per-pixel get_pixel.
		# Converting to RGBA8 lets us index the raw byte array directly:
		# pixel i's red component lives at byte (i * 4).
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
	var raw: PackedByteArray = img.get_data()
	var total: int = target_size * target_size
	# Defensive: the buffer must hold at least 4 bytes per cell. If
	# format conversion failed silently (rare but possible on damaged
	# imports), refuse to scan past the end.
	if raw.size() < total * 4:
		return PackedFloat32Array()
	var inv255: float = max_height / 255.0
	var heights := PackedFloat32Array()
	heights.resize(total)
	for i in range(total):
		heights[i] = float(raw[i * 4]) * inv255
	return heights
