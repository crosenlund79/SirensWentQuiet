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
##              picked, needs, noise, secs, minutes, room, stash}]: searchable
##              (holds: item categories it may hold, [] = anything; table:
##              "loot" | "locked" (the location's locked table) | "stash";
##              picked: already emptied; needs: "crowbar" | "flashlight" | "";
##              stash: Exp 009 (G) the one main stash, PoiState's own roll)
##   stash      Exp 009 (G): the main stash container's id
##   pickups    [{id, item, n, at}]: loose items
##   wood       [{id, at, yaw, len, chops}]: fallen trees to chop (planks)
##   trees      [Vector2]: standing pines (collision)
##   rooms      [{id, rect, dark}]
##   entry      Vector2 (arrival), exits [Vector2] ("[E] Leave for home")
##   car        {rect, facing, cargo: Vector2}: where the car stands when Eli drove
##   hide       [Vector2]: where hidden enemies wait (inside rooms)
##   wander     [Rect2]: where wandering enemies walk
##   edges      [Vector2]: where arriving enemies come in from the fog
## Optional (SPEC-008; layouts without them work as before):
##   peek       [{at, look}]: a spot outside a window and the point inside
##              it watches
##   doorways   [Vector2]: points just outside each entrance
##   lights     [{at, h, color, energy, flicker, kind, range, yaw}]: small
##              lights left burning (PoiDressing draws them)
##   story      [{type, at, yaw, ...}]: signs of who was here first, no
##              gameplay (types: PoiDressing)

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
	"coffee_table": Vector3(1.1, 0.45, 0.6), "stool": Vector3(0.4, 0.7, 0.4),      # Exp 008 (H)
	"gun_rack": Vector3(1.6, 1.9, 0.35), "exam_bed": Vector3(1.9, 0.75, 0.7), "lumber_rack": Vector3(2.0, 1.8, 0.7),
}
const FRONT := {"N": Vector2(0, -1), "E": Vector2(1, 0), "S": Vector2(0, 1), "W": Vector2(-1, 0)}
## A story piece's yaw that turns its -z toward that side (HouseWorld.FACING_YAW).
const YAW := {"N": 0.0, "E": -PI * 0.5, "S": PI, "W": PI * 0.5}


static func build(def: Dictionary) -> Dictionary:
	match str(def.get("template", "")):
		"pine_woods":
			return _pine_woods(def)
		"corner_store":
			return _corner_store(def)
		"library":
			return _library(def)
		"hardware_store":
			return _hardware_store(def)
		"gun_shop":
			return _gun_shop(def)
		"clinic":
			return _clinic(def)
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
		"holds": holds, "weight": 1.0, "table": "loot", "picked": false, "needs": "", "noise": 1,
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


## Exp 008 (H): a story detail (PoiDressing types). opts: yaw, or "lean"
## (N/E/S/W: the side its back is to), and the type's own keys.
static func _tell(L: Dictionary, type: String, at: Vector2, opts := {}) -> void:
	var e := {"type": type, "at": at, "yaw": float(YAW.get(str(opts.get("lean", "")), 0.0))}
	for k in opts:
		if k != "lean":
			e[k] = opts[k]
	if not L.has("story"):
		L["story"] = []
	L["story"].append(e)


## Exp 008 (H): a light left burning (PoiDressing kinds).
static func _light(L: Dictionary, at: Vector2, h: float, kind: String, color: int, energy: float, flicker := false, opts := {}) -> void:
	var e := {"at": at, "h": h, "kind": kind, "color": color, "energy": energy, "flicker": flicker}
	for k in opts:
		e[k] = opts[k]
	if not L.has("lights"):
		L["lights"] = []
	L["lights"].append(e)


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
		{"table": "stash", "stash": true, "needs": "crowbar", "room": "shelter"})      # Exp 009 (G): the main stash
	L["stash"] = "tool_cabinet"
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
		Vector2(5.6, 6.8), Vector2(9.2, 7.6), Vector2(17.6, 4.4), Vector2(15.2, 4.8), Vector2(19.2, 8.0),
		Vector2(-5.0, 8.6), Vector2(6.8, 2.2)]     # none on the south side: they would stand between the camera and Eli
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
	L["doorways"] = [Vector2(11.5, 5.8)]      # Exp 008 (E): into the shelter (no windows to look in by)
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
	_box(L, "stock_shelf_1", "shelves", Vector2(10.2, 0.35), "S", "stockroom shelf", ANY, {"room": "stockroom", "table": "stash", "stash": true})
	L["stash"] = "stock_shelf_1"            # Exp 009 (G): the main stash
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
	# Exp 008 (E): the shop windows and the side windows; the open front and the back door
	L["peek"] = [{"at": Vector2(3.0, 9.75), "look": Vector2(3.0, 6.0)}, {"at": Vector2(11.0, 9.75), "look": Vector2(11.0, 6.0)},
		{"at": Vector2(-0.75, 7.5), "look": Vector2(3.0, 7.5)}, {"at": Vector2(14.75, 6.0), "look": Vector2(11.0, 5.5)}]
	L["doorways"] = [Vector2(7.0, 9.7), Vector2(6.5, -0.7)]
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
	_box(L, "archive_shelf", "shelves", Vector2(8.4, 0.33), "S", "archive shelf", ANY, {"room": "archive", "table": "stash", "needs": "flashlight", "stash": true})
	L["stash"] = "archive_shelf"            # Exp 009 (G): the main stash
	_box(L, "archive_box_2", "boxes", Vector2(10.3, 2.2), "W", "archive boxes", ANY, arch)
	# the stacks: rows of shelves, little light, not every shelf gives something
	_box(L, "stack_a1", "bookshelf", Vector2(12.6, 1.6), "W", "bookshelf", BOOKS, {"room": "stacks"})
	_box(L, "stack_a2", "bookshelf", Vector2(12.6, 3.0), "W", "bookshelf", BOOKS, {"room": "stacks", "picked": true})
	_box(L, "stack_b1", "bookshelf", Vector2(14.2, 1.6), "E", "bookshelf", BOOKS, {"room": "stacks"})
	_box(L, "stack_b2", "bookshelf", Vector2(14.2, 3.0), "E", "bookshelf", BOOKS, {"room": "stacks", "picked": true})
	_box(L, "stack_c1", "bookshelf", Vector2(12.6, 5.4), "W", "bookshelf", BOOKS, {"room": "stacks"})
	_box(L, "stack_c2", "bookshelf", Vector2(14.2, 5.4), "E", "reference shelf", ["book", "utility"], {"room": "stacks"})
	_box(L, "stack_d", "bookshelf", Vector2(15.7, 8.6), "W", "bookshelf", BOOKS, {"room": "stacks", "picked": true})
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
	# Exp 008 (E): the reading room, stacks and office windows; the front doors and the back door
	L["peek"] = [{"at": Vector2(2.5, 10.75), "look": Vector2(2.5, 7.5)}, {"at": Vector2(13.5, 10.75), "look": Vector2(13.5, 7.0)},
		{"at": Vector2(2.5, -0.75), "look": Vector2(2.5, 2.5)}, {"at": Vector2(-0.75, 7.5), "look": Vector2(2.5, 7.5)},
		{"at": Vector2(16.75, 3.0), "look": Vector2(13.5, 3.0)}]
	L["doorways"] = [Vector2(8.0, 10.7), Vector2(14.5, -0.7)]
	return L


# --- Hardware Store (hardware) -----------------------------------------------------------------
# Exp 008 (H): a wide brick store on the ring road with its delivery yard fenced in behind.
# Lumber racks on the west wall, tool aisles running north-south (the camera looks down them),
# the till by the smashed entrance, a storage room with the loading door into the yard and,
# behind a jammed door, the stockroom with the better building stock.

static func _hardware_store(_def: Dictionary) -> Dictionary:
	var L := _base()
	L["floors"] = [{"rect": Rect2(-0.1, 2.9, 15.2, 7.2), "art": "floor_concrete"},
		{"rect": Rect2(11, 2.9, 4.1, 7.2), "art": "floor_wood"}, {"rect": Rect2(1.9, -3.1, 13.2, 6.0), "art": "asphalt"}]
	_wall(L, Vector2(0, 10), Vector2(15, 10), "brick", [_win(0.6, 4.4, 0.6, 2.2), _open(5, 7), _win(7.6, 10.4, 0.6, 2.2), _win(12.4, 14.0, 1.5, 2.2)])
	_wall(L, Vector2(0, 3), Vector2(15, 3), "brick", [_win(6, 8, 1.2, 2.1), _open(12, 14)])
	_wall(L, Vector2(0, 3), Vector2(0, 10), "brick", [_win(8.2, 9.6, 1.0, 2.1)])
	_wall(L, Vector2(15, 3), Vector2(15, 10), "brick")
	_wall(L, Vector2(11, 3), Vector2(11, 10), "drywall", [_dgap(4, 5)], 0xd6d0c0)
	_wall(L, Vector2(11, 7), Vector2(15, 7), "drywall", [_dgap(13, 14)], 0xd6d0c0)
	# the delivery yard's plank fence; the gate is gone
	_wall(L, Vector2(2, -3), Vector2(15, -3), "plank", [_open(8, 10)])
	_wall(L, Vector2(2, -3), Vector2(2, 3), "plank")
	_wall(L, Vector2(15, -3), Vector2(15, 3), "plank")
	_door(L, "storage", 1, 11, 4, 3)
	_door(L, "stockroom", 0, 7, 13, 0, true)      # jammed: a crowbar
	_room(L, "sales", Rect2(0, 3, 11, 7))
	_room(L, "storage", Rect2(11, 3, 4, 4))
	_room(L, "stockroom", Rect2(11, 7, 4, 3))
	var sales := {"room": "sales"}
	# lumber racks: one stripped bare
	_box(L, "lumber_1", "lumber_rack", Vector2(0.45, 4.3), "E", "lumber rack", MATERIALS, {"room": "sales", "weight": 1.5, "secs": 2.4, "minutes": 10})
	_box(L, "lumber_2", "lumber_rack", Vector2(0.45, 6.5), "E", "lumber rack", MATERIALS, {"room": "sales", "picked": true})
	# two gondolas of shelves, back to back
	_box(L, "hand_tools", "shelves", Vector2(3.775, 5.0), "W", "hand tool shelf", ["tool", "utility"], sales)
	_box(L, "fasteners", "shelves", Vector2(4.225, 5.0), "E", "shelf of nails and screws", ["material"], sales)
	_box(L, "paint", "shelves", Vector2(3.775, 6.6), "W", "paint shelf", ANY, {"room": "sales", "picked": true})
	_box(L, "electrical", "shelves", Vector2(4.225, 6.6), "E", "electrical shelf", ["material", "utility"], sales)
	_box(L, "plumbing", "shelves", Vector2(6.775, 5.0), "W", "plumbing shelf", ANY, {"room": "sales", "picked": true})
	_box(L, "power_tools", "shelves", Vector2(7.225, 5.0), "E", "power tool shelf", ["tool", "utility"], sales)
	_box(L, "manuals", "shelves", Vector2(6.775, 6.6), "W", "shelf of how-to books", ["book", "material"], sales)
	_box(L, "garden", "shelves", Vector2(7.225, 6.6), "E", "garden aisle", ["material", "water", "food"], {"room": "sales", "picked": true})
	_box(L, "tool_wall", "tool_cabinet", Vector2(10.675, 6.2), "W", "tool cabinet", ["tool", "material", "utility"], sales)
	# the till by the entrance, a key-cutting bench behind it
	_box(L, "till", "counter", Vector2(8.0, 8.4), "W", "till", DESK, sales)
	_prop(L, "counter", Vector2(8.0, 9.4), "W")
	_box(L, "bench", "workbench", Vector2(10.575, 8.3), "W", "key-cutting bench", MATERIALS, {"room": "sales", "weight": 0.6})
	# the storage room and its loading door
	var store := {"room": "storage"}
	_box(L, "storage_shelf", "shelves", Vector2(14.675, 4.6), "W", "storage shelf", ANY, store)
	_box(L, "storage_boxes", "boxes", Vector2(12.0, 6.55), "N", "boxes of stock", ANY, store)
	_box(L, "storage_crate", "crate", Vector2(14.45, 6.6), "N", "crate", MATERIALS, store)
	# the jammed stockroom: the location's locked table
	var stock := {"room": "stockroom", "table": "locked"}
	_box(L, "stock_shelf", "shelves", Vector2(11.325, 8.6), "E", "stockroom shelf", ANY, stock)
	_box(L, "stock_cage", "tool_cabinet", Vector2(14.675, 8.2), "W", "tool cage", ["tool", "material", "book", "utility"],
		{"room": "stockroom", "table": "stash", "stash": true})
	L["stash"] = "stock_cage"               # Exp 009 (G): the main stash
	_box(L, "stock_crate", "crate", Vector2(13.4, 9.55), "N", "crate of fittings", MATERIALS, stock)
	# the yard: the last delivery, half unloaded
	_box(L, "yard_crate_1", "crate", Vector2(4.6, -2.6), "S", "delivery crate", MATERIALS)
	_box(L, "yard_crate_2", "crate", Vector2(5.6, -2.6), "S", "delivery crate", MATERIALS, {"picked": true})
	_box(L, "yard_pallet", "boxes", Vector2(13.6, -2.55), "S", "pallet of boxes", ANY)
	_prop(L, "trash_bin_tipped", Vector2(3.0, 2.2), "W")
	_prop(L, "streetlight_dead", Vector2(-1.4, 10.8), "S")
	_pickup(L, "nails", "nails", 6, Vector2(5.5, 7.9))
	_pickup(L, "planks", "wood", 2, Vector2(2.2, 8.9))
	_pickup(L, "scrap", "scrap", 2, Vector2(11.0, -1.2))
	# who was here first: they smashed the doors, started boarding the windows and gave up
	_tell(L, "glass", Vector2(6.0, 9.6), {"w": 2.2, "d": 0.9})
	_tell(L, "barricade", Vector2(2.4, 9.68), {"lean": "S", "len": 1.4})
	_tell(L, "planks", Vector2(1.6, 7.9), {"n": 3, "yaw": 0.3})
	_tell(L, "spill", Vector2(5.5, 4.7), {"yaw": 0.4})
	_tell(L, "toppled", Vector2(9.6, 7.5), {"piece": "stool", "yaw": 1.1})
	_tell(L, "pallet", Vector2(12.7, 1.6))
	_tell(L, "pallet", Vector2(10.8, -2.2), {"load": "bags"})
	_tell(L, "pallet", Vector2(7.0, -1.2), {"load": "boxes", "yaw": 0.2})
	_tell(L, "planks", Vector2(4.8, -0.8), {"n": 5, "len": 2.4, "yaw": -0.2})
	# a tube dying over the aisles, a battery lantern on the till, the exit light over the loading door
	_light(L, Vector2(5.5, 6.0), 2.5, "tube", 0xe4ecff, 1.4, true)
	_light(L, Vector2(8.0, 8.1), 0.92, "lantern", 0xffd29a, 0.9)
	_light(L, Vector2(13.0, 3.2), 2.35, "emergency", 0x55ff88, 0.55)
	L["peek"] = [{"at": Vector2(2.5, 10.9), "look": Vector2(2.5, 8.0)}, {"at": Vector2(9.0, 10.9), "look": Vector2(9.0, 8.0)},
		{"at": Vector2(-0.9, 8.9), "look": Vector2(1.8, 8.9)}, {"at": Vector2(7.0, 2.2), "look": Vector2(5.5, 4.0)},
		{"at": Vector2(13.2, 10.9), "look": Vector2(13.2, 8.6)}]
	L["doorways"] = [Vector2(6.0, 10.8), Vector2(13.0, 2.1), Vector2(9.0, -3.8)]
	L["entry"] = Vector2(6.0, 11.0)
	L["exits"] = [Vector2(2.0, 13.0), Vector2(9.0, -4.6)]
	_car(L, 9.8, 11.3)
	L["hide"] = [Vector2(12.4, 8.5), Vector2(12.6, 4.4), Vector2(5.5, 4.0), Vector2(14.0, -1.5)]
	L["wander"] = [Rect2(1.4, 7.8, 5.6, 1.8), Rect2(3.0, -2.0, 11.0, 4.0), Rect2(-3.0, 11.0, 12.0, 2.6)]
	return L


# --- Pike's Guns (gun_shop) ---------------------------------------------------------------------
# Exp 008 (H): a small L-shaped shop: the shop floor across the front, an office and the back
# room behind it, a snowy back lot in the corner of the L. Looted early: a rack stands empty and
# the display case is smashed, but nobody got through the back room's steel door.

static func _gun_shop(_def: Dictionary) -> Dictionary:
	var L := _base()
	L["floors"] = [{"rect": Rect2(0.9, 4.9, 10.2, 5.2), "art": "floor_wood"},
		{"rect": Rect2(4.9, 0.9, 6.2, 4.2), "art": "floor_concrete"}, {"rect": Rect2(4.9, 0.9, 3.1, 4.1), "art": "floor_wood_light"}]
	_wall(L, Vector2(1, 10), Vector2(11, 10), "brick", [_win(1.6, 4.4, 1.0, 2.1), _dgap(6, 7), _win(8.0, 10.4, 1.0, 2.1)])
	_wall(L, Vector2(1, 5), Vector2(1, 10), "brick")
	_wall(L, Vector2(1, 5), Vector2(5, 5), "brick")
	_wall(L, Vector2(5, 5), Vector2(11, 5), "drywall", [_dgap(6, 7), _dgap(9, 10)], 0xcfc6b4)
	_wall(L, Vector2(5, 1), Vector2(5, 5), "brick", [_dgap(2, 3)])
	_wall(L, Vector2(5, 1), Vector2(11, 1), "brick", [_win(5.8, 7.2, 1.2, 2.0)])
	_wall(L, Vector2(11, 1), Vector2(11, 10), "brick", [_win(7.6, 9.2, 1.2, 2.1)])
	_wall(L, Vector2(8, 1), Vector2(8, 5), "drywall", [], 0xcfc6b4)
	_door(L, "front", 0, 10, 6, 2, false, true)
	_door(L, "office", 0, 5, 6, 2)
	_door(L, "back_room", 0, 5, 9, 2, true)
	L["doors"].back()["mat"] = "metal"            # the back room's steel door: a crowbar
	_door(L, "back", 1, 5, 2, 3)
	_room(L, "shop", Rect2(1, 5, 10, 5))
	_room(L, "office", Rect2(5, 1, 3, 4))
	_room(L, "back_room", Rect2(8, 1, 3, 4))
	var shop := {"room": "shop"}
	# the counter: a glass display case, the till, and the long guns on the wall behind
	_box(L, "display_case", "counter", Vector2(7.5, 7.0), "S", "glass display case", ["ammo", "utility", "protective"], shop)
	_prop(L, "counter", Vector2(8.5, 7.0), "S")
	_box(L, "till", "counter", Vector2(9.5, 7.0), "S", "till", DESK, {"room": "shop", "weight": 0.6})
	_box(L, "wall_rack", "gun_rack", Vector2(8.0, 5.275), "S", "gun rack", ["weapon"], {"room": "shop", "weight": 0.5})
	# the racks on the west wall: one picked over, one stripped bare (story)
	_box(L, "rifle_rack", "gun_rack", Vector2(1.275, 6.2), "E", "rifle rack", ["weapon", "ammo"], {"room": "shop", "weight": 0.5})
	_tell(L, "empty_rack", Vector2(1.275, 8.2), {"rect": rect_of("gun_rack", Vector2(1.275, 8.2), "E"), "facing": "E", "h": 1.9})
	# the ammunition gondola and the smashed case in the window
	_box(L, "ammo_w", "shelves", Vector2(3.775, 7.4), "W", "ammunition shelf", ["ammo"], {"room": "shop", "picked": true})
	_box(L, "ammo_e", "shelves", Vector2(4.225, 7.4), "E", "ammunition shelf", ["ammo", "utility"], shop)
	_box(L, "window_case", "counter", Vector2(2.6, 9.35), "N", "smashed display case", ["utility", "protective", "ammo"], {"room": "shop", "picked": true})
	# the office: someone holed up here for a while
	var office := {"room": "office"}
	_box(L, "desk", "dining_table", Vector2(6.5, 1.55), "S", "desk", DESK, office)
	_box(L, "filing", "dresser", Vector2(7.65, 3.6), "W", "filing cabinet", DESK, office)
	# the back room (the steel door: a crowbar): the location's locked table; the gun locker
	# needs the crowbar again
	var back := {"room": "back_room", "table": "locked"}
	_box(L, "gun_locker", "tool_cabinet", Vector2(9.2, 1.325), "S", "gun locker", ["weapon", "ammo", "protective"],
		{"room": "back_room", "table": "stash", "stash": true, "needs": "crowbar", "noise": 2})
	L["stash"] = "gun_locker"               # Exp 009 (G): the main stash
	_box(L, "ammo_crate", "storage_chest", Vector2(10.625, 2.6), "W", "ammo crate", ["ammo"], back)
	_box(L, "back_shelf", "shelves", Vector2(8.325, 3.6), "E", "back-room shelf", ANY, back)
	_prop(L, "trash_bin_tipped", Vector2(2.2, 3.4), "E")
	_prop(L, "streetlight_dead", Vector2(12.6, 10.6), "S")
	_pickup(L, "rounds", "ammo", 3, Vector2(5.4, 6.4))
	_pickup(L, "snacks", "snacks", 1, Vector2(6.9, 4.3))
	_pickup(L, "shells", "shells", 2, Vector2(2.8, 2.2))
	_tell(L, "glass", Vector2(2.6, 8.6), {"w": 1.4, "d": 0.6})
	_tell(L, "barricade", Vector2(5.3, 9.68), {"lean": "S", "len": 1.1})
	_tell(L, "toppled", Vector2(6.3, 6.0), {"piece": "stool", "yaw": 0.7})
	_tell(L, "spill", Vector2(5.5, 8.4), {"yaw": -0.5, "r": 0.5})
	_tell(L, "camp", Vector2(5.75, 3.85))
	_tell(L, "toppled", Vector2(7.1, 2.6), {"piece": "chair", "yaw": 2.2})
	_tell(L, "pallet", Vector2(3.6, 1.9), {"load": "boxes", "yaw": 0.3})
	# the desk lamp left on, the back room's red emergency light, a tube dying over the counter
	_light(L, Vector2(6.0, 1.4), 0.75, "lamp", 0xffd7a0, 0.8)
	_light(L, Vector2(10.3, 1.2), 2.2, "emergency", 0xff3b2e, 0.9)
	_light(L, Vector2(8.5, 6.2), 2.5, "tube", 0xe8f0ff, 1.1, true)
	L["peek"] = [{"at": Vector2(3.0, 10.9), "look": Vector2(3.0, 8.0)}, {"at": Vector2(9.2, 10.9), "look": Vector2(8.5, 7.8)},
		{"at": Vector2(11.9, 8.4), "look": Vector2(9.6, 8.0)}, {"at": Vector2(6.5, 0.2), "look": Vector2(6.5, 3.0)}]
	L["doorways"] = [Vector2(6.5, 10.8), Vector2(4.2, 2.5)]
	L["entry"] = Vector2(6.5, 11.0)
	L["exits"] = [Vector2(9.6, 13.0), Vector2(2.4, 0.4)]
	_car(L, 0.4, 11.3)
	L["hide"] = [Vector2(9.6, 3.6), Vector2(7.0, 4.4), Vector2(9.8, 6.0)]
	L["wander"] = [Rect2(4.6, 7.6, 2.2, 2.0), Rect2(1.5, 1.2, 3.0, 3.2), Rect2(-3.0, 11.0, 22.0, 2.6)]
	return L


# --- Medical Clinic (clinic) ---------------------------------------------------------------------
# Exp 008 (H): a T: the waiting room and reception across the front, with windows, and a long
# corridor running north with rooms either side. The west rooms have windows (two examination
# rooms, picked over, and the staff room); the east ones have none: an examination room nobody
# searched in the dark, and the locked, pitch-dark medical store. A fire exit at the far end.

static func _clinic(_def: Dictionary) -> Dictionary:
	var L := _base()
	var paint := 0xdfe3dc
	L["floors"] = [{"rect": Rect2(-0.1, 6.9, 14.2, 4.2), "art": "floor_wood_light"}, {"rect": Rect2(1.9, -3.1, 10.2, 10.1), "art": "floor_tile"},
		{"rect": Rect2(2, -3.1, 4.0, 4.1), "art": "floor_kitchen"}, {"rect": Rect2(8, -3.1, 4.1, 6.1), "art": "floor_concrete"}]
	_wall(L, Vector2(0, 11), Vector2(14, 11), "brick", [_win(0.6, 3.4, 0.9, 2.1), _dgap(4, 5), _dgap(5, 6), _win(6.6, 8.4, 0.9, 2.1), _win(10, 13, 1.0, 2.1)])
	_wall(L, Vector2(0, 7), Vector2(0, 11), "brick", [_win(8, 10, 0.9, 2.1)])
	_wall(L, Vector2(14, 7), Vector2(14, 11), "brick", [_win(8, 10, 1.0, 2.1)])
	_wall(L, Vector2(0, 7), Vector2(2, 7), "brick")
	_wall(L, Vector2(12, 7), Vector2(14, 7), "brick")
	_wall(L, Vector2(2, 7), Vector2(12, 7), "drywall", [_open(6, 8)], paint)
	_wall(L, Vector2(9, 7), Vector2(9, 11), "drywall", [_dgap(8, 9), _win(9.6, 10.6, 1.0, 2.0)], paint)
	# the wing: the corridor and its rooms
	_wall(L, Vector2(2, -3), Vector2(2, 7), "brick", [_win(4.8, 6.2), _win(1.4, 2.6), _win(-2.2, -0.8)])
	_wall(L, Vector2(12, -3), Vector2(12, 7), "brick")
	_wall(L, Vector2(2, -3), Vector2(12, -3), "brick", [_win(3, 5, 1.0, 2.1), _dgap(7, 8)])
	_wall(L, Vector2(6, -3), Vector2(6, 7), "drywall", [_dgap(5, 6), _dgap(2, 3), _dgap(-2, -1)], paint)
	_wall(L, Vector2(8, -3), Vector2(8, 7), "drywall", [_dgap(5, 6), _dgap(1, 2)], paint)
	_wall(L, Vector2(2, 4), Vector2(6, 4), "drywall", [], paint)
	_wall(L, Vector2(2, 1), Vector2(6, 1), "drywall", [], paint)
	_wall(L, Vector2(8, 3), Vector2(12, 3), "drywall", [], paint)
	_door(L, "front_l", 0, 11, 4, 2, false, true)
	_door(L, "front_r", 0, 11, 5, 2)
	_door(L, "reception", 1, 9, 8, 3, false, true)
	_door(L, "exam_1", 1, 6, 5, 1)
	_door(L, "exam_2", 1, 6, 2, 1, false, true)
	_door(L, "staff", 1, 6, -2, 1)
	_door(L, "exam_3", 1, 8, 5, 3)
	_door(L, "storage", 1, 8, 1, 3, true)
	_door(L, "fire_exit", 0, -3, 7, 2)
	_room(L, "waiting", Rect2(0, 7, 9, 4))
	_room(L, "reception", Rect2(9, 7, 5, 4))
	_room(L, "corridor", Rect2(6, -3, 2, 10))
	_room(L, "exam_1", Rect2(2, 4, 4, 3))
	_room(L, "exam_2", Rect2(2, 1, 4, 3))
	_room(L, "staff", Rect2(2, -3, 4, 4))
	_room(L, "exam_3", Rect2(8, 3, 4, 4), true)
	_room(L, "storage", Rect2(8, -3, 4, 6), true)
	# the waiting room
	_box(L, "drinks", "fridge", Vector2(1.0, 7.45), "S", "drinks machine", FOOD, {"room": "waiting"})
	for z in [8.4, 8.9, 9.4, 9.9]:
		_prop(L, "chair", Vector2(0.33, z), "E", false)
	_prop(L, "coffee_table", Vector2(2.2, 9.3), "S")
	_prop(L, "plant", Vector2(8.55, 10.5), "S")
	# reception
	var rec := {"room": "reception"}
	_box(L, "reception_desk", "counter", Vector2(9.41, 10.1), "E", "reception desk", ["medical", "utility", "food", "water"], rec)
	_box(L, "first_aid", "tool_cabinet", Vector2(12.7, 7.325), "S", "first-aid cabinet", ["medical", "utility"], rec)
	_box(L, "records", "dresser", Vector2(13.65, 8.7), "W", "filing cabinet", DESK, {"room": "reception", "picked": true})
	_prop(L, "chair", Vector2(10.2, 10.1), "W", false)
	# examination rooms 1 and 2: picked over (a drawer or two left)
	_prop(L, "exam_bed", Vector2(2.45, 5.5), "E")
	_box(L, "exam1_cupboard", "cupboard", Vector2(4.0, 4.4), "S", "supply cupboard", ["medical"], {"room": "exam_1", "picked": true})
	_box(L, "exam1_drawers", "dresser", Vector2(3.5, 6.65), "N", "drawers", ["medical", "utility"], {"room": "exam_1", "picked": true})
	_prop(L, "exam_bed", Vector2(3.4, 1.45), "S")
	_box(L, "exam2_cabinet", "tool_cabinet", Vector2(2.325, 3.4), "E", "medicine cabinet", ["medical"], {"room": "exam_2", "picked": true})
	_box(L, "exam2_drawers", "dresser", Vector2(4.6, 3.65), "N", "drawers", ["medical", "utility"], {"room": "exam_2", "weight": 0.5})
	# the staff room: food and water; someone slept here
	var staff := {"room": "staff"}
	_box(L, "staff_fridge", "fridge", Vector2(5.4, -2.55), "S", "staff fridge", FOOD, staff)
	_box(L, "kitchenette", "cupboard", Vector2(4.4, -2.6), "S", "kitchenette cupboard", ["food", "water", "utility"], staff)
	_box(L, "lockers", "wardrobe", Vector2(5.59, 0.0), "W", "staff lockers", ["utility", "medical", "food", "water", "protective", "tool"], staff)
	# examination room 3: no window, pitch dark (a flashlight); nobody searched it
	var ex3 := {"room": "exam_3", "needs": "flashlight", "weight": 1.6}
	_prop(L, "exam_bed", Vector2(11.55, 5.0), "W")
	_box(L, "exam3_cupboard", "cupboard", Vector2(9.5, 3.4), "S", "supply cupboard", ["medical"], ex3)
	_box(L, "exam3_cabinet", "tool_cabinet", Vector2(10.8, 3.325), "S", "medicine cabinet", ["medical", "utility"], ex3)
	_box(L, "exam3_drawers", "dresser", Vector2(10.2, 6.65), "N", "drawers", ["medical", "utility"], ex3)
	# the medical store: locked (a crowbar), pitch dark (a flashlight): the locked table
	var cage := {"room": "storage", "table": "locked", "needs": "flashlight"}
	_box(L, "drug_cage", "tool_cabinet", Vector2(11.675, -1.5), "W", "drug cage", ["medical"],
		{"room": "storage", "table": "stash", "needs": "flashlight", "stash": true})
	L["stash"] = "drug_cage"                # Exp 009 (G): the main stash
	_box(L, "store_shelf_1", "shelves", Vector2(9.6, -2.675), "S", "medical supply shelf", ANY, cage)
	_box(L, "store_shelf_2", "shelves", Vector2(11.675, 1.6), "W", "store shelf", ANY, cage)
	_box(L, "store_boxes", "boxes", Vector2(8.45, -1.2), "E", "boxes of supplies", ANY, cage)
	_prop(L, "streetlight_dead", Vector2(-1.4, 11.8), "S")
	_pickup(L, "bandage", "bandage", 1, Vector2(7.0, 4.2))
	_pickup(L, "water", "water", 1, Vector2(12.4, 10.4))
	_tell(L, "toppled", Vector2(3.2, 8.4), {"piece": "chair", "yaw": 0.6})
	_tell(L, "toppled", Vector2(4.6, 9.8), {"piece": "chair", "yaw": 2.4})
	_tell(L, "barricade", Vector2(4.0, 7.3), {"lean": "N", "len": 1.3})
	_tell(L, "papers", Vector2(11.0, 8.9), {"r": 0.8, "n": 14})
	_tell(L, "papers", Vector2(4.4, 5.6), {"r": 0.5, "n": 7})
	_tell(L, "papers", Vector2(7.0, 1.0), {"r": 0.5, "n": 6})
	_tell(L, "toppled", Vector2(4.2, 2.5), {"piece": "stool", "yaw": -0.4})
	_tell(L, "camp", Vector2(3.2, -0.2))
	_tell(L, "toppled", Vector2(4.4, 0.4), {"piece": "chair", "yaw": 1.9})
	# a tube dying along the corridor, the fire exit's green light, the reception lamp left on
	_light(L, Vector2(7.0, 2.0), 2.5, "tube", 0xdfe8ff, 1.0, true, {"yaw": PI * 0.5})
	_light(L, Vector2(7.5, -2.85), 2.3, "emergency", 0x4dff7a, 0.6)
	_light(L, Vector2(9.4, 10.4), 0.92, "lamp", 0xffd7a0, 0.7)
	L["peek"] = [{"at": Vector2(2.0, 11.9), "look": Vector2(2.0, 9.0)}, {"at": Vector2(7.5, 11.9), "look": Vector2(7.0, 8.5)},
		{"at": Vector2(11.5, 11.7), "look": Vector2(11.5, 9.0)}, {"at": Vector2(-0.9, 9.0), "look": Vector2(1.5, 9.0)},
		{"at": Vector2(14.9, 9.0), "look": Vector2(12.5, 9.0)}, {"at": Vector2(1.1, 5.5), "look": Vector2(3.6, 5.5)},
		{"at": Vector2(1.1, 2.0), "look": Vector2(3.6, 2.5)}, {"at": Vector2(1.1, -1.5), "look": Vector2(3.6, -1.0)},
		{"at": Vector2(4.0, -3.9), "look": Vector2(4.0, -1.5)}]
	L["doorways"] = [Vector2(5.0, 11.8), Vector2(7.5, -3.8)]
	L["entry"] = Vector2(5.0, 12.0)
	L["exits"] = [Vector2(1.4, 13.4), Vector2(7.5, -4.6)]
	_car(L, 9.2, 12.3)
	L["hide"] = [Vector2(9.4, 5.2), Vector2(10.2, 0.0), Vector2(3.4, -1.9), Vector2(12.6, 9.6)]
	L["wander"] = [Rect2(1.0, 8.2, 7.4, 2.2), Rect2(6.4, -2.4, 1.2, 9.0), Rect2(-3.0, 12.2, 11.0, 1.8)]
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
	# Exp 008 (E): its five windows; the front and back doors
	L["peek"] = [{"at": Vector2(4.5, 8.75), "look": Vector2(4.5, 5.0)}, {"at": Vector2(9.25, 8.75), "look": Vector2(9.25, 5.0)},
		{"at": Vector2(5.5, 1.25), "look": Vector2(5.5, 4.5)}, {"at": Vector2(2.25, 7.0), "look": Vector2(5.0, 7.0)},
		{"at": Vector2(11.7, 6.7), "look": Vector2(9.0, 7.0)}]
	L["doorways"] = [Vector2(6.5, 8.7), Vector2(9.5, 1.3)]
	return L
