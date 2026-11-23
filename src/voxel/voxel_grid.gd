class_name VoxelGrid
extends RefCounted
## Dense voxel volume (Version A): one material byte plus two colours per cell.
##
## Cell (x, y, z) covers [origin + (x, y, z) * vs, origin + (x+1, y+1, z+1) * vs).
## The outermost layer of cells is always empty, so the mesher can look at
## neighbours without bounds checks. Index = (y * sz + z) * sx + x.
##
## Colours are 0xRRGGBB ints. `col` is the voxel's body colour (what a fresh
## cut shows); `pcol` is shown on faces whose bit is set in `pmask` (paint,
## glaze, varnish: the original finished surface).

var sx: int
var sy: int
var sz: int
var vs: float
var origin: Vector3
var mat := PackedByteArray()
var col := PackedInt32Array()
var pcol := PackedInt32Array()
var pmask := PackedByteArray()
var solid_count := 0
## Wall tops: up-faces of structural voxels in this row use `cap_color`.
var cap_row := -1
var cap_color := 0x26221f


func _init(size: Vector3i, voxel_size: float, min_corner: Vector3) -> void:
	sx = size.x
	sy = size.y
	sz = size.z
	vs = voxel_size
	origin = min_corner
	var n := sx * sy * sz
	mat.resize(n)
	col.resize(n)
	pcol.resize(n)
	pmask.resize(n)


func idx(x: int, y: int, z: int) -> int:
	return (y * sz + z) * sx + x


func is_inner(x: int, y: int, z: int) -> bool:
	return x > 0 and y > 0 and z > 0 and x < sx - 1 and y < sy - 1 and z < sz - 1


func get_mat(x: int, y: int, z: int) -> int:
	if x < 0 or y < 0 or z < 0 or x >= sx or y >= sy or z >= sz:
		return VoxelMat.AIR
	return mat[idx(x, y, z)]


func set_voxel(x: int, y: int, z: int, m: int, c: int, pc := 0, pm := 0) -> void:
	if not is_inner(x, y, z):
		return
	var i := idx(x, y, z)
	if mat[i] == 0 and m != 0:
		solid_count += 1
	elif mat[i] != 0 and m == 0:
		solid_count -= 1
	mat[i] = m
	col[i] = c
	pcol[i] = pc
	pmask[i] = pm


func clear_index(i: int) -> void:
	if mat[i] != 0:
		solid_count -= 1
	mat[i] = 0
	pmask[i] = 0


func coords(i: int) -> Vector3i:
	var x := i % sx
	var r := i / sx
	return Vector3i(x, r / sz, r % sz)


func cell_of(p: Vector3) -> Vector3i:
	var q := (p - origin) / vs
	return Vector3i(floori(q.x), floori(q.y), floori(q.z))


func center(c: Vector3i) -> Vector3:
	return origin + (Vector3(c) + Vector3(0.5, 0.5, 0.5)) * vs


func world_aabb() -> AABB:
	return AABB(origin, Vector3(sx, sy, sz) * vs)


## Range of cell indices along one axis whose centres lie in [lo, hi)
## (the same centre-in-rect rule GridNav uses). Returns Vector2i(first, end).
func centre_range(axis: int, lo: float, hi: float) -> Vector2i:
	var o: float = origin[axis] + vs * 0.5
	var n: int = [sx, sy, sz][axis]
	var a := int(ceil((lo - o) / vs - 1e-4))
	var b := int(ceil((hi - o) / vs - 1e-4))
	return Vector2i(clampi(a, 0, n), clampi(b, 0, n))


## Amanatides-Woo traversal. Returns {} or {"cell", "pos", "normal", "dist", "mat"}.
## `skip` (256 bytes, optional) lists material ids the ray passes through;
## `skip_cell` (optional Callable(Vector3i) -> bool) skips individual cells.
func raycast(from: Vector3, dir: Vector3, max_dist: float, skip := PackedByteArray(), skip_cell := Callable()) -> Dictionary:
	dir = dir.normalized()
	var box := world_aabb()
	# Clip the ray to the grid box.
	var t0 := 0.0
	var t1 := max_dist
	for a in 3:
		if absf(dir[a]) < 1e-9:
			if from[a] < box.position[a] or from[a] > box.end[a]:
				return {}
			continue
		var ta: float = (box.position[a] - from[a]) / dir[a]
		var tb: float = (box.end[a] - from[a]) / dir[a]
		if ta > tb:
			var tmp := ta
			ta = tb
			tb = tmp
		t0 = maxf(t0, ta)
		t1 = minf(t1, tb)
		if t0 > t1:
			return {}
	var p := from + dir * (t0 + 1e-5)
	var c := cell_of(p)
	c = c.clamp(Vector3i.ZERO, Vector3i(sx - 1, sy - 1, sz - 1))
	var step := Vector3i(signi(int(signf(dir.x))), signi(int(signf(dir.y))), signi(int(signf(dir.z))))
	var t_max := Vector3.ZERO
	var t_delta := Vector3.ZERO
	for a in 3:
		if step[a] != 0:
			var boundary: float = origin[a] + (c[a] + (1 if step[a] > 0 else 0)) * vs
			t_max[a] = (boundary - from[a]) / dir[a]
			t_delta[a] = vs / absf(dir[a])
		else:
			t_max[a] = INF
			t_delta[a] = INF
	var t := t0
	var normal := Vector3.ZERO
	# Entry normal for the first cell: the face of the box we came through.
	if t0 > 0.0:
		var best := -1
		for a in 3:
			if step[a] != 0:
				var tb: float = ((box.position[a] if step[a] > 0 else box.end[a]) - from[a]) / dir[a]
				if absf(tb - t0) < 1e-4:
					best = a
		if best >= 0:
			normal[best] = -step[best]
	var has_skip := not skip.is_empty()
	var has_cell_skip := skip_cell.is_valid()
	var guard := 0
	while t <= t1 and guard < 4096:
		guard += 1
		if c.x < 0 or c.y < 0 or c.z < 0 or c.x >= sx or c.y >= sy or c.z >= sz:
			break
		var m := mat[idx(c.x, c.y, c.z)]
		if m != 0 and not (has_skip and skip[m] != 0) and not (has_cell_skip and skip_cell.call(c)):
			return {"cell": c, "pos": from + dir * t, "normal": normal, "dist": t, "mat": m}
		# advance
		if t_max.x < t_max.y and t_max.x < t_max.z:
			c.x += step.x
			t = t_max.x
			t_max.x += t_delta.x
			normal = Vector3(-step.x, 0, 0)
		elif t_max.y < t_max.z:
			c.y += step.y
			t = t_max.y
			t_max.y += t_delta.y
			normal = Vector3(0, -step.y, 0)
		else:
			c.z += step.z
			t = t_max.z
			t_max.z += t_delta.z
			normal = Vector3(0, 0, -step.z)
	return {}


## True if any structural voxel remains in rows [row_lo, row_hi] for the
## voxel columns whose centres lie in the plan rect (x, z) [lo, hi).
func any_struct_in(lo: Vector2, hi: Vector2, row_lo: int, row_hi: int) -> bool:
	var rx := centre_range(0, lo.x, hi.x)
	var rz := centre_range(2, lo.y, hi.y)
	var st := VoxelMat.STRUCT
	for y in range(maxi(row_lo, 0), mini(row_hi + 1, sy)):
		for z in range(rz.x, rz.y):
			var base := (y * sz + z) * sx
			for x in range(rx.x, rx.y):
				if st[mat[base + x]] == 1:
					return true
	return false
