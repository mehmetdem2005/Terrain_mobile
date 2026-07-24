@tool
extends RefCounted
class_name IslandTerrainRegionRepository

const RegionData = preload("res://addons/island_terrain/core/terrain_region_data.gd")

var _world_data_root: String
var _manifest: Resource
var _budget: Resource
var _cache: Dictionary = {}
var _lru: Array[Vector2i] = []
var _dirty: Dictionary = {}
var _cached_bytes: int = 0


func _init(world_data_root: String, manifest: Resource, budget: Resource) -> void:
	_world_data_root = world_data_root.trim_suffix("/")
	_manifest = manifest
	_budget = budget
	_ensure_directories()


func get_or_create(coord: Vector2i) -> Resource:
	if not _manifest.contains_region(coord):
		return null
	if _cache.has(coord):
		_touch(coord)
		return _cache[coord]

	var region: Resource = _load_region(coord)
	if region == null:
		region = RegionData.new()
		region.initialize(coord, _manifest.region_samples)
	_admit(coord, region)
	return region


func get_cached(coord: Vector2i) -> Resource:
	if not _cache.has(coord):
		return null
	_touch(coord)
	return _cache[coord]


func mark_dirty(coord: Vector2i) -> void:
	if _cache.has(coord):
		_dirty[coord] = true


func is_dirty(coord: Vector2i) -> bool:
	return _dirty.has(coord)


func save_dirty(max_regions: int = 1) -> int:
	var saved: int = 0
	var coords: Array = _dirty.keys()
	for untyped_coord in coords:
		if saved >= maxi(1, max_regions):
			break
		var coord: Vector2i = untyped_coord
		if not _cache.has(coord):
			_dirty.erase(coord)
			continue
		var error: Error = _save_region(coord, _cache[coord])
		if error == OK:
			_dirty.erase(coord)
			saved += 1
		else:
			push_error("IT-004: Region save failed for %s with error %d" % [coord, error])
	return saved


func flush_all() -> Error:
	while not _dirty.is_empty():
		var before: int = _dirty.size()
		save_dirty(before)
		if _dirty.size() == before:
			return ERR_CANT_CREATE
	return OK


func cached_region_count() -> int:
	return _cache.size()


func cached_memory_bytes() -> int:
	return _cached_bytes


func dirty_region_count() -> int:
	return _dirty.size()


func clear_clean_cache() -> void:
	var coords: Array[Vector2i] = _lru.duplicate()
	for coord in coords:
		if not _dirty.has(coord):
			_evict(coord)


func region_file_path(coord: Vector2i) -> String:
	return "%s/regions/region_%d_%d.res" % [_world_data_root, coord.x, coord.y]


func _load_region(coord: Vector2i) -> Resource:
	var path: String = region_file_path(coord)
	if not ResourceLoader.exists(path):
		return null
	var loaded: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if loaded == null or not loaded.has_method("validate_dimensions"):
		push_error("IT-003: Invalid region resource at %s" % path)
		return null
	var errors: PackedStringArray = loaded.validate_dimensions()
	if not errors.is_empty():
		push_error("IT-003: Corrupt region %s: %s" % [coord, "; ".join(errors)])
		return null
	return loaded


func _save_region(coord: Vector2i, region: Resource) -> Error:
	_ensure_directories()
	region.checksum = _calculate_checksum(region.height_data)
	return ResourceSaver.save(region, region_file_path(coord), ResourceSaver.FLAG_COMPRESS)


func _admit(coord: Vector2i, region: Resource) -> void:
	var bytes: int = region.estimated_memory_bytes()
	_make_room(bytes)
	_cache[coord] = region
	_lru.append(coord)
	_cached_bytes += bytes


func _make_room(incoming_bytes: int) -> void:
	var guard: int = _lru.size() + 1
	while guard > 0 and (
		_cache.size() >= _budget.max_cached_regions
		or not _budget.can_cache_region(incoming_bytes, _cached_bytes)
	):
		guard -= 1
		var candidate := _find_oldest_clean_region()
		if candidate == Vector2i(-2147483648, -2147483648):
			push_warning("IT-W02: Region cache budget reached but all cached regions are dirty; keeping data to avoid loss")
			break
		_evict(candidate)


func _find_oldest_clean_region() -> Vector2i:
	for coord in _lru:
		if not _dirty.has(coord):
			return coord
	return Vector2i(-2147483648, -2147483648)


func _evict(coord: Vector2i) -> void:
	if not _cache.has(coord) or _dirty.has(coord):
		return
	var region: Resource = _cache[coord]
	_cached_bytes = maxi(0, _cached_bytes - region.estimated_memory_bytes())
	_cache.erase(coord)
	_lru.erase(coord)


func _touch(coord: Vector2i) -> void:
	_lru.erase(coord)
	_lru.append(coord)


func _ensure_directories() -> void:
	var absolute_path: String = ProjectSettings.globalize_path("%s/regions" % _world_data_root)
	var error: Error = DirAccess.make_dir_recursive_absolute(absolute_path)
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_error("IT-002: Cannot create terrain data directory: %s" % absolute_path)


func _calculate_checksum(values: PackedFloat32Array) -> int:
	# Fast deterministic integrity marker. It is not cryptographic; it detects
	# truncated or accidentally replaced region payloads without extra copies.
	var hash_value: int = 2166136261
	var step: int = maxi(1, values.size() / 4096)
	var index: int = 0
	while index < values.size():
		hash_value = int((hash_value ^ hash(values[index])) * 16777619) & 0x7fffffff
		index += step
	return hash_value
