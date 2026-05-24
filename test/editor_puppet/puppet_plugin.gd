@tool
extends EditorPlugin

## Editor-puppet verification harness — TEST ONLY.
##
## This plugin is NOT part of the shipping addon. It is enabled only inside the
## throwaway project that test/run_editor_puppet.sh builds, and launched under
## xvfb with the env var MT_PUPPET=<scenario>. It opens a MobileTerrain3D scene,
## drives the REAL plugin/node code (sculpt, object placement, painting) exactly
## like a user would, screenshots the editor's 3D viewport, and quits. This lets
## the assistant visually verify editor behaviour headlessly (no human needed).
##
## Scenarios (MT_PUPPET value):
##   "objects" (default) — sculpt hills, place spheres → mt_puppet_objects.png
##   "perslot"           — flat terrain, 2 slots different scale, paint slot 1
##                          → mt_puppet_perslot.png
##   "lodseed"           — raise map_size with a far camera; assert the terrain
##                          never meshes full-res on load → mt_puppet_lodseed.png
##                          + MT_PUPPET_LODSEED_PASS/FAIL line
##
## Why a separate plugin (not a hook in mobile_terrain): keeps the shipping
## addon free of test code. It drives the terrain via the node's public methods
## + EditorInterface, so it needs no access to the mobile_terrain plugin object.

const SCENE_PATH := "res://puppet.tscn"


# Faithful duck-typed stand-in for the mobile_terrain EditorPlugin, exposing the
# fields/methods TerrainInputRouter touches AND mirroring the real plugin's
# object-placement bookkeeping (foliage_placed recording + commit_placement_undo
# on finalise, using the puppet's REAL EditorUndoRedoManager). Lets the puppet
# drive the exact path a user's touch takes, including the undo commit that runs
# between separate taps — so multi-tap accumulation is verified, not just one
# gesture.
class _RouterStub:
	extends RefCounted
	var selected_node
	var _cached_camera
	var _cached_mouse_pos: Vector2 = Vector2.ZERO
	var brush_enabled: bool = true
	var _touch_active: bool = false
	var is_sculpting: bool = false
	var placement_records: Array = []
	var placement_initial_counts: Dictionary = {}
	var splatmap_backup: PackedByteArray = PackedByteArray()
	var heightmap_backup: PackedFloat32Array = PackedFloat32Array()
	var brush_cursor = null
	var _last_brush_hit: Vector3 = Vector3.INF
	var undo_redo  # real EditorUndoRedoManager, injected by the scenario

	func _conform_decal_to_surface(_pos) -> void:
		pass

	func _ensure_backup_for_current_tool() -> void:
		pass

	# Mirrors mobile_terrain_plugin._on_foliage_placed.
	func _on_foliage_placed(mmi, index: int, tf: Transform3D) -> void:
		if not is_instance_valid(mmi):
			return
		if not placement_initial_counts.has(mmi):
			placement_initial_counts[mmi] = index
		placement_records.append({"mmi": mmi, "index": index, "transform": tf})

	# Mirrors mobile_terrain_plugin._finalize_active_stroke for tool 8.
	func _finalize_active_stroke() -> void:
		if selected_node != null:
			selected_node.end_stroke()
		if undo_redo != null and not placement_records.is_empty():
			TerrainUndoRecorder.commit_placement_undo(
				undo_redo, selected_node, placement_records, placement_initial_counts
			)
		placement_records.clear()
		placement_initial_counts.clear()


func _enter_tree() -> void:
	if OS.has_environment("MT_PUPPET"):
		call_deferred("_run")


func _run() -> void:
	var scenario := OS.get_environment("MT_PUPPET")
	var ei := get_editor_interface()
	await _frames(25)
	print("MT_PUPPET: opening %s (scenario=%s)" % [SCENE_PATH, scenario])
	ei.open_scene_from_path(SCENE_PATH)
	await _frames(35)
	ei.set_main_screen_editor("3D")
	await _frames(12)
	var terrain = ei.get_edited_scene_root()
	var vp := ei.get_editor_viewport_3d(0)
	print("MT_PUPPET: terrain=%s viewport=%s" % [str(terrain), str(vp)])
	if terrain == null or vp == null:
		printerr("MT_PUPPET: missing terrain/viewport")
		get_tree().quit(1)
		return
	match scenario:
		"perslot":
			await _scenario_perslot(terrain, vp)
		"lodseed":
			await _scenario_lodseed(terrain, vp)
		_:
			await _scenario_objects(terrain, vp)
	get_tree().quit()


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _shot(vp: Viewport, shot_name: String) -> void:
	var tex := vp.get_texture()
	var img: Image = tex.get_image() if tex != null else null
	var p := "user://" + shot_name + ".png"
	if img != null and img.save_png(p) == OK:
		print("MT_PUPPET_SHOT: " + ProjectSettings.globalize_path(p))
	else:
		printerr("MT_PUPPET: shot failed " + shot_name)


# Sculpt hills, then place spheres by driving the REAL input router with
# synthetic touch events (press + drag trail + release) — the same path a
# user's finger takes. Asserts objects actually landed, then shoots.
func _scenario_objects(terrain, vp: Viewport) -> void:
	var hd := PackedFloat32Array()
	hd.resize(64 * 64)
	for z in range(64):
		for x in range(64):
			hd[z * 64 + x] = 3.0 + 1.4 * sin(x * 0.28) * cos(z * 0.24)
	terrain.height_data = hd
	terrain.force_update_all()
	await _frames(8)
	var cam := vp.get_camera_3d()
	if cam != null:
		# Steep near-top-down view so every placed object is visible (a low/3-4
		# angle lines the trail up in depth and the front sphere hides the rest).
		cam.look_at_from_position(Vector3(32, 78, 72), Vector3(32, 2, 34), Vector3.UP)
	await _frames(5)
	var sphere := SphereMesh.new()
	sphere.radius = 3.5
	sphere.height = 7.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.2, 0.15)
	sphere.material = mat
	terrain.asset_meshes.clear()
	terrain.asset_meshes.append(sphere)
	terrain.current_object_slot = 0
	terrain.current_tool = 8
	terrain.last_placement_pos = Vector3.INF

	# Separate TAPS (press+release each) at different points — exactly the
	# user's "tap here, tap there" sequence. object_spacing wide so the spheres
	# don't overlap; the INF reset per gesture is the router's job.
	terrain.object_spacing = 2.0
	var stub := _RouterStub.new()
	stub.selected_node = terrain
	stub.undo_redo = get_undo_redo()
	terrain.foliage_placed.connect(stub._on_foliage_placed)
	var screen_pts: Array[Vector2] = []
	var vs: Vector2 = vp.get_visible_rect().size
	if vs.x > 0.0 and vs.y > 0.0:
		for k in range(4):
			var fx: float = lerpf(0.46, 0.62, float(k) / 3.0)
			screen_pts.append(Vector2(vs.x * fx, vs.y * 0.5))
	# Drive each tap as its own press→release gesture through the REAL router
	# (and the real undo commit between taps). Record the running count so a
	# "single object that relocates each tap" regression is caught.
	var counts: Array[int] = []
	for pt in screen_pts:
		TerrainInputRouter.route(stub, cam, _mk_touch(0, true, pt))
		TerrainInputRouter.route(stub, cam, _mk_touch(0, false, pt))
		await _frames(3)
		counts.append(_count_object_instances(terrain))
	print("MT_PUPPET_OBJECTS counts after each tap: %s" % str(counts))
	for mesh in terrain.multimesh_instances:
		var dbg = terrain.multimesh_instances[mesh]
		if is_instance_valid(dbg) and dbg.multimesh != null:
			var origins: Array = []
			for i in range(dbg.multimesh.instance_count):
				origins.append(dbg.multimesh.get_instance_transform(i).origin.round())
			print("MT_PUPPET_OBJECTS origins: %s" % str(origins))

	var placed := _count_object_instances(terrain)
	# Each distinct tap must ADD an instance — N taps → N objects. A relocating
	# single object would leave placed==1.
	var verdict := "PASS" if placed >= screen_pts.size() else "FAIL"
	print(
		(
			"MT_PUPPET_OBJECTS_%s: placed=%d after %d taps (expected %d)"
			% [verdict, placed, screen_pts.size(), screen_pts.size()]
		)
	)
	_shot(vp, "mt_puppet_objects")  # proof shot at full count, before the undo sim

	# Exercise the undo RESTORE primitive that commit_placement_undo registers
	# (_apply_object_buffer) with the real RenderingServer buffer: shrink to N-1
	# and rewrite the buffer, exactly as an undo of the last tap would. The
	# realloc-clear bug also corrupts undo, so without the buffer-restore every
	# survivor would collapse onto the world origin. All taps were far from
	# origin, so any survivor near (0,0,0) means the bug is back.
	var after_undo := placed
	var survivors_ok := true
	for mesh in terrain.multimesh_instances:
		var u = terrain.multimesh_instances[mesh]
		if not (is_instance_valid(u) and u.multimesh != null):
			continue
		var mmx: MultiMesh = u.multimesh
		var keep: int = mmx.instance_count - 1
		var full: PackedFloat32Array = mmx.buffer.duplicate()
		var stride: int = full.size() / mmx.instance_count if mmx.instance_count > 0 else 0
		terrain._apply_object_buffer(mmx, keep, full.slice(0, keep * stride))
		await _frames(2)
		for i in range(mmx.instance_count):
			if mmx.get_instance_transform(i).origin.length() < 1.0:
				survivors_ok = false
	after_undo = _count_object_instances(terrain)
	var uverdict := "PASS" if (after_undo == placed - 1 and survivors_ok) else "FAIL"
	print(
		(
			"MT_PUPPET_UNDO_%s: count %d->%d, survivors_kept=%s"
			% [uverdict, placed, after_undo, str(survivors_ok)]
		)
	)


func _count_object_instances(terrain) -> int:
	var n := 0
	for mesh in terrain.multimesh_instances:
		var mmi = terrain.multimesh_instances[mesh]
		if is_instance_valid(mmi) and mmi.multimesh != null:
			n += mmi.multimesh.instance_count
	return n


func _mk_touch(idx: int, pressed: bool, pos: Vector2) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.pressed = pressed
	e.position = pos
	return e


func _mk_drag(idx: int, pos: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = pos
	return e


# Flat terrain, same checker on slots 0 & 1 with different per-slot scale, paint
# slot 1 into the right half, shoot — the two halves should tile differently.
func _scenario_perslot(terrain, vp: Viewport) -> void:
	var hd := PackedFloat32Array()
	hd.resize(64 * 64)
	hd.fill(2.0)
	terrain.height_data = hd
	terrain.force_update_all()
	await _frames(8)
	var checker := _make_checker(64)
	while terrain.terrain_textures.size() < 2:
		terrain.terrain_textures.append(null)
	terrain.terrain_textures[0] = checker
	terrain.terrain_textures[1] = checker
	terrain.texture_scale[0] = 0.015
	terrain.texture_scale[1] = 0.08
	terrain.update_shader_textures()
	terrain.current_tool = 7
	terrain.current_paint_slot = 1
	terrain.brush_radius = 18.0
	terrain.brush_strength = 2.0
	terrain.start_stroke()
	for k in range(6):
		var px := 40.0 + (k % 2) * 12.0
		var pz := 12.0 + (k / 2) * 20.0
		terrain.apply_brush_stroke_slope(Vector3(px, 2.0, pz), Vector3.UP)
	terrain.end_stroke()
	terrain.force_refresh_splatmap()
	var cam := vp.get_camera_3d()
	if cam != null:
		cam.look_at_from_position(Vector3(32, 40, 66), Vector3(32, 0, 28), Vector3.UP)
	await _frames(8)
	_shot(vp, "mt_puppet_perslot")


# Large-map load: prove the editor LOD seeds BEFORE the chunk build, so the
# whole terrain never materialises at full resolution (the transient full-res
# spike that OOM-closed the editor on big maps). Pull the camera far back, raise
# map_size to a deferred-build size, then track the PEAK number of chunks that
# are BOTH built (mesh != null) AND still at full-res stride 1. With the fix the
# LOD pass populates _chunk_lod before any chunk meshes, so from a bird's-eye
# distance ~every chunk builds coarse → peak ≈ 0. Without it the drain meshed
# all chunks full-res first → peak ≈ every chunk.
func _scenario_lodseed(terrain, vp: Viewport) -> void:
	var stress_map := 1024
	var c := float(stress_map) * 0.5
	var cam := vp.get_camera_3d()
	if cam != null:
		# Bird's-eye, high above the map centre so every chunk falls in the
		# farthest LOD band (collapses to one quad). Set BEFORE raising map_size
		# so the very first LOD seed already sees the far camera.
		cam.look_at_from_position(
			Vector3(c, float(stress_map) * 1.5, c), Vector3(c, 0.0, c), Vector3.UP
		)
	await _frames(3)
	terrain.map_size = stress_map  # triggers deferred build + the LOD seed hold
	var peak_full_res := 0
	var total := 0
	for _i in range(80):
		await get_tree().process_frame
		var n1 := 0
		for key in terrain.chunks:
			var chunk = terrain.chunks[key]
			if chunk != null and chunk.mesh != null and int(terrain._chunk_lod.get(key, 1)) == 1:
				n1 += 1
		if n1 > peak_full_res:
			peak_full_res = n1
		total = terrain.chunks.size()
	_shot(vp, "mt_puppet_lodseed")
	# A far bird's-eye view should leave ~zero full-res chunks; allow a small
	# margin for any chunk near the look-at point. A high peak means the whole
	# map meshed at full res on load — the OOM regression returning.
	var verdict := "PASS" if peak_full_res <= 8 else "FAIL"
	print(
		(
			"MT_PUPPET_LODSEED_%s: total_chunks=%d peak_full_res_built=%d (bound=8)"
			% [verdict, total, peak_full_res]
		)
	)


func _make_checker(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var on := ((x / 8) + (y / 8)) % 2 == 0
			img.set_pixel(x, y, Color(0.9, 0.9, 0.9, 1.0) if on else Color(0.12, 0.12, 0.12, 1.0))
	return ImageTexture.create_from_image(img)
