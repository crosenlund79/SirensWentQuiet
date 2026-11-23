class_name VoxelCarver
extends RefCounted
## Destruction on a VoxelGrid (pure data, no nodes): noisy sphere carves,
## glass pane shattering, loose-voxel cleanup and GridNav synchronisation.
##
## Every function returns a "change" dictionary:
##   cells:  PackedInt32Array  removed cell indices
##   colors: PackedInt32Array  their visible colour (for debris)
##   mats:   PackedByteArray   their material ids
##   lo, hi: Vector3i          cell range touched (hi exclusive), incl. AO margin


static func empty_change() -> Dictionary:
	return {"cells": PackedInt32Array(), "colors": PackedInt32Array(), "mats": PackedByteArray(), "lo": Vector3i(1 << 20, 1 << 20, 1 << 20), "hi": Vector3i(-1, -1, -1)}


static func merge(a: Dictionary, b: Dictionary) -> Dictionary:
	a["cells"].append_array(b["cells"])
	a["colors"].append_array(b["colors"])
	a["mats"].append_array(b["mats"])
	a["lo"] = (a["lo"] as Vector3i).min(b["lo"])
	a["hi"] = (a["hi"] as Vector3i).max(b["hi"])
	return a


static func _visible_color(g: VoxelGrid, i: int) -> int:
	if g.pmask[i] != 0 and (i * 2654435761) & 0x100 != 0:
		return g.pcol[i]
	return g.col[i]


static func _remove(g: VoxelGrid, i: int, ch: Dictionary) -> void:
	var c := g.coords(i)
	# touched range = removed cells plus a one-cell margin (their neighbours' AO)
	ch["lo"] = (ch["lo"] as Vector3i).min(c - Vector3i.ONE)
	ch["hi"] = (ch["hi"] as Vector3i).max(c + Vector3i(2, 2, 2))
	ch["cells"].append(i)
	ch["colors"].append(_visible_color(g, i))
	ch["mats"].append(g.mat[i])
	g.clear_index(i)


## Removes a ragged ball of voxels around `center`. With a shot direction
## `dir` and `stretch` > 1 it becomes a crater that narrows as it goes deeper
## (wide in the outer skin, tight in the inner one), so the wall's layers show
## as rings: paint/siding edge, insulation and studs, then the far skin. Harder materials resist
## (smaller effective radius); FOUNDATION never goes. Glass touched by the
## carve shatters as a whole pane.
##
## `quantum` > 1 (the survival game's coarser damage, see
## docs/experiment-002/VOXEL_RESOLUTION.md) carves whole aligned blocks of
## quantum³ voxels inside the same 0.1 m storage: the same crater rule is
## evaluated once per block centre, and a block that falls loses all its
## carvable voxels together.
static func carve_sphere(g: VoxelGrid, center: Vector3, radius: float, seed: int, dir := Vector3.ZERO, stretch := 1.0, quantum := 1) -> Dictionary:
	if quantum > 1:
		return _carve_blocks(g, center, radius, seed, dir, stretch, quantum)
	var ch := empty_change()
	var r_max := radius * 1.25 * maxf(stretch, 1.0)
	var has_dir := dir.length() > 0.01
	var inv_s := 1.0 / maxf(stretch, 0.01)
	var lo := g.cell_of(center - Vector3.ONE * r_max).clamp(Vector3i.ONE, Vector3i(g.sx - 2, g.sy - 2, g.sz - 2))
	var hi := (g.cell_of(center + Vector3.ONE * r_max) + Vector3i.ONE).clamp(Vector3i.ONE, Vector3i(g.sx - 1, g.sy - 1, g.sz - 1))
	var flags := VoxelMat.FLAGS
	var hard := VoxelMat.HARDNESS
	var glass_hit := -1
	for y in range(lo.y, hi.y):
		for z in range(lo.z, hi.z):
			for x in range(lo.x, hi.x):
				var i := g.idx(x, y, z)
				var m := g.mat[i]
				if m == 0 or (flags[m] & VoxelMat.F_HARD) != 0:
					continue
				var rel := g.origin + (Vector3(x, y, z) + Vector3(0.5, 0.5, 0.5)) * g.vs - center
				var n := VoxelArt.hash3(x, y, z, seed)
				var thr := radius * (0.78 + 0.44 * n) * (1.0 - hard[m] * 0.45)
				if has_dir:
					var along := rel.dot(dir)
					var depth := clampf((along + radius * 0.5) / (radius * stretch * 1.5), 0.0, 1.0)
					thr *= 1.1 - 0.3 * depth
					rel += dir * (along * inv_s - along)
				if rel.length() < thr:
					if (flags[m] & VoxelMat.F_GLASS) != 0:
						glass_hit = i
						continue
					_remove(g, i, ch)
	if glass_hit >= 0:
		merge(ch, shatter_glass(g, glass_hit))
	crumble(g, ch, lo - Vector3i.ONE, hi + Vector3i.ONE)
	return ch


static func _carve_blocks(g: VoxelGrid, center: Vector3, radius: float, seed: int, dir: Vector3, stretch: float, q: int) -> Dictionary:
	var ch := empty_change()
	var grow := g.vs * 0.5 * (q - 1)
	var r_max := radius * 1.25 * maxf(stretch, 1.0) + grow + g.vs * q * 0.5
	var has_dir := dir.length() > 0.01
	var inv_s := 1.0 / maxf(stretch, 0.01)
	var lo := g.cell_of(center - Vector3.ONE * r_max).clamp(Vector3i.ONE, Vector3i(g.sx - 2, g.sy - 2, g.sz - 2))
	var hi := (g.cell_of(center + Vector3.ONE * r_max) + Vector3i.ONE).clamp(Vector3i.ONE, Vector3i(g.sx - 1, g.sy - 1, g.sz - 1))
	var b0 := Vector3i(lo.x / q, lo.y / q, lo.z / q)
	var b1 := Vector3i((hi.x - 1) / q, (hi.y - 1) / q, (hi.z - 1) / q)
	var flags := VoxelMat.FLAGS
	var hard := VoxelMat.HARDNESS
	var glass_hit := -1
	var half := float(q) * 0.5
	# A block goes when its centre is inside the crater, grown by half a voxel
	# per extra quantum step (`grow`: keeps shots-per-hole of the 0.1 m rule).
	for by in range(b0.y, b1.y + 1):
		for bz in range(b0.z, b1.z + 1):
			for bx in range(b0.x, b1.x + 1):
				var bc := g.origin + (Vector3(bx * q, by * q, bz * q) + Vector3.ONE * half) * g.vs
				var rel := bc - center
				var n := VoxelArt.hash3(bx, by, bz, seed)
				var thr := radius * (0.78 + 0.44 * n)
				if has_dir:
					var along := rel.dot(dir)
					var depth := clampf((along + radius * 0.5) / (radius * stretch * 1.5), 0.0, 1.0)
					thr *= 1.1 - 0.3 * depth
					rel += dir * (along * inv_s - along)
				var d := rel.length()
				if d >= thr + grow:
					continue     # outside even for the softest material
				# carvable voxels of this block and their mean hardness
				var cells := PackedInt32Array()
				var h_sum := 0.0
				var glass_i := -1
				for y in range(by * q, by * q + q):
					for z in range(bz * q, bz * q + q):
						for x in range(bx * q, bx * q + q):
							if not g.is_inner(x, y, z):
								continue
							var i := g.idx(x, y, z)
							var m := g.mat[i]
							if m == 0 or (flags[m] & VoxelMat.F_HARD) != 0:
								continue
							if (flags[m] & VoxelMat.F_GLASS) != 0:
								glass_i = i
								continue
							cells.append(i)
							h_sum += hard[m]
				if cells.is_empty() and glass_i < 0:
					continue
				var hm := h_sum / maxf(1.0, cells.size())
				if d < thr * (1.0 - hm * 0.45) + grow:
					if glass_i >= 0:
						glass_hit = glass_i
					for i in cells:
						_remove(g, i, ch)
	if glass_hit >= 0:
		merge(ch, shatter_glass(g, glass_hit))
	crumble(g, ch, lo - Vector3i.ONE, hi + Vector3i.ONE)
	return ch


## Settles a change: loose crumbs, thin strips, slender posts, floor-level
## stubs and floating fragments fall. Repeats around whatever fell (falls can
## expose new crumbs) until nothing more goes (at most three rounds).
static func crumble(g: VoxelGrid, ch: Dictionary, lo: Vector3i, hi: Vector3i) -> void:
	var done := 0
	for round_i in 3:
		var before := (ch["cells"] as PackedInt32Array).size()
		if round_i > 0:
			lo = ch["lo"]
			hi = ch["hi"]
		merge(ch, remove_loose(g, lo, hi))
		merge(ch, crumble_strips(g, lo, hi))
		merge(ch, crumble_sills(g, lo, hi))
		var cells: PackedInt32Array = ch["cells"]
		merge(ch, remove_floating(g, cells.slice(done)))
		done = before
		if (ch["cells"] as PackedInt32Array).size() == before and round_i > 0:
			break


## Free-hanging horizontal strips of wall at most two voxels tall (air above
## and below, e.g. siding left between two holes) break off, and so do
## free-standing one-voxel posts. Studs still held at the top stay.
static func crumble_strips(g: VoxelGrid, lo: Vector3i, hi: Vector3i) -> Dictionary:
	var ch := empty_change()
	lo = lo.clamp(Vector3i(1, 3, 1), Vector3i(g.sx - 1, g.sy - 1, g.sz - 1))
	hi = hi.clamp(Vector3i.ONE, Vector3i(g.sx - 1, g.sy - 1, g.sz - 1))
	var st := VoxelMat.STRUCT
	var up := g.sx * g.sz
	var doomed := PackedInt32Array()
	for y in range(lo.y, hi.y):
		for z in range(lo.z, hi.z):
			for x in range(lo.x, hi.x):
				var i := g.idx(x, y, z)
				if st[g.mat[i]] == 0:
					continue
				# vertical solid run through this voxel
				var a := 0
				while a < 3 and g.mat[i - (a + 1) * up] != 0:
					a += 1
				var b := 0
				while b < 3 and g.mat[i + (b + 1) * up] != 0:
					b += 1
				if a + b + 1 <= 2:
					doomed.append(i)
	for i in doomed:
		if g.mat[i] != 0:
			_remove(g, i, ch)
	# Free-standing slender posts (nothing above, nothing on any side) topple;
	# scanning top-down takes a whole post at once. Studs still held by the
	# wall above stay.
	for y in range(hi.y - 1, lo.y - 1, -1):
		if y <= VoxelHouse.BASE_ROW:
			break
		for z in range(lo.z, hi.z):
			for x in range(lo.x, hi.x):
				var i := g.idx(x, y, z)
				if st[g.mat[i]] == 0 or g.mat[i + up] != 0:
					continue
				if g.mat[i + 1] == 0 and g.mat[i - 1] == 0 and g.mat[i + g.sx] == 0 and g.mat[i - g.sx] == 0:
					_remove(g, i, ch)
	return ch


## A stub of wall at most two voxels tall left standing at floor level (just
## above the bottom plate) crumbles once the wall above it is gone, so ragged
## holes reach the floor and stay walkable (bottom edge at 0.1 m).
static func crumble_sills(g: VoxelGrid, lo: Vector3i, hi: Vector3i) -> Dictionary:
	var ch := empty_change()
	var y1 := VoxelHouse.BASE_ROW + 1
	if lo.y > y1 + 3 or hi.y <= y1:
		return ch
	lo = lo.clamp(Vector3i.ONE, Vector3i(g.sx - 1, g.sy - 1, g.sz - 1))
	hi = hi.clamp(Vector3i.ONE, Vector3i(g.sx - 1, g.sy - 1, g.sz - 1))
	var st := VoxelMat.STRUCT
	for z in range(lo.z, hi.z):
		for x in range(lo.x, hi.x):
			if g.mat[g.idx(x, y1 + 2, z)] != 0 or g.mat[g.idx(x, y1 + 3, z)] != 0:
				continue
			for y in [y1, y1 + 1]:
				var i := g.idx(x, y, z)
				if st[g.mat[i]] == 1:
					_remove(g, i, ch)
	return ch


## Drops fragments that a carve left hanging in mid-air. Starting from the
## solid neighbours of the removed `cells`, a bounded flood fill (6-connected,
## any solid material) explores each piece; a piece that runs out before
## FLOAT_CAP voxels touches nothing big (the house is one huge connected
## body through walls and floor slab), so it falls: removed, becomes debris.
## Bounded and local; crumb cleanup, not structural simulation.
const FLOAT_CAP := 400


static func remove_floating(g: VoxelGrid, cells: PackedInt32Array) -> Dictionary:
	var ch := empty_change()
	var deltas := PackedInt32Array([1, -1, g.sx, -g.sx, g.sx * g.sz, -g.sx * g.sz])
	var anchored := {}
	var n_total := g.mat.size()
	for start_cell in cells:
		for dl in deltas:
			var s: int = start_cell + dl
			if s < 0 or s >= n_total or g.mat[s] == 0 or anchored.has(s):
				continue
			var seen := {s: true}
			var queue := PackedInt32Array([s])
			var k := 0
			var capped := false
			while k < queue.size():
				var i := queue[k]
				k += 1
				for d2 in deltas:
					var j := i + d2
					if j < 0 or j >= n_total or g.mat[j] == 0 or seen.has(j):
						continue
					if anchored.has(j):
						capped = true
						break
					seen[j] = true
					queue.append(j)
				if capped or queue.size() >= FLOAT_CAP:
					capped = true
					break
			if capped:
				for i in queue:
					anchored[i] = true
			else:
				for i in queue:
					if (VoxelMat.FLAGS[g.mat[i]] & VoxelMat.F_HARD) == 0:
						_remove(g, i, ch)
	return ch


## Removes the whole face-connected glass pane containing cell index `start`.
static func shatter_glass(g: VoxelGrid, start: int) -> Dictionary:
	var ch := empty_change()
	if start < 0 or start >= g.mat.size() or g.mat[start] != VoxelMat.GLASS:
		return ch
	var deltas := [1, -1, g.sx, -g.sx, g.sx * g.sz, -g.sx * g.sz]
	var stack := [start]
	var seen := {start: true}
	var lo := g.coords(start)
	var hi := lo
	while not stack.is_empty() and seen.size() < 4000:
		var i: int = stack.pop_back()
		var c := g.coords(i)
		lo = lo.min(c)
		hi = hi.max(c)
		_remove(g, i, ch)
		for dl in deltas:
			var j: int = i + dl
			if j >= 0 and j < g.mat.size() and not seen.has(j) and g.mat[j] == VoxelMat.GLASS:
				seen[j] = true
				stack.append(j)
	return ch


## Removes voxels in [lo, hi) left with at most one face neighbour (floating
## crumbs and one-voxel slivers), so holes stay clean and navigable.
static func remove_loose(g: VoxelGrid, lo: Vector3i, hi: Vector3i) -> Dictionary:
	var ch := empty_change()
	lo = lo.clamp(Vector3i.ONE, Vector3i(g.sx - 1, g.sy - 1, g.sz - 1))
	hi = hi.clamp(Vector3i.ONE, Vector3i(g.sx - 1, g.sy - 1, g.sz - 1))
	var flags := VoxelMat.FLAGS
	var deltas := [1, -1, g.sx, -g.sx, g.sx * g.sz, -g.sx * g.sz]
	for pass_i in 2:
		var removed_any := false
		for y in range(lo.y, hi.y):
			for z in range(lo.z, hi.z):
				for x in range(lo.x, hi.x):
					var i := g.idx(x, y, z)
					var m := g.mat[i]
					if m == 0 or (flags[m] & (VoxelMat.F_HARD | VoxelMat.F_GLASS)) != 0:
						continue
					var n := 0
					for dl in deltas:
						if g.mat[i + dl] != 0:
							n += 1
					if n <= 1:
						_remove(g, i, ch)
						removed_any = true
		if not removed_any:
			break
	return ch


## Navigation contract (SPEC 1, step 1-2): every raw WALL cell touched by the
## change becomes OPEN once no structural voxel remains in its footprint
## columns between 0.15 m and CLEARANCE_HEIGHT. Cells never turn back into
## walls and SOLID is never touched. Returns the number of cells opened.
static func sync_nav(nav: GridNav, g: VoxelGrid, lo: Vector3i, hi: Vector3i) -> int:
	if hi.x <= lo.x:
		return 0
	var p0 := Vector2(g.origin.x + lo.x * g.vs, g.origin.z + lo.z * g.vs)
	var p1 := Vector2(g.origin.x + hi.x * g.vs, g.origin.z + hi.z * g.vs)
	var rect := Rect2(p0, p1 - p0).grow(GridNav.CELL)
	var half := Vector2.ONE * GridNav.CELL * 0.5
	var opened := 0
	for c in nav.cells_in_rect(rect):
		if nav.get_raw(c) != GridNav.WALL:
			continue
		var cc := nav.center_of(c)
		if not g.any_struct_in(cc - half, cc + half, VoxelHouse.NAV_ROW_LO, VoxelHouse.NAV_ROW_HI):
			nav.set_raw(c, GridNav.OPEN)
			opened += 1
	if opened > 0:
		nav.refresh_region(rect)
	return opened
