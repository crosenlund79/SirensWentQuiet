class_name BuildCatalog
extends RefCounted
## Exp 006 (U): the construction menu's data. Pure data and small helpers.
##
## The menu (BuildPalette) is built from two things only: CATEGORIES (the tabs,
## in key order 1-8) and the pieces in BuildPieces.LIST. Each piece belongs
## to one category and has one icon (a UiIcons name):
##   - a LIST entry's own "cat" and "icon" fields win (new entries set them,
##     SPEC-006 §1);
##   - the pieces of Experiments 002-005 are categorised in PIECES below (one
##     table instead of edits to every LIST line, so the other agents' edits
##     of those lines merge cleanly);
##   - an entry with only the old "slot" falls back to SLOT_CAT;
##   - an unknown icon falls back to the category's icon.
## Adding an item to the menu = adding a LIST entry with "cat" (and "icon").
## Adding a category = one CATEGORIES line and its icon alias in UiIcons.
##
## Gating (SPEC-006 §2): lock_reason() asks R's `Research.locked_reason(state,
## piece)` when that class exists (R keeps the gates in Research.GATES by
## piece id), else checks an entry's "requires" against `state.skills`. Availability (SPEC-006 §3): available() asks B's supply
## helper (BuildMode.available / stored: carried plus stored in the house's
## furniture) when it is there, else counts the household inventory.

const CATEGORIES := [
	{"id": "walls", "key": "1", "name": "Walls & foundations", "short": "Walls", "icon": "cat_walls"},
	{"id": "floors", "key": "2", "name": "Floors & stairs", "short": "Floors", "icon": "cat_floors"},
	{"id": "doors", "key": "3", "name": "Doors & windows", "short": "Doors", "icon": "cat_doors"},
	{"id": "defense", "key": "4", "name": "Fortifications", "short": "Defence", "icon": "cat_defense"},
	{"id": "furniture", "key": "5", "name": "Furniture & storage", "short": "Furniture", "icon": "cat_furniture"},
	{"id": "utilities", "key": "6", "name": "Utilities", "short": "Utilities", "icon": "cat_utilities"},
	{"id": "decor", "key": "7", "name": "Decorations", "short": "Decor", "icon": "cat_decor"},
	{"id": "tools", "key": "8", "name": "Demolition & modifications", "short": "Tools", "icon": "cat_tools"},
]

## Pieces of Experiments 002-005: id -> [category, icon].
const PIECES := {
	"wall": ["walls", "planks"], "stone_wall": ["walls", "bricks"], "foundation": ["walls", "slab"],
	"wood_floor": ["floors", "floor"], "stairs_up": ["floors", "stairs"], "stairs_down": ["floors", "stairs"],
	"upper_floor": ["floors", "storey"], "excavate": ["floors", "shovel"], "pillar": ["floors", "pillar"],
	"door": ["doors", "door"], "doorway": ["doors", "doorway"], "iron_door": ["doors", "door"],
	"metal_door": ["doors", "door_metal"],
	"barricade": ["defense", "barricade"], "iron_barricade": ["defense", "barricade"],
	"window_boards": ["defense", "boards"],
	"crate": ["furniture", "crate"], "cupboard": ["furniture", "cabinet"], "storage_chest": ["furniture", "chest"],
	"tool_cabinet": ["furniture", "cabinet"], "wardrobe": ["furniture", "cabinet"], "shelves": ["furniture", "shelves"],
	"bookshelf": ["furniture", "book"], "dresser": ["furniture", "cabinet"], "nightstand": ["furniture", "cabinet"],
	"bed": ["furniture", "bed"], "sofa": ["furniture", "sofa"], "armchair": ["furniture", "chair"],
	"chair": ["furniture", "chair"], "dining_table": ["furniture", "table"], "coffee_table": ["furniture", "table"],
	"rain_collector": ["utilities", "barrel"], "workbench": ["utilities", "workbench"], "fuse_box": ["utilities", "fuse"],
	"floor_lamp": ["utilities", "lamp"], "table_lamp": ["utilities", "lamp"],
	"rug": ["decor", "rug"], "painting": ["decor", "painting"], "plant": ["decor", "plant"],
	"repair": ["tools", "wrench"], "upgrade": ["tools", "plate"], "demolish": ["tools", "demolish"], "move": ["tools", "move"],
	# Exp 006 (D, B): the defences and the house pieces (their entries carry "cat"; icons here)
	"spikes_wood": ["defense", "spikes"], "spikes_metal": ["defense", "spikes_metal"], "trench": ["defense", "trench"],
	"trench_water": ["defense", "moat"], "backfill": ["defense", "shovel"], "drawbridge_1": ["defense", "bridge"],
	"drawbridge_2": ["defense", "bridge"], "timber_footing": ["walls", "slab"], "remove_window": ["tools", "window"],
	"tv_stand": ["utilities", "tv"], "radio": ["utilities", "radio"],
}

## What a tile says instead of a cost (free tools and pieces), by piece id, then by tool.
const NOTES := {
	"excavate": "shovel, +1 stone", "trench": "shovel, free", "trench_water": "rain or bottles",
	"backfill": "shovel, free",
}
const TOOL_NOTES := {"repair": "uses the material", "demolish": "gives back", "move": "free", "dig": "shovel"}

## Experiment 004-005 palette slots -> category (entries that only set "slot").
const SLOT_CAT := {0: "walls", 1: "defense", 2: "doors", 3: "doors", 4: "furniture", 5: "utilities",
	6: "tools", 7: "tools", 8: "tools", 9: "floors"}

## Direct keys for the frequent tools in build mode (no menu dive).
const QUICK := [
	{"key": "F", "keycode": KEY_F, "id": "repair", "name": "Repair"},
	{"key": "X", "keycode": KEY_X, "id": "demolish", "name": "Demolish"},
	{"key": "G", "keycode": KEY_G, "id": "move", "name": "Move"},
]
const RECENT_MAX := 6

## Materials shown in the menu's header, in this order.
const MATERIALS := ["wood", "stone", "iron", "nails", "scrap"]

static var _research: Variant = 0      # 0 = not looked up yet; null = absent


static func count() -> int:
	return CATEGORIES.size()


## Index of category `id` (0-7), or -1.
static func index_of(id: String) -> int:
	for i in CATEGORIES.size():
		if CATEGORIES[i]["id"] == id:
			return i
	return -1


## The category id of BuildPieces.LIST[i].
static func category_of(i: int) -> String:
	if i < 0 or i >= BuildPieces.LIST.size():
		return ""
	return category_for(BuildPieces.LIST[i])


## The category id of a piece entry: its "cat", the PIECES table, its old "slot".
static func category_for(p: Dictionary) -> String:
	var c := str(p.get("cat", ""))
	if c != "" and index_of(c) >= 0:
		return c
	if PIECES.has(str(p.get("id", ""))):
		return PIECES[str(p["id"])][0]
	return str(SLOT_CAT.get(int(p.get("slot", 8)), "tools"))


## The category index (0-7) of BuildPieces.LIST[i], or -1.
static func category_index_of(i: int) -> int:
	return index_of(category_of(i))


## The icon of BuildPieces.LIST[i]: its own, the table's, or its category's.
static func icon_of(i: int) -> String:
	if i < 0 or i >= BuildPieces.LIST.size():
		return "dot"
	return icon_for(BuildPieces.LIST[i])


## The icon of a piece entry: its "icon" (when UiIcons knows it), the PIECES
## table's, else its category's.
static func icon_for(p: Dictionary) -> String:
	var ic := str(p.get("icon", ""))
	if ic != "" and UiIcons.has(ic):
		return ic
	if PIECES.has(str(p.get("id", ""))):
		return PIECES[str(p["id"])][1]
	var ci := index_of(category_for(p))
	return str(CATEGORIES[ci]["icon"]) if ci >= 0 else "dot"


## LIST indices of category index `ci`, in LIST order.
static func pieces_in(ci: int) -> Array:
	var out := []
	if ci < 0 or ci >= CATEGORIES.size():
		return out
	var id: String = CATEGORIES[ci]["id"]
	for i in BuildPieces.LIST.size():
		if category_of(i) == id:
			out.append(i)
	return out


## "" when `piece` may be built, else why not ("Requires Metalworking ...").
static func lock_reason(state: Object, piece: Dictionary) -> String:
	var research := _research_script()
	if research != null:
		var r: Variant = research.call("locked_reason", state, piece)
		return str(r) if r != null else ""
	var req := str(piece.get("requires", ""))
	if req == "" or state == null:
		return ""
	var skills: Variant = state.get("skills")
	if skills is Dictionary:
		return "" if (skills as Dictionary).get(req, false) else "Requires %s" % req.capitalize()
	if skills is Array:
		return "" if req in skills else "Requires %s" % req.capitalize()
	return ""


## R's Research class (a global script class) when it is in the project.
static func _research_script() -> Script:
	if typeof(_research) == TYPE_INT:
		_research = null
		for c in ProjectSettings.get_global_class_list():
			if str(c.get("class", "")) == "Research":
				var s: Variant = load(str(c.get("path", "")))
				if s is Script:
					for m in (s as Script).get_script_method_list():
						if str(m.get("name", "")) == "locked_reason":
							_research = s
							break
				break
	return _research as Script


## How many of `item` building can draw on: B's house supply (inventory plus
## the house's storage) when it is wired, else the inventory.
static func available(build: Object, item: String) -> int:
	if build == null:
		return 0
	if build.has_method("available"):                 # B's BuildMode.available (carried + stored)
		return int(build.call("available", item))
	var supply: Variant = build.get("supply")
	if supply is Object and supply != null and (supply as Object).has_method("available"):
		return int((supply as Object).call("available", item))
	var state: Variant = build.get("state")
	if not (state is Object) or state == null:
		return 0
	if (state as Object).has_method("available"):
		return int((state as Object).call("available", item))
	return int((state as GameState).inventory.count(item)) if state is GameState else 0


## How much of `item` the house's storage adds (B's BuildMode.stored), else 0.
static func stored(build: Object, item: String) -> int:
	if build != null and build.has_method("stored"):
		return int(build.call("stored", item))
	return 0


## What a tile shows instead of a cost for a piece without one.
static func note_for(p: Dictionary) -> String:
	var id := str(p.get("id", ""))
	if NOTES.has(id):
		return NOTES[id]
	return str(TOOL_NOTES.get(str(p.get("tool", "")), "free"))


## True when the menu should compare the piece's cost with what is available
## (placing, upgrading, B's window removal; not the free tools).
static func priced(p: Dictionary) -> bool:
	return not (p.get("cost", {}) as Dictionary).is_empty() and not str(p.get("tool", "")) in ["repair", "demolish", "move", "dig"]


## What is missing to pay `cost` from `build` ({} when affordable; the
## unlimited cheat makes everything affordable).
static func missing(build: Object, cost: Dictionary) -> Dictionary:
	var out := {}
	if cost.is_empty() or build == null:
		return out
	var state: Variant = build.get("state")
	if state is GameState and (state as GameState).cheats.get("unlimited", false):
		return out
	for k in cost:
		var short := int(cost[k]) - available(build, str(k))
		if short > 0:
			out[k] = short
	return out
