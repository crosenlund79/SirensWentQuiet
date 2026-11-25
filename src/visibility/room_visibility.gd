class_name RoomVisibility
extends RefCounted
## Experiment 007 (N): which rooms of a storey Eli can see (the user's §10).
## Pure rules over a HouseRooms map; GameVisibility applies them.
##
##   FULL     the room Eli is in. Rooms joined by a breach big enough to walk
##            through are one room in the flood fill, so they are FULL too.
##   NEAR     joined to Eli's room by an open doorway (no door leaf):
##            substantially visible (contents shown, barely dimmed)
##   PARTIAL  joined to Eli's room by an open door: contents shown, dimmed
##   HIDDEN   closed off: furniture, objects, lamps and enemies hidden, the
##            floor darkened
## Outdoors (Eli in no room of the storey): rooms open to the outside (a
## breach, a doorway without a door) are NEAR, rooms behind an open outer door
## PARTIAL, the rest HIDDEN. The outdoors itself has no room logic.
## Tiny openings (bullet holes, a gap under a window) don't change the rooms
## or the doors, so they reveal nothing.

enum { FULL, NEAR, PARTIAL, HIDDEN }

const NAMES := ["full", "near", "partial", "hidden"]
## Floor overlay darkness (alpha) per state.
const DIM := [0.0, 0.12, 0.3, 0.72]


## Open passages between rooms and to the outside:
## {"pairs": [[a, b, kind]], "outside": {room: kind}} where kind is "doorway"
## (no leaf) or "door" (an open leaf). Closed doors, boards and barricades
## are no passage.
static func links(world: HouseWorld, map: Dictionary) -> Dictionary:
	var pairs := []
	var outside := {}
	for d in NoisePlace.door_sides(world, map):
		if not d["open"]:
			continue
		var a := int(d["a"])
		var b := int(d["b"])
		var kind: String = d["kind"]
		if a >= 0 and b >= 0 and a != b:
			pairs.append([a, b, kind])
		elif a >= 0 and b < 0:
			outside[a] = _better(outside.get(a, ""), kind)
		elif b >= 0 and a < 0:
			outside[b] = _better(outside.get(b, ""), kind)
	return {"pairs": pairs, "outside": outside}


static func _better(old: String, kind: String) -> String:
	return "doorway" if old == "doorway" or kind == "doorway" else kind


## room index -> state for a map, its links and Eli's room (`here`, -1 outdoors).
static func compute(map: Dictionary, lk: Dictionary, here: int) -> Dictionary:
	var out := {}
	var rooms: Array = map.get("rooms", [])
	for r in rooms:
		out[int(r["index"])] = HIDDEN
	if rooms.is_empty():
		return out
	if here >= 0 and out.has(here):
		out[here] = FULL
		for p in lk.get("pairs", []):
			var other := -1
			if int(p[0]) == here:
				other = int(p[1])
			elif int(p[1]) == here:
				other = int(p[0])
			if other >= 0 and out.has(other):
				out[other] = mini(out[other], NEAR if p[2] == "doorway" else PARTIAL)
		return out
	var outside: Dictionary = lk.get("outside", {})
	for r in rooms:
		var i := int(r["index"])
		if r["exposed"]:
			out[i] = NEAR
		elif outside.has(i):
			out[i] = NEAR if outside[i] == "doorway" else PARTIAL
	return out


static func name_of(state: int) -> String:
	return NAMES[clampi(state, 0, NAMES.size() - 1)]


## Counts per state name, e.g. {"full": 1, "near": 0, "partial": 1, "hidden": 4}.
static func counts(states: Dictionary) -> Dictionary:
	var out := {"full": 0, "near": 0, "partial": 0, "hidden": 0}
	for k in states:
		out[name_of(states[k])] += 1
	return out
