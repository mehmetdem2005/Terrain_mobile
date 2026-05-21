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
