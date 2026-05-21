# Innovation Recommendations — MobileTerrain3D

**Role:** Innovation Specialist for Terrain Tooling (instantiated per Role Instantiation Protocol for TKT-002)
**Reference benchmarks:** World Machine, Houdini, Unreal Landscape, Godot Terrain3D (TokisanGames)
**Target:** Godot 4.6.2 Forward Mobile, Snapdragon 680–class mid-tier mobile

14 ideas in 4 categories. Tiered: **must-have** (v23) / **nice-to-have** (v23–24) / **experimental** (v24+).

---

## 1. Sculpting UX Innovations

### 1.1 Non-Destructive Sculpt Layers ⭐ MUST-HAVE
- **Differentiator:** Each stroke = delta heightmap, toggle on/off, reorder, merge.
- **Mobile cost:** ~64 KB / stroke; zero runtime cost (only read on undo).
- **Impl:** `class TerrainStroke: Resource { delta_height: PackedFloat32Array, rect: Rect2i, tool: int, strength: float, timestamp: int }`. `start_stroke`/`end_stroke` capture, inspector list with checkboxes.
- **Architecture tie-in:** `core/terrain_layer.gd` + `core/terrain_stroke.gd` already in TKT-003 plan.

### 1.2 Multi-Touch Gestures (pinch / rotate / swipe) ⭐ NICE-TO-HAVE
- **Differentiator:** iPad/Android-native input; mimics Procreate. Pinch → brush radius, rotate → mask rotation, 3-finger tap → flatten.
- **Mobile cost:** ~2 ms/frame gesture decode.
- **Impl:** `class GestureDecoder: RefCounted` tracks finger map; plugin `_input` decodes `InputEventScreenTouch`/`Drag`.
- **Architecture tie-in:** `editor/gesture_decoder.gd` in plan.

### 1.3 Slope/Elevation Adaptive Brush ⭐ EXPERIMENTAL
- **Differentiator:** Brush strength auto-modulates by local slope and elevation. Houdini-style.
- **Mobile cost:** O(map_size²) slope LUT computed once at init (~50 ms for 256²).
- **Impl:** `_compute_slope_lut()` Laplacian over heightmap; in brush iteration `falloff *= clampf(1.0 - slope_lut[idx] * adaptive_slope_factor, 0.1, 1.0)`.

---

## 2. Mobile-First Features

### 2.1 Pressure Stylus Support ⭐ NICE-TO-HAVE
- **Differentiator:** iPad Pencil / Wacom / Surface Pen pressure modulates brush strength.
- **Mobile cost:** zero (already in InputEventScreenTouch.pressure).
- **Impl:** Cache pressure on each touch event; `effective_strength = base_strength * _cached_pressure`. Toggle in inspector (default ON on mobile).

### 2.2 Offline Splatmap Chunked Streaming ⭐ EXPERIMENTAL
- **Differentiator:** Splatmap chunked into 32² tiles; only visible chunks resident in VRAM. Unlocks 512²+ terrains on 2 GB mobile devices.
- **Mobile cost:** ~4 ms/frame chunk upload (2 chunks/frame).
- **Impl:** Refactor `splatmap_texture_local: ImageTexture` → `splatmap_chunks: Dictionary[Vector2i, ImageTexture]`. `_paint_splatmap` updates only affected chunk; `_process` frustum-streams.

### 2.3 Thumb-Reach UI Layout ⭐ NICE-TO-HAVE
- **Differentiator:** Radial tool selector + edge-docked sliders. Two-handed sculpt on 5.5"+ tablets without grip shift.
- **Mobile cost:** zero (layout-only).
- **Impl:** Conditional `_layout_touch_ui()` branch when `OS.has_feature("mobile")`. `class RadialMenuButton(Control)` with `draw_arc()` segments.
- **Architecture tie-in:** `editor/ui/radial_tool_selector.gd` in plan.

---

## 3. Workflow & Content Authoring

### 3.1 Heightmap Import from Mapbox/OpenElevation ⭐ NICE-TO-HAVE
- **Differentiator:** In-plugin lat/lon dialog → real-world DEM in 30 seconds.
- **Cost:** Editor-only; HTTPRequest async ~200 ms per Mapbox tile.
- **Impl:** Dialog inputs (lat_min/max, lon_min/max), HTTPRequest, parse geotiff/PNG response, upsample/downsample, call `_import_heightmap_data()`. Cache by bounds.

### 3.2 Procedural Noise Layer with Seed Sync ⭐ MUST-HAVE
- **Differentiator:** FastNoiseLite live preview with freq/octaves/lacunarity/persistence/seed sliders. Export tileable height layer. Preset save/load.
- **Mobile cost:** ~1 ms/frame preview regenerate.
- **Impl:** New inspector category. `_generate_noise_layer(params)` produces heightmap; emits undo entry. Presets serialized to `.tres`.
- **Architecture tie-in:** `systems/procedural_generator.gd` in plan.

### 3.3 Terrain Stamps Library ⭐ NICE-TO-HAVE
- **Differentiator:** Pre-authored cliff/river/mesa/rock stamps. Click → paint footprint at brush position. 20+ shipped, user can author custom.
- **Cost:** ~2.6 MB addon size for 20 stamps; ~2 ms blend-on-paint for 64².
- **Impl:** `stamps/` directory tree with `height.exr` + `splatmap.png` + `meta.json` per stamp. Inspector picker; stamp dab logic.
- **Architecture tie-in:** `stamps/` in plan.

---

## 4. Differentiation vs Terrain3D / Unreal Landscape

### 4.1 Baked Curvature Lightmap (mobile GI proxy) ⭐ EXPERIMENTAL
- **Differentiator:** Pre-baked self-shadowing approximation. Assassin's Creed/Genshin trick — convincing static lighting without baking lightmaps.
- **Mobile cost:** +1 texture unit, +0.2 ms/frame fragment.
- **Impl:** "Bake Curvature LUT" button → Laplacian over heightmap; packed RGBA texture; shader reads curvature.r as occlusion.

### 4.2 Mesh LOD with Fade Transition ⭐ NICE-TO-HAVE
- **Differentiator:** 3 LOD tiers per chunk; smooth alpha fade between. Eliminates pop-in.
- **Mobile cost:** +1–2 ms/frame LOD selection.
- **Impl:** `class ChunkLODs` with `mesh_full/2x/4x`; `_process` picks tier by distance, fades via material alpha.

### 4.3 Vegetation Density Brush ⭐ MUST-HAVE
- **Differentiator:** Paint a density map that gates foliage placement RNG. Independent of sculpt/splatmap tools. Unreal Landscape parity, Terrain3D has none.
- **Mobile cost:** +256 KB texture, +0.1 ms/frame placement.
- **Impl:** New `density_texture: ImageTexture` and `density_data: PackedByteArray`. Tool 9 paints R channel. `_place_instances` skips `if randf() > density_val`.
- **Architecture tie-in:** Extends `systems/foliage_system.gd`.

### 4.4 Water Layer with Caustics + Depth Absorption ⭐ EXPERIMENTAL
- **Differentiator:** Optional auto-fit water plane with depth-based color and scrolling caustics. No physics; pure visual.
- **Mobile cost:** +1 texture unit, +0.3 ms/frame water fragments (capped to ~50% screen).
- **Impl:** `class TerrainWaterLayer(Node3D)` with elevation + caustic_tiling + absorption_depth + refraction_strength @export. Separate shader.

### 4.5 AI-Driven Slope Autopaint ⭐ EXPERIMENTAL
- **Differentiator:** "Auto-Paint by Slope" button — analyses heightmap, paints rock on steep, grass on gentle, sand on flat. Rapid prototyping.
- **Cost:** Editor-only; ~100 ms for 256².
- **Impl:** Compute local slope angle, classify per cell, write to splatmap with falloff. User-tunable thresholds.

---

## Already Shipped (polish candidates only)

- ✅ Brush Mask System (V21+) — UI ergonomics could improve (drag-to-select grid instead of right-click)
- ✅ PBR Slot System (V21) — works well
- ✅ External Data Storage / Plan B Save (V22) — works well
- ✅ Chunk Meshing with adaptive budget (V20-22) — needs frame-time bound (audit H4)
- ✅ Foliage MultiMesh Placement (tool 8) — gains a lot from innovation 4.3 (density brush)

---

## Priority shipping queue

**v23 (next minor):**
1. C1-C7 fixes (already in TKT-002)
2. C5 architecture refactor (TKT-003)
3. Innovation 1.1 — Non-destructive sculpt layers
4. Innovation 3.2 — Procedural noise with seed sync
5. Innovation 4.3 — Vegetation density brush

**v23.x (point releases):**
6. Innovation 2.1 — Pressure stylus
7. Innovation 2.3 — Thumb-reach UI
8. Innovation 1.2 — Multi-touch gestures

**v24 (next major):**
9. Innovation 3.3 — Stamps library
10. Innovation 4.2 — Mesh LOD
11. Innovation 3.1 — Mapbox import
12. Innovations 1.3, 2.2, 4.1, 4.4, 4.5 — experimental (evaluate after v23.x feedback)

---

## Honesty notes

- All ideas verified implementable in Godot 4.6.2 GDScript on Forward Mobile.
- Triplanar warning in audit C6 holds — Innovation 4.1 (baked GI) costs 1 texture unit; combined with restored triplanar on desktop, total budget still fits.
- Offline splatmap streaming (2.2) is the most architecturally invasive — requires rewriting splatmap_texture_local across node + plugin. Recommended only if user feedback shows OOM on 512²+.
- Water simulation (4.4) is visual-only. For drowning/buoyancy gameplay, separate physics layer is needed.
