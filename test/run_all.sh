#!/usr/bin/env bash
# Run the full MobileTerrain3D V22 test suite headlessly.
# Usage: test/run_all.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> 1/7 parse check"
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
cd "$SAVE_TEST"
godot --headless --import --quit >/dev/null 2>&1 || true

echo "==> 2/7 save roundtrip"
godot --headless --script integration_tests/save_roundtrip.gd 2>&1 | tee /tmp/save_roundtrip.log
grep -q "^SAVE_ROUNDTRIP_OK" /tmp/save_roundtrip.log

echo "==> 3/7 multi-terrain save"
godot --headless --script integration_tests/multi_terrain_save.gd 2>&1 | tee /tmp/multi_terrain.log
grep -q "^MULTI_TERRAIN_OK" /tmp/multi_terrain.log

echo "==> 4/7 raymarch unit test"
godot --headless --script unit_tests/test_raymarch_system.gd 2>&1 | tee /tmp/raymarch.log
grep -q "^RAYMARCH_TEST_OK" /tmp/raymarch.log

echo "==> 5/7 sculpt ops unit test"
godot --headless --script unit_tests/test_sculpt_ops.gd 2>&1 | tee /tmp/sculpt_ops.log
grep -q "^SCULPT_OPS_TEST_OK" /tmp/sculpt_ops.log

echo "==> 6/7 path safety unit test (TKT-002 C1 regression)"
godot --headless --script unit_tests/test_path_safety.gd 2>&1 | tee /tmp/path_safety.log
grep -q "^PATH_SAFETY_TEST_OK" /tmp/path_safety.log

echo "==> 7/7 brush system unit test (TKT-002 C4 regression)"
godot --headless --script unit_tests/test_brush_system.gd 2>&1 | tee /tmp/brush_system.log
grep -q "^BRUSH_SYSTEM_TEST_OK" /tmp/brush_system.log

echo
echo "ALL TESTS PASSED"
