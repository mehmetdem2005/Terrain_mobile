@tool
extends SceneTree

# Editor LOD seed regression test (load-spike / OOM fix).
#
# The bug: on scene-load / map_size change the editor used to mesh the WHOLE
# terrain at FULL resolution before the distance-LOD pass reduced it — a
# transient full-res spike that OOM-crashed the editor on large maps. The fix
# (mobile_terrain_node._process) seeds _chunk_lod BEFORE the first chunk build
# and holds the drain until it has. The seed-before-build TIMING is proven in
# the real editor by test/run_editor_puppet.sh (scenario "lodseed").
#
# This headless test pins the WIRING that timing depends on: that
# update_chunk_mesh honours a pre-seeded _chunk_lod entry — building that chunk
# at the seeded vertex stride instead of the full-res default. If this breaks,
# seeding the LOD early would no longer reduce the built mesh and the spike
# would return.

const TerrainScript := preload("res://addons/mobile_terrain/mobile_terrain_node.gd")

const MAP_SIZE := 16
const CHUNK_SIZE := 8  # → 2x2 chunks; chunk (0,0) is a full chunk


func _init() -> void:
	var failures: Array[String] = []
	var t = TerrainScript.new()
	t.chunk_size = CHUNK_SIZE
	t.map_size = MAP_SIZE
	var hd := PackedFloat32Array()
	hd.resize(MAP_SIZE * MAP_SIZE)
	hd.fill(0.0)
	t.height_data = hd
	# _ready defers the build (call_deferred), which never fires in a synchronous
	# SceneTree test, so build directly. Safe out-of-tree (no get_tree() use).
	t.initialize_terrain()

	var key := Vector2i(0, 0)
	if not t.chunks.has(key):
		failures.append("setup: chunk (0,0) was not created (chunks=%d)" % t.chunks.size())
		_report(t, failures)
		return

	var full_expected: int = (CHUNK_SIZE + 1) * (CHUNK_SIZE + 1)  # 81

	# Control: with no _chunk_lod entry, update_chunk_mesh builds at full res.
	t._chunk_lod.erase(key)
	t.update_chunk_mesh(0, 0)
	var n_full := _vert_count(t, key)
	if n_full != full_expected:
		failures.append("default build: expected %d verts (full res), got %d" % [full_expected, n_full])

	# Seed the coarsest stride (== chunk_size) → chunk must collapse to one quad.
	t._chunk_lod[key] = CHUNK_SIZE
	t.update_chunk_mesh(0, 0)
	var n_coarse := _vert_count(t, key)
	if n_coarse != 4:
		failures.append("seeded coarse build: expected 4 verts (single quad), got %d" % n_coarse)

	# A mid stride is honoured too: step=2 → (chunk_size/2 + 1)² = 25 verts.
	t._chunk_lod[key] = 2
	t.update_chunk_mesh(0, 0)
	var n_mid := _vert_count(t, key)
	var mid_expected: int = (CHUNK_SIZE / 2 + 1) * (CHUNK_SIZE / 2 + 1)  # 25
	if n_mid != mid_expected:
		failures.append("seeded mid build: expected %d verts, got %d" % [mid_expected, n_mid])

	# TKT-019 H3: disabling LOD must release a pending seed hold (otherwise
	# the dirty drain in _process stays gated forever and the terrain never
	# meshes) and re-dirty decimated chunks so they rebuild at full res.
	t._lod_needs_seed = true
	t._lod_held_frames = 7
	t._chunk_lod[key] = CHUNK_SIZE
	t.dirty_chunks.clear()
	t.editor_lod_enabled = false
	if t._lod_needs_seed:
		failures.append("lod-disable: seed hold must be released")
	if t._lod_held_frames != 0:
		failures.append("lod-disable: held-frame counter must reset")
	if not t._chunk_lod.is_empty():
		failures.append("lod-disable: per-chunk strides must clear")
	if not t.dirty_chunks.has(key):
		failures.append("lod-disable: decimated chunks must be re-dirtied for full-res rebuild")

	# Re-enabling re-arms the camera-epsilon gate so the next LOD tick
	# re-evaluates even with a stationary camera.
	t._last_lod_cam_pos = Vector3(1, 2, 3)
	t.editor_lod_enabled = true
	if t._last_lod_cam_pos != Vector3.INF:
		failures.append("lod-enable: camera epsilon gate must re-arm")

	# The distance-scale setter re-arms it too (slider must not feel dead).
	t._last_lod_cam_pos = Vector3(1, 2, 3)
	t.editor_lod_distance_scale = 2.0
	if t._last_lod_cam_pos != Vector3.INF:
		failures.append("distance-scale: camera epsilon gate must re-arm")

	_report(t, failures)


func _vert_count(t, key: Vector2i) -> int:
	var chunk = t.chunks.get(key)
	if chunk == null or chunk.mesh == null:
		return -1
	return chunk.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()


func _report(t, failures: Array[String]) -> void:
	t.free()
	if failures.is_empty():
		print("EDITOR_LOD_SEED_OK")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: " + f)
		print("EDITOR_LOD_SEED_FAILED count=%d" % failures.size())
		quit(1)
