#!/usr/bin/env bash
# AutoNPC v4.0 — .mcaddon paketleyici. Önce doğrulama, sonra zip.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/dist/AutoNPC_PlayerAI_v4_0.mcaddon}"

python3 "$ROOT/tools/validate.py"

if command -v node >/dev/null; then
  find "$ROOT/BP/scripts" -name '*.js' -print0 | while IFS= read -r -d '' f; do
    node --check "$f"
  done
  echo "node --check: tüm scriptler sözdizimi temiz"
fi

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
TMP="$(mktemp -d)"
cp -r "$ROOT/BP" "$TMP/AutoNPC_PlayerAI_v40_BP"
cp -r "$ROOT/RP" "$TMP/AutoNPC_PlayerAI_v40_RP"
(cd "$TMP" && zip -r -q "$OUT" .)
rm -rf "$TMP"
echo "BUILD_OK $OUT ($(du -h "$OUT" | cut -f1))"
