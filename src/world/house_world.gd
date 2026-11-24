class_name HouseWorld
extends Node3D
## The survival game's house and lot (SPEC §7.3). Owner: V.
##
## Structure is voxels (walls, floors, foundation, trim, windows, rugs) on a
## 0.1 m grid that covers the whole lot; furniture, doors, lights, storage and
## yard props are PropKit meshes. Two grids:
##   design - the intended structure: pristine house + construction - demolition
##   grid   - the current state: design - damage. Repair copies design -> grid.
## Objects (WorldObject: doors, barricades, crates, rain collectors) carry HP,
## collision (SPEC §4) and a navigation mark. Navigation is recomputed per
## region from voxels + furniture + objects, so built or repaired walls close
## it again. Persistence saves both grids as diffs against the pristine house.
## Docs: docs/experiment-002/world.md; Experiment 003 additions (stone walls,
## foundations, iron doors and barricades, the workbench, explode and
## weak_points, section materials, save version 2):
## docs/experiment-003/construction.md.
## Experiment 004 (see house_furniture.gd for the lifecycle): furniture is a
## gameplay object with an intact -> damaged (voxels) -> destroyed (rubble)
## lifecycle (HouseFurniture, `furniture`); bullets damage objects; window
## boards, metal doors, door reinforcement; the fuse box (`fuse_box()`,
## `power_changed`); closing a door nudges the player out of the doorway;
## demolishing original structures and furniture for salvage.
## Refinement 01 (S): nothing is left hanging in the air (settle(): after a
## demolition, blast or bite, voxels without a chain to the ground fall, and
## doors, window boards and the fuse box fall with their wall), and the roof
## and the upper floor need their outer walls (`support`, HouseSupport).

signal structure_changed
signal object_destroyed(kind: String, at: Vector3)
## Experiment 004: the main power switch changed (toggled, destroyed,
## rebuilt, demolished, loaded). Read fuse_box() for the state.
signal power_changed
## Experiment 004: a furniture piece changed state (damaged, destroyed,
## removed, restored). furniture_ok(id) says whether it still works.
signal furniture_changed(id: String)

const SURFACE_SHADER := preload("res://src/voxel/shaders/voxel_surface.gdshader")
const GLASS_SHADER := preload("res://src/voxel/shaders/voxel_glass.gdshader")
const BED_SCRIPT := preload("res://src/world/bed_interactable.gd")

## Version 2 (Experiment 003) adds stone walls, foundations, object
## materials and blast scars; version 1 saves (Experiment 002) still load.
const SAVE_VERSION := 2
const LOADABLE_VERSIONS := [1, 2]
## Bump when the pristine house (HousePlan, VoxelHouse, the grid) changes:
## saves of another layout are refused instead of misapplied.
const LAYOUT := "swq-house-1"
const LOT := Rect2(-4.5, -3.5, 23.0, 16.0)

const WALL_CARVE := 0.23
const PENETRATION := 1.5
const FLOOR_CARVE := 0.13
const FURNITURE_CARVE := 0.17
const BITE_RADIUS := 0.17
const CUT_RADIUS := 2.1
## Carve radius scale when the voxel hit is sheet metal (upgrade): small dents.
const SHEET_CARVE := 0.45
const DOOR_ROWS := 21                  ## a doorway is cut 2.1 m high
const SECTION_ACROSS := 0.2            ## half-width of a 1 m wall section across its line
## Experiment 003: shots and bites into masonry carve this much smaller (and
## barely penetrate); stone walls are three voxels (0.3 m) thick.
const STONE_CARVE := 0.55
const STONE_STRETCH := 1.1
const STONE_BITE := 0.6
const SHEET_BITE := 0.55               ## Experiment 002 used SHEET_CARVE + 0.2 = 0.65
const STONE_HALF := 0.15
const FOUNDATION_HALF := 0.5           ## a foundation tile is 1 m x 1 m centred on its segment
## Wall materials of the 1 m sections: "strength" is the measured resistance
## relative to the original house wall (shots, bites and blasts to breach;
## docs/experiment-003/construction.md); "load" the material's share of the
## coarse support estimate (section_load_hint). Iron plating multiplies both.
const SECTION_MATERIALS := {
	"frame": {"name": "House wall", "strength": 1.0, "load": 1.0},
	"wood": {"name": "Wooden wall", "strength": 0.9, "load": 0.6},
	"stone": {"name": "Stone wall", "strength": 3.0, "load": 2.5},
}
const PLATED_FACTOR := 2.0
const UNFOUNDED_LOAD := 0.5            ## support factor of a wall without a foundation under it
## Blasts: objects within radius x this are damaged; scorch reaches radius x SCORCH_REACH.
const BLAST_OBJECT_REACH := 1.5
const SCORCH_REACH := 1.35
const SCARS_MAX := 24
## Meshing time spent on the blast's own frame (the rest follows over the next frames).
const BLAST_MESH_BUDGET_MS := 30.0
const SOOT := 0x1f1b18
const STONE_TONES := [0x7f7a73, 0x8c867c, 0x746f69, 0x99928a, 0x6b6762, 0x857d70, 0x8a8278]
const MORTAR_TONE := 0xaca493
const PAVING_TONES := [0x8b867e, 0x7e7a74, 0x948f86, 0x87827a, 0x7a756d]
const PAVING_JOINT := 0x57524b
const PLATE_TONES := [0x5d6366, 0x686d70, 0x54595c, 0x6e6c68, 0x60666a]

## Plan facing -> node yaw (front faces -Z before rotation).
const FACING_YAW := {"N": 0.0, "E": -PI * 0.5, "S": PI, "W": PI * 0.5}
const PROP_IMPACT := {
	"fridge": VoxelMat.Impact.METAL, "water_heater": VoxelMat.Impact.METAL, "floor_lamp": VoxelMat.Impact.METAL,
	"car": VoxelMat.Impact.METAL, "mailbox": VoxelMat.Impact.METAL, "streetlight_dead": VoxelMat.Impact.METAL,
	"wardrobe": VoxelMat.Impact.WOOD, "bookshelf": VoxelMat.Impact.WOOD, "shelves": VoxelMat.Impact.WOOD,
	"dead_tree": VoxelMat.Impact.WOOD,
}
const IMPACT_SOUND := {
	VoxelMat.Impact.WOOD: "impact/wood", VoxelMat.Impact.GLASS: "impact/glass", VoxelMat.Impact.METAL: "impact/metal",
	VoxelMat.Impact.PLANT: "impact/wood",
}
## Night lights (no grid power): candles and battery lanterns on furniture.
## Three cast shadows; the others are cheap fill.
const NIGHT_LIGHTS := [
	{"type": "lantern", "pos": Vector3(11.15, 0.92, 2.5), "shadow": true},     # kitchen island
	{"type": "candle", "pos": Vector3(4.55, 0.45, 5.6), "shadow": true},       # coffee table
	{"type": "lantern", "pos": Vector3(12.2, 0.9, 4.42), "shadow": true},      # utility workbench
	{"type": "candle", "pos": Vector3(7.75, 0.75, 5.62), "shadow": false},     # dining table
	{"type": "candle", "pos": Vector3(3.07, 0.55, 0.42), "shadow": false},     # bedside
	{"type": "candle", "pos": Vector3(7.62, 0.85, 1.65), "shadow": false},     # bathroom vanity
]
const LIGHT_KINDS := {
	"candle": {"size": Vector3(0.1, 0.22, 0.1), "flame": 0.24, "energy": 1.15, "range": 4.6, "color": Color(1.0, 0.64, 0.34)},
	"lantern": {"size": Vector3(0.2, 0.34, 0.2), "flame": 0.2, "energy": 1.9, "range": 6.2, "color": Color(1.0, 0.74, 0.46)},
}
## A few shrubs for the hybrid yard (visual only).
const BUSHES := [Vector2(-3.2, -2.4), Vector2(-3.9, 4.0), Vector2(-3.6, 8.6), Vector2(2.0, -2.6), Vector2(9.6, -2.7),
	Vector2(15.6, -2.2), Vector2(17.6, 2.6), Vector2(17.8, 6.4), Vector2(12.6, 11.8), Vector2(-1.6, 11.8)]
const BOARD_COLORS := [0x8a6a4a, 0x7b5d40, 0x96785a, 0x6e5640, 0x857565, 0x7f6a55, 0x5f6b6a, 0x8c4a3a]
## Experiment 004: the pristine house's fuse box, on the inside of the east
## wall of the utility room, south of the back door (front facing west).
const FUSE_BOX_AT := Vector2(13.77, 8.3)
const FUSE_BOX_ROT := 3
## HP a bullet takes from an object it hits (doors, boards, crates, the fuse box).
const SHOT_OBJECT_DAMAGE := 1

## Options, set before build_new() / load_data().
var voxel_furniture := false   ## Version A look: voxel furniture and voxel yard props
var damage_quantum := 2        ## damage resolution in voxels (1 = 0.1 m, 2 = 0.2 m blocks)

static var _pristine_cache := {}

var grid: VoxelGrid            ## current structure
var design: VoxelGrid          ## intended structure
var nav: GridNav
var fx: VoxelFx
var chunks: VoxelWorld
var yard: VoxelYard
var lighting: VoxelLighting
var surface_mat: ShaderMaterial
var glass_mat: ShaderMaterial
var cut_materials: Array[ShaderMaterial] = []
var bed: Node3D
var objects: Array[WorldObject] = []
## 1 m wall sections along integer plan lines, Vector3i(axis, line, start) ->
## {"orig": bool, "design": int, "current": int} (structural voxel counts in
## the section; "current" follows every shot from the carve's removed cells).
## The hook for a later coarse structural-support model: no per-voxel scans.
var sections := {}
var built := {}                ## player-built wall segments (seg -> true)
var upgraded := {}             ## sheathed (iron-plated) sections (seg -> true)
var foundations := {}          ## stone foundation tiles laid by the player (seg -> true)
var scars: Array = []          ## blast scorch marks on the ground: [x, z, radius]
var openings: Array = []       ## door-like gaps: {"axis", "line", "from", "to", "orig"}
var props: Array = []          ## tall meshes the cutaway hides: {"node", "centre", "half", "body", "cut"}
var night_lights: Array = []   ## {"node", "light", "base", "phase", "geos"}
var furniture: HouseFurniture  ## Experiment 004: furniture states (null with voxel_furniture)
var aim_furniture := ""        ## furniture piece whose collider the last aim_ray hit
var stats := {"build_ms": 0.0, "save_ms": 0.0, "load_ms": 0.0, "nav_ms": 0.0, "carve_ms": 0.0}
## Refinement 01 (S): the roof's and upper floor's support zones (created by
## the ground floor's _build; the upper storey shares the ground floor's).
var support: HouseSupport
var settled := 0                ## voxels dropped by settle() (tests)

var _static_solid := PackedByteArray()
var _opening_clip := {}        # nav cell -> Rect2 that clips its footprint (door gaps ignore their jambs)
var _obj_cells := {}           # nav cell -> WorldObject
var _struct_zone := {}         # nav cells near built walls (outside the house)
var _bullet_skip := PackedByteArray()
var _rng := RandomNumberGenerator.new()
var _shots := 0
var _cut_origin := Vector3(0, -100, 0)
var _cut_dir := Vector3.UP
var _cut_radius := CUT_RADIUS
var _cut_on := false
var _hidden_bodies: Array[RID] = []
var _t := 0.0
var _house_zone := HousePlan.FOOTPRINT.grow(0.5)
var _scar_root: Node3D
var _settle_boxes: Array = []  # Refinement 01 (S): [lo, hi] of damage waiting for settle()
var _settling := false


func setup(light: VoxelLighting) -> void:
	lighting = light


func _ready() -> void:
	_rng.seed = 1979
	_bullet_skip.resize(256)
	for i in 256:
		_bullet_skip[i] = 1 if (VoxelMat.FLAGS[i] & VoxelMat.F_PASS) != 0 else 0


## The undamaged house on the lot-sized grid (built once per run, then copied).
static func pristine(furniture := false) -> VoxelGrid:
	if not _pristine_cache.has(furniture):
		var g := VoxelHouse.create_grid(true)
		VoxelHouse.build(g, furniture)
		_pristine_cache[furniture] = g
	return _pristine_cache[furniture]


func layout_id() -> String:
	return "%s|%s|%s" % [LAYOUT, str(VoxelHouse.LOT_SIZE), "voxel-furniture" if voxel_furniture else "mesh-furniture"]


## Fresh, undamaged house with wooden doors closed in the front and back doorways.
func build_new() -> void:
	var p := pristine(voxel_furniture)
	var objs := []
	for o in HousePlan.OPENINGS:
		if o["id"] in ["front_door", "back_door"]:
			var w := HousePlan.wall_by_id(o["wall"])
			var horiz := HousePlan.is_horizontal(w)
			var mid: float = (o["from"] + o["to"]) * 0.5
			var c := Vector2(mid, w["a"].y) if horiz else Vector2(w["a"].x, mid)
			objs.append({"kind": "door", "x": c.x, "y": c.y, "rot": _outward_rot(c, horiz), "hp": WorldObject.DEFS["door"]["hp"], "open": false, "built": false})
	objs.append(_pristine_fuse_box())
	_build(p.copy(), p.copy(), objs, [], [], [], [], [], [])
	power_changed.emit()


static func _pristine_fuse_box() -> Dictionary:
	return {"kind": "fuse_box", "x": FUSE_BOX_AT.x, "y": FUSE_BOX_AT.y, "rot": FUSE_BOX_ROT,
		"hp": WorldObject.DEFS["fuse_box"]["hp"], "open": false, "built": false, "mains_on": true}


# --- persistence ----------------------------------------------------------------------

## Versioned save: both grids as voxel diffs against the pristine house, plus
## objects, built and sheathed sections and cut openings (docs: world.md);
## version 2 adds "stone" (built sections of masonry), "foundations" and
## "scars", and objects carry "mat".
func save_data() -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var p := pristine(voxel_furniture)
	var objs := []
	for o in objects:
		objs.append(o.to_dict())
	var cut := []
	for op in openings:
		if not op["orig"]:
			cut.append([op["axis"], op["line"], op["from"], op["to"]])
	var d := {
		"version": SAVE_VERSION, "layout": layout_id(), "cells": p.mat.size(),
		"design": VoxelDiff.encode(design, p), "current": VoxelDiff.encode(grid, p),
		"objects": objs, "built": _keys(built), "upgraded": _keys(upgraded), "openings": cut,
		"stone": _keys(_stone_sections()), "foundations": _keys(foundations), "scars": scars.duplicate(true),
		# Experiment 004 (optional): furniture states; "exp4" marks a save that
		# already knows the fuse box (older saves get the pristine one)
		"furniture": furniture.save_data() if furniture != null else {}, "exp4": 1,
	}
	if support != null and not support.roof_gone.is_empty():
		d["collapsed"] = support.save_data()   # Refinement 01 (S), optional: zones whose roof came down
	stats["save_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	return d


## Restores a saved house exactly (instead of build_new). Returns false, having
## built nothing, if the data is invalid or from another house layout; the
## caller can then report it and call build_new(). Version 1 saves
## (Experiment 002) load with the version 2 defaults: every built wall wooden,
## no foundations, wooden doors and barricades, no scars.
func load_data(d: Dictionary) -> bool:
	var t0 := Time.get_ticks_usec()
	if typeof(d.get("version")) != TYPE_INT or not (d["version"] in LOADABLE_VERSIONS):
		push_warning("HouseWorld: unsupported world save version %s" % str(d.get("version")))
		return false
	if d.get("layout") != layout_id():
		push_warning("HouseWorld: the save is for another house layout (%s)" % str(d.get("layout")))
		return false
	var p := pristine(voxel_furniture)
	if typeof(d.get("cells")) != TYPE_INT or d["cells"] != p.mat.size():
		push_warning("HouseWorld: the save's voxel grid has another size")
		return false
	var dd := VoxelDiff.decode(d.get("design"), p)
	var dc := VoxelDiff.decode(d.get("current"), p)
	if dd.is_empty() or dc.is_empty():
		push_warning("HouseWorld: damaged voxel data in the save")
		return false
	var objs: Variant = _valid_objects(d.get("objects"))
	var b: Variant = _valid_segs(d.get("built"), 3)
	var u: Variant = _valid_segs(d.get("upgraded"), 3)
	var cut: Variant = _valid_segs(d.get("openings"), 4)
	var v2: bool = d["version"] >= 2
	var st: Variant = _valid_segs(d.get("stone"), 3) if v2 else []
	var fd: Variant = _valid_segs(d.get("foundations"), 3) if v2 else []
	var sc: Variant = _valid_scars(d.get("scars")) if v2 else []
	if objs == null or b == null or u == null or cut == null or st == null or fd == null or sc == null:
		push_warning("HouseWorld: damaged object or section data in the save")
		return false
	var g_design := p.copy()
	VoxelDiff.apply(g_design, dd)
	var g_cur := p.copy()
	VoxelDiff.apply(g_cur, dc)
	if not d.has("exp4"):
		objs.append(_pristine_fuse_box())        # a save from before Experiment 004
	_build(g_design, g_cur, objs, b, u, cut, st, fd, sc)
	if support != null:
		support.load_data(d.get("collapsed", []))     # Refinement 01 (S)
	if furniture != null:
		furniture.load_data(d.get("furniture", {}))
		_update_light_hosts()
	stats["load_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	power_changed.emit()
	return true


static func _keys(dict: Dictionary) -> Array:
	var out := []
	for k in dict:
		out.append([k.x, k.y, k.z])
	return out


static func _valid_segs(v: Variant, n: int) -> Variant:
	if not (v is Array):
		return null
	var out := []
	for e in v:
		if not (e is Array) or e.size() != n:
			return null
		for x in e:
			if typeof(x) != TYPE_INT and typeof(x) != TYPE_FLOAT:
				return null
			if not is_finite(float(x)) or absf(float(x)) > 100.0:
				return null
		if int(e[0]) != 0 and int(e[0]) != 1:
			return null
		out.append(e)
	return out


static func _valid_scars(v: Variant) -> Variant:
	if not (v is Array) or (v as Array).size() > SCARS_MAX:
		return null
	var out := []
	for e in v:
		if not (e is Array) or e.size() != 3:
			return null
		for x in e:
			if (typeof(x) != TYPE_INT and typeof(x) != TYPE_FLOAT) or not is_finite(float(x)):
				return null
		if not HousePlan.YARD.has_point(Vector2(e[0], e[1])) or float(e[2]) <= 0.0 or float(e[2]) > 5.0:
			return null
		out.append([float(e[0]), float(e[1]), float(e[2])])
	return out


static func _valid_objects(v: Variant) -> Variant:
	if not (v is Array):
		return null
	var out := []
	for e in v:
		if not (e is Dictionary):
			return null
		var k: Variant = e.get("kind")
		if not (k is String) or not WorldObject.DEFS.has(k):
			return null
		var mat: Variant = e.get("mat", "wood")
		if not (mat is String) or not WorldObject.has_mat(k, mat):
			return null
		var x: Variant = e.get("x")
		var y: Variant = e.get("y")
		if typeof(x) not in [TYPE_FLOAT, TYPE_INT] or typeof(y) not in [TYPE_FLOAT, TYPE_INT]:
			return null
		if not is_finite(float(x)) or not is_finite(float(y)) or not HousePlan.YARD.has_point(Vector2(x, y)):
			return null
		var r: Variant = e.get("rot")
		var hp: Variant = e.get("hp")
		if typeof(r) != TYPE_INT or r < 0 or r > 3 or typeof(hp) != TYPE_INT or hp < 1 or hp > WorldObject.max_hp_of(k, mat):
			return null
		out.append({"kind": k, "x": float(x), "y": float(y), "rot": r, "hp": hp, "open": e.get("open") == true, "built": e.get("built") == true, "mat": mat,
			"mains_on": e.get("mains_on") != false})
	return out


# --- building the scene ---------------------------------------------------------------

func _build(g_design: VoxelGrid, g_cur: VoxelGrid, objs: Array, built_list: Array, upgraded_list: Array, cut_list: Array,
		stone_list: Array, foundation_list: Array, scar_list: Array) -> void:
	var t0 := Time.get_ticks_usec()
	design = g_design
	grid = g_cur
	surface_mat = _surface_material(grid.origin, grid.vs)
	glass_mat = ShaderMaterial.new()
	glass_mat.shader = GLASS_SHADER
	cut_materials.append(glass_mat)
	if lighting != null:
		lighting.night_materials.append(glass_mat)
		lighting.set_practicals_enabled(false)     # the grid is down
	# Integration: mesh props share the voxel cutaway (same uniforms, same 0.1 m quantisation).
	if not voxel_furniture:
		for m in PropMaterials.cut_materials():
			m.set_shader_parameter("grid_origin", grid.origin)
			m.set_shader_parameter("voxel_size", grid.vs)
			if not cut_materials.has(m):
				cut_materials.append(m)
	chunks = VoxelWorld.new()
	chunks.name = "VoxelWorld"
	chunks.setup(grid, surface_mat, glass_mat)
	add_child(chunks)
	chunks.build_all()
	nav = GridNav.new()
	_static_solid.resize(nav.size.x * nav.size.y)
	_static_solid.fill(0)
	# Experiment 004: mesh furniture is bashable (HouseFurniture.cell_kind);
	# yard props (and Version A voxel furniture) stay SOLID
	for f in (HousePlan.FURNITURE + HousePlan.PROPS if voxel_furniture else HousePlan.PROPS):
		if f["blocks"]:
			for c in nav.cells_in_rect(f["rect"]):
				_static_solid[c.y * nav.size.x + c.x] = 1
	for b in static_blockers:          # Refinement 01: fixed fittings stay solid across rebuilds
		for c in nav.cells_in_rect((b["rect"] as Rect2).grow(-0.05)):
			_static_solid[c.y * nav.size.x + c.x] = 1
	for e in foundation_list:
		foundations[Vector3i(int(e[0]), int(e[1]), int(e[2]))] = true
	yard = VoxelYard.new()
	yard.name = "Yard"
	yard.demo = self
	yard.voxel_props = voxel_furniture
	yard.tuft_avoid = _foundation_rects()
	add_child(yard)
	fx = VoxelFx.new()
	fx.grid = grid
	fx.debris_scale = 1.0 + 0.45 * (damage_quantum - 1)
	add_child(fx)
	_place_furniture()
	_place_night_lights()
	for w in HousePlan.WALLS:
		var horiz := HousePlan.is_horizontal(w)
		var a: Vector2 = w["a"]
		var b: Vector2 = w["b"]
		var lo := int(minf(a.x, b.x)) if horiz else int(minf(a.y, b.y))
		var hi := int(maxf(a.x, b.x)) if horiz else int(maxf(a.y, b.y))
		for s in range(lo, hi):
			sections[Vector3i(0 if horiz else 1, int(a.y) if horiz else int(a.x), s)] = _new_section(true, "frame")
	for o in HousePlan.OPENINGS:
		if o["kind"] == "door":
			var w := HousePlan.wall_by_id(o["wall"])
			var horiz := HousePlan.is_horizontal(w)
			openings.append({"axis": 0 if horiz else 1, "line": int(w["a"].y if horiz else w["a"].x), "from": float(o["from"]), "to": float(o["to"]), "orig": true})
	var stone := {}
	for e in stone_list:
		stone[Vector3i(int(e[0]), int(e[1]), int(e[2]))] = true
	for e in built_list:
		var s := Vector3i(int(e[0]), int(e[1]), int(e[2]))
		built[s] = true
		if not sections.has(s) or sections[s]["orig"]:      # Refinement 01: a wall built where a house wall was knocked out
			sections[s] = _new_section(false, "stone" if stone.has(s) else "wood")
		_mark_struct_zone(s)
	for e in upgraded_list:
		upgraded[Vector3i(int(e[0]), int(e[1]), int(e[2]))] = true
	_hide_covered_bushes()
	for e in cut_list:
		openings.append({"axis": int(e[0]), "line": int(e[1]), "from": float(e[2]), "to": float(e[3]), "orig": false})
	_index_openings()
	for e in objs:
		var o := _spawn_object(e["kind"], Vector2(e["x"], e["y"]), e["rot"], e.get("built", true), e["hp"], e["open"], e.get("mat", "wood"))
		if e.get("mains_on", true) == false:
			o.set_mains(false)
	_index_objects()
	_full_nav()
	for s in sections:
		_count_section(s)
	_scar_root = Node3D.new()
	_scar_root.name = "Scars"
	add_child(_scar_root)
	for e in scar_list:
		_add_scar(e[0], e[1], e[2])
	bed = BED_SCRIPT.new()
	bed.name = "Bed"
	bed.position = bed_position()
	add_child(bed)
	support = HouseSupport.new(self)       # Refinement 01 (S)
	stats["build_ms"] = (Time.get_ticks_usec() - t0) / 1000.0


func _surface_material(origin: Vector3, vs: float, model_space := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SURFACE_SHADER
	m.set_shader_parameter("grid_origin", origin)
	m.set_shader_parameter("voxel_size", vs)
	m.set_shader_parameter("model_space", 1.0 if model_space else 0.0)
	cut_materials.append(m)
	if lighting != null:
		lighting.night_materials.append(m)
	return m


## Used by VoxelYard (duck-typed "demo") and for furniture collision.
func _box_body(rect: Rect2, height: float, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(rect.size.x, height, rect.size.y)
	cs.shape = box
	body.add_child(cs)
	body.position = Vector3(rect.get_center().x, height * 0.5, rect.get_center().y)
	return body


## One PropKit mesh per furniture and yard prop (rugs stay voxel), with box
## collision: tall pieces on layer 1 (they stop bullets), low ones on layer 5.
func _place_furniture() -> void:
	if not voxel_furniture:
		furniture = HouseFurniture.new(self)
		furniture.place_all()
	for f in HousePlan.FURNITURE + HousePlan.PROPS:
		var r: Rect2 = f["rect"]
		var h: float = f["height"]
		var is_yard: bool = f["room"] == "yard"
		if furniture != null and not is_yard:
			continue
		if voxel_furniture:
			if not is_yard and f["blocks"]:
				add_child(_box_body(r, maxf(h, 0.4), 1 << 4))   # as in Version A
			continue
		if f["type"] == "rug":
			continue
		var tall := h >= Tuning.TALL_THRESHOLD
		var node := _prop(f["type"], r, f["facing"], h, hash(f["id"]) & 0xffff)
		node.name = "Prop_" + f["id"]
		add_child(node)
		var body: StaticBody3D = null
		if f["blocks"]:
			body = _box_body(r, maxf(h, 0.4), 1 if tall else 1 << 4)
			body.set_meta("impact", PROP_IMPACT.get(f["type"], VoxelMat.Impact.WOOD if tall else VoxelMat.Impact.FABRIC))
			body.name = "Body_" + f["id"]
			add_child(body)
		if tall:
			props.append({"node": node, "centre": Vector3(r.get_center().x, h * 0.5, r.get_center().y),
				"half": maxf(r.size.x, r.size.y) * 0.5, "body": body.get_rid() if body != null else RID(), "cut": false})
	if not voxel_furniture:
		for k in BUSHES.size():
			var p: Vector2 = BUSHES[k]
			var b := PropKit.make("bush", Vector3(0.9, 0.8, 0.9), {"facing": "N", "seed": 31 + k})
			b.position = Vector3(p.x, 0, p.y)
			b.rotation.y = float(k) * 1.7
			b.name = "Bush_%d" % k
			add_child(b)


## A PropKit mesh for a plan rect, turned to face `facing`. The kit builds it
## facing -Z (facing "N"); a wrapper node carries the yaw.
func _prop(type: String, r: Rect2, facing: String, h: float, seed: int) -> Node3D:
	var ns := facing == "N" or facing == "S"
	var size := Vector3(r.size.x if ns else r.size.y, h, r.size.y if ns else r.size.x)
	var wrap := Node3D.new()
	wrap.position = Vector3(r.get_center().x, 0, r.get_center().y)
	wrap.rotation.y = FACING_YAW.get(facing, 0.0)
	wrap.add_child(PropKit.make(type, size, {"facing": "N", "seed": seed}))
	return wrap


func _place_night_lights() -> void:
	var k := 0
	for l in NIGHT_LIGHTS:
		var kind: Dictionary = LIGHT_KINDS[l["type"]]
		var p: Vector3 = l["pos"]
		var node := PropKit.make(l["type"], kind["size"], {"facing": "N", "seed": 7 + k, "lit": true})
		node.position = p
		node.name = "Light_%s_%d" % [l["type"], k]
		var geos := node.find_children("*", "GeometryInstance3D", true, false)
		for n in geos:
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		var o := OmniLight3D.new()
		o.light_color = kind["color"]
		o.omni_range = kind["range"]
		o.omni_attenuation = 1.5
		o.light_energy = 0.0
		o.light_specular = 0.2
		o.shadow_enabled = l["shadow"]
		o.shadow_bias = 0.08
		o.position = p + Vector3(0, kind["flame"], 0)
		o.visible = false
		o.name = "Glow_%d" % k
		add_child(o)
		night_lights.append({"node": node, "light": o, "base": kind["energy"], "phase": float(k) * 2.31, "geos": geos})
		k += 1
	_update_light_hosts()


## Experiment 004: a candle or lantern standing on a furniture piece that is
## destroyed or removed goes with it.
func _update_light_hosts() -> void:
	if furniture == null:
		return
	for l in night_lights:
		var n: Node3D = l["node"]
		if not is_instance_valid(n):
			continue
		var host := furniture.piece_at(Vector2(n.position.x, n.position.z), 0.02, false)
		var gone := host == "" and furniture.piece_at(Vector2(n.position.x, n.position.z), 0.02, true) != ""
		l["hidden"] = gone
		n.visible = not gone


func night_amount() -> float:
	return lighting.night_amount if lighting != null else 0.0


func _process(delta: float) -> void:
	_t += delta
	process_structure()             # Refinement 01 (S): once per frame, only after changes
	var n := night_amount()
	for l in night_lights:
		var o: OmniLight3D = l["light"]
		var ph: float = l["phase"]
		var f := 1.0 + 0.07 * sin(_t * 9.1 + ph) + 0.05 * sin(_t * 23.7 + ph * 1.7) + 0.03 * sin(_t * 41.0 + ph * 0.3)
		o.light_energy = l["base"] * n * f
		o.visible = n > 0.02 and not l.get("hidden", false)
		var lit := clampf(n * 1.4, 0.0, 1.0) * (0.9 + 0.1 * f)
		for gi in l["geos"]:
			if is_instance_valid(gi):
				(gi as GeometryInstance3D).set_instance_shader_parameter("lit", lit)


# --- view ------------------------------------------------------------------------------

func update_view(player_pos: Vector3, camera: Camera3D, delta: float) -> void:
	_cut_on = true
	_cut_origin = player_pos + Vector3(0, 1.0, 0)
	_cut_dir = (camera.global_position - _cut_origin).normalized()
	var dist := camera.global_position.distance_to(_cut_origin)
	_cut_radius = CUT_RADIUS + (dist - 20.0) * 0.03
	for m in cut_materials:
		m.set_shader_parameter("cut_origin", _cut_origin)
		m.set_shader_parameter("cut_dir", _cut_dir)
		m.set_shader_parameter("cut_radius", _cut_radius)
		m.set_shader_parameter("cut_floor", 0.45)
	if yard != null:
		yard.update_roof(player_pos, delta)
	_update_mesh_cut()


## Tall meshes (furniture, yard props, doors, collectors, barricades) between
## the camera and the player, inside the cut radius, are hidden (they keep
## their shadow) and ignored by aim_ray.
func _update_mesh_cut() -> void:
	_hidden_bodies.clear()
	for p in props:
		var cut := _in_cut(p["centre"], p["half"])
		if cut != p["cut"]:
			p["cut"] = cut
			WorldObject.set_geometry_cut(p["node"], cut)
		if cut and (p["body"] as RID).is_valid():
			_hidden_bodies.append(p["body"])
	for o in objects:
		if o.kind == "crate":
			continue
		var h: float = WorldObject.DEFS[o.kind]["size"].y
		var cut := _in_cut(Vector3(o.pos.x, o.base_y() + h * 0.5, o.pos.y), 0.5)
		o.set_cut(cut)
		if cut and o.body != null:
			_hidden_bodies.append(o.body.get_rid())


func _in_cut(c: Vector3, half: float) -> bool:
	if not _cut_on:
		return false
	var rel := c - _cut_origin
	var t := rel.dot(_cut_dir)
	if t <= 0.2:
		return false
	return (rel - _cut_dir * t).length() < _cut_radius + half * 0.5


func is_prop_cut(id: String) -> bool:
	for p in props:
		if (p["node"] as Node).name == "Prop_" + id:
			return p["cut"]
	return false


func is_cut(c: Vector3i) -> bool:
	if not _cut_on:
		return false
	var p := grid.center(c)
	var rel := p - _cut_origin
	var t := rel.dot(_cut_dir)
	if t <= 0.45 or p.y <= 0.45:
		return false
	return (rel - _cut_dir * t).length() < _cut_radius - 0.15


## `low` (Experiment 004, build-mode demolish) also stops at low obstacles
## (low furniture) on layer 5.
func aim_ray(from: Vector3, dir: Vector3, low := false) -> Vector3:
	var best := 200.0
	var vh := grid.raycast(from, dir, best, _bullet_skip, is_cut)
	if not vh.is_empty():
		best = vh["dist"]
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * best, 1 | 8 | (16 if low else 0))
	q.exclude = _hidden_bodies
	var ph := get_world_3d().direct_space_state.intersect_ray(q)
	aim_furniture = ""
	if not ph.is_empty():
		best = from.distance_to(ph["position"])
		var col: Object = ph["collider"]
		if col != null and col.has_meta("furniture"):
			aim_furniture = col.get_meta("furniture")
	if dir.y < -0.001:
		var tg := -from.y / dir.y
		if tg < best:
			best = tg
	return from + dir * best


# --- shooting --------------------------------------------------------------------------

## One bullet. Returns {"kind": "voxel"|"enemy"|"body"|"ground"|"none", "pos", "collider"}.
## Doors, crates, collectors and tall furniture stop bullets (impact, no
## damage); barricades let them pass between the planks. `max_range`
## (Experiment 003, e.g. the shotgun's 14 m) is the ray length: nothing
## beyond it is hit ("none", the tracer ends there).
func shoot(origin: Vector3, dir: Vector3, exclude: Array, muzzle := Vector3.INF, max_range := Tuning.SHOT_RANGE) -> Dictionary:
	_shots += 1
	dir = dir.normalized()
	var best := clampf(max_range, 0.1, Tuning.SHOT_RANGE * 4.0) if is_finite(max_range) else Tuning.SHOT_RANGE
	var kind := "none"
	var vh := grid.raycast(origin, dir, best, _bullet_skip)
	if not vh.is_empty():
		best = vh["dist"]
		kind = "voxel"
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * best, 1 | 8)
	q.exclude = exclude
	var ph := get_world_3d().direct_space_state.intersect_ray(q)
	var col: Object = null
	if not ph.is_empty():
		best = origin.distance_to(ph["position"])
		col = ph["collider"]
		kind = "enemy" if col is VoxelEnemy else "body"
	# Experiment 004: an intact tall furniture piece turns to voxels and takes the hit
	if kind == "body" and furniture != null and col != null and col.has_meta("furniture"):
		var fid: String = col.get_meta("furniture")
		furniture.voxelise(fid)
		var vh2 := grid.raycast(origin, dir, best + 0.8, _bullet_skip)
		if not vh2.is_empty():
			vh = vh2
			best = vh["dist"]
			kind = "voxel"
			col = null
		else:
			furniture.hurt(fid, HouseFurniture.SHOT_DAMAGE)
	if kind == "none" and dir.y < -0.001:
		var tg := -origin.y / dir.y
		if tg < best:
			best = tg
			kind = "ground"
	var hit := origin + dir * best
	match kind:
		"voxel":
			_hit_voxels(vh, dir)
		"enemy":
			(col as VoxelEnemy).take_hit(dir)
			fx.flesh_hit(hit, -dir, VoxelArt.to_color(0x5a5550))
			Sfx.play("impact/flesh", hit)
		"body":
			var imp: int = col.get_meta("impact", VoxelMat.Impact.DUST) if col != null else VoxelMat.Impact.DUST
			fx.impact(imp, hit, ph["normal"], dir, {})
			Sfx.play(IMPACT_SOUND.get(imp, "impact/plaster"), hit)
			# Experiment 004: objects (doors, boards, crates, the fuse box) take bullet damage
			var obj := _object_of(col)
			if obj != null:
				damage_object(obj, SHOT_OBJECT_DAMAGE, origin, true)
		"ground":
			fx.ground_hit(hit, dir)
			Sfx.play("impact/ground", hit)
	fx.tracer(muzzle if muzzle != Vector3.INF else origin, hit)
	return {"kind": kind, "pos": hit, "collider": col}


## The WorldObject owning a collider (its "Body" under the pivot), or null.
func _object_of(col: Object) -> WorldObject:
	var n := col as Node
	while n != null and n != self:
		if n is WorldObject:
			return n
		n = n.get_parent()
	return null


func _hit_voxels(vh: Dictionary, dir: Vector3) -> void:
	var m: int = vh["mat"]
	var pos: Vector3 = vh["pos"]
	var c: Vector3i = vh["cell"]
	var ch: Dictionary
	if m == VoxelMat.GLASS:
		ch = VoxelCarver.shatter_glass(grid, grid.idx(c.x, c.y, c.z))
	else:
		var r := WALL_CARVE
		if c.y <= VoxelHouse.FLOOR_ROW:
			r = FLOOR_CARVE
		elif not VoxelMat.is_struct(m):
			r = FURNITURE_CARVE
		var stretch := PENETRATION if r == WALL_CARVE else 1.0
		if m == VoxelMat.METAL_SHEET:
			r *= SHEET_CARVE
		elif m == VoxelMat.MASONRY or m == VoxelMat.MORTAR:
			r *= STONE_CARVE
			stretch = minf(stretch, STONE_STRETCH)
		var t0 := Time.get_ticks_usec()
		ch = VoxelCarver.carve_sphere(grid, pos + dir * 0.07, r, _shots * 7919 + c.x, dir, stretch, damage_quantum)
		stats["carve_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	_apply_damage(ch)
	fx.impact(VoxelMat.IMPACT[m], pos, vh["normal"], dir, ch)
	Sfx.play(IMPACT_SOUND.get(VoxelMat.IMPACT[m], "impact/plaster"), pos)
	if furniture != null and m >= VoxelMat.WOOD:
		furniture.on_shot_cell(c)


## Damage only removes voxels, so only WALL cells can change (to OPEN).
func _apply_damage(ch: Dictionary) -> void:
	var cells: PackedInt32Array = ch["cells"]
	if cells.is_empty():
		return
	chunks.apply_change(ch)
	var mats: PackedByteArray = ch["mats"]
	var row_lo := grid.idx(0, VoxelHouse.BASE_ROW, 0)
	var row_hi := grid.idx(0, VoxelHouse.TOP_ROW + 1, 0)
	for k in cells.size():
		if VoxelMat.is_struct(mats[k]) and cells[k] >= row_lo and cells[k] < row_hi:
			var s: Variant = _section_of_index(cells[k])
			if s != null:
				sections[s]["current"] -= 1
	if _recompute_nav(_plan_rect(ch["lo"], ch["hi"]).grow(GridNav.CELL), true):
		Sfx.play("structure/crumble", grid.center((ch["lo"] + ch["hi"]) / 2))
	if furniture != null:
		furniture.on_removed(ch)
	if not _settling:                # Refinement 01 (S): what this left hanging falls next frame
		_queue_settle(ch["lo"], ch["hi"])
	structure_changed.emit()


# --- enemies ---------------------------------------------------------------------------

## An enemy swing at nav cell `target`: damages a door or barricade standing
## there, otherwise bites the voxels still blocking the passage. `strength`
## (Experiment 003, e.g. 3 for a brute) multiplies the object damage
## (rounded) and the bites (that many bites in one swing; below 1 a smaller
## bite). Bites into masonry and iron plate are much smaller.
func enemy_strike(attacker_pos: Vector3, target: Vector2, strength := 1.0) -> void:
	strength = clampf(strength, 0.1, 20.0)
	var o: WorldObject = _obj_cells.get(nav.cell_of(target))
	if o != null and o.bashable():
		damage_object(o, maxi(1, roundi(Tuning.ENEMY_WALL_DAMAGE * strength)), attacker_pos)
		return
	# Experiment 004: furniture in the way is smashed
	var fid := furniture.id_at_cell(nav.cell_of(target)) if furniture != null else ""
	if fid != "":
		furniture.strike(fid, maxi(1, roundi(Tuning.ENEMY_WALL_DAMAGE * strength * HouseFurniture.BLOW)), attacker_pos)
		return
	for k in maxi(1, roundi(strength)):
		_bite(attacker_pos, target, minf(strength, 1.0))


func _bite(attacker_pos: Vector3, target: Vector2, strength: float) -> void:
	var h := _rng.randf_range(0.2, 1.5)
	var aim := target
	var to_t := target - Vector2(attacker_pos.x, attacker_pos.z)
	var along := Vector2(0, 1) if absf(to_t.x) > absf(to_t.y) else Vector2(1, 0)
	var blockers := _blockers(target, along)
	if not blockers.is_empty():
		var b: Vector3 = blockers[_rng.randi() % blockers.size()]
		h = clampf(b.y, 0.2, 1.55)
		aim = Vector2(b.x, b.z)
	var from := Vector3(attacker_pos.x, h, attacker_pos.z)
	var to := Vector3(aim.x + _rng.randf_range(-0.08, 0.08), h, aim.y + _rng.randf_range(-0.08, 0.08))
	var dir := (to - from).normalized()
	var vh := grid.raycast(from, dir, from.distance_to(to) + 0.4, _bullet_skip)
	var center := to
	var m := VoxelMat.DRYWALL
	var n := -dir
	if not vh.is_empty():
		center = (vh["pos"] as Vector3) + dir * 0.1
		m = vh["mat"]
		n = vh["normal"]
	var r := BITE_RADIUS * pow(strength, 1.0 / 3.0)
	if m == VoxelMat.METAL_SHEET:
		r *= SHEET_BITE
	elif m == VoxelMat.MASONRY or m == VoxelMat.MORTAR:
		r *= STONE_BITE
	var ch := VoxelCarver.carve_sphere(grid, center, r, _rng.randi(), Vector3.ZERO, 1.0, damage_quantum)
	if (ch["cells"] as PackedInt32Array).is_empty():
		return
	_apply_damage(ch)
	fx.impact(VoxelMat.IMPACT[m], center - dir * 0.1, n, dir, ch)
	Sfx.play(IMPACT_SOUND.get(VoxelMat.IMPACT[m], "impact/plaster"), center)


func _blockers(target: Vector2, along: Vector2) -> Array:
	var out := []
	var half := Vector2.ONE * GridNav.CELL * 0.5 + along * GridNav.CELL
	var xr := grid.centre_range(0, target.x - half.x, target.x + half.x)
	var zr := grid.centre_range(2, target.y - half.y, target.y + half.y)
	for y in range(VoxelHouse.NAV_ROW_LO, VoxelHouse.NAV_ROW_HI + 1):
		for z in range(zr.x, zr.y):
			for x in range(xr.x, xr.y):
				if VoxelMat.is_struct(grid.get_mat(x, y, z)):
					out.append(grid.center(Vector3i(x, y, z)))
	return out


# --- objects ---------------------------------------------------------------------------

func _spawn_object(kind: String, p: Vector2, rot: int, is_built: bool, hp := -1, is_open := false, mat := "wood") -> WorldObject:
	var o := WorldObject.new()
	o.setup(kind, p, rot, self, is_built, mat)
	if hp > 0:
		o.hp = mini(hp, o.max_hp)
	o.open = is_open
	add_child(o)
	objects.append(o)
	return o


## Places an object (no validity checks: BuildMode validates). Updates nav.
## `mat` "iron" makes a reinforced door or an iron barricade (WorldObject.MATS).
func place_object(kind: String, p: Vector2, rot: int, is_built := true, mat := "wood") -> WorldObject:
	var o := _spawn_object(kind, p, rot, is_built, -1, false, mat)
	_index_objects()
	_recompute_nav(o.footprint().grow(GridNav.CELL))
	structure_changed.emit()
	if kind == "fuse_box":
		power_changed.emit()
	return o


func remove_object(o: WorldObject) -> void:
	if not objects.has(o):
		return
	var rect := o.footprint().grow(GridNav.CELL)
	objects.erase(o)
	if o.body != null:
		o.body.collision_layer = 0
	o.queue_free()
	_index_objects()
	_recompute_nav(rect)
	structure_changed.emit()
	if o.kind == "fuse_box":
		power_changed.emit()


## Damages an object (doors and barricades by enemies, anything by blasts);
## destroyed objects break into debris in their material's colours. `quiet`
## (blasts) skips the per-hit chips and sounds.
func damage_object(o: WorldObject, n: int, from := Vector3.INF, quiet := false) -> void:
	var at := Vector3(o.pos.x, 1.0, o.pos.y)
	var dir := Vector3(at.x - from.x, 0, at.z - from.z).normalized() if from != Vector3.INF else Vector3.FORWARD
	if dir.length() < 0.5:
		dir = Vector3.FORWARD
	var tones := o.debris_tones()
	if not quiet:
		for k in 5:
			fx.debris(at + Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.5, 0.4), 0), dir * 1.5 + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.5, 2.0), _rng.randf_range(-1, 1)), VoxelArt.to_color(tones[k % tones.size()]), 0.7)
		Sfx.play("door/bash" if o.mat == "wood" else "impact/metal", at)
	if not o.take_damage(n):
		return
	for k in 26:
		var c := VoxelArt.to_color(tones[k % tones.size()])
		fx.debris(at + Vector3(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.9, 0.8), _rng.randf_range(-0.1, 0.1)),
			dir * 2.0 + Vector3(_rng.randf_range(-1.5, 1.5), _rng.randf_range(0.5, 3.0), _rng.randf_range(-1.5, 1.5)), c, _rng.randf_range(0.8, 1.6))
	fx.impact(VoxelMat.Impact.WOOD if o.mat == "wood" else VoxelMat.Impact.METAL, at, -dir, dir, {})
	Sfx.play("structure/break", at)
	var kind := o.kind
	var where := Vector3(o.pos.x, 0, o.pos.y)
	remove_object(o)
	object_destroyed.emit(kind, where)


## SPEC-003 §4. A blast at `center` (plan x, height, plan y; a bomber blows
## up at about 1 m). The structure is carved by VoxelCarver.carve_blast in the
## damage quantum's blocks: the reach `radius` is used up by the material in
## between (VoxelMat.BLAST), so stone and iron plating resist far more than
## timber, and the foundation slab never goes. What is left around the crater
## is scorched (persistent, repair cleans it). Every object within
## BLAST_OBJECT_REACH x radius loses up to `power` HP at the centre, falling
## off with distance ((1 - d / reach)^0.75) and with the armour between the
## blast and the object (walls shield what stands behind them). Collision and
## navigation are updated before this returns; the crater's meshes too, the
## rest of the scorch over the next frames. Plays the flash, fireball,
## debris in the materials' colours, dust and smoke, and leaves a scorch mark
## on the ground (saved with the world). Characters are hurt by the caller
## (the game), and the camera shake is the game's. Returns
##   {"voxels": removed voxels, "hit": [object kinds], "destroyed": [kinds],
##    "opened": nav cells that became walkable, "breach": bool (a wall, door
##    or barricade cell opened), "sections": [Vector3i] sections that lost
##    voxels, "ms": time taken}.
func explode(center: Vector3, radius: float, power: float) -> Dictionary:
	var out := {"voxels": 0, "hit": [], "destroyed": [], "opened": 0, "breach": false, "sections": [], "ms": 0.0}
	if grid == null or not center.is_finite() or not is_finite(radius) or not is_finite(power) or radius <= 0.0:
		return out
	var t0 := Time.get_ticks_usec()
	radius = minf(radius, 4.0)
	power = maxf(power, 0.0)
	var p := Vector2(center.x, center.z)
	var reach := radius * BLAST_OBJECT_REACH
	var area := Rect2(p - Vector2.ONE * (reach + 0.5), Vector2.ONE * (reach + 0.5) * 2.0)
	var before := {}
	for c in nav.cells_in_rect(area):
		before[c] = [nav.is_walkable(c), nav.get_raw(c)]
	# object damage factors, measured before anything breaks (walls shield)
	var hits := []
	for o in objects_in(Rect2(p - Vector2.ONE * reach, Vector2.ONE * reach * 2.0)):
		var fp: Rect2 = (o as WorldObject).footprint()
		var d := p.distance_to(p.clamp(fp.position, fp.end))
		if d > reach:
			continue
		var oc := Vector3(o.pos.x, clampf(center.y, 0.3, 1.2), o.pos.y)
		var shield := VoxelCarver.blast_armour(grid, center, oc, reach)
		var f := pow(1.0 - d / reach, 0.75) * clampf(1.0 - shield / reach, 0.0, 1.0)
		if f > 0.0:
			hits.append([o, f])
	# Experiment 004: furniture in reach; survivors turn to voxels first so the crater bites into them
	var fhits := _blast_furniture(center, p, reach, power)
	var t1 := Time.get_ticks_usec()
	var ch := VoxelCarver.carve_blast(grid, center, radius, _rng.randi(), damage_quantum)
	var t2 := Time.get_ticks_usec()
	var cells: PackedInt32Array = ch["cells"]
	var mats: PackedByteArray = ch["mats"]
	out["voxels"] = cells.size()
	var touched := {}
	for k in cells.size():
		if VoxelMat.is_struct(mats[k]):
			var s: Variant = _section_of_index(cells[k])
			if s != null:
				touched[s] = true
	out["sections"] = touched.keys()
	_apply_damage(ch)
	if not cells.is_empty():
		# exact counts for every section near the crater (corners included)
		var crater := _plan_rect(ch["lo"], ch["hi"])
		for s in sections:
			if seg_rect(s, 0.3, 0.2).intersects(crater):
				_count_section(s)
		settle(ch["lo"], ch["hi"])     # Refinement 01 (S): wall left hanging over the crater falls
	var t3 := Time.get_ticks_usec()
	_scorch(center, radius)
	var t4 := Time.get_ticks_usec()
	var splinters := PackedColorArray()
	for h in hits:
		var o: WorldObject = h[0]
		if not is_instance_valid(o) or not objects.has(o):
			continue
		var kind := o.kind
		out["hit"].append(kind)
		var tones := o.debris_tones()
		damage_object(o, maxi(1, int(ceil(power * float(h[1])))), center, true)
		if not objects.has(o):
			out["destroyed"].append(kind)
			for k in 10:
				splinters.append(VoxelArt.to_color(tones[k % tones.size()]))
	out["furniture"] = []
	for h in fhits:
		if furniture.ok(h[0]):
			furniture.hurt(h[0], h[1], true)
			if not furniture.ok(h[0]):
				out["furniture"].append(h[0])
	for c in before:
		if not before[c][0] and nav.is_walkable(c):
			out["opened"] += 1
			if before[c][1] == GridNav.WALL:
				out["breach"] = true
	# the crater shows in the same frame as the flash
	var t5 := Time.get_ticks_usec()
	chunks.flush(BLAST_MESH_BUDGET_MS)
	var t6 := Time.get_ticks_usec()
	stats["blast"] = {"prep_ms": (t1 - t0) / 1000.0, "carve_ms": (t2 - t1) / 1000.0, "apply_ms": (t3 - t2) / 1000.0,
		"scorch_ms": (t4 - t3) / 1000.0, "objects_ms": (t5 - t4) / 1000.0, "mesh_ms": (t6 - t5) / 1000.0}
	_add_scar(center.x, center.z, radius * 1.15)
	if fx != null:
		fx.blast(center, radius, ch, splinters)
	if ResourceLoader.exists(AssetResolver.audio_fallback_path("structure/blast")):
		Sfx.play("structure/blast", center)
	Sfx.play("structure/break", center)
	Sfx.play("structure/crumble", center)
	structure_changed.emit()
	out["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	return out


## Furniture a blast at `center` damages: [[id, HP], ...] with the same
## fall-off and shielding as objects. Pieces that survive are voxelised now.
func _blast_furniture(center: Vector3, p: Vector2, reach: float, power: float) -> Array:
	var out := []
	if furniture == null:
		return out
	for id in furniture.pieces:
		if not furniture.ok(id):
			continue
		var pc: Dictionary = furniture.pieces[id]
		var r: Rect2 = pc["f"]["rect"]
		var near := p.clamp(r.position, r.end)
		var d := p.distance_to(near)
		if d > reach:
			continue
		var fc := Vector3(near.x, clampf(center.y, 0.2, minf(float(pc["f"]["height"]), 1.2) * 0.6), near.y)
		var shield := VoxelCarver.blast_armour(grid, center, fc, reach)
		var f := pow(1.0 - d / reach, 0.75) * clampf(1.0 - shield / reach, 0.0, 1.0)
		if f <= 0.0:
			continue
		var n := maxi(1, int(ceil(power * f)))
		out.append([id, n])
		if n < int(pc["hp"]):
			furniture.voxelise(id)
	return out


## Darkens the exposed voxels within radius x SCORCH_REACH of a blast (the
## current grid only: repair brings the design's colours back). Meshes are
## rebuilt over the next frames; collision is not touched.
func _scorch(center: Vector3, radius: float) -> void:
	var rr := radius * SCORCH_REACH
	var lo := grid.cell_of(center - Vector3.ONE * rr).clamp(Vector3i(1, VoxelHouse.FLOOR_ROW, 1), Vector3i(grid.sx - 2, grid.sy - 2, grid.sz - 2))
	var hi := (grid.cell_of(center + Vector3.ONE * rr) + Vector3i.ONE).clamp(Vector3i.ONE, Vector3i(grid.sx - 1, grid.sy - 1, grid.sz - 1))
	var up := grid.sx * grid.sz
	var sx := grid.sx
	var gm := grid.mat
	var flags := VoxelMat.FLAGS
	var n := 0
	for y in range(lo.y, hi.y):
		for z in range(lo.z, hi.z):
			for x in range(lo.x, hi.x):
				var i := (y * grid.sz + z) * sx + x
				var m := gm[i]
				if m == 0 or (flags[m] & VoxelMat.F_GLASS) != 0:
					continue
				if gm[i + 1] != 0 and gm[i - 1] != 0 and gm[i + sx] != 0 and gm[i - sx] != 0 and gm[i + up] != 0 and gm[i - up] != 0:
					continue
				var d := (grid.origin + (Vector3(x, y, z) + Vector3(0.5, 0.5, 0.5)) * grid.vs).distance_to(center)
				if d >= rr:
					continue
				var k := clampf((1.0 - d / rr) * 1.3, 0.0, 0.86) * (0.72 + 0.28 * VoxelArt.hash3(x, y, z, 77))
				grid.col[i] = VoxelArt.mix(grid.col[i], SOOT, k)
				grid.pcol[i] = VoxelArt.mix(grid.pcol[i], SOOT, k)
				n += 1
	if n > 0:
		chunks.mark_visual_dirty(lo - Vector3i.ONE, hi + Vector3i.ONE)


const SCAR_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled;
instance uniform float seed = 0.0;
float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float n = vnoise(q * 3.0 + seed) * 0.6 + vnoise(q * 7.0 - seed * 1.7) * 0.4;
	float edge = 0.62 + (n - 0.5) * 0.45;
	float a = 1.0 - smoothstep(edge * 0.5, edge, r);
	float ang = atan(q.y, q.x);
	float streak = vnoise(vec2(ang * 2.6 + seed, seed * 0.3));
	a = max(a, (1.0 - smoothstep(0.25, 0.98, r)) * smoothstep(0.55, 0.85, streak) * 0.75);
	ALBEDO = mix(vec3(0.025, 0.022, 0.02), vec3(0.09, 0.075, 0.06), smoothstep(0.0, 0.85, r));
	ALPHA = a * 0.9;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
"""
static var _scar_mat: ShaderMaterial


## A scorch mark on the ground (just above the yard's ground plane; the
## house floor hides it indoors, where the scorched floor voxels show
## instead). Recorded in `scars` (saved); the oldest goes past SCARS_MAX.
func _add_scar(x: float, z: float, r: float) -> void:
	if _scar_root == null:
		return
	if scars.size() >= SCARS_MAX:
		scars.pop_front()
		if _scar_root.get_child_count() > 0:
			_scar_root.get_child(0).free()
	scars.append([x, z, r])
	if _scar_mat == null:
		var sh := Shader.new()
		sh.code = SCAR_SHADER
		_scar_mat = ShaderMaterial.new()
		_scar_mat.shader = sh
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(r * 2.0, r * 2.0)
	mi.mesh = pm
	mi.material_override = _scar_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(x, VoxelYard.GROUND_Y + 0.012, z)
	mi.rotation.y = fmod(absf(x * 12.9898 + z * 78.233), TAU)
	mi.set_instance_shader_parameter("seed", fmod(absf(x * 3.7 + z * 5.3), 50.0))
	_scar_root.add_child(mi)


## SPEC-003 §5. Where a wall-seeking attacker (the bomber) should strike,
## best first. Candidates: closed doors, barricades, and the exterior walls
## of the house and every player-built wall, wherever their outside can be
## reached on foot. Each entry:
##   {"kind": "door" | "barricade" | "wall",
##    "pos": Vector2, where the attacker stands: the first walkable nav cell
##           0.3-1.2 m out from the OUTSIDE face,
##    "target": Vector2, the centre of the door, barricade or wall section,
##    "score": float (higher = better target), "seg": Vector3i,
##    "object": WorldObject or null, "material": "wood" | "iron" (objects),
##           "frame" | "wood" | "stone" (walls),
##    "strength": float, relative resistance (a wooden door = 1)}
## Score = protection (door 1.0, barricade 0.9, wall 0.6) / strength
## (objects: HP over a wooden door's 18; walls: section_strength x the
## remaining integrity x the square root of how much of a full wall the
## section is, so windows and damaged walls are weaker, stone and plated
## walls strong) + up to 0.8
## for lying within 8 m of `near` (pass the player's position) - 0.03 per
## metre from `from`. Sections already walkable through, and doors or
## barricades standing in them, are left out of the walls (they are listed
## as objects).
func weak_points(from: Vector2, near := Vector2.INF) -> Array:
	var out := []
	var wood_door := float(WorldObject.max_hp_of("door", "wood"))
	for o in objects:
		if not (o.kind == "barricade" or o.kind == "boards" or (o.kind == "door" and not o.open)):
			continue
		var stand := _stand_point(o.pos, WorldObject.front_dir(o.rot))
		if stand == Vector2.INF:
			continue
		# Experiment 004: window boards (a weak window behind planks), metal doors (HP 70)
		var base := 1.0 if o.kind == "door" else (0.85 if o.kind == "boards" else 0.9)
		var strength := float(o.hp) / wood_door + (0.3 if o.kind == "boards" else 0.0)
		out.append(_weak_point(o.kind, stand, o.pos, base, strength, from, near, o.seg, o, o.mat))
	for s in sections:
		var sec: Dictionary = sections[s]
		if int(sec["design"]) <= 0 or not _is_outer_wall(s):
			continue
		var c := seg_center(s)
		if nav.is_walkable(nav.cell_of(c)) or not objects_in(seg_rect(s, 0.12, -0.1)).is_empty():
			continue
		var stand := _stand_point(c, _outward(s))
		if stand == Vector2.INF:
			continue
		var thick := 2.0 if sec["material"] == "wood" else 3.0
		var fill := sqrt(clampf(float(sec["design"]) / (VoxelHouse.WALL_ROWS * 10.0 * thick), 0.25, 1.0))
		var strength := section_strength(s) * maxf(section_integrity(s), 0.1) * fill
		out.append(_weak_point("wall", stand, c, 0.6, strength, from, near, s, null, sec["material"]))
	out.sort_custom(func(a, b): return a["score"] > b["score"])
	return out


func _weak_point(kind: String, stand: Vector2, target: Vector2, base: float, strength: float, from: Vector2, near: Vector2,
		seg: Vector3i, o: WorldObject, mat: String) -> Dictionary:
	strength = maxf(strength, 0.1)
	var score := base / strength - target.distance_to(from) * 0.03
	if near.is_finite():
		score += 0.8 * maxf(0.0, 1.0 - target.distance_to(near) / 8.0)
	return {"kind": kind, "pos": stand, "target": target, "score": score, "seg": seg, "object": o, "material": mat, "strength": strength}


## The first walkable nav cell centre 0.3-1.2 m from `c` along `dir`, inside
## the lot; INF if there is none (the outside is blocked or off the lot).
func _stand_point(c: Vector2, dir: Vector2) -> Vector2:
	var t := 0.3
	while t <= 1.2:
		var q := c + dir * t
		var cell := nav.cell_of(q)
		if LOT.has_point(q) and nav.is_walkable(cell):
			return nav.center_of(cell)
		t += 0.125
	return Vector2.INF


## Exterior house walls and every player-built wall.
func _is_outer_wall(s: Vector3i) -> bool:
	if built.has(s):
		return true
	var f := HousePlan.FOOTPRINT
	if s.x == 0:
		return s.y == int(f.position.y) or s.y == int(f.end.y)
	return s.y == int(f.position.x) or s.y == int(f.end.x)


## Unit plan vector from a wall section toward its outside: away from the
## house for its walls, away from the bed for built walls.
func _outward(s: Vector3i) -> Vector2:
	var sign := 1.0
	if built.has(s) or not sections.get(s, {}).get("orig", false):
		sign = float(outer_sign(s))
	else:
		var mid := HousePlan.FOOTPRINT.get_center()
		sign = 1.0 if float(s.y) > (mid.y if s.x == 0 else mid.x) else -1.0
	return Vector2(0, sign) if s.x == 0 else Vector2(sign, 0)


## Opens or closes a door. Returns "" or the reason it can't close.
## Experiment 004: closing a door the player stands in steps the player
## clear (to their side of the door line) instead of refusing; an enemy in
## the doorway still blocks it.
func toggle_door(o: WorldObject) -> String:
	if o.kind != "door":
		return ""
	if o.open:
		var why := _clear_doorway(o)
		if why != "":
			return why
	set_door_open(o, not o.open)
	return ""


## Bodies overlapping a door's footprint: "" after moving players out of
## the way, or the reason it can't close (an enemy or something else).
func _clear_doorway(o: WorldObject) -> String:
	var rect := o.footprint().grow(0.05)
	var box := BoxShape3D.new()
	box.size = Vector3(rect.size.x, 1.4, rect.size.y)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.transform = Transform3D(Basis(), Vector3(rect.get_center().x, 0.85, rect.get_center().y))
	q.collision_mask = 4 | 8
	var players: Array[Node3D] = []
	for hit in get_world_3d().direct_space_state.intersect_shape(q, 8):
		var b := hit["collider"] as CollisionObject3D
		if b == null or (b.collision_layer & 4) == 0 or not (b is Node3D):
			return "Something is in the way."
		players.append(b as Node3D)
	var horiz := o.rot % 2 == 0
	var back := -WorldObject.front_dir(o.rot)
	for b in players:
		var p := Vector2(b.global_position.x, b.global_position.z)
		var across := (p.y - o.pos.y) if horiz else (p.x - o.pos.x)
		var side := signf(across) if absf(across) > 0.01 else (back.y if horiz else back.x)
		var clear := 0.125 + Tuning.PLAYER_RADIUS + 0.1
		if horiz:
			p = Vector2(clampf(p.x, o.pos.x - 0.25, o.pos.x + 0.25), o.pos.y + side * clear)
		else:
			p = Vector2(o.pos.x + side * clear, clampf(p.y, o.pos.y - 0.25, o.pos.y + 0.25))
		b.global_position = Vector3(p.x, b.global_position.y, p.y)
		if b is CharacterBody3D:
			(b as CharacterBody3D).velocity = Vector3.ZERO
	return ""


func set_door_open(o: WorldObject, on: bool) -> void:
	o.set_open(on)
	_recompute_nav(o.footprint().grow(GridNav.CELL))
	Sfx.play("door/open" if on else "door/close", Vector3(o.pos.x, 1.0, o.pos.y))
	structure_changed.emit()


func object_at(p: Vector2, margin := 0.15) -> WorldObject:
	for o in objects:
		if o.footprint().grow(margin).has_point(p):
			return o
	return null


func objects_in(rect: Rect2) -> Array:
	var out := []
	for o in objects:
		if o.footprint().intersects(rect):
			out.append(o)
	return out


func _index_objects() -> void:
	_obj_cells.clear()
	for o in objects:
		for c in nav.cells_in_rect(o.footprint()):
			_obj_cells[c] = o


# --- navigation ------------------------------------------------------------------------

## Raw kind of one nav cell: SOLID for furniture, yard props, crates and
## collectors; WALL for closed doors, barricades and remaining structural
## voxels in the cell's footprint columns between the nav rows; else OPEN.
## In a door-like gap only voxels inside the gap count (not its jambs).
func _cell_kind(c: Vector2i) -> int:
	if _static_solid[c.y * nav.size.x + c.x] == 1:
		return GridNav.SOLID
	if furniture != null:
		var fk := furniture.cell_kind(c)
		if fk >= 0:
			return fk
	var o: WorldObject = _obj_cells.get(c)
	if o != null:
		var k := o.nav_kind()
		if k >= 0:
			return k
	return GridNav.WALL if _cell_has_struct(c) else GridNav.OPEN


func _cell_has_struct(c: Vector2i) -> bool:
	var cc := nav.center_of(c)
	if not _house_zone.has_point(cc) and not _struct_zone.has(c):
		return false
	var lo := cc - Vector2.ONE * GridNav.CELL * 0.5
	var hi := cc + Vector2.ONE * GridNav.CELL * 0.5
	if _opening_clip.has(c):
		var r: Rect2 = _opening_clip[c]
		lo = lo.max(r.position)
		hi = hi.min(r.end)
		if hi.x <= lo.x or hi.y <= lo.y:
			return false
	return grid.any_struct_in(lo, hi, VoxelHouse.NAV_ROW_LO, VoxelHouse.NAV_ROW_HI)


## Recomputes raw cells in `rect` (plan metres). walls_only: only WALL cells
## may change (damage). Returns true if any cell changed.
func _recompute_nav(rect: Rect2, walls_only := false) -> bool:
	var changed := false
	for c in nav.cells_in_rect(rect):
		var old := nav.get_raw(c)
		if walls_only and old != GridNav.WALL:
			continue
		var k := _cell_kind(c)
		if k != old:
			nav.set_raw(c, k)
			changed = true
	if changed:
		nav.refresh_region(rect)
	return changed


func _full_nav() -> void:
	var t0 := Time.get_ticks_usec()
	for j in nav.size.y:
		for i in nav.size.x:
			var c := Vector2i(i, j)
			nav.set_raw(c, _cell_kind(c))
	nav.rebuild()
	stats["nav_ms"] = (Time.get_ticks_usec() - t0) / 1000.0


func _index_openings() -> void:
	_opening_clip.clear()
	for op in openings:
		var f: float = op["from"]
		var t: float = op["to"]
		var line: float = op["line"]
		var clip := Rect2(f, line - 0.3, t - f, 0.6) if op["axis"] == 0 else Rect2(line - 0.3, f, 0.6, t - f)
		var on_line := Rect2(f, line - 0.125, t - f, 0.25) if op["axis"] == 0 else Rect2(line - 0.125, f, 0.25, t - f)
		for c in nav.cells_in_rect(on_line):
			_opening_clip[c] = clip


func _mark_struct_zone(s: Vector3i) -> void:
	for c in nav.cells_in_rect(seg_rect(s, 0.4, 0.3)):
		_struct_zone[c] = true


## Plan rect of grid cells [lo, hi).
func _plan_rect(lo: Vector3i, hi: Vector3i) -> Rect2:
	var p0 := Vector2(grid.origin.x + lo.x * grid.vs, grid.origin.z + lo.z * grid.vs)
	var p1 := Vector2(grid.origin.x + hi.x * grid.vs, grid.origin.z + hi.z * grid.vs)
	return Rect2(p0, p1 - p0)


# --- the exit rule ---------------------------------------------------------------------

## SPEC §6: a walkable path (body clearance) must lead from the bed to the lot
## edge, counting doors (open or closed) as passable and walls, barricades,
## furniture and objects as blocking. `extra` (nav cell -> GridNav kind)
## previews a change without applying it.
func exit_path_exists(extra := {}) -> bool:
	var special := {}
	for c in _obj_cells:
		if (_obj_cells[c] as WorldObject).kind == "door":
			for dj in range(-1, 2):
				for di in range(-1, 2):
					special[c + Vector2i(di, dj)] = true
	for c in extra:
		for dj in range(-1, 2):
			for di in range(-1, 2):
				special[c + Vector2i(di, dj)] = true
	var start := []
	var bp := bed_position()
	for c in nav.cells_in_rect(Rect2(bp.x - 1.0, bp.z - 0.6, 2.0, 1.2)):
		if _exit_walk(c, special, extra):
			start.append(c)
	var seen := {}
	var queue := start.duplicate()
	for c in start:
		seen[c] = true
	var k := 0
	while k < queue.size():
		var c: Vector2i = queue[k]
		k += 1
		if not LOT.has_point(nav.center_of(c)):
			return true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nc: Vector2i = c + d
			if seen.has(nc):
				continue
			seen[nc] = true
			if _exit_walk(nc, special, extra):
				queue.append(nc)
	return false


func _exit_walk(c: Vector2i, special: Dictionary, extra: Dictionary) -> bool:
	if not nav.in_grid(c):
		return false
	if not special.has(c):
		return nav.is_walkable(c)
	for dj in range(-1, 2):
		for di in range(-1, 2):
			if _exit_kind(c + Vector2i(di, dj), extra) != GridNav.OPEN:
				return false
	return true


func _exit_kind(c: Vector2i, extra: Dictionary) -> int:
	if extra.has(c):
		return extra[c]
	var o: WorldObject = _obj_cells.get(c)
	if o != null and o.kind == "door":
		return GridNav.OPEN
	return nav.get_raw(c)


# --- sections and construction -----------------------------------------------------------

## Plan rect of a 1 m section: `half` across the line, `ext` past each end.
static func seg_rect(s: Vector3i, half := SECTION_ACROSS, ext := 0.0) -> Rect2:
	if s.x == 0:
		return Rect2(s.z - ext, s.y - half, 1.0 + 2.0 * ext, 2.0 * half)
	return Rect2(s.y - half, s.z - ext, 2.0 * half, 1.0 + 2.0 * ext)


## Nearest 1 m segment on an integer plan line to plan point p.
static func nearest_seg(p: Vector2) -> Vector3i:
	var dy := absf(p.y - roundf(p.y))
	var dx := absf(p.x - roundf(p.x))
	if dy <= dx:
		return Vector3i(0, roundi(p.y), floori(p.x))
	return Vector3i(1, roundi(p.x), floori(p.y))


static func seg_center(s: Vector3i) -> Vector2:
	return Vector2(s.z + 0.5, s.y) if s.x == 0 else Vector2(s.y, s.z + 0.5)


## Quarter turn of a wall-like object on segment s whose front faces outward.
func seg_rot(s: Vector3i) -> int:
	var sign := outer_sign(s)
	if s.x == 0:
		return 2 if sign > 0 else 0
	return 1 if sign > 0 else 3


func _box_of(g: VoxelGrid, rect: Rect2, row_lo: int, row_hi: int) -> Array:
	var xr := g.centre_range(0, rect.position.x, rect.end.x)
	var zr := g.centre_range(2, rect.position.y, rect.end.y)
	return [Vector3i(xr.x, row_lo, zr.x), Vector3i(xr.y, row_hi + 1, zr.y)]


func _section_of_index(i: int) -> Variant:
	var c := grid.coords(i)
	var p := VoxelHouse.column_plan(grid, c.x, c.z)
	var ky := roundi(p.y)
	if absf(p.y - ky) < SECTION_ACROSS:
		var s := Vector3i(0, ky, floori(p.x))
		if sections.has(s):
			return s
	var kx := roundi(p.x)
	if absf(p.x - kx) < SECTION_ACROSS:
		var s := Vector3i(1, kx, floori(p.y))
		if sections.has(s):
			return s
	return null


func _new_section(orig: bool, material: String) -> Dictionary:
	return {"orig": orig, "design": 0, "current": 0, "material": material, "strength": float(SECTION_MATERIALS[material]["strength"])}


func _count_section(s: Vector3i) -> void:
	if not sections.has(s):
		return
	sections[s]["strength"] = section_strength(s)
	var b := _box_of(grid, seg_rect(s), VoxelHouse.BASE_ROW, VoxelHouse.TOP_ROW)
	var nd := 0
	var nc := 0
	var st := VoxelMat.STRUCT
	for y in range(b[0].y, b[1].y):
		for z in range(b[0].z, b[1].z):
			for x in range(b[0].x, b[1].x):
				var i := grid.idx(x, y, z)
				nd += st[design.mat[i]]
				nc += st[grid.mat[i]]
	sections[s]["design"] = nd
	sections[s]["current"] = nc


## What a 1 m segment holds, from the design grid: structural coverage of its
## core (0..1, nav rows), glass or window frames, a door-like gap between two
## wall ends, damage, construction state and objects on it.
func section_info(s: Vector3i) -> Dictionary:
	var horiz := s.x == 0
	var b := _box_of(design, seg_rect(s, 0.15, -0.1), VoxelHouse.NAV_ROW_LO, VoxelHouse.NAV_ROW_HI)
	var a0: int = b[0].x if horiz else b[0].z
	var a1: int = b[1].x if horiz else b[1].z
	var t0: int = b[0].z if horiz else b[0].x
	var t1: int = b[1].z if horiz else b[1].x
	var cols := 0
	var covered := 0
	var st := VoxelMat.STRUCT
	for y in range(b[0].y, b[1].y):
		for a in range(a0, a1):
			cols += 1
			for t in range(t0, t1):
				var i := design.idx(a, y, t) if horiz else design.idx(t, y, a)
				if st[design.mat[i]] == 1:
					covered += 1
					break
	var glass := false
	var full := _box_of(design, seg_rect(s, 0.2), VoxelHouse.BASE_ROW, VoxelHouse.TOP_ROW)
	for y in range(full[0].y, full[1].y):
		for z in range(full[0].z, full[1].z):
			for x in range(full[0].x, full[1].x):
				var m := design.mat[design.idx(x, y, z)]
				if m == VoxelMat.GLASS or m == VoxelMat.FRAME:
					glass = true
	var coverage := float(covered) / maxf(1.0, cols)
	var ends := 0
	for e in [-0.1, 1.05]:
		var er := Rect2(s.z + e - 0.05, s.y - 0.15, 0.1, 0.3) if horiz else Rect2(s.y - 0.15, s.z + e - 0.05, 0.3, 0.1)
		if design.any_struct_in(er.position, er.end, VoxelHouse.NAV_ROW_LO, VoxelHouse.NAV_ROW_HI):
			ends += 1
	var sec: Dictionary = sections.get(s, {})
	return {
		"exists": not sec.is_empty(), "orig": sec.get("orig", false), "built": built.has(s), "upgraded": upgraded.has(s),
		"coverage": coverage, "wall": coverage >= 0.5, "glass": glass, "gap": coverage < 0.1 and ends == 2,
		"missing": section_missing(s), "integrity": section_integrity(s),
		"objects": objects_in(seg_rect(s, 0.1)),
		"material": sec.get("material", ""), "strength": section_strength(s) if not sec.is_empty() else 0.0,
		"founded": is_founded(s), "foundation": foundations.has(s), "load": section_load_hint(s),
	}


## Relative resistance of a section's wall (SECTION_MATERIALS strength, x
## PLATED_FACTOR when iron-plated); 0 for no section. Damage is not included
## (see section_integrity).
func section_strength(s: Vector3i) -> float:
	var sec: Dictionary = sections.get(s, {})
	if sec.is_empty():
		return 0.0
	var st := float(SECTION_MATERIALS.get(sec.get("material", "frame"), SECTION_MATERIALS["frame"])["strength"])
	return st * (PLATED_FACTOR if upgraded.has(s) else 1.0)


## Load-bearing hook (no collapse simulation; SPEC-003 §4): a coarse estimate
## of the load the section could carry, for a later support model. It is the
## material's "load" (house frame 1, timber 0.6, stone 2.5) x the remaining
## integrity (0..1) x 1 on a foundation (the house slab or a stone foundation)
## or UNFOUNDED_LOAD without one, x PLATED_FACTOR when iron-plated. 0 for a
## missing section or one without structure. Nothing reads it yet.
func section_load_hint(s: Vector3i) -> float:
	var sec: Dictionary = sections.get(s, {})
	if sec.is_empty() or int(sec["design"]) <= 0:
		return 0.0
	var load := float(SECTION_MATERIALS.get(sec.get("material", "frame"), SECTION_MATERIALS["frame"])["load"])
	return load * section_integrity(s) * (1.0 if is_founded(s) else UNFOUNDED_LOAD) * (PLATED_FACTOR if upgraded.has(s) else 1.0)


## True if the wall line of segment s stands on a floor: the house slab or a
## stone foundation (the design's floor-finish row under the 0.3 m wall
## footprint, at least 85 % covered).
func is_founded(s: Vector3i) -> bool:
	var b := _box_of(design, seg_rect(s, STONE_HALF), VoxelHouse.FLOOR_ROW, VoxelHouse.FLOOR_ROW)
	var n := 0
	var on := 0
	for z in range(b[0].z, b[1].z):
		for x in range(b[0].x, b[1].x):
			n += 1
			var m := design.get_mat(x, VoxelHouse.FLOOR_ROW, z)
			if m == VoxelMat.FLOOR or m == VoxelMat.SCREED or m == VoxelMat.THRESHOLD or m == VoxelMat.PAVING:
				on += 1
	return n > 0 and on >= n * 0.85


## Missing design voxels of a section (as section_missing) by the resource
## that repairs them: "stone" (masonry, mortar), "iron" (plating), "wood"
## (everything else: timber framing, boards, drywall, trim, glass).
func section_missing_by(s: Vector3i) -> Dictionary:
	var b := _box_of(grid, seg_rect(s, SECTION_ACROSS, 0.1), VoxelHouse.FLOOR_ROW, VoxelHouse.TOP_ROW)
	var out := {"wood": 0, "stone": 0, "iron": 0}
	for y in range(b[0].y, b[1].y):
		for z in range(b[0].z, b[1].z):
			for x in range(b[0].x, b[1].x):
				var i := grid.idx(x, y, z)
				var m := design.mat[i]
				if m != 0 and grid.mat[i] != m:
					if m == VoxelMat.MASONRY or m == VoxelMat.MORTAR:
						out["stone"] += 1
					elif m == VoxelMat.METAL_SHEET:
						out["iron"] += 1
					elif m != VoxelMat.PAVING:
						out["wood"] += 1
	return out


func _stone_sections() -> Dictionary:
	var out := {}
	for s in built:
		if sections.has(s) and sections[s].get("material", "") == "stone":
			out[s] = true
	return out


## Fraction of the section's structural voxels still standing (1 = intact).
func section_integrity(s: Vector3i) -> float:
	var sec: Dictionary = sections.get(s, {})
	if sec.is_empty() or sec["design"] <= 0:
		return 1.0
	return clampf(float(sec["current"]) / float(sec["design"]), 0.0, 1.0)


## Voxels of the design missing (or different) in the current grid, over the
## section plus 0.1 m past each end (corner and jamb pieces).
func section_missing(s: Vector3i) -> int:
	var b := _box_of(grid, seg_rect(s, SECTION_ACROSS, 0.1), VoxelHouse.FLOOR_ROW, VoxelHouse.TOP_ROW)
	var n := 0
	for y in range(b[0].y, b[1].y):
		for z in range(b[0].z, b[1].z):
			for x in range(b[0].x, b[1].x):
				var i := grid.idx(x, y, z)
				if design.mat[i] != 0 and grid.mat[i] != design.mat[i]:
					n += 1
	return n


## Copies the design back over the section. Returns the voxels restored.
func repair_section(s: Vector3i) -> int:
	var b := _box_of(grid, seg_rect(s, SECTION_ACROSS, 0.1), VoxelHouse.FLOOR_ROW, VoxelHouse.TOP_ROW)
	var n := _copy_design(b[0], b[1])
	_edited(b[0], b[1])
	return n


func repair_object(o: WorldObject) -> void:
	o.restore()
	structure_changed.emit()


func _copy_design(lo: Vector3i, hi: Vector3i) -> int:
	var n := 0
	for y in range(lo.y, hi.y):
		for z in range(lo.z, hi.z):
			for x in range(lo.x, hi.x):
				var i := grid.idx(x, y, z)
				var m := design.mat[i]
				if m == 0 and grid.mat[i] >= VoxelMat.WOOD:
					continue          # Experiment 004: a damaged furniture piece's voxels
				if grid.mat[i] != m or grid.col[i] != design.col[i] or grid.pcol[i] != design.pcol[i] or grid.pmask[i] != design.pmask[i]:
					if m != 0 and grid.mat[i] != m:
						n += 1
					grid.set_voxel(x, y, z, m, design.col[i], design.pcol[i], design.pmask[i])
	return n


## After any construction edit of cells [lo, hi): meshes and collision now,
## nav for the area, section counts.
func _edited(lo: Vector3i, hi: Vector3i) -> void:
	chunks.mark_dirty(lo - Vector3i.ONE, hi + Vector3i.ONE)
	chunks.flush(12.0)
	var rect := _plan_rect(lo, hi).grow(GridNav.CELL)
	_recompute_nav(rect)
	for s in sections:
		if seg_rect(s, 0.3, 0.2).intersects(rect):
			_count_section(s)
	structure_changed.emit()


## Outward side of a segment: the side farther from the bed (+1 = toward the
## larger plan coordinate across the line).
func outer_sign(s: Vector3i) -> int:
	var bp := bed_position()
	var across := bp.z if s.x == 0 else bp.x
	return 1 if across < s.y else -1


## Builds a wall on segments (design and current), no checks. "wood": two
## voxels thick on the line, full height; outer boards, inner boards with
## studs every 0.5 m; a sole plate where it stands on the ground. "stone":
## three voxels (0.3 m) of masonry in courses with mortar joints, full
## height (BuildMode only allows it on a foundation).
func build_walls(segs: Array, material := "wood") -> void:
	var lo := Vector3i(1 << 20, 1 << 20, 1 << 20)
	var hi := -lo
	for s in segs:
		var b := _stamp_stone(s) if material == "stone" else _stamp_wall(s)
		lo = lo.min(b[0])
		hi = hi.max(b[1])
		built[s] = true
		sections[s] = _new_section(false, "stone" if material == "stone" else "wood")
		_mark_struct_zone(s)
	_edited(lo, hi)


## Masonry: courses of two stone rows under a mortar bed joint, head joints
## every 0.5 m staggered by 0.2 m per course, each stone in its own tone;
## the same pattern through the whole thickness, so a crater shows joints.
func _stamp_stone(s: Vector3i) -> Array:
	var horiz := s.x == 0
	var b := _box_of(design, seg_rect(s, STONE_HALF), VoxelHouse.BASE_ROW, VoxelHouse.TOP_ROW)
	var a0: int = b[0].x if horiz else b[0].z
	var a1: int = b[1].x if horiz else b[1].z
	var t0: int = b[0].z if horiz else b[0].x
	var t1: int = b[1].z if horiz else b[1].x
	for a in range(a0, a1):
		for r in VoxelHouse.WALL_ROWS:
			var y := VoxelHouse.BASE_ROW + r
			var course := r / 3
			var u := a + (course % 2) * 2
			var joint := r % 3 == 2 or posmod(u, 5) == 0
			var stone: int = STONE_TONES[int(VoxelArt.hash3(floori(u / 5.0), course, s.y, 13) * STONE_TONES.size()) % STONE_TONES.size()]
			for t in range(t0, t1):
				var x := a if horiz else t
				var z := t if horiz else a
				var old := design.get_mat(x, y, z)
				if old != VoxelMat.AIR and old != VoxelMat.BASEBOARD and old != VoxelMat.SILL:
					continue
				if joint:
					var mc := VoxelArt.jitter(MORTAR_TONE, x, y, z, 0.04)
					_put(x, y, z, VoxelMat.MORTAR, mc, mc, 0)
				else:
					var c := VoxelArt.jitter(stone, x, y, z, 0.05)
					_put(x, y, z, VoxelMat.MASONRY, c, c, 0)
	return b


func _stamp_wall(s: Vector3i) -> Array:
	var horiz := s.x == 0
	var b := _box_of(design, seg_rect(s, 0.1), VoxelHouse.FLOOR_ROW, VoxelHouse.TOP_ROW)
	var sign := outer_sign(s)
	var a0: int = b[0].x if horiz else b[0].z
	var a1: int = b[1].x if horiz else b[1].z
	var t0: int = b[0].z if horiz else b[0].x
	var t1: int = b[1].z if horiz else b[1].x
	var outer_t := t1 - 1 if sign > 0 else t0
	var out_dir := (4 if sign > 0 else 5) if horiz else (0 if sign > 0 else 1)
	var in_dir := out_dir ^ 1
	var end_bits := (1 << 1 | 1 << 0) if horiz else (1 << 5 | 1 << 4)
	var pine := VoxelArt.pal(VoxelArt.Slot.STUD)
	var seed := s.x * 7 + s.y * 131 + s.z * 17
	var house := HousePlan.FOOTPRINT.grow(0.15)
	for a in range(a0, a1):
		var u := a - a0
		var stud_col := u == 0 or u == 5 or u == a1 - a0 - 1
		for t in range(t0, t1):
			var x := a if horiz else t
			var z := t if horiz else a
			var outer := t == outer_t
			if design.get_mat(x, VoxelHouse.FLOOR_ROW, z) == VoxelMat.AIR and not house.has_point(VoxelHouse.column_plan(design, x, z)):
				_put(x, VoxelHouse.FLOOR_ROW, z, VoxelMat.STUD, VoxelArt.jitter(0x4e4136, x, 3, z, 0.06), 0x4e4136, 0)
			for r in VoxelHouse.WALL_ROWS:
				var y := VoxelHouse.BASE_ROW + r
				var old := design.get_mat(x, y, z)
				if old != VoxelMat.AIR and old != VoxelMat.BASEBOARD and old != VoxelMat.SILL:
					continue
				var board := r / 2
				var pick := VoxelArt.hash3(board, seed, int(outer), 5) * (6.0 if VoxelArt.hash3(board, seed, 1, 9) > 0.15 else 8.0)
				var bc: int = BOARD_COLORS[int(pick) % BOARD_COLORS.size()]
				bc = VoxelArt.jitter(bc, x, y, z, 0.04)
				if r % 2 == 0:
					bc = VoxelArt.scale(bc, 0.86)     # board seam
				var bits := 0
				if u == 0 or u == a1 - a0 - 1:
					bits |= end_bits
				if outer:
					_put(x, y, z, VoxelMat.SIDING, VoxelArt.jitter(pine, x, y, z, 0.07), bc, bits | (1 << out_dir))
				elif stud_col or r == 0 or r >= VoxelHouse.WALL_ROWS - 2:
					var sc := VoxelArt.jitter(pine, x, y, z, 0.06)
					_put(x, y, z, VoxelMat.STUD, sc, VoxelArt.scale(sc, 0.92), bits | (1 << in_dir))
				else:
					_put(x, y, z, VoxelMat.SIDING, VoxelArt.jitter(pine, x, y, z, 0.07), VoxelArt.scale(bc, 1.08), bits | (1 << in_dir))
	return b


func _put(x: int, y: int, z: int, m: int, c: int, pc: int, pm: int) -> void:
	design.set_voxel(x, y, z, m, c, pc, pm)
	grid.set_voxel(x, y, z, m, c, pc, pm)


## Removes a player-built wall segment (design and current). A stone
## foundation under it stays.
func demolish_wall(s: Vector3i) -> void:
	var stone: bool = sections.get(s, {}).get("material", "") == "stone"
	var rect := seg_rect(s, STONE_HALF if stone else 0.1)
	var b := _box_of(design, rect, VoxelHouse.FLOOR_ROW, VoxelHouse.TOP_ROW)
	var house := HousePlan.FOOTPRINT.grow(0.15)
	for y in range(b[0].y, b[1].y):
		for z in range(b[0].z, b[1].z):
			for x in range(b[0].x, b[1].x):
				if y == VoxelHouse.FLOOR_ROW and house.has_point(VoxelHouse.column_plan(design, x, z)):
					continue
				var i := design.idx(x, y, z)
				if design.mat[i] != 0 and design.mat[i] != VoxelMat.PAVING and (VoxelMat.FLAGS[design.mat[i]] & VoxelMat.F_HARD) == 0:
					design.clear_index(i)
				if grid.mat[i] != 0 and grid.mat[i] != VoxelMat.PAVING and (VoxelMat.FLAGS[grid.mat[i]] & VoxelMat.F_HARD) == 0:
					grid.clear_index(i)
	built.erase(s)
	upgraded.erase(s)
	if sections.has(s) and not sections[s]["orig"]:
		sections.erase(s)
	# a neighbour sharing a corner column gets it back
	for o in built:
		var o_stone: bool = sections.get(o, {}).get("material", "") == "stone"
		if seg_rect(o, STONE_HALF if o_stone else 0.1).intersects(rect.grow(0.05)):
			if o_stone:
				_stamp_stone(o)
			else:
				_stamp_wall(o)
	_edited(b[0], b[1])
	settle(b[0], b[1], true)           # Refinement 01 (S)


## Lays stone foundation tiles (design and current), no checks: 1 m x 1 m
## centred on each segment, two voxel rows of paving slabs (the top row flush
## with the house floor, 3 cm above the yard ground) in 0.5 m flagstones with
## dark joints. Cells that already have a floor are left alone.
func build_foundation(segs: Array) -> void:
	var lo := Vector3i(1 << 20, 1 << 20, 1 << 20)
	var hi := -lo
	for s in segs:
		var b := _box_of(design, seg_rect(s, FOUNDATION_HALF), VoxelHouse.SCREED_ROW, VoxelHouse.FLOOR_ROW)
		for z in range(b[0].z, b[1].z):
			for x in range(b[0].x, b[1].x):
				if design.get_mat(x, VoxelHouse.FLOOR_ROW, z) != VoxelMat.AIR:
					continue
				var p := VoxelHouse.column_plan(design, x, z)
				var xi := roundi(p.x * 10.0)
				var zi := roundi(p.y * 10.0)
				var slab: int = PAVING_TONES[int(VoxelArt.hash3(floori(p.x * 2.0), floori(p.y * 2.0), 3, 29) * PAVING_TONES.size()) % PAVING_TONES.size()]
				var c := VoxelArt.jitter(slab, x, 0, z, 0.05)
				if posmod(xi, 5) == 0 or posmod(zi, 5) == 0:
					c = VoxelArt.jitter(PAVING_JOINT, x, 0, z, 0.06)
				_put(x, VoxelHouse.FLOOR_ROW, z, VoxelMat.PAVING, c, c, 0)
				var under := VoxelArt.scale(c, 0.8)
				_put(x, VoxelHouse.SCREED_ROW, z, VoxelMat.PAVING, under, under, 0)
		lo = lo.min(b[0])
		hi = hi.max(b[1])
		foundations[s] = true
	if hi.x > lo.x:
		_edited(lo, hi)
	_foundations_changed()


## Takes up a foundation tile (design and current); columns another tile
## still covers stay.
func remove_foundation(s: Vector3i) -> void:
	if not foundations.has(s):
		return
	foundations.erase(s)
	var b := _box_of(design, seg_rect(s, FOUNDATION_HALF), VoxelHouse.SCREED_ROW, VoxelHouse.FLOOR_ROW)
	for z in range(b[0].z, b[1].z):
		for x in range(b[0].x, b[1].x):
			var p := VoxelHouse.column_plan(design, x, z)
			var keep := false
			for o in foundations:
				if seg_rect(o, FOUNDATION_HALF).has_point(p):
					keep = true
					break
			if keep:
				continue
			for y in [VoxelHouse.SCREED_ROW, VoxelHouse.FLOOR_ROW]:
				var i := design.idx(x, y, z)
				if design.mat[i] == VoxelMat.PAVING:
					design.clear_index(i)
				if grid.mat[i] == VoxelMat.PAVING:
					grid.clear_index(i)
	_edited(b[0], b[1])
	_foundations_changed()


func _foundation_rects() -> Array:
	var out := []
	for s in foundations:
		out.append(seg_rect(s, FOUNDATION_HALF))
	return out


## No grass or shrubs grow through paving.
func _foundations_changed() -> void:
	if yard != null:
		yard.set_tuft_avoid(_foundation_rects())
	_hide_covered_bushes()


func _hide_covered_bushes() -> void:
	var rects := _foundation_rects()
	for k in BUSHES.size():
		var b := get_node_or_null("Bush_%d" % k) as Node3D
		if b == null:
			continue
		var on := false
		for r in rects:
			if (r as Rect2).grow(0.3).has_point(BUSHES[k]):
				on = true
		b.visible = not on


## Fraction (0..1) of a foundation tile's columns that already have a floor
## (the house floor or paving).
func floor_coverage(s: Vector3i) -> float:
	var b := _box_of(design, seg_rect(s, FOUNDATION_HALF), VoxelHouse.FLOOR_ROW, VoxelHouse.FLOOR_ROW)
	var n := 0
	var on := 0
	for z in range(b[0].z, b[1].z):
		for x in range(b[0].x, b[1].x):
			n += 1
			if design.get_mat(x, VoxelHouse.FLOOR_ROW, z) != VoxelMat.AIR:
				on += 1
	return float(on) / maxf(1.0, n)


## The player-laid foundation tile under plan point p, or Vector3i(-1, 0, 0).
func foundation_at(p: Vector2) -> Vector3i:
	for s in foundations:
		if seg_rect(s, FOUNDATION_HALF).has_point(p):
			return s
	return Vector3i(-1, 0, 0)


## Cuts a 1 m opening (design and current): a doorway 2.1 m high, or the full
## wall height (demolishing an original wall). Recorded as a door-like gap.
func cut_opening(s: Vector3i, full_height := false) -> void:
	var b := _box_of(design, seg_rect(s, SECTION_ACROSS), VoxelHouse.BASE_ROW, VoxelHouse.TOP_ROW if full_height else VoxelHouse.BASE_ROW + DOOR_ROWS - 1)
	for y in range(b[0].y, b[1].y):
		for z in range(b[0].z, b[1].z):
			for x in range(b[0].x, b[1].x):
				var i := design.idx(x, y, z)
				if design.mat[i] != 0:
					design.clear_index(i)
				if grid.mat[i] != 0:
					grid.clear_index(i)
	var found := false
	for op in openings:
		if op["axis"] == s.x and op["line"] == s.y and op["from"] <= s.z and op["to"] >= s.z + 1:
			found = true
	if not found:
		openings.append({"axis": s.x, "line": s.y, "from": float(s.z), "to": float(s.z + 1), "orig": false})
		_index_openings()
	built.erase(s)
	upgraded.erase(s)
	_edited(b[0], b[1])
	settle(b[0], b[1], true)           # Refinement 01 (S): lintels, sills, window remains, doors fall


## Iron plating (Experiment 002 "metal sheathing", the same METAL_SHEET
## voxels): the outermost structural voxel of every (along, row) of
## the section becomes sheet metal in the design; standing voxels in the
## current grid change with it (missing ones come back as metal on repair).
func upgrade_section(s: Vector3i) -> void:
	var horiz := s.x == 0
	var b := _box_of(design, seg_rect(s, SECTION_ACROSS), VoxelHouse.BASE_ROW, VoxelHouse.TOP_ROW)
	var sign := outer_sign(s)
	var a0: int = b[0].x if horiz else b[0].z
	var a1: int = b[1].x if horiz else b[1].z
	var t0: int = b[0].z if horiz else b[0].x
	var t1: int = b[1].z if horiz else b[1].x
	var out_dir := (4 if sign > 0 else 5) if horiz else (0 if sign > 0 else 1)
	var ts := range(t1 - 1, t0 - 1, -1) if sign > 0 else range(t0, t1)
	for y in range(b[0].y, b[1].y):
		for a in range(a0, a1):
			for t in ts:
				var x: int = a if horiz else t
				var z: int = t if horiz else a
				var i := design.idx(x, y, z)
				if not VoxelMat.is_struct(design.mat[i]):
					continue
				# riveted iron plates 0.5 m x 0.6 m: a tone per plate, dark
				# seams, light rivets inside the corners, rust runs near the ground
				var row := y - VoxelHouse.BASE_ROW
				var pa := posmod(a, 5)
				var pr := posmod(row, 6)
				var corr: int = PLATE_TONES[int(VoxelArt.hash3(floori(a / 5.0), row / 6, s.y, 23) * PLATE_TONES.size()) % PLATE_TONES.size()]
				if pa == 0 or pr == 0:
					corr = VoxelArt.scale(corr, 0.8)
				elif (pa == 1 or pa == 4) and (pr == 1 or pr == 5):
					corr = VoxelArt.scale(corr, 1.3)
				var rust := VoxelArt.hash3(a, row / 3, s.y, 21)
				if (row <= 1 and rust > 0.3) or rust > 0.94:
					corr = VoxelArt.mix(corr, 0x7b4a2c, 0.4)
				var pc := VoxelArt.jitter(corr, x, y, z, 0.03)
				var pm := design.pmask[i] | (1 << out_dir)
				var body := VoxelArt.jitter(0xa9aeb2, x, y, z, 0.03)
				design.set_voxel(x, y, z, VoxelMat.METAL_SHEET, body, pc, pm)
				if grid.mat[i] != 0:
					grid.set_voxel(x, y, z, VoxelMat.METAL_SHEET, body, pc, pm)
				break
	upgraded[s] = true
	_edited(b[0], b[1])


# --- queries ---------------------------------------------------------------------------

func interactables() -> Array:
	var out := []
	if bed != null:
		out.append(bed)
	for o in objects:
		if o.interact_prompt() != "":
			out.append(o)
	return out


## Where the player stands to sleep (the foot of the bed); also where the exit rule starts.
func bed_position() -> Vector3:
	for f in HousePlan.FURNITURE:
		if f["type"] == "bed":
			var r: Rect2 = f["rect"]
			return Vector3(r.get_center().x, 0, r.end.y + 0.4)
	return Vector3(2.0, 0, 2.7)


func count_objects(kind: String) -> int:
	var n := 0
	for o in objects:
		if o.kind == kind:
			n += 1
	return n


## Dev: design -> current everywhere, every object back to full HP.
func repair_all() -> void:
	grid.mat = design.mat.duplicate()
	grid.col = design.col.duplicate()
	grid.pcol = design.pcol.duplicate()
	grid.pmask = design.pmask.duplicate()
	grid.solid_count = design.solid_count
	for o in objects:
		o.restore()
	# Experiment 004: furniture back to intact meshes, a fuse box back on its wall
	if furniture != null:
		furniture.restore_all()
		_update_light_hosts()
	if count_objects("fuse_box") == 0:
		_spawn_object("fuse_box", FUSE_BOX_AT, FUSE_BOX_ROT, false)
		_index_objects()
		power_changed.emit()
	chunks.mark_dirty(Vector3i.ZERO, Vector3i(grid.sx, grid.sy, grid.sz))
	_full_nav()
	for s in sections:
		_count_section(s)
	structure_changed.emit()


func damage_summary() -> Dictionary:
	var damaged := 0
	for o in objects:
		if o.hp < o.max_hp:
			damaged += 1
	var furn := furniture.voxels_in_grid() if furniture != null else 0
	var broken := furniture.count(HouseFurniture.DAMAGED) + furniture.count(HouseFurniture.DESTROYED) if furniture != null else 0
	return {"missing_voxels": maxi(design.solid_count - (grid.solid_count - furn), 0), "damaged_objects": damaged, "damaged_furniture": broken}


func is_blocked(p: Vector2) -> bool:
	var space := get_world_3d().direct_space_state
	var y := 1.0
	for seg in [[Vector3(p.x, y, p.y - 0.25), Vector3(p.x, y, p.y + 0.25)], [Vector3(p.x - 0.25, y, p.y), Vector3(p.x + 0.25, y, p.y)]]:
		for pair in [[seg[0], seg[1]], [seg[1], seg[0]]]:
			var q := PhysicsRayQueryParameters3D.create(pair[0], pair[1], 1 | 2 | 16)
			if not space.intersect_ray(q).is_empty():
				return true
	return false


## True if a player or enemy body overlaps the plan rect (physics query).
func bodies_in(rect: Rect2) -> bool:
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(rect.size.x, 0.01), 1.4, maxf(rect.size.y, 0.01))
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.transform = Transform3D(Basis(), Vector3(rect.get_center().x, 0.85, rect.get_center().y))
	q.collision_mask = 4 | 8
	return not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## True if a blocking furniture piece or yard prop overlaps the plan rect
## (Experiment 004: destroyed and removed furniture no longer counts).
func furniture_in(rect: Rect2) -> bool:
	for f in (HousePlan.FURNITURE + HousePlan.PROPS if furniture == null else HousePlan.PROPS):
		if f["blocks"] and (f["rect"] as Rect2).intersects(rect):
			return true
	for b in static_blockers:          # Refinement 01: fixed fittings (the fireplace) and their clearance
		if (b["reserve"] as Rect2).intersects(rect):
			return true
	return furniture != null and furniture.blocks_rect(rect)


# --- Refinement 01: static blockers ---------------------------------------------------

## Fixed fittings that aren't HousePlan furniture (the fireplace): their
## footprint `rect` is solid for navigation (like furniture), and `reserve`
## (the footprint plus the space in front that must stay clear to use it) is
## refused by construction, through furniture_in(). Game helpers add them
## after the world is built or loaded; they aren't saved.
var static_blockers: Array = []


func add_static_blocker(rect: Rect2, reserve := Rect2()) -> void:
	static_blockers.append({"rect": rect, "reserve": reserve if reserve.has_area() else rect})
	_mark_static_blocker(rect)


func _mark_static_blocker(rect: Rect2) -> void:
	if nav == null or _static_solid.is_empty():
		return
	for c in nav.cells_in_rect(rect.grow(-0.05)):
		var i: int = c.y * nav.size.x + c.x
		if i >= 0 and i < _static_solid.size():
			_static_solid[i] = 1
	_recompute_nav(rect.grow(0.3))


# --- Experiment 004: furniture, power, reinforcement -----------------------------------

## True while the furniture piece with this HousePlan id (e.g. "fridge",
## "sink_counter") is intact or only damaged; false once destroyed or
## removed, or for an unknown id. Always true in Version A (voxel furniture).
func furniture_ok(id: String) -> bool:
	if furniture == null:
		return true
	return furniture.ok(id)


## Demolishes a furniture piece (build mode). Returns what it gives back.
func demolish_furniture(id: String) -> Dictionary:
	if furniture == null or not furniture.pieces.has(id):
		return {}
	var got := furniture.salvage(id)
	furniture.remove(id)
	_update_light_hosts()
	return got


## The fuse box that is still standing, or null.
func fuse_box() -> WorldObject:
	for o in objects:
		if o.kind == "fuse_box":
			return o
	return null


## Flips the main power switch.
func toggle_mains(o: WorldObject) -> void:
	if o == null or o.kind != "fuse_box":
		return
	o.set_mains(not o.mains_on)
	Sfx.play("door/close", Vector3(o.pos.x, 1.4, o.pos.y))
	power_changed.emit()


## Reinforce (build mode): a door becomes `mat` ("iron" reinforced, "metal").
func reinforce_object(o: WorldObject, mat: String) -> void:
	o.set_mat(mat)
	structure_changed.emit()


## The outward-facing quarter turn of a door on a house wall.
static func _outward_rot(c: Vector2, horiz: bool) -> int:
	var mid := HousePlan.FOOTPRINT.get_center()
	if horiz:
		return 2 if c.y > mid.y else 0
	return 1 if c.x > mid.x else 3


# --- Refinement 01 (S): support -----------------------------------------------------------

## Margin (voxels) around a change where settle() starts looking for what it
## left hanging (the search itself follows a piece wherever it goes).
const SETTLE_MARGIN := 2
const SETTLE_QUEUE := 24
## Wall-mounted objects and the rows (m) of wall they need: [from, to, min voxels].
const MOUNTS := {"door": [0.0, 2.6, 12], "boards": [0.85, 2.15, 12], "fuse_box": [0.9, 2.0, 8]}


## Runs what structural changes left to do: settle() over the damage of the
## last frame, then the support zones. Called by _process (once per frame);
## tests call it to skip the frame.
func process_structure() -> void:
	var boxes := _settle_boxes
	_settle_boxes = []
	for b in boxes:
		settle(b[0], b[1])
	if support != null:
		support.process()


## Queues a damaged box for the next settle(); overlapping boxes merge (so a
## bite and a shot at the same spot settle once, far-apart ones separately).
func _queue_settle(lo: Vector3i, hi: Vector3i) -> void:
	for b in _settle_boxes:
		if lo.x <= b[1].x and b[0].x <= hi.x and lo.y <= b[1].y and b[0].y <= hi.y and lo.z <= b[1].z and b[0].z <= hi.z:
			b[0] = (b[0] as Vector3i).min(lo)
			b[1] = (b[1] as Vector3i).max(hi)
			return
	if _settle_boxes.size() >= SETTLE_QUEUE:
		var last: Array = _settle_boxes[_settle_boxes.size() - 1]
		last[0] = (last[0] as Vector3i).min(lo)
		last[1] = (last[1] as Vector3i).max(hi)
		return
	_settle_boxes.append([lo, hi])


## Issue 3: voxels near cells [lo, hi) left without a chain of solid voxels
## to the ground (VoxelSupport) fall: removed with falling debris, and the
## doors, window boards and fuse box whose wall went fall too.
## `design_too` (demolition): the design loses the same hanging pieces, so
## repair can't put them back in mid-air. Returns the voxels dropped.
func settle(lo: Vector3i, hi: Vector3i, design_too := false) -> int:
	if grid == null or hi.x < lo.x:
		return 0
	lo = (lo - Vector3i.ONE * SETTLE_MARGIN).max(Vector3i(0, VoxelHouse.BASE_ROW + 1, 0))
	hi = hi + Vector3i.ONE * SETTLE_MARGIN
	for k in range(_settle_boxes.size() - 1, -1, -1):          # this pass covers what was queued inside it
		var b: Array = _settle_boxes[k]
		if b[0].x >= lo.x and b[0].y >= lo.y and b[0].z >= lo.z and b[1].x <= hi.x and b[1].y <= hi.y and b[1].z <= hi.z:
			_settle_boxes.remove_at(k)
	var n := 0
	if design_too:
		var dl := VoxelSupport.unsupported(design, lo, hi)
		for i in dl:
			design.clear_index(i)
		if not dl.is_empty():
			var rect := _plan_rect(lo, hi)
			for s in sections:
				if seg_rect(s, 0.3, 0.2).intersects(rect):
					_count_section(s)
	var cells := VoxelSupport.unsupported(grid, lo, hi)
	if not cells.is_empty():
		var ch := VoxelCarver.empty_change()
		for i in cells:
			if grid.mat[i] != 0:
				VoxelCarver._remove(grid, i, ch)
		n = cells.size()
		settled += n
		_settling = true
		_apply_damage(ch)
		_settling = false
		chunks.flush(BLAST_MESH_BUDGET_MS)
		if fx != null:
			HouseSupport._fall_fx(fx, grid, ch, 0.0)
		if n >= 20:
			Sfx.play("structure/crumble", grid.center((ch["lo"] + ch["hi"]) / 2))
	_check_mounts(_plan_rect(lo, hi).grow(0.3))
	return n


## Wall-mounted objects in plan rect `rect` whose wall is gone fall (destroyed,
## with debris; object_destroyed tells the game).
func _check_mounts(rect: Rect2) -> void:
	for o in objects_in(rect).duplicate():
		if MOUNTS.has(o.kind) and not is_mounted(o):
			damage_object(o, o.hp + 1, Vector3(o.pos.x, 2.5, o.pos.y), true)


## True if a door, window boards or the fuse box still has wall to hang on
## (structure around its segment's ends and lintel, or behind it).
func is_mounted(o: WorldObject) -> bool:
	if not MOUNTS.has(o.kind):
		return true
	var m: Array = MOUNTS[o.kind]
	var rect := seg_rect(o.seg, 0.22, 0.15) if WorldObject.is_segment_kind(o.kind) else o.footprint().grow(0.3)
	var y0 := o.position.y - grid.origin.y      # the storey's floor in grid metres (LevelWorld objects stand at base_y)
	var rows := Vector2i(int(floor((y0 + float(m[0])) / grid.vs)), int(floor((y0 + float(m[1])) / grid.vs - 0.01)))
	var b := _box_of(grid, rect, maxi(rows.x, VoxelHouse.BASE_ROW), mini(rows.y, VoxelHouse.TOP_ROW))
	var st := VoxelMat.STRUCT
	var n := 0
	for y in range(b[0].y, b[1].y):
		for z in range(b[0].z, b[1].z):
			for x in range(b[0].x, b[1].x):
				n += st[grid.mat[grid.idx(x, y, z)]]
				if n >= int(m[2]):
					return true
	return false


## True if wall (structure) stands within `reach` m of plan point p at height
## h m above this storey's floor: wall switches and wall lights hang on it.
func wall_at(p: Vector2, h: float, reach := 0.25) -> bool:
	if grid == null:
		return true
	var row := VoxelHouse.row_of(h)
	return grid.any_struct_in(p - Vector2.ONE * reach, p + Vector2.ONE * reach, row - 1, row + 1)


## True if the ceiling (the roof) above plan point p still stands.
func ceiling_at(p: Vector2) -> bool:
	return support == null or support.roof_intact_at(p)


## Build mode's demolish preview for wall section s: "" or what it carries.
func bearing_warning(s: Vector3i) -> String:
	return support.demolish_warning(self, s) if support != null else ""
