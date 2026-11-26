class_name ExpeditionData
extends RefCounted
## The destination framework for simulated expeditions (SPEC-002 §7.7,
## SPEC-003 §3). Owner: X. Pure data and pure helpers: nothing here touches
## the scene or mutates a GameState, except `apply_region`, which records an
## expedition's region consequences once per result id.
##
## Places come from RegionLocations (the ONE list: names, categories,
## positions, travel times). This file adds the gameplay data, keyed by the
## same ids, without per-location code:
##   PROFILES    shared loot tables per kind of place (main + "locked" table)
##               with default danger, search time, events and depletion
##   LOCATIONS   per place: its profile plus small variations (mods, extra
##               entries), danger, search minutes, requirements, preparation
##               effects, event pool and depletion overrides
##   APPROACHES  general / targeted / careful / raid
##   EVENTS      short decision events with 2-3 options
## `destination(id)` merges a place with its profile into one Dictionary.
##
## Loot entries are [item_id, min, max, chance]. Unique items (cap 1 in
## Items.DEFS: tools, weapons, the vest) are found at most once and never when
## already owned; multipliers scale their chance (capped). Stackable items
## scale their amounts (stochastic rounding).
##
## Location fields (all optional except profile; the profile supplies the rest):
##   profile     key of PROFILES
##   danger      injury scale (1.0 = moderate); risk_floor: minimum after gear
##   search      minutes on site for a general search (travel comes from RegionLocations)
##   place       word used in event text ("the supermarket's storage-room door")
##   mods        {item: factor}: stackables x amounts, uniques x chance, 0 removes
##   extra       more loot entries for this place
##   locked      replaces the profile's locked table (opened by a brought crowbar)
##   events      {event_id: weight} replaces the profile's pool; two_events: chance of a second
##   requires    [item ids] that must be owned (and are always brought)
##   prep        {"vest"|"flashlight"|"shots": factor}: the trip's danger x factor when
##               brought (shots: at least prep_shots rounds; a shell counts as SHELL_SHOTS)
##   deplete, regen, floor   stock lost per general visit, regained per day, minimum
##   max_damage  health one trip can cost at most here
##
## Event option fields (all optional):
##   label    button text
##   needs    {"crowbar"|"flashlight"|"backpack"|"vest": 1}: brought gear required
##   shots    rounds fired (needs at least as many; a shell counts as two)
##   minutes  time added (negative: the trip is cut short)
##   loot     multiplier on the main search
##   bonus    "locked" (the place's locked table), "cache" (half the main
##            table) or an Array of loot entries
##   hurt     [chance, min, max]: injury roll (scaled by the trip's danger)
##   hurt_loot  loot multiplier when the injury happens (a fight gone badly)
##   lose     [item_id, chance]: a brought tool can be lost
##   mark     [flag, days]: a lasting consequence for the place (see FLAGS)
##   discover n places found on the way (if any are left)
##   outcome  text after choosing; hurt_text / lose_text are appended when they happen
##   log      one line for the report
## Event fields: title, text (may contain %s for the place), tags (fight, dark),
## only ([approach ids]: the event only happens on those approaches).

const T := preload("res://src/survival/survival_tuning.gd")

## Gear that can be taken along: what is equipped (K's slots). The hammer
## stays home (building needs it).
const BRINGABLE_GEAR := ["crowbar", "flashlight", "backpack", "vest"]
const BRINGABLE_TOOLS := BRINGABLE_GEAR       ## Experiment 002 name
## Worn gear always comes along when equipped (it can't be left on the hook
## for one trip); the crowbar and flashlight can be left at home so they
## can't be lost.
const WORN_GEAR := ["vest", "backpack"]
## Ammunition -> the weapon that fires it (SPEC-003 §2). Rounds only count
## when that weapon is equipped (reserve + magazines, GameState.rounds_carried).
const AMMO_TYPES := {"ammo": "handgun", "shells": "shotgun"}
const SHELL_SHOTS := 2               ## a shell is worth two 9 mm rounds in a simulated fight
const BACKPACK_BONUS := 0.5          ## fallback when the state has no carry_multiplier(): +50 % on stackable loot
## The vest's -35 % on injuries is applied by GameState.damage when the result
## is applied (K); the resolver only uses the vest for risk and options.
const MAX_DAMAGE := 40.0             ## health one expedition can cost at most (default)
const MIN_MINUTES := 60
const TRAVEL_JITTER := Vector2i(-15, 15)
const LOOT_MULT_RANGE := Vector2(0.3, 1.6)
const LOW_ENERGY := 15.0             ## exhausted: risk up
const LOW_ENERGY_DANGER := 1.25
const DARK_FLASHLIGHT_SCALE := 0.5   ## injury chance in dark places with a flashlight
const FIGHT_AMMO_SCALE := 0.5        ## damage when you fire to get clear (1 round)
const UNIQUE_CHANCE_MAX := 0.95
const DEFAULT_ROUNDS := 12           ## the gear screen suggests up to this many 9 mm rounds
const DEFAULT_SHELLS := 6

## Experiment 004 (E): the repaired yard car (GameState.car_repaired) as
## expedition equipment, gear id "car" (not an item). It needs a fuel can and
## burns CAR_FUEL per trip; travel takes CAR_TRAVEL of the time; stackable
## loot x CAR_CARRY (on top of the backpack), materials x CAR_MATERIAL_MULT
## more, and the heavy loads of CAR_HAUL (by kind of place) only come home by car.
const CAR := "car"
const CAR_FUEL := 1
const CAR_TRAVEL := 0.6
const CAR_CARRY := 2.0
const CAR_MATERIAL_MULT := 1.5
const CAR_MATERIALS := ["wood", "stone", "iron", "scrap"]
const CAR_HAUL := {
	"residential": [["wood", 3, 6, 0.6], ["scrap", 2, 4, 0.5], ["fuel", 1, 1, 0.3]],
	"food": [["water", 3, 6, 0.7], ["canned_food", 2, 4, 0.6]],
	"medical": [["medkit", 1, 1, 0.35], ["water", 2, 3, 0.4]],
	"construction": [["stone", 3, 6, 0.6], ["iron", 1, 3, 0.5], ["wood", 4, 8, 0.6]],
	"weapons": [["ammo", 3, 6, 0.4], ["iron", 1, 2, 0.3]],
}

const RISK_NAMES := ["Low", "Moderate", "High", "Severe"]
const RISK_BOUNDS := [0.9, 1.15, 1.45]

## Category display order (RegionLocations.CATEGORIES has the names).
const CATEGORY_ORDER := ["residential", "food", "medical", "construction", "weapons", "knowledge"]   # Exp 006 (R): knowledge

## Display order (grouped by category); the same ids as RegionLocations.
const ORDER := [
	"homes", "cul_de_sac", "trailer_park", "farmhouse", "apartments",
	"convenience", "grocery", "diner", "restaurant", "fast_food",
	"drugstore", "clinic", "vet_clinic", "hospital", "fire_station",
	"hardware", "forest", "logging", "sawmill", "quarry", "construction_site", "scrapyard", "warehouse",
	"auto_garage", "workshop", "factory",
	"gun_shop", "shooting_range", "police", "military",
	"library", "office_block",      # Exp 006 (R): the library; Exp 009 (D): + six places
]

# --- loot profiles ---------------------------------------------------------------------

const PROFILES := {
	"residential": {
		"place": "house", "danger": 0.8, "search": 130, "two_events": 0.4,
		"loot": [
			["canned_food", 1, 2, 0.85], ["snacks", 1, 3, 0.7], ["water", 1, 3, 0.85],
			["wood", 2, 5, 0.55], ["nails", 4, 10, 0.65], ["bandage", 1, 1, 0.35],      # Exp 008 (E): nails 0.5 -> 0.65 (PACING.md)
			["ammo", 2, 4, 0.15], ["crowbar", 1, 1, 0.12], ["flashlight", 1, 1, 0.2], ["backpack", 1, 1, 0.15],
		],
		"locked": [["wood", 3, 5, 0.8], ["nails", 6, 12, 0.7], ["scrap", 1, 3, 0.5], ["canned_food", 1, 2, 0.5]],
		"locked_name": "locked garages", "locked_text": "The crowbar opened a locked garage.",
		"events": {"boarded_house": 3, "collapsed_floor": 2, "locked_car": 2, "dogs": 2, "lone_psycho": 1, "tracks": 1, "fog_bank": 1},
		"deplete": 0.2, "regen": 0.03, "floor": 0.15,
	},
	"food": {
		"place": "shop", "danger": 1.0, "search": 170, "two_events": 0.6,
		"loot": [["canned_food", 2, 4, 0.95], ["snacks", 2, 4, 0.85], ["water", 2, 4, 1.0], ["bandage", 1, 1, 0.2], ["backpack", 1, 1, 0.08]],
		"locked": [["water", 2, 3, 0.85], ["canned_food", 1, 3, 0.75], ["snacks", 1, 2, 0.5]],
		"locked_name": "the stockroom", "locked_text": "The crowbar opened the stockroom.",
		"events": {"storage_door": 3, "lone_psycho": 2, "dogs": 1, "locked_car": 1, "tracks": 1, "fog_bank": 1},
		"deplete": 0.25, "regen": 0.02, "floor": 0.1,
	},
	"medical": {
		"place": "clinic", "danger": 1.1, "search": 180, "two_events": 0.7,
		"loot": [["bandage", 2, 4, 1.0], ["medkit", 1, 2, 0.6], ["ammo", 3, 6, 0.3], ["water", 1, 2, 0.4]],
		"locked": [["medkit", 1, 1, 0.9], ["bandage", 1, 3, 0.7], ["ammo", 2, 5, 0.4]],
		"locked_name": "the drug cage", "locked_text": "The crowbar opened the drug cage.",
		"events": {"dark_pharmacy": 4, "waiting_room": 2, "dogs": 1, "tracks": 1, "fog_bank": 1},
		"deplete": 0.3, "regen": 0.015, "floor": 0.1,
	},
	"construction_wood": {
		"place": "timber yard", "danger": 0.95, "search": 190, "two_events": 0.55,
		"loot": [
			["wood", 6, 12, 1.0], ["nails", 6, 12, 0.8], ["scrap", 1, 4, 0.5],
			["hammer", 1, 1, 0.4], ["crowbar", 1, 1, 0.35], ["flashlight", 1, 1, 0.2],
		],
		"locked": [["wood", 5, 9, 0.8], ["nails", 8, 14, 0.75], ["scrap", 2, 5, 0.6]],
		"locked_name": "the stockroom", "locked_text": "The crowbar opened the stockroom.",
		"events": {"timber_rack": 3, "heavy_load": 2, "storage_door": 1, "lone_psycho": 1, "tracks": 1, "fog_bank": 1},
		"deplete": 0.22, "regen": 0.03, "floor": 0.15,
	},
	"construction_stone": {
		"place": "site", "danger": 1.0, "search": 200, "two_events": 0.5,
		"loot": [
			["stone", 4, 8, 1.0], ["scrap", 1, 3, 0.45], ["iron", 1, 2, 0.3], ["nails", 2, 6, 0.35],
			["wood", 1, 3, 0.3], ["flashlight", 1, 1, 0.12], ["crowbar", 1, 1, 0.12],
		],
		"locked": [["stone", 3, 6, 0.85], ["iron", 1, 3, 0.5], ["nails", 4, 8, 0.5]],
		"locked_name": "the site container", "locked_text": "The crowbar opened the site container.",
		"events": {"heavy_load": 3, "lone_psycho": 1, "dogs": 1, "tracks": 1, "fog_bank": 2},
		"deplete": 0.12, "regen": 0.06, "floor": 0.4,
	},
	"construction_iron": {
		"place": "yard", "danger": 1.05, "search": 190, "two_events": 0.6,
		"loot": [["scrap", 3, 7, 1.0], ["iron", 1, 3, 0.7], ["nails", 4, 10, 0.5], ["wood", 1, 3, 0.3], ["crowbar", 1, 1, 0.2]],
		"locked": [["iron", 2, 4, 0.8], ["scrap", 3, 6, 0.8], ["nails", 6, 10, 0.5]],
		"locked_name": "the locked shed", "locked_text": "The crowbar opened the locked shed.",
		"events": {"heavy_load": 3, "dogs": 2, "lone_psycho": 1, "locked_car": 2, "fog_bank": 1},
		"deplete": 0.15, "regen": 0.05, "floor": 0.3,
	},
	"weapons": {
		"place": "shop", "danger": 1.45, "search": 150, "two_events": 0.75,
		"loot": [
			["ammo", 2, 5, 0.65], ["shells", 1, 3, 0.4], ["bandage", 1, 1, 0.3],
			["flashlight", 1, 1, 0.2], ["vest", 1, 1, 0.08], ["shotgun", 1, 1, 0.06],
		],
		"locked": [["ammo", 2, 6, 0.7], ["shells", 1, 3, 0.5], ["shotgun", 1, 1, 0.15], ["vest", 1, 1, 0.15]],
		"locked_name": "the locked cabinet", "locked_text": "The crowbar opened a locked cabinet.",
		"events": {"armoury": 3, "lone_psycho": 2, "patrol": 2, "storage_door": 1, "fog_bank": 1},
		"deplete": 0.35, "regen": 0.01, "floor": 0.05,
		"max_damage": 50.0, "risk_floor": 0.9,
	},
	"military": {
		"place": "outpost", "danger": 2.6, "search": 260, "two_events": 1.0,
		"loot": [
			["ammo", 3, 8, 0.7], ["shells", 2, 4, 0.5], ["vest", 1, 1, 0.3], ["shotgun", 1, 1, 0.18],
			["medkit", 1, 1, 0.5], ["bandage", 1, 2, 0.5], ["flashlight", 1, 1, 0.3],
			["canned_food", 1, 3, 0.5], ["water", 1, 3, 0.5], ["iron", 1, 2, 0.3],
		],
		"locked": [["ammo", 4, 8, 0.75], ["shells", 2, 4, 0.6], ["vest", 1, 1, 0.35], ["shotgun", 1, 1, 0.25], ["medkit", 1, 2, 0.5]],
		"locked_name": "a sealed container", "locked_text": "The crowbar opened a sealed container.",
		"events": {"outpost_gate": 5, "patrol": 3, "armoury": 3, "fog_bank": 1},
		"deplete": 0.3, "regen": 0.02, "floor": 0.15,
		"max_damage": 60.0, "risk_floor": 1.0,
	},
	# Exp 006 (R): books and technical manuals (Research). Books are unique
	# items: found once, never when owned or already learned (ExpeditionRun).
	# Few people looted a library, so the stock falls slowly and stays.
	"library": {
		"place": "library", "danger": 1.05, "search": 180, "two_events": 0.55,
		"loot": [
			["book_woodworking", 1, 1, 0.45], ["book_reinforced", 1, 1, 0.25], ["book_metalworking", 1, 1, 0.14],
			["book_advanced_metal", 1, 1, 0.06], ["water", 1, 2, 0.4], ["snacks", 1, 2, 0.45], ["bandage", 1, 1, 0.25],
			["flashlight", 1, 1, 0.12], ["backpack", 1, 1, 0.06],
			["book_electronics", 1, 1, 0.2], ["book_automation", 1, 1, 0.07],      # Exp 007 (S)
		],
		"locked": [["book_reinforced", 1, 1, 0.3], ["book_metalworking", 1, 1, 0.25], ["book_advanced_metal", 1, 1, 0.15], ["snacks", 1, 2, 0.4], ["water", 1, 2, 0.3],
			["book_automation", 1, 1, 0.15]],      # Exp 007 (S)
		"locked_name": "the locked archive", "locked_text": "The crowbar opened the locked archive in the basement.",
		"events": {"dark_stacks": 3, "reading_room": 3, "lone_psycho": 2, "tracks": 1, "fog_bank": 1},
		"deplete": 0.15, "regen": 0.03, "floor": 0.3,
	},
}

# --- locations (keyed by RegionLocations ids) --------------------------------------------

const LOCATIONS := {
	# family houses: small variations of the residential profile
	"homes": {"profile": "residential", "place": "house", "danger": 0.8, "search": 130, "deplete": 0.15},
	"cul_de_sac": {"profile": "residential", "place": "house", "danger": 0.85, "search": 150,
		"mods": {"nails": 1.3, "canned_food": 0.8},
		"extra": [["bandage", 1, 2, 0.5], ["medkit", 1, 1, 0.25], ["hammer", 1, 1, 0.2], ["crowbar", 1, 1, 0.2], ["flashlight", 1, 1, 0.15]],
		"events": {"locked_car": 3, "boarded_house": 2, "collapsed_floor": 2, "dogs": 1, "lone_psycho": 1, "tracks": 1, "fog_bank": 1},
		"two_events": 0.45},
	"trailer_park": {"profile": "residential", "place": "trailer", "danger": 0.95, "search": 140,
		"mods": {"canned_food": 0.7, "wood": 0.6, "backpack": 0.7},
		"extra": [["shells", 1, 3, 0.25], ["scrap", 1, 3, 0.4]],
		"events": {"dogs": 3, "lone_psycho": 2, "locked_car": 2, "collapsed_floor": 1, "tracks": 1, "fog_bank": 1},
		"two_events": 0.5},
	"farmhouse": {"profile": "residential", "place": "farmhouse", "danger": 0.85, "search": 160,
		"mods": {"water": 0.8, "nails": 0.6},
		"extra": [["canned_food", 1, 3, 0.7], ["wood", 3, 6, 0.7], ["shells", 1, 2, 0.15], ["shotgun", 1, 1, 0.07],
			["fuel", 1, 2, 0.45], ["car_battery", 1, 1, 0.2]],
		"events": {"collapsed_floor": 3, "dogs": 2, "tracks": 2, "boarded_house": 1, "fog_bank": 2},
		"two_events": 0.45, "deplete": 0.25, "regen": 0.025},
	# Exp 009 (D): a block of flats: many small kitchens, little lumber
	"apartments": {"profile": "residential", "place": "apartment block", "danger": 0.95, "search": 170,
		"mods": {"wood": 0.6, "nails": 0.8, "backpack": 1.2},
		"extra": [["canned_food", 1, 2, 0.5], ["water", 1, 2, 0.5], ["bandage", 1, 1, 0.3], ["flashlight", 1, 1, 0.1]],
		"events": {"boarded_house": 2, "collapsed_floor": 2, "lone_psycho": 2, "dogs": 1, "tracks": 1, "fog_bank": 1},
		"two_events": 0.5, "deplete": 0.15, "regen": 0.03},
	# food and water
	"convenience": {"profile": "food", "place": "corner shop", "danger": 0.8, "search": 90,
		"mods": {"canned_food": 0.6, "snacks": 1.2, "water": 0.9},      # Exp 008 (E): snacks 0.9 -> 1.2, water 0.7 -> 0.9 (PACING.md: 18 containers, too many empty)
		"extra": [["bandage", 1, 2, 0.35], ["flashlight", 1, 1, 0.08],
			["nails", 2, 6, 0.4], ["scrap", 1, 2, 0.35], ["ammo", 1, 3, 0.2]],      # Exp 008 (E): the back room and the counter
		"events": {"storage_door": 2, "lone_psycho": 2, "locked_car": 1, "tracks": 1, "fog_bank": 1},
		"two_events": 0.35, "deplete": 0.35},
	"grocery": {"profile": "food", "place": "supermarket", "danger": 1.0, "search": 170},
	"diner": {"profile": "food", "place": "diner", "danger": 0.85, "search": 120,
		"mods": {"canned_food": 0.8, "snacks": 0.7, "water": 0.8},
		"extra": [["wood", 1, 3, 0.3], ["nails", 2, 5, 0.3]],
		"events": {"storage_door": 3, "locked_car": 2, "collapsed_floor": 1, "lone_psycho": 1, "fog_bank": 1},
		"two_events": 0.45},
	"restaurant": {"profile": "food", "place": "restaurant", "danger": 1.05, "search": 150,
		"mods": {"water": 1.3, "canned_food": 1.1, "snacks": 0.5},
		"events": {"storage_door": 3, "dogs": 2, "lone_psycho": 2, "fog_bank": 2, "tracks": 1}},
	"fast_food": {"profile": "food", "place": "restaurant", "danger": 0.95, "search": 110,
		"mods": {"water": 1.1, "canned_food": 0.5, "snacks": 1.2},
		"events": {"storage_door": 3, "lone_psycho": 2, "dogs": 1, "locked_car": 1, "fog_bank": 1},
		"two_events": 0.5},
	# medical
	"drugstore": {"profile": "medical", "place": "pharmacy", "danger": 1.05, "search": 120,
		"mods": {"medkit": 0.6, "ammo": 0.0, "water": 0.8},
		"extra": [["snacks", 1, 2, 0.4]],
		"events": {"dark_pharmacy": 3, "storage_door": 2, "lone_psycho": 2, "tracks": 1, "fog_bank": 1},
		"two_events": 0.6},
	# Exp 008 (H): a real building now (PoiLayouts): the waiting room has
	# windows, only the inner rooms are dark, so a flashlight is no longer
	# required to go, it lowers the risk; the staff room holds food and water.
	"clinic": {"profile": "medical", "place": "clinic", "danger": 1.3, "search": 250,
		"prep": {"flashlight": 0.85},
		"mods": {"ammo": 0.5},
		"extra": [["canned_food", 1, 2, 0.45], ["snacks", 1, 2, 0.5], ["water", 1, 2, 0.35]],
		"events": {"dark_pharmacy": 4, "waiting_room": 3, "dogs": 1, "tracks": 1, "fog_bank": 1},
		"two_events": 1.0},
	"vet_clinic": {"profile": "medical", "place": "vet's", "danger": 0.9, "search": 150,
		"mods": {"medkit": 0.5, "ammo": 0.4, "bandage": 0.8},
		"events": {"dark_pharmacy": 3, "dogs": 3, "tracks": 1, "fog_bank": 1},
		"two_events": 0.55},
	"hospital": {"profile": "medical", "place": "hospital", "danger": 1.6, "search": 300,
		"mods": {"medkit": 1.6, "bandage": 1.5, "ammo": 0.7},
		"extra": [["water", 1, 3, 0.4]],
		"events": {"ward": 4, "waiting_room": 3, "dark_pharmacy": 2, "patrol": 2, "fog_bank": 1},
		"two_events": 1.0, "prep": {"flashlight": 0.85, "shots": 0.85}, "prep_shots": 3,
		"max_damage": 50.0, "risk_floor": 0.9},
	# Exp 009 (D): first-aid bags and rescue tools
	"fire_station": {"profile": "medical", "place": "fire station", "danger": 1.05, "search": 170,
		"mods": {"medkit": 0.8, "ammo": 0.0},
		"extra": [["crowbar", 1, 1, 0.3], ["flashlight", 1, 1, 0.3], ["fuel", 1, 2, 0.4], ["hammer", 1, 1, 0.15],
			["water", 1, 3, 0.4], ["vest", 1, 1, 0.05]],
		"locked": [["medkit", 1, 1, 0.7], ["bandage", 1, 3, 0.6], ["fuel", 1, 1, 0.4], ["crowbar", 1, 1, 0.2]],
		"locked_name": "the equipment lockers", "locked_text": "The crowbar opened the crew's equipment lockers.",
		"events": {"storage_door": 2, "locked_car": 2, "lone_psycho": 2, "dogs": 1, "tracks": 1, "fog_bank": 1},
		"two_events": 0.55},
	# construction
	"hardware": {"profile": "construction_wood", "place": "hardware store", "danger": 1.0, "search": 210,
		"mods": {"nails": 1.3, "scrap": 1.3, "hammer": 1.5, "crowbar": 1.4},
		"extra": [["fuel", 1, 1, 0.3], ["car_battery", 1, 1, 0.2],
			["book_woodworking", 1, 1, 0.12], ["book_reinforced", 1, 1, 0.05],      # Exp 006 (R): a DIY shelf
			["electronics", 1, 3, 0.45], ["book_electronics", 1, 1, 0.1], ["drill", 1, 1, 0.25]],      # Exp 007 (S): the electrical aisle; (O): a hand drill
		# Exp 008 (H): the jammed stockroom: the better building stock, a little iron, a manual
		"locked": [["nails", 8, 16, 0.8], ["wood", 4, 8, 0.6], ["scrap", 2, 5, 0.6], ["iron", 1, 2, 0.3],
			["electronics", 1, 3, 0.4], ["drill", 1, 1, 0.2], ["book_reinforced", 1, 1, 0.12]],
		"locked_name": "the jammed stockroom", "locked_text": "The crowbar sprang the stockroom's jammed door.",
		"events": {"timber_rack": 3, "storage_door": 2, "collapsed_floor": 1, "lone_psycho": 1, "locked_car": 1, "tracks": 1, "fog_bank": 1}},
	# Experiment 004 (E): the pine woods near home, a low-risk wood source
	"forest": {"profile": "construction_wood", "place": "woods", "danger": 0.7, "search": 150,
		"mods": {"wood": 1.4, "nails": 0.0, "scrap": 0.5, "hammer": 0.0, "flashlight": 0.0, "crowbar": 0.0},
		"extra": [["wood", 3, 6, 0.6]],
		"locked": [["wood", 5, 9, 0.9], ["nails", 2, 6, 0.6], ["scrap", 1, 2, 0.4]],
		"locked_name": "the woodcutter's shed", "locked_text": "The crowbar opened a woodcutter's shed under the snow.",
		"events": {"deadfall": 3, "hunters_cabin": 2, "dogs": 1, "tracks": 1, "fog_bank": 1},
		"two_events": 0.4, "deplete": 0.08, "regen": 0.1, "floor": 0.5},
	"logging": {"profile": "construction_wood", "place": "clearing", "danger": 0.9, "search": 180,
		"mods": {"wood": 1.5, "nails": 0.0, "scrap": 0.4, "hammer": 0.0, "flashlight": 0.0, "crowbar": 0.5},
		"locked": [["wood", 6, 10, 0.9], ["scrap", 1, 2, 0.4]],
		"locked_name": "the timber shed", "locked_text": "The crowbar opened the timber shed.",
		"events": {"heavy_load": 3, "timber_rack": 2, "dogs": 2, "fog_bank": 2, "tracks": 1},
		"deplete": 0.1, "regen": 0.08, "floor": 0.5},
	"sawmill": {"profile": "construction_wood", "place": "sawmill", "danger": 0.95, "search": 180,
		"mods": {"wood": 1.2, "nails": 0.8},
		"events": {"timber_rack": 3, "heavy_load": 2, "storage_door": 1, "lone_psycho": 1, "fog_bank": 1}},
	"quarry": {"profile": "construction_stone", "place": "quarry", "danger": 1.0, "search": 200,
		"mods": {"stone": 1.4, "wood": 0.0},
		"deplete": 0.08, "regen": 0.1, "floor": 0.6},
	"construction_site": {"profile": "construction_stone", "place": "site", "danger": 1.1, "search": 190,
		"mods": {"stone": 0.9},
		"extra": [["wood", 3, 6, 0.8], ["iron", 1, 3, 0.55], ["fuel", 1, 2, 0.4],
			["book_reinforced", 1, 1, 0.1], ["book_metalworking", 1, 1, 0.05],      # Exp 006 (R): the site office
			["book_electronics", 1, 1, 0.08]],      # Exp 007 (S)
		"events": {"scaffold": 4, "heavy_load": 2, "lone_psycho": 2, "dogs": 1, "fog_bank": 1},
		"two_events": 0.65, "deplete": 0.2, "regen": 0.03, "floor": 0.2},
	"scrapyard": {"profile": "construction_iron", "place": "scrapyard", "danger": 1.05, "search": 180,
		"mods": {"scrap": 1.4},
		"extra": [["car_battery", 1, 1, 0.35], ["fuel", 1, 2, 0.3], ["electronics", 1, 3, 0.45]]},      # Exp 007 (S): stripped appliances
	"warehouse": {"profile": "construction_iron", "place": "warehouse", "danger": 1.1, "search": 200,
		"mods": {"scrap": 0.7, "iron": 0.8},
		"extra": [["wood", 3, 6, 0.7], ["stone", 2, 4, 0.4], ["canned_food", 1, 2, 0.35], ["water", 1, 2, 0.35],
			["electronics", 1, 2, 0.35]],      # Exp 007 (S)
		"events": {"storage_door": 3, "heavy_load": 2, "lone_psycho": 2, "collapsed_floor": 1, "fog_bank": 1},
		"deplete": 0.22, "regen": 0.02, "floor": 0.15},
	# Exp 009 (D): a garage, a joiner's workshop, a metal factory
	"auto_garage": {"profile": "construction_iron", "place": "garage", "danger": 1.0, "search": 160,
		"mods": {"scrap": 1.2, "iron": 0.8},
		"extra": [["fuel", 1, 2, 0.5], ["car_battery", 1, 1, 0.35], ["flashlight", 1, 1, 0.1]],
		"events": {"locked_car": 3, "heavy_load": 2, "dogs": 1, "lone_psycho": 1, "fog_bank": 1},
		"deplete": 0.2, "regen": 0.03, "floor": 0.15},
	"workshop": {"profile": "construction_wood", "place": "workshop", "danger": 0.95, "search": 170,
		"mods": {"wood": 0.8, "nails": 1.2, "hammer": 1.3},
		"extra": [["iron", 1, 2, 0.3], ["electronics", 1, 2, 0.3], ["drill", 1, 1, 0.15], ["book_woodworking", 1, 1, 0.08]],
		"events": {"timber_rack": 2, "storage_door": 2, "lone_psycho": 1, "tracks": 1, "fog_bank": 1},
		"deplete": 0.2, "regen": 0.03, "floor": 0.15},
	"factory": {"profile": "construction_iron", "place": "factory", "danger": 1.2, "search": 220,
		"mods": {"iron": 1.3, "scrap": 1.2},
		"extra": [["nails", 4, 10, 0.5], ["electronics", 1, 3, 0.4], ["fuel", 1, 1, 0.25], ["book_metalworking", 1, 1, 0.06]],
		"events": {"heavy_load": 3, "storage_door": 2, "lone_psycho": 2, "collapsed_floor": 1, "fog_bank": 1},
		"two_events": 0.65, "prep": {"flashlight": 0.9}},
	# weapons and ammunition (dangerous)
	# Exp 006 (R): tuned. Known from the start (RegionState.START_KNOWN), so its
	# danger and quick depletion keep it scarce: the shotgun is uncommon (10 %
	# on the shelves; with a crowbar also 25 % in the locked back room and the
	# gun counter event: about half the first visits), shells and 9 mm are
	# likely, the vest and a flashlight sometimes, a few supplies.
	"gun_shop": {"profile": "weapons", "place": "gun shop", "danger": 1.4, "search": 140,
		"mods": {"ammo": 1.3, "shells": 1.5, "shotgun": 1.6, "vest": 1.5},
		"extra": [["shells", 1, 2, 0.35], ["snacks", 1, 2, 0.3], ["water", 1, 1, 0.25], ["backpack", 1, 1, 0.06]],
		# Exp 008 (H): the back room (the profile's table with the mods, plus a
		# handgun now and then: it only matters once yours is gone)
		"locked": [["ammo", 3, 8, 0.75], ["shells", 2, 5, 0.55], ["shotgun", 1, 1, 0.25], ["vest", 1, 1, 0.22], ["handgun", 1, 1, 0.15]],
		"locked_name": "the back room", "locked_text": "The crowbar opened the back room's steel door.",
		"events": {"gun_counter": 4, "armoury": 2, "lone_psycho": 2, "patrol": 2, "fog_bank": 1},
		"prep": {"shots": 0.85}, "prep_shots": 3,
		"deplete": 0.4, "regen": 0.01, "floor": 0.08},
	"shooting_range": {"profile": "weapons", "place": "range", "danger": 1.2, "search": 170,
		"mods": {"ammo": 1.3, "vest": 2.0, "shotgun": 0.5},
		"events": {"armoury": 3, "lone_psycho": 2, "dogs": 1, "patrol": 1, "fog_bank": 1},
		"two_events": 0.6, "risk_floor": 0.0},
	"police": {"profile": "weapons", "place": "station", "danger": 1.6, "search": 220,
		"mods": {"vest": 2.5, "shotgun": 1.5},
		"extra": [["medkit", 1, 1, 0.25], ["flashlight", 1, 1, 0.2], ["fuel", 1, 1, 0.3], ["car_battery", 1, 1, 0.15],
			["book_reinforced", 1, 1, 0.06], ["book_metalworking", 1, 1, 0.05],      # Exp 006 (R): the armourer's shelf
			["electronics", 1, 2, 0.35], ["book_electronics", 1, 1, 0.08], ["book_automation", 1, 1, 0.06]],      # Exp 007 (S): the security office
		"events": {"armoury": 4, "patrol": 3, "waiting_room": 1, "lone_psycho": 1, "fog_bank": 1},
		"two_events": 1.0, "prep": {"vest": 0.85, "shots": 0.85}, "prep_shots": 3},
	"military": {"profile": "military", "place": "outpost",
		"requires": ["flashlight"], "requires_text": "The bunkers are pitch dark.",
		"prep": {"vest": 0.75, "shots": 0.7}, "prep_shots": 4,
		"extra": [["book_advanced_metal", 1, 1, 0.06],      # Exp 006 (R): a field engineering manual
			["electronics", 2, 4, 0.5], ["book_automation", 1, 1, 0.12], ["book_electronics", 1, 1, 0.08]]},      # Exp 007 (S)
	# Exp 006 (R): books and technical manuals
	"library": {"profile": "library", "place": "library", "danger": 1.05, "search": 180,
		"prep": {"flashlight": 0.85},
		"extra": [["water", 1, 2, 0.35], ["snacks", 1, 2, 0.35], ["bandage", 1, 1, 0.25]]},      # Exp 008 (E): the desks and the returns (PACING.md)
	# Exp 009 (D): an office block: a few manuals on the shelves, wiring, the staff kitchen
	"office_block": {"profile": "library", "place": "office", "danger": 1.0, "search": 150,
		"mods": {"book_woodworking": 0.3, "book_reinforced": 0.3, "book_metalworking": 0.3, "book_advanced_metal": 0.0, "book_automation": 0.6},
		"extra": [["snacks", 1, 2, 0.5], ["water", 1, 2, 0.5], ["electronics", 1, 2, 0.4], ["bandage", 1, 1, 0.2]],
		"locked": [["electronics", 1, 3, 0.6], ["book_electronics", 1, 1, 0.2], ["book_automation", 1, 1, 0.1], ["snacks", 1, 2, 0.4]],
		"locked_name": "the server room", "locked_text": "The crowbar opened the locked server room.",
		"events": {"storage_door": 3, "lone_psycho": 2, "collapsed_floor": 1, "tracks": 1, "fog_bank": 1},
		"two_events": 0.5, "deplete": 0.2, "regen": 0.02},
}

# --- mission approaches ----------------------------------------------------------------------

## search / loot / danger / deplete: multipliers. discover: chances of finding
## a new place (one roll per entry). events: added to the place's pool;
## two_events: added to the chance of a second event. needs_shots: rounds that
## must be brought. mark: [flag, days] left on the place.
const APPROACHES := {
	"general": {"name": "General scavenging", "short": "A bit of everything",
		"desc": "Search the place for whatever is useful.",
		"search": 1.0, "loot": 1.0, "danger": 1.0, "deplete": 1.0, "discover": [0.1]},
	"targeted": {"name": "Targeted collection", "short": "Much more of one thing",
		"desc": "Go straight for one resource: much more of it, little of anything else.",
		"search": 1.0, "loot": 1.0, "danger": 1.0, "deplete": 0.9, "discover": [],
		"target_mult": 1.8, "target_chance": 0.9, "other_mult": 0.4},
	"careful": {"name": "Careful exploration", "short": "Slower, safer, finds new places",
		"desc": "Slow and quiet: safer, a little less loot, and a good chance to find new places for the map.",
		"search": 1.5, "loot": 0.9, "danger": 0.65, "deplete": 0.8, "discover": [0.55, 0.15],
		"events": {"lookout": 2}, "two_events": -0.15},
	"raid": {"name": "High-risk raid", "short": "Fast and loud: more loot, more danger",
		"desc": "In fast and loud with a loaded weapon: more loot in less time, far more danger, and they remember.",
		"search": 0.55, "loot": 1.4, "danger": 1.6, "deplete": 1.3, "discover": [],
		"events": {"alarm": 3}, "two_events": 0.25, "needs_shots": 3, "mark": ["guarded", 2]},
}
const APPROACH_ORDER := ["general", "targeted", "careful", "raid"]

## Lasting consequences on a place (RegionState notes): danger x while active.
## Setting one clears the flags it lists in "clears".
const FLAGS := {
	"guarded": {"danger": 1.3, "clears": ["cleared"], "text": "Guarded since your raid (until day %d)."},
	"cleared": {"danger": 0.8, "clears": ["guarded"], "text": "Quieter: you thinned them out (until day %d)."},
}

const STASH := [["ammo", 2, 5, 0.5], ["water", 2, 3, 0.6], ["canned_food", 1, 2, 0.5]]
const CAR_BAG := [["ammo", 2, 4, 0.35], ["water", 1, 2, 0.7], ["snacks", 1, 3, 0.7], ["bandage", 1, 1, 0.3]]
const CAR_BOOT := [["ammo", 2, 4, 0.35], ["water", 1, 2, 0.7], ["snacks", 1, 3, 0.7], ["bandage", 1, 1, 0.3], ["scrap", 1, 2, 0.6], ["nails", 4, 8, 0.5], ["fuel", 1, 1, 0.25]]
## Named bonus tables for event options ("locked" and "cache" come from the destination).
const BONUS_TABLES := {"stash": STASH, "car": CAR_BAG, "car_quiet": CAR_BOOT}

const EVENTS := {
	"storage_door": {
		"title": "Behind the door",
		"text": "You hear someone moving behind the %s's storage-room door. A shuffle, a scrape, then nothing.",
		"tags": ["fight"],
		"options": [
			{"label": "Leave with what you have", "minutes": -40, "loot": 0.7,
				"outcome": "You don't wait to find out. You slip out with half-full bags.",
				"log": "Heard something behind the storage-room door and left early."},
			{"label": "Keep searching, quietly", "minutes": 30, "loot": 1.2, "hurt": [0.35, 8, 16],
				"outcome": "You work the far aisles in silence, one eye on the door.",
				"hurt_text": "The door bangs open behind you. You get away, but not cleanly.",
				"log": "Kept searching with something behind the storage-room door."},
			{"label": "Investigate: force the door", "needs": {"crowbar": 1}, "minutes": 20, "bonus": "locked", "hurt": [0.45, 8, 18],
				"outcome": "The crowbar bites and the door gives. One of them, half-starved, and behind it shelves nobody has touched.",
				"hurt_text": "It's on you before you're ready.",
				"log": "Forced the storage-room door with the crowbar."},
		],
	},
	"dogs": {
		"title": "Dogs",
		"text": "A pack of dogs blocks the way ahead, ribs showing. The lead dog hasn't decided about you yet.",
		"tags": ["fight"],
		"options": [
			{"label": "Back away and go around", "minutes": 25, "hurt": [0.1, 4, 8],
				"outcome": "You take the long way round, through gardens and over fences.",
				"hurt_text": "One of them follows you over a fence.",
				"log": "Went around a pack of dogs."},
			{"label": "Fire a warning shot", "shots": 1,
				"outcome": "The shot cracks off the walls. The pack scatters into the fog.",
				"log": "Scattered a pack of dogs with a warning shot."},
			{"label": "Walk straight through", "hurt": [0.5, 8, 16],
				"outcome": "You keep your eyes down and your pace steady.",
				"hurt_text": "The lead dog decides. Teeth, then you're past.",
				"log": "Walked through a pack of dogs."},
		],
	},
	"lone_psycho": {
		"title": "One of them",
		"text": "One of them stands in your way, swaying, its face to the wall. It hasn't noticed you yet.",
		"tags": ["fight"],
		"options": [
			{"label": "Shoot it", "shots": 2, "loot": 1.15, "hurt": [0.08, 5, 10],
				"outcome": "Two shots. It folds. Nobody else comes, and you search at leisure.",
				"hurt_text": "It doesn't go down at once.",
				"log": "Shot one of them and searched in peace."},
			{"label": "Sneak around it", "minutes": 20, "hurt": [0.3, 8, 16],
				"outcome": "You move one step at a time, breath held.",
				"hurt_text": "A board creaks. It turns.",
				"log": "Crept past one of them."},
			{"label": "Leave now", "minutes": -30, "loot": 0.7,
				"outcome": "Not worth it. You go with what you've found so far.",
				"log": "Left early to avoid one of them."},
		],
	},
	"dark_pharmacy": {
		"title": "The pharmacy",
		"text": "The pharmacy is at the end of a corridor with no windows. Something heavy has been dragged across the floor and into the dark.",
		"tags": ["dark"],
		"options": [
			{"label": "Search it by flashlight", "needs": {"flashlight": 1}, "minutes": 20, "loot": 1.25, "hurt": [0.25, 6, 12],
				"outcome": "Shelf by shelf, in a small circle of light.",
				"hurt_text": "Something in the dark lunges for the light.",
				"log": "Searched the pharmacy by flashlight."},
			{"label": "Grab what's near the door", "minutes": -15, "loot": 0.8,
				"outcome": "You sweep the nearest shelves into your bag and back out.",
				"log": "Grabbed what was near the pharmacy door."},
			{"label": "Pry open the drug cage", "needs": {"crowbar": 1}, "minutes": 25, "bonus": "locked", "hurt": [0.3, 8, 15],
				"outcome": "The cage lock shears with a crack that echoes down the corridor.",
				"hurt_text": "The echo brings something.",
				"log": "Pried open the drug cage."},
		],
	},
	"waiting_room": {
		"title": "The waiting room",
		"text": "The waiting room isn't empty. Three of them, slumped in plastic chairs. One lifts its head.",
		"tags": ["fight", "dark"],
		"options": [
			{"label": "Fight your way through", "shots": 3, "loot": 1.1, "hurt": [0.25, 8, 16], "mark": ["cleared", 3],
				"outcome": "Three shots, three bodies. The ringing in your ears takes longer to fade.",
				"hurt_text": "The third one gets close first.",
				"log": "Shot your way through the waiting room."},
			{"label": "Run for the side corridor", "minutes": 10, "hurt": [0.45, 10, 20], "lose": ["flashlight", 0.3],
				"outcome": "You sprint past the reception desk and slam a fire door behind you.",
				"hurt_text": "Hands catch your coat, your arm, your neck.",
				"lose_text": "The flashlight is somewhere on the floor back there.",
				"log": "Ran through the waiting room."},
			{"label": "Back out and leave", "minutes": -60, "loot": 0.5, "hurt": [0.12, 5, 10],
				"outcome": "You back out the way you came, slowly, and don't stop until you're outside.",
				"hurt_text": "One of them follows you out.",
				"log": "Backed out of the building."},
		],
	},
	"tracks": {
		"title": "Footprints",
		"text": "Fresh footprints in the dust, and a list chalked on a door: WATER. ROUNDS. DON'T GO NEAR THE CLINIC. The chalk is still sharp.",
		"tags": [],
		"options": [
			{"label": "Follow the footprints", "minutes": 40, "bonus": "stash", "hurt": [0.2, 6, 12],
				"outcome": "They lead to a stash under a porch. Whoever left it isn't coming back for it.",
				"hurt_text": "Something else was following them too.",
				"log": "Followed fresh footprints to a stash."},
			{"label": "Leave them be",
				"outcome": "Whoever it was made their choice. You make yours.",
				"log": "Found fresh footprints and left them be."},
		],
	},
	"collapsed_floor": {
		"title": "The cellar",
		"text": "The floor of a back room has given way. Below is a cellar: dry, dark, and lined with shelves.",
		"tags": ["dark"],
		"options": [
			{"label": "Climb down with the flashlight", "needs": {"flashlight": 1}, "minutes": 30, "bonus": "cache", "hurt": [0.1, 4, 8],
				"outcome": "The beam finds jars, tins and tools nobody has touched.",
				"hurt_text": "A rotten step gives way under you.",
				"log": "Searched a cellar by flashlight."},
			{"label": "Climb down in the dark", "minutes": 30, "bonus": "cache", "hurt": [0.45, 6, 14],
				"outcome": "You search by touch.",
				"hurt_text": "You miss the last step in the dark.",
				"log": "Searched a cellar in the dark."},
			{"label": "Leave it",
				"outcome": "You keep to the rooms you can see.",
				"log": "Left a dark cellar alone."},
		],
	},
	"locked_car": {
		"title": "A locked car",
		"text": "A car in a driveway, doors locked. On the back seat, a sports bag, zipped and full.",
		"tags": [],
		"options": [
			{"label": "Smash the window", "minutes": 5, "bonus": "car", "hurt": [0.25, 4, 10],
				"outcome": "Glass everywhere. You grab the bag.",
				"hurt_text": "The noise carries. Something answers it.",
				"log": "Smashed a car window for a bag."},
			{"label": "Pry the boot open", "needs": {"crowbar": 1}, "minutes": 10, "bonus": "car_quiet", "hurt": [0.05, 3, 6],
				"outcome": "The boot pops quietly. The bag, and a box of odds and ends under it.",
				"log": "Pried a car boot open."},
			{"label": "Walk on",
				"outcome": "Someone packed that bag for a reason. You leave it.",
				"log": "Left a locked car alone."},
		],
	},
	"fog_bank": {
		"title": "The fog",
		"text": "The fog closes in until you can't see your own hands. Every direction sounds the same.",
		"tags": ["dark"],
		"options": [
			{"label": "Wait for it to thin", "minutes": 45,
				"outcome": "You crouch by a wall and wait. It takes most of an hour.",
				"log": "Waited out a thick fog bank."},
			{"label": "Feel your way along the kerb", "minutes": 10, "loot": 0.9, "hurt": [0.25, 4, 9],
				"outcome": "Step by step, one hand on the kerb, until shapes come back.",
				"hurt_text": "You walk into something sharp.",
				"log": "Felt your way through thick fog."},
			{"label": "Light the way", "needs": {"flashlight": 1}, "minutes": 5,
				"outcome": "The beam gives you a few metres of kerb. Enough.",
				"log": "Crossed thick fog by flashlight."},
		],
	},
	"boarded_house": {
		"title": "A boarded house",
		"text": "One house is boarded up from the inside. Whoever did it did a careful job.",
		"tags": [],
		"options": [
			{"label": "Pry the boards off", "needs": {"crowbar": 1}, "minutes": 25, "bonus": [["wood", 3, 6, 1.0], ["nails", 6, 12, 0.9], ["canned_food", 1, 3, 0.7], ["water", 1, 2, 0.6]],
				"outcome": "The boards come away whole: good planks. Inside, a pantry nobody lived to empty.",
				"log": "Pried open a boarded-up house."},
			{"label": "Climb in through an upstairs window", "minutes": 20, "bonus": [["canned_food", 1, 2, 0.7], ["water", 1, 2, 0.6], ["snacks", 1, 2, 0.5]], "hurt": [0.3, 5, 12],
				"outcome": "Up the drainpipe and in.",
				"hurt_text": "The drainpipe comes away from the wall.",
				"log": "Climbed into a boarded-up house."},
			{"label": "Leave it be",
				"outcome": "Some doors are closed for a reason.",
				"log": "Left a boarded-up house alone."},
		],
	},
	# --- Experiment 004 (E): the pine woods -------------------------------------------------
	"deadfall": {
		"title": "Deadfall",
		"text": "A storm-felled pine lies across the path, half buried in snow. Dry, seasoned wood, and a lot of it.",
		"tags": [],
		"options": [
			{"label": "Cut it up and haul it", "minutes": 45, "bonus": [["wood", 4, 8, 1.0]], "hurt": [0.15, 3, 8],
				"outcome": "It takes the better part of an hour, but the planks are good.",
				"hurt_text": "The saw jumps on a frozen knot.",
				"log": "Cut up a fallen pine for planks."},
			{"label": "Lever the trunk free with the crowbar", "needs": {"crowbar": 1}, "minutes": 25, "bonus": [["wood", 5, 9, 1.0]], "lose": ["crowbar", 0.15],
				"outcome": "The trunk rolls free of the snow and splits clean.",
				"lose_text": "The crowbar slips into the snow under the trunk. Gone.",
				"log": "Levered a fallen pine free for planks."},
			{"label": "Climb over and go on", "minutes": -10,
				"outcome": "You leave it for the next storm.",
				"log": "Climbed over a fallen pine."},
		],
	},
	"hunters_cabin": {
		"title": "A hunter's cabin",
		"text": "A cabin among the pines, its door frozen shut. No smoke from the chimney. No tracks but yours.",
		"tags": ["dark"],
		"options": [
			{"label": "Pry the door", "needs": {"crowbar": 1}, "minutes": 20, "bonus": [["canned_food", 1, 2, 0.7], ["water", 1, 2, 0.5], ["shells", 1, 2, 0.25], ["wood", 2, 4, 0.8]],
				"outcome": "The ice cracks and the door gives. Tins on a shelf, a box of shells, stacked firewood.",
				"log": "Pried open a hunter's cabin."},
			{"label": "Climb in through the window", "minutes": 25, "bonus": [["canned_food", 1, 2, 0.6], ["wood", 1, 3, 0.7]], "hurt": [0.3, 4, 10],
				"outcome": "You knock out the frosted pane and climb into the dark.",
				"hurt_text": "The glass bites through your sleeve.",
				"log": "Climbed into a hunter's cabin."},
			{"label": "Leave it be",
				"outcome": "Whoever lived here might still. You keep to the trees.",
				"log": "Left a hunter's cabin alone."},
		],
	},
	"timber_rack": {
		"title": "The timber rack",
		"text": "A rack of timber shifts above you with a long, slow groan.",
		"tags": [],
		"options": [
			{"label": "Jump clear", "hurt": [0.35, 6, 14],
				"outcome": "Planks crash down where you stood.",
				"hurt_text": "Not quite clear.",
				"log": "Dodged a collapsing timber rack."},
			{"label": "Brace it with the crowbar", "needs": {"crowbar": 1}, "bonus": [["wood", 4, 8, 1.0]], "lose": ["crowbar", 0.35],
				"outcome": "You wedge it and ease the load down plank by plank.",
				"lose_text": "The crowbar is pinned under the rack. You leave it.",
				"log": "Braced a timber rack and took the planks."},
			{"label": "Back away and search elsewhere", "minutes": 15, "loot": 0.85,
				"outcome": "You leave that aisle to whatever brings it down.",
				"log": "Backed away from a sagging timber rack."},
		],
	},
	# --- Experiment 003: new kinds of places and approach-specific events ------------------
	"heavy_load": {
		"title": "Too much to carry",
		"text": "There's more here than you can carry, and the way home is long.",
		"tags": [],
		"options": [
			{"label": "Load up anyway", "minutes": 30, "loot": 1.25, "hurt": [0.25, 4, 10],
				"outcome": "You stagger home under the weight, resting every few hundred metres.",
				"hurt_text": "Something in your back gives.",
				"log": "Carried more than was comfortable."},
			{"label": "Pack it properly", "needs": {"backpack": 1}, "minutes": 15, "loot": 1.3,
				"outcome": "Heavy things at the bottom, straps tight. It works.",
				"log": "Packed the backpack to the brim."},
			{"label": "Take what's easy", "minutes": -15, "loot": 0.85,
				"outcome": "You take what you can carry without a struggle.",
				"log": "Took only what was easy to carry."},
		],
	},
	"scaffold": {
		"title": "The scaffolding",
		"text": "Rebar and a pallet of blocks sit on the second level of the scaffolding. The whole frame sways in the wind.",
		"tags": [],
		"options": [
			{"label": "Climb up for the rebar", "minutes": 20, "bonus": [["iron", 1, 3, 0.9], ["stone", 2, 4, 0.6]], "hurt": [0.35, 6, 14],
				"outcome": "Hand over hand, up the swaying frame.",
				"hurt_text": "A board slides out from under you.",
				"log": "Climbed the scaffolding for rebar."},
			{"label": "Lever the pallet down with the crowbar", "needs": {"crowbar": 1}, "minutes": 25, "bonus": [["stone", 3, 6, 1.0], ["iron", 1, 2, 0.8]], "hurt": [0.08, 4, 8],
				"outcome": "Block by block, the pallet comes down where you want it.",
				"hurt_text": "One block doesn't.",
				"log": "Levered a pallet of blocks off the scaffolding."},
			{"label": "Stay on the ground", "loot": 0.9,
				"outcome": "You search the ground floor and leave the scaffolding alone.",
				"log": "Left the scaffolding alone."},
		],
	},
	"outpost_gate": {
		"title": "The gate",
		"text": "The outpost gate hangs open. Between the containers, several of them move together, like they remember drills.",
		"tags": ["fight"],
		"options": [
			{"label": "Fight your way in", "shots": 4, "loot": 1.2, "hurt": [0.4, 10, 25], "hurt_loot": 0.6, "mark": ["cleared", 3],
				"outcome": "You pick them off from behind a truck, one by one, then walk in.",
				"hurt_text": "There were more than you counted. You get out with what you can carry.",
				"log": "Fought your way into the outpost."},
			{"label": "Slip in along the fence", "needs": {"flashlight": 1}, "minutes": 40, "hurt": [0.35, 10, 22], "hurt_loot": 0.6,
				"outcome": "Through a gap in the fence and into the bunkers, the light cupped in your hand.",
				"hurt_text": "One of them was waiting in the dark. You run for it.",
				"log": "Slipped into the outpost along the fence."},
			{"label": "Turn back", "minutes": -60, "loot": 0.3, "hurt": [0.1, 5, 10],
				"outcome": "Not today. You take what's lying outside the fence and go.",
				"hurt_text": "One of them follows you into the trees.",
				"log": "Turned back at the outpost gate."},
		],
	},
	"armoury": {
		"title": "The armoury",
		"text": "A steel door at the back, its lock still holding. Through the slot you can see a rack that isn't quite empty.",
		"tags": ["fight"],
		"options": [
			{"label": "Pry the door open", "needs": {"crowbar": 1}, "minutes": 30, "bonus": "locked", "hurt": [0.3, 8, 18],
				"outcome": "It takes everything you have. The door gives with a bang that carries.",
				"hurt_text": "The bang brings them.",
				"log": "Pried open the armoury door."},
			{"label": "Search the lockers instead", "minutes": 15, "bonus": [["ammo", 2, 5, 0.6], ["shells", 1, 3, 0.4], ["bandage", 1, 1, 0.4]], "hurt": [0.15, 5, 12],
				"outcome": "Locker after locker: most empty, a few not.",
				"hurt_text": "One locker wasn't empty in the wrong way.",
				"log": "Searched the lockers by the armoury."},
			{"label": "Leave it", "minutes": -10,
				"outcome": "Steel needs tools. You move on.",
				"log": "Left the armoury door shut."},
		],
	},
	"ward": {
		"title": "The stairwell",
		"text": "The supply rooms are three floors up. The stairwell is pitch dark, and something is moving on the second landing.",
		"tags": ["dark", "fight"],
		"options": [
			{"label": "Climb with the flashlight", "needs": {"flashlight": 1}, "minutes": 35, "bonus": [["medkit", 1, 2, 0.8], ["bandage", 2, 4, 0.9]], "hurt": [0.25, 8, 16],
				"outcome": "Floor by floor in a circle of light. The supply room is half full.",
				"hurt_text": "The light draws it down the stairs to you.",
				"log": "Climbed to the supply rooms by flashlight."},
			{"label": "Climb in the dark", "minutes": 35, "bonus": [["medkit", 1, 2, 0.8], ["bandage", 2, 4, 0.9]], "hurt": [0.55, 10, 22], "hurt_loot": 0.7,
				"outcome": "One hand on the rail, counting the steps.",
				"hurt_text": "It finds you before you find it. You come down faster than you went up.",
				"log": "Climbed the dark stairwell."},
			{"label": "Search the ground floor", "loot": 0.85,
				"outcome": "You keep to the ground floor, where the light gets in.",
				"log": "Kept to the ground floor."},
		],
	},
	"patrol": {
		"title": "A pack of them",
		"text": "Five or six of them, moving together down the corridor, heading your way.",
		"tags": ["fight"],
		"options": [
			{"label": "Open fire", "shots": 3, "loot": 1.1, "hurt": [0.25, 10, 20], "mark": ["cleared", 3],
				"outcome": "The first shots scatter them. The rest don't come back.",
				"hurt_text": "Not all of them scatter.",
				"log": "Opened fire on a pack of them."},
			{"label": "Hide and let them pass", "minutes": 30, "hurt": [0.3, 10, 24], "hurt_loot": 0.7,
				"outcome": "You hold your breath in a cupboard while they shuffle past.",
				"hurt_text": "One of them opens the cupboard.",
				"log": "Hid from a pack of them."},
			{"label": "Run for the exit", "minutes": -45, "loot": 0.5, "hurt": [0.2, 6, 14],
				"outcome": "You run, and keep running until the fog closes behind you.",
				"hurt_text": "One of them is faster than you.",
				"log": "Ran from a pack of them."},
		],
	},
	"alarm": {
		"title": "Too loud",
		"text": "You went in fast, and it was loud. Somewhere inside, things are waking up.",
		"tags": ["fight"],
		"only": ["raid"],
		"options": [
			{"label": "Grab and go", "minutes": -20, "loot": 0.85,
				"outcome": "Bags full of whatever was closest, and out.",
				"log": "Grabbed what you could before they came."},
			{"label": "Hold your ground", "shots": 2, "loot": 1.15, "hurt": [0.2, 8, 16],
				"outcome": "They come in ones and twos. You're ready for each.",
				"hurt_text": "One gets close.",
				"log": "Held your ground against what the noise brought."},
			{"label": "Keep searching", "loot": 1.2, "hurt": [0.45, 8, 18],
				"outcome": "You ignore the noises and keep filling bags.",
				"hurt_text": "They find you mid-search.",
				"log": "Kept searching while they came."},
		],
	},
	# --- Exp 006 (R): the library and the gun shop -----------------------------------------
	"dark_stacks": {
		"title": "The stacks",
		"text": "The technical section is at the back, where the windows end. Rows of shelves run into the dark, and something has pulled books down in heaps.",
		"tags": ["dark"],
		"options": [
			{"label": "Search the shelves by flashlight", "needs": {"flashlight": 1}, "minutes": 30,
				"bonus": [["book_reinforced", 1, 1, 0.25], ["book_metalworking", 1, 1, 0.2], ["book_advanced_metal", 1, 1, 0.1]], "hurt": [0.15, 5, 10],
				"outcome": "Shelf by shelf: engineering, trades, workshop practice.",
				"hurt_text": "A shelf comes down on you in the dark.",
				"log": "Searched the technical stacks by flashlight."},
			{"label": "Feel along the shelves in the dark", "minutes": 35,
				"bonus": [["book_woodworking", 1, 1, 0.3], ["book_reinforced", 1, 1, 0.15]], "hurt": [0.4, 6, 14],
				"outcome": "You pull out whatever has a diagram on the cover and read the titles by the door.",
				"hurt_text": "Something in the dark was sitting very still.",
				"log": "Searched the stacks in the dark."},
			{"label": "Stay near the windows", "minutes": -10, "loot": 0.9,
				"outcome": "You keep to the reading room, where you can see.",
				"log": "Kept out of the dark stacks."},
		],
	},
	"reading_room": {
		"title": "The reading room",
		"text": "Someone lived in the reading room for a while: a mattress, empty tins, a stack of books by the bed with notes in the margins. The door to the staff office is locked.",
		"tags": [],
		"options": [
			{"label": "Go through their books", "minutes": 20,
				"bonus": [["book_woodworking", 1, 1, 0.4], ["book_reinforced", 1, 1, 0.2], ["snacks", 1, 2, 0.4]],
				"outcome": "Whoever it was read about building. Pages are dog-eared at the useful parts.",
				"log": "Went through someone's reading pile."},
			{"label": "Pry open the staff office", "needs": {"crowbar": 1}, "minutes": 20, "bonus": "locked", "hurt": [0.1, 4, 8],
				"outcome": "The lock gives. Inside: the archive keys, and the reserved shelf.",
				"hurt_text": "The noise brings something up from the basement.",
				"log": "Pried open the library's staff office."},
			{"label": "Leave their things alone", "minutes": -10,
				"outcome": "They might come back. You leave everything as it was.",
				"log": "Left someone's camp in the reading room alone."},
		],
	},
	"gun_counter": {
		"title": "Behind the counter",
		"text": "The display cases are smashed and empty. Behind the counter, a shotgun is still chained to the wall rack, and the drawers under the till are shut.",
		"tags": ["fight"],
		"options": [
			{"label": "Cut the chain with the crowbar", "needs": {"crowbar": 1}, "minutes": 15,
				"bonus": [["shotgun", 1, 1, 0.4], ["shells", 2, 4, 0.8]], "hurt": [0.2, 6, 12], "lose": ["crowbar", 0.1],
				"outcome": "The chain snaps on the third try. It's loud in the empty shop.",
				"hurt_text": "Something heard the chain go.",
				"lose_text": "The crowbar slips behind the rack, out of reach.",
				"log": "Cut a shotgun off the wall rack."},
			{"label": "Search the drawers under the till", "minutes": 10,
				"bonus": [["ammo", 2, 5, 0.7], ["shells", 1, 3, 0.5], ["flashlight", 1, 1, 0.15]], "hurt": [0.12, 5, 10],
				"outcome": "Receipts, a cleaning kit, and loose rounds rolling in the corners.",
				"hurt_text": "You're bent over the drawers when it comes through the door.",
				"log": "Searched the drawers behind the gun counter."},
			{"label": "Don't linger", "minutes": -15, "loot": 0.9,
				"outcome": "Someone chained that gun for a reason, and someone may come back for it.",
				"log": "Left the gun counter alone."},
		],
	},
	"lookout": {
		"title": "A view",
		"text": "A ladder leads up to a high vantage point. Up there the fog thins, and the land spreads out below you.",
		"tags": [],
		"only": ["careful"],
		"options": [
			{"label": "Climb up and map what you see", "minutes": 25, "discover": 1, "hurt": [0.1, 4, 8],
				"outcome": "Rooftops, a water tower, roads you didn't know. You sketch it all.",
				"hurt_text": "A rusted rung snaps under you.",
				"log": "Mapped the area from a high point."},
			{"label": "Keep your head down",
				"outcome": "Up there, anyone could see you too.",
				"log": "Stayed off the high ground."},
		],
	},
}

static var _cache := {}


# --- lookups ------------------------------------------------------------------------

static func has_destination(id: String) -> bool:
	return LOCATIONS.has(id) and RegionLocations.has(id)


## The place merged with its profile and its RegionLocations entry (cached):
## id, name, desc, category, district, place, danger, search, travel, minutes
## (general round trip), loot, locked, locked_name, locked_text, events,
## two_events, requires, requires_text, prep, prep_shots, deplete, regen,
## floor, max_damage, risk_floor, rewards, recommends. {} for an unknown id.
static func destination(id: String) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	if not has_destination(id):
		return {}
	var loc: Dictionary = LOCATIONS[id]
	var p: Dictionary = PROFILES[loc["profile"]]
	var d := {
		"place": "place", "danger": 1.0, "search": 150, "two_events": 0.5, "requires": [], "requires_text": "",
		"prep": {}, "prep_shots": 3, "max_damage": MAX_DAMAGE, "risk_floor": 0.0,
		"locked_name": "locked doors", "locked_text": "The crowbar opened a locked door.",
	}
	for k in p:
		d[k] = p[k]
	for k in loc:
		if not k in ["mods", "extra", "locked"]:
			d[k] = loc[k]
	var mods: Dictionary = loc.get("mods", {})
	var loot := _apply_mods(p["loot"], mods)
	for e in loc.get("extra", []):
		loot.append((e as Array).duplicate())
	d["loot"] = loot
	d["locked"] = _apply_mods(loc["locked"], {}) if loc.has("locked") else _apply_mods(p["locked"], mods)
	var r := RegionLocations.get_def(id)
	d["id"] = id
	d["name"] = str(r["name"])
	d["desc"] = str(r["desc"])
	d["category"] = str(r["category"])
	d["district"] = str(r["district"])
	d["travel"] = RegionLocations.travel_minutes(id)
	d["minutes"] = 2 * int(d["travel"]) + int(d["search"])
	d["rewards"] = _rewards_text(d)
	d["recommends"] = []
	_cache[id] = d
	d["recommends"] = _recommends(id)
	return d


static func _apply_mods(table: Array, mods: Dictionary) -> Array:
	var out := []
	for e in table:
		var f := float(mods.get(e[0], 1.0))
		if f <= 0.0:
			continue
		if is_unique(e[0]):
			out.append([e[0], 1, 1, minf(float(e[3]) * f, UNIQUE_CHANCE_MAX)])
		else:
			var lo := maxi(int(round(float(e[1]) * f)), 1)
			out.append([e[0], lo, maxi(int(round(float(e[2]) * f)), lo), float(e[3])])
	return out


static func event(id: String) -> Dictionary:
	return EVENTS.get(id, {})


static func approach_def(id: String) -> Dictionary:
	return APPROACHES.get(id, {})


## The four mission approaches for the map and the screen, in order:
## [{id, name, short, desc, search, loot, danger, discovers, needs_shots}].
static func approaches() -> Array:
	var out := []
	for id in APPROACH_ORDER:
		var a: Dictionary = APPROACHES[id]
		out.append({"id": id, "name": a["name"], "short": a["short"], "desc": a["desc"],
			"search": a["search"], "loot": a["loot"], "danger": a["danger"],
			"discovers": not (a.get("discover", []) as Array).is_empty(), "needs_shots": int(a.get("needs_shots", 0))})
	return out


## "careful", "targeted:stone" -> {"approach": .., "target": ..}. Unknown
## approaches become "general"; the target is only kept for "targeted".
static func parse_purpose(purpose: String) -> Dictionary:
	var parts := purpose.strip_edges().split(":", true, 1)
	var a := parts[0] if parts.size() > 0 else ""
	if not APPROACHES.has(a):
		a = "general"
	var t := parts[1] if parts.size() > 1 and a == "targeted" else ""
	return {"approach": a, "target": t}


## The inverse of parse_purpose: "targeted:stone", "careful".
static func purpose_of(approach: String, target := "") -> String:
	return approach + (":" + target if approach == "targeted" and target != "" else "")


## The place's event pool for an approach: its own events plus the
## approach's, without events reserved for other approaches.
static func event_pool(id: String, approach := "general") -> Dictionary:
	var pool := {}
	var d := destination(id)
	var own: Dictionary = d.get("events", {})
	for e in own:
		pool[e] = own[e]
	var extra: Dictionary = approach_def(approach).get("events", {})
	for e in extra:
		pool[e] = float(pool.get(e, 0)) + float(extra[e])
	for e in pool.keys():
		var only: Array = event(e).get("only", [])
		if not only.is_empty() and not approach in only:
			pool.erase(e)
	return pool


static func two_events_chance(id: String, approach := "general") -> float:
	return clampf(float(destination(id).get("two_events", 0.5)) + float(approach_def(approach).get("two_events", 0.0)), 0.0, 1.0)


static func has_tag(id: String, tag: String, approach := "general") -> bool:
	for e in event_pool(id, approach):
		if tag in event(e).get("tags", []):
			return true
	return false


## Every item a destination can yield from its search and its locked table.
static func possible_rewards(dest_id: String) -> Array:
	var d := destination(dest_id)
	var out := []
	for table in [d.get("loot", []), d.get("locked", [])]:
		for e in table:
			if not e[0] in out:
				out.append(e[0])
	return out


## Item ids for the map and the screen, most plentiful first (the main table,
## then what only the locked table has).
static func resources(id: String) -> Array:
	var d := destination(id)
	var scored := []
	for e in d.get("loot", []):
		scored.append([e[0], float(e[3]) * (float(e[1]) + float(e[2])) * 0.5 * (4.0 if is_unique(e[0]) else 1.0)])
	scored.sort_custom(func(a, b): return a[1] > b[1])
	var out := []
	for s in scored:
		if not s[0] in out:
			out.append(s[0])
	for e in d.get("locked", []):
		if not e[0] in out:
			out.append(e[0])
	return out


## What targeted collection can go for here: stackable items of the main
## table, most plentiful first (at most 6).
static func targets(id: String) -> Array:
	var out := []
	var loot: Array = destination(id).get("loot", [])
	for item in resources(id):
		if not is_unique(item) and _in_table(loot, item):
			out.append(item)
	return out.slice(0, 6)


static func _in_table(table: Array, item: String) -> bool:
	for e in table:
		if e[0] == item:
			return true
	return false


## True if some event at this destination can cost the given tool.
static func can_lose(dest_id: String, tool: String) -> bool:
	for e in destination(dest_id).get("events", {}):
		for o in event(e).get("options", []):
			if o.has("lose") and o["lose"][0] == tool:
				return true
	return false


## Unique items (gear, one of each): tools, utility gear, weapons, the vest.
static func is_unique(item: String) -> bool:
	return Items.is_unique(item)


# --- ownership (inventory, equipment, magazines) -------------------------------------------

## Owned: in the inventory (equipped gear stays in the inventory), or
## equipped where a state keeps it elsewhere.
static func owns(state: GameState, item: String) -> bool:
	if state == null:
		return false
	if state.inventory.count(item) > 0:
		return true
	if state.has_method("has_equipped"):
		return bool(state.call("has_equipped", item))
	var eq = state.get("equipment")
	return typeof(eq) == TYPE_DICTIONARY and item in (eq as Dictionary).values()


## Gear a trip can take: equipped (K's slots); owned where a state has no
## equipment system.
static func can_bring(state: GameState, item: String) -> bool:
	if state == null:
		return false
	if state.has_method("has_equipped"):
		return bool(state.call("has_equipped", item))
	return owns(state, item)


## Loot multiplier of a brought backpack: GameState.carry_multiplier() (K), or
## 1 + BACKPACK_BONUS.
static func carry_multiplier(state: GameState) -> float:
	if state != null and state.has_method("carry_multiplier"):
		return maxf(float(state.call("carry_multiplier")), 1.0)
	return 1.0 + BACKPACK_BONUS


## Rounds in a weapon's magazine (GameState.weapons[weapon].loaded), 0 if unknown.
static func loaded_rounds(state: GameState, weapon: String) -> int:
	if state == null:
		return 0
	var w = state.get("weapons")
	if typeof(w) != TYPE_DICTIONARY:
		return 0
	var e = (w as Dictionary).get(weapon)
	if typeof(e) == TYPE_DICTIONARY:
		return maxi(Inventory.to_count((e as Dictionary).get("loaded", 0)), 0)
	return 0


## Rounds of an ammunition type you can bring: the reserve in the inventory
## plus the magazines (GameState.rounds_carried), and only if the weapon that
## fires them is equipped.
static func rounds_owned(state: GameState, ammo_id: String) -> int:
	if state == null or not AMMO_TYPES.has(ammo_id) or not can_bring(state, AMMO_TYPES[ammo_id]):
		return 0
	if state.has_method("rounds_carried"):
		return maxi(int(state.call("rounds_carried", ammo_id)), 0)
	return state.inventory.count(ammo_id) + loaded_rounds(state, AMMO_TYPES[ammo_id])


## Fight value of brought ammunition: 9 mm rounds plus SHELL_SHOTS per shell.
static func shots_of(gear: Dictionary) -> int:
	return maxi(int(gear.get("ammo", 0)), 0) + SHELL_SHOTS * maxi(int(gear.get("shells", 0)), 0)


# --- risk -------------------------------------------------------------------------------

static func _difficulty(state: GameState, key: String, fallback: float) -> float:
	var level := Difficulty.DEFAULT if state == null else str(state.get("difficulty"))
	var v = Difficulty.get_value(level, key)
	return float(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else fallback


## Difficulty `loot` multiplier for a state (1.0 for null).
static func loot_scale(state: GameState) -> float:
	return _difficulty(state, "loot", 1.0)


## Danger x from the place's lasting flags (guarded, cleared) today.
static func flag_factor(state: GameState, id: String) -> float:
	if state == null or state.region == null:
		return 1.0
	var k := 1.0
	for f in FLAGS:
		if state.region.has_flag(id, f, state.day()):
			k *= float(FLAGS[f]["danger"])
	return k


## Danger x from the place's preparation rules for the gear brought.
static func prep_factor(id: String, gear: Dictionary) -> float:
	var d := destination(id)
	var p: Dictionary = d.get("prep", {})
	var k := 1.0
	if p.has("vest") and int(gear.get("vest", 0)) > 0:
		k *= float(p["vest"])
	if p.has("flashlight") and int(gear.get("flashlight", 0)) > 0:
		k *= float(p["flashlight"])
	if p.has("shots") and shots_of(gear) >= int(d.get("prep_shots", 3)):
		k *= float(p["shots"])
	return k


## The trip's danger: it scales every injury chance on the trip. Place x
## approach x preparation x flags (at least the place's risk floor) x
## difficulty `scavenge_danger` x exhaustion.
static func trip_danger(state: GameState, id: String, approach := "general", gear := {}) -> float:
	return _danger(state, id, approach, gear, false, state.energy if state != null else 100.0)


## The risk shown to the player: the trip's danger with the per-event gear
## effects folded in (rounds and the vest in fights, the flashlight in dark
## places), unless the place's preparation rule already counts that gear.
static func danger_for(state: GameState, id: String, gear := {}, approach := "general") -> float:
	return _danger(state, id, approach, gear, true, state.energy if state != null else 100.0)


## Experiment 002 signature (Normal difficulty, general approach, no flags).
static func danger(dest_id: String, gear: Dictionary, energy := 100.0) -> float:
	return _danger(null, dest_id, "general", gear, true, energy)


static func _danger(state: GameState, id: String, approach: String, gear: Dictionary, shown: bool, energy: float) -> float:
	var d := destination(id)
	if d.is_empty():
		return 1.0
	var k := float(d["danger"]) * float(approach_def(approach).get("danger", 1.0))
	k *= prep_factor(id, gear) * flag_factor(state, id)
	if shown:
		var p: Dictionary = d.get("prep", {})
		if has_tag(id, "fight", approach):
			var shots := shots_of(gear)
			if not p.has("shots"):
				k *= 0.78 if shots >= 3 else (0.9 if shots >= 1 else 1.0)
			if int(gear.get("vest", 0)) > 0 and not p.has("vest"):
				k *= 0.85
		if has_tag(id, "dark", approach) and int(gear.get("flashlight", 0)) > 0 and not p.has("flashlight"):
			k *= 0.9
	k = maxf(k, float(d.get("risk_floor", 0.0)))
	k *= _difficulty(state, "scavenge_danger", 1.0)
	if energy <= LOW_ENERGY:
		k *= LOW_ENERGY_DANGER
	return k


static func risk_tier(danger_value: float) -> int:
	for i in RISK_BOUNDS.size():
		if danger_value < RISK_BOUNDS[i]:
			return i
	return RISK_BOUNDS.size()


static func risk_name(danger_value: float) -> String:
	return RISK_NAMES[risk_tier(danger_value)]


# --- time -------------------------------------------------------------------------------

## Minutes on site for an approach (rounded to 5, at least 30).
static func search_minutes(id: String, approach := "general") -> int:
	var d := destination(id)
	if d.is_empty():
		return 0
	return maxi(int(round(float(d["search"]) * float(approach_def(approach).get("search", 1.0)) / 5.0)) * 5, 30)


## Nominal trip length: travel there and back (RegionLocations) plus the
## search. `car`: by car (Experiment 004), travel x CAR_TRAVEL.
static func nominal_minutes(id: String, approach := "general", car := false) -> int:
	var d := destination(id)
	if d.is_empty():
		return 0
	return 2 * travel_minutes(id, car) + search_minutes(id, approach)


## One-way travel in minutes, on foot or by car (rounded to 5, at least 5).
static func travel_minutes(id: String, car := false) -> int:
	var d := destination(id)
	if d.is_empty():
		return 0
	if not car:
		return int(d["travel"])
	return RegionRouter.minutes("home", id, true)       # Exp 012 (L): the 4x4's own route


# --- the car (Experiment 004, E) ---------------------------------------------------------

## Why the car can't come along now ("" = it can): it must be repaired and
## there must be a fuel can (the unlimited cheat needs none).
static func car_state(state: GameState) -> String:
	if state == null or not bool(state.get("car_repaired")):
		return "The car in the yard doesn't run yet."
	if not state.cheats.get("unlimited", false) and state.inventory.count("fuel") < CAR_FUEL:
		return "No fuel for the car."
	return ""


static func can_drive(state: GameState) -> bool:
	return car_state(state) == ""


## The heavy loads only the car brings home from this kind of place.
static func car_haul(dest_id: String) -> Array:
	var d := destination(dest_id)
	return CAR_HAUL.get(str(d.get("category", "")), [])


# --- departure rules ---------------------------------------------------------------------

## {"ok": bool, "reason": String} for setting out now to `dest_id` with an
## approach (pure). Checks the departure window (05:00-18:00, back by 20:00 with
## this approach's nominal time), invasions, required gear and the approach's
## needs against what you own. Discovery is the screen's and the map's concern.
static func availability(state: GameState, dest_id: String, approach := "general", car := false) -> Dictionary:
	var d := destination(dest_id)
	if d.is_empty():
		return {"ok": false, "reason": "Unknown place."}
	if not APPROACHES.has(approach):
		return {"ok": false, "reason": "Unknown approach."}
	if state.dead:
		return {"ok": false, "reason": "You're dead."}
	if state.run.get("invasion_active", false):
		return {"ok": false, "reason": "Not while they're outside."}
	var m := state.minute_of_day()
	if m < T.EXPEDITION_DEPART_FROM:
		return {"ok": false, "reason": "It's still dark out there. You can set out from %s." % clock(T.EXPEDITION_DEPART_FROM)}
	if m > T.EXPEDITION_DEPART_UNTIL:
		return {"ok": false, "reason": "Too late to set out. You'd be coming back in the dark."}
	var mins := float(nominal_minutes(dest_id, approach, car))
	var back := m + mins
	if back > T.EXPEDITION_RETURN_BY:
		return {"ok": false, "reason": "You'd be coming back in the dark (around %s). Leave by %s." % [clock(back), clock(T.EXPEDITION_RETURN_BY - mins)]}
	for id in d.get("requires", []):
		if not can_bring(state, id):
			var nm := Items.name_of(id).to_lower()
			if owns(state, id):
				return {"ok": false, "reason": "Needs a %s. Equip yours first." % nm}
			return {"ok": false, "reason": ("Needs a %s. %s" % [nm, d.get("requires_text", "")]).strip_edges()}
	var need := int(approach_def(approach).get("needs_shots", 0))
	if need > 0 and rounds_owned(state, "ammo") + SHELL_SHOTS * rounds_owned(state, "shells") < need:
		return {"ok": false, "reason": "A raid needs a loaded weapon: %s." % shots_text(need)}
	return {"ok": true, "reason": ""}


## {"ok", "reason"} for the approach with the gear actually brought.
static func approach_state(state: GameState, dest_id: String, approach: String, gear: Dictionary) -> Dictionary:
	var av := availability(state, dest_id, approach, int(gear.get(CAR, 0)) > 0)
	if not av["ok"]:
		return av
	var need := int(approach_def(approach).get("needs_shots", 0))
	if need > 0 and shots_of(gear) < need:
		return {"ok": false, "reason": "Bring a loaded weapon: %s." % shots_text(need)}
	if approach == "targeted" and targets(dest_id).is_empty():
		return {"ok": false, "reason": "Nothing here worth targeting."}
	return {"ok": true, "reason": ""}


## "3 rounds (or 2 shells)".
static func shots_text(n: int) -> String:
	var shells := int(ceil(float(n) / SHELL_SHOTS))
	return "%d round%s (or %d shell%s)" % [n, "" if n == 1 else "s", shells, "" if shells == 1 else "s"]


## Clamps a gear request to what the player has equipped; required and worn
## gear is always brought. Always has "ammo" and "shells" (rounds, 0..carried).
static func sanitize_gear(state: GameState, dest_id: String, gear: Dictionary) -> Dictionary:
	var out := {}
	for a in AMMO_TYPES:
		var v = gear.get(a, 0)
		out[a] = clampi(int(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else 0, 0, rounds_owned(state, a))
	var req: Array = destination(dest_id).get("requires", [])
	for id in BRINGABLE_GEAR:
		var want = gear.get(id, 0)
		if can_bring(state, id) and ((typeof(want) in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL] and int(want) > 0) or id in req or id in WORN_GEAR):
			out[id] = 1
	var car = gear.get(CAR, 0)
	if typeof(car) in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL] and int(car) > 0 and can_drive(state):
		out[CAR] = 1
	return out


## The gear the screen suggests: everything equipped, and up to DEFAULT_ROUNDS /
## DEFAULT_SHELLS rounds.
static func default_gear(state: GameState, dest_id: String) -> Dictionary:
	var g := {"ammo": mini(rounds_owned(state, "ammo"), DEFAULT_ROUNDS), "shells": mini(rounds_owned(state, "shells"), DEFAULT_SHELLS)}
	for id in BRINGABLE_GEAR:
		g[id] = 1
	g[CAR] = 1                       # the repaired car with fuel comes along by default
	return sanitize_gear(state, dest_id, g)


## The best gear you could bring (for "with the right gear" hints).
static func best_gear() -> Dictionary:
	return {"ammo": DEFAULT_ROUNDS, "shells": DEFAULT_SHELLS, "crowbar": 1, "flashlight": 1, "backpack": 1, "vest": 1}


## Short effect line for a piece of gear at a place. `id` may be a gear id,
## an ammunition id or a weapon id ("handgun"/"shotgun" describe their rounds).
static func gear_effect(id: String, dest_id: String) -> String:
	var d := destination(dest_id)
	var p: Dictionary = d.get("prep", {})
	var req: Array = d.get("requires", [])
	match id:
		"ammo", "handgun":
			return "In a fight you fire to get clear: injuries halved, one round each time. Some options need rounds." + (" %d or more sharply lower the risk here." % int(d.get("prep_shots", 3)) if p.has("shots") else "")
		"shells", "shotgun":
			return "Each shell counts as %d rounds in a fight." % SHELL_SHOTS + (" Enough firepower sharply lowers the risk here." if p.has("shots") else "")
		"crowbar":
			return "Opens %s (more loot) and unlocks forced-entry options.%s" % [d.get("locked_name", "locked doors"), " It can be lost here." if can_lose(dest_id, id) else ""]
		"flashlight":
			return ("Required here. " if "flashlight" in req else "") + "Halves the risk of injury in dark places." + (" Lowers the risk here." if p.has("flashlight") else "") + (" It can be lost here." if can_lose(dest_id, id) else "")
		"backpack":
			return "Worn: +%d %% on everything you carry back." % int(round((Equipment.BACKPACK_CARRY - 1.0) * 100.0))
		"vest":
			return "Worn: injuries -35 %." + (" Sharply lowers the risk here." if p.has("vest") else "")
		CAR:
			var haul := []
			for e in car_haul(dest_id):
				if not Items.name_of(e[0]).to_lower() in haul:
					haul.append(Items.name_of(e[0]).to_lower())
			return "1 fuel can. Travel %d min instead of %d each way; carries x%d (building materials x%d)%s." % [
				travel_minutes(dest_id, true), travel_minutes(dest_id), int(CAR_CARRY), int(CAR_CARRY * CAR_MATERIAL_MULT),
				("; heavy loads too: " + ", ".join(haul)) if not haul.is_empty() else ""]
	return ""


## Gear that matters at a place, most important first: required gear,
## preparation gear, then the rest that the place's events or tables use.
static func relevant_equipment(id: String) -> Array:
	var d := destination(id)
	if d.is_empty():
		return []
	var p: Dictionary = d.get("prep", {})
	var out := []
	for r in d.get("requires", []):
		out.append(r)
	if p.has("shots"):
		out.append_array(["handgun", "shotgun"])
	if p.has("vest"):
		out.append("vest")
	if p.has("flashlight"):
		out.append("flashlight")
	if has_tag(id, "fight", "general"):
		out.append_array(["handgun", "vest"])
	if has_tag(id, "dark", "general"):
		out.append("flashlight")
	if not (d.get("locked", []) as Array).is_empty():
		out.append("crowbar")
	out.append("backpack")
	var uniq := []
	for x in out:
		if not x in uniq:
			uniq.append(x)
	return uniq


static func _recommends(id: String) -> Array:
	var out := []
	for g in relevant_equipment(id):
		if g in destination(id).get("requires", []) or g == "shotgun":
			continue
		out.append("ammo" if g == "handgun" else g)
	return out.slice(0, 3)


# --- region (discovery, stock, consequences) ----------------------------------------------

static func regen_per_day(id: String) -> float:
	return float(destination(id).get("regen", 0.0))


## Stock today (0..1), with the slow recovery since the last visit.
static func stock_now(state: GameState, id: String) -> float:
	if state == null or state.region == null:
		return 1.0
	return state.region.stock_on(id, state.day())


static func stock_text(stock: float, visits := 0) -> String:
	if stock >= 0.85:
		return "Untouched" if visits == 0 else "Plenty left"
	if stock >= 0.5:
		return "Picked over"
	if stock >= 0.25:
		return "Mostly stripped"
	return "Picked clean"


## Lines about a place's state for the map and the screen.
static func notes_text(state: GameState, id: String) -> Array:
	var out := []
	if state == null or state.region == null:
		return out
	var v: int = state.region.visits(id)
	if v > 0:
		out.append("Visited %d time%s, last on day %d." % [v, "" if v == 1 else "s", state.region.last_day(id)])
	var s := stock_now(state, id)
	if s < 0.85 or v > 0:
		out.append("%s (%d %% left)." % [stock_text(s, v), int(round(s * 100.0))])
	for f in FLAGS:
		if state.region.has_flag(id, f, state.day()):
			out.append(str(FLAGS[f]["text"]) % state.region.flag_until(id, f))
	return out


## Records an expedition's region consequences (discoveries, stock, visits,
## flags, the used plan) exactly once per result id. Returns true when applied.
## The game calls it right after GameState.apply_expedition(result).
static func apply_region(state: GameState, result: Dictionary) -> bool:
	if state == null or state.region == null:
		return false
	return state.region.apply_result(result)


## Everything the map shows for a place (SPEC-003 §6); see
## docs/experiment-003/scavenging.md. `state` may be null (a fresh run).
static func location_summary(id: String, state: GameState) -> Dictionary:
	var d := destination(id)
	if d.is_empty():
		return {}
	var s := state if state != null else GameState.new()
	var gear := default_gear(s, id)
	var shown := danger_for(s, id, gear, "general")
	var bare := danger_for(s, id, sanitize_gear(s, id, {}), "general")
	var aps := []
	for a in APPROACH_ORDER:
		var st := approach_state(s, id, a, gear)
		var dv := danger_for(s, id, gear, a)
		aps.append({"id": a, "name": APPROACHES[a]["name"], "short": APPROACHES[a]["short"], "desc": APPROACHES[a]["desc"],
			"available": st["ok"], "reason": st["reason"],
			"minutes": nominal_minutes(id, a), "search_minutes": search_minutes(id, a),
			"risk_name": risk_name(dv), "risk_value": dv})
	var eq := []
	for g in relevant_equipment(id):
		eq.append({"id": g, "name": Items.name_of(g), "effect": gear_effect(g, id), "have": owns(s, g),
			"equipped": can_bring(s, g), "required": g in d.get("requires", [])})
	var av_now := availability(s, id, "general")
	var stock := stock_now(s, id)
	return {
		"id": id, "name": d["name"], "category": d["category"],
		"category_name": str(RegionLocations.CATEGORIES.get(d["category"], d["category"])),
		"district": d["district"], "desc": d["desc"],
		"risk_name": risk_name(shown), "risk_value": shown,
		"risk_bare_name": risk_name(bare), "risk_bare_value": bare,
		"travel_minutes": int(d["travel"]), "search_minutes": search_minutes(id, "general"),
		"minutes": nominal_minutes(id, "general"),
		"resources": resources(id), "rewards": d["rewards"], "targets": targets(id),
		"equipment": eq, "requires": (d.get("requires", []) as Array).duplicate(),
		"approaches": aps,
		"stock": stock, "stock_text": stock_text(stock, s.region.visits(id)),
		"discovered": s.region.is_discovered(id),
		"notes": notes_text(s, id),
		"available": av_now["ok"], "reason": av_now["reason"],
	}


# --- formatting ---------------------------------------------------------------------------

static func clock(minute_of_day: float) -> String:
	var m := int(round(fposmod(minute_of_day, 1440.0)))
	return "%02d:%02d" % [(m / 60) % 24, m % 60]


static func duration(minutes: float) -> String:
	var m := int(round(minutes))
	if m < 60:
		return "%d min" % m
	if m % 60 == 0:
		return "%d h" % (m / 60)
	return "%d h %02d min" % [m / 60, m % 60]


## Countable names for the report: [singular, plural].
const COUNT_NAMES := {
	"canned_food": ["can of food", "cans of food"], "snacks": ["pack of snacks", "packs of snacks"],
	"water": ["bottle of water", "bottles of water"], "ammo": ["round", "rounds"],
	"shells": ["shell", "shells"],
	"wood": ["plank", "planks"], "nails": ["nail", "nails"], "scrap": ["piece of scrap metal", "pieces of scrap metal"],
	"stone": ["block of stone", "blocks of stone"], "iron": ["iron bar", "iron bars"],
	"bandage": ["bandage", "bandages"], "medkit": ["first-aid kit", "first-aid kits"],
	# Exp 006 (R): books
	"book_woodworking": ["copy of 'Basic Woodworking'", "copies of 'Basic Woodworking'"],
	"book_reinforced": ["copy of 'Reinforced Construction'", "copies of 'Reinforced Construction'"],
	"book_metalworking": ["copy of the 'Metalworking Manual'", "copies of the 'Metalworking Manual'"],
	"book_advanced_metal": ["copy of 'Advanced Metal Fabrication'", "copies of 'Advanced Metal Fabrication'"],
	# Exp 007 (S)
	"electronics": ["electronic component", "electronic components"],
	"book_electronics": ["copy of 'Basic Electronics'", "copies of 'Basic Electronics'"],
	"book_automation": ["copy of 'Automated Defense Systems'", "copies of 'Automated Defense Systems'"],
}


## "3 cans of food", "1 round", "1 crowbar".
static func count_text(id: String, n: int) -> String:
	var names: Array = COUNT_NAMES.get(id, [Items.name_of(id).to_lower(), Items.name_of(id).to_lower()])
	return "%d %s" % [n, names[0] if n == 1 else names[1]]


## "3 cans of food, 1 bottle of water" (in Items.DEFS order).
static func items_text(counts: Dictionary) -> String:
	var parts := []
	for id in Items.DEFS:
		var n := int(counts.get(id, 0))
		if n > 0:
			parts.append(count_text(id, n))
	return ", ".join(parts)


## Short item name for lists: "stone", "9 mm rounds", "a shotgun".
static func reward_name(id: String) -> String:
	if Items.category(id) == "book":       # Exp 006 (R): "a book on metalworking"
		return "a book on " + Research.name_of(Items.DEFS[id].get("skill", "")).to_lower()
	if is_unique(id):
		var n := Items.name_of(id).to_lower()
		return ("an " if n.substr(0, 1) in ["a", "e", "i", "o", "u"] else "a ") + n
	if id == "water":
		return "bottled water"
	if id == "stone" or id == "iron":
		return id
	return str(COUNT_NAMES.get(id, [Items.name_of(id).to_lower(), Items.name_of(id).to_lower()])[1])


## "Cans of food, packs of snacks and bottled water; sometimes bandages; rarely a backpack."
static func _rewards_text(d: Dictionary) -> String:
	var tiers := [[], [], []]
	for e in d.get("loot", []):
		var c := float(e[3])
		var i := 0 if c >= 0.6 else (1 if c >= 0.25 else 2)
		var nm := reward_name(e[0])
		if not nm in tiers[i]:
			tiers[i].append(nm)
	var parts := []
	if not tiers[0].is_empty():
		parts.append(_and_list(tiers[0]))
	if not tiers[1].is_empty():
		parts.append("sometimes " + _and_list(tiers[1]))
	if not tiers[2].is_empty():
		parts.append("rarely " + _and_list(tiers[2]))
	var s := "; ".join(parts) + "."
	return s.substr(0, 1).to_upper() + s.substr(1)


static func _and_list(names: Array) -> String:
	if names.size() == 1:
		return names[0]
	return ", ".join(names.slice(0, names.size() - 1)) + " and " + names[-1]
