class_name ExpeditionData
extends RefCounted
## Static data for simulated expeditions (SPEC §7.7): destinations, events and
## the small rules shared by the resolver (ExpeditionRun) and the screen.
## Owner: E. Pure data and pure helpers; nothing here touches the scene or
## mutates a GameState.
##
## Loot entries are [item_id, min, max, chance]. Tools (category "tool") are
## found at most once and never when already owned.
##
## Event option fields (all optional):
##   label    button text
##   needs    {"crowbar": 1 | "flashlight": 1 | "ammo": n}: brought gear required
##   ammo     rounds spent (the option needs at least as many)
##   minutes  time added (negative: the trip is cut short)
##   loot     multiplier on the main search
##   bonus    "locked" (the destination's locked table), "cache" (half the
##            main table) or an Array of loot entries
##   hurt     [chance, min, max]: injury roll (scaled by the destination's danger)
##   lose     [tool_id, chance]: a brought tool can be lost
##   outcome  text after choosing; hurt_text / lose_text are appended when they happen
##   log      one line for the report

const T := preload("res://src/survival/survival_tuning.gd")

## Gear that can be taken along (the hammer stays home: building needs it).
const BRINGABLE_TOOLS := ["crowbar", "flashlight", "backpack"]
const BACKPACK_BONUS := 0.5          ## +50 % on stackable loot
const MAX_DAMAGE := 40.0             ## health one expedition can cost at most
const MIN_MINUTES := 60
const TRAVEL_JITTER := Vector2i(-15, 15)
const LOOT_MULT_RANGE := Vector2(0.3, 1.6)
const LOW_ENERGY := 15.0             ## exhausted: risk up
const LOW_ENERGY_DANGER := 1.25
const DARK_FLASHLIGHT_SCALE := 0.5   ## injury chance in dark places with a flashlight
const FIGHT_AMMO_SCALE := 0.5        ## damage when you fire to get clear (1 round)

const RISK_NAMES := ["Low", "Moderate", "High", "Severe"]
const RISK_BOUNDS := [0.9, 1.15, 1.45]

const DESTINATIONS := {
	"homes": {
		"name": "Nearby Homes",
		"place": "house",
		"desc": "The houses along the road, left in a hurry. Pantries, garages, bathroom cabinets. Close by, and mostly quiet.",
		"minutes": 150,
		"danger": 0.8,
		"requires": [],
		"recommends": ["backpack"],
		"rewards": "Food, water, planks and nails, sometimes a bandage. Rarely ammo, a crowbar, a flashlight or a backpack.",
		"loot": [
			["canned_food", 1, 2, 0.85], ["snacks", 1, 3, 0.7], ["water", 1, 3, 0.85],
			["wood", 2, 5, 0.55], ["nails", 4, 10, 0.5], ["bandage", 1, 1, 0.35],
			["ammo", 2, 4, 0.15], ["crowbar", 1, 1, 0.12], ["flashlight", 1, 1, 0.2], ["backpack", 1, 1, 0.15],
		],
		"locked": [["wood", 3, 5, 0.8], ["nails", 6, 12, 0.7], ["scrap", 1, 3, 0.5], ["canned_food", 1, 2, 0.5]],
		"locked_name": "locked garages",
		"locked_text": "The crowbar opened a locked garage.",
		"events": {"boarded_house": 3, "collapsed_floor": 2, "locked_car": 2, "dogs": 2, "lone_psycho": 1, "tracks": 1, "fog_bank": 1},
		"two_events": 0.4,
	},
	"grocery": {
		"name": "Grocery Store",
		"place": "supermarket",
		"desc": "The supermarket at the crossroads. The shelves by the doors are bare; the back aisles and the storage room might not be.",
		"minutes": 210,
		"danger": 1.0,
		"requires": [],
		"recommends": ["backpack", "crowbar"],
		"rewards": "Canned food, snacks and bottled water in quantity; sometimes bandages, rarely a backpack.",
		"loot": [
			["canned_food", 2, 4, 0.95], ["snacks", 2, 4, 0.85], ["water", 2, 4, 1.0], ["bandage", 1, 1, 0.2], ["backpack", 1, 1, 0.08],
		],
		"locked": [["water", 2, 3, 0.85], ["canned_food", 1, 3, 0.75], ["snacks", 1, 2, 0.5]],
		"locked_name": "the stockroom",
		"locked_text": "The crowbar opened the stockroom.",
		"events": {"storage_door": 3, "lone_psycho": 2, "dogs": 1, "locked_car": 1, "tracks": 1, "fog_bank": 1},
		"two_events": 0.65,
	},
	"hardware": {
		"name": "Hardware Store",
		"place": "hardware store",
		"desc": "A builders' merchant on the edge of town. Timber, fixings, sheet metal, and tools nobody thought to take.",
		"minutes": 240,
		"danger": 1.0,
		"requires": [],
		"recommends": ["crowbar", "backpack"],
		"rewards": "Planks, nails and scrap metal; a crowbar or a hammer if you lack one, sometimes a flashlight.",
		"loot": [
			["wood", 6, 12, 1.0], ["nails", 8, 16, 0.95], ["scrap", 2, 5, 0.75],
			["crowbar", 1, 1, 0.5], ["hammer", 1, 1, 0.6], ["flashlight", 1, 1, 0.25],
		],
		"locked": [["scrap", 3, 6, 0.9], ["nails", 8, 14, 0.8], ["wood", 5, 9, 0.75]],
		"locked_name": "the stockroom",
		"locked_text": "The crowbar opened the stockroom.",
		"events": {"timber_rack": 3, "storage_door": 2, "collapsed_floor": 1, "lone_psycho": 1, "locked_car": 1, "tracks": 1, "fog_bank": 1},
		"two_events": 0.55,
	},
	"clinic": {
		"name": "Medical Clinic",
		"place": "clinic",
		"desc": "The health centre past the school. Windowless corridors, a pharmacy, and whatever happened in the waiting room.",
		"minutes": 300,
		"danger": 1.3,
		"requires": ["flashlight"],
		"recommends": ["ammo", "crowbar"],
		"rewards": "Bandages and first-aid kits; sometimes ammo from a guard's locker.",
		"loot": [
			["bandage", 2, 4, 1.0], ["medkit", 1, 2, 0.6], ["ammo", 3, 6, 0.3], ["water", 1, 2, 0.4],
		],
		"locked": [["medkit", 1, 1, 0.9], ["bandage", 1, 3, 0.7], ["ammo", 2, 5, 0.4]],
		"locked_name": "the drug cage",
		"locked_text": "The crowbar opened the drug cage.",
		"events": {"dark_pharmacy": 4, "waiting_room": 3, "dogs": 1, "tracks": 1, "fog_bank": 1},
		"two_events": 1.0,
	},
}

## Display order.
const ORDER := ["homes", "grocery", "hardware", "clinic"]

const STASH := [["ammo", 2, 5, 0.5], ["water", 2, 3, 0.6], ["canned_food", 1, 2, 0.5]]
const CAR_BAG := [["ammo", 2, 4, 0.35], ["water", 1, 2, 0.7], ["snacks", 1, 3, 0.7], ["bandage", 1, 1, 0.3]]
const CAR_BOOT := [["ammo", 2, 4, 0.35], ["water", 1, 2, 0.7], ["snacks", 1, 3, 0.7], ["bandage", 1, 1, 0.3], ["scrap", 1, 2, 0.6], ["nails", 4, 8, 0.5]]
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
		"text": "A pack of dogs blocks the street ahead, ribs showing. The lead dog hasn't decided about you yet.",
		"tags": ["fight"],
		"options": [
			{"label": "Back away and go around", "minutes": 25, "hurt": [0.1, 4, 8],
				"outcome": "You take the long way round, through gardens and over fences.",
				"hurt_text": "One of them follows you over a fence.",
				"log": "Went around a pack of dogs."},
			{"label": "Fire a warning shot", "needs": {"ammo": 1}, "ammo": 1,
				"outcome": "The shot cracks off the house fronts. The pack scatters into the fog.",
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
			{"label": "Shoot it", "needs": {"ammo": 2}, "ammo": 2, "loot": 1.15, "hurt": [0.08, 5, 10],
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
			{"label": "Fight your way through", "needs": {"ammo": 3}, "ammo": 3, "loot": 1.1, "hurt": [0.25, 8, 16],
				"outcome": "Three rounds, three bodies. The ringing in your ears takes longer to fade.",
				"hurt_text": "The third one gets close first.",
				"log": "Shot your way through the waiting room."},
			{"label": "Run for the side corridor", "minutes": 10, "hurt": [0.45, 10, 20], "lose": ["flashlight", 0.3],
				"outcome": "You sprint past the reception desk and slam a fire door behind you.",
				"hurt_text": "Hands catch your coat, your arm, your neck.",
				"lose_text": "The flashlight is somewhere on the floor back there.",
				"log": "Ran through the waiting room."},
			{"label": "Back out and leave", "minutes": -60, "loot": 0.5, "hurt": [0.12, 5, 10],
				"outcome": "You back out the way you came, slowly, and don't stop until the school.",
				"hurt_text": "One of them follows you out.",
				"log": "Backed out of the clinic."},
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
}


# --- lookups ------------------------------------------------------------------------

static func destination(id: String) -> Dictionary:
	return DESTINATIONS.get(id, {})


static func event(id: String) -> Dictionary:
	return EVENTS.get(id, {})


## Every item a destination can yield (main, locked and event bonus tables).
static func possible_rewards(dest_id: String) -> Array:
	var d := destination(dest_id)
	var out := []
	for table in [d.get("loot", []), d.get("locked", [])]:
		for e in table:
			if not e[0] in out:
				out.append(e[0])
	return out


## True if some event at this destination can cost the given tool.
static func can_lose(dest_id: String, tool: String) -> bool:
	for e in destination(dest_id).get("events", {}):
		for o in event(e).get("options", []):
			if o.has("lose") and o["lose"][0] == tool:
				return true
	return false


# --- risk -------------------------------------------------------------------------------

## Effective danger for a destination and the gear brought (the screen shows its tier).
static func danger(dest_id: String, gear: Dictionary, energy := 100.0) -> float:
	var d := destination(dest_id)
	var k: float = d.get("danger", 1.0)
	var fights := false
	var dark := false
	for e in d.get("events", {}):
		var tags: Array = event(e).get("tags", [])
		fights = fights or "fight" in tags
		dark = dark or "dark" in tags
	var ammo := int(gear.get("ammo", 0))
	if fights:
		k *= 0.78 if ammo >= 3 else (0.9 if ammo >= 1 else 1.0)
	if dark and int(gear.get("flashlight", 0)) > 0:
		k *= 0.9
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


# --- departure rules ---------------------------------------------------------------------

## {"ok": bool, "reason": String} for setting out now to `dest_id` (pure).
static func availability(state: GameState, dest_id: String) -> Dictionary:
	var d := destination(dest_id)
	if d.is_empty():
		return {"ok": false, "reason": "Unknown place."}
	if state.dead:
		return {"ok": false, "reason": "You're dead."}
	if state.run.get("invasion_active", false):
		return {"ok": false, "reason": "Not while they're outside."}
	var m := state.minute_of_day()
	if m < T.EXPEDITION_DEPART_FROM:
		return {"ok": false, "reason": "It's still dark out there. You can set out from %s." % clock(T.EXPEDITION_DEPART_FROM)}
	if m > T.EXPEDITION_DEPART_UNTIL:
		return {"ok": false, "reason": "Too late to set out. You'd be coming back in the dark."}
	var back := m + float(d["minutes"])
	if back > T.EXPEDITION_RETURN_BY:
		return {"ok": false, "reason": "You'd be coming back in the dark (around %s). Leave by %s." % [clock(back), clock(T.EXPEDITION_RETURN_BY - float(d["minutes"]))]}
	for id in d.get("requires", []):
		if state.inventory.count(id) <= 0:
			return {"ok": false, "reason": "Needs a %s. %s" % [Items.name_of(id).to_lower(), "The clinic has no windows." if dest_id == "clinic" else ""]}
	return {"ok": true, "reason": ""}


## Clamps a gear request to what the player owns; required tools are always brought.
static func sanitize_gear(state: GameState, dest_id: String, gear: Dictionary) -> Dictionary:
	var out := {"ammo": clampi(int(gear.get("ammo", 0)), 0, state.inventory.count("ammo"))}
	var req: Array = destination(dest_id).get("requires", [])
	for id in BRINGABLE_TOOLS:
		if state.inventory.count(id) > 0 and (int(gear.get(id, 0)) > 0 or id in req):
			out[id] = 1
	return out


## The gear the screen suggests: every owned tool and up to six rounds.
static func default_gear(state: GameState, dest_id: String) -> Dictionary:
	var g := {"ammo": mini(state.inventory.count("ammo"), 6)}
	for id in BRINGABLE_TOOLS:
		g[id] = 1
	return sanitize_gear(state, dest_id, g)


## Short effect line for a piece of gear (gear screen).
static func gear_effect(id: String, dest_id: String) -> String:
	var d := destination(dest_id)
	match id:
		"ammo":
			return "In a fight you fire to get clear: injuries halved, 1 round each time. Some options need rounds."
		"crowbar":
			return "Opens %s (more loot) and unlocks forced-entry options.%s" % [d.get("locked_name", "locked doors"), " It can be lost here." if can_lose(dest_id, id) else ""]
		"flashlight":
			return ("Required here. " if "flashlight" in d.get("requires", []) else "") + "Halves the risk of injury in dark places." + (" It can be lost here." if can_lose(dest_id, id) else "")
		"backpack":
			return "+50 % on everything you carry back."
	return ""


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
	"wood": ["plank", "planks"], "nails": ["nail", "nails"], "scrap": ["piece of scrap metal", "pieces of scrap metal"],
	"bandage": ["bandage", "bandages"], "medkit": ["first-aid kit", "first-aid kits"],
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
