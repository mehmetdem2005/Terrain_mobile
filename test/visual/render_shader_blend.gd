@tool
extends SceneTree

# TKT-006 splatmap-blend diagnosis. Renders the REAL terrain.gdshader on a
# flat plane with 4 solid-colour albedo slots (R=red, G=green, B=blue,
# A=yellow) and a 4-quadrant splatmap (one slot dominant per quadrant). If
# the 4-way blend works, the plane shows four coloured quadrants. If slots
# 1-3 "don't integrate" (the user's report), they'll be missing/wrong.

var _frames := 0
var _shot_path := "user://shader_blend.png"


func _solid_tex(c: Color) -> ImageTexture:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)


func _blank_tex(c: Color) -> ImageTexture:
	return _solid_tex(c)


func _make_splatmap() -> ImageTexture:
	# 64x64, 4 quadrants. Each quadrant sets ONE channel to 255 (one slot
	# fully dominant) so a correct blend yields four flat colours.
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in range(n):
		for x in range(n):
			var left := x < n / 2
			var top := y < n / 2
			var c: Color
			if top and left:
				c = Color(1, 0, 0, 0)  # slot 0 (red)
			elif top and not left:
				c = Color(0, 1, 0, 0)  # slot 1 (green)
			elif not top and left:
				c = Color(0, 0, 1, 0)  # slot 2 (blue)
			else:
				c = Color(0, 0, 0, 1)  # slot 3 (yellow)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _process(_delta: float) -> bool:
	if _frames == 0:
		var shader: Shader = load("res://addons/mobile_terrain/shaders/terrain.gdshader")
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("splatmap", _make_splatmap())
		mat.set_shader_parameter("tex_scale", 1.0)
		mat.set_shader_parameter("normal_strength", 1.0)
		mat.set_shader_parameter("roughness_multiplier", 1.0)
		mat.set_shader_parameter("ao_strength", 0.0)
		mat.set_shader_parameter("texture_variation", 0.0)
		mat.set_shader_parameter("texture_cell_size", 10.0)
		mat.set_shader_parameter("rotation_jitter", 0.0)
		mat.set_shader_parameter("triplanar_blend", 0.0)
		mat.set_shader_parameter("mobile_quality", false)
		mat.set_shader_parameter("tex_a_0", _solid_tex(Color(0.9, 0.1, 0.1)))  # red
		mat.set_shader_parameter("tex_a_1", _solid_tex(Color(0.1, 0.8, 0.1)))  # green
		mat.set_shader_parameter("tex_a_2", _solid_tex(Color(0.2, 0.3, 0.95)))  # blue
		mat.set_shader_parameter("tex_a_3", _solid_tex(Color(0.95, 0.85, 0.1)))  # yellow
		for i in range(4):
			mat.set_shader_parameter("tex_n_%d" % i, _blank_tex(Color(0.5, 0.5, 1.0)))
			mat.set_shader_parameter("tex_r_%d" % i, _blank_tex(Color(1, 1, 1)))
			mat.set_shader_parameter("tex_ao_%d" % i, _blank_tex(Color(1, 1, 1)))

		var plane := PlaneMesh.new()
		plane.size = Vector2(10, 10)
		var mi := MeshInstance3D.new()
		mi.mesh = plane
		mi.material_override = mat
		root.add_child(mi)

		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 11.0
		cam.look_at_from_position(Vector3(0, 10, 0), Vector3(0, 0, 0), Vector3(0, 0, -1))
		root.add_child(cam)
		cam.make_current()

		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-90, 0, 0)
		root.add_child(light)
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.1, 0.1, 0.1)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(1, 1, 1)
		env.ambient_light_energy = 1.0
		var we := WorldEnvironment.new()
		we.environment = env
		root.add_child(we)

	_frames += 1
	if _frames >= 8:
		var img := root.get_texture().get_image()
		if img.save_png(_shot_path) == OK:
			print("BLEND_SHOT: " + ProjectSettings.globalize_path(_shot_path))
		quit(0)
		return true
	return false
