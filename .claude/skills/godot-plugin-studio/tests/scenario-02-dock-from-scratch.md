# Scenario 02 — Dock Plugin From Scratch

## Setup

> User: "I need a dock plugin for Godot 4.6 that shows a list of all `@tool` scripts in my project, with a button to open each one in the script editor. Should refresh when scripts are added or removed."

## Expected triage

- **Size**: L
- **Mobile flag**: false (user didn't mention; default desktop)
- **Roster**: standard L + Dock Specialist + Editor Integration Engineer

## Expected behaviors

1. **Filesystem scanning** — design how to find `@tool` scripts (grep / EditorFileSystem API / both)
2. **Dock slot selection** — choose a sensible default (e.g., `DOCK_SLOT_RIGHT_BL`)
3. **EditorFileSystem signal connection** — `filesystem_changed` signal to refresh
4. **Open in editor** — use `EditorInterface.edit_script(script)` or `EditorInterface.edit_resource(...)`
5. **Signal symmetry** — connect to filesystem_changed in `_enter_tree`, disconnect in `_exit_tree`
6. **Performance** — for large projects, scanning may be slow; defer with `call_deferred` or use `EditorFileSystem`'s API

## Planted complexities

| Trap | What should happen |
|------|--------------------|
| Naively recursive directory scan | Performance Engineer flags; suggests EditorFileSystem |
| Reading file content to find `@tool` (instead of API path) | Tools Lead questions; alternative: read script via ResourceLoader and check |
| Forgetting `EditorFileSystem` filesystem_changed disconnect | Signal Specialist catches |
| Hardcoded "@tool" detection that misses `tool` (legacy 3.x) | Edge Case Hunter notes that 3.x scripts won't be detected — is that intended? |

## Expected deliverable

`addons/tool_script_dock/`:
- `plugin.cfg`
- `plugin.gd`
- `tool_script_dock.gd` — Control subclass for the dock UI
- `script_scanner.gd` — helper for finding @tool scripts
- `README.md`

## Scoring rubric

| Role | Max | Notes |
|------|-----|-------|
| Dock Specialist | 100 | Slot choice, layout, refresh logic |
| Editor Integration Engineer | 80 | `add_control_to_dock` / `remove_control_from_docks` pair |
| Signal System Specialist | 80 | filesystem_changed connection lifecycle |
| Frame-time Specialist | 60 | Scan performance assessment |
| API Verification Specialist | 80 | Verifies EditorFileSystem and EditorInterface APIs |
| Honesty Auditor | 90 | API claims verified |
| QA Lead | 70 | Tests project with 0, 1, 100 scripts |
| Polish Lead | 50 | Empty-state message, refresh feedback |
