@tool
class_name SculptOps
extends RefCounted

# V22: extracted height-mutation ops. All six sculpt brushes share the
# same footprint iteration (BrushSystem.iterate_footprint); each static
# method here adds the op-specific mutation + dirty-mark behaviour.
#
# Signature pattern:
#   static func op_name(
#       brush: BrushSystem,
#       height_data: PackedFloat32Array,
#       map_size: int,
#       mark_dirty: Callable,           # (x: int, z: int) -> void
#       cx: float, cz: float,
#       radius: float, strength: float,
#       [extra params]
#   ) -> PackedFloat32Array | void
#
# In-place ops (modify, flatten, noise, terrace) return nothing; they
# mutate `height_data` directly.
#
# Snapshot-and-swap ops (smooth, erode) return a NEW PackedFloat32Array
# that the caller must assign back to its height_data. The snapshot is
# necessary because neighbour reads inside the loop would otherwise see
# already-mutated cells and produce direction-biased results.


static func modify_height(
	brush: BrushSystem,
	height_data: PackedFloat32Array,
	map_size: int,
	mark_dirty: Callable,
	cx: float,
	cz: float,
	radius: float,
	strength: float
) -> void:
	brush.iterate_footprint(
		cx,
		cz,
		radius,
		func(x: int, z: int, f: float) -> void:
			height_data[z * map_size + x] += strength * f
			mark_dirty.call(x, z)
	)


static func flatten_height(
	brush: BrushSystem,
	height_data: PackedFloat32Array,
	map_size: int,
	mark_dirty: Callable,
	cx: float,
	cz: float,
	radius: float,
	target_h: float,
	strength: float
) -> void:
	brush.iterate_footprint(
		cx,
		cz,
		radius,
		func(x: int, z: int, f: float) -> void:
			var idx: int = z * map_size + x
			var cur: float = height_data[idx]
			height_data[idx] = cur + (target_h - cur) * f * strength
			mark_dirty.call(x, z)
	)


static func smooth_height(
	brush: BrushSystem,
	height_data: PackedFloat32Array,
	map_size: int,
	mark_dirty: Callable,
	cx: float,
	cz: float,
	radius: float,
	strength: float
) -> PackedFloat32Array:
	# Copy-on-write means the duplicate is cheap (256 KB max). Writes
	# go to the duplicate; reads stay against `height_data` so neighbour
	# averaging is order-independent.
	var temp: PackedFloat32Array = height_data.duplicate()
	brush.iterate_footprint(
		cx,
		cz,
		radius,
		func(x: int, z: int, f: float) -> void:
			var idx: int = z * map_size + x
			var avg: float = 0.0
			var c: int = 0
			for nz in range(max(0, z - 1), min(map_size, z + 2)):
				for nx in range(max(0, x - 1), min(map_size, x + 2)):
					avg += height_data[nz * map_size + nx]
					c += 1
			temp[idx] = lerpf(height_data[idx], avg / float(c), strength * f * 0.5)
			mark_dirty.call(x, z)
	)
	return temp


static func noise_height(
	brush: BrushSystem,
	height_data: PackedFloat32Array,
	map_size: int,
	mark_dirty: Callable,
	cx: float,
	cz: float,
	radius: float,
	strength: float
) -> void:
	# V22 deterministic: noise_gen.get_noise_2d (was randf_range, which
	# broke undo/redo replay).
	var noise: FastNoiseLite = brush.noise_gen
	brush.iterate_footprint(
		cx,
		cz,
		radius,
		func(x: int, z: int, f: float) -> void:
			var n: float = noise.get_noise_2d(float(x), float(z)) if noise != null else 0.0
			height_data[z * map_size + x] += n * strength * f * 0.2
			mark_dirty.call(x, z)
	)


static func terrace_height(
	brush: BrushSystem,
	height_data: PackedFloat32Array,
	map_size: int,
	mark_dirty: Callable,
	cx: float,
	cz: float,
	radius: float,
	strength: float
) -> void:
	# Step size scales with strength; clamped to >= 1.0 so terraces
	# remain visible even at low slider values.
	var step: float = maxf(1.0, strength * 5.0)
	brush.iterate_footprint(
		cx,
		cz,
		radius,
		func(x: int, z: int, f: float) -> void:
			var idx: int = z * map_size + x
			var cur: float = height_data[idx]
			var tar: float = round(cur / step) * step
			height_data[idx] = lerpf(cur, tar, f * 0.5)
			mark_dirty.call(x, z)
	)


static func erode_height(
	brush: BrushSystem,
	height_data: PackedFloat32Array,
	map_size: int,
	mark_dirty: Callable,
	cx: float,
	cz: float,
	radius: float,
	strength: float
) -> PackedFloat32Array:
	# Thermal erosion: each cell donates a slice of its height to its
	# lowest 8-neighbour. Source AND destination chunks get marked
	# dirty so cross-boundary transfers don't leave stale seams.
	var temp: PackedFloat32Array = height_data.duplicate()
	var erosion_rate: float = strength * 0.1
	brush.iterate_footprint(
		cx,
		cz,
		radius,
		func(x: int, z: int, f: float) -> void:
			var idx: int = z * map_size + x
			var h: float = height_data[idx]
			var lowest_h: float = h
			var lowest_idx: int = -1
			for nz in range(max(0, z - 1), min(map_size, z + 2)):
				for nx in range(max(0, x - 1), min(map_size, x + 2)):
					var n_idx: int = nz * map_size + nx
					var nh: float = height_data[n_idx]
					if nh < lowest_h:
						lowest_h = nh
						lowest_idx = n_idx
			if lowest_idx == -1:
				return
			var diff: float = h - lowest_h
			var amount: float = minf(diff * 0.5, erosion_rate) * f
			temp[idx] -= amount
			temp[lowest_idx] += amount
			mark_dirty.call(x, z)
			# V22 Phase 4 (audit-brush-erode-bounds): lowest_idx is by
			# construction within (nz * map_size + nx) where nz/nx came from
			# the bounded range above, so it's always inside [0, map_size²).
			# No extra clamp needed.
			var dest_z: int = lowest_idx / map_size
			var dest_x: int = lowest_idx % map_size
			mark_dirty.call(dest_x, dest_z)
	)
	return temp
