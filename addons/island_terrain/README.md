# IslandTerrain 0.1 Foundation

Mobile-first Godot 4.6.3 terrain foundation for a 4 km survival island. This milestone establishes the data, streaming, rendering and future digging contracts without replacing the existing `MobileTerrain3D` add-on.

## Current capabilities

- Versioned `IslandTerrainManifest` with a canonical 4 km / 256 m region layout.
- Translation-aware canonical coordinate system shared by runtime/editor callers.
- Sparse `IslandTerrainRegionData`; only the height channel is allocated for a new region. Paint, biome, wetness, holes and foliage channels are allocated on first use.
- Live RAM accounting for lazy channels. Cache totals update when a region grows, and the oldest clean region is evicted when the profile budget is exceeded.
- Dirty regions are never silently evicted.
- Runtime copy-on-write storage: packaged/source regions remain under `res://`, while changed runtime regions are saved under `user://`.
- Verified atomic region saves: temporary resource, reload and dimension/full-array checksum validation, previous-file backup, then promotion.
- Camera-following indexed geometry clipmap with centre grid, hollow LOD rings and outer skirts.
- All rings share one snapped centre until trim meshes are introduced, preventing fine/coarse ring gaps.
- Seven-level maximum clipmap coverage. A 64-quad, seven-level profile reaches a 2048 m radius and covers the default 4 km island.
- Frame-budgeted mesh construction: at most one LOD level is created per frame.
- Shared terrain material with per-instance LOD/skirt uniforms; distant shadow LODs are limited by device profile.
- Incremental deterministic island preview generation. Noise rows are generated under a per-frame CPU budget instead of one blocking operation.
- Mobile-safe RF macro height texture capped at 257 or 513 samples for runtime profiles.
- Stable deformation backend contract for the later sparse voxel/SDF digging phase.
- Headless foundation tests covering coordinates, sparse memory, clipmap topology and runtime copy-on-write persistence.

## Enable

1. Open **Project > Project Settings > Plugins**.
2. Enable **IslandTerrain**.
3. Add an `IslandTerrain3D` node to a 3D scene.
4. Keep the project renderer set to **Mobile**.
5. Start with the **Balanced** device profile.

The node creates internal clipmap children that are visible in the 3D viewport but are not serialized into the scene. Heavy height and region data remain external to `.tscn` files.

The terrain node may be translated, but it must retain identity rotation and unit scale. Render sampling, coordinate conversion and `get_height_at_world()` use the same translated origin.

## Mobile profiles

| Profile | Macro height | Clipmap | Base quads | Cached regions | Shadow LODs | CPU budget |
|---|---:|---:|---:|---:|---:|---:|
| Low | 257² RF | 5 levels | 48 | 5 | 1 | 1 ms/frame |
| Balanced | 257² RF | 6 levels | 64 | 9 | 2 | 2 ms/frame |
| High | 513² RF | 7 levels | 80 | 25 | 4 | 3 ms/frame |
| Editor Preview | 513² RF | 7 levels | 64 | 9 | 2 | 2 ms/frame |

`High` is not the default for phones. The Redmi Note 8 Pro / Mali-G76 class should begin with `Balanced`; quality increases must be based on profiler evidence.

## Persistence paths

- Authoring/source data: `res://terrain_data/island_01`
- Runtime overrides: `user://terrain_data/island_01`
- Runtime loading order: writable override → validated backup → packaged/source region
- Runtime autosave: at most one dirty region per frame
- Explicit save point: `flush_pending_saves()`

This prevents an exported Android build from attempting to write into packaged `res://` content.

## Test

Run from a Godot project root containing this add-on:

```bash
godot --headless --path . --editor --quit-after 3
godot --headless --path . --script addons/island_terrain/test/foundation_test.gd
```

The repository includes `.github/workflows/island-terrain-foundation.yml` for Godot 4.6.3 headless validation.

Current validation state for this branch: official API compatibility and static architecture reviews were performed, but no successful Godot 4.6.3 runner result has been observed yet. The pull request must remain draft until the parser and foundation test commands complete successfully.

## Architectural boundaries

- Rendering never reads or writes files.
- Region persistence never owns scene nodes or rendering RIDs.
- Editor/runtime callers use the coordinate system instead of duplicating region conversion math.
- Heightfield code depends only on the deformation interface, never on a concrete voxel backend.
- Internal clipmap meshes are generated once and repositioned; camera movement does not rebuild meshes.
- Material state is shared; LOD-specific values use instance uniforms rather than cloned materials.
- Full 4097² heightmaps are prohibited in the runtime foundation. Detailed terrain is streamed by region in later milestones.
- Region channel allocation must pass through `IslandTerrainRegionData` methods so live memory accounting cannot be bypassed.

## Next milestone

The next implementation phase adds the sculpt command pipeline, dirty-rectangle texture uploads, undo/redo deltas, region-to-macro height synchronization and a touch-oriented editor toolbar. Digging remains disabled until the heightfield editor, persistence and collision streaming pass their acceptance tests.
