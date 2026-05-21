# Module Gap Audit — MobileTerrain3D

**Role:** Module Gap Analyst (instantiated per Role Instantiation Protocol for TKT-002)
**Scope:** All 10 plugin .gd files
**Total gaps identified:** 32 across 10 categories

This role identifies what is **currently missing from existing modules** to make them production-quality — *not* new features (that is the Innovation Specialist's domain).

---

## Category 1 — Documentation gaps

| ID | Where | Gap | Impact |
|----|-------|-----|--------|
| G1.1 | `mobile_terrain_plugin.gd:1` | No top-level `##` docstring explaining plugin lifecycle, brush cursor lifecycle, undo strategy | New maintainers can't grasp intent without code-archaeology |
| G1.2 | `mobile_terrain_node.gd:1335, 1380, 1700, 1745, 1790, 1797, 1839, 1885, 1890, 1906, 1927` | 11 public methods (`get_height`, `initialize_terrain`, `force_update_all`, etc.) lack `##` docstrings | Script users can't discover API contracts |
| G1.3 | `mobile_terrain_node.gd:233, 241` | Signals (`foliage_placed`, `brush_applied`) have parameters but no doc | Can't connect correctly without reading emit() callsites |

**Fix:** Add `##` blocks documenting inputs, outputs, preconditions, examples.

---

## Category 2 — API symmetry & query helpers

| ID | Where | Gap | Recommendation |
|----|-------|-----|----------------|
| G2.1 | `mobile_terrain_node.gd:1335 get_height` | Silent clamping; users assume out-of-bounds errors | Add `clamp: bool = true` parameter |
| G2.2 | `mobile_terrain_node.gd:1890, 1906` | No `is_stroke_active() -> bool` query for external UI gating | Add it |
| G2.3 | `systems/brush_system.gd` | No `get_footprint_bounds(cx, cz, r) -> Rect2i` or `get_falloff_grid() -> PackedFloat32Array` | Add for inspector preview UI |
| G2.4 | `save_orchestrator.gd` | No pre-save / post-restore signals/hooks | Add `pre_save_terrains(terrains)` and `post_restore_terrains(terrains)` |

---

## Category 3 — Hardcoded values that should be configurable

| ID | Where | Constant | Recommendation |
|----|-------|----------|----------------|
| G3.1 | `mobile_terrain_node.gd:2031-2052` | Per-tool strength multipliers (0.5, 0.1, 0.2, ...) buried in `_apply_brush_single` | Move to `terrain_constants.gd: TOOL_STRENGTH_MULTIPLIERS: Array` |
| G3.2 | `mobile_terrain_node.gd:1943-1950, 1970-1972` | `MIN_OBJECT_INTERVAL=0.08`, `MIN_STATIONARY_INTERVAL=0.04`, step_dist=0.1 | Move to TerrainConstants; expose `@export_range` |
| G3.3 | `mobile_terrain_node.gd:1362-1368, 1713` | Chunk budget constants (`MAX_CHUNK_PER_FRAME=64`, `MIN_CHUNK_PER_FRAME=4`, `SYNC_REBUILD_CHUNK_LIMIT=256`); `:1713` duplicates value | De-duplicate, single TerrainConstants source |
| G3.4 | `systems/raymarch_system.gd:51-52` | `max_iters cap 8000`, `early_term_y_offset -200` magic constants | TerrainConstants: `RAYMARCH_MAX_ITERATIONS`, `RAYMARCH_EARLY_TERM_OFFSET` |
| G3.5 | `mobile_terrain_node.gd:335-336` | `noise_gen.frequency = 0.1` hardcoded | `@export var noise_frequency: float = 0.1` |

---

## Category 4 — Diagnostics gaps

| ID | Where | Missing | Recommendation |
|----|-------|---------|----------------|
| G4.1 | `mobile_terrain_node.gd:837, 901, 906, 948, 953, 1000, 1010, 1020, 1267, 1278, 1291, 1309, 1313, 1418, 1756` | 15 `push_warning` calls without MT-* codes | Convert to `TerrainDiagnostics.warn(MT-WXX, ...)`. Add codes MT-W14..MT-W28 |
| G4.2 | `mobile_terrain_node.gd:275-297 _set_external_data_path` | No `E_EXTERNAL_LOAD_CORRUPTED` / `E_EXTERNAL_LOAD_WRONG_SCHEMA` codes | Add — also tie into TKT-002 C1 fix |
| G4.3 | `mobile_terrain_plugin.gd:655-657` | Brush-mask load silent fail | Emit `MT-W15` on null load |

---

## Category 5 — Safety guards

| ID | Where | Missing | Recommendation |
|----|-------|---------|----------------|
| G5.1 | `mobile_terrain_node.gd:2057-2059` | `current_paint_slot` not clamped at setter, only warned at use | Add `_set_current_paint_slot` clamping to `[0, SPLATMAP_SLOT_COUNT-1]` |
| G5.2 | `mobile_terrain_node.gd:101-135` | `_set_brush_radius` / `_set_brush_strength` clamp but undocumented bounds | Add `##` docstring explaining ranges |
| G5.3 | `mobile_terrain_node.gd:2157-2173` | `_mark_chunk_dirty` no re-entrancy guard if called during `_process` iteration | Add deferred-mark path |
| G5.4 | `mobile_terrain_node.gd:1797-1810` | `garbage_collect_multimeshes` loops `asset_meshes` without `null` check | Add `if m == null: continue` |
| G5.5 | `mobile_terrain_node.gd:1306-1327` | `_load_external_data_if_set` checks type AFTER `load()` (RCE risk) | **Fixed in TKT-002 C1** |

---

## Category 6 — Missing public API surface

| ID | Where | Missing | Recommendation |
|----|-------|---------|----------------|
| G6.1 | `mobile_terrain_node.gd` | No `get_terrain_aabb() -> AABB` | Add — needed for external culling / collision |
| G6.2 | `mobile_terrain_node.gd` | No `get_min_height()` / `get_max_height()` / `get_average_height()` | Add — cached, maintained by brush ops |
| G6.3 | `mobile_terrain_data.gd` | No `static create_empty(map_size: int) -> MobileTerrainData` | Add factory |
| G6.4 | `mobile_terrain_data.gd` | No `schema_version: int` field; no migration path | Add — needed before any field changes in V23+ |
| G6.5 | `mobile_terrain_node.gd` | No `apply_height_delta(x, z, delta)` public method | Add — for procedural/scripted edits |
| G6.6 | `mobile_terrain_node.gd` | No batch `apply_brush_strokes(Array[BrushStroke])` with single undo action | Add — for procedural systems and innovation 1.1 (layers) |

---

## Category 7 — Module boundary issues

| ID | Where | Problem | Recommendation |
|----|-------|---------|----------------|
| G7.1 | `mobile_terrain_plugin.gd` (2031 lines) | God-class | **Plan in TKT-003 architecture-plan.md** |
| G7.2 | `mobile_terrain_node.gd:2157-2173` + `mobile_terrain_plugin.gd` | `_mark_chunk_dirty` private; plugin can't invalidate after script-level mutation | Make public `mark_chunk_dirty` |
| G7.3 | `mobile_terrain_node.gd:1713` | Duplicates `SYNC_REBUILD_CHUNK_LIMIT` (already in TerrainConstants) | Remove local const, use TerrainConstants |

---

## Category 8 — Resource lifecycle

| ID | Where | Missing | Recommendation |
|----|-------|---------|----------------|
| G8.1 | `mobile_terrain_data.gd` | No `duplicate() -> MobileTerrainData` | Add deep-copy method |
| G8.2 | `mobile_terrain_node.gd:1306-1327` | No validation `height_data.size() == map_size²` after load | **Fixed in TKT-002 C1** (M14 closed) |
| G8.3 | `mobile_terrain_node.gd` | No `_exit_tree` cleanup → dangling undo refs on terrain deletion | Add `_exit_tree` clearing undo state |

---

## Category 9 — Test coverage gaps

| ID | Module | Missing tests |
|----|--------|---------------|
| G9.1 | `mobile_terrain_plugin.gd` | Brush state machine, slider sync, asset manager slot mutation, plugin enable/disable cycle |
| G9.2 | `save_orchestrator.gd` | Multi-terrain save with failure rollback, restore callback timing |
| G9.3 | `brush_mask_picker` | Missing PNG, importer lag (ResourceLoader.exists temporarily false) |

**All covered by TKT-003 architecture plan** (`tests/` directory layout).

---

## Category 10 — Design documentation gaps

| ID | Where | Missing | Recommendation |
|----|-------|---------|----------------|
| G10.1 | `mobile_terrain_node.gd:2093-2099` | Splatmap normalization (competitive blend) explained inline only | Add to shader comment + DESIGN.md |
| G10.2 | `mobile_terrain_node.gd:1532-1556` | Chunk boundary seam-welding undocumented in public design | Add to DESIGN.md (chunk layout + map_size divisibility) |
| G10.3 | `mobile_terrain_plugin.gd:216-256` | Custom out-of-band undo strategy (foliage signal vs property) undocumented | Add module-level comment + DESIGN.md section |

---

## Priority remediation queue

**Already addressed in TKT-002:**
- ✅ G5.5 (RCE risk → C1 fix)
- ✅ G8.2 (schema validation → C1 fix)
- ✅ G2.4 (security ~ external_data_path scope) partial

**TKT-003 Phase A (systems extraction):**
- G2.2 `is_stroke_active()`, G2.3 brush helpers, G3.1-G3.5 constants migration, G5.1 paint_slot clamp, G5.4 null guards, G6.1-G6.6 API surface, G7.2-G7.3 boundary cleanups, G8.1 `duplicate()`, G8.3 `_exit_tree`.

**TKT-003 Phase C (UI/polish):**
- G1.1-G1.3 docstrings, G2.1 clamp param, G4.1-G4.3 diagnostic codes, G5.2-G5.3 safety, G10.1-G10.3 DESIGN.md sections.

**Standalone polish PRs:**
- `gdformat .` for cosmetic 340 lint issues.
- Migration of MT-* codes (G4.1) — one PR per category.
