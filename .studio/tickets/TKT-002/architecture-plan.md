# TKT-002 — AAA Architecture & UI/UX Plan

This document is the studio's plan for transforming MobileTerrain3D from
its current "two-god-class" structure into an AAA-grade modular plugin.
It is the deliverable for the "mimariyi AAA şekilde tasarla, UI/UX dahil
kur" portion of the user's request. Implementation lives in TKT-003.

---

## 1. Current state (problem)

| Concern | mobile_terrain_node.gd | mobile_terrain_plugin.gd | Total |
|---------|------------------------|---------------------------|-------|
| LOC | 2321 | 2031 | 4352 |
| % of plugin code | 43% | 38% | 81% |
| Public methods | 52 | 66 | 118 |
| `class-definitions-order` lint failures | 50 | (mixed in 153) | — |
| Subsystem boundaries | none | none | — |
| Undo/redo dispatch | string-based `add_do_method("force_update_all")` | string-based | brittle |

**Symptoms:**
- Adding a new brush tool requires touching both files + 3 callsites
- UI builder code drowns out plugin logic
- Cannot unit-test brush input handling without spinning up the full plugin
- Function rename in node.gd silently breaks undo restoration on save reload (audit H12)

---

## 2. Target state — AAA modular layout

```
addons/mobile_terrain/
├── plugin.cfg
├── CHANGES.md
├── DESIGN.md                          (NEW: architecture overview, this doc summarised)
│
├── core/                              ← stable primitives, no editor deps
│   ├── terrain_constants.gd           (exists)
│   ├── terrain_diagnostics.gd         (exists)
│   ├── terrain_data.gd                (exists: MobileTerrainData; ADD: schema_version, duplicate(), create_empty())
│   ├── terrain_brush_config.gd        (NEW: BrushConfig resource — radius, strength, mask, shape, tool)
│   ├── terrain_stroke.gd              (NEW: TerrainStroke resource — delta height + metadata, supports innovation 1.1)
│   └── terrain_layer.gd               (NEW: TerrainLayer resource — for non-destructive layering)
│
├── systems/                           ← pure computation, no editor / scene deps
│   ├── brush_system.gd                (exists: keep, expand with LUT)
│   ├── sculpt_ops.gd                  (exists: move 6 sculpt fns from node here)
│   ├── splatmap_system.gd             (NEW: extract _paint_splatmap, _initialize_splatmap)
│   ├── chunk_renderer.gd              (NEW: extract update_chunk_mesh, mesh caching)
│   ├── foliage_system.gd              (NEW: extract place_object + density brush)
│   ├── raymarch_system.gd             (exists: keep)
│   ├── heightmap_io.gd                (NEW: EXR/PNG import, chunked streaming for innovation 2.2)
│   └── procedural_generator.gd        (NEW: FastNoiseLite layer generation, innovation 3.2)
│
├── editor/                            ← editor-only, depends on systems/
│   ├── save_orchestrator.gd           (exists: keep)
│   ├── undo_recorder.gd               (NEW: typed undo/redo dispatch, replaces string-based add_do_method)
│   ├── input_router.gd                (NEW: extract _forward_3d_gui_input + gesture decoder)
│   ├── gesture_decoder.gd             (NEW: multi-touch pinch/rotate/swipe for innovation 1.2)
│   ├── brush_cursor.gd                (NEW: extract _create_brush_cursor + draping logic)
│   │
│   ├── ui/                            ← UI builders, themes
│   │   ├── theme.gd                   (NEW: central theme/colour resource — dark default, light/high-contrast variants)
│   │   ├── toolbar.gd                 (NEW: extract _build_main_ui toolbar portion)
│   │   ├── asset_manager_panel.gd     (NEW: extract _build_asset_manager_ui + slot rows)
│   │   ├── brush_mask_picker.gd       (NEW: extract brush mask popup + grid)
│   │   ├── radial_tool_selector.gd    (NEW: touch-first tool picker, innovation 2.3)
│   │   ├── inspector_extensions.gd    (NEW: EditorInspectorPlugin with custom property editors)
│   │   └── status_bar.gd              (NEW: live MT-* diagnostic surface for users)
│   │
│   └── icons/                         (NEW: SVG icons for MobileTerrain3D custom type + tools)
│       ├── MobileTerrain3D.svg
│       ├── tool_raise.svg / tool_flatten.svg / ... (one per tool)
│       └── brush_*.svg
│
├── shaders/
│   └── terrain.gdshader               (exists; will split into mobile/desktop variants in TKT-003)
│
├── stamps/                            (NEW: bundled terrain stamp library, innovation 3.3)
│   └── README.md
│
├── tests/                             ← extends /test/ with plugin-internal tests
│   ├── test_plugin_lifecycle.gd       (NEW: enable/disable/hot-reload cycles)
│   ├── test_cross_terrain_undo.gd     (NEW: catches audit H3)
│   ├── test_tool_switch_backup.gd     (NEW: catches audit H2)
│   ├── test_external_data_path.gd     (NEW: catches audit C1)
│   ├── test_signal_lifecycle.gd       (NEW: catches audit C2)
│   ├── test_brush_path_traversal.gd   (NEW: catches audit H10)
│   ├── test_splatmap_system.gd        (NEW)
│   ├── test_foliage_system.gd         (NEW)
│   └── test_chunk_renderer.gd         (NEW)
│
├── mobile_terrain_node.gd             (TRIMMED to ~500 lines: facade + @export props + signals)
└── mobile_terrain_plugin.gd           (TRIMMED to ~400 lines: lifecycle + delegation)
```

**Result:** each file ≤ 500 lines, single responsibility, no cyclic deps. 18 new files + 2 trimmed facades.

---

## 3. Dependency graph (acyclic, layered)

```
                  ┌─────────────────────────────┐
                  │  editor/ (UI, input, undo)  │   ← editor-only deps
                  └────────┬────────────────────┘
                           │
                  ┌────────▼────────────────────┐
                  │  systems/ (pure logic)      │   ← no editor deps
                  └────────┬────────────────────┘
                           │
                  ┌────────▼────────────────────┐
                  │  core/ (resources, consts)  │   ← no scene deps
                  └─────────────────────────────┘
```

Rules:
- `core/` files do not preload anything from `systems/` or `editor/`.
- `systems/` files may preload from `core/` only.
- `editor/` files may preload from `core/` and `systems/`.
- `mobile_terrain_node.gd` is a `Node3D` facade; uses `systems/` heavily.
- `mobile_terrain_plugin.gd` is an `EditorPlugin` facade; uses `editor/` and indirectly `systems/`.

Static analysis: a CI check will grep imports and fail if `core/` imports `systems/` or `editor/`. Cycle detector via `grep -rn 'preload\(' addons/mobile_terrain/`.

---

## 4. UI/UX redesign — AAA standards

### 4.1 Design system

Move from inline `Color(0.13, 0.13, 0.18, 0.5)` style hacks to a **`TerrainTheme: Resource`** with:
- Palette (background, panel, accent, success, warning, error)
- Typography (label, header, subtle)
- Spacing tokens (xs=2, sm=4, md=6, lg=12, xl=20)
- Three variants: `dark.tres` (default), `light.tres`, `high_contrast.tres`

**File:** `editor/ui/theme.gd` + `editor/ui/themes/*.tres`.

User can switch via plugin settings (`addons/mobile_terrain/.plugin_settings.cfg` — new file, not git-ignored, lives in project).

### 4.2 Touch-first layout (innovation 2.3)

Detect runtime: `OS.has_feature("mobile") or OS.has_feature("android_editor")` → switch to thumb-reach layout.

**Desktop layout (current):**
```
[Toolbar at top: brush toggle | size | strength | shape | tool | mask | manage]
                                  ↓ viewport
[Asset manager floats top-left at 20,80]
```

**Touch layout (new):**
```
                   ┌────────────────────┐
                   │  3D viewport       │
                   │                    │
[VSlider: size]    │   ●  brush cursor  │   [VSlider: strength]
                   │                    │
                   └────────────────────┘
[Radial tool picker — bottom-center, 56dp segments]
```

- Sliders dock to viewport edges so thumb reach is preserved on 5.5"+ tablets
- Radial picker: 8 segments (6 sculpt tools + paint + foliage); tap centre to swap dimension
- Long-press centre → opens mask picker (no top-of-screen reach)
- Asset manager: full-screen modal sheet on touch, floating panel on desktop

### 4.3 Inspector polish — EditorInspectorPlugin

Replace generic `@export` rendering with custom inspector for `MobileTerrain3D`:
- Heightmap section: visual mini-map preview (256×256 from current data) + buttons for import/export/clear
- Layers section (innovation 1.1): list of strokes with toggle / merge / delete / drag-reorder
- Procedural section (innovation 3.2): live noise preview, seed input, generate button
- Diagnostics section: live MT-* code feed (status_bar tied in)
- "Advanced" collapsible with tweakables currently hardcoded (audit gaps 3.1-3.5)

### 4.4 Tooltips, learnability, error recovery

Every interactive control gets:
- `tooltip_text` in user language (Turkish currently shipped)
- `focus_neighbor_*` set for keyboard navigation
- Error states: red border + sub-label explaining what went wrong (e.g., "Path must start with res:// or user://")

### 4.5 Onboarding

First-time-open detection (no `.plugin_settings.cfg`) → modal walkthrough:
1. "Create a MobileTerrain3D node" (with one-click button)
2. "Set map size and click Initialize"
3. "Toggle brush, sculpt, paint"
4. "Save scene — terrain auto-externalises"

Walkthrough modal lives in `editor/ui/onboarding.gd`. Skippable. Re-launchable from a "?" button in the toolbar.

### 4.6 Accessibility

- Colour-blind-safe palette (deuteranopia / protanopia tested)
- Keyboard shortcuts surfaced in tooltips: `B = brush toggle`, `1-9 = tool select`, `[`/`]` = brush size
- Screen-reader-friendly Control names (set `name` AND `tooltip_text`)
- Reduced-motion option: skips slider/picker fade transitions

---

## 5. Refactor strategy — 3 phases

### Phase A — Extract systems (TKT-003a, ~1 day)
1. Move `_paint_splatmap` + helpers → `systems/splatmap_system.gd` (`class_name SplatmapSystem`).
2. Move `update_chunk_mesh` + helpers → `systems/chunk_renderer.gd`.
3. Move `place_object` + foliage logic → `systems/foliage_system.gd`.
4. Move EXR import → `systems/heightmap_io.gd`.
5. node.gd delegates to systems via `_splatmap_system.paint(...)` etc.

Tests: `test_splatmap_system.gd`, `test_chunk_renderer.gd`, `test_foliage_system.gd` written **first** (TDD).

### Phase B — Extract editor controllers (TKT-003b, ~1 day)
1. Move undo dispatch → `editor/undo_recorder.gd` (typed: `record_height_delta(rect, before, after)`).
2. Move input routing → `editor/input_router.gd`.
3. Move brush cursor → `editor/brush_cursor.gd`.
4. Move UI builders → `editor/ui/{toolbar,asset_manager_panel,brush_mask_picker}.gd`.

Tests: `test_plugin_lifecycle.gd`, `test_cross_terrain_undo.gd`, `test_tool_switch_backup.gd` — runs in headless Godot via test harness project.

### Phase C — Polish + UX (TKT-003c, ~1 day)
1. Add `core/terrain_layer.gd` + Layers UI.
2. Add `editor/ui/theme.gd` + 3 theme variants.
3. Touch layout branch in `editor/ui/toolbar.gd`.
4. EditorInspectorPlugin with custom MobileTerrain3D inspector.
5. Onboarding walkthrough.

Each phase: dedicated PR, auto-merge per CLAUDE.md policy, post-merge regression sweep.

---

## 6. Risks and trade-offs

| Risk | Mitigation |
|------|------------|
| Breaking saved scenes during refactor | Migration shim in `mobile_terrain_node.gd._ready` — accepts old inline data, lazy-converts on save |
| User scripts referencing internal methods break | Public API stays on node.gd facade; only private `_*` methods move into systems |
| Slower iteration during refactor | All TDD: tests written first, refactor proceeds only when test passes |
| Touch layout regression on desktop | Feature-detect via `OS.has_feature` not `OS.get_name` — desktop path unchanged unless explicit override |
| EditorInspectorPlugin adds binding cost | Lazy-attach: only instantiate when a MobileTerrain3D is selected; remove on deselect |

---

## 7. Definition of Done (TKT-003 completion criteria)

- [ ] All 10 plugin .gd files migrated to new structure
- [ ] node.gd + plugin.gd both < 600 lines
- [ ] Each new system has unit test with ≥ 80% line coverage
- [ ] `gdlint` clean (all max-line-length, class-definitions-order, max-file-lines resolved)
- [ ] `godot --headless --script ... --check-only` clean for all .gd in project context
- [ ] Touch layout renders on Godot Android Editor without overflow
- [ ] EditorInspectorPlugin: heightmap mini-map renders for 256² and 1024² terrains
- [ ] Onboarding walkthrough complete from blank scene to first paint stroke
- [ ] Honesty Auditor: every claim cites file:line; every API verified against XML reference
- [ ] CHANGES.md updated with V23 entry covering all the above
