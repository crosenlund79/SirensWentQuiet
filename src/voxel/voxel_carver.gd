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
	ch["cells"].append(i)
	ch["colors"].append(_visible_color(g, i))
	ch["mats"].append(g.mat[i])
	g.clear_index(i)


## Removes a ragged ball of voxels around `center`, optionally stretched by
## `stretch` along `dir` (bullet penetration). Harder materials resist
## (smaller effective radius); FOUNDATION never goes. Glass touched by the
## carve shatters as a whole pane.
static func carve_sphere(g: VoxelGrid, center: Vector3, radius: float, seed: int, dir := Vector3.ZERO, stretch := 1.0) -> Dictionary:
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
				if has_dir:
					var along := rel.dot(dir)
					rel += dir * (along * inv_s - along)
				var n := VoxelArt.hash3(x, y, z, seed)
				var thr := radius * (0.78 + 0.44 * n) * (1.0 - hard[m] * 0.45)
				if rel.length() < thr:
					if (flags[m] & VoxelMat.F_GLASS) != 0:
						glass_hit = i
						continue
					_remove(g, i, ch)
	ch["lo"] = lo - Vector3i.ONE
	ch["hi"] = hi + Vector3i.ONE
	if glass_hit >= 0:
		merge(ch, shatter_glass(g, glass_hit))
	merge(ch, remove_loose(g, lo - Vector3i.ONE, hi + Vector3i.ONE))
	merge(ch, remove_floating(g, lo - Vector3i(2, 2, 2), hi + Vector3i(2, 2, 2)))
	merge(ch, crumble_strips(g, lo - Vector3i.ONE, hi + Vector3i.ONE))
	merge(ch, crumble_sills(g, lo - Vector3i.ONE, hi + Vector3i.ONE))
	return ch


## Free-hanging horizontal strips of wall at most two voxels tall (air above
## and below, e.g. siding left between two holes) break off. Vertical members
## such as exposed studs are untouched.
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
	ch["lo"] = lo
	ch["hi"] = hi
	return ch


## A one-voxel strip of wall left standing at floor level (the row just above
## the bottom plate) crumbles once the wall above it is gone, so ragged holes
## reach the floor and stay walkable (bottom edge at 0.1 m).
static func crumble_sills(g: VoxelGrid, lo: Vector3i, hi: Vector3i) -> Dictionary:
	var ch := empty_change()
	var y1 := VoxelHouse.BASE_ROW + 1
	if lo.y > y1 + 2 or hi.y <= y1:
		return ch
	lo = lo.clamp(Vector3i.ONE, Vector3i(g.sx - 1, g.sy - 1, g.sz - 1))
	hi = hi.clamp(Vector3i.ONE, Vector3i(g.sx - 1, g.sy - 1, g.sz - 1))
	var st := VoxelMat.STRUCT
	for z in range(lo.z, hi.z):
		for x in range(lo.x, hi.x):
			var i := g.idx(x, y1, z)
			if st[g.mat[i]] == 1 and g.mat[g.idx(x, y1 + 1, z)] == 0 and g.mat[g.idx(x, y1 + 2, z)] == 0:
				_remove(g, i, ch)
	ch["lo"] = Vector3i(lo.x, y1 - 1, lo.z)
	ch["hi"] = Vector3i(hi.x, y1 + 2, hi.z)
	return ch


## Drops fragments that a carve left hanging in mid-air: inside the box
## [lo, hi), any face-connected solid component that does not reach the box
## boundary has nothing holding it, so it falls (is removed, becomes debris).
## Local and bounded; this is crumb cleanup, not structural simulation.
static func remove_floating(g: VoxelGrid, lo: Vector3i, hi: Vector3i) -> Dictionary:
	var ch := empty_change()
	lo = lo.clamp(Vector3i.ONE, Vector3i(g.sx - 1, g.sy - 1, g.sz - 1))
	hi = hi.clamp(Vector3i.ONE, Vector3i(g.sx - 1, g.sy - 1, g.sz - 1))
	var b := hi - lo
	if b.x <= 2 or b.y <= 2 or b.z <= 2:
		return ch
	var seen := PackedByteArray()
	seen.resize(b.x * b.y * b.z)
	var offs := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	for y in range(lo.y, hi.y):
		for z in range(lo.z, hi.z):
			for x in range(lo.x, hi.x):
				var li := ((y - lo.y) * b.z + (z - lo.z)) * b.x + (x - lo.x)
				if seen[li] != 0 or g.mat[g.idx(x, y, z)] == 0:
					continue
				seen[li] = 1
				var comp: Array[Vector3i] = [Vector3i(x, y, z)]
				var anchored := false
				var k := 0
				while k < comp.size():
					var c := comp[k]
					k += 1
					if c.x == lo.x or c.y == lo.y or c.z == lo.z or c.x == hi.x - 1 or c.y == hi.y - 1 or c.z == hi.z - 1:
						anchored = true
					for o in offs:
						var n: Vector3i = c + o
						if n.x < lo.x or n.y < lo.y or n.z < lo.z or n.x >= hi.x or n.y >= hi.y or n.z >= hi.z:
							continue
						var ln := ((n.y - lo.y) * b.z + (n.z - lo.z)) * b.x + (n.x - lo.x)
						if seen[ln] != 0 or g.mat[g.idx(n.x, n.y, n.z)] == 0:
							continue
						seen[ln] = 1
						comp.append(n)
				if not anchored:
					for c in comp:
						var i := g.idx(c.x, c.y, c.z)
						if (VoxelMat.FLAGS[g.mat[i]] & VoxelMat.F_HARD) == 0:
							_remove(g, i, ch)
	ch["lo"] = lo
	ch["hi"] = hi
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
	ch["lo"] = lo - Vector3i.ONE
	ch["hi"] = hi + Vector3i(2, 2, 2)
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
	ch["lo"] = lo
	ch["hi"] = hi
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
