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
##
## Why a separate plugin (not a hook in mobile_terrain): keeps the shipping
## addon free of test code. It drives the terrain via the node's public methods
## + EditorInterface, so it needs no access to the mobile_terrain plugin object.

const SCENE_PATH := "res://puppet.tscn"


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


# Sculpt hills, place spheres along a line via the real placement path, shoot.
func _scenario_objects(terrain, vp: Viewport) -> void:
	var hd := PackedFloat32Array()
	hd.resize(64 * 64)
	for z in range(64):
		for x in range(64):
			hd[z * 64 + x] = 6.0 + 5.0 * sin(x * 0.35) * cos(z * 0.3)
	terrain.height_data = hd
	terrain.force_update_all()
	await _frames(8)
	var cam := vp.get_camera_3d()
	if cam != null:
		cam.look_at_from_position(Vector3(32, 15, 104), Vector3(34, 8, 56), Vector3.UP)
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
	terrain.start_stroke()
	for k in range(6):
		var wx := 12.0 + k * 8.0
		var wz := 56.0
		var wy: float = terrain.get_height(int(wx), int(wz))
		terrain.apply_brush_stroke_slope(Vector3(wx, wy, wz), Vector3.UP)
	terrain.end_stroke()
	await _frames(6)
	_shot(vp, "mt_puppet_objects")


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


func _make_checker(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var on := ((x / 8) + (y / 8)) % 2 == 0
			img.set_pixel(x, y, Color(0.9, 0.9, 0.9, 1.0) if on else Color(0.12, 0.12, 0.12, 1.0))
	return ImageTexture.create_from_image(img)
