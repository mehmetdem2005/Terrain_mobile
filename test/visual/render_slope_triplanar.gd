@tool
extends SceneTree

# TKT-006 slope-stretch diagnosis. Builds a steep ridge with ChunkRenderer,
# textures it with a checker pattern through the REAL terrain.gdshader, and
# renders it with mobile_quality + triplanar_blend taken from CLI args:
#   --  <mobile_quality 0|1> <triplanar_blend 0..1> <out_name>
# A checker on a steep face shows obvious vertical streaking when triplanar
# is off/bypassed, and crisp squares when triplanar is active.

const ChunkRenderer := preload("res://addons/mobile_terrain/systems/chunk_renderer.gd")

var _frames := 0
var _mobile := true
var _tri := 0.8
var _shot := "user://slope_tri.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_mobile = args[0] == "1"
	if args.size() >= 2:
		_tri = args[1].to_float()
	if args.size() >= 3:
		_shot = "user://" + args[2]


func _checker_tex() -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in range(n):
		for x in range(n):
			var on := ((x / 8) + (y / 8)) % 2 == 0
			img.set_pixel(x, y, Color(0.95, 0.55, 0.15) if on else Color(0.15, 0.2, 0.35))
	var t := ImageTexture.create_from_image(img)
	return t


func _blank(c: Color) -> ImageTexture:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)


func _process(_delta: float) -> bool:
	if _frames == 0:
		var map_size := 64
		var chunk_size := 32
		# Sharp cones/ridges so there are plenty of steep faces for the
		# checker to streak on when triplanar is off/bypassed.
		var heights := PackedFloat32Array()
		heights.resize(map_size * map_size)
		for z in range(map_size):
			for x in range(map_size):
				var fx := float(x) / float(map_size)
				var fz := float(z) / float(map_size)
				var h := sin(fx * TAU * 1.5) * cos(fz * TAU * 1.5) * 18.0
				h += (1.0 - absf(fx - fz)) * 14.0
				heights[z * map_size + x] = h

		var shader: Shader = load("res://addons/mobile_terrain/shaders/terrain.gdshader")
		var mat := ShaderMaterial.new()
		mat.shader = shader
		# Splatmap all slot 0.
		var sm := Image.create(map_size, map_size, false, Image.FORMAT_RGBA8)
		sm.fill(Color(1, 0, 0, 0))
		mat.set_shader_parameter("splatmap", ImageTexture.create_from_image(sm))
		mat.set_shader_parameter("tex_scale", 0.12)
		mat.set_shader_parameter("normal_strength", 1.0)
		mat.set_shader_parameter("roughness_multiplier", 1.0)
		mat.set_shader_parameter("ao_strength", 0.0)
		mat.set_shader_parameter("texture_variation", 0.0)
		mat.set_shader_parameter("texture_cell_size", 10.0)
		mat.set_shader_parameter("rotation_jitter", 0.0)
		mat.set_shader_parameter("triplanar_blend", _tri)
		mat.set_shader_parameter("mobile_quality", _mobile)
		var checker := _checker_tex()
		for i in range(4):
			mat.set_shader_parameter("tex_a_%d" % i, checker)
			mat.set_shader_parameter("tex_n_%d" % i, _blank(Color(0.5, 0.5, 1.0)))
			mat.set_shader_parameter("tex_r_%d" % i, _blank(Color(1, 1, 1)))
			mat.set_shader_parameter("tex_ao_%d" % i, _blank(Color(1, 1, 1)))

		var terrain := Node3D.new()
		root.add_child(terrain)
		var nc := map_size / chunk_size
		for cz in range(nc):
			for cx in range(nc):
				var mesh: ArrayMesh = ChunkRenderer.build_chunk_mesh(heights, map_size, chunk_size, cx, cz)
				if mesh == null:
					continue
				var mi := MeshInstance3D.new()
				mi.mesh = mesh
				mi.position = Vector3(cx * chunk_size, 0, cz * chunk_size)
				mi.material_override = mat
				terrain.add_child(mi)

		var cam := Camera3D.new()
		# Proven framing from render_terrain.gd — angled bird's-eye that
		# shows the whole patch and its slopes clearly.
		cam.look_at_from_position(
			Vector3(float(map_size) * 0.5, 46.0, float(map_size) * 1.25),
			Vector3(float(map_size) * 0.5, 2.0, float(map_size) * 0.45),
			Vector3.UP)
		root.add_child(cam)
		cam.make_current()
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-48, -38, 0)
		root.add_child(light)
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.5, 0.6, 0.7)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.6, 0.6, 0.6)
		env.ambient_light_energy = 0.8
		var we := WorldEnvironment.new()
		we.environment = env
		root.add_child(we)

	_frames += 1
	if _frames >= 6:
		var img := root.get_texture().get_image()
		if img.save_png(_shot) == OK:
			print("SLOPE_SHOT: " + ProjectSettings.globalize_path(_shot))
		quit(0)
		return true
	return false
