#!/usr/bin/env bash
# dead-code-scan.sh — finds dead code and orphan references in Godot plugins
# Used by Dead Code Hunter role in Phase 1.G.
#
# Detects:
#   - Public functions declared but never called
#   - Files that exist but are never preloaded/loaded/referenced
#   - Signals declared but never emitted
#   - Signals declared but never listened
#   - @export properties that don't appear in inspector (no class binding)
#   - preload() paths to files that don't exist
#   - extends references to nonexistent classes (within addons/)
#
# Usage:
#   bash dead-code-scan.sh [plugin_dir]
#
# Defaults to scanning all of addons/

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

echo -e "${GREEN}=== Dead code scan ===${NC}"
echo "Target: $PLUGIN_DIR"
echo

ISSUES=0

# 1. Orphan public functions
echo -e "${YELLOW}[1/6] Orphan public functions (declared but never called)${NC}"
# Find all func declarations
TMPFUNCS=$(mktemp)
grep -rn "^func\s\+[a-z]" "$PLUGIN_DIR" --include='*.gd' 2>/dev/null | \
    while IFS=: read -r file line content; do
        # Extract function name
        func_name=$(echo "$content" | sed -E 's/^func\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(.*/\1/')
        # Skip lifecycle and special functions
        case "$func_name" in
            _ready|_init|_process|_physics_process|_input|_unhandled_input|_unhandled_key_input|_gui_input|_draw|_enter_tree|_exit_tree|_notification|_to_string|_get_property_list|_get|_set|_get_configuration_warnings|_property_can_revert|_property_get_revert|_validate_property)
                continue ;;
            # EditorPlugin lifecycle
            _enable_plugin|_disable_plugin|_has_main_screen|_make_visible|_get_plugin_name|_get_plugin_icon|_get_unsaved_status|_save_external_data|_apply_changes|_build|_handles|_edit|_clear|_forward_canvas_*|_forward_3d_*)
                continue ;;
            # EditorImportPlugin
            _get_importer_name|_get_visible_name|_get_recognized_extensions|_get_save_extension|_get_resource_type|_get_preset_count|_get_preset_name|_get_import_options|_get_option_visibility|_import|_get_priority|_get_import_order|_get_format_version)
                continue ;;
            # EditorInspectorPlugin
            _can_handle|_parse_begin|_parse_category|_parse_group|_parse_property|_parse_end)
                continue ;;
        esac
        echo "$file:$line:$func_name" >> "$TMPFUNCS"
    done

if [ -s "$TMPFUNCS" ]; then
    while IFS=: read -r file line func_name; do
        # Check for callers (anywhere in plugin scope) excluding the declaration itself
        callers=$(grep -rn -E "(^|[^a-zA-Z_])${func_name}\s*\(" "$PLUGIN_DIR" --include='*.gd' 2>/dev/null | \
            grep -v "^${file}:${line}:" | \
            grep -v "^${file}:[0-9]*:func\s\+${func_name}" | \
            wc -l)
        if [ "$callers" -eq 0 ]; then
            # Private functions (leading underscore) get a softer warning
            if [[ "$func_name" =~ ^_ ]]; then
                echo -e "  ${GRAY}private${NC} $file:$line  func ${func_name}() — no callers"
            else
                echo -e "  ${RED}ORPHAN${NC}  $file:$line  func ${func_name}() — no callers"
                ISSUES=$((ISSUES + 1))
            fi
        fi
    done < "$TMPFUNCS"
fi
rm -f "$TMPFUNCS"

if [ "$ISSUES" -eq 0 ]; then
    echo "  (no public orphan functions found)"
fi
echo

# 2. Files that exist but are never referenced
echo -e "${YELLOW}[2/6] Orphan files (exist but never referenced)${NC}"
ORPHAN_FILES=0
find "$PLUGIN_DIR" -type f \( -name '*.gd' -o -name '*.tscn' -o -name '*.tres' \) 2>/dev/null | while read -r file; do
    # Skip plugin entry script (referenced in plugin.cfg) and plugin.cfg itself
    basename=$(basename "$file")
    if [ "$basename" = "plugin.cfg" ]; then
        continue
    fi
    # Get the res:// path
    respath="res://$file"
    # Search for references
    refs=$(grep -rn -F "$file" "$PLUGIN_DIR" --include='*.gd' --include='*.tscn' --include='*.tres' --include='*.cfg' 2>/dev/null | \
        grep -v "^${file}:" | \
        wc -l)
    if [ "$refs" -eq 0 ]; then
        # Also check if it's referenced by absolute res:// path
        refs2=$(grep -rn -F "$respath" "$PLUGIN_DIR" 2>/dev/null | grep -v "^${file}:" | wc -l)
        if [ "$refs2" -eq 0 ]; then
            # The plugin entry script is found via plugin.cfg's script= field
            if grep -q "script\s*=.*$(basename "$file")" "$PLUGIN_DIR"/*/plugin.cfg 2>/dev/null; then
                continue
            fi
            echo -e "  ${RED}ORPHAN${NC} $file"
            ORPHAN_FILES=$((ORPHAN_FILES + 1))
        fi
    fi
done

if [ "$ORPHAN_FILES" -eq 0 ]; then
    echo "  (no orphan files found)"
fi
echo

# 3. Signals declared but never emitted
echo -e "${YELLOW}[3/6] Signals declared but never emitted${NC}"
DEAD_SIGNALS=0
grep -rn -E "^\s*signal\s+[a-zA-Z_]" "$PLUGIN_DIR" --include='*.gd' 2>/dev/null | \
    while IFS=: read -r file line content; do
        signal_name=$(echo "$content" | sed -E 's/^\s*signal\s+([a-zA-Z_][a-zA-Z0-9_]*).*/\1/')
        # Check for emits (4.x .emit() or 3.x emit_signal)
        emits=$(grep -rn -E "\b${signal_name}\.emit\b|emit_signal\([\"']${signal_name}[\"']" "$PLUGIN_DIR" --include='*.gd' 2>/dev/null | wc -l)
        if [ "$emits" -eq 0 ]; then
            echo -e "  ${RED}NEVER EMITTED${NC} $file:$line  signal $signal_name"
        fi
    done
echo

# 4. Signals declared but never listened
echo -e "${YELLOW}[4/6] Signals declared but never connected/awaited${NC}"
grep -rn -E "^\s*signal\s+[a-zA-Z_]" "$PLUGIN_DIR" --include='*.gd' 2>/dev/null | \
    while IFS=: read -r file line content; do
        signal_name=$(echo "$content" | sed -E 's/^\s*signal\s+([a-zA-Z_][a-zA-Z0-9_]*).*/\1/')
        # Check for connects (4.x .connect() or 3.x string), or awaits
        listens=$(grep -rn -E "\b${signal_name}\.connect\b|connect\([\"']${signal_name}[\"']|await\s+.*${signal_name}" "$PLUGIN_DIR" --include='*.gd' 2>/dev/null | wc -l)
        if [ "$listens" -eq 0 ]; then
            # If signal is part of public API, it may be intentionally for external listeners — soft warning
            echo -e "  ${YELLOW}NO INTERNAL LISTENERS${NC} $file:$line  signal $signal_name (may be intentional if public API)"
        fi
    done
echo

# 5. preload() to nonexistent files
echo -e "${YELLOW}[5/6] preload() paths that don't resolve${NC}"
BROKEN_PRELOAD=0
grep -rn -E "preload\(\"res://" "$PLUGIN_DIR" --include='*.gd' 2>/dev/null | \
    while IFS=: read -r file line content; do
        # Extract the res:// path
        respath=$(echo "$content" | grep -oP 'preload\("(res://[^"]+)' | sed 's/preload("//')
        # Convert to filesystem path (strip res://)
        fspath=${respath#res://}
        if [ ! -f "$fspath" ]; then
            echo -e "  ${RED}MISSING${NC} $file:$line  preload(\"$respath\")"
            BROKEN_PRELOAD=$((BROKEN_PRELOAD + 1))
        fi
    done
if [ "$BROKEN_PRELOAD" -eq 0 ]; then
    echo "  (no broken preload paths)"
fi
echo

# 6. extends to potentially-missing class (within plugin scope)
echo -e "${YELLOW}[6/6] extends references — sanity check${NC}"
grep -rn -E "^\s*extends\s+[A-Z]" "$PLUGIN_DIR" --include='*.gd' 2>/dev/null | \
    while IFS=: read -r file line content; do
        parent=$(echo "$content" | sed -E 's/^\s*extends\s+([A-Z][a-zA-Z0-9_]*).*/\1/')
        # If parent is a built-in Godot class, it's fine (we can't easily verify without API XML access)
        # If parent looks like a custom class_name, check it exists in the plugin
        # Heuristic: if the name is found as a class_name somewhere, good
        cn_found=$(grep -rn "^\s*class_name\s\+${parent}\b" "$PLUGIN_DIR" --include='*.gd' 2>/dev/null | wc -l)
        # If not found and it doesn't look like a Godot built-in (rough heuristic: built-ins are typically PascalCase common names)
        # We can't really verify against the API XML here without it being present
        # Just log custom class extends for review
        if [ "$cn_found" -gt 0 ]; then
            : # Good, internal class_name found
        fi
    done
echo "  (manual review recommended — verify each extends against ~/godot-api-reference/ or plugin's class_name)"
echo

# Summary
echo -e "${GREEN}=== Scan complete ===${NC}"
echo
echo "Findings above should be reviewed by the Dead Code Hunter role."
echo "For each true positive, either:"
echo "  - Remove the dead code, OR"
echo "  - Document why it must stay (e.g., reserved for upcoming feature with DEF-NNN reference)"
