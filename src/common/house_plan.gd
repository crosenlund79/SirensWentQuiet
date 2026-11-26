class_name HousePlan
extends RefCounted
## The one shared floor plan for Experiment 001.
##
## Units are meters. Plan X points east, plan Y points south (screen-down in
## the top-down view). North is "up" on screen in all three versions.
##   3D versions: plan (x, y) -> Vector3(x, height, y)   (north = -Z)
##   2D version:  plan (x, y) -> Vector2(x, y) * pixels_per_meter
##
## Walls are centre lines on whole-meter grid lines. Openings are given as
## `from`/`to` coordinates along the wall's axis (x for horizontal walls,
## y for vertical walls). Rects are axis-aligned footprints Rect2(x, y, w, d).
##
##        x=0       5     8        14
##   y=0  +---------+-----+---------+
##        | Bedroom |Bath | Kitchen |
##   y=4  +--d------+-d---+  open +-+---+
##        |  Living room      | Utility |
##        |                   d         d (back door)
##   y=9  +-----D-------------+---------+
##              front door

const FOOTPRINT := Rect2(0, 0, 14, 9)
## Playable area around the house. Enemies spawn near its edge.
const YARD := Rect2(-7, -6, 28, 21)

const WALL_HEIGHT := 2.6
const EXTERIOR_THICKNESS := 0.3
const INTERIOR_THICKNESS := 0.2
const DOOR_HEIGHT := 2.1
const WINDOW_SILL := 0.9
const WINDOW_HEAD := 2.1

const ROOMS := [
	{"id": "bedroom", "name": "Bedroom", "rect": Rect2(0, 0, 5, 4), "floor": "wood_light"},
	{"id": "bathroom", "name": "Bathroom", "rect": Rect2(5, 0, 3, 4), "floor": "tile"},
	{"id": "kitchen", "name": "Kitchen", "rect": Rect2(8, 0, 6, 4), "floor": "kitchen_tile"},
	{"id": "living", "name": "Living room", "rect": Rect2(0, 4, 10, 5), "floor": "wood"},
	{"id": "utility", "name": "Utility room", "rect": Rect2(10, 4, 4, 5), "floor": "concrete"},
]

const WALLS := [
	{"id": "north", "a": Vector2(0, 0), "b": Vector2(14, 0), "exterior": true},
	{"id": "east", "a": Vector2(14, 0), "b": Vector2(14, 9), "exterior": true},
	{"id": "south", "a": Vector2(0, 9), "b": Vector2(14, 9), "exterior": true},
	{"id": "west", "a": Vector2(0, 0), "b": Vector2(0, 9), "exterior": true},
	# y = 4, between the north rooms and the living room. Kitchen side is open (x 8..10).
	{"id": "mid_west", "a": Vector2(0, 4), "b": Vector2(8, 4), "exterior": false},
	{"id": "mid_east", "a": Vector2(10, 4), "b": Vector2(14, 4), "exterior": false},
	{"id": "bed_bath", "a": Vector2(5, 0), "b": Vector2(5, 4), "exterior": false},
	{"id": "bath_kitchen", "a": Vector2(8, 0), "b": Vector2(8, 4), "exterior": false},
	{"id": "living_utility", "a": Vector2(10, 4), "b": Vector2(10, 9), "exterior": false},
]

## kind: "door" (open doorway, passable) or "window" (blocks movement, glass).
## Door leaves, if drawn, stand open and never block.
const OPENINGS := [
	{"id": "front_door", "kind": "door", "wall": "south", "from": 4.0, "to": 5.0},
	{"id": "back_door", "kind": "door", "wall": "east", "from": 6.0, "to": 7.0},
	{"id": "bedroom_door", "kind": "door", "wall": "mid_west", "from": 2.0, "to": 3.0},
	{"id": "bathroom_door", "kind": "door", "wall": "mid_west", "from": 6.0, "to": 7.0},
	{"id": "utility_door", "kind": "door", "wall": "living_utility", "from": 7.0, "to": 8.0},
	{"id": "bedroom_window", "kind": "window", "wall": "north", "from": 1.0, "to": 3.0},
	{"id": "bathroom_window", "kind": "window", "wall": "north", "from": 6.0, "to": 7.0, "sill": 1.4},
	{"id": "kitchen_window_n", "kind": "window", "wall": "north", "from": 10.0, "to": 12.0},
	{"id": "kitchen_window_e", "kind": "window", "wall": "east", "from": 1.0, "to": 3.0},
	{"id": "living_window_s1", "kind": "window", "wall": "south", "from": 1.0, "to": 3.0},
	{"id": "living_window_s2", "kind": "window", "wall": "south", "from": 6.0, "to": 8.0},
	{"id": "living_window_w", "kind": "window", "wall": "west", "from": 6.0, "to": 8.0},
	{"id": "utility_window", "kind": "window", "wall": "south", "from": 12.0, "to": 13.0},
]

## facing: the side the "front" of the piece points to (N/E/S/W).
## height: meters. blocks: blocks movement (and navigation).
## Pieces with height >= Tuning.TALL_THRESHOLD also stop bullets.
const FURNITURE := [
	# Living room
	{"id": "tv_stand", "type": "tv_stand", "room": "living", "rect": Rect2(3.5, 4.12, 2.0, 0.45), "facing": "S", "height": 1.1, "blocks": true},
	{"id": "sofa", "type": "sofa", "room": "living", "rect": Rect2(3.3, 6.6, 2.4, 0.95), "facing": "N", "height": 0.85, "blocks": true},
	{"id": "coffee_table", "type": "coffee_table", "room": "living", "rect": Rect2(3.95, 5.35, 1.1, 0.6), "facing": "N", "height": 0.45, "blocks": true},
	{"id": "rug_living", "type": "rug", "room": "living", "rect": Rect2(2.8, 4.9, 3.4, 2.9), "facing": "N", "height": 0.01, "blocks": false},
	{"id": "armchair", "type": "armchair", "room": "living", "rect": Rect2(1.4, 5.3, 0.9, 0.9), "facing": "E", "height": 0.85, "blocks": true},
	{"id": "floor_lamp", "type": "floor_lamp", "room": "living", "rect": Rect2(1.55, 6.55, 0.4, 0.4), "facing": "N", "height": 1.6, "blocks": true},
	{"id": "bookshelf", "type": "bookshelf", "room": "living", "rect": Rect2(0.15, 4.4, 0.4, 1.4), "facing": "E", "height": 1.9, "blocks": true},
	{"id": "dining_table", "type": "dining_table", "room": "living", "rect": Rect2(7.0, 5.2, 1.6, 0.9), "facing": "N", "height": 0.75, "blocks": true},
	# Exp 012 (L, §23): the chairs tucked in to the table's edges (a 0.68 m way behind the north pair)
	{"id": "dining_chair_1", "type": "chair", "room": "living", "rect": Rect2(7.15, 4.78, 0.45, 0.42), "facing": "S", "height": 0.9, "blocks": true},
	{"id": "dining_chair_2", "type": "chair", "room": "living", "rect": Rect2(8.0, 4.78, 0.45, 0.42), "facing": "S", "height": 0.9, "blocks": true},
	{"id": "dining_chair_3", "type": "chair", "room": "living", "rect": Rect2(7.15, 6.1, 0.45, 0.42), "facing": "N", "height": 0.9, "blocks": true},
	{"id": "dining_chair_4", "type": "chair", "room": "living", "rect": Rect2(8.0, 6.1, 0.45, 0.42), "facing": "N", "height": 0.9, "blocks": true},
	{"id": "plant_living", "type": "plant", "room": "living", "rect": Rect2(9.3, 8.25, 0.5, 0.5), "facing": "N", "height": 1.1, "blocks": true},
	# Kitchen
	{"id": "fridge", "type": "fridge", "room": "kitchen", "rect": Rect2(8.15, 0.2, 0.75, 0.7), "facing": "S", "height": 1.85, "blocks": true},
	{"id": "counter_a", "type": "counter", "room": "kitchen", "rect": Rect2(8.95, 0.17, 1.55, 0.62), "facing": "S", "height": 0.92, "blocks": true},
	{"id": "sink_counter", "type": "sink_counter", "room": "kitchen", "rect": Rect2(10.5, 0.17, 1.0, 0.62), "facing": "S", "height": 0.92, "blocks": true},
	{"id": "counter_b", "type": "counter", "room": "kitchen", "rect": Rect2(11.5, 0.17, 1.0, 0.62), "facing": "S", "height": 0.92, "blocks": true},
	{"id": "stove", "type": "stove", "room": "kitchen", "rect": Rect2(12.5, 0.17, 0.75, 0.62), "facing": "S", "height": 0.92, "blocks": true},
	{"id": "counter_c", "type": "counter", "room": "kitchen", "rect": Rect2(13.25, 0.17, 0.6, 0.62), "facing": "S", "height": 0.92, "blocks": true},
	{"id": "counter_east", "type": "counter", "room": "kitchen", "rect": Rect2(13.23, 0.79, 0.62, 1.5), "facing": "W", "height": 0.92, "blocks": true},
	# Exp 012 (L, §23): the island sits 0.15 m further north and the stools are
	# a little smaller and tucked against it, so a walkway of about 0.7 m stays
	# free between them and the kitchen's south wall (it was 0.45 m: Eli got stuck)
	{"id": "island", "type": "island", "room": "kitchen", "rect": Rect2(10.2, 1.95, 1.9, 0.85), "facing": "S", "height": 0.92, "blocks": true},
	{"id": "stool_1", "type": "stool", "room": "kitchen", "rect": Rect2(10.55, 2.84, 0.36, 0.36), "facing": "N", "height": 0.7, "blocks": true},
	{"id": "stool_2", "type": "stool", "room": "kitchen", "rect": Rect2(11.45, 2.84, 0.36, 0.36), "facing": "N", "height": 0.7, "blocks": true},
	# Bedroom
	{"id": "bed", "type": "bed", "room": "bedroom", "rect": Rect2(1.2, 0.17, 1.6, 2.1), "facing": "S", "height": 0.6, "blocks": true},
	{"id": "nightstand_l", "type": "nightstand", "room": "bedroom", "rect": Rect2(0.7, 0.2, 0.45, 0.42), "facing": "S", "height": 0.55, "blocks": true},
	{"id": "nightstand_r", "type": "nightstand", "room": "bedroom", "rect": Rect2(2.85, 0.2, 0.45, 0.42), "facing": "S", "height": 0.55, "blocks": true},
	{"id": "wardrobe", "type": "wardrobe", "room": "bedroom", "rect": Rect2(4.25, 0.5, 0.62, 1.5), "facing": "W", "height": 2.0, "blocks": true},
	{"id": "dresser", "type": "dresser", "room": "bedroom", "rect": Rect2(3.6, 3.35, 1.2, 0.5), "facing": "N", "height": 0.8, "blocks": true},
	{"id": "rug_bed", "type": "rug", "room": "bedroom", "rect": Rect2(0.9, 2.35, 2.2, 1.1), "facing": "N", "height": 0.01, "blocks": false},
	# Bathroom
	{"id": "bathtub", "type": "bathtub", "room": "bathroom", "rect": Rect2(5.12, 0.17, 0.8, 1.7), "facing": "E", "height": 0.55, "blocks": true},
	{"id": "toilet", "type": "toilet", "room": "bathroom", "rect": Rect2(7.3, 0.25, 0.55, 0.7), "facing": "W", "height": 0.8, "blocks": true},
	{"id": "vanity", "type": "vanity", "room": "bathroom", "rect": Rect2(7.35, 1.4, 0.52, 0.9), "facing": "W", "height": 0.85, "blocks": true},
	{"id": "bath_mat", "type": "rug", "room": "bathroom", "rect": Rect2(6.0, 0.6, 0.5, 0.8), "facing": "N", "height": 0.01, "blocks": false},
	# Utility room
	{"id": "water_heater", "type": "water_heater", "room": "utility", "rect": Rect2(10.15, 4.15, 0.6, 0.6), "facing": "S", "height": 1.6, "blocks": true},
	{"id": "workbench", "type": "workbench", "room": "utility", "rect": Rect2(10.9, 4.12, 1.8, 0.65), "facing": "S", "height": 0.9, "blocks": true},
	{"id": "washer", "type": "washer", "room": "utility", "rect": Rect2(13.2, 4.15, 0.62, 0.62), "facing": "W", "height": 0.85, "blocks": true},
	{"id": "dryer", "type": "dryer", "room": "utility", "rect": Rect2(13.2, 4.82, 0.62, 0.62), "facing": "W", "height": 0.85, "blocks": true},
	{"id": "shelves", "type": "shelves", "room": "utility", "rect": Rect2(10.12, 5.2, 0.45, 1.6), "facing": "E", "height": 1.9, "blocks": true},
	{"id": "boxes", "type": "boxes", "room": "utility", "rect": Rect2(11.6, 8.15, 1.0, 0.7), "facing": "N", "height": 0.6, "blocks": true},
]

## Exterior dressing. Same fields as furniture; room is "yard".
const PROPS := [
	{"id": "porch_deck", "type": "deck", "room": "yard", "rect": Rect2(2.5, 9.15, 4.0, 1.3), "facing": "S", "height": 0.15, "blocks": false},
	{"id": "front_path", "type": "path", "room": "yard", "rect": Rect2(4.0, 10.45, 1.0, 3.05), "facing": "S", "height": 0.02, "blocks": false},
	{"id": "road", "type": "road", "room": "yard", "rect": Rect2(-7, 13.5, 28, 1.5), "facing": "S", "height": 0.0, "blocks": false},
	{"id": "driveway", "type": "driveway", "room": "yard", "rect": Rect2(15.5, 8.0, 3.0, 5.5), "facing": "S", "height": 0.02, "blocks": false},
	{"id": "back_step", "type": "step", "room": "yard", "rect": Rect2(14.15, 5.9, 0.6, 1.2), "facing": "E", "height": 0.15, "blocks": false},
	{"id": "car", "type": "car", "room": "yard", "rect": Rect2(16.0, 8.5, 2.0, 4.4), "facing": "N", "height": 1.45, "blocks": true},
	# Experiment 004 (northern atmosphere): snow-laden pines along the lot edge
	# and in the fog band, clear of the spawn points, the paths and the lanes.
	# More pines stand further out in the fog (visual only: VoxelYard.FOG_PINES).
	{"id": "tree_1", "type": "pine", "room": "yard", "rect": Rect2(-4.3, 1.2, 0.6, 0.6), "facing": "N", "height": 6.2, "blocks": true},
	{"id": "tree_2", "type": "pine", "room": "yard", "rect": Rect2(18.2, -3.3, 0.6, 0.6), "facing": "N", "height": 5.6, "blocks": true},
	{"id": "tree_3", "type": "pine", "room": "yard", "rect": Rect2(-4.8, 11.0, 0.6, 0.6), "facing": "N", "height": 5.2, "blocks": true},
	{"id": "tree_4", "type": "pine", "room": "yard", "rect": Rect2(-3.5, -4.7, 0.6, 0.6), "facing": "N", "height": 6.8, "blocks": true},
	{"id": "tree_5", "type": "pine", "room": "yard", "rect": Rect2(6.5, -4.7, 0.6, 0.6), "facing": "N", "height": 7.2, "blocks": true},
	{"id": "tree_6", "type": "pine", "room": "yard", "rect": Rect2(14.9, -4.9, 0.6, 0.6), "facing": "N", "height": 6.4, "blocks": true},
	{"id": "tree_7", "type": "pine", "room": "yard", "rect": Rect2(19.6, 0.5, 0.6, 0.6), "facing": "N", "height": 6.0, "blocks": true},
	{"id": "tree_8", "type": "pine", "room": "yard", "rect": Rect2(19.8, 9.1, 0.6, 0.6), "facing": "N", "height": 5.4, "blocks": true},
	{"id": "tree_9", "type": "pine", "room": "yard", "rect": Rect2(-6.4, 2.8, 0.6, 0.6), "facing": "N", "height": 6.6, "blocks": true},
	{"id": "tree_10", "type": "pine", "room": "yard", "rect": Rect2(-6.2, 8.6, 0.6, 0.6), "facing": "N", "height": 5.8, "blocks": true},
	{"id": "tree_11", "type": "pine", "room": "yard", "rect": Rect2(12.6, -2.7, 0.6, 0.6), "facing": "N", "height": 4.6, "blocks": true},
	{"id": "trash_bin", "type": "trash_bin_tipped", "room": "yard", "rect": Rect2(15.0, 0.6, 0.9, 0.6), "facing": "E", "height": 0.6, "blocks": true},
	{"id": "mailbox", "type": "mailbox", "room": "yard", "rect": Rect2(5.6, 12.9, 0.3, 0.3), "facing": "S", "height": 1.2, "blocks": true},
	{"id": "streetlight", "type": "streetlight_dead", "room": "yard", "rect": Rect2(9.8, 13.2, 0.25, 0.25), "facing": "S", "height": 4.5, "blocks": true},
]

## Light fixtures. `night_on`: lit in the night state (all interior fixtures
## are off in the overcast day state). `flicker`: unstable bulb.
const LIGHTS := [
	{"id": "living_lamp", "room": "living", "pos": Vector2(1.75, 6.75), "height": 1.5, "kind": "floor_lamp", "night_on": true, "flicker": false},
	{"id": "living_ceiling", "room": "living", "pos": Vector2(5.0, 6.2), "height": 2.5, "kind": "ceiling", "night_on": false, "flicker": false},
	{"id": "kitchen_hood", "room": "kitchen", "pos": Vector2(12.9, 0.5), "height": 1.6, "kind": "hood", "night_on": true, "flicker": false},
	{"id": "kitchen_ceiling", "room": "kitchen", "pos": Vector2(11.0, 2.0), "height": 2.5, "kind": "ceiling", "night_on": false, "flicker": false},
	{"id": "bedside_lamp", "room": "bedroom", "pos": Vector2(0.92, 0.4), "height": 0.8, "kind": "table_lamp", "night_on": true, "flicker": false},
	{"id": "bathroom_ceiling", "room": "bathroom", "pos": Vector2(6.5, 2.0), "height": 2.5, "kind": "ceiling", "night_on": true, "flicker": true},
	{"id": "utility_bulb", "room": "utility", "pos": Vector2(12.0, 6.5), "height": 2.4, "kind": "bare_bulb", "night_on": true, "flicker": false},
]

const PLAYER_START := Vector2(6.5, 7.8)

## Enemies appear at one of these (outside the house, inside YARD).
const SPAWN_POINTS := [
	Vector2(-6.0, -5.0), Vector2(3.0, -5.5), Vector2(11.0, -5.5),
	Vector2(20.0, -4.5), Vector2(20.5, 4.0), Vector2(20.0, 14.2),
	Vector2(10.0, 14.3), Vector2(-1.0, 14.3), Vector2(-6.5, 6.0),
]


static func wall_by_id(id: String) -> Dictionary:
	for w in WALLS:
		if w["id"] == id:
			return w
	return {}


static func is_horizontal(wall: Dictionary) -> bool:
	return is_equal_approx(wall["a"].y, wall["b"].y)


static func thickness(wall: Dictionary) -> float:
	return EXTERIOR_THICKNESS if wall["exterior"] else INTERIOR_THICKNESS


## Footprint of the whole wall. Ends extend by half the thickness so corners
## and T-junctions close.
static func wall_rect(wall: Dictionary) -> Rect2:
	var t := thickness(wall)
	var a: Vector2 = wall["a"]
	var b: Vector2 = wall["b"]
	if is_horizontal(wall):
		return Rect2(minf(a.x, b.x) - t * 0.5, a.y - t * 0.5, absf(b.x - a.x) + t, t)
	return Rect2(a.x - t * 0.5, minf(a.y, b.y) - t * 0.5, t, absf(b.y - a.y) + t)


## Footprint of a stretch [from, to] along a wall, full wall thickness.
static func span_rect(wall: Dictionary, from: float, to: float) -> Rect2:
	var t := thickness(wall)
	if is_horizontal(wall):
		return Rect2(from, wall["a"].y - t * 0.5, to - from, t)
	return Rect2(wall["a"].x - t * 0.5, from, t, to - from)


static func openings_on(wall_id: String) -> Array:
	var out := []
	for o in OPENINGS:
		if o["wall"] == wall_id:
			out.append(o)
	out.sort_custom(func(p, q): return p["from"] < q["from"])
	return out


## The wall split into consecutive spans covering its full length:
## [{"from", "to", "kind": "solid"|"door"|"window", "opening": Dictionary}]
static func wall_spans(wall: Dictionary) -> Array:
	var horiz := is_horizontal(wall)
	var start: float = minf(wall["a"].x, wall["b"].x) if horiz else minf(wall["a"].y, wall["b"].y)
	var end: float = maxf(wall["a"].x, wall["b"].x) if horiz else maxf(wall["a"].y, wall["b"].y)
	var spans := []
	var cursor := start
	for o in openings_on(wall["id"]):
		if o["from"] > cursor:
			spans.append({"from": cursor, "to": o["from"], "kind": "solid", "opening": {}})
		spans.append({"from": o["from"], "to": o["to"], "kind": o["kind"], "opening": o})
		cursor = o["to"]
	if cursor < end:
		spans.append({"from": cursor, "to": end, "kind": "solid", "opening": {}})
	return spans


static func window_sill(opening: Dictionary) -> float:
	return opening.get("sill", WINDOW_SILL)


static func room_at(p: Vector2) -> Dictionary:
	for r in ROOMS:
		if (r["rect"] as Rect2).has_point(p):
			return r
	return {}


## Fill a GridNav with the intact house: walls and windows are WALL
## (destructible), doorways open, blocking furniture and props SOLID.
static func rasterize_into(nav: GridNav) -> void:
	for w in WALLS:
		nav.mark_rect(wall_rect(w), GridNav.WALL)
	for o in OPENINGS:
		if o["kind"] == "door":
			nav.mark_rect(span_rect(wall_by_id(o["wall"]), o["from"], o["to"]), GridNav.OPEN)
	for f in FURNITURE + PROPS:
		if f["blocks"]:
			nav.mark_rect(f["rect"], GridNav.SOLID)
	nav.rebuild()
