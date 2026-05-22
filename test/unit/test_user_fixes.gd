@tool
extends SceneTree

# TKT-006 — user-reported fixes:
#   1. Scene-embed: terrain data baking inline into the .tscn (multi-MiB
#      "large text resource" warning). The auto-externalize threshold must
#      cover the DEFAULT map_size (256² = 65536) or a plain save embeds it.
#   2. Dead "Eğim" setting: slope_rock_factor is a no-op since V21 but still
#      showed in the inspector. It must be hidden from the editor while
#      keeping STORAGE so old scenes still deserialize.

const TerrainNode := preload("res://addons/mobile_terrain/mobile_terrain_node.gd")
const Consts := preload("res://addons/mobile_terrain/core/terrain_constants.gd")

const DEFAULT_MAP_SIZE := 256


func _init() -> void:
	var failures: Array[String] = []
	_run("externalize_threshold_covers_default_map", _test_threshold, failures)
	_run("slope_rock_factor_hidden_from_inspector", _test_slope_hidden, failures)
	_run("slope_rock_factor_keeps_storage", _test_slope_storage, failures)
	_run("active_pbr_props_stay_visible", _test_pbr_visible, failures)
	_run("albedo_triplanar_runs_on_mobile", _test_albedo_triplanar_mobile, failures)
	_run("normal_sample_kept_single_proj", _test_normal_sample_exists, failures)

	if failures.is_empty():
		print("USER_FIXES_TEST_OK")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: " + f)
		print("USER_FIXES_TEST_FAILED count=%d" % failures.size())
		quit(1)


func _run(name: String, fn: Callable, failures: Array[String]) -> void:
	var err: String = fn.call()
	if err != "":
		failures.append("%s — %s" % [name, err])
	else:
		print("OK  %s" % name)


func _test_threshold() -> String:
	# Default terrain is DEFAULT_MAP_SIZE² cells. If the threshold is above
	# that, the default terrain never auto-externalises and bakes inline.
	var default_cells := DEFAULT_MAP_SIZE * DEFAULT_MAP_SIZE
	if Consts.AUTO_EXTERNALIZE_THRESHOLD > default_cells:
		return (
			"threshold %d must be <= default map cells %d, else default terrain embeds in .tscn"
			% [Consts.AUTO_EXTERNALIZE_THRESHOLD, default_cells]
		)
	return ""


func _test_slope_hidden() -> String:
	var node: Node3D = TerrainNode.new()
	var prop := {"name": "slope_rock_factor", "usage": PROPERTY_USAGE_DEFAULT}
	node._validate_property(prop)
	var shows_in_editor: bool = (int(prop["usage"]) & PROPERTY_USAGE_EDITOR) != 0
	node.free()
	if shows_in_editor:
		return "dead slope_rock_factor must not show in the inspector"
	return ""


func _test_slope_storage() -> String:
	# Must still serialize so V19/V20 scenes that saved it round-trip cleanly.
	var node: Node3D = TerrainNode.new()
	var prop := {"name": "slope_rock_factor", "usage": PROPERTY_USAGE_DEFAULT}
	node._validate_property(prop)
	var has_storage: bool = (int(prop["usage"]) & PROPERTY_USAGE_STORAGE) != 0
	node.free()
	if not has_storage:
		return "slope_rock_factor must keep STORAGE for scene back-compat"
	return ""


func _test_pbr_visible() -> String:
	# Regression guard: hiding slope_rock_factor must not hide the working
	# PBR controls that share its inspector category.
	var node: Node3D = TerrainNode.new()
	var ok := true
	for pname in ["roughness_multiplier", "ao_strength", "triplanar_blend"]:
		var prop := {"name": pname, "usage": PROPERTY_USAGE_DEFAULT}
		node._validate_property(prop)
		if (int(prop["usage"]) & PROPERTY_USAGE_EDITOR) == 0:
			ok = false
			break
	node.free()
	if not ok:
		return "active PBR controls must stay visible in the inspector"
	return ""


const SHADER_PATH := "res://addons/mobile_terrain/shaders/terrain.gdshader"


func _albedo_sample_body() -> String:
	var code := FileAccess.get_file_as_string(SHADER_PATH)
	if code.is_empty():
		return ""
	var start := code.find("vec3 _mt_albedo_sample")
	if start < 0:
		return ""
	var brace := code.find("{", start)
	var close := code.find("}", brace)
	if brace < 0 or close < 0:
		return ""
	return code.substr(brace, close - brace)


func _test_albedo_triplanar_mobile() -> String:
	# The bug was `if (mobile_quality || triplanar_blend < 0.001) return xz;`
	# in _mt_albedo_sample — that fully bypassed triplanar on Forward Mobile,
	# so the slider did nothing and slopes kept stretching. Albedo must NOT
	# gate triplanar on mobile_quality. (Normal maps may; see next test.)
	var body := _albedo_sample_body()
	if body == "":
		return "could not isolate _mt_albedo_sample in terrain.gdshader"
	# Match the actual gate STATEMENT, not the word in an explanatory comment
	# (the fix's comment legitimately mentions the old `mobile_quality ||`).
	if "if (mobile_quality" in body:
		return "albedo triplanar must not gate on mobile_quality (re-introduces eğimde kayma)"
	return ""


func _test_normal_sample_exists() -> String:
	# Normals keep single-projection on mobile to bound the read count, so a
	# dedicated _mt_normal_sample (which DOES check mobile_quality) must exist
	# and be distinct from the albedo path.
	var code := FileAccess.get_file_as_string(SHADER_PATH)
	if code.is_empty():
		return "could not read terrain.gdshader"
	if not ("_mt_normal_sample" in code):
		return "_mt_normal_sample must exist (mobile keeps normal maps single-projection)"
	return ""
