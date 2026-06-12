#!/usr/bin/env bash
# Skill yönetişim doğrulayıcısı — .claude/skills/ altındaki her SKILL.md'nin
# docs/STANDARDS.md'deki yapı sözleşmesine uyduğunu mekanik olarak denetler.
#
# Sözleşme (her SKILL.md için):
#   1. YAML frontmatter: name, description, version (SemVer MAJOR.MINOR.PATCH)
#   2. frontmatter `name` == klasör adı
#   3. Zorunlu bölümler: İzlenebilirlik, Prosedür, Kabul kriterleri,
#      Hata yolları, Changelog
#   4. Skill içinde referans verilen scripts/*.sh dosyaları mevcut + çalıştırılabilir
#
# Kullanım: scripts/validate_skills.sh
# Çıkış kodu: 0 = hepsi uyumlu, 1 = en az bir ihlal
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS_DIR="$ROOT/.claude/skills"
FAIL=0

# Üçüncü-parti / harici skill'ler sözleşme dışı (kendi yönetişimleri var)
EXEMPT="godot-plugin-studio"

SKILL_FAIL=0
note() { printf '%s\n' "$*"; }
violation() { printf 'İHLAL  %s\n' "$*"; FAIL=1; SKILL_FAIL=1; }

for dir in "$SKILLS_DIR"/*/; do
  skill="$(basename "$dir")"
  SKILL_FAIL=0
  case " $EXEMPT " in *" $skill "*) note "ATLA   $skill (harici, sözleşme dışı)"; continue;; esac

  md="$dir/SKILL.md"
  if [ ! -f "$md" ]; then violation "$skill: SKILL.md yok"; continue; fi

  # --- 1. frontmatter alanları ---
  fm="$(awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$md")"
  name="$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p' | head -1)"
  desc="$(printf '%s\n' "$fm" | sed -n 's/^description:[[:space:]]*//p' | head -1)"
  ver="$(printf '%s\n' "$fm" | sed -n 's/^version:[[:space:]]*//p' | head -1)"

  [ -n "$name" ] || violation "$skill: frontmatter 'name' eksik"
  [ -n "$desc" ] || violation "$skill: frontmatter 'description' eksik"
  if ! printf '%s' "$ver" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    violation "$skill: 'version' SemVer değil (bulunan: '${ver:-yok}')"
  fi

  # --- 2. name == klasör adı ---
  if [ -n "$name" ] && [ "$name" != "$skill" ]; then
    violation "$skill: frontmatter name '$name' klasör adıyla uyuşmuyor"
  fi

  # --- 3. zorunlu bölümler ---
  # Türkçe İ/i büyük-küçük dönüşümü locale'e bağlı olduğundan desenler
  # baş harfsiz/ASCII-güvenli fragman olarak aranır.
  for sec in "zlenebilirlik" "Prosedür" "Kabul kriterleri" "Hata yolları" "Changelog"; do
    grep -q "^#.*$sec" "$md" || violation "$skill: zorunlu bölüm eksik: $sec"
  done

  # --- 4. referans verilen scriptler mevcut + çalıştırılabilir ---
  refs="$(grep -oE 'scripts/[A-Za-z0-9_./-]+\.(sh|py)' "$md" | sort -u || true)"
  for ref in $refs; do
    if [ ! -f "$ROOT/$ref" ]; then
      violation "$skill: referans verilen $ref mevcut değil"
    elif [ "${ref##*.}" = "sh" ] && [ ! -x "$ROOT/$ref" ]; then
      violation "$skill: $ref çalıştırılabilir değil (chmod +x gerekli)"
    fi
  done

  if [ $SKILL_FAIL -eq 0 ]; then
    note "UYUMLU $skill (v$ver)"
  fi
done

echo
if [ $FAIL -ne 0 ]; then
  echo "SKILL_VALIDATION_FAILED"
  exit 1
fi
echo "SKILL_VALIDATION_OK"
