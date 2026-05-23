# Deferred Work Tracker

The studio does not forget. When work is deferred to a future ticket, that deferral is tracked, due-dated, and resurfaced. The Deferred Work Tracker exists because "we'll do it later" without a record is the most common source of technical debt in any project.

This tracker is a **persistent system in `.studio/deferred/`** — not a transient ticket field. Every deferred item has its own file, lifecycle, and accountability.

---

## Core principle

**Nothing is deferred without three things:**
1. A unique identifier (DEF-NNN)
2. A specific resurfacing condition (when does this come back?)
3. An owner (which role is responsible for resurfacing it?)

If any of these is missing, the item is not deferred — it is being silently dropped. The Audit Trail Officer treats silent drops as critical defects.

---

## The deferral lifecycle

```
       ┌─────────┐
       │ CREATED │  (role identifies item must be deferred)
       └────┬────┘
            │
            ▼
       ┌─────────┐
       │ ACTIVE  │  (tracked, awaiting resurfacing condition)
       └────┬────┘
            │
   resurfacing condition met
            │
            ▼
   ┌──────────────────┐
   │  RESURFACED      │  (review ticket auto-opened)
   └────────┬─────────┘
            │
            ▼
   ┌──────────────────┐
   │  ADDRESSED       │  (work is done, OR explicitly re-deferred with new conditions, OR closed as no-longer-relevant)
   └──────────────────┘
```

A deferred item NEVER quietly disappears. The three valid closing states are ADDRESSED (work done), RE-DEFERRED (with new explicit conditions), or CLOSED (explicitly acknowledged as no longer relevant, with rationale).

---

## What can be deferred

| Type | Example | Typical resurface condition |
|------|---------|-----------------------------|
| Feature | "Tutorial walkthrough for VECTOR_FIELD" | Before next minor release |
| Optimization | "Cache the script scan result" | When user reports slowness, OR after 5 closed tickets |
| Test coverage | "Edge case: VECTOR_FIELD on Resource (not Node)" | Before next release |
| Documentation | "API reference for advanced hook" | At Q4 documentation pass |
| Refactor | "Split god object VectorFieldInspector" | When module touches 3+ tickets in a row |
| Risk mitigation | "Forward compat for Godot 4.7" | When Godot 4.7-rc1 releases |
| Cross-platform | "Test on macOS" | Before public release |
| Mobile adaptation | "Touch-optimize the dock" | If user asks for mobile, OR before Android editor release |

## What CANNOT be deferred

Some items can never be deferred — they must be addressed in the current ticket or block sign-off:

- Honesty Auditor blockers (unverified API claims)
- Architecture Veto Officer findings on Phase 1.E
- Security issues (any severity)
- Crash safety issues
- Memory leaks
- Lifecycle symmetry violations (unmatched add/remove, connect/disconnect)
- Data loss risks

The Semantic Dependency Engineer enforces this distinction. If a role tries to defer something on the "cannot defer" list, the Semantic Dependency Engineer escalates immediately to Tech Director.

---

## Deferral file format

Each deferred item gets a file at `.studio/deferred/DEF-NNN.md`:

```markdown
# DEF-014 — Tutorial section for VECTOR_FIELD usage

## Origin
- Ticket: TKT-007
- Created by: Tutorial Writer
- Created at: 2026-05-21T19:14:00Z

## Item
Add a step-by-step cookbook walkthrough showing how to use @export_custom(PROPERTY_HINT_VECTOR_FIELD) in a real scene, including:
- Setting up the node
- Configuring the hint string
- Connecting to velocity_changed signal
- Example use case (e.g., wind direction in a particle system)

## Type
documentation

## Why deferred
TKT-007 scope is the plugin itself. Tutorial walkthrough is a documentation pass; scope-bumping would slow down the core implementation.

## Resurface condition
Before next minor version release (when CHANGELOG is being prepared)

## Owner role
Tutorial Writer

## State
ACTIVE

## Related items
- (none)

## Resurface log
[populated when resurfacing condition is met]

## Closure
[populated when item is ADDRESSED, RE-DEFERRED, or CLOSED]
```

---

## Resurfacing conditions

A deferred item can specify any of these condition types. The system checks them at appropriate times.

### Time-based
- "Before next minor release"
- "After 30 days"
- "By Q4"
- "Before 2026-12-31"

Checked: at ticket close (Producer scans deferred items with time-based conditions), and at release time (Release Manager).

### Event-based
- "When user reports slowness"
- "When Godot 4.7 releases"
- "When the next L ticket touches module X"
- "If user enables mobile target"

Checked: when the corresponding event occurs. Producer + Audit Trail Officer cross-reference deferrals on every new ticket triage.

### Count-based
- "After 5 closed tickets in this area"
- "After 3 occurrences of the same defect"
- "When this module is touched in a 4th ticket"

Checked: after every ticket close (Studio Knowledge Curator).

### Manual
- "When user explicitly asks"
- "On project review"

These are the weakest conditions — they rely on someone bringing the item up. The studio prefers any non-manual condition where possible.

---

## Resurfacing flow

When a resurfacing condition is met:

1. **Audit Trail Officer or Studio Knowledge Curator** identifies the trigger
2. A **Resurface Notice** is added to the deferral file:
   ```
   ## Resurface log
   - 2026-08-15: condition met (next minor release approaching). Notice raised.
   ```
3. **Producer** opens a new ticket referencing the DEF-NNN
4. The new ticket's `audit_trail` includes the deferral history (full context, not just the item)
5. The deferral state changes to RESURFACED
6. After the new ticket closes, the deferral state changes to ADDRESSED

**Critical**: the resurfacing creates a real ticket. It does not just notify someone. The studio treats deferred items as commitments, not wishes.

---

## Deferral as audit trail entry

When a deferral is created, an entry goes into the originating ticket's audit trail:

```json
{
  "timestamp": "2026-05-21T19:14:00Z",
  "role": "Tutorial Writer",
  "role_version": "1.2",
  "action": "defer_work",
  "deferral_id": "DEF-014",
  "subject": "Tutorial section for VECTOR_FIELD usage",
  "type": "documentation",
  "resurface_condition": "before_next_minor_release",
  "owner_role": "Tutorial Writer",
  "rationale": "TKT-007 scope is core plugin; documentation pass is separate",
  "blocks_current_ticket": false,
  "ticket_state_after": "IN_PROGRESS"
}
```

This entry is permanent. Even if the deferred item is closed years later, the deferral history is preserved in the originating ticket.

---

## Bulk operations

### List all active deferrals
```bash
ls .studio/deferred/*.md | xargs -I {} grep -l "State.*ACTIVE" {} 
```

### Find deferrals approaching their resurface condition
The Audit Trail Officer runs this at every ticket close:
```bash
# Scan time-based conditions
for f in .studio/deferred/*.md; do
    if grep -q "State.*ACTIVE" "$f"; then
        # Check resurface condition date / event
        # (Studio Knowledge Curator maintains a script for this)
        :
    fi
done
```

### Audit "forgotten" deferrals
A deferral that has been ACTIVE for more than 6 months without resurfacing is flagged for review. Studio Knowledge Curator reviews:
- Is the resurface condition still valid?
- Is this item still relevant?
- Should it be re-deferred with new conditions, or closed as no longer needed?

A "lost" deferral (one that was never resurfaced when its condition was met) is treated as a process defect and triggers a postmortem.

---

## The "I'll fix it later" failure mode

Without this tracker, the studio's previous failure mode was:

> Engineer: "We can fix the inspector drawer's tab order later."
> [conversation moves on]
> [ticket closes]
> [item is forever lost]

With this tracker, the same sentence forces:

> Engineer: "We can fix the inspector drawer's tab order later."
> Semantic Dependency Engineer: "Specify: when? Who owns? What's the resurface condition?"
> Engineer: "Resurface when the next ticket touches Inspector code, or before public release. Owner: Inspector Specialist."
> [DEF-XXX file created, audit trail entry logged]
> [item resurfaces when condition met]

This is the difference between an aspirational TODO comment and a tracked commitment.

---

## What goes in the deferred/ directory

```
.studio/deferred/
├── README.md          # this file's pointer
├── DEF-001.md         # one file per deferred item
├── DEF-002.md
├── DEF-014.md
├── ...
└── _archive/          # CLOSED and ADDRESSED items move here annually
    ├── DEF-001.md
    └── ...
```

Archived deferrals are NEVER deleted — they remain searchable as part of the studio's institutional memory.

---

## Cross-references

- **Origin ticket** — the ticket that created the deferral; preserved in DEF file
- **Resurfacing tickets** — when condition met, ticket is created and DEF file is updated
- **Related DEFs** — if multiple deferrals are about the same area, they cross-reference each other
- **Knowledge base** — recurring deferral patterns are extracted to `.studio/knowledge-base/recurring-deferrals.md`

---

## Anti-patterns this tracker prevents

| Anti-pattern | How tracker prevents |
|--------------|---------------------|
| "TODO: fix later" in code with no follow-up | Code-comment TODOs must reference a DEF-NNN, else flagged |
| Verbal commitments without record | Deferral requires audit trail entry + DEF file |
| Forgotten work | Resurface conditions trigger automatic ticket creation |
| Drift in scope | Scope Guardian + Deferral Tracker working together; out-of-scope items get DEF'd, not dropped |
| "We meant to do X but never did" | DEF stays ACTIVE forever until ADDRESSED, CLOSED, or RE-DEFERRED |
| Loss of context across long projects | Each DEF preserves origin context, why deferred, resurface condition |

---

## When the user asks "what's pending?"

The user can at any time ask the studio for a deferral inventory. The Audit Trail Officer (or Studio Knowledge Curator) produces a summary:

```
ACTIVE DEFERRALS (12)

By owner:
  Tutorial Writer: 3
  Inspector Specialist: 2
  Mobile Performance Specialist: 2
  Other: 5

By resurface condition timing:
  Imminent (next ticket / release): 4
  Within 30 days: 3
  Long-term: 5

By type:
  Feature: 4
  Test coverage: 3
  Documentation: 3
  Optimization: 2

Specific items pending resurfacing soon:
  DEF-014: Tutorial section for VECTOR_FIELD (before next minor release — release planned ~2 weeks)
  DEF-019: macOS compatibility test (before public release — release planned ~1 month)
  ...
```

This is how the user knows what the studio has committed to but not yet delivered.

---

End of Deferred Work Tracker. This system is the studio's memory across tickets. Combined with the Semantic Dependency Engine (Faz 3), it ensures that the studio does not silently lose any thread of work.
