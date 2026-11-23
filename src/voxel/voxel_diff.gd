class_name VoxelDiff
extends RefCounted
## Compact, validated difference between a VoxelGrid and a base grid of the
## same size (the survival world saves its design and current grids as diffs
## against the pristine house). Pure data, no nodes.
##
## Encoded form (Godot Variant-safe: ints and PackedByteArrays only):
##   {"removed": {"n", "idx"},                    cells solid in base, empty here
##    "set": {"n", "idx", "mat", "col", "pcol", "pmask"}}   cells solid here that
##                                                differ from base (added or changed)
## Index lists are ascending and delta-encoded; every array is zstd-compressed
## (`<name>` holds the bytes, the size is implied by n).

const MODE := FileAccess.COMPRESSION_ZSTD


## Cells that differ. Compares whole y-layers and z-rows natively first, so an
## untouched layer costs almost nothing.
static func compute(g: VoxelGrid, base: VoxelGrid) -> Dictionary:
	var removed := PackedInt32Array()
	var s_idx := PackedInt32Array()
	var s_mat := PackedByteArray()
	var s_col := PackedInt32Array()
	var s_pcol := PackedInt32Array()
	var s_pmask := PackedByteArray()
	var layer := g.sx * g.sz
	for y in g.sy:
		var a := y * layer
		if _same(g, base, a, a + layer):
			continue
		for z in g.sz:
			var r := a + z * g.sx
			if _same(g, base, r, r + g.sx):
				continue
			for i in range(r, r + g.sx):
				var m := g.mat[i]
				var bm := base.mat[i]
				if m == 0:
					if bm != 0:
						removed.append(i)
					continue
				if m != bm or g.col[i] != base.col[i] or g.pcol[i] != base.pcol[i] or g.pmask[i] != base.pmask[i]:
					s_idx.append(i)
					s_mat.append(m)
					s_col.append(g.col[i])
					s_pcol.append(g.pcol[i])
					s_pmask.append(g.pmask[i])
	return {"removed": removed, "idx": s_idx, "mat": s_mat, "col": s_col, "pcol": s_pcol, "pmask": s_pmask}


static func _same(g: VoxelGrid, base: VoxelGrid, a: int, b: int) -> bool:
	return g.mat.slice(a, b) == base.mat.slice(a, b) and g.pmask.slice(a, b) == base.pmask.slice(a, b) \
		and g.col.slice(a, b) == base.col.slice(a, b) and g.pcol.slice(a, b) == base.pcol.slice(a, b)


static func encode(g: VoxelGrid, base: VoxelGrid) -> Dictionary:
	var d := compute(g, base)
	var rem: PackedInt32Array = d["removed"]
	var idx: PackedInt32Array = d["idx"]
	return {
		"removed": {"n": rem.size(), "idx": _z(_delta(rem).to_byte_array())},
		"set": {"n": idx.size(), "idx": _z(_delta(idx).to_byte_array()), "mat": _z(d["mat"]),
			"col": _z((d["col"] as PackedInt32Array).to_byte_array()), "pcol": _z((d["pcol"] as PackedInt32Array).to_byte_array()),
			"pmask": _z(d["pmask"])},
	}


## Validates an encoded diff against grid `g` (sizes, ascending in-range
## indices, solid materials, never the empty border). Returns the decoded
## arrays (as compute() returns them), or {} if anything is off.
static func decode(e: Variant, g: VoxelGrid) -> Dictionary:
	var cells := g.mat.size()
	if not (e is Dictionary):
		return {}
	var rem_d: Variant = e.get("removed")
	var set_d: Variant = e.get("set")
	if not (rem_d is Dictionary) or not (set_d is Dictionary):
		return {}
	var nr := _count(rem_d.get("n"), cells)
	var ns := _count(set_d.get("n"), cells)
	if nr < 0 or ns < 0:
		return {}
	var rem := _ints(_unz(rem_d.get("idx"), nr * 4), nr, cells)
	var idx := _ints(_unz(set_d.get("idx"), ns * 4), ns, cells)
	var mat := _unz(set_d.get("mat"), ns)
	var col := _unz(set_d.get("col"), ns * 4)
	var pcol := _unz(set_d.get("pcol"), ns * 4)
	var pmask := _unz(set_d.get("pmask"), ns)
	if rem.size() != nr or idx.size() != ns or mat.size() != ns or col.size() != ns * 4 or pcol.size() != ns * 4 or pmask.size() != ns:
		return {}
	for m in mat:
		if m == 0 or (VoxelMat.FLAGS[m] & VoxelMat.F_SOLID) == 0:
			return {}
	for i in idx:
		var c := g.coords(i)
		if not g.is_inner(c.x, c.y, c.z):
			return {}
	return {"removed": rem, "idx": idx, "mat": mat, "col": col.to_int32_array(), "pcol": pcol.to_int32_array(), "pmask": pmask}


## Applies a decoded diff to a copy of the base grid (same size).
static func apply(g: VoxelGrid, d: Dictionary) -> void:
	for i in (d["removed"] as PackedInt32Array):
		g.clear_index(i)
	var idx: PackedInt32Array = d["idx"]
	var mat: PackedByteArray = d["mat"]
	var col: PackedInt32Array = d["col"]
	var pcol: PackedInt32Array = d["pcol"]
	var pmask: PackedByteArray = d["pmask"]
	for k in idx.size():
		var i := idx[k]
		if g.mat[i] == 0:
			g.solid_count += 1
		g.mat[i] = mat[k]
		g.col[i] = col[k]
		g.pcol[i] = pcol[k]
		g.pmask[i] = pmask[k]


static func _delta(a: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(a.size())
	var prev := -1
	for k in a.size():
		out[k] = a[k] - prev
		prev = a[k]
	return out


static func _z(b: PackedByteArray) -> PackedByteArray:
	return b.compress(MODE) if not b.is_empty() else PackedByteArray()


static func _unz(v: Variant, size: int) -> PackedByteArray:
	if size == 0:
		return PackedByteArray()
	if not (v is PackedByteArray) or (v as PackedByteArray).is_empty():
		return PackedByteArray()
	var out := (v as PackedByteArray).decompress(size, MODE)
	return out if out.size() == size else PackedByteArray()


static func _count(v: Variant, cells: int) -> int:
	if not (v is int):
		return -1
	return v if v >= 0 and v <= cells else -1


## Delta-decoded, strictly ascending indices in [0, cells), or an empty array.
static func _ints(b: PackedByteArray, n: int, cells: int) -> PackedInt32Array:
	if n == 0:
		return PackedInt32Array()
	if b.size() != n * 4:
		return PackedInt32Array()
	var deltas := b.to_int32_array()
	var out := PackedInt32Array()
	out.resize(n)
	var prev := -1
	for k in n:
		var dlt := deltas[k]
		if dlt <= 0:
			return PackedInt32Array()
		prev += dlt
		if prev >= cells:
			return PackedInt32Array()
		out[k] = prev
	return out
