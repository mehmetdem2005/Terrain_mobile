@tool
class_name TerrainInputRouter
extends RefCounted

## TerrainInputRouter — Phase B: 3D viewport input → terrain stroke lifecycle.
##
## Extracted from mobile_terrain_plugin._forward_3d_gui_input (the plugin's
## largest input function, which also tripped gdlint max-returns + two
## no-elif-return). Splitting the press / release / motion paths into
## separate handlers removes the long if/elif return ladder and isolates
## input routing from the rest of the EditorPlugin.
##
## NOT pure: this drives editor-runtime state, so it takes the plugin (`p`)
## and reads/writes its stroke fields (selected_node, is_sculpting, the
## backup arrays) and calls its shared helpers (_finalize_active_stroke,
## _ensure_backup_for_current_tool, _conform_decal_to_surface). The coupling
## is intentional — the goal is a smaller, single-responsibility plugin file
## and a testable-by-smoke routing surface, not a standalone subsystem.
## Verified via the headed editor smoke test; interactive sculpt/paint
## behaviour needs manual editor verification.


# Entry point — called from EditorPlugin._forward_3d_gui_input. Returns one
# of EditorPlugin.AFTER_GUI_INPUT_{PASS,STOP}.
static func route(p, camera: Camera3D, event: InputEvent) -> int:
	if not p.selected_node:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	# V21: cache camera + mouse from EVERY event (before the brush_enabled
	# gate) so brush-toggle-on can re-raycast without touching EditorInterface
	# (whose API shifted across Godot 4.x). Captured even with brush off so
	# toggling back on picks up wherever the camera ended up.
	p._cached_camera = camera
	if event is InputEventMouse:
		p._cached_mouse_pos = (event as InputEventMouse).position
	# V21: master toggle gate. PASS lets the editor camera controller see the
	# event so zoom/pan/orbit keep working; stroke/placement input is dropped.
	# Cursor isn't hidden here (the toggle handler did that) and MouseMotion
	# isn't processed, so the cursor doesn't flicker while orbiting.
	if not p.brush_enabled:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if _is_left_press(event):
		return _on_left_press(p, camera, event)
	if _is_left_release(event):
		return _on_left_release(p)
	if event is InputEventMouseMotion:
		return _on_motion(p, camera, event)
	return EditorPlugin.AFTER_GUI_INPUT_PASS


static func _is_left_press(event: InputEvent) -> bool:
	return (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_LEFT
	)


static func _is_left_release(event: InputEvent) -> bool:
	return (
		event is InputEventMouseButton
		and not event.pressed
		and event.button_index == MOUSE_BUTTON_LEFT
	)


static func _on_left_press(p, camera: Camera3D, event: InputEvent) -> int:
	# V22 FIX: raycast BEFORE start_stroke(). A miss used to open a stroke
	# (allocating a paint-cache image) then return without closing it,
	# leaving the cache pointing at a stale splatmap image — the next stroke
	# on another tool would write through it and corrupt splatmap_data. We
	# only commit to a stroke once the cursor actually hits the terrain.
	var result = p.selected_node.get_intersection_raymarch_persistent(camera, event.position)
	if typeof(result) != TYPE_DICTIONARY or result.pos == Vector3.INF:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	p.is_sculpting = true
	# Clear placement records on every stroke start so leftover state from a
	# previously interrupted object stroke can't leak into the new one.
	p.placement_records.clear()
	p.placement_initial_counts.clear()
	# Backups are filled lazily by _ensure_backup_for_current_tool on the
	# first dab that actually modifies the terrain — clicks on empty space
	# cost zero memory and record no empty undo entry.
	p.splatmap_backup = PackedByteArray()
	p.heightmap_backup = PackedFloat32Array()

	p.selected_node.start_stroke()
	p._conform_decal_to_surface(result.pos)
	p._ensure_backup_for_current_tool()
	p.selected_node.apply_brush_stroke_slope(result.pos, result.normal)
	return EditorPlugin.AFTER_GUI_INPUT_STOP


static func _on_left_release(p) -> int:
	# V21: route through the shared finaliser so all stroke-end paths
	# (mouse-up, brush-toggle-off, tool-change, visibility-loss) behave
	# identically and the backup arrays get cleared (TKT-004 H2/H3).
	p.is_sculpting = false
	p._finalize_active_stroke()
	return EditorPlugin.AFTER_GUI_INPUT_STOP


static func _on_motion(p, camera: Camera3D, event: InputEvent) -> int:
	var res = p.selected_node.get_intersection_raymarch_persistent(camera, event.position)
	if typeof(res) == TYPE_DICTIONARY and res.pos != Vector3.INF:
		p._conform_decal_to_surface(res.pos)
		if p.is_sculpting:
			# V20 FIX (#15): snapshot lazily for drags that started off the
			# terrain and only landed on it later in the stroke.
			p._ensure_backup_for_current_tool()
			p.selected_node.apply_brush_stroke_slope(res.pos, res.normal)
	else:
		# V21: cursor left the terrain. Hide it AND invalidate _last_brush_hit;
		# without the reset a later slider drag would call
		# _conform_brush_to_surface with the stale hit and the cursor would
		# resurrect at a random earlier spot (the "ghost cursor" symptom).
		if is_instance_valid(p.brush_cursor):
			p.brush_cursor.hide()
		p._last_brush_hit = Vector3.INF
	if p.is_sculpting:
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS
