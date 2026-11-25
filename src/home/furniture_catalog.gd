class_name FurnitureCatalog
extends RefCounted
## Experiment 005 (F): placeable and movable furniture. Pure data and rules
## shared by WorldObject (the placed pieces), BuildPieces / BuildMode (key 5
## "Furniture & storage": place and Move) and HouseWorld (furniture_items).
##
## Placed furniture is a WorldObject whose `kind` is the SPEC §2 type name
## (WorldObject.DEFS holds HP, size, collision and impact for each). Original
## house pieces (HouseFurniture) that are moved become placed objects of the
## same type, keeping their HP fraction, size and contents (`built` stays
## false, so demolishing them still gives salvage, not a full refund).

## Pieces the player can build, in palette order (key 5 variants after the
## crate and Move).
const PLACEABLE := ["cupboard", "storage_chest", "tool_cabinet", "wardrobe", "shelves", "bookshelf", "dresser", "nightstand",
	"bed", "sofa", "armchair", "chair", "dining_table", "coffee_table", "rug", "floor_lamp", "table_lamp", "painting", "plant",
	"tv_stand", "radio"]          # Exp 006 (B): the TV (on its stand) and a radio
## Every WorldObject kind that is furniture (placeable plus the original types
## that can be moved: they become objects of the same kind).
const KINDS := ["cupboard", "storage_chest", "tool_cabinet", "wardrobe", "shelves", "bookshelf", "dresser", "nightstand",
	"bed", "sofa", "armchair", "chair", "dining_table", "coffee_table", "rug", "floor_lamp", "table_lamp", "painting", "plant",
	"tv_stand", "fridge", "counter", "island", "stool", "boxes", "workbench", "radio"]
## Original pieces that stay where they are (plumbed or wired in; the old bed
## is where the night starts and the exit rule begins).
const FIXED := {"sink_counter": "It's plumbed in.", "bathtub": "It's plumbed in.", "toilet": "It's plumbed in.", "vanity": "It's plumbed in.",
	"water_heater": "It's plumbed in.", "washer": "It's plumbed in.", "dryer": "It's plumbed in.", "stove": "It's wired in.",
	"bed": "The old bed stays: build a new one to sleep elsewhere."}
## Build costs (planks, nails, scrap). Demolishing a placed piece refunds it in full.
const COST := {
	"cupboard": {"wood": 4, "nails": 6, "scrap": 1},
	"storage_chest": {"wood": 5, "nails": 6, "scrap": 1},
	"tool_cabinet": {"wood": 2, "nails": 4, "scrap": 5},
	"wardrobe": {"wood": 7, "nails": 8},
	"shelves": {"wood": 2, "nails": 4, "scrap": 3},
	"bookshelf": {"wood": 5, "nails": 6},
	"dresser": {"wood": 4, "nails": 6},
	"nightstand": {"wood": 2, "nails": 3},
	"bed": {"wood": 6, "nails": 8, "scrap": 1},
	"sofa": {"wood": 5, "nails": 6, "scrap": 2},
	"armchair": {"wood": 3, "nails": 4, "scrap": 1},
	"chair": {"wood": 2, "nails": 2},
	"dining_table": {"wood": 5, "nails": 6},
	"coffee_table": {"wood": 3, "nails": 4},
	"rug": {"nails": 2, "scrap": 1},
	"floor_lamp": {"scrap": 3, "nails": 1},
	"table_lamp": {"scrap": 2},
	"painting": {"wood": 1, "nails": 1},
	"plant": {"wood": 1},
	"tv_stand": {"wood": 3, "nails": 4, "scrap": 6},      # Exp 006 (B)
	"radio": {"scrap": 4, "nails": 1},
}
const SHORT := {"storage_chest": "Chest", "tool_cabinet": "Tool cabinet", "dining_table": "Table", "coffee_table": "Coffee table",
	"floor_lamp": "Floor lamp", "table_lamp": "Table lamp", "nightstand": "Nightstand", "cupboard": "Cupboard"}
const HINT := {
	"cupboard": "Kitchen cupboard · holds 30 (food and household supplies)",
	"storage_chest": "Storage chest · holds 80 (anything)",
	"tool_cabinet": "Tool cabinet · holds 60 (tools and construction supplies)",
	"wardrobe": "Wardrobe · holds 24 (clothing and equipment)",
	"shelves": "Shelves · hold 60 (materials and smaller items)",
	"bookshelf": "Bookshelf · holds 30 (materials and smaller items)",
	"dresser": "Dresser · holds 20 (small personal things)",
	"nightstand": "Nightstand · holds 8 (small personal things)",
	"bed": "E sleeps in it",
	"floor_lamp": "Shines while the house has power · E switches it",
	"table_lamp": "Stands on a table or the floor · shines while the house has power · E switches it",
	"painting": "Aim at a wall: it hangs on your side",
	"rug": "Lies flat: furniture can stand on it",
	"tv_stand": "A TV on a stand · E switches it · needs power",
	"radio": "A mains radio · E switches it · needs power · on a table or the floor",
}
const LAMPS := ["floor_lamp", "table_lamp"]
## Exp 006 (B): media sources (E switches them; HouseMedia, src/home/media.gd).
const MEDIA := ["tv_stand", "radio"]
## Exp 006 (B): small pieces that stand on a table, a dresser... or the floor.
const ON_SURFACES := ["table_lamp", "radio"]
## Surfaces a table lamp may stand on (tops no higher than this).
const SURFACE_MAX := 1.1
const SNAP := 0.05


static func is_furniture(kind: String) -> bool:
	return kind in KINDS


static func is_placeable(kind: String) -> bool:
	return kind in PLACEABLE


static func is_lamp(kind: String) -> bool:
	return kind in LAMPS


static func is_media(kind: String) -> bool:
	return kind in MEDIA


static func on_surfaces(kind: String) -> bool:
	return kind in ON_SURFACES


static func is_wall_hung(kind: String) -> bool:
	return kind == "painting"


## Flat or tiny pieces other furniture may stand over or next to (they don't block).
static func is_flat(kind: String) -> bool:
	return kind == "rug" or kind == "painting" or kind == "table_lamp" or kind == "radio"


static func cost(kind: String) -> Dictionary:
	return COST.get(kind, {})


static func short_name(kind: String) -> String:
	return str(SHORT.get(kind, kind.capitalize()))


## Why an original piece of `type` can't be moved ("" = it can).
static func move_block(type: String) -> String:
	if FIXED.has(type):
		return FIXED[type]
	if not type in KINDS:
		return "That can't be moved."
	return ""


## Facing letter -> rotation index (WorldObject: 0..3 = N, E, S, W).
static func rot_of_facing(facing: String) -> int:
	return maxi(["N", "E", "S", "W"].find(facing), 0)


## Canonical size (w across the front, h, d) of a plan rect seen from `facing`.
static func size_of_rect(r: Rect2, h: float, facing: String) -> Vector3:
	var turned := facing == "E" or facing == "W"
	return Vector3(r.size.y if turned else r.size.x, h, r.size.x if turned else r.size.y)


## Plan footprint of a canonical size at centre p and rotation r.
static func footprint(size: Vector3, p: Vector2, r: int) -> Rect2:
	var ext := Vector2(size.x, size.z) if r % 2 == 0 else Vector2(size.z, size.x)
	return Rect2(p - ext * 0.5, ext)


## Snaps the footprint's corner to SNAP (furniture stands close to walls).
static func snap(size: Vector3, p: Vector2, r: int) -> Vector2:
	var ext := Vector2(size.x, size.z) if r % 2 == 0 else Vector2(size.z, size.x)
	var lo := ((p - ext * 0.5) / SNAP).round() * SNAP
	return lo + ext * 0.5


## What demolishing a moved original gives back: its HouseFurniture salvage,
## scaled by the HP left (as demolishing it in place would).
static func original_salvage(kind: String, hp: int, max_hp: int) -> Dictionary:
	var frac := clampf(float(hp) / float(maxi(max_hp, 1)), 0.0, 1.0)
	var out := {}
	var base: Dictionary = HouseFurniture.type_def(kind)["salvage"]
	for k in base:
		var n := ceili(int(base[k]) * frac)
		if n > 0:
			out[k] = n
	return out
