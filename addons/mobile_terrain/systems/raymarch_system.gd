@tool
class_name TerrainRaymarchSystem
extends RefCounted

# V22: extracted raymarch logic. Pure function — no terrain-node state
# of its own; the caller passes height_data, map_size, and global
# position. Output Dictionary mirrors the legacy node.get_intersection_*
# return shape so callers don't need to change.
#
# Behaviour preserved from V21:
#   - 1-unit step (not 2.0) so thin ridges aren't skipped
#   - adaptive max iterations (cap min(8000, diag + cam_dist + 100))
#   - i==0 spurious-hit guard (camera below terrain)
#   - binary-search OOB clamp
#   - early-termination floor at global_y - 200
#
# Returns: { "pos": Vector3, "normal": Vector3 }. pos == Vector3.INF
# signals no hit.

static func intersect(
	camera: Camera3D,
	screen_pos: Vector2,
	height_data: PackedFloat32Array,
	map_size: int,
	terrain_origin: Vector3
) -> Dictionary:
	if camera == null or map_size <= 0 or height_data.size() < map_size * map_size:
		return {"pos": Vector3.INF, "normal": Vector3.UP}
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var ray_step := dir
	var march_pos := from
	var hit_pos := Vector3.INF
	var diag: float = sqrt(2.0) * float(map_size)
	var cam_to_origin: float = (from - terrain_origin).length()
	var max_iters: int = mini(8000, int(diag + cam_to_origin + 100.0))
	var early_term_y: float = terrain_origin.y - 200.0

	for i in range(max_iters):
		var lx := floori(march_pos.x - terrain_origin.x)
		var lz := floori(march_pos.z - terrain_origin.z)
		if lx >= 0 and lx < map_size and lz >= 0 and lz < map_size:
			var h_here := height_data[lz * map_size + lx] + terrain_origin.y
			if march_pos.y <= h_here:
				if i == 0:
					# Camera started inside the heightfield; treat as no hit.
					march_pos += ray_step
					if march_pos.y < early_term_y:
						break
					continue
				var p_start := march_pos - ray_step
				var p_end := march_pos
				for j in range(5):
					var mid := (p_start + p_end) * 0.5
					var mid_lx := floori(mid.x - terrain_origin.x)
					var mid_lz := floori(mid.z - terrain_origin.z)
					if mid_lx < 0 or mid_lx >= map_size or mid_lz < 0 or mid_lz >= map_size:
						break
					var h: float = height_data[mid_lz * map_size + mid_lx] + terrain_origin.y
					if mid.y <= h:
						p_end = mid
					else:
						p_start = mid
				hit_pos = p_end
				break
		march_pos += ray_step
		if march_pos.y < early_term_y:
			break

	if hit_pos == Vector3.INF:
		return {"pos": Vector3.INF, "normal": Vector3.UP}

	var lx := floori(hit_pos.x - terrain_origin.x)
	var lz := floori(hit_pos.z - terrain_origin.z)
	var max_idx: int = map_size - 1
	lx = clampi(lx, 0, max_idx)
	lz = clampi(lz, 0, max_idx)
	var nxL: int = lx - 1 if lx > 0 else 0
	var nxR: int = lx + 1 if lx < max_idx else max_idx
	var nzD: int = lz - 1 if lz > 0 else 0
	var nzU: int = lz + 1 if lz < max_idx else max_idx
	var hL: float = height_data[lz * map_size + nxL]
	var hR: float = height_data[lz * map_size + nxR]
	var hD: float = height_data[nzD * map_size + lx]
	var hU: float = height_data[nzU * map_size + lx]
	var norm := Vector3(hL - hR, 2.0, hD - hU).normalized()
	return {"pos": hit_pos, "normal": norm}
