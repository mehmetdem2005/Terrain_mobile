# Rollback Decision — TKT-<NNN>

Produced when a rollback request is filed per `references/rollback-strategy-protocol.md` Part 3.

Owner: **Rollback Officer** (facilitates; does not decide)

Convening attendees:
- Role who filed the request
- Tech Director
- Honesty Auditor
- Devil's Advocate (always)
- Architecture Veto Officer (if Category A trigger)
- Risk Officer (if Category B trigger)
- Defect Pattern Specialist (if Category C trigger)

Without this file when a rollback request was filed, Gate L56 fails and the ticket cannot close.

Delete this header section after filling.

---

## Trigger reviewed

**Original request**: <link to rollback request in audit trail>
**Filed by**: <role>
**Trigger fired**: <ID, e.g., A2, B1, C2, D1>
**Filed at**: <phase, e.g., during Phase 1.F sub-task 4>

---

## Dimension 1 — Validity assessment

**Devil's Advocate stress-test of the trigger**:
<2-4 sentences. Was the observation accurate? Is the signal real, or could it be normal in-progress noise?>

**Validity verdict**: <VALID | INVALID>

If INVALID: close request here with reasoning. Skip remaining dimensions.

---

## Dimension 2 — Scope assessment

**Is the problem localized (one sub-task) or systemic (the direction itself)?**

<2-3 sentences. What's the actual blast radius?>

**Scope verdict**: <LOCALIZED | SYSTEMIC>

If LOCALIZED: this is a normal defect, not a rollback signal. Treat as Phase 1.G item. Skip remaining dimensions.

---

## Dimension 3 — Cost of continuing forward

- **Estimated remaining work to fix in place**: <hours/sessions>
- **Estimated probability of success**: <%>
- **Risks if continuing**: <list — what compounds if we push through>
- **Quality of forward path's outcome**: <high | acceptable | compromised>

---

## Dimension 4 — Cost of rolling back

- **Proposed target checkpoint**: <path, e.g., `.studio/checkpoints/TKT-NNN-phase-1.D/`>
- **Work discarded by rollback**: <list>
- **Work preserved (carries forward)**: <list>
- **Estimated rework on new path**: <hours/sessions>
- **New estimated probability of success**: <%>
- **Quality of rollback path's outcome**: <high | acceptable | compromised>

---

## Dimension 5 — Decision

**Verdict**: <CONTINUE | PARTIAL ROLLBACK | FULL PHASE ROLLBACK | TICKET RESTART>

**Reasoning** (forward-looking only — no sunk-cost arguments):
<2-4 sentences. WHY this decision, based purely on cost-forward vs cost-back analysis.>

**If rolling back**:
- Target checkpoint: <path>
- What carries forward: <list>
- What is redone: <list>
- New starting phase: <Phase 1.X>

---

## Sign-offs

| Role | Position | Notes |
|------|----------|-------|
| Tech Director | <concur | dissent> | |
| Honesty Auditor | <concur | dissent | veto-pending> | |
| Devil's Advocate | <concur | dissent> | |
| Architecture Veto Officer (if attending) | <concur | dissent> | |
| Risk Officer (if attending) | <concur | dissent> | |
| Defect Pattern Specialist (if attending) | <concur | dissent> | |

---

## Dissent log (if any)

<Document any role's dissent in their own words. Dissent does not block the decision but is preserved permanently.>

---

## Honesty Audit review

*Honesty Auditor fills this after the decision is recorded. Reviews for sunk-cost reasoning.*

**Sunk-cost reasoning detected?**: <yes | no>

If yes:
- Quote(s) from the decision that triggered the flag: <list>
- Veto issued: <yes — the decision is rejected; session re-evaluates forward-looking>
- Re-evaluation outcome: <link to updated decision document>

If no: decision stands. Execution resumes per the decision.
