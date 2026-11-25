class_name BuildPieces
extends RefCounted
## Construction pieces, tools and costs (SPEC-002 §6, SPEC-003 §4). Pure data.
##
## LIST is flat and its first nine entries keep their Experiment 002 index
## (select(i) and the keys 1-9 still pick them first). Every piece belongs to a
## palette slot (one building class); a slot with several pieces holds
## material variants: pressing the slot's key again cycles them.
##   key 1 Walls (wood, stone) · 2 Barricades (wood, iron, window boards) ·
##   3 Doors (wood, reinforced, metal) · 4 Doorway · 5 Furniture & storage
##   (crate, Move, then FurnitureCatalog.PLACEABLE; Exp 005, F) ·
##   6 Equipment (rain collector, workbench, fuse box) · 7 Repair ·
##   8 Reinforce (iron plating; doors: wood -> reinforced -> metal) ·
##   9 Demolish · 0 Floors & levels (stone foundation, wooden floor, stairs up
##   and down, next storey, excavate, pillar; Experiments 004-005,
##   src/levels/level_build.gd)
## Experiment 004 refunds: the player's own pieces give back their FULL
## cost; original structures (walls, windows, doors, the fuse box) and
## furniture give salvage, about half (ORIGINAL_SALVAGE, object_refund,
## HouseFurniture.TYPES).
## Piece fields: "id", "name", "short", "tool" (place | repair | upgrade |
## demolish), "slot", "cost", "per_m" (cost per 1 m segment), "hint", and
## for objects "kind" + "mat" (WorldObject kind and material).

const SLOTS := [
	{"key": "1", "name": "Walls"}, {"key": "2", "name": "Barricades"}, {"key": "3", "name": "Doors"},
	{"key": "4", "name": "Doorway"}, {"key": "5", "name": "Furniture & storage"}, {"key": "6", "name": "Equipment"},   # Exp 005 (F): 5 was "Storage"
	{"key": "7", "name": "Repair"}, {"key": "8", "name": "Reinforce"}, {"key": "9", "name": "Demolish"},
	{"key": "0", "name": "Floors & levels"},   # Experiment 004 (L): was "Foundation"
]
## Palette order of the slots: pieces first, then the tools.
const SLOT_ORDER := [0, 9, 1, 2, 3, 4, 5, 6, 7, 8]

const LIST := [
	{"id": "wall", "name": "Wooden wall", "short": "Wood", "tool": "place", "slot": 0, "cost": {"wood": 4, "nails": 6}, "per_m": true,
		"hint": "LMB place · drag along a line for a run · RMB cancel"},
	{"id": "barricade", "name": "Barricade", "short": "Wood", "tool": "place", "slot": 1, "cost": {"wood": 2, "nails": 4}, "per_m": true,
		"kind": "barricade", "mat": "wood",
		"hint": "Planks across a 1 m gap or line · drag for several · bullets pass, bodies don't"},
	{"id": "door", "name": "Door", "short": "Wood", "tool": "place", "slot": 2, "cost": {"wood": 4, "nails": 6, "scrap": 1},
		"kind": "door", "mat": "wood",
		"hint": "Aim at a wall (cuts it) or a 1 m doorway · E opens and closes it"},
	{"id": "doorway", "name": "Doorway", "short": "Doorway", "tool": "place", "slot": 3, "cost": {},
		"hint": "Aim at a wall: cuts a 1 m opening"},
	{"id": "crate", "name": "Storage crate", "short": "Crate", "tool": "place", "slot": 4, "cost": {"wood": 3, "nails": 4},
		"kind": "crate", "mat": "wood",
		"hint": "Raises material caps · R rotates"},
	{"id": "rain_collector", "name": "Rain collector", "short": "Collector", "tool": "place", "slot": 5, "cost": {"wood": 2, "nails": 2, "scrap": 3},
		"kind": "rain_collector", "mat": "wood",
		"hint": "One water every dawn · R rotates"},
	{"id": "repair", "name": "Repair", "short": "Repair", "tool": "repair", "slot": 6, "cost": {},
		"hint": "Aim at a damaged wall section or object · paid in its own material"},
	{"id": "upgrade", "name": "Iron plating", "short": "Plate", "tool": "upgrade", "slot": 7, "cost": {"iron": 2, "nails": 4},
		"hint": "Aim at a 1 m wall section: its outer skin becomes riveted iron plate · at a door: wood → reinforced → metal"},
	{"id": "demolish", "name": "Demolish", "short": "Demolish", "tool": "demolish", "slot": 8, "cost": {},
		"hint": "Your pieces refund in full · original walls, windows, doors and furniture give salvage"},
	# --- Experiment 003 -----------------------------------------------------------------
	{"id": "stone_wall", "name": "Stone wall", "short": "Stone", "tool": "place", "slot": 0, "cost": {"stone": 6}, "per_m": true,
		"hint": "Masonry on a foundation (the house floor or a stone foundation) · drag for a run"},
	{"id": "iron_barricade", "name": "Iron barricade", "short": "Iron", "tool": "place", "slot": 1, "cost": {"iron": 3, "wood": 1, "nails": 2}, "per_m": true,
		"kind": "barricade", "mat": "iron",
		"hint": "Steel bars on posts · 30 HP (wood 12) · drag for several"},
	{"id": "iron_door", "name": "Reinforced door", "short": "Iron", "tool": "place", "slot": 2, "cost": {"wood": 4, "nails": 6, "iron": 3},
		"kind": "door", "mat": "iron",
		"hint": "A plank door under riveted iron · 42 HP (wood 18) · aim at a wall or doorway"},
	{"id": "workbench", "name": "Workbench", "short": "Workbench", "tool": "place", "slot": 5, "cost": {"wood": 5, "nails": 6, "scrap": 2},
		"kind": "workbench", "mat": "wood",
		"hint": "E at the bench turns 3 scrap into 1 iron · R rotates"},
	{"id": "foundation", "name": "Stone foundation", "short": "Stone", "tool": "place", "slot": 9, "cost": {"stone": 2}, "per_m": true,
		"hint": "1 m x 1 m slabs on a wall line · drag for a strip · stone walls need one"},
	# --- Experiment 004 -----------------------------------------------------------------
	{"id": "window_boards", "name": "Window boards", "short": "Window", "tool": "place", "slot": 1, "cost": {"wood": 3, "nails": 6},
		"kind": "boards", "mat": "wood",
		"hint": "Planks over a 1 m window section · 14 HP · stop bullets and bodies"},
	{"id": "metal_door", "name": "Metal door", "short": "Metal", "tool": "place", "slot": 2, "cost": {"iron": 6, "scrap": 2, "nails": 4},
		"kind": "door", "mat": "metal",
		"hint": "A steel door · 70 HP (wood 18, reinforced 42) · aim at a wall or doorway"},
	{"id": "fuse_box", "name": "Fuse box", "short": "Fuse box", "tool": "place", "slot": 5, "cost": {"iron": 6, "scrap": 8, "nails": 4},
		"kind": "fuse_box", "mat": "wood",
		"hint": "The main power switch · only one · aim at a wall: it hangs on your side"},
	# --- Experiment 004: floors, stairs and storeys (owner L; src/levels/level_build.gd) ----
	{"id": "wood_floor", "name": "Wooden floor", "short": "Wood floor", "tool": "place", "slot": 9, "cost": {"wood": 2, "nails": 2},
		"hint": "A 1 m plank tile where there is no floor · Demolish takes floor tiles up"},
	# Exp 005 (V): hints for five levels (-2..+2); "upper_floor" is the "Next storey" piece; the pillar.
	{"id": "stairs_up", "name": "Stairs up", "short": "Stairs up", "tool": "place", "slot": 9, "cost": {"wood": 8, "nails": 10},
		"hint": "Ground floor or higher, 1 x 2 m plus a free cell at the foot · R turns · walk onto them or E"},
	{"id": "stairs_down", "name": "Stairs down", "short": "Stairs down", "tool": "place", "slot": 9, "cost": {"wood": 8, "nails": 10},
		"hint": "Ground floor or lower, over dug cells below: the 2 under them and 1 past the end · R turns"},
	{"id": "upper_floor", "name": "Next storey", "short": "Next storey", "tool": "place", "slot": 9, "cost": {"wood": 40, "nails": 40, "iron": 4},
		"hint": "Needs stairs up · a deck over the house with outer walls and windows, one level up (+1, then +2) · PgUp / PgDn change level"},
	{"id": "excavate", "name": "Excavate", "short": "Dig", "tool": "dig", "slot": 9, "cost": {},
		"hint": "Shovel · a 1 m cell under the house (25 min, energy, +1 stone) · down there: next to dug space · PgDn from the basement: the lower basement"},
	{"id": "pillar", "name": "Stone pillar", "short": "Pillar", "tool": "place", "slot": 9, "cost": {"stone": 4},
		"hint": "A 0.4 m masonry column in a cell · carries a floor tile above · props an outer wall within 2 m"},
	# --- Exp 005 (F): furniture and storage (key 5; FurnitureCatalog, src/home/) ----------
	{"id": "move", "name": "Move furniture", "short": "Move", "tool": "move", "slot": 4, "cost": {},
		"hint": "Click a piece to pick it up (yours or the house's) · click again to set it down · R turns it · RMB puts it back · free"},
	{"id": "cupboard", "name": "Kitchen cupboard", "short": "Cupboard", "tool": "place", "slot": 4, "cost": {"wood": 4, "nails": 6, "scrap": 1}, "kind": "cupboard", "mat": "wood",
		"hint": "Kitchen cupboard · holds 30 (food and household supplies) · R rotates"},
	{"id": "storage_chest", "name": "Storage chest", "short": "Chest", "tool": "place", "slot": 4, "cost": {"wood": 5, "nails": 6, "scrap": 1}, "kind": "storage_chest", "mat": "wood",
		"hint": "Storage chest · holds 80 (anything) · R rotates"},
	{"id": "tool_cabinet", "name": "Tool cabinet", "short": "Tool cab.", "tool": "place", "slot": 4, "cost": {"wood": 2, "nails": 4, "scrap": 5}, "kind": "tool_cabinet", "mat": "wood",
		"hint": "Tool cabinet · holds 60 (tools and construction supplies) · R rotates"},
	{"id": "wardrobe", "name": "Wardrobe", "short": "Wardrobe", "tool": "place", "slot": 4, "cost": {"wood": 7, "nails": 8}, "kind": "wardrobe", "mat": "wood",
		"hint": "Wardrobe · holds 24 (clothing and equipment) · R rotates"},
	{"id": "shelves", "name": "Shelves", "short": "Shelves", "tool": "place", "slot": 4, "cost": {"wood": 2, "nails": 4, "scrap": 3}, "kind": "shelves", "mat": "wood",
		"hint": "Shelves · hold 60 (materials and smaller items) · R rotates"},
	{"id": "bookshelf", "name": "Bookshelf", "short": "Bookshelf", "tool": "place", "slot": 4, "cost": {"wood": 5, "nails": 6}, "kind": "bookshelf", "mat": "wood",
		"hint": "Bookshelf · holds 30 (materials and smaller items) · R rotates"},
	{"id": "dresser", "name": "Dresser", "short": "Dresser", "tool": "place", "slot": 4, "cost": {"wood": 4, "nails": 6}, "kind": "dresser", "mat": "wood",
		"hint": "Dresser · holds 20 (small personal things) · R rotates"},
	{"id": "nightstand", "name": "Nightstand", "short": "Nightstand", "tool": "place", "slot": 4, "cost": {"wood": 2, "nails": 3}, "kind": "nightstand", "mat": "wood",
		"hint": "Nightstand · holds 8 (small personal things) · R rotates"},
	{"id": "bed", "name": "Bed", "short": "Bed", "tool": "place", "slot": 4, "cost": {"wood": 6, "nails": 8, "scrap": 1}, "kind": "bed", "mat": "wood",
		"hint": "E sleeps in it · R rotates"},
	{"id": "sofa", "name": "Sofa", "short": "Sofa", "tool": "place", "slot": 4, "cost": {"wood": 5, "nails": 6, "scrap": 2}, "kind": "sofa", "mat": "wood",
		"hint": "Furniture · R rotates"},
	{"id": "armchair", "name": "Armchair", "short": "Armchair", "tool": "place", "slot": 4, "cost": {"wood": 3, "nails": 4, "scrap": 1}, "kind": "armchair", "mat": "wood",
		"hint": "Furniture · R rotates"},
	{"id": "chair", "name": "Chair", "short": "Chair", "tool": "place", "slot": 4, "cost": {"wood": 2, "nails": 2}, "kind": "chair", "mat": "wood",
		"hint": "Furniture · R rotates"},
	{"id": "dining_table", "name": "Dining table", "short": "Table", "tool": "place", "slot": 4, "cost": {"wood": 5, "nails": 6}, "kind": "dining_table", "mat": "wood",
		"hint": "Furniture · R rotates"},
	{"id": "coffee_table", "name": "Coffee table", "short": "Coffee tbl", "tool": "place", "slot": 4, "cost": {"wood": 3, "nails": 4}, "kind": "coffee_table", "mat": "wood",
		"hint": "Furniture · R rotates"},
	{"id": "rug", "name": "Rug", "short": "Rug", "tool": "place", "slot": 4, "cost": {"nails": 2, "scrap": 1}, "kind": "rug", "mat": "wood",
		"hint": "Lies flat: furniture can stand on it · R rotates"},
	{"id": "floor_lamp", "name": "Floor lamp", "short": "Floor lamp", "tool": "place", "slot": 4, "cost": {"scrap": 3, "nails": 1}, "kind": "floor_lamp", "mat": "wood",
		"hint": "Shines while the house has power · E switches it · R rotates"},
	{"id": "table_lamp", "name": "Table lamp", "short": "Table lamp", "tool": "place", "slot": 4, "cost": {"scrap": 2}, "kind": "table_lamp", "mat": "wood",
		"hint": "On a table or the floor · shines while the house has power · E switches it · R rotates"},
	{"id": "painting", "name": "Painting", "short": "Painting", "tool": "place", "slot": 4, "cost": {"wood": 1, "nails": 1}, "kind": "painting", "mat": "wood",
		"hint": "Aim at a wall: it hangs on your side"},
	{"id": "plant", "name": "Plant", "short": "Plant", "tool": "place", "slot": 4, "cost": {"wood": 1}, "kind": "plant", "mat": "wood",
		"hint": "Furniture · R rotates"},
	# --- Exp 006 (B): house and balance -------------------------------------------------
	{"id": "timber_footing", "name": "Timber footing", "short": "Timber", "tool": "place", "slot": 9, "cost": {"wood": 2, "nails": 2}, "per_m": true,
		"cat": "walls", "requires": "", "icon": "foundation",
		"hint": "Cheap 1 m plank footing · wooden walls on it are founded (stone walls need stone) · drag for a strip"},
	{"id": "remove_window", "name": "Remove window", "short": "Window", "tool": "remove_window", "slot": 8, "cost": {"wood": 3, "nails": 4}, "per_m": true,
		"cat": "tools", "requires": "", "icon": "window",
		"hint": "Aim at a window: it becomes solid wall like the wall around it · the frame gives back a plank, a nail and scrap per metre"},
	{"id": "tv_stand", "name": "TV", "short": "TV", "tool": "place", "slot": 4, "cost": {"wood": 3, "nails": 4, "scrap": 6}, "kind": "tv_stand", "mat": "wood",
		"cat": "utilities", "requires": "", "icon": "tv",
		"hint": "A TV on a stand · E switches it · needs power · a little comfort and mood while it's on (one per room counts) · R rotates"},
	{"id": "radio", "name": "Radio", "short": "Radio", "tool": "place", "slot": 4, "cost": {"scrap": 4, "nails": 1}, "kind": "radio", "mat": "wood",
		"cat": "utilities", "requires": "", "icon": "radio",
		"hint": "A mains radio: soft static and voices · E switches it · needs power · on a table or the floor · R rotates"},
]

## Wall costs per 1 m segment by material (demolish refunds half).
const WALL_COST := {"wood": 4, "nails": 6}
const WALL_COSTS := {"wood": {"wood": 4, "nails": 6}, "stone": {"stone": 6}}
const FOUNDATION_COST := {"stone": 2}
const TIMBER_FOOTING_COST := {"wood": 2, "nails": 2}       ## Exp 006 (B)
## Exp 006 (B): "Remove window" per 1 m section: the wall that fills it
## (cost) and what the frame gives back (glass breaks: nothing for it).
const WINDOW_FILL_COST := {"wood": 3, "nails": 4}
const WINDOW_FRAME_SALVAGE := {"wood": 1, "nails": 1, "scrap": 1}
## Costs of placed objects (object repair and demolish refunds); iron
## variants in OBJECT_COST_MAT.
const OBJECT_COST := {
	"door": {"wood": 4, "nails": 6, "scrap": 1},
	"barricade": {"wood": 2, "nails": 4},
	"crate": {"wood": 3, "nails": 4},
	"rain_collector": {"wood": 2, "nails": 2, "scrap": 3},
	"workbench": {"wood": 5, "nails": 6, "scrap": 2},
	"boards": {"wood": 3, "nails": 6},
	"fuse_box": {"iron": 6, "scrap": 8, "nails": 4},
}
const OBJECT_COST_MAT := {
	"door": {"iron": {"wood": 4, "nails": 6, "iron": 3}, "metal": {"iron": 6, "scrap": 2, "nails": 4}},
	"barricade": {"iron": {"iron": 3, "wood": 1, "nails": 2}},
}
## Repair rates: voxels of a section restored per unit of each resource.
## Timber framing: 1 plank / 150 voxels + 1 nail / 60 (Experiment 002);
## masonry: 1 stone / 90; iron plating: 1 iron / 60.
const REPAIR_RATE := {"wood": 150.0, "nails": 60.0, "stone": 90.0, "iron": 60.0}
const COST_ORDER := ["wood", "stone", "iron", "nails", "scrap"]
## Experiment 004: Reinforce on a door, material -> {"to", "cost"}.
const REINFORCE := {
	"door": {"wood": {"to": "iron", "cost": {"iron": 3, "nails": 4}}, "iron": {"to": "metal", "cost": {"iron": 4, "scrap": 2}}},
}
## Salvage from demolishing original house structures (per 1 m section,
## scaled by the section's integrity): about half of a built one's cost.
const ORIGINAL_SALVAGE := {"wall": {"wood": 2, "nails": 3}, "window": {"wood": 1, "scrap": 2}}


static func index_of(id: String) -> int:
	for i in LIST.size():
		if LIST[i]["id"] == id:
			return i
	return -1


## LIST indices of the pieces in palette slot `slot`, in variant order.
static func variants(slot: int) -> Array:
	var out := []
	for i in LIST.size():
		if int(LIST[i]["slot"]) == slot:
			out.append(i)
	return out


static func slot_of(i: int) -> int:
	return int(LIST[i]["slot"]) if i >= 0 and i < LIST.size() else -1


static func times(cost: Dictionary, n: int) -> Dictionary:
	var out := {}
	for k in cost:
		out[k] = int(cost[k]) * n
	return out


static func add(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	for k in b:
		out[k] = int(out.get(k, 0)) + int(b[k])
	return out


## The next Reinforce step of an object ({"to", "cost"}), or {}.
static func reinforce_step(kind: String, mat: String) -> Dictionary:
	return REINFORCE.get(kind, {}).get(mat, {})


## What demolishing an object gives back: its full cost when the player
## built it; for an original piece half of its plain (wooden) cost, plus
## every Reinforce step the player paid for on it.
static func object_refund(kind: String, mat: String, is_built: bool) -> Dictionary:
	if is_built:
		return object_cost(kind, mat).duplicate()
	var out := refund(object_cost(kind, "wood"))
	var m := "wood"
	var steps := 0
	while m != mat and REINFORCE.get(kind, {}).has(m) and steps < 4:
		var st: Dictionary = REINFORCE[kind][m]
		out = add(out, st["cost"])
		m = st["to"]
		steps += 1
	return out


## Salvage of an original wall ("wall") or window ("window") section with
## `integrity` 0..1 left (rounded, at least 1 of each while anything stands).
static func original_salvage(what: String, integrity := 1.0) -> Dictionary:
	var out := {}
	var base: Dictionary = ORIGINAL_SALVAGE.get(what, {})
	for k in base:
		var n := roundi(int(base[k]) * clampf(integrity, 0.0, 1.0))
		if n <= 0 and integrity > 0.05:
			n = 1
		if n > 0:
			out[k] = n
	return out


## Half the cost, rounded down.
static func refund(cost: Dictionary) -> Dictionary:
	var out := {}
	for k in cost:
		if int(cost[k]) / 2 > 0:
			out[k] = int(cost[k]) / 2
	return out


## What an object of `kind` in material `mat` costs.
static func object_cost(kind: String, mat := "wood") -> Dictionary:
	if mat != "wood" and OBJECT_COST_MAT.has(kind) and OBJECT_COST_MAT[kind].has(mat):
		return OBJECT_COST_MAT[kind][mat]
	return OBJECT_COST.get(kind, FurnitureCatalog.cost(kind))      # Exp 005 (F): furniture


static func wall_cost(material: String) -> Dictionary:
	return WALL_COSTS.get(material, WALL_COST)


## SPEC-002: 1 wood per 150 missing voxels + 1 nail per 60 (rounded up).
static func section_repair_cost(missing: int) -> Dictionary:
	if missing <= 0:
		return {}
	return {"wood": ceili(missing / REPAIR_RATE["wood"]), "nails": ceili(missing / REPAIR_RATE["nails"])}


## Repair by material (HouseWorld.section_missing_by): timber as above,
## 1 stone per 90 missing masonry voxels, 1 iron per 60 missing plate voxels.
static func section_repair_cost_by(missing: Dictionary) -> Dictionary:
	var out := section_repair_cost(int(missing.get("wood", 0)))
	var st := int(missing.get("stone", 0))
	if st > 0:
		out["stone"] = ceili(st / REPAIR_RATE["stone"])
	var ir := int(missing.get("iron", 0))
	if ir > 0:
		out["iron"] = ceili(ir / REPAIR_RATE["iron"])
	return out


## SPEC-002: lost-HP fraction x the piece's cost (its material's), minimum
## 1 of its main material (wood, or iron for iron and metal pieces and the
## fuse box).
static func object_repair_cost(kind: String, hp: int, max_hp: int, mat := "wood") -> Dictionary:
	var frac := clampf(1.0 - float(hp) / float(maxi(max_hp, 1)), 0.0, 1.0)
	if frac <= 0.0:
		return {}
	var out := {}
	var base: Dictionary = object_cost(kind, mat)
	if base.is_empty():
		base = {"wood": 1}
	for k in base:
		var n := ceili(frac * int(base[k]))
		if n > 0:
			out[k] = n
	var main := "iron" if mat != "wood" or kind == "fuse_box" else "wood"
	out[main] = maxi(int(out.get(main, 0)), 1)
	return out


static func cost_text(cost: Dictionary) -> String:
	if cost.is_empty():
		return "free"
	var parts := PackedStringArray()
	for k in COST_ORDER:
		if cost.has(k) and int(cost[k]) > 0:
			parts.append("%d %s" % [cost[k], Items.name_of(k).to_lower()])
	return ", ".join(parts)
