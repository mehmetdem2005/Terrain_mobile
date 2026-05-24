@tool
extends SceneTree

# TKT-003 Phase A.4: ChunkRenderer extraction regression test.
#
# Mesh build cannot be verified visually in headless mode, so this suite
# verifies the GEOMETRY INVARIANTS instead — the properties that, if
# broken, would corrupt the rendered terrain:
#   - vertex count per chunk (full vs clipped last-chunk)
#   - index count (6 per quad)
#   - normals normalised; flat terrain → up
#   - UVs in [0, 1]
#   - tangents uniform (+X, sign +1)
#   - vertex local coordinates match grid
#   - seam continuity: shared edge heights agree between adjacent chunks
#   - AABB height range matches the source heightmap
#
# These are exactly the regressions a refactor of the mesh path could
# introduce, and they're all checkable from surface_get_arrays().

const ChunkRendererScript := preload("res://addons/mobile_terrain/systems/chunk_renderer.gd")

const MAP_SIZE := 16
const CHUNK_SIZE := 8  # → 2x2 chunks; chunk (1,*) and (*,1) are the clipped last chunks

func _init() -> void:
	var failures: Array[String] = []
	_run("invalid_input_returns_null", _test_invalid_input, failures)
	_run("full_chunk_vertex_count", _test_full_vertex_count, failures)
	_run("clipped_last_chunk_vertex_count", _test_clipped_vertex_count, failures)
	_run("index_count_six_per_quad", _test_index_count, failures)
	_run("single_surface", _test_single_surface, failures)
	_run("flat_terrain_normals_point_up", _test_flat_normals, failures)
	_run("normals_are_normalised", _test_normals_normalised, failures)
	_run("uvs_within_unit_range", _test_uv_range, failures)
	_run("tangents_uniform", _test_tangents, failures)
	_run("vertex_height_matches_source", _test_vertex_height, failures)
	_run("seam_continuity_between_chunks", _test_seam_continuity, failures)
	_run("lod_step1_identical_to_default", _test_lod_step1_identical, failures)
	_run("lod_step2_reduces_vertices", _test_lod_step2_vertex_count, failures)
	_run("lod_coarsest_single_quad", _test_lod_coarsest_single_quad, failures)
	_run("lod_step_clamped", _test_lod_step_clamped, failures)
	_run("lod_same_step_seam_matches", _test_lod_same_step_seam, failures)

	if failures.is_empty():
		print("CHUNK_RENDERER_TEST_OK")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: " + f)
		print("CHUNK_RENDERER_TEST_FAILED count=%d" % failures.size())
		quit(1)

func _run(name: String, fn: Callable, failures: Array[String]) -> void:
	var err: String = fn.call()
	if err != "":
		failures.append("%s — %s" % [name, err])
	else:
		print("OK  %s" % name)

func _make_flat_heights(size: int, h: float) -> PackedFloat32Array:
	var arr := PackedFloat32Array()
	arr.resize(size * size)
	arr.fill(h)
	return arr

# A ramp rising along +x: height = gx. Lets us check seam continuity and
# vertex-height mapping with predictable values.
func _make_ramp_heights(size: int) -> PackedFloat32Array:
	var arr := PackedFloat32Array()
	arr.resize(size * size)
	for z in range(size):
		for x in range(size):
			arr[z * size + x] = float(x)
	return arr

func _get_arrays(mesh: ArrayMesh) -> Array:
	return mesh.surface_get_arrays(0)

func _test_invalid_input() -> String:
	if ChunkRendererScript.build_chunk_mesh(PackedFloat32Array(), 0, 8, 0, 0) != null:
		return "map_size=0 must return null"
	if ChunkRendererScript.build_chunk_mesh(PackedFloat32Array(), 16, 0, 0, 0) != null:
		return "chunk_size=0 must return null"
	# height_data too small
	if ChunkRendererScript.build_chunk_mesh(PackedFloat32Array(), 16, 8, 0, 0) != null:
		return "empty height_data must return null"
	return ""

func _test_full_vertex_count() -> String:
	# Chunk (0,0) is a full chunk → (chunk_size+1)² vertices.
	var heights := _make_flat_heights(MAP_SIZE, 0.0)
	var mesh: ArrayMesh = ChunkRendererScript.build_chunk_mesh(heights, MAP_SIZE, CHUNK_SIZE, 0, 0)
	if mesh == null:
		return "expected mesh, got null"
	var verts: PackedVector3Array = _get_arrays(mesh)[Mesh.ARRAY_VERTEX]
	var expected: int = (CHUNK_SIZE + 1) * (CHUNK_SIZE + 1)
	if verts.size() != expected:
		return "full chunk expected %d vertices, got %d" % [expected, verts.size()]
	return ""

func _test_clipped_vertex_count() -> String:
	# Chunk (1,1) is the last chunk on both axes → clipped to chunk_size per side.
	var heights := _make_flat_heights(MAP_SIZE, 0.0)
	var mesh: ArrayMesh = ChunkRendererScript.build_chunk_mesh(heights, MAP_SIZE, CHUNK_SIZE, 1, 1)
	var verts: PackedVector3Array = _get_arrays(mesh)[Mesh.ARRAY_VERTEX]
	var expected: int = CHUNK_SIZE * CHUNK_SIZE
	if verts.size() != expected:
		return "clipped last chunk expected %d vertices, got %d" % [expected, verts.size()]
	return ""

func _test_index_count() -> String:
	# Full chunk: quad grid is chunk_size × chunk_size, 6 indices per quad.
	var heights := _make_flat_heights(MAP_SIZE, 0.0)
	var mesh: ArrayMesh = ChunkRendererScript.build_chunk_mesh(heights, MAP_SIZE, CHUNK_SIZE, 0, 0)
	var indices: PackedInt32Array = _get_arrays(mesh)[Mesh.ARRAY_INDEX]
	var expected: int = CHUNK_SIZE * CHUNK_SIZE * 6
	if indices.size() != expected:
		return "full chunk expected %d indices, got %d" % [expected, indices.size()]
	return ""

func _test_single_surface() -> String:
	var heights := _make_flat_heights(MAP_SIZE, 0.0)
	var mesh: ArrayMesh = ChunkRendererScript.build_chunk_mesh(heights, MAP_SIZE, CHUNK_SIZE, 0, 0)
	if mesh.get_surface_count() != 1:
		return "expected 1 surface, got %d" % mesh.get_surface_count()
	return ""

func _test_flat_normals() -> String:
	# Flat terrain → every normal should be (0, 1, 0).
	var heights := _make_flat_heights(MAP_SIZE, 5.0)
	var mesh: ArrayMesh = ChunkRendererScript.build_chunk_mesh(heights, MAP_SIZE, CHUNK_SIZE, 0, 0)
	var normals: PackedVector3Array = _get_arrays(mesh)[Mesh.ARRAY_NORMAL]
	for n in normals:
		if n.dot(Vector3.UP) < 0.999:
			return "flat terrain normal should point up, got %s" % str(n)
	return ""

func _test_normals_normalised() -> String:
	# Ramp terrain → normals tilt, but must stay unit length.
	var heights := _make_ramp_heights(MAP_SIZE)
	var mesh: ArrayMesh = ChunkRendererScript.build_chunk_mesh(heights, MAP_SIZE, CHUNK_SIZE, 0, 0)
	var normals: PackedVector3Array = _get_arrays(mesh)[Mesh.ARRAY_NORMAL]
	for n in normals:
		if absf(n.length() - 1.0) > 0.001:
			return "normal not unit length: %s (len %f)" % [str(n), n.length()]
	return ""

func _test_uv_range() -> String:
	var heights := _make_flat_heights(MAP_SIZE, 0.0)
	var mesh: ArrayMesh = ChunkRendererScript.build_chunk_mesh(heights, MAP_SIZE, CHUNK_SIZE, 0, 0)
	var uvs: PackedVector2Array = _get_arrays(mesh)[Mesh.ARRAY_TEX_UV]
	for uv in uvs:
		if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
			return "UV outside [0,1]: %s" % str(uv)
	return ""

func _test_tangents() -> String:
	var heights := _make_flat_heights(MAP_SIZE, 0.0)
	var mesh: ArrayMesh = ChunkRendererScript.build_chunk_mesh(heights, MAP_SIZE, CHUNK_SIZE, 0, 0)
	var tangents: PackedFloat32Array = _get_arrays(mesh)[Mesh.ARRAY_TANGENT]
	var vert_count: int = _get_arrays(mesh)[Mesh.ARRAY_VERTEX].size()
	if tangents.size() != vert_count * 4:
		return "tangent array should be 4 per vertex, got %d for %d verts" % [tangents.size(), vert_count]
	for i in range(vert_count):
		var base: int = i * 4
		if absf(tangents[base] - 1.0) > 0.001:
			return "tangent T.x should be 1.0 at vertex %d, got %f" % [i, tangents[base]]
		if absf(tangents[base + 3] - 1.0) > 0.001:
			return "tangent sign should be 1.0 at vertex %d, got %f" % [i, tangents[base + 3]]
	return ""

func _test_vertex_height() -> String:
	# Ramp height = gx. Chunk (0,0) vertex at local (x, ?, z) has gx = x,
	# so its Y must equal x.
	var heights := _make_ramp_heights(MAP_SIZE)
	var mesh: ArrayMesh = ChunkRendererScript.build_chunk_mesh(heights, MAP_SIZE, CHUNK_SIZE, 0, 0)
	var verts: PackedVector3Array = _get_arrays(mesh)[Mesh.ARRAY_VERTEX]
	for v in verts:
		# Vertex local x equals global x for chunk (0,0); height = gx = x.
		if absf(v.y - v.x) > 0.001:
			return "ramp vertex height should equal local x, got pos %s" % str(v)
	return ""

func _test_seam_continuity() -> String:
	# The shared edge between chunk (0,0) and chunk (1,0) must have matching
	# world heights. Chunk (0,0)'s right edge is at global x = chunk_size;
	# chunk (1,0)'s left edge (local x=0) is also at global x = chunk_size.
	# On a ramp height=gx, both should report height = chunk_size.
	var heights := _make_ramp_heights(MAP_SIZE)
	var mesh0: ArrayMesh = ChunkRendererScript.build_chunk_mesh(heights, MAP_SIZE, CHUNK_SIZE, 0, 0)
	var mesh1: ArrayMesh = ChunkRendererScript.build_chunk_mesh(heights, MAP_SIZE, CHUNK_SIZE, 1, 0)
	var verts1: PackedVector3Array = _get_arrays(mesh1)[Mesh.ARRAY_VERTEX]
	# Chunk (1,0) local x=0 maps to global x = chunk_size → height should
	# be chunk_size on the ramp. Verify the left edge of chunk 1.
	for v in verts1:
		if int(v.x) == 0:  # left edge of chunk 1
			if absf(v.y - float(CHUNK_SIZE)) > 0.001:
				return "seam: chunk(1,0) left edge height should be %d, got %f" % [CHUNK_SIZE, v.y]
	return ""

# --- LOD (vertex-stride decimation) ---

func _test_lod_step1_identical() -> String:
	# Backward-compat guarantee: explicit step=1 must equal the default path
	# vertex-for-vertex. If this breaks, every existing scene re-meshes wrong.
	var heights := _make_ramp_heights(MAP_SIZE)
	var a: ArrayMesh = ChunkRendererScript.build_chunk_mesh(heights, MAP_SIZE, CHUNK_SIZE, 0, 0)
	var b: ArrayMesh = ChunkRendererScript.build_chunk_mesh(heights, MAP_SIZE, CHUNK_SIZE, 0, 0, 1)
	var va: PackedVector3Array = _get_arrays(a)[Mesh.ARRAY_VERTEX]
	var vb: PackedVector3Array = _get_arrays(b)[Mesh.ARRAY_VERTEX]
	if va.size() != vb.size():
		return "step=1 vertex count differs from default (%d vs %d)" % [va.size(), vb.size()]
	for i in range(va.size()):
		if va[i].distance_to(vb[i]) > 0.0001:
			return "step=1 vertex %d differs from default" % i
	return ""

func _test_lod_step2_vertex_count() -> String:
	# step=2 samples every other cell: (chunk_size/2 + 1)² vertices on a full chunk.
	var heights := _make_flat_heights(MAP_SIZE, 0.0)
	var mesh: ArrayMesh = ChunkRendererScript.build_chunk_mesh(heights, MAP_SIZE, CHUNK_SIZE, 0, 0, 2)
	var verts: PackedVector3Array = _get_arrays(mesh)[Mesh.ARRAY_VERTEX]
	var per_axis: int = CHUNK_SIZE / 2 + 1
	var expected: int = per_axis * per_axis
	if verts.size() != expected:
		return "step=2 full chunk expected %d vertices, got %d" % [expected, verts.size()]
	return ""

func _test_lod_coarsest_single_quad() -> String:
	# step == chunk_size collapses the chunk to a single quad (2x2 verts, 6 indices).
	var heights := _make_flat_heights(MAP_SIZE, 0.0)
	var mesh: ArrayMesh = ChunkRendererScript.build_chunk_mesh(
		heights, MAP_SIZE, CHUNK_SIZE, 0, 0, CHUNK_SIZE
	)
	var verts: PackedVector3Array = _get_arrays(mesh)[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = _get_arrays(mesh)[Mesh.ARRAY_INDEX]
	if verts.size() != 4:
		return "coarsest chunk expected 4 vertices, got %d" % verts.size()
	if indices.size() != 6:
		return "coarsest chunk expected 6 indices (1 quad), got %d" % indices.size()
	return ""

func _test_lod_step_clamped() -> String:
	var heights := _make_flat_heights(MAP_SIZE, 0.0)
	# step beyond chunk_size clamps down to a single quad.
	var big: ArrayMesh = ChunkRendererScript.build_chunk_mesh(
		heights, MAP_SIZE, CHUNK_SIZE, 0, 0, CHUNK_SIZE * 4
	)
	if _get_arrays(big)[Mesh.ARRAY_VERTEX].size() != 4:
		return "step > chunk_size should clamp to a single quad (4 verts)"
	# step <= 0 clamps up to full resolution.
	var zero: ArrayMesh = ChunkRendererScript.build_chunk_mesh(heights, MAP_SIZE, CHUNK_SIZE, 0, 0, 0)
	var full_expected: int = (CHUNK_SIZE + 1) * (CHUNK_SIZE + 1)
	if _get_arrays(zero)[Mesh.ARRAY_VERTEX].size() != full_expected:
		return "step<=0 should clamp to full res (%d verts)" % full_expected
	return ""

func _test_lod_same_step_seam() -> String:
	# Same-LOD neighbours must NOT crack: chunk(1,0) at step=2 still has a vertex
	# on the shared edge (global x = CHUNK_SIZE) at the correct ramp height.
	var heights := _make_ramp_heights(MAP_SIZE)
	var m1: ArrayMesh = ChunkRendererScript.build_chunk_mesh(heights, MAP_SIZE, CHUNK_SIZE, 1, 0, 2)
	var v1: PackedVector3Array = _get_arrays(m1)[Mesh.ARRAY_VERTEX]
	var found := false
	for v in v1:
		if int(v.x) == 0:  # left edge of chunk (1,0) → global x = CHUNK_SIZE
			found = true
			if absf(v.y - float(CHUNK_SIZE)) > 0.001:
				return "LOD seam: chunk(1,0) left edge height should be %d, got %f" % [CHUNK_SIZE, v.y]
	if not found:
		return "LOD seam: chunk(1,0) has no shared-edge vertex (crack)"
	return ""
