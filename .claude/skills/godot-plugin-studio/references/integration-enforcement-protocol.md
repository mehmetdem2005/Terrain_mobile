# Integration Enforcement Protocol

When you write a new module, it must wire into the system at the moment of creation — not "later." When you add a public function, something must call it. When you add a signal, something must emit and something must listen (or the signal is documented as public API surface for external consumers). When you add a file, something must reference it.

The studio rejects dead-on-arrival code. This protocol is how that rejection happens.

This protocol is the active enforcement layer that pairs with the Semantic Dependency Engine (which catches conceptual dominoes) and the Impact Analysis Protocol (which catches symbol-level dominoes). Where those two find problems, this protocol prevents them at creation time.

---

## The new roles

### Role 1: Integration Engineer

#### Charter
You verify that every new module, function, signal, and file added in a ticket is wired into the system. You do not write the wiring; you verify it exists. If wiring is missing, you raise a blocker against the engineer who introduced the unwired item.

You operate in Phase 1.F (Execution) — as soon as a sub-task adds new code — and again in Phase 1.G (Integration) for final verification.

#### Activation triggers
- Phase 1.F sub-task closure (any new public surface added)
- Phase 1.G mandatory final pass
- New signal declared anywhere
- New file added to the plugin directory

#### Verification protocol

The protocol has four mandatory checks per new item:

##### Check 1: Forward wiring
For each new public function, public property, or public signal:
- Is there at least one caller / reader / connection in the codebase?
- If not, the item is orphan-on-arrival.

##### Check 2: Reverse wiring
For each new module (file):
- Is the module invoked/referenced from somewhere else?
- A new `helpers.gd` that nothing preloads is dead code.
- A new `EditorInspectorPlugin` subclass that the main plugin script never instantiates is dead code.

##### Check 3: Signal full-loop wiring
For each new signal:
- Is it emitted from at least one place?
- Is it listened (connected or awaited) from at least one place?
- **Exception**: if the signal is public API for external consumers (documented in README), it may have no internal listener — but this must be explicitly marked.

##### Check 4: Lifecycle wiring
For each new resource that requires lifecycle management:
- Is the resource initialized in the appropriate place (`_enter_tree`, `_ready`, etc.)?
- Is the resource cleaned up in the appropriate place (`_exit_tree`, etc.)?
- Is the lifecycle pair complete and symmetric?

#### Output: per-item wiring audit
```markdown
## Integration audit — TKT-NNN — Phase 1.G

### New module: addons/vector_field_inspector/keyboard_handler.gd
- Reverse wiring: ✓ instantiated in plugin.gd:34 (`var kb_handler := KeyboardHandler.new()`)
- Lifecycle: ✓ `kb_handler.detach()` called in plugin.gd:_exit_tree:67

### New public function: VectorFieldDrawer.commit_value(value, axis)
- Forward wiring: ✓ called from KeyboardHandler:_on_arrow_pressed:42
- Forward wiring: ✓ called from MouseHandler:_on_drag_end:88
- Forward wiring: ✓ called from drawer.gd:_on_text_submitted:115
- Total callers: 3

### New signal: VectorFieldDrawer.value_changed
- Emit sites: ✓ drawer.gd:118 (after commit_value)
- Listen sites: ✓ plugin.gd:45 (forwards to public surface)
- Marked as public API: yes — documented in README under "Signals"

### Verdict
All new public surface is wired. Zero orphans.
```

When wiring is missing:
```markdown
### New public function: VectorFieldDrawer.reset_to_default()
- Forward wiring: ✗ ZERO CALLERS
- Status: BLOCKED. Either:
  (a) wire this function from a meaningful caller, OR
  (b) make it private (rename to _reset_to_default), OR
  (c) remove it as not yet needed, OR
  (d) defer via DEF-NNN with documented intent to call it in a future ticket
- Cannot close ticket with this unwired public method.
```

### Role 2: Dead Code Hunter

#### Charter
You run the dead code scan and validate its output. Where the Integration Engineer focuses on **new** code being wired, you focus on **all** code — including code that may have become dead due to changes elsewhere in this ticket.

You consume the output of `scripts/dead-code-scan.sh` and turn it into actionable findings.

#### Activation triggers
- Phase 1.G mandatory final scan
- After any rename or signature change (existing callers may have been removed)
- Periodic studio-wide health scan (not per-ticket; scheduled)

#### Verification protocol

1. Run `scripts/dead-code-scan.sh` on the plugin directory
2. For each finding, classify:
   - **TRUE DEAD CODE**: never referenced, no documented future use → must be removed or deferred
   - **PUBLIC API DEAD INTERNALLY**: not called inside plugin, but exposed as public API for external code → mark as such in audit trail; not a defect
   - **FALSE POSITIVE**: scan missed a reference (rare, but happens with reflection-style code or scene-file references) → document why and add to scan exception list
3. For each true dead code finding, raise a blocker:
   - Engineer either removes the code, OR
   - Documents the future use (DEF-NNN created), OR
   - Marks as public API with explicit annotation

#### Anti-patterns flagged on sight
- "I'll wire it in the next ticket" without a DEF-NNN
- Private functions (leading underscore) with zero internal callers — these are *definitely* dead
- Files that were renamed but old files were not deleted
- preload paths that resolve but the loaded resource is never used
- Helper modules created "just in case"

#### Output
```markdown
## Dead code scan — TKT-NNN — Phase 1.G

### Scan command
bash scripts/dead-code-scan.sh addons/vector_field_inspector

### Findings classified
- TRUE DEAD CODE (3):
  - addons/vector_field_inspector/drawer.gd:_unused_helper() at line 220 — REMOVE
  - addons/vector_field_inspector/legacy/old_drawer.gd — entire file orphan; legacy from rewrite — REMOVE
  - addons/vector_field_inspector/utils.gd:get_default_step() — never called — REMOVE

- PUBLIC API DEAD INTERNALLY (1):
  - addons/vector_field_inspector/drawer.gd:value_changed signal — no internal listener; public API per README — KEEP, annotated

- FALSE POSITIVES (0): none

### Actions taken
- Removed 2 files and 2 functions (see commit diff)
- Annotated value_changed signal with `## @api: public — emitted for external listeners`

### Verdict
Codebase clean. Zero unjustified dead code.
```

### Role 3: Orphan Reference Hunter

#### Charter
The inverse of Dead Code Hunter. Where Dead Code Hunter finds code that nothing calls, you find calls/references to things that don't exist. This catches broken `preload` paths after renames, missing class references, signal connect to methods that no longer exist, etc.

#### Activation triggers
- Phase 1.G final pass
- After any rename in Phase 1.F
- Periodic studio-wide scan

#### Verification protocol

For each reference type, verify the target exists:

1. **`preload()` paths**: file exists at the path
2. **`load()` runtime paths**: file exists (if constant) or path is constructed from valid inputs
3. **`class_name` references**: the class is declared in the codebase or is a Godot built-in
4. **`connect()` to method names**: the method exists with compatible signature
5. **Scene tree paths** (`$Path/To/Node`, `get_node("...")`): the path resolves at runtime
6. **`@onready var x = $Path`**: the path is valid at `_ready` time
7. **`@export_node_path` references**: the type filter matches the assigned node

#### Output
```markdown
## Orphan reference scan — TKT-NNN — Phase 1.G

### Findings
- BROKEN PRELOAD (0): none
- MISSING CLASS REFERENCE (0): none
- METHOD CONNECT TO MISSING (0): none
- SCENE PATH ISSUES (0): none

### Verdict
All references resolve.
```

When something is broken:
```markdown
- BROKEN PRELOAD (1):
  - addons/foo/plugin.gd:12: preload("res://addons/foo/old_helper.gd")
  - target file does not exist (was renamed to helper.gd in this ticket)
  - BLOCKER raised against the engineer who renamed
```

---

## The "wire-as-you-build" discipline

The protocol enforces a specific working order during Phase 1.F. The engineer cannot create code in isolation and "wire it later." Each sub-task in the task breakdown (from Phase 1.D) must:

1. Create the new code
2. Wire it into its consumers (forward wiring)
3. Wire it from its callers (reverse wiring)
4. Verify wiring with `scripts/wiring-audit.sh`
5. Only then mark the sub-task complete

This prevents the failure mode where modules accumulate across multiple sub-tasks and integration is treated as a final-step cleanup. **Integration is part of every step.**

### Example: building a custom inspector plugin

**Bad workflow (rejected by protocol):**
```
ST-01: Create plugin.gd  — done, plugin.gd exists
ST-02: Create inspector.gd — done, inspector.gd exists
ST-03: Create drawer.gd — done, drawer.gd exists
ST-04: Wire everything together — discover plugin.gd never references inspector.gd; rewrite
```

This is the "tek seferde yapma" failure pattern.

**Required workflow:**
```
ST-01: Create plugin.gd with empty _enter_tree (no orphans yet)
ST-02: Create inspector.gd → IN THE SAME SUB-TASK, register it in plugin.gd:_enter_tree.
        Verify: plugin.gd references inspector.gd via add_inspector_plugin().
        Verify: _exit_tree calls remove_inspector_plugin().
        Sub-task closes only after wiring is verified.
ST-03: Create drawer.gd → IN THE SAME SUB-TASK, instantiate it from inspector.gd.
        Verify: inspector.gd creates a drawer when _parse_property fires.
        Verify: drawer's lifecycle is owned by inspector.
ST-04: Add public signal value_changed to drawer.gd → IN THE SAME SUB-TASK,
        either connect a listener inside the plugin, OR mark as public API.
```

Each sub-task closes with the new code already wired. There is no "wire it later" sub-task at the end.

---

## Wiring audit scripts

Two scripts support this protocol:

### `scripts/wiring-audit.sh`
Forward wiring scan. For each new public function/property/signal in the ticket diff, verify at least one usage exists.

### `scripts/reverse-wiring-audit.sh`
Reverse wiring scan. For each new file, verify it is referenced from elsewhere.

These run automatically in Phase 1.G and on-demand during Phase 1.F.

---

## Integration with v2.0 protocols

Integration enforcement does not stand alone. It cooperates with other v2.0 protocols:

| Protocol | What it provides | What integration enforcement does with it |
|----------|------------------|------------------------------------------|
| Semantic Dependency Engine | "If you add X, consider also Y" rules | Integration verifies the Y items are actually wired, not just considered |
| Impact Analysis | List of affected files after a change | Integration confirms each affected file is updated AND the new code is wired |
| Multi-phase execution | 7-phase structure | Integration runs at Phase 1.F (per sub-task) and 1.G (comprehensive) |
| Deferred Work Tracker | Mechanism to defer non-critical wiring | Integration accepts deferrals with DEF-NNN reference; rejects undocumented "I'll do it later" |
| Architectural Veto | Catches structural problems | Integration catches wiring problems; architectural problems are caught earlier in 1.E |

---

## What CANNOT be deferred (wiring edition)

These wiring issues block sign-off no matter what:

1. New public function with zero internal AND zero documented external callers
2. New file that nothing references (truly orphan)
3. `_enter_tree` that adds something with no matching `_exit_tree` removal
4. `connect()` with no `disconnect()` and no documented lifetime justification
5. New module that has no entry point invoked from the plugin's lifecycle

These all become blockers and require resolution in the current ticket. Deferred Work Tracker explicitly forbids deferring these (see `deferred-work-tracker.md` "What CANNOT be deferred" section).

---

## "Working code, broken integration" — the failure mode this prevents

Without this protocol, a plugin can:
- Parse cleanly (GDScript Language Specialist: PASS)
- Pass lint and format (Static Analysis Engineer: PASS)
- Verify all APIs exist (API Verification Specialist: PASS)
- Pass smoke test (QA Lead: PASS)
- ...but contain a function that is never called, a module that is never invoked, a signal that fires into the void.

The plugin "works" in the sense that nothing crashes. But the codebase is degraded — it carries weight without doing work. This is how technical debt accumulates silently.

The Integration Engineer + Dead Code Hunter + Orphan Reference Hunter trio prevents this. Every line of public surface earns its place by being wired, or it leaves the codebase.

---

## Verbose example — what a real audit looks like

For a real L ticket creating a vector field inspector:

```markdown
## Phase 1.G integration enforcement — TKT-007

### New files (4)
1. addons/vector_field_inspector/plugin.cfg
   - Referenced from: Godot editor (plugin discovery)
   - Status: ROOT — no internal referent needed; plugin.cfg IS the entry
   - VERDICT: ✓

2. addons/vector_field_inspector/plugin.gd
   - Referenced from: plugin.cfg "script=" field
   - VERDICT: ✓

3. addons/vector_field_inspector/inspector.gd
   - Instantiated at: plugin.gd:24 (`preload(".../inspector.gd").new()`)
   - Registered at: plugin.gd:25 (`add_inspector_plugin(...)`)
   - Unregistered at: plugin.gd:48 (`remove_inspector_plugin(...)`)
   - VERDICT: ✓ wired with lifecycle

4. addons/vector_field_inspector/drawer.gd
   - Instantiated at: inspector.gd:42 (within `_parse_property`)
   - Lifecycle: drawer attached to inspector's Control; freed when Control freed
   - VERDICT: ✓ wired with lifecycle

### New public functions (5)
1. InspectorPlugin._can_handle(object: Object) -> bool
   - Type: framework callback
   - Caller: Godot editor calls this for every inspected object
   - VERDICT: ✓ framework callback (no internal caller needed)

2. InspectorPlugin._parse_property(...)
   - Type: framework callback
   - VERDICT: ✓ framework callback

3. VectorFieldDrawer.commit_value(value: Vector3, axis: int = -1) -> void
   - Callers: drawer.gd:142 (mouse drag end), drawer.gd:177 (keyboard arrow), drawer.gd:199 (text submit)
   - VERDICT: ✓ wired

4. VectorFieldDrawer.reset_to_default() -> void
   - Callers: ZERO
   - VERDICT: ✗ BLOCKED. No callers. Either:
     (a) wire from a "reset" button if planned, OR
     (b) make it private (_reset_to_default), OR
     (c) remove if not yet needed.

   [Engineer addressed: removed function; reset functionality not in scope for this ticket. Logged as DEF-021 for future "reset to default" feature consideration.]

5. VectorFieldDrawer._on_focus_lost() -> void  (private callback)
   - Bound at: drawer.gd:28 (`focus_exited.connect(_on_focus_lost)`)
   - VERDICT: ✓ wired

### New signals (1)
1. VectorFieldDrawer.value_changed(value: Vector3)
   - Emit: drawer.gd:145 (after commit_value)
   - Listen: NONE internally
   - Public API: YES — documented in README under "Signals"
   - VERDICT: ✓ marked as public API surface

### Wiring audit script output
bash scripts/wiring-audit.sh addons/vector_field_inspector
> 0 orphan items found
> 0 unwired files
> 0 orphan signals (1 marked as public API)

### Dead code scan output
bash scripts/dead-code-scan.sh addons/vector_field_inspector
> 0 true dead code findings
> 1 deferred (DEF-021: reset_to_default for future)

### Orphan reference scan
> All preload paths resolve
> All class_name references valid
> All connect targets exist
> All @onready paths valid

### Final verdict
Integration enforcement: PASS
```

---

## When wiring requires architectural change

Sometimes during Phase 1.F, integration enforcement reveals that wiring as planned is awkward or impossible. Example:
- Engineer creates a Helper class with 5 utility functions
- Integration audit: 3 functions used in module A, 2 used in module B
- Realization: the "helper" is actually two separate concerns

The correct response: STOP Phase 1.F. Return to Phase 1.C with the finding. The architecture is amended (split helper into two modules). Phase 1.D is amended (sub-tasks reorganized). Then Phase 1.F resumes.

This is correct and protocol-compliant. The wrong response would be to grit teeth and ship the awkward helper.

---

End of Integration Enforcement Protocol. Combined with Semantic Dependency Engine, Impact Analysis Protocol, and Deferred Work Tracker, this forms the studio's complete "no code ships dead, no work ships forgotten" guarantee.
