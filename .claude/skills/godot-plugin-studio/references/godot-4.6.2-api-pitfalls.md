# Godot 4.6.2 API Pitfalls

The traps LLMs commonly fall into when generating Godot 4 code. Honesty Auditor consults this file. So should every Tools Engineer before claiming an API exists.

This file is maintained — every ticket that surfaces a new pitfall extends it via Studio Knowledge Curator.

## Class methods that don't exist (but LLMs invent)

These are commonly hallucinated. Always verify against `~/godot-api-reference/<Class>.xml`.

| Claimed method | Reality |
|---------------|---------|
| `EditorInterface.get_editor_main_screen()` | Use `get_editor_main_screen()` from `EditorInterface` — verify; existed by some versions but path can vary |
| `EditorInspector.add_section()` | Does not exist. Use `EditorInspectorPlugin.add_custom_control()` |
| `EditorInspector.refresh()` | Use `EditorInterface.get_inspector().refresh()` actually returns void, may or may not exist by exact name — verify |
| `Node.find_parent_of_type()` | Does not exist directly. Loop via `get_parent()` and check class |
| `Resource.deep_copy()` | Use `Resource.duplicate(true)` |
| `String.is_empty()` | Yes, this works in 4.x — but for `String` not `StringName` (verify) |
| `Array.is_empty()` | Yes, exists |
| `Dictionary.is_empty()` | Yes, exists |
| `Color.from_html()` | Use `Color.html()` to construct, or `Color("#RRGGBB")` constructor |
| `Vector3.is_zero_approx()` | Yes, exists (verify exact name) |
| `Engine.editor_hint` (as property) | Property doesn't exist; use `Engine.is_editor_hint()` (function) |
| `OS.execute_in_thread()` | Does not exist. Use Thread class with OS.execute inside |
| `EditorPlugin.add_undo_redo_manager()` | Use `get_undo_redo()` — returns `EditorUndoRedoManager` |

## Signal mistakes

LLMs frequently invent or misspell signal names. Common cases:

| Claimed signal | Reality |
|---------------|---------|
| `EditorPlugin.scene_changed` | Actually: `scene_changed(scene_root: Node)` — verify exact signature |
| `Tree.item_clicked` | Use `item_selected` or `item_activated` (different semantics) |
| `Button.clicked` | Use `pressed` |
| `Inspector.property_changed` | Use `EditorInterface.get_inspector().property_edited(property: String)` or similar — verify |

Always grep first:
```bash
grep "signal name=" ~/godot-api-reference/<Class>.xml
```

## Inheritance gotchas

Methods inherited from parent classes are not redocumented in the child. If you grep for `add_child` on `EditorPlugin.xml` you'll find nothing — but `add_child` is inherited from `Node`. Always check the inheritance chain:

```bash
grep "<class name=" ~/godot-api-reference/EditorPlugin.xml | head -1
# <class name="EditorPlugin" inherits="Node">
```

Then grep on the parent:
```bash
grep "method name=\"add_child\"" ~/godot-api-reference/Node.xml
```

## Deprecated APIs (work but warn)

These compile in 4.6.2 but produce deprecation warnings. Plugin code should avoid them:

| Deprecated | Use instead |
|-----------|-------------|
| `OS.window_size` | `DisplayServer.window_get_size()` or `get_window().size` |
| `OS.center_window()` | `DisplayServer.window_set_position()` with computed center |
| `OS.set_window_title()` | `get_window().title = "..."` |
| `OS.set_window_position()` | `get_window().position = ...` |
| `Input.get_mouse_position()` | `get_viewport().get_mouse_position()` or `DisplayServer.mouse_get_position()` |
| Generic `Array` without type | `Array[T]` typed array |
| `Engine.get_main_loop()` (in some contexts) | Direct access to scene tree via `get_tree()` |

## Editor-only vs game-runtime APIs

Some classes exist in the editor only. Plugin code using them only works with `Engine.is_editor_hint()` true (or in EditorPlugin context):

- `EditorPlugin` and all `Editor*` classes
- `EditorInterface`
- `EditorUndoRedoManager` (different from `UndoRedo` which works at game runtime too)
- `EditorInspector`, `EditorInspectorPlugin`
- `EditorImportPlugin`, `EditorExportPlugin`
- `EditorScript`

If a plugin script extends one of these but is also referenced by a game scene, the game will crash. Use `@tool` annotation properly and gate editor-only logic.

## Typed collections — verify exact syntax

Typed arrays in 4.x:
```gdscript
var a: Array[int] = []         # ✓
var b: Array[Node] = []        # ✓
var c: Array[Variant] = []     # redundant; just use Array
```

Typed dictionaries landed in 4.4:
```gdscript
var d: Dictionary[String, int] = {}            # ✓ in 4.4+
var e: Dictionary[StringName, Variant] = {}    # ✓
```

Type promotion between typed and untyped:
- Assignment from typed to untyped: implicit, works
- Assignment from untyped to typed: explicit, use `.assign()` for arrays
- Iteration over typed: preserves type

## `@export` annotation quick reference

Always verify exact syntax against parse check:

```gdscript
@export var x: int = 5
@export_range(0, 100, 1) var y: int = 50
@export_range(0.0, 1.0, 0.01) var z: float = 0.5
@export_enum("a", "b", "c") var e: String = "a"
@export_enum("a", "b", "c") var ei: int = 0
@export_file("*.png") var path: String
@export_dir var dir: String
@export_node_path("Node3D") var n: NodePath
@export_flags("Foo:1", "Bar:2", "Baz:4") var f: int = 0
@export_multiline var text: String
@export_color_no_alpha var color: Color
@export_group("Group Name")
@export_subgroup("Subgroup Name")
@export_category("Category Name")
@export_custom(PROPERTY_HINT_FLAGS, "Foo,Bar") var x: int
```

Custom hints via `@export_custom` require knowledge of the `PropertyHint` enum.

## Connection patterns

### 4.x signal connect — Callable, not string
```gdscript
# WRONG (Godot 3.x)
signal.connect(self, "method_name")
signal.connect("name", self, "method_name")  # legacy

# RIGHT (Godot 4.x)
signal_name.connect(method_name)
signal_name.connect(_on_callback)
signal_name.connect(node.method_name)
signal_name.connect(target.method.bind(arg))
```

### Connect flags
```gdscript
signal_name.connect(_handler, CONNECT_DEFERRED)         # defers to idle frame
signal_name.connect(_handler, CONNECT_ONE_SHOT)         # auto-disconnects after 1 emit
signal_name.connect(_handler, CONNECT_PERSIST)          # persists across scene save (rare)
signal_name.connect(_handler, CONNECT_REFERENCE_COUNTED) # multiple connects allowed; ref-counted
```

### Disconnect
```gdscript
signal_name.disconnect(_handler)
# Check before disconnect
if signal_name.is_connected(_handler):
    signal_name.disconnect(_handler)
```

### Emit
```gdscript
signal_name.emit()
signal_name.emit(arg1, arg2)
# Old form still works but `.emit()` is idiomatic in 4.x
emit_signal("signal_name")
```

## `await` on signals
```gdscript
await signal_name
await get_tree().create_timer(1.0).timeout
await some_object.some_signal
```

The function containing `await` becomes a coroutine. Callers don't have to await it but may want to.

## Lambdas and Callable
```gdscript
# Lambda
var cb := func(x): return x * 2
signal_name.connect(func(): print("emitted"))

# Lambda capture is by reference; long-lived lambdas can keep nodes alive
# Avoid lambdas connected to long-lived signals unless deliberate
```

## Scene tree pitfalls in plugins

| Pattern | Result |
|---------|--------|
| `get_tree()` from EditorPlugin | Returns editor's SceneTree, NOT the user's edited scene |
| `EditorInterface.get_edited_scene_root()` | Returns the root of the scene currently open in the editor |
| `get_tree().current_scene` | In editor, this is the *editor's* current scene (not user's edit target) |
| `EditorInterface.get_selection().get_selected_nodes()` | User's current selection — empty if nothing selected |

Plugins manipulating user's scene must operate on `get_edited_scene_root()`, not `get_tree()`.

## Plugin-specific @tool nuances

For a script to be edited and run in the editor:
```gdscript
@tool
extends EditorPlugin
```

For a custom Node type that runs in the editor:
```gdscript
@tool
class_name MyCustomNode
extends Node

func _ready():
    if Engine.is_editor_hint():
        # editor-time setup
        pass
    else:
        # runtime setup
        pass
```

Common bug: `@tool` script with `_process` runs both in editor (sometimes harmful) and at runtime. Gate properly:
```gdscript
func _process(delta):
    if Engine.is_editor_hint():
        return  # or: do editor preview only
    # ... game logic
```

## UndoRedo correctness

Plugin actions that modify user data MUST use `EditorUndoRedoManager`:
```gdscript
var undo := get_undo_redo()  # returns EditorUndoRedoManager from EditorPlugin
undo.create_action("Set My Property")
undo.add_do_property(target, "my_property", new_value)
undo.add_undo_property(target, "my_property", old_value)
undo.commit_action()
```

For methods (not properties):
```gdscript
undo.create_action("Add Custom Item")
undo.add_do_method(target, "add_item", item_data)
undo.add_undo_method(target, "remove_item", item_data)
undo.commit_action()
```

For complex actions, can mix:
```gdscript
undo.create_action("Complex Change")
undo.add_do_method(target, "method_a")
undo.add_undo_method(target, "method_b")
undo.add_do_property(target, "prop", new_val)
undo.add_undo_property(target, "prop", old_val)
undo.commit_action()
```

## Always-verify-before-claiming patterns

Whenever you would write any of these, run a verification first:

- "Method X exists on class Y" → grep
- "Class Y inherits from Z" → grep
- "Property X on Y has type T" → grep
- "Signal X on Y emits with parameters P" → grep
- "Function works the same as Godot 3" → almost certainly false; verify
- "This was added in 4.X" → verify the minor version

---

End of API pitfalls. This file is consulted by the Honesty Auditor for every API claim review.
