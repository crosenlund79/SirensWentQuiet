class_name Items
extends RefCounted
## The small item catalogue (SPEC §6, SPEC-003 §2). Owner: K. Every item has a
## purpose in the game. Materials are capped (storage crates raise the caps);
## gear (weapons, protective, tools, utility) is capped at one each; food,
## water, ammo and medical items have no cap. Consumables carry a `verb` for UI
## buttons. Gear carries a `slot` ("weapon" = primary or secondary, "body",
## "back", "utility", "tool"; see Equipment). `raw` materials are processed
## before use (scrap -> iron at a workbench, Crafting).

const CATEGORIES := ["weapon", "ammo", "protective", "tool", "utility", "medical", "food", "water", "material"]

const DEFS := {
	"canned_food": {"name": "Canned food", "category": "food", "desc": "Beans, soup, something. Filling.", "hunger": 30.0, "hydration": 4.0, "verb": "Eat"},
	"snacks": {"name": "Snacks", "category": "food", "desc": "Crackers and bars. Takes the edge off.", "hunger": 12.0, "verb": "Eat"},
	"water": {"name": "Bottled water", "category": "water", "desc": "Clean water. The most precious thing you own.", "hydration": 30.0, "verb": "Drink"},
	"ammo": {"name": "9 mm rounds", "category": "ammo", "desc": "For the handgun. Count every one."},
	"wood": {"name": "Planks", "category": "material", "desc": "Building, barricades and repairs.", "cap": 40, "cap_per_crate": 20},
	"nails": {"name": "Nails", "category": "material", "desc": "Holds everything together.", "cap": 80, "cap_per_crate": 40},
	"scrap": {"name": "Scrap metal", "category": "material", "desc": "Raw metal: a workbench turns 3 into 1 iron. Also hinges and collectors.", "cap": 20, "cap_per_crate": 10, "raw": true},
	"bandage": {"name": "Bandage", "category": "medical", "desc": "Stops the bleeding.", "health": 20.0, "verb": "Apply"},
	"medkit": {"name": "First-aid kit", "category": "medical", "desc": "Proper supplies.", "health": 50.0, "verb": "Use"},
	# --- Experiment 003 foundation (K owns the semantics; "slot" = equipment slot) ---
	"stone": {"name": "Stone", "category": "material", "desc": "Cut stone and blocks: masonry, foundations, strong walls.", "cap": 40, "cap_per_crate": 20},
	"iron": {"name": "Iron", "category": "material", "desc": "Bars and plate: reinforcement and strong components.", "cap": 20, "cap_per_crate": 10},
	"shells": {"name": "12-gauge shells", "category": "ammo", "desc": "For the shotgun. Heavy, loud, final."},
	"handgun": {"name": "Handgun", "category": "weapon", "desc": "9 mm pistol. Reliable, quiet enough, a small magazine.", "cap": 1, "slot": "weapon"},
	"shotgun": {"name": "Shotgun", "category": "weapon", "desc": "Pump shotgun: a wide, short-range blast. Slow to reload.", "cap": 1, "slot": "weapon"},
	"vest": {"name": "Protective vest", "category": "protective", "desc": "Equipped: blows and blasts hurt 35 % less.", "cap": 1, "slot": "body"},
	"hammer": {"name": "Hammer", "category": "tool", "desc": "Needed to build and repair (kept at home).", "cap": 1, "slot": "tool"},
	"shovel": {"name": "Shovel", "category": "tool", "desc": "Digs out a basement under the house (kept at home).", "cap": 1, "slot": "tool"},
	"crowbar": {"name": "Crowbar", "category": "tool", "desc": "Equipped: opens stockrooms and locked doors on expeditions.", "cap": 1, "slot": "tool"},
	"flashlight": {"name": "Flashlight", "category": "utility", "desc": "Equipped: needed in dark places like the clinic.", "cap": 1, "slot": "utility"},
	"backpack": {"name": "Backpack", "category": "utility", "desc": "Equipped: carry half as much again from expeditions.", "cap": 1, "slot": "back"},
}


static func has(id) -> bool:
	return (typeof(id) == TYPE_STRING or typeof(id) == TYPE_STRING_NAME) and DEFS.has(str(id))


static func name_of(id) -> String:
	return DEFS[str(id)]["name"] if has(id) else str(id)


static func category(id) -> String:
	return DEFS[str(id)]["category"] if has(id) else ""


static func ids(cat := "") -> Array:
	var out := []
	for id in DEFS:
		if cat == "" or DEFS[id]["category"] == cat:
			out.append(id)
	return out


## Gear: one of each at most (weapons, protective, tools, utility).
static func is_unique(id) -> bool:
	return has(id) and int(DEFS[str(id)].get("cap", 0)) == 1


## The equipment slot kind of `id` ("weapon", "body", "back", "utility",
## "tool"), or "" if it can't be equipped.
static func slot(id) -> String:
	return str(DEFS[str(id)].get("slot", "")) if has(id) else ""


## Raw materials are processed before use (scrap -> iron, Crafting).
static func is_raw(id) -> bool:
	return has(id) and bool(DEFS[str(id)].get("raw", false))


static func is_consumable(id) -> bool:
	return category(id) in ["food", "water", "medical"]


## UI verb for a consumable ("Eat", "Drink", "Apply", "Use"); "" otherwise.
static func verb(id) -> String:
	return str(DEFS[str(id)].get("verb", "")) if is_consumable(id) else ""
