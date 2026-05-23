# Architectural Quality Audit

This is the studio's answer to "temiz kod" — clean code in the sense the engineer meant it: **professional, non-spaghetti, well-conceived**. Not "short." Not "few parameters." A 200-line function can be clean if it expresses one coherent thought; a 20-line function can be spaghetti if it tangles three concerns.

This protocol rejects numerical thresholds (function length limits, parameter counts, complexity scores) as the primary measure of code quality. They are weak proxies that produce amateurish reviews. Instead, this protocol enforces **qualitative criteria** evaluated by trained eyes.

The Clean Code Officer and Architectural Quality Auditor roles introduced here are not lint runners. They are senior code reviewers.

---

## Why no numeric thresholds

A previous draft of this protocol included rules like "max 50 lines per function" and "max 4 parameters." On review, the user pointed out (correctly) that these are amateur metrics. Real senior engineers don't reject code by counting lines. They reject code by reading it and seeing whether it *makes sense*.

Specifically:
- A function can be long because the work is genuinely long and breaking it up would scatter the logic. Reading a 200-line linear function is often easier than chasing five 40-line helpers.
- A function can have many parameters because it genuinely operates on many inputs, and tucking them into a struct just hides the truth.
- Complexity scores measure branching, but branching is sometimes the simplest expression of the domain logic.

What matters is **whether the code is professional**: does it express its intent clearly, avoid tangling concerns, and stay maintainable?

The Clean Code Officer evaluates this. There is no formula.

---

## The new roles

### Role 1: Clean Code Officer

#### Charter
You evaluate whether the code shipped from this studio reads like professional engineering work or like an amateur copying patterns. You do not run a linter; you read the code and form a judgment. Your judgment is grounded in specific, named anti-patterns — but the application requires taste.

You are the equivalent of a senior code reviewer at a real AAA studio. Your job is to demand that the studio's output is something a senior engineer would be proud to have written.

#### Activation triggers
- Every M, L, XL ticket — after Phase 1.F, before Phase 1.G's other audits
- Refactor tickets — primary evaluator
- Audit tickets — collaborates with Architectural Debt Auditor

#### Verification protocol

Walk the code in the ticket and evaluate against the **professional code criteria** below. For each criterion: SOLID / WEAK / FAIL. Aggregate is the verdict.

You do not run scripts. You read. You apply judgment. You write findings in plain language — not "function too long" but "the `update_state` function is doing three things at once: validating input, mutating state, and emitting notifications. A senior engineer would split these or, if keeping them together, restructure to make the three phases visible as labeled sections."

#### Output: Clean Code Review
```markdown
# Clean Code Review — TKT-NNN

## Files reviewed
- addons/vector_field_inspector/plugin.gd
- addons/vector_field_inspector/drawer.gd
- addons/vector_field_inspector/inspector.gd

## Per-criterion verdict
- Conceptual cohesion: SOLID / WEAK / FAIL — [findings]
- Coupling discipline: SOLID / WEAK / FAIL — [findings]
- Naming honesty: SOLID / WEAK / FAIL — [findings]
- Concept layering: SOLID / WEAK / FAIL — [findings]
- Reversibility: SOLID / WEAK / FAIL — [findings]
- Testability: SOLID / WEAK / FAIL — [findings]
- Documentation alignment: SOLID / WEAK / FAIL — [findings]

## Specific findings
[itemized issues with file:line references, in plain language]

## Verdict
PASS | PASS_WITH_CONDITIONS | FAIL
```

---

### Role 2: Architectural Quality Auditor

#### Charter
Where the Clean Code Officer reads files, you read **the relationships between files**. You evaluate how the system holds together at the module level. Spaghetti at the module level is often invisible when you read one file at a time — you have to see the call graph, the data flow, the lifecycle.

You enforce the **Clean Architecture Manifesto** (`clean-architecture-manifesto.md`) — the five binding invariants and the "doesn't fall apart when it grows" test. Where the spaghetti catalog tells engineers what to avoid, the manifesto tells them what to do; you verify they did it.

You collaborate with the Architecture Veto Officer (who evaluates architecture at design time). You evaluate the architecture *as built* — after Phase 1.F, the architecture in code may have drifted from the architecture in the design doc. You catch this.

#### Activation triggers
- Phase 1.G of L and XL tickets
- Audit and refactor tickets — primary evaluator with Architectural Debt Auditor
- After Phase 1.F to verify the built code matches the approved architecture

#### Verification protocol

Evaluate the system at the module level:

1. **Call graph clarity** — Trace which modules call which. Is the graph a tree (good), a layered structure (good), or a tangle (bad)?
2. **Data ownership** — For each piece of state, identify the single module that owns it. Is ownership clear, or does state live in multiple places?
3. **Lifecycle threading** — Trace what happens from plugin enable → operation → plugin disable. Is the path clear?
4. **Boundary violations** — Does any module reach into another's internals? Does UI code know about persistence? Does state code know about display?
5. **Conceptual integrity** — Do module names match what they actually do? Or have modules drifted from their declared purposes?

#### Output: Architectural Quality Audit
```markdown
# Architectural Quality Audit — TKT-NNN

## Module-level call graph
[ASCII or prose diagram of which module calls which]

## Data ownership map
- VectorFieldDrawer owns: drag state, displayed value
- Inspector owns: drawer instances per inspected object
- Plugin owns: lifecycle, registration

## Lifecycle thread
[walk through: plugin enables → inspector instantiates → drawer attaches → user interacts → drawer commits → undo records → plugin disables]

## Boundary checks
- UI ↔ Persistence: clean — drawer doesn't know about save/load
- UI ↔ State: clean — drawer holds presentation state only; canonical state lives in target object
- Plugin ↔ Inspector: clean — plugin instantiates and registers, doesn't touch inspector internals

## Conceptual integrity
- "VectorFieldDrawer" — name matches: handles vector field UI exclusively ✓
- "Inspector" — name slightly broad; this is actually "VectorFieldInspectorPlugin" but file is just inspector.gd ⚠ MINOR

## Drift from design doc
- Design doc (Phase 1.C) said inspector would have a "_refresh_all" method; not present in code
- Reason: refresh is now handled via signal subscription instead — simpler and event-driven
- Drift is improvement; ADR recorded retroactively

## Verdict
PASS — architectural quality matches design intent; minor naming nit noted.
```

---

## Professional code criteria

These are the criteria the Clean Code Officer evaluates. They are described qualitatively, with examples of SOLID, WEAK, and FAIL for each.

### Criterion 1: Conceptual cohesion

**What it asks:** does each function/class express one coherent idea?

**SOLID example:**
```gdscript
func commit_value(value: Vector3, axis: int = -1) -> void:
    var old := target.get(property_name)
    var new := _apply_axis(old, value, axis) if axis >= 0 else value
    _record_undo_action("Set Vector Field", target, property_name, old, new)
    target.set(property_name, new)
    value_changed.emit(new)
```
This function does one thing: commit a value change. The steps (compute, record, apply, notify) are aspects of the same single thought.

**WEAK example:**
```gdscript
func update():
    refresh_display()
    if has_pending_save:
        save_to_disk()
        notify_user()
    process_input_queue()
    update_telemetry()
```
This function does several unrelated things. The name "update" doesn't tell you what; it's a junk drawer. Either split into focused functions, OR rename to honestly reflect "do everything pending" if that is the actual intent.

**FAIL example:**
```gdscript
func _on_thing_happened(event):
    # parse the event
    var parts = event.split(",")
    if parts[0] == "click":
        # do click handling
        if button == 1:
            # left click
            ...
            # also save settings here for some reason
            FileAccess.open(...)
        elif button == 2:
            # right click — different concept entirely
            ...
    elif parts[0] == "key":
        # key handling — entirely different concern
        ...
    # also update some unrelated UI element
    label.text = str(counter)
    counter += 1
```
This tangles input parsing, event dispatch, business logic, persistence, and UI update. It's spaghetti.

**Clean Code Officer's job:** identify FAIL and WEAK cases; recommend the split or restructuring.

---

### Criterion 2: Coupling discipline

**What it asks:** does each module's connection to others go through a clean, named interface, or does it reach into internals?

**SOLID:**
```gdscript
# inspector.gd
func _parse_property(object, type, name, ...) -> bool:
    if type != TYPE_VECTOR3: return false
    var drawer = VectorFieldDrawer.new()
    drawer.target = object
    drawer.property_name = name
    add_custom_control(drawer)
    return true
```
The inspector hands the drawer two pieces of context (target, property_name) through its public surface. Drawer doesn't need to know about inspector internals.

**WEAK:**
```gdscript
var drawer = VectorFieldDrawer.new()
drawer.parent_inspector = self
drawer.editor_settings_ref = EditorInterface.get_editor_settings()
drawer.scene_root = EditorInterface.get_edited_scene_root()
```
Drawer is given references to several environment pieces. Now it can do anything. Surface is wide and unclear. The drawer's contract with the world is "trust me with all this stuff."

**FAIL:**
```gdscript
drawer.inspector = self  # drawer can now call any inspector method
drawer.plugin_ref = get_parent()  # drawer can now reach into plugin internals
```
Drawer has back-references to its environment and can call arbitrary methods. Coupling is invisible — looking at drawer in isolation doesn't tell you what it depends on.

**Clean Code Officer's job:** identify back-references, wide environment passing, and "manager" or "context" objects that smuggle dependencies.

---

### Criterion 3: Naming honesty

**What it asks:** does each name describe what the thing actually does?

**SOLID:**
- `commit_value(value, axis)` — commits a value, optionally on a specific axis
- `_on_drag_ended` — handler for drag-ended events
- `target.get(property_name)` — clearly accessing a property on a target

**WEAK:**
- `update()` — what does it update?
- `process()` — process what?
- `handle_event(event)` — handle how?
- `do_stuff()` — joke entry; would be FAIL in real code

**FAIL:**
- `commit_value(v)` that also writes to disk and updates UI — the name promises one thing, function does three
- `is_valid` that returns true even when state is inconsistent (lying boolean)
- `temporary_helper` that has lived for two years
- `total` that is actually a partial sum

**Clean Code Officer's job:** read names; verify they match behavior. Lying names are worse than ugly code — they erode trust.

---

### Criterion 4: Concept layering

**What it asks:** does code stay within its layer, or do concerns leak across layers?

Layers in a typical plugin:
1. **Lifecycle** — plugin.gd; handles enable/disable
2. **Subsystem** — inspector.gd; integrates with Godot's inspector API
3. **UI** — drawer.gd; visual presentation
4. **Domain logic** — vector field math, helpers
5. **Persistence** — save/load (if any)

**SOLID:**
- UI layer (drawer.gd) calls domain logic (vector_math.gd) to compute values
- Domain logic returns values; UI displays them
- Persistence reads/writes; subsystem invokes persistence at appropriate times

**WEAK:**
- Domain logic (vector_math.gd) checks `Engine.is_editor_hint()` — domain code shouldn't know about editor context
- UI directly calls persistence — UI shouldn't write files

**FAIL:**
- Persistence layer queries the UI for current state — backward dependency
- Domain logic emits UI events — domain shouldn't know about UI
- Lifecycle code does math — wrong place

**Clean Code Officer's job:** identify cross-layer violations. The most common is UI knowing too much about persistence, or domain logic having UI awareness.

---

### Criterion 5: Reversibility

**What it asks:** how hard is it to undo or change this design decision later?

**SOLID:**
- Module exposes a small public surface; internal changes don't ripple
- Module can be replaced with an alternative implementation
- Removing the module touches a few well-defined call sites

**WEAK:**
- Module's internals are accessed from outside; changing internals breaks callers
- Module is referenced from many places; removing requires touching many files
- Module has many public methods; changing any of them is a breaking change

**FAIL:**
- Module is referenced via globals or singletons; "everyone" depends on it
- Module's data structures are exposed to callers who read them directly
- Removing the module requires rewriting half the codebase

**Clean Code Officer's job:** ask "if we wanted to change this in six months, how painful would it be?" If the answer is "extensive surgery," coupling is too tight.

---

### Criterion 6: Testability

**What it asks:** can pieces of this code be tested in isolation, or is everything entangled with the editor / scene tree / signal chains?

**SOLID:**
- Pure functions for domain logic (no global state, no side effects, no editor dependencies)
- UI logic separated from data logic; data logic testable without the UI
- External dependencies (file I/O, editor APIs) injected, not hardcoded

**WEAK:**
- Logic mixed with UI such that testing requires instantiating the UI
- Editor APIs called from places where they could have been avoided (e.g., a math utility that reads EditorSettings for no reason)

**FAIL:**
- Logic depends on `EditorInterface` everywhere; cannot run without a full editor environment
- Functions have side effects buried in them (write to disk, emit signals) that make unit testing impossible

**Clean Code Officer's job:** identify code that *could* be testable but isn't because of unnecessary entanglement.

---

### Criterion 7: Documentation alignment

**What it asks:** does the documentation reflect the code, or is it aspirational?

**SOLID:**
- README describes what the plugin does, accurately
- Function docstrings (where present) describe actual behavior
- Examples in docs work as written

**WEAK:**
- README describes a feature that exists but is harder to use than described
- Docstrings exist for some functions and not others

**FAIL:**
- README promises a feature that doesn't exist
- Docstrings describe an older behavior that has changed
- Examples in docs error out when copy-pasted

**Clean Code Officer's job:** spot-check documentation against code. If they disagree, code is the truth — but the documentation must be updated, or removed if no longer applicable.

---

## What about long functions?

A long function is not automatically bad. The Clean Code Officer's test is:

1. **Read the whole function.** Does it express a single coherent thought?
2. **If yes**: the length is fine. Maintenance is by reading top-to-bottom — easier than chasing helpers.
3. **If no**: it tangles concerns. Length didn't cause this; it just made it visible. Split by concern.

A 200-line function that walks linearly through a complex algorithm in one logical thread is often better than five 40-line functions that fragment the same algorithm.

A 30-line function that does input validation, business logic, UI update, AND error handling all in one place is spaghetti at 30 lines.

---

## What about many parameters?

A function with 7 parameters is not automatically bad. The Clean Code Officer's test:

1. **Are the parameters genuinely independent?** If yes, 7 might be necessary.
2. **Do they always travel together?** If yes, group them into a struct/Dictionary/Resource.
3. **Do some of them constrain or modify others?** Consider whether the API has a hidden state machine that should be made explicit.

The point is: count of parameters is a symptom worth investigating, not a defect. The Clean Code Officer investigates; doesn't just count.

---

## What about deeply nested code?

Deep nesting (5+ levels) is usually a smell, but not always:

- Nested `if` checking preconditions, then loop, then nested condition — this is often fine and would be uglier with guard clauses pulled out
- Nested `for x in: for y in: for z in:` for 3D processing — sometimes the cleanest way to express the algorithm
- Deeply nested callbacks (signal handlers within signal handlers) — usually a real problem

The Clean Code Officer judges. Counting indents is not the test.

---

## The "would a senior engineer be proud of this?" question

At the end of the review, the Clean Code Officer asks themselves: **would a senior engineer at a real AAA studio be proud to have written this?**

- If yes: PASS
- If "mostly, with reservations": PASS_WITH_CONDITIONS, with the reservations named
- If "no, this is amateur work": FAIL

The reservations and FAIL findings are specific. "I would be uncomfortable with X" is not a finding; "I would be uncomfortable with X because the inspector.gd's `_parse_property` is doing two unrelated things — type filtering AND drawer setup — these should be separate functions" is.

---

## Collaboration with the Architecture Veto Officer

These two roles overlap but are distinct:

| Role | When | Scope |
|------|------|-------|
| Architecture Veto Officer | Phase 1.E (design time, pre-code) | Evaluates the design doc |
| Clean Code Officer | Phase 1.G (post-code, pre-gate) | Evaluates the code |
| Architectural Quality Auditor | Phase 1.G (post-code, pre-gate) | Evaluates the module-level system as built |

The Architecture Veto Officer says "this design is fit to implement." The Clean Code Officer + Architectural Quality Auditor say "this implementation is fit to ship."

A ticket where the design was approved but the implementation drifted into spaghetti — common failure mode — is caught here.

---

## When a fail happens

If the Clean Code Officer FAILs a ticket, the engineer's options are:

1. **Refactor** — address the named findings; submit for re-review
2. **Justify** — explain why the apparent issue is actually fine (sometimes the Officer is wrong; this is a real conversation, not a rubber stamp)
3. **Defer** — for non-critical findings, document via DEF-NNN; resurface in a follow-up cleanup ticket

Critical findings (lying names, concept tangles in core functions) cannot be deferred — these become real blockers.

---

## What this protocol does NOT do

- Does not run linters (gdlint does that; this is layered on top)
- Does not enforce numeric thresholds (no max-lines, no max-params, no complexity score)
- Does not require specific patterns (single-responsibility, DRY, SOLID names are descriptive guidelines, not laws)
- Does not block on style preferences (the Coding Standards Enforcer handles formatting)

This protocol enforces **professional judgment** about whether code reads as senior-engineer work.

---

## Why qualitative matters

The user pointed out, correctly: numeric thresholds produce amateurish reviews. A studio that rejects code because "function is 51 lines" is performing theater. A studio that rejects code because "this function ties together input parsing, business logic, and UI update in a way that will be hard to maintain" is doing real review.

The Clean Code Officer is the senior reviewer the studio needs. The Architectural Quality Auditor is the senior architect the studio needs at code-review time.

Together, they ensure the studio's output is professional engineering, not pattern-matched amateur work.
