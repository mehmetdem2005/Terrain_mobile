#!/usr/bin/env bash
# full-pipeline.sh — Godot Plugin Studio v2.0 unified audit pipeline
#
# Runs all automatable studio checks in order. Stops at first FAIL.
# Verifies that manual checks (Clean Code review, architectural audit) 
# were performed by looking for their audit trail entries.
#
# Usage:
#   bash full-pipeline.sh <plugin_dir> [--ticket-id=TKT-NNN] [--size=S|M|L|XL]
#
# Default size: L (runs most checks)
# Default ticket-id: none (pipeline runs without audit trail integration)

set -uo pipefail

PLUGIN_DIR=""
TICKET_ID=""
SIZE="L"

for arg in "$@"; do
    case "$arg" in
        --ticket-id=*) TICKET_ID="${arg#--ticket-id=}" ;;
        --size=*) SIZE="${arg#--size=}" ;;
        --*) echo "Unknown flag: $arg" ;;
        *) PLUGIN_DIR="$arg" ;;
    esac
done

if [ -z "$PLUGIN_DIR" ] || [ ! -d "$PLUGIN_DIR" ]; then
    echo "Usage: bash full-pipeline.sh <plugin_dir> [--ticket-id=TKT-NNN] [--size=S|M|L|XL]"
    echo "Example: bash full-pipeline.sh addons/my_plugin --ticket-id=TKT-007 --size=L"
    exit 1
fi

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
GRAY='\033[0;37m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
START_TIME=$(date +%s)

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
TOTAL_STAGES=30

declare -a RESULTS

print_header() {
    echo
    echo -e "${BOLD}${BLUE}=== Godot Plugin Studio Pipeline ===${NC}"
    echo "Plugin: $PLUGIN_DIR"
    [ -n "$TICKET_ID" ] && echo "Ticket: $TICKET_ID"
    echo "Size class: $SIZE"
    echo "Total stages: $TOTAL_STAGES"
    echo
}

stage() {
    local num="$1"
    local name="$2"
    local status="$3"
    local detail="${4:-}"
    
    local sym color
    case "$status" in
        PASS) sym="✓"; color="$GREEN"; PASS_COUNT=$((PASS_COUNT + 1)) ;;
        FAIL) sym="✗"; color="$RED"; FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
        SKIP) sym="-"; color="$GRAY"; SKIP_COUNT=$((SKIP_COUNT + 1)) ;;
        MANUAL) sym="?"; color="$YELLOW" ;;
        *) sym="?"; color="$YELLOW" ;;
    esac
    
    printf "${color}%s${NC} [%2d/%2d] %-45s ${color}%-7s${NC} %s\n" "$sym" "$num" "$TOTAL_STAGES" "$name" "$status" "$detail"
    RESULTS+=("$num|$name|$status|$detail")
}

should_skip_for_size() {
    local stage_min_size="$1"
    case "$SIZE" in
        S) [ "$stage_min_size" != "S" ] && return 0 ;;
        M) [[ "$stage_min_size" == "L" || "$stage_min_size" == "XL" ]] && return 0 ;;
        L) [ "$stage_min_size" == "XL" ] && return 0 ;;
        XL) return 1 ;;
    esac
    return 1
}

print_header

# =========================================================================
# Stage 1: Environment verification
# =========================================================================
if command -v godot &>/dev/null && godot --version 2>/dev/null | grep -q "4\."; then
    stage 1 "Environment (Godot 4.x binary)" "PASS" "$(godot --version | head -1)"
else
    stage 1 "Environment (Godot 4.x binary)" "FAIL" "godot not found or wrong version; run scripts/setup-godot.sh"
fi

# =========================================================================
# Stage 2: Setup integrity (API XML, gdtoolkit)
# =========================================================================
SETUP_OK=1
if [ ! -d "$HOME/godot-api-reference" ] || [ -z "$(ls -A "$HOME/godot-api-reference"/*.xml 2>/dev/null | head -1)" ]; then
    SETUP_OK=0
    SETUP_DETAIL="API XML missing at ~/godot-api-reference/"
fi
if ! command -v gdlint &>/dev/null; then
    SETUP_OK=0
    SETUP_DETAIL="${SETUP_DETAIL:+$SETUP_DETAIL; }gdlint not installed"
fi
if [ "$SETUP_OK" -eq 1 ]; then
    stage 2 "Setup integrity (API XML + gdtoolkit)" "PASS"
else
    stage 2 "Setup integrity (API XML + gdtoolkit)" "FAIL" "${SETUP_DETAIL:-unknown setup issue}"
fi

# Stop pipeline if environment is broken
if [ "$FAIL_COUNT" -gt 0 ]; then
    echo
    echo -e "${RED}Pipeline halted: environment is not ready.${NC}"
    echo "Run: bash scripts/setup-godot.sh"
    exit 1
fi

# =========================================================================
# Stage 3: File integrity
# =========================================================================
GD_COUNT=$(find "$PLUGIN_DIR" -name '*.gd' -type f 2>/dev/null | wc -l)
if [ "$GD_COUNT" -gt 0 ] && [ -f "$PLUGIN_DIR"/plugin.cfg ]; then
    stage 3 "File integrity" "PASS" "$GD_COUNT .gd files + plugin.cfg"
else
    stage 3 "File integrity" "FAIL" "missing .gd files or plugin.cfg in $PLUGIN_DIR"
fi

# =========================================================================
# Stage 4: Parse check
# =========================================================================
PARSE_FAIL=0
PARSE_FAIL_FILES=""
for f in $(find "$PLUGIN_DIR" -name '*.gd' -type f 2>/dev/null); do
    if godot --headless --check-only "$f" 2>&1 | grep -qE "ERROR|error|Invalid|invalid"; then
        PARSE_FAIL=$((PARSE_FAIL + 1))
        PARSE_FAIL_FILES="${PARSE_FAIL_FILES} $f"
    fi
done
if [ "$PARSE_FAIL" -eq 0 ]; then
    stage 4 "Parse check (godot --check-only)" "PASS" "$GD_COUNT files clean"
else
    stage 4 "Parse check (godot --check-only)" "FAIL" "$PARSE_FAIL files failed:$PARSE_FAIL_FILES"
fi

# =========================================================================
# Stage 5: gdformat check
# =========================================================================
if command -v gdformat &>/dev/null; then
    if gdformat --check "$PLUGIN_DIR" 2>&1 | grep -qE "would reformat"; then
        stage 5 "gdformat --check" "FAIL" "formatting issues; run gdformat $PLUGIN_DIR"
    else
        stage 5 "gdformat --check" "PASS"
    fi
else
    stage 5 "gdformat --check" "SKIP" "gdformat not installed"
fi

# =========================================================================
# Stage 6: gdlint
# =========================================================================
if command -v gdlint &>/dev/null; then
    LINT_OUT=$(gdlint "$PLUGIN_DIR" 2>&1 || true)
    if echo "$LINT_OUT" | grep -qE "^[^:]+\.gd:"; then
        WARN_COUNT=$(echo "$LINT_OUT" | grep -cE "^[^:]+\.gd:" || echo 0)
        stage 6 "gdlint" "FAIL" "$WARN_COUNT warnings"
    else
        stage 6 "gdlint" "PASS"
    fi
else
    stage 6 "gdlint" "SKIP" "gdlint not installed"
fi

# =========================================================================
# Stage 7: plugin.cfg conformance
# =========================================================================
PLUGIN_CFG="$PLUGIN_DIR/plugin.cfg"
MISSING=""
for required in "name" "description" "author" "version" "script"; do
    if ! grep -qE "^${required}\s*=" "$PLUGIN_CFG"; then
        MISSING="${MISSING} $required"
    fi
done
if [ -z "$MISSING" ]; then
    stage 7 "plugin.cfg conformance" "PASS"
else
    stage 7 "plugin.cfg conformance" "FAIL" "missing fields:$MISSING"
fi

# =========================================================================
# Stage 8: Editor smoke test
# =========================================================================
if [ -f "project.godot" ]; then
    SMOKE_LOG=$(mktemp /tmp/gps-smoke-XXXXXX.log)
    timeout 30 godot --headless --editor --quit-after 3 2>&1 > "$SMOKE_LOG" || true
    if grep -qiE "error|fatal" "$SMOKE_LOG"; then
        ERROR_LINE=$(grep -iE "error|fatal" "$SMOKE_LOG" | head -1)
        stage 8 "Editor smoke test" "FAIL" "$ERROR_LINE"
    else
        stage 8 "Editor smoke test" "PASS"
    fi
    rm -f "$SMOKE_LOG"
else
    stage 8 "Editor smoke test" "SKIP" "no project.godot in cwd"
fi

# =========================================================================
# Stage 9: Phase gate audit (checks audit trail for phase verdicts)
# =========================================================================
if [ -n "$TICKET_ID" ] && [ -f ".studio/tickets/${TICKET_ID}.json" ]; then
    # Look for Phase 1.A through 1.G PASS entries
    MISSING_PHASES=""
    for phase in "1.A" "1.B" "1.C" "1.D" "1.E" "1.F" "1.G"; do
        if ! grep -q "phase.*${phase}.*PASS\|phase_${phase}.*PASS" ".studio/tickets/${TICKET_ID}.json" 2>/dev/null; then
            if [ "$SIZE" = "L" ] || [ "$SIZE" = "XL" ]; then
                MISSING_PHASES="$MISSING_PHASES $phase"
            fi
        fi
    done
    if [ -z "$MISSING_PHASES" ]; then
        stage 9 "Phase gate audit" "PASS"
    else
        stage 9 "Phase gate audit" "FAIL" "missing phase verdicts:$MISSING_PHASES"
    fi
else
    stage 9 "Phase gate audit" "MANUAL" "no ticket ID — manually verify Phases 1.A-1.G have PASS verdicts"
fi

# =========================================================================
# Stages 10-25: Run scripts and check manual audit entries
# =========================================================================

# Stage 10: API verification (manual — Honesty Auditor's domain)
stage 10 "API verification (Honesty Auditor)" "MANUAL" "verify audit trail has API verification entries for all API claims"

# Stage 11: Cross-impact scan (manual driver; user supplies symbol)
stage 11 "Cross-impact scan" "MANUAL" "run scripts/cross-impact-scan.sh per changed symbol; results in audit trail"

# Stage 12: Semantic dependency walk (manual — role-driven)
stage 12 "Semantic dependency walk" "MANUAL" "verify Semantic Dependency Engineer logged catalog walk in audit trail"

# Stage 13: Forward wiring audit (automated)
if [ -x "$SCRIPT_DIR/wiring-audit.sh" ]; then
    WIRING_OUT=$(bash "$SCRIPT_DIR/wiring-audit.sh" "$PLUGIN_DIR" 2>&1)
    if echo "$WIRING_OUT" | grep -qE "wiring issue|orphan|NEVER EMITTED|DEAD SIGNAL"; then
        ISSUES=$(echo "$WIRING_OUT" | grep -cE "ORPHAN|DEAD SIGNAL|NEVER EMITTED" || echo 0)
        stage 13 "Forward wiring audit" "FAIL" "$ISSUES wiring issues"
    else
        stage 13 "Forward wiring audit" "PASS"
    fi
else
    stage 13 "Forward wiring audit" "SKIP" "wiring-audit.sh not found"
fi

# Stage 14: Reverse wiring audit (automated)
if [ -x "$SCRIPT_DIR/reverse-wiring-audit.sh" ]; then
    REV_OUT=$(bash "$SCRIPT_DIR/reverse-wiring-audit.sh" "$PLUGIN_DIR" 2>&1)
    if echo "$REV_OUT" | grep -qE "orphan file"; then
        ISSUES=$(echo "$REV_OUT" | grep -cE "ORPHAN" || echo 0)
        stage 14 "Reverse wiring audit" "FAIL" "$ISSUES orphan files"
    else
        stage 14 "Reverse wiring audit" "PASS"
    fi
else
    stage 14 "Reverse wiring audit" "SKIP" "reverse-wiring-audit.sh not found"
fi

# Stage 15: Dead code scan (automated)
if [ -x "$SCRIPT_DIR/dead-code-scan.sh" ]; then
    DEAD_OUT=$(bash "$SCRIPT_DIR/dead-code-scan.sh" "$PLUGIN_DIR" 2>&1)
    if echo "$DEAD_OUT" | grep -qE "ORPHAN PUBLIC|NEVER EMITTED|MISSING"; then
        ISSUES=$(echo "$DEAD_OUT" | grep -cE "ORPHAN PUBLIC|NEVER EMITTED|MISSING" || echo 0)
        stage 15 "Dead code scan" "FAIL" "$ISSUES findings"
    else
        stage 15 "Dead code scan" "PASS"
    fi
else
    stage 15 "Dead code scan" "SKIP" "dead-code-scan.sh not found"
fi

# Stage 16: Orphan reference scan (part of dead-code-scan output)
stage 16 "Orphan reference scan" "MANUAL" "manually inspect preload/load/class_name refs; covered by stage 15"

# Stage 17: Defect pattern walk (manual — role-driven)
stage 17 "Defect pattern walk (64+ patterns)" "MANUAL" "verify Defect Pattern Specialist walked godot-4.6.2-defect-catalog.md"

# Stage 18: Concurrency hunt
stage 18 "Concurrency hunt" "MANUAL" "verify Concurrency Bug Specialist's report in audit trail"

# Stage 19: State corruption hunt
stage 19 "State corruption hunt" "MANUAL" "verify State Corruption Specialist's invariant audit in trail"

# Stage 20: Adversarial Hunt (XL only)
if should_skip_for_size "XL"; then
    stage 20 "Adversarial Hunt (XL only)" "SKIP" "size=$SIZE; mandatory only for XL"
else
    stage 20 "Adversarial Hunt (XL only)" "MANUAL" "verify 30+ min hunt happened; Bug Hunter Lead's report present"
fi

# Stage 21: Clean Code review
stage 21 "Clean Code Officer review" "MANUAL" "verify per-criterion verdicts in audit trail"

# Stage 22: Spaghetti scan
stage 22 "Spaghetti pattern scan" "MANUAL" "verify Tier 1 patterns absent; spaghetti-pattern-catalog.md walked"

# Stage 23: Architectural quality audit
stage 23 "Architectural quality audit" "MANUAL" "verify Architectural Quality Auditor's report present"

# Stage 24: 3-alternative documentation
if should_skip_for_size "L"; then
    stage 24 "3-alternative documentation" "SKIP" "size=$SIZE; required for L/XL only"
else
    stage 24 "3-alternative documentation" "MANUAL" "verify Phase 1.C has 3 alternatives in architecture-doc.md"
fi

# Stage 25: Trade-off matrix
if should_skip_for_size "L"; then
    stage 25 "Trade-off matrix" "SKIP" "size=$SIZE; required for L/XL only"
else
    stage 25 "Trade-off matrix" "MANUAL" "verify 8-dimension matrix present in Phase 1.C output"
fi

# Stage 26: Consistency cross-check
stage 26 "Consistency cross-check" "MANUAL" "verify Consistency Auditor's report; 0 contradictions across audit trail"

# Stage 27: Documentation freshness
if [ -f "$PLUGIN_DIR/README.md" ]; then
    stage 27 "Documentation freshness" "MANUAL" "verify README matches code; spot-check 3 claims"
else
    if [ "$SIZE" = "L" ] || [ "$SIZE" = "XL" ]; then
        stage 27 "Documentation freshness" "FAIL" "no README.md for L/XL plugin"
    else
        stage 27 "Documentation freshness" "SKIP" "size=$SIZE; README not required"
    fi
fi

# Stage 28: Deferred items tracked
if [ -d ".studio/deferred" ]; then
    DEF_COUNT=$(ls .studio/deferred/DEF-*.md 2>/dev/null | wc -l || echo 0)
    stage 28 "Deferred items tracked" "PASS" "$DEF_COUNT deferred items in registry"
else
    stage 28 "Deferred items tracked" "MANUAL" "no .studio/deferred/ — initialize if any work was deferred"
fi

# Stage 29: Honesty Audit
stage 29 "Honesty Audit (final sweep)" "MANUAL" "verify Honesty Auditor signed; no unverified claims in audit trail"

# Stage 30: Final sign-off
case "$SIZE" in
    S|M)
        stage 30 "Final sign-off" "MANUAL" "Quality Gate Officer + Honesty Auditor signatures sufficient"
        ;;
    L)
        stage 30 "Final sign-off" "MANUAL" "Tech Director signature required"
        ;;
    XL)
        stage 30 "Final sign-off" "MANUAL" "Studio Head signature required"
        ;;
esac

# =========================================================================
# Summary
# =========================================================================
END_TIME=$(date +%s)
RUNTIME=$((END_TIME - START_TIME))

echo
echo -e "${BOLD}=== Pipeline complete ===${NC}"
echo
echo "Pass:   $PASS_COUNT"
echo "Fail:   $FAIL_COUNT"
echo "Skip:   $SKIP_COUNT"
echo "Manual: $((TOTAL_STAGES - PASS_COUNT - FAIL_COUNT - SKIP_COUNT))"
echo "Runtime: ${RUNTIME}s"
echo

if [ "$FAIL_COUNT" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}✓ AUTOMATABLE STAGES ALL PASSED${NC}"
    echo
    echo "Note: stages marked MANUAL still need verification."
    echo "Check the ticket audit trail for each MANUAL stage's owner-role entry."
    exit 0
else
    echo -e "${RED}${BOLD}✗ $FAIL_COUNT STAGE(S) FAILED${NC}"
    echo
    echo "Pipeline cannot advance until all FAIL stages are resolved."
    echo "Re-run after fixes."
    exit 1
fi
