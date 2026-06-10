@tool
extends SceneTree

# TKT-010 A1 regression: object placement mesh-identity across reload.
#
# Path-less meshes (inspector primitives) get embedded as SEPARATE copies in
# the .tscn (asset_meshes export) and the companion .res (object_slots). After
# a scene reload they deserialize as different instances, which used to fork
# the multimesh registry: restored placements keyed by the .res copy, new
# placements keyed by the .tscn copy → duplicate Assets_* children, and
# garbage_collect_multimeshes (identity check) freeing the restored ones.
#
# The reload is SIMULATED here by handing _restore_object_slots a duplicated
# mesh instance — exactly what ResourceLoader produces for an embedded
# path-less sub-resource. Runs headless: only registry/child bookkeeping is
# asserted, not rendered transforms.

const TerrainScript := preload("res://addons/mobile_terrain/mobile_terrain_node.gd")

var _failed: int = 0


func _init() -> void:
	_test_restore_reunifies_pathless_mesh()
	_test_gc_survives_reload()
	_test_unmatched_mesh_still_restores()
	if _failed == 0:
		print("OBJECT_IDENTITY_TEST_OK")
		quit(0)
	else:
		printerr("OBJECT_IDENTITY_TEST_FAILED: %d failure(s)" % _failed)
		quit(1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failed += 1
		printerr("  FAIL: " + msg)


func _make_terrain_with_box_slot() -> Node3D:
	var terrain: Node3D = TerrainScript.new()
	terrain.map_size = 16
	var box := BoxMesh.new()
	terrain.asset_meshes = [box] as Array[Mesh]
	root.add_child(terrain)
	return terrain


func _slot_for(mesh: Mesh, slot_idx: int) -> Array:
	var transforms: Array[Transform3D] = [Transform3D(Basis(), Vector3(1, 2, 3))]
	return [{"mesh": mesh, "slot": slot_idx, "transforms": transforms}]


# Restoring a slot whose mesh is a DIFFERENT instance of the same primitive
# must re-key onto asset_meshes[slot], producing exactly one registry entry
# keyed by the asset mesh and exactly one Assets_* child.
func _test_restore_reunifies_pathless_mesh() -> void:
	var terrain := _make_terrain_with_box_slot()
	var reloaded_copy: Mesh = (terrain.asset_meshes[0] as Mesh).duplicate()
	terrain._restore_object_slots(_slot_for(reloaded_copy, 0))

	_check(
		terrain.multimesh_instances.has(terrain.asset_meshes[0]),
		"registry keyed by asset_meshes[0] (re-unified), keys=%s"
		% [terrain.multimesh_instances.keys()]
	)
	_check(
		not terrain.multimesh_instances.has(reloaded_copy),
		"registry NOT keyed by the .res copy"
	)
	var assets_children := 0
	for child in terrain.get_children():
		if child is MultiMeshInstance3D and String(child.name).begins_with("Assets_"):
			assets_children += 1
	_check(assets_children == 1, "exactly one Assets_* child (got %d)" % assets_children)
	terrain.free()


# After the simulated reload, a GC pass (triggered by any slot mutation in the
# editor) must NOT free the restored placements.
func _test_gc_survives_reload() -> void:
	var terrain := _make_terrain_with_box_slot()
	var reloaded_copy: Mesh = (terrain.asset_meshes[0] as Mesh).duplicate()
	terrain._restore_object_slots(_slot_for(reloaded_copy, 0))
	var before: int = terrain.multimesh_instances.size()
	terrain.garbage_collect_multimeshes()
	_check(
		terrain.multimesh_instances.size() == before and before == 1,
		"GC kept the re-unified multimesh (before=%d after=%d)"
		% [before, terrain.multimesh_instances.size()]
	)
	terrain.free()


# A restored mesh with NO equivalent asset slot must still restore (render),
# keyed by its own instance — degraded but lossless.
func _test_unmatched_mesh_still_restores() -> void:
	var terrain := _make_terrain_with_box_slot()
	var orphan := SphereMesh.new()
	terrain._restore_object_slots(_slot_for(orphan, -1))
	_check(
		terrain.multimesh_instances.has(orphan),
		"orphan mesh restored under its own key"
	)
	terrain.free()
