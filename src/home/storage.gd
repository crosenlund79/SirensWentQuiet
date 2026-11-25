class_name FurnitureStorage
extends RefCounted
## Experiment 005 (F): storage furniture. Pure rules for what a piece of
## furniture holds and for moving items between it and the household pool
## (GameState.inventory). No nodes here.
##
## Model: the household pool is what you carry and use. Furniture storage is
## extra, separately counted space: putting items into a cupboard takes them
## out of the pool's count (and out from under the pool's material caps);
## taking them out puts them back. Building, crafting, eating from the bar
## and expeditions only use the pool; food and drink can also be eaten
## straight out of storage (use_from). Every transfer moves exactly what it
## reports: the count leaves one side and arrives on the other, or nothing
## happens (no duplication, no deletion).
##
## Contents are a Dictionary item id -> positive int, owned by the piece
## (HouseFurniture piece "items", WorldObject.items) and saved with its world.

## Profiles: capacity in items, the item categories it takes ([] = anything)
## and what it is for (shown in the panel).
const PROFILES := {
	"cupboard": {"holds": ["food", "water", "medical", "utility", "ammo"], "for": "food and household supplies"},
	"fridge": {"holds": ["food", "water"], "for": "food and drink"},
	"wardrobe": {"holds": ["weapon", "ammo", "protective", "utility", "tool", "medical"], "for": "clothing and equipment"},
	"chest": {"holds": [], "for": "general supplies"},
	"shelf": {"holds": ["material", "food", "water", "medical", "ammo", "utility", "tool"], "for": "materials and smaller items"},
	"tools": {"holds": ["tool", "material", "ammo", "utility"], "for": "tools and construction supplies"},
	"drawers": {"holds": ["weapon", "ammo", "protective", "utility", "medical", "food", "water"], "for": "small personal things"},
	"cabinet": {"holds": ["medical", "water", "utility"], "for": "medicine and toiletries"},
	"pile": {"holds": [], "for": "whatever was inside"},
}
## Furniture type (SPEC §2 names, original or placed) -> [profile, capacity].
## Capacity 0 = unlimited (loot piles only).
const TYPES := {
	"cupboard": ["cupboard", 30],
	"counter": ["cupboard", 20],
	"island": ["cupboard", 24],
	"fridge": ["fridge", 24],
	"wardrobe": ["wardrobe", 24],
	"storage_chest": ["chest", 80],
	"boxes": ["chest", 30],
	"shelves": ["shelf", 60],
	"bookshelf": ["shelf", 30],
	"tool_cabinet": ["tools", 60],
	"dresser": ["drawers", 20],
	"nightstand": ["drawers", 8],
	"vanity": ["cabinet", 10],
	"loot_pile": ["pile", 0],
}
## Display names of the storage types that differ from their capitalised type.
const NAMES := {"cupboard": "Kitchen cupboard", "counter": "Kitchen cupboard", "island": "Kitchen island", "storage_chest": "Storage chest",
	"boxes": "Cardboard boxes", "tool_cabinet": "Tool cabinet", "vanity": "Bathroom cabinet", "loot_pile": "Pile of belongings", "shelves": "Shelves"}
## What the original house starts with in some of its containers (a small
## bonus on top of the start items, found by looking around).
const START := {"fridge": {"canned_food": 1, "water": 1}, "shelves": {"nails": 6, "scrap": 1}, "vanity": {"bandage": 1}}
const RULE_TEXT := "Stored items are kept aside: building, crafting and the quick bar use only what you carry. Take them out to use them."


static func is_storage(type: String) -> bool:
	return TYPES.has(type)


static func profile_of(type: String) -> String:
	return str(TYPES[type][0]) if TYPES.has(type) else ""


## Items the type holds (0 = unlimited; -1 = not storage).
static func capacity(type: String) -> int:
	return int(TYPES[type][1]) if TYPES.has(type) else -1


static func name_of(type: String) -> String:
	return str(NAMES.get(type, type.capitalize()))


static func purpose(type: String) -> String:
	return str(PROFILES.get(profile_of(type), {}).get("for", ""))


## True if `type` takes item `id` at all (its categories).
static func accepts(type: String, id: String) -> bool:
	if not TYPES.has(type) or not Items.has(id):
		return false
	var holds: Array = PROFILES[profile_of(type)]["holds"]
	return holds.is_empty() or Items.category(id) in holds


static func total(items: Dictionary) -> int:
	var n := 0
	for id in items:
		n += maxi(int(items[id]), 0)
	return n


## How many more items fit (a large number for unlimited).
static func space_left(type: String, items: Dictionary) -> int:
	var cap := capacity(type)
	if cap < 0:
		return 0
	if cap == 0:
		return Inventory.MAX_COUNT
	return maxi(cap - total(items), 0)


## "12/30" (or "12" for a pile).
static func fill_text(type: String, items: Dictionary) -> String:
	var cap := capacity(type)
	return "%d/%d" % [total(items), cap] if cap > 0 else str(total(items))


## Untrusted save data -> clean contents: known items, positive ints.
static func clean(v: Variant) -> Dictionary:
	var out := {}
	if typeof(v) != TYPE_DICTIONARY:
		return out
	for id in v:
		if not Items.has(id):
			continue
		var n := Inventory.to_count(v[id])
		if n > 0:
			out[str(id)] = int(out.get(str(id), 0)) + n
	return out


static func merge(into: Dictionary, add: Dictionary) -> void:
	for id in add:
		var n := int(add[id])
		if n > 0:
			into[id] = int(into.get(id, 0)) + n


## "2 canned food, 6 nails" (sorted by item order), or "empty".
static func contents_text(items: Dictionary) -> String:
	var parts := PackedStringArray()
	for id in Items.DEFS:
		if int(items.get(id, 0)) > 0:
			parts.append("%d %s" % [int(items[id]), Items.name_of(id).to_lower()])
	return ", ".join(parts) if not parts.is_empty() else "empty"


## Moves up to `n` of `id` from the household pool into `items` (a piece of
## type `type`). Returns how many moved. A weapon leaving the pool unloads
## its magazine into the pool first (no rounds vanish with it).
static func store(state: GameState, items: Dictionary, type: String, id: String, n: int) -> int:
	if state == null or not accepts(type, id):
		return 0
	var k := mini(mini(n, state.inventory.count(id)), space_left(type, items))
	if k <= 0:
		return 0
	if WeaponDefs.has(id) and state.inventory.count(id) - k <= 0:
		var loaded := state.magazine(id)
		if loaded > 0:
			state.inventory.add(WeaponDefs.ammo_of(id), loaded)
			state.set_magazine(id, 0)
	if not state.inventory.remove(id, k):
		return 0
	items[id] = int(items.get(id, 0)) + k
	return k


## Moves up to `n` of `id` from `items` into the household pool (as far as
## the pool's caps allow). Returns how many moved.
static func take(state: GameState, items: Dictionary, id: String, n: int) -> int:
	if state == null:
		return 0
	var k := mini(mini(n, int(items.get(id, 0))), state.inventory.space_for(id))
	if k <= 0:
		return 0
	var added := state.inventory.add(id, k)
	if added <= 0:
		return 0
	var left := int(items[id]) - added
	if left <= 0:
		items.erase(id)
	else:
		items[id] = left
	return added


## Takes everything that fits. Returns {id: n} of what moved.
static func take_all(state: GameState, items: Dictionary) -> Dictionary:
	var got := {}
	for id in items.keys():
		var k := take(state, items, id, int(items[id]))
		if k > 0:
			got[id] = k
	return got


## Eats, drinks or applies one `id` straight from `items` (through the pool
## and GameState.use_item, so the needs rules stay one). Returns
## {"ok", "text"}: the game's text, or why not (nothing moved then).
static func use_from(state: GameState, items: Dictionary, id: String) -> Dictionary:
	if state == null or not Items.is_consumable(id) or int(items.get(id, 0)) <= 0:
		return {"ok": false, "text": "Nothing to use."}
	if take(state, items, id, 1) != 1:
		return {"ok": false, "text": "No room for it."}
	var why := state.can_use(id)
	var text := state.use_item(id) if why == "" else ""
	if text == "":          # refused: it goes back where it was
		items[id] = int(items.get(id, 0)) + 1
		state.inventory.remove(id, 1)
		return {"ok": false, "text": why if why != "" else "Not now."}
	return {"ok": true, "text": text}
