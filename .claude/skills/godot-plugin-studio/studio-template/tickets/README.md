# Tickets

One JSON file per ticket: `TKT-NNN.json`. See `references/coordination-protocol.md` for the full schema and state machine.

## Numbering

Sequential starting from TKT-001. Sub-tickets use letter suffix: TKT-007-A.
Incident tickets prefixed: TKT-INC-001.
Postmortem tickets prefixed: TKT-PM-001.

## Lifecycle

```
OPEN → TRIAGED → IN_PROGRESS ↔ BLOCKED → QUALITY_GATE → HONESTY_AUDIT → SIGN_OFF → CLOSED
```

## v2.2 audit-trail artifacts (Intelligence Layer)

Every L/XL ticket produces these files in its audit trail:

| File | Created at | Owner | Gate |
|------|-----------|-------|------|
| `relevant-lessons.md` | Phase 1.B start | Tech Director | L43 |
| `risk-register.md` | Phase 1.B close | Risk Officer | L45 |
| `ticket-fingerprint.md` | Phase 1.C close | Defect Pattern Specialist | L50 |
| `predictive-checklist.md` | Phase 1.C → 1.D | Defect Pattern Specialist + Tech Director | L51 |
| `lessons.md` | Phase 1.G close | Studio Knowledge Curator | L41 |
| `predictive-vs-actual.md` | Phase 1.G | Bug Hunter Lead + Defect Pattern Specialist | L53 |
| `repeat-mistake-postmortem.md` | Only if repeat triggered | Postmortem Lead | L44 |
| `rollback-decision.md` | Only if rollback request filed | Rollback Officer | L56 |

Templates in this directory: `_lessons-template.md`, `_relevant-lessons-template.md`, `_risk-register-template.md`, `_ticket-fingerprint-template.md`, `_predictive-checklist-template.md`, `_rollback-decision-template.md`. Copy and rename per ticket.

The risk register is reopened at Phase 1.G for reconciliation (Gate L48). The predictive checklist is verified at Phase 1.G via predictive-vs-actual (Gate L53).

## Checkpoints (v2.2)

Every phase boundary auto-creates a checkpoint under `.studio/checkpoints/TKT-NNN-phase-1.X/`. Owner: Audit Trail Officer. These enable rollback per `references/rollback-strategy-protocol.md`. Checkpointing is mandatory — Gate L54 requires checkpoints exist for every completed phase boundary.

Tickets are not deleted on close. The full audit trail is preserved for postmortems and future learning.

## Schema

See the canonical schema in `references/coordination-protocol.md`. Briefly:
- `id`, `title`, `kind`, `size`, `priority`
- `opened_at`, `opened_by`, `user_original_request`
- `scope` (in_scope, out_of_scope)
- `acceptance_criteria`
- `target_godot`, `target_platform`, `mobile_targeted`
- `state`, `active_roles`, `blockers`
- `audit_trail` (append-only)
- `quality_gate_status`, `honesty_audit_status`
- `final_artifact_paths`, `closed_at`, `performance_scores`
