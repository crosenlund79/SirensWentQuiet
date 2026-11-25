class_name HouseFurniture
extends RefCounted
## Experiment 004: the house's furniture as gameplay objects (owned by
## HouseWorld, mesh-furniture mode only). Lifecycle of each HousePlan
## FURNITURE piece (rugs stay floor voxels):
##   intact    - one PropKit mesh and one box collider (as before): cheap
##               static geometry, no per-voxel anything.
##   damaged   - on its first damage the piece is voxelised into the house's
##               current grid (VoxelFurniture, the Experiment 001 Version A
##               builder), the mesh is freed and the collider drops to the
##               low-obstacle layer (bullets now reach the voxels). Shots,
##               bites and blasts carve it like walls; debris flies in its
##               own colours. Only damaged pieces have voxels.
##   destroyed - at 0 HP, or with less than KEEP_FRACTION of its voxels
##               left: the remaining voxels go (a capped burst of debris),
##               the collider goes, and a low "rubble" mesh (PropKit, no
##               collision) marks the spot. Navigation opens.
##   removed   - demolished by the player (build mode, key 9): nothing left.
## Blocking pieces are WALL cells for navigation while they stand, so
## enemies bash through furniture in their way (HouseWorld.enemy_strike) and
## prefer to go around it. HP and salvage per type are in TYPES. The state is
## saved as {id: [state, hp, voxels]} for pieces that aren't intact; the
## voxels of damaged pieces travel in the world's current-grid diff.
## Exp 005 (F): storage pieces (FurnitureStorage.TYPES: fridge, counters and
## island, wardrobe, dresser, nightstands, bookshelf, shelves, boxes, vanity)
## hold items ("items", saved by the world as "storage"); E at a StorageSpot in
## front of one opens it. Destroying or demolishing a piece drops what it held
## into a loot pile (HouseWorld.drop_loot). take_out() lifts a piece away for
## the Move tool (no salvage, no pile: the contents travel with it).

enum { INTACT, DAMAGED, DESTROYED, REMOVED }
const STATE_NAMES := ["intact", "damaged", "destroyed", "removed"]
## A damaged piece with fewer voxels than this fraction of its own is destroyed.
const KEEP_FRACTION := 0.4
## Bullet damage per hit; enemy blows do ENEMY_WALL_DAMAGE x strength x BLOW.
const SHOT_DAMAGE := 1
const BLOW := 2.0
const RUBBLE_HEIGHT := 0.18
const DEBRIS_CAP := 60

## Per furniture type: hit points, salvage (what demolishing an intact piece
## gives back: about half of what it is made of) and the rubble's material.
const TYPES := {
	"sofa": {"hp": 16, "salvage": {"wood": 2, "nails": 3, "scrap": 1}, "mat": "fabric"},
	"armchair": {"hp": 10, "salvage": {"wood": 1, "nails": 2, "scrap": 1}, "mat": "fabric"},
	"tv_stand": {"hp": 10, "salvage": {"wood": 2, "nails": 2, "scrap": 1}, "mat": "wood"},
	"coffee_table": {"hp": 8, "salvage": {"wood": 2, "nails": 2}, "mat": "wood"},
	"floor_lamp": {"hp": 4, "salvage": {"scrap": 2}, "mat": "metal"},
	"bookshelf": {"hp": 10, "salvage": {"wood": 3, "nails": 3}, "mat": "wood"},
	"dining_table": {"hp": 12, "salvage": {"wood": 3, "nails": 3}, "mat": "wood"},
	"chair": {"hp": 5, "salvage": {"wood": 1, "nails": 1}, "mat": "wood"},
	"plant": {"hp": 4, "salvage": {}, "mat": "plant"},
	"fridge": {"hp": 14, "salvage": {"scrap": 3, "iron": 2}, "mat": "metal"},
	"counter": {"hp": 12, "salvage": {"wood": 2, "nails": 2, "scrap": 1}, "mat": "wood"},
	"sink_counter": {"hp": 12, "salvage": {"wood": 1, "nails": 2, "scrap": 2}, "mat": "wood"},
	"stove": {"hp": 16, "salvage": {"scrap": 3, "iron": 2}, "mat": "metal"},
	"island": {"hp": 14, "salvage": {"wood": 3, "nails": 3}, "mat": "wood"},
	"stool": {"hp": 4, "salvage": {"scrap": 1}, "mat": "metal"},
	"bed": {"hp": 14, "salvage": {"wood": 3, "nails": 3, "scrap": 1}, "mat": "fabric"},
	"nightstand": {"hp": 5, "salvage": {"wood": 1, "nails": 1}, "mat": "wood"},
	"wardrobe": {"hp": 12, "salvage": {"wood": 4, "nails": 4}, "mat": "wood"},
	"dresser": {"hp": 10, "salvage": {"wood": 2, "nails": 3}, "mat": "wood"},
	"bathtub": {"hp": 18, "salvage": {"scrap": 4}, "mat": "ceramic"},
	"toilet": {"hp": 10, "salvage": {"scrap": 2}, "mat": "ceramic"},
	"vanity": {"hp": 8, "salvage": {"wood": 1, "scrap": 1}, "mat": "wood"},
	"water_heater": {"hp": 12, "salvage": {"scrap": 3, "iron": 1}, "mat": "metal"},
	"workbench": {"hp": 14, "salvage": {"wood": 3, "nails": 3, "scrap": 1}, "mat": "wood"},
	"washer": {"hp": 14, "salvage": {"scrap": 3, "iron": 1}, "mat": "metal"},
	"dryer": {"hp": 14, "salvage": {"scrap": 3, "iron": 1}, "mat": "metal"},
	"shelves": {"hp": 8, "salvage": {"scrap": 2, "wood": 1}, "mat": "metal"},
	"boxes": {"hp": 5, "salvage": {"scrap": 1}, "mat": "wood"},
}
const DEFAULT_TYPE := {"hp": 8, "salvage": {"wood": 1}, "mat": "wood"}

var world: HouseWorld
## id -> {"id", "f" (HousePlan entry), "hp", "max_hp", "state", "tall", "node",
##        "body", "rubble", "n0" (voxels when voxelised), "left", "lo", "hi"}
var pieces := {}
var stats := {"voxelised": 0, "destroyed": 0, "voxelise_ms": 0.0, "destroy_ms": 0.0}
var _cells := {}                # nav cell -> id (blocking pieces)
var _root: Node3D               # rubble meshes
var _rng := RandomNumberGenerator.new()


func _init(w: HouseWorld) -> void:
	world = w
	_rng.seed = 4004


static func type_def(type: String) -> Dictionary:
	return TYPES.get(type, DEFAULT_TYPE)


## Mesh, collider and state for every FURNITURE piece (HouseWorld._build).
func place_all() -> void:
	_root = Node3D.new()
	_root.name = "Rubble"
	world.add_child(_root)
	for f in HousePlan.FURNITURE:
		if f["type"] == "rug":
			continue
		var hp := int(type_def(f["type"])["hp"])
		var p := {"id": f["id"], "f": f, "hp": hp, "max_hp": hp, "state": INTACT, "tall": float(f["height"]) >= Tuning.TALL_THRESHOLD,
			"node": null, "body": null, "rubble": null, "n0": 0, "left": 0, "items": {}, "spot": null}
		if FurnitureStorage.is_storage(f["type"]):       # Exp 005 (F)
			p["spot"] = _make_spot(f)
		var b := _grid_box(f)
		p["lo"] = b[0]
		p["hi"] = b[1]
		pieces[f["id"]] = p
		_make_intact(p)
	_index_cells()


func _grid_box(f: Dictionary) -> Array:
	var g := world.grid
	var rows := maxi(1, int(round((float(f["height"]) + float(VoxelFurniture.EXTRA.get(f["type"], 0.0))) / VoxelFurniture.VS)))
	var xr := g.centre_range(0, f["rect"].position.x, f["rect"].end.x)
	var zr := g.centre_range(2, f["rect"].position.y, f["rect"].end.y)
	return [Vector3i(xr.x, VoxelHouse.BASE_ROW, zr.x), Vector3i(xr.y, mini(VoxelHouse.BASE_ROW + rows, g.sy - 1), zr.y)]


func _make_intact(p: Dictionary) -> void:
	var f: Dictionary = p["f"]
	var r: Rect2 = f["rect"]
	var h: float = f["height"]
	var node := world._prop(f["type"], r, f["facing"], h, hash(f["id"]) & 0xffff)
	node.name = "Prop_" + f["id"]
	world.add_child(node)
	p["node"] = node
	if f["blocks"]:
		var body := world._box_body(r, maxf(h, 0.4), 1 if p["tall"] else 1 << 4)
		body.set_meta("impact", HouseWorld.PROP_IMPACT.get(f["type"], VoxelMat.Impact.WOOD if p["tall"] else VoxelMat.Impact.FABRIC))
		body.set_meta("furniture", f["id"])
		body.name = "Body_" + f["id"]
		world.add_child(body)
		p["body"] = body
	if p["tall"]:
		world.props.append({"node": node, "centre": Vector3(r.get_center().x, h * 0.5, r.get_center().y),
			"half": maxf(r.size.x, r.size.y) * 0.5, "body": p["body"].get_rid() if p["body"] != null else RID(), "cut": false})


func _index_cells() -> void:
	_cells.clear()
	for id in pieces:
		var f: Dictionary = pieces[id]["f"]
		if f["blocks"]:
			for c in world.nav.cells_in_rect(f["rect"]):
				_cells[c] = id


# --- queries ----------------------------------------------------------------------------

## GridNav kind of a nav cell for furniture: WALL under a standing blocking
## piece (bashable), else -1.
func cell_kind(c: Vector2i) -> int:
	var id: Variant = _cells.get(c)
	if id == null:
		return -1
	return GridNav.WALL if int(pieces[id]["state"]) <= DAMAGED else -1


## The standing piece whose blocking cells include nav cell c, or "".
func id_at_cell(c: Vector2i) -> String:
	var id: Variant = _cells.get(c)
	if id == null or int(pieces[id]["state"]) > DAMAGED:
		return ""
	return id


func ok(id: String) -> bool:
	return pieces.has(id) and int(pieces[id]["state"]) <= DAMAGED


func state_of(id: String) -> String:
	return STATE_NAMES[pieces[id]["state"]] if pieces.has(id) else ""


## True if a standing blocking piece overlaps the plan rect.
func blocks_rect(rect: Rect2) -> bool:
	for id in pieces:
		var p: Dictionary = pieces[id]
		if int(p["state"]) <= DAMAGED and p["f"]["blocks"] and (p["f"]["rect"] as Rect2).intersects(rect):
			return true
	return false


## The piece at plan point p (standing, or rubble when `rubble`), nearest
## centre first; "" if none.
func piece_at(pt: Vector2, margin := 0.05, rubble := true) -> String:
	var best := ""
	var best_d := INF
	for id in pieces:
		var p: Dictionary = pieces[id]
		var st := int(p["state"])
		if st == REMOVED or (st == DESTROYED and not rubble):
			continue
		var r: Rect2 = p["f"]["rect"]
		if r.grow(margin).has_point(pt):
			var d := r.get_center().distance_to(pt)
			if d < best_d:
				best_d = d
				best = id
	return best


## The standing piece whose grid box holds voxel cell c, or "".
func id_of_cell(c: Vector3i) -> String:
	for id in pieces:
		var p: Dictionary = pieces[id]
		if int(p["state"]) != DAMAGED:
			continue
		var lo: Vector3i = p["lo"]
		var hi: Vector3i = p["hi"]
		if c.x >= lo.x and c.x < hi.x and c.y >= lo.y and c.y < hi.y and c.z >= lo.z and c.z < hi.z:
			return id
	return ""


## What demolishing the piece gives back: TYPES salvage, scaled by the HP
## left for a damaged piece (rounded up); rubble gives nothing.
func salvage(id: String) -> Dictionary:
	if not pieces.has(id):
		return {}
	var p: Dictionary = pieces[id]
	if int(p["state"]) > DAMAGED:
		return {}
	var frac := float(p["hp"]) / float(maxi(int(p["max_hp"]), 1))
	var out := {}
	var base: Dictionary = type_def(p["f"]["type"])["salvage"]
	for k in base:
		var n := ceili(int(base[k]) * frac)
		if n > 0:
			out[k] = n
	return out


func display_name(id: String) -> String:
	return str(pieces[id]["f"]["type"]).capitalize() if pieces.has(id) else id


## Furniture voxels in the current grid (damaged pieces), for damage_summary.
func voxels_in_grid() -> int:
	var n := 0
	for id in pieces:
		if int(pieces[id]["state"]) == DAMAGED:
			n += int(pieces[id]["left"])
	return n


func count(state: int) -> int:
	var n := 0
	for id in pieces:
		if int(pieces[id]["state"]) == state:
			n += 1
	return n


# --- damage -----------------------------------------------------------------------------

## Switches an intact piece to its voxel representation (first damage).
func voxelise(id: String) -> void:
	var p: Dictionary = pieces.get(id, {})
	if p.is_empty() or int(p["state"]) != INTACT:
		return
	var t0 := Time.get_ticks_usec()
	if VoxelFurniture.C.is_empty():
		VoxelFurniture._palette()
	VoxelFurniture.build_piece(world.grid, p["f"])
	var n := _count_voxels(p)
	p["n0"] = n
	p["left"] = n
	p["state"] = DAMAGED
	_drop_node(p)
	if p["body"] != null:
		(p["body"] as StaticBody3D).collision_layer = 1 << 4     # bodies only: bullets reach the voxels
	world.chunks.mark_visual_dirty(p["lo"] - Vector3i.ONE, p["hi"] + Vector3i.ONE)
	world.chunks.flush(8.0)
	stats["voxelised"] += 1
	stats["voxelise_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	world.furniture_changed.emit(id)
	world.furniture_layout_changed.emit()     # Exp 005 (F): intact -> damaged


func _count_voxels(p: Dictionary) -> int:
	var g := world.grid
	var lo: Vector3i = p["lo"]
	var hi: Vector3i = p["hi"]
	var n := 0
	for y in range(lo.y, hi.y):
		for z in range(lo.z, hi.z):
			var row := (y * g.sz + z) * g.sx
			for x in range(lo.x, hi.x):
				if g.mat[row + x] >= VoxelMat.WOOD:
					n += 1
	return n


## A bullet carved voxel cell c (HouseWorld._hit_voxels): the piece there loses SHOT_DAMAGE.
func on_shot_cell(c: Vector3i) -> void:
	var id := id_of_cell(c)
	if id != "":
		hurt(id, SHOT_DAMAGE)


## Damage `n` to a piece without carving (blasts carve on their own). A
## piece that this destroys goes straight to rubble (no voxels first).
func hurt(id: String, n: int, quiet := false) -> void:
	var p: Dictionary = pieces.get(id, {})
	if p.is_empty() or int(p["state"]) > DAMAGED:
		return
	if int(p["hp"]) - n <= 0:
		destroy(id, quiet)
		return
	if int(p["state"]) == INTACT:
		voxelise(id)
	p["hp"] = int(p["hp"]) - n
	world.furniture_changed.emit(id)


## An enemy blow or other point damage at `from`'s side of the piece: a
## bite out of it (voxelising it first) and `n` HP.
func strike(id: String, n: int, from: Vector3) -> void:
	var p: Dictionary = pieces.get(id, {})
	if p.is_empty() or int(p["state"]) > DAMAGED:
		return
	if int(p["state"]) == INTACT:
		voxelise(id)
	var r: Rect2 = p["f"]["rect"]
	var near := Vector2(from.x, from.z).clamp(r.position, r.end)
	var h := _rng.randf_range(0.15, minf(float(p["f"]["height"]), 1.4) * 0.85)
	var at := Vector3(near.x, h, near.y)
	var dir := (at - Vector3(from.x, h, from.z))
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	var ch := VoxelCarver.carve_sphere(world.grid, at + dir * 0.08, HouseWorld.FURNITURE_CARVE * 1.2, _rng.randi(), Vector3.ZERO, 1.0, world.damage_quantum)
	if not (ch["cells"] as PackedInt32Array).is_empty():
		world._apply_damage(ch)
		world.fx.impact(VoxelMat.IMPACT[(ch["mats"] as PackedByteArray)[0]], at, -dir, dir, ch)
		Sfx.play(HouseWorld.IMPACT_SOUND.get(VoxelMat.IMPACT[(ch["mats"] as PackedByteArray)[0]], "impact/wood"), at)
	if pieces[id]["state"] == DAMAGED:
		hurt(id, n)


## Removed voxels (any carve through HouseWorld._apply_damage): pieces that
## fall below KEEP_FRACTION of their voxels are destroyed.
func on_removed(ch: Dictionary) -> void:
	var cells: PackedInt32Array = ch["cells"]
	if cells.is_empty():
		return
	var lo: Vector3i = ch["lo"]
	var hi: Vector3i = ch["hi"]
	var hit := []
	for id in pieces:
		var p: Dictionary = pieces[id]
		if int(p["state"]) != DAMAGED:
			continue
		var plo: Vector3i = p["lo"]
		var phi: Vector3i = p["hi"]
		if plo.x >= hi.x or phi.x <= lo.x or plo.y >= hi.y or phi.y <= lo.y or plo.z >= hi.z or phi.z <= lo.z:
			continue
		hit.append(id)
	if hit.is_empty():
		return
	var mats: PackedByteArray = ch["mats"]
	var g := world.grid
	for k in cells.size():
		if mats[k] < VoxelMat.WOOD:
			continue
		var c := g.coords(cells[k])
		for id in hit:
			var p: Dictionary = pieces[id]
			var plo: Vector3i = p["lo"]
			var phi: Vector3i = p["hi"]
			if c.x >= plo.x and c.x < phi.x and c.y >= plo.y and c.y < phi.y and c.z >= plo.z and c.z < phi.z:
				p["left"] = int(p["left"]) - 1
				break
	for id in hit:
		var p: Dictionary = pieces[id]
		if int(p["state"]) == DAMAGED and float(p["left"]) < float(p["n0"]) * KEEP_FRACTION:
			destroy(id)


## Destroyed: its voxels and collider go, rubble stays, navigation opens.
## `quiet` (blasts) skips the extra burst.
func destroy(id: String, quiet := false) -> void:
	var p: Dictionary = pieces.get(id, {})
	if p.is_empty() or int(p["state"]) > DAMAGED:
		return
	var t0 := Time.get_ticks_usec()
	_clear(p, not quiet)
	p["state"] = DESTROYED
	p["hp"] = 0
	_make_rubble(p)
	stats["destroyed"] += 1
	stats["destroy_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	var at := Vector3(p["f"]["rect"].get_center().x, 0.5, p["f"]["rect"].get_center().y)
	if not quiet:
		Sfx.play("structure/break", at)
	_drop_items(p)       # Exp 005 (F)
	_changed(p)


## Demolished (build mode): voxels, collider and rubble go.
func remove(id: String) -> void:
	var p: Dictionary = pieces.get(id, {})
	if p.is_empty() or int(p["state"]) == REMOVED:
		return
	_drop_items(p)       # Exp 005 (F)
	_clear(p, false)
	if p["rubble"] != null and is_instance_valid(p["rubble"]):
		(p["rubble"] as Node).queue_free()
	p["rubble"] = null
	p["state"] = REMOVED
	p["hp"] = 0
	_changed(p)


## Every piece back to an intact mesh with full HP (dev repair). The caller
## restores the grid (repair_all copies the design) and the navigation.
func restore_all() -> void:
	for id in pieces:
		var p: Dictionary = pieces[id]
		if int(p["state"]) == INTACT:
			p["hp"] = p["max_hp"]
			continue
		_clear(p, false)
		if p["rubble"] != null and is_instance_valid(p["rubble"]):
			(p["rubble"] as Node).queue_free()
		p["rubble"] = null
		p["state"] = INTACT
		p["hp"] = p["max_hp"]
		p["n0"] = 0
		p["left"] = 0
		_make_intact(p)
		world.furniture_changed.emit(id)
	world.furniture_layout_changed.emit()     # Exp 005 (F)


func _changed(p: Dictionary) -> void:
	var rect: Rect2 = p["f"]["rect"]
	world._recompute_nav(rect.grow(GridNav.CELL))
	world._update_light_hosts()
	world.furniture_changed.emit(p["id"])
	world.structure_changed.emit()
	world.furniture_layout_changed.emit()     # Exp 005 (F)


## Frees the mesh and collider, clears the piece's voxels from the grid
## (with a capped debris burst when `burst`).
func _clear(p: Dictionary, burst: bool) -> void:
	_drop_node(p)
	if p["body"] != null and is_instance_valid(p["body"]):
		var b: StaticBody3D = p["body"]
		b.collision_layer = 0
		b.queue_free()
	p["body"] = null
	if int(p["state"]) != DAMAGED:
		return
	var g := world.grid
	var lo: Vector3i = p["lo"]
	var hi: Vector3i = p["hi"]
	var ch := VoxelCarver.empty_change()
	for y in range(lo.y, hi.y):
		for z in range(lo.z, hi.z):
			for x in range(lo.x, hi.x):
				var i := g.idx(x, y, z)
				if g.mat[i] >= VoxelMat.WOOD:
					VoxelCarver._remove(g, i, ch)
	p["left"] = 0
	var cells: PackedInt32Array = ch["cells"]
	if cells.is_empty():
		return
	world.chunks.apply_change(ch)
	if burst and world.fx != null:
		var stride := maxi(1, cells.size() / DEBRIS_CAP)
		var k := 0
		var colors: PackedInt32Array = ch["colors"]
		while k < cells.size():
			var c := g.center(g.coords(cells[k]))
			world.fx.debris(c, Vector3(_rng.randf_range(-1.5, 1.5), _rng.randf_range(0.5, 2.5), _rng.randf_range(-1.5, 1.5)),
					VoxelArt.to_color(colors[k]), _rng.randf_range(0.7, 1.3) * world.fx.debris_scale)
			k += stride


func _drop_node(p: Dictionary) -> void:
	var node: Node3D = p["node"]
	if node == null:
		return
	for i in range(world.props.size() - 1, -1, -1):
		if world.props[i]["node"] == node:
			world.props.remove_at(i)
	if is_instance_valid(node):
		node.queue_free()
	p["node"] = null


func _make_rubble(p: Dictionary) -> void:
	var f: Dictionary = p["f"]
	var r: Rect2 = f["rect"]
	var node := PropKit.make("rubble", Vector3(r.size.x, RUBBLE_HEIGHT, r.size.y),
			{"facing": "N", "seed": hash(f["id"]) & 0xffff, "style": type_def(f["type"])["mat"]})
	node.position = Vector3(r.get_center().x, 0.0, r.get_center().y)
	node.name = "Rubble_" + f["id"]
	for gi in node.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(node)
	p["rubble"] = node


# --- persistence ------------------------------------------------------------------------

## {id: [state, hp, voxels when voxelised]} for pieces that aren't intact.
func save_data() -> Dictionary:
	var out := {}
	for id in pieces:
		var p: Dictionary = pieces[id]
		if int(p["state"]) != INTACT:
			out[id] = [int(p["state"]), int(p["hp"]), int(p["n0"])]
	return out


## Applies a saved state after the world was built from the save (the
## voxels of damaged pieces are already in the loaded grid). Unknown ids and
## malformed entries are skipped. Returns the pieces applied.
func load_data(d: Variant) -> int:
	if not (d is Dictionary):
		return 0
	var n := 0
	for id in d:
		if not (id is String) or not pieces.has(id):
			continue
		var e: Variant = d[id]
		if not (e is Array) or (e as Array).size() < 2:
			continue
		if typeof(e[0]) not in [TYPE_INT, TYPE_FLOAT] or typeof(e[1]) not in [TYPE_INT, TYPE_FLOAT]:
			continue
		var st := int(e[0])
		if st < DAMAGED or st > REMOVED:
			continue
		var p: Dictionary = pieces[id]
		match st:
			DAMAGED:
				p["state"] = DAMAGED
				p["hp"] = clampi(int(e[1]), 1, int(p["max_hp"]))
				_drop_node(p)
				if p["body"] != null:
					(p["body"] as StaticBody3D).collision_layer = 1 << 4
				p["left"] = _count_voxels(p)
				var n0: int = int(e[2]) if (e as Array).size() > 2 and typeof(e[2]) in [TYPE_INT, TYPE_FLOAT] else 0
				p["n0"] = maxi(n0, int(p["left"]))
				if int(p["left"]) == 0:
					p["state"] = INTACT       # inconsistent: no voxels in the grid
					p["hp"] = p["max_hp"]
					_drop_node(p)
					_make_intact_visual_only(p)
					continue
			DESTROYED:
				_clear(p, false)
				p["state"] = DESTROYED
				p["hp"] = 0
				_make_rubble(p)
			REMOVED:
				_clear(p, false)
				p["state"] = REMOVED
				p["hp"] = 0
		n += 1
	if n > 0:
		world._full_nav()
	return n


## The mesh of an intact piece whose collider still exists (save repair).
func _make_intact_visual_only(p: Dictionary) -> void:
	var f: Dictionary = p["f"]
	if p["body"] != null:
		(p["body"] as StaticBody3D).collision_layer = 1 if p["tall"] else 1 << 4
	var node := world._prop(f["type"], f["rect"], f["facing"], f["height"], hash(f["id"]) & 0xffff)
	node.name = "Prop_" + f["id"]
	world.add_child(node)
	p["node"] = node


# --- Exp 005 (F): storage, comfort listing, Move --------------------------------------

func _make_spot(f: Dictionary) -> Node3D:
	var spot := StorageSpot.new()
	spot.name = "Storage_" + str(f["id"])
	spot.owner_f = self
	spot.id = f["id"]
	var r: Rect2 = f["rect"]
	var dir: Vector2 = WorldObject.front_dir(FurnitureCatalog.rot_of_facing(f["facing"]))
	var depth := r.size.y if absf(dir.y) > 0.5 else r.size.x
	# at its back edge: in front of the piece it is still within reach, while
	# things standing in front of it (the fireplace by the bookshelf) win
	var at: Vector2 = r.get_center() - dir * (depth * 0.5)
	spot.position = Vector3(at.x, 0.0, at.y)
	world.add_child(spot)
	return spot


## The E targets of the standing storage pieces.
func storage_spots() -> Array:
	var out := []
	for id in pieces:
		var p: Dictionary = pieces[id]
		if p["spot"] != null and int(p["state"]) <= DAMAGED and is_instance_valid(p["spot"]):
			out.append(p["spot"])
	return out


func storage_type(id: String) -> String:
	if not pieces.has(id):
		return ""
	var t: String = pieces[id]["f"]["type"]
	return t if FurnitureStorage.is_storage(t) else ""


## The live contents of a piece ({} for unknown ids).
func items_of(id: String) -> Dictionary:
	return pieces[id]["items"] if pieces.has(id) else {}


func spot_prompt(id: String) -> String:
	var t := storage_type(id)
	if t == "" or not ok(id):
		return ""
	return "[E] Open the %s (%s)" % [FurnitureStorage.name_of(t).to_lower(), FurnitureStorage.fill_text(t, items_of(id))]


## True if plan point p is not behind the piece (the side its back faces).
func can_reach(id: String, p: Vector2) -> bool:
	if not pieces.has(id):
		return false
	var f: Dictionary = pieces[id]["f"]
	var r: Rect2 = f["rect"]
	var dir: Vector2 = WorldObject.front_dir(FurnitureCatalog.rot_of_facing(f["facing"]))
	var depth := r.size.y if absf(dir.y) > 0.5 else r.size.x
	return (p - r.get_center()).dot(dir) > -depth * 0.5


func open_spot(id: String, game: Node) -> void:
	var h: Variant = game.get("storage") if game != null else null
	if h is Object and is_instance_valid(h) and h.has_method("open_piece"):
		h.open_piece(world, id)
	elif game != null and game.has_method("toast"):
		game.toast("%s: %s." % [FurnitureStorage.name_of(storage_type(id)), FurnitureStorage.contents_text(items_of(id))], "info")


## Standing pieces for HouseWorld.furniture_items(), plus the house's rugs
## (floor voxels, always there).
func items_list() -> Array:
	var out := []
	for id in pieces:
		var p: Dictionary = pieces[id]
		var st := int(p["state"])
		if st > DAMAGED:
			continue
		var f: Dictionary = p["f"]
		out.append({"type": f["type"], "rect": f["rect"], "rot": FurnitureCatalog.rot_of_facing(f["facing"]),
			"state": STATE_NAMES[st], "id": id})
	for f in HousePlan.FURNITURE:
		if f["type"] == "rug":
			out.append({"type": "rug", "rect": f["rect"], "rot": FurnitureCatalog.rot_of_facing(f["facing"]), "state": "intact", "id": f["id"]})
	return out


func containers() -> Array:
	var out := []
	for id in pieces:
		var t := storage_type(id)
		if t != "" and ok(id):
			out.append({"id": id, "type": t, "name": FurnitureStorage.name_of(t), "items": pieces[id]["items"],
				"pos": (pieces[id]["f"]["rect"] as Rect2).get_center()})
	return out


## A new house: a little food in the fridge, nails on the utility shelves...
func fill_start() -> void:
	for id in FurnitureStorage.START:
		if pieces.has(id):
			pieces[id]["items"] = (FurnitureStorage.START[id] as Dictionary).duplicate()


func _drop_items(p: Dictionary) -> void:
	var items: Dictionary = p["items"]
	if items.is_empty():
		return
	var keep := items.duplicate()
	items.clear()
	world.drop_loot((p["f"]["rect"] as Rect2).get_center(), keep)


## {id: items} for the pieces that hold something.
func storage_save() -> Dictionary:
	var out := {}
	for id in pieces:
		if not (pieces[id]["items"] as Dictionary).is_empty():
			out[id] = (pieces[id]["items"] as Dictionary).duplicate()
	return out


## Untrusted: unknown ids, non-storage pieces and bad items are skipped.
func storage_load(d: Variant) -> void:
	for id in pieces:
		(pieces[id]["items"] as Dictionary).clear()
	if not (d is Dictionary):
		return
	for id in d:
		if id is String and pieces.has(id) and storage_type(id) != "" and ok(id):
			FurnitureStorage.merge(pieces[id]["items"], FurnitureStorage.clean(d[id]))


## Move tool: lifts a standing piece out of the house (state REMOVED, no
## salvage, no pile) and returns what the placed object takes over:
## {"type", "size", "hp", "max_hp", "items"} ({} if it can't be moved).
func take_out(id: String) -> Dictionary:
	var p: Dictionary = pieces.get(id, {})
	if p.is_empty() or int(p["state"]) > DAMAGED or FurnitureCatalog.move_block(p["f"]["type"]) != "":
		return {}
	var f: Dictionary = p["f"]
	var out := {"type": f["type"], "size": FurnitureCatalog.size_of_rect(f["rect"], f["height"], f["facing"]),
		"hp": int(p["hp"]), "max_hp": int(p["max_hp"]), "items": (p["items"] as Dictionary).duplicate()}
	(p["items"] as Dictionary).clear()
	_clear(p, false)
	if p["rubble"] != null and is_instance_valid(p["rubble"]):
		(p["rubble"] as Node).queue_free()
	p["rubble"] = null
	p["state"] = REMOVED
	p["hp"] = 0
	_changed(p)
	return out


## An original storage piece's E target (at its back edge).
class StorageSpot extends Node3D:
	var owner_f: RefCounted
	var id := ""

	func interact_prompt() -> String:
		return owner_f.spot_prompt(id) if owner_f != null else ""

	func interact(game: Node) -> void:
		if owner_f != null:
			owner_f.open_spot(id, game)

	## Only from in front of the piece or beside it, never from behind (its wall).
	func interact_reach(p: Vector2) -> bool:
		return owner_f == null or owner_f.can_reach(id, p)
