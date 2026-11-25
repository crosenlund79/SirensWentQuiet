extends Node
## Exp 007 (T): visible travel and the home <-> POI flow. SurvivalGame creates
## it in _assemble() as `travel` (the game_*.gd pattern), at home and at a POI.
##
## The loop (the user's §2-3):
## 1. Pick a known place on the region map (M, the dining-table map, or E at
##    the fog edge), see the travel panel, press Travel (RegionMapScreen
##    `travel_requested` -> depart()).
## 2. depart(): the checkpoint autosave "departed" (an ordinary home save),
##    the home snapshot (the same RunSave dictionary: all storeys, objects,
##    furniture...), the travel animation on the map (a few real seconds),
##    the car's fuel can, then a scene change to the game scene in POI mode
##    with GameLaunch.site = id and GameLaunch.carry = {"state", "home",
##    "travel"}.
## 3. At the POI (after the game's site_ready, arrive() -> arrive_at_site()): the road's
##    minutes pass on the clock, the region records the visit (visits, last
##    day, discovery), Eli stands at the POI's entry, autosave "arrived".
## 4. An exit's "[E] Leave for home" (P's, or the test site's) calls
##    game.leave_site() -> leave_for_home(): the return animation, the road's
##    minutes, the car's cargo box (P's poi.take_cargo()), then a scene change
##    home with {"state", "home", "travel", "cargo"}.
## 5. Home (arrive() -> arrive_home()): the house is the snapshot (the game loaded it),
##    the attacks recorded while away are resolved (OffscreenHome), the car's
##    cargo goes into the household (leftovers into a pile by the car), Eli
##    stands at the fog edge, autosave "returned".
## What Eli brings back is what he carries (the GameState travels with him)
## plus the cargo: no second loot roll.
##
## Saves: see run_save.gd ("site"). The travel animation itself is never
## saved: quitting during it resumes at the last checkpoint ("departed" at
## home on the way out, the POI on the way back).
##
## F10 "Travel" (dev_*): instant travel to any place, instant return home,
## fuel, car repair, skip the animation.

const RunSave := preload("res://src/game/run_save.gd")
const NEAR_ENEMY := 9.0                 ## metres: an enemy this close keeps Eli from leaving a POI

static var skip_animation := false      ## F10 toggle and tests: no map animation (the time still passes)

var game: Node                          ## SurvivalGame
var info := {}                          ## this trip: {"to"/"from", "car", "minutes", "depart_at", "leg"}
var home_snapshot := {}                 ## at a POI: the home's save dictionary carried along
var busy := false                       ## a departure or return is under way
var last_report := {}                   ## OffscreenHome.resolve() on the last return (tests)
var last_cargo := {}                    ## cargo moved into the household on the last return (tests)
var last_depart := ""                   ## the last place set out for (tests)


func setup(g: Node) -> void:
	game = g
	process_mode = Node.PROCESS_MODE_ALWAYS
	var c: Dictionary = game.get("_carry") if typeof(game.get("_carry")) == TYPE_DICTIONARY else {}
	info = (c.get("travel", {}) as Dictionary).duplicate(true) if typeof(c.get("travel")) == TYPE_DICTIONARY else {}
	if not game.is_home():
		home_snapshot = (c.get("home", {}) as Dictionary) if typeof(c.get("home")) == TYPE_DICTIONARY else {}


func by_car() -> bool:
	return bool(info.get("car", false))


# --- leaving home -------------------------------------------------------------------------

## Sets out from home for `id` (the map's Travel button, F10). Returns "" or
## why not. `instant` (F10): no animation and no time on the road.
func depart(id: String, car := false, instant := false) -> String:
	if busy:
		return "busy"
	if not game.is_home():
		return _refuse("You're already away from home.")
	var s: GameState = game.state
	var why := TravelRules.block_reason(s, id, car)
	if why == "":
		why = game.travel_block_reason()
	if why != "":
		return _refuse(why)
	busy = true
	last_depart = id
	var minutes := 0 if instant else TravelRules.minutes(id, car)
	game._autosave("departed")              # the checkpoint: quitting during the animation resumes here
	var snap: Dictionary = game.compose_home_save()
	var t0 := s.total_minutes
	game._set_modal("travel", true)
	Sfx.play_first(["travel/car_start", "car/start"] if car else ["travel/depart", "ui/open"])
	if not instant and not skip_animation:
		await game.map.play_travel(id, car, true, TravelRules.anim_seconds(minutes, car), t0, minutes)
	if car and not s.cheats.get("unlimited", false):
		s.inventory.remove("fuel", TravelRules.fuel_needed(true))
	OffscreenHome.begin(s)
	GameLaunch.site = id
	GameLaunch.mode = "carry"
	GameLaunch.carry = {"state": s.to_dict(), "home": snap,
		"travel": {"to": id, "car": car, "minutes": minutes, "depart_at": t0, "leg": "out"}}
	busy = false
	game.change_scene_to_site()
	return ""


func _refuse(why: String) -> String:
	game.toast(why, "warn")
	return why


# --- at the POI ---------------------------------------------------------------------------

## The game calls this after site_ready when the scene came by travel.
func arrive(carry: Dictionary) -> void:
	if game.is_home():
		var cargo: Variant = carry.get("cargo", {})
		arrive_home(cargo if typeof(cargo) == TYPE_DICTIONARY else {})
	else:
		arrive_at_site()


## At the POI (mode "carry"): the road's time, the visit, autosave "arrived".
func arrive_at_site() -> void:
	var s: GameState = game.state
	var id: String = game.site_id()
	OffscreenHome.begin(s)
	var mins := float(info.get("minutes", 0))
	if mins > 0.0:
		game._advance_clock(mins)           # on the road; attacks at home are recorded offscreen
	if s.dead:
		return
	s.region.apply_result({"id": "visit:%s:%d" % [id, int(s.total_minutes)], "location": id, "day": s.day()})
	game.toast("%s. Look around, and leave through an exit when you're done." % RegionLocations.name_of(id), "info")
	game._autosave("arrived")


## "[E] Leave for home" at a POI exit (game.leave_site()). Returns "" or why not.
func leave_for_home(instant := false) -> String:
	if busy:
		return "busy"
	if game.is_home():
		return _refuse("You're already home.")
	var why: String = game.travel_block_reason(true)
	if why != "":
		return _refuse(why)
	busy = true
	var s: GameState = game.state
	var id: String = game.site_id()
	var car := by_car()
	var minutes := 0 if instant else TravelRules.minutes(id, car)
	var cargo := {}
	var poi: Variant = game.get("poi")
	if poi is Object and is_instance_valid(poi) and poi.has_method("take_cargo"):
		var c: Variant = poi.take_cargo()
		cargo = c if typeof(c) == TYPE_DICTIONARY else {}
	var t0 := s.total_minutes
	game._set_modal("travel", true)
	Sfx.play_first(["travel/car_start", "car/start"] if car else ["travel/depart", "ui/open"])
	if not instant and not skip_animation:
		await game.map.play_travel(id, car, false, TravelRules.anim_seconds(minutes, car), t0, minutes)
	if minutes > 0:
		game._advance_clock(float(minutes))
	if s.dead:
		busy = false
		return "dead"
	GameLaunch.site = "home"
	GameLaunch.mode = "carry"
	GameLaunch.carry = {"state": s.to_dict(), "home": home_with_director(),
		"travel": {"from": id, "car": car, "minutes": minutes, "depart_at": t0, "leg": "back"}, "cargo": cargo}
	busy = false
	game.change_scene_to_site()
	return ""


## The carried home snapshot with the director's straggler bookkeeping as it
## is now (stragglers recorded offscreen count as done).
func home_with_director() -> Dictionary:
	var h := home_snapshot.duplicate(true)
	var g: Dictionary = h.get("game", {}) if typeof(h.get("game")) == TYPE_DICTIONARY else {}
	var d: Dictionary = g.get("director", {}) if typeof(g.get("director")) == TYPE_DICTIONARY else {}
	d["stragglers_done"] = game._stragglers_done.keys()
	g["director"] = d
	h["game"] = g
	return h


## The save while at a POI (RunSave layout plus "site"): "world" and "game"
## are the home snapshot (so an older build loads the home), "site" holds the
## place, Eli's position there, this trip and the POI helper's state.
func compose_site_save() -> Dictionary:
	var s: GameState = game.state
	var h := home_with_director()
	var p: Vector3 = game.player.global_position
	var site := {"id": game.site_id(), "player": {"pos": [p.x, p.z], "yaw": game.player.rig.rotation.y},
		"travel": info.duplicate(true), "camera_turns": game.camera.turns}
	var poi: Variant = game.get("poi")
	if poi is Object and is_instance_valid(poi) and poi.has_method("save_state"):
		var st: Variant = poi.save_state()
		if typeof(st) == TYPE_DICTIONARY:
			site["poi"] = st
	var summary := RunSave.summary_of(s)
	summary["site"] = RegionLocations.name_of(game.site_id())
	summary["text"] = "%s · %s" % [UiTheme.day_time_text(s.day(), s.clock_text()), summary["site"]]     # the main menu's Continue
	return {"summary": summary, "state": s.to_dict(), "world": h.get("world", {}), "game": h.get("game", {}), "site": site}


## Gives the POI helper its saved state back (Continue at a POI).
func restore_poi(d: Variant) -> void:
	var poi: Variant = game.get("poi")
	if typeof(d) == TYPE_DICTIONARY and not (d as Dictionary).is_empty() and poi is Object and is_instance_valid(poi) and poi.has_method("load_state"):
		poi.load_state(d)


# --- back home ----------------------------------------------------------------------------

## Home again, restored from the snapshot (mode "carry"): resolve what happened
## while away, unload the car, report, autosave "returned".
func arrive_home(cargo: Dictionary) -> void:
	var s: GameState = game.state
	last_report = OffscreenHome.resolve(game.world, s, int(s.run.get("seed", 0)) * 13 + int(s.total_minutes))
	OffscreenHome.finish(s)
	last_cargo = _unload(cargo)
	var where := RegionLocations.name_of(str(info.get("from", "")))
	game.toast("Back home from %s, %s." % [where, s.clock_text()] if where != "" else "Back home.", "good")
	if not last_cargo.is_empty():
		game.toast("Unloaded the car: %s." % ExpeditionData.items_text(last_cargo), "good")
	var lines: Array = last_report.get("lines", [])
	if int(last_report.get("attacks", 0)) > 0:
		game.toast("While you were away: " + " ".join(lines), "bad" if int(last_report.get("strikes", 0)) > 0 else "warn")
	elif not lines.is_empty():
		game.toast(" ".join(lines), "info")
	for l in lines:
		s._log("While away: " + str(l))
	GameLaunch.carry = {}
	game._autosave("returned")


## The car's cargo into the household: what fits into the inventory, the rest
## into a loot pile beside the car. Returns {item: n} moved in.
func _unload(cargo: Dictionary) -> Dictionary:
	var s: GameState = game.state
	var moved := {}
	var left := {}
	for id in cargo:
		var n := Inventory.to_count(cargo[id])
		if n <= 0 or not Items.has(id):
			continue
		var k := s.inventory.add(id, n)
		if k > 0:
			moved[str(id)] = k
		if n > k:
			left[str(id)] = n - k
	if not left.is_empty() and game.world != null:
		var at := Vector2(15.4, 10.7)
		var car: Variant = game.get("car")
		if car is Object and is_instance_valid(car) and "rect" in car:
			var r: Rect2 = car.rect
			at = Vector2(r.position.x - 0.6, r.get_center().y)
		game.world.drop_loot(at, left)
		for id in left:
			moved[id] = int(moved.get(id, 0)) + int(left[id])
	return moved


# --- developer tools (F10 "Travel") -----------------------------------------------------

## Instantly to a place (no animation, no time on the road). From a POI, via home.
func dev_travel_to(id: String) -> String:
	if not RegionLocations.has(id):
		return "Unknown place."
	if not game.is_home():
		return "Return home first (F10: Return home)."
	game.state.region.discover(id)
	var why := await depart(id, false, true)
	return "Travelling to %s" % RegionLocations.name_of(id) if why == "" else why


func dev_return_home() -> String:
	if game.is_home():
		return "Already home."
	game.debug_kill_enemies()
	var why := await leave_for_home(true)
	return "Going home" if why == "" else why


func dev_give_fuel() -> String:
	game.state.inventory.add("fuel", 3)
	return "+3 fuel cans (%d)" % game.state.inventory.count("fuel")


func dev_repair_car() -> String:
	game.state.car_repaired = true
	game.state.changed.emit()
	return "The car runs"


func dev_toggle_skip() -> String:
	skip_animation = not skip_animation
	return "Travel animation %s" % ("skipped" if skip_animation else "shown")


func info_text() -> String:
	var t := "Site: %s" % ("home" if game.is_home() else RegionLocations.name_of(game.site_id()))
	if not game.is_home():
		t += " (%s)" % ("by car" if by_car() else "on foot")
	var n := OffscreenHome.events(game.state).size()
	if n > 0:
		t += " · %d thing%s happened at home" % [n, "" if n == 1 else "s"]
	return t
