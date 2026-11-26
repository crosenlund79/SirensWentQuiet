class_name RegionRouter
extends RefCounted
## Exp 012 (L, §20): the one route and travel time of every leg on the region
## map. A weighted grid A* over RegionTerrain (1 cell = 25 m): on foot Eli is
## not tied to the roads (gardens, fields, parks, open land and forest are
## fine, roads are the quickest ground), never through buildings, other
## places' lots, open water (bridges are fine) or cliffs. The car is an old,
## battered off-road 4x4: roads are fast, open ground (fields, lawns, dirt,
## sand, a quarry floor) slower, and dense forest, rock, snow, gardens,
## buildings, water and steep slopes are out.
##
## route(from, to, car) -> {"pts": PackedVector2Array (region positions, the
## places' centres at the ends), "minutes": int (rounded to 5, at least 5),
## "raw": float minutes, "km", "road_km", "off_km", "ok": bool (false: no
## path, a straight-line estimate)}. minutes() is route()["minutes"]: the map
## draws `pts` and shows `minutes`, and the travel flow advances the clock by
## the same `minutes` (TravelRules), so what is shown is what is used.
## Deterministic (the terrain is) and cached per leg; either end may be
## "home". road_only(from, to, car) prices the old road route with the same
## costs (F10 route debug, tests).

const HOME := "home"
const CELL_KM := RegionLocations.CELL_M / 1000.0
## Minutes per km by ground, on foot and by car (INF = impassable).
const FOOT_ROAD := {RegionTerrain.R_MAIN: 12.0, RegionTerrain.R_STREET: 12.0, RegionTerrain.R_LANE: 13.0}
const CAR_ROAD := {RegionTerrain.R_MAIN: 6.0, RegionTerrain.R_STREET: 7.0, RegionTerrain.R_LANE: 8.0}
const FOOT_COVER := {
	RegionTerrain.C_PAVED: 13.0, RegionTerrain.C_YARD: 14.0, RegionTerrain.C_QUAY: 14.0, RegionTerrain.C_PARK: 15.0,
	RegionTerrain.C_LAWN: 16.0, RegionTerrain.C_GRASS: 16.0, RegionTerrain.C_MEADOW: 17.0, RegionTerrain.C_DIRT: 15.0,
	RegionTerrain.C_FIELD: 19.0, RegionTerrain.C_SAND: 21.0, RegionTerrain.C_QUARRY: 22.0, RegionTerrain.C_FOREST: 25.0,
	RegionTerrain.C_ROCK: 32.0, RegionTerrain.C_SNOW: 40.0,
}
const CAR_COVER := {
	RegionTerrain.C_PAVED: 9.0, RegionTerrain.C_YARD: 10.0, RegionTerrain.C_QUAY: 10.0, RegionTerrain.C_PARK: 13.0,
	RegionTerrain.C_LAWN: 13.0, RegionTerrain.C_GRASS: 13.0, RegionTerrain.C_MEADOW: 14.0, RegionTerrain.C_DIRT: 11.0,
	RegionTerrain.C_FIELD: 15.0, RegionTerrain.C_SAND: 17.0, RegionTerrain.C_QUARRY: 14.0,
}
const FOOT_GARDEN := 22.0         ## a suburban or rural lot with its house: round the house, over the fence
const FOOT_CLIFF := 7             ## height steps to a neighbour: too steep to walk (off a road)
const CAR_CLIFF := 3              ## ... too steep for the 4x4 off a road
const LOT := 13.0                 ## the start and end places' own lots (both modes)

static var _grids := {}           ## "foot" / "car" -> AStarGrid2D
static var _costs := {}           ## "foot" / "car" -> PackedFloat32Array minutes per cell (INF = solid)
static var _owner := {}           ## Vector2i -> place id ("home" too): the places' lots
static var _cache := {}           ## "from|to|car" -> route


## The route of a leg (see the header). Either end may be "home".
## Both ways of a leg are one route (solved from home's side, or from the
## place first in order), so there and back always agree.
static func route(from: String, to: String, car := false) -> Dictionary:
	var flip := to == HOME or (from != HOME and from > to)
	var a := to if flip else from
	var b := from if flip else to
	var key := "%s|%s|%s" % [a, b, car]
	if not _cache.has(key):
		_cache[key] = _solve(a, b, car)
	var r: Dictionary = _cache[key]
	if not flip:
		return r
	var back := r.duplicate()
	var pts: PackedVector2Array = (r["pts"] as PackedVector2Array).duplicate()
	pts.reverse()
	back["pts"] = pts
	return back


## One-way minutes of a leg (rounded to 5, at least 5; 0 for the same place
## or an unknown end).
static func minutes(from: String, to: String, car := false) -> int:
	if from == to or not _known(from) or not _known(to):
		return 0
	return int(route(from, to, car)["minutes"])


## The minutes of the region's old road-only route, with the same costs
## (debug and tests). -1 when there is no road route.
static func road_only(from: String, to: String, car := false) -> float:
	var t := RegionTerrain.shared()
	var pts := t.route_between(from, to)
	if pts.size() < 2:
		return -1.0
	_ensure()
	var c: PackedFloat32Array = _costs["car" if car else "foot"]
	var raw := 0.0
	for k in range(1, pts.size()):
		var b := RegionTerrain.cell_of(pts[k])
		var step := pts[k - 1].distance_to(pts[k])
		var w := c[RegionTerrain.idx(b)]
		if _owner.has(b) or not is_finite(w):
			w = LOT * CELL_KM
		raw += step * w
	return raw


## Developer and tests: drops the cached routes and grids.
static func reset() -> void:
	_grids.clear()
	_costs.clear()
	_owner.clear()
	_cache.clear()


## Minutes per cell for a mode at cell c (INF: impassable), the lots aside.
static func cell_cost(c: Vector2i, car := false) -> float:
	_ensure()
	if not RegionTerrain.in_bounds(c):
		return INF
	return (_costs["car" if car else "foot"] as PackedFloat32Array)[RegionTerrain.idx(c)]


static func pos_of(id: String) -> Vector2:
	if id == HOME:
		return RegionLocations.HOME
	return RegionLocations.get_def(id).get("pos", RegionLocations.HOME)


static func _known(id: String) -> bool:
	return id == HOME or RegionLocations.has(id)


# --- the grids ------------------------------------------------------------------------------

static func _ensure() -> void:
	if not _grids.is_empty():
		return
	var t := RegionTerrain.shared()
	var ids: Array = RegionLocations.ids().duplicate()
	ids.append(HOME)
	for id in ids:
		var r := RegionTerrain.footprint(id)
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				_owner[Vector2i(x, y)] = id
	for mode in ["foot", "car"]:
		var car: bool = mode == "car"
		var costs := PackedFloat32Array()
		costs.resize(RegionTerrain.W * RegionTerrain.H)
		var lo := INF
		for y in RegionTerrain.H:
			for x in RegionTerrain.W:
				var c := Vector2i(x, y)
				var w := _ground(t, c, car)
				costs[RegionTerrain.idx(c)] = w
				if is_finite(w):
					lo = minf(lo, w)
		var g := AStarGrid2D.new()
		g.region = Rect2i(0, 0, RegionTerrain.W, RegionTerrain.H)
		g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		g.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
		g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
		g.update()
		# weights relative to the cheapest ground (>= 1), so the straight-line
		# heuristic never overestimates and A* finds the cheapest route
		for y in RegionTerrain.H:
			for x in RegionTerrain.W:
				var c := Vector2i(x, y)
				var w := costs[RegionTerrain.idx(c)]
				if _owner.has(c) or not is_finite(w):
					g.set_point_solid(c, true)
				else:
					g.set_point_weight_scale(c, w / lo)
		_grids[mode] = g
		_costs[mode] = costs
		_costs[mode + "_lo"] = lo


## Minutes per cell of the ground at c (see the header), INF = impassable.
static func _ground(t: RegionTerrain, c: Vector2i, car: bool) -> float:
	var i := RegionTerrain.idx(c)
	var rd := int(t.road[i])
	if t.water[i] > 0:
		if t.bridge[i] > 0 and rd != RegionTerrain.R_NONE:
			return float((CAR_ROAD if car else FOOT_ROAD).get(rd, 12.0)) * CELL_KM
		return INF
	if rd != RegionTerrain.R_NONE:
		return float((CAR_ROAD if car else FOOT_ROAD).get(rd, 12.0)) * CELL_KM
	var cover := int(t.cover[i])
	var per_km := INF
	if int(t.plot[i]) == 2:
		# a building lot: a garden round a house on foot; never by car, never a block
		per_km = FOOT_GARDEN if not car and cover == RegionTerrain.C_LAWN else INF
	else:
		per_km = float((CAR_COVER if car else FOOT_COVER).get(cover, INF))
	if not is_finite(per_km):
		return INF
	var s := _slope(t, c)
	if s >= (CAR_CLIFF if car else FOOT_CLIFF):
		return INF
	per_km *= 1.0 + (0.15 if car else 0.12) * maxf(float(s - 1), 0.0)
	return per_km * CELL_KM


static func _slope(t: RegionTerrain, c: Vector2i) -> int:
	var s := 0
	var h := t.height_at(c)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = c + d
		if RegionTerrain.in_bounds(n) and t.water_at(n) <= 0:
			s = maxi(s, absi(h - t.height_at(n)))
	return s


# --- solving --------------------------------------------------------------------------------------

static func _lot_cells(id: String) -> Array:
	var out := []
	var r := RegionTerrain.footprint(id)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			if RegionTerrain.in_bounds(c) and _owner.get(c, "") == id:
				out.append(c)
	return out


static func _solve(from: String, to: String, car: bool) -> Dictionary:
	var a := pos_of(from)
	var b := pos_of(to)
	if from == to or not _known(from) or not _known(to):
		return {"pts": PackedVector2Array([a, b]), "minutes": 0, "raw": 0.0, "km": 0.0, "road_km": 0.0, "off_km": 0.0, "ok": false}
	_ensure()
	var mode := "car" if car else "foot"
	var g: AStarGrid2D = _grids[mode]
	var lo := float(_costs[mode + "_lo"])
	var lot_w := LOT * CELL_KM
	var opened := []
	for id in [from, to]:
		for c in _lot_cells(id):
			g.set_point_solid(c, false)
			g.set_point_weight_scale(c, lot_w / lo)
			opened.append(c)
	var ca := RegionTerrain.cell_of(a)
	var cb := RegionTerrain.cell_of(b)
	var path: Array[Vector2i] = []
	if not g.is_point_solid(ca) and not g.is_point_solid(cb):
		path = g.get_id_path(ca, cb)
	for c in opened:
		g.set_point_solid(c, true)
	if path.size() < 2:
		return _fallback(from, to, car)
	var cells := PackedVector2Array()
	for c in path:
		cells.append(Vector2(c) + Vector2(0.5, 0.5))
	var r := _price(cells, car)
	var pts := _simplify(cells)
	pts[0] = a
	pts[pts.size() - 1] = b
	r["pts"] = pts
	r["ok"] = true
	return r


## Minutes and km along a cell-centre polyline with the mode's costs (the
## same step costs A* used: step length x the entered cell's cost).
static func _price(cells: PackedVector2Array, car: bool) -> Dictionary:
	var costs: PackedFloat32Array = _costs["car" if car else "foot"]
	var t := RegionTerrain.shared()
	var raw := 0.0
	var road := 0.0
	var off := 0.0
	for k in range(1, cells.size()):
		var c := RegionTerrain.cell_of(cells[k])
		var step := cells[k - 1].distance_to(cells[k])
		var w := costs[RegionTerrain.idx(c)]
		if _owner.has(c) or not is_finite(w):
			w = LOT * CELL_KM
		raw += step * w
		if int(t.road[RegionTerrain.idx(c)]) != RegionTerrain.R_NONE:
			road += step * CELL_KM
		else:
			off += step * CELL_KM
	return {"minutes": _round(raw), "raw": raw, "km": road + off, "road_km": road, "off_km": off}


static func _round(raw: float) -> int:
	return maxi(int(round(raw / 5.0)) * 5, 5)


## Drops the points in the middle of straight runs (the polyline and its
## length stay the same).
static func _simplify(cells: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in cells.size():
		if k == 0 or k == cells.size() - 1:
			out.append(cells[k])
			continue
		var d0 := (cells[k] - cells[k - 1]).normalized()
		var d1 := (cells[k + 1] - cells[k]).normalized()
		if d0.is_equal_approx(d1):
			continue
		out.append(cells[k])
	return out


## No path (should not happen: every place has a road to the house): the
## road route when there is one, else a straight line at a walking pace.
static func _fallback(from: String, to: String, car: bool) -> Dictionary:
	var t := RegionTerrain.shared()
	var pts := t.route_between(from, to)
	var raw := road_only(from, to, car)
	if pts.size() >= 2 and raw >= 0.0:
		var km := 0.0
		for k in range(1, pts.size()):
			km += pts[k - 1].distance_to(pts[k]) * CELL_KM
		return {"pts": pts, "minutes": _round(raw), "raw": raw, "km": km, "road_km": km, "off_km": 0.0, "ok": false}
	var a := pos_of(from)
	var b := pos_of(to)
	var km2 := a.distance_to(b) * CELL_KM
	var raw2 := km2 * RegionLocations.ROAD_FACTOR * RegionLocations.MINUTES_PER_KM * (ExpeditionData.CAR_TRAVEL if car else 1.0)
	return {"pts": PackedVector2Array([a, b]), "minutes": _round(raw2), "raw": raw2, "km": km2, "road_km": 0.0, "off_km": km2, "ok": false}
