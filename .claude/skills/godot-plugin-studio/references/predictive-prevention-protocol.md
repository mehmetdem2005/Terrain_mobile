# Predictive Prevention Protocol (v2.2)

The studio's protocol for turning defect catalogs from **reactive evidence at bug-hunt time** into **proactive checklists at plan time**. The defect catalogs (plugin: 64 patterns, game: 75+ patterns) are walked at Phase 1.G to verify nothing slipped through. This protocol walks them again at Phase 1.D — before code is written — to prevent the patterns that this specific ticket's shape makes likely.

This is what the difference between a junior and a senior engineer looks like, encoded as protocol. A junior writes code and waits to see what breaks. A senior writes code knowing the specific failure modes their domain has, and pre-emptively avoids them.

The studio operationalizes "senior engineering thinking" via this protocol.

---

## What's broken without this protocol

In v2.1 the defect catalogs are walked at Phase 1.G — after code exists. The pattern recognition is reactive: "did this code do GAME-DEF-024?" If yes, fix; if no, move on. The catalogs are a graveyard of known mistakes, used as evidence collection rather than as prevention.

In v2.2 (with this protocol), the catalogs are walked at Phase 1.D — *before* code exists. The pattern recognition is proactive: "this ticket touches save data, so GAME-DEF-024 through 030 are pre-emptively in scope. The Phase 1.D plan must show explicit mitigations for each that is plausibly relevant."

Same catalog. Different consumption pattern. Massive difference in outcomes.

The catalogs become **predictive instruments**, not just postmortem references.

---

## How predictive prevention works

The protocol has three steps:

1. **Ticket fingerprinting** — extract the technical characteristics that determine which defect categories apply
2. **Catalog pre-scan** — pull the relevant categories from the defect catalogs into a ticket-specific checklist
3. **Plan integration** — the Phase 1.D plan demonstrates explicit mitigation per relevant pattern

Each step has an owner role and a gate.

---

## Step 1 — Ticket fingerprinting

At Phase 1.C close (architecture chosen), the Defect Pattern Specialist produces a `ticket-fingerprint.md` describing the technical surface of the ticket. This is the input to Step 2.

### Fingerprint dimensions

Standard fingerprint axes — answer each with yes/no/unsure:

**Persistence & I/O**
- Touches save data?
- Touches user files (read/write outside `user://`)?
- Touches project files (`res://` writes)?
- Touches network (HTTP, sockets, multiplayer)?

**Editor vs runtime**
- Editor-time only (plugin work)?
- Runtime-only (game work)?
- Both?
- @tool annotations involved?

**Lifecycle surface**
- Adds new autoloads?
- Modifies `_enter_tree` / `_exit_tree` / `_ready` / `_process` / `_physics_process`?
- Adds new signals?
- Modifies plugin.cfg or project.godot?

**State management**
- New persistent state (saved across sessions)?
- New session state (lost on quit)?
- New state machine?
- Cross-system state references?

**Concurrency & timing**
- `await` / coroutines?
- `call_deferred`?
- Frame-rate-dependent logic?
- Tweens?
- Timers?

**Rendering & assets**
- Custom shaders or materials?
- Procedural geometry?
- Texture loading at runtime?
- Resource sharing across instances?

**Input & UI**
- New input actions?
- Touch input required?
- Modal UI (consumes vs lets through)?
- Theme changes?

**Platform & target**
- Mobile target?
- Multi-platform target?
- Console target (if applicable)?
- Specific Godot version requirements?

**Multiplayer (game-only)**
- RPC calls?
- MultiplayerSynchronizer?
- Server-authoritative vs client-authoritative?

### Format

```markdown
# Ticket Fingerprint — TKT-NNN

## Persistence & I/O
- Touches save data: yes — save settings to user://
- Touches user files: no
- Touches project files: no
- Touches network: no

## Editor vs runtime
- Editor-time only: yes (plugin work)
- @tool annotations: yes

## Lifecycle surface
- Adds new autoloads: no
- Modifies lifecycle hooks: yes — _enter_tree adds dock; _exit_tree removes it
- Adds new signals: yes — three signals on the new dock controller
- Modifies plugin.cfg: yes — new dock listed

...

## Summary of relevant defect categories

Based on the fingerprint, the following catalog categories apply to this ticket:

- **Plugin catalog**: Lifecycle (A), Inspector (B-partial), Signals (D), Persistence (G)
- **Game catalog**: not applicable (editor-time only)

Total estimated patterns to walk: 24 (out of 64+75 = 139 in catalogs)
```

### Owner

**Defect Pattern Specialist** (existing v2.0 role, now active at Phase 1.D). They produce the fingerprint by reviewing:

- Architecture document from Phase 1.C
- Original ticket intent
- The user's responses from Phase 1.A turns

### Gate

**L50 — Ticket fingerprint complete**. `ticket-fingerprint.md` exists, every axis answered yes/no/unsure, summary of relevant catalog categories listed.

---

## Step 2 — Catalog pre-scan

The Defect Pattern Specialist takes the fingerprint and produces a `predictive-checklist.md`: every pattern from every relevant category, scoped to this ticket.

### Process

For each catalog category listed in the fingerprint summary:

1. Open the catalog (plugin or game)
2. For each pattern in that category, decide:
   - **Applies**: the pattern is plausibly relevant to this ticket
   - **Doesn't apply**: the pattern is in scope category but not in scope for this ticket's specifics
3. For each "Applies" pattern, write a checklist entry

### Format

```markdown
# Predictive Checklist — TKT-NNN

Source fingerprint: `ticket-fingerprint.md`
Categories walked: A (Lifecycle), D (Signals), G (Persistence) from plugin catalog

## Category A: Lifecycle

### DEF-PATTERN-001: `_enter_tree` doesn't undo state from `_exit_tree`
**Status**: APPLIES — this ticket adds a dock in _enter_tree
**Mitigation in plan**: Sub-task 3 explicitly tests reload cycle; _exit_tree removes-and-destroys, _enter_tree builds fresh.
**Owner**: Plugin Lifecycle Engineer

### DEF-PATTERN-002: `_exit_tree` leaves dangling references
**Status**: APPLIES — this ticket holds dock reference
**Mitigation in plan**: Sub-task 3 includes explicit nullification in _exit_tree.
**Owner**: Plugin Lifecycle Engineer

### DEF-PATTERN-003: Plugin registration not idempotent
**Status**: APPLIES
**Mitigation in plan**: Sub-task 4 wraps registration in is_already_registered check.
**Owner**: Plugin Lifecycle Engineer

### DEF-PATTERN-004: ... 
**Status**: DOESN'T APPLY — this ticket doesn't touch UndoRedo
**Reasoning**: No history-modifying operations in scope.

## Category D: Signals

### DEF-PATTERN-018: Signal connected in _ready but not disconnected
**Status**: APPLIES
**Mitigation in plan**: Sub-task 5 uses connect(callable) Godot 4 syntax which auto-cleans on free; verified in test.

...

## Summary

- Total patterns walked: 24
- APPLIES (requires mitigation): 11
- DOESN'T APPLY (with reasoning): 13
- Plan covers all APPLIES patterns: ✓
```

### Rules

- Every applying pattern must reference a specific sub-task in the Phase 1.D plan
- Every dismissed pattern must have reasoning — never silent dismissal
- The Defect Pattern Specialist can recommend new sub-tasks to the Tech Director if the existing plan doesn't cover an APPLIES pattern

### Owner

**Defect Pattern Specialist** drives the walk. Sub-task assignments confirmed with **Tech Director**.

### Gate

**L51 — Predictive checklist complete and integrated**. Every APPLIES pattern has a plan sub-task; every DOESN'T APPLY has reasoning; Tech Director countersigned.

---

## Step 3 — Plan integration

The Phase 1.D plan is updated so each APPLIES pattern explicitly maps to one or more sub-tasks. This is not a separate document — it's an annotation in the existing plan.

### Plan annotation format

```markdown
# Phase 1.D Plan — TKT-NNN

## Sub-task 1: Set up plugin entry point
**Predictive coverage**: DEF-PATTERN-001 (lifecycle invariance), DEF-PATTERN-003 (idempotent registration)
**Owner**: Plugin Lifecycle Engineer
**Acceptance**: Plugin enables and disables cleanly N times in a row; no leftover state.

## Sub-task 2: Add dock control with three signals
**Predictive coverage**: DEF-PATTERN-002 (no dangling refs), DEF-PATTERN-018 (signal cleanup)
**Owner**: Plugin Lifecycle Engineer + Plugin UI Engineer
**Acceptance**: Dock visible after enable; disappears cleanly after disable; signals fire only when dock is alive.

## Sub-task 3: ...
```

Every sub-task explicitly states which predictive patterns it covers. At Phase 1.G:

- Bug Hunter Lead's catalog walk should find **no surprises** — every catalog match was already predicted. If a defect IS found that wasn't predicted, the Defect Pattern Specialist owes an explanation: was the fingerprint incomplete? Was the pattern dismissed wrongly?

This makes the catalog walk at Phase 1.G a **verification** of the predictive checklist, not an open-ended discovery. The discovery happened at Phase 1.D.

### Owner

**Tech Director** owns the integrated plan. **Defect Pattern Specialist** is consulted for predictive coverage annotations.

### Gate

**L52 — Plan predictive-coverage annotations complete**. Every sub-task in the Phase 1.D plan either has a "predictive coverage" line OR explicitly states "no catalog patterns apply to this sub-task — coverage by other sub-tasks."

---

## Phase 1.G verification (closing the loop)

At Phase 1.G, the catalog walk is restructured. Instead of "did anything from the catalog match?" the new question is:

**"Did we miss anything beyond what the predictive checklist anticipated?"**

The Bug Hunter Lead runs the catalog walk and produces a `predictive-vs-actual.md`:

```markdown
# Predictive vs Actual — TKT-NNN

## Patterns predicted as APPLIES — verification

| Pattern | Predicted | Actual outcome | Notes |
|---------|-----------|----------------|-------|
| DEF-PATTERN-001 | Mitigation in sub-task 1 | Mitigation worked, no defect | ✓ |
| DEF-PATTERN-002 | Mitigation in sub-task 2 | Defect found during bug-hunt; mitigation was incomplete | ✗ — see fix in sub-task 9 |
| ... | | | |

## Patterns predicted as DOESN'T APPLY — verification

| Pattern | Reasoning at Phase 1.D | Re-verified at 1.G | Notes |
|---------|----------------------|-------------------|-------|
| DEF-PATTERN-004 | No UndoRedo in scope | Still correct | ✓ |
| ... | | | |

## Patterns not predicted but matched

| Pattern | How missed | New entry for Knowledge Loop? |
|---------|------------|------------------------------|
| DEF-PATTERN-027 | Fingerprint missed the "modal UI" axis | Yes — lesson candidate L-N |
| ... | | |

## Summary

- Predicted APPLIES verified: 10/11 worked, 1/11 needed additional fix
- Predicted DOESN'T APPLY verified: 13/13 correct
- Unpredicted matches: 1 — lesson harvested
```

### Gate

**L53 — Predictive vs actual reconciliation complete**. The `predictive-vs-actual.md` exists; unpredicted matches feed Knowledge Loop lesson candidates; fingerprint gaps that caused misses are documented.

---

## Integration with Knowledge Loop

This protocol creates a tight feedback loop with the Knowledge Loop:

- **Unpredicted matches** → lesson candidates (the fingerprint axis was missing or misapplied)
- **Repeated unpredicted matches in the same axis** → that axis gets a synthesis pattern in the knowledge base
- **Repeatedly-predicted-but-rarely-applies patterns** → the fingerprint heuristics get refined to predict less aggressively

The Studio Knowledge Curator does periodic review (every 10 tickets):

- Which fingerprint axes have predicted accurately?
- Which axes over-predict (lots of APPLIES that never materialize)?
- Which axes under-predict (lots of unpredicted matches)?

This drives evolution of the fingerprint template itself. The fingerprint is not static — it learns.

---

## Integration with Risk Register

Risk Register and Predictive Prevention are complementary:

| Risk Register | Predictive Prevention |
|---------------|----------------------|
| Adversarial: "what could go wrong?" | Systematic: "what does this ticket's shape predict?" |
| Probability × impact reasoning | Pattern category mapping |
| Owner per risk, mitigation per risk | Sub-task per pattern, mitigation per sub-task |
| Phase 1.B output | Phase 1.D output |
| Captures unique ticket-specific risks | Captures known-category risks systematically |
| Bridges to Knowledge Loop via lesson candidates | Bridges to Knowledge Loop via fingerprint refinement |

A risk in the Risk Register might cite a pattern from the Predictive Checklist; conversely, a pattern that the Predictive Checklist marks APPLIES might warrant a more detailed Risk Register entry if its impact is high.

The two protocols overlap on purpose: redundancy at the planning layer is acceptable because it's cheap. Missed risks at execution are expensive.

---

## Roles in the protocol

### Defect Pattern Specialist (existing, expanded)
- Produces `ticket-fingerprint.md` at Phase 1.C close
- Produces `predictive-checklist.md` at Phase 1.C → Phase 1.D transition
- Verifies plan integration
- Participates in Phase 1.G predictive-vs-actual reconciliation

### Tech Director (existing, expanded)
- Countersigns predictive checklist
- Owns plan annotations
- Coordinates with Defect Pattern Specialist on sub-task adjustments

### Bug Hunter Lead (existing, role evolves)
- Phase 1.G catalog walk now structured around predictive checklist, not open exploration
- Reports unpredicted matches as findings
- Collaborates with Defect Pattern Specialist on `predictive-vs-actual.md`

### Studio Knowledge Curator (existing, new collaboration)
- Reviews fingerprint accuracy every 10 tickets
- Proposes fingerprint axis refinements based on accuracy data

---

## Quality Gates

| Gate | Check | Owner |
|------|-------|-------|
| **L50** | Ticket fingerprint exists, every axis answered, relevant categories summarized | Defect Pattern Specialist |
| **L51** | Predictive checklist complete; every APPLIES has sub-task; every DOESN'T APPLY has reasoning | Defect Pattern Specialist + Tech Director |
| **L52** | Phase 1.D plan sub-tasks annotated with predictive coverage | Tech Director |
| **L53** | Phase 1.G predictive-vs-actual reconciliation complete; unpredicted matches fed to Knowledge Loop | Bug Hunter Lead + Defect Pattern Specialist |

---

## Cost-aware mode behavior

- **Lite (S tickets)**: Skipped. S tickets are too small for the fingerprint overhead. If Tech Director suspects pattern risk, upgrade to Standard.
- **Standard (M, most L)**: Fingerprint axes can be narrowed to the relevant 3-4 dimensions (not all axes always relevant). Predictive checklist usually covers 10-25 patterns.
- **Full (XL)**: Full protocol. Fingerprint walks all axes. Predictive checklist may cover 30-60 patterns. Phase 1.G reconciliation is detailed.

---

## What this protocol does NOT do

- It does not require predicting every possible defect. Unpredicted matches are okay — they become lessons.
- It does not replace the Phase 1.G catalog walk. It restructures it from open discovery to predictive verification.
- It does not require running the full catalog on every ticket. The fingerprint scopes which categories apply.
- It does not make the Defect Pattern Specialist a fortune teller. They map ticket characteristics to known patterns; novel patterns will still surprise the studio occasionally.

---

## Why this is part of the intelligence layer

Without Predictive Prevention, the catalog is a graveyard — full of known mistakes, used only when something has already broken. Bug Hunter Lead walks it at Phase 1.G with the question "did we step on something?" — and often the answer is yes, but the recovery is costly.

With Predictive Prevention, the catalog is a prevention instrument:
- Patterns are pulled forward to planning time
- Mitigations are designed in, not bolted on
- The Phase 1.G walk becomes verification of predictions, not discovery
- Misses teach the fingerprint to be sharper next time

This is what the difference between reactive and proactive engineering looks like. The studio's defect catalogs were always knowledge; this protocol makes them **active** knowledge.

This is the third of four v2.2 layers. With Knowledge Loop (the studio remembers) and Risk Register (the studio names risks) and Predictive Prevention (the studio anticipates patterns) in place, the only remaining intelligence gap is what to do when the studio realizes it took the wrong direction. That's Rollback Strategy — the final layer.
