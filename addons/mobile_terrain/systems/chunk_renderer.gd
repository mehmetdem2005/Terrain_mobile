@tool
class_name ChunkRenderer
extends RefCounted

## ChunkRenderer — pure terrain chunk mesh generation.
##
## TKT-003 Phase A.4: extracted from `mobile_terrain_node.gd.update_chunk_mesh`,
## the single largest piece of the node god-class (~155 lines). The mesh
## build — vertex grid, finite-difference normals, planar UVs, uniform
## tangents, index buffer — is pure: given height_data + grid parameters
## it returns an ArrayMesh. The node keeps responsibility for the chunk
## dictionary, MeshInstance assignment, and positioning.
##
## Making this pure unlocks headless mesh-invariant testing (vertex count,
## normal normalisation, UV range, seam continuity) that the previous
## inline form couldn't support — mesh geometry can now be verified
## without a viewport, even though final pixels still need a real GPU.
##
## All V20/V21 invariants are preserved verbatim:
##   - V20 #13: clip the outer edge of the last chunk per axis so the
##     terrain boundary lands on valid height data (no flat edge strip).
##   - V21 perf: pre-allocate arrays (resize + index-assign, no append),
##     inline get_height in the hot loop, hoist the UV denominator, bulk
##     tangent fill.


# Build the ArrayMesh for chunk (cx, cz). Returns null on invalid input.
#
# Inputs:
#   height_data — row-major heights, length map_size².
#   map_size    — terrain edge length in cells.
#   chunk_size  — chunk edge length in cells; map_size must be a multiple.
#   cx, cz      — chunk grid coordinates.
#
# Output ArrayMesh is in chunk-local space: vertex (x, h, z) where x/z are
# 0..chunk_size. The node positions the MeshInstance at (cx*chunk_size, 0,
# cz*chunk_size) so chunks tile in world space.
static func build_chunk_mesh(
	height_data: PackedFloat32Array, map_size: int, chunk_size: int, cx: int, cz: int
) -> ArrayMesh:
	if map_size <= 0 or chunk_size <= 0:
		return null
	if height_data.size() < map_size * map_size:
		return null

	var start_x: int = cx * chunk_size
	var start_z: int = cz * chunk_size

	# V20 FIX (#13): clip the outer edge of the last chunk in each axis so
	# its outer vertex lands on index map_size-1 (valid height) rather than
	# map_size (out of bounds → flat edge strip). Paired with the
	# divisibility guard in the node's _set_map_size / _set_chunk_size.
	var num_chunks: int = map_size / chunk_size
	var vx_count_x: int = chunk_size + 1
	var vx_count_z: int = chunk_size + 1
	if cx == num_chunks - 1:
		vx_count_x = chunk_size
	if cz == num_chunks - 1:
		vx_count_z = chunk_size

	var vx_count: int = vx_count_x * vx_count_z
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	vertices.resize(vx_count)
	normals.resize(vx_count)
	uvs.resize(vx_count)

	var inv_uv_denom: float = 1.0 / float(max(1, map_size - 1))
	var max_idx: int = map_size - 1
	var vi: int = 0
	for z in range(vx_count_z):
		for x in range(vx_count_x):
			var gx: int = start_x + x
			var gz: int = start_z + z
			var center_idx: int = gz * map_size + gx
			var h: float = height_data[center_idx]
			vertices[vi] = Vector3(x, h, z)
			# Finite-difference normal with manual clamp (faster than a
			# get_height() call at 2M+ invocations per full rebuild).
			var nx_l: int = gx - 1 if gx > 0 else 0
			var nx_r: int = gx + 1 if gx < max_idx else max_idx
			var nz_d: int = gz - 1 if gz > 0 else 0
			var nz_u: int = gz + 1 if gz < max_idx else max_idx
			var h_l: float = height_data[gz * map_size + nx_l]
			var h_r: float = height_data[gz * map_size + nx_r]
			var h_d: float = height_data[nz_d * map_size + gx]
			var h_u: float = height_data[nz_u * map_size + gx]
			normals[vi] = Vector3(h_l - h_r, 2.0, h_d - h_u).normalized()
			uvs[vi] = Vector2(float(gx) * inv_uv_denom, float(gz) * inv_uv_denom)
			vi += 1

	var quad_count_x: int = vx_count_x - 1
	var quad_count_z: int = vx_count_z - 1
	var indices := PackedInt32Array()
	indices.resize(quad_count_x * quad_count_z * 6)
	var ii: int = 0
	for z in range(quad_count_z):
		for x in range(quad_count_x):
			var row1: int = z * vx_count_x
			var row2: int = (z + 1) * vx_count_x
			indices[ii] = row1 + x
			ii += 1
			indices[ii] = row1 + x + 1
			ii += 1
			indices[ii] = row2 + x
			ii += 1
			indices[ii] = row1 + x + 1
			ii += 1
			indices[ii] = row2 + x + 1
			ii += 1
			indices[ii] = row2 + x
			ii += 1

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs

	# V21: uniform tangent (T = +X, binormal sign +1) for normal-map decode
	# on the Mobile renderer. Bulk fill — three of four components are 0.0
	# (resize already zeroed them), so only touch base+0 and base+3.
	var tangents := PackedFloat32Array()
	tangents.resize(vx_count * 4)
	for i in range(vx_count):
		var base: int = i * 4
		tangents[base] = 1.0
		tangents[base + 3] = 1.0
	arrays[Mesh.ARRAY_TANGENT] = tangents

	var amesh := ArrayMesh.new()
	amesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return amesh
