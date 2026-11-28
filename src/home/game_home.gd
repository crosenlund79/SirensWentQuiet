extends Node
## Experiment 004 "Make This House a Home" in the survival game (H's scope):
## the northern atmosphere, the electrical lights and the household
## interactions, wired into the running game. Created by SurvivalGame in
## _assemble() as `home` (like game_map.gd and game_dev.gd); the game merges
## `interactables()` into the interaction finder.
##
## - Atmosphere: the far-north palette (VoxelLighting.set_northern), the
##   northern lights and falling snow (NorthernSky), snow on outdoor props
##   (PropMaterials' `snow`), the fireplace (Fireplace; lit on a new game).
## - Electricity (HomeElectrical): fixture meshes for HousePlan.LIGHTS, a wall
##   switch per room ("[E] Lights on/off"), hand switches on the reachable
##   lamps. A light shines only if its switch, its room switch and the fuse
##   box's mains are on (HouseWorld.fuse_box() / power_changed when the world
##   has them; without that API the mains count as always on).
## - Household: "[E] Drink from the sink", "[E] Eat from the fridge"
##   (Household, gated by HouseWorld.furniture_ok when it exists).
## - Sprint: VoxelPlayer sprints on Shift; this drains energy while it does.
## - Saving: GameState.home = {"fire", "lights", "rooms"} (optional field).
## - F10 "Home" section: dev_toggle_fire, dev_all_lights, dev_force_aurora,
##   dev_night, dev_snow.

const CEILING := 2.6
const SPRINT_DRAIN := 0.12             ## extra energy per real second of sprinting
const SPRINT_MIN_ENERGY := 5.0
const RELIGHT_COST := {"wood": 1}
const REFRESH := 0.25                  ## seconds between electrical checks (signals refresh at once)
## A wall switch per room, near its door, on the room side: plan position and
## the direction its front faces (into the room).
const SWITCHES := {
	"bedroom": {"pos": Vector2(4.9, 2.65), "facing": "W"},
	"bathroom": {"pos": Vector2(5.55, 3.9), "facing": "N"},
	"living": {"pos": Vector2(3.5, 8.85), "facing": "N"},
	"utility": {"pos": Vector2(10.1, 8.45), "facing": "E"},
	"kitchen": {"pos": Vector2(8.1, 3.45), "facing": "E"},
}
const FACING_DIR := {"N": Vector2(0, -1), "S": Vector2(0, 1), "E": Vector2(1, 0), "W": Vector2(-1, 0)}

var game: Node                         ## SurvivalGame
var state: GameState
var world: HouseWorld
var electrical: HomeElectrical
var sky: NorthernSky
var fireplace: Fireplace
var fixtures := {}                     ## light id -> Node3D (PropKit fixture)
var switches := {}                     ## room id -> WallSwitch
var lamps := {}                        ## light id -> LampSwitch (reachable lamps)
var sink: KitchenSpot
var fridge: KitchenSpot
var last_text := ""                    ## the last message (tests)
var _states := {}
var _mains := true
var _refresh_t := 0.0
var _root: Node3D
var _place_at := Vector2.INF           ## --player-at=x,z (screenshots): placed on the first frame
var _fallen := {}                      ## Refinement 01 (S): light id -> true: its ceiling or wall is gone


func setup(g: Node) -> void:
	game = g
	state = g.state
	world = g.world
	electrical = HomeElectrical.from_dict(state.home)
	_root = Node3D.new()
	_root.name = "HomeNodes"
	game.add_child(_root)
	game.lighting.set_northern(true)
	PropMaterials.kit().set_shader_parameter("snow", 1.0)
	sky = NorthernSky.new()
	sky.name = "NorthernSky"
	sky.setup(game.camera, game.lighting, game.boundary, int(state.run.get("seed", 0)))
	_root.add_child(sky)
	fireplace = Fireplace.new()
	fireplace.name = "Fireplace"
	fireplace.owner_helper = self
	var fire = state.home.get("fire", true)
	fireplace.lit = not (typeof(fire) == TYPE_BOOL and not fire)
	_root.add_child(fireplace)
	_claim_nav(Fireplace.RECT)
	_build_fixtures()
	_build_kitchen()
	if world.has_signal("power_changed"):
		world.connect("power_changed", _on_power_changed)
	if world.has_signal("structure_changed"):
		world.structure_changed.connect(_on_power_changed)
	if world.has_signal("object_destroyed"):
		world.object_destroyed.connect(_on_power_changed)
	refresh_power(true)
	_save()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--player-at="):
			var v := a.trim_prefix("--player-at=").split(",")
			if v.size() == 2:
				_place_at = Vector2(float(v[0]), float(v[1]))


func _exit_tree() -> void:
	PropMaterials.kit().set_shader_parameter("snow", 0.0)    # the galleries and demos stay snow-free


## Interactables this helper adds to the world's (merged by the game).
func interactables() -> Array:
	var out := []
	if fireplace != null:
		out.append(fireplace)
	for r in switches:
		if (switches[r] as Node3D).visible:      # Refinement 01 (S): fallen with its wall
			out.append(switches[r])
	for id in lamps:
		if (lamps[id] as Node3D).visible:
			out.append(lamps[id])
	if sink != null:
		out.append(sink)
	if fridge != null and game.get("storage") == null:     # Exp 005 (F): E at the fridge opens its storage instead
		out.append(fridge)
	return out


# --- the fireplace -------------------------------------------------------------------

## [E] at the fireplace: put it out, or light it (costs RELIGHT_COST).
func on_fireplace() -> void:
	if fireplace.lit:
		fireplace.set_lit(false)
		_say("You put out the fire.", "info")
	else:
		if not state.can_pay(RELIGHT_COST):
			_say("You need a plank to light the fire.", "warn")
			return
		state.pay(RELIGHT_COST)
		fireplace.set_lit(true)
		_say("The fire catches. (-1 plank)", "good")
	Sfx.ui("ui/click")
	_save()


# --- electricity ---------------------------------------------------------------------

## True if a fuse box exists and its mains are on (always true without that API).
func mains_on() -> bool:
	if world == null or not world.has_method("fuse_box"):
		return true
	var fb = world.call("fuse_box")
	if fb == null or not is_instance_valid(fb):
		return false
	var v = fb.get("mains_on")
	return v == null or bool(v)


func _furniture_ok(id: String) -> bool:
	if world != null and world.has_method("furniture_ok"):
		return bool(world.call("furniture_ok", id))
	return true


func on_room_switch(room: String) -> void:
	var on := electrical.toggle_room(room)
	Sfx.play_first(["home/light_switch", "ui/click"])   # Exp 005 (A): a recorded switch when there is one
	if on and not mains_on():
		_say("Nothing. There's no power.", "warn")
	refresh_power(true)
	_save()


func on_lamp(id: String) -> void:
	var on := electrical.toggle_light(id)
	Sfx.play_first(["home/light_switch", "ui/click"])   # Exp 005 (A)
	if on and not electrical.shines(id, mains_on(), _furniture_ok):
		_say("Nothing. There's no power." if not mains_on() else "The switch on the wall is off.", "warn")
	refresh_power(true)
	_save()


## Recomputes which lights shine and pushes it to the practicals and fixtures.
func refresh_power(force := false) -> void:
	_mains = mains_on()
	var s := electrical.states(_mains, _furniture_ok)
	var fell := _apply_mounts(s)       # Refinement 01 (S): lights and switches fall with their ceiling or wall
	if not force and s == _states and not fell:
		return
	_states = s
	game.lighting.set_electric(s)
	for id in fixtures:
		var n: Node3D = fixtures[id]
		PropKit.set_lit(n, 1.0 if s.get(id, false) else 0.0)
		var need: String = HomeElectrical.NEEDS_FURNITURE.get(id, "")
		n.visible = (need == "" or _furniture_ok(need)) and not _fallen.has(id)
		if lamps.has(id):
			(lamps[id] as Node3D).visible = n.visible
	for r in switches:
		PropKit.set_lit((switches[r] as WallSwitch).plate, 1.0 if (_mains and electrical.rooms.get(r, false)) else 0.0)


func _on_power_changed(_a = null, _b = null) -> void:
	refresh_power()


func _build_fixtures() -> void:
	for l in HousePlan.LIGHTS:
		var id: String = l["id"]
		var p: Vector2 = l["pos"]
		var n: Node3D = null
		match str(l["kind"]):
			"ceiling":
				n = PropKit.make("ceiling_light", Vector3(0.42, 0.2, 0.42), {"seed": 3})
				n.position = Vector3(p.x, CEILING - 0.2, p.y)
			"hood":
				n = PropKit.make("range_hood", Vector3(0.75, 1.0, 0.5), {"facing": "S", "seed": 3})
				n.position = Vector3(p.x, l["height"] - 0.05, 0.4)
			"table_lamp":
				n = PropKit.make("table_lamp", Vector3(0.26, 0.42, 0.26), {"seed": 3})
				n.position = Vector3(p.x, 0.55, p.y)
			"bare_bulb":
				n = PropKit.make("bare_bulb", Vector3(0.12, 0.25, 0.12), {"seed": 3})
				n.position = Vector3(p.x, CEILING - 0.25, p.y)
			"floor_lamp":
				# the furniture lamp exists; this is its bulb, glowing inside the shade
				n = PropKit.make("bulb", Vector3(0.11, 0.12, 0.11), {"seed": 3})
				n.position = Vector3(p.x, l["height"] - 0.14, p.y)
		if n == null:
			continue
		n.name = "Fixture_" + id
		_root.add_child(n)
		fixtures[id] = n
		if HomeElectrical.REACHABLE.has(l["kind"]):
			var ls := LampSwitch.new()
			ls.name = "Lamp_" + id
			ls.helper = self
			ls.light_id = id
			_root.add_child(ls)
			ls.global_position = Vector3(p.x, 0.0, p.y)
			lamps[id] = ls
	for room in SWITCHES:
		if not electrical.rooms.has(room):
			continue
		var spec: Dictionary = SWITCHES[room]
		var at: Vector2 = spec["pos"] + FACING_DIR[spec["facing"]] * 0.012
		var ws := WallSwitch.new()
		ws.name = "Switch_" + room
		ws.helper = self
		ws.room = room
		_root.add_child(ws)
		ws.global_position = Vector3(at.x, 0.0, at.y)
		ws.plate = PropKit.make("light_switch", Vector3.ZERO, {"facing": spec["facing"], "seed": 1})
		ws.plate.position = Vector3(0, 1.1, 0)
		ws.add_child(ws.plate)
		switches[room] = ws


# --- the kitchen ---------------------------------------------------------------------

func _build_kitchen() -> void:
	for f in HousePlan.FURNITURE:
		if f["id"] == "sink_counter" or f["id"] == "fridge":
			var r: Rect2 = f["rect"]
			var k := KitchenSpot.new()
			k.name = "Kitchen_" + str(f["id"])
			k.helper = self
			k.what = str(f["id"])
			_root.add_child(k)
			k.global_position = Vector3(r.get_center().x, 0.0, r.end.y + 0.15)
			if f["id"] == "fridge":
				fridge = k
			else:
				sink = k


func on_sink() -> void:
	var r := Household.drink_from_sink(state, _furniture_ok("sink_counter"))
	if r["ok"]:
		Sfx.play("player/drink")
		if game.has_method("_advance_clock"):
			game.call("_advance_clock", Household.SINK_MINUTES)
	_say(str(r["text"]), "good" if r["ok"] else "warn")


func on_fridge() -> void:
	var r := Household.eat_from_fridge(state, _furniture_ok("fridge"))
	if r["ok"]:
		Sfx.play("player/eat")
	_say(str(r["text"]), "good" if r["ok"] else "warn")


# --- the frame -----------------------------------------------------------------------

func _process(delta: float) -> void:
	if game == null or state == null:
		return
	if _place_at != Vector2.INF:
		game.debug_teleport_player(_place_at)
		game.camera.snap()
		_place_at = Vector2.INF
	var n := state.night_amount()
	sky.tick(state.total_minutes, n)
	fireplace.set_night(n)
	if world.yard != null:
		fireplace.set_roof_visible(world.yard.roof_visible())
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = REFRESH
		refresh_power()
	var p: VoxelPlayer = game.player
	p.sprint_allowed = state.energy > SPRINT_MIN_ENERGY
	if p.sprinting and not state.dead and not get_tree().paused:
		state.energy -= SPRINT_DRAIN * delta


# --- saving --------------------------------------------------------------------------

func _save() -> void:
	var d := electrical.to_dict()
	d["fire"] = fireplace.lit if fireplace != null else true
	if state.home.has("seen"):
		d["seen"] = state.home["seen"]     # Exp 012 (V): the fog of war's memory lives here too
	state.home = d


func _say(text: String, kind: String) -> void:
	if text == "":
		return
	last_text = text
	if game.has_method("toast"):
		game.toast(text, kind)


## The fireplace stands where the plan has no furniture: its footprint is
## solid for navigation, and its footprint plus the space in front is kept
## clear of construction (Refinement 01: HouseWorld.add_static_blocker).
func _claim_nav(rect: Rect2) -> void:
	if world == null or world.nav == null:
		return
	if world.has_method("add_static_blocker"):
		world.add_static_blocker(rect, Fireplace.RESERVE)


# --- F10 (the dev menu's "Home" section) -----------------------------------------------

func dev_toggle_fire() -> String:
	fireplace.set_lit(not fireplace.lit)
	_save()
	return "Fireplace %s" % ("lit" if fireplace.lit else "out")


func dev_all_lights(on: bool) -> String:
	electrical.set_all(on)
	refresh_power(true)
	_save()
	return "All lights %s%s" % ["on" if on else "off", "" if mains_on() or not on else " (but no power)"]


func dev_force_aurora() -> String:
	sky.force_tonight()
	return "Northern lights tonight"


func dev_night() -> String:
	if game.has_method("dev_skip_to"):
		game.dev_skip_to(23.0)
	return "23:00"


func dev_snow() -> String:
	sky.set_snow(not sky.snow_on)
	return "Snowfall %s" % ("on" if sky.snow_on else "off")


func info() -> String:
	var lit := []
	for id in _states:
		if _states[id]:
			lit.append(id)
	return "Home: fire %s · mains %s · lights on %s · aurora tonight %.2f (now %.2f) · snow %s" % [
		"lit" if fireplace.lit else "out", "on" if _mains else "off", lit, sky.tonight, sky.shown, "on" if sky.snow_on else "off"]


# --- interactables ---------------------------------------------------------------------

## A room's wall switch: "[E] Lights off" / "[E] Lights on".
class WallSwitch extends Node3D:
	var helper: Object
	var room := ""
	var plate: Node3D

	func interact_prompt() -> String:
		var on: bool = helper.electrical.rooms.get(room, false)
		return "[E] Lights %s" % ("off" if on else "on")

	func interact(_g: Node) -> void:
		helper.on_room_switch(room)


## The hand switch of a reachable lamp ("[E] Turn the lamp off").
class LampSwitch extends Node3D:
	var helper: Object
	var light_id := ""

	func interact_prompt() -> String:
		return HomeElectrical.light_prompt(light_id, helper.electrical.lights.get(light_id, false))

	func interact(_g: Node) -> void:
		helper.on_lamp(light_id)


## The kitchen sink ("[E] Drink from the sink") or the fridge ("[E] Eat from the fridge").
class KitchenSpot extends Node3D:
	var helper: Object
	var what := ""

	func interact_prompt() -> String:
		return "[E] Eat from the fridge" if what == "fridge" else "[E] Drink from the sink"

	func interact(_g: Node) -> void:
		if what == "fridge":
			helper.on_fridge()
		else:
			helper.on_sink()


# --- Refinement 01 (S): fixtures need their ceiling or wall --------------------------------

## Ceiling lights and the bare bulb fall with a collapsed roof, the range
## hood and the wall switches with their wall section (HouseWorld.ceiling_at /
## wall_at): fallen lights are dark and hidden, fallen switches hidden.
func _apply_mounts(s: Dictionary) -> bool:
	if not world.has_method("wall_at"):
		return false
	var before := _fallen.size()
	_fallen.clear()
	for l in HousePlan.LIGHTS:
		var id: String = l["id"]
		var p: Vector2 = l["pos"]
		var ok := true
		match str(l["kind"]):
			"ceiling", "bare_bulb":
				ok = world.ceiling_at(p)
			"hood":
				ok = world.wall_at(Vector2(p.x, 0.1), 2.0, 0.3)
		if not ok:
			_fallen[id] = true
			s[id] = false
	for r in switches:
		(switches[r] as Node3D).visible = world.wall_at(SWITCHES[r]["pos"], 1.1)
	return _fallen.size() != before          # something fell (or a repaired wall took it back)
