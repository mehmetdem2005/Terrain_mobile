#!/usr/bin/env bash
# Godot Plugin Studio — CI checks
# Bundles M and L tier checks into a single command.
# Run from a project root; specify the plugin directory.
#
# Usage:
#   bash ci-checks.sh addons/my_plugin
#   bash ci-checks.sh addons/my_plugin --skip-editor-smoke

set -uo pipefail

PLUGIN_DIR="${1:-}"
shift || true

if [ -z "$PLUGIN_DIR" ] || [ ! -d "$PLUGIN_DIR" ]; then
    echo "Usage: bash ci-checks.sh <plugin_directory>"
    echo "Example: bash ci-checks.sh addons/my_plugin"
    exit 1
fi

SKIP_EDITOR_SMOKE=0
for arg in "$@"; do
    case "$arg" in
        --skip-editor-smoke) SKIP_EDITOR_SMOKE=1 ;;
    esac
done

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

FAILED=0

echo -e "${GREEN}=== Godot Plugin Studio CI checks ===${NC}"
echo "Plugin: $PLUGIN_DIR"
echo

# Check 1: All .gd files parse cleanly
echo -e "${YELLOW}[1/5] Parse check (godot --script <f> --check-only)${NC}"
GD_FILES=$(find "$PLUGIN_DIR" -name '*.gd' -type f)
GD_COUNT=$(echo "$GD_FILES" | wc -l)
if [ -z "$GD_FILES" ]; then
    echo "  No .gd files found in $PLUGIN_DIR"
else
    PARSE_FAIL=0
    for f in $GD_FILES; do
        PARSE_OUT=$(godot --headless --script "$f" --check-only 2>&1)
        if echo "$PARSE_OUT" | grep -qE "Parse Error|SCRIPT ERROR|Failed to load"; then
            echo -e "  ${RED}✗${NC} $f"
            echo "$PARSE_OUT" | grep -E "Parse Error|SCRIPT ERROR|Failed to load" | head -3
            PARSE_FAIL=$((PARSE_FAIL + 1))
        fi
    done
    if [ "$PARSE_FAIL" -eq 0 ]; then
        echo -e "  ${GREEN}✓${NC} All $GD_COUNT files parse cleanly"
    else
        echo -e "  ${RED}✗ $PARSE_FAIL files failed parse check${NC}"
        FAILED=$((FAILED + 1))
    fi
fi

# Check 2: gdlint
echo -e "${YELLOW}[2/5] Static analysis (gdlint)${NC}"
if command -v gdlint &> /dev/null; then
    if gdlint "$PLUGIN_DIR" 2>&1 | tee /tmp/gdlint-out.txt | grep -qE "^[^:]+\.gd:"; then
        echo -e "  ${RED}✗ gdlint found issues:${NC}"
        cat /tmp/gdlint-out.txt | head -20
        FAILED=$((FAILED + 1))
    else
        echo -e "  ${GREEN}✓${NC} gdlint clean"
    fi
else
    echo -e "  ${YELLOW}⚠${NC} gdlint not installed; skipping"
fi

# Check 3: gdformat
echo -e "${YELLOW}[3/5] Formatting (gdformat --check)${NC}"
if command -v gdformat &> /dev/null; then
    if gdformat --check "$PLUGIN_DIR" 2>&1 | tee /tmp/gdformat-out.txt | grep -qE "would reformat"; then
        echo -e "  ${RED}✗ gdformat would reformat files:${NC}"
        grep "would reformat" /tmp/gdformat-out.txt
        echo -e "  Run: ${YELLOW}gdformat $PLUGIN_DIR${NC} to fix"
        FAILED=$((FAILED + 1))
    else
        echo -e "  ${GREEN}✓${NC} Formatting clean"
    fi
else
    echo -e "  ${YELLOW}⚠${NC} gdformat not installed; skipping"
fi

# Check 4: plugin.cfg validity
echo -e "${YELLOW}[4/5] plugin.cfg conformance${NC}"
PLUGIN_CFG="$PLUGIN_DIR/plugin.cfg"
if [ ! -f "$PLUGIN_CFG" ]; then
    echo -e "  ${RED}✗${NC} No plugin.cfg found at $PLUGIN_CFG"
    FAILED=$((FAILED + 1))
else
    CFG_OK=1
    for required in "name" "description" "author" "version" "script"; do
        if ! grep -qE "^${required}\s*=" "$PLUGIN_CFG"; then
            echo -e "  ${RED}✗${NC} plugin.cfg missing required field: $required"
            CFG_OK=0
            FAILED=$((FAILED + 1))
        fi
    done
    if [ "$CFG_OK" -eq 1 ]; then
        echo -e "  ${GREEN}✓${NC} plugin.cfg conformant"
    fi
fi

# Check 5: Editor smoke test
if [ "$SKIP_EDITOR_SMOKE" -eq 1 ]; then
    echo -e "${YELLOW}[5/5] Editor smoke test (SKIPPED via --skip-editor-smoke)${NC}"
else
    echo -e "${YELLOW}[5/5] Editor smoke test (godot --editor --quit-after)${NC}"
    if [ -f "project.godot" ]; then
        SMOKE_LOG=$(mktemp /tmp/gps-editor-smoke-XXXXXX.log)
        timeout 30 godot --headless --editor --quit-after 3 2>&1 > "$SMOKE_LOG" || true
        if grep -qiE "error|fatal" "$SMOKE_LOG"; then
            echo -e "  ${RED}✗ Editor produced errors:${NC}"
            grep -iE "error|fatal" "$SMOKE_LOG" | head -5
            FAILED=$((FAILED + 1))
        else
            echo -e "  ${GREEN}✓${NC} Editor smoke test passed (no errors in 3-frame run)"
        fi
        rm -f "$SMOKE_LOG"
    else
        echo -e "  ${YELLOW}⚠${NC} No project.godot in current directory; cannot run editor smoke"
    fi
fi

# Summary
echo
if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}=== ALL CHECKS PASSED ===${NC}"
    exit 0
else
    echo -e "${RED}=== $FAILED CHECK(S) FAILED ===${NC}"
    exit 1
fi
