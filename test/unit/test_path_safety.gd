@tool
extends SceneTree

# TKT-002 C1 regression test.
#
# Locks the contract for MobileTerrain3D._is_safe_external_path:
#   - Accept paths under res:// or user:// only
#   - Reject empty, absolute filesystem paths, and path-traversal sequences
#
# This test exists because the C1 fix closes a load()-before-type-check
# RCE risk: the function executes any GDScript embedded in a .res before
# our `is MobileTerrainData` guard fires, so the path scope is the
# security boundary. Any future refactor that loosens _is_safe_external_path
# must update this test alongside it.

const TerrainNodeScript := preload("res://addons/mobile_terrain/mobile_terrain_node.gd")
# TKT-004 H11: fix_texture_imports confines its recursive scan + .import
# writes to res:// only (no user://, unlike the data-load path above).
const FixTextureScript := preload("res://addons/mobile_terrain/fix_texture_imports.gd")

func _init() -> void:
	var failures: Array[String] = []
	_run("res_path_accepted", _test_res_accepted, failures)
	_run("user_path_accepted", _test_user_accepted, failures)
	_run("nested_res_path_accepted", _test_nested_res, failures)
	_run("empty_rejected", _test_empty, failures)
	_run("absolute_unix_rejected", _test_absolute_unix, failures)
	_run("absolute_windows_rejected", _test_absolute_windows, failures)
	_run("relative_rejected", _test_relative, failures)
	_run("parent_traversal_rejected", _test_parent_traversal, failures)
	_run("trailing_parent_rejected", _test_trailing_parent, failures)
	_run("http_url_rejected", _test_http_url, failures)
	# H11 — fix_texture_imports scope guard
	_run("h11_res_import_accepted", _test_h11_res_accepted, failures)
	_run("h11_user_rejected", _test_h11_user_rejected, failures)
	_run("h11_absolute_rejected", _test_h11_absolute_rejected, failures)
	_run("h11_traversal_rejected", _test_h11_traversal_rejected, failures)

	if failures.is_empty():
		print("PATH_SAFETY_TEST_OK")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: " + f)
		print("PATH_SAFETY_TEST_FAILED count=%d" % failures.size())
		quit(1)

func _run(name: String, fn: Callable, failures: Array[String]) -> void:
	var err: String = fn.call()
	if err != "":
		failures.append("%s — %s" % [name, err])
	else:
		print("OK  %s" % name)

func _test_res_accepted() -> String:
	if not TerrainNodeScript._is_safe_external_path("res://terrain.res"):
		return "res:// path must be accepted"
	return ""

func _test_user_accepted() -> String:
	if not TerrainNodeScript._is_safe_external_path("user://saves/world1.res"):
		return "user:// path must be accepted"
	return ""

func _test_nested_res() -> String:
	if not TerrainNodeScript._is_safe_external_path("res://addons/mobile_terrain/data/x.res"):
		return "nested res:// path must be accepted"
	return ""

func _test_empty() -> String:
	if TerrainNodeScript._is_safe_external_path(""):
		return "empty path must be rejected"
	return ""

func _test_absolute_unix() -> String:
	if TerrainNodeScript._is_safe_external_path("/etc/passwd"):
		return "absolute /etc path must be rejected"
	if TerrainNodeScript._is_safe_external_path("/tmp/x.res"):
		return "absolute /tmp path must be rejected"
	return ""

func _test_absolute_windows() -> String:
	if TerrainNodeScript._is_safe_external_path("C:\\Users\\victim\\malware.res"):
		return "absolute Windows path must be rejected"
	return ""

func _test_relative() -> String:
	if TerrainNodeScript._is_safe_external_path("terrain.res"):
		return "bare relative path must be rejected"
	if TerrainNodeScript._is_safe_external_path("data/terrain.res"):
		return "relative subdir path must be rejected"
	return ""

func _test_parent_traversal() -> String:
	if TerrainNodeScript._is_safe_external_path("res://../../../../etc/passwd"):
		return "res:// with /../ must be rejected"
	if TerrainNodeScript._is_safe_external_path("user://saves/../../etc/passwd"):
		return "user:// with /../ must be rejected"
	if TerrainNodeScript._is_safe_external_path("../terrain.res"):
		return "leading ../ must be rejected"
	return ""

func _test_trailing_parent() -> String:
	if TerrainNodeScript._is_safe_external_path("res://data/.."):
		return "trailing /.. must be rejected"
	return ""

func _test_http_url() -> String:
	if TerrainNodeScript._is_safe_external_path("https://attacker.example/payload.res"):
		return "https:// URL must be rejected"
	if TerrainNodeScript._is_safe_external_path("file:///etc/passwd"):
		return "file:// URL must be rejected"
	return ""

func _test_h11_res_accepted() -> String:
	if not FixTextureScript._is_within_res("res://"):
		return "res:// root must be accepted"
	if not FixTextureScript._is_within_res("res://addons/mobile_terrain/x.png.import"):
		return "nested res:// .import must be accepted"
	return ""

func _test_h11_user_rejected() -> String:
	# Unlike the data-load path, the import fixer must stay inside res://.
	if FixTextureScript._is_within_res("user://saves/x.import"):
		return "user:// must be rejected by the import scope guard"
	return ""

func _test_h11_absolute_rejected() -> String:
	if FixTextureScript._is_within_res("/etc/passwd"):
		return "absolute /etc must be rejected"
	if FixTextureScript._is_within_res("/tmp/evil.import"):
		return "absolute /tmp must be rejected"
	return ""

func _test_h11_traversal_rejected() -> String:
	if FixTextureScript._is_within_res("res://../../etc/passwd"):
		return "res:// with /../ must be rejected"
	if FixTextureScript._is_within_res("res://data/.."):
		return "trailing /.. must be rejected"
	return ""
