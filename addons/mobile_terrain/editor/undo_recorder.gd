@tool
class_name TerrainUndoRecorder
extends RefCounted

## TerrainUndoRecorder — Phase B.2: terrain stroke undo/redo action builders.
##
## Extracted from mobile_terrain_plugin (_finalize_active_stroke's three
## commit branches + _commit_placement_undo). Unlike the input router, these
## are written as PARAMETRIC builders: each takes the undo_redo manager, the
## terrain, and the backup data explicitly, rather than reaching into the
## plugin. That keeps the plugin owning the stroke/backup STATE while this
## class owns the action CONSTRUCTION — and, crucially, makes the action
## shape unit-testable with a mock undo_redo (no editor required).
##
## API verified against EditorUndoRedoManager.xml (Godot 4.6.2):
##   create_action(name, merge_mode=MERGE_DISABLE, custom_context=null,
##                 backward_undo_ops=false)
##   add_do_property(object, property, value) / add_undo_property(...)
##   add_do_method(object, method: StringName, ...) / add_undo_method(...)
##   commit_action(execute=true)
## The builders also work with a duck-typed mock exposing those methods,
## which is how test/unit/test_undo_recorder.gd exercises them headlessly.


# Commit the paint (splatmap) undo action. Returns true if an action was
# committed (i.e. the backup held data). undo_redo is untyped so tests can
# pass a mock; in the plugin it's the EditorUndoRedoManager.
static func commit_paint_undo(undo_redo, terrain, splatmap_backup: PackedByteArray) -> bool:
	if splatmap_backup.size() == 0:
		return false
	undo_redo.create_action("Terrain Paint")
	undo_redo.add_do_property(terrain, "splatmap_data", terrain.splatmap_data.duplicate())
	undo_redo.add_undo_property(terrain, "splatmap_data", splatmap_backup)
	undo_redo.add_do_method(terrain, "force_refresh_splatmap")
	undo_redo.add_undo_method(terrain, "force_refresh_splatmap")
	undo_redo.commit_action(false)
	return true


# Commit the sculpt (heightmap) undo action. Covers all sculpt tools — the
# plugin only calls this for current_tool not in {7 Paint, 8 Object}.
static func commit_sculpt_undo(undo_redo, terrain, heightmap_backup: PackedFloat32Array) -> bool:
	if heightmap_backup.size() == 0:
		return false
	undo_redo.create_action("Terrain Sculpt")
	undo_redo.add_do_property(terrain, "height_data", terrain.height_data.duplicate())
	undo_redo.add_undo_property(terrain, "height_data", heightmap_backup)
	undo_redo.add_do_method(terrain, "force_update_all")
	undo_redo.add_undo_method(terrain, "force_update_all")
	undo_redo.commit_action(false)
	return true


# Commit the object-placement undo action (foliage/multimesh). Returns true
# if an action was committed. Filters freed multimeshes so undo execution
# can't crash on a stale reference.
#
# Changing MultiMesh.instance_count reallocates and CLEARS the whole transform
# buffer (any size change wipes it), so undo/redo cannot just rewind the count
# and trust the surviving instances to keep their transforms — they would all
# collapse to the origin. Instead we snapshot the FULL transform buffer before
# (initial slice) and after (current) the stroke, and restore it atomically via
# the node's _apply_object_buffer (sets count, then rewrites the buffer). `node`
# is the terrain that owns the multimeshes and the restore method.
static func commit_placement_undo(
	undo_redo, node, placement_records: Array, placement_initial_counts: Dictionary
) -> bool:
	if placement_records.is_empty():
		return false
	undo_redo.create_action("Terrain Place Objects")

	# One restore op per touched multimesh. Skip any freed since the stroke
	# (e.g. asset slot removed mid-stroke) — a freed reference would crash on
	# undo execution.
	for mmi in placement_initial_counts.keys():
		if not is_instance_valid(mmi) or mmi.multimesh == null:
			continue
		var mm: MultiMesh = mmi.multimesh
		var initial: int = placement_initial_counts[mmi]
		var after_count: int = mm.instance_count
		if after_count == initial:
			continue
		var after_buffer: PackedFloat32Array = mm.buffer.duplicate()
		# Per-instance stride (12 floats for TRANSFORM_3D); derive it from the
		# live buffer so 2D/3D both work without a hard-coded constant.
		var stride: int = after_buffer.size() / after_count if after_count > 0 else 0
		var before_buffer: PackedFloat32Array = after_buffer.slice(0, initial * stride)
		undo_redo.add_do_method(node, "_apply_object_buffer", mm, after_count, after_buffer)
		undo_redo.add_undo_method(node, "_apply_object_buffer", mm, initial, before_buffer)

	undo_redo.commit_action(false)
	return true
