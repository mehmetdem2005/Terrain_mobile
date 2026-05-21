# Scenario 01 — Inspector Plugin From Scratch

## Setup (what the studio receives)

> User: "Make me a Godot 4.6 inspector plugin that adds a custom drawer for `Vector3` properties annotated with `@export_custom(PROPERTY_HINT_VECTOR_FIELD, ...)`. Drag bars for each axis, keyboard accessible. Must support undo/redo. Desktop only — I don't care about mobile."

## Expected triage

- **Size**: L (multi-file inspector plugin, <500 LOC expected, sensitive area: inspector internals + UndoRedo)
- **Mobile flag**: false (user explicitly out-of-scope)
- **Roster** (key roles that must activate):
  - Producer, Tech Director, Plugin Design Lead, Inspector Specialist, UndoRedo Specialist, GDScript Language Specialist, API Verification Specialist, Theme/UI Specialist, Tools Lead, Senior Tools Engineer, QA Lead, Automation QA Engineer, Honesty Auditor, Quality Gate Officer, Polish Lead, Edge Case Hunter, End-User Advocate

## Expected behaviors

The studio should:

1. **API verification for `@export_custom`** — does it accept `PROPERTY_HINT_VECTOR_FIELD`? (No — that's not a built-in hint. The studio must catch that the hint will be custom and require corresponding parsing logic.)
2. **API verification for `EditorInspectorPlugin.parse_property`** — verify signature matches what's planned
3. **UndoRedo flow** — every drag commit must create an UndoRedo action; drag-in-progress should not pollute the undo stack with intermediate values
4. **Plugin lifecycle symmetry** — `add_inspector_plugin` in `_enter_tree`, `remove_inspector_plugin` in `_exit_tree`
5. **Theme integration** — drag bar colors pull from `EditorInterface.get_editor_theme()`, not hardcoded
6. **Keyboard accessibility** — Control's `focus_mode` set; tab order makes sense; arrow keys adjust values

## Planted complexities

The user's request contains traps the studio should catch:

| Trap | What should happen |
|------|--------------------|
| `PROPERTY_HINT_VECTOR_FIELD` doesn't exist as a built-in | Plugin Design Lead designs a custom hint string parser; doesn't blindly use a non-existent enum |
| User says "support undo/redo" but doesn't specify drag-vs-final | UndoRedo Specialist should propose: only commit on drag-end, not per-frame |
| Mobile out of scope, but the inspector code might still run on Android editor if user later changes mind | Cross-Platform Compatibility Engineer notes this as a non-blocking risk in the risk register |

## Expected deliverable

A working plugin at `addons/vector_field_inspector/`:
- `plugin.cfg`
- `plugin.gd` — EditorPlugin entry
- `vector_field_inspector.gd` — EditorInspectorPlugin
- `vector_field_drawer.gd` — Control subclass, the actual drawer UI
- `README.md`
- Total LOC: ~250-400

## Expected audit trail highlights

- Honesty Auditor catches at least the `PROPERTY_HINT_VECTOR_FIELD` hallucination if any role tries it
- API Verification Specialist runs grep on EditorInspectorPlugin methods
- GDScript Language Specialist runs `--check-only` on at least the main script
- UndoRedo Specialist demands `add_do_property` / `add_undo_property` pattern
- Polish Lead reviews error messages and naming
- Edge Case Hunter enumerates at least 5 edges

## Scoring rubric

| Role | Max | Notes |
|------|-----|-------|
| Inspector Specialist | 100 | Must propose correct EditorInspectorPlugin pattern |
| UndoRedo Specialist | 100 | Must demand correct undo/redo flow |
| GDScript Language Specialist | 80 | Parse checks on every file |
| API Verification Specialist | 80 | At least 5 API verifications logged |
| Honesty Auditor | 90 | Must catch any unverified hint name |
| Theme/UI Specialist | 60 | Must catch hardcoded colors if present |
| Polish Lead | 50 | Reviews naming and errors |
| Edge Case Hunter | 50 | At least 5 edge cases |
| End-User Advocate | 40 | Reviews first-run experience |
| Plugin Design Lead | 60 | Design doc exists |
| Quality Gate Officer | 100 | All L gates run |
| Tools Lead | 50 | Coordination evidence |

## Pass criteria

- All roles in expected roster activate
- All API claims verified
- Plugin parses and would load (verified via setup test harness)
- README exists with installation + usage
- No leaked references in lifecycle audit
- UndoRedo flow correct
- Studio composite score for this ticket: ≥75
