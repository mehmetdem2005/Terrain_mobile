#!/usr/bin/env bash
# Run the full MobileTerrain3D V22 test suite headlessly.
# Usage: test/run_all.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> 1/5 parse check"
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

echo "==> 2/5 save roundtrip"
godot --headless --script integration_tests/save_roundtrip.gd 2>&1 | tee /tmp/save_roundtrip.log
grep -q "^SAVE_ROUNDTRIP_OK" /tmp/save_roundtrip.log

echo "==> 3/5 multi-terrain save"
godot --headless --script integration_tests/multi_terrain_save.gd 2>&1 | tee /tmp/multi_terrain.log
grep -q "^MULTI_TERRAIN_OK" /tmp/multi_terrain.log

echo "==> 4/5 raymarch unit test"
godot --headless --script unit_tests/test_raymarch_system.gd 2>&1 | tee /tmp/raymarch.log
grep -q "^RAYMARCH_TEST_OK" /tmp/raymarch.log

echo "==> 5/5 sculpt ops unit test"
godot --headless --script unit_tests/test_sculpt_ops.gd 2>&1 | tee /tmp/sculpt_ops.log
grep -q "^SCULPT_OPS_TEST_OK" /tmp/sculpt_ops.log

echo
echo "ALL TESTS PASSED"
