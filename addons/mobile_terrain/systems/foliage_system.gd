@tool
class_name FoliageSystem
extends RefCounted

## FoliageSystem — pure foliage placement helpers.
##
## TKT-003 Phase A.3: extracted from `mobile_terrain_node.gd._scatter_foliage`
## and `_place_foliage_slope`. The math that turns a (position, normal)
## pair into a randomised Transform3D, and the math that samples a disc
## of candidate points with minimum spacing, both become pure static
## functions here. The node retains responsibility for MultiMesh state
## mutation, signal emission, and slot lookup.
##
## Future innovation 1.1 (non-destructive sculpt layers) and 4.3
## (vegetation density brush) will plug straight into these helpers
## without touching node state.

const _MIN_RIGHT_LEN_SQ := 0.0001
const _SCATTER_ACCEPTANCE_BUDGET_MULT := 4  # try 4x density to hit the spacing target


# Build a randomised orientation Transform3D for a foliage instance.
# - up is the surface normal at the placement point
# - rotation around UP is uniform in [0, TAU)
# - uniform scale in [0.8, 1.2]
# - origin is the world-space placement position
#
# Falls back to Vector3.RIGHT × up when the surface is nearly vertical
# so the basis stays orthogonal even on cliff faces.
static func compute_orientation_transform(pos: Vector3, normal: Vector3) -> Transform3D:
	var up: Vector3 = normal
	if up.length_squared() < 0.0001:
		up = Vector3.UP
	else:
		up = up.normalized()
	var right: Vector3 = Vector3.UP.cross(up)
	if right.length_squared() < _MIN_RIGHT_LEN_SQ:
		right = Vector3.RIGHT.cross(up)
	right = right.normalized()
	var forward: Vector3 = right.cross(up).normalized()
	var tf := Transform3D()
	tf.basis = Basis(right, up, forward)
	tf = tf.rotated_local(Vector3.UP, randf_range(0.0, TAU))
	var s: float = randf_range(0.8, 1.2)
	tf = tf.scaled_local(Vector3(s, s, s))
	tf.origin = pos
	return tf


# Sample up to `count` disc positions inside a circle of radius `radius`
# centred on `centre`, rejecting candidates closer than `min_spacing` to
# any already-accepted point. Heights are fetched via `height_lookup`, a
# Callable that takes (sample_x: float, sample_z: float) and returns the
# terrain Y at that world position.
#
# Uses sqrt-of-uniform radius distribution so samples are uniform across
# the disc rather than bunched at the centre.
#
# Returns the accepted world positions; may be shorter than `count` if
# the spacing target is too dense relative to the disc area.
static func sample_disc_with_spacing(
	centre: Vector3, radius: float, count: int, min_spacing: float, height_lookup: Callable
) -> Array[Vector3]:
	var accepted: Array[Vector3] = []
	if count <= 0 or radius <= 0.0 or not height_lookup.is_valid():
		return accepted
	var min_sq: float = min_spacing * min_spacing
	var attempts: int = 0
	var max_attempts: int = count * _SCATTER_ACCEPTANCE_BUDGET_MULT
	while accepted.size() < count and attempts < max_attempts:
		attempts += 1
		var r: float = radius * sqrt(randf())
		var angle: float = randf() * TAU
		var dx: float = cos(angle) * r
		var dz: float = sin(angle) * r
		var sample_x: float = centre.x + dx
		var sample_z: float = centre.z + dz
		var sample_y: float = float(height_lookup.call(sample_x, sample_z))
		var candidate := Vector3(sample_x, sample_y, sample_z)
		var ok: bool = true
		for p in accepted:
			if p.distance_squared_to(candidate) < min_sq:
				ok = false
				break
		if ok:
			accepted.append(candidate)
	return accepted
