#!/usr/bin/env bash
# wiring-audit.sh — forward wiring scan for Godot plugins
# For every PUBLIC function, property, and signal in the plugin, verify
# at least one caller / reader / connection exists.
#
# Used by Integration Engineer in Phase 1.F (per sub-task) and Phase 1.G (final).
#
# Usage:
#   bash wiring-audit.sh [plugin_dir]
#   bash wiring-audit.sh addons/my_plugin
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

# Scan scope is the entire project (plugin may be called from scenes, scripts, tests)
SCAN_SCOPE="$PLUGIN_DIR scripts scenes test tests"
EXISTING_SCOPE=""
for d in $SCAN_SCOPE; do
    [ -d "$d" ] && EXISTING_SCOPE="$EXISTING_SCOPE $d"
done

echo -e "${GREEN}=== Forward wiring audit ===${NC}"
echo "Plugin dir: $PLUGIN_DIR"
echo "Scan scope:$EXISTING_SCOPE"
echo

ISSUES=0

# Framework callbacks that don't need internal callers (the engine calls them)
FRAMEWORK_CALLBACKS="_ready _init _process _physics_process _input _unhandled_input _unhandled_key_input _gui_input _draw _enter_tree _exit_tree _notification _to_string _get_property_list _get _set _get_configuration_warnings _property_can_revert _property_get_revert _validate_property _enable_plugin _disable_plugin _has_main_screen _make_visible _get_plugin_name _get_plugin_icon _get_unsaved_status _save_external_data _apply_changes _build _handles _edit _clear _forward_canvas_gui_input _forward_canvas_draw_over_viewport _forward_canvas_force_draw_over_viewport _forward_3d_gui_input _forward_3d_draw_over_viewport _forward_3d_force_draw_over_viewport _get_importer_name _get_visible_name _get_recognized_extensions _get_save_extension _get_resource_type _get_preset_count _get_preset_name _get_import_options _get_option_visibility _import _get_priority _get_import_order _get_format_version _can_handle _parse_begin _parse_category _parse_group _parse_property _parse_end _export_file _export_begin _export_end _customize_resource _customize_scene _get_customization_configuration_hash _begin_customize_resources _begin_customize_scenes"

is_framework_callback() {
    local name="$1"
    case " $FRAMEWORK_CALLBACKS " in
        *" $name "*) return 0 ;;
        *) return 1 ;;
    esac
}

echo -e "${YELLOW}[1/3] Public functions — checking callers${NC}"
echo

# Find all public function declarations (not starting with _ — those are conventionally private)
TMPFUNCS=$(mktemp)
grep -rn -E "^\s*(static\s+)?func\s+[a-z]" $EXISTING_SCOPE --include='*.gd' 2>/dev/null > "$TMPFUNCS" || true

while IFS=: read -r file line content; do
    # Extract function name
    func_name=$(echo "$content" | sed -E 's/^\s*(static\s+)?func\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(.*/\2/')
    
    # Skip framework callbacks
    if is_framework_callback "$func_name"; then
        continue
    fi
    
    # Skip private (leading underscore) for now — Dead Code Hunter handles those
    if [[ "$func_name" =~ ^_ ]]; then
        continue
    fi
    
    # Count callers across the project
    # Caller patterns: .func_name(, instance.func_name(, ClassName.func_name(, plain func_name(
    callers=$(grep -rn -E "(\.|\b)${func_name}\s*\(" $EXISTING_SCOPE --include='*.gd' 2>/dev/null | \
        grep -v "^${file}:${line}:" | \
        grep -v ":[[:space:]]*\(static\s\+\)\?func\s\+${func_name}\b" | \
        wc -l)
    
    if [ "$callers" -eq 0 ]; then
        # Check if it's a signal handler bound via .connect()
        # Heuristic: methods starting with _on_ are likely signal handlers
        if [[ "$func_name" =~ ^_on_ ]]; then
            # Look for connects to this method
            connects=$(grep -rn -E "\.connect\(${func_name}\)|\.connect\(self\.${func_name}\b" $EXISTING_SCOPE --include='*.gd' 2>/dev/null | wc -l)
            if [ "$connects" -gt 0 ]; then
                continue  # wired via signal
            fi
        fi
        echo -e "  ${RED}ORPHAN PUBLIC${NC} $file:$line  func ${func_name}() — no callers found"
        ISSUES=$((ISSUES + 1))
    fi
done < "$TMPFUNCS"
rm -f "$TMPFUNCS"

if [ "$ISSUES" -eq 0 ]; then
    echo "  (all public functions are wired)"
fi
echo

# 2. Public signals — must have BOTH emit and listen (or be marked public API)
echo -e "${YELLOW}[2/3] Signals — checking emit and listen sites${NC}"
echo

SIG_ISSUES=0
TMPSIGS=$(mktemp)
grep -rn -E "^\s*signal\s+[a-zA-Z_]" $EXISTING_SCOPE --include='*.gd' 2>/dev/null > "$TMPSIGS" || true

while IFS=: read -r file line content; do
    signal_name=$(echo "$content" | sed -E 's/^\s*signal\s+([a-zA-Z_][a-zA-Z0-9_]*).*/\1/')
    
    # Check emit
    emits=$(grep -rn -E "\b${signal_name}\.emit\b|emit_signal\([\"']${signal_name}[\"']" $EXISTING_SCOPE --include='*.gd' 2>/dev/null | wc -l)
    # Check listen (connect or await)
    listens=$(grep -rn -E "\b${signal_name}\.connect\b|connect\([\"']${signal_name}[\"']|await\s+.*\.${signal_name}\b|await\s+${signal_name}\b" $EXISTING_SCOPE --include='*.gd' 2>/dev/null | wc -l)
    
    # Check for @api: public annotation in a comment near the signal declaration
    is_public_api=0
    # Look at 3 lines before the signal
    start=$((line > 3 ? line - 3 : 1))
    if sed -n "${start},${line}p" "$file" 2>/dev/null | grep -qE "@api:?\s*public|public[\s-]api|external listeners"; then
        is_public_api=1
    fi
    
    if [ "$emits" -eq 0 ] && [ "$listens" -eq 0 ]; then
        echo -e "  ${RED}DEAD SIGNAL${NC} $file:$line  signal ${signal_name} — no emits AND no listeners"
        SIG_ISSUES=$((SIG_ISSUES + 1))
    elif [ "$emits" -eq 0 ]; then
        echo -e "  ${RED}NEVER EMITTED${NC} $file:$line  signal ${signal_name} — listeners exist but signal never fires"
        SIG_ISSUES=$((SIG_ISSUES + 1))
    elif [ "$listens" -eq 0 ]; then
        if [ "$is_public_api" -eq 1 ]; then
            echo -e "  ${GRAY}public-api${NC} $file:$line  signal ${signal_name} — no internal listeners (marked @api: public)"
        else
            echo -e "  ${YELLOW}NO LISTENERS${NC} $file:$line  signal ${signal_name} — emitted but nothing listens (mark @api: public if intentional)"
            SIG_ISSUES=$((SIG_ISSUES + 1))
        fi
    fi
done < "$TMPSIGS"
rm -f "$TMPSIGS"

if [ "$SIG_ISSUES" -eq 0 ]; then
    echo "  (all signals are wired or marked public API)"
fi
echo

# 3. Public @export properties — soft check (their "use" is via inspector, not code calls)
echo -e "${YELLOW}[3/3] @export properties — sanity check${NC}"
EXPORT_COUNT=$(grep -rn -E "^\s*@export" $EXISTING_SCOPE --include='*.gd' 2>/dev/null | wc -l)
echo "  Found ${EXPORT_COUNT} @export declarations across the codebase"
echo "  (these are wired by the Godot editor; no caller check needed)"
echo

# Summary
TOTAL=$((ISSUES + SIG_ISSUES))
echo -e "${GREEN}=== Forward wiring audit complete ===${NC}"
if [ "$TOTAL" -eq 0 ]; then
    echo -e "${GREEN}✓ All public surface is wired.${NC}"
    exit 0
else
    echo -e "${RED}✗ $TOTAL wiring issue(s) found.${NC}"
    echo
    echo "For each finding, the engineer must either:"
    echo "  - Add a caller/listener (wire it)"
    echo "  - Make the function/signal private (leading underscore + not exposed in API)"
    echo "  - Mark with @api: public comment (intentional external surface)"
    echo "  - Remove the unused symbol"
    echo "  - Defer via DEF-NNN with documented future plan"
    exit 1
fi
