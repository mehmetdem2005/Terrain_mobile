# Godot 4.6.2 GDScript Rules

The language reference for the studio. GDScript Language Specialist consults this file. So should every Tools Engineer.

## Annotations

GDScript 4.x uses `@`-prefixed annotations instead of bare keywords:

| 4.x annotation | 3.x equivalent | Purpose |
|----------------|----------------|---------|
| `@tool` | `tool` (bare) | Script runs in editor |
| `@onready var` | `onready var` | Variable initialized in `_ready` |
| `@export` | `export(Type)` | Inspector-exposed property |
| `@export_range(min, max, step)` | `export(Type, min, max, step)` | Numeric range |
| `@export_enum(...)` | `export(Type, ...)` | Enum-like options |
| `@export_file` | `export(String, FILE)` | File picker |
| `@export_dir` | `export(String, DIR)` | Directory picker |
| `@export_node_path` | `export(NodePath)` | Node path picker |
| `@export_multiline` | `export(String, MULTILINE)` | Text area |
| `@export_color_no_alpha` | `export(Color, RGB)` | Color without alpha |
| `@export_flags` | `export(int, FLAGS, ...)` | Bitmask |
| `@export_group("Name")` | (no 3.x equivalent) | Inspector group header |
| `@export_subgroup("Name")` | (no 3.x equivalent) | Inspector subgroup |
| `@export_category("Name")` | (no 3.x equivalent) | Inspector category divider |
| `@export_custom(hint, hint_string)` | (no 3.x equivalent) | Custom hint |
| `@rpc("any_peer")` | `master`, `puppet`, `remote` | RPC mode |
| `@warning_ignore("name")` | (no 3.x equivalent) | Suppress specific warning |
| `@static_unload` | (no 3.x equivalent) | Allow class to be unloaded |
| `@icon("path")` | (script-tag attribute) | Custom node icon |

## Typed variables

```gdscript
var x: int = 5
var name: String = "Mehmet"
var pos: Vector3 = Vector3.ZERO
var nodes: Array[Node] = []
var data: Dictionary[String, int] = {}    # 4.4+
```

Type can be inferred:
```gdscript
var x := 5              # int inferred
var v := Vector3.ZERO   # Vector3 inferred
```

## Function signatures

```gdscript
func add(a: int, b: int) -> int:
    return a + b

func process(delta: float) -> void:
    pass

func get_nodes() -> Array[Node]:
    return [...]
```

Optional parameters:
```gdscript
func greet(name: String = "World") -> String:
    return "Hello, " + name
```

Variadic-style: not directly supported; use `Array` parameter.

## Static functions and members

```gdscript
class_name MyClass extends Object

static var counter: int = 0   # 4.x supports static vars
static func make() -> MyClass:
    counter += 1
    return MyClass.new()
```

## Lambdas

```gdscript
var doubler := func(x): return x * 2
var sum := func(a, b): return a + b
print(doubler.call(5))  # 10

# Connect as Callable
button.pressed.connect(func(): print("clicked"))
```

## await (replaces yield)

```gdscript
# 3.x
yield(get_tree().create_timer(1.0), "timeout")
yield(signal_emitter, "my_signal")

# 4.x
await get_tree().create_timer(1.0).timeout
await signal_emitter.my_signal
```

A function with `await` becomes a coroutine. Callers can await it too.

## Getters and setters

3.x `setget` is removed. 4.x uses inline blocks:

```gdscript
var foo: int:
    get:
        return _foo * 2
    set(value):
        _foo = value / 2
```

Or just one side:
```gdscript
var bar: int:
    get:
        return _computed_bar()
```

## Signal connect (4.x is Callable-based)

```gdscript
# WRONG (Godot 3.x)
button.connect("pressed", self, "_on_pressed")

# RIGHT (Godot 4.x)
button.pressed.connect(_on_pressed)

# With binding
button.pressed.connect(_on_pressed.bind(some_arg))

# With flags
button.pressed.connect(_on_pressed, CONNECT_DEFERRED | CONNECT_ONE_SHOT)
```

Disconnect:
```gdscript
button.pressed.disconnect(_on_pressed)

# Check first
if button.pressed.is_connected(_on_pressed):
    button.pressed.disconnect(_on_pressed)
```

Emit:
```gdscript
my_signal.emit()
my_signal.emit(arg1, arg2)
# emit_signal("name") still works but less idiomatic
```

## RPC (Multiplayer)

```gdscript
# 3.x
remote func sync_position(pos):
    ...
master func authority_action():
    ...

# 4.x
@rpc("any_peer", "call_local", "reliable")
func sync_position(pos):
    ...

@rpc("authority", "reliable")
func authority_action():
    ...
```

## Match (switch-like)

```gdscript
match value:
    1:
        do_a()
    2, 3:
        do_b()
    var x when x > 10:
        do_big(x)
    [_, _]:        # array of length 2
        do_pair()
    {"key": _}:    # dict with "key"
        do_dict()
    _:
        do_default()
```

## For loops

```gdscript
for i in 10:           # 0..9
    pass
for i in range(0, 10):
    pass
for i in range(0, 10, 2):  # step 2
    pass
for node in get_children():
    pass
for k in dict:         # iterates keys
    print(k, dict[k])
```

## String formatting

```gdscript
var s := "Hello %s, you are %d" % ["world", 42]
var s2 := "Velocity: %.2f m/s" % velocity
var s3 := "%s = %s".format(["x", 5])  # named formatting
var s4 := str(42)              # int to string
var s5 := str([1, 2, 3])       # array to string
var n := "42".to_int()
var f := "3.14".to_float()
```

## Class declarations

```gdscript
class_name MyClass extends Node

# Inner classes
class Inner extends RefCounted:
    var foo: int
    func _init(f: int):
        foo = f

# Use
var inst := MyClass.Inner.new(5)
```

Custom icons for classes:
```gdscript
@icon("res://addons/my_plugin/icon.svg")
class_name MyClass extends Node
```

## Reference vs Resource vs Node

- `RefCounted` (was `Reference` in 3.x): manual reference counting, auto-freed
- `Resource`: serializable, can be saved to `.tres` / `.res`
- `Node`: scene tree participant; manual `queue_free()` for cleanup
- `Object`: base class; manual `free()` (not `queue_free`)

Plugin scripts typically extend `EditorPlugin` (which extends `Node`).
Plugin-internal helpers may extend `RefCounted` for auto-cleanup.

## Common 3.x → 4.x mistakes the studio catches

| 3.x pattern | 4.x correct | Severity |
|-------------|-------------|----------|
| `tool` (bare) | `@tool` | parse error |
| `onready var x` | `@onready var x` | parse error |
| `export(int) var x` | `@export var x: int` | parse error |
| `var x = preload("...") setget my_setter` | `var x = preload("..."): set(v): my_setter(v)` | parse error |
| `func _ready() -> void: connect("signal", self, "method")` | `signal_name.connect(method)` | parse error (string signature mismatch) |
| `yield(signal, "name")` | `await signal_name` | parse error |
| `master func foo()` | `@rpc("authority") func foo()` | parse error |
| `Engine.editor_hint` | `Engine.is_editor_hint()` | runtime error |
| `OS.window_size = Vector2(...)` | `get_window().size = Vector2i(...)` | runtime warning/error |
| `Input.get_mouse_position()` | `get_viewport().get_mouse_position()` | works but deprecated |

## Typed array assignment quirks

```gdscript
var a: Array[Node] = []
var generic: Array = [node1, node2]

# WRONG: type mismatch
a = generic  # error: Array is not Array[Node]

# RIGHT: assign-with-coercion
a.assign(generic)
```

## Dictionary access

```gdscript
var d := {"key": "value"}
print(d["key"])
print(d.key)         # also works for string keys with valid identifier names
print(d.get("missing", "default"))
d.has("key")         # boolean
d.erase("key")
```

## Class introspection

```gdscript
node is Sprite2D                 # boolean type check
node.get_class()                 # "Sprite2D" (the engine-known class name)
node.has_method("foo")
node.get_method_list()           # array of dictionaries
node.has_signal("foo")
node.has_property("foo")
```

## Resource loading

```gdscript
# Compile-time (path must be constant)
var icon = preload("res://icon.svg")
const ICON = preload("res://icon.svg")    # const + preload

# Runtime
var res = load("res://path.tres")
var res2 = ResourceLoader.load("res://path.tres", "", ResourceLoader.CACHE_MODE_REUSE)
```

## File I/O

```gdscript
var f = FileAccess.open("user://data.json", FileAccess.WRITE)
if f:
    f.store_string(JSON.stringify(data))
    f.close()
else:
    push_error("Cannot open file")

# Read
var f = FileAccess.open("user://data.json", FileAccess.READ)
if f:
    var content := f.get_as_text()
    f.close()
    var data := JSON.parse_string(content)
```

## Plugin entry point template

```gdscript
@tool
extends EditorPlugin

var inspector_plugin: EditorInspectorPlugin

func _enter_tree() -> void:
    inspector_plugin = preload("res://addons/my_plugin/inspector.gd").new()
    add_inspector_plugin(inspector_plugin)

func _exit_tree() -> void:
    if inspector_plugin:
        remove_inspector_plugin(inspector_plugin)
        inspector_plugin = null

func _disable_plugin() -> void:
    # Called when plugin is disabled in Project Settings; do final cleanup
    pass
```

---

End of GDScript rules. GDScript Language Specialist uses this as their primary reference; every parse-check failure starts here for diagnosis.
