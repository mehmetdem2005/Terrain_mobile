@tool
extends SceneTree

# TKT-011 PR-2: object persistence roundtrip — REAL RenderingServer (xvfb).
#
# Headless (--headless) gives a dummy RenderingServer that doesn't store
# MultiMesh instance transforms, so this can't be a unit test. Here, under a
# real GL context, we:
#   1. build a terrain + place objects (deterministic transforms),
#   2. _collect_object_slots() → the .res-bound representation,
#   3. _restore_object_slots() into a FRESH node,
#   4. assert the restored transforms match (prints OBJECT_PERSISTENCE_OK),
#   5. render both so the objects are visible side by side.
#
# Usage: -- <out_name>

const TerrainNode := preload("res://addons/mobile_terrain/mobile_terrain_node.gd")

var _frames := 0
var _shot := "user://object_persistence.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_shot = "user://" + args[0]


func _process(_delta: float) -> bool:
	if _frames == 0:
		var mesh_path := "res://test_obj_mesh.tres"
		var box := BoxMesh.new()
		box.size = Vector3(2.0, 4.0, 2.0)
		ResourceSaver.save(box, mesh_path)
		box = load(mesh_path)  # carries resource_path

		var placed := [
			Transform3D(Basis(), Vector3(6, 2, 6)),
			Transform3D(Basis(), Vector3(16, 2, 11)),
			Transform3D(Basis(), Vector3(26, 2, 22)),
		]

		# Source node: place objects directly via the multimesh.
		var node1 := TerrainNode.new()
		root.add_child(node1)
		var mmi1: MultiMeshInstance3D = node1._get_or_create_multimesh(box)
		var mm1: MultiMesh = mmi1.multimesh
		mm1.instance_count = placed.size()
		for i in range(placed.size()):
			mm1.set_instance_transform(i, placed[i])

		# Collect → restore into a fresh node (the .res roundtrip in memory).
		var slots: Array = node1._collect_object_slots()
		var node2 := TerrainNode.new()
		root.add_child(node2)
		node2.position = Vector3(40, 0, 0)
		node2._restore_object_slots(slots)

		# Assert the roundtrip under the real RenderingServer.
		var ok := node2.multimesh_instances.has(mesh_path)
		var detail := "slot missing"
		if ok:
			var mm2: MultiMesh = node2.multimesh_instances[mesh_path].multimesh
			if mm2.instance_count != placed.size():
				ok = false
				detail = "count %d != %d" % [mm2.instance_count, placed.size()]
			else:
				for i in range(placed.size()):
					if not mm2.get_instance_transform(i).origin.is_equal_approx(placed[i].origin):
						ok = false
						detail = (
							"xform %d origin %s != %s"
							% [i, mm2.get_instance_transform(i).origin, placed[i].origin]
						)
						break
		if ok:
			print("OBJECT_PERSISTENCE_OK")
		else:
			printerr("OBJECT_PERSISTENCE_FAILED: " + detail)

		var cam := Camera3D.new()
		cam.look_at_from_position(Vector3(30, 40, 60), Vector3(25, 0, 12), Vector3.UP)
		root.add_child(cam)
		cam.make_current()
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-50, -30, 0)
		root.add_child(light)
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.5, 0.6, 0.7)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.7, 0.7, 0.7)
		env.ambient_light_energy = 0.9
		var we := WorldEnvironment.new()
		we.environment = env
		root.add_child(we)

		DirAccess.remove_absolute(ProjectSettings.globalize_path(mesh_path))

	_frames += 1
	if _frames >= 6:
		var img := root.get_texture().get_image()
		if img.save_png(_shot) == OK:
			print("OBJ_SHOT: " + ProjectSettings.globalize_path(_shot))
		quit(0)
		return true
	return false
