# Godot 4.6.2 Defect Catalog

The studio's curated catalog of recognized bug patterns in Godot 4.6.2 plugins. Walked by the Defect Pattern Specialist for every L/XL ticket. Grows over time as new patterns are recognized.

Each entry has:
- **ID** — stable identifier (DEF-PATTERN-NNN)
- **Pattern** — the code/structure that contains the defect
- **Why it's a bug** — the failure mode
- **How to detect** — grep command, audit question, or manual inspection
- **Fix template** — the standard remediation
- **Severity baseline** — typical P-level (may be adjusted per ticket context)

Patterns are organized by category. The catalog is currently 64 entries across 12 categories.

---

## Category A — Lifecycle defects

### DEF-PATTERN-001: connect in _enter_tree without disconnect in _exit_tree
- **Pattern**: `_enter_tree` contains `some_signal.connect(handler)` but `_exit_tree` does not contain the matching `disconnect`
- **Bug**: Signal handler leaks; on plugin reload, multiple handlers fire for one signal
- **Detect**: For each `connect` in `_enter_tree`, verify matching `disconnect` in `_exit_tree`
- **Fix**: Add disconnect; OR use CONNECT_ONE_SHOT if appropriate; OR document why connection outlives `_exit_tree`
- **Severity**: HIGH

### DEF-PATTERN-002: add_* without remove_* on EditorPlugin
- **Pattern**: `_enter_tree` calls `add_inspector_plugin/add_control_to_dock/add_custom_type/add_autoload_singleton/etc` without matching `remove_*` in `_exit_tree`
- **Bug**: Registration persists across plugin disable; can cause duplicates, leaks, or stale state
- **Detect**: `grep "add_" plugin.gd` vs `grep "remove_" plugin.gd`; counts and names must match
- **Fix**: Add matching `remove_*` call; ensure reference is stored so it can be passed to `remove_*`
- **Severity**: HIGH

### DEF-PATTERN-003: Reference to added control lost
- **Pattern**: `add_control_to_dock(SLOT, ControlClass.new())` — anonymous instance, no reference stored
- **Bug**: Cannot later call `remove_control_from_docks(...)` because the instance is unreachable
- **Detect**: `add_*` calls where the second argument is a `.new()` expression
- **Fix**: Store the instance in a member var first, then add
- **Severity**: HIGH

### DEF-PATTERN-004: _exit_tree accesses possibly-null reference
- **Pattern**: `_exit_tree` calls `something.free()` or `remove_X(something)` without null-check
- **Bug**: If `_enter_tree` failed before initializing `something`, `_exit_tree` crashes
- **Detect**: Look at `_exit_tree` body; identify each external reference; verify defensive null check
- **Fix**: `if something: remove_X(something)` pattern
- **Severity**: MEDIUM

### DEF-PATTERN-005: queue_free vs free confusion
- **Pattern**: Calling `free()` on a Node that is currently in the tree (not `queue_free()`)
- **Bug**: Editor crash or warning
- **Detect**: `grep "\.free()" plugin/` — every match needs review to confirm it's not a Node-in-tree
- **Fix**: Use `queue_free()` for Nodes that are in the scene tree; `free()` only for orphan Nodes or non-Node Objects
- **Severity**: HIGH

### DEF-PATTERN-006: @onready var with null path at _ready time
- **Pattern**: `@onready var x = $Path` where `$Path` may not exist when `_ready` runs (e.g., if the plugin is loaded before the path's parent is added)
- **Bug**: `x` is null; subsequent access crashes
- **Detect**: For each `@onready var`, verify the path exists at the moment `_ready` runs
- **Fix**: Use `$Path` directly with null check, or restructure so the @onready is in a script whose path is guaranteed
- **Severity**: MEDIUM

### DEF-PATTERN-007: Partial-init recovery missing
- **Pattern**: `_enter_tree` does several setup steps; if step 3 fails (exception, missing resource), steps 1-2 are not cleaned up
- **Bug**: Plugin in half-initialized state; subsequent disable leaves residue
- **Detect**: `_enter_tree` body — look for sequential operations without error handling
- **Fix**: Either wrap setup in a transaction (track what's been initialized, undo on failure) OR validate preconditions first
- **Severity**: MEDIUM

### DEF-PATTERN-008: Tween outlives target
- **Pattern**: `create_tween().tween_property(target, "x", 5, 1.0)` — tween references target; if target is freed mid-tween, the tween hits a freed node
- **Bug**: Crash or "previously freed object" error
- **Detect**: For each tween, check whether the target's lifetime is shorter than the tween's
- **Fix**: Use `target.create_tween()` (bound tween — auto-killed when target frees) OR explicitly kill the tween in target's exit/free path
- **Severity**: HIGH

---

## Category B — Signal defects

### DEF-PATTERN-009: 3.x-style signal connect (string-based)
- **Pattern**: `something.connect("signal_name", target, "method_name")` — the Godot 3.x style
- **Bug**: Does not compile in Godot 4.x; parse error
- **Detect**: `grep -nE 'connect\("' plugin/`
- **Fix**: Convert to 4.x: `something.signal_name.connect(target.method_name)`
- **Severity**: P0 (parse failure)

### DEF-PATTERN-010: emit_signal with string name
- **Pattern**: `emit_signal("signal_name", arg1, arg2)` — works in 4.x but is legacy
- **Bug**: Not a bug per se, but flagged for modernization; `signal_name.emit(...)` is idiomatic 4.x
- **Detect**: `grep "emit_signal\\(" plugin/`
- **Fix**: Convert to `signal_name.emit(...)`
- **Severity**: P4 (code style; not a functional bug)

### DEF-PATTERN-011: Signal handler signature mismatch
- **Pattern**: Signal declared with parameters; handler connected has wrong arity or types
- **Bug**: Connect succeeds, but emit raises runtime error
- **Detect**: For each `signal_name.connect(handler)`, verify handler's signature matches signal declaration
- **Fix**: Update handler signature OR use `.bind()` to adapt
- **Severity**: HIGH (runtime crash)

### DEF-PATTERN-012: Signal connected twice
- **Pattern**: `_enter_tree` runs twice (editor reload, plugin disable-enable cycle), signal handler is connected twice
- **Bug**: Handler fires twice per emit
- **Detect**: Patterns where `_enter_tree` connects to a signal whose source outlives the plugin
- **Fix**: Guard with `is_connected()` OR use `CONNECT_REFERENCE_COUNTED` flag OR ensure `_exit_tree` properly disconnects
- **Severity**: MEDIUM

### DEF-PATTERN-013: await on signal that may not fire
- **Pattern**: `await some_signal` where there's no guarantee `some_signal` emits
- **Bug**: Coroutine hangs indefinitely
- **Detect**: For each `await`, trace whether the awaited signal is guaranteed to emit
- **Fix**: Use `await` with a timeout (race with timer.timeout) OR document the precondition that ensures emission
- **Severity**: MEDIUM

### DEF-PATTERN-014: Lambda connected to long-lived signal
- **Pattern**: `EditorInterface.scene_changed.connect(func(s): print(s))` — anonymous lambda, no way to disconnect
- **Bug**: Cannot disconnect; handler leaks
- **Detect**: `connect()` calls with `func(` immediately after
- **Fix**: Store the Callable: `_handler = func(s): print(s); signal.connect(_handler)`; then `signal.disconnect(_handler)`
- **Severity**: MEDIUM

### DEF-PATTERN-015: Signal emitted from _exit_tree
- **Pattern**: `_exit_tree` emits a signal; listeners may try to access nodes that are being torn down
- **Bug**: Listeners see inconsistent state or crash on freed-node access
- **Detect**: `_exit_tree` body — look for `.emit()` calls
- **Fix**: Don't emit from `_exit_tree`; if cleanup-notification is needed, emit before shutdown begins
- **Severity**: MEDIUM

---

## Category C — Inspector defects

### DEF-PATTERN-016: _parse_property returns false but tries to handle
- **Pattern**: `_parse_property` calls `add_property_editor` but returns false
- **Bug**: Godot renders both the default editor AND the custom one; visual mess
- **Detect**: `_parse_property` body — if anything is added, must return true
- **Fix**: Return true when intercepting; false when not
- **Severity**: MEDIUM

### DEF-PATTERN-017: Custom drawer doesn't commit via UndoRedo
- **Pattern**: Custom inspector drawer modifies target.property directly (`target.x = new_value`)
- **Bug**: User's undo doesn't restore the change
- **Detect**: For each property mutation in an inspector drawer, verify UndoRedo wrapping
- **Fix**: Use `EditorUndoRedoManager.create_action()` with do/undo property pairs
- **Severity**: HIGH (user-visible broken undo)

### DEF-PATTERN-018: Inspector drawer accesses stale object reference
- **Pattern**: `_parse_property` stores `object` reference in member var; user switches selection; reference is stale
- **Bug**: Subsequent drawer interactions affect the wrong object
- **Detect**: Look for member vars storing the inspected object across `_parse_property` calls
- **Fix**: Get the object fresh on each interaction, OR clear stored references when selection changes
- **Severity**: HIGH

### DEF-PATTERN-019: Inspector drawer doesn't refresh on external change
- **Pattern**: Another script modifies the inspected property; drawer shows stale value
- **Bug**: UI desync with model
- **Detect**: Drawer-side handling of `target.property_list_changed` or similar refresh signals
- **Fix**: Connect to the refresh signal in drawer setup; update displayed value
- **Severity**: MEDIUM

---

## Category D — Resource defects

### DEF-PATTERN-020: Resource subclass holds Node reference
- **Pattern**: `extends Resource` with a property typed `Node` or holding a node reference
- **Bug**: Resources outlive Nodes; the reference dangles or is null after scene change
- **Detect**: For each `extends Resource`, scan member vars for Node-typed declarations
- **Fix**: Use `NodePath` instead; resolve to Node when needed
- **Severity**: HIGH

### DEF-PATTERN-021: Resource _init has required parameters
- **Pattern**: `func _init(required_arg): ...` on a Resource subclass
- **Bug**: ResourceLoader cannot construct via zero-arg `.new()`; load fails
- **Detect**: Each Resource subclass — verify `_init` has zero required args
- **Fix**: Make all `_init` args optional with defaults; OR remove `_init`
- **Severity**: HIGH

### DEF-PATTERN-022: Resource class_name collision with built-in
- **Pattern**: `class_name Camera` or any name that collides with Godot built-in class
- **Bug**: Editor refuses to load the script
- **Detect**: For each `class_name`, check if a same-named XML exists in `~/godot-api-reference/`
- **Fix**: Pick a non-colliding name; prefix with plugin namespace if needed
- **Severity**: HIGH

### DEF-PATTERN-023: ResourceLoader.load with user-supplied path
- **Pattern**: `ResourceLoader.load(user_path)` where `user_path` came from a file dialog or user input
- **Bug**: Loading arbitrary `.gd` resources executes their `_init`; security risk
- **Detect**: All `ResourceLoader.load` calls; check whether the path is user-controlled
- **Fix**: Validate path is in expected directory; reject `.gd` resources unless intentional; consider type-check on loaded resource
- **Severity**: HIGH (security)

---

## Category E — File I/O defects

### DEF-PATTERN-024: FileAccess.open without null check
- **Pattern**: `var f = FileAccess.open(path, FileAccess.READ); f.get_as_text()` — no null check on `f`
- **Bug**: If file missing/permission denied, `open` returns null; next call crashes
- **Detect**: `FileAccess.open` calls — verify the next line(s) check for null
- **Fix**: `if not f: push_error("..."); return` before using `f`
- **Severity**: HIGH

### DEF-PATTERN-025: FileAccess not closed
- **Pattern**: `FileAccess.open(path, ...)` without explicit `.close()` or RAII pattern
- **Bug**: File handle held until GC; on Windows, file is locked
- **Detect**: `FileAccess.open` calls without matching `.close()`
- **Fix**: Always close; or use the var-scope auto-close pattern (out of scope = close)
- **Severity**: MEDIUM

### DEF-PATTERN-026: User input concatenated to path
- **Pattern**: `var path = "res://addons/foo/" + user_input + ".tres"`
- **Bug**: `..` traversal: user_input = "../../malicious"; path escapes plugin
- **Detect**: Path strings constructed via concatenation with non-constant inputs
- **Fix**: Validate the constructed path stays within expected directory; use `ProjectSettings.localize_path` and verify prefix
- **Severity**: HIGH (security)

### DEF-PATTERN-027: Plugin writes to res:// at runtime
- **Pattern**: `FileAccess.open("res://addons/foo/data.json", FileAccess.WRITE)` at runtime
- **Bug**: `res://` is read-only in exported games; writes fail silently or with error
- **Detect**: Writes to `res://` paths
- **Fix**: Use `user://` for runtime-mutable data; `res://` only for plugin-shipped assets
- **Severity**: HIGH

---

## Category F — Scene tree / EditorPlugin context defects

### DEF-PATTERN-028: get_tree() confused with edited scene
- **Pattern**: Plugin code calls `get_tree().get_nodes_in_group(...)` expecting user's scene
- **Bug**: Returns nodes from EDITOR's tree, not user's edited scene
- **Detect**: `get_tree()` calls in plugin code that intend to access user's scene
- **Fix**: Use `EditorInterface.get_edited_scene_root()` and traverse from there
- **Severity**: HIGH (functionally wrong)

### DEF-PATTERN-029: Modifying edited scene without UndoRedo
- **Pattern**: Plugin code does `edited_root.add_child(new_node)` directly
- **Bug**: User can't undo; user's work changes without trace
- **Detect**: Mutations of `EditorInterface.get_edited_scene_root()` or its descendants
- **Fix**: Use `EditorUndoRedoManager` to wrap the mutation
- **Severity**: HIGH

### DEF-PATTERN-030: Stale reference across scene change
- **Pattern**: Plugin caches a reference to a node in the edited scene; user switches scenes; reference is stale
- **Bug**: Subsequent access crashes or affects nothing
- **Detect**: Member vars storing user-scene node references
- **Fix**: Listen to `EditorInterface.scene_changed`; clear references on change
- **Severity**: MEDIUM

---

## Category G — UI and theme defects

### DEF-PATTERN-031: Hardcoded color in plugin UI
- **Pattern**: `Color(0, 0, 0)` or `Color("#000000")` in plugin UI code
- **Bug**: Doesn't match user's theme; looks broken with light themes or custom themes
- **Detect**: `grep -E 'Color\([0-9.,\s]+\)' plugin/`
- **Fix**: Use `EditorInterface.get_editor_theme().get_color("foo", "Editor")`
- **Severity**: MEDIUM

### DEF-PATTERN-032: Hardcoded font size in plugin UI
- **Pattern**: `Label.add_theme_font_size_override("font_size", 14)`
- **Bug**: Doesn't scale with editor font size setting
- **Detect**: `add_theme_font_size_override` with literal sizes
- **Fix**: Pull size from editor theme; OR scale relative to editor's font size
- **Severity**: LOW

### DEF-PATTERN-033: Plugin icon wrong size
- **Pattern**: Plugin icon PNG is not 16x16
- **Bug**: Icon renders blurry or misaligned in editor
- **Detect**: Inspect icon dimensions
- **Fix**: Use 16x16 PNG; for HiDPI, also provide 32x32 with `@2x` suffix
- **Severity**: LOW

### DEF-PATTERN-034: Focus indicator hidden
- **Pattern**: Custom Control overrides theme to remove focus styling
- **Bug**: Keyboard navigation invisible
- **Detect**: Custom Controls with `focus_mode = FOCUS_NONE` OR custom drawing that ignores focus state
- **Fix**: Draw focus indicator using editor theme's focus style
- **Severity**: MEDIUM (accessibility)

---

## Category H — UndoRedo defects

### DEF-PATTERN-035: create_action without commit_action
- **Pattern**: `undo.create_action(...)` followed by `.add_do_*` and `.add_undo_*` but no `.commit_action()`
- **Bug**: Action accumulates in pending state; subsequent actions get merged unexpectedly
- **Detect**: Each `create_action` — verify a matching `commit_action` follows
- **Fix**: Always commit; even on error path, either commit the partial or abort the action
- **Severity**: HIGH

### DEF-PATTERN-036: do_method without matching undo_method
- **Pattern**: `add_do_method` with no corresponding `add_undo_method` (or vice versa)
- **Bug**: Undo doesn't fully reverse the action, or redo doesn't reapply
- **Detect**: Count of `add_do_*` vs `add_undo_*` per action — must be symmetric
- **Fix**: Add the missing inverse method
- **Severity**: HIGH

### DEF-PATTERN-037: Drag commits every frame to undo stack
- **Pattern**: Mouse drag emits per-frame `commit_action`, polluting undo with 60 actions per second
- **Bug**: User undoes once, expects to undo the full drag; instead undoes one frame
- **Detect**: UndoRedo commits in `_process` or in mouse-motion handlers
- **Fix**: Defer commit until drag-end; OR use action merging via repeated `create_action` with same name
- **Severity**: HIGH (user-visible)

### DEF-PATTERN-038: Action name not user-friendly
- **Pattern**: `undo.create_action("update")` or `create_action("doStuff")`
- **Bug**: User sees meaningless text in Edit menu
- **Detect**: Each action name — does it describe what the user did?
- **Fix**: Use descriptive names: "Set Vector Field Velocity", "Toggle Visibility"
- **Severity**: LOW

---

## Category I — Performance defects

### DEF-PATTERN-039: _process scanning scene tree linearly
- **Pattern**: `_process` does `get_tree().get_nodes_in_group("foo")` or recursive `get_children()`
- **Bug**: O(n) per frame; degrades editor performance with large scenes
- **Detect**: `_process` body — look for tree-walking or group queries
- **Fix**: Cache results; subscribe to add/remove events; invalidate cache on change
- **Severity**: MEDIUM

### DEF-PATTERN-040: Dictionary allocated in hot path
- **Pattern**: `var d = {}` or `{"key": value}` literal inside `_process` or `_draw`
- **Bug**: Per-frame allocation; GC pressure; frame hitches
- **Detect**: Hot-path bodies — look for `{...}` literals or `Dictionary.new()`
- **Fix**: Allocate once at init; clear and reuse in hot path
- **Severity**: LOW (unless hot path is genuinely hot)

### DEF-PATTERN-041: String concatenation in tight loop
- **Pattern**: `var s = ""; for x in items: s += str(x)`
- **Bug**: O(n²) string allocations
- **Detect**: For-loop bodies with `+=` on strings
- **Fix**: Build a `PackedStringArray` and join at end; OR use `String.format`
- **Severity**: LOW

### DEF-PATTERN-042: RegEx compiled in function
- **Pattern**: `var re = RegEx.new(); re.compile(pattern); re.search(text)` inside a frequently-called function
- **Bug**: Compile is expensive; called every invocation
- **Detect**: `RegEx.new()` inside non-init function bodies
- **Fix**: Move to `@onready var` or const init; reuse the compiled RegEx
- **Severity**: LOW

---

## Category J — Mobile / Android editor defects

### DEF-PATTERN-043: Right-click required for context menu
- **Pattern**: Context menu shown on right-click only; no alternative trigger
- **Bug**: Android editor has no right-click; feature inaccessible
- **Detect**: `MOUSE_BUTTON_RIGHT` references; right-click triggered popups
- **Fix**: Also bind long-press OR add a visible "menu" button
- **Severity**: MEDIUM (if mobile in scope)

### DEF-PATTERN-044: Touch targets too small
- **Pattern**: Buttons/clickable Controls smaller than ~44x44 device pixels
- **Bug**: Difficult to tap accurately on touch
- **Detect**: `custom_minimum_size` of clickable Controls
- **Fix**: Set minimum size to at least 44x44 for touch targets (or add invisible padding)
- **Severity**: MEDIUM (if mobile in scope)

### DEF-PATTERN-045: Forward+-only feature in mobile sample
- **Pattern**: Sample scene uses SDFGI, glow, DoF, or compute shaders
- **Bug**: Sample looks wrong on Forward Mobile renderer
- **Detect**: Sample scenes — check WorldEnvironment, materials, shaders
- **Fix**: Mobile-compatible sample variant OR document desktop-only
- **Severity**: MEDIUM

### DEF-PATTERN-046: 4K texture in plugin assets
- **Pattern**: Sample textures at 4096x4096 or larger
- **Bug**: Slow load, large APK on mobile, VRAM pressure
- **Detect**: Inspect texture dimensions in plugin assets
- **Fix**: Use 1K or 2K for sample assets; let user provide hi-res if needed
- **Severity**: LOW (only if mobile in scope)

---

## Category K — Security defects

### DEF-PATTERN-047: var_to_str / str_to_var on user input
- **Pattern**: `var data = str_to_var(user_string)`
- **Bug**: Executes arbitrary Variant construction; can construct any built-in type, potential code execution path
- **Detect**: All `str_to_var` calls — verify input is trusted
- **Fix**: Use `JSON.parse_string` instead for user data; reserve `str_to_var` for plugin-internal serialization
- **Severity**: HIGH (security)

### DEF-PATTERN-048: GDScript.new() from string
- **Pattern**: `var script = GDScript.new(); script.source_code = user_input; script.reload()`
- **Bug**: Executes arbitrary user-provided code
- **Detect**: `GDScript.new()` followed by `source_code =` assignment
- **Fix**: Don't accept code from user; if scripting is part of the feature, use a sandboxed expression language
- **Severity**: P0 (security, code execution)

### DEF-PATTERN-049: OS.execute with user input
- **Pattern**: `OS.execute(cmd, [user_arg])` where `user_arg` is unsanitized
- **Bug**: Shell injection
- **Detect**: `OS.execute` calls with non-constant args
- **Fix**: Validate args; whitelist; never pass shell metacharacters
- **Severity**: HIGH (security)

### DEF-PATTERN-050: HTTPRequest without URL validation
- **Pattern**: `http.request(user_url)` where `user_url` is unsanitized
- **Bug**: SSRF risk; data exfiltration; arbitrary endpoint hit
- **Detect**: `HTTPRequest.request` calls with non-constant URLs
- **Fix**: Validate URL is in expected domain; reject `file://`, `data:`, suspicious schemes
- **Severity**: HIGH (security)

---

## Category L — State and consistency defects

### DEF-PATTERN-051: Drag flag stuck after cancel
- **Pattern**: Drag interaction sets `is_dragging = true`; doesn't reset on focus loss, ESC, or other cancel
- **Bug**: `is_dragging` permanently true; subsequent interactions misbehave
- **Detect**: For each drag-state flag, verify reset on all cancel paths (focus_exited, ESC, scene change, plugin disable)
- **Fix**: Centralize cancel logic; reset on every cancel path
- **Severity**: MEDIUM

### DEF-PATTERN-052: Cache not invalidated on source change
- **Pattern**: Plugin caches a computed value; source data changes; cache serves stale
- **Bug**: UI / behavior desync
- **Detect**: For each cache, identify all paths that could mutate the source; verify cache invalidation hooks
- **Fix**: Listen to change signals; invalidate cache on emit
- **Severity**: MEDIUM

### DEF-PATTERN-053: Save schema change without migration
- **Pattern**: Plugin v0.2 reads `data.json`; v0.3 changes schema; no migration
- **Bug**: Existing user data is corrupted or rejected
- **Detect**: Plugin version bump + schema change without `migrate_from_v_N` logic
- **Fix**: Always include version field; write migration logic for each breaking change
- **Severity**: HIGH

### DEF-PATTERN-054: Settings key renamed silently
- **Pattern**: Setting key was `my_plugin/old_name`; v0.3 changes to `my_plugin/new_name`; user's old value dropped
- **Bug**: User's customization lost on update
- **Detect**: Diff settings keys between versions
- **Fix**: Read both old and new key; migrate value; remove old key after migration
- **Severity**: MEDIUM

---

## Category M — Concurrency / ordering defects

### DEF-PATTERN-055: call_deferred operations interdependent without explicit order
- **Pattern**: `call_deferred("op_a")` then `call_deferred("op_b")` where op_b depends on op_a's result
- **Bug**: Both run at frame end; order is FIFO but easy to misjudge
- **Detect**: Multiple `call_deferred` in same scope
- **Fix**: Make op_b's dependency explicit (op_a's last line calls op_b) OR await
- **Severity**: MEDIUM

### DEF-PATTERN-056: Signal handler emits signal it listens to
- **Pattern**: Handler `_on_X_emitted` emits signal X
- **Bug**: Infinite recursion or unintended reentry
- **Detect**: For each handler, check if its body emits the same signal
- **Fix**: Guard with a flag; break the cycle deliberately
- **Severity**: HIGH

### DEF-PATTERN-057: Editor reload doesn't restore plugin state
- **Pattern**: Plugin has state (settings, in-progress action); project reload runs `_enter_tree` fresh; state lost
- **Bug**: User loses work on reload
- **Detect**: Plugin has mutable state — is it persisted? Restored on `_enter_tree`?
- **Fix**: Persist state to `user://`; restore in `_enter_tree`
- **Severity**: MEDIUM (depends on state importance)

---

## Category N — Compatibility defects

### DEF-PATTERN-058: Uses 4.4+ feature without version check
- **Pattern**: Plugin uses typed Dictionary (4.4+) but `plugin.cfg` claims 4.x compat broadly
- **Bug**: Loads but fails to parse on 4.0-4.3
- **Detect**: Identify minimum version of each API used; compare to declared compat
- **Fix**: Either pin minimum version in plugin.cfg OR provide fallback for older versions
- **Severity**: MEDIUM

### DEF-PATTERN-059: Hardcoded platform path
- **Pattern**: `OS.execute("bash", ["-c", "..."])` — Linux/macOS only; fails on Windows
- **Bug**: Plugin doesn't work cross-platform
- **Detect**: `OS.execute` with shell-specific paths
- **Fix**: Use `OS.has_feature("windows")` etc. to branch; OR avoid shell exec entirely
- **Severity**: MEDIUM (if cross-platform claimed)

---

## Category O — Documentation and discoverability defects

### DEF-PATTERN-060: README missing installation step
- **Pattern**: README jumps to "Usage" without "Installation"
- **Bug**: Users don't know how to install
- **Detect**: Read README structure
- **Fix**: Add installation section: how to copy to addons/, how to enable in Project Settings
- **Severity**: LOW

### DEF-PATTERN-061: Plugin description in plugin.cfg too vague
- **Pattern**: `description="A helpful plugin"` or empty description
- **Bug**: Asset Library users can't tell what the plugin does
- **Detect**: Read `plugin.cfg` description field
- **Fix**: Specific, action-oriented description: what it adds, who it's for
- **Severity**: LOW

### DEF-PATTERN-062: User-facing string not wrapped in tr()
- **Pattern**: `Label.text = "Save"` — hardcoded English
- **Bug**: Plugin not localizable
- **Detect**: `grep -E '\.text\s*=\s*"' plugin/`
- **Fix**: `Label.text = tr("Save")`; provide translation file template
- **Severity**: LOW (unless localization is in scope)

---

## Category P — Plugin metadata defects

### DEF-PATTERN-063: Missing plugin.cfg required field
- **Pattern**: `plugin.cfg` missing `name`, `description`, `author`, `version`, or `script`
- **Bug**: Editor warning; plugin may not load
- **Detect**: Verify all 5 fields present
- **Fix**: Add missing field(s)
- **Severity**: HIGH

### DEF-PATTERN-064: plugin.cfg script= path is wrong
- **Pattern**: `script="plugin.gd"` but file is at `addons/foo/plugin.gd` — relative-path mismatch
- **Bug**: Plugin fails to load
- **Detect**: Verify `script=` path resolves to an existing file
- **Fix**: Use the correct relative path (typically just the filename)
- **Severity**: HIGH

---

## How to extend the catalog

When the Defect Pattern Specialist (or any role) encounters a defect pattern not in the catalog:

1. Verify it is a *pattern* (could recur) not a one-off
2. Document it in the format above
3. Submit to Studio Knowledge Curator
4. After 1-2 sightings, promote to catalog
5. Bug Hunter Lead refreshes the pattern walk to include the new entry

The catalog is the studio's accumulated wisdom. It compounds over time.

---

## Walking the catalog (for the Defect Pattern Specialist)

For each L/XL ticket:
1. Read the ticket's scope; identify which categories are relevant
2. For each relevant category, walk every pattern
3. For each pattern, use the "Detect" instruction (grep command, audit question, or manual inspection)
4. Log every pattern checked (PASS/MATCH/N/A) to the audit trail
5. For matches, raise blockers with the catalog's suggested severity

A complete walk on a typical L ticket takes 10-20 minutes. On an XL ticket, 30-45 minutes. This is part of the bug hunt budget.

A walk that finds zero matches is suspicious for non-trivial tickets — Bug Hunter Lead reviews whether the walk was thorough.
