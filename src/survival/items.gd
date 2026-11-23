class_name Items
extends RefCounted
## The small item catalogue (SPEC §6). Owner: S. Every item has a purpose in the game.

const CATEGORIES := ["food", "water", "ammo", "material", "medical", "tool"]

const DEFS := {
	"canned_food": {"name": "Canned food", "category": "food", "desc": "Beans, soup, something. Filling.", "hunger": 30.0, "hydration": 4.0},
	"snacks": {"name": "Snacks", "category": "food", "desc": "Crackers and bars. Takes the edge off.", "hunger": 12.0},
	"water": {"name": "Bottled water", "category": "water", "desc": "Clean water. The most precious thing you own.", "hydration": 30.0},
	"ammo": {"name": "9 mm rounds", "category": "ammo", "desc": "For the handgun. Count every one."},
	"wood": {"name": "Planks", "category": "material", "desc": "Building, barricades and repairs.", "cap": 40, "cap_per_crate": 20},
	"nails": {"name": "Nails", "category": "material", "desc": "Holds everything together.", "cap": 80, "cap_per_crate": 40},
	"scrap": {"name": "Scrap metal", "category": "material", "desc": "Sheathing, hinges, collectors.", "cap": 20, "cap_per_crate": 10},
	"bandage": {"name": "Bandage", "category": "medical", "desc": "Stops the bleeding.", "health": 20.0},
	"medkit": {"name": "First-aid kit", "category": "medical", "desc": "Proper supplies.", "health": 50.0},
	"hammer": {"name": "Hammer", "category": "tool", "desc": "Needed to build and repair."},
	"crowbar": {"name": "Crowbar", "category": "tool", "desc": "Opens stockrooms and locked doors on expeditions."},
	"flashlight": {"name": "Flashlight", "category": "tool", "desc": "Needed in dark places like the clinic."},
	"backpack": {"name": "Backpack", "category": "tool", "desc": "Carry half as much again from expeditions."},
}


static func has(id: String) -> bool:
	return DEFS.has(id)


static func name_of(id: String) -> String:
	return DEFS[id]["name"] if DEFS.has(id) else id


static func category(id: String) -> String:
	return DEFS[id]["category"] if DEFS.has(id) else ""


static func ids(cat := "") -> Array:
	var out := []
	for id in DEFS:
		if cat == "" or DEFS[id]["category"] == cat:
			out.append(id)
	return out


static func is_consumable(id: String) -> bool:
	return category(id) in ["food", "water", "medical"]
