@tool
class_name TerrainConstants
extends RefCounted

# Centralised numeric tunables for the MobileTerrain3D addon.
# Re-exported as static constants so they can be referenced as
# TerrainConstants.SYNC_BUILD_CHUNK_LIMIT from anywhere without a
# RefCounted instance.

# Chunk lifecycle thresholds.
const SYNC_BUILD_CHUNK_LIMIT := 64  # > this many chunks → deferred build (avoid editor freeze)
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

# Storage: TKT-011 rewrote the save system. Heavy data (height + splatmap +
# objects) is NEVER serialized into the .tscn — it always lives in a
# companion .res under TERRAIN_DATA_DIR, referenced by external_data_path.
# The directory is created on demand (DirAccess.make_dir_recursive) and the
# save is scene-independent (works even on an unsaved/untitled scene).
const TERRAIN_DATA_DIR := "res://terrain_data"

# Stroke throttling intervals (seconds between applied dabs).
const MIN_STATIONARY_INTERVAL := 0.04  # ~25 Hz cap for sculpt/paint
const MIN_OBJECT_INTERVAL := 0.08  # ~12 Hz cap for foliage scatter

# TKT-010 B2: paint dabs no longer upload the full splatmap texture to the
# GPU per dab (6.5 MB at 1280² × 25 Hz ≈ 163 MB/s). In-stroke uploads are
# coalesced in _process to at most one per this interval; end_stroke always
# flushes, so nothing is ever lost. ~10 Hz visual feedback while painting.
const SPLATMAP_UPLOAD_INTERVAL := 0.1

# TKT-010 B4: the brush decal rebuild (400 height samples + ~2.2k
# ImmediateMesh calls) used to run on EVERY mouse-motion event — at OS event
# rates that is >100k RenderingServer calls/sec for the cursor alone. Rebuilds
# are now rate-capped; ~30 Hz tracks the pointer imperceptibly.
const CURSOR_CONFORM_INTERVAL_MSEC := 33

# TKT-010 B5: while a mass rebuild is draining (undo force_update_all, EXR
# import, map resize), the editor LOD pass must not pile a second dirty wave
# on top of the first. Above this backlog the throttled LOD pass skips;
# it resumes once the queue drains below it.
const LOD_SKIP_DIRTY_THRESHOLD := 128

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

# Editor-only distance LOD (mobile_terrain_node._update_editor_lod). Chunk-centre
# distance (world units) thresholds; the LOD band = how many thresholds the
# distance exceeds, and the vertex stride doubles per band (1,2,4,8,16,32...)
# clamped to chunk_size. The farthest band collapses a whole chunk to a single
# quad — "aşırı optimizasyon" so a bird's-eye view of the whole world can't
# choke the editor. RUNTIME rendering is unaffected (LOD is is_editor_hint-gated).
const EDITOR_LOD_DISTANCES: Array = [50.0, 110.0, 220.0, 420.0, 820.0]
const EDITOR_LOD_UPDATE_INTERVAL := 0.15  # seconds between LOD re-evaluations
const EDITOR_LOD_CAMERA_EPSILON := 4.0  # min editor-camera move (world units) to re-evaluate
