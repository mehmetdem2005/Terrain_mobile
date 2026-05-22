@tool
class_name TerrainConstants
extends RefCounted

# Centralised numeric tunables for the MobileTerrain3D addon.
# Re-exported as static constants so they can be referenced as
# TerrainConstants.SYNC_BUILD_CHUNK_LIMIT from anywhere without a
# RefCounted instance.

# Chunk lifecycle thresholds.
const SYNC_BUILD_CHUNK_LIMIT := 256  # > this many chunks → deferred build
const SYNC_REBUILD_CHUNK_LIMIT := 256  # force_update_all switch point
const MAX_CHUNK_COUNT := 1024  # auto-bump chunk_size trigger
const MAX_CHUNK_PER_FRAME := 64  # adaptive _process budget upper bound
const MIN_CHUNK_PER_FRAME := 4  # adaptive _process budget lower bound
# TKT-004 H4: wall-clock cap on the per-frame chunk rebuild loop. A chunk's
# mesh cost scales with chunk_size, so a fixed chunk COUNT can still blow
# the frame budget on large maps (a 256-wide chunk meshes far slower than a
# 32-wide one). 8000µs (~8ms) keeps the rebuild under half a 60fps frame
# even when MAX_CHUNK_PER_FRAME chunks would individually be too slow.
const MAX_CHUNK_REBUILD_USEC := 8000

# Storage thresholds.
# TKT-006: lowered 262144 (512²) -> 65536 (256²). map_size DEFAULTS to 256,
# so the old 512² threshold meant the default terrain (256² = 65536 cells,
# ~256KB heights + ~256KB splatmap) never auto-externalised and got baked
# inline into the .tscn as base64 — producing the multi-MiB "large text
# resource" scenes users were hitting on a plain save. At 256² the default
# terrain now externalises to a .res companion on first save; only small
# prototype terrains (<256²) stay inline, where the cost is negligible.
const AUTO_EXTERNALIZE_THRESHOLD := 65536  # 256² cells → auto-externalise

# Stroke throttling intervals (seconds between applied dabs).
const MIN_STATIONARY_INTERVAL := 0.04  # ~25 Hz cap for sculpt/paint
const MIN_OBJECT_INTERVAL := 0.08  # ~12 Hz cap for foliage scatter

# Brush slider clamps.
const BRUSH_RADIUS_MIN := 1.0
const BRUSH_RADIUS_MAX := 50.0
const BRUSH_STRENGTH_MIN := 0.1
const BRUSH_STRENGTH_MAX := 2.0

# Map sizing clamps.
const MAP_SIZE_MIN := 4
const MAP_SIZE_MAX := 16384  # extreme upper bound

# Splatmap.
const SPLATMAP_SLOT_COUNT := 4  # RGBA8 → 4 channels

# Auto-bump chunk size progression for large maps (chosen so map_size %
# chunk_size == 0 stays valid for typical power-of-two map sizes).
const AUTO_CHUNK_SIZE_LADDER: Array = [64, 128, 256, 512, 1024]
