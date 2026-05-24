#!/usr/bin/env bash
# Run the full MobileTerrain3D V22 test suite headlessly.
# Usage: test/run_all.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> 1/12 parse check"
bash "$ROOT/test/parse_check.sh"

# Shared fixture setup: symlink the addon + test scripts into the fixture
# project so a single re-import registers class_names for all suites.
SAVE_TEST="$ROOT/test/fixtures/save_test"
mkdir -p "$SAVE_TEST/addons"
if [ ! -L "$SAVE_TEST/addons/mobile_terrain" ]; then
  rm -rf "$SAVE_TEST/addons/mobile_terrain"
  ln -s "$ROOT/addons/mobile_terrain" "$SAVE_TEST/addons/mobile_terrain"
fi
if [ ! -L "$SAVE_TEST/integration_tests" ]; then
  ln -s "$ROOT/test/integration" "$SAVE_TEST/integration_tests"
fi
if [ ! -L "$SAVE_TEST/unit_tests" ]; then
  ln -s "$ROOT/test/unit" "$SAVE_TEST/unit_tests"
fi
if [ ! -L "$SAVE_TEST/visual_tests" ]; then
  ln -s "$ROOT/test/visual" "$SAVE_TEST/visual_tests"
fi
cd "$SAVE_TEST"
godot --headless --import --quit >/dev/null 2>&1 || true

echo "==> 2/12 save roundtrip"
godot --headless --script integration_tests/save_roundtrip.gd 2>&1 | tee /tmp/save_roundtrip.log
grep -q "^SAVE_ROUNDTRIP_OK" /tmp/save_roundtrip.log

echo "==> 3/12 multi-terrain save"
godot --headless --script integration_tests/multi_terrain_save.gd 2>&1 | tee /tmp/multi_terrain.log
grep -q "^MULTI_TERRAIN_OK" /tmp/multi_terrain.log

echo "==> 4/12 raymarch unit test"
godot --headless --script unit_tests/test_raymarch_system.gd 2>&1 | tee /tmp/raymarch.log
grep -q "^RAYMARCH_TEST_OK" /tmp/raymarch.log

echo "==> 5/12 sculpt ops unit test"
godot --headless --script unit_tests/test_sculpt_ops.gd 2>&1 | tee /tmp/sculpt_ops.log
grep -q "^SCULPT_OPS_TEST_OK" /tmp/sculpt_ops.log

echo "==> 6/12 path safety unit test (TKT-002 C1 regression)"
godot --headless --script unit_tests/test_path_safety.gd 2>&1 | tee /tmp/path_safety.log
grep -q "^PATH_SAFETY_TEST_OK" /tmp/path_safety.log

echo "==> 7/12 brush system unit test (TKT-002 C4 regression)"
godot --headless --script unit_tests/test_brush_system.gd 2>&1 | tee /tmp/brush_system.log
grep -q "^BRUSH_SYSTEM_TEST_OK" /tmp/brush_system.log

echo "==> 8/14 splatmap system unit test (TKT-003 Phase A.1 extraction)"
godot --headless --script unit_tests/test_splatmap_system.gd 2>&1 | tee /tmp/splatmap_system.log
grep -q "^SPLATMAP_SYSTEM_TEST_OK" /tmp/splatmap_system.log

echo "==> 9/14 heightmap io unit test (TKT-003 Phase A.2 extraction)"
godot --headless --script unit_tests/test_heightmap_io.gd 2>&1 | tee /tmp/heightmap_io.log
grep -q "^HEIGHTMAP_IO_TEST_OK" /tmp/heightmap_io.log

echo "==> object placement unit test (transform + spacing logic)"
godot --headless --script unit_tests/test_object_placement.gd 2>&1 | tee /tmp/object_placement.log
grep -q "^OBJECT_PLACEMENT_TEST_OK" /tmp/object_placement.log

echo "==> input router unit test (touch + mouse stroke routing)"
godot --headless --script unit_tests/test_input_router.gd 2>&1 | tee /tmp/input_router.log
grep -q "^INPUT_ROUTER_TEST_OK" /tmp/input_router.log

echo "==> object .res roundtrip (path-less mesh persistence)"
godot --headless --script integration_tests/object_roundtrip.gd 2>&1 | tee /tmp/object_roundtrip.log
grep -q "^OBJECT_ROUNDTRIP_OK" /tmp/object_roundtrip.log

echo "==> scene no-embed (material/splatmap stays out of the .tscn)"
godot --headless --script integration_tests/scene_no_embed.gd 2>&1 | tee /tmp/scene_no_embed.log
grep -q "^SCENE_NO_EMBED_OK" /tmp/scene_no_embed.log

echo "==> 11/14 chunk renderer unit test (TKT-003 Phase A.4 extraction)"
godot --headless --script unit_tests/test_chunk_renderer.gd 2>&1 | tee /tmp/chunk_renderer.log
grep -q "^CHUNK_RENDERER_TEST_OK" /tmp/chunk_renderer.log

echo "==> 12/14 HIGH fixes wave 1 (TKT-004 H5 brush LUT + H8 paint-slot clamp)"
godot --headless --script unit_tests/test_high_fixes_wave1.gd 2>&1 | tee /tmp/high_wave1.log
grep -q "^HIGH_WAVE1_TEST_OK" /tmp/high_wave1.log

echo "==> 13/14 user-reported fixes (TKT-006/007 externalize + map_size adapt + dead slope)"
godot --headless --script unit_tests/test_user_fixes.gd 2>&1 | tee /tmp/user_fixes.log
grep -q "^USER_FIXES_TEST_OK" /tmp/user_fixes.log

echo "==> 14/15 undo recorder unit test (TKT-009 Phase B.2 extraction)"
godot --headless --script unit_tests/test_undo_recorder.gd 2>&1 | tee /tmp/undo_recorder.log
grep -q "^UNDO_RECORDER_TEST_OK" /tmp/undo_recorder.log

echo "==> 15/15 editor LOD seed unit test (load-spike fix: update_chunk_mesh honours seeded _chunk_lod)"
godot --headless --script unit_tests/test_editor_lod_seed.gd 2>&1 | tee /tmp/editor_lod_seed.log
grep -q "^EDITOR_LOD_SEED_OK" /tmp/editor_lod_seed.log

echo
echo "ALL TESTS PASSED"
