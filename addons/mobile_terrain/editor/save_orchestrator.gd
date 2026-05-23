@tool
class_name TerrainSaveOrchestrator
extends RefCounted

# TKT-011: simplified save flow.
#
# Heavy terrain data (height + splatmap + objects) is no longer @export'd on
# MobileTerrain3D — it's a plain var, so the serializer NEVER writes it into
# the .tscn. That removes the whole reason the old "Plan B" existed: there's
# nothing to strip from the scene, so no NOSTORE toggle, no pack/wipe/restore
# dance, no deferred restore callback.
#
# EditorPlugin._save_external_data just asks each terrain in the edited scene
# to write its own companion .res under res://terrain_data/. The terrain owns
# directory creation + path binding (save_terrain_data), and the whole thing
# is scene-INDEPENDENT — it works even on an unsaved/untitled scene, which is
# what kept failing before.

const _TerrainNode := preload("res://addons/mobile_terrain/mobile_terrain_node.gd")


# Write every terrain's data to its .res companion. Returns the first non-OK
# error encountered (OK if all succeed or there are no terrains with data).
func save_all_terrains(edited_root: Node) -> int:
	if edited_root == null:
		return ERR_INVALID_PARAMETER
	var terrains: Array = []
	_collect_terrains(edited_root, terrains)
	var first_err: int = OK
	for terrain in terrains:
		if not is_instance_valid(terrain) or not (terrain is _TerrainNode):
			continue
		if terrain.height_data.is_empty():
			continue  # nothing to persist yet
		var err: int = terrain.save_terrain_data()
		if err != OK and first_err == OK:
			first_err = err
	return first_err


func _collect_terrains(node: Node, out: Array) -> void:
	if node is _TerrainNode:
		out.append(node)
	for child in node.get_children():
		_collect_terrains(child, out)
