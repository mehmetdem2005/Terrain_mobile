@tool
class_name TerrainObjectPlacement
extends RefCounted

## TerrainObjectPlacement — discrete "tap the terrain, drop one object" stamping.
##
## This is the placement MODULE: stateless helpers that own the geometry of a
## single placement (which MultiMesh, the per-instance transform, the spacing
## gate) but NOT the gesture lifecycle. The terrain node owns the registry +
## the foliage_placed signal; the editor input router owns the press/drag/
## release gesture. Keeping this layer stateless is what makes the placement
## math unit-testable under --headless (the dummy RenderingServer never stores
## MultiMesh transforms, so place_one's buffer write is the only part that
## needs the editor/visual harness).
##
## Replaces the previous object_placer.gd. The behavioural fix that motivated
## the rewrite lives in the input router (placement no longer rides the sculpt
## stroke's is_sculpting/press-hit gate), but the module was re-cut alongside it
## so the placement path is one coherent unit rather than helpers bolted onto
## the sculpt brush.

# Safety cap on instances per mesh: a runaway drag (tiny spacing, fast motion)
# must not grow the MultiMesh buffer without bound and exhaust memory / overload
# the GPU (a cause of the editor stall on heavy object painting).
const MAX_INSTANCES_PER_MESH := 8192

# Upper clamp on per-instance scale. object_scale comes from an @export_range
# that only constrains the inspector — direct/scripted assignment is NOT
# bounded — so a stray huge value could otherwise produce a kilometre-wide
# instance (degenerate basis, GPU stall). Matches the node's export bound.
const MAX_OBJECT_SCALE := 100.0


# Human-readable Scene-dock name fragment for a mesh. Tolerates path-less
# meshes (inspector primitives: BoxMesh, CapsuleMesh, ...) by falling back to
# resource_name, then the class name, so the batch node is never named
# "Assets_".
static func mesh_label(mesh: Mesh) -> String:
	if mesh == null:
		return "Object"
	if mesh.resource_path != "":
		return mesh.resource_path.get_file().get_basename()
	if mesh.resource_name != "":
		return mesh.resource_name
	return mesh.get_class()


# Get (or lazily create) the MultiMeshInstance3D that batches `mesh`, tracked
# in `registry` keyed by the Mesh resource itself (robust for path-less
# inspector primitives, unlike the old "::sub_resource" path key). The child is
# runtime-only — deliberately NOT owner-promoted — so it never serialises into
# the .tscn; placements persist via the terrain's .res object_slots instead.
static func get_or_create_mmi(
	node: Node3D, mesh: Mesh, registry: Dictionary
) -> MultiMeshInstance3D:
	if mesh == null:
		return null
	if registry.has(mesh):
		var existing = registry[mesh]
		if is_instance_valid(existing):
			return existing
		registry.erase(mesh)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Assets_" + mesh_label(mesh)
	node.add_child(mmi)
	var mm := MultiMesh.new()
	# CRITICAL: 3D format must be set before transforms are written, or the
	# instance buffer is interpreted as 2D and renders as stretched garbage.
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = 0
	mmi.multimesh = mm
	registry[mesh] = mmi
	return mmi


# Decide whether a new dab at `new_pos` is far enough from the previous
# placement to drop another instance. last_pos == Vector3.INF means "first
# placement of this gesture" → always allowed, so a single tap always drops
# exactly one and a held-still finger does not pile up a stack.
static func should_place(last_pos: Vector3, new_pos: Vector3, spacing: float) -> bool:
	if last_pos == Vector3.INF:
		return true
	return last_pos.distance_to(new_pos) >= maxf(0.01, spacing)


# PURE: build the per-instance Transform3D, in the MMI's LOCAL space, for an
# object dropped at world-space `world_pos`. Kept free of MultiMesh state so it
# is unit-testable under --headless. `mmi_global_xform` is passed explicitly so
# the world→local map needs no scene-tree side effects.
static func build_instance_transform(
	world_pos: Vector3,
	surface_normal: Vector3,
	object_scale: float,
	align_to_normal: bool,
	random_yaw: bool,
	mmi_global_xform: Transform3D,
	mesh_min_y: float = 0.0
) -> Transform3D:
	var basis := _orientation_basis(surface_normal, align_to_normal, random_yaw)
	var s: float = object_scale if object_scale > 0.0 else 1.0
	s = minf(s, MAX_OBJECT_SCALE)
	basis = basis.scaled(Vector3(s, s, s))
	# Sit the mesh ON the surface: shift the origin up by the mesh's bottom (its
	# AABB min-y, already scaled because basis carries the scale) along the
	# instance up-axis, so a centre-pivot mesh (sphere/box/capsule) doesn't sink
	# half below the terrain.
	var origin: Vector3 = world_pos + basis * Vector3(0.0, -mesh_min_y, 0.0)
	var world_tf := Transform3D(basis, origin)
	return mmi_global_xform.affine_inverse() * world_tf


# Append exactly one instance to `mmi` at `world_pos`. Returns the new instance
# index (== the previous instance_count), or -1 on bad input / cap hit. The
# index is handed back so the editor can record it for undo.
static func place_one(
	mmi: MultiMeshInstance3D,
	world_pos: Vector3,
	surface_normal: Vector3,
	object_scale: float,
	align_to_normal: bool,
	random_yaw: bool
) -> int:
	if mmi == null or mmi.multimesh == null:
		return -1
	var mm := mmi.multimesh
	if mm.instance_count >= MAX_INSTANCES_PER_MESH:
		return -1
	var mesh_min_y: float = mm.mesh.get_aabb().position.y if mm.mesh != null else 0.0
	var local_tf := build_instance_transform(
		world_pos,
		surface_normal,
		object_scale,
		align_to_normal,
		random_yaw,
		mmi.global_transform,
		mesh_min_y
	)
	var idx: int = mm.instance_count
	# CRITICAL: growing instance_count reallocates the transform buffer and
	# CLEARS every existing instance (RenderingServer behaviour — any
	# instance_count change wipes the buffer), so existing transforms must
	# be restored after the grow. Without that, every placement reset all
	# previously placed objects to the origin.
	#
	# TKT-019 M1 (independently converged with TKT-010 B3): restore via a
	# raw `buffer` splice — snapshot the packed float buffer, grow,
	# zero-extend the snapshot to the new size, assign it back. Two native
	# property accesses + a memcpy-backed resize, instead of the old
	# per-instance get/set_instance_transform loop that cost O(existing
	# instances) native calls per placement (~16ms stalls near the 8192
	# cap). The new slot is zeroed by the resize and immediately
	# overwritten below.
	#
	# Headless builds: the dummy RenderingServer reports an EMPTY buffer
	# (verified on 4.6.2), so the splice is skipped there — the same
	# degenerate no-op the per-instance loop had under --headless.
	var kept: PackedFloat32Array = mm.buffer
	mm.instance_count = idx + 1
	var grown_size: int = mm.buffer.size()
	if idx > 0 and grown_size > 0 and kept.size() > 0:
		kept.resize(grown_size)
		mm.buffer = kept
	mm.set_instance_transform(idx, local_tf)
	return idx


# Orthonormal orientation basis. Upright (world Y up) by default so cubes /
# capsules stand straight; aligned to the surface normal when align_to_normal
# is on (objects tilt to follow slopes). Optional uniform-random yaw around the
# up axis. Always orthonormal — never the degenerate/NaN basis that renders as
# a stretched spike.
static func _orientation_basis(
	surface_normal: Vector3, align_to_normal: bool, random_yaw: bool
) -> Basis:
	var up := Vector3.UP
	if align_to_normal and surface_normal.length_squared() > 0.0001:
		up = surface_normal.normalized()
	var basis := Basis()
	if not up.is_equal_approx(Vector3.UP):
		var right := Vector3.UP.cross(up)
		if right.length_squared() < 0.0001:
			right = Vector3.RIGHT.cross(up)
		right = right.normalized()
		var forward := right.cross(up).normalized()
		basis = Basis(right, up, forward)
	if random_yaw:
		basis = basis.rotated(up, randf() * TAU)
	return basis
