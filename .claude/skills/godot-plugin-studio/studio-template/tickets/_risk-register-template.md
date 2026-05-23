# Risk Register — TKT-<NNN>

Produced at Phase 1.B close per `references/risk-register-protocol.md`.
Reopened at Phase 1.G for reconciliation.

Owner: **Risk Officer** (or Tech Director if Risk Officer not activated)

Format rules:
- Probability: low (<20%) | medium (20-60%) | high (>60%)
- Impact: low | medium | high | critical
- Each risk has a single named owner role
- "Accept and monitor" is a valid mitigation but must be explicit — silent acceptance is forbidden
- Lessons from `relevant-lessons.md` must appear here as risks OR be explicitly dismissed

Without this file at Phase 1.B close, Gate L45 fails and Phase 1.C cannot begin.

Delete this header section after filling. Keep the risk entries.

---

## R1: <One-sentence risk title>

**Probability**: <low | medium | high>

**Impact**: <low | medium | high | critical>

**Category**: <api-stability | data-loss | performance | platform-compat | security | scope-creep | dependency | architectural | other>

**Source**: <how this risk was identified. Examples:
- "Knowledge Loop L-NNN cited it in TKT-MMM"
- "Discovery surfaced uncertain Godot behavior around X"
- "Mobile target makes this likely"
- "Designer concern raised in intake turn 2"
- "Devil's Advocate adversarial pass">

**Description**: <2-4 sentences. What specifically could go wrong, under what conditions, with what consequence.>

**Mitigation**: <What this ticket's plan will do to reduce probability or impact. If "accept and monitor," say so explicitly with reasoning for acceptance.>

**Owner**: <Specific role name. Not "QA" — name the role.>

**Trigger to escalate**: <What real-time signal would tell us this risk is materializing. Examples:
- "Test test_save_round_trip_v1.gd fails"
- "Pixel 6 frame profiler shows >16ms frame time"
- "Compile error mentioning 'invalid base type'"
- "(none — risk only visible at Phase 1.G)">

---

## R2: ...

(Add more as identified. Reasonable expectation: 0-4 risks for M/L tickets, 3-8 for XL.)

---

## Reconciliation (Phase 1.G)

*This section is empty at Phase 1.B close. Risk Officer fills it at Phase 1.G before lesson harvest.*

### R1

**Outcome**: <mitigated | materialized | ducked | accepted>

**Evidence**: <file/line, audit trail entry, gate result, test output>

**How handled** (if materialized): <2-3 sentences>

**Lesson candidate?**: <yes — see lessons.md L-N | no — reasoning>

**New risk surfaced?**: <no | yes — see R-N below>

---

### R2: ...

---

## New risks surfaced during execution

*Add any risks that came up during Phase 1.C/1.D/1.F that weren't predicted in the original session. Number them continuing from the highest R-N above.*

### R<NEW>: ...

(Same format as R1-RN above. Each new risk should also consider whether it belongs in the Deferred Work Tracker if not closed in this ticket.)
