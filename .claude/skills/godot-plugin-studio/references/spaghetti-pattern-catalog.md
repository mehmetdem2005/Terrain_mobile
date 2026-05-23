# Spaghetti and Amateur-Code Patterns

Companion catalog for `architectural-quality-audit.md`. The Clean Code Officer and Architectural Quality Auditor consult this when forming judgments. It is a library of recognized anti-patterns with concrete examples — what amateur code looks like, why it's bad, what professional code does instead.

Unlike `godot-4.6.2-defect-catalog.md` (which catches *functional bugs*), this catalog catches *quality bugs*: code that works but reveals amateur thinking. Functionally correct, but spaghetti.

---

## Tier 1 — Cardinal sins (block sign-off on detection)

### S-001: The God Module
**Pattern**: One module/file does the work of three or more conceptually distinct modules. Usually 500+ lines, but length is the symptom, not the disease.

**Example** (FAIL):
```gdscript
# plugin.gd (450 lines)
@tool
extends EditorPlugin

# Lifecycle management
func _enter_tree(): ...

# Inspector hooks (should be in inspector.gd)
func _parse_property(): ...

# Custom drawing (should be in drawer.gd)
func _draw_vector_field(...): ...

# Persistence (should be in settings.gd)
func save_settings(): ...
func load_settings(): ...

# Math utilities (should be in math.gd)
func compute_field_intensity(...): ...
func interpolate_vectors(...): ...

# Network (should be in sync.gd or shouldn't exist)
func sync_to_server(...): ...

# Theme integration (should be in theme.gd)
func get_themed_color(...): ...
```

**Why bad**: every concept must be loaded into your head to read any one function. Changes to one concern risk breaking another. Tests cannot be written.

**Professional**: split into the named modules. Plugin entry stays under 100 lines and only handles lifecycle.

**Detection**: see a file approaching 500 lines? Read the function names. If they fall into 3+ unrelated groups, this is the God Module.

---

### S-002: The Lying Name
**Pattern**: Function/variable/class name that does not match its behavior.

**Examples** (FAIL):
```gdscript
# Function called "validate" that also mutates
func validate_input(data):
    if not data.has("x"):
        data["x"] = 0   # ← mutation, not validation
    return data["x"] >= 0

# Property called "is_ready" that returns true even when init is incomplete  
var is_ready: bool:
    get: return _enter_tree_called   # ← but resources may still be loading

# Class called "Cache" that doesn't cache (re-computes every call)
class ResultCache:
    func get_result(key):
        return _compute(key)   # ← no caching

# Variable called "temp" that's been there for 2 years
var temp_solution = ...   # ← it's the permanent solution now
```

**Why bad**: every future reader is misled. Trust in the codebase erodes. Bugs hide because names create false expectations.

**Professional**: name expresses behavior. If `validate_input` mutates, it's `normalize_input`. If a cache doesn't cache, it's `result_factory`.

---

### S-003: The Wide Environment
**Pattern**: Function or class given references to many environmental concepts it doesn't strictly need, "in case it might want them."

**Example** (FAIL):
```gdscript
# Drawer is given the world
class VectorFieldDrawer extends Control:
    var inspector_ref            # why does drawer need inspector?
    var plugin_ref               # why does drawer need plugin?
    var editor_settings          # why does drawer need settings?
    var scene_root               # why does drawer need scene?
    var theme_ref                # could ask the engine
    var undo_redo_manager        # could be fetched on demand
```

**Why bad**: drawer can now do anything. Its contract is "trust me with everything." Coupling is invisible — reading drawer in isolation doesn't tell you what it depends on.

**Professional**: drawer is given exactly what it needs. Probably 2-3 things: the target object, the property name, the commit callback (or signal).

---

### S-004: The Manager God Object
**Pattern**: A class named `*Manager`, `*Controller`, `*Coordinator`, or similar generic title that everyone calls into.

**Example** (FAIL):
```gdscript
# VectorFieldManager — a typical name for a god object
class VectorFieldManager extends Node:
    func get_value(target, prop): ...
    func set_value(target, prop, value): ...
    func validate(target, prop): ...
    func get_history(target, prop): ...
    func undo(target, prop): ...
    func subscribe(target, prop, callback): ...
    func render_to_inspector(target, prop): ...
    # ... 30 more methods
```

**Why bad**: the name "Manager" tells you nothing about what it does. It accumulates methods until it does "everything." Removing the Manager requires touching every caller.

**Professional**: methods are split by what they actually do. `VectorFieldStore` (state), `VectorFieldValidator` (validation), `VectorFieldHistory` (undo), `VectorFieldRenderer` (display). Each has a clear, narrow contract.

---

### S-005: The Tangled Function
**Pattern**: One function that does input parsing AND business logic AND persistence AND UI update.

**Example** (FAIL):
```gdscript
func _on_save_button_pressed():
    # input parsing
    var input_text = name_field.text
    var parts = input_text.split("/")
    
    # validation
    if parts.size() < 2:
        error_label.text = "Invalid format"   # ← UI update
        return
    
    # business logic
    var first_name = parts[0].strip_edges()
    var last_name = parts[1].strip_edges()
    var person = Person.new(first_name, last_name)
    
    # persistence
    var file = FileAccess.open("user://people.json", FileAccess.WRITE)
    file.store_string(JSON.stringify(person.to_dict()))
    file.close()
    
    # UI update
    list_view.add_item(input_text)
    name_field.text = ""
    notification_label.text = "Saved"
    
    # analytics (because why not)
    save_count += 1
    if save_count % 10 == 0:
        notification_label.text += " (you've saved 10 times!)"
```

**Why bad**: changing any concern (input format, validation, storage backend, UI) requires reading the whole function and risking breakage to other concerns.

**Professional**:
```gdscript
func _on_save_button_pressed():
    var parsed = NameParser.parse(name_field.text)
    if not parsed.ok:
        _show_error(parsed.error)
        return
    var person = Person.new(parsed.first, parsed.last)
    PersonStore.save(person)
    _refresh_list()
    _clear_form()
```
Each concern is in its own place. The handler is a thin coordinator.

---

### S-006: The Forever Temporary
**Pattern**: Code marked "temporary", "hack", "fix later", "TODO" that has lived for months or years.

**Detection**: `grep -rn "TODO\|FIXME\|HACK\|XXX\|temp\|temporary" plugin/` — every match needs a ticket reference (DEF-NNN) or a justification.

**Why bad**: every reader sees a TODO and either (a) ignores it (training the team to ignore TODOs) or (b) wastes time wondering whether to act on it. Either way, the comment is lying about urgency.

**Professional**: every TODO has a DEF-NNN reference. Without a reference, either fix it or remove the comment.

---

## Tier 2 — Smells (raise findings, often need addressing)

### S-007: The Speculative General
**Pattern**: Abstraction layer with one concrete implementation, justified as "in case we want to add more later."

**Example** (WEAK):
```gdscript
# IVectorFieldRenderer interface
class IVectorFieldRenderer:
    func render(target, value): pass

class DefaultVectorFieldRenderer extends IVectorFieldRenderer:
    func render(target, value): ...

# Only one renderer exists. The interface buys nothing.
```

**Why bad**: indirection cost without present-day benefit. Future "different renderer" rarely materializes.

**Professional**: collapse to the concrete class. If a second implementation is ever needed, extract the interface then. **YAGNI** — but the Clean Code Officer applies it with judgment, not as dogma.

---

### S-008: The Hidden State Machine
**Pattern**: Class with several boolean flags that constrain each other implicitly.

**Example** (WEAK):
```gdscript
class Drawer:
    var is_dragging = false
    var is_editing_text = false
    var is_keyboard_focused = false
    var pending_commit = false
    var is_disabled = false
    
    # ... lots of methods that check combinations of these flags
    func handle_input(event):
        if is_dragging and not is_disabled:
            ...
        elif is_editing_text and not is_dragging:
            ...
        elif is_keyboard_focused and not is_editing_text and not is_dragging:
            ...
```

**Why bad**: the actual state machine is implicit. Invalid combinations are possible (`is_dragging=true, is_editing_text=true` shouldn't be valid). Bugs hide in the combinatorial space.

**Professional**: make the state machine explicit:
```gdscript
enum State { IDLE, DRAGGING, EDITING_TEXT, KEYBOARD_FOCUSED, DISABLED }
var state: State = State.IDLE
```
Now invalid combinations are impossible. Transitions are explicit.

---

### S-009: The Configuration Cascade
**Pattern**: Function takes a configuration object that has many fields, most of which are unused for any given call.

**Example** (WEAK):
```gdscript
func create_drawer(config: Dictionary) -> VectorFieldDrawer:
    # config can have: target, property, range_min, range_max, step, axis_count,
    # use_keyboard, use_mouse, theme_override, undo_action_name, refresh_signal,
    # commit_callback, validate_callback, format_string, locale, ...
    
    var drawer = VectorFieldDrawer.new()
    drawer.target = config.get("target")
    drawer.property = config.get("property")
    # ... 20 more lines of get-with-default
    return drawer
```

**Why bad**: callers pass mostly-empty dictionaries; defaults are scattered; type safety is gone (Dictionary[String, Variant]).

**Professional**: required parameters as positional, optional as named with defaults:
```gdscript
func create_drawer(target: Object, property: String, 
                   range: Vector2 = Vector2(-INF, INF),
                   commit_callback: Callable = Callable()) -> VectorFieldDrawer:
    ...
```

---

### S-010: The Back-Reference
**Pattern**: Child object holds a reference back to its parent so it can call parent methods.

**Example** (WEAK):
```gdscript
class Drawer:
    var parent_inspector  # back-reference
    func commit(value):
        parent_inspector.notify_drawer_committed(self, value)  # reaches up
```

**Why bad**: cycle. Drawer's lifetime is tied to inspector's lifetime — but the parent reference can outlive valid state. Also, drawer now depends on inspector having `notify_drawer_committed`.

**Professional**: use signal instead:
```gdscript
class Drawer:
    signal committed(value)
    func commit(value):
        committed.emit(value)

# Inspector connects to drawer.committed when creating the drawer.
```
No back-reference; clean event flow upward.

---

### S-011: The Stringly-Typed API
**Pattern**: Function signatures using `String` where an enum or typed value would be clearer.

**Example** (WEAK):
```gdscript
func set_mode(mode_name: String):
    if mode_name == "idle":
        ...
    elif mode_name == "drag":
        ...
    elif mode_name == "edit":
        ...

# Caller:
set_mode("drag")   # easy to typo as "darg" — silent fail
```

**Why bad**: typos at call sites pass through silently. No autocomplete. No refactoring tool can rename safely.

**Professional**:
```gdscript
enum Mode { IDLE, DRAG, EDIT }
func set_mode(mode: Mode):
    match mode:
        Mode.IDLE: ...
        Mode.DRAG: ...
        Mode.EDIT: ...
```

---

### S-012: The Reaching Into
**Pattern**: Module A reads/writes module B's internal state directly instead of going through B's methods.

**Example** (WEAK):
```gdscript
# In plugin.gd
inspector._cached_drawers.clear()  # plugin reaching into inspector internals
drawer._pending_value = some_value  # plugin reaching into drawer internals
```

**Why bad**: changing inspector's or drawer's internals breaks plugin. Encapsulation lost.

**Professional**: inspector and drawer expose methods for what plugin needs to do. `inspector.reset_drawers()`, `drawer.set_pending_value(value)`. Plugin uses the methods.

---

### S-013: The Boolean Trap
**Pattern**: Function with multiple boolean parameters, callers can't tell at call site what they do.

**Example** (WEAK):
```gdscript
func commit(value, true, false, true, false)
```
The reader has no idea what those booleans mean. Compare:
```gdscript
func commit(value, animated=false, validate=true, undo=true, notify=false)
commit(value, animated=true, validate=false, undo=true, notify=false)
```
Better, but still hides intent. Best: factor into separate methods:
```gdscript
commit_validated(value)
commit_silent(value)
commit_animated(value)
```

---

### S-014: The Magic Cluster
**Pattern**: Constants without names, used directly in code.

**Example** (WEAK):
```gdscript
if event.position.x > 442 and event.position.x < 642:
    if drawer.size > 0.7853:   # what is 0.7853?
        commit_value(value * 1.4142)   # and 1.4142?
```

**Why bad**: reader has no idea what 442, 0.7853, 1.4142 mean. (They might be pixel-X bounds, π/4 radians, √2.)

**Professional**:
```gdscript
const DRAWER_X_MIN = 442
const DRAWER_X_MAX = 642
const ANGLE_THRESHOLD_RAD = PI / 4
const SQRT_2 = sqrt(2.0)
```
Or better, derive: `if event.position.x >= drawer.position.x and event.position.x <= drawer.position.x + drawer.size.x:` — no magic.

---

### S-015: The Comment Lying
**Pattern**: Comment that describes what the code used to do, not what it does now.

**Example** (WEAK):
```gdscript
# Compute the average of the input values
func compute_metric(values):
    return values.max()   # ← actually returns max, not average
```

**Why bad**: comments outrank code in the reader's first read. Wrong comment misleads. (Code is the truth; comment lies.)

**Professional**: either fix the comment or delete it. If the function's behavior is obvious from the name (`compute_max`), no comment needed.

---

## Tier 3 — Style smells (low severity, address opportunistically)

### S-016: Unnecessary abbreviation
- `cnt` instead of `count`
- `idx` instead of `index`
- `cfg` instead of `config`
- `tmp` instead of `temporary` (which is usually itself the wrong name; see S-006)

Modern editors don't need 3-character names. Spell it out.

### S-017: Inconsistent return shape
- One branch returns a `Dictionary`; another returns `null`; another returns a `String`
- Callers can't write type-safe code; must guard every result with type checks

Pick one return shape and stick with it. Use `Result`-like wrapping if you need success/failure (`{ok: true, value: ...}` or `{ok: false, error: ...}`).

### S-018: Print statements in production
Sign of debugging not cleaned up. Either remove or convert to `push_error` / `push_warning` with appropriate condition.

### S-019: Unnecessary `else` after `return`
```gdscript
# Not ideal:
if condition:
    return value_a
else:
    return value_b

# Better:
if condition:
    return value_a
return value_b
```
Saves a level of nesting; reads as "early return, then default."

### S-020: Variable defined far from use
A variable declared at top of function but first used 80 lines later. Move it to where it's first needed.

---

## Tier 4 — Architectural smells (module-level, caught by Architectural Quality Auditor)

### A-001: The Centralized Knowledge Module
Module that knows about every other module ("knows where everything is"). Becomes the bottleneck for any change.

### A-002: The Pass-Through Layer
Module whose only job is to forward calls to another module. Adds indirection without value.

### A-003: The Concept Sprawl
Plugin started as "vector field editor"; now also handles texture import, particle systems, and shader debugging. Scope crept; module boundaries didn't follow.

### A-004: The Circular Reference
Module A imports module B; module B imports module A. Either through preloads, signals, or shared resources. Cycle should be broken (extract common into a third module, or use signals to invert one direction).

### A-005: The Hidden Coupling Through Globals
Modules don't reference each other directly, but both modify a shared singleton. The dependency is invisible until you trace through the singleton.

### A-006: The Dual Ownership
Two modules both believe they own a piece of state. Both modify it. Race conditions, inconsistent reads.

### A-007: The Implicit Order
Module A must initialize before module B. Nothing in the code expresses this; if someone reorders init, things break in non-obvious ways.

### A-008: The Layer Leak
Higher-level concepts referenced from lower-level code. Math library calls UI. Persistence reads from inspector state. Up-references break the layering.

---

## Detection workflow

When the Clean Code Officer reviews:

1. **Open each modified file.** Read top-to-bottom.
2. **For each function**: name honest? cohesive? — flag S-001, S-002, S-005.
3. **For each class**: focused? coupling clean? — flag S-001, S-003, S-004, S-010.
4. **Look for patterns from Tier 1.** These are blockers.
5. **Look for patterns from Tier 2.** These are findings to discuss with the engineer.
6. **Spot-check Tier 3.** Address opportunistically.

When the Architectural Quality Auditor reviews:

1. **Map the call graph.** Tree? Layered? Tangle?
2. **Trace data ownership.** Single owner per state, or distributed?
3. **Walk the lifecycle.** Clear path? Or surprises?
4. **Check for A-001 through A-008.** These are architectural smells.

---

## When findings are wrong

Sometimes the Clean Code Officer's reading is wrong. The engineer may have a real reason for the apparent smell:

- "Yes, this function is long, but it's a linear state machine and splitting it would scatter the logic"
- "Yes, this name looks vague, but it matches the domain term the user community uses"
- "Yes, this looks like the God Module pattern, but these methods are genuinely related and splitting would create artificial boundaries"

These conversations happen. The Clean Code Officer isn't infallible; they apply judgment. If the engineer's justification is sound, the finding is dismissed (with the justification logged so future reviewers don't raise the same finding).

If the engineer's justification is weak ("I didn't have time to split it"), the finding stands.

---

## Why this catalog matters

Without specific anti-patterns named, "clean code" reviews degenerate into vague preferences ("I don't like it"). With a catalog, findings become concrete and actionable.

The Clean Code Officer can say: "S-005 detected at drawer.gd:_on_drag_end — input parsing, validation, business logic, and UI update are tangled. Suggest extracting NameParser and PersonStore."

This is actionable. The engineer knows exactly what to change.

The catalog is the working library for that level of specificity.
