class_name PoiWorld
extends HouseWorld
## Experiment 007 (P): a playable destination, as its own HouseWorld (the
## pattern of LevelWorld): voxel walls and floors on the same lot-sized grid,
## so shooting, wall damage, enemy bashing, navigation and the cutaway work
## unchanged; PropKit meshes with collision for furniture, shelves, trees, the
## car and fallen logs; doors are WorldObjects (PoiDoor: locked ones need a
## crowbar). Nothing of the house's plan is used: no HousePlan fixtures, yard,
## roof, furniture states, fuse box, bed, support or defences.
##
## Built from PoiDefs.get_def(id)["layout"] (PoiLayouts); Exp 008 (H): its
## optional lights and story details through PoiDressing. The searchable
## containers, loose pickups, fallen trees, exits and the car's boot are PoiSpot
## interactables (interactables() lists them with the doors); the game's POI
## helper (`helper`, game_poi.gd) owns their rules and the visit's state
## (`record`, PoiState). The pristine design is cached per POI; saves are a
## small door list (everything else lives in the run's RegionState).
## API for the game (SPEC §2): entry_point(), exit_points(),
## encounter_plan(danger, seed), rooms(), spots_of(kind), set_reveal(on).

const POI_SAVE_VERSION := 1
const POI_LAYOUT := "swq-poi-1"
const GROUND_ORIGIN := Vector2(-15.0, -13.0)
const GROUND_SIZE := Vector2(44.0, 36.0)
const GROUND_PX := 0.2
const BRICK := [0x8a4a3a, 0x93503f, 0x7d4234, 0x9a5a46, 0x86493a, 0x7a4636]
const POI_MORTAR := 0xa49c8c
const SIDING_TONE := 0x8d8a80
const PLANK_TONES := [0x6e5640, 0x7a5c40, 0x5e4a36, 0x85694c]
const LINTEL_TONE := 0x6a645a
const SNOW := 0xe3e8ee
const SNOW_SHADE := 0xc2cdda
const PICKUP_COLORS := {"food": Color(0.72, 0.22, 0.16), "water": Color(0.45, 0.65, 0.85), "ammo": Color(0.72, 0.6, 0.25),
	"medical": Color(0.92, 0.92, 0.9), "material": Color(0.55, 0.42, 0.3), "book": Color(0.42, 0.26, 0.2)}

static var _pristine_poi := {}
static var _ground_tex := {}

var poi_id := ""
var def := {}
var layout := {}
var state: GameState            ## the run (prompts read the gear)
var record := {}                ## PoiState record (live; the helper sets it)
var helper: Node                ## the game's POI helper (game.poi)
var has_car := false
var spots: Array = []           ## PoiSpot
var ground: MeshInstance3D
var _reveal: Node3D
var _box_props := {}            ## Exp 008 (L): container id -> its props entry (container_cut)


## Call before adding to the tree.
func configure(id: String, light: VoxelLighting, car := false) -> void:
	poi_id = id
	def = PoiDefs.get_def(id)
	layout = def.get("layout", {})
	lighting = light
	has_car = car
	name = "World"


func layout_id() -> String:
	return "%s|%s" % [POI_LAYOUT, poi_id]


## The POI as first built (cached; copied per build).
static func poi_pristine(id: String) -> VoxelGrid:
	if not _pristine_poi.has(id):
		var g := VoxelHouse.create_grid(true)
		var L: Dictionary = PoiDefs.get_def(id).get("layout", {})
		_stamp_floors(g, L.get("floors", []))
		for w in L.get("walls", []):
			_stamp_poi_wall(g, w)
		_pristine_poi[id] = g
	return _pristine_poi[id]


func build_new() -> void:
	var job := begin_build()
	while not job.step():
		pass


## Exp 009 (R): build_new in small steps (the same calls in the same order,
## the same result), for the loading screen: `job.step()` does one and
## returns true when the place is built; `job.stage` ("interior",
## "furniture", "containers") and `job.progress` (0..1, weighted) say how far.
## The voxel design is stamped wall by wall (unless cached) and the chunks
## are meshed one per step. Call it with the world configured and in the tree.
func begin_build() -> BuildJob:
	return BuildJob.new(self)


## The doors of the layout as world objects (build_new).
func _layout_doors() -> Array:
	var objs := []
	for d in layout.get("doors", []):
		var mat := str(d.get("mat", "wood"))        # Exp 008 (H): a steel door ("metal") keeps its own HP
		objs.append({"kind": "door", "x": d["x"], "y": d["y"], "rot": d["rot"], "hp": WorldObject.DEFS["door"]["hp"] if mat == "wood" else -1,
			"open": d["open"], "built": false, "door_id": d["id"], "locked": d["locked"], "mat": mat})
	return objs


# --- the voxel design --------------------------------------------------------------------

static func _stamp_floors(g: VoxelGrid, floors: Array) -> void:
	var found := VoxelArt.pal(VoxelArt.Slot.FOUNDATION)
	var screed := VoxelArt.pal(VoxelArt.Slot.SCREED)
	for f in floors:
		var r: Rect2 = f["rect"]
		var xr := g.centre_range(0, r.position.x, r.end.x)
		var zr := g.centre_range(2, r.position.y, r.end.y)
		for z in range(zr.x, zr.y):
			for x in range(xr.x, xr.y):
				g.set_voxel(x, VoxelHouse.FOUNDATION_ROW, z, VoxelMat.FOUNDATION, VoxelArt.jitter(found, x, 1, z, 0.04))
				g.set_voxel(x, VoxelHouse.SCREED_ROW, z, VoxelMat.SCREED, VoxelArt.jitter(screed, x, 2, z, 0.05))
				var top := VoxelArt.sample(str(f["art"]), x, z)
				g.set_voxel(x, VoxelHouse.FLOOR_ROW, z, VoxelMat.FLOOR, VoxelArt.scale(top, 0.72), top, VoxelHouse.UP_BIT)


## Two voxels thick (0.2 m) on its line, 2.6 m high, 0.1 m past each end so
## corners close; door and open gaps leave 2.1 m clear under a lintel, window
## gaps get a frame and glass between sill and head. A footing under it.
static func _stamp_poi_wall(g: VoxelGrid, w: Dictionary) -> void:
	var a: Vector2 = w["a"]
	var b: Vector2 = w["b"]
	var horiz := is_equal_approx(a.y, b.y)
	var line := a.y if horiz else a.x
	var lo := minf(a.x, b.x) if horiz else minf(a.y, b.y)
	var hi := maxf(a.x, b.x) if horiz else maxf(a.y, b.y)
	var rect := Rect2(lo - 0.1, line - 0.1, hi - lo + 0.2, 0.2) if horiz else Rect2(line - 0.1, lo - 0.1, 0.2, hi - lo + 0.2)
	var xr := g.centre_range(0, rect.position.x, rect.end.x)
	var zr := g.centre_range(2, rect.position.y, rect.end.y)
	var style := str(w.get("style", "drywall"))
	var paint := int(w.get("paint", 0xcfc8bb))
	var found := VoxelArt.pal(VoxelArt.Slot.FOUNDATION)
	for z in range(zr.x, zr.y):
		for x in range(xr.x, xr.y):
			var p := VoxelHouse.column_plan(g, x, z)
			var along := p.x if horiz else p.y
			var gap := {}
			for gp in w.get("gaps", []):
				if along > float(gp["from"]) and along < float(gp["to"]):
					gap = gp
					break
			for y in range(VoxelHouse.FOUNDATION_ROW, VoxelHouse.BASE_ROW):
				if g.get_mat(x, y, z) == VoxelMat.AIR:
					g.set_voxel(x, y, z, VoxelMat.FOUNDATION, VoxelArt.jitter(found, x, y, z, 0.04))
			var ai := int(floor(along * 10.0 + 0.001))
			for r in VoxelHouse.WALL_ROWS:
				var y := VoxelHouse.BASE_ROW + r
				var h := (float(r) + 0.5) * 0.1
				if not gap.is_empty():
					if gap["kind"] != "window":
						if h < HousePlan.DOOR_HEIGHT:
							continue
						var lt := VoxelArt.jitter(LINTEL_TONE, x, y, z, 0.04)
						g.set_voxel(x, y, z, VoxelMat.TRIM, lt, lt)
						continue
					if h > float(gap["sill"]) and h < float(gap["head"]):
						var edge := along - float(gap["from"]) < 0.1 or float(gap["to"]) - along < 0.1 \
							or h - float(gap["sill"]) < 0.1 or float(gap["head"]) - h < 0.1
						if edge:
							var fc := VoxelArt.pal(VoxelArt.Slot.FRAME)
							g.set_voxel(x, y, z, VoxelMat.FRAME, fc, fc)
						else:
							var gc := VoxelArt.pal(VoxelArt.Slot.GLASS)
							g.set_voxel(x, y, z, VoxelMat.GLASS, gc, gc)
						continue
				_wall_voxel(g, x, y, z, r, ai, style, paint)


static func _wall_voxel(g: VoxelGrid, x: int, y: int, z: int, r: int, ai: int, style: String, paint: int) -> void:
	match style:
		"brick":
			var mortar := r % 3 == 2 or (ai + (r / 3 % 2) * 2) % 4 == 3
			if mortar:
				var mc := VoxelArt.jitter(POI_MORTAR, x, y, z, 0.03)
				g.set_voxel(x, y, z, VoxelMat.MORTAR, mc, mc)
			else:
				var bc := VoxelArt.jitter(BRICK[(ai / 4 + r / 3 * 7) % BRICK.size()], x, y, z, 0.05)
				g.set_voxel(x, y, z, VoxelMat.MASONRY, bc, bc)
		"siding":
			var board := VoxelArt.scale(VoxelArt.jitter(SIDING_TONE, x, r / 2, z, 0.05), 0.88 if r % 2 == 0 else 1.0)
			g.set_voxel(x, y, z, VoxelMat.SIDING, board, board)
		"plank":
			var pc := VoxelArt.scale(VoxelArt.jitter(PLANK_TONES[(r / 3) % PLANK_TONES.size()], x, r / 3, z, 0.06), 0.85 if r % 3 == 0 else 1.0)
			g.set_voxel(x, y, z, VoxelMat.SIDING, pc, pc)
		_:
			var dc := VoxelArt.jitter(paint, x, y, z, 0.02)
			if r < 1:
				dc = VoxelArt.scale(paint, 0.62)        # a dark skirting line
			g.set_voxel(x, y, z, VoxelMat.DRYWALL, dc, dc)


# --- building the scene --------------------------------------------------------------------

func _build_poi(g_design: VoxelGrid, g_cur: VoxelGrid, objs: Array) -> void:
	var job := BuildJob.new(self, g_design, g_cur, objs)
	while not job.step():
		pass


# Exp 009 (R): _build_poi in parts (BuildJob runs them in this order).

func _build_setup(g_design: VoxelGrid, g_cur: VoxelGrid) -> void:
	design = g_design
	grid = g_cur
	surface_mat = _surface_material(grid.origin, grid.vs)
	glass_mat = ShaderMaterial.new()
	glass_mat.shader = GLASS_SHADER
	cut_materials.append(glass_mat)
	if lighting != null:
		lighting.night_materials.append(glass_mat)
		lighting.set_practicals_enabled(false)
	for m in PropMaterials.cut_materials():
		m.set_shader_parameter("grid_origin", grid.origin)
		m.set_shader_parameter("voxel_size", grid.vs)
		if not cut_materials.has(m):
			cut_materials.append(m)
	chunks = VoxelWorld.new()
	chunks.name = "VoxelWorld"
	chunks.setup(grid, surface_mat, glass_mat)
	add_child(chunks)


func _build_structure(objs: Array) -> void:
	nav = GridNav.new()
	_static_solid.resize(nav.size.x * nav.size.y)
	_static_solid.fill(0)
	_house_zone = Rect2()          # walls are found through _struct_zone (cells near the layout's walls)
	for w in layout.get("walls", []):
		var a: Vector2 = w["a"]
		var b: Vector2 = w["b"]
		for c in nav.cells_in_rect(Rect2(a.min(b), (b - a).abs()).grow(0.45)):
			_struct_zone[c] = true
		var horiz := is_equal_approx(a.y, b.y)
		for gp in w.get("gaps", []):
			if gp["kind"] != "window":
				openings.append({"axis": 0 if horiz else 1, "line": int(a.y if horiz else a.x), "from": float(gp["from"]), "to": float(gp["to"]), "orig": true})
	_index_openings()
	fx = VoxelFx.new()
	fx.grid = grid
	fx.debris_scale = 1.0 + 0.45 * (damage_quantum - 1)
	add_child(fx)
	for e in objs:
		var o := _spawn_object(e["kind"], Vector2(e["x"], e["y"]), e["rot"], e.get("built", false), e["hp"], e["open"], e.get("mat", "wood"))
		if o is PoiDoor:
			(o as PoiDoor).door_id = str(e.get("door_id", ""))
			(o as PoiDoor).locked = e.get("locked", false) == true


func _build_navigation() -> void:
	_index_objects()
	_full_nav()


func _build_surroundings() -> void:
	_scar_root = Node3D.new()
	_scar_root.name = "Scars"
	add_child(_scar_root)
	_build_ground()
	_build_bounds()
	if layout.get("outdoor", false):
		_build_fog_pines()


## Exp 009 (R): PoiWorld.build_new / _build_poi in steps (see begin_build).
## Each step is one call of the original sequence: stamping one floor or wall
## of the design (when it isn't cached yet), meshing one chunk, placing the
## pieces, the navigation, the ground, the spots. Stage weights are rough
## shares of a headless build (meshing dominates).
class BuildJob extends RefCounted:
	const WEIGHTS := {"stamp": 0.16, "chunks": 0.56, "furniture": 0.22, "containers": 0.06}
	const STAGE_OF := {"stamp": "interior", "chunks": "interior", "furniture": "furniture", "containers": "containers"}

	var stage := "interior"       ## "interior" | "furniture" | "containers"
	var progress := 0.0           ## 0..1 over the whole build, weighted
	var build_ms := 0.0           ## the build's own time (as stats["build_ms"]: after stamping)
	var stamp_ms := 0.0
	var steps := 0                ## steps taken (tests)
	var w: PoiWorld
	var _design: VoxelGrid
	var _cur: VoxelGrid
	var _objs: Array
	var _parts := ["stamp", "chunks", "furniture", "containers"]
	var _part := -1
	var _queue: Array = []        # Callables of the current part
	var _n := 0
	var _done_w := 0.0
	var _done := false

	func _init(world: PoiWorld, g_design: VoxelGrid = null, g_cur: VoxelGrid = null, objs: Variant = null) -> void:
		w = world
		_design = g_design
		_cur = g_cur
		_objs = objs if objs is Array else w._layout_doors()

	## One step; true when the place is built (further calls do nothing).
	func step() -> bool:
		if _done:
			return true
		while _queue.is_empty():
			if _part >= 0:
				_done_w += WEIGHTS[_parts[_part]]
			_part += 1
			if _part >= _parts.size():
				_finish()
				return true
			stage = STAGE_OF[_parts[_part]]
			_queue = _make(_parts[_part])
			_n = _queue.size()
		var t0 := Time.get_ticks_usec()
		var f: Callable = _queue.pop_front()
		f.call()
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		if _parts[_part] == "stamp":
			stamp_ms += ms
		else:
			build_ms += ms
		steps += 1
		progress = minf(_done_w + WEIGHTS[_parts[_part]] * float(_n - _queue.size()) / float(maxi(_n, 1)), 1.0)
		return false

	func _make(part: String) -> Array:
		var q: Array = []
		match part:
			"stamp":
				if _design == null and PoiWorld._pristine_poi.has(w.poi_id):
					var p: VoxelGrid = PoiWorld._pristine_poi[w.poi_id]
					_design = p.copy()
					_cur = p.copy()
				elif _design == null:
					var g := VoxelHouse.create_grid(true)
					for f in w.layout.get("floors", []):
						for strip in _strips(f):          # a big floor in 1 m strips (the same voxels)
							q.append(func() -> void: PoiWorld._stamp_floors(g, [strip]))
					for wall in w.layout.get("walls", []):
						q.append(func() -> void: PoiWorld._stamp_poi_wall(g, wall))
					q.append(func() -> void:
						PoiWorld._pristine_poi[w.poi_id] = g
						_design = g.copy()
						_cur = g.copy())
			"chunks":
				w._build_setup(_design, _cur)
				for c in w.chunks.chunk_coords():
					q.append(w.chunks.build_chunk.bind(c))
			"furniture":
				q = [w._build_structure.bind(_objs), w._place_pieces, w._build_navigation, w._build_surroundings]
			"containers":
				q = [w._place_spots, w.apply_record]
		return q

	## A floor as strips 1 m deep (centre_range is half-open: they tile it exactly).
	static func _strips(f: Dictionary) -> Array:
		var r: Rect2 = f["rect"]
		var out := []
		var z := r.position.y
		while z < r.end.y - 0.0001:
			var z1 := minf(z + 1.0, r.end.y)
			var part := f.duplicate()
			part["rect"] = Rect2(r.position.x, z, r.size.x, z1 - z)
			out.append(part)
			z = z1
		return out

	func _finish() -> void:
		_done = true
		progress = 1.0
		stage = "containers"
		w.stats["build_ms"] = build_ms


func _spawn_object(kind: String, p: Vector2, rot: int, is_built: bool, hp := -1, is_open := false, mat := "wood") -> WorldObject:
	var o: WorldObject = PoiDoor.new() if kind == "door" else WorldObject.new()
	o.setup(kind, p, rot, self, is_built, mat)
	if hp > 0:
		o.hp = mini(hp, o.max_hp)
	o.open = is_open
	add_child(o)
	objects.append(o)
	return o


## A PropKit mesh on plan rect `r` with box collision (tall ones stop bullets
## and are hidden by the cutaway) and a SOLID navigation mark.
func _piece(type: String, r: Rect2, facing: String, h: float, block: bool, seed: int, node_name: String) -> Node3D:
	var node := _prop(type, r, facing, h, seed)
	node.name = node_name
	add_child(node)
	var tall := h >= Tuning.TALL_THRESHOLD
	var body: StaticBody3D = null
	if block:
		body = _box_body(r, maxf(h, 0.4), 1 if tall else 1 << 4)
		body.set_meta("impact", PROP_IMPACT.get(type, VoxelMat.Impact.WOOD if tall else VoxelMat.Impact.FABRIC))
		body.name = "Body_" + node_name
		add_child(body)
		for c in nav.cells_in_rect(r.grow(-0.05)):
			_static_solid[c.y * nav.size.x + c.x] = 1
	if tall:
		props.append({"node": node, "centre": Vector3(r.get_center().x, h * 0.5, r.get_center().y),
			"half": maxf(r.size.x, r.size.y) * 0.5, "body": body.get_rid() if body != null else RID(), "cut": false})
	return node


func _place_pieces() -> void:
	var k := 0
	for p in layout.get("props", []):
		_piece(p["type"], p["rect"], p["facing"], p["h"], p["block"], 300 + k, "Prop_%d_%s" % [k, p["type"]])
		k += 1
	for c in layout.get("containers", []):
		_piece(c["type"], c["rect"], c["facing"], c["h"], true, hash(c["id"]) & 0xffff, "Box_" + str(c["id"]))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(poi_id)
	var t := 0
	for q in layout.get("trees", []):
		var h := rng.randf_range(4.8, 6.6)
		var node := PropKit.make("pine", Vector3(0.6, h, 0.6), {"seed": 60 + t})
		node.position = Vector3(q.x, 0, q.y)
		node.rotation.y = rng.randf() * TAU
		node.name = "Pine_%d" % t
		add_child(node)
		var r := Rect2(q - Vector2(0.25, 0.25), Vector2(0.5, 0.5))
		var body := _box_body(r, 3.0, 1)
		body.set_meta("impact", VoxelMat.Impact.WOOD)
		add_child(body)
		for c in nav.cells_in_rect(r.grow(0.05)):
			_static_solid[c.y * nav.size.x + c.x] = 1
		props.append({"node": node, "centre": Vector3(q.x, h * 0.55, q.y), "half": 1.3, "body": body.get_rid(), "cut": false})
		t += 1
	for wd in layout.get("wood", []):
		_place_log(wd)
	if has_car and not (layout.get("car", {}) as Dictionary).is_empty():
		var car: Dictionary = layout["car"]
		_piece("car", car["rect"], car["facing"], 1.45, true, 77, "Car")
	PoiDressing.place(self)            # Exp 008 (H): the layout's lights and story details


## Exp 008 (H): collision and a SOLID navigation mark for a piece drawn
## elsewhere (a story piece that stands tall), as _piece gives its own.
func _block(r: Rect2, h: float, node: Node3D) -> void:
	var tall := h >= Tuning.TALL_THRESHOLD
	var body := _box_body(r, maxf(h, 0.4), 1 if tall else 1 << 4)
	body.set_meta("impact", VoxelMat.Impact.WOOD)
	body.name = "Body_" + node.name
	add_child(body)
	for c in nav.cells_in_rect(r.grow(-0.05)):
		_static_solid[c.y * nav.size.x + c.x] = 1
	if tall:
		props.append({"node": node, "centre": Vector3(r.get_center().x, h * 0.5, r.get_center().y),
			"half": maxf(r.size.x, r.size.y) * 0.5, "body": body.get_rid(), "cut": false})


## Exp 008 (H): the POI's own lights burn day and night (HouseWorld drives
## the candles by the night first).
func _process(delta: float) -> void:
	super(delta)
	PoiDressing.update_lights(self, _t)


## A fallen tree lying along `yaw` (collision for bodies, not bullets).
func _place_log(wd: Dictionary) -> void:
	var at: Vector2 = wd["at"]
	var yaw := float(wd["yaw"])
	var length := float(wd["len"])
	var wrap := Node3D.new()
	wrap.name = "Log_" + str(wd["id"])
	wrap.position = Vector3(at.x, 0, at.y)
	wrap.rotation.y = yaw
	add_child(wrap)
	var tree := PropKit.make("dead_tree", Vector3(0.55, length, 0.55), {"seed": hash(wd["id"]) & 0xff})
	tree.rotation.z = PI * 0.5
	tree.position = Vector3(length * 0.5, 0.28, 0)
	wrap.add_child(tree)
	var body := StaticBody3D.new()
	body.collision_layer = 1 << 4
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(length, 0.6, 0.6)
	cs.shape = box
	body.add_child(cs)
	body.position = Vector3(0, 0.3, 0)
	body.set_meta("impact", VoxelMat.Impact.WOOD)
	wrap.add_child(body)
	var dir := Vector2(cos(yaw), -sin(yaw))
	var n := int(ceil(length / 0.2))
	for i in n + 1:
		var q := at + dir * (-length * 0.5 + length * float(i) / float(n))
		for c in nav.cells_in_rect(Rect2(q - Vector2(0.22, 0.22), Vector2(0.44, 0.44))):
			_static_solid[c.y * nav.size.x + c.x] = 1


## Where the player stands to chop a log: beside its middle, on the camera's side.
static func log_stand(wd: Dictionary) -> Vector2:
	var yaw := float(wd["yaw"])
	var side := Vector2(sin(yaw), cos(yaw))
	if side.y < 0.0:
		side = -side
	return (wd["at"] as Vector2) + side * 0.75


func _place_spots() -> void:
	for c in layout.get("containers", []):
		_add_spot("container", c["id"], PoiLayouts.front_point(c["rect"], c["facing"]), c)
	for p in layout.get("pickups", []):
		var s := _add_spot("pickup", p["id"], p["at"], p)
		s.visual = _pickup_mesh(str(p["item"]))
		s.add_child(s.visual)
	for wd in layout.get("wood", []):
		_add_spot("wood", wd["id"], log_stand(wd), wd)
	_place_exit_spots()             # Exp 009 (X): the car, or the departure markers; the dark hallway end
	if has_car and not (layout.get("car", {}) as Dictionary).is_empty():
		_add_spot("cargo", "car", layout["car"]["cargo"], {"label": "car"})


func _add_spot(k: String, id: String, at: Vector2, d: Dictionary) -> PoiSpot:
	var s := PoiSpot.new()
	s.setup(k, id, at, d, self)
	add_child(s)
	spots.append(s)
	return s


func _pickup_mesh(item: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Item"
	var mi := MeshInstance3D.new()
	var cat := Items.category(item)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PICKUP_COLORS.get(cat, Color(0.6, 0.55, 0.45))
	mat.roughness = 0.7
	if cat == "food" or cat == "water":
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.06 if cat == "food" else 0.045
		cyl.bottom_radius = cyl.top_radius
		cyl.height = 0.12 if cat == "food" else 0.26
		mi.mesh = cyl
		mi.position.y = cyl.height * 0.5
	else:
		var bx := BoxMesh.new()
		bx.size = Vector3(0.22, 0.08, 0.15) if cat != "material" else Vector3(0.5, 0.06, 0.2)
		mi.mesh = bx
		mi.position.y = 0.04
	mi.material_override = mat
	root.add_child(mi)
	return root


## A trail post with a flare on top (lit at night too): the way home.
func _exit_marker() -> Node3D:
	var root := Node3D.new()
	root.name = "ExitMarker"
	var post := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.09, 1.2, 0.09)
	post.mesh = pm
	post.position.y = 0.6
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.32, 0.25, 0.19)
	post.material_override = wood
	root.add_child(post)
	var flare := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.12, 0.16, 0.12)
	flare.mesh = fm
	flare.position.y = 1.28
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.45, 0.18)
	flare.material_override = glow
	root.add_child(flare)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.25)
	light.omni_range = 3.2
	light.light_energy = 0.8
	light.position.y = 1.35
	root.add_child(light)
	return root


# --- Exp 009 (X): the ways out ----------------------------------------------------------------

## When Eli drove, the car is the way out: "[E] Leave location" by its door
## (the boot stays its own spot), and no trail posts. On foot: a departure
## marker at each of the layout's exits. An apartment's dark hallway end
## (layout "dark_exit") fades into darkness; the helper asks there.
func _place_exit_spots() -> void:
	var car: Dictionary = layout.get("car", {})
	if has_car and not car.is_empty():
		_add_spot("exit", "car", car_door_point(), {"label": "the car", "via": "car"})
	else:
		var k := 0
		for e in layout.get("exits", []):
			var s := _add_spot("exit", "exit_%d" % k, e, {"label": "the way out", "via": "edge"})
			s.add_child(_departure_marker(e))
			k += 1
	if dark_exit().size != Vector2.ZERO:
		_build_dark_exit()


## Where Eli stands to leave by car: beside the driver's door (the layout's
## "door", else the side the open door hangs on, else the other side), on
## walkable ground inside the lot.
func car_door_point() -> Vector2:
	var car: Dictionary = layout.get("car", {})
	var tries := []
	if car.get("door") is Vector2:
		tries.append(car["door"])
	tries.append(PoiExterior.car_points(car["rect"], str(car.get("facing", "E")))["door"])
	tries.append(PoiExterior.car_points(car["rect"], str(car.get("facing", "E")), true)["door"])
	for p in tries:
		if HousePlan.YARD.grow(-0.6).has_point(p) and (nav == null or nav.is_walkable(nav.cell_of(p))):
			return p
	return tries[0]


## A trail post with a flare (lit at night too) and a small board pointing
## out to the nearest edge of the lot: the way out on foot.
func _departure_marker(at: Vector2) -> Node3D:
	var root := _exit_marker()
	var y := HousePlan.YARD
	var gaps := [at.x - y.position.x, y.end.x - at.x, at.y - y.position.y, y.end.y - at.y]
	var dirs := [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]
	var out: Vector2 = dirs[gaps.find(gaps.min())]
	var board := MeshInstance3D.new()
	board.name = "Board"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.14, 0.03)
	board.mesh = bm
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.78, 0.74, 0.62)
	board.material_override = paint
	board.position = Vector3(out.x * 0.22, 0.95, out.y * 0.22)
	board.rotation.y = atan2(-out.y, out.x)
	root.add_child(board)
	return root


func dark_exit() -> Rect2:
	var r: Variant = layout.get("dark_exit")
	return r if r is Rect2 else Rect2()


## The way into the dark (plan, unit): the layout's "dark_dir", else along
## the dark end's long side, away from the building's middle.
func dark_dir() -> Vector2:
	var d: Variant = layout.get("dark_dir")
	if d is Vector2 and (d as Vector2).length() > 0.01:
		return (d as Vector2).normalized()
	var r := dark_exit()
	var b: Variant = layout.get("bounds")
	var mid: Vector2 = (b as Rect2).get_center() if b is Rect2 else building_rect().get_center()
	var to := r.get_center() - mid
	if r.size.x >= r.size.y:
		return Vector2(signf(to.x) if to.x != 0.0 else 1.0, 0)
	return Vector2(0, signf(to.y) if to.y != 0.0 else 1.0)


const DARK_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec2 dir = vec2(1.0, 0.0);
uniform vec2 half_size = vec2(1.0, 1.0);
uniform float top = 1.0;
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	float t = dot(lp.xz, dir) / max(dot(abs(dir), half_size), 0.001);
	ALBEDO = vec3(0.0);
	ALPHA = clamp(smoothstep(-1.0, 0.7, t) * top, 0.0, 0.985);
}
"""


## A cheap darkness: stacked flat layers over the hallway end, each clear at
## the lit side and black toward the far end (denser near the floor), so it
## reads as a volume of dark from the game camera (no collision, no fog).
func _build_dark_exit() -> void:
	var r := dark_exit()
	var dir := dark_dir()
	var sh := Shader.new()
	sh.code = DARK_SHADER
	var layers := [[0.03, 0.97], [0.7, 0.5], [1.4, 0.45], [2.1, 0.4]]
	for i in layers.size():
		var mi := MeshInstance3D.new()
		mi.name = "Dark" if i == 0 else "Dark%d" % i
		var pm := PlaneMesh.new()
		pm.size = r.size
		mi.mesh = pm
		var m := ShaderMaterial.new()
		m.shader = sh
		m.render_priority = i
		m.set_shader_parameter("dir", dir)
		m.set_shader_parameter("half_size", r.size * 0.5)
		m.set_shader_parameter("top", layers[i][1])
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(r.get_center().x, layers[i][0], r.get_center().y)
		add_child(mi)


## Exp 009 (X): the layout's ground patches (PoiExterior): {rect, art:
## "asphalt" | "paving" | "line"} and trodden paths {pts, r, art: "trodden"}.
func _paint_exterior(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for e in layout.get("paint", []):
		var art := str(e.get("art", ""))
		if e.get("rect") is Rect2:
			var r: Rect2 = e["rect"]
			var i0 := maxi(int((r.position.x - GROUND_ORIGIN.x) / GROUND_PX), 0)
			var i1 := mini(int((r.end.x - GROUND_ORIGIN.x) / GROUND_PX) + 1, w)
			var j0 := maxi(int((r.position.y - GROUND_ORIGIN.y) / GROUND_PX), 0)
			var j1 := mini(int((r.end.y - GROUND_ORIGIN.y) / GROUND_PX) + 1, h)
			for j in range(j0, j1):
				for i in range(i0, i1):
					var p := GROUND_ORIGIN + Vector2(i + 0.5, j + 0.5) * GROUND_PX
					if not r.has_point(p):
						continue
					var c := 0
					var was := img.get_pixel(i, j)
					var cur := (int(was.r8) << 16) | (int(was.g8) << 8) | int(was.b8)
					match art:
						"asphalt":
							c = VoxelArt.mix(VoxelArt.sample("asphalt", i, j), cur, 0.35 + 0.3 * VoxelArt.hash3(i, j, 21))
						"paving":
							c = VoxelArt.mix(VoxelArt.sample("paving", i, j), cur, 0.45)
						"line":
							c = VoxelArt.mix(0xd9d4bf, cur, 0.35 + 0.4 * VoxelArt.hash3(i, j, 22))
						_:
							c = cur
					img.set_pixel(i, j, VoxelArt.to_color(c))
		elif e.get("pts") is Array and art == "trodden":
			var rad := float(e.get("r", 0.55))
			var pts: Array = e["pts"]
			for k in range(pts.size() - 1):
				var a: Vector2 = pts[k]
				var b: Vector2 = pts[k + 1]
				var box := Rect2(a, Vector2.ZERO).expand(b).grow(rad)
				for j in range(maxi(int((box.position.y - GROUND_ORIGIN.y) / GROUND_PX), 0), mini(int((box.end.y - GROUND_ORIGIN.y) / GROUND_PX) + 1, h)):
					for i in range(maxi(int((box.position.x - GROUND_ORIGIN.x) / GROUND_PX), 0), mini(int((box.end.x - GROUND_ORIGIN.x) / GROUND_PX) + 1, w)):
						var p := GROUND_ORIGIN + Vector2(i + 0.5, j + 0.5) * GROUND_PX
						var d := Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p)
						if d > rad or VoxelArt.hash3(i, j, 23) > 1.15 - d / rad:
							continue
						var was := img.get_pixel(i, j)
						img.set_pixel(i, j, was.lerp(Color8(0xaa, 0xb4, 0xc0), 0.35 + 0.2 * VoxelArt.hash3(i, j, 24)))


## The snowy ground (with an asphalt lot and a sidewalk around buildings).
func _build_ground() -> void:
	if not _ground_tex.has(poi_id):
		_ground_tex[poi_id] = ImageTexture.create_from_image(_ground_image())
	ground = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 100)
	ground.mesh = pm
	ground.position = Vector3(7, VoxelYard.GROUND_Y, 4.5)
	var m := ShaderMaterial.new()
	m.shader = load("res://src/voxel/shaders/voxel_ground.gdshader")
	m.set_shader_parameter("ground_tex", _ground_tex[poi_id])
	m.set_shader_parameter("snow", 1.0)
	m.set_shader_parameter("snow_color", VoxelArt.to_color(SNOW))
	m.set_shader_parameter("lawn_tex", AssetResolver.get_texture("voxel/ground", true))
	m.set_shader_parameter("img_origin", GROUND_ORIGIN)
	m.set_shader_parameter("img_size", GROUND_SIZE)
	ground.material_override = m
	ground.name = "Ground"
	add_child(ground)


func building_rect() -> Rect2:
	var out := Rect2()
	var first := true
	for w in layout.get("walls", []):
		var a: Vector2 = w["a"]
		var b: Vector2 = w["b"]
		var r := Rect2(a.min(b), (b - a).abs())
		out = r if first else out.merge(r)
		first = false
	return out


func _ground_image() -> Image:
	var w := int(GROUND_SIZE.x / GROUND_PX)
	var h := int(GROUND_SIZE.y / GROUND_PX)
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	var drift := FastNoiseLite.new()
	drift.seed = 91 + (hash(poi_id) & 0xff)
	drift.frequency = 0.22
	var lot: bool = layout.get("ground", "snow") == "lot" and not layout.get("outdoor", false)
	var house := building_rect()
	var walk := house.grow(1.2)
	var asphalt := Rect2(-30, house.end.y + 1.2, 80, 4.2)
	var trees: Array = layout.get("trees", [])
	for j in h:
		for i in w:
			var p := GROUND_ORIGIN + Vector2(i + 0.5, j + 0.5) * GROUND_PX
			var c := VoxelArt.mix(SNOW, SNOW_SHADE, clampf(drift.get_noise_2d(p.x, p.y) * 0.9 + 0.2, 0.0, 0.6))
			if VoxelArt.hash3(i, j, 5) > 0.985:
				c = 0xf5f8fb
			if lot and asphalt.has_point(p):
				var tr := absf(p.y - asphalt.position.y - 1.4) < 0.3 or absf(p.y - asphalt.position.y - 2.9) < 0.3
				c = VoxelArt.mix(VoxelArt.sample("asphalt", i, j), c, 0.25 if tr else 0.55)
			elif lot and walk.has_point(p) and not house.has_point(p):
				c = VoxelArt.mix(VoxelArt.sample("paving", i, j), c, 0.45)
			img.set_pixel(i, j, VoxelArt.to_color(c))
	# needle litter under the pines (a second pass, only near them)
	for t in trees:
		for j in range(maxi(int((t.y - 1.3 - GROUND_ORIGIN.y) / GROUND_PX), 0), mini(int((t.y + 1.3 - GROUND_ORIGIN.y) / GROUND_PX) + 1, h)):
			for i in range(maxi(int((t.x - 1.3 - GROUND_ORIGIN.x) / GROUND_PX), 0), mini(int((t.x + 1.3 - GROUND_ORIGIN.x) / GROUND_PX) + 1, w)):
				var p := GROUND_ORIGIN + Vector2(i + 0.5, j + 0.5) * GROUND_PX
				var d := p.distance_to(t)
				if d < 1.3 and VoxelArt.hash3(i, j, 12) < (1.0 - d / 1.3) * 0.8:
					img.set_pixel(i, j, VoxelArt.to_color([0x5e5540, 0x4b4636, 0x6e6450, 0x8a8f86][int(VoxelArt.hash3(i, j, 13) * 4.0) % 4]))
	_paint_exterior(img)            # Exp 009 (X): driveways, parking, trodden paths (layout "paint")
	return img


## Invisible walls at the edge of the walkable area (the player's "lot
## boundary" layer; enemies walk through them, in and out of the fog).
func _build_bounds() -> void:
	var b := HousePlan.YARD.grow(-0.3)
	var body := StaticBody3D.new()
	body.name = "Bounds"
	body.collision_layer = 32
	body.collision_mask = 0
	for r in [Rect2(b.position.x - 1, b.position.y - 1, b.size.x + 2, 1), Rect2(b.position.x - 1, b.end.y, b.size.x + 2, 1),
			Rect2(b.position.x - 1, b.position.y, 1, b.size.y), Rect2(b.end.x, b.position.y, 1, b.size.y)]:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(r.size.x, 4.0, r.size.y)
		cs.shape = box
		cs.position = Vector3(r.get_center().x, 2.0, r.get_center().y)
		body.add_child(cs)
	add_child(body)


## Pines further out in the fog (visual only), as the house's yard.
func _build_fog_pines() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5252
	var per := [[], [], []]
	var placed: Array[Vector2] = []
	var area := Rect2(-18, -18, 50, 40)
	var tries := 0
	while placed.size() < 60 and tries < 3000:
		tries += 1
		var q := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		if HousePlan.YARD.grow(0.5).has_point(q) or q.y > 9.0:      # none to the south (between the camera and Eli)
			continue
		var ok := true
		for o in placed:
			if o.distance_to(q) < 2.4:
				ok = false
				break
		if ok:
			placed.append(q)
			per[rng.randi() % 3].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.85, 1.25)), Vector3(q.x, 0.0, q.y)))
	for v in 3:
		var src := PropKit.make("pine", Vector3(0.6, [6.5, 7.5, 5.5][v], 0.6), {"seed": 90 + v})
		var mesh: Mesh = (src.get_node("Mesh") as MeshInstance3D).mesh
		src.free()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = per[v].size()
		for k in per[v].size():
			mm.set_instance_transform(k, per[v][k])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "FogPines%d" % v
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


# --- the visit's state ------------------------------------------------------------------------

## Shows what the record says: taken pickups are gone, forced doors unlocked.
func apply_record() -> void:
	var taken: Dictionary = record.get("taken", {})
	var forced: Dictionary = record.get("forced", {})
	for s in spots:
		if s.kind == "pickup" and s.visual != null:
			s.visual.visible = not taken.has(s.id)
	for o in objects:
		if o is PoiDoor and forced.has((o as PoiDoor).door_id):
			(o as PoiDoor).locked = false
	_update_reveal()


## Exp 008 (L): true while the cutaway hides container `cid`'s piece (its
## marker hides with it; the prompt still works).
func container_cut(cid: String) -> bool:
	if not _box_props.has("~"):
		_box_props["~"] = true
		for p in props:
			var n: Variant = p.get("node")
			if n is Node and is_instance_valid(n) and str((n as Node).name).begins_with("Box_"):
				_box_props[str((n as Node).name).trim_prefix("Box_")] = p
	var e: Variant = _box_props.get(cid)
	return e is Dictionary and bool((e as Dictionary).get("cut", false))


func spots_of(k: String) -> Array:
	return spots.filter(func(s): return s.kind == k)


func spot(k: String, id: String) -> PoiSpot:
	for s in spots:
		if s.kind == k and s.id == id:
			return s
	return null


func door(id: String) -> PoiDoor:
	for o in objects:
		if o is PoiDoor and (o as PoiDoor).door_id == id:
			return o
	return null


## Developer: a label over every container with what it still holds.
func set_reveal(on: bool) -> void:
	if on and _reveal == null:
		_reveal = Node3D.new()
		_reveal.name = "Reveal"
		add_child(_reveal)
	elif not on and _reveal != null:
		_reveal.queue_free()
		_reveal = null
	_update_reveal()


func is_revealed() -> bool:
	return _reveal != null


func _update_reveal() -> void:
	if _reveal == null:
		return
	for c in _reveal.get_children():
		c.queue_free()
	for s in spots_of("container"):
		var box: Dictionary = record.get("c", {}).get(s.id, {})
		var items: Dictionary = box.get("items", {})
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.font_size = 40
		l.pixel_size = 0.006
		l.modulate = Color(1, 0.9, 0.5) if not items.is_empty() else Color(0.7, 0.7, 0.7)
		l.text = "%s\n%s" % [s.label(), FurnitureStorage.contents_text(items)]
		var r: Rect2 = s.data["rect"]
		l.position = Vector3(r.get_center().x, float(s.data["h"]) + 0.5, r.get_center().y)
		_reveal.add_child(l)


# --- the API for the game ------------------------------------------------------------------------

func entry_point() -> Vector2:
	return layout.get("entry", Vector2(7, 11))


func exit_points() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for e in layout.get("exits", []):
		out.append(e)
	return out


func rooms() -> Array:
	return layout.get("rooms", [])


## For agent N's room visibility (Rooms): the floor areas of this place's
## rooms on `storey` (POIs have one storey: the ground).
func room_floor_rects(storey := 0) -> Array:
	var out := []
	if storey != 0:
		return out
	for r in rooms():
		out.append(r["rect"])
	return out


## Who is here this visit: [{kind, at: Vector2, when: s after arrival (0 =
## there already), mode, ...}], from the visit's danger (PoiDefs.danger_of)
## and a seed. Not an arena: a quiet visit (nobody at all) with
## quiet_share(danger), low-danger places more often; else one to five
## (dangerous places), psychos, runners from danger 1.0, brutes from 1.3, no
## bombers. Exp 008 (E) modes (the helper, game_poi.gd, runs them):
##   hidden  already inside, waiting in a room (layout "hide"): an apparently
##           empty building that isn't
##   peek    outside a window looking in (layout "peek": "at", "look"); there
##           from the start when the spot is far from the entry, else it comes
##           to the window later ("spot", "look"; "at" is a fog edge). It may
##           see Eli through the glass and come in by the nearest doorway.
##   enter   comes in from the fog later and walks in by a doorway ("door",
##           from the layout's "doorways"), opening a closed door
##   arrive  comes in from the fog later and roams outside; a loud noise brings
##           it (and every other arrival) sooner, to the doorway nearest the
##           noise and in to look
##   wander  already about
## A layout without "peek" or "doorways" gets hidden, arrive and wander only.
## Exp 009 (P):
##   dormant busy with something at one of the layout's "dormant" spots
##           ({at, behaviour, target, radius}; DormantMind): a psycho, now and
##           then a brute (never a runner), with its own sensitivity
##           (0.5-1.5) and maybe a mumble. DORMANT_SHARE of the occupants
##           when the layout has spots (at most DORMANT_MAX); the quiet share
##           and the count stay as they were. At most one sits within
##           GUARD_RANGE m of a valuable container (the stash, a locked one).
##           A layout without "dormant" spots gets none (and the same plans
##           as before).
func encounter_plan(danger: float, seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out := []
	if rng.randf() < quiet_share(danger):
		return out
	var n := clampi(1 + int(floor(rng.randf() * danger * 1.6)), 1, 5)
	var hide: Array = (layout.get("hide", []) as Array).duplicate()
	var peeks: Array = (layout.get("peek", []) as Array).duplicate()
	var doors: Array = layout.get("doorways", [])
	var edges: Array = layout.get("edges", PoiLayouts.EDGES)
	var dorm := dormant_spots()
	var valuables := valuable_points()
	var guarded := false
	var dormants := 0
	for i in n:
		var r := rng.randf()
		var kind := "psycho"
		if danger >= 1.3 and r < 0.15:
			kind = "brute"
		elif danger >= 1.0 and r < 0.3:
			kind = "runner"
		var m := rng.randf()
		var mode := "hidden" if m < 0.3 else ("peek" if m < 0.45 else ("enter" if m < 0.62 else ("arrive" if m < 0.8 else "wander")))
		if mode == "hidden" and hide.is_empty() or mode == "peek" and peeks.is_empty():
			mode = "wander"
		if mode == "enter" and doors.is_empty():
			mode = "arrive"
		if not dorm.is_empty() and dormants < DORMANT_MAX and rng.randf() < DORMANT_SHARE:
			var k := _pick_dormant(dorm, valuables, guarded, rng)
			if k >= 0:
				var sp: Dictionary = dorm.pop_at(k)
				guarded = guarded or _near_any(sp["at"], valuables)
				dormants += 1
				out.append({"kind": "brute" if kind == "brute" else "psycho", "at": sp["at"], "when": 0.0, "mode": "dormant",
					"dormant": {"behaviour": str(sp.get("behaviour", "sway")), "spot": sp["at"], "target": sp.get("target", Vector2.INF),
						"radius": float(sp.get("radius", 1.2)), "sensitivity": snappedf(rng.randf_range(0.5, 1.5), 0.01),
						"mumble": rng.randf() < 0.55}})
				continue
		var e := {"kind": kind, "at": Vector2.ZERO, "when": 0.0, "mode": mode}
		match mode:
			"hidden":
				e["at"] = hide.pop_at(rng.randi() % hide.size())
			"peek":
				var pk: Dictionary = peeks.pop_at(rng.randi() % peeks.size())
				e["look"] = pk["look"]
				if (pk["at"] as Vector2).distance_to(entry_point()) >= PEEK_FAR:
					e["at"] = pk["at"]
				else:
					e["spot"] = pk["at"]
					e["at"] = nearest_of(edges, pk["at"])
					e["when"] = rng.randf_range(30.0, 120.0)
			"enter":
				var d: Vector2 = doors[rng.randi() % doors.size()]
				e["door"] = d
				e["at"] = nearest_of(edges, d)
				e["when"] = rng.randf_range(45.0, 170.0)
			"arrive":
				e["at"] = edges[rng.randi() % edges.size()]
				e["when"] = rng.randf_range(60.0, 200.0)
			_:
				e["at"] = wander_point(rng, entry_point(), 9.0)
		out.append(e)
	return out


## Exp 009 (P): the share of a visit's occupants who are dormant when the
## layout has spots, at most this many, and the guard rule's range (m).
const DORMANT_SHARE := 0.45
const DORMANT_MAX := 3
const GUARD_RANGE := 2.2


## Exp 009 (P): the layout's valid dormant spots (Dictionaries with a
## finite "at"; agent G's generator provides them).
func dormant_spots() -> Array:
	var out := []
	for d in layout.get("dormant", []):
		if typeof(d) == TYPE_DICTIONARY and d.get("at") is Vector2 and (d["at"] as Vector2).is_finite():
			out.append(d)
	return out


## Exp 009 (P): the middles of the valuable containers (the stash, locked
## ones, the location's locked table).
func valuable_points() -> Array:
	var out := []
	var stash := str(layout.get("stash", ""))
	for c in layout.get("containers", []):
		if typeof(c) != TYPE_DICTIONARY or not (c.get("rect") is Rect2):
			continue
		if c.get("stash", false) == true or (stash != "" and str(c.get("id", "")) == stash) or str(c.get("table", "")) == "locked" \
				or str(c.get("needs", "")) == "crowbar":
			out.append((c["rect"] as Rect2).get_center())
	return out


static func _near_any(p: Vector2, pts: Array) -> bool:
	for q in pts:
		if (q as Vector2).distance_to(p) <= GUARD_RANGE:
			return true
	return false


## A random spot of `spots` (index), skipping those beside a valuable
## container once one dormant already sits by one; -1 if none fits.
static func _pick_dormant(spots: Array, valuables: Array, guarded: bool, rng: RandomNumberGenerator) -> int:
	var start := rng.randi() % spots.size()
	for i in spots.size():
		var k := (start + i) % spots.size()
		if not guarded or not _near_any(spots[k]["at"], valuables):
			return k
	return -1


## Exp 008 (E): the chance a visit is quiet (nobody there and nobody coming):
## about 45 % at danger 0.7 (Pine Woods), a third at 1.05 (the library), a
## fifth at 1.4 (the gun shop), never below 8 %.
static func quiet_share(danger: float) -> float:
	return clampf(0.75 - 0.4 * danger, 0.08, 0.6)


## A peek spot this close to the entry is empty on arrival (its watcher comes later).
const PEEK_FAR := 9.0


## The point of `pts` (Vector2) nearest to p (p itself when there are none).
static func nearest_of(pts: Array, p: Vector2) -> Vector2:
	var best := p
	var best_d := INF
	for q in pts:
		if q is Vector2 and (q as Vector2).distance_to(p) < best_d:
			best_d = (q as Vector2).distance_to(p)
			best = q
	return best


## The middle of the room a doorway leads into (the nearest room within
## 1.5 m of it), else the building's middle: where someone who comes in by
## that doorway heads.
func inside_of(door: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	for r in rooms():
		var rect: Rect2 = r["rect"]
		if not rect.grow(1.5).has_point(door):
			continue
		var d := rect.get_center().distance_to(door)
		if d < best_d:
			best_d = d
			best = rect.get_center()
	if best == Vector2.INF and not layout.get("walls", []).is_empty():
		best = building_rect().get_center()
	return best if best != Vector2.INF else door


## A walkable point in one of the layout's wander areas, at least `away` m
## from `from` when possible (else the farthest one tried).
func wander_point(rng: RandomNumberGenerator, from := Vector2.INF, away := 0.0) -> Vector2:
	var areas: Array = layout.get("wander", [])
	if areas.is_empty():
		areas = [HousePlan.YARD.grow(-2.0)]
	var best := Vector2.ZERO
	var best_d := -1.0
	for t in 40:
		var a: Rect2 = areas[rng.randi() % areas.size()]
		var q := Vector2(rng.randf_range(a.position.x, a.end.x), rng.randf_range(a.position.y, a.end.y))
		if nav != null and not nav.is_walkable(nav.cell_of(q)):
			continue
		if from == Vector2.INF or q.distance_to(from) >= away:
			return q
		if q.distance_to(from) > best_d:
			best = q
			best_d = q.distance_to(from)
	return best


# --- overrides: no house plan here -------------------------------------------------------------------

func interactables() -> Array:
	var out := []
	for o in objects:
		if o.interact_prompt() != "":
			out.append(o)
	out.append_array(spots)
	return out


func bed_position() -> Vector3:
	var e := entry_point()
	return Vector3(e.x, 0, e.y)


func exit_path_exists(_extra := {}) -> bool:
	return true


func furniture_in(_rect: Rect2) -> bool:
	return false


## The POI's containers are not house storage (HouseSupply must not count them).
func containers() -> Array:
	return []


## Storage crates stay the home's (the material caps don't change while away).
func count_objects(kind: String) -> int:
	if kind == "crate" and state != null:
		return state.inventory.storage_crates
	return super(kind)


func repair_all() -> void:
	grid.mat = design.mat.duplicate()
	grid.col = design.col.duplicate()
	grid.pcol = design.pcol.duplicate()
	grid.pmask = design.pmask.duplicate()
	grid.solid_count = design.solid_count
	for o in objects:
		o.restore()
	chunks.mark_dirty(Vector3i.ZERO, Vector3i(grid.sx, grid.sy, grid.sz))
	_full_nav()
	structure_changed.emit()


func save_data() -> Dictionary:
	var doors := []
	for o in objects:
		if o is PoiDoor:
			doors.append({"id": (o as PoiDoor).door_id, "open": o.open, "hp": o.hp})
	return {"version": POI_SAVE_VERSION, "layout": layout_id(), "poi": poi_id, "doors": doors}


## Rebuilds the POI and restores its doors (the rest lives in RegionState).
func load_data(d: Dictionary) -> bool:
	if d.get("layout") != layout_id():
		push_warning("PoiWorld: the save is for another place (%s)" % str(d.get("layout")))
		return false
	build_new()
	var doors: Variant = d.get("doors", [])
	if typeof(doors) == TYPE_ARRAY:
		for e in doors:
			if typeof(e) != TYPE_DICTIONARY:
				continue
			var o := door(str(e.get("id", "")))
			if o == null:
				continue
			if typeof(e.get("hp")) in [TYPE_INT, TYPE_FLOAT]:
				o.set_hp(clampi(int(e["hp"]), 1, o.max_hp))
			if e.get("open", false) == true and not o.open:
				set_door_open(o, true)
	return true
