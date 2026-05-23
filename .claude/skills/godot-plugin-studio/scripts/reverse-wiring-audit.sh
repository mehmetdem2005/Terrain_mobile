#!/usr/bin/env bash
# reverse-wiring-audit.sh — reverse wiring scan
# For each file in the plugin, verify it is referenced from at least one other file.
# Orphan files (exist but nothing references them) are flagged.
#
# Used by Integration Engineer + Dead Code Hunter in Phase 1.G.
#
# Usage:
#   bash reverse-wiring-audit.sh [plugin_dir]

set -uo pipefail

PLUGIN_DIR="${1:-addons}"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
GRAY='\033[0;37m'
NC='\033[0m'

if [ ! -d "$PLUGIN_DIR" ]; then
    echo -e "${RED}Directory not found: $PLUGIN_DIR${NC}"
    exit 1
fi

SCAN_SCOPE="$PLUGIN_DIR scripts scenes test tests"
EXISTING_SCOPE=""
for d in $SCAN_SCOPE; do
    [ -d "$d" ] && EXISTING_SCOPE="$EXISTING_SCOPE $d"
done

echo -e "${GREEN}=== Reverse wiring audit ===${NC}"
echo "Plugin dir: $PLUGIN_DIR"
echo "Scan scope:$EXISTING_SCOPE"
echo

ORPHANS=0
TOTAL_FILES=0

# Find all files that should be referenced
while IFS= read -r file; do
    TOTAL_FILES=$((TOTAL_FILES + 1))
    basename=$(basename "$file")
    
    # plugin.cfg is the root — Godot finds it via directory scan; no internal referent needed
    if [ "$basename" = "plugin.cfg" ]; then
        echo -e "  ${GRAY}ROOT${NC}      $file (plugin entry, discovered by Godot)"
        continue
    fi
    
    # README, LICENSE, CHANGELOG: documentation, no code reference expected
    case "$basename" in
        README.md|README.txt|LICENSE|LICENSE.md|LICENSE.txt|CHANGELOG.md|CHANGELOG.txt)
            echo -e "  ${GRAY}DOC${NC}       $file"
            continue
            ;;
    esac
    
    # Icon files (referenced from plugin.cfg or via @icon annotation)
    case "$basename" in
        icon.png|icon.svg|*.import)
            # .import files are auto-generated companions; tied to their original
            if [[ "$basename" == *.import ]]; then
                original="${file%.import}"
                if [ -f "$original" ]; then
                    echo -e "  ${GRAY}IMPORT${NC}    $file (companion to $original)"
                    continue
                fi
            fi
            ;;
    esac
    
    # Look for references to this file
    # Try several patterns: full path, just basename, res:// path
    respath="res://$file"
    
    refs=0
    
    # 1. Direct path reference (full or partial)
    r1=$(grep -rln -F "$file" $EXISTING_SCOPE 2>/dev/null | grep -v "^${file}$" | wc -l)
    refs=$((refs + r1))
    
    # 2. res:// path reference
    r2=$(grep -rln -F "$respath" $EXISTING_SCOPE 2>/dev/null | grep -v "^${file}$" | wc -l)
    refs=$((refs + r2))
    
    # 3. For .gd files: also check if they're the entry script of a plugin
    if [[ "$basename" == *.gd ]]; then
        # Check plugin.cfg files in this directory tree for script= reference
        dir=$(dirname "$file")
        while [ "$dir" != "." ] && [ "$dir" != "/" ]; do
            if [ -f "$dir/plugin.cfg" ]; then
                if grep -q "script\s*=.*$basename" "$dir/plugin.cfg" 2>/dev/null; then
                    refs=$((refs + 1))
                    break
                fi
            fi
            dir=$(dirname "$dir")
        done
    fi
    
    # 4. For class_name'd .gd files: also check by class_name (the class can be referenced without preload)
    if [[ "$basename" == *.gd ]]; then
        class_name=$(grep -E "^\s*class_name\s+[A-Z]" "$file" 2>/dev/null | head -1 | sed -E 's/^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*).*/\1/')
        if [ -n "$class_name" ]; then
            r3=$(grep -rln -E "\b${class_name}\b" $EXISTING_SCOPE --include='*.gd' --include='*.tscn' --include='*.tres' 2>/dev/null | grep -v "^${file}$" | wc -l)
            refs=$((refs + r3))
        fi
    fi
    
    if [ "$refs" -eq 0 ]; then
        echo -e "  ${RED}ORPHAN${NC}    $file"
        ORPHANS=$((ORPHANS + 1))
    else
        echo -e "  ${GREEN}wired${NC}     $file (referenced by ${refs} files)"
    fi
done < <(find "$PLUGIN_DIR" -type f \( -name '*.gd' -o -name '*.tscn' -o -name '*.tres' -o -name '*.cfg' -o -name '*.gdshader' -o -name '*.png' -o -name '*.svg' -o -name '*.md' \) 2>/dev/null | sort)

echo
echo -e "${GREEN}=== Reverse wiring audit complete ===${NC}"
echo "Files scanned: $TOTAL_FILES"
if [ "$ORPHANS" -eq 0 ]; then
    echo -e "${GREEN}✓ Zero orphan files.${NC}"
    exit 0
else
    echo -e "${RED}✗ $ORPHANS orphan file(s) found.${NC}"
    echo
    echo "For each orphan, the engineer must either:"
    echo "  - Reference the file from another (preload, load, scene ext_resource, etc.)"
    echo "  - Remove the file if no longer needed"
    echo "  - Defer via DEF-NNN if file is for upcoming feature (document the future caller)"
    exit 1
fi
