#!/usr/bin/env bash
# Run the full MobileTerrain3D V22 test suite headlessly.
# Usage: test/run_all.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> 1/2 parse check"
bash "$ROOT/test/parse_check.sh"

echo "==> 2/2 save roundtrip"
SAVE_TEST="$ROOT/test/fixtures/save_test"
mkdir -p "$SAVE_TEST/addons"
if [ ! -L "$SAVE_TEST/addons/mobile_terrain" ]; then
  rm -rf "$SAVE_TEST/addons/mobile_terrain"
  ln -s "$ROOT/addons/mobile_terrain" "$SAVE_TEST/addons/mobile_terrain"
fi
if [ ! -L "$SAVE_TEST/integration_tests" ]; then
  ln -s "$ROOT/test/integration" "$SAVE_TEST/integration_tests"
fi
cd "$SAVE_TEST"
# Re-import so new class_name globals (added during refactor) register.
godot --headless --import --quit >/dev/null 2>&1 || true
godot --headless --script integration_tests/save_roundtrip.gd 2>&1 | tee /tmp/save_roundtrip.log
grep -q "^SAVE_ROUNDTRIP_OK" /tmp/save_roundtrip.log

echo
echo "ALL TESTS PASSED"
