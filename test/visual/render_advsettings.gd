@tool
extends SceneTree

# DIAGNOSTIC: render the "Gelişmiş Ayarlar" texture knobs one at a time on a
# directional (diagonal-stripe) texture so each effect is unmistakable. Flat
# ground + a top-down camera isolates the texture look from terrain shape.
# Saves: advset_base / advset_rotation / advset_variation / advset_triplanar.
# Lets us SEE which knobs actually change the surface (the user reports some
# have "no effect") and what rotation_jitter looks like (the "rotating blocks").

const ChunkRenderer := preload("res://addons/mobile_terrain/systems/chunk_renderer.gd")

var _frames := 0
var _mat: ShaderMaterial = null


func _stripes() -> ImageTexture:
	# Diagonal high-contrast stripes — rotation of a cell is immediately obvious.
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in range(n):
		for x in range(n):
			var on := (((x + y) / 6) % 2) == 0
			img.set_pixel(x, y, Color(0.95, 0.75, 0.2) if on else Color(0.1, 0.15, 0.3))
	return ImageTexture.create_from_image(img)


func _blank(c: Color) -> ImageTexture:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)


func _save(name: String) -> void:
	var img := root.get_texture().get_image()
	var p := "user://" + name + ".png"
	if img.save_png(p) == OK:
		print("ADVSET_SHOT: %s -> %s" % [name, ProjectSettings.globalize_path(p)])


func _process(_delta: float) -> bool:
	if _frames == 0:
		var map_size := 64
		var chunk_size := 32
		# Mostly flat, with a ramp on the +x half so triplanar has a steep face.
		var heights := PackedFloat32Array()
		heights.resize(map_size * map_size)
		for z in range(map_size):
			for x in range(map_size):
				heights[z * map_size + x] = 0.0 if x < 40 else float(x - 40) * 2.2

		var shader: Shader = load("res://addons/mobile_terrain/shaders/terrain.gdshader")
		_mat = ShaderMaterial.new()
		_mat.shader = shader
		var sm := Image.create(map_size, map_size, false, Image.FORMAT_RGBA8)
		sm.fill(Color(1, 0, 0, 0))  # splatmap all slot 0
		_mat.set_shader_parameter("splatmap", ImageTexture.create_from_image(sm))
		# CURRENT shader uses ARRAY uniforms (the old scalar tex_scale is gone).
		var scale_arr := [0.08, 0.08, 0.08, 0.08]
		_mat.set_shader_parameter("tex_scale_arr", scale_arr)
		_mat.set_shader_parameter("normal_strength_arr", [1.0, 1.0, 1.0, 1.0])
		_mat.set_shader_parameter("roughness_mult_arr", [1.0, 1.0, 1.0, 1.0])
		_mat.set_shader_parameter("ao_strength_arr", [0.0, 0.0, 0.0, 0.0])
		_mat.set_shader_parameter("texture_variation", 0.0)
		_mat.set_shader_parameter("texture_cell_size", 12.0)
		_mat.set_shader_parameter("rotation_jitter", 0.0)
		_mat.set_shader_parameter("triplanar_blend", 0.0)
		var stripes := _stripes()
		for i in range(4):
			_mat.set_shader_parameter("tex_a_%d" % i, stripes)
			_mat.set_shader_parameter("tex_n_%d" % i, _blank(Color(0.5, 0.5, 1.0)))
			_mat.set_shader_parameter("tex_r_%d" % i, _blank(Color(1, 1, 1)))
			_mat.set_shader_parameter("tex_ao_%d" % i, _blank(Color(1, 1, 1)))

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
				mi.material_override = _mat
				terrain.add_child(mi)

		var cam := Camera3D.new()
		# Near-top-down so the stripe pattern reads flat (rotation/variation clear).
		cam.look_at_from_position(
			Vector3(float(map_size) * 0.5, 70.0, float(map_size) * 0.52),
			Vector3(float(map_size) * 0.5, 0.0, float(map_size) * 0.48),
			Vector3.UP
		)
		root.add_child(cam)
		cam.make_current()
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-70, -30, 0)
		root.add_child(light)
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.5, 0.6, 0.7)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.8, 0.8, 0.8)
		env.ambient_light_energy = 1.0
		var we := WorldEnvironment.new()
		we.environment = env
		root.add_child(we)

	_frames += 1
	# Baseline (all knobs 0).
	if _frames == 6:
		_save("advset_base")
		_mat.set_shader_parameter("rotation_jitter", 0.8)
	# Rotation jitter on.
	elif _frames == 12:
		_save("advset_rotation")
		_mat.set_shader_parameter("rotation_jitter", 0.0)
		_mat.set_shader_parameter("texture_variation", 0.9)
	# Variation on.
	elif _frames == 18:
		_save("advset_variation")
		_mat.set_shader_parameter("texture_variation", 0.0)
		_mat.set_shader_parameter("triplanar_blend", 0.9)
	# Triplanar on (visible on the +x ramp).
	elif _frames == 24:
		_save("advset_triplanar")
		quit(0)
		return true
	return false
