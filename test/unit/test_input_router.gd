@tool
extends SceneTree

# Unit test for TerrainInputRouter (editor/input_router.gd), focused on the
# TOUCH path added so the brush/paint/object tools work on a touchscreen /
# Android editor. Drives the router with a duck-typed mock plugin + mock node
# (no editor required) and asserts touch press/drag/release drive the same
# start_stroke / apply_brush_stroke_slope / finalize calls mouse does — and
# that emulated-from-touch mouse events don't double-fire.

const Router := preload("res://addons/mobile_terrain/editor/input_router.gd")

var _failed: int = 0


class MockNode:
	extends RefCounted
	var hit: Dictionary = {"pos": Vector3(1, 2, 3), "normal": Vector3.UP}
	var start_calls: int = 0
	var apply_calls: int = 0
	var end_calls: int = 0

	func get_intersection_raymarch_persistent(_cam, _pos):
		return hit

	func start_stroke() -> void:
		start_calls += 1

	func apply_brush_stroke_slope(_p, _n) -> void:
		apply_calls += 1

	func end_stroke() -> void:
		end_calls += 1


class MockPlugin:
	extends RefCounted
	var selected_node
	var _cached_camera
	var _cached_mouse_pos: Vector2 = Vector2.ZERO
	var brush_enabled: bool = true
	var _touch_active: bool = false
	var is_sculpting: bool = false
	var placement_records: Array = []
	var placement_initial_counts: Dictionary = {}
	var splatmap_backup: PackedByteArray = PackedByteArray()
	var heightmap_backup: PackedFloat32Array = PackedFloat32Array()
	var brush_cursor = null
	var _last_brush_hit: Vector3 = Vector3.INF
	var conform_calls: int = 0
	var finalize_calls: int = 0

	func _conform_decal_to_surface(_pos) -> void:
		conform_calls += 1

	func _ensure_backup_for_current_tool() -> void:
		pass

	func _finalize_active_stroke() -> void:
		finalize_calls += 1
		selected_node.end_stroke()


func _init() -> void:
	_test_touch_press_starts_and_places()
	_test_touch_drag_places()
	_test_touch_release_finalizes()
	_test_emulated_mouse_dropped_during_touch()
	_test_mouse_still_works()
	_test_multifinger_passes_to_editor()
	if _failed == 0:
		print("INPUT_ROUTER_TEST_OK")
		quit(0)
	else:
		printerr("INPUT_ROUTER_TEST_FAILED: %d failure(s)" % _failed)
		quit(1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failed += 1
		printerr("  FAIL: " + msg)


func _touch(idx: int, pressed: bool, pos: Vector2) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.pressed = pressed
	e.position = pos
	return e


func _drag(idx: int, pos: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = pos
	return e


func _mouse_left(pressed: bool, pos: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	return e


func _new_pair() -> Array:
	var p := MockPlugin.new()
	var n := MockNode.new()
	p.selected_node = n
	return [p, n]


func _test_touch_press_starts_and_places() -> void:
	var pair := _new_pair()
	var p = pair[0]
	var n = pair[1]
	var r: int = Router.route(p, null, _touch(0, true, Vector2(10, 10)))
	_check(n.start_calls == 1, "touch press starts stroke (got %d)" % n.start_calls)
	_check(n.apply_calls == 1, "touch press places one (got %d)" % n.apply_calls)
	_check(p.is_sculpting, "touch press sets is_sculpting")
	_check(p._touch_active, "touch press sets _touch_active")
	_check(r == EditorPlugin.AFTER_GUI_INPUT_STOP, "touch press returns STOP")


func _test_touch_drag_places() -> void:
	var pair := _new_pair()
	var p = pair[0]
	var n = pair[1]
	Router.route(p, null, _touch(0, true, Vector2(10, 10)))
	Router.route(p, null, _drag(0, Vector2(40, 40)))
	_check(n.apply_calls == 2, "touch drag places again while sculpting (got %d)" % n.apply_calls)


func _test_touch_release_finalizes() -> void:
	var pair := _new_pair()
	var p = pair[0]
	var n = pair[1]
	Router.route(p, null, _touch(0, true, Vector2(10, 10)))
	var r: int = Router.route(p, null, _touch(0, false, Vector2(10, 10)))
	_check(p.finalize_calls == 1, "touch release finalizes stroke")
	_check(n.end_calls == 1, "touch release ends stroke")
	_check(not p.is_sculpting, "touch release clears is_sculpting")
	_check(not p._touch_active, "touch release clears _touch_active")
	_check(r == EditorPlugin.AFTER_GUI_INPUT_STOP, "touch release returns STOP")


func _test_emulated_mouse_dropped_during_touch() -> void:
	var pair := _new_pair()
	var p = pair[0]
	var n = pair[1]
	Router.route(p, null, _touch(0, true, Vector2(10, 10)))  # start: start=1, apply=1
	var r: int = Router.route(p, null, _mouse_left(true, Vector2(10, 10)))  # emulated
	_check(n.start_calls == 1, "emulated mouse during touch does not re-start (got %d)" % n.start_calls)
	_check(n.apply_calls == 1, "emulated mouse during touch does not place (got %d)" % n.apply_calls)
	_check(r == EditorPlugin.AFTER_GUI_INPUT_STOP, "emulated mouse swallowed (STOP)")


func _test_mouse_still_works() -> void:
	var pair := _new_pair()
	var p = pair[0]
	var n = pair[1]
	var r: int = Router.route(p, null, _mouse_left(true, Vector2(5, 5)))
	_check(n.start_calls == 1, "mouse press starts stroke")
	_check(n.apply_calls == 1, "mouse press places one")
	_check(r == EditorPlugin.AFTER_GUI_INPUT_STOP, "mouse press returns STOP")


func _test_multifinger_passes_to_editor() -> void:
	var pair := _new_pair()
	var p = pair[0]
	var n = pair[1]
	var r: int = Router.route(p, null, _touch(1, true, Vector2(10, 10)))  # second finger
	_check(n.start_calls == 0, "second finger does not start a stroke")
	_check(r == EditorPlugin.AFTER_GUI_INPUT_PASS, "second finger passes to editor (camera)")
