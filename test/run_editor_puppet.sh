#!/usr/bin/env bash
# Editor-puppet harness: drive the REAL editor + plugin headlessly and shoot the 3D viewport.
#
# Where run_visual.sh renders the node through a bare SceneTree, this opens the
# actual Godot EDITOR (under xvfb + software GL), lets the shipping
# mobile_terrain plugin load, and runs test/editor_puppet/puppet_plugin.gd which
# drives the node exactly like a user (sculpt, place objects, paint per-slot) and
# saves a PNG of the editor's 3D viewport. This lets the assistant visually
# verify EDITOR behaviour with no human in the loop.
#
# It is fully self-contained: it regenerates a throwaway project in /tmp each run
# (symlinking the shipping addon + the puppet addon, writing project.godot +
# puppet.tscn), so nothing but the two committed files
# (test/editor_puppet/* and this script) is needed.
#
# Requirements (install once, root):
#   apt-get install -y libgl1-mesa-dri mesa-vulkan-drivers libvulkan1 mesa-utils xvfb
#
# Usage: test/run_editor_puppet.sh [objects|perslot] [output.png]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCENARIO="${1:-objects}"
OUT="${2:-/tmp/mt_puppet_${SCENARIO}.png}"
PROJ="/tmp/mt_puppet_proj"
TIMEOUT="${MT_PUPPET_TIMEOUT:-240}"

case "$SCENARIO" in
  objects|perslot) ;;
  *) echo "ERROR: unknown scenario '$SCENARIO' (use 'objects' or 'perslot')"; exit 2 ;;
esac

command -v xvfb-run >/dev/null 2>&1 || { echo "SKIP: xvfb-run not installed"; exit 0; }
command -v godot >/dev/null 2>&1 || { echo "ERROR: godot not on PATH"; exit 1; }

# --- (re)build the throwaway project ------------------------------------------
mkdir -p "$PROJ/addons"
# Symlink the shipping addon + the test-only puppet addon into the project.
ln -sfn "$ROOT/addons/mobile_terrain" "$PROJ/addons/mobile_terrain"
ln -sfn "$ROOT/test/editor_puppet"   "$PROJ/addons/editor_puppet"

cat > "$PROJ/project.godot" <<'EOF'
config_version=5

[application]

config/name="MT Puppet"
config/features=PackedStringArray("4.6", "GL Compatibility")

[editor_plugins]

enabled=PackedStringArray("res://addons/mobile_terrain/plugin.cfg", "res://addons/editor_puppet/plugin.cfg")

[rendering]

renderer/rendering_method="gl_compatibility"
EOF

# Root node IS the terrain (puppet uses get_edited_scene_root()). map_size=64
# matches the puppet scenarios' 64x64 height_data; chunk_size=32 tiles it 2x2.
cat > "$PROJ/puppet.tscn" <<'EOF'
[gd_scene format=3]

[ext_resource type="Script" path="res://addons/mobile_terrain/mobile_terrain_node.gd" id="1"]

[node name="PuppetTerrain" type="Node3D"]
script = ExtResource("1")
map_size = 64
chunk_size = 32
EOF

LOG="/tmp/mt_puppet_${SCENARIO}.log"
echo "==> importing puppet project (headless)"
( cd "$PROJ" && godot --headless --import --quit ) >/dev/null 2>&1 || true

echo "==> driving editor (xvfb + software GL, scenario=$SCENARIO, timeout=${TIMEOUT}s)"
set +e
MT_PUPPET="$SCENARIO" timeout "$TIMEOUT" xvfb-run -a -s "-screen 0 1280x720x24" godot \
  --editor --rendering-driver opengl3 --rendering-method gl_compatibility \
  --path "$PROJ" 2>&1 | tee "$LOG"
RC=${PIPESTATUS[1]}
set -e
if [ "$RC" -eq 124 ]; then
  echo "PUPPET_FAILED: editor timed out after ${TIMEOUT}s (software GL is slow; raise MT_PUPPET_TIMEOUT)"
  exit 1
fi

# Surface real script/shader errors (the editor often exits 0 even after them).
if grep -qE "SCRIPT ERROR|SHADER ERROR|Parse Error|Failed to load script" "$LOG"; then
  echo "PUPPET_WARN: errors found in log:"
  grep -nE "SCRIPT ERROR|SHADER ERROR|Parse Error|Failed to load script" "$LOG" | head -20
fi

# The puppet prints the globalized PNG path; copy it to the requested output.
SHOT="$(grep -oE 'MT_PUPPET_SHOT: .*' "$LOG" | tail -1 | sed 's/MT_PUPPET_SHOT: //')"
if [ -n "$SHOT" ] && [ -f "$SHOT" ]; then
  cp "$SHOT" "$OUT"
  echo "PUPPET_OK -> $OUT"
else
  echo "PUPPET_FAILED: no screenshot produced (see $LOG)"
  exit 1
fi
