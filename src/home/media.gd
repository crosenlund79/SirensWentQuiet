class_name HouseMedia
extends RefCounted
## Exp 006 (B): the TV and the radio (the user's §9). Pure rules; the game's
## balance helper (src/home/game_balance.gd) runs the switches, the screen
## glow, the static and the save.
##
## Sources: the house's own TV (the living room's tv_stand, while it stands
## where it was) and placed pieces (WorldObject "tv_stand" = a TV on its
## stand, "radio"; a moved original TV becomes one). E switches a source on or
## off (`WorldObject.media_on`, or GameState.run["media"] for the house's
## TV); it plays only while the house has power (the fuse box's mains) and the
## piece isn't wrecked.
##
## Balance (modest, never stacking):
##   comfort  a room with a playing source gets one factor (the best one
##            there: TV COMFORT["tv_stand"], radio less); at most ROOMS_MAX
##            rooms in the house count (the best ones), so a TV in every room
##            is worth no more than two.
##   mood     "Watching TV" / "The radio for company" while Eli is in a room
##            where one plays: one cause, at most MOOD_CAP.

const KINDS := ["tv_stand", "radio"]
const NAMES := {"tv_stand": "TV", "radio": "radio"}
const COMFORT := {"tv_stand": 2.0, "radio": 1.0}
const MOOD := {"tv_stand": 3.0, "radio": 2.0}
const FACTORS := {"tv_stand": "The TV on", "radio": "The radio playing"}
const CAUSES := {"tv_stand": "Watching TV", "radio": "The radio for company"}
const ROOMS_MAX := 2
const MOOD_CAP := 3.0
const NO_POWER := "Nothing. There's no power."


static func is_media(kind: String) -> bool:
	return kind in KINDS


static func prompt(kind: String, on: bool) -> String:
	return "[E] Turn the %s %s" % [NAMES.get(kind, kind), "off" if on else "on"]


static func comfort_of(kind: String) -> float:
	return float(COMFORT.get(kind, 0.0))


static func mood_of(kind: String) -> float:
	return minf(float(MOOD.get(kind, 0.0)), MOOD_CAP)


## The most valuable of the playing kinds in one room ("" for none).
static func best(kinds: Array) -> String:
	var out := ""
	for k in kinds:
		if comfort_of(str(k)) > comfort_of(out):
			out = str(k)
	return out


## Per room (an Array of the playing kinds in each room) -> the kind whose
## comfort that room gets ("" = none): one per room, ROOMS_MAX rooms at most
## (the most valuable first; ties keep the room order).
static func room_bonuses(per_room: Array) -> Array:
	var out := []
	var order := []
	for i in per_room.size():
		var b := best(per_room[i])
		out.append("")
		if b != "":
			order.append([i, b])
	order.sort_custom(func(a, b): return comfort_of(a[1]) > comfort_of(b[1]) or (comfort_of(a[1]) == comfort_of(b[1]) and a[0] < b[0]))
	for k in mini(order.size(), ROOMS_MAX):
		out[order[k][0]] = order[k][1]
	return out


## The comfort factor of a room for kind `kind` ("" = none): [text, value] or [].
static func factor(kind: String) -> Array:
	if kind == "":
		return []
	return [FACTORS.get(kind, "Media"), comfort_of(kind)]


## The mood cause for the room Eli is in ([] = none).
static func cause(kind: String) -> Array:
	if kind == "":
		return []
	return [CAUSES.get(kind, "Media"), mood_of(kind)]
