class_name PoiArchetypes
extends RefCounted
## Experiment 009 (G): the catalog of building archetypes the generator
## (PoiGenerator) builds from, and the site -> archetype table (SPEC-009
## "Sites and archetypes"). Pure data; no nodes.
##
## A new archetype is one ARCHETYPES entry (and, for a new map site, one
## SITES line). Its keys:
##   family     residential | commercial | industry | public | outdoor
##   name       what the F10 tools and the test sites call it
##   plan       "bands": rows of rooms from the front (south) to the back,
##              each row split across the width; "corridor": a front row,
##              then a corridor running north with rooms either side;
##              "yard": a site hut on open ground (bands inside the hut;
##              the hut is the bounds, PoiExterior fences the lot)
##   w, d       the footprint's width (x) and depth (z) ranges in metres, by
##              setup size s / m / l (the lower, middle or upper part)
##   bands      plan bands: [{"d": [lo, hi], "rooms": [room]}], front first;
##              room: {"type", "w": [lo, hi], "req": bool, "p": chance when
##              optional, "grow": takes the spare width}. A band with
##              "grow" takes the spare depth.
##   front, cols  plan corridor: the front row (as a band) and the two columns
##              beside the corridor ([[room], [room]]: room "d" ranges, one
##              with "grow")
##   hut        plan yard: the hut's bands (its own w / d ranges)
##   style      exterior wall style (brick | siding | plank); "paint" for
##              interior drywall; "floor" the default floor art
##   entrance   "door" | "double" | "open" (a smashed or open shopfront) |
##              "bay" (a wide open vehicle door plus a door)
##   back_door  chance of a rear door on the north wall
##   storefront true: big low windows either side of the entrance
##   stash      {"rooms": [types, best first], "kinds": [{piece, label,
##              holds}], "needs": chance it needs a crowbar, "lock_room":
##              chance its room's door is locked}
##   danger     {"hide": n, "dormant": [lo, hi], "behaviours": {name: weight}}
##   picked     share of containers already picked clean
##   dark       chance a windowless back room is pitch dark
##   loot_site  an ExpeditionData id whose loot tables test sites
##              (gen:<archetype>:<seed>) use
##   pickups    loose items that may lie about [[item, n]]
##   arrival    arrival lines (one by seed)
##   variants   named overrides (police "outpost" for the military site)

const FAMILIES := ["residential", "commercial", "industry", "public", "outdoor"]

## Room kinds. floor: art ("" = the archetype's floor); win: gets windows on
## outside walls; open: an open-plan room (open gaps to its open neighbours);
## hub: how readily other rooms open off it (corridors highest); private: a
## dead end (never a way through); dark: may be pitch dark when windowless.
const ROOM_TYPES := {
	"living": {"floor": "", "win": true, "open": true, "hub": 2, "name": "living room"},
	"kitchen": {"floor": "floor_kitchen", "win": true, "open": true, "hub": 1, "name": "kitchen"},
	"dining": {"floor": "", "win": true, "open": true, "hub": 3, "name": "dining room"},
	"bedroom": {"floor": "floor_wood", "win": true, "private": true, "name": "bedroom"},
	"bathroom": {"floor": "floor_tile", "private": true, "name": "bathroom"},
	"storage": {"floor": "floor_concrete", "private": true, "dark": true, "name": "storage room"},
	"hallway": {"floor": "floor_wood_light", "hub": 4, "name": "hallway"},
	"corridor": {"floor": "floor_tile", "hub": 5, "name": "corridor"},
	"lobby": {"floor": "floor_tile", "win": true, "open": true, "hub": 4, "name": "lobby"},
	"waiting": {"floor": "floor_wood_light", "win": true, "open": true, "hub": 3, "name": "waiting room"},
	"sales": {"floor": "floor_tile", "win": true, "hub": 4, "name": "sales floor"},
	"gun_counter": {"floor": "floor_wood", "win": true, "hub": 4, "name": "shop"},
	"stockroom": {"floor": "floor_concrete", "private": true, "dark": true, "hub": 1, "name": "stockroom"},
	"office": {"floor": "floor_wood", "win": true, "private": true, "name": "office"},
	"toilet": {"floor": "floor_tile", "private": true, "name": "toilet"},
	"staff": {"floor": "floor_kitchen", "win": true, "private": true, "name": "staff room"},
	"lockers": {"floor": "floor_tile", "private": true, "dark": true, "name": "locker room"},
	"work_floor": {"floor": "floor_concrete", "win": true, "hub": 4, "name": "work floor"},
	"bay": {"floor": "floor_concrete", "hub": 4, "name": "bay"},
	"hall": {"floor": "floor_concrete", "hub": 4, "name": "warehouse floor"},
	"ward": {"floor": "floor_tile", "win": true, "private": true, "name": "ward"},
	"exam": {"floor": "floor_tile", "win": true, "private": true, "name": "examination room"},
	"pharmacy": {"floor": "floor_tile", "private": true, "dark": true, "name": "dispensary"},
	"armoury": {"floor": "floor_concrete", "private": true, "dark": true, "name": "armoury"},
	"cells": {"floor": "floor_concrete", "private": true, "name": "cells"},
	"evidence": {"floor": "floor_concrete", "private": true, "dark": true, "name": "evidence room"},
	"lanes": {"floor": "floor_concrete", "hub": 2, "name": "firing lanes"},
	"dorm": {"floor": "floor_wood", "win": true, "private": true, "name": "dormitory"},
	"hut": {"floor": "floor_wood_light", "win": true, "hub": 3, "name": "site hut"},
}

const ARCHETYPES := {
	# --- residential --------------------------------------------------------------------
	"house_small": {
		"family": "residential", "name": "Small house", "plan": "bands", "style": "siding", "paint": 0xd8cfc0, "floor": "floor_wood",
		"w": [8, 11], "d": [7, 9],
		"bands": [
			{"d": [4, 5], "grow": true, "rooms": [{"type": "living", "w": [4, 6], "req": true, "grow": true}, {"type": "kitchen", "w": [3, 4], "req": true}]},
			{"d": [3, 4], "rooms": [{"type": "bedroom", "w": [3, 4], "req": true, "grow": true}, {"type": "bathroom", "w": [2, 3], "req": true},
				{"type": "storage", "w": [2, 3], "p": 0.5}]},
		],
		"entrance": "door", "back_door": 0.6,
		"stash": {"rooms": ["bedroom", "storage"], "kinds": [{"piece": "safe", "label": "wall safe", "holds": []},
			{"piece": "storage_chest", "label": "locked strongbox", "holds": []}], "needs": 0.85, "lock_room": 0.15},
		"danger": {"hide": 3, "dormant": [1, 3], "behaviours": {"sway": 3, "stare": 3, "bang": 1, "tap": 1, "circle": 1}},
		"picked": 0.25, "dark": 0.3, "loot_site": "homes", "pickups": [["snacks", 1], ["water", 1], ["bandage", 1]],
		"arrival": ["A small house. The curtains are drawn.", "A small house. The front door hangs open."],
	},
	"house_family": {
		"family": "residential", "name": "Family house", "plan": "bands", "style": "siding", "paint": 0xdcd3c2, "floor": "floor_wood",
		"w": [11, 14], "d": [9, 11],
		"bands": [
			{"d": [4, 5], "grow": true, "rooms": [{"type": "living", "w": [4, 6], "req": true, "grow": true}, {"type": "dining", "w": [3, 4], "p": 0.5},
				{"type": "kitchen", "w": [3, 4], "req": true}]},
			{"d": [2, 2], "rooms": [{"type": "hallway", "w": [4, 20], "req": true, "grow": true}]},
			{"d": [3, 4], "rooms": [{"type": "bedroom", "w": [3, 4], "req": true, "grow": true}, {"type": "bathroom", "w": [2, 3], "req": true},
				{"type": "bedroom", "w": [3, 4], "req": true}, {"type": "storage", "w": [2, 2], "p": 0.4}]},
		],
		"entrance": "door", "back_door": 0.7,
		"stash": {"rooms": ["bedroom", "storage"], "kinds": [{"piece": "safe", "label": "gun safe", "holds": ["weapon", "ammo", "protective", "tool"]},
			{"piece": "safe", "label": "wall safe", "holds": []}], "needs": 0.85, "lock_room": 0.2},
		"danger": {"hide": 4, "dormant": [2, 3], "behaviours": {"sway": 3, "stare": 3, "bang": 2, "tap": 1, "circle": 1}},
		"picked": 0.25, "dark": 0.3, "loot_site": "cul_de_sac", "pickups": [["snacks", 1], ["water", 1], ["nails", 4]],
		"arrival": ["A family house. Toys in the snow by the door.", "A family house. Somebody boarded up one window and stopped."],
	},
	"cottage": {
		"family": "residential", "name": "Cottage", "plan": "bands", "style": "plank", "paint": 0xd6ccb4, "floor": "floor_wood",
		"w": [7, 9], "d": [6, 8],
		"bands": [
			{"d": [3, 4], "grow": true, "rooms": [{"type": "living", "w": [3, 5], "req": true, "grow": true}, {"type": "kitchen", "w": [3, 3], "req": true}]},
			{"d": [3, 4], "rooms": [{"type": "bedroom", "w": [3, 4], "req": true, "grow": true}, {"type": "bathroom", "w": [2, 2], "req": true},
				{"type": "storage", "w": [2, 3], "p": 0.6}]},
		],
		"entrance": "door", "back_door": 0.5,
		"stash": {"rooms": ["storage", "bedroom"], "kinds": [{"piece": "storage_chest", "label": "padlocked chest", "holds": []}],
			"needs": 0.8, "lock_room": 0.1},
		"danger": {"hide": 3, "dormant": [1, 2], "behaviours": {"sway": 3, "stare": 2, "bang": 2, "tap": 1, "circle": 1}},
		"picked": 0.3, "dark": 0.35, "loot_site": "farmhouse", "pickups": [["wood", 2], ["water", 1]],
		"arrival": ["A cottage. Smoke stains above the stove pipe, long cold.", "A cottage. The porch boards creak."],
	},
	"apartment": {
		"family": "residential", "name": "Apartment", "plan": "bands", "style": "brick", "paint": 0xd4cec0, "floor": "floor_wood",
		"w": [9, 12], "d": [7, 9], "apartment": true,
		"bands": [
			{"d": [2, 2], "rooms": [{"type": "hallway", "w": [4, 20], "req": true, "grow": true, "shared": true}]},
			{"d": [3, 4], "grow": true, "rooms": [{"type": "living", "w": [4, 6], "req": true, "grow": true}, {"type": "kitchen", "w": [3, 4], "req": true}]},
			{"d": [2, 3], "rooms": [{"type": "bedroom", "w": [3, 4], "req": true, "grow": true}, {"type": "bathroom", "w": [2, 3], "req": true},
				{"type": "storage", "w": [2, 2], "req": true}]},
		],
		"entrance": "none", "back_door": 0.0,
		"stash": {"rooms": ["storage", "bedroom"], "kinds": [{"piece": "safe", "label": "closet safe", "holds": []},
			{"piece": "storage_chest", "label": "locked trunk", "holds": []}], "needs": 0.85, "lock_room": 0.25},
		"danger": {"hide": 3, "dormant": [1, 3], "behaviours": {"sway": 3, "stare": 3, "bang": 2, "tap": 2, "circle": 1}},
		"picked": 0.25, "dark": 0.4, "loot_site": "homes", "pickups": [["snacks", 1], ["water", 1]],
		"arrival": ["The stairwell. One door on this landing is still shut.", "A dark hallway. Somebody's flat at the end."],
	},
	# --- commercial ---------------------------------------------------------------------
	"supermarket": {
		"family": "commercial", "name": "Supermarket", "plan": "bands", "style": "brick", "paint": 0xd8d2c4, "floor": "floor_tile",
		"w": [13, 17], "d": [9, 12],
		"bands": [
			{"d": [6, 8], "grow": true, "rooms": [{"type": "sales", "w": [8, 20], "req": true, "grow": true}]},
			{"d": [3, 4], "rooms": [{"type": "stockroom", "w": [4, 7], "req": true, "grow": true}, {"type": "office", "w": [3, 4], "req": true},
				{"type": "toilet", "w": [2, 2], "p": 0.7}, {"type": "staff", "w": [3, 4], "p": 0.4}]},
		],
		"entrance": "open", "storefront": true, "back_door": 0.8,
		"stash": {"rooms": ["office", "stockroom"], "kinds": [{"piece": "safe", "label": "manager's safe", "holds": []},
			{"piece": "tool_cabinet", "label": "locked stock cage", "holds": []}], "needs": 0.85, "lock_room": 0.4},
		"danger": {"hide": 4, "dormant": [2, 4], "behaviours": {"sway": 2, "stare": 2, "bang": 1, "tap": 3, "circle": 2}},
		"picked": 0.35, "dark": 0.4, "loot_site": "grocery", "pickups": [["canned_food", 1], ["water", 1], ["snacks", 1]],
		"arrival": ["The supermarket. Trolleys frozen into the snow outside.", "The supermarket. The aisles go back into the dark."],
	},
	"diner": {
		"family": "commercial", "name": "Diner", "plan": "bands", "style": "brick", "paint": 0xe0d6c0, "floor": "floor_tile",
		"w": [10, 13], "d": [8, 10],
		"bands": [
			{"d": [5, 6], "grow": true, "rooms": [{"type": "dining", "w": [8, 20], "req": true, "grow": true}]},
			{"d": [3, 4], "rooms": [{"type": "kitchen", "w": [4, 6], "req": true, "grow": true}, {"type": "storage", "w": [2, 3], "req": true},
				{"type": "toilet", "w": [2, 2], "p": 0.6}, {"type": "office", "w": [2, 3], "p": 0.5}]},
		],
		"entrance": "double", "storefront": true, "back_door": 0.8,
		"stash": {"rooms": ["office", "storage"], "kinds": [{"piece": "safe", "label": "cash safe", "holds": []},
			{"piece": "storage_chest", "label": "locked dry-goods chest", "holds": ["food", "water", "utility"]}], "needs": 0.8, "lock_room": 0.3},
		"danger": {"hide": 3, "dormant": [1, 3], "behaviours": {"sway": 2, "stare": 2, "bang": 2, "tap": 2, "circle": 3}},
		"picked": 0.3, "dark": 0.3, "loot_site": "diner", "pickups": [["canned_food", 1], ["water", 1]],
		"arrival": ["The diner. Plates still on the tables.", "The diner. The neon sign is dead; the smell isn't."],
	},
	"pharmacy": {
		"family": "commercial", "name": "Pharmacy", "plan": "bands", "style": "brick", "paint": 0xe2e4dc, "floor": "floor_tile",
		"w": [9, 12], "d": [8, 10],
		"bands": [
			{"d": [5, 6], "grow": true, "rooms": [{"type": "sales", "w": [6, 20], "req": true, "grow": true}]},
			{"d": [3, 4], "rooms": [{"type": "pharmacy", "w": [3, 5], "req": true, "grow": true}, {"type": "office", "w": [2, 3], "req": true},
				{"type": "toilet", "w": [2, 2], "p": 0.5}]},
		],
		"entrance": "double", "storefront": true, "back_door": 0.6,
		"stash": {"rooms": ["pharmacy", "office"], "kinds": [{"piece": "tool_cabinet", "label": "controlled-drugs cabinet", "holds": ["medical"]},
			{"piece": "safe", "label": "pharmacy safe", "holds": ["medical", "utility"]}], "needs": 0.9, "lock_room": 0.5},
		"danger": {"hide": 3, "dormant": [1, 3], "behaviours": {"sway": 2, "stare": 3, "bang": 1, "tap": 3, "circle": 1}},
		"picked": 0.4, "dark": 0.5, "loot_site": "drugstore", "pickups": [["bandage", 1], ["water", 1]],
		"arrival": ["The pharmacy. The shutters were forced long ago.", "The pharmacy. Empty blister packs crunch underfoot."],
	},
	"office": {
		"family": "commercial", "name": "Office block", "plan": "corridor", "style": "brick", "paint": 0xd6d6d0, "floor": "floor_wood",
		"w": [11, 14], "d": [9, 12],
		"front": {"d": [3, 4], "rooms": [{"type": "lobby", "w": [5, 20], "req": true, "grow": true}, {"type": "office", "w": [3, 4], "p": 0.6}]},
		"cols": [
			[{"type": "office", "d": [3, 4], "req": true, "grow": true}, {"type": "office", "d": [3, 3], "req": true}, {"type": "toilet", "d": [2, 2], "p": 0.5}],
			[{"type": "staff", "d": [3, 4], "req": true}, {"type": "storage", "d": [2, 3], "req": true}, {"type": "office", "d": [3, 4], "req": true, "grow": true}],
		],
		"entrance": "double", "back_door": 0.7,
		"stash": {"rooms": ["storage", "office"], "kinds": [{"piece": "safe", "label": "office safe", "holds": []},
			{"piece": "filing_cabinet", "label": "locked records cabinet", "holds": ["book", "utility", "medical", "ammo"]}], "needs": 0.85, "lock_room": 0.4},
		"danger": {"hide": 4, "dormant": [2, 4], "behaviours": {"sway": 3, "stare": 3, "bang": 2, "tap": 2, "circle": 1}},
		"picked": 0.3, "dark": 0.5, "loot_site": "library", "pickups": [["water", 1], ["snacks", 1]],
		"arrival": ["The office block. Papers drift across the lobby.", "The office block. A phone off the hook somewhere."],
	},
	# --- light industry -----------------------------------------------------------------
	"workshop": {
		"family": "industry", "name": "Workshop", "plan": "bands", "style": "brick", "paint": 0xcfc8b8, "floor": "floor_concrete",
		"w": [10, 13], "d": [8, 10],
		"bands": [
			{"d": [5, 6], "grow": true, "rooms": [{"type": "work_floor", "w": [6, 20], "req": true, "grow": true}]},
			{"d": [3, 4], "rooms": [{"type": "storage", "w": [3, 5], "req": true, "grow": true}, {"type": "office", "w": [3, 4], "req": true},
				{"type": "toilet", "w": [2, 2], "p": 0.5}]},
		],
		"entrance": "bay", "back_door": 0.6,
		"stash": {"rooms": ["storage", "office"], "kinds": [{"piece": "tool_cabinet", "label": "locked tool cage", "holds": ["tool", "material", "utility"]},
			{"piece": "storage_chest", "label": "padlocked tool chest", "holds": ["tool", "material", "utility"]}], "needs": 0.85, "lock_room": 0.35},
		"danger": {"hide": 3, "dormant": [1, 3], "behaviours": {"sway": 2, "stare": 2, "bang": 3, "tap": 2, "circle": 2}},
		"picked": 0.3, "dark": 0.4, "loot_site": "hardware", "pickups": [["nails", 6], ["scrap", 1]],
		"arrival": ["The workshop. Sawdust and old oil.", "The workshop. A radio on the bench, hissing on a dead battery."],
	},
	"garage": {
		"family": "industry", "name": "Auto garage", "plan": "bands", "style": "brick", "paint": 0xcac4b6, "floor": "floor_concrete",
		"w": [11, 14], "d": [8, 10],
		"bands": [
			{"d": [5, 6], "grow": true, "rooms": [{"type": "bay", "w": [7, 20], "req": true, "grow": true}]},
			{"d": [3, 4], "rooms": [{"type": "storage", "w": [3, 5], "req": true, "grow": true}, {"type": "office", "w": [3, 4], "req": true},
				{"type": "toilet", "w": [2, 2], "p": 0.4}]},
		],
		"entrance": "bay", "back_door": 0.5,
		"stash": {"rooms": ["storage", "office"], "kinds": [{"piece": "tool_cabinet", "label": "locked parts cage", "holds": ["tool", "material", "utility"]},
			{"piece": "safe", "label": "cash safe", "holds": []}], "needs": 0.85, "lock_room": 0.35},
		"danger": {"hide": 3, "dormant": [1, 3], "behaviours": {"sway": 2, "stare": 2, "bang": 2, "tap": 2, "circle": 3}},
		"picked": 0.3, "dark": 0.4, "loot_site": "scrapyard", "pickups": [["scrap", 2], ["nails", 4]],
		"arrival": ["The auto garage. A car still up on the ramp.", "The auto garage. The roller door is jammed half open."],
	},
	"warehouse": {
		"family": "industry", "name": "Warehouse", "plan": "bands", "style": "plank", "paint": 0xc9c2b2, "floor": "floor_concrete",
		"w": [14, 18], "d": [10, 12],
		"bands": [
			{"d": [7, 9], "grow": true, "rooms": [{"type": "hall", "w": [10, 20], "req": true, "grow": true}]},
			{"d": [3, 3], "rooms": [{"type": "office", "w": [3, 4], "req": true}, {"type": "storage", "w": [3, 5], "req": true, "grow": true},
				{"type": "toilet", "w": [2, 2], "p": 0.5}, {"type": "staff", "w": [3, 4], "p": 0.4}]},
		],
		"entrance": "bay", "back_door": 0.8,
		"stash": {"rooms": ["storage", "office"], "kinds": [{"piece": "tool_cabinet", "label": "locked security cage", "holds": []},
			{"piece": "safe", "label": "office safe", "holds": []}], "needs": 0.85, "lock_room": 0.4},
		"danger": {"hide": 4, "dormant": [2, 4], "behaviours": {"sway": 2, "stare": 2, "bang": 2, "tap": 2, "circle": 3}},
		"picked": 0.3, "dark": 0.5, "loot_site": "warehouse", "pickups": [["nails", 6], ["wood", 2]],
		"arrival": ["The warehouse. The racks go up into the dark.", "The warehouse. Forklift tracks frozen into the dust."],
	},
	"factory": {
		"family": "industry", "name": "Factory", "plan": "bands", "style": "brick", "paint": 0xc4c0b4, "floor": "floor_concrete",
		"w": [14, 18], "d": [10, 12],
		"bands": [
			{"d": [6, 8], "grow": true, "rooms": [{"type": "work_floor", "w": [10, 20], "req": true, "grow": true}]},
			{"d": [3, 4], "rooms": [{"type": "lockers", "w": [3, 4], "req": true}, {"type": "office", "w": [3, 4], "req": true},
				{"type": "storage", "w": [3, 5], "req": true, "grow": true}, {"type": "toilet", "w": [2, 2], "p": 0.6}]},
		],
		"entrance": "bay", "back_door": 0.8,
		"stash": {"rooms": ["office", "storage"], "kinds": [{"piece": "safe", "label": "payroll safe", "holds": []},
			{"piece": "tool_cabinet", "label": "locked maintenance cage", "holds": ["tool", "material", "utility"]}], "needs": 0.85, "lock_room": 0.4},
		"danger": {"hide": 4, "dormant": [2, 4], "behaviours": {"sway": 2, "stare": 2, "bang": 3, "tap": 2, "circle": 2}},
		"picked": 0.3, "dark": 0.5, "loot_site": "warehouse", "pickups": [["scrap", 2], ["nails", 6]],
		"arrival": ["The factory. The machines stopped mid-shift.", "The factory. Something drips in the dark at the back."],
	},
	# --- outdoor industrial ---------------------------------------------------------------
	"yard": {
		"family": "outdoor", "name": "Yard", "plan": "yard", "style": "plank", "paint": 0xd0c8b4, "floor": "floor_concrete",
		"w": [14, 18], "d": [9, 11],
		"hut": {"w": [4, 6], "d": [3, 4], "bands": [{"d": [3, 4], "grow": true, "rooms": [{"type": "hut", "w": [3, 4], "req": true, "grow": true},
			{"type": "storage", "w": [2, 2], "p": 0.5}]}]},
		"entrance": "door", "back_door": 0.0,
		"stash": {"rooms": ["hut", "storage"], "kinds": [{"piece": "safe", "label": "site safe", "holds": []},
			{"piece": "storage_chest", "label": "padlocked site box", "holds": ["tool", "material", "utility"]}], "needs": 0.9, "lock_room": 0.3},
		"danger": {"hide": 2, "dormant": [1, 3], "behaviours": {"sway": 3, "stare": 2, "bang": 1, "tap": 1, "circle": 3}},
		"picked": 0.3, "dark": 0.2, "loot_site": "scrapyard", "pickups": [["scrap", 2], ["wood", 2], ["nails", 4]],
		"arrival": ["The yard. Snow over everything, and things under the snow.", "The yard. The gate chain was cut."],
	},
	# --- public -------------------------------------------------------------------------
	"hospital": {
		"family": "public", "name": "Hospital wing", "plan": "corridor", "style": "brick", "paint": 0xdfe3dc, "floor": "floor_tile",
		"w": [14, 18], "d": [10, 12],
		"front": {"d": [4, 4], "rooms": [{"type": "lobby", "w": [5, 20], "req": true, "grow": true}, {"type": "waiting", "w": [4, 6], "req": true}]},
		"cols": [
			[{"type": "ward", "d": [3, 4], "req": true, "grow": true}, {"type": "ward", "d": [3, 4], "p": 0.7}, {"type": "exam", "d": [3, 3], "req": true}],
			[{"type": "pharmacy", "d": [3, 3], "req": true}, {"type": "staff", "d": [3, 4], "req": true, "grow": true}, {"type": "toilet", "d": [2, 2], "p": 0.6},
				{"type": "storage", "d": [2, 3], "p": 0.5}],
		],
		"entrance": "double", "back_door": 0.9,
		"stash": {"rooms": ["pharmacy", "storage"], "kinds": [{"piece": "tool_cabinet", "label": "drug cage", "holds": ["medical"]}],
			"needs": 0.9, "lock_room": 0.5},
		"danger": {"hide": 5, "dormant": [2, 5], "behaviours": {"sway": 3, "stare": 3, "bang": 2, "tap": 2, "circle": 1}},
		"picked": 0.35, "dark": 0.6, "loot_site": "hospital", "pickups": [["bandage", 1], ["water", 1]],
		"arrival": ["The hospital wing. Gurneys in the doorway.", "The hospital wing. The emergency lights still flicker down the corridor."],
	},
	"police": {
		"family": "public", "name": "Police station", "plan": "corridor", "style": "brick", "paint": 0xd2d4cc, "floor": "floor_tile",
		"w": [12, 15], "d": [10, 12],
		"front": {"d": [3, 4], "rooms": [{"type": "lobby", "w": [5, 20], "req": true, "grow": true}, {"type": "office", "w": [3, 4], "req": true}]},
		"cols": [
			[{"type": "office", "d": [3, 4], "req": true, "grow": true}, {"type": "lockers", "d": [3, 3], "req": true}, {"type": "toilet", "d": [2, 2], "p": 0.5}],
			[{"type": "cells", "d": [3, 4], "req": true, "grow": true}, {"type": "armoury", "d": [3, 3], "req": true}, {"type": "evidence", "d": [2, 3], "p": 0.7}],
		],
		"entrance": "double", "back_door": 0.8,
		"stash": {"rooms": ["armoury", "evidence"], "kinds": [{"piece": "gun_rack", "label": "locked weapons rack", "holds": ["weapon", "ammo"]},
			{"piece": "safe", "label": "evidence safe", "holds": []}], "needs": 0.95, "lock_room": 0.6},
		"danger": {"hide": 4, "dormant": [2, 4], "behaviours": {"sway": 2, "stare": 3, "bang": 3, "tap": 2, "circle": 1}},
		"picked": 0.4, "dark": 0.5, "loot_site": "police", "pickups": [["ammo", 3], ["bandage", 1]],
		"arrival": ["The police station. The front desk is barricaded from the inside.", "The police station. Every cell door is open."],
		"variants": {"outpost": {
			"name": "Army outpost", "style": "siding", "paint": 0xc6c8b8, "w": [10, 12], "d": [9, 11],
			"front": {"d": [3, 4], "rooms": [{"type": "lobby", "w": [4, 20], "req": true, "grow": true}, {"type": "office", "w": [3, 4], "req": true}]},
			"cols": [
				[{"type": "dorm", "d": [3, 4], "req": true, "grow": true}, {"type": "storage", "d": [2, 3], "req": true}],
				[{"type": "armoury", "d": [3, 4], "req": true, "grow": true}, {"type": "lockers", "d": [2, 3], "req": true}],
			],
			"entrance": "door", "dark": 0.8, "loot_site": "military",
			"arrival": ["The outpost. Sandbags, a dead floodlight and no sentry.", "The outpost. The door was left on the latch."],
		}},
	},
	"clinic_small": {
		"family": "public", "name": "Small clinic", "plan": "bands", "style": "brick", "paint": 0xe0e4dc, "floor": "floor_tile",
		"w": [9, 12], "d": [8, 10],
		"bands": [
			{"d": [4, 5], "grow": true, "rooms": [{"type": "waiting", "w": [5, 20], "req": true, "grow": true}, {"type": "office", "w": [3, 3], "req": true}]},
			{"d": [3, 4], "rooms": [{"type": "exam", "w": [3, 4], "req": true, "grow": true}, {"type": "exam", "w": [3, 4], "p": 0.6},
				{"type": "pharmacy", "w": [2, 3], "req": true}, {"type": "toilet", "w": [2, 2], "p": 0.4}]},
		],
		"entrance": "door", "storefront": false, "back_door": 0.6,
		"stash": {"rooms": ["pharmacy", "office"], "kinds": [{"piece": "tool_cabinet", "label": "drug cabinet", "holds": ["medical"]}],
			"needs": 0.85, "lock_room": 0.4},
		"danger": {"hide": 3, "dormant": [1, 3], "behaviours": {"sway": 3, "stare": 3, "bang": 1, "tap": 2, "circle": 1}},
		"picked": 0.35, "dark": 0.5, "loot_site": "vet_clinic", "pickups": [["bandage", 1]],
		"arrival": ["The clinic. A bell over the door that nobody answers.", "The clinic. Paw prints in the dust of the waiting room."],
	},
	"range": {
		"family": "public", "name": "Shooting range", "plan": "bands", "style": "brick", "paint": 0xcfc9b8, "floor": "floor_concrete",
		"w": [11, 14], "d": [9, 11],
		"bands": [
			{"d": [4, 4], "rooms": [{"type": "gun_counter", "w": [5, 20], "req": true, "grow": true}, {"type": "office", "w": [3, 3], "p": 0.6}]},
			{"d": [5, 7], "grow": true, "rooms": [{"type": "lanes", "w": [7, 20], "req": true, "grow": true}, {"type": "armoury", "w": [3, 3], "req": true}]},
		],
		"entrance": "door", "back_door": 0.5,
		"stash": {"rooms": ["armoury", "office"], "kinds": [{"piece": "safe", "label": "ammunition safe", "holds": ["ammo", "weapon", "protective"]},
			{"piece": "gun_rack", "label": "locked rental rack", "holds": ["weapon", "ammo"]}], "needs": 0.9, "lock_room": 0.5},
		"danger": {"hide": 3, "dormant": [1, 3], "behaviours": {"sway": 2, "stare": 3, "bang": 2, "tap": 2, "circle": 1}},
		"picked": 0.45, "dark": 0.5, "loot_site": "shooting_range", "pickups": [["ammo", 2]],
		"arrival": ["The shooting range. Brass in drifts on the floor.", "The shooting range. The targets still hang at the far end."],
	},
	"fire_station": {
		"family": "public", "name": "Fire station", "plan": "bands", "style": "brick", "paint": 0xd4cfc2, "floor": "floor_concrete",
		"w": [13, 16], "d": [9, 11],
		"bands": [
			{"d": [6, 7], "grow": true, "rooms": [{"type": "bay", "w": [8, 20], "req": true, "grow": true}]},
			{"d": [3, 4], "rooms": [{"type": "dorm", "w": [3, 5], "req": true, "grow": true}, {"type": "kitchen", "w": [3, 4], "req": true},
				{"type": "lockers", "w": [2, 3], "req": true}, {"type": "office", "w": [2, 3], "p": 0.6}]},
		],
		"entrance": "bay", "back_door": 0.6,
		"stash": {"rooms": ["office", "lockers"], "kinds": [{"piece": "safe", "label": "station safe", "holds": []},
			{"piece": "locker", "label": "chief's locked locker", "holds": ["medical", "tool", "protective", "utility"]}], "needs": 0.85, "lock_room": 0.3},
		"danger": {"hide": 3, "dormant": [1, 3], "behaviours": {"sway": 2, "stare": 2, "bang": 2, "tap": 1, "circle": 3}},
		"picked": 0.3, "dark": 0.4, "loot_site": "hospital", "pickups": [["bandage", 1], ["water", 1]],
		"arrival": ["The fire station. The engine never left.", "The fire station. Helmets lined up on their hooks."],
	},
}

## The map sites (RegionLocations ids) -> archetype ("hand_made" = a PoiLayouts template).
const SITES := {
	"forest": "hand_made", "convenience": "hand_made", "library": "hand_made", "hardware": "hand_made", "gun_shop": "hand_made", "clinic": "hand_made",
	"homes": "house_small", "cul_de_sac": "house_family", "farmhouse": "cottage", "trailer_park": "cottage", "apartments": "apartment",
	"grocery": "supermarket", "diner": "diner", "restaurant": "diner", "fast_food": "diner", "drugstore": "pharmacy", "office_block": "office",
	"workshop": "workshop", "auto_garage": "garage", "warehouse": "warehouse", "sawmill": "warehouse", "factory": "factory",
	"scrapyard": "yard", "quarry": "yard", "construction_site": "yard", "logging": "yard",
	"hospital": "hospital", "police": "police", "military": "police", "vet_clinic": "clinic_small", "shooting_range": "range",
	"fire_station": "fire_station",
}
## Site -> archetype variant.
const SITE_VARIANTS := {"military": "outpost"}
const TEST_PREFIX := "gen:"


static func ids() -> Array:
	return ARCHETYPES.keys()


static func has(arch: String) -> bool:
	return ARCHETYPES.has(arch)


## The archetype of map site `id`: an ARCHETYPES key, "hand_made", or "" (unknown).
## Test ids gen:<archetype>:<seed> give their archetype.
static func for_site(id: String) -> String:
	if is_test_id(id):
		var a := str(id.split(":")[1])
		return a if ARCHETYPES.has(a) else ""
	return str(SITES.get(id, ""))


static func is_test_id(id: String) -> bool:
	if not id.begins_with(TEST_PREFIX):
		return false
	var parts := id.split(":")
	return parts.size() == 3 and ARCHETYPES.has(parts[1]) and parts[2].is_valid_int()


static func test_id(arch: String, seed: int) -> String:
	return "%s%s:%d" % [TEST_PREFIX, arch, seed]


static func variant_for_site(id: String) -> String:
	return str(SITE_VARIANTS.get(id, ""))


## The archetype's data with its variant's overrides applied ({} if unknown).
static func get_arch(arch: String, variant := "") -> Dictionary:
	if not ARCHETYPES.has(arch):
		return {}
	var a: Dictionary = ARCHETYPES[arch]
	var v: Dictionary = (a.get("variants", {}) as Dictionary).get(variant, {})
	if v.is_empty():
		return a
	var out := a.duplicate()
	for k in v:
		out[k] = v[k]
	return out


static func family_of(arch: String) -> String:
	return str((ARCHETYPES.get(arch, {}) as Dictionary).get("family", ""))


static func room_type(t: String) -> Dictionary:
	return ROOM_TYPES.get(t, {})


static func room_name(t: String) -> String:
	return str(room_type(t).get("name", t.replace("_", " ")))


## A setup with the SPEC's Stage A fields (DailySites.setup's shape) for a
## site, when the daily selection isn't there: seed = hash of the run seed
## and the id; the size by the seed.
static func default_setup(id: String, run_seed: int) -> Dictionary:
	var arch := for_site(id)
	var seed := hash([run_seed, id])
	if is_test_id(id):
		seed = int(id.split(":")[2])
	var sizes := ["s", "m", "l"]
	return {"id": id, "archetype": arch, "family": family_of(arch), "size": sizes[posmod(seed, 3)],
		"surroundings": "", "categories": [], "risk": 0.0, "seed": seed, "hand_made": arch == "hand_made",
		"available": true, "overrun_until": -1, "variant": variant_for_site(id)}


## A test site's setup (gen:<archetype>:<seed>).
static func test_setup(arch: String, seed: int, size := "") -> Dictionary:
	var s := default_setup(test_id(arch, seed), 0)
	if size != "":
		s["size"] = size
	return s
