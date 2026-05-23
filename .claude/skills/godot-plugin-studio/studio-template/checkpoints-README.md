# Checkpoints

Per `references/rollback-strategy-protocol.md` Part 1.

Owner: **Audit Trail Officer**

Every phase boundary in every L/XL ticket auto-creates a checkpoint directory here. Structure:

```
.studio/checkpoints/
├── TKT-NNN-phase-1.A/
│   ├── ticket-state.json
│   ├── audit-trail-snapshot.md
│   ├── artifacts/
│   │   └── intent-doc.md
│   └── checkpoint-summary.md
├── TKT-NNN-phase-1.B/
│   ├── ticket-state.json
│   ├── audit-trail-snapshot.md
│   ├── artifacts/
│   │   ├── feasibility-doc.md
│   │   ├── relevant-lessons.md
│   │   └── risk-register.md
│   └── checkpoint-summary.md
├── TKT-NNN-phase-1.C/
├── TKT-NNN-phase-1.D/
├── TKT-NNN-phase-1.E/
├── TKT-NNN-phase-1.F/
└── TKT-NNN-phase-1.G/
```

## Why checkpoints exist

Without checkpoints, "rolling back to Phase 1.C" is impossible — the artifacts and reasoning at that point are gone, overwritten by subsequent work. Checkpoints preserve the state at each transition so a rollback decision can actually land somewhere.

## What's in a checkpoint

- **`ticket-state.json`**: snapshot of the ticket JSON (state, active roles, blockers, etc.) at this phase boundary
- **`audit-trail-snapshot.md`**: the audit trail entries up to this point, frozen
- **`artifacts/`**: the documents/code that existed at this phase boundary
- **`code-state-manifest.md`** (when code exists): list of files with line counts and content hashes
- **`checkpoint-summary.md`**: 1-paragraph "where we are, what's decided, what's still open"

## Cost-aware mode behavior

- **Lite/Standard**: Minimal checkpoints (ticket-state.json + checkpoint-summary.md only)
- **Full (XL)**: Complete checkpoints with all artifacts

## Lifecycle

- Checkpoints are created automatically at every phase boundary
- They are not deleted when a ticket closes
- They persist for the lifetime of the ticket audit trail (forever, unless the user explicitly cleans up)
- They are used in two situations: rollback execution, and postmortem reconstruction

## Gate

L54: At Phase 1.G close, every completed phase boundary in this ticket has a populated checkpoint directory. Missing checkpoints fail the gate — checkpointing is mandatory.
