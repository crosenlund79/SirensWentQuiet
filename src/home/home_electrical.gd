class_name HomeElectrical
extends RefCounted
## Experiment 004 electrical system, as plain data (no nodes): each electric
## light in HousePlan.LIGHTS has its own switch, each room has a wall switch,
## and the whole house hangs on the fuse box's mains. A light shines only if
##   its own switch is on AND its room switch is on AND a fuse box exists AND
##   the fuse box's mains are on (and the furniture it stands on is intact).
## The fireplace, candles and lanterns don't depend on any of this.
##
## Saved as an optional part of GameState.home ("lights", "rooms").

## Lights a player can reach and switch by hand (the rest only by the room switch).
const REACHABLE := {
	"floor_lamp": "[E] Turn the lamp %s",
	"table_lamp": "[E] Turn the lamp %s",
	"hood": "[E] Turn the hood light %s",
	"bare_bulb": "[E] Pull the cord (light %s)",
}
## Furniture an electric light needs (HouseWorld.furniture_ok), by light id.
const NEEDS_FURNITURE := {"living_lamp": "floor_lamp", "bedside_lamp": "nightstand_l"}

var lights := {}        ## light id -> own switch on
var rooms := {}         ## room id -> wall switch on


## The defaults of a new game: every room switch on; the lamps that were lit
## in the old night state on, the big ceiling lights off.
static func create() -> HomeElectrical:
	var e := HomeElectrical.new()
	for l in HousePlan.LIGHTS:
		e.lights[l["id"]] = bool(l.get("night_on", true))
		e.rooms[l["room"]] = true
	return e


## A system restored from saved data (unknown ids ignored, missing ones default).
static func from_dict(d) -> HomeElectrical:
	var e := create()
	if typeof(d) != TYPE_DICTIONARY:
		return e
	var ls = d.get("lights", {})
	if typeof(ls) == TYPE_DICTIONARY:
		for id in ls:
			if e.lights.has(str(id)):
				e.lights[str(id)] = ls[id] == true
	var rs = d.get("rooms", {})
	if typeof(rs) == TYPE_DICTIONARY:
		for id in rs:
			if e.rooms.has(str(id)):
				e.rooms[str(id)] = rs[id] == true
	return e


func to_dict() -> Dictionary:
	return {"lights": lights.duplicate(), "rooms": rooms.duplicate()}


static func light_def(id: String) -> Dictionary:
	for l in HousePlan.LIGHTS:
		if l["id"] == id:
			return l
	return {}


static func room_name(room: String) -> String:
	for r in HousePlan.ROOMS:
		if r["id"] == room:
			return str(r["name"])
	return room.capitalize()


## The dependency rule. `mains`: a fuse box exists and its mains are on.
## `furniture_ok`: Callable(id) -> bool, or an invalid Callable (all intact).
func shines(id: String, mains: bool, furniture_ok := Callable()) -> bool:
	if not mains or not lights.get(id, false):
		return false
	var l := light_def(id)
	if l.is_empty() or not rooms.get(l["room"], false):
		return false
	if NEEDS_FURNITURE.has(id) and furniture_ok.is_valid() and not furniture_ok.call(NEEDS_FURNITURE[id]):
		return false
	return true


## Every light id -> shines (for VoxelLighting.set_electric).
func states(mains: bool, furniture_ok := Callable()) -> Dictionary:
	var out := {}
	for l in HousePlan.LIGHTS:
		out[l["id"]] = shines(l["id"], mains, furniture_ok)
	return out


func toggle_light(id: String) -> bool:
	if lights.has(id):
		lights[id] = not lights[id]
	return lights.get(id, false)


func toggle_room(room: String) -> bool:
	if rooms.has(room):
		rooms[room] = not rooms[room]
	return rooms.get(room, false)


## Dev: every light and room switch on or off.
func set_all(on: bool) -> void:
	for id in lights:
		lights[id] = on
	for r in rooms:
		rooms[r] = on


## "[E] Turn the lamp off" etc. for a reachable light, "" for the others.
static func light_prompt(id: String, on: bool) -> String:
	var l := light_def(id)
	if l.is_empty() or not REACHABLE.has(l["kind"]):
		return ""
	return REACHABLE[l["kind"]] % ("off" if on else "on")
