class_name PoiFurniture
extends RefCounted
## Experiment 009 (G): the pieces the generator (PoiGenerator) furnishes rooms
## with, tagged by room type and filtered by archetype / family. Pure data.
##
## PIECES: type -> {size: Vector3 (w across the front, h, d front to back),
##   clear: metres kept free in front (where Eli stands to search or use it),
##   block: collision and a solid navigation mark (false: chairs, plants)}.
##   Types are PropKit types (src/props/; prop_gen_interior.gd for the
##   generator's own).
## ROOM_SETS: room type -> entries, placed in order:
##   piece     PIECES key
##   n         [lo, hi] how many (after p)
##   p         chance the entry is used at all (default 1)
##   place     "wall" (back to a wall, facing in; the default) | "centre"
##             (free-standing, clear all round) | "rows" (gondolas / racks
##             running north-south, the camera looks down the aisles)
##   pair      rows: back-to-back pairs (shop gondolas)
##   side      wall: only these walls ("N", "S", "E", "W": the wall's side of
##             the room)
##   near      wall: "entrance" (close to the room's door to the outside)
##   chairs    centre: chairs around it [lo, hi] (non-blocking)
##   size      a size override (a single bed, a long counter)
##   facing    centre: the facing ("S": the front toward the camera)
##   box       a searchable container: {label, holds, weight}; "c": chance a
##             placed one is a container (else a plain piece)
##   only / not  archetype ids or families the entry is limited to / kept from

const ANY := []
const FOOD := ["food", "water"]
const SUPPLIES := ["food", "water", "medical", "utility", "ammo"]
const DESK := ["utility", "medical", "ammo", "tool", "food", "water", "book"]
const GEAR := ["weapon", "ammo", "protective", "utility", "tool", "medical"]
const BOOKS := ["book"]
const MATERIALS := ["material", "tool"]
const MED := ["medical", "utility"]
const TOOLS := ["tool", "material", "utility"]

const PIECES := {
	"sofa": {"size": Vector3(2.0, 0.85, 0.9), "clear": 0.5},
	"armchair": {"size": Vector3(0.9, 0.85, 0.9), "clear": 0.4, "block": false},
	"tv_stand": {"size": Vector3(1.6, 1.1, 0.45), "clear": 0.5},
	"coffee_table": {"size": Vector3(1.1, 0.45, 0.6), "clear": 0.0},
	"bookshelf": {"size": Vector3(1.4, 1.9, 0.4), "clear": 0.7},
	"dresser": {"size": Vector3(1.2, 0.8, 0.5), "clear": 0.7},
	"plant": {"size": Vector3(0.5, 1.1, 0.5), "clear": 0.0, "block": false},
	"counter": {"size": Vector3(1.0, 0.92, 0.62), "clear": 0.7},
	"sink_counter": {"size": Vector3(1.0, 0.92, 0.62), "clear": 0.6},
	"stove": {"size": Vector3(0.75, 0.92, 0.62), "clear": 0.6},
	"fridge": {"size": Vector3(0.75, 1.85, 0.7), "clear": 0.7},
	"cupboard": {"size": Vector3(1.0, 0.92, 0.6), "clear": 0.7},
	"dining_table": {"size": Vector3(1.6, 0.75, 0.9), "clear": 0.0},
	"chair": {"size": Vector3(0.45, 0.9, 0.42), "clear": 0.0, "block": false},
	"stool": {"size": Vector3(0.4, 0.7, 0.4), "clear": 0.0, "block": false},
	"bed": {"size": Vector3(1.6, 0.6, 2.1), "clear": 0.5},
	"nightstand": {"size": Vector3(0.45, 0.55, 0.42), "clear": 0.6},
	"wardrobe": {"size": Vector3(1.5, 2.0, 0.62), "clear": 0.7},
	"bathtub": {"size": Vector3(1.7, 0.55, 0.8), "clear": 0.4},
	"toilet": {"size": Vector3(0.6, 0.8, 0.55), "clear": 0.5},
	"vanity": {"size": Vector3(0.9, 0.85, 0.52), "clear": 0.6},
	"water_heater": {"size": Vector3(0.6, 1.6, 0.6), "clear": 0.3},
	"washer": {"size": Vector3(0.62, 0.85, 0.62), "clear": 0.5},
	"workbench": {"size": Vector3(1.8, 0.9, 0.65), "clear": 0.7},
	"shelves": {"size": Vector3(1.6, 1.9, 0.45), "clear": 0.7},
	"boxes": {"size": Vector3(1.0, 0.6, 0.7), "clear": 0.6},
	"crate": {"size": Vector3(0.9, 0.6, 0.6), "clear": 0.6},
	"storage_chest": {"size": Vector3(1.0, 0.6, 0.55), "clear": 0.6},
	"tool_cabinet": {"size": Vector3(0.9, 1.8, 0.45), "clear": 0.7},
	"gun_rack": {"size": Vector3(1.6, 1.9, 0.35), "clear": 0.7},
	"exam_bed": {"size": Vector3(1.9, 0.75, 0.7), "clear": 0.5},
	"lumber_rack": {"size": Vector3(2.0, 1.8, 0.7), "clear": 0.7},
	"car": {"size": Vector3(2.0, 1.45, 4.4), "clear": 0.0},
	"water_dispenser": {"size": Vector3(0.35, 1.25, 0.35), "clear": 0.4},
	"filing_cabinet": {"size": Vector3(0.5, 1.3, 0.62), "clear": 0.7},
	"tool_rack": {"size": Vector3(1.4, 1.8, 0.35), "clear": 0.7},
	"pallet": {"size": Vector3(1.2, 0.9, 1.0), "clear": 0.6},
	"machine": {"size": Vector3(1.8, 1.5, 1.0), "clear": 0.0},
	"locker": {"size": Vector3(1.2, 1.9, 0.5), "clear": 0.7},
	"hospital_bed": {"size": Vector3(1.0, 0.85, 2.1), "clear": 0.5},
	"desk": {"size": Vector3(1.4, 0.76, 0.7), "clear": 0.7},
	"safe": {"size": Vector3(0.7, 0.95, 0.6), "clear": 0.7},
	"pallet_rack": {"size": Vector3(2.4, 2.4, 1.0), "clear": 0.7},
	"trash_bin_tipped": {"size": Vector3(0.6, 0.6, 0.9), "clear": 0.0},
}

const SINGLE_BED := Vector3(1.0, 0.55, 2.0)

const ROOM_SETS := {
	"living": [
		{"piece": "sofa", "n": [1, 1]},
		{"piece": "tv_stand", "p": 0.7},
		{"piece": "bookshelf", "p": 0.6, "box": {"label": "bookshelf", "holds": BOOKS + ["utility"], "weight": 0.7}},
		{"piece": "dresser", "p": 0.6, "box": {"label": "sideboard", "holds": DESK}},
		{"piece": "armchair", "p": 0.6},
		{"piece": "coffee_table", "place": "centre", "p": 0.8},
		{"piece": "plant", "p": 0.5},
	],
	"kitchen": [
		{"piece": "fridge", "box": {"label": "fridge", "holds": FOOD}},
		{"piece": "stove", "only": ["residential", "diner", "staff_kitchen", "fire_station"]},
		{"piece": "sink_counter"},
		{"piece": "counter", "n": [2, 3], "box": {"label": "kitchen cupboard", "holds": SUPPLIES}, "c": 0.7},
		{"piece": "cupboard", "p": 0.5, "box": {"label": "pantry cupboard", "holds": FOOD}},
		{"piece": "dining_table", "place": "centre", "p": 0.5, "chairs": [2, 4], "only": ["residential", "fire_station"]},
	],
	"dining": [
		{"piece": "counter", "n": [2, 3], "side": ["N"], "box": {"label": "counter", "holds": SUPPLIES}, "c": 0.7, "only": ["diner"]},
		{"piece": "fridge", "n": [1, 2], "box": {"label": "drinks fridge", "holds": FOOD}, "only": ["diner"]},
		{"piece": "dining_table", "place": "centre", "n": [2, 4], "chairs": [2, 4], "only": ["diner"]},
		{"piece": "dining_table", "place": "centre", "chairs": [3, 4], "not": ["diner"]},
		{"piece": "dresser", "p": 0.7, "box": {"label": "sideboard", "holds": DESK}, "not": ["diner"]},
		{"piece": "plant", "p": 0.5},
	],
	"bedroom": [
		{"piece": "bed"},
		{"piece": "wardrobe", "p": 0.85, "box": {"label": "wardrobe", "holds": GEAR}},
		{"piece": "nightstand", "p": 0.8, "box": {"label": "nightstand", "holds": DESK, "weight": 0.6}},
		{"piece": "dresser", "p": 0.6, "box": {"label": "chest of drawers", "holds": DESK}},
	],
	"bathroom": [
		{"piece": "toilet"},
		{"piece": "vanity", "box": {"label": "bathroom cabinet", "holds": MED}},
		{"piece": "bathtub", "p": 0.6},
	],
	"toilet": [
		{"piece": "toilet"},
		{"piece": "vanity", "p": 0.8, "box": {"label": "washbasin cabinet", "holds": MED, "weight": 0.5}},
	],
	"storage": [
		{"piece": "shelves", "n": [1, 2], "box": {"label": "storage shelf", "holds": ANY}},
		{"piece": "boxes", "n": [1, 2], "box": {"label": "boxes", "holds": ANY}, "c": 0.8},
		{"piece": "water_heater", "p": 0.5, "only": ["residential"]},
		{"piece": "washer", "p": 0.4, "only": ["residential"]},
		{"piece": "storage_chest", "p": 0.4, "box": {"label": "old chest", "holds": ANY}, "only": ["residential"]},
		{"piece": "crate", "p": 0.6, "box": {"label": "crate", "holds": MATERIALS}, "only": ["industry", "outdoor"]},
		{"piece": "pallet", "p": 0.4, "box": {"label": "pallet of stock", "holds": ANY}, "only": ["industry"]},
		{"piece": "filing_cabinet", "p": 0.6, "box": {"label": "records cabinet", "holds": DESK}, "only": ["office", "hospital", "police"]},
		{"piece": "tool_cabinet", "p": 0.4, "box": {"label": "supply cupboard", "holds": TOOLS}, "only": ["industry", "outdoor"]},
	],
	"hallway": [
		{"piece": "dresser", "p": 0.4, "box": {"label": "hall table", "holds": DESK, "weight": 0.6}, "not": ["apartment"]},
		{"piece": "boxes", "p": 0.4, "box": {"label": "abandoned boxes", "holds": ANY, "weight": 0.6}, "only": ["apartment"]},
		{"piece": "plant", "p": 0.4},
	],
	"corridor": [
		{"piece": "water_dispenser", "p": 0.5},
		{"piece": "chair", "n": [1, 2], "p": 0.5},
		{"piece": "plant", "p": 0.3},
	],
	"lobby": [
		{"piece": "counter", "n": [1, 2], "box": {"label": "reception desk", "holds": SUPPLIES}, "c": 0.8},
		{"piece": "chair", "n": [1, 3]},
		{"piece": "water_dispenser", "p": 0.5},
		{"piece": "plant", "p": 0.6},
		{"piece": "filing_cabinet", "p": 0.4, "box": {"label": "filing cabinet", "holds": DESK}},
		{"piece": "coffee_table", "place": "centre", "p": 0.3},
	],
	"waiting": [
		{"piece": "chair", "n": [2, 4]},
		{"piece": "fridge", "p": 0.5, "box": {"label": "drinks machine", "holds": FOOD}},
		{"piece": "sofa", "p": 0.3},
		{"piece": "water_dispenser", "p": 0.5},
		{"piece": "plant", "p": 0.5},
		{"piece": "coffee_table", "place": "centre", "p": 0.6},
	],
	"sales": [
		{"piece": "counter", "n": [1, 2], "place": "centre", "facing": "W", "near": "entrance", "box": {"label": "checkout", "holds": SUPPLIES}, "c": 0.7, "only": ["supermarket"]},
		{"piece": "counter", "n": [1, 2], "box": {"label": "pharmacy counter", "holds": MED}, "c": 0.8, "only": ["pharmacy"]},
		{"piece": "fridge", "n": [2, 4], "side": ["W", "E", "N"], "box": {"label": "drinks fridge", "holds": FOOD}, "only": ["supermarket"]},
		{"piece": "fridge", "p": 0.5, "box": {"label": "drinks fridge", "holds": FOOD}, "only": ["pharmacy"]},
		{"piece": "shelves", "place": "rows", "pair": true, "box": {"label": "shelf", "holds": ANY}, "c": 0.45, "only": ["supermarket"]},
		{"piece": "shelves", "place": "rows", "pair": true, "box": {"label": "shelf", "holds": ["medical", "utility", "food", "water"]}, "c": 0.5, "only": ["pharmacy"]},
		{"piece": "shelves", "n": [1, 3], "side": ["N", "W", "E"], "box": {"label": "wall shelf", "holds": ANY}, "c": 0.7},
		{"piece": "plant", "p": 0.3},
	],
	"gun_counter": [
		{"piece": "counter", "n": [2, 3], "box": {"label": "display case", "holds": ["ammo", "utility", "protective"]}, "c": 0.6},
		{"piece": "gun_rack", "n": [1, 2], "box": {"label": "gun rack", "holds": ["weapon"], "weight": 0.5}},
		{"piece": "shelves", "n": [1, 2], "box": {"label": "ammunition shelf", "holds": ["ammo", "utility"]}},
		{"piece": "chair", "p": 0.5},
	],
	"stockroom": [
		{"piece": "shelves", "n": [2, 3], "box": {"label": "stockroom shelf", "holds": ANY}},
		{"piece": "boxes", "n": [1, 2], "box": {"label": "stock boxes", "holds": ANY}},
		{"piece": "pallet", "p": 0.5, "box": {"label": "pallet of stock", "holds": ANY}},
		{"piece": "crate", "p": 0.3, "box": {"label": "crate", "holds": ANY}},
	],
	"office": [
		{"piece": "desk", "box": {"label": "desk", "holds": DESK}},
		{"piece": "filing_cabinet", "n": [1, 2], "box": {"label": "filing cabinet", "holds": DESK}, "c": 0.7},
		{"piece": "chair"},
		{"piece": "bookshelf", "p": 0.4, "box": {"label": "bookshelf", "holds": BOOKS + ["utility"], "weight": 0.6}},
		{"piece": "water_dispenser", "p": 0.3},
		{"piece": "plant", "p": 0.3},
	],
	"staff": [
		{"piece": "fridge", "box": {"label": "staff fridge", "holds": FOOD}},
		{"piece": "counter", "n": [1, 2], "box": {"label": "kitchenette cupboard", "holds": SUPPLIES}, "c": 0.8},
		{"piece": "locker", "p": 0.5, "box": {"label": "staff lockers", "holds": GEAR}},
		{"piece": "water_dispenser", "p": 0.4},
		{"piece": "sofa", "p": 0.3},
		{"piece": "dining_table", "place": "centre", "p": 0.7, "chairs": [2, 3]},
	],
	"lockers": [
		{"piece": "locker", "n": [2, 3], "box": {"label": "locker", "holds": GEAR}, "c": 0.8},
		{"piece": "stool", "n": [1, 2], "p": 0.6},
	],
	"work_floor": [
		{"piece": "workbench", "n": [1, 3], "box": {"label": "workbench", "holds": TOOLS}, "c": 0.8},
		{"piece": "tool_rack", "n": [1, 2], "box": {"label": "tool rack", "holds": ["tool", "utility"]}, "c": 0.8},
		{"piece": "machine", "place": "centre", "n": [1, 2], "only": ["workshop"]},
		{"piece": "machine", "place": "centre", "n": [2, 4], "only": ["factory"]},
		{"piece": "tool_cabinet", "p": 0.6, "box": {"label": "tool cabinet", "holds": TOOLS}},
		{"piece": "lumber_rack", "p": 0.5, "box": {"label": "lumber rack", "holds": MATERIALS}, "only": ["workshop"]},
		{"piece": "pallet", "n": [1, 2], "p": 0.7, "box": {"label": "pallet of parts", "holds": ["material", "utility"]}, "only": ["factory"]},
		{"piece": "crate", "p": 0.5, "box": {"label": "crate", "holds": MATERIALS}},
		{"piece": "shelves", "p": 0.5, "box": {"label": "parts shelf", "holds": ["material", "utility", "tool"]}},
	],
	"bay": [
		{"piece": "car", "place": "centre", "facing": "S"},
		{"piece": "tool_cabinet", "n": [1, 2], "box": {"label": "tool cabinet", "holds": TOOLS}, "only": ["garage"]},
		{"piece": "workbench", "box": {"label": "workbench", "holds": TOOLS}, "only": ["garage"]},
		{"piece": "tool_rack", "p": 0.7, "box": {"label": "tool rack", "holds": ["tool", "utility"]}, "only": ["garage"]},
		{"piece": "storage_chest", "p": 0.5, "box": {"label": "parts chest", "holds": ["material", "utility", "tool"]}, "only": ["garage"]},
		{"piece": "locker", "n": [2, 3], "box": {"label": "gear locker", "holds": ["protective", "medical", "utility", "tool"]}, "c": 0.8, "only": ["fire_station"]},
		{"piece": "shelves", "p": 0.7, "box": {"label": "equipment shelf", "holds": ["medical", "utility", "tool"]}, "only": ["fire_station"]},
		{"piece": "crate", "p": 0.4, "box": {"label": "crate", "holds": MATERIALS}},
	],
	"hall": [
		{"piece": "pallet_rack", "place": "rows", "box": {"label": "pallet rack", "holds": ANY}, "c": 0.6},
		{"piece": "pallet", "n": [2, 3], "box": {"label": "pallet of goods", "holds": ANY}, "c": 0.7},
		{"piece": "crate", "n": [1, 2], "box": {"label": "crate", "holds": MATERIALS}},
		{"piece": "shelves", "p": 0.5, "box": {"label": "shelf", "holds": ANY}},
	],
	"ward": [
		{"piece": "hospital_bed", "n": [2, 3]},
		{"piece": "nightstand", "n": [1, 2], "box": {"label": "bedside cabinet", "holds": MED, "weight": 0.6}},
		{"piece": "cupboard", "p": 0.6, "box": {"label": "supply cupboard", "holds": ["medical"]}},
		{"piece": "chair", "p": 0.5},
	],
	"exam": [
		{"piece": "exam_bed"},
		{"piece": "cupboard", "box": {"label": "supply cupboard", "holds": ["medical"]}},
		{"piece": "tool_cabinet", "p": 0.6, "box": {"label": "medicine cabinet", "holds": MED}},
		{"piece": "dresser", "p": 0.4, "box": {"label": "drawers", "holds": MED}},
		{"piece": "chair", "p": 0.5},
	],
	"pharmacy": [
		{"piece": "shelves", "n": [1, 2], "box": {"label": "medicine shelf", "holds": ["medical"]}},
		{"piece": "tool_cabinet", "p": 0.5, "box": {"label": "medicine cabinet", "holds": MED}},
		{"piece": "counter", "p": 0.5, "box": {"label": "dispensing counter", "holds": MED}},
		{"piece": "fridge", "p": 0.3, "box": {"label": "medicine fridge", "holds": ["medical", "water"]}},
	],
	"armoury": [
		{"piece": "gun_rack", "n": [1, 2], "box": {"label": "gun rack", "holds": ["weapon", "ammo"], "weight": 0.6}},
		{"piece": "locker", "box": {"label": "equipment locker", "holds": ["protective", "ammo", "utility"]}},
		{"piece": "storage_chest", "p": 0.6, "box": {"label": "ammo crate", "holds": ["ammo"]}},
		{"piece": "shelves", "p": 0.5, "box": {"label": "armoury shelf", "holds": GEAR}},
	],
	"cells": [
		{"piece": "bed", "n": [1, 2], "size": SINGLE_BED},
		{"piece": "toilet", "p": 0.7},
	],
	"evidence": [
		{"piece": "shelves", "n": [1, 2], "box": {"label": "evidence shelf", "holds": ANY}},
		{"piece": "boxes", "box": {"label": "evidence boxes", "holds": ANY}},
		{"piece": "filing_cabinet", "p": 0.6, "box": {"label": "filing cabinet", "holds": DESK}},
	],
	"lanes": [
		{"piece": "counter", "n": [3, 5], "side": ["S"], "box": {"label": "shooting booth", "holds": ["ammo"], "weight": 0.5}, "c": 0.4},
		{"piece": "storage_chest", "p": 0.7, "box": {"label": "ammo crate", "holds": ["ammo"]}},
		{"piece": "crate", "p": 0.4, "box": {"label": "crate", "holds": ["ammo", "utility"]}},
	],
	"dorm": [
		{"piece": "bed", "n": [2, 3], "size": SINGLE_BED},
		{"piece": "locker", "n": [1, 2], "box": {"label": "locker", "holds": GEAR}},
		{"piece": "nightstand", "p": 0.5, "box": {"label": "nightstand", "holds": DESK, "weight": 0.6}},
	],
	"hut": [
		{"piece": "desk", "box": {"label": "desk", "holds": DESK}},
		{"piece": "filing_cabinet", "p": 0.6, "box": {"label": "filing cabinet", "holds": DESK}},
		{"piece": "tool_cabinet", "p": 0.6, "box": {"label": "tool cabinet", "holds": TOOLS}},
		{"piece": "locker", "p": 0.4, "box": {"label": "locker", "holds": GEAR}},
		{"piece": "water_dispenser", "p": 0.4},
		{"piece": "chair"},
	],
}

## The open ground of a yard (outside the hut): placed in the fence.
const YARD_SET := [
	{"piece": "pallet", "n": [2, 4], "place": "centre", "box": {"label": "pallet", "holds": ANY}, "c": 0.7},
	{"piece": "crate", "n": [1, 3], "box": {"label": "crate", "holds": MATERIALS}},
	{"piece": "lumber_rack", "p": 0.6, "box": {"label": "lumber rack", "holds": MATERIALS}},
	{"piece": "storage_chest", "p": 0.6, "box": {"label": "site box", "holds": TOOLS}},
	{"piece": "machine", "place": "centre", "p": 0.6},
	{"piece": "car", "place": "centre", "p": 0.5, "facing": "E"},
]

## Pieces that may stand only in these room types (the "furniture context").
const ONLY_IN := {
	"bed": ["bedroom", "dorm", "cells"], "hospital_bed": ["ward"], "exam_bed": ["exam"], "sofa": ["living", "waiting", "staff"],
	"bathtub": ["bathroom"], "toilet": ["bathroom", "toilet", "cells"], "stove": ["kitchen"], "machine": ["work_floor", "yard"],
	"car": ["bay", "yard"], "pallet_rack": ["hall"], "gun_rack": ["gun_counter", "armoury"],
}


static func piece(type: String) -> Dictionary:
	return PIECES.get(type, {"size": Vector3(1, 1, 0.5), "clear": 0.5})


static func size_of(type: String) -> Vector3:
	return piece(type)["size"]


static func blocks(type: String) -> bool:
	return bool(piece(type).get("block", true))


## The entries of room type `room` an archetype may use.
static func entries(room: String, arch: String, family: String) -> Array:
	var out := []
	for e in ROOM_SETS.get(room, []):
		if e.has("only") and not (arch in e["only"] or family in e["only"]):
			continue
		if e.has("not") and (arch in e["not"] or family in e["not"]):
			continue
		out.append(e)
	return out


## True if `type` may stand in a room of type `room` (ONLY_IN).
static func fits_room(type: String, room: String) -> bool:
	return not ONLY_IN.has(type) or room in ONLY_IN[type]
