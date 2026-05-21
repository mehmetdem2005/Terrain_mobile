@tool
extends SceneTree

# Headless parse + load check for the MobileTerrain3D addon.
# Walks every .gd under addons/mobile_terrain/ and asserts load() succeeds.
# Exits 0 on clean, 1 on any failure.

func _init() -> void:
	var dir := DirAccess.open("res://addons/mobile_terrain")
	if dir == null:
		printerr("Cannot open res://addons/mobile_terrain")
		quit(2)
		return
	var paths: Array[String] = []
	_collect_gd("res://addons/mobile_terrain", paths)
	paths.sort()
	var failed := 0
	for p in paths:
		var s = load(p)
		if s == null:
			print("FAIL  %s" % p)
			failed += 1
		else:
			print("OK    %s" % p)
	if failed > 0:
		print("PARSE_CHECK_FAILED count=%d total=%d" % [failed, paths.size()])
		quit(1)
	else:
		print("PARSE_CHECK_OK total=%d" % paths.size())
		quit(0)

func _collect_gd(root: String, out: Array[String]) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name == "":
			break
		if name.begins_with("."):
			continue
		var full := root + "/" + name
		if dir.current_is_dir():
			_collect_gd(full, out)
		elif name.ends_with(".gd"):
			out.append(full)
	dir.list_dir_end()
