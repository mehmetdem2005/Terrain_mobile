#!/usr/bin/env bash
# SLSA L1 uyumlu release build — MobileTerrain3D
#
# Üretilen artefaktlar (build/ altına):
#   MobileTerrain3D_v<X.Y.Z>.zip   — yalnızca addons/mobile_terrain (git arşivi, temiz ağaç)
#   SHA256SUMS                     — artefakt özetleri
#   provenance.json                — SLSA provenance: commit, tarih, builder, kaynak
#   sbom.spdx.txt                  — basit SPDX dosya envanteri (SHA256 + lisans alanı)
#
# Standart izlenebilirliği: docs/STANDARDS.md 2.1 (SemVer), 2.5 (SLSA),
# 2.6 (SBOM/SPDX), 2.8 (Keep a Changelog), 2.9 (Asset Library).
#
# Kullanım:
#   scripts/release_build.sh           # build (tüm ön koşullar sağlanmalı)
#   scripts/release_build.sh --check   # yalnızca uyumluluk denetimi, build yok
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CFG="$ROOT/addons/mobile_terrain/plugin.cfg"
CHANGES="$ROOT/addons/mobile_terrain/CHANGES.md"
CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1
FAIL=0
violation() { printf 'İHLAL  %s\n' "$*"; FAIL=1; }
ok() { printf 'OK     %s\n' "$*"; }

# --- Ön koşul 1: SemVer (STANDARDS 2.1) ---
VERSION="$(sed -n 's/^version="\(.*\)"/\1/p' "$CFG")"
if printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  ok "plugin.cfg sürümü SemVer: $VERSION"
else
  violation "plugin.cfg sürümü SemVer değil: '$VERSION' (MAJOR.MINOR.PATCH bekleniyor)"
fi

# --- Ön koşul 2: Changelog sürümü içeriyor (STANDARDS 2.8) ---
if grep -q "$VERSION" "$CHANGES"; then
  ok "CHANGES.md sürüm $VERSION kaydı içeriyor"
else
  violation "CHANGES.md '$VERSION' kaydı içermiyor (Keep a Changelog: her release girdili)"
fi

# --- Ön koşul 3: LICENSE (STANDARDS 2.9 Asset Library + 2.10) ---
if [ -f "$ROOT/LICENSE" ]; then
  ok "kök LICENSE mevcut"
else
  violation "kök LICENSE yok (Godot Asset Library zorunluluğu)"
fi

# --- Ön koşul 4: temiz çalışma ağacı (STANDARDS 2.5 SLSA: provenance commit'e bağlanır) ---
if git -C "$ROOT" diff --quiet && git -C "$ROOT" diff --cached --quiet; then
  ok "çalışma ağacı temiz"
else
  violation "çalışma ağacı kirli — provenance belirsiz olur, önce commit'le"
fi

# --- Ön koşul 5: test pipeline kanıtı (STANDARDS 1.7 / 4.10-3) ---
if [ -f /tmp/save_roundtrip.log ] && grep -q '^SAVE_ROUNDTRIP_OK' /tmp/save_roundtrip.log; then
  ok "test kanıtı bulundu (save_roundtrip yeşil)"
else
  violation "test kanıtı yok — önce test/run_all.sh çalıştır (log: /tmp/save_roundtrip.log)"
fi

echo
if [ $FAIL -ne 0 ]; then
  echo "RELEASE_PRECHECK_FAILED"
  exit 1
fi
echo "RELEASE_PRECHECK_OK"
[ $CHECK_ONLY -eq 1 ] && exit 0

# --- Build ---
OUT="$ROOT/build"
mkdir -p "$OUT"
COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
ZIP="$OUT/MobileTerrain3D_v${VERSION}.zip"

# git archive: yalnızca commit'lenmiş içerik → kurcalanmamışlık garantisi
git -C "$ROOT" archive --format=zip -o "$ZIP" HEAD addons/mobile_terrain LICENSE 2>/dev/null \
  || git -C "$ROOT" archive --format=zip -o "$ZIP" HEAD addons/mobile_terrain

# SBOM: dosya envanteri + SHA256 (SPDX-benzeri satır formatı)
{
  echo "SPDXVersion: SPDX-2.3"
  echo "DocumentName: MobileTerrain3D-${VERSION}"
  echo "Created: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  git -C "$ROOT" ls-files addons/mobile_terrain | while read -r f; do
    h="$(git -C "$ROOT" show "HEAD:$f" | sha256sum | cut -d' ' -f1)"
    echo "FileName: $f  SHA256: $h  LicenseConcluded: NOASSERTION"
  done
} > "$OUT/sbom.spdx.txt"

# SLSA provenance
cat > "$OUT/provenance.json" <<EOF
{
  "buildType": "scripts/release_build.sh",
  "builder": "$(git -C "$ROOT" config user.name 2>/dev/null || echo unknown)",
  "buildTimestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "sourceCommit": "$COMMIT",
  "sourceRepo": "$(git -C "$ROOT" remote get-url origin 2>/dev/null || echo local)",
  "artifact": "$(basename "$ZIP")",
  "version": "$VERSION"
}
EOF

(cd "$OUT" && sha256sum "$(basename "$ZIP")" sbom.spdx.txt provenance.json > SHA256SUMS)

echo "RELEASE_BUILD_OK $ZIP"
