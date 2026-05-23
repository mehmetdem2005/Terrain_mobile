@tool
extends SceneTree

# Integration test: placed objects survive a real .res save/load when the
# source mesh has NO resource_path (an inspector primitive).
#
# This is the exact case the old object system could not handle: it keyed
# everything by resource_path and stored a "mesh_path" string, so a BoxMesh
# created in the inspector was silently dropped. The new schema stores the
# Mesh resource itself, which ResourceSaver embeds into the .res.

const RES_PATH := "res://test_object_roundtrip.res"


func _init() -> void:
	var ok := _run()
	if FileAccess.file_exists(RES_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RES_PATH))
	if ok:
		print("OBJECT_ROUNDTRIP_OK")
		quit(0)
	else:
		print("OBJECT_ROUNDTRIP_FAILED")
		quit(1)


func _run() -> bool:
	# A primitive with no resource_path — the mesh the old code rejected.
	var box := BoxMesh.new()
	box.size = Vector3(1.5, 3.0, 1.5)
	if box.resource_path != "":
		printerr("precondition failed: BoxMesh unexpectedly has a resource_path")
		return false

	var transforms: Array[Transform3D] = [
		Transform3D(Basis(), Vector3(2, 1, 4)),
		Transform3D(Basis().rotated(Vector3.UP, 0.7), Vector3(9, 2, 5)),
	]

	var data := MobileTerrainData.new()
	data.object_slots = [{"mesh": box, "transforms": transforms}]

	var err := ResourceSaver.save(data, RES_PATH)
	if err != OK:
		printerr("ResourceSaver.save failed err=%d" % err)
		return false

	var loaded = load(RES_PATH)
	if not (loaded is MobileTerrainData):
		printerr("loaded resource is not MobileTerrainData")
		return false
	if loaded.object_slots.size() != 1:
		printerr("object_slots size %d != 1" % loaded.object_slots.size())
		return false

	var slot: Dictionary = loaded.object_slots[0]
	var lmesh = slot.get("mesh", null)
	if not (lmesh is Mesh):
		printerr("restored slot has no embedded Mesh (path-less mesh was not persisted)")
		return false

	var lxf: Array = slot.get("transforms", [])
	if lxf.size() != transforms.size():
		printerr("restored transform count %d != %d" % [lxf.size(), transforms.size()])
		return false
	for i in range(transforms.size()):
		if not lxf[i].origin.is_equal_approx(transforms[i].origin):
			printerr(
				"transform %d origin mismatch: %s != %s" % [i, lxf[i].origin, transforms[i].origin]
			)
			return false
	return true
