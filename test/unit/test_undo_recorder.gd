@tool
extends SceneTree

# TKT-009 Phase B.2: TerrainUndoRecorder unit test.
#
# The undo action builders take undo_redo as an untyped parameter precisely
# so they can be exercised with a mock here — no EditorUndoRedoManager (and
# thus no editor) required. We verify the SHAPE of each committed action:
# the action name, which properties get do/undo values, and that an empty
# backup commits nothing (so the undo history stays clean).

const Recorder := preload("res://addons/mobile_terrain/editor/undo_recorder.gd")


class MockUndoRedo:
	extends RefCounted
	var action_name: String = ""
	var create_count: int = 0
	var do_props: Array = []  # [[obj, prop, val], ...]
	var undo_props: Array = []
	var do_methods: Array = []  # [[obj, method], ...]
	var undo_methods: Array = []
	var committed: bool = false

	func create_action(name: String, _merge: int = 0, _ctx = null, _backward: bool = false) -> void:
		action_name = name
		create_count += 1

	func add_do_property(obj, prop, val) -> void:
		do_props.append([obj, prop, val])

	func add_undo_property(obj, prop, val) -> void:
		undo_props.append([obj, prop, val])

	func add_do_method(obj, method, a = null, b = null, c = null) -> void:
		do_methods.append([obj, method, a, b, c])

	func add_undo_method(obj, method, a = null, b = null, c = null) -> void:
		undo_methods.append([obj, method, a, b, c])

	func commit_action(_execute: bool = true) -> void:
		committed = true


class MockTerrain:
	extends RefCounted
	var splatmap_data: PackedByteArray = PackedByteArray()
	var height_data: PackedFloat32Array = PackedFloat32Array()

	func force_refresh_splatmap() -> void:
		pass

	func force_update_all() -> void:
		pass


func _init() -> void:
	var failures: Array[String] = []
	_run("paint_undo_builds_action", _test_paint_undo, failures)
	_run("paint_undo_empty_backup_no_action", _test_paint_empty, failures)
	_run("sculpt_undo_builds_action", _test_sculpt_undo, failures)
	_run("sculpt_undo_empty_backup_no_action", _test_sculpt_empty, failures)
	_run("placement_undo_empty_records_no_action", _test_placement_empty, failures)
	_run("placement_undo_builds_count_delta", _test_placement_undo, failures)

	if failures.is_empty():
		print("UNDO_RECORDER_TEST_OK")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: " + f)
		print("UNDO_RECORDER_TEST_FAILED count=%d" % failures.size())
		quit(1)


func _run(name: String, fn: Callable, failures: Array[String]) -> void:
	var err: String = fn.call()
	if err != "":
		failures.append("%s — %s" % [name, err])
	else:
		print("OK  %s" % name)


func _test_paint_undo() -> String:
	var ur := MockUndoRedo.new()
	var t := MockTerrain.new()
	t.splatmap_data = PackedByteArray([1, 2, 3, 4])
	var backup := PackedByteArray([9, 9, 9, 9])
	var committed: bool = Recorder.commit_paint_undo(ur, t, backup)
	if not committed:
		return "should return true when backup has data"
	if ur.action_name != "Terrain Paint":
		return "action name should be 'Terrain Paint', got '%s'" % ur.action_name
	if not ur.committed:
		return "commit_action must be called"
	# undo property must restore the backup; do property must be the current data.
	if ur.undo_props.size() != 1 or ur.undo_props[0][1] != "splatmap_data":
		return "must add_undo_property splatmap_data"
	if ur.undo_props[0][2] != backup:
		return "undo value must be the backup bytes"
	if ur.do_props.size() != 1 or ur.do_props[0][1] != "splatmap_data":
		return "must add_do_property splatmap_data"
	return ""


func _test_paint_empty() -> String:
	var ur := MockUndoRedo.new()
	var t := MockTerrain.new()
	var committed: bool = Recorder.commit_paint_undo(ur, t, PackedByteArray())
	if committed:
		return "empty backup must return false (no undo entry)"
	if ur.create_count != 0 or ur.committed:
		return "empty backup must create no action"
	return ""


func _test_sculpt_undo() -> String:
	var ur := MockUndoRedo.new()
	var t := MockTerrain.new()
	t.height_data = PackedFloat32Array([1.0, 2.0])
	var backup := PackedFloat32Array([5.0, 6.0])
	var committed: bool = Recorder.commit_sculpt_undo(ur, t, backup)
	if not committed:
		return "should return true when backup has data"
	if ur.action_name != "Terrain Sculpt":
		return "action name should be 'Terrain Sculpt', got '%s'" % ur.action_name
	if ur.undo_props.size() != 1 or ur.undo_props[0][1] != "height_data":
		return "must add_undo_property height_data"
	if ur.undo_props[0][2] != backup:
		return "undo value must be the backup heights"
	return ""


func _test_sculpt_empty() -> String:
	var ur := MockUndoRedo.new()
	var t := MockTerrain.new()
	var committed: bool = Recorder.commit_sculpt_undo(ur, t, PackedFloat32Array())
	if committed:
		return "empty backup must return false"
	if ur.create_count != 0:
		return "empty backup must create no action"
	return ""


func _test_placement_empty() -> String:
	var ur := MockUndoRedo.new()
	var committed: bool = Recorder.commit_placement_undo(ur, null, [], {})
	if committed:
		return "empty records must return false"
	if ur.create_count != 0:
		return "empty records must create no action"
	return ""


func _test_placement_undo() -> String:
	var ur := MockUndoRedo.new()
	var node := MockTerrain.new()  # the restore-method target
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = 3  # grew from 0 during the stroke
	mmi.multimesh = mm
	var initial_counts := {mmi: 0}
	var records := [
		{"mmi": mmi, "index": 0, "transform": Transform3D()},
		{"mmi": mmi, "index": 1, "transform": Transform3D()},
		{"mmi": mmi, "index": 2, "transform": Transform3D()},
	]
	var committed: bool = Recorder.commit_placement_undo(ur, node, records, initial_counts)
	mmi.free()
	if not committed:
		return "non-empty records must return true"
	if ur.action_name != "Terrain Place Objects":
		return "action name should be 'Terrain Place Objects', got '%s'" % ur.action_name
	# Buffer-restore via the node's _apply_object_buffer, one op each direction.
	# Changing instance_count clears the buffer, so a property-based count rewind
	# would strand survivors at the origin — must be a single restore method.
	if not ur.do_props.is_empty() or not ur.undo_props.is_empty():
		return "placement undo must use methods (buffer restore), not properties"
	# do-method args: [node, "_apply_object_buffer", mm, final_count, after_buffer].
	if ur.do_methods.size() != 1 or ur.do_methods[0][1] != "_apply_object_buffer":
		return "do-method must be _apply_object_buffer, got %d ops" % ur.do_methods.size()
	if ur.do_methods[0][0] != node:
		return "do-method target must be the terrain node"
	if ur.do_methods[0][3] != 3:
		return "do-method must restore final count 3, got %s" % str(ur.do_methods[0][3])
	if ur.undo_methods.size() != 1 or ur.undo_methods[0][1] != "_apply_object_buffer":
		return "undo-method must be _apply_object_buffer"
	if ur.undo_methods[0][3] != 0:
		return "undo-method must restore initial count 0, got %s" % str(ur.undo_methods[0][3])
	return ""
