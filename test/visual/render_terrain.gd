@tool
extends SceneTree

# TKT-003 visual render harness.
#
# Proves the headed (xvfb + llvmpipe/lavapipe software GPU) pipeline works
# and gives a real screenshot of terrain geometry produced by the extracted
# ChunkRenderer — visual confirmation on top of the headless mesh-invariant
# unit tests. Reused as the basis for Phase B UI screenshot verification.
#
# Run:  xvfb-run -a godot --rendering-method gl_compatibility \
#         --script res://test/visual/render_terrain.gd --path .

const ChunkRenderer := preload("res://addons/mobile_terrain/systems/chunk_renderer.gd")

var _frames := 0
var _setup_done := false
var _shot_path := "user://terrain_render.png"

func _build_scene() -> void:
	var map_size := 64
	var chunk_size := 16

	# Procedural ridged heightmap so the screenshot shows real relief
	# (hills + a diagonal ridge), not a flat plane.
	var heights := PackedFloat32Array()
	heights.resize(map_size * map_size)
	for z in range(map_size):
		for x in range(map_size):
			var fx := float(x) / float(map_size)
			var fz := float(z) / float(map_size)
			var h := sin(fx * TAU * 2.0) * cos(fz * TAU * 2.0) * 6.0
			h += sin(fx * TAU * 5.0) * 1.5
			h += (1.0 - absf(fx - fz)) * 4.0  # diagonal ridge
			heights[z * map_size + x] = h

	var terrain := Node3D.new()
	root.add_child(terrain)

	var num_chunks := map_size / chunk_size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.55, 0.32)
	mat.roughness = 0.9
	for cz in range(num_chunks):
		for cx in range(num_chunks):
			var mesh: ArrayMesh = ChunkRenderer.build_chunk_mesh(heights, map_size, chunk_size, cx, cz)
			if mesh == null:
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.position = Vector3(cx * chunk_size, 0, cz * chunk_size)
			mi.material_override = mat
			terrain.add_child(mi)

	var cam := Camera3D.new()
	# look_at_from_position computes the transform directly — no "inside
	# tree" requirement, so it's safe regardless of add_child ordering.
	cam.look_at_from_position(
		Vector3(float(map_size) * 0.5, 46.0, float(map_size) * 1.25),
		Vector3(float(map_size) * 0.5, 2.0, float(map_size) * 0.45),
		Vector3.UP)
	root.add_child(cam)
	cam.make_current()

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48.0, -38.0, 0.0)
	light.light_energy = 1.2
	root.add_child(light)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.53, 0.71, 0.92)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.48, 0.55)
	env.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)

func _process(_delta: float) -> bool:
	# Build on the first frame — by now root (the viewport) is live, which
	# it isn't yet during _initialize().
	if not _setup_done:
		_setup_done = true
		_build_scene()
		return false
	_frames += 1
	# Let a few frames render so lighting/material settle before capture.
	if _frames >= 6:
		var img := root.get_texture().get_image()
		var err := img.save_png(_shot_path)
		if err == OK:
			print("SHOT_SAVED: " + ProjectSettings.globalize_path(_shot_path))
		else:
			printerr("SHOT_FAILED err=%d" % err)
		quit(0)
		return true
	return false
