class_name Levels
extends RefCounted
## Experiment 004 (owner L), generalised in Experiment 005 (V): the house's
## storeys and stairs as pure data and small helpers (no scene). Storeys:
## -2 lower basement, -1 basement, 0 ground floor, +1 first upper floor, +2
## second upper floor (LOWEST..HIGHEST; nothing below or above). Every
## storey has the same row layout as the ground floor's voxel grid
## (VoxelHouse rows), shifted by HEIGHT per storey, so the floor finish of
## storey s is at y = s * HEIGHT. One set of rules for all of them.
##
## Floor tiles and dug cells are 1 m x 1 m plan cells: cell (i, j) covers
## [i, i + 1) x [j, j + 1). A stairs piece covers two cells in a line, from its
## start cell in direction DIRS[rot]; it joins storey `lo` and `lo + 1`:
##   "up" stairs (lo >= 0): stand on storey lo, rising from the start edge to
##     storey lo + 1, whose floor has a stairwell over both cells.
##   "down" stairs (lo < 0): in a hole in storey lo + 1's floor, descending
##     from the start edge into dug cells of storey lo.
## So above ground you build stairs up from the floor you stand on, below
## ground stairs down; the start storey (start_storey) is where the foot is.
## Each end has an exit point 0.5 m outside the stairs (where a body arrives).

const HEIGHT := 2.9
const LOWEST := -2               ## Exp 005 (V): nothing below the lower basement
const HIGHEST := 2               ## Exp 005 (V): nothing above the second upper floor
const LOWER_BASEMENT := -2
const BASEMENT := -1
const GROUND := 0
const UPPER := 1
const UPPER2 := 2
const ALL := [-2, -1, 0, 1, 2]
const NAMES := {-2: "Lower basement", -1: "Basement", 0: "Ground floor", 1: "First upper floor", 2: "Second upper floor"}
## Plan directions of the stairs' quarter turns (0 north, 1 east, 2 south, 3 west).
const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const EXIT_GAP := 0.5          ## m from the stairs' end to its exit point
const STEPS := 13

const WOOD_FLOOR_COST := {"wood": 2, "nails": 2}
const STAIRS_COST := {"wood": 8, "nails": 10}
const UPPER_FLOOR_COST := {"wood": 40, "nails": 40, "iron": 4}
const PILLAR_COST := {"stone": 4}      ## Exp 005 (V): a 0.4 m masonry column
## Digging one basement cell: game minutes, energy, stone found.
const DIG_MINUTES := 25.0
const DIG_ENERGY := 6.0
const DIG_STONE := 1
const DIG_MIN_ENERGY := 10.0


static func base_y(storey: int) -> float:
	return float(storey) * HEIGHT


static func name_of(storey: int) -> String:
	return NAMES.get(storey, "Storey %d" % storey)


## Exp 005 (V): "Level +1 · First upper floor" (the HUD indicator, toasts).
static func label(storey: int) -> String:
	return "Level %s · %s" % [number(storey), name_of(storey)]


## "+1", "0", "-2".
static func number(storey: int) -> String:
	if storey == 0:
		return "0"
	return ("+%d" % storey) if storey > 0 else ("-%d" % -storey)


static func valid(storey: int) -> bool:
	return storey >= LOWEST and storey <= HIGHEST


## The storey whose floor is nearest below height y (bodies stand on floors).
static func storey_at(y: float) -> int:
	return clampi(roundi(y / HEIGHT), LOWEST, HIGHEST)


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


## Exp 005 (V): up stairs stand on `lo` (lo >= 0); down stairs hang from lo + 1.
static func is_up(st: Dictionary) -> bool:
	return int(st["lo"]) >= GROUND


## The storey with the stairs' start edge and foot cell (where they are built).
static func start_storey(st: Dictionary) -> int:
	return int(st["lo"]) if is_up(st) else int(st["lo"]) + 1


static func stairs_dir(st: Dictionary) -> Vector2i:
	return DIRS[int(st["rot"])]


static func stairs_cells(st: Dictionary) -> Array:
	var c: Vector2i = st["cell"]
	return [c, c + stairs_dir(st)]


static func stairs_rect(st: Dictionary) -> Rect2:
	var r := cell_rect(st["cell"])
	return r.merge(cell_rect((st["cell"] as Vector2i) + stairs_dir(st)))


## The cell before the start edge (on the start storey: where you step on).
static func foot_cell(st: Dictionary) -> Vector2i:
	return (st["cell"] as Vector2i) - stairs_dir(st)


## The cell past the far edge (on the storey the stairs lead to from their start).
static func far_cell(st: Dictionary) -> Vector2i:
	return (st["cell"] as Vector2i) + stairs_dir(st) * 2


static func _start_edge(st: Dictionary) -> Vector2:
	return cell_center(st["cell"]) - Vector2(stairs_dir(st)) * 0.5


static func _far_edge(st: Dictionary) -> Vector2:
	return _start_edge(st) + Vector2(stairs_dir(st)) * 2.0


## Plan point where a body arrives on `storey` (one of the two the stairs join):
## before the start edge on the start storey, past the far edge on the other.
static func exit_point(st: Dictionary, storey: int) -> Vector2:
	var d := Vector2(stairs_dir(st))
	if storey == start_storey(st):
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
	var away := -d if storey == start_storey(st) else d
	return atan2(-away.x, -away.y)


## Height of step k's walking surface over the start storey's floor (for the
## mesh): from the start edge (0) to the far edge (+HEIGHT up, -HEIGHT down).
static func step_height(st: Dictionary, k: int) -> float:
	var h := HEIGHT * float(k + 1) / float(STEPS)
	return h if is_up(st) else -h


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
	if lo < LOWEST or lo >= HIGHEST:
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


# --- Exp 005 (V): pillars ------------------------------------------------------------------
# A pillar is a 0.4 m x 0.4 m masonry column in the middle of a 1 m cell, the
# full wall height. Its voxels live in the storey's grids (so they are saved,
# shot, carved and repaired like walls); GameLevels keeps the cells.

const PILLAR_HALF := 0.2
const PILLAR_TONES := [0x8a8478, 0x7d776c, 0x938c80, 0x857f73]
const PILLAR_MORTAR := 0xb3ab9c


static func pillar_rect(c: Vector2i) -> Rect2:
	var cc := cell_center(c)
	return Rect2(cc - Vector2.ONE * PILLAR_HALF, Vector2.ONE * PILLAR_HALF * 2.0)


static func stamp_pillar(w: HouseWorld, c: Vector2i) -> void:
	var r := pillar_rect(c)
	var xr := w.design.centre_range(0, r.position.x, r.end.x)
	var zr := w.design.centre_range(2, r.position.y, r.end.y)
	for z in range(zr.x, zr.y):
		for x in range(xr.x, xr.y):
			for k in VoxelHouse.WALL_ROWS:
				var y := VoxelHouse.BASE_ROW + k
				if w.design.get_mat(x, y, z) != VoxelMat.AIR:
					continue
				if k % 3 == 2:
					var mc := VoxelArt.jitter(PILLAR_MORTAR, x, y, z, 0.04)
					_put(w, x, y, z, VoxelMat.MORTAR, mc, mc, 0)
				else:
					var t: int = PILLAR_TONES[(k / 3 + x + z) % PILLAR_TONES.size()]
					var col := VoxelArt.jitter(t, x, y, z, 0.05)
					_put(w, x, y, z, VoxelMat.MASONRY, col, col, 0)
	w._edited(Vector3i(xr.x, VoxelHouse.BASE_ROW, zr.x), Vector3i(xr.y, VoxelHouse.TOP_ROW + 1, zr.y))


## Takes a pillar's masonry out of the design and the current grid.
static func clear_pillar(w: HouseWorld, c: Vector2i) -> int:
	var r := pillar_rect(c)
	var xr := w.design.centre_range(0, r.position.x, r.end.x)
	var zr := w.design.centre_range(2, r.position.y, r.end.y)
	var n := 0
	for z in range(zr.x, zr.y):
		for x in range(xr.x, xr.y):
			for y in range(VoxelHouse.BASE_ROW, VoxelHouse.TOP_ROW + 1):
				var i := w.design.idx(x, y, z)
				var m := w.design.mat[i]
				if m != VoxelMat.MASONRY and m != VoxelMat.MORTAR:
					continue
				w.design.clear_index(i)
				if w.grid.mat[i] != VoxelMat.AIR:
					w.grid.clear_index(i)
				n += 1
	w._edited(Vector3i(xr.x, VoxelHouse.BASE_ROW, zr.x), Vector3i(xr.y, VoxelHouse.TOP_ROW + 1, zr.y))
	return n


## True if at least half of the pillar's masonry (by its design) still stands.
static func pillar_stands(w: HouseWorld, c: Vector2i) -> bool:
	var r := pillar_rect(c)
	var xr := w.grid.centre_range(0, r.position.x, r.end.x)
	var zr := w.grid.centre_range(2, r.position.y, r.end.y)
	var want := 0
	var have := 0
	for z in range(zr.x, zr.y):
		for x in range(xr.x, xr.y):
			for y in range(VoxelHouse.BASE_ROW, VoxelHouse.TOP_ROW + 1):
				var i := w.grid.idx(x, y, z)
				var m := w.design.mat[i]
				if m == VoxelMat.MASONRY or m == VoxelMat.MORTAR:
					want += 1
					if w.grid.mat[i] != VoxelMat.AIR:
						have += 1
	return want > 0 and have * 2 >= want


## Plan rects of the stairs (helper for callers that only hold the list).
static func stairs_rect_any(list: Array, p: Vector2) -> bool:
	for st in list:
		if stairs_rect(st).has_point(p):
			return true
	return false
