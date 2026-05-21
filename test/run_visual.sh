#!/usr/bin/env bash
# Visual render smoke test for MobileTerrain3D.
#
# Unlike run_all.sh (pure headless), this renders real frames through a
# software GPU (Mesa llvmpipe/lavapipe) under a virtual framebuffer (Xvfb)
# and saves a PNG. It proves the render path produces actual geometry —
# the visual complement to the headless mesh-invariant unit tests, and the
# harness Phase B reuses for UI screenshot verification.
#
# Requirements (install once, root):
#   apt-get install -y libgl1-mesa-dri mesa-vulkan-drivers \
#       libvulkan1 mesa-utils xvfb
#
# Usage: test/run_visual.sh [output.png]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-/tmp/terrain_render.png}"

command -v xvfb-run >/dev/null 2>&1 || { echo "SKIP: xvfb-run not installed"; exit 0; }
command -v godot >/dev/null 2>&1 || { echo "ERROR: godot not on PATH"; exit 1; }

SAVE_TEST="$ROOT/test/fixtures/save_test"
mkdir -p "$SAVE_TEST/addons"
[ -L "$SAVE_TEST/addons/mobile_terrain" ] || ln -s "$ROOT/addons/mobile_terrain" "$SAVE_TEST/addons/mobile_terrain"
[ -L "$SAVE_TEST/visual_tests" ] || ln -s "$ROOT/test/visual" "$SAVE_TEST/visual_tests"

echo "==> rendering terrain (xvfb + software GPU)"
xvfb-run -a -s "-screen 0 1280x720x24" godot \
  --rendering-driver opengl3 --rendering-method gl_compatibility \
  --path "$SAVE_TEST" \
  --script res://visual_tests/render_terrain.gd 2>&1 | tee /tmp/visual_render.log

# render_terrain.gd writes to user://; resolve and copy to the requested path.
SHOT="$(grep -oE 'SHOT_SAVED: .*' /tmp/visual_render.log | sed 's/SHOT_SAVED: //')"
if [ -n "$SHOT" ] && [ -f "$SHOT" ]; then
  cp "$SHOT" "$OUT"
  echo "VISUAL_RENDER_OK -> $OUT"
else
  echo "VISUAL_RENDER_FAILED"
  exit 1
fi
