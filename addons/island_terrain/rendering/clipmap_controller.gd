@tool
extends Node3D
class_name IslandTerrainClipmapController

const MeshBuilder = preload("res://addons/island_terrain/rendering/clipmap_mesh_builder.gd")

var _manifest: Resource
var _budget: Resource
var _source_material: ShaderMaterial
var _height_texture: Texture2D
var _camera: Camera3D
var _pending_levels: Array[int] = []
var _level_instances: Array[MeshInstance3D] = []
var _configured: bool = false


func _ready() -> void:
	set_process(true)


func configure(
	manifest: Resource,
	budget: Resource,
	material: ShaderMaterial,
	height_texture: Texture2D
) -> void:
	_manifest = manifest
	_budget = budget
	_source_material = material
	_height_texture = height_texture
	_budget.sanitize(Engine.is_editor_hint())
	rebuild_deferred()


func set_tracking_camera(camera: Camera3D) -> void:
	_camera = camera


func set_height_texture(texture: Texture2D) -> void:
	_height_texture = texture
	for instance in _level_instances:
		if not is_instance_valid(instance):
			continue
		var material := instance.material_override as ShaderMaterial
		if material != null:
			material.set_shader_parameter("height_texture", _height_texture)


func rebuild_deferred() -> void:
	_clear_levels()
	_pending_levels.clear()
	if _manifest == null or _budget == null or _source_material == null or _height_texture == null:
		_configured = false
		return
	for level in range(_budget.clipmap_levels):
		_pending_levels.append(level)
	_level_instances.resize(_budget.clipmap_levels)
	_configured = true


func _process(_delta: float) -> void:
	if not _configured:
		return
	_build_within_frame_budget()
	_update_camera_snapping()


func _build_within_frame_budget() -> void:
	if _pending_levels.is_empty():
		return
	var start_usec: int = Time.get_ticks_usec()
	var budget_usec: int = maxi(250, int(_budget.frame_work_budget_ms * 1000.0))
	var built_this_frame: int = 0
	while not _pending_levels.is_empty():
		var level: int = _pending_levels.pop_front()
		_build_level(level)
		built_this_frame += 1
		# One level per frame is the mobile default. The time check also protects
		# custom low-resolution profiles where a second level would be cheap.
		if built_this_frame >= 1 or Time.get_ticks_usec() - start_usec >= budget_usec:
			break


func _build_level(level: int) -> void:
	var instance := MeshInstance3D.new()
	instance.name = "ClipmapLOD%d" % level
	instance.mesh = MeshBuilder.build_level(_budget.base_quads, level)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	instance.extra_cull_margin = float(_manifest.max_height_m) + 32.0

	var material := _source_material.duplicate() as ShaderMaterial
	material.set_shader_parameter("height_texture", _height_texture)
	material.set_shader_parameter("world_size_m", float(_manifest.world_size_m))
	material.set_shader_parameter("max_height_m", _manifest.max_height_m)
	material.set_shader_parameter("sea_level_m", _manifest.sea_level_m)
	material.set_shader_parameter("lod_level", float(level))
	material.set_shader_parameter("skirt_depth_m", maxf(4.0, float(1 << level) * 2.0))
	instance.material_override = material
	add_child(instance)
	_level_instances[level] = instance


func _update_camera_snapping() -> void:
	var camera: Camera3D = _camera
	if not is_instance_valid(camera):
		camera = get_viewport().get_camera_3d()
	if not is_instance_valid(camera):
		return
	var camera_local: Vector3 = to_local(camera.global_position)
	for level in range(_level_instances.size()):
		var instance: MeshInstance3D = _level_instances[level]
		if not is_instance_valid(instance):
			continue
		var grid_spacing: float = float(1 << level)
		instance.position = Vector3(
			floorf(camera_local.x / grid_spacing) * grid_spacing,
			0.0,
			floorf(camera_local.z / grid_spacing) * grid_spacing
		)


func _clear_levels() -> void:
	for instance in _level_instances:
		if is_instance_valid(instance):
			instance.queue_free()
	_level_instances.clear()
