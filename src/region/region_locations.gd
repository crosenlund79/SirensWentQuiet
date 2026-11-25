class_name RegionLocations
extends RefCounted
## The ONE list of places outside the lot (Experiment 003 SPEC §3). Owner: lead.
## The voxel city map (src/map) draws them, and the expedition system
## (src/expedition) sends the player there. Gameplay data (loot profiles,
## risk, events, search time) lives in src/expedition keyed by these ids;
## geography (terrain, roads, districts) lives in src/map, built around these
## positions. Changes to this list: ask the lead.
##
## Map coordinates are region cells: 1 cell = 25 m, the region is
## SIZE = 160 x 120 cells (4 km x 3 km), x east, y south. The player's house is
## HOME. North-west: mountains (quarry in the foothills). North: forest
## (logging, sawmill on the river). The river runs from the mountains south-
## east through the city into the bay on the east coast (harbour). City centre
## (commercial) just west of the river mouth; industry along the lower river
## and the docks; suburbs south-west of the centre; the house on the south-
## western edge of town; remote facilities in the southern hills.

const CELL_M := 25.0
const SIZE := Vector2i(160, 120)
const HOME := Vector2(58, 92)
## Walking-and-searching pace used for travel estimates (minutes per km of
## road, roads wind: x 1.3 of the straight distance).
const MINUTES_PER_KM := 15.0
const ROAD_FACTOR := 1.3

const CATEGORIES := {
	"construction": "Construction",
	"weapons": "Weapons and ammunition",
	"medical": "Medical",
	"food": "Food and water",
	"residential": "Family houses",
	"knowledge": "Books and knowledge",     # Exp 006 (R): the library
}

const DISTRICTS := {
	"suburbs": "Suburbs", "centre": "City centre", "industrial": "Industrial river", "docks": "Docks",
	"forest": "North woods", "mountains": "Mountains", "hills": "Southern hills", "farmland": "Farmland",
}

## id -> {name, category, district, pos (region cells), size (cells, footprint
## for the map), desc}. The four Experiment 002 destinations keep their ids.
const LOCATIONS := {
	# --- family houses -------------------------------------------------------------
	"homes": {"name": "Nearby Homes", "category": "residential", "district": "suburbs", "pos": Vector2(64, 90), "size": Vector2(6, 4),
		"desc": "The houses along your own road, left in a hurry."},
	"cul_de_sac": {"name": "Birch Court", "category": "residential", "district": "suburbs", "pos": Vector2(76, 82), "size": Vector2(6, 5),
		"desc": "A comfortable cul-de-sac: garages full of tools, well-stocked medicine cabinets."},
	"trailer_park": {"name": "Riverside Trailer Park", "category": "residential", "district": "industrial", "pos": Vector2(98, 92), "size": Vector2(7, 4),
		"desc": "Cramped trailers by the river. Odds and ends, sometimes a box of shells."},
	"farmhouse": {"name": "Halvorsen Farm", "category": "residential", "district": "farmland", "pos": Vector2(36, 108), "size": Vector2(5, 4),
		"desc": "An isolated farmhouse: preserves, firewood, and maybe an old shotgun."},
	# --- food and water ------------------------------------------------------------
	"convenience": {"name": "Corner Store", "category": "food", "district": "suburbs", "pos": Vector2(70, 94), "size": Vector2(2, 2),
		"desc": "A small corner shop near home. A little of everything."},
	"grocery": {"name": "Supermarket", "category": "food", "district": "centre", "pos": Vector2(92, 66), "size": Vector2(5, 4),
		"desc": "The big supermarket at the crossroads. Bare at the front, maybe not at the back."},
	"diner": {"name": "Route 9 Diner", "category": "food", "district": "suburbs", "pos": Vector2(82, 98), "size": Vector2(3, 2),
		"desc": "A roadside diner: a pantry, a walk-in cooler, household odds and ends."},
	"restaurant": {"name": "Harbour Restaurant", "category": "food", "district": "docks", "pos": Vector2(126, 62), "size": Vector2(3, 3),
		"desc": "A seafood restaurant on the quay. Stores of water and tins."},
	"fast_food": {"name": "Burger Barn", "category": "food", "district": "centre", "pos": Vector2(100, 74), "size": Vector2(2, 2),
		"desc": "A fast-food place by the ring road. Sealed drinks and frozen everything."},
	# --- medical -------------------------------------------------------------------
	"drugstore": {"name": "Main Street Pharmacy", "category": "medical", "district": "centre", "pos": Vector2(98, 60), "size": Vector2(2, 2),
		"desc": "A pharmacy: bandages and basic medicine, if nobody beat you to it."},
	"clinic": {"name": "Medical Clinic", "category": "medical", "district": "centre", "pos": Vector2(88, 56), "size": Vector2(3, 3),
		"desc": "A small clinic. Dark inside; first-aid supplies in the back rooms."},
	"vet_clinic": {"name": "Valley Vet", "category": "medical", "district": "farmland", "pos": Vector2(50, 104), "size": Vector2(2, 2),
		"desc": "A veterinary practice on the farm road. Mixed medical supplies."},
	"hospital": {"name": "St. Brigid's Hospital", "category": "medical", "district": "centre", "pos": Vector2(108, 50), "size": Vector2(7, 6),
		"desc": "The regional hospital. Large stores, many floors, and whatever stayed behind."},
	# --- construction --------------------------------------------------------------
	"hardware": {"name": "Hardware Store", "category": "construction", "district": "suburbs", "pos": Vector2(80, 76), "size": Vector2(4, 3),
		"desc": "A hardware store on the ring road. Planks, nails, tools; a locked stockroom."},
	"forest": {"name": "Pine Woods", "category": "construction", "district": "hills", "pos": Vector2(47, 70), "size": Vector2(5, 6),
		"desc": "Snowy pine woods a short walk from home. Deadfall and timber for the taking; quiet, mostly."},
	"logging": {"name": "Logging Area", "category": "construction", "district": "forest", "pos": Vector2(60, 18), "size": Vector2(6, 5),
		"desc": "A clearing in the north woods with stacked timber."},
	"sawmill": {"name": "Pine Creek Sawmill", "category": "construction", "district": "forest", "pos": Vector2(78, 32), "size": Vector2(5, 4),
		"desc": "A sawmill on the river: cut planks and tools."},
	"quarry": {"name": "Granite Quarry", "category": "construction", "district": "mountains", "pos": Vector2(34, 30), "size": Vector2(7, 6),
		"desc": "A quarry in the foothills: cut stone, a site office, heavy machinery."},
	"construction_site": {"name": "Construction Site", "category": "construction", "district": "centre", "pos": Vector2(84, 66), "size": Vector2(4, 4),
		"desc": "Half-built apartments: timber, blocks and rebar."},
	"scrapyard": {"name": "Scrapyard", "category": "construction", "district": "industrial", "pos": Vector2(112, 88), "size": Vector2(6, 5),
		"desc": "Mountains of scrap by the river: iron for the taking, if you can carry it."},
	"warehouse": {"name": "Riverside Warehouse", "category": "construction", "district": "docks", "pos": Vector2(122, 78), "size": Vector2(6, 4),
		"desc": "A distribution warehouse: mixed materials on pallets."},
	# --- weapons and ammunition ----------------------------------------------------
	"gun_shop": {"name": "Pike's Guns", "category": "weapons", "district": "centre", "pos": Vector2(102, 68), "size": Vector2(2, 2),
		"desc": "A gun shop. Looted early, but not everything was on the shelves."},
	"shooting_range": {"name": "Shooting Range", "category": "weapons", "district": "hills", "pos": Vector2(42, 80), "size": Vector2(4, 3),
		"desc": "An indoor range at the edge of the hills: ammunition, protective gear."},
	"police": {"name": "Police Station", "category": "weapons", "district": "centre", "pos": Vector2(94, 54), "size": Vector2(4, 3),
		"desc": "The precinct. An armoury, an evidence room, and cells."},
	"military": {"name": "Military Outpost", "category": "weapons", "district": "hills", "pos": Vector2(16, 98), "size": Vector2(8, 7),
		"desc": "A fenced outpost in the southern hills. Rare equipment, and something still guards it."},
	# --- books and knowledge (Exp 006, R) ------------------------------------------
	"library": {"name": "Public Library", "category": "knowledge", "district": "centre", "pos": Vector2(106, 60), "size": Vector2(4, 3),
		"desc": "The town library: handbooks and technical manuals nobody thought to loot. Dark between the stacks."},
}


static func ids() -> Array:
	return LOCATIONS.keys()


static func has(id: String) -> bool:
	return LOCATIONS.has(id)


static func get_def(id: String) -> Dictionary:
	return LOCATIONS.get(id, {})


static func name_of(id: String) -> String:
	return str(LOCATIONS.get(id, {}).get("name", id))


static func in_category(cat: String) -> Array:
	var out := []
	for id in LOCATIONS:
		if LOCATIONS[id]["category"] == cat:
			out.append(id)
	return out


## Straight distance from the house in km.
static func distance_km(id: String) -> float:
	var d: Dictionary = LOCATIONS.get(id, {})
	if d.is_empty():
		return 0.0
	return (d["pos"] as Vector2).distance_to(HOME) * CELL_M / 1000.0


## One-way travel estimate in minutes (rounded to 5), the same for the map and
## the expedition system.
static func travel_minutes(id: String) -> int:
	var m := distance_km(id) * ROAD_FACTOR * MINUTES_PER_KM
	return maxi(int(round(m / 5.0)) * 5, 10)
