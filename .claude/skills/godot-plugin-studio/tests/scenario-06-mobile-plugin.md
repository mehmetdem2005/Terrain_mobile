# Scenario 06 — Mobile-Targeted Plugin

## Setup

> User (in Turkish): "Godot Android Editor'da çalışacak bir dock plugin'i istiyorum. Sahnedeki tüm Node2D'leri listesin, her birine dokununca o node'a focus olsun (kamera ona gitsin). Touch için optimize edilsin, mobile performance düşmesin. Mobile renderer'da test edilebilsin."

## Expected triage

- **Size**: XL (mobile-targeted with full XL gates)
- **Mobile flag**: TRUE — mobile roster activates
- **Kind**: new
- **Roster**: full XL + mobile add-on roster:
  - **Mobile Renderer Specialist**
  - **Android Editor Specialist**
  - **Mobile Performance Specialist**
  - **Cross-Platform Compatibility Engineer**
  - **NOT** Android Plugin v2 Specialist (this is an EditorPlugin running in the Android editor, not a runtime Android plugin)

## Expected behaviors

1. **Android Plugin v2 Specialist disambiguation FIRST** — Before any other work, the studio confirms: this is an EditorPlugin that runs in the Godot Android Editor, not an Android Plugin v2. The user's phrasing ("Godot Android Editor'da çalışacak") makes this clear, but the specialist should explicitly note the disambiguation.

2. **Mobile Renderer Specialist** reviews: plugin doesn't add rendering features that don't work on Forward Mobile. (Simple dock with list — should be fine.)

3. **Android Editor Specialist** reviews:
   - Touch target sizes: list items must be ≥44px tall
   - No right-click context menu (none expected here)
   - Refresh button must be touch-tappable
   - Dock layout works in compressed (small-screen) mode
   - No keyboard shortcuts required

4. **Mobile Performance Specialist** sets budgets:
   - Plugin enable on mid-tier Android: <200ms
   - Dock list update: <33ms (one frame at 30fps)
   - RAM overhead: <50MB

5. **Cross-Platform Compatibility Engineer** verifies:
   - Plugin works on desktop AND Android editor
   - No desktop-only APIs used
   - File paths stay in `res://`

6. **Inspector Specialist** is NOT in this ticket (no inspector work)

7. **Dock Specialist** handles the dock implementation

8. **Performance Budget Officer** enforces mobile-specific budgets

## Planted complexities

| Trap | What should happen |
|------|--------------------|
| Plugin uses `_process` to poll selection state | Mobile Performance Specialist flags — should be event-driven (`EditorSelection.selection_changed` signal) |
| Plugin sets WorldEnvironment values to "highlight" focused node | Mobile Renderer Specialist flags — WorldEnvironment changes affect all rendering, plus may trigger Forward+-only features |
| Plugin uses `Camera2D.position = node.position` for "focus" | Scene Tree Specialist notes — the camera concept in editor is the editor camera, not user's Camera2D node |
| "Focus" implementation actually means: select the node + scroll viewport to it via `EditorInterface.edit_node` and `EditorPlugin.get_viewport_container()` | Editor Integration Engineer guides the correct approach |
| Plugin scans full scene tree every frame | Frame-time Specialist + Mobile Performance Specialist both flag |
| User says "touch için optimize edilsin" but doesn't specify how | End-User Advocate translates: ≥44px touch targets, large hit areas, no fine-grained drag |

## Expected deliverable

`addons/node2d_focus_dock/`:
- `plugin.cfg`
- `plugin.gd`
- `node2d_focus_dock.gd` — main dock UI (Control)
- `node_lister.gd` — efficient enumeration logic
- `README.md` (mention: tested on Forward Mobile renderer; Godot Android Editor compatible)
- `TUTORIAL.md`
- `LICENSE`

Total LOC: ~400-600

## Scoring rubric

| Role | Max | Notes |
|------|-----|-------|
| **Android Plugin v2 Specialist** | 60 | Performs disambiguation FIRST; correctly stands down |
| **Mobile Renderer Specialist** | 100 | Confirms no Forward+-only features; reviews any rendering changes |
| **Android Editor Specialist** | 100 | Touch sizes, no right-click, layout in compressed mode |
| **Mobile Performance Specialist** | 100 | Budgets defined, measured, met |
| **Cross-Platform Compatibility Engineer** | 80 | Desktop + Android editor both work |
| Dock Specialist | 80 | Dock implementation correct |
| Scene Tree Specialist | 80 | Catches `get_tree()` vs `get_edited_scene_root()` confusion if it arises |
| Editor Integration Engineer | 80 | Lifecycle symmetry |
| Performance Budget Officer | 70 | Mobile budgets enforced |
| Frame-time Specialist | 60 | `_process` polling caught and replaced |
| Tutorial Writer | 50 | Mobile-specific notes in tutorial |
| Architecture Review Board | 60 | All 3 seats |
| Studio Head | 60 | Sign-off |

## Pass criteria

- All four mobile specialists activate
- Android Plugin v2 disambiguation happens
- Mobile performance budgets are met (or measured-and-justified-exception)
- Plugin would work in Godot Android Editor (per Android Editor Specialist's review)
- Studio composite score for this ticket: ≥75

## Critical failure mode

If the studio confuses this with an Android Plugin v2 request and starts writing Kotlin/Java code, it has failed catastrophically. Android Plugin v2 Specialist's disambiguation step must run before implementation.
