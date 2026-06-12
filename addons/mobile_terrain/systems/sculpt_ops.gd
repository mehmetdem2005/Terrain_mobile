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
# ALL ops mutate `height_data` in place (packed arrays are passed by
# reference in Godot 4).
#
# Neighbour-reading ops (smooth, erode) must not see already-mutated cells
# inside the same dab, or the result is direction-biased. TKT-010 B1: this
# used to be done by duplicating the ENTIRE heightmap per dab (6.5 MB at
# 1280², ~162 MB/s of copies at the 25 Hz dab rate — the "COW makes it
# cheap" comment was wrong: duplicate() on a packed array is always an
# eager full copy). Now the writes are buffered in footprint-sized locals
# during the pass and applied afterwards: same order-independence, ~40 KB
# instead of 6.5 MB per dab.


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
) -> void:
	# Buffered writes: reads stay against the untouched `height_data` during
	# the pass so neighbour averaging is order-independent; each footprint
	# cell is written exactly once, applied after the pass.
	var w_idx := PackedInt32Array()
	var w_val := PackedFloat32Array()
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
			w_idx.append(idx)
			w_val.append(lerpf(height_data[idx], avg / float(c), strength * f * 0.5))
			mark_dirty.call(x, z)
	)
	for i in range(w_idx.size()):
		height_data[w_idx[i]] = w_val[i]


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
) -> void:
	# Thermal erosion: each cell donates a slice of its height to its
	# lowest 8-neighbour. Source AND destination chunks get marked
	# dirty so cross-boundary transfers don't leave stale seams.
	# Transfers accumulate as deltas (several cells can feed the same
	# lowest neighbour) and are applied after the pass.
	var deltas: Dictionary = {}
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
			deltas[idx] = deltas.get(idx, 0.0) - amount
			deltas[lowest_idx] = deltas.get(lowest_idx, 0.0) + amount
			mark_dirty.call(x, z)
			# V22 Phase 4 (audit-brush-erode-bounds): lowest_idx is by
			# construction within (nz * map_size + nx) where nz/nx came from
			# the bounded range above, so it's always inside [0, map_size²).
			# No extra clamp needed.
			var dest_z: int = lowest_idx / map_size
			var dest_x: int = lowest_idx % map_size
			mark_dirty.call(dest_x, dest_z)
	)
	for k in deltas:
		height_data[k] += deltas[k]
