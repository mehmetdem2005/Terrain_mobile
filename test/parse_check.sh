#!/usr/bin/env bash
# Headless parse-check for the MobileTerrain3D addon.
# Usage: test/parse_check.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE="$ROOT/test/fixtures/parse_check"

# Make sure the addon is symlinked into the fixture project (idempotent).
mkdir -p "$FIXTURE/addons"
if [ ! -L "$FIXTURE/addons/mobile_terrain" ]; then
  rm -rf "$FIXTURE/addons/mobile_terrain"
  ln -s "$ROOT/addons/mobile_terrain" "$FIXTURE/addons/mobile_terrain"
fi

cd "$FIXTURE"
# Import first so class_name globals are registered.
godot --headless --import --quit >/dev/null 2>&1 || true
godot --headless --script parse_check.gd 2>&1 | tee /tmp/parse_check.log
grep -q "^PARSE_CHECK_OK" /tmp/parse_check.log
