# IslandTerrain 0.1 Foundation

Mobile-first Godot 4.6 terrain foundation for a 4 km survival island. This milestone establishes the data, streaming, rendering and future digging contracts without replacing the existing `MobileTerrain3D` add-on.

## Current capabilities

- Versioned `IslandTerrainManifest` with a canonical 4 km / 256 m region layout.
- Sparse `IslandTerrainRegionData`; only the height channel is allocated for a new region. Paint, biome, wetness, holes and foliage channels are allocated on first use.
- RAM-budgeted LRU region repository. Dirty regions are never silently evicted.
- Verified atomic region saves: temporary resource, reload and dimension/checksum validation, previous-file backup, then promotion.
- Camera-following indexed geometry clipmap with centre grid, hollow LOD rings and outer skirts.
- Seven-level maximum clipmap coverage. A 64-quad, seven-level profile reaches a 2048 m radius and covers the default 4 km island.
- Frame-budgeted mesh construction: at most one LOD level is created per frame.
- Incremental deterministic island preview generation. Noise rows are generated under a per-frame CPU budget instead of one blocking operation.
- Mobile-safe RF macro height texture capped at 257 or 513 samples for runtime profiles.
- Stable deformation backend contract for the later sparse voxel/SDF digging phase.
- Headless foundation test script.

## Enable

1. Open **Project > Project Settings > Plugins**.
2. Enable **IslandTerrain**.
3. Add an `IslandTerrain3D` node to a 3D scene.
4. Keep the project renderer set to **Mobile**.
5. Start with the **Balanced** device profile.

The node creates internal clipmap children that are visible in the 3D viewport but are not serialized into the scene. Heavy height and region data remain external to `.tscn` files.

## Mobile profiles

| Profile | Macro height | Clipmap | Base quads | Cached regions | CPU budget |
|---|---:|---:|---:|---:|---:|
| Low | 257² RF | 5 levels | 48 | 5 | 1 ms/frame |
| Balanced | 257² RF | 6 levels | 64 | 9 | 2 ms/frame |
| High | 513² RF | 7 levels | 80 | 25 | 3 ms/frame |
| Editor Preview | 513² RF | 7 levels | 64 | 9 | 2 ms/frame |

`High` is not the default for phones. The Redmi Note 8 Pro / Mali-G76 class should begin with `Balanced`; quality increases must be based on profiler evidence.

## Test

Run from a Godot project root containing this add-on:

```bash
godot --headless --path . --script addons/island_terrain/test/foundation_test.gd
```

The test checks sample dimensions, world/region conversion, lazy region channels, memory profiles and clipmap mesh creation.

## Architectural boundaries

- Rendering never reads or writes files.
- Region persistence never owns scene nodes or rendering RIDs.
- Editor/runtime callers use the coordinate system instead of duplicating conversion math.
- Heightfield code depends only on the deformation interface, never on a concrete voxel backend.
- Internal clipmap meshes are generated once and repositioned; camera movement does not rebuild meshes.
- Full 4097² heightmaps are prohibited in the runtime foundation. Detailed terrain is streamed by region in later milestones.

## Next milestone

The next implementation phase adds the sculpt command pipeline, dirty-rectangle texture uploads, undo/redo deltas, region-to-macro height synchronization and a touch-oriented editor toolbar. Digging remains disabled until the heightfield editor, persistence and collision streaming pass their acceptance tests.
