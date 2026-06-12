@tool
extends SceneTree

# TKT-020 F1 regression test: editor-only chunk visibility (whitelist model).
#
# Pins the contract that makes the feature safe AND useful:
#   1. With the mode enabled, non-whitelisted chunks hide, DROP their mesh,
#      and skip every rebuild (the lag fix — adjusting a big map costs
#      nothing for hidden regions).
#   2. Skipped work is remembered (stale set); re-showing a chunk queues a
#      fresh rebuild from current height_data instead of trusting a stale
#      or missing mesh.
#   3. Disabling the mode releases EVERYTHING back to visible and re-queues
#      stale chunks (TKT-019 H3 lesson: a flag that gates a queue carries
#      its release path in the same setter).
#   4. RUNTIME IS INERT: without the editor hint (or the test hook), the
#      whitelist is ignored entirely — an exported game renders the whole
#      terrain even if the scene saved enabled=true.
#
# Uses the _force_chunk_visibility test hook to exercise the editor-only
# behaviour headlessly (Engine.is_editor_hint() is false under --script).

const TerrainScript := preload("res://addons/mobile_terrain/mobile_terrain_node.gd")

const MAP_SIZE := 32
const CHUNK_SIZE := 8  # → 4×4 = 16 chunks, all sync-built (≤ 64 limit)


func _init() -> void:
	var failures: Array[String] = []
	var t = TerrainScript.new()
	t.chunk_size = CHUNK_SIZE
	t.map_size = MAP_SIZE
	var hd := PackedFloat32Array()
	hd.resize(MAP_SIZE * MAP_SIZE)
	hd.fill(1.0)
	t.height_data = hd
	t._force_chunk_visibility = true
	t.initialize_terrain()

	var key := Vector2i(0, 0)
	var total: int = (MAP_SIZE / CHUNK_SIZE) * (MAP_SIZE / CHUNK_SIZE)
	if t.chunks.size() != total:
		failures.append("setup: expected %d chunks, got %d" % [total, t.chunks.size()])
		_report(t, failures)
		return
	if t.chunks[key].mesh == null:
		failures.append("setup: sync build should have meshed chunk (0,0)")

	# 1. Enable with an EMPTY whitelist → everything hides and drops meshes.
	t.chunk_visibility_enabled = true
	var any_visible := false
	var any_meshed := false
	for c in t.chunks.values():
		if c.visible:
			any_visible = true
		if c.mesh != null:
			any_meshed = true
	if any_visible:
		failures.append("enable+empty whitelist: every chunk must hide")
	if any_meshed:
		failures.append("enable+empty whitelist: every chunk must drop its ArrayMesh")

	# 2. Hidden chunks skip rebuilds and go stale instead.
	t.update_chunk_mesh(0, 0)
	if t.chunks[key].mesh != null:
		failures.append("hidden chunk must not mesh on update_chunk_mesh")
	if not t._stale_hidden_chunks.has(key):
		failures.append("skipped rebuild must mark the chunk stale")

	# 3. Toggling a chunk ON shows it and QUEUES a rebuild (never builds
	#    synchronously — a single chunk can be 1024² on auto-bumped maps).
	t.set_chunk_visible(key, true)
	if not t.chunks[key].visible:
		failures.append("set_chunk_visible(true) must show the chunk")
	if not t.dirty_chunks.has(key):
		failures.append("re-shown stale chunk must be queued for rebuild")
	if t.visible_chunks.size() != 1:
		failures.append("whitelist must hold exactly the shown chunk, got %d" % t.visible_chunks.size())
	t.update_chunk_mesh(0, 0)  # simulate the drain picking it up
	if t.chunks[key].mesh == null:
		failures.append("visible chunk must mesh again on rebuild")

	# 4. Bulk ops: all on → all off via invert.
	t.set_all_chunks_visible(true)
	if t.visible_chunks.size() != total:
		failures.append(
			"set_all(true): whitelist should hold %d, got %d" % [total, t.visible_chunks.size()]
		)
	t.invert_chunk_visibility()
	if t.visible_chunks.size() != 0:
		failures.append(
			"invert after all-on: whitelist should be empty, got %d" % t.visible_chunks.size()
		)
	if t.chunks[key].visible:
		failures.append("invert: previously-shown chunk must hide")

	# 5. Disabling the mode restores everything and re-queues stale chunks.
	t.dirty_chunks.clear()
	t.chunk_visibility_enabled = false
	for c in t.chunks.values():
		if not c.visible:
			failures.append("disable: every chunk must become visible")
			break
	var queued: int = 0
	for k in t.chunks.keys():
		if t.dirty_chunks.has(k):
			queued += 1
	if queued != total:
		failures.append("disable: all %d stale chunks must re-queue, got %d" % [total, queued])

	# 6. Runtime-inert: hook off (and no editor hint) → whitelist ignored.
	var rt = TerrainScript.new()
	rt.chunk_size = CHUNK_SIZE
	rt.map_size = MAP_SIZE
	rt.height_data = hd.duplicate()
	rt.chunk_visibility_enabled = true  # saved-scene worst case
	rt.initialize_terrain()
	var rt_chunk = rt.chunks.get(key)
	if rt_chunk == null or not rt_chunk.visible or rt_chunk.mesh == null:
		failures.append("runtime: visibility mode must be inert (chunk hidden or unmeshed)")
	rt.free()

	_report(t, failures)


func _report(t, failures: Array[String]) -> void:
	t.free()
	if failures.is_empty():
		print("CHUNK_VISIBILITY_TEST_OK")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: " + f)
		print("CHUNK_VISIBILITY_TEST_FAILED count=%d" % failures.size())
		quit(1)
