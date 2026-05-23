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
const Orch := preload("res://addons/mobile_terrain/editor/save_orchestrator.gd")


func _init() -> void:
	var failures: Array[String] = []
	_run("externalize_is_size_independent", _test_externalize_any_size, failures)
	_run("map_size_adapts_to_any_value", _test_map_size_adapts, failures)
	_run("slope_rock_factor_hidden_from_inspector", _test_slope_hidden, failures)
	_run("slope_rock_factor_keeps_storage", _test_slope_storage, failures)
	_run("active_pbr_props_stay_visible", _test_pbr_visible, failures)
	_run("slot_sample_no_mobile_gate", _test_slot_sample_no_mobile_gate, failures)
	_run("all_slot_maps_share_sample_path", _test_all_maps_use_slot_sample, failures)

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


func _test_map_size_adapts() -> String:
	# "Whatever map_size I pick, the plugin must adapt." A value that isn't a
	# multiple of chunk_size would otherwise leave orphan modulo cells
	# (un-rendered, un-paintable). The setter aligns it to a clean
	# chunk-divisible value so the chunk grid always tiles. (Headless: the
	# setter still aligns map_size even though it skips the editor-only
	# rebuild branch.)
	var node: Node3D = TerrainNode.new()
	var cs: int = node.chunk_size
	node.map_size = cs * 4 + 7  # deliberately not a multiple of chunk_size
	var ms: int = node.map_size
	node.free()
	if ms <= 0:
		return "map_size must stay positive after adapt, got %d" % ms
	if cs > 0 and ms % cs != 0:
		return "map_size %d must adapt to a multiple of chunk_size %d (no orphan cells)" % [ms, cs]
	return ""


func _test_externalize_any_size() -> String:
	# TKT-007: externalisation must be size-INDEPENDENT so terrain data is
	# never embedded in the .tscn whatever map_size the user picks.
	# Tiny terrain, no external path yet → must externalise.
	if not Orch._should_externalize(16, false, false):
		return "tiny terrain (16 cells / 4²) must externalise"
	# Default 256² → must externalise.
	if not Orch._should_externalize(65536, false, false):
		return "256² terrain must externalise"
	# Large 1024² → must externalise.
	if not Orch._should_externalize(1048576, false, false):
		return "1024² terrain must externalise"
	# Empty terrain → nothing to write.
	if Orch._should_externalize(0, false, false):
		return "empty terrain must not externalise"
	# Already external with a present .res → don't rewrite every save.
	if Orch._should_externalize(65536, true, false):
		return "already-external terrain must not re-externalise"
	# Already external but .res went missing → must re-externalise.
	if not Orch._should_externalize(65536, true, true):
		return "external terrain with a missing .res must re-externalise"
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


func _slot_sample_body() -> String:
	var code := FileAccess.get_file_as_string(SHADER_PATH)
	if code.is_empty():
		return ""
	var start := code.find("vec3 _mt_slot_sample")
	if start < 0:
		return ""
	var brace := code.find("{", start)
	var close := code.find("}", brace)
	if brace < 0 or close < 0:
		return ""
	return code.substr(brace, close - brace)


func _test_slot_sample_no_mobile_gate() -> String:
	# TKT-006 + TKT-010: triplanar must NOT gate on mobile_quality — that
	# bypass made the triplanar slider do nothing on Forward Mobile and
	# slopes kept stretching ("eğimde kayma"). TKT-010 removed mobile_quality
	# entirely; the single _mt_slot_sample path must not reference it.
	var body := _slot_sample_body()
	if body == "":
		return "could not isolate _mt_slot_sample in terrain.gdshader"
	if "mobile_quality" in body:
		return "slot sampling must not gate on mobile_quality (re-introduces eğimde kayma)"
	return ""


func _test_all_maps_use_slot_sample() -> String:
	# TKT-010: every map of a slot (albedo, normal, roughness, ao) must go
	# through the SAME _mt_slot_sample path so changing tiling/variation/
	# triplanar keeps them coherent. Roughness/AO previously sampled flat
	# texture(tex_r_/tex_ao_, uv) and desynced; that must be gone, and the
	# old separate _mt_normal_sample must no longer exist.
	var code := FileAccess.get_file_as_string(SHADER_PATH)
	if code.is_empty():
		return "could not read terrain.gdshader"
	if "_mt_normal_sample" in code:
		return "_mt_normal_sample must be gone (normal now shares _mt_slot_sample)"
	if "texture(tex_r_" in code or "texture(tex_ao_" in code:
		return "roughness/ao must use _mt_slot_sample, not flat texture(uv)"
	for sampler in ["tex_a_0", "tex_n_0", "tex_r_0", "tex_ao_0"]:
		if not ("_mt_slot_sample(" + sampler in code):
			return "%s must be sampled via _mt_slot_sample" % sampler
	return ""
