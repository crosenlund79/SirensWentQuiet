class_name RegionTerrain
extends RefCounted
## The deterministic region behind the voxel city map (SPEC-003 §6). Owner: M.
## Pure data, no nodes: a heightfield of RegionLocations.SIZE columns (1 cell
## = 1 world unit = 25 m), water levels, land cover, roads, districts, plus
## the building boxes and tree instances that RegionMapMesher turns into meshes.
##
## The layout is authored around RegionLocations (coastline, river course,
## ring road, Route 9, district shapes, special buildings per location) with
## procedural detail (FastNoiseLite hills, ridges, forests, street blocks,
## houses, roads found by A* between every place and HOME). The same build
## always gives the same region (content_hash()). LAYOUT_ID names this layout;
## RegionState.layout is compared against it.
##
##   var t := RegionTerrain.shared()        # built once, cached
##   t.height_at(Vector2i(58, 92))          # ground level in steps
##   t.district_at(Vector2i(94, 54))        # "centre"
##   t.route_from_home("quarry")            # road path (region cells)

const LAYOUT_ID := "region-v1"
const W := 160
const H := 120
const STEP := 0.5            ## world units per height step (columns are 1 x 1)
const SEA := 4               ## sea surface level (steps)
const BASE := -6             ## bottom of the diorama block (steps)
const SEED := 3117

# land cover
const C_GRASS := 0
const C_MEADOW := 1
const C_FOREST := 2
const C_FIELD := 3
const C_SAND := 4
const C_ROCK := 5
const C_SNOW := 6
const C_PAVED := 7
const C_YARD := 8
const C_QUAY := 9
const C_PARK := 10
const C_BED := 11
const C_QUARRY := 12
const C_LAWN := 13
const C_DIRT := 14

# roads
const R_NONE := 0
const R_LANE := 1      ## rural gravel lane
const R_STREET := 2    ## town street
const R_MAIN := 3      ## ring road and Route 9

const DISTRICT_IDS := ["", "suburbs", "centre", "industrial", "docks", "forest", "mountains", "hills", "farmland"]

## Authored east coast: (row y, shoreline x). The docks quay (rows 57..85) is straight.
const COAST := [Vector2(0, 146), Vector2(18, 148), Vector2(32, 153), Vector2(42, 153), Vector2(49, 143), Vector2(54, 131),
	Vector2(57, 129.5), Vector2(85, 129.5), Vector2(89, 134), Vector2(95, 149), Vector2(102, 154), Vector2(110, 152), Vector2(120, 147)]
const DOCKS_ROWS := Vector2(57, 85)
## River centreline from the mountain tarn to the bay (region cells).
const RIVER := [Vector2(15, 12), Vector2(22, 16.5), Vector2(31, 20.5), Vector2(41, 22.5), Vector2(51, 24.5),
	Vector2(61, 25.5), Vector2(70, 26.3), Vector2(76, 27.2), Vector2(81, 28.6), Vector2(83.5, 32), Vector2(84.3, 38),
	Vector2(84.4, 45), Vector2(84.3, 51), Vector2(84.3, 56.5), Vector2(86.4, 61), Vector2(87.8, 65), Vector2(88.2, 70.5),
	Vector2(90.5, 77), Vector2(94.5, 82.3), Vector2(100, 84.4), Vector2(106, 83.5), Vector2(112, 81.6), Vector2(118, 82.4),
	Vector2(124, 83), Vector2(132, 83.5)]
## Main roads (polylines in cells). The ring road is generated (RING).
const ROUTE_9 := [Vector2(0, 88), Vector2(24, 90), Vector2(44, 93), Vector2(54, 98), Vector2(64, 100), Vector2(88, 100),
	Vector2(94, 97), Vector2(118, 95), Vector2(126, 91), Vector2(126, 64)]
const RING := Rect2(76, 44, 40, 34)     ## ring road around the centre (rounded corners)
const RING_RADIUS := 4.0
const CORE := Vector2(97, 62)           ## tallest towers
const HOME_PLOT := Vector2(3, 3)

# --- palettes (muted, like the house in the fog) -------------------------------
const WALLS := [Color(0.78, 0.74, 0.66), Color(0.85, 0.83, 0.78), Color(0.62, 0.66, 0.68), Color(0.66, 0.69, 0.6),
	Color(0.8, 0.73, 0.56), Color(0.6, 0.45, 0.37), Color(0.52, 0.56, 0.6), Color(0.74, 0.68, 0.62)]
const ROOFS := [Color(0.3, 0.31, 0.33), Color(0.42, 0.31, 0.27), Color(0.5, 0.33, 0.27), Color(0.36, 0.38, 0.42), Color(0.26, 0.27, 0.3)]
const CITY := [Color(0.66, 0.65, 0.62), Color(0.55, 0.55, 0.55), Color(0.7, 0.64, 0.54), Color(0.47, 0.5, 0.55),
	Color(0.6, 0.46, 0.38), Color(0.42, 0.44, 0.48), Color(0.78, 0.76, 0.72), Color(0.53, 0.57, 0.58), Color(0.62, 0.55, 0.47), Color(0.36, 0.38, 0.42)]
const SHEDS := [Color(0.52, 0.56, 0.6), Color(0.6, 0.58, 0.54), Color(0.55, 0.43, 0.35), Color(0.66, 0.66, 0.64), Color(0.42, 0.48, 0.52)]
const CARS := [Color(0.62, 0.62, 0.64), Color(0.32, 0.34, 0.38), Color(0.55, 0.28, 0.24), Color(0.3, 0.38, 0.5), Color(0.8, 0.8, 0.78), Color(0.45, 0.5, 0.4)]
const CONTAINERS := [Color(0.58, 0.3, 0.25), Color(0.3, 0.42, 0.55), Color(0.36, 0.5, 0.38), Color(0.72, 0.5, 0.28), Color(0.6, 0.6, 0.6)]
const PINE := [Color(0.27, 0.38, 0.31), Color(0.24, 0.34, 0.3), Color(0.31, 0.41, 0.32), Color(0.22, 0.31, 0.27)]
const LEAF := [Color(0.5, 0.54, 0.3), Color(0.7, 0.56, 0.3), Color(0.64, 0.38, 0.24), Color(0.42, 0.5, 0.32), Color(0.76, 0.66, 0.36), Color(0.56, 0.46, 0.28)]
const CONCRETE := Color(0.62, 0.6, 0.57)
const ASPHALT := Color(0.3, 0.3, 0.31)
const RUST := Color(0.5, 0.32, 0.22)
const WOOD := Color(0.5, 0.38, 0.27)
const LOGS := Color(0.45, 0.33, 0.22)
const OLIVE := Color(0.38, 0.42, 0.3)
const KHAKI := Color(0.58, 0.54, 0.4)
const CRANE := Color(0.74, 0.4, 0.24)
const MACHINE := Color(0.78, 0.63, 0.24)
const WARM := Color(1.0, 0.74, 0.42)

# --- data ----------------------------------------------------------------------
var height := PackedInt32Array()     ## ground top (steps)
var water := PackedInt32Array()      ## water surface (steps), 0 = dry
var cover := PackedByteArray()       ## C_*
var road := PackedByteArray()        ## R_*
var bridge := PackedInt32Array()     ## bridge deck level (steps) or 0
var district := PackedByteArray()    ## index into DISTRICT_IDS
var waterkind := PackedByteArray()   ## 0 dry, 1 river or lake, 2 sea
var plot := PackedByteArray()        ## 1: a location's footprint (or HOME), 2: a building lot
var field := PackedByteArray()       ## farmland crop (0..3) for C_FIELD cells
## Building masses: [lo: Vector3, hi: Vector3, color: Color, glow: float] in world units.
var boxes: Array = []
## Tree instances: [pos: Vector3, variant: int, scale: float, tint: Color, quarter_turns: int].
var trees: Array = []
var river_path := PackedVector2Array()
var river_level := PackedInt32Array()
var loc_level := {}      ## id -> pad level (steps); "home" included
var loc_top := {}        ## id -> highest point of its buildings (world y)
var home_light := Vector3.ZERO
var build_ms := 0.0

var _rng := RandomNumberGenerator.new()
var _n_hills := FastNoiseLite.new()
var _n_detail := FastNoiseLite.new()
var _n_ridge := FastNoiseLite.new()
var _n_warp := FastNoiseLite.new()
var _n_forest := FastNoiseLite.new()
var _n_coast := FastNoiseLite.new()
var _paths: Array = []   ## road paths (Array of PackedVector2Array) for smoothing
var _road_astar: AStarGrid2D
var _reach := {}
var _box_owner := ""     ## location id whose buildings are being placed (for loc_top)

static var _shared: RegionTerrain


## The region, built on first use and cached for the session (deterministic).
static func shared() -> RegionTerrain:
	if _shared == null:
		_shared = RegionTerrain.new()
		_shared.build()
	return _shared


func build() -> void:
	var t0 := Time.get_ticks_usec()
	_setup()
	_base_heights()
	_districts()
	_carve_river()
	_pads()
	_roads()
	_levees()
	_land_cover()
	_buildings()
	_trees()
	build_ms = (Time.get_ticks_usec() - t0) / 1000.0


# --- queries -------------------------------------------------------------------

static func idx(c: Vector2i) -> int:
	return c.y * W + c.x


static func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H


static func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(clampi(int(floor(pos.x)), 0, W - 1), clampi(int(floor(pos.y)), 0, H - 1))


func height_at(c: Vector2i) -> int:
	return height[idx(c)] if in_bounds(c) else BASE


func water_at(c: Vector2i) -> int:
	return water[idx(c)] if in_bounds(c) else 0


func is_water(c: Vector2i) -> bool:
	return in_bounds(c) and water[idx(c)] > 0


func district_at(c: Vector2i) -> String:
	return DISTRICT_IDS[district[idx(c)]] if in_bounds(c) else ""


## Top of the ground, a bridge deck or the water surface at a cell (world y).
func surface_y(c: Vector2i) -> float:
	if not in_bounds(c):
		return 0.0
	var i := idx(c)
	return maxf(maxf(height[i], water[i]), bridge[i]) * STEP


## World position on the surface for a region position (cells, continuous).
func world_of(pos: Vector2) -> Vector3:
	return Vector3(pos.x, surface_y(cell_of(pos)), pos.y)


## Ground anchor of a location (or "home") for markers, in world units.
func anchor_of(id: String) -> Vector3:
	var pos := RegionLocations.HOME if id == "home" else (RegionLocations.get_def(id).get("pos", Vector2.ZERO) as Vector2)
	return Vector3(pos.x, float(loc_level.get(id, height_at(cell_of(pos)))) * STEP, pos.y)


## The footprint of a location in cells (inclusive-exclusive Rect2i).
static func footprint(id: String) -> Rect2i:
	if id == "home":
		return _rect_cells(RegionLocations.HOME, HOME_PLOT)
	var d := RegionLocations.get_def(id)
	return _rect_cells(d.get("pos", Vector2.ZERO), d.get("size", Vector2.ONE))


static func _rect_cells(pos: Vector2, size: Vector2) -> Rect2i:
	var lo := Vector2i(int(floor(pos.x - size.x * 0.5)), int(floor(pos.y - size.y * 0.5)))
	var hi := Vector2i(int(ceil(pos.x + size.x * 0.5)), int(ceil(pos.y + size.y * 0.5)))
	return Rect2i(lo, hi - lo)


## Road path from the house to a location (region cell centres), or [] if none.
func route_from_home(id: String) -> PackedVector2Array:
	if _road_astar == null:
		_build_road_astar()
	var from := _road_access("home")
	var to := _road_access(id)
	if from.x < 0 or to.x < 0:
		return PackedVector2Array()
	var pts := _road_astar.get_id_path(from, to)
	var out := PackedVector2Array()
	out.append(RegionLocations.HOME)
	for p in pts:
		out.append(Vector2(p) + Vector2(0.5, 0.5))
	if id != "home":
		out.append(RegionLocations.get_def(id)["pos"])
	return out


func _build_road_astar() -> void:
	_road_astar = AStarGrid2D.new()
	_road_astar.region = Rect2i(0, 0, W, H)
	_road_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_road_astar.update()
	for y in H:
		for x in W:
			if road[y * W + x] == R_NONE:
				_road_astar.set_point_solid(Vector2i(x, y), true)
	_reach = roads_reachable_from_home()


## The road cell next to a place's footprint (connected to the house) that is
## closest to its centre; (-1, -1) if none.
func _road_access(id: String) -> Vector2i:
	if _road_astar == null:
		_build_road_astar()
	var r := footprint(id)
	var ctr := Vector2(r.position) + Vector2(r.size) * 0.5
	var best := Vector2i(-1, -1)
	var bd := 1e9
	for c in _ring_cells(r):
		if _reach.has(c):
			var d := (Vector2(c) + Vector2(0.5, 0.5)).distance_squared_to(ctr)
			if d < bd:
				bd = d
				best = c
	return best


## True if a road cell next to the place connects to the house.
func connected_to_home(id: String) -> bool:
	return _road_access(id).x >= 0


## Road cells reachable from the house (4-connected flood fill over roads).
func roads_reachable_from_home() -> Dictionary:
	var seen := {}
	var queue: Array[Vector2i] = []
	for c in _ring_cells(footprint("home")):
		if in_bounds(c) and road[idx(c)] != R_NONE:
			seen[c] = true
			queue.append(c)
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if in_bounds(n) and not seen.has(n) and road[idx(n)] != R_NONE:
				seen[n] = true
				queue.append(n)
	return seen


## SHA-256 over every generated array and object (determinism check).
func content_hash() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for a in [height.to_byte_array(), water.to_byte_array(), cover, road, bridge.to_byte_array(), district, waterkind, plot, field]:
		ctx.update(a)
	ctx.update(var_to_bytes([boxes, trees]))
	return ctx.finish().hex_encode()


func counts() -> Dictionary:
	var land := 0
	var wet := 0
	var roads := 0
	for i in W * H:
		if water[i] > 0:
			wet += 1
		else:
			land += 1
		if road[i] != R_NONE:
			roads += 1
	return {"land": land, "water": wet, "road": roads, "boxes": boxes.size(), "trees": trees.size()}


# --- generation: setup and heights --------------------------------------------

func _setup() -> void:
	_rng.seed = SEED
	var n := W * H
	for a in [height, water, bridge]:
		a.resize(n)
		a.fill(0)
	for a in [cover, road, district, waterkind, plot, field]:
		a.resize(n)
		a.fill(0)
	boxes.clear()
	trees.clear()
	_paths.clear()
	loc_level.clear()
	loc_top.clear()
	_road_astar = null
	_reach = {}
	var cfg := [[_n_hills, 0.024, 3, FastNoiseLite.FRACTAL_FBM], [_n_detail, 0.09, 2, FastNoiseLite.FRACTAL_FBM],
		[_n_ridge, 0.045, 4, FastNoiseLite.FRACTAL_RIDGED], [_n_warp, 0.035, 2, FastNoiseLite.FRACTAL_FBM],
		[_n_forest, 0.07, 3, FastNoiseLite.FRACTAL_FBM], [_n_coast, 0.09, 2, FastNoiseLite.FRACTAL_FBM]]
	for k in cfg.size():
		var nz: FastNoiseLite = cfg[k][0]
		nz.seed = SEED + k * 101
		nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		nz.frequency = cfg[k][1]
		nz.fractal_octaves = cfg[k][2]
		nz.fractal_type = cfg[k][3]


func coast_x(y: float) -> float:
	var x: float = COAST[COAST.size() - 1].y
	for k in COAST.size() - 1:
		var a: Vector2 = COAST[k]
		var b: Vector2 = COAST[k + 1]
		if y >= a.x and y <= b.x:
			x = lerpf(a.y, b.y, smoothstep(0.0, 1.0, (y - a.x) / (b.x - a.x)))
			break
	if y < DOCKS_ROWS.x - 2.0 or y > DOCKS_ROWS.y + 2.0:
		x += _n_coast.get_noise_1d(y) * 3.0
	return x


static func _ell(x: float, y: float, cx: float, cy: float, rx: float, ry: float) -> float:
	return sqrt(pow((x - cx) / rx, 2.0) + pow((y - cy) / ry, 2.0))


static func _bump(x: float, y: float, cx: float, cy: float, r: float) -> float:
	var t := 1.0 - (pow(x - cx, 2.0) + pow(y - cy, 2.0)) / (r * r)
	return t * t if t > 0.0 else 0.0


## 1 in the town basin (centre, suburbs, industry, docks), 0 outside.
static func town_mask(x: float, y: float) -> float:
	var e := minf(minf(_ell(x, y, 97, 62, 21, 19), _ell(x, y, 72, 90, 19, 14)), minf(_ell(x, y, 108, 89, 21, 9), _ell(x, y, 123, 70, 9, 19)))
	return 1.0 - smoothstep(0.75, 1.2, e)


static func farm_mask(x: float, y: float) -> float:
	return 1.0 - smoothstep(0.8, 1.25, _ell(x, y, 42, 109, 17, 12))


func _land_height(x: float, y: float) -> float:
	var hills := _n_hills.get_noise_2d(x, y)
	var detail := _n_detail.get_noise_2d(x, y)
	var h := 9.0 + hills * 4.5 + detail * 1.0
	h += (1.0 - smoothstep(16.0, 64.0, y)) * 3.0
	# the north-west mountains
	var dm := Vector2(x, y).distance_to(Vector2(9, 7)) + _n_warp.get_noise_2d(x, y) * 9.0
	var m := 1.0 - smoothstep(8.0, 52.0, dm)
	var ridge := clampf(_n_ridge.get_noise_2d(x, y) * 0.5 + 0.5, 0.0, 1.0)
	h += m * m * (21.0 + ridge * 17.0)
	# the southern hills and the headlands of the bay
	h += _bump(x, y, 18, 94, 21) * 7.0 + _bump(x, y, 4, 116, 16) * 6.0 + _bump(x, y, 30, 74, 13) * 4.0 + _bump(x, y, 48, 120, 10) * 3.0
	h += _bump(x, y, 142, 28, 20) * 4.0 + _bump(x, y, 147, 110, 12) * 3.0 + _bump(x, y, 120, 10, 22) * 3.0
	h = lerpf(h, 7.0 + detail * 0.9 + hills * 0.6, town_mask(x, y))
	h = lerpf(h, 8.0 + hills * 1.4, farm_mask(x, y) * 0.85)
	return h


func _base_heights() -> void:
	for y in H:
		var cy := y + 0.5
		var cx0 := coast_x(cy)
		var docks := cy >= DOCKS_ROWS.x and cy <= DOCKS_ROWS.y
		for x in W:
			var cx := x + 0.5
			var i := y * W + x
			var dc := cx0 - cx
			var hf: float
			if dc <= 0.0:
				hf = SEA - 1.5 - minf(-dc * 0.4, 3.5) + _n_detail.get_noise_2d(cx, cy) * 0.6
				water[i] = SEA
				waterkind[i] = 2
			else:
				var land := _land_height(cx, cy)
				if docks:
					hf = lerpf(SEA + 2.4, land, smoothstep(2.0, 6.0, dc))
				else:
					hf = lerpf(SEA + 1.0, land, smoothstep(1.5, 10.0, dc))
				hf = maxf(hf, SEA + 1.0)
			height[i] = int(round(hf))
			if water[i] > 0:
				height[i] = mini(height[i], SEA - 1)


# --- districts -------------------------------------------------------------------

## The district rule for a cell centre (authored shapes, see docs/experiment-003/map.md).
static func district_rule(x: float, y: float) -> String:
	if x >= 115.0 and y >= 54.0 and y <= 85.0:
		return "docks"
	if _ell(x, y, 97, 62, 18, 17) <= 1.0:
		return "centre"
	if x >= 89.0 and x < 134.0 and y >= 79.0 and y <= 98.0:
		return "industrial"
	if x >= 55.0 and x <= 93.0 and y >= 70.0 and y <= 104.0:
		return "suburbs"
	if Vector2(x, y).distance_to(Vector2(4, 2)) <= 44.0:
		return "mountains"
	if y < 50.0:
		return "forest"
	if x >= 28.0 and x < 58.0 and y > 98.0:
		return "farmland"
	if x < 58.0 and y >= 62.0:
		return "hills"
	return ""


func _districts() -> void:
	for y in H:
		for x in W:
			var i := y * W + x
			if waterkind[i] == 2:
				continue
			district[i] = DISTRICT_IDS.find(district_rule(x + 0.5, y + 0.5))


# --- the river ---------------------------------------------------------------------

func _river_samples() -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := RIVER.size()
	for k in n - 1:
		var p0: Vector2 = RIVER[maxi(k - 1, 0)]
		var p1: Vector2 = RIVER[k]
		var p2: Vector2 = RIVER[k + 1]
		var p3: Vector2 = RIVER[mini(k + 2, n - 1)]
		var steps := int(ceil(p1.distance_to(p2) / 0.25))
		for s in steps:
			var t := float(s) / steps
			var p := 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t)
			out.append(p)
	out.append(RIVER[n - 1])
	# a gentle meander upstream of the town
	for k in out.size():
		var p := out[k]
		if p.x < 72.0:
			var dir := (out[mini(k + 1, out.size() - 1)] - out[maxi(k - 1, 0)]).normalized()
			var amp := 1.4 * smoothstep(20.0, 30.0, p.x) * (1.0 - smoothstep(64.0, 72.0, p.x))
			out[k] = p + Vector2(-dir.y, dir.x) * _n_coast.get_noise_1d(p.x * 2.3 + 40.0) * amp
	return out


static func _river_half_width(p: Vector2) -> float:
	if p.x < 40.0:
		return 0.8
	if p.x < 80.0:
		return lerpf(0.85, 1.05, (p.x - 40.0) / 40.0)
	if p.x < 92.0:
		return 1.15
	if p.x < 122.0:
		return 1.5
	return lerpf(1.6, 2.6, clampf((p.x - 122.0) / 8.0, 0.0, 1.0))


func _carve_river() -> void:
	river_path = _river_samples()
	var n := river_path.size()
	var src := cell_of(river_path[0])
	var source_level := height_at(src) - 1
	# Water level: a concave profile (steep in the mountains, flat in town),
	# never above the ground along the course, never rising downstream.
	river_level.resize(n)
	var prev := source_level
	var total := 0.0
	var arc := PackedFloat32Array([0.0])
	for k in range(1, n):
		total += river_path[k].distance_to(river_path[k - 1])
		arc.append(total)
	for k in n:
		var p := river_path[k]
		var t := arc[k] / total
		var designed := SEA + (source_level - SEA) * pow(1.0 - t, 2.4)
		var lowest := 999
		var hw := _river_half_width(p)
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var c := cell_of(p + Vector2(dx, dy))
				if Vector2(c).distance_to(p - Vector2(0.5, 0.5)) <= hw + 0.6 and waterkind[idx(c)] != 2:
					lowest = mini(lowest, height[idx(c)])
		var drop := 2 if town_mask(p.x, p.y) > 0.5 else 1
		var lv := mini(int(floor(designed)), lowest - drop)
		lv = clampi(mini(lv, prev), SEA, 999)
		river_level[k] = lv
		prev = lv
	# Carve: nearest sample per cell.
	var best_d := PackedFloat32Array()
	best_d.resize(W * H)
	best_d.fill(1e9)
	var best_k := PackedInt32Array()
	best_k.resize(W * H)
	best_k.fill(-1)
	for k in n:
		var p := river_path[k]
		var reach := _river_half_width(p) + (2.0 if town_mask(p.x, p.y) > 0.5 else 5.0)
		for y in range(int(p.y - reach) - 1, int(p.y + reach) + 2):
			for x in range(int(p.x - reach) - 1, int(p.x + reach) + 2):
				if x < 0 or y < 0 or x >= W or y >= H:
					continue
				var d := Vector2(x + 0.5, y + 0.5).distance_to(p)
				var i := y * W + x
				if d < best_d[i]:
					best_d[i] = d
					best_k[i] = k
	for i in W * H:
		var k := best_k[i]
		if k < 0 or waterkind[i] == 2:
			continue
		var p := river_path[k]
		var hw := _river_half_width(p)
		var lv := river_level[k]
		var d := best_d[i]
		if d <= hw:
			water[i] = lv
			waterkind[i] = 1
			height[i] = lv - (2 if d < hw * 0.55 else 1)
		else:
			var town := town_mask(p.x, p.y) > 0.5
			var slope := 3.0 if town else 1.3
			height[i] = mini(height[i], lv + 1 + int(floor((d - hw) * slope)))
	# The tarn at the source.
	for y in range(src.y - 3, src.y + 4):
		for x in range(src.x - 3, src.x + 4):
			var c := Vector2i(x, y)
			if in_bounds(c) and Vector2(c).distance_to(Vector2(src)) <= 2.4:
				var i := idx(c)
				water[i] = source_level
				waterkind[i] = 1
				height[i] = source_level - 2


## Raises dry cells next to water so no water stands above its banks.
func _levees() -> void:
	for y in H:
		for x in W:
			var i := y * W + x
			if water[i] <= 0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var c: Vector2i = Vector2i(x, y) + d
				if not in_bounds(c):
					continue
				var j := idx(c)
				if water[j] <= 0 and height[j] < water[i] + 1:
					height[j] = water[i] + 1


# --- location pads -----------------------------------------------------------------

func _pads() -> void:
	var ids: Array = RegionLocations.ids()
	ids.append("home")
	for id in ids:
		var r := footprint(id)
		var hs := []
		for c in _cells(r):
			if in_bounds(c) and water[idx(c)] == 0:
				hs.append(height[idx(c)])
		hs.sort()
		var level: int = hs[hs.size() / 2] if not hs.is_empty() else SEA + 2
		level = maxi(level, SEA + 2)
		if id == "quarry":
			level = int(hs[hs.size() / 2]) - 4
		loc_level[id] = level
		for c in _cells(r.grow(1)):
			if not in_bounds(c) or water[idx(c)] > 0:
				continue
			var i := idx(c)
			if r.has_point(c):
				plot[i] = 1
				if id == "quarry":
					# a cut terrace: benches step up toward the rim, never filled
					var e := mini(mini(c.x - r.position.x, r.end.x - 1 - c.x), mini(c.y - r.position.y, r.end.y - 1 - c.y))
					height[i] = mini(height[i], level + maxi(0, 3 - e))
					cover[i] = C_QUARRY
				else:
					height[i] = level
			elif id != "quarry":
				height[i] = int(round((height[i] + level) * 0.5))


static func _cells(r: Rect2i) -> Array:
	var out := []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			out.append(Vector2i(x, y))
	return out


## Cells just outside a rectangle (4-adjacent to it).
static func _ring_cells(r: Rect2i) -> Array:
	var out := []
	for x in range(r.position.x, r.end.x):
		out.append(Vector2i(x, r.position.y - 1))
		out.append(Vector2i(x, r.end.y))
	for y in range(r.position.y, r.end.y):
		out.append(Vector2i(r.position.x - 1, y))
		out.append(Vector2i(r.end.x, y))
	return out


# --- roads ---------------------------------------------------------------------------

func _mark_road(c: Vector2i, kind: int) -> void:
	if not in_bounds(c):
		return
	var i := idx(c)
	if waterkind[i] == 2 or plot[i] == 1:
		return
	road[i] = maxi(road[i], kind)


## Marks a polyline (4-connected) and returns its cells in order.
func _raster(points: Array, kind: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var last := Vector2i(-999, -999)
	for k in points.size() - 1:
		var a: Vector2 = points[k]
		var b: Vector2 = points[k + 1]
		var steps := int(ceil(a.distance_to(b) / 0.2))
		for s in steps + 1:
			var c := cell_of(a.lerp(b, float(s) / maxf(steps, 1)))
			if c == last:
				continue
			if last.x > -999 and c.x != last.x and c.y != last.y:
				var mid := Vector2i(c.x, last.y)
				_mark_road(mid, kind)
				out.append(Vector2(mid))
			_mark_road(c, kind)
			out.append(Vector2(c))
			last = c
	return out


func _ring_points() -> Array:
	var r := RING
	var rr := RING_RADIUS
	var pts := []
	var corners := [[r.end.x - rr, r.end.y - rr, 0.0], [r.position.x + rr, r.end.y - rr, 90.0],
		[r.position.x + rr, r.position.y + rr, 180.0], [r.end.x - rr, r.position.y + rr, 270.0]]
	for c in corners:
		for s in 7:
			var a := deg_to_rad(c[2] + s * 15.0)
			pts.append(Vector2(c[0] + cos(a) * rr, c[1] + sin(a) * rr))
	pts.append(pts[0])
	return pts


func _roads() -> void:
	_paths.append(_raster(_ring_points(), R_MAIN))
	_paths.append(_raster(ROUTE_9, R_MAIN))
	# Street blocks: a grid in the centre, long streets in the suburbs.
	for y in H:
		for x in W:
			var i := y * W + x
			if waterkind[i] != 0 or plot[i] != 0:
				continue
			var dist: String = DISTRICT_IDS[district[i]]
			if dist == "centre" and ((x - 76) % 6 == 0 or (y - 44) % 6 == 0):
				road[i] = maxi(road[i], R_STREET)
			elif dist == "suburbs" and (y % 6 == 0 or (x - 2) % 9 == 0):
				road[i] = maxi(road[i], R_STREET)
	# A* from every place to the house, preferring roads, gentle slopes and dry feet.
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, W, H)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.update()
	var base := PackedFloat32Array()
	base.resize(W * H)
	for y in H:
		for x in W:
			var i := y * W + x
			var c := Vector2i(x, y)
			if waterkind[i] == 2:
				astar.set_point_solid(c, true)
				continue
			var slope := 0
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + d
				if in_bounds(n) and water[idx(n)] == 0:
					slope = maxi(slope, absi(height[idx(n)] - height[i]))
			var w := 3.0 + minf(slope * slope * 2.0, 60.0)
			if water[i] > 0:
				w += 26.0
			if plot[i] == 1:
				w += 8.0
			if DISTRICT_IDS[district[i]] == "mountains":
				w += 2.0
			base[i] = w
			astar.set_point_weight_scale(c, 1.0 if road[i] != R_NONE else w)
	var ids: Array = RegionLocations.ids()
	ids.sort_custom(func(a, b): return RegionLocations.distance_km(a) < RegionLocations.distance_km(b))
	var home_cells := _cells(footprint("home"))
	for id in ids:
		var own := _cells(footprint(id))
		for c in own + home_cells:
			if in_bounds(c):
				astar.set_point_weight_scale(c, 1.0)
		var start := cell_of(RegionLocations.get_def(id)["pos"])
		var path := astar.get_id_path(start, cell_of(RegionLocations.HOME))
		var cells := PackedVector2Array()
		for p in path:
			var i := idx(p)
			if (p in own) or (p in home_cells):
				continue
			if road[i] == R_NONE:
				road[i] = R_STREET if town_mask(p.x + 0.5, p.y + 0.5) > 0.5 else R_LANE
			astar.set_point_weight_scale(p, 1.0)
			cells.append(Vector2(p))
		for c in own + home_cells:
			if in_bounds(c):
				astar.set_point_weight_scale(c, base[idx(c)])
		_paths.append(cells)
	_smooth_roads()


## Cut and fill along each road so it climbs at most one step per cell;
## roads over water become bridges.
func _smooth_roads() -> void:
	for path in _paths:
		var prev := -1
		for p in path:
			var c := Vector2i(p)
			var i := idx(c)
			if road[i] == R_NONE:
				continue
			if water[i] > 0:
				var deck := maxi(water[i] + 1, prev)
				bridge[i] = maxi(bridge[i], deck)
				prev = bridge[i]
				continue
			var h := height[i]
			if prev >= 0:
				h = clampi(h, prev - 1, prev + 1)
			height[i] = h
			prev = h
	# Bridges level with their banks.
	for i in W * H:
		if bridge[i] > 0:
			var c := Vector2i(i % W, i / W)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + d
				if in_bounds(n) and road[idx(n)] != R_NONE and water[idx(n)] == 0:
					bridge[i] = maxi(bridge[i], height[idx(n)])


# --- land cover ------------------------------------------------------------------------

func _slope(c: Vector2i) -> int:
	var s := 0
	var h := height[idx(c)]
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = c + d
		if in_bounds(n):
			s = maxi(s, h - height[idx(n)])
	return s


func _near_sea(c: Vector2i, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var n := c + Vector2i(dx, dy)
			if in_bounds(n) and waterkind[idx(n)] == 2:
				return true
	return false


func _land_cover() -> void:
	for y in H:
		for x in W:
			var c := Vector2i(x, y)
			var i := y * W + x
			if water[i] > 0:
				cover[i] = C_BED
				continue
			if cover[i] == C_QUARRY:
				continue
			var h := height[i]
			var dist: String = DISTRICT_IDS[district[i]]
			var fx := x + 0.5
			var fy := y + 0.5
			var fn := _n_forest.get_noise_2d(fx, fy)
			var cv := C_GRASS if _n_detail.get_noise_2d(fx * 1.7, fy * 1.7) > -0.1 else C_MEADOW
			if h >= 39 + int(fn * 3.0):
				cv = C_SNOW
			elif h >= 26 + int(fn * 4.0) or _slope(c) >= 4:
				cv = C_ROCK
			elif h <= SEA + 1 and _near_sea(c, 3):
				cv = C_SAND
			elif dist == "docks":
				cv = C_QUAY
			elif dist == "centre":
				cv = C_PAVED
				if _river_distance(Vector2(fx, fy)) < 3.6:
					cv = C_PARK
			elif dist == "industrial":
				cv = C_YARD if town_mask(fx, fy) > 0.4 else cv
			elif dist == "suburbs":
				cv = C_LAWN
			elif farm_mask(fx, fy) > 0.35 or dist == "farmland":
				cv = C_FIELD
				var fid := Vector2i(int(floor((fx + 3.0) / 7.0)), int(floor((fy + 1.0) / 5.0)))
				field[i] = (fid.x * 7 + fid.y * 13 + fid.x * fid.y) % 4
			else:
				var density := fn + (0.45 if dist == "forest" else 0.0) + (0.3 if dist == "mountains" and h < 25 else 0.0)
				density -= 0.3 * town_mask(fx, fy)
				if dist == "hills":
					density -= 0.1
				if density > 0.32:
					cv = C_FOREST
			cover[i] = cv
	# Experiment 004 (E): the pine woods near home are dense forest
	for c in _cells(footprint("forest").grow(2)):
		if in_bounds(c) and water[idx(c)] == 0 and cover[idx(c)] != C_QUARRY:
			cover[idx(c)] = C_FOREST
	# the logging clearing and the farm yard
	for id in ["logging", "farmhouse", "sawmill", "shooting_range", "military"]:
		for c in _cells(footprint(id).grow(1)):
			if in_bounds(c) and water[idx(c)] == 0:
				cover[idx(c)] = C_DIRT if id != "military" else C_YARD


func _river_distance(p: Vector2) -> float:
	var best := 1e9
	for k in range(0, river_path.size(), 4):
		best = minf(best, river_path[k].distance_squared_to(p))
	return sqrt(best)


# --- buildings ----------------------------------------------------------------------------

func _box(lo: Vector3, hi: Vector3, col: Color, glow := 0.0) -> void:
	boxes.append([lo, hi, col, glow])
	if _box_owner != "":
		loc_top[_box_owner] = maxf(float(loc_top.get(_box_owner, 0.0)), hi.y)


func _gy(c: Vector2i) -> float:
	return height_at(c) * STEP


## A house: walls plus a stepped (voxel) gable roof with its ridge along x
## (along_x) or z. `c` is the footprint centre on the ground (world).
func _house(c: Vector3, w: float, d: float, wall_h: float, wall: Color, roof: Color, along_x: bool) -> void:
	var hw := Vector3(w * 0.5, 0, d * 0.5)
	_box(Vector3(c.x - hw.x, c.y - 0.3, c.z - hw.z), Vector3(c.x + hw.x, c.y + wall_h, c.z + hw.z), wall)
	var span := d if along_x else w
	var layers := 3
	var t := 0.07 + span * 0.05
	for k in layers:
		var f := 1.0 - float(k) / layers
		var ov := 0.05
		var y0 := c.y + wall_h + k * t
		if along_x:
			_box(Vector3(c.x - hw.x - ov, y0, c.z - (hw.z + ov) * f), Vector3(c.x + hw.x + ov, y0 + t, c.z + (hw.z + ov) * f), roof)
		else:
			_box(Vector3(c.x - (hw.x + ov) * f, y0, c.z - hw.z - ov), Vector3(c.x + (hw.x + ov) * f, y0 + t, c.z + hw.z + ov), roof)


## A flat-roofed block with a lighter parapet line on top.
func _block(lo: Vector3, hi: Vector3, col: Color) -> void:
	_box(Vector3(lo.x, lo.y - 0.3, lo.z), hi, col)
	_box(Vector3(lo.x + 0.04, hi.y, lo.z + 0.04), Vector3(hi.x - 0.04, hi.y + 0.04, hi.z - 0.04), col.lightened(0.12))


func _pick(a: Array) -> Color:
	return a[_rng.randi() % a.size()]


func _free(c: Vector2i) -> bool:
	if not in_bounds(c):
		return false
	var i := idx(c)
	return water[i] == 0 and road[i] == R_NONE and plot[i] == 0 and cover[i] != C_PARK


func _buildings() -> void:
	_box_owner = ""
	_city_blocks()
	_suburb_houses()
	_industry()
	_docks()
	_bridges()
	_rural_houses()
	for id in RegionLocations.ids():
		_box_owner = id
		_location(id)
	_box_owner = "home"
	_home()
	_box_owner = ""


func _city_blocks() -> void:
	var sizes := [Vector2i(2, 2), Vector2i(2, 1), Vector2i(1, 2), Vector2i(1, 1)]
	for y in H:
		for x in W:
			var c := Vector2i(x, y)
			if district_at(c) != "centre" or not _free(c):
				continue
			var size := Vector2i(1, 1)
			for s in sizes:
				if _rng.randf() < 0.55:
					var ok := true
					for cc in _cells(Rect2i(c, s)):
						if not _free(cc) or district_at(cc) != "centre":
							ok = false
					if ok:
						size = s
						break
			var lo_y := 999.0
			for cc in _cells(Rect2i(c, size)):
				plot[idx(cc)] = 2
				lo_y = minf(lo_y, _gy(cc))
			var core := 1.0 - clampf(Vector2(x, y).distance_to(CORE) / 19.0, 0.0, 1.0)
			var hgt := snappedf(0.55 + core * core * 4.4 + _rng.randf() * (0.5 + core * 1.2), 0.25)
			var m := 0.1
			var lo := Vector3(x + m, lo_y, y + m)
			var hi := Vector3(x + size.x - m, lo_y + hgt, y + size.y - m)
			var col := _pick(CITY)
			_block(lo, hi, col)
			if hgt > 2.2 and _rng.randf() < 0.7:
				var inset := 0.18 + _rng.randf() * 0.12
				var top := hgt * (0.25 + _rng.randf() * 0.25)
				_block(Vector3(lo.x + inset, hi.y, lo.z + inset), Vector3(hi.x - inset, hi.y + top, hi.z - inset), col.darkened(0.06))
			elif _rng.randf() < 0.5:
				var p := Vector3(lerpf(lo.x, hi.x, 0.3 + _rng.randf() * 0.3), hi.y, lerpf(lo.z, hi.z, 0.3 + _rng.randf() * 0.3))
				_box(p, p + Vector3(0.22, 0.12, 0.18), Color(0.55, 0.56, 0.57))


func _road_dir(c: Vector2i) -> Vector2i:
	for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var n: Vector2i = c + d
		if in_bounds(n) and road[idx(n)] != R_NONE and water[idx(n)] == 0:
			return d
	return Vector2i.ZERO


func _suburb_houses() -> void:
	for y in H:
		for x in W:
			var c := Vector2i(x, y)
			if district_at(c) != "suburbs" or not _free(c):
				continue
			var d := _road_dir(c)
			if d == Vector2i.ZERO:
				continue
			plot[idx(c)] = 2
			var along_x := d.y != 0
			var side := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
			var ctr := Vector3(x + 0.5, _gy(c), y + 0.5) + Vector3(d.x, 0, d.y) * 0.12
			for k in 2:
				if _rng.randf() > 0.8:
					continue
				var w := 0.34 + _rng.randf() * 0.08
				var dd := 0.3 + _rng.randf() * 0.08
				var q := ctr + side * (-0.24 + k * 0.48)
				var hgt := 0.22 + _rng.randf() * 0.1
				if along_x:
					_house(q, w, dd, hgt, _pick(WALLS), _pick(ROOFS), true)
				else:
					_house(q, dd, w, hgt, _pick(WALLS), _pick(ROOFS), false)
			if _rng.randf() < 0.3:
				_car(ctr + Vector3(d.x, 0, d.y) * 0.3, along_x)


func _car(p: Vector3, along_x: bool) -> void:
	var s := Vector3(0.22, 0.08, 0.11) if along_x else Vector3(0.11, 0.08, 0.22)
	var col := _pick(CARS)
	_box(p - Vector3(s.x * 0.5, 0, s.z * 0.5), p + Vector3(s.x * 0.5, s.y, s.z * 0.5), col)
	var t := s * Vector3(0.55, 1, 0.8) if along_x else s * Vector3(0.8, 1, 0.55)
	_box(p - Vector3(t.x * 0.5, -s.y, t.z * 0.5), p + Vector3(t.x * 0.5, s.y + 0.05, t.z * 0.5), col.darkened(0.25))


func _industry() -> void:
	for y in H:
		for x in W:
			var c := Vector2i(x, y)
			if district_at(c) != "industrial" or not _free(c) or town_mask(x + 0.5, y + 0.5) < 0.5:
				continue
			if _rng.randf() > 0.42:
				continue
			var size := Vector2i(1 + _rng.randi() % 3, 1 + _rng.randi() % 2)
			var ok := true
			for cc in _cells(Rect2i(c, size)):
				if not _free(cc) or district_at(cc) != "industrial":
					ok = false
			if not ok:
				size = Vector2i(1, 1)
			var lo_y := 999.0
			for cc in _cells(Rect2i(c, size)):
				plot[idx(cc)] = 2
				lo_y = minf(lo_y, _gy(cc))
			var hgt := 0.45 + _rng.randf() * 0.45
			var col := _pick(SHEDS)
			_block(Vector3(x + 0.08, lo_y, y + 0.12), Vector3(x + size.x - 0.08, lo_y + hgt, y + size.y - 0.12), col)
	# two brick chimneys: landmarks of the river works
	for p in [Vector2(105.5, 90.5), Vector2(118.5, 89.5)]:
		var c := cell_of(p)
		var g := _gy(c)
		_box(Vector3(p.x - 0.18, g - 0.3, p.y - 0.18), Vector3(p.x + 0.18, g + 3.4, p.y + 0.18), Color(0.55, 0.35, 0.28))
		_box(Vector3(p.x - 0.2, g + 3.0, p.y - 0.2), Vector3(p.x + 0.2, g + 3.15, p.y + 0.2), Color(0.78, 0.76, 0.72))
		plot[idx(c)] = 2


func _docks() -> void:
	# cranes and container stacks along the quay
	for y in range(int(DOCKS_ROWS.x) + 2, int(DOCKS_ROWS.y) - 1):
		for x in range(112, W):
			var c := Vector2i(x, y)
			if not _free(c) or district_at(c) != "docks":
				continue
			var e := c + Vector2i(1, 0)
			var quay_edge := in_bounds(e) and waterkind[idx(e)] == 2
			var g := _gy(c)
			if quay_edge and y % 7 == 2:
				_crane(Vector3(x + 0.5, g, y + 0.5))
				plot[idx(c)] = 2
			elif not quay_edge and _rng.randf() < 0.4:
				plot[idx(c)] = 2
				for k in 1 + _rng.randi() % 3:
					var col := _pick(CONTAINERS)
					var z := y + 0.2 + (k % 2) * 0.32
					var lv := k / 2
					_box(Vector3(x + 0.12, g + lv * 0.13, z), Vector3(x + 0.88, g + lv * 0.13 + 0.13, z + 0.28), col)
	# piers and boats in the bay
	for py in [66.5, 74.5]:
		var x0 := coast_x(py)
		var top := SEA * STEP + 0.2
		_box(Vector3(x0 - 0.5, top - 0.1, py - 0.25), Vector3(x0 + 4.5, top, py + 0.25), WOOD)
		for k in 5:
			_box(Vector3(x0 + k - 0.05, SEA * STEP - 1.0, py - 0.3), Vector3(x0 + k + 0.05, top, py - 0.2), WOOD.darkened(0.3))
	for b in [[Vector3(132.6, 0, 67.2), true], [Vector3(133.4, 0, 73.8), true], [Vector3(138, 0, 79), false], [Vector3(141, 0, 61), true]]:
		_boat(b[0], b[1])


func _crane(p: Vector3) -> void:
	for dz in [-0.32, 0.32]:
		_box(Vector3(p.x - 0.36, p.y, p.z + dz - 0.05), Vector3(p.x - 0.26, p.y + 1.7, p.z + dz + 0.05), CRANE)
		_box(Vector3(p.x + 0.26, p.y, p.z + dz - 0.05), Vector3(p.x + 0.36, p.y + 1.7, p.z + dz + 0.05), CRANE)
	_box(Vector3(p.x - 0.5, p.y + 1.7, p.z - 0.4), Vector3(p.x + 0.5, p.y + 2.0, p.z + 0.4), CRANE.darkened(0.1))
	_box(Vector3(p.x - 1.3, p.y + 1.85, p.z - 0.08), Vector3(p.x + 2.6, p.y + 1.98, p.z + 0.08), CRANE)


func _boat(p: Vector3, along_x: bool) -> void:
	var y := SEA * STEP - 0.04
	var s := Vector3(0.9, 0.14, 0.3) if along_x else Vector3(0.3, 0.14, 0.9)
	_box(Vector3(p.x - s.x * 0.5, y, p.z - s.z * 0.5), Vector3(p.x + s.x * 0.5, y + s.y, p.z + s.z * 0.5), Color(0.82, 0.82, 0.8))
	var t := s * 0.45
	_box(Vector3(p.x - t.x * 0.5, y + s.y, p.z - t.z * 0.5), Vector3(p.x + t.x * 0.5, y + s.y + 0.12, p.z + t.z * 0.5), Color(0.36, 0.38, 0.42))


func _bridges() -> void:
	for y in H:
		for x in W:
			var i := y * W + x
			if bridge[i] <= 0:
				continue
			var top := bridge[i] * STEP
			var c := Vector2i(x, y)
			var ew := (in_bounds(c + Vector2i(1, 0)) and road[idx(c + Vector2i(1, 0))] != R_NONE) or (in_bounds(c - Vector2i(1, 0)) and road[idx(c - Vector2i(1, 0))] != R_NONE)
			_box(Vector3(x, top - 0.22, y), Vector3(x + 1, top, y + 1), CONCRETE)
			_box(Vector3(x, top, y), Vector3(x + 1, top + 0.02, y + 1), ASPHALT)
			if ew:
				_box(Vector3(x, top, y - 0.02), Vector3(x + 1, top + 0.1, y + 0.08), CONCRETE.lightened(0.1))
				_box(Vector3(x, top, y + 0.92), Vector3(x + 1, top + 0.1, y + 1.02), CONCRETE.lightened(0.1))
			else:
				_box(Vector3(x - 0.02, top, y), Vector3(x + 0.08, top + 0.1, y + 1), CONCRETE.lightened(0.1))
				_box(Vector3(x + 0.92, top, y), Vector3(x + 1.02, top + 0.1, y + 1), CONCRETE.lightened(0.1))
			if (x + y) % 2 == 0:
				_box(Vector3(x + 0.35, height[i] * STEP, y + 0.35), Vector3(x + 0.65, top - 0.2, y + 0.65), CONCRETE.darkened(0.15))


## A few farms and cottages along the country lanes.
func _rural_houses() -> void:
	for y in range(2, H - 2):
		for x in range(2, W - 2):
			var c := Vector2i(x, y)
			if not _free(c) or road[idx(c)] != R_NONE:
				continue
			var dist := district_at(c)
			if dist in ["centre", "suburbs", "industrial", "docks", "mountains"] or cover[idx(c)] in [C_ROCK, C_SNOW, C_SAND]:
				continue
			var d := _road_dir(c)
			if d == Vector2i.ZERO or road[idx(c + d)] != R_LANE or _rng.randf() > 0.07:
				continue
			plot[idx(c)] = 2
			cover[idx(c)] = C_LAWN
			var ctr := Vector3(x + 0.5, _gy(c), y + 0.5)
			_house(ctr, 0.52, 0.42, 0.32, _pick(WALLS), _pick(ROOFS), d.y != 0)


# --- the places themselves -----------------------------------------------------------------

func _loc_base(id: String) -> float:
	return float(loc_level[id]) * STEP


func _location(id: String) -> void:
	var d := RegionLocations.get_def(id)
	var p: Vector2 = d["pos"]
	var s: Vector2 = d["size"]
	var g := _loc_base(id)
	var lo := Vector3(p.x - s.x * 0.5, g, p.y - s.y * 0.5)
	var hi := Vector3(p.x + s.x * 0.5, g, p.y + s.y * 0.5)
	var ctr := Vector3(p.x, g, p.y)
	match id:
		"homes":
			for k in 5:
				var x := lo.x + 0.7 + k * 1.15
				_house(Vector3(x, g, lo.z + 0.8), 0.6, 0.45, 0.34, _pick(WALLS), _pick(ROOFS), true)
				_house(Vector3(x + 0.3, g, hi.z - 0.8), 0.6, 0.45, 0.34, _pick(WALLS), _pick(ROOFS), true)
		"cul_de_sac":
			_pave(ctr, 1.1, ASPHALT)
			for k in 8:
				var a := TAU * k / 8.0 + 0.2
				var q := ctr + Vector3(cos(a) * 2.2, 0, sin(a) * 1.8)
				_house(q, 0.62, 0.5, 0.36, _pick(WALLS), _pick(ROOFS), absf(sin(a)) > 0.7)
		"trailer_park":
			for row in 3:
				for k in 6:
					var q := Vector3(lo.x + 0.7 + k * 1.05, g, lo.z + 0.8 + row * 1.2)
					_box(q - Vector3(0.38, 0.3, 0.14), q + Vector3(0.38, 0.2, 0.14), [Color(0.84, 0.82, 0.76), Color(0.74, 0.78, 0.8), Color(0.8, 0.74, 0.62)][(row + k) % 3])
		"farmhouse":
			_house(ctr + Vector3(-1.2, 0, -0.6), 0.9, 0.6, 0.38, Color(0.86, 0.84, 0.8), Color(0.3, 0.3, 0.32), true)
			_house(ctr + Vector3(0.9, 0, 0.3), 1.4, 1.0, 0.55, Color(0.56, 0.27, 0.22), Color(0.36, 0.34, 0.33), false)
			for k in 4:
				var r := 0.3 - k * 0.03
				_box(ctr + Vector3(-0.2 - r, -0.3 + k * 0.35, 1.2 - r), ctr + Vector3(-0.2 + r, 0.05 + k * 0.35, 1.2 + r), Color(0.7, 0.7, 0.68))
		"convenience", "drugstore", "gun_shop", "vet_clinic":
			var band: Color = {"convenience": Color(0.4, 0.55, 0.42), "drugstore": Color(0.36, 0.62, 0.55), "gun_shop": Color(0.62, 0.26, 0.22), "vet_clinic": Color(0.5, 0.62, 0.7)}[id]
			var wall := Color(0.36, 0.35, 0.34) if id == "gun_shop" else Color(0.8, 0.78, 0.72)
			_block(ctr - Vector3(0.7, 0, 0.55), ctr + Vector3(0.7, 0.42, 0.55), wall)
			_box(ctr + Vector3(-0.72, 0.26, 0.55), ctr + Vector3(0.72, 0.36, 0.68), band)
		"grocery":
			_block(Vector3(lo.x + 0.3, g, lo.z + 0.3), Vector3(hi.x - 0.3, g + 0.6, lo.z + 2.2), Color(0.76, 0.75, 0.72))
			_box(Vector3(lo.x + 0.3, g + 0.4, lo.z + 2.2), Vector3(hi.x - 0.3, g + 0.5, lo.z + 2.3), Color(0.62, 0.36, 0.26))
			_parking(Rect2(lo.x + 0.3, lo.z + 2.5, s.x - 0.6, s.y - 2.8), g)
		"diner":
			_block(ctr - Vector3(1.1, 0, 0.45), ctr + Vector3(1.1, 0.34, 0.45), Color(0.8, 0.82, 0.82))
			_box(ctr + Vector3(-1.12, 0.16, -0.47), ctr + Vector3(1.12, 0.24, 0.47), Color(0.66, 0.28, 0.24))
			_parking(Rect2(lo.x + 0.2, ctr.z + 0.55, s.x - 0.4, 0.4), g)
		"restaurant":
			_block(ctr - Vector3(0.8, 0, 0.7), ctr + Vector3(0.8, 0.46, 0.7), Color(0.8, 0.84, 0.86))
			_box(ctr + Vector3(0.8, 0.0, -0.7), ctr + Vector3(1.5, 0.06, 0.7), WOOD)
			_box(ctr + Vector3(-0.82, 0.34, -0.72), ctr + Vector3(0.82, 0.4, 0.72), Color(0.32, 0.44, 0.56))
		"fast_food":
			_block(ctr - Vector3(0.65, 0, 0.6), ctr + Vector3(0.65, 0.38, 0.6), Color(0.82, 0.78, 0.68))
			_box(ctr + Vector3(-0.67, 0.38, -0.62), ctr + Vector3(0.67, 0.48, 0.62), Color(0.66, 0.3, 0.22))
			_box(ctr + Vector3(0.75, 0, 0.6), ctr + Vector3(0.82, 1.1, 0.67), Color(0.4, 0.4, 0.4))
			_box(ctr + Vector3(0.62, 1.1, 0.56), ctr + Vector3(0.95, 1.32, 0.71), Color(0.82, 0.64, 0.26))
		"clinic":
			_block(ctr - Vector3(1.2, 0, 0.8), ctr + Vector3(0.6, 0.62, 0.8), Color(0.86, 0.86, 0.84))
			_block(ctr + Vector3(0.6, 0, -0.5), ctr + Vector3(1.3, 0.4, 0.5), Color(0.78, 0.8, 0.8))
		"hospital":
			var white := Color(0.86, 0.86, 0.84)
			_block(Vector3(lo.x + 0.4, g, lo.z + 2.0), Vector3(hi.x - 0.4, g + 2.6, lo.z + 3.6), white)
			_block(Vector3(lo.x + 0.4, g, lo.z + 0.4), Vector3(lo.x + 2.0, g + 1.9, hi.z - 0.4), white.darkened(0.04))
			_block(Vector3(hi.x - 2.0, g, lo.z + 0.4), Vector3(hi.x - 0.4, g + 1.9, hi.z - 0.4), white.darkened(0.04))
			_box(Vector3(lo.x + 2.6, g + 2.64, lo.z + 2.2), Vector3(lo.x + 3.8, g + 2.7, lo.z + 3.4), Color(0.42, 0.46, 0.44))
			_box(Vector3(lo.x + 3.0, g + 2.7, lo.z + 2.75), Vector3(lo.x + 3.4, g + 2.72, lo.z + 2.85), Color(0.9, 0.9, 0.88))
		"hardware":
			_block(Vector3(lo.x + 0.2, g, lo.z + 0.2), Vector3(hi.x - 0.2, g + 0.7, lo.z + 1.9), Color(0.72, 0.56, 0.34))
			_stacks(Rect2(lo.x + 0.3, lo.z + 2.1, s.x - 0.6, 0.7), g, WOOD, 4)
		"logging":
			_stacks(Rect2(lo.x + 0.6, lo.z + 0.6, s.x - 1.2, s.y - 1.6), g, LOGS, 10)
			_house(Vector3(hi.x - 0.8, g, hi.z - 0.7), 0.7, 0.5, 0.3, WOOD, Color(0.3, 0.3, 0.3), true)
			_box(Vector3(lo.x + 0.6, g, hi.z - 1.0), Vector3(lo.x + 1.3, g + 0.26, hi.z - 0.6), Color(0.46, 0.5, 0.36))
		"sawmill":
			_house(Vector3(ctr.x - 0.3, g, ctr.z - 0.6), 3.2, 1.2, 0.62, Color(0.5, 0.4, 0.3), Color(0.36, 0.33, 0.3), true)
			_stacks(Rect2(lo.x + 0.3, ctr.z + 0.4, s.x - 0.8, 1.0), g, LOGS, 5)
		"quarry":
			var floor_y := _loc_base("quarry")
			_block(Vector3(lo.x + 1.4, floor_y, lo.z + 1.6), Vector3(lo.x + 2.3, floor_y + 0.34, lo.z + 2.3), Color(0.82, 0.8, 0.74))
			_box(Vector3(ctr.x + 0.3, floor_y, ctr.z + 0.4), Vector3(ctr.x + 1.0, floor_y + 0.32, ctr.z + 0.9), MACHINE)
			_box(Vector3(ctr.x + 0.5, floor_y + 0.32, ctr.z + 0.5), Vector3(ctr.x + 0.85, floor_y + 0.55, ctr.z + 0.8), MACHINE.darkened(0.2))
			_box(Vector3(ctr.x + 1.0, floor_y + 0.4, ctr.z + 0.6), Vector3(ctr.x + 1.9, floor_y + 0.48, ctr.z + 0.7), MACHINE)
			_stacks(Rect2(ctr.x - 1.6, ctr.z + 1.0, 1.6, 0.8), floor_y, Color(0.74, 0.73, 0.7), 4)
		"construction_site":
			var b0 := Vector3(lo.x + 0.6, g, lo.z + 0.6)
			for k in 3:
				_box(b0 + Vector3(0, 0.55 + k * 0.6, 0), b0 + Vector3(2.4, 0.62 + k * 0.6, 2.2), CONCRETE)
			for q in [Vector3(0, 0, 0), Vector3(2.3, 0, 0), Vector3(0, 0, 2.1), Vector3(2.3, 0, 2.1), Vector3(1.15, 0, 0), Vector3(1.15, 0, 2.1)]:
				_box(b0 + q, b0 + q + Vector3(0.1, 2.3, 0.1), CONCRETE.darkened(0.1))
			var m := Vector3(hi.x - 0.6, g, hi.z - 0.6)
			_box(m - Vector3(0.1, 0.3, 0.1), m + Vector3(0.1, 4.2, 0.1), MACHINE)
			_box(m + Vector3(-3.2, 4.1, -0.07), m + Vector3(1.0, 4.24, 0.07), MACHINE)
			_box(Vector3(lo.x + 0.3, g, hi.z - 0.7), Vector3(lo.x + 1.0, g + 0.2, hi.z - 0.3), Color(0.74, 0.66, 0.5))
		"scrapyard":
			for heap in 3:
				var hc := Vector3(lo.x + 1.3 + heap * 1.8, g, ctr.z + (0.6 if heap % 2 else -0.5))
				for lv in 4:
					var n := 7 - lv * 2
					for k in n:
						var q := hc + Vector3(_rng.randf_range(-1.0, 1.0) * (0.9 - lv * 0.2), lv * 0.14, _rng.randf_range(-1.0, 1.0) * (0.8 - lv * 0.18))
						var col: Color = [RUST, Color(0.45, 0.46, 0.48), Color(0.33, 0.3, 0.28), Color(0.4, 0.46, 0.55), RUST.lightened(0.1)][_rng.randi() % 5]
						_box(q - Vector3(0.18, 0, 0.14), q + Vector3(0.18, 0.16, 0.14), col)
			_fence(Rect2(lo.x, lo.z, s.x, s.y), g, Color(0.36, 0.36, 0.36))
		"warehouse":
			_block(Vector3(lo.x + 0.3, g, lo.z + 0.3), Vector3(hi.x - 0.3, g + 0.9, lo.z + 1.8), Color(0.55, 0.6, 0.64))
			_block(Vector3(lo.x + 0.3, g, lo.z + 2.2), Vector3(hi.x - 1.4, g + 0.8, hi.z - 0.3), Color(0.62, 0.62, 0.6))
		"shooting_range":
			_block(Vector3(lo.x + 0.2, g, lo.z + 0.2), Vector3(hi.x - 0.2, g + 0.4, lo.z + 1.1), Color(0.74, 0.7, 0.6))
			for k in 3:
				_box(Vector3(lo.x + 0.2, g, lo.z + 1.5 + k * 0.5), Vector3(hi.x - 0.2, g + 0.2, lo.z + 1.7 + k * 0.5), Color(0.46, 0.4, 0.3))
		"police":
			_block(Vector3(lo.x + 0.2, g, lo.z + 0.2), Vector3(hi.x - 0.2, g + 0.95, lo.z + 1.8), Color(0.5, 0.56, 0.64))
			_box(Vector3(lo.x + 0.2, g + 0.75, lo.z + 1.8), Vector3(hi.x - 0.2, g + 0.82, lo.z + 1.86), Color(0.86, 0.86, 0.84))
			_box(Vector3(hi.x - 0.6, g + 0.95, lo.z + 0.5), Vector3(hi.x - 0.52, g + 2.0, lo.z + 0.58), Color(0.6, 0.6, 0.6))
			for k in 3:
				_car(Vector3(lo.x + 0.6 + k * 0.5, g, hi.z - 0.5), false)
		"library":      # Exp 006 (R): a stone library with a columned porch
			var lib := Color(0.78, 0.74, 0.66)
			_block(Vector3(lo.x + 0.3, g, lo.z + 0.3), Vector3(hi.x - 0.3, g + 0.75, hi.z - 0.9), lib)
			_box(Vector3(lo.x + 0.2, g + 0.75, lo.z + 0.2), Vector3(hi.x - 0.2, g + 0.85, hi.z - 0.8), lib.darkened(0.25))
			for k in 5:
				var q := Vector3(lo.x + 0.6 + k * (s.x - 1.2) / 4.0, g, hi.z - 0.6)
				_box(q - Vector3(0.06, 0, 0.06), q + Vector3(0.06, 0.6, 0.06), lib.lightened(0.12))
			_box(Vector3(lo.x + 0.45, g + 0.6, hi.z - 0.85), Vector3(hi.x - 0.45, g + 0.68, hi.z - 0.42), lib)
		"military":
			_fence(Rect2(lo.x, lo.z, s.x, s.y), g, Color(0.4, 0.42, 0.36))
			for k in 3:
				_block(Vector3(lo.x + 0.6, g, lo.z + 0.7 + k * 1.3), Vector3(lo.x + 3.4, g + 0.42, lo.z + 1.5 + k * 1.3), OLIVE)
			_box(Vector3(hi.x - 3.2, g, hi.z - 3.0), Vector3(hi.x - 0.8, g + 0.03, hi.z - 0.6), Color(0.36, 0.38, 0.36))
			for q in [Vector3(lo.x + 0.4, g, lo.z + 0.4), Vector3(hi.x - 0.4, g, lo.z + 0.4)]:
				for dx in [-0.2, 0.2]:
					for dz in [-0.2, 0.2]:
						_box(q + Vector3(dx - 0.03, 0, dz - 0.03), q + Vector3(dx + 0.03, 1.2, dz + 0.03), WOOD.darkened(0.2))
				_box(q + Vector3(-0.28, 1.2, -0.28), q + Vector3(0.28, 1.5, 0.28), OLIVE.darkened(0.1))
			for k in 2:
				var q := Vector3(hi.x - 2.6 + k * 1.0, g, lo.z + 1.0)
				_box(q, q + Vector3(0.36, 0.2, 0.7), OLIVE)
				_box(q + Vector3(0.0, 0.2, 0.0), q + Vector3(0.36, 0.34, 0.26), OLIVE.darkened(0.15))
			_box(Vector3(lo.x + 3.8, g, lo.z + 0.6), Vector3(lo.x + 4.0, g + 0.16, lo.z + 3.0), KHAKI)


func _pave(c: Vector3, r: float, col: Color) -> void:
	_box(c - Vector3(r, 0.01, r), c + Vector3(r, 0.02, r), col)


func _parking(r: Rect2, g: float) -> void:
	_box(Vector3(r.position.x, g - 0.01, r.position.y), Vector3(r.end.x, g + 0.02, r.end.y), ASPHALT)
	var n := int(r.size.x / 0.34)
	for k in n:
		if _rng.randf() < 0.45:
			_car(Vector3(r.position.x + 0.17 + k * 0.34, g + 0.02, r.position.y + r.size.y * 0.5), false)


func _stacks(r: Rect2, g: float, col: Color, n: int) -> void:
	for k in n:
		var q := Vector3(r.position.x + _rng.randf() * r.size.x, g, r.position.y + _rng.randf() * r.size.y)
		var along_x := _rng.randf() < 0.5
		var s := Vector3(0.6, 0.1, 0.22) if along_x else Vector3(0.22, 0.1, 0.6)
		for lv in 1 + _rng.randi() % 3:
			var sh := s * Vector3(1.0 - lv * 0.15, 1, 1.0 - lv * 0.15)
			_box(q + Vector3(-sh.x * 0.5, lv * 0.1, -sh.z * 0.5), q + Vector3(sh.x * 0.5, lv * 0.1 + 0.1, sh.z * 0.5), col.darkened(lv * 0.06))


func _fence(r: Rect2, g: float, col: Color) -> void:
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
	for k in 4:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var n := int(ceil(a.distance_to(b) / 0.5))
		for s in n:
			var q := a.lerp(b, float(s) / n)
			_box(Vector3(q.x - 0.03, g, q.y - 0.03), Vector3(q.x + 0.03, g + 0.28, q.y + 0.03), col)
		var lo2 := Vector2(minf(a.x, b.x), minf(a.y, b.y))
		var hi2 := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
		_box(Vector3(lo2.x - 0.015, g + 0.22, lo2.y - 0.015), Vector3(hi2.x + 0.015, g + 0.25, hi2.y + 0.015), col)


func _home() -> void:
	var p := RegionLocations.HOME
	var g := _loc_base("home")
	var c := Vector3(p.x, g, p.y)
	var slate := Color(0.27, 0.3, 0.34)
	_house(c, 0.9, 0.6, 0.4, slate, Color(0.18, 0.19, 0.21), true)
	_box(c + Vector3(-0.15, 0.0, 0.3), c + Vector3(0.15, 0.04, 0.48), WOOD)
	# warm windows (emissive)
	for x in [-0.3, 0.22]:
		_box(c + Vector3(x - 0.08, 0.16, 0.3), c + Vector3(x + 0.08, 0.28, 0.315), WARM, 1.0)
	_box(c + Vector3(0.45, 0.16, -0.1), c + Vector3(0.455, 0.28, 0.1), WARM, 1.0)
	# the lot's fence
	_fence(Rect2(p.x - 1.4, p.y - 1.4, 2.8, 2.8), g, Color(0.42, 0.36, 0.3))
	home_light = c + Vector3(0.0, 0.5, 0.55)
	for cc in _cells(footprint("home")):
		cover[idx(cc)] = C_LAWN


# --- trees ----------------------------------------------------------------------------------

func _tree(pos: Vector3, variant: int, s: float, tint: Color) -> void:
	trees.append([pos, variant, s, tint, _rng.randi() % 4])


func _trees() -> void:
	for y in H:
		for x in W:
			var c := Vector2i(x, y)
			var i := y * W + x
			if water[i] > 0 or road[i] != R_NONE or plot[i] != 0:
				continue
			var cv := cover[i]
			var g := height[i] * STEP
			var fx := x + 0.5
			var fy := y + 0.5
			var dist: String = DISTRICT_IDS[district[i]]
			var n := 0
			var chance := 0.0
			match cv:
				C_FOREST:
					n = 1 + (1 if _rng.randf() < 0.3 else 0)
				C_LAWN:
					chance = 0.32
				C_PARK:
					chance = 0.55
				C_GRASS, C_MEADOW:
					chance = 0.05 if dist != "hills" else 0.09
					if _river_distance(Vector2(fx, fy)) < 2.8:
						chance = 0.3
				C_FIELD:
					var fe := (int(floor(fx + 3.0)) % 7 == 0) or (int(floor(fy + 1.0)) % 5 == 0)
					chance = 0.3 if fe else 0.0
				C_ROCK:
					chance = 0.08 if height[i] < 26 else 0.0
			if chance > 0.0 and _rng.randf() < chance:
				n = 1
			for k in n:
				var q := Vector3(x + 0.2 + _rng.randf() * 0.6, g, y + 0.2 + _rng.randf() * 0.6)
				var conifer := cv == C_ROCK or height[i] >= 15 or (cv == C_FOREST and _n_warp.get_noise_2d(fx * 2.0, fy * 2.0) > -0.05 - (40.0 - fy) * 0.01)
				conifer = conifer or (cv == C_FOREST and footprint("forest").grow(2).has_point(c))   # Experiment 004: pines
				if conifer:
					_tree(q, 0 if _rng.randf() < 0.6 else 1, 0.8 + _rng.randf() * 0.45, PINE[_rng.randi() % PINE.size()])
				else:
					_tree(q, 2 if _rng.randf() < 0.7 else 3, 0.75 + _rng.randf() * 0.45, LEAF[_rng.randi() % LEAF.size()])
	# a few dead trees near the house, like the ones in the yard
	for k in 3:
		var a := 1.0 + k * 2.1
		var q := RegionLocations.HOME + Vector2(cos(a), sin(a)) * 2.1
		var cc := cell_of(q)
		if road[idx(cc)] == R_NONE and water[idx(cc)] == 0:
			_tree(Vector3(q.x, height_at(cc) * STEP, q.y), 4, 0.9, Color(0.46, 0.4, 0.36))
