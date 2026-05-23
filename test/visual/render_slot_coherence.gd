@tool
extends SceneTree

# TKT-010 slot-coherence diagnosis. Renders the REAL terrain.gdshader on a
# gently rolling patch, slot 0 only, with the SAME checker pattern fed to
# albedo, roughness AND ao, and texture_variation / rotation_jitter /
# triplanar all ON.
#
# Before TKT-010: albedo (and normal) ran through _mt_sample_var (variation
# + jitter) and triplanar, while roughness/ao sampled a flat texture(uv).
# So the albedo colour checker shifts/rotates per cell while the ao shadow
# checker stays a rigid grid — the two patterns DON'T line up.
# After TKT-010: all four maps share _mt_slot_sample, so the albedo colour
# squares and the ao shadow squares land on the SAME cells — patterns align.
#
# Usage: -- <out_name>

var _frames := 0
var _shot := "user://slot_coherence.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_shot = "user://" + args[0]


# Distinct colour checker for albedo (warm vs cool).
func _albedo_checker() -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in range(n):
		for x in range(n):
			var on := ((x / 8) + (y / 8)) % 2 == 0
			img.set_pixel(x, y, Color(0.95, 0.55, 0.15) if on else Color(0.12, 0.18, 0.35))
	return ImageTexture.create_from_image(img)


# Single-channel checker for ao/roughness: on = bright (R=1), off = dark.
func _scalar_checker(on_val: float, off_val: float) -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in range(n):
		for x in range(n):
			var on := ((x / 8) + (y / 8)) % 2 == 0
			var v := on_val if on else off_val
			img.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(img)


func _blank(c: Color) -> ImageTexture:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)


func _process(_delta: float) -> bool:
	if _frames == 0:
		var ChunkRenderer = load("res://addons/mobile_terrain/systems/chunk_renderer.gd")
		var map_size := 64
		var chunk_size := 32
		var heights := PackedFloat32Array()
		heights.resize(map_size * map_size)
		for z in range(map_size):
			for x in range(map_size):
				var fx := float(x) / float(map_size)
				var fz := float(z) / float(map_size)
				heights[z * map_size + x] = sin(fx * TAU) * cos(fz * TAU) * 8.0

		var shader: Shader = load("res://addons/mobile_terrain/shaders/terrain.gdshader")
		var mat := ShaderMaterial.new()
		mat.shader = shader
		var sm := Image.create(map_size, map_size, false, Image.FORMAT_RGBA8)
		sm.fill(Color(1, 0, 0, 0))  # all slot 0
		mat.set_shader_parameter("splatmap", ImageTexture.create_from_image(sm))
		mat.set_shader_parameter("tex_scale", 0.15)
		mat.set_shader_parameter("normal_strength", 1.0)
		mat.set_shader_parameter("roughness_multiplier", 1.0)
		# AO fully expressed so the ao checker reads as visible shadow squares.
		mat.set_shader_parameter("ao_strength", 1.0)
		# Anti-tile + triplanar all ON — this is what desynced the maps before.
		mat.set_shader_parameter("texture_variation", 0.85)
		mat.set_shader_parameter("texture_cell_size", 8.0)
		mat.set_shader_parameter("rotation_jitter", 0.4)
		mat.set_shader_parameter("triplanar_blend", 0.5)
		var albedo := _albedo_checker()
		var ao_check := _scalar_checker(1.0, 0.25)
		var rough_check := _scalar_checker(0.15, 0.9)
		for i in range(4):
			mat.set_shader_parameter("tex_a_%d" % i, albedo)
			mat.set_shader_parameter("tex_n_%d" % i, _blank(Color(0.5, 0.5, 1.0)))
			mat.set_shader_parameter("tex_r_%d" % i, rough_check)
			mat.set_shader_parameter("tex_ao_%d" % i, ao_check)

		var terrain := Node3D.new()
		root.add_child(terrain)
		var nc := map_size / chunk_size
		for cz in range(nc):
			for cx in range(nc):
				var mesh: ArrayMesh = ChunkRenderer.build_chunk_mesh(
					heights, map_size, chunk_size, cx, cz
				)
				if mesh == null:
					continue
				var mi := MeshInstance3D.new()
				mi.mesh = mesh
				mi.position = Vector3(cx * chunk_size, 0, cz * chunk_size)
				mi.material_override = mat
				terrain.add_child(mi)

		var cam := Camera3D.new()
		# Top-down-ish so the checker grid is read flat and pattern alignment
		# (albedo colour vs ao shadow) is obvious.
		cam.look_at_from_position(
			Vector3(float(map_size) * 0.5, 70.0, float(map_size) * 0.62),
			Vector3(float(map_size) * 0.5, 0.0, float(map_size) * 0.5),
			Vector3.UP
		)
		root.add_child(cam)
		cam.make_current()
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-70, -25, 0)
		root.add_child(light)
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.5, 0.6, 0.7)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.7, 0.7, 0.7)
		env.ambient_light_energy = 0.9
		var we := WorldEnvironment.new()
		we.environment = env
		root.add_child(we)

	_frames += 1
	if _frames >= 6:
		var img := root.get_texture().get_image()
		if img.save_png(_shot) == OK:
			print("COHERENCE_SHOT: " + ProjectSettings.globalize_path(_shot))
		quit(0)
		return true
	return false
