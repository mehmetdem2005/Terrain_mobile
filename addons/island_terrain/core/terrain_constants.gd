@tool
extends RefCounted
class_name IslandTerrainConstants

const DATA_FORMAT_VERSION: int = 1
const DEFAULT_WORLD_SIZE_M: int = 4096
const DEFAULT_REGION_SIZE_M: int = 256
const DEFAULT_REGION_SAMPLES: int = 257
const DEFAULT_MAX_HEIGHT_M: float = 512.0

# Mobile safety limits. These are hard caps, not suggested quality values.
const MIN_CLIPMAP_LEVELS: int = 3
const MAX_CLIPMAP_LEVELS: int = 6
const DEFAULT_CLIPMAP_LEVELS: int = 5
const MIN_BASE_QUADS: int = 16
const MAX_BASE_QUADS: int = 96
const DEFAULT_BASE_QUADS: int = 64
const MOBILE_MACRO_RESOLUTION: int = 257
const EDITOR_MACRO_RESOLUTION: int = 513
const MAX_MOBILE_MACRO_RESOLUTION: int = 513
const MAX_EDITOR_MACRO_RESOLUTION: int = 1025
const DEFAULT_FRAME_WORK_BUDGET_MS: float = 2.0
const MAX_FRAME_WORK_BUDGET_MS: float = 4.0
const DEFAULT_MAX_CACHED_REGIONS: int = 9
const DEFAULT_COLLISION_RADIUS_M: float = 96.0

const DIAGNOSTIC_PREFIX: String = "IT-"


static func is_valid_sample_count(sample_count: int) -> bool:
	if sample_count < 3:
		return false
	return _is_power_of_two(sample_count - 1)


static func clamp_clipmap_levels(levels: int) -> int:
	return clampi(levels, MIN_CLIPMAP_LEVELS, MAX_CLIPMAP_LEVELS)


static func clamp_base_quads(quads: int) -> int:
	var clamped: int = clampi(quads, MIN_BASE_QUADS, MAX_BASE_QUADS)
	# Even dimensions keep ring seams symmetric.
	return clamped if clamped % 2 == 0 else clamped - 1


static func safe_macro_resolution(requested: int, editor_hint: bool) -> int:
	var hard_cap: int = MAX_EDITOR_MACRO_RESOLUTION if editor_hint else MAX_MOBILE_MACRO_RESOLUTION
	var value: int = clampi(requested, 65, hard_cap)
	# Height textures use 2^n + 1 dimensions for exact region/LOD alignment.
	var intervals: int = maxi(64, value - 1)
	var power: int = 1
	while power < intervals:
		power <<= 1
	if power + 1 > hard_cap:
		power >>= 1
	return power + 1


static func _is_power_of_two(value: int) -> bool:
	return value > 0 and (value & (value - 1)) == 0
