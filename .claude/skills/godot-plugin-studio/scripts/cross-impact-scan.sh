#!/usr/bin/env bash
# cross-impact-scan.sh — symbol-level dependency scan for Godot plugins
# Used by the Impact Analysis Engineer in Phase 1.F and 1.G.
#
# Usage:
#   bash cross-impact-scan.sh <symbol_name> [--type=func|prop|signal|class|file]
#   bash cross-impact-scan.sh commit_value --type=func
#   bash cross-impact-scan.sh VectorFieldDrawer --type=class
#   bash cross-impact-scan.sh velocity_changed --type=signal
#
# Scans addons/, scripts/, scenes/ recursively for references to the symbol.
# Outputs a categorized report suitable for inclusion in the impact analysis.

set -uo pipefail

SYMBOL="${1:-}"
TYPE="func"  # default
for arg in "${@:2}"; do
    case "$arg" in
        --type=*) TYPE="${arg#--type=}" ;;
    esac
done

if [ -z "$SYMBOL" ]; then
    echo "Usage: $0 <symbol_name> [--type=func|prop|signal|class|file]"
    exit 1
fi

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

SCAN_DIRS="addons scripts scenes test tests"
EXISTING_DIRS=""
for d in $SCAN_DIRS; do
    [ -d "$d" ] && EXISTING_DIRS="$EXISTING_DIRS $d"
done

if [ -z "$EXISTING_DIRS" ]; then
    echo -e "${RED}No scan directories found (addons/, scripts/, scenes/, etc.)${NC}"
    echo "Run this from your project root."
    exit 1
fi

echo -e "${GREEN}=== Cross-impact scan ===${NC}"
echo "Symbol: $SYMBOL"
echo "Type: $TYPE"
echo "Scan dirs:$EXISTING_DIRS"
echo

run_scan() {
    local label="$1"
    local pattern="$2"
    shift 2
    echo -e "${YELLOW}[$label]${NC}"
    # shellcheck disable=SC2086
    local results
    results=$(grep -rn -E "$pattern" $EXISTING_DIRS "$@" 2>/dev/null || true)
    if [ -z "$results" ]; then
        echo "  (no matches)"
    else
        echo "$results" | sed 's/^/  /'
    fi
    echo
}

case "$TYPE" in
    func)
        run_scan "Function calls" "\\.${SYMBOL}\\s*\\(" --include='*.gd'
        run_scan "Direct calls (self/static)" "(^|[^.])\\b${SYMBOL}\\s*\\(" --include='*.gd'
        run_scan "Function declaration" "^\\s*(static\\s+)?func\\s+${SYMBOL}\\b" --include='*.gd'
        run_scan "Callable references (signal connects)" "\\.connect\\(${SYMBOL}\\)|\\.connect\\(self\\.${SYMBOL}" --include='*.gd'
        ;;
    prop)
        run_scan "Property access" "\\.${SYMBOL}\\b" --include='*.gd'
        run_scan "@export declarations" "@export.*${SYMBOL}\\b" --include='*.gd'
        run_scan "Scene/resource references" "${SYMBOL}\\s*=" --include='*.tscn' --include='*.tres'
        ;;
    signal)
        run_scan "Signal connect (4.x style)" "\\b${SYMBOL}\\.connect\\b" --include='*.gd'
        run_scan "Signal connect (3.x string style — should not exist in 4.x)" "connect\\([\"']${SYMBOL}[\"']" --include='*.gd'
        run_scan "Signal emit (4.x)" "\\b${SYMBOL}\\.emit\\b" --include='*.gd'
        run_scan "Signal emit (legacy)" "emit_signal\\([\"']${SYMBOL}[\"']" --include='*.gd'
        run_scan "Signal declaration" "^\\s*signal\\s+${SYMBOL}\\b" --include='*.gd'
        run_scan "Signal await" "await\\s+.*\\.${SYMBOL}\\b|await\\s+${SYMBOL}\\b" --include='*.gd'
        ;;
    class)
        run_scan "Type hint" ":\\s*${SYMBOL}\\b" --include='*.gd'
        run_scan "new() calls" "\\b${SYMBOL}\\.new\\b" --include='*.gd'
        run_scan "extends declarations" "^\\s*extends\\s+${SYMBOL}\\b" --include='*.gd'
        run_scan "is checks" "\\bis\\s+${SYMBOL}\\b" --include='*.gd'
        run_scan "class_name declarations" "^\\s*class_name\\s+${SYMBOL}\\b" --include='*.gd'
        run_scan "Scene/resource type references" "type=\"${SYMBOL}\"|\\[ext_resource.*type=\"${SYMBOL}\"" --include='*.tscn' --include='*.tres'
        ;;
    file)
        run_scan "preload paths" "preload\\([\"']${SYMBOL}[\"']\\)" --include='*.gd'
        run_scan "load paths" "load\\([\"']${SYMBOL}[\"']\\)" --include='*.gd'
        run_scan "ResourceLoader paths" "ResourceLoader\\.load\\([\"']${SYMBOL}[\"']" --include='*.gd'
        run_scan "Scene ext_resource references" "${SYMBOL}" --include='*.tscn' --include='*.tres'
        run_scan "plugin.cfg references" "${SYMBOL}" --include='plugin.cfg'
        ;;
    *)
        echo -e "${RED}Unknown type: $TYPE${NC}"
        echo "Valid types: func, prop, signal, class, file"
        exit 1
        ;;
esac

echo -e "${GREEN}=== Scan complete ===${NC}"
echo
echo "Next step: review each match. For each, decide:"
echo "  - Caller updated to match the change?     → log as ADDRESSED"
echo "  - Caller doesn't need updating?           → log as NOT_AFFECTED with reason"
echo "  - Caller needs updating but not in scope? → create DEF-NNN deferral"
echo
echo "Append the analysis to the ticket's audit trail per impact-analysis-protocol.md"
