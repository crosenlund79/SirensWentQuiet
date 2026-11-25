class_name GridNav
extends RefCounted
## Rudimentary, rebuildable navigation grid in plan meters (see HousePlan).
##
## Each version owns its geometry and writes a *raw* occupancy per cell:
##   OPEN  - free floor / ground
##   WALL  - destructible wall material (enemies may bash through it)
##   SOLID - furniture, props, anything not destructible
## Raw cells are sampled at the cell CENTRE ("centre-in-rect" for rects).
## Cell (i, j) has its centre at YARD.position + (i, j) * CELL, so wall
## centre lines on whole meters pass through cell centres.
##
## Derived per cell (3x3 inflation = clearance for a 0.25 m radius body):
##   walkable - no WALL/SOLID in the 3x3 neighbourhood     (weight 1)
##   bashable - not walkable, but only WALL nearby         (weight BASH_WEIGHT)
##   blocked  - SOLID in the neighbourhood                 (never entered)
## A path through bashable cells means "break the wall here"; the cost makes
## enemies prefer real openings unless the detour is long.
## Call refresh_region() after changing raw cells; `revision` then increases
## so pursuers repath and immediately use new openings.
##
## Exp 006 (D), defences (src/defense/): two more raw kinds on the outdoor lot.
##   WATER  - a water-filled trench cell: blocked like SOLID for the shared
##            nav (never entered); `is_wade(c)` marks cells blocked only by
##            water, which a wading planner (WeightedNav, brutes) may cross
##   TRENCH - a dry trench cell: walkable, but each step costs TRENCH_WEIGHT
##            (walk_weight) and bodies slow down in it

enum { OPEN = 0, WALL = 1, SOLID = 2, WATER = 3, TRENCH = 4 }

const CELL := 0.25
const BASH_WEIGHT := 12.0
const TRENCH_WEIGHT := 4.0       ## Exp 006 (D): per dry-trench cell

var bounds: Rect2
var size: Vector2i
var revision := 0
var _raw := PackedByteArray()
var _walkable := PackedByteArray()
var _wade := PackedByteArray()      # Exp 006 (D): 1 = blocked only by water nearby
var _astar := AStarGrid2D.new()


func _init(area: Rect2 = HousePlan.YARD) -> void:
	bounds = area
	size = Vector2i(int(round(area.size.x / CELL)) + 1, int(round(area.size.y / CELL)) + 1)
	_raw.resize(size.x * size.y)
	_raw.fill(OPEN)
	_walkable.resize(size.x * size.y)
	_walkable.fill(1)
	_wade.resize(size.x * size.y)
	_wade.fill(0)
	_astar.region = Rect2i(Vector2i.ZERO, size)
	_astar.cell_size = Vector2.ONE
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()


# --- coordinates ---------------------------------------------------------------

func cell_of(p: Vector2) -> Vector2i:
	var q := (p - bounds.position) / CELL
	return Vector2i(int(round(q.x)), int(round(q.y)))


func center_of(c: Vector2i) -> Vector2:
	return bounds.position + Vector2(c) * CELL


func in_grid(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y


# --- raw occupancy -------------------------------------------------------------

func get_raw(c: Vector2i) -> int:
	return _raw[c.y * size.x + c.x] if in_grid(c) else SOLID


func set_raw(c: Vector2i, kind: int) -> void:
	if in_grid(c):
		_raw[c.y * size.x + c.x] = kind


## Cells whose centre lies in [rect.position, rect.end) get `kind`.
func mark_rect(rect: Rect2, kind: int) -> void:
	for c in cells_in_rect(rect):
		set_raw(c, kind)


func cells_in_rect(rect: Rect2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var lo := (rect.position - bounds.position) / CELL
	var hi := (rect.end - bounds.position) / CELL
	for j in range(int(ceil(lo.y - 1e-4)), int(ceil(hi.y - 1e-4))):
		for i in range(int(ceil(lo.x - 1e-4)), int(ceil(hi.x - 1e-4))):
			var c := Vector2i(i, j)
			if in_grid(c):
				out.append(c)
	return out


# --- derived walkability ------------------------------------------------------

func rebuild() -> void:
	_recompute(Rect2i(Vector2i.ZERO, size))


## Recompute derived data around `rect` (meters) after raw cells changed.
func refresh_region(rect: Rect2) -> void:
	var a := cell_of(rect.position) - Vector2i(2, 2)
	var b := cell_of(rect.end) + Vector2i(2, 2)
	_recompute(Rect2i(a, b - a + Vector2i.ONE))


func _recompute(r: Rect2i) -> void:
	r = r.intersection(Rect2i(Vector2i.ZERO, size))
	for j in range(r.position.y, r.end.y):
		for i in range(r.position.x, r.end.x):
			_recompute_cell(i, j)
	revision += 1


## Exp 006 (D): recomputes the derived data of just these cells (each once),
## e.g. the 3x3 neighbourhoods of changed raw cells; one revision step.
func refresh_cells(list: Array) -> void:
	for c in list:
		if in_grid(c):
			_recompute_cell(c.x, c.y)
	revision += 1


func _recompute_cell(i: int, j: int) -> void:
	var has_wall := false
	var has_solid := false
	var has_water := false
	for dj in range(-1, 2):
		for di in range(-1, 2):
			var k := get_raw(Vector2i(i + di, j + dj))
			if k == SOLID:
				has_solid = true
			elif k == WALL:
				has_wall = true
			elif k == WATER:
				has_water = true
	var c := Vector2i(i, j)
	var idx := j * size.x + i
	_walkable[idx] = 1 if not (has_wall or has_solid or has_water) else 0
	_wade[idx] = 1 if has_water and not has_solid else 0
	_astar.set_point_solid(c, has_solid or has_water)
	_astar.set_point_weight_scale(c, BASH_WEIGHT if has_wall and not (has_solid or has_water) else walk_weight(c))


func is_walkable(c: Vector2i) -> bool:
	return in_grid(c) and _walkable[c.y * size.x + c.x] == 1


func is_bashable(c: Vector2i) -> bool:
	return in_grid(c) and not is_walkable(c) and not _astar.is_point_solid(c)


func is_passable(c: Vector2i) -> bool:
	return in_grid(c) and not _astar.is_point_solid(c)


## Exp 006 (D): the cost of one step on a walkable cell (a dry trench costs more).
func walk_weight(c: Vector2i) -> float:
	return TRENCH_WEIGHT if get_raw(c) == TRENCH else 1.0


## Exp 006 (D): blocked only because water is next to it (a wader may cross).
func is_wade(c: Vector2i) -> bool:
	return in_grid(c) and _wade[c.y * size.x + c.x] == 1


# --- queries -------------------------------------------------------------------

## Path in plan meters from `from` to `to` (first point = start cell centre).
## Unreachable targets yield a path toward the closest reachable cell.
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var a := _nearest_passable(cell_of(from))
	var b := _nearest_passable(cell_of(to))
	if a.x < 0 or b.x < 0:
		return out
	var ids := _astar.get_id_path(a, b, true)
	for c in ids:
		out.append(center_of(c))
	return out


## True if a body can walk straight from a to b without touching walls.
func segment_walkable(a: Vector2, b: Vector2) -> bool:
	var n := int(ceil(a.distance_to(b) / (CELL * 0.4))) + 1
	for s in range(n + 1):
		if not is_walkable(cell_of(a.lerp(b, float(s) / float(n)))):
			return false
	return true


## True if no raw WALL/SOLID cell lies on the segment (line of sight at body height).
## Exp 006 (D): trenches and water are below body height: they don't block.
func segment_clear(a: Vector2, b: Vector2) -> bool:
	var n := int(ceil(a.distance_to(b) / (CELL * 0.4))) + 1
	for s in range(n + 1):
		var k := get_raw(cell_of(a.lerp(b, float(s) / float(n))))
		if k == WALL or k == SOLID:
			return false
	return true


## Nearest raw WALL cell within `radius` cells of `c`, measured from `from`.
## Returns Vector2i(-1, -1) if none.
func nearest_raw_wall(c: Vector2i, from: Vector2, radius: int = 1) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for dj in range(-radius, radius + 1):
		for di in range(-radius, radius + 1):
			var k := c + Vector2i(di, dj)
			if get_raw(k) == WALL and in_grid(k):
				var d := from.distance_squared_to(center_of(k))
				if d < best_d:
					best_d = d
					best = k
	return best


func _nearest_passable(c: Vector2i) -> Vector2i:
	c = c.clamp(Vector2i.ZERO, size - Vector2i.ONE)
	if is_walkable(c):
		return c
	var fallback := Vector2i(-1, -1)
	for r in range(1, 9):
		for dj in range(-r, r + 1):
			for di in range(-r, r + 1):
				if maxi(absi(di), absi(dj)) != r:
					continue
				var k := c + Vector2i(di, dj)
				if is_walkable(k):
					return k
				if fallback.x < 0 and is_passable(k):
					fallback = k
		if fallback.x >= 0 and r >= 2:
			return fallback
	if is_passable(c):
		return c
	return fallback
