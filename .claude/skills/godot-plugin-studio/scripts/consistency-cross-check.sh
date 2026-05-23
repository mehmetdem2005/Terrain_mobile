#!/usr/bin/env bash
# consistency-cross-check.sh — scans ticket audit trail for contradictions
# Used by Consistency Auditor in Phase 1.G of the pipeline.
#
# Looks for:
#   - Same API claim with conflicting verdicts (one PASS, one FAIL)
#   - Phase 1.C architecture decisions contradicted by Phase 1.F code
#   - README claims vs actual code behavior (limited automated check)
#   - Cross-ADR violations (current ticket violates a recorded ADR)
#
# Usage:
#   bash consistency-cross-check.sh --ticket=TKT-NNN
#   bash consistency-cross-check.sh --ticket=TKT-NNN --plugin=addons/my_plugin

set -uo pipefail

TICKET_ID=""
PLUGIN_DIR=""

for arg in "$@"; do
    case "$arg" in
        --ticket=*) TICKET_ID="${arg#--ticket=}" ;;
        --plugin=*) PLUGIN_DIR="${arg#--plugin=}" ;;
    esac
done

if [ -z "$TICKET_ID" ]; then
    echo "Usage: bash consistency-cross-check.sh --ticket=TKT-NNN [--plugin=addons/my_plugin]"
    exit 1
fi

TICKET_FILE=".studio/tickets/${TICKET_ID}.json"
if [ ! -f "$TICKET_FILE" ]; then
    echo "Ticket file not found: $TICKET_FILE"
    echo "(this script requires .studio/ to be initialized; if you don't have one,"
    echo " contradictions are checked manually by the Consistency Auditor role)"
    exit 1
fi

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Consistency cross-check ===${NC}"
echo "Ticket: $TICKET_ID"
[ -n "$PLUGIN_DIR" ] && echo "Plugin: $PLUGIN_DIR"
echo

CONTRADICTIONS=0

# =========================================================================
# Check 1: Same subject, conflicting verdicts within ticket
# =========================================================================
echo -e "${YELLOW}[1/5] Same-subject verdict conflicts${NC}"
# Extract pairs of (subject, result) from audit trail
# Look for any subject that has both PASS and FAIL entries
SUBJECTS=$(jq -r '.audit_trail[] | "\(.subject)|\(.result)"' "$TICKET_FILE" 2>/dev/null | sort -u || true)
if [ -z "$SUBJECTS" ]; then
    echo "  (no audit trail entries to compare)"
else
    SEEN_PASS=""
    SEEN_FAIL=""
    while IFS='|' read -r subj result; do
        if [ "$result" = "PASS" ] && [[ "$SEEN_FAIL" == *"$subj"* ]]; then
            echo -e "  ${RED}CONFLICT${NC} subject '$subj' has both PASS and FAIL verdicts"
            CONTRADICTIONS=$((CONTRADICTIONS + 1))
        elif [ "$result" = "FAIL" ] && [[ "$SEEN_PASS" == *"$subj"* ]]; then
            echo -e "  ${RED}CONFLICT${NC} subject '$subj' has both PASS and FAIL verdicts"
            CONTRADICTIONS=$((CONTRADICTIONS + 1))
        fi
        [ "$result" = "PASS" ] && SEEN_PASS="$SEEN_PASS|$subj"
        [ "$result" = "FAIL" ] && SEEN_FAIL="$SEEN_FAIL|$subj"
    done <<< "$SUBJECTS"
    
    if [ "$CONTRADICTIONS" -eq 0 ]; then
        echo "  (no same-subject conflicts found)"
    fi
fi
echo

# =========================================================================
# Check 2: Phase 1.C vs Phase 1.F drift
# =========================================================================
echo -e "${YELLOW}[2/5] Architecture drift (Phase 1.C → Phase 1.F)${NC}"
# Check if Phase 1.C decisions are still in effect at Phase 1.F
PHASE_C_ENTRIES=$(jq -r '.audit_trail[] | select(.phase == "1.C") | .action' "$TICKET_FILE" 2>/dev/null || true)
PHASE_F_ENTRIES=$(jq -r '.audit_trail[] | select(.phase == "1.F") | .action' "$TICKET_FILE" 2>/dev/null || true)

if [ -z "$PHASE_C_ENTRIES" ] || [ -z "$PHASE_F_ENTRIES" ]; then
    echo "  (insufficient phase data to compare; ensure phases are tagged in audit trail)"
else
    # Look for "architecture amended" without matching design doc update
    AMENDED=$(jq -r '.audit_trail[] | select(.action == "architecture_amended") | .timestamp' "$TICKET_FILE" 2>/dev/null || true)
    if [ -n "$AMENDED" ]; then
        echo -e "  ${YELLOW}NOTE${NC} architecture was amended during execution; verify amendment is logged in architecture-doc.md"
    else
        echo "  (no architecture amendments logged; assumes design intent preserved)"
    fi
fi
echo

# =========================================================================
# Check 3: README vs code (basic check — public API surface match)
# =========================================================================
echo -e "${YELLOW}[3/5] README claims vs code reality${NC}"
if [ -n "$PLUGIN_DIR" ] && [ -f "$PLUGIN_DIR/README.md" ]; then
    # Extract code-like tokens from README (functions, classes mentioned)
    # Then verify those exist in the code
    README_TOKENS=$(grep -oE '\b[A-Z][a-zA-Z0-9]+\b|\b[a-z_][a-zA-Z0-9_]*\s*\(' "$PLUGIN_DIR/README.md" 2>/dev/null | sed 's/\s*($//' | sort -u | head -30 || true)
    
    MISSING_TOKENS=""
    for token in $README_TOKENS; do
        # Skip very common words
        case "$token" in
            The|A|An|This|That|It|If|When|For|And|Or|But|Note|Example|Usage|Install|Installation)
                continue ;;
        esac
        # Check if token exists in the codebase
        if ! grep -rq "\b$token\b" "$PLUGIN_DIR" --include='*.gd' 2>/dev/null; then
            # Not in code; might be a documentation-only term, but flag for review
            MISSING_TOKENS="${MISSING_TOKENS} $token"
        fi
    done
    
    if [ -z "$MISSING_TOKENS" ] || [ "$(echo $MISSING_TOKENS | wc -w)" -le 3 ]; then
        echo "  (README terms broadly match code; spot-check remaining manually)"
    else
        TOKEN_COUNT=$(echo "$MISSING_TOKENS" | wc -w)
        echo -e "  ${YELLOW}WARN${NC} ${TOKEN_COUNT} README terms not found in code:$MISSING_TOKENS"
        echo "  (may be legitimate docs-only terms, but Consistency Auditor should review)"
    fi
else
    echo "  (no README.md found at $PLUGIN_DIR; skipping)"
fi
echo

# =========================================================================
# Check 4: ADR violations
# =========================================================================
echo -e "${YELLOW}[4/5] ADR violations${NC}"
if [ -d ".studio/knowledge-base/architectural-decision-records" ]; then
    ADR_COUNT=$(ls .studio/knowledge-base/architectural-decision-records/ADR-*.md 2>/dev/null | wc -l || echo 0)
    if [ "$ADR_COUNT" -gt 0 ]; then
        echo "  $ADR_COUNT ADRs found"
        echo "  (manual review required: Consistency Auditor must compare current ticket's"
        echo "   decisions against ACCEPTED ADRs to ensure no silent violations)"
    else
        echo "  (no ADRs to check)"
    fi
else
    echo "  (no ADR directory; skipping)"
fi
echo

# =========================================================================
# Check 5: Override + postmortem coherence
# =========================================================================
echo -e "${YELLOW}[5/5] Override sanity${NC}"
OVERRIDE_COUNT=$(jq -r '.audit_trail[] | select(.action == "override") | .timestamp' "$TICKET_FILE" 2>/dev/null | wc -l || echo 0)
if [ "$OVERRIDE_COUNT" -gt 0 ]; then
    echo -e "  ${YELLOW}NOTE${NC} ${OVERRIDE_COUNT} override(s) in this ticket"
    echo "  Verify each has:"
    echo "    - explicit rationale in audit trail"
    echo "    - entry in .studio/knowledge-base/overrides.md"
    echo "    - auto-postmortem ticket created"
    # Check if overrides.md has entries
    if [ -f ".studio/knowledge-base/overrides.md" ]; then
        OVR_ENTRIES=$(grep -c "^## OVR-" .studio/knowledge-base/overrides.md 2>/dev/null || echo 0)
        echo "  overrides.md entries: $OVR_ENTRIES"
    fi
else
    echo "  (no overrides this ticket)"
fi
echo

# =========================================================================
# Summary
# =========================================================================
echo -e "${GREEN}=== Cross-check complete ===${NC}"
if [ "$CONTRADICTIONS" -eq 0 ]; then
    echo -e "${GREEN}✓ No automated contradictions detected.${NC}"
    echo
    echo "Manual review still needed for:"
    echo "  - README vs code semantic agreement (not just symbol presence)"
    echo "  - ADR adherence (current decisions vs prior ACCEPTED ADRs)"
    echo "  - Override justifications"
    exit 0
else
    echo -e "${RED}✗ $CONTRADICTIONS contradiction(s) detected.${NC}"
    echo "Each must be addressed: identify which entry is the truth, correct the other."
    exit 1
fi
