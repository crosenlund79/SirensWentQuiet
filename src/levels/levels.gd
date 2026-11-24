class_name Levels
extends RefCounted
## Experiment 004 (owner L): the house's storeys and stairs as pure data and
## small helpers (no scene). Storeys: -1 basement, 0 ground floor, 1 upper
## floor. Every storey has the same row layout as the ground floor's voxel
## grid (VoxelHouse rows), shifted by HEIGHT per storey, so the floor finish of
## storey s is at y = s * HEIGHT.
##
## Floor tiles and basement cells are 1 m x 1 m plan cells: cell (i, j) covers
## [i, i + 1) x [j, j + 1). A stairs piece covers two cells in a line, from its
## start cell in direction DIRS[rot]; it joins storey `lo` and `lo + 1`:
##   "up" stairs (lo 0): on the ground floor, rising from the start edge to
##     the upper floor; the upper deck has a stairwell over both cells.
##   "down" stairs (lo -1): in a hole in the ground floor, descending from the
##     start edge into dug basement cells.
## Each end has an exit point 0.5 m outside the stairs (where a body arrives).

const HEIGHT := 2.9
const BASEMENT := -1
const GROUND := 0
const UPPER := 1
const NAMES := {-1: "Basement", 0: "Ground floor", 1: "Upper floor"}
## Plan directions of the stairs' quarter turns (0 north, 1 east, 2 south, 3 west).
const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const EXIT_GAP := 0.5          ## m from the stairs' end to its exit point
const STEPS := 13

const WOOD_FLOOR_COST := {"wood": 2, "nails": 2}
const STAIRS_COST := {"wood": 8, "nails": 10}
const UPPER_FLOOR_COST := {"wood": 40, "nails": 40, "iron": 4}
## Digging one basement cell: game minutes, energy, stone found.
const DIG_MINUTES := 25.0
const DIG_ENERGY := 6.0
const DIG_STONE := 1
const DIG_MIN_ENERGY := 10.0


static func base_y(storey: int) -> float:
	return float(storey) * HEIGHT


static func name_of(storey: int) -> String:
	return NAMES.get(storey, "Storey %d" % storey)


## The storey whose floor is nearest below height y (bodies stand on floors).
static func storey_at(y: float) -> int:
	return clampi(roundi(y / HEIGHT), BASEMENT, UPPER)


static func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x), floori(p.y))


static func cell_rect(c: Vector2i) -> Rect2:
	return Rect2(c.x, c.y, 1.0, 1.0)


static func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c.x + 0.5, c.y + 0.5)


## A cell under the house (where floors can change, basements be dug and stairs stand).
static func in_house(c: Vector2i) -> bool:
	return HousePlan.FOOTPRINT.encloses(cell_rect(c))


# --- stairs ----------------------------------------------------------------------------

## A stairs record: {"lo": -1 | 0, "cell": Vector2i (start), "rot": 0..3}.
static func make_stairs(lo: int, start: Vector2i, rot: int) -> Dictionary:
	return {"lo": lo, "cell": start, "rot": posmod(rot, 4)}


static func stairs_dir(st: Dictionary) -> Vector2i:
	return DIRS[int(st["rot"])]


static func stairs_cells(st: Dictionary) -> Array:
	var c: Vector2i = st["cell"]
	return [c, c + stairs_dir(st)]


static func stairs_rect(st: Dictionary) -> Rect2:
	var r := cell_rect(st["cell"])
	return r.merge(cell_rect((st["cell"] as Vector2i) + stairs_dir(st)))


## The cell before the start edge (on the ground floor: where you step on).
static func foot_cell(st: Dictionary) -> Vector2i:
	return (st["cell"] as Vector2i) - stairs_dir(st)


## The cell past the far edge (up stairs: on the upper floor; down stairs: in the basement).
static func far_cell(st: Dictionary) -> Vector2i:
	return (st["cell"] as Vector2i) + stairs_dir(st) * 2


static func _start_edge(st: Dictionary) -> Vector2:
	return cell_center(st["cell"]) - Vector2(stairs_dir(st)) * 0.5


static func _far_edge(st: Dictionary) -> Vector2:
	return _start_edge(st) + Vector2(stairs_dir(st)) * 2.0


## Plan point where a body arrives on `storey` (one of the two the stairs join).
## Up stairs: the foot on the ground, the top on the upper floor. Down stairs:
## the start edge on the ground, the bottom in the basement.
static func exit_point(st: Dictionary, storey: int) -> Vector2:
	var d := Vector2(stairs_dir(st))
	if storey == GROUND:          # both kinds start on the ground floor
		return _start_edge(st) - d * EXIT_GAP
	return _far_edge(st) + d * EXIT_GAP


## The storey the stairs lead to from `storey`, or `storey` if they don't touch it.
static func other_storey(st: Dictionary, storey: int) -> int:
	var lo := int(st["lo"])
	if storey == lo:
		return lo + 1
	if storey == lo + 1:
		return lo
	return storey


static func joins(st: Dictionary, storey: int) -> bool:
	return other_storey(st, storey) != storey


## Yaw a body faces after arriving on `storey` (away from the stairs).
static func arrival_yaw(st: Dictionary, storey: int) -> float:
	var d := Vector2(stairs_dir(st))
	var away := -d if storey == GROUND else d
	return atan2(-away.x, -away.y)


## Height of the stairs' walking surface at plan point p (for the mesh): from
## the start edge (y 0) to the far edge (+HEIGHT up, -HEIGHT down).
static func step_height(st: Dictionary, k: int) -> float:
	var h := HEIGHT * float(k + 1) / float(STEPS)
	return h if int(st["lo"]) == GROUND else -h


## Stairs from `storey` toward `target` that a body at plan point `from` should
## take: the nearest joining storey and the next storey toward the target.
## Returns {} when none exists.
static func route(stairs: Array, storey: int, target: int, from: Vector2) -> Dictionary:
	if storey == target:
		return {}
	var next := storey + signi(target - storey)
	var best := {}
	var best_d := INF
	for st in stairs:
		if other_storey(st, storey) != next:
			continue
		var d := from.distance_to(exit_point(st, storey))
		if d < best_d:
			best_d = d
			best = st
	return best


## Serialised stairs: [lo, i, j, rot]. Returns null for invalid data.
static func stairs_to_array(st: Dictionary) -> Array:
	return [int(st["lo"]), (st["cell"] as Vector2i).x, (st["cell"] as Vector2i).y, int(st["rot"])]


static func stairs_from_array(v: Variant) -> Variant:
	if not (v is Array) or (v as Array).size() != 4:
		return null
	for x in v:
		if typeof(x) != TYPE_INT and typeof(x) != TYPE_FLOAT:
			return null
	var lo := int(v[0])
	if lo != BASEMENT and lo != GROUND:
		return null
	var st := make_stairs(lo, Vector2i(int(v[1]), int(v[2])), int(v[3]))
	for c in stairs_cells(st):
		if not in_house(c):
			return null
	return st


static func cells_from_array(v: Variant) -> Variant:
	if not (v is Array):
		return null
	var out := []
	for e in v:
		if not (e is Array) or (e as Array).size() != 2:
			return null
		if typeof(e[0]) not in [TYPE_INT, TYPE_FLOAT] or typeof(e[1]) not in [TYPE_INT, TYPE_FLOAT]:
			return null
		var c := Vector2i(int(e[0]), int(e[1]))
		if not in_house(c):
			return null
		out.append(c)
	return out


# --- floor tiles on any world (HouseWorld or LevelWorld) -----------------------------

## Fraction (0..1) of the cell's columns with a floor finish in the design.
static func floor_coverage(w: HouseWorld, c: Vector2i) -> float:
	var b := _cell_box(w.design, c, VoxelHouse.FLOOR_ROW, VoxelHouse.FLOOR_ROW)
	var n := 0
	var on := 0
	for z in range(b[0].z, b[1].z):
		for x in range(b[0].x, b[1].x):
			n += 1
			var m := w.design.get_mat(x, VoxelHouse.FLOOR_ROW, z)
			if m != VoxelMat.AIR and m != VoxelMat.EARTH:
				on += 1
	return float(on) / maxf(1.0, n)


## True if structure (a wall) stands on the cell's columns (nav rows).
static func wall_on(w: HouseWorld, c: Vector2i) -> bool:
	var r := cell_rect(c).grow(-0.12)
	return w.design.any_struct_in(r.position, r.end, VoxelHouse.NAV_ROW_LO, VoxelHouse.NAV_ROW_HI)


## Takes the floor out of a cell (design and current): rows 1-3 (the whole
## slab, so the ground floor shows bare earth and the upper floor a hole).
## Columns under a wall keep their floor. Returns the voxels removed.
static func remove_floor(w: HouseWorld, c: Vector2i) -> int:
	var b := _cell_box(w.design, c, VoxelHouse.FOUNDATION_ROW, VoxelHouse.FLOOR_ROW)
	var n := 0
	for z in range(b[0].z, b[1].z):
		for x in range(b[0].x, b[1].x):
			if _wall_column(w.design, x, z):
				continue
			for y in range(b[0].y, b[1].y):
				var i := w.design.idx(x, y, z)
				var m := w.design.mat[i]
				if m == VoxelMat.AIR or m == VoxelMat.EARTH:
					continue
				w.design.clear_index(i)
				if w.grid.mat[i] != VoxelMat.AIR:
					w.grid.clear_index(i)
				n += 1
	w._edited(b[0], b[1])
	return n


## Lays a wooden plank floor in a cell (design and current) where it has none:
## joists (row 1, only where empty), subfloor and planks.
static func lay_wood_floor(w: HouseWorld, c: Vector2i) -> void:
	var b := _cell_box(w.design, c, VoxelHouse.FOUNDATION_ROW, VoxelHouse.FLOOR_ROW)
	var screed := VoxelArt.pal(VoxelArt.Slot.SCREED)
	for z in range(b[0].z, b[1].z):
		for x in range(b[0].x, b[1].x):
			if w.design.get_mat(x, VoxelHouse.FLOOR_ROW, z) != VoxelMat.AIR:
				continue
			if w.design.get_mat(x, VoxelHouse.FOUNDATION_ROW, z) == VoxelMat.AIR:
				var j := VoxelArt.jitter(0x5a4632, x, 1, z, 0.06)
				_put(w, x, VoxelHouse.FOUNDATION_ROW, z, VoxelMat.SCREED, j, j, 0)
			if w.design.get_mat(x, VoxelHouse.SCREED_ROW, z) == VoxelMat.AIR:
				var s := VoxelArt.jitter(screed, x, 2, z, 0.05)
				_put(w, x, VoxelHouse.SCREED_ROW, z, VoxelMat.SCREED, s, s, 0)
			var top := VoxelArt.sample("floor_wood", x, z)
			_put(w, x, VoxelHouse.FLOOR_ROW, z, VoxelMat.FLOOR, VoxelArt.scale(top, 0.72), top, VoxelHouse.UP_BIT)
	w._edited(b[0], b[1])


static func _put(w: HouseWorld, x: int, y: int, z: int, m: int, c: int, pc: int, pm: int) -> void:
	w.design.set_voxel(x, y, z, m, c, pc, pm)
	w.grid.set_voxel(x, y, z, m, c, pc, pm)


static func _wall_column(g: VoxelGrid, x: int, z: int) -> bool:
	for y in range(VoxelHouse.NAV_ROW_LO, VoxelHouse.NAV_ROW_LO + 3):
		var m := g.get_mat(x, y, z)
		if VoxelMat.is_struct(m) and m != VoxelMat.EARTH:
			return true
	return false


## Grid cell box [lo, hi) of plan cell c, rows row_lo..row_hi.
static func _cell_box(g: VoxelGrid, c: Vector2i, row_lo: int, row_hi: int) -> Array:
	var xr := g.centre_range(0, c.x, c.x + 1.0)
	var zr := g.centre_range(2, c.y, c.y + 1.0)
	return [Vector3i(xr.x, row_lo, zr.x), Vector3i(xr.y, row_hi + 1, zr.y)]
