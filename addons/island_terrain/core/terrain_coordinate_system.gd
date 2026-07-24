@tool
extends RefCounted
class_name IslandTerrainCoordinateSystem

const Manifest = preload("res://addons/island_terrain/core/terrain_manifest.gd")

var _manifest: Manifest


func _init(manifest: Manifest) -> void:
	_manifest = manifest


func world_half_extent() -> float:
	return float(_manifest.world_size_m) * 0.5


func is_inside_world(world_position: Vector3) -> bool:
	var half: float = world_half_extent()
	return world_position.x >= -half and world_position.z >= -half \
		and world_position.x < half and world_position.z < half


func world_to_region(world_position: Vector3) -> Vector2i:
	var half: float = world_half_extent()
	var local_x: float = world_position.x + half
	var local_z: float = world_position.z + half
	return Vector2i(
		floori(local_x / float(_manifest.region_size_m)),
		floori(local_z / float(_manifest.region_size_m))
	)


func world_to_region_clamped(world_position: Vector3) -> Vector2i:
	return clamp_region(world_to_region(world_position))


func clamp_region(coord: Vector2i) -> Vector2i:
	var max_index: int = maxi(0, _manifest.region_count_axis() - 1)
	return Vector2i(clampi(coord.x, 0, max_index), clampi(coord.y, 0, max_index))


func region_origin_world(coord: Vector2i) -> Vector3:
	var half: float = world_half_extent()
	return Vector3(
		-half + float(coord.x * _manifest.region_size_m),
		0.0,
		-half + float(coord.y * _manifest.region_size_m)
	)


func world_to_region_local(world_position: Vector3, coord: Vector2i) -> Vector2:
	var origin: Vector3 = region_origin_world(coord)
	return Vector2(world_position.x - origin.x, world_position.z - origin.z)


func world_to_region_pixel(world_position: Vector3, coord: Vector2i) -> Vector2i:
	var local: Vector2 = world_to_region_local(world_position, coord)
	var interval_count: int = maxi(1, _manifest.region_samples - 1)
	var samples_per_meter: float = float(interval_count) / float(_manifest.region_size_m)
	return Vector2i(
		clampi(roundi(local.x * samples_per_meter), 0, interval_count),
		clampi(roundi(local.y * samples_per_meter), 0, interval_count)
	)


func region_pixel_to_world(coord: Vector2i, pixel: Vector2i, height_m: float = 0.0) -> Vector3:
	var origin: Vector3 = region_origin_world(coord)
	var interval_count: int = maxi(1, _manifest.region_samples - 1)
	var meters_per_sample: float = float(_manifest.region_size_m) / float(interval_count)
	return Vector3(
		origin.x + float(pixel.x) * meters_per_sample,
		height_m,
		origin.z + float(pixel.y) * meters_per_sample
	)


func region_linear_index(pixel: Vector2i) -> int:
	return pixel.y * _manifest.region_samples + pixel.x
