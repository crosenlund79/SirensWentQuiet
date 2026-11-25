class_name WeightedNav
extends RefCounted
## A path planner over a shared GridNav with its own bash weight (the cost of
## crossing a wall, door or barricade cell). The shared nav uses
## GridNav.BASH_WEIGHT (12); a runner plans with a high weight (detours to an
## open door or a hole when one exists), a brute with a low one (goes through).
## Walkable and solid cells are exactly the shared nav's; only bashable cells
## get another weight. Plug it into PursuitBrain.planner.
##
## One layer per (nav, weight), shared by every enemy that uses it (for_nav):
## kept in the nav's metadata, holding the nav only weakly, so it goes away
## with the nav.
## It follows the nav's `revision`: changed raw rows are found by comparing
## row slices of the raw occupancy, and only the 3x3 neighbourhoods of changed
## cells are recomputed (a full rebuild if the raw array isn't readable).
##
## Exp 006 (D): walkable cells keep the nav's own step cost (a dry trench
## costs GridNav.TRENCH_WEIGHT), and a wading layer (`wade`, the brute) may
## cross water-filled trench cells at WADE_WEIGHT per cell; everyone else
## treats water as solid.

const WADE_WEIGHT := 10.0

var nav: GridNav:
	get:
		return _nav_ref.get_ref() as GridNav
var weight := GridNav.BASH_WEIGHT
var wade := false                   ## Exp 006 (D): may cross water (slowly)
var rebuilds := 0                   ## full rebuilds (tests)
var patched := 0                    ## cells patched incrementally (tests)
var _astar := AStarGrid2D.new()
var _rev := -1
var _raw := PackedByteArray()
var _nav_ref: WeakRef


## The shared planner for `nav` and `w`: the nav itself for the default weight.
## Exp 006 (D): `wading` gives a layer that crosses water.
static func for_nav(grid: GridNav, w: float, wading := false) -> Object:
	if grid == null or (is_equal_approx(w, GridNav.BASH_WEIGHT) and not wading):
		return grid
	var key := "ai_weighted_nav_%d%s" % [roundi(w * 100.0), "_wade" if wading else ""]
	if grid.has_meta(key):
		return grid.get_meta(key)
	var layer := WeightedNav.new(grid, w, wading)
	grid.set_meta(key, layer)
	return layer


func _init(grid: GridNav, w: float, wading := false) -> void:
	_nav_ref = weakref(grid)
	weight = w
	wade = wading
	_astar.region = Rect2i(Vector2i.ZERO, grid.size)
	_astar.cell_size = Vector2.ONE
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()


## Same contract as GridNav.find_path.
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var n := nav
	var out := PackedVector2Array()
	if n == null:
		return out
	sync()
	var a := _nearest_passable(n, n.cell_of(from))
	var b := _nearest_passable(n, n.cell_of(to))
	if a.x < 0 or b.x < 0:
		return out
	for c in _astar.get_id_path(a, b, true):
		out.append(n.center_of(c))
	return out


## Brings the layer up to the nav's revision.
func sync() -> void:
	var n := nav
	if n == null or _rev == n.revision:
		return
	var raw: Variant = n.get("_raw")
	if _rev < 0 or typeof(raw) != TYPE_PACKED_BYTE_ARRAY or (raw as PackedByteArray).size() != n.size.x * n.size.y:
		_full(n)
	else:
		_patch(n, raw)
	_rev = n.revision


func _full(n: GridNav) -> void:
	rebuilds += 1
	for j in n.size.y:
		for i in n.size.x:
			_set_cell(n, Vector2i(i, j))
	var raw: Variant = n.get("_raw")
	_raw = (raw as PackedByteArray).duplicate() if typeof(raw) == TYPE_PACKED_BYTE_ARRAY else PackedByteArray()


func _patch(n: GridNav, raw: PackedByteArray) -> void:
	var w := n.size.x
	var dirty := {}
	for j in n.size.y:
		var a := j * w
		if raw.slice(a, a + w) == _raw.slice(a, a + w):
			continue
		for i in w:
			if raw[a + i] != _raw[a + i]:
				for dj in range(-1, 2):
					for di in range(-1, 2):
						dirty[Vector2i(i + di, j + dj)] = true
	for c in dirty:
		if n.in_grid(c):
			_set_cell(n, c)
			patched += 1
	_raw = raw.duplicate()


func _set_cell(n: GridNav, c: Vector2i) -> void:
	if wade and n.is_wade(c):          # Exp 006 (D): wading through water
		_astar.set_point_solid(c, false)
		_astar.set_point_weight_scale(c, WADE_WEIGHT)
		return
	_astar.set_point_solid(c, not n.is_passable(c))
	_astar.set_point_weight_scale(c, weight if n.is_bashable(c) else n.walk_weight(c))


func _nearest_passable(n: GridNav, c: Vector2i) -> Vector2i:
	c = c.clamp(Vector2i.ZERO, n.size - Vector2i.ONE)
	if n.is_walkable(c):
		return c
	var fallback := Vector2i(-1, -1)
	for r in range(1, 9):
		for dj in range(-r, r + 1):
			for di in range(-r, r + 1):
				if maxi(absi(di), absi(dj)) != r:
					continue
				var k := c + Vector2i(di, dj)
				if n.is_walkable(k):
					return k
				if fallback.x < 0 and (n.is_passable(k) or (wade and n.is_wade(k))):
					fallback = k
		if fallback.x >= 0 and r >= 2:
			return fallback
	if n.is_passable(c) or (wade and n.is_wade(c)):
		return c
	return fallback
