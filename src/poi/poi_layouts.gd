class_name PoiLayouts
extends RefCounted
## Experiment 007 (P): the hand-made POI layouts and the reusable placeholder
## template, as plain data (PoiWorld builds them). Plan metres on the same
## lot-sized voxel grid as the house (x about -4.5..18.3, z -3.5..12.3; the
## walkable area is HousePlan.YARD), walls on whole-metre lines, door gaps on
## whole-metre segments (doors are WorldObjects), the camera looking north.
##
## A layout Dictionary:
##   outdoor    true: no building (Pine Woods)
##   ground     "snow" | "lot" (snow with an asphalt lot and a sidewalk)
##   floors     [{rect, art}]: voxel floors (later entries paint over earlier)
##   walls      [{a, b, style, paint, gaps: [{from, to, kind, sill, head}]}]
##              style brick | drywall | siding | plank; gap kind door (a door
##              object stands there) | open | window
##   doors      [{id, x, y, rot, locked, open}]: door objects (rot 0..3 = N E S W)
##   props      [{type, rect, facing, h, block}]: decoration with collision
##   containers [{id, type, rect, facing, h, label, holds, weight, table,
##              picked, needs, noise, secs, minutes, room}]: searchable
##              (holds: item categories it may hold, [] = anything; table:
##              "loot" | "locked" (the location's locked table); picked:
##              already emptied; needs: "crowbar" | "flashlight" | "")
##   pickups    [{id, item, n, at}]: loose items
##   wood       [{id, at, yaw, len, chops}]: fallen trees to chop (planks)
##   trees      [Vector2]: standing pines (collision)
##   rooms      [{id, rect, dark}]
##   entry      Vector2 (arrival), exits [Vector2] ("[E] Leave for home")
##   car        {rect, facing, cargo: Vector2}: where the car stands when Eli drove
##   hide       [Vector2]: where hidden enemies wait (inside rooms)
##   wander     [Rect2]: where wandering enemies walk
##   edges      [Vector2]: where arriving enemies come in from the fog

const ANY := []
const FOOD := ["food", "water"]
const SUPPLIES := ["food", "water", "medical", "utility", "ammo"]
const DESK := ["utility", "medical", "ammo", "tool", "food", "water", "book"]
const GEAR := ["weapon", "ammo", "protective", "utility", "tool", "medical"]
const BOOKS := ["book"]
const MATERIALS := ["material", "tool"]
const VARIANT_NAMES := {"house": "house", "shop": "shop", "clinic": "clinic", "depot": "depot", "armoury": "gun shop", "office": "office"}
const EDGES := [Vector2(-6.4, 12.0), Vector2(20.4, 12.0), Vector2(-6.4, -4.6), Vector2(20.4, -4.6), Vector2(7.0, 14.4)]
## PropKit default sizes (w across the front, h, d) of the types used here.
const SIZES := {
	"shelves": Vector3(1.6, 1.9, 0.45), "fridge": Vector3(0.75, 1.85, 0.7), "counter": Vector3(1.0, 0.92, 0.62),
	"bookshelf": Vector3(1.4, 1.9, 0.4), "boxes": Vector3(1.0, 0.6, 0.7), "storage_chest": Vector3(1.0, 0.6, 0.55),
	"tool_cabinet": Vector3(0.9, 1.8, 0.45), "dresser": Vector3(1.2, 0.8, 0.5), "wardrobe": Vector3(1.5, 2.0, 0.62),
	"dining_table": Vector3(1.6, 0.75, 0.9), "workbench": Vector3(1.8, 0.9, 0.65), "crate": Vector3(0.9, 0.6, 0.6),
	"armchair": Vector3(0.9, 0.85, 0.9), "chair": Vector3(0.45, 0.9, 0.42), "car": Vector3(2.0, 1.45, 4.4),
	"trash_bin_tipped": Vector3(0.6, 0.6, 0.9), "streetlight_dead": Vector3(0.25, 4.5, 0.25), "mailbox": Vector3(0.3, 1.2, 0.3),
	"bush": Vector3(1.2, 0.9, 1.0), "dead_tree": Vector3(0.6, 4.5, 0.6), "cupboard": Vector3(1.0, 0.92, 0.6),
	"vanity": Vector3(0.9, 0.85, 0.52), "plant": Vector3(0.5, 1.1, 0.5),
}
const FRONT := {"N": Vector2(0, -1), "E": Vector2(1, 0), "S": Vector2(0, 1), "W": Vector2(-1, 0)}


static func build(def: Dictionary) -> Dictionary:
	match str(def.get("template", "")):
		"pine_woods":
			return _pine_woods(def)
		"corner_store":
			return _corner_store(def)
		"library":
			return _library(def)
	return _placeholder(def)


# --- helpers -------------------------------------------------------------------------

static func _base() -> Dictionary:
	return {"outdoor": false, "ground": "lot", "floors": [], "walls": [], "doors": [], "props": [], "containers": [],
		"pickups": [], "wood": [], "trees": [], "rooms": [], "entry": Vector2(7, 11), "exits": [], "car": {},
		"hide": [], "wander": [], "edges": EDGES.duplicate()}


## Plan rect of a piece of `type` centred at c, its front facing `facing`.
static func rect_of(type: String, c: Vector2, facing: String) -> Rect2:
	var s: Vector3 = SIZES.get(type, Vector3(1, 1, 0.5))
	var ns := facing == "N" or facing == "S"
	var w := s.x if ns else s.z
	var d := s.z if ns else s.x
	return Rect2(c.x - w * 0.5, c.y - d * 0.5, w, d)


## Where the player stands to use a piece: in front of it.
static func front_point(rect: Rect2, facing: String) -> Vector2:
	var f: Vector2 = FRONT.get(facing, Vector2(0, 1))
	var half := (rect.size.y if f.y != 0.0 else rect.size.x) * 0.5
	return rect.get_center() + f * (half + 0.42)


static func _wall(L: Dictionary, a: Vector2, b: Vector2, style: String, gaps := [], paint := 0xcfc8bb) -> void:
	L["walls"].append({"a": a, "b": b, "style": style, "gaps": gaps, "paint": paint})


static func _win(f: float, t: float, sill := 0.9, head := 2.1) -> Dictionary:
	return {"from": f, "to": t, "kind": "window", "sill": sill, "head": head}


static func _open(f: float, t: float) -> Dictionary:
	return {"from": f, "to": t, "kind": "open"}


static func _dgap(f: float, t: float) -> Dictionary:
	return {"from": f, "to": t, "kind": "door"}


## A door object on the 1 m segment starting at `start` of an integer line
## (axis 0: along x on z = line; 1: along z on x = line).
static func _door(L: Dictionary, id: String, axis: int, line: int, start: int, rot: int, locked := false, open := false) -> void:
	var c := Vector2(start + 0.5, line) if axis == 0 else Vector2(line, start + 0.5)
	L["doors"].append({"id": id, "x": c.x, "y": c.y, "rot": rot, "locked": locked, "open": open})


static func _prop(L: Dictionary, type: String, c: Vector2, facing := "S", block := true) -> void:
	var r := rect_of(type, c, facing)
	L["props"].append({"type": type, "rect": r, "facing": facing, "h": float(SIZES.get(type, Vector3.ONE).y), "block": block})


## A searchable container. opts: weight, table, picked, needs, noise, secs, minutes, room, h.
static func _box(L: Dictionary, id: String, type: String, c: Vector2, facing: String, label: String, holds: Array, opts := {}) -> void:
	var r := rect_of(type, c, facing)
	var big := type in ["boxes", "storage_chest", "crate", "tool_cabinet", "wardrobe"]
	var e := {"id": id, "type": type, "rect": r, "facing": facing, "h": float(SIZES.get(type, Vector3.ONE).y), "label": label,
		"holds": holds, "weight": 1.0, "table": "loot", "picked": false, "needs": "", "noise": 2 if big else 1,
		"secs": 2.4 if big else 1.6, "minutes": 10 if big else 6, "room": ""}
	for k in opts:
		e[k] = opts[k]
	L["containers"].append(e)


static func _pickup(L: Dictionary, id: String, item: String, n: int, at: Vector2) -> void:
	L["pickups"].append({"id": id, "item": item, "n": n, "at": at})


static func _room(L: Dictionary, id: String, r: Rect2, dark := false) -> void:
	L["rooms"].append({"id": id, "rect": r, "dark": dark})


static func _car(L: Dictionary, x: float, z: float) -> void:
	L["car"] = {"rect": Rect2(x, z, 4.4, 2.0), "facing": "E", "cargo": Vector2(x - 0.45, z + 1.0)}


# --- Pine Woods (forest) -----------------------------------------------------------------

static func _pine_woods(_def: Dictionary) -> Dictionary:
	var L := _base()
	L["outdoor"] = true
	L["ground"] = "snow"
	# a small abandoned woodcutter's shelter, open to the south
	_wall(L, Vector2(10, 2), Vector2(13, 2), "plank")
	_wall(L, Vector2(10, 2), Vector2(10, 5), "plank")
	_wall(L, Vector2(13, 2), Vector2(13, 5), "plank")
	L["floors"].append({"rect": Rect2(10, 2, 3, 3), "art": "floor_wood"})
	_room(L, "shelter", Rect2(10, 2, 3, 3))
	_box(L, "tool_cabinet", "tool_cabinet", Vector2(11.0, 2.33), "S", "woodcutter's tool cabinet", MATERIALS,
		{"table": "locked", "needs": "crowbar", "room": "shelter"})
	_box(L, "old_chest", "storage_chest", Vector2(12.3, 2.38), "S", "old chest", ANY, {"room": "shelter"})
	_prop(L, "workbench", Vector2(10.43, 4.0), "E")
	_box(L, "crate", "crate", Vector2(8.4, 4.4), "S", "woodcutter's crate", ["material", "food", "water"])
	_box(L, "hunters_stash", "storage_chest", Vector2(16.6, 0.6), "S", "hunter's stash box", GEAR, {"weight": 0.6})
	_box(L, "cooler", "storage_chest", Vector2(2.4, 9.0), "S", "abandoned cooler", ["food", "water", "medical"], {"weight": 0.8})
	# deadfall to chop (planks; noise; game time)
	L["wood"] = [
		{"id": "log_a", "at": Vector2(3.2, 3.6), "yaw": 0.35, "len": 4.2, "chops": 3},
		{"id": "log_b", "at": Vector2(14.8, 8.6), "yaw": 1.25, "len": 3.8, "chops": 3},
		{"id": "log_c", "at": Vector2(-1.8, 8.4), "yaw": 2.1, "len": 4.0, "chops": 2},
		{"id": "log_d", "at": Vector2(6.4, -1.6), "yaw": 0.05, "len": 4.6, "chops": 3},
	]
	L["trees"] = [Vector2(-3.4, -2.6), Vector2(-0.6, -3.0), Vector2(2.2, -2.2), Vector2(9.6, -2.8), Vector2(12.8, -1.2),
		Vector2(15.6, -2.6), Vector2(18.2, -1.0), Vector2(-3.8, 1.6), Vector2(0.4, 6.2), Vector2(-3.6, 5.4),
		Vector2(5.6, 6.8), Vector2(9.2, 8.0), Vector2(17.6, 4.4), Vector2(15.2, 4.8), Vector2(18.0, 9.8),
		Vector2(-2.8, 11.0), Vector2(2.2, 10.6), Vector2(12.4, 10.2), Vector2(16.4, 12.0), Vector2(6.8, 2.2)]
	_prop(L, "dead_tree", Vector2(4.4, 0.6), "S")
	_prop(L, "dead_tree", Vector2(16.4, 7.0), "S")
	_prop(L, "bush", Vector2(1.6, 4.4), "S", false)
	_prop(L, "bush", Vector2(8.2, 9.4), "E", false)
	_prop(L, "bush", Vector2(13.6, 6.4), "S", false)
	_pickup(L, "snacks", "snacks", 2, Vector2(4.6, 8.6))
	_pickup(L, "water", "water", 1, Vector2(16.6, 6.0))
	_pickup(L, "ammo", "ammo", 3, Vector2(0.4, 0.9))
	_pickup(L, "bandage", "bandage", 1, Vector2(11.6, 3.8))
	L["entry"] = Vector2(7.0, 10.6)
	L["exits"] = [Vector2(7.0, 12.9), Vector2(-5.4, 4.6)]
	_car(L, 9.6, 11.2)
	L["wander"] = [Rect2(-3.0, -2.0, 20.0, 12.0)]
	L["edges"] = [Vector2(-6.4, -4.6), Vector2(20.4, -4.6), Vector2(-6.4, 13.6), Vector2(20.4, 3.0), Vector2(7.0, -5.4)]
	return L


# --- Corner Store (convenience) -------------------------------------------------------------

static func _corner_store(_def: Dictionary) -> Dictionary:
	var L := _base()
	L["floors"] = [{"rect": Rect2(-0.1, -0.1, 14.2, 9.2), "art": "floor_tile"},
		{"rect": Rect2(4, -0.1, 10.1, 3.1), "art": "floor_concrete"}, {"rect": Rect2(-0.1, -0.1, 4.1, 3.1), "art": "floor_wood"}]
	_wall(L, Vector2(0, 9), Vector2(14, 9), "brick", [_win(0.6, 5.4, 0.6, 2.2), _open(6, 8), _win(8.6, 13.4, 0.6, 2.2)])
	_wall(L, Vector2(0, 0), Vector2(14, 0), "brick", [_dgap(6, 7)])
	_wall(L, Vector2(0, 0), Vector2(0, 9), "brick", [_win(6.5, 8.5, 1.0)])
	_wall(L, Vector2(14, 0), Vector2(14, 9), "brick", [_win(5, 7, 1.0)])
	_wall(L, Vector2(0, 3), Vector2(14, 3), "drywall", [_dgap(1, 2), _open(5, 7), _dgap(11, 12)], 0xd8d2c4)
	_wall(L, Vector2(4, 0), Vector2(4, 3), "drywall", [], 0xd8d2c4)
	_wall(L, Vector2(9, 0), Vector2(9, 3), "drywall", [], 0xd8d2c4)
	_door(L, "office", 0, 3, 1, 2)
	_door(L, "rear", 0, 0, 6, 0)
	_door(L, "stockroom", 0, 3, 11, 2, true)
	_room(L, "sales", Rect2(0, 3, 14, 6))
	_room(L, "office", Rect2(0, 0, 4, 3))
	_room(L, "back", Rect2(4, 0, 5, 3))
	_room(L, "stockroom", Rect2(9, 0, 5, 3))
	# aisles: some shelves were picked clean before you came
	_box(L, "aisle_1a", "shelves", Vector2(2.6, 4.62), "S", "shelf", ANY, {"room": "sales"})
	_box(L, "aisle_1b", "shelves", Vector2(4.2, 4.62), "S", "shelf", ANY, {"room": "sales", "picked": true})
	_box(L, "aisle_1c", "shelves", Vector2(6.6, 4.62), "S", "shelf", ANY, {"room": "sales"})
	_box(L, "aisle_2a", "shelves", Vector2(2.6, 6.22), "S", "shelf", ANY, {"room": "sales", "picked": true})
	_box(L, "aisle_2b", "shelves", Vector2(4.2, 6.22), "S", "shelf", ANY, {"room": "sales"})
	_box(L, "aisle_2c", "shelves", Vector2(6.6, 6.22), "S", "shelf", ANY, {"room": "sales"})
	_box(L, "fridge_1", "fridge", Vector2(0.45, 3.6), "E", "drinks fridge", FOOD, {"room": "sales"})
	_box(L, "fridge_2", "fridge", Vector2(0.45, 4.35), "E", "drinks fridge", FOOD, {"room": "sales", "picked": true})
	_box(L, "fridge_3", "fridge", Vector2(0.45, 5.1), "E", "drinks fridge", FOOD, {"room": "sales"})
	_box(L, "checkout", "counter", Vector2(10.5, 6.8), "N", "checkout counter", SUPPLIES, {"room": "sales"})
	_prop(L, "counter", Vector2(11.5, 6.8), "N")
	_box(L, "snack_rack", "shelves", Vector2(13.68, 4.0), "W", "snack rack", ["food", "water", "medical"], {"room": "sales"})
	_box(L, "back_boxes", "boxes", Vector2(5.0, 0.55), "S", "cardboard boxes", ANY, {"room": "back"})
	_box(L, "back_boxes_2", "boxes", Vector2(8.45, 1.7), "W", "cardboard boxes", ANY, {"room": "back"})
	_box(L, "desk", "dining_table", Vector2(2.0, 1.25), "S", "desk", DESK, {"room": "office"})
	_box(L, "filing", "dresser", Vector2(3.2, 0.37), "S", "filing cabinet", DESK, {"room": "office"})
	# the stockroom (locked: a crowbar) holds the better loot (the location's locked table)
	_box(L, "stock_shelf_1", "shelves", Vector2(10.2, 0.35), "S", "stockroom shelf", ANY, {"room": "stockroom", "table": "locked"})
	_box(L, "stock_shelf_2", "shelves", Vector2(12.0, 0.35), "S", "stockroom shelf", ANY, {"room": "stockroom", "table": "locked"})
	_box(L, "stock_boxes", "boxes", Vector2(13.45, 1.9), "W", "stock boxes", ANY, {"room": "stockroom", "table": "locked"})
	_pickup(L, "can", "canned_food", 1, Vector2(8.0, 5.4))
	_pickup(L, "rounds", "ammo", 2, Vector2(15.6, 2.0))
	_prop(L, "trash_bin_tipped", Vector2(15.4, 7.6), "W")
	_prop(L, "streetlight_dead", Vector2(-1.2, 9.8), "S")
	_prop(L, "mailbox", Vector2(13.6, 9.9), "S")
	L["entry"] = Vector2(7.0, 10.9)
	L["exits"] = [Vector2(10.2, 12.9), Vector2(6.5, -1.4)]
	_car(L, 1.0, 11.0)
	L["hide"] = [Vector2(11.6, 1.6), Vector2(2.8, 2.2), Vector2(6.6, 1.4)]
	L["wander"] = [Rect2(1.2, 3.6, 12.0, 4.8), Rect2(-3.0, 9.8, 20.0, 2.6)]
	return L


# --- Public Library (library) -----------------------------------------------------------------

static func _library(_def: Dictionary) -> Dictionary:
	var L := _base()
	L["floors"] = [{"rect": Rect2(-0.1, -0.1, 16.2, 10.2), "art": "floor_wood"},
		{"rect": Rect2(5, 5, 6, 5.1), "art": "floor_tile"}, {"rect": Rect2(5, -0.1, 6, 5.1), "art": "floor_concrete"}]
	_wall(L, Vector2(0, 10), Vector2(16, 10), "brick", [_win(0.6, 4.4, 0.8), _dgap(7, 8), _dgap(8, 9), _win(12, 15, 1.2)])
	_wall(L, Vector2(0, 0), Vector2(16, 0), "brick", [_win(1, 4, 1.3), _dgap(14, 15)])
	_wall(L, Vector2(0, 0), Vector2(0, 10), "brick", [_win(6, 9, 0.8)])
	_wall(L, Vector2(16, 0), Vector2(16, 10), "brick", [_win(2, 4, 1.4)])
	_wall(L, Vector2(5, 0), Vector2(5, 10), "drywall", [_open(7, 8)], 0xc9c2a8)
	_wall(L, Vector2(0, 5), Vector2(11, 5), "drywall", [_dgap(2, 3), _dgap(7, 8)], 0xc9c2a8)
	_wall(L, Vector2(11, 0), Vector2(11, 10), "drywall", [_dgap(7, 8)], 0xc9c2a8)
	_door(L, "front_l", 0, 10, 7, 2, false, true)
	_door(L, "front_r", 0, 10, 8, 2)
	_door(L, "rear", 0, 0, 14, 0)
	_door(L, "office", 0, 5, 2, 2)
	_door(L, "archive", 0, 5, 7, 2, true)
	_door(L, "stacks", 1, 11, 7, 1)
	_room(L, "reading", Rect2(0, 5, 5, 5))
	_room(L, "lobby", Rect2(5, 5, 6, 5))
	_room(L, "office", Rect2(0, 0, 5, 5))
	_room(L, "archive", Rect2(5, 0, 6, 5), true)
	_room(L, "stacks", Rect2(11, 0, 5, 10))
	# reading room
	_box(L, "read_shelf_1", "bookshelf", Vector2(1.0, 5.3), "S", "bookshelf", BOOKS, {"room": "reading"})
	_box(L, "read_shelf_2", "bookshelf", Vector2(4.1, 5.3), "S", "bookshelf", BOOKS, {"room": "reading"})
	_prop(L, "dining_table", Vector2(2.5, 7.6), "S")
	_prop(L, "armchair", Vector2(1.0, 9.0), "N", false)
	_prop(L, "armchair", Vector2(3.9, 9.0), "N", false)
	# lobby
	_box(L, "reception", "counter", Vector2(9.4, 6.0), "S", "reception desk", ["food", "water", "medical", "utility"], {"room": "lobby"})
	_prop(L, "counter", Vector2(10.4, 6.0), "S")
	_box(L, "returns", "boxes", Vector2(6.0, 9.3), "N", "book returns", ["book", "food", "water"], {"room": "lobby", "weight": 0.6})
	# office
	_box(L, "desk", "dining_table", Vector2(1.9, 1.6), "S", "librarian's desk", DESK, {"room": "office"})
	_box(L, "filing", "dresser", Vector2(3.9, 0.37), "S", "filing cabinet", DESK, {"room": "office"})
	_box(L, "supplies", "tool_cabinet", Vector2(0.33, 3.6), "E", "supply cupboard", ["utility", "medical", "tool", "water"], {"room": "office"})
	# the archive (locked: a crowbar; pitch dark: a flashlight): the locked table
	var arch := {"room": "archive", "table": "locked", "needs": "flashlight"}
	_box(L, "archive_box_1", "boxes", Vector2(6.2, 0.5), "S", "archive boxes", ANY, arch)
	_box(L, "archive_shelf", "shelves", Vector2(8.4, 0.33), "S", "archive shelf", ANY, arch)
	_box(L, "archive_box_2", "boxes", Vector2(10.3, 2.2), "W", "archive boxes", ANY, arch)
	# the stacks: rows of shelves, little light, not every shelf gives something
	_box(L, "stack_a1", "bookshelf", Vector2(12.6, 1.6), "W", "bookshelf", BOOKS, {"room": "stacks"})
	_box(L, "stack_a2", "bookshelf", Vector2(12.6, 3.0), "W", "bookshelf", BOOKS, {"room": "stacks"})
	_box(L, "stack_b1", "bookshelf", Vector2(14.2, 1.6), "E", "bookshelf", BOOKS, {"room": "stacks"})
	_box(L, "stack_b2", "bookshelf", Vector2(14.2, 3.0), "E", "bookshelf", BOOKS, {"room": "stacks"})
	_box(L, "stack_c1", "bookshelf", Vector2(12.6, 5.4), "W", "bookshelf", BOOKS, {"room": "stacks"})
	_box(L, "stack_c2", "bookshelf", Vector2(14.2, 5.4), "E", "reference shelf", ["book", "utility"], {"room": "stacks"})
	_box(L, "stack_d", "bookshelf", Vector2(15.7, 8.6), "W", "bookshelf", BOOKS, {"room": "stacks"})
	_box(L, "stack_e", "bookshelf", Vector2(12.2, 9.6), "N", "bookshelf", BOOKS, {"room": "stacks", "picked": true})
	_pickup(L, "snacks", "snacks", 1, Vector2(1.4, 6.6))
	_pickup(L, "water", "water", 1, Vector2(10.4, 8.9))
	_prop(L, "streetlight_dead", Vector2(-1.4, 10.6), "S")
	_prop(L, "trash_bin_tipped", Vector2(17.2, 8.4), "W")
	L["entry"] = Vector2(8.5, 11.3)
	L["exits"] = [Vector2(11.2, 12.8), Vector2(14.5, -1.3)]
	_car(L, 1.4, 11.0)
	L["hide"] = [Vector2(13.4, 4.3), Vector2(8.0, 2.6), Vector2(3.0, 3.2), Vector2(15.0, 7.0)]
	L["wander"] = [Rect2(11.4, 0.6, 4.2, 9.0), Rect2(5.6, 6.8, 5.0, 2.6), Rect2(-3.0, 10.6, 22.0, 2.4)]
	return L


# --- the placeholder template (every other location) -----------------------------------------

## [type, label, holds, opts] per slot (A1 A2 A3 in the left room, B1 B2 B3 in the right).
const PLACEHOLDER_SETS := {
	"house": [["wardrobe", "wardrobe", GEAR, {}], ["dresser", "dresser", DESK, {}], ["boxes", "moving boxes", ANY, {}],
		["counter", "kitchen cupboard", SUPPLIES, {}], ["fridge", "fridge", FOOD, {}], ["storage_chest", "locked garage chest", ANY, {"table": "locked", "needs": "crowbar"}]],
	"shop": [["shelves", "shelf", ANY, {}], ["shelves", "shelf", ANY, {}], ["shelves", "shelf", ANY, {"picked": true}],
		["shelves", "back shelf", ANY, {}], ["fridge", "fridge", FOOD, {}], ["storage_chest", "locked stock crate", ANY, {"table": "locked", "needs": "crowbar"}]],
	"clinic": [["tool_cabinet", "medicine cabinet", ["medical", "utility", "water"], {}], ["shelves", "supply shelf", ANY, {}], ["counter", "reception", SUPPLIES, {}],
		["tool_cabinet", "drug cage", ANY, {"table": "locked", "needs": "crowbar"}], ["shelves", "shelf", ANY, {}], ["dresser", "drawers", DESK, {}]],
	"depot": [["shelves", "shelf", ANY, {}], ["tool_cabinet", "tool cabinet", ["tool", "material", "ammo", "utility"], {}], ["boxes", "crates of parts", ANY, {}],
		["storage_chest", "locked site box", ANY, {"table": "locked", "needs": "crowbar"}], ["shelves", "shelf", ANY, {}], ["boxes", "boxes", ANY, {}]],
	"armoury": [["tool_cabinet", "gun locker", ANY, {"table": "locked", "needs": "crowbar"}], ["shelves", "shelf", ANY, {}], ["counter", "counter", ANY, {}],
		["shelves", "shelf", ANY, {}], ["storage_chest", "ammo chest", ["ammo", "weapon", "protective"], {}], ["dresser", "drawers", DESK, {}]],
	"office": [["bookshelf", "bookshelf", BOOKS, {}], ["bookshelf", "bookshelf", BOOKS, {}], ["dining_table", "desk", DESK, {}],
		["tool_cabinet", "locked cabinet", ANY, {"table": "locked", "needs": "crowbar"}], ["bookshelf", "bookshelf", BOOKS, {}], ["dresser", "drawers", DESK, {}]],
}
## Slot: wall it stands against (inner faces: N z 2.1, S z 7.9, W x 3.1, E x 10.9) and its position along it.
const PLACEHOLDER_SLOTS := [["N", 4.2], ["W", 4.0], ["S", 4.4], ["N", 7.9], ["E", 4.0], ["S", 9.3]]
const PLACEHOLDER_FLOOR := {"house": "floor_wood", "shop": "floor_tile", "clinic": "floor_tile", "depot": "floor_concrete",
	"armoury": "floor_concrete", "office": "floor_wood"}


static func _placeholder(def: Dictionary) -> Dictionary:
	var L := _base()
	var variant := str(def.get("variant", "house"))
	var style := "siding" if variant == "house" else ("plank" if variant == "depot" else "brick")
	L["floors"] = [{"rect": Rect2(2.9, 1.9, 8.2, 6.2), "art": PLACEHOLDER_FLOOR.get(variant, "floor_wood")}]
	_wall(L, Vector2(3, 8), Vector2(11, 8), style, [_win(3.5, 5.5), _dgap(6, 7), _win(8, 10.5)])
	_wall(L, Vector2(3, 2), Vector2(11, 2), style, [_win(4.5, 6.5, 1.2), _dgap(9, 10)])
	_wall(L, Vector2(3, 2), Vector2(3, 8), style, [_win(6.4, 7.6)])
	_wall(L, Vector2(11, 2), Vector2(11, 8), style, [_win(6.4, 7.6)])
	_wall(L, Vector2(7, 2), Vector2(7, 8), "drywall", [_open(4, 5)])
	_door(L, "front", 0, 8, 6, 2)
	_door(L, "rear", 0, 2, 9, 0)
	var dark := bool(def.get("dark", false))
	_room(L, "left", Rect2(3, 2, 4, 6), dark)
	_room(L, "right", Rect2(7, 2, 4, 6), dark)
	var set: Array = PLACEHOLDER_SETS.get(variant, PLACEHOLDER_SETS["house"])
	for i in set.size():
		var e: Array = set[i]
		var slot: Array = PLACEHOLDER_SLOTS[i]
		var type: String = e[0]
		var s: Vector3 = SIZES.get(type, Vector3(1, 1, 0.5))
		var c := Vector2.ZERO
		var facing := "S"
		match str(slot[0]):
			"N":
				c = Vector2(slot[1], 2.1 + s.z * 0.5)
				facing = "S"
			"S":
				c = Vector2(slot[1], 7.9 - s.z * 0.5)
				facing = "N"
			"W":
				c = Vector2(3.1 + s.z * 0.5, slot[1])
				facing = "E"
			"E":
				c = Vector2(10.9 - s.z * 0.5, slot[1])
				facing = "W"
		var opts: Dictionary = (e[3] as Dictionary).duplicate()
		opts["room"] = "left" if i < 3 else "right"
		if dark and str(opts.get("needs", "")) == "":
			opts["needs"] = "flashlight"
		_box(L, "slot_%d" % (i + 1), type, c, facing, e[1], e[2], opts)
	_pickup(L, "loose", "snacks" if variant != "depot" else "nails", 1 if variant != "depot" else 6, Vector2(5.2, 6.4))
	_prop(L, "streetlight_dead", Vector2(1.2, 8.8), "S")
	_prop(L, "trash_bin_tipped", Vector2(12.6, 7.2), "W")
	L["entry"] = Vector2(6.5, 9.6)
	L["exits"] = [Vector2(9.4, 11.4), Vector2(9.5, 0.6)]
	_car(L, -0.6, 9.6)
	L["hide"] = [Vector2(9.0, 5.0), Vector2(5.0, 5.6)]
	L["wander"] = [Rect2(3.5, 2.5, 7.0, 5.0), Rect2(-2.0, 8.6, 16.0, 2.8)]
	return L
