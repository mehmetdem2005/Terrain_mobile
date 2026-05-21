@tool
class_name TerrainSaveOrchestrator
extends RefCounted

# V22 Plan B save flow, isolated from the EditorPlugin shell.
#
# Why this exists
# ---------------
# Godot 4.6 calls EditorPlugin._save_external_data AFTER the .tscn is
# already on disk, and the _validate_property NOSTORE toggle is ignored
# by the serializer. Earlier addon versions tried to schedule a second
# EditorInterface.save_scene() via call_deferred — that re-entry was
# racy in 4.6 (the deferred call sometimes never reached this codebase's
# logging point in user-reported logs).
#
# Plan B bypasses EditorInterface entirely:
#   1. Externalise qualifying terrains (write a .res companion).
#   2. Snapshot the live heavy arrays + ImageTextures, then wipe them.
#   3. PackedScene.pack(edited_root) + ResourceSaver.save(packed, path).
#   4. Restore the snapshots so the live editor stays renderable.
#
# Deterministic, single-pass, no re-entrancy, no suppress flag.

const _TerrainNode := preload("res://addons/mobile_terrain/mobile_terrain_node.gd")

# Drive a full Plan B save against an editor-edited scene root. Returns
# the ResourceSaver.save error code (OK on success). Safe to call from
# any frame; the deferred restore is owned by `restore_host` so it lives
# beyond this call.
#
# `restore_host`: any Node that's alive long enough to invoke the
# deferred _restore_after_save callback (usually the EditorPlugin
# itself).
func save_with_externalized_terrains(edited_root: Node, restore_host: Object) -> int:
	if edited_root == null:
		return ERR_INVALID_PARAMETER
	var scene_path: String = edited_root.scene_file_path
	if scene_path.is_empty():
		return ERR_FILE_NOT_FOUND
	var terrains: Array = []
	_collect_terrains(edited_root, terrains)
	if terrains.is_empty():
		return OK
	var backups: Array = []
	for terrain in terrains:
		if not is_instance_valid(terrain):
			continue
		var threshold: int = TerrainConstants.AUTO_EXTERNALIZE_THRESHOLD
		var size_qualifies: bool = terrain.height_data.size() >= threshold
		var path_set: bool = terrain.external_data_path != ""
		var res_missing: bool = path_set and not ResourceLoader.exists(terrain.external_data_path)
		if size_qualifies and (not path_set or res_missing):
			if res_missing:
				terrain._suppress_external_path_setter = true
				terrain.external_data_path = ""
				terrain._suppress_external_path_setter = false
			terrain._externalize_data(true)
		if terrain.external_data_path != "" and terrain.height_data.size() > 0:
			backups.append({
				"node": terrain,
				"height_data": terrain.height_data,
				"splatmap_texture_local": terrain.splatmap_texture_local,
			})
			terrain.height_data = PackedFloat32Array()
			terrain.splatmap_texture_local = null
	if backups.is_empty():
		return OK

	var packed := PackedScene.new()
	var pack_err := packed.pack(edited_root)
	if pack_err != OK:
		TerrainDiagnostics.error(TerrainDiagnostics.E_SAVE_PACK_FAILED, [scene_path, pack_err])
		_restore(backups)
		return pack_err
	var save_err := ResourceSaver.save(packed, scene_path)
	if save_err != OK:
		TerrainDiagnostics.error(TerrainDiagnostics.E_SAVE_RESOURCE_FAILED, [scene_path, save_err])

	# Defer restore so any engine-side flush completes before we mutate
	# the live nodes again.
	if restore_host != null and restore_host.has_method("_terrain_restore_callback"):
		restore_host.call_deferred("_terrain_restore_callback", backups)
	else:
		_restore(backups)
	return save_err

func _collect_terrains(node: Node, out: Array) -> void:
	if node is _TerrainNode:
		out.append(node)
	for child in node.get_children():
		_collect_terrains(child, out)

func _restore(backups: Array) -> void:
	for entry in backups:
		if not entry.has("node"):
			continue
		var terrain = entry["node"]
		if not is_instance_valid(terrain):
			TerrainDiagnostics.warn(TerrainDiagnostics.W_RESTORE_INVALID)
			continue
		if entry.has("height_data"):
			terrain.height_data = entry["height_data"]
		if entry.has("splatmap_texture_local"):
			terrain.splatmap_texture_local = entry["splatmap_texture_local"]
		if terrain.has_method("force_update_all"):
			terrain.force_update_all()
		if terrain.has_method("force_refresh_splatmap"):
			terrain.force_refresh_splatmap()
