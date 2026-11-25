class_name NoisePlace
extends RefCounted
## Experiment 007 (N): how exposed a noise is, by place (the user's §12).
## No sound waves and no voxel propagation: the rooms of the storey
## (HouseRooms flood fill, through a RoomCache) decide.
##
##   place            exposure   when
##   outdoors         1.00       not in any room (the lot, a deck, a POI's outside)
##   exterior room    0.75       a ground-floor room with an outer wall
##   central room     0.50       a ground-floor room with no outer wall
##   upper interior   0.50       a room on an upper storey
##   basement         0.25       below ground (earth all round)
## Openings raise it (at most +MAX_RAISE in all):
##   breach           +0.30      the room is open to the outside (a missing
##                               wall, a hole, a doorway without a door)
##   open door        +0.20      per open outer door of the room (doors and
##                               doorways between rooms keep the sound inside)
##   broken window    +0.10      per broken window of the room

const OUTDOORS := 1.0
const EXTERIOR := 0.75
const CENTRAL := 0.5
const UPPER := 0.5
const BASEMENT := 0.25
const BREACH := 0.3
const OPEN_DOOR_OUT := 0.2
const BROKEN_WINDOW := 0.1
const MAX_RAISE := 0.45
const EDGE := 0.6                ## m beyond a room's box: outside the floor = an outer wall


## {"place", "exposure", "room": index or -1, "label", "notes": [text]} for plan
## point p on `storey` of `world`. `cache` may be null (rooms are found now).
static func classify(world: HouseWorld, storey: int, p: Vector2, cache: RoomCache = null) -> Dictionary:
	if world == null or world.nav == null:
		return {"place": "outdoors", "exposure": OUTDOORS, "room": -1, "label": "outdoors", "notes": []}
	var map := cache.map_of(world, storey) if cache != null else HouseRooms.find(world, storey)
	var i := HouseRooms.room_index_at(map, world.nav, p, 1)
	if i < 0:
		if storey < 0:
			return {"place": "basement", "exposure": BASEMENT, "room": -1, "label": "underground", "notes": []}
		return {"place": "outdoors", "exposure": OUTDOORS, "room": -1, "label": "outdoors", "notes": []}
	var room: Dictionary = map["rooms"][i]
	var place := "central room"
	var base := CENTRAL
	if storey < 0:
		place = "basement"
		base = BASEMENT
	elif storey > 0:
		place = "upper interior"
		base = UPPER
	elif is_exterior(world, storey, room):
		place = "exterior room"
		base = EXTERIOR
	var raise := 0.0
	var notes := []
	if room["exposed"]:
		raise += BREACH
		notes.append("breach")
	for d in door_sides(world, map):
		if not d["open"]:
			continue
		if (int(d["a"]) == i and int(d["b"]) < 0) or (int(d["b"]) == i and int(d["a"]) < 0):
			raise += OPEN_DOOR_OUT
			notes.append("open door")
	var wins := cache.windows_of(world, storey) if cache != null else HouseRooms.windows(world, storey)
	for win in wins:
		if win["state"] == "broken" and HouseRooms.room_index_at(map, world.nav, win["inside"], 2) == i:
			raise += BROKEN_WINDOW
			notes.append("broken window")
	var exposure := clampf(base + minf(raise, MAX_RAISE), 0.1, 1.0)
	return {"place": place, "exposure": exposure, "room": i, "label": "%s room %d" % [Levels.name_of(storey), i], "notes": notes}


## True if the room has an outer wall: a bounding section HouseWorld counts as
## outer, or floor-less ground just beyond its box (POIs, odd shapes).
static func is_exterior(world: HouseWorld, storey: int, room: Dictionary) -> bool:
	if not world.has_method("entry_point"):
		for s in room["sections"]:
			if world._is_outer_wall(s):
				return true
	var rects := HouseRooms.floor_rects(world, storey)
	var b: Rect2 = room["bbox"]
	var c := b.get_center()
	for q in [Vector2(b.position.x - EDGE, c.y), Vector2(b.end.x + EDGE, c.y), Vector2(c.x, b.position.y - EDGE), Vector2(c.x, b.end.y + EDGE)]:
		var inside := false
		for r in rects:
			if (r as Rect2).has_point(q):
				inside = true
				break
		if not inside:
			return true
	return false


## Every door and door-like opening of the world with the rooms on its two
## sides: [{"pos": Vector2, "a": room or -1, "b": room or -1, "open": bool,
## "door": WorldObject or null, "kind": "door" | "doorway"}]. A doorway with no
## leaf is open; boards or a barricade in it close it.
static func door_sides(world: HouseWorld, map: Dictionary) -> Array:
	var out := []
	if world == null or map.is_empty():
		return out
	var seen := {}
	for op in world.openings:
		var f: float = op["from"]
		var t: float = op["to"]
		var line := float(op["line"])
		var horiz: bool = int(op["axis"]) == 0
		var mid := (f + t) * 0.5
		var at := Vector2(mid, line) if horiz else Vector2(line, mid)
		var span := Rect2(f, line - 0.2, t - f, 0.4) if horiz else Rect2(line - 0.2, f, 0.4, t - f)
		var door: WorldObject = null
		var closed := false
		for o in world.objects_in(span):
			var wo := o as WorldObject
			if wo.kind == "door":
				door = wo
				seen[wo.get_instance_id()] = true
				closed = closed or not wo.open
			elif wo.kind in ["boards", "barricade"]:
				closed = true
		var n := Vector2(0, 1) if horiz else Vector2(1, 0)
		out.append({"pos": at, "a": HouseRooms.room_index_at(map, world.nav, at - n * 0.5, 1),
			"b": HouseRooms.room_index_at(map, world.nav, at + n * 0.5, 1), "open": not closed,
			"door": door, "kind": "door" if door != null else "doorway"})
	for o in world.objects:              # doors hung outside the indexed openings
		if o.kind != "door" or seen.has(o.get_instance_id()):
			continue
		var fd := WorldObject.front_dir(o.rot)
		out.append({"pos": o.pos, "a": HouseRooms.room_index_at(map, world.nav, o.pos - fd * 0.5, 1),
			"b": HouseRooms.room_index_at(map, world.nav, o.pos + fd * 0.5, 1), "open": o.open, "door": o, "kind": "door"})
	return out
