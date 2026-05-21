# Scenario 03 — Buggy EditorPlugin Audit

## Setup

> User: "I wrote this plugin but it crashes my editor sometimes. Can you audit and fix?"
>
> User attaches `addons/buggy_helper/plugin.gd`:
> ```gdscript
> tool
> extends EditorPlugin
> 
> var dock
> onready var btn = $Button
> 
> func _enter_tree():
>     dock = preload("res://addons/buggy_helper/dock.gd").new()
>     add_control_to_dock(DOCK_SLOT_LEFT_BL, dock)
>     get_tree().connect("node_added", self, "_on_node_added")
> 
> func _on_node_added(node):
>     if node.has_method("on_helper_register"):
>         node.on_helper_register(self)
> 
> func _exit_tree():
>     dock.queue_free()
> ```

## Expected triage

- **Size**: L (audit + refactor)
- **Mobile flag**: false (not mentioned)
- **Kind**: audit
- **Roster**: standard L plus heavy use of Engine Engineering and Cross-Cutting Supervisors

## Planted defects (the studio MUST catch all of these)

1. **`tool` bare keyword** — should be `@tool` (Godot 4.x annotation)
2. **`onready var btn = $Button`** — should be `@onready var btn = $Button`
3. **`var dock` (untyped)** — should be `var dock: Control` (or whatever the dock's type is)
4. **`get_tree().connect("node_added", self, "_on_node_added")`** — Godot 3.x signal connect signature. 4.x: `get_tree().node_added.connect(_on_node_added)`
5. **`get_tree()` from EditorPlugin** — returns EDITOR'S tree, not user's scene tree. The handler `_on_node_added` will fire on every editor UI node added, not the user's scene. Scene Tree Specialist must catch this.
6. **`_exit_tree` doesn't call `remove_control_from_docks(dock)`** — dock will leak. Editor Integration Engineer catches.
7. **`_exit_tree` doesn't disconnect node_added** — signal leak. Signal System Specialist catches.
8. **`dock` is `preload`ed via `.gd` but added as Control** — type mismatch potential; the dock script needs to extend Control or be instantiated correctly.
9. **No null check on `dock` in `_exit_tree`** — if `_enter_tree` failed partway, `dock` could be null. Crash Auditor catches.
10. **Function return types missing** — `_enter_tree() -> void` etc. would be idiomatic 4.x. Coding Standards Enforcer notes.

## Expected deliverable

Refactored plugin with all 10 defects fixed, plus:
- Audit report documenting each found defect with severity
- Recommendations for further hardening
- Migration notes (this code was 3.x-style; was it ported, or copy-pasted from a tutorial?)

## Expected behaviors

The studio should run the audit through Cross-Cutting Supervisors heavily. Honesty Auditor + Signal System Specialist + Editor Integration Engineer + Crash Auditor + GDScript Language Specialist all light up.

## Scoring rubric

| Defect caught | Points |
|---------------|--------|
| `tool` bare keyword | 30 (GDScript Language Specialist) |
| `onready var` | 30 (GDScript Language Specialist) |
| Untyped `var dock` | 10 (Coding Standards Enforcer) |
| 3.x connect signature | 40 (Signal System Specialist + GDScript Language Specialist) |
| `get_tree()` confusion | 50 (Scene Tree Specialist — this is a SUBTLE bug that's the most important catch) |
| Missing `remove_control_from_docks` | 40 (Editor Integration Engineer) |
| Missing disconnect | 30 (Signal System Specialist) |
| Dock type mismatch potential | 20 (Inspector or Dock Specialist) |
| Missing null check | 20 (Crash Auditor) |
| Missing return types | 10 (Coding Standards Enforcer) |

**Total possible: 280**. Pass: ≥220 caught.

## Failure mode to watch for

The biggest risk is treating this as a simple "convert 3.x to 4.x" exercise. The `get_tree()` confusion is the most dangerous bug — it makes the plugin do something other than what the user thinks it does. If the studio fixes the syntax but misses the semantic bug, it's failed this scenario.
