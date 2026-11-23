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
## Docs: docs/experiment-002/world.md.

signal structure_changed
signal object_destroyed(kind: String, at: Vector3)

const SURFACE_SHADER := preload("res://src/voxel/shaders/voxel_surface.gdshader")
const GLASS_SHADER := preload("res://src/voxel/shaders/voxel_glass.gdshader")
const BED_SCRIPT := preload("res://src/world/bed_interactable.gd")

const SAVE_VERSION := 1
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
const BUSHES := [Vector2(-1.2, 0.6), Vector2(-1.0, 7.6), Vector2(1.0, 10.2), Vector2(8.6, 10.0), Vector2(13.2, 10.1),
	Vector2(15.3, 3.4), Vector2(6.5, -1.1), Vector2(12.8, -1.3), Vector2(-3.6, 4.2), Vector2(17.6, 1.2)]
const BOARD_COLORS := [0x8a6a4a, 0x7b5d40, 0x96785a, 0x6e5640, 0x857565, 0x7f6a55, 0x5f6b6a, 0x8c4a3a]

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
var upgraded := {}             ## sheathed sections (seg -> true)
var openings: Array = []       ## door-like gaps: {"axis", "line", "from", "to", "orig"}
var props: Array = []          ## tall meshes the cutaway hides: {"node", "centre", "half", "body", "cut"}
var night_lights: Array = []   ## {"node", "light", "base", "phase", "geos"}
var stats := {"build_ms": 0.0, "save_ms": 0.0, "load_ms": 0.0, "nav_ms": 0.0}

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
	_build(p.copy(), p.copy(), objs, [], [], [])


# --- persistence ----------------------------------------------------------------------

## Versioned save: both grids as voxel diffs against the pristine house, plus
## objects, built and sheathed sections and cut openings (docs: world.md).
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
	}
	stats["save_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	return d


## Restores a saved house exactly (instead of build_new). Returns false, having
## built nothing, if the data is invalid or from another house layout; the
## caller can then report it and call build_new().
func load_data(d: Dictionary) -> bool:
	var t0 := Time.get_ticks_usec()
	if typeof(d.get("version")) != TYPE_INT or d["version"] != SAVE_VERSION:
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
	if objs == null or b == null or u == null or cut == null:
		push_warning("HouseWorld: damaged object or section data in the save")
		return false
	var g_design := p.copy()
	VoxelDiff.apply(g_design, dd)
	var g_cur := p.copy()
	VoxelDiff.apply(g_cur, dc)
	_build(g_design, g_cur, objs, b, u, cut)
	stats["load_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
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
		var x: Variant = e.get("x")
		var y: Variant = e.get("y")
		if typeof(x) not in [TYPE_FLOAT, TYPE_INT] or typeof(y) not in [TYPE_FLOAT, TYPE_INT]:
			return null
		if not is_finite(float(x)) or not is_finite(float(y)) or not HousePlan.YARD.has_point(Vector2(x, y)):
			return null
		var r: Variant = e.get("rot")
		var hp: Variant = e.get("hp")
		if typeof(r) != TYPE_INT or r < 0 or r > 3 or typeof(hp) != TYPE_INT or hp < 1 or hp > WorldObject.DEFS[k]["hp"]:
			return null
		out.append({"kind": k, "x": float(x), "y": float(y), "rot": r, "hp": hp, "open": e.get("open") == true, "built": e.get("built") == true})
	return out


# --- building the scene ---------------------------------------------------------------

func _build(g_design: VoxelGrid, g_cur: VoxelGrid, objs: Array, built_list: Array, upgraded_list: Array, cut_list: Array) -> void:
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
	chunks = VoxelWorld.new()
	chunks.name = "VoxelWorld"
	chunks.setup(grid, surface_mat, glass_mat)
	add_child(chunks)
	chunks.build_all()
	nav = GridNav.new()
	_static_solid.resize(nav.size.x * nav.size.y)
	_static_solid.fill(0)
	for f in HousePlan.FURNITURE + HousePlan.PROPS:
		if f["blocks"]:
			for c in nav.cells_in_rect(f["rect"]):
				_static_solid[c.y * nav.size.x + c.x] = 1
	yard = VoxelYard.new()
	yard.name = "Yard"
	yard.demo = self
	yard.voxel_props = voxel_furniture
	add_child(yard)
	fx = VoxelFx.new()
	fx.grid = grid
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
			sections[Vector3i(0 if horiz else 1, int(a.y) if horiz else int(a.x), s)] = {"orig": true, "design": 0, "current": 0}
	for o in HousePlan.OPENINGS:
		if o["kind"] == "door":
			var w := HousePlan.wall_by_id(o["wall"])
			var horiz := HousePlan.is_horizontal(w)
			openings.append({"axis": 0 if horiz else 1, "line": int(w["a"].y if horiz else w["a"].x), "from": float(o["from"]), "to": float(o["to"]), "orig": true})
	for e in built_list:
		var s := Vector3i(int(e[0]), int(e[1]), int(e[2]))
		built[s] = true
		if not sections.has(s):
			sections[s] = {"orig": false, "design": 0, "current": 0}
		_mark_struct_zone(s)
	for e in upgraded_list:
		upgraded[Vector3i(int(e[0]), int(e[1]), int(e[2]))] = true
	for e in cut_list:
		openings.append({"axis": int(e[0]), "line": int(e[1]), "from": float(e[2]), "to": float(e[3]), "orig": false})
	_index_openings()
	for e in objs:
		_spawn_object(e["kind"], Vector2(e["x"], e["y"]), e["rot"], e.get("built", true), e["hp"], e["open"])
	_index_objects()
	_full_nav()
	for s in sections:
		_count_section(s)
	bed = BED_SCRIPT.new()
	bed.name = "Bed"
	bed.position = bed_position()
	add_child(bed)
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
	for f in HousePlan.FURNITURE + HousePlan.PROPS:
		var r: Rect2 = f["rect"]
		var h: float = f["height"]
		var is_yard: bool = f["room"] == "yard"
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


func night_amount() -> float:
	return lighting.night_amount if lighting != null else 0.0


func _process(delta: float) -> void:
	_t += delta
	var n := night_amount()
	for l in night_lights:
		var o: OmniLight3D = l["light"]
		var ph: float = l["phase"]
		var f := 1.0 + 0.07 * sin(_t * 9.1 + ph) + 0.05 * sin(_t * 23.7 + ph * 1.7) + 0.03 * sin(_t * 41.0 + ph * 0.3)
		o.light_energy = l["base"] * n * f
		o.visible = n > 0.02
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
		var cut := _in_cut(Vector3(o.pos.x, h * 0.5, o.pos.y), 0.5)
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


func aim_ray(from: Vector3, dir: Vector3) -> Vector3:
	var best := 200.0
	var vh := grid.raycast(from, dir, best, _bullet_skip, is_cut)
	if not vh.is_empty():
		best = vh["dist"]
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * best, 1 | 8)
	q.exclude = _hidden_bodies
	var ph := get_world_3d().direct_space_state.intersect_ray(q)
	if not ph.is_empty():
		best = from.distance_to(ph["position"])
	if dir.y < -0.001:
		var tg := -from.y / dir.y
		if tg < best:
			best = tg
	return from + dir * best


# --- shooting --------------------------------------------------------------------------

## One bullet. Returns {"kind": "voxel"|"enemy"|"body"|"ground"|"none", "pos", "collider"}.
## Doors, crates, collectors and tall furniture stop bullets (impact, no
## damage); barricades let them pass between the planks.
func shoot(origin: Vector3, dir: Vector3, exclude: Array, muzzle := Vector3.INF) -> Dictionary:
	_shots += 1
	dir = dir.normalized()
	var best := Tuning.SHOT_RANGE
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
		"ground":
			fx.ground_hit(hit, dir)
			Sfx.play("impact/ground", hit)
	fx.tracer(muzzle if muzzle != Vector3.INF else origin, hit)
	return {"kind": kind, "pos": hit, "collider": col}


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
		ch = VoxelCarver.carve_sphere(grid, pos + dir * 0.07, r, _shots * 7919 + c.x, dir, stretch, damage_quantum)
	_apply_damage(ch)
	fx.impact(VoxelMat.IMPACT[m], pos, vh["normal"], dir, ch)
	Sfx.play(IMPACT_SOUND.get(VoxelMat.IMPACT[m], "impact/plaster"), pos)


## Damage only removes voxels, so only WALL cells can change (to OPEN).
func _apply_damage(ch: Dictionary) -> void:
	var cells: PackedInt32Array = ch["cells"]
	if cells.is_empty():
		return
	chunks.apply_change(ch)
	var mats: PackedByteArray = ch["mats"]
	for k in cells.size():
		if VoxelMat.is_struct(mats[k]):
			var s: Variant = _section_of_index(cells[k])
			if s != null:
				sections[s]["current"] -= 1
	if _recompute_nav(_plan_rect(ch["lo"], ch["hi"]).grow(GridNav.CELL), true):
		Sfx.play("structure/crumble", grid.center((ch["lo"] + ch["hi"]) / 2))
	structure_changed.emit()


# --- enemies ---------------------------------------------------------------------------

## An enemy swing at nav cell `target`: damages a door or barricade standing
## there, otherwise bites the voxels still blocking the passage.
func enemy_strike(attacker_pos: Vector3, target: Vector2) -> void:
	var o: WorldObject = _obj_cells.get(nav.cell_of(target))
	if o != null and o.bashable():
		damage_object(o, Tuning.ENEMY_WALL_DAMAGE, attacker_pos)
		return
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
	var r := BITE_RADIUS * (SHEET_CARVE + 0.2 if m == VoxelMat.METAL_SHEET else 1.0)
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

func _spawn_object(kind: String, p: Vector2, rot: int, is_built: bool, hp := -1, is_open := false) -> WorldObject:
	var o := WorldObject.new()
	o.setup(kind, p, rot, self, is_built)
	if hp > 0:
		o.hp = mini(hp, o.max_hp)
	o.open = is_open
	add_child(o)
	objects.append(o)
	return o


## Places an object (no validity checks: BuildMode validates). Updates nav.
func place_object(kind: String, p: Vector2, rot: int, is_built := true) -> WorldObject:
	var o := _spawn_object(kind, p, rot, is_built)
	_index_objects()
	_recompute_nav(o.footprint().grow(GridNav.CELL))
	structure_changed.emit()
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


## Damages a door or barricade; destroyed objects break into debris.
func damage_object(o: WorldObject, n: int, from := Vector3.INF) -> void:
	var at := Vector3(o.pos.x, 1.0, o.pos.y)
	var dir := Vector3(at.x - from.x, 0, at.z - from.z).normalized() if from != Vector3.INF else Vector3.FORWARD
	var wood := VoxelArt.to_color(0x7a5c40)
	for k in 5:
		fx.debris(at + Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.5, 0.4), 0), dir * 1.5 + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.5, 2.0), _rng.randf_range(-1, 1)), wood, 0.7)
	Sfx.play("door/bash", at)
	if not o.take_damage(n):
		return
	for k in 26:
		var c := VoxelArt.to_color([0x7a5c40, 0x8c6c4c, 0x5e4a36, 0x9a8466][k % 4])
		fx.debris(at + Vector3(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.9, 0.8), _rng.randf_range(-0.1, 0.1)),
			dir * 2.0 + Vector3(_rng.randf_range(-1.5, 1.5), _rng.randf_range(0.5, 3.0), _rng.randf_range(-1.5, 1.5)), c, _rng.randf_range(0.8, 1.6))
	fx.impact(VoxelMat.Impact.WOOD, at, -dir, dir, {})
	Sfx.play("structure/break", at)
	var kind := o.kind
	var where := Vector3(o.pos.x, 0, o.pos.y)
	remove_object(o)
	object_destroyed.emit(kind, where)


## Opens or closes a door. Returns "" or the reason it can't close.
func toggle_door(o: WorldObject) -> String:
	if o.kind != "door":
		return ""
	if o.open and bodies_in(o.footprint().grow(0.05)):
		return "Something is in the way."
	set_door_open(o, not o.open)
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


func _count_section(s: Vector3i) -> void:
	if not sections.has(s):
		return
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
	}


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
				if grid.mat[i] != m or grid.col[i] != design.col[i] or grid.pcol[i] != design.pcol[i] or grid.pmask[i] != design.pmask[i]:
					if m != 0 and grid.mat[i] != m:
						n += 1
					grid.set_voxel(x, y, z, m, design.col[i], design.pcol[i], design.pmask[i])
	return n


## After any construction edit of cells [lo, hi): meshes and collision now,
## nav for the area, section counts.
func _edited(lo: Vector3i, hi: Vector3i) -> void:
	chunks.mark_dirty(lo - Vector3i.ONE, hi + Vector3i.ONE)
	chunks.flush(40.0)
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


## Builds a wooden wall on segments (design and current), no checks:
## two voxels thick on the line, full height; outer boards, inner boards with
## studs every 0.5 m; a sole plate where it stands on the ground.
func build_walls(segs: Array) -> void:
	var lo := Vector3i(1 << 20, 1 << 20, 1 << 20)
	var hi := -lo
	for s in segs:
		var b := _stamp_wall(s)
		lo = lo.min(b[0])
		hi = hi.max(b[1])
		built[s] = true
		if not sections.has(s):
			sections[s] = {"orig": false, "design": 0, "current": 0}
		_mark_struct_zone(s)
	_edited(lo, hi)


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


## Removes a player-built wall segment (design and current).
func demolish_wall(s: Vector3i) -> void:
	var rect := seg_rect(s, 0.1)
	var b := _box_of(design, rect, VoxelHouse.FLOOR_ROW, VoxelHouse.TOP_ROW)
	var house := HousePlan.FOOTPRINT.grow(0.15)
	for y in range(b[0].y, b[1].y):
		for z in range(b[0].z, b[1].z):
			for x in range(b[0].x, b[1].x):
				if y == VoxelHouse.FLOOR_ROW and house.has_point(VoxelHouse.column_plan(design, x, z)):
					continue
				var i := design.idx(x, y, z)
				if design.mat[i] != 0 and (VoxelMat.FLAGS[design.mat[i]] & VoxelMat.F_HARD) == 0:
					design.clear_index(i)
				if grid.mat[i] != 0 and (VoxelMat.FLAGS[grid.mat[i]] & VoxelMat.F_HARD) == 0:
					grid.clear_index(i)
	built.erase(s)
	upgraded.erase(s)
	if sections.has(s) and not sections[s]["orig"]:
		sections.erase(s)
	# a neighbour sharing a corner column gets it back
	for o in built:
		if seg_rect(o, 0.1).intersects(rect.grow(0.05)):
			_stamp_wall(o)
	_edited(b[0], b[1])


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


## Metal sheathing: the outermost structural voxel of every (along, row) of
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
				var corr := 0x7d858a if (a % 2 == 0) else 0x666e73      # corrugation
				var rust := VoxelArt.hash3(a / 2, y / 3, s.y, 21)
				if rust > 0.82 or (y <= VoxelHouse.BASE_ROW + 2 and rust > 0.4):
					corr = VoxelArt.mix(corr, 0x7b4a2c, 0.55)
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
	return {"missing_voxels": maxi(design.solid_count - grid.solid_count, 0), "damaged_objects": damaged}


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


## True if a blocking furniture piece or yard prop overlaps the plan rect.
func furniture_in(rect: Rect2) -> bool:
	for f in HousePlan.FURNITURE + HousePlan.PROPS:
		if f["blocks"] and (f["rect"] as Rect2).intersects(rect):
			return true
	return false


## The outward-facing quarter turn of a door on a house wall.
static func _outward_rot(c: Vector2, horiz: bool) -> int:
	var mid := HousePlan.FOOTPRINT.get_center()
	if horiz:
		return 2 if c.y > mid.y else 0
	return 1 if c.x > mid.x else 3
