class_name ComfortCatalog
extends RefCounted
## Experiment 005 (C): the one place to tune comfort. Furniture type ->
## category and value, the categories' caps and display names, the
## environmental factors (light, warmth, windows, damage) and the comfort
## levels. HomeComfort reads it; nothing here has state.
##
## Diminishing returns: within a category the pieces are sorted by value and
## the n-th counts value x DECAY^(n - 1); the category's sum is capped at its
## `cap`, and all furniture together at FURNITURE_CAP. Twenty chairs are worth
## about two; a room with a bed, a rug, a lamp and a picture beats a room of
## beds. A damaged piece counts DAMAGED_FACTOR of its value.

## Furniture type -> [category, value]. Type names are shared with agent F
## (SPEC §2) and HousePlan.FURNITURE. Unknown types count as "other".
const TYPES := {
	# sleeping
	"bed": ["bed", 8.0],
	# seating
	"sofa": ["seating", 5.0],
	"armchair": ["seating", 4.0],
	"chair": ["seating", 1.5],
	"stool": ["seating", 1.0],
	# tables
	"dining_table": ["table", 3.0],
	"coffee_table": ["table", 2.5],
	"island": ["table", 1.5],
	"nightstand": ["table", 1.0],
	# soft floor
	"rug": ["rug", 3.0],
	# decoration
	"painting": ["decor", 3.0],
	"plant": ["decor", 2.5],
	"bookshelf": ["decor", 2.5],
	"tv_stand": ["decor", 1.5],
	# storage (tidy, and three of them make a storage room)
	"wardrobe": ["storage", 1.5],
	"dresser": ["storage", 1.5],
	"cupboard": ["storage", 1.5],
	"storage_chest": ["storage", 1.0],
	"tool_cabinet": ["storage", 1.0],
	"shelves": ["storage", 1.0],
	"boxes": ["storage", 0.5],
	"crate": ["storage", 0.5],          # the build-mode storage crate (WorldObject)
	# kitchen
	"fridge": ["kitchen", 2.0],
	"stove": ["kitchen", 2.0],
	"sink_counter": ["kitchen", 2.0],
	"counter": ["kitchen", 0.5],
	# bathroom
	"bathtub": ["bath", 3.0],
	"toilet": ["bath", 2.0],
	"vanity": ["bath", 1.5],
	# utility and work
	"workbench": ["utility", 1.0],
	"water_heater": ["utility", 1.0],
	"washer": ["utility", 0.5],
	"dryer": ["utility", 0.5],
	# lamps: their light counts (LAMP_*), not the furniture
	"floor_lamp": ["lamp", 0.0],
	"table_lamp": ["lamp", 0.0],
}
const OTHER := ["other", 0.5]

## Category -> {"name", "cap"}.
const CATEGORIES := {
	"bed": {"name": "Bed", "cap": 9.0},
	"seating": {"name": "Seating", "cap": 8.0},
	"table": {"name": "Tables", "cap": 5.0},
	"rug": {"name": "Rugs", "cap": 4.0},
	"decor": {"name": "Decoration", "cap": 6.0},
	"storage": {"name": "Storage", "cap": 3.0},
	"kitchen": {"name": "Kitchen", "cap": 5.0},
	"bath": {"name": "Bathroom fittings", "cap": 5.0},
	"utility": {"name": "Utilities", "cap": 2.0},
	"lamp": {"name": "Lamps", "cap": 0.0},
	"other": {"name": "Other furniture", "cap": 2.0},
}
## Categories that count toward "well furnished" (a balanced room).
const LIVING_CATEGORIES := ["bed", "seating", "table", "rug", "decor", "kitchen", "bath"]
const DECAY := 0.5
const FURNITURE_CAP := 22.0
const DAMAGED_FACTOR := 0.6
const PLURALS := {"shelves": "shelves", "boxes": "boxes", "dining_table": "dining tables", "bookshelf": "bookshelves",
	"sink_counter": "sinks", "storage_chest": "storage chests", "tool_cabinet": "tool cabinets", "coffee_table": "coffee tables"}

# --- environment (per room) ---------------------------------------------------------------

const WELL_FURNISHED := 2.0          ## 3+ living categories
const WELL_FURNISHED_MIN := 3
const BARE_ROOM := -3.0              ## no furniture at all (not hallways)
const FINISHED_FLOOR := 2.0          ## at least FLOOR_GOOD of the room has a finished floor
const BARE_FLOOR := -2.0             ## less than FLOOR_BAD: packed earth or stone slabs
const FLOOR_GOOD := 0.8
const FLOOR_BAD := 0.4
const LAMP_FIRST := 3.0              ## working lamps in the room (x DAY_LAMP_FACTOR by day)
const LAMP_MORE := 1.5
const LAMP_CAP := 4.5
const DAY_LAMP_FACTOR := 0.5
const DAYLIGHT_FIRST := 3.0          ## intact windows by day (x 0.5 at dusk)
const DAYLIGHT_MORE := 1.0
const DAYLIGHT_CAP := 4.0
const BOARDED_GLOOM := -1.0          ## by day, all windows boarded
const DARK_NIGHT := -5.0             ## nothing lights the room at night
const DARK_DAY := -3.0               ## no window and no lamp by day
const FIRE_HERE := 6.0               ## a lit fireplace in the room
const FIRE_NEAR := 2.5               ## a lit fireplace in a room next door
const FIRE_NEAR_REACH := 6.0         ## m from the hearth to the next room's centre
const EXPOSED := -8.0                ## a gap to the outside (missing wall, open doorway, hole)
const BROKEN_WINDOW_FIRST := -4.0
const BROKEN_WINDOW_MORE := -2.0
const BROKEN_WINDOW_CAP := -8.0
const DAMAGED_WALL := -1.0           ## per bounding wall section below WALL_DAMAGED integrity
const DAMAGED_WALL_CAP := -5.0
const WALL_DAMAGED := 0.85
const WRECKED := -1.5                ## per destroyed (rubble) piece of furniture
const WRECKED_CAP := -4.5

# --- levels -------------------------------------------------------------------------------

## Comfort thresholds: below LEVELS[0] Miserable, ..., at or above LEVELS[3] At home.
const LEVELS := [-2.0, 8.0, 18.0, 27.0]
const LEVEL_NAMES := ["Miserable", "Uncomfortable", "Content", "Comfortable", "At home"]

# --- room labels --------------------------------------------------------------------------

const BED_TYPES := ["bed"]
const KITCHEN_TYPES := ["stove", "fridge", "sink_counter"]
const LIVING_TYPES := ["sofa", "armchair"]          # + a fireplace
const WORK_TYPES := ["workbench", "tool_cabinet"]
const BATH_TYPES := ["bathtub", "toilet"]
const STORAGE_FOR_ROOM := 3
const HALLWAY_MAX_AREA := 6.0        ## m²
const HALLWAY_MAX_WIDTH := 1.6       ## m (the narrow side of the room's box)
## House comfort weights by label (a bedroom matters more than a hallway).
const LABEL_WEIGHT := {"Bedroom": 1.5, "Living room": 1.5, "Kitchen & living room": 1.8, "Kitchen": 1.2,
	"Bathroom": 0.8, "Workshop": 0.8, "Storage room": 0.5, "Room": 0.7, "Hallway": 0.3}


static func entry(type: String) -> Array:
	return TYPES.get(type, OTHER)


static func category_of(type: String) -> String:
	return str(entry(type)[0])


static func value_of(type: String) -> float:
	return float(entry(type)[1])


static func level_of(comfort: float) -> int:
	var i := 0
	while i < LEVELS.size() and comfort >= float(LEVELS[i]):
		i += 1
	return i


static func level_name(comfort: float) -> String:
	return LEVEL_NAMES[level_of(comfort)]


## "chair" -> "Chair", 3 x "chair" -> "3 chairs".
static func type_name(type: String, n := 1) -> String:
	var base := type.replace("_", " ")
	if n <= 1:
		return base.left(1).to_upper() + base.substr(1)
	return "%d %s" % [n, PLURALS.get(type, base + "s")]
