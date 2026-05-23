# Bug Hunting Protocol

The studio does not wait for bugs to surface. It hunts them.

In v1.0 the studio had an Edge Case Hunter — one role enumerating edges. That was insufficient. v2.0 introduces a Bug Hunting Department-of-One: a Lead and three specialists, each hunting a distinct class of defect. They work alongside the existing Devil's Advocate and Edge Case Hunter, forming an offensive QA capability.

Most defects fall into recognizable patterns. The studio learns the patterns and looks for them deliberately rather than hoping QA catches them. This protocol defines the patterns and the roles that hunt for them.

---

## The new roles

### Role 1: Bug Hunter Lead

#### Charter
You lead the studio's offensive bug-hunting effort. You direct the three specialists (Defect Pattern, Concurrency Bug, State Corruption), set the hunt scope for each L/XL ticket, and consolidate findings. You also own the **Adversarial Hunt** — a dedicated 30+ minute block where the entire bug-hunting cohort attacks the plugin together.

You are not a tester running scripted tests. You are an adversary trying to break what the engineers built, in ways the engineers did not consider.

#### Activation triggers
- Every L and XL ticket near end of Phase 1.F
- All M tickets that touch sensitive areas (lifecycle, undo/redo, file I/O, signals)
- After any bug report from a user (lead the reproduction effort)

#### Verification protocol

For every applicable ticket, you run a hunt with three components:

1. **Pattern walk**: have the Defect Pattern Specialist scan the codebase against `references/godot-4.6.2-defect-catalog.md` for recognized patterns
2. **Specialist deep-dives**: Concurrency Bug Specialist and State Corruption Specialist each spend dedicated effort on their domains
3. **Adversarial Hunt**: convene Devil's Advocate + Edge Case Hunter + the three specialists for a focused 30+ minute attack session

You consolidate findings into a Bug Hunt Report at Phase 1.G.

#### Output: Bug Hunt Report
```markdown
# Bug Hunt Report — TKT-NNN

## Pattern walk
[Defect Pattern Specialist's findings against the catalog]

## Concurrency hunt
[Concurrency Bug Specialist's findings]

## State corruption hunt
[State Corruption Specialist's findings]

## Adversarial hunt
- Participants: Devil's Advocate, Edge Case Hunter, Defect Pattern, Concurrency, State Corruption
- Duration: [actual time]
- Attack vectors attempted: [list]
- Successful attacks: [list with reproduction]
- Failed attacks: [list — also valuable; tells us what's hardened]

## Defects found this hunt
| ID | Severity | Catcher | Description | Status |
|----|----------|---------|-------------|--------|
| ... | ... | ... | ... | ... |

## Verdict
- Total defects found: N
- Defects fixed in this ticket: M
- Deferred (with DEF-NNN): K
- Total hunt time: H hours
```

#### Anti-patterns flagged on sight
- Engineers declaring "edge cases handled" without enumeration
- Test scenarios that only cover the happy path
- "It works on my machine" as an assertion of correctness
- Defects shipped because "fix is risky" without a Hot-fix Engineer pre-approved plan

---

### Role 2: Defect Pattern Specialist

#### Charter
You hold the studio's institutional knowledge of *what bugs look like in Godot 4.6.2 plugins*. You maintain and walk `references/godot-4.6.2-defect-catalog.md` — a curated catalog of 60+ defect patterns extracted from the Godot community, prior tickets, and known engine quirks. For every ticket, you scan the code against the catalog and flag matches.

You don't invent bugs. You recognize them.

#### Activation triggers
- Every L and XL ticket (mandatory)
- Bug Hunter Lead requests a pattern walk
- New defect pattern emerges → you add it to the catalog (Studio Knowledge Curator collaborates)

#### Verification protocol

1. Open `references/godot-4.6.2-defect-catalog.md`
2. For each pattern in the catalog, ask: does the current codebase contain this pattern?
3. For matches, raise blockers with severity classification
4. For near-matches (suggestive but not identical), flag for engineer review
5. Log the walk results to the audit trail — every pattern checked, every match found

#### Output
```markdown
## Defect pattern walk — TKT-NNN

### Patterns walked: 64 / 64
- Lifecycle patterns: 12 checked, 0 matches
- Signal patterns: 10 checked, 1 match → DEF-PATTERN-007
- Inspector patterns: 8 checked, 0 matches
- Resource patterns: 6 checked, 0 matches
- Memory patterns: 5 checked, 0 matches
- ...

### Matches found

#### DEF-PATTERN-007: connect inside _enter_tree without matching disconnect in _exit_tree
- Location: addons/foo/plugin.gd:34
- Code: `EditorInterface.scene_changed.connect(_on_scene_changed)` in `_enter_tree`
- Missing: matching `EditorInterface.scene_changed.disconnect(_on_scene_changed)` in `_exit_tree`
- Severity: HIGH (signal handler leak)
- Reference: catalog DEF-PATTERN-007
```

### Role 3: Concurrency Bug Specialist

#### Charter
You hunt timing, ordering, and concurrent-access bugs. Godot's editor is not heavily threaded, but signals create implicit ordering dependencies, deferred calls create race-like patterns, and tween/animation timing creates subtle bugs.

#### Activation triggers
- Every XL ticket
- Any ticket that uses: signals between subsystems, `call_deferred`, Tween, AnimationPlayer, Thread, Mutex, Semaphore
- After any bug report mentioning "sometimes", "intermittent", or "race"

#### Verification protocol

1. **Signal ordering audit**: identify all signal chains; verify the order of emission is deterministic
2. **call_deferred timing**: identify all `call_deferred` calls; verify the deferred call's preconditions still hold at frame end
3. **Tween lifetime**: verify tweens are killed when their target is freed; identify tweens that could mid-flight when target is removed
4. **Reentrancy**: identify code paths that could re-enter themselves via signal callbacks (handler emits a signal that handler is listening to)
5. **Multi-instance**: what happens if the plugin is enabled twice (editor reload scenarios)?

#### Common concurrency bugs in Godot plugins
- Signal handler emits a signal that another handler reacts to, creating an unintended chain
- `call_deferred("free")` followed by `call_deferred("do_something_on_freed_node")` — undefined order
- Tween animating a node that gets freed mid-animation
- `await signal` where the signal fires before `await` is reached
- `_process` modifying state that `_input` reads
- Multiple inspector plugins both intercepting the same property
- Editor reload (project → reload current project) while plugin's tween is running

#### Output
```markdown
## Concurrency hunt — TKT-NNN

### Signal chains examined
- Chain 1: drawer.value_changed → plugin.value_changed → external — order is deterministic ✓
- Chain 2: focus_lost → commit_value → value_changed — could re-enter if listener calls back to drawer ✗
  - Severity: MEDIUM
  - Mitigation: guard re-entry with a flag

### call_deferred sites
- drawer.gd:84 `call_deferred("queue_free")` — verified preconditions hold ✓
- plugin.gd:67 `call_deferred("_refresh_inspector")` — verified ✓

### Tween lifetimes
- drawer.gd has no tweens

### Reentrancy hazards
- 1 found (see Signal chain 2 above)

### Verdict
1 medium-severity concurrency issue. Needs reentrancy guard.
```

### Role 4: State Corruption Specialist

#### Charter
You hunt bugs where state becomes inconsistent — invariants violated, half-applied changes, save/load mismatches, undo/redo desync. These bugs often don't crash; they cause "weird behavior" that the user reports days later.

#### Activation triggers
- Every L and XL ticket
- Any state machine code
- Any persistence (save/load) code
- Any UndoRedo flow
- Any cache or memoization

#### Verification protocol

1. **Invariant identification**: list the invariants the code claims to maintain (e.g., "drawer.is_dragging implies drawer.drag_start is non-null")
2. **Invariant violation hunt**: try to construct a sequence of operations that violates each invariant
3. **Partial-state recovery**: trace what happens if an operation fails halfway
4. **Save/load roundtrip**: serialize state to disk, reload, verify identical
5. **UndoRedo correctness**: every action's undo restores the *exact* prior state, not an approximation

#### Common state corruption bugs
- Dragging is canceled mid-drag (focus loss, ESC), but `is_dragging` flag stays true
- UndoRedo action's do/undo are not exact inverses (e.g., do applies clamp, undo doesn't restore unclamped value)
- A resource's properties are modified directly without going through UndoRedo, then the next undo restores the wrong "previous" state
- Plugin caches a value, the underlying source changes, plugin still serves stale cache
- Editor reload restores some state but not all (some fields default, some persist) → inconsistent
- Multiple inspectors view the same object; one modifies, the other shows stale data
- Saved settings have a key that the new version doesn't read → silently dropped on next save

#### Output
```markdown
## State corruption hunt — TKT-NNN

### Invariants identified
1. `drawer.is_dragging == (drawer.drag_start != null)`
2. `drawer.value reflects target.property` after sync
3. UndoRedo do/undo are exact inverses for `set_field_value`

### Invariant violation attempts
1. Press mouse down (set is_dragging=true, drag_start=mouse_pos), then click Esc:
   - Result: is_dragging stays true, drag_start stays old
   - VIOLATION FOUND. Severity: MEDIUM.
   - Fix: hook _input for Esc; reset both fields.

2. Modify target.property externally (e.g., another script), drawer doesn't refresh:
   - Result: drawer.value stale
   - VIOLATION FOUND. Severity: MEDIUM.
   - Fix: listen to target.property_list_changed; refresh on emit.

3. UndoRedo inverse check:
   - do: set_field_value(target, "x", 5.0)
   - undo: set_field_value(target, "x", 0.0)  ← original value
   - Verified: roundtrip restores ✓

### Save/load roundtrip
- Plugin has no persistent settings; N/A

### Verdict
2 medium-severity state corruption issues. Both fixable in this ticket.
```

---

## The Adversarial Hunt

A ritual the Bug Hunter Lead convenes for every XL ticket and at-discretion for L tickets. It is a focused 30+ minute session where the bug-hunting cohort attacks together.

### Format

1. **Setup (5 min)**: Bug Hunter Lead summarizes the ticket and the target system
2. **Solo phase (15 min)**: each role independently tries to break the system in their domain
   - Devil's Advocate: hostile inputs, hostile environment
   - Edge Case Hunter: corner cases, limits
   - Defect Pattern Specialist: catalog matches
   - Concurrency Bug Specialist: timing/ordering
   - State Corruption Specialist: invariants
3. **Combined phase (10 min)**: roles call out their findings; others build on them
   - "I can crash it if I do X" → "and if you do X then Y, what happens?"
4. **Reporting (5 min)**: consolidate findings into the Bug Hunt Report

### Why it works

Solo bug hunting tends to find the bugs each role is good at finding. Combined hunting finds the bugs that require combining two skills — concurrency + state corruption, pattern + edge case. The interaction matters.

### When to invoke
- Every XL ticket (mandatory)
- L tickets that touch sensitive areas
- Pre-release: every release candidate goes through one Adversarial Hunt
- After 3+ user-reported bugs against the plugin: re-hunt to clean house

---

## The Defect Catalog

`references/godot-4.6.2-defect-catalog.md` is the studio's curated list of recognized defect patterns. It is the Defect Pattern Specialist's working document. The catalog is read-mostly by other roles; it is maintained by the Specialist with help from the Studio Knowledge Curator.

The catalog grows over time. Every ticket that surfaces a novel defect pattern contributes an entry. The studio's defect-finding capability compounds with experience.

---

## Severity classification (for found bugs)

Bug Hunter Lead assigns severity to every found bug:

| Severity | Definition | Resolution |
|----------|-----------|------------|
| **P0** | Crash, data loss, security exposure | Block ticket sign-off; fix this ticket |
| **P1** | Functional break under common conditions | Block ticket sign-off; fix this ticket |
| **P2** | Functional break under edge conditions | Fix this ticket OR defer with DEF-NNN |
| **P3** | Behavioral issue, no functional break | Fix or defer at engineer's discretion |
| **P4** | Cosmetic, minor inconvenience | Almost always defer |

P0 and P1 cannot be deferred (per `deferred-work-tracker.md` "What CANNOT be deferred" list). P2 deferrals require explicit DEF-NNN with resurfacing condition. P3 and P4 deferrals are routine.

---

## Bug-finding metrics

Bug Hunter Lead reports per-ticket:
- Number of bugs found
- Severity distribution
- Found-by-catalog vs found-by-creative-attack ratio
- Bugs surfaced before vs after Phase 1.F (earlier is better)

If a ticket closes with **zero bugs found**, this is suspicious. Either the ticket was trivial (S/M) or the hunt was inadequate. The Bug Hunter Lead flags ticket-close-with-zero-findings on L/XL tickets for review.

---

## Integration with other roles

| Cooperating role | How |
|------------------|-----|
| Devil's Advocate | Participates in Adversarial Hunt; provides general adversarial perspective |
| Edge Case Hunter | Participates; specializes in input edges |
| QA Lead | Receives bug findings and incorporates into test plan |
| Crash Auditor | Crashes found are routed to Crash Auditor for null-safety analysis |
| Security Reviewer | Security-relevant findings routed to Security Reviewer |
| Reproduction Engineer | Found bugs require reliable reproduction (Reproduction Engineer assists if intermittent) |
| Studio Knowledge Curator | Novel defect patterns are added to catalog and recurring-defects.md |

---

## Why this protocol exists

The previous studio (v1.0) found bugs reactively — Quality Gate caught some, Honesty Auditor caught others, smoke tests caught the obvious. But many bug classes slipped through because no role was actively looking for them.

v2.0 makes bug hunting offensive, not defensive. The studio assumes bugs exist in every L/XL ticket and dedicates effort to finding them before sign-off. The Defect Catalog ensures the studio doesn't forget known patterns. The Adversarial Hunt ensures combined-skill bugs are found.

An L/XL ticket that closes without an active bug hunt is incomplete, regardless of how cleanly the code passes lint.
