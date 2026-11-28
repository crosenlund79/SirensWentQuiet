class_name WorldObject
extends Node3D
## A placeable object of the survival house (SPEC §7.3 d, §4): door,
## barricade, storage crate, rain collector or (Experiment 003) workbench.
## Kind, material, HP, footprint, a PropKit visual and the SPEC collision
## layers. Navigation and collision consistency are kept by HouseWorld,
## which owns every object. Doors and barricades come in "wood" and "iron"
## (a reinforced door, an iron barricade: same behaviour, more HP); `kind`
## stays "door" / "barricade" for both.
##
## Experiment 004: "boards" (window boards: planks over a window section,
## mounted at window height on the outside face; they stop bullets and
## bodies), a third door material "metal" (a steel door, 70 HP) and the
## "fuse_box" (wall-mounted main power switch, `mains_on`; HouseWorld emits
## power_changed). DEFS "y0" lifts the visual and collision above the floor,
## "out" moves them toward the front (outside) of the wall line.
##
## Wall-like objects (door, barricade, boards) sit on a 1 m segment of an integer plan
## line: `seg` = Vector3i(axis, line, start) with axis 0 = along plan x on
## y = line, axis 1 = along plan y on x = line. Free-standing objects (crate,
## rain collector) sit on 0.5 m cells with a quarter-turn `rot`.

const FACINGS := ["N", "E", "S", "W"]
const YAW := [0.0, -PI * 0.5, PI, PI * 0.5]   ## node yaw that turns local -Z to N, E, S, W
const DOOR_CUT_H := 0.75                      ## Exp 012 (V): a door's height in the cutaway (walls are cut to 0.45 m)

## size = Vector3(width across the front, height, depth) before rotation.
const DEFS := {
	"door": {"name": "Door", "hp": 18, "size": Vector3(1.0, 2.1, 0.16), "segment": true, "layers": 1 | 2, "impact": VoxelMat.Impact.WOOD},
	"barricade": {"name": "Barricade", "hp": 12, "size": Vector3(1.0, 1.5, 0.22), "segment": true, "layers": 2, "impact": VoxelMat.Impact.WOOD},
	"crate": {"name": "Storage crate", "hp": 10, "size": Vector3(1.0, 0.75, 0.5), "segment": false, "layers": 1, "impact": VoxelMat.Impact.WOOD},
	"rain_collector": {"name": "Rain collector", "hp": 10, "size": Vector3(0.5, 1.1, 0.5), "segment": false, "layers": 1, "impact": VoxelMat.Impact.METAL},
	"workbench": {"name": "Workbench", "hp": 14, "size": Vector3(1.0, 0.9, 0.5), "segment": false, "layers": 1, "impact": VoxelMat.Impact.WOOD},
	# Experiment 004
	"boards": {"name": "Window boards", "hp": 14, "size": Vector3(1.0, 1.3, 0.08), "segment": true, "layers": 1 | 2, "impact": VoxelMat.Impact.WOOD,
		"y0": 0.85, "out": 0.19},
	"fuse_box": {"name": "Fuse box", "hp": 20, "size": Vector3(0.5, 0.7, 0.16), "segment": false, "layers": 1, "impact": VoxelMat.Impact.METAL,
		"y0": 1.1},
	# Exp 005 (F): furniture (FurnitureCatalog.KINDS; SPEC §2 type names). Tall
	# pieces (>= 1.2 m) stop bullets (layer 1), low ones only bodies (layer 5),
	# flat ones nothing. HP as HouseFurniture.TYPES.
	"cupboard": {"name": "Kitchen cupboard", "hp": 10, "size": Vector3(1.0, 0.92, 0.6), "segment": false, "layers": 16, "impact": VoxelMat.Impact.WOOD},
	"storage_chest": {"name": "Storage chest", "hp": 12, "size": Vector3(1.0, 0.6, 0.55), "segment": false, "layers": 16, "impact": VoxelMat.Impact.WOOD},
	"tool_cabinet": {"name": "Tool cabinet", "hp": 14, "size": Vector3(0.9, 1.8, 0.45), "segment": false, "layers": 1, "impact": VoxelMat.Impact.METAL},
	"wardrobe": {"name": "Wardrobe", "hp": 12, "size": Vector3(1.5, 2.0, 0.62), "segment": false, "layers": 1, "impact": VoxelMat.Impact.WOOD},
	"shelves": {"name": "Shelves", "hp": 8, "size": Vector3(1.2, 1.9, 0.45), "segment": false, "layers": 1, "impact": VoxelMat.Impact.WOOD},
	"bookshelf": {"name": "Bookshelf", "hp": 10, "size": Vector3(1.4, 1.9, 0.4), "segment": false, "layers": 1, "impact": VoxelMat.Impact.WOOD},
	"dresser": {"name": "Dresser", "hp": 10, "size": Vector3(1.2, 0.8, 0.5), "segment": false, "layers": 16, "impact": VoxelMat.Impact.WOOD},
	"nightstand": {"name": "Nightstand", "hp": 5, "size": Vector3(0.45, 0.55, 0.42), "segment": false, "layers": 16, "impact": VoxelMat.Impact.WOOD},
	"bed": {"name": "Bed", "hp": 14, "size": Vector3(1.6, 0.6, 2.1), "segment": false, "layers": 16, "impact": VoxelMat.Impact.FABRIC},
	"sofa": {"name": "Sofa", "hp": 16, "size": Vector3(2.0, 0.85, 0.9), "segment": false, "layers": 16, "impact": VoxelMat.Impact.FABRIC},
	"armchair": {"name": "Armchair", "hp": 10, "size": Vector3(0.9, 0.85, 0.9), "segment": false, "layers": 16, "impact": VoxelMat.Impact.FABRIC},
	"chair": {"name": "Chair", "hp": 5, "size": Vector3(0.45, 0.9, 0.42), "segment": false, "layers": 16, "impact": VoxelMat.Impact.WOOD},
	"dining_table": {"name": "Dining table", "hp": 12, "size": Vector3(1.6, 0.75, 0.9), "segment": false, "layers": 16, "impact": VoxelMat.Impact.WOOD},
	"coffee_table": {"name": "Coffee table", "hp": 8, "size": Vector3(1.1, 0.45, 0.6), "segment": false, "layers": 16, "impact": VoxelMat.Impact.WOOD},
	"rug": {"name": "Rug", "hp": 4, "size": Vector3(2.0, 0.01, 1.4), "segment": false, "layers": 0, "impact": VoxelMat.Impact.FABRIC},
	"floor_lamp": {"name": "Floor lamp", "hp": 4, "size": Vector3(0.4, 1.6, 0.4), "segment": false, "layers": 1, "impact": VoxelMat.Impact.METAL},
	"table_lamp": {"name": "Table lamp", "hp": 3, "size": Vector3(0.26, 0.42, 0.26), "segment": false, "layers": 0, "impact": VoxelMat.Impact.CERAMIC},
	"painting": {"name": "Painting", "hp": 3, "size": Vector3(0.8, 0.6, 0.05), "segment": false, "layers": 0, "impact": VoxelMat.Impact.WOOD,
		"y0": 1.25},
	"plant": {"name": "Plant", "hp": 4, "size": Vector3(0.5, 1.1, 0.5), "segment": false, "layers": 16, "impact": VoxelMat.Impact.PLANT},
	"tv_stand": {"name": "TV stand", "hp": 10, "size": Vector3(2.0, 1.1, 0.45), "segment": false, "layers": 16, "impact": VoxelMat.Impact.WOOD},
	"fridge": {"name": "Fridge", "hp": 14, "size": Vector3(0.75, 1.85, 0.7), "segment": false, "layers": 1, "impact": VoxelMat.Impact.METAL},
	"counter": {"name": "Kitchen counter", "hp": 12, "size": Vector3(1.0, 0.92, 0.62), "segment": false, "layers": 16, "impact": VoxelMat.Impact.WOOD},
	"island": {"name": "Kitchen island", "hp": 14, "size": Vector3(1.9, 0.92, 0.85), "segment": false, "layers": 16, "impact": VoxelMat.Impact.WOOD},
	"stool": {"name": "Stool", "hp": 4, "size": Vector3(0.4, 0.7, 0.4), "segment": false, "layers": 16, "impact": VoxelMat.Impact.METAL},
	"boxes": {"name": "Cardboard boxes", "hp": 5, "size": Vector3(1.0, 0.6, 0.7), "segment": false, "layers": 16, "impact": VoxelMat.Impact.PAPER},
	## Exp 006 (B): a small mains radio (HouseMedia); flat: it stands on tables too.
	"radio": {"name": "Radio", "hp": 3, "size": Vector3(0.34, 0.2, 0.14), "segment": false, "layers": 0, "impact": VoxelMat.Impact.METAL},
	## Exp 005 (F): what a destroyed or demolished storage piece leaves (E searches it).
	"loot_pile": {"name": "Pile of belongings", "hp": 1, "size": Vector3(0.8, 0.3, 0.8), "segment": false, "layers": 0, "impact": VoxelMat.Impact.PAPER},
	# Exp 006 (D): defences (src/defense/). Spikes sit on a 1 m wall line like
	# barricades (bodies, not bullets); drawbridges span 1 or 2 trench cells
	# (size.z), `open` = lowered (DefenseObjects, DefenseGrid).
	"spikes_wood": {"name": "Wooden spikes", "hp": 10, "size": Vector3(1.0, 0.85, 0.5), "segment": true, "layers": 2, "impact": VoxelMat.Impact.WOOD},
	"spikes_metal": {"name": "Metal spikes", "hp": 26, "size": Vector3(1.0, 0.85, 0.5), "segment": true, "layers": 2, "impact": VoxelMat.Impact.METAL},
	"drawbridge_1": {"name": "Drawbridge", "hp": 24, "size": Vector3(1.0, 0.12, 1.0), "segment": false, "layers": 2, "impact": VoxelMat.Impact.WOOD},
	"drawbridge_2": {"name": "Long drawbridge", "hp": 32, "size": Vector3(1.0, 0.12, 2.0), "segment": false, "layers": 2, "impact": VoxelMat.Impact.WOOD},
	# Exp 007 (S): security (src/security/). A sensor on a thin post blocks
	# nothing; a turret mount stops bullets and bodies and is bashed like a
	# barricade when it stands in the way. Their settings live in `sec`.
	"motion_sensor": {"name": "Motion sensor", "hp": 6, "size": Vector3(0.3, 2.0, 0.3), "segment": false, "layers": 0, "impact": VoxelMat.Impact.METAL},
	"turret_mount": {"name": "Turret mount", "hp": 30, "size": Vector3(0.6, 1.2, 0.6), "segment": false, "layers": 1, "impact": VoxelMat.Impact.METAL},
}
## Material variants (Experiment 003). "wood" is DEFS itself; others override
## name, hp, the PropKit style and the impact kind.
const MATS := {
	"door": {"iron": {"name": "Reinforced door", "hp": 42, "style": "iron", "impact": VoxelMat.Impact.METAL},
		"metal": {"name": "Metal door", "hp": 70, "style": "metal", "impact": VoxelMat.Impact.METAL}},
	"barricade": {"iron": {"name": "Iron barricade", "hp": 30, "style": "iron", "impact": VoxelMat.Impact.METAL}},
}
const WOOD_TONES := [0x7a5c40, 0x8c6c4c, 0x5e4a36, 0x9a8466]
const IRON_TONES := [0x5d6266, 0x7a7f82, 0x4a4643, 0x7b4a2c]

var kind := ""
var hp := 1
var max_hp := 1
var pos := Vector2.ZERO          ## plan centre of the footprint
var rot := 0                     ## 0..3 = front faces N, E, S, W
var seg := Vector3i(-1, 0, 0)    ## wall-like objects only
var open := false                ## doors
var built := true                ## placed by the player (demolish refunds half)
var mat := "wood"                ## "wood" | "iron" (doors and barricades) | "metal" (doors)
var mains_on := true             ## fuse box: the main power switch (saved)
var world: Node                  ## the owning HouseWorld
var visual: Node3D
var body: StaticBody3D
# Exp 005 (F): furniture (FurnitureCatalog) and loot piles
var uid := ""                    ## stable id of furniture and piles ("o12"; saved): HouseWorld.storage_of / furniture_items
var items := {}                  ## storage contents (item -> count; FurnitureStorage), saved
var size_override := Vector3.ZERO   ## a moved original keeps its own size (w, h, d); ZERO = DEFS size
var lift := 0.0                  ## a table lamp standing on a surface: the surface's height
var lamp_on := true              ## a lamp's own switch (saved)
var powered := false             ## the house has power (set by the game's storage helper)
var media_on := false            ## Exp 006 (B): a TV's or radio's own switch (saved as "on")
var sec := {}                    ## Exp 007 (S): a sensor's or turret's settings (Security; saved as "sec")
var _lamp_light: OmniLight3D

static var _next_uid := 1

var _pivot: Node3D
var _shape: CollisionShape3D
var _leaf: Node3D
var _leaf_sign := -1.0
var _leaf_angle := 0.0
var _cut := false


## Exp 005 (F): the next object id (and keeps it above any loaded one).
static func new_uid() -> String:
	_next_uid += 1
	return "o%d" % (_next_uid - 1)


static func note_uid(id: String) -> void:
	if id.begins_with("o") and id.substr(1).is_valid_int():
		_next_uid = maxi(_next_uid, id.substr(1).to_int() + 1)


static func is_segment_kind(k: String) -> bool:
	return DEFS.has(k) and DEFS[k]["segment"]


static func has_mat(k: String, m: String) -> bool:
	return DEFS.has(k) and (m == "wood" or (MATS.has(k) and MATS[k].has(m)))


static func _def(k: String, m: String, key: String) -> Variant:
	if m != "wood" and MATS.has(k) and MATS[k].has(m) and MATS[k][m].has(key):
		return MATS[k][m][key]
	return DEFS[k].get(key)


static func max_hp_of(k: String, m := "wood") -> int:
	return int(_def(k, m, "hp")) if DEFS.has(k) else 1


static func name_of(k: String, m := "wood") -> String:
	return str(_def(k, m, "name")) if DEFS.has(k) else k


## Plan direction of an object's front (the attacker's side of doors and
## barricades): rotation 0..3 = N, E, S, W.
static func front_dir(r: int) -> Vector2:
	return [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)][posmod(r, 4)]


## Plan footprint used for navigation and overlap checks. `size` (Exp 005)
## overrides the kind's size (a moved original piece).
static func footprint_of(k: String, p: Vector2, r: int, size := Vector3.ZERO) -> Rect2:
	if is_segment_kind(k):
		var horiz := r % 2 == 0
		return Rect2(p.x - 0.5, p.y - 0.125, 1.0, 0.25) if horiz else Rect2(p.x - 0.125, p.y - 0.5, 0.25, 1.0)
	var s: Vector3 = DEFS[k]["size"] if size == Vector3.ZERO else size
	var ext := Vector2(s.x, s.z) if r % 2 == 0 else Vector2(s.z, s.x)
	return Rect2(p - ext * 0.5, ext)


## Segment of a wall-like object at plan centre `p` and rotation `r`.
static func segment_of(p: Vector2, r: int) -> Vector3i:
	if r % 2 == 0:
		return Vector3i(0, roundi(p.y), floori(p.x))
	return Vector3i(1, roundi(p.x), floori(p.y))


func setup(k: String, p: Vector2, r: int, w: Node, is_built := true, m := "wood") -> void:
	kind = k
	pos = p
	rot = posmod(r, 4)
	world = w
	built = is_built
	mat = m if has_mat(k, m) else "wood"
	max_hp = max_hp_of(k, mat)
	hp = max_hp
	if is_segment_kind(k):
		seg = segment_of(p, rot)
	name = "%s_%d_%d" % [k, int(round(p.x * 10)), int(round(p.y * 10))]
	if FurnitureCatalog.is_furniture(k) or k == "loot_pile" or Security.is_kind(k):      # Exp 007 (S): sensors link turrets by uid
		uid = new_uid()


func _ready() -> void:
	position = Vector3(pos.x, 0, pos.y)
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	_pivot.rotation.y = YAW[rot]
	add_child(_pivot)
	_refresh_visual()
	body = StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = DEFS[kind]["layers"]
	body.collision_mask = 0
	body.set_meta("impact", _def(kind, mat, "impact"))
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	var s: Vector3 = size3()
	box.size = Vector3(s.x - (0.02 if is_segment_kind(kind) else 0.0), s.y, maxf(s.z, 0.12))
	_shape.shape = box
	_shape.position = Vector3(0, base_y() + s.y * 0.5, -float(DEFS[kind].get("out", 0.0)))
	body.add_child(_shape)
	_pivot.add_child(body)
	_apply_open(true)
	if FurnitureCatalog.is_lamp(kind):
		_apply_lamp()


func footprint() -> Rect2:
	return footprint_of(kind, pos, rot, size_override)


## Exp 005 (F): this object's size (w across the front, h, d).
func size3() -> Vector3:
	return DEFS[kind]["size"] if size_override == Vector3.ZERO else size_override


## Height of the visual's and collision's bottom (window boards, fuse box;
## Exp 005: a painting on its wall, a table lamp on a surface).
func base_y() -> float:
	return (float(DEFS[kind].get("y0", 0.0)) if DEFS.has(kind) else 0.0) + lift


func facing() -> String:
	return FACINGS[rot]


func display_name() -> String:
	return name_of(kind, mat)


## Debris colours when this object is hit or breaks (0xRRGGBB).
func debris_tones() -> Array:
	return IRON_TONES if mat != "wood" or kind == "fuse_box" or kind == "spikes_metal" or Security.is_kind(kind) else WOOD_TONES   # Exp 007 (S)


func damage_fraction() -> float:
	return clampf(1.0 - float(hp) / float(max_hp), 0.0, 1.0)


## Closed doors and barricades block bodies and count as WALL for navigation;
## crates and collectors are SOLID; an open door is OPEN (-1 = no mark).
func nav_kind() -> int:
	match kind:
		"door":
			return -1 if open else GridNav.WALL
		"barricade", "boards":
			return GridNav.WALL
		"fuse_box", "loot_pile", "motion_sensor":      # Exp 007 (S): a sensor post
			return -1
		"turret_mount":                       # Exp 007 (S): bashed through like a barricade
			return GridNav.WALL
		"spikes_wood", "spikes_metal":       # Exp 006 (D): bashed through like a barricade
			return GridNav.WALL
		"drawbridge_1", "drawbridge_2":      # Exp 006 (D): over the trench; raised it's bashed like a door
			return GridNav.OPEN if open else GridNav.WALL
	# Exp 005 (F): standing furniture is bashed through like the house's
	# (WALL); flat pieces (rugs, paintings, table lamps) don't block.
	if FurnitureCatalog.is_furniture(kind) and kind != "workbench":
		return -1 if FurnitureCatalog.is_flat(kind) else GridNav.WALL
	return GridNav.SOLID


## True for objects an enemy swing damages (SPEC: doors and barricades;
## Experiment 004: window boards and the fuse box).
func bashable() -> bool:
	if FurnitureCatalog.is_furniture(kind) and kind != "workbench":     # Exp 005 (F)
		return not FurnitureCatalog.is_flat(kind)
	if DefenseGrid.is_bridge(kind):          # Exp 006 (D): a raised drawbridge
		return not open
	return kind in ["barricade", "boards", "fuse_box", "spikes_wood", "spikes_metal", "turret_mount"] or (kind == "door" and not open)   # Exp 007 (S): + turret


## Returns true when this hit destroyed the object.
func take_damage(n: int) -> bool:
	if kind == "loot_pile":           # Exp 005 (F): a pile only goes when it's empty
		return false
	# Exp 006 (D): a raised drawbridge battered to nothing crashes down (jammed, 1 HP)
	if DefenseGrid.is_bridge(kind) and not open and hp - n <= 0 and world != null and world.get("defense") is DefenseGrid:
		(world.get("defense") as DefenseGrid).smash_bridge(self)
		_refresh_visual()
		return false
	hp = maxi(hp - n, 0)
	_refresh_visual()
	return hp <= 0


func restore() -> void:
	hp = max_hp
	_refresh_visual()


## Exp 005 (F): a moved piece keeps its HP.
func set_hp(v: int) -> void:
	hp = clampi(v, 1, max_hp)
	_refresh_visual()


func set_open(on: bool, instant := false) -> void:
	open = on
	_apply_open(instant)


func set_cut(on: bool) -> void:
	if on == _cut:
		return
	_cut = on
	_apply_cut()


## Experiment 004: a door's material changes in place (Reinforce: wood ->
## iron -> metal). The missing HP stay missing.
func set_mat(m: String) -> void:
	if not has_mat(kind, m) or m == mat:
		return
	var lost := max_hp - hp
	mat = m
	max_hp = max_hp_of(kind, mat)
	hp = clampi(max_hp - lost, 1, max_hp)
	if body != null:
		body.set_meta("impact", _def(kind, mat, "impact"))
	_refresh_visual()


func set_mains(on: bool) -> void:
	mains_on = on
	_refresh_visual()


func to_dict() -> Dictionary:
	var d := {"kind": kind, "x": pos.x, "y": pos.y, "rot": rot, "hp": hp, "open": open, "built": built, "mat": mat}
	if kind == "fuse_box":
		d["mains_on"] = mains_on
	# Exp 005 (F), optional: furniture and piles
	if uid != "":
		d["uid"] = uid
	if not items.is_empty():
		d["items"] = items.duplicate()
	if size_override != Vector3.ZERO:
		d["size"] = [size_override.x, size_override.y, size_override.z]
	if lift > 0.0:
		d["lift"] = lift
	if FurnitureCatalog.is_lamp(kind):
		d["on"] = lamp_on
	elif FurnitureCatalog.is_media(kind):      # Exp 006 (B)
		d["on"] = media_on
	if not sec.is_empty():
		d["sec"] = sec.duplicate()            # Exp 007 (S)
	return d


## Exp 005 (F): the optional saved fields (validated by HouseWorld._valid_objects).
func apply_extra(e: Dictionary) -> void:
	if e.get("uid", "") is String and str(e.get("uid", "")) != "":
		uid = str(e["uid"])
		note_uid(uid)
	if e.get("items") is Dictionary:
		items = FurnitureStorage.clean(e["items"])
	if e.get("size") is Vector3 and (e["size"] as Vector3) != Vector3.ZERO:
		set_size(e["size"])
	if typeof(e.get("lift")) == TYPE_FLOAT and float(e["lift"]) > 0.0:
		set_lift(float(e["lift"]))
	if typeof(e.get("on")) == TYPE_BOOL:
		if FurnitureCatalog.is_media(kind):      # Exp 006 (B)
			media_on = e["on"]
		else:
			set_lamp(e["on"])
	if e.get("sec") is Dictionary and Security.is_kind(kind):      # Exp 007 (S): cleaned by HouseWorld._valid_extra
		sec = (e["sec"] as Dictionary).duplicate()
		_refresh_visual()


## Exp 005 (F): a moved original's own size (before it is in the tree).
func set_size(s: Vector3) -> void:
	size_override = s
	if _shape != null and _shape.shape is BoxShape3D:
		(_shape.shape as BoxShape3D).size = Vector3(s.x, s.y, maxf(s.z, 0.12))
		_shape.position = Vector3(0, base_y() + s.y * 0.5, 0)
	_refresh_visual()


## Exp 005 (F): a table lamp on a surface of height h (0 = the floor).
func set_lift(h: float) -> void:
	lift = maxf(h, 0.0)
	if _shape != null:
		_shape.position.y = base_y() + size3().y * 0.5
	if visual != null:
		visual.position.y = base_y()
	if _lamp_light != null:
		_lamp_light.position.y = base_y() + size3().y * 0.8


# --- Exp 005 (F): lamps and storage --------------------------------------------------

## A placed lamp shines while its own switch is on and the house has power.
func is_lit() -> bool:
	return FurnitureCatalog.is_lamp(kind) and lamp_on and powered and hp > 0


func set_lamp(on: bool) -> void:
	lamp_on = on
	_apply_lamp()


func set_powered(on: bool) -> void:
	if on == powered:
		return
	powered = on
	_apply_lamp()


func _apply_lamp() -> void:
	if not FurnitureCatalog.is_lamp(kind) or _pivot == null:
		return
	var lit := is_lit()
	if visual != null:
		PropKit.set_lit(visual, 1.0 if lit else 0.0)
	if _lamp_light == null and lit:
		_lamp_light = OmniLight3D.new()
		_lamp_light.name = "LampLight"
		_lamp_light.light_color = Color(1.0, 0.82, 0.6)
		_lamp_light.omni_range = 4.5 if kind == "floor_lamp" else 3.2
		_lamp_light.omni_attenuation = 1.4
		_lamp_light.light_energy = 1.3 if kind == "floor_lamp" else 0.9
		_lamp_light.light_specular = 0.2
		_lamp_light.shadow_enabled = false
		_lamp_light.position = Vector3(0, base_y() + size3().y * (0.85 if kind == "floor_lamp" else 0.75), 0)
		_pivot.add_child(_lamp_light)
	if _lamp_light != null:
		_lamp_light.visible = lit


## The storage type of this object ("" if it holds nothing).
func storage_type() -> String:
	return kind if FurnitureStorage.is_storage(kind) else ""


# --- interactable duck type (SPEC §7.3) -------------------------------------------

func interact_prompt() -> String:
	match kind:
		"door":
			return "[E] Close door" if open else "[E] Open door"
		"crate":
			return "[E] Storage crate · +%d planks, +%d nails, +%d scrap" % [
				Items.DEFS["wood"]["cap_per_crate"], Items.DEFS["nails"]["cap_per_crate"], Items.DEFS["scrap"]["cap_per_crate"]]
		"rain_collector":
			return "[E] Rain collector · 1 water at dawn"
		"workbench":
			return "[E] Workbench · %d scrap → 1 iron (%d with Metalworking)" % [Workbench.SCRAP_PER_IRON, Research.SCRAP_PER_IRON_SKILLED]   # Exp 006 (R)
		"fuse_box":
			return "[E] Switch the main power off" if mains_on else "[E] Switch the main power on"
		# Exp 005 (F)
		"loot_pile":
			return "[E] Search the pile" if not items.is_empty() else ""
		"bed":
			return "[E] Sleep"
		"floor_lamp", "table_lamp":
			return "[E] Turn the lamp off" if lamp_on else "[E] Turn the lamp on"
		"tv_stand", "radio":      # Exp 006 (B)
			return HouseMedia.prompt(kind, media_on)
		"drawbridge_1", "drawbridge_2":      # Exp 006 (D)
			return DefenseObjects.bridge_prompt(self)
		"motion_sensor", "turret_mount":      # Exp 007 (S)
			return SecurityObjects.prompt(self)
	if storage_type() != "":
		return "[E] Open the %s (%s)" % [FurnitureStorage.name_of(kind).to_lower(), FurnitureStorage.fill_text(kind, items)]
	return ""


func interact(game: Node) -> void:
	match kind:
		"door":
			if world != null and world.has_method("toggle_door"):
				var err: String = world.toggle_door(self)
				if err != "" and game != null and game.has_method("toast"):
					game.toast(err, "warn")
		"crate":
			if game != null and game.has_method("toast"):
				game.toast("Storage crate: holds %d more planks, %d more nails and %d more scrap." % [
					Items.DEFS["wood"]["cap_per_crate"], Items.DEFS["nails"]["cap_per_crate"], Items.DEFS["scrap"]["cap_per_crate"]], "info")
		"rain_collector":
			if game != null and game.has_method("toast"):
				game.toast("Rain collector: gathers 1 water at dawn.", "info")
		"workbench":
			var st: Variant = game.get("state") if game != null else null
			var r := Workbench.convert(st, 1)
			if r["ok"]:
				Sfx.play("build/hammer", Vector3(pos.x, 0.9, pos.y))
			if game != null and game.has_method("toast"):
				game.toast(r["text"], "info" if r["ok"] else "warn")
		"fuse_box":
			if world != null and world.has_method("toggle_mains"):
				world.toggle_mains(self)
			if game != null and game.has_method("toast"):
				game.toast("Main power on." if mains_on else "Main power off.", "info")
		"drawbridge_1", "drawbridge_2":      # Exp 006 (D): E raises or lowers it
			var why := ""
			if world != null and world.get("defense") is DefenseGrid:
				why = (world.get("defense") as DefenseGrid).toggle_bridge(self)
			if game != null and game.has_method("toast"):
				game.toast(why if why != "" else ("Drawbridge lowered." if open else "Drawbridge raised."), "warn" if why != "" else "info")
		# Exp 005 (F)
		"bed":
			if game != null and game.has_method("open_sleep"):
				game.open_sleep()
		"floor_lamp", "table_lamp":
			set_lamp(not lamp_on)
			Sfx.ui("ui/click")
			var h: Variant = game.get("storage") if game != null else null
			if h is Object and is_instance_valid(h) and h.has_method("refresh_lamps"):
				h.refresh_lamps()
			if lamp_on and not powered and game != null and game.has_method("toast"):
				game.toast("Nothing. There's no power.", "warn")
			if world != null and world.has_signal("furniture_layout_changed"):
				world.emit_signal("furniture_layout_changed")
		"motion_sensor", "turret_mount":      # Exp 007 (S): the game's security helper (panel, hand reload)
			var sh: Variant = game.get("security") if game != null else null
			if sh is Object and is_instance_valid(sh) and sh.has_method("interact"):
				sh.interact(self)
			elif game != null and game.has_method("toast"):
				game.toast("%s." % Security.title(self), "info")
		"tv_stand", "radio":      # Exp 006 (B): the game's balance helper switches it (power, effects)
			var b: Variant = game.get("balance") if game != null else null
			if b is Object and is_instance_valid(b) and b.has_method("toggle_object"):
				b.toggle_object(self)
			else:
				media_on = not media_on
		_:
			if storage_type() != "" or kind == "loot_pile":
				var h: Variant = game.get("storage") if game != null else null
				if h is Object and is_instance_valid(h) and h.has_method("open_object"):
					h.open_object(self)
				elif game != null and game.has_method("toast"):
					game.toast("%s: %s." % [FurnitureStorage.name_of(kind), FurnitureStorage.contents_text(items)], "info")


# --- visuals -----------------------------------------------------------------------

func _refresh_visual() -> void:
	if _pivot == null:
		return
	if visual != null:
		visual.queue_free()
	var s: Vector3 = size3()
	var style := str(_def(kind, mat, "style") if mat != "wood" else "")
	if kind == "fuse_box" and not mains_on:
		style = "off"
	var seed := (hash(uid) if uid != "" else hash(name)) & 0xffff
	if DefenseObjects.handles(kind):          # Exp 006 (D): spikes and drawbridges
		visual = DefenseObjects.make(kind, s, seed, damage_fraction())
	elif SecurityObjects.handles(kind):       # Exp 007 (S): sensors and turret mounts
		visual = SecurityObjects.make_for(self, s, seed, damage_fraction())
	else:
		visual = PropKit.make(kind, s, {"facing": "N", "seed": seed, "damage": damage_fraction(), "style": style})
	visual.name = "Visual"
	visual.position = Vector3(0, base_y(), -float(DEFS[kind].get("out", 0.0)))
	if kind == "floor_lamp":          # Exp 005 (F): the bulb glowing in the shade
		var bulb := PropKit.make("bulb", Vector3(0.11, 0.12, 0.11), {"seed": 3})
		bulb.position = Vector3(0, s.y - 0.14, 0)
		visual.add_child(bulb)
	if kind == "rug" or kind == "loot_pile":
		for gi in visual.find_children("*", "GeometryInstance3D", true, false):
			(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pivot.add_child(visual)
	if FurnitureCatalog.is_lamp(kind):
		PropKit.set_lit(visual, 1.0 if is_lit() else 0.0)
	if DefenseGrid.is_bridge(kind):          # Exp 006 (D): the deck at its current angle
		DefenseObjects.pose_bridge(self)
	_leaf = visual.find_child("Leaf", true, false) as Node3D
	if _leaf != null:
		_leaf_sign = _leaf_open_sign(_leaf)
		_leaf.rotation.y = _leaf_angle
	_apply_cut()


## The leaf opens toward the back (+Z, away from the front). Which way that
## is depends on the hinge side, so look at where the leaf's geometry lies.
static func _leaf_open_sign(leaf: Node3D) -> float:
	var sum := 0.0
	for n in leaf.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		var a := vi.get_aabb()
		var c := leaf.global_transform.affine_inverse() * (vi.global_transform * a.get_center()) if leaf.is_inside_tree() else (vi.transform * a.get_center())
		sum += c.x
	return -1.0 if sum >= 0.0 else 1.0


func _apply_open(instant: bool) -> void:
	if DefenseGrid.is_bridge(kind):          # Exp 006 (D): open = lowered
		DefenseObjects.apply_bridge(self, _shape, instant)
		return
	if _shape != null:
		_shape.set_deferred("disabled", kind == "door" and open)
	if kind != "door":
		return
	var goal := deg_to_rad(95.0) * _leaf_sign if open else 0.0
	if _leaf == null or instant or not is_inside_tree():
		_leaf_angle = goal
		if _leaf != null:
			_leaf.rotation.y = goal
		return
	var tw := create_tween()
	tw.tween_method(func(a: float) -> void:
		_leaf_angle = a
		if is_instance_valid(_leaf):
			_leaf.rotation.y = a, _leaf_angle, goal, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _apply_cut() -> void:
	if visual == null:
		return
	if kind == "door":
		# Exp 012 (V, the user's §18): a door in the cutaway isn't hidden with
		# its wall: it is cut down to a low stub (frame and leaf, DOOR_CUT_H
		# high, a little above the cut walls), so a closed door still reads as
		# closed and an open one as open (the leaf keeps its swing).
		visual.scale.y = DOOR_CUT_H / maxf(size3().y, 0.1) if _cut else 1.0
		return
	set_geometry_cut(visual, _cut)


## Cutaway for meshes: hidden from the camera but still casting shadows (as
## the voxel cutaway does); restores each part's own shadow setting.
static func set_geometry_cut(root: Node, on: bool) -> void:
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if on:
			if not gi.has_meta("cut_cs"):
				gi.set_meta("cut_cs", gi.cast_shadow)
			if gi.get_meta("cut_cs") == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				gi.visible = false
			else:
				gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		elif gi.has_meta("cut_cs"):
			var cs: int = gi.get_meta("cut_cs")
			if cs == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				gi.visible = true
			gi.cast_shadow = cs
			gi.remove_meta("cut_cs")
