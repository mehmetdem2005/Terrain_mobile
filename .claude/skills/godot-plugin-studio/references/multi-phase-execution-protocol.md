# Multi-Phase Execution Protocol

This protocol replaces the "tek seferde yap" failure mode. Every L and XL ticket must walk through 7 mandatory phases before sign-off. **No code is written before Phase 1.F.** Skipping a phase requires explicit Studio Head override and creates an auto-postmortem ticket.

For M tickets the phases collapse but the discipline holds: at minimum the engineer must perform 1.A (understand) and 1.C (architect) before coding, even if briefly.

---

## Why this exists

The previous default was: read user request → start coding → discover issues mid-flight → patch → ship. This produces:
- Unconsidered architectures discovered too late to redo
- Half-thought-through edge cases
- Dependencies discovered after they bite
- Plans that mutate during implementation, leaving the original intent behind

The studio rejects this mode of work. AAA studios spend more time *thinking before coding* than *coding*. This protocol enforces that ratio.

---

## The 7 phases

| Phase | Name | Role(s) leading | Output | Gate |
|-------|------|-----------------|--------|------|
| 1.A | Understanding | Producer + Tech Director + R&D Engineer | `intent-doc.md` | User confirmation if ambiguous |
| 1.B | Discovery | Prior Art Researcher + Feasibility Analyst + API Verification Specialist | `feasibility-doc.md` | Feasible? Y/N/conditional |
| 1.C | Architecture | Plugin Design Lead + Principal Engineer + ARB | `architecture-doc.md` + ADR(s) | ARB unanimous-or-majority approval |
| 1.D | Planning | Producer + Tools Lead + DoD Steward + Impact Analyzer | `task-breakdown.md` (per-file, per-module sub-tasks) | DoD Steward signs the breakdown |
| 1.E | **Architecture Gate** (the hard stop) | Architecture Veto Officer + ARB | Architectural quality assessment | **Pass = code can begin. Fail = back to 1.C.** |
| 1.F | Execution | Tools Engineering + Engine Engineering specialists | Code, module by module | Each module passes its own M-tier checks |
| 1.G | Integration | Integration Engineer + Semantic Dependency Engineer + Consistency Auditor | `integration-report.md` | Every wired-in dependency accounted for |

After 1.G, the ticket enters the existing QUALITY_GATE → HONESTY_AUDIT → SIGN_OFF flow.

---

## Phase 1.A — Understanding

**Goal:** convert the user's natural-language request into an unambiguous, structured intent document. No assumptions about *how* — only *what* and *why*.

### Required actions
1. Producer extracts: domain, scope boundaries, hard requirements, soft preferences
2. Tech Director identifies unstated constraints (platform, version, dependencies)
3. R&D Engineer flags any domain unknowns that need spike investigation in Phase 1.B
4. If ANYTHING is ambiguous: ASK USER. Do not assume. Do not proceed.

### Output: `intent-doc.md` (lives in ticket folder)
```markdown
# Intent — TKT-NNN

## What the user said (verbatim)
[paste user's original message]

## What they actually want (our interpretation)
[restated in studio language]

## Hard requirements (will block sign-off if not met)
- ...

## Soft preferences (we'll honor where possible)
- ...

## Out of scope
- ...

## Unknowns to resolve in Phase 1.B
- ...

## Confidence
[high / medium / low] — if low, ASK USER before proceeding
```

### Exit criteria
- Every hard requirement is testable (you can write a check for it)
- Every soft preference is documented even if we won't act on it
- Out-of-scope list exists (Scope Guardian will police this)
- If confidence is low, user has confirmed our interpretation

---

## Phase 1.B — Discovery

**Goal:** verify the work is feasible before architecting it. Run spikes, check prior art, verify APIs exist.

### Required actions
1. Prior Art Researcher searches Asset Library and GitHub — has this been built already?
2. Feasibility Analyst checks every required Godot capability against 4.6.2 API XML
3. API Verification Specialist verifies the methods/signals/classes that the implementation will lean on
4. R&D Engineer runs spikes on each unknown from 1.A — write throwaway proof-of-concepts
5. Any "infeasible" finding triggers a return to 1.A to renegotiate scope with user

### Output: `feasibility-doc.md`
```markdown
# Feasibility — TKT-NNN

## Required capabilities
| Capability | Godot 4.6.2 status | Evidence |
|-----------|--------------------|----------|
| EditorInspectorPlugin.parse_property | EXISTS | grep ~/godot-api-reference/EditorInspectorPlugin.xml |
| ... | ... | ... |

## Prior art
- [link/path]: similar plugin, evaluated — [we'll use it / partial overlap / not a fit]

## Spikes run
- Spike 1: [unknown] → result: [feasible / infeasible / requires X]

## Verdict
- FEASIBLE — proceed to 1.C
- FEASIBLE WITH CAVEATS — proceed with explicit risks logged
- INFEASIBLE AS STATED — return to 1.A; renegotiate
```

### Exit criteria
- Every API claim that will be made in 1.C has an XML verification entry
- All R&D spikes are concluded (no "we'll see" items)
- Verdict is explicit

---

## Phase 1.C — Architecture

**Goal:** design the solution at the architectural level — module boundaries, data flow, lifecycle, public surface. This is where the studio is most ambitious. **Architecture decisions made here are expensive to undo later, so the studio spends real thinking here.**

### Required actions
1. Plugin Design Lead drafts the architecture proposal — at least 3 alternatives (see Innovation Engine; Phase 7 enforces this)
2. ARB (all 3 seats) evaluates each alternative independently
3. Trade-off Analyst produces comparison matrix: maintainability, performance, complexity, mobile compatibility, time, risk
4. Principal Engineer challenges the chosen design — devil's advocate stance on the architecture itself
5. ADR(s) recorded for every decision that will outlive this ticket

### Output: `architecture-doc.md` + one or more `ADR-NNN.md`
```markdown
# Architecture — TKT-NNN

## Solution chosen
[short statement]

## Alternatives considered
### Alternative A: Conservative
- approach: ...
- trade-offs: ...
- rejected because: ...

### Alternative B: Modern idiomatic
- approach: ...
- trade-offs: ...
- chosen because: ...

### Alternative C: Creative/unconventional
- approach: ...
- trade-offs: ...
- rejected/deferred because: ...

## Module boundaries
[ASCII or prose architecture diagram]

## Data flow
[how data moves through the system]

## Lifecycle
[what happens on enable, on disable, on project switch, on Godot restart]

## Public API surface
[what the user / other code sees]

## Internal modules
[helpers, no external surface]

## Dependencies
[other plugins, Godot subsystems, external resources]

## Risks accepted
[explicit risks the architecture introduces, logged to risks.md]

## ADRs created
- ADR-NNN: [topic]
- ...
```

### Exit criteria
- ≥3 alternatives evaluated (not just "we picked this") — Innovation Engine enforces
- ARB has voted; dissent recorded
- ADRs exist for any decision touching multiple modules or the public API
- The chosen architecture is **drawable as a diagram in <5 minutes** — if it cannot be sketched simply, it is too complex; reconsider

---

## Phase 1.D — Planning

**Goal:** break the architecture into concrete, ordered, per-file/per-module work units. This is where "what we're building" becomes "who does what when."

### Required actions
1. Producer creates a task tree: every file to be created/modified gets a sub-task with an ID
2. Tools Lead assigns specialists to each sub-task
3. Impact Analyzer pre-emptively identifies cross-file dependencies (which sub-tasks unblock or block which others)
4. DoD Steward defines acceptance criteria per sub-task
5. Producer orders the sub-tasks; identifies parallelizable vs sequential

### Output: `task-breakdown.md`
```markdown
# Task Breakdown — TKT-NNN

## Sub-tasks

### ST-01: Create plugin.cfg
- Owner: Senior Tools Engineer
- Depends on: [nothing — this is the entry]
- Blocks: ST-02, ST-08
- Acceptance: plugin.cfg has all required fields, parses, references valid script

### ST-02: Create plugin.gd (EditorPlugin entry)
- Owner: Senior Tools Engineer
- Depends on: ST-01 (needs script path)
- Blocks: ST-03, ST-04, ST-09
- Acceptance: _enter_tree/_exit_tree symmetric, parses, loads in test harness

### ST-03: Create inspector.gd
- Owner: Inspector Specialist
- Depends on: ST-02
- Blocks: ST-05
- Acceptance: ...

[...]

## Execution order
Phase 1.F.1 (sequential, blocking): ST-01 → ST-02
Phase 1.F.2 (parallel after ST-02): ST-03, ST-04 (different files, no overlap)
Phase 1.F.3 (after ST-03 and ST-04): ST-05, ST-06
Phase 1.F.4 (final wire-up): ST-07, ST-08, ST-09
```

### Exit criteria
- Every architecture component from 1.C maps to ≥1 sub-task
- No sub-task is "implement everything else"
- Dependency graph is acyclic
- DoD Steward signs the breakdown

---

## Phase 1.E — Architecture Gate (the hard stop)

**This is the most important phase in the protocol. It exists to prevent the studio from coding a bad architecture beautifully.**

### Required actions
The **Architecture Veto Officer** (see `architectural-veto-protocol.md`) reviews:
1. Is the chosen architecture from 1.C actually AAA-quality, or is it just "okay"?
2. Does the task breakdown from 1.D actually realize the architecture, or has the plan drifted?
3. Are there any "we'll figure it out in 1.F" items? (These are red flags.)
4. Would a senior engineer at a real AAA studio approve this design?

### Decision
- **PASS** → Phase 1.F begins. Code may be written.
- **FAIL** → Ticket returns to Phase 1.C with specific findings. Cannot bypass.
- **PASS WITH CONDITIONS** → Code may begin, but specific risks must be addressed before Quality Gate.

### What "AAA" means at this gate
Not perfect — pragmatic. AAA means:
- Module boundaries align with conceptual boundaries (not artifacts of expedience)
- Each module has a single, expressible responsibility
- Coupling between modules is intentional and minimal
- Lifecycle is fully thought through (init, runtime, teardown, error paths)
- The design accommodates extension without major rework
- The design can be explained to another engineer in <10 minutes

If any of these is not true, the gate fails.

### Output: gate decision logged to ticket audit trail
```json
{
  "phase_gate": "1.E",
  "verdict": "PASS|FAIL|PASS_WITH_CONDITIONS",
  "evaluator": "Architecture Veto Officer",
  "rationale": "...",
  "conditions": [...],
  "blocks_until": null | "phase_1.C_redo"
}
```

---

## Phase 1.F — Execution

**Goal:** write the code, module by module, following the task breakdown.

### Required actions
1. Execute sub-tasks in the order defined in 1.D
2. After each sub-task: run the module's parse check, lint, and any relevant unit tests
3. After each sub-task: append to ticket audit trail with file paths and line ranges
4. NEVER deviate from the architecture without re-opening 1.C
5. If a sub-task reveals an architecture issue: STOP. Raise blocker. Return to 1.C.

### Anti-pattern
"While I was coding ST-03, I realized the architecture should be different, so I changed it on the fly."

This is forbidden. The architecture is the architecture. If discovery happens mid-execution, the ticket returns to 1.C — the architecture is amended explicitly, then execution resumes.

### Exit criteria
- Every sub-task is complete with its acceptance criteria verified
- Audit trail is complete (no gaps)
- No deviation from 1.C's architecture (or, if deviation occurred, 1.C was re-opened and amended)

---

## Phase 1.G — Integration

**Goal:** wire everything together. Verify the parts work as a whole. Apply semantic dependency rules. Account for every domino effect.

This is the phase where Faz 3 (Semantic Dependency Engine) and Faz 4 (Integration Enforcement) live.

### Required actions
1. **Semantic Dependency Engineer** runs the 7-question audit for every new/changed concept
2. **Integration Engineer** verifies every public function has callers and every new module is invoked
3. **Dead Code Hunter** scans for orphan functions, unused preloads, unreferenced symbols
4. **Consistency Auditor** cross-checks the audit trail for contradictions
5. **Cross-impact analysis** is run (Faz 3 protocol)
6. Every deferred item is logged to the Deferred Work Tracker (see `deferred-work-tracker.md`)

### Output: `integration-report.md`
```markdown
# Integration Report — TKT-NNN

## Semantic dependencies addressed
[per-concept 7-question audit results]

## Wiring audit
- New public functions: [list] — all have callers ✓
- New modules: [list] — all invoked ✓
- New signals: [list] — emitters + listeners verified ✓

## Dead code scan
- Orphan functions found: [none, or list]
- Unused preloads: [none, or list]
- Unreferenced symbols: [none, or list]

## Cross-impact
- Files outside this ticket's direct scope that were touched: [list]
- Justification: [why each was necessary]

## Deferred items
- DEF-NNN: [item] — [why deferred] — [tracked in deferred-work-tracker.md]

## Final consistency check
- Audit trail contradictions: [none, or list]
- All blockers resolved: ✓
```

### Exit criteria
- Every semantic dependency rule that applies has been considered
- Zero dead code introduced
- Zero unaddressed cross-impact
- All deferrals tracked

---

## Collapsed phases for M tickets

M tickets do not require the full 7-phase walk. Minimum required:

| Phase | M ticket requirement |
|-------|---------------------|
| 1.A | Verbal/internal restate of intent (1-2 sentences in audit trail) |
| 1.B | Verify the APIs used exist (API Verification Specialist) |
| 1.C | Architecture sketch — even 5 sentences is fine if it's coherent |
| 1.D | List the files to change |
| 1.E | Self-evaluation against AAA criteria (Tools Lead signs) |
| 1.F | Execute |
| 1.G | Semantic dependency audit + dead code scan |

S tickets skip phases 1.A through 1.E (the work is trivial). They still get 1.G (cannot ship dead code or orphans even in a trivial change).

---

## Anti-patterns this protocol prevents

| Anti-pattern | How protocol prevents it |
|--------------|--------------------------|
| Start coding before understanding | 1.A is mandatory and gates everything |
| Architect on the fly while coding | 1.C is locked once approved; deviation reopens it |
| "Fix it later" mentality | Deferred Work Tracker (no "later" without a ticket reference) |
| Beautiful code in bad architecture | 1.E veto kills this before any code is written |
| Domino effects discovered after ship | 1.G semantic dependency audit catches them |
| Lost intent over long tickets | 1.A intent doc is referenced at every later phase |
| "I'll figure it out as I go" | 1.D task breakdown forces upfront thinking |

---

End of protocol. This protocol is the single biggest difference between the v1.0 studio (tactical) and the v2.0 studio (architecturally disciplined). It is required reading for Tech Director, Plugin Design Lead, and every Tools Engineering specialist.
