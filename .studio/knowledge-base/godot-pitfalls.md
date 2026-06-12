# Godot Pitfalls — Encountered

Pitfalls this studio has encountered in real tickets. Grows over time. Entries link back to tickets so context is recoverable.

## Format

```
## <Short title>
- Encountered: YYYY-MM-DD
- Tickets: TKT-NNN, TKT-MMM
- Description: [what went wrong]
- Mitigation: [what to do instead]
- Status: ACTIVE / SUPERSEDED / RESOLVED
```

## Entries

_(none yet — this project's first ticket will populate)_

## TKT-019 lessons (2026-06-12)

- **Image byte-bulk reads quantise float sources.** Converting any source to
  RGBA8 and indexing one byte per cell silently crushes EXR/16-bit heightmaps
  to 256 levels. For numeric image data, convert to `Image.FORMAT_RF` and use
  `get_data().to_float32_array()` — same bulk speed, full precision (verified
  on 4.6.2 binary). Convert BEFORE `resize()` so bilinear runs in float.
- **Constructor-baked caches need long-lived instances.** Moving a LUT bake
  into `_init` (TKT-004 H5) became a regression because both call sites built
  the object per dab. When optimising init-time work, grep every construction
  site for per-frame/per-dab patterns first.
- **Any flag that gates a queue/hold needs a release on toggle-off.** A plain
  `@export var enabled` that participates in a hold condition
  (`_lod_needs_seed`) deadlocks the queue when flipped off mid-hold; give it a
  setter that releases the hold and restores steady-state.
- **Headless dummy RenderingServer returns an EMPTY `MultiMesh.buffer`** even
  with instance_count > 0 (verified 4.6.2). Any buffer-splice logic must guard
  `size() > 0` or headless CI breaks.
- **`create_trimesh_collision` bakes the CURRENT mesh** — under editor LOD
  decimation that means wrong collision. Force full-res rebuild before baking.
