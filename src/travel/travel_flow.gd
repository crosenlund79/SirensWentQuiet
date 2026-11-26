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
## 3. At the POI (agent P's PoiWorld and helper; after the game's
##    site_ready, arrive() -> arrive_at_site()): the road's minutes pass on
##    the clock, the place is known, 30 % to spot a new place nearby
##    (TravelRules), Eli stands at world.entry_point(), autosave "arrived".
##    P starts the visit (pack, boot) and counts it when it ends.
## 4. An exit's "[E] Leave for home": agent P's helper calls leave_poi() ->
##    leave_for_home(): once its checks pass it ends the visit
##    (game.poi.finish(): the place's stock and visit count, GameLaunch.carry
##    ["poi"] = {site, by_car, cargo, pack, left}), then the return
##    animation, the road's minutes, then a scene change home with
##    {"state", "home", "travel", "cargo", "poi"}.
##    Every exit works at any time (P's rule), enemies or not.
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
## Exp 008 (T): chains. At a POI, M opens the map from THERE (times, routes
## and the daylight check from where Eli is; "Your house" is always on the
## list) and Travel goes straight on: travel_on(id) (E at an exit still goes
## home: "[E] Leave for home · M: travel on"). Each leg:
## - the visit here ends once (game.poi.finish() -> PoiState.finish_visit),
##   so stock, visit counts and encounter seeds stay per place;
## - the rules of TravelRules (header): the road time of the leg
##   (minutes_between), the mode he came with (the car stays with him), fuel
##   (leaving home by car 1 can for the whole trip, each further stop by car
##   1 more, home is paid, walking free), the gear a place needs;
## - GameLaunch.carry = {"state", "home": the SAME home snapshot, "travel":
##   {"to", "from", "car", "minutes", "depart_at", "leg": "on", "stops":
##   [the places before this one]}, "cargo": the car's boot, "pack": what he
##   took on the earlier stops and still carries}. On arrival the boot and
##   the pack go into the new visit's record (the boot stays the boot, the
##   pack keeps counting toward the pack limit); nothing goes into the
##   household until home. The offscreen ledger (state.run["away"]) stays
##   open over every leg and is resolved once at home;
## - discovery on the way (TravelRules.roll_discovery) on every arrival.
## A save at the second POI stores that place, the chain ("travel") and the
## carried home; Continue resumes there and the chain goes on.
## Departures and arrivals show a short title card (travel_card.gd:
## "Hardware Store" / "Day 3, 10:42"); Space skips. Not with skip_animation.
##
## F10 "Travel" (dev_*): instant travel to any place (from a POI, straight
## on), instant return home, fuel, car repair, skip the animation.
##
## Exp 009 (D): an overrun place (DailySites) is refused like any blocked
## place (TravelRules); F10 travel makes it available for the day first.
## F10 test sites ("gen:<archetype>:<seed>", src/poigen/dev_poigen.gd) go
## through dev_travel_to too: no discovery, no save while there, and
## DailySites.forget_test clears their record when Eli leaves.

const RunSave := preload("res://src/game/run_save.gd")
const TravelCard := preload("res://src/travel/travel_card.gd")

static var skip_animation := false      ## F10 toggle and tests: no map animation (the time still passes)

var game: Node                          ## SurvivalGame
var info := {}                          ## this leg: {"to"/"from", "car", "minutes", "depart_at", "leg", "stops"}
var home_snapshot := {}                 ## at a POI: the home's save dictionary carried along
var busy := false                       ## a departure or return is under way
var last_report := {}                   ## OffscreenHome.resolve() on the last return (tests)
var last_cargo := {}                    ## cargo moved into the household on the last return (tests)
var last_depart := ""                   ## the last place set out for (tests)
var brought := {}                       ## Exp 008 (T): {"cargo", "pack"} brought along from the earlier stops (tests)
var card: Node                          ## Exp 008 (T): the last title card shown (tests)


func setup(g: Node) -> void:
	game = g
	process_mode = Node.PROCESS_MODE_ALWAYS
	var c: Dictionary = game.get("_carry") if typeof(game.get("_carry")) == TYPE_DICTIONARY else {}
	info = (c.get("travel", {}) as Dictionary).duplicate(true) if typeof(c.get("travel")) == TYPE_DICTIONARY else {}
	if not game.is_home():
		home_snapshot = (c.get("home", {}) as Dictionary) if typeof(c.get("home")) == TYPE_DICTIONARY else {}


func by_car() -> bool:
	return bool(info.get("car", false))


## Exp 008 (T): the places this trip went to before this one (a chain), in order.
func stops() -> Array:
	var out := []
	var v: Variant = info.get("stops", [])
	if typeof(v) == TYPE_ARRAY:
		for x in v:
			if typeof(x) == TYPE_STRING and RegionLocations.has(x):
				out.append(x)
	return out


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
		_departure_card(TravelRules.HOME, id, car, t0)
		await game.map.play_leg(TravelRules.HOME, id, car, TravelRules.anim_seconds(minutes, car), t0, minutes)
	if car and not s.cheats.get("unlimited", false):
		s.inventory.remove("fuel", TravelRules.leg_fuel(TravelRules.HOME, id, true))
	OffscreenHome.begin(s)
	GameLaunch.site = id
	GameLaunch.mode = "carry"
	GameLaunch.carry = {"state": s.to_dict(), "home": snap,
		"travel": {"to": id, "car": car, "minutes": minutes, "depart_at": t0, "leg": "out", "stops": []}}
	busy = false
	game.change_scene_to_site()
	return ""


func _refuse(why: String) -> String:
	game.toast(why, "warn")
	return why


# --- on from a POI (Exp 008) -------------------------------------------------------------

## From a POI straight on to another known place (the map at a POI), or home
## ("home": leave_for_home). See the header for the chain's rules. Returns ""
## or why not. `instant` (F10): no animation and no time on the road.
func travel_on(id: String, car := false, instant := false) -> String:
	if id == TravelRules.HOME:
		return await leave_for_home(instant)
	if game.is_home():
		return await depart(id, car, instant)
	if busy:
		return "busy"
	var s: GameState = game.state
	var from: String = game.site_id()
	var why := TravelRules.leg_block_reason(s, from, id, car, by_car())
	if why == "":
		why = game.travel_block_reason(true)    # every exit works at any time: enemies here don't hold Eli
	if why != "":
		return _refuse(why)
	busy = true
	last_depart = id
	var minutes := 0 if instant else TravelRules.minutes_between(from, id, car)
	game._autosave("departed")              # quitting on the road resumes here (skipped with enemies about)
	var fin := _end_visit()                 # once, before the next leg: this place's stock and visit count
	DailySites.forget_test(s, from)         # Exp 009 (D): a test site leaves nothing in the region
	var cargo: Dictionary = (fin.get("cargo", {}) as Dictionary).duplicate() if typeof(fin.get("cargo")) == TYPE_DICTIONARY else {}
	var pack := _still_carried(fin.get("pack", {}) if typeof(fin.get("pack")) == TYPE_DICTIONARY else {})
	var t0 := s.total_minutes
	game._set_modal("travel", true)
	Sfx.play_first(["travel/car_start", "car/start"] if car else ["travel/depart", "ui/open"])
	if not instant and not skip_animation:
		_departure_card(from, id, car, t0)
		await game.map.play_leg(from, id, car, TravelRules.anim_seconds(minutes, car), t0, minutes)
	var fuel := TravelRules.leg_fuel(from, id, car)
	if fuel > 0 and not s.cheats.get("unlimited", false):
		s.inventory.remove("fuel", fuel)
	OffscreenHome.begin(s)                  # open since home; resolved once, at home
	GameLaunch.site = id
	GameLaunch.mode = "carry"
	GameLaunch.carry = {"state": s.to_dict(), "home": home_with_director(),
		"travel": {"to": id, "from": from, "car": car, "minutes": minutes, "depart_at": t0, "leg": "on", "stops": stops() + [from]},
		"cargo": cargo, "pack": pack}
	busy = false
	game.change_scene_to_site()
	return ""


## Ends the visit at this POI once (the POI helper's finish(), idempotent)
## and returns its result ({"cargo", "pack", ...}; {} without a helper).
func _end_visit() -> Dictionary:
	var poi: Variant = game.get("poi")
	if not (poi is Object and is_instance_valid(poi)):
		return {}
	if poi.has_method("cancel_action"):
		poi.cancel_action("")
	if not poi.has_method("finish"):
		return {}
	var f: Variant = poi.finish()          # the cargo left the inventory; the pack is still in it
	return f if typeof(f) == TYPE_DICTIONARY else {}


## What of a visit's pack Eli still carries (eaten or stowed, it's gone).
func _still_carried(pack: Dictionary) -> Dictionary:
	var out := {}
	for id in pack:
		var n := mini(Inventory.to_count(pack[id]), game.state.inventory.count(str(id)))
		if n > 0:
			out[str(id)] = n
	return out


## A later stop of a chain: the boot and what Eli took on the earlier stops
## go into this visit's record (the POI helper's live `cargo` and `pack`).
## Nothing goes into the household here.
func _bring_along(carry: Dictionary) -> void:
	brought = {}
	var poi: Variant = game.get("poi")
	if not (poi is Object and is_instance_valid(poi)):
		return
	var cargo: Variant = carry.get("cargo", {})
	var boot: Variant = poi.get("cargo")
	if typeof(cargo) == TYPE_DICTIONARY and typeof(boot) == TYPE_DICTIONARY and not (cargo as Dictionary).is_empty():
		for id in cargo:
			var n := Inventory.to_count(cargo[id])
			if n > 0 and Items.has(str(id)):
				boot[str(id)] = int(boot.get(str(id), 0)) + n
		brought["cargo"] = (cargo as Dictionary).duplicate()
	var pack: Variant = carry.get("pack", {})
	if typeof(pack) == TYPE_DICTIONARY and not (pack as Dictionary).is_empty() and poi.has_method("pack_add"):
		for id in pack:
			poi.pack_add(str(id), Inventory.to_count(pack[id]))
		brought["pack"] = (pack as Dictionary).duplicate()


# --- title cards (Exp 008) ----------------------------------------------------------------

## The departure's card over the map: "Setting out" / "Leaving Pine Woods".
func _departure_card(from: String, to: String, car: bool, total: float) -> void:
	var title := "Setting out" if from == TravelRules.HOME else "Leaving %s" % RegionLocations.name_of(from)
	var where := "home" if to == TravelRules.HOME else RegionLocations.name_of(to)
	_show_card(title, "%s  ·  %s to %s" % [TravelRules.day_clock(total), "by car" if car else "on foot", where], 0.8, 0.6, 0.5, false)


## The arrival's card, from black: "Hardware Store" / "Day 3, 10:42".
func _arrival_card(title: String, sub: String) -> void:
	if skip_animation or GameLaunch.mode != "carry":
		return
	_show_card(title, sub, 1.0, 0.75, 0.6, true)


func _show_card(title: String, sub: String, dim: float, hold: float, fade: float, skippable: bool) -> void:
	if card != null and is_instance_valid(card):
		card.queue_free()
	card = TravelCard.new()
	card.name = "TravelCard"
	card.skippable = skippable
	game.add_child(card)
	card.play(title, sub, dim, hold, fade)


# --- at the POI ---------------------------------------------------------------------------

## The game calls this after site_ready when the scene came by travel.
func arrive(carry: Dictionary) -> void:
	if game.is_home():
		var cargo: Variant = carry.get("cargo", {})
		arrive_home(cargo if typeof(cargo) == TYPE_DICTIONARY else {})
	else:
		arrive_at_site(carry)


## At the POI (mode "carry"): the road's time, the visit, autosave "arrived".
## Exp 008 (T): on a later stop of a chain, the boot and the pack come along.
func arrive_at_site(carry := {}) -> void:
	var s: GameState = game.state
	var id: String = game.site_id()
	OffscreenHome.begin(s)
	var mins := float(info.get("minutes", 0))
	if mins > 0.0:
		game._advance_clock(mins)           # on the road; attacks at home are recorded offscreen
	if s.dead:
		return
	_bring_along(carry)
	_arrival_card(RegionLocations.name_of(id), TravelRules.day_clock(s.total_minutes))
	if DailySites.is_test_id(id):           # Exp 009 (D): an F10 test site: no discovery, nothing recorded
		game.toast("%s. A generated test site: nothing here is saved." % RegionLocations.name_of(id), "info")
		return
	var found := TravelRules.roll_discovery(s, id, int(s.run.get("seed", 0)) * 7 + s.region.visits(id) * 131 + id.hash())
	var poi: Variant = game.get("poi")
	if poi is Object and is_instance_valid(poi) and poi.has_method("finish"):
		s.region.discover(id)                  # P counts the visit, the day and the stock when it ends
		if found != "":
			s.region.discover(found)
	else:
		var disc := [found] if found != "" else []
		s.region.apply_result({"id": "visit:%s:%d" % [id, int(s.total_minutes)], "location": id, "day": s.day(), "discovered": disc})
	if not (poi is Object and is_instance_valid(poi) and poi.has_method("finish")):
		game.toast("%s. Look around, and leave through an exit when you're done." % RegionLocations.name_of(id), "info")   # P greets with its own line
	if found != "":
		game.toast("On the way you spotted %s. It's on your map now." % RegionLocations.name_of(found), "good")
	game._autosave("arrived")


## The POI helper's "[E] Leave for home" calls this. Exp 008: the visit
## ends here (in leave_for_home), only once the departure is accepted.
func leave_poi() -> String:
	return await leave_for_home()


## Back home from a POI (leave_poi, game.leave_site(), the map, F10). Returns
## "" or why not. Every check comes before the visit ends (_end_visit), so a
## refusal leaves the visit running (it is counted once, when Eli does go).
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
	var fin := _end_visit()                 # P: ends the visit once (idempotent); the cargo left the inventory
	DailySites.forget_test(s, id)           # Exp 009 (D): a test site leaves nothing in the region
	var cargo: Dictionary = fin.get("cargo", {}) if typeof(fin.get("cargo")) == TYPE_DICTIONARY else {}
	var t0 := s.total_minutes
	game._set_modal("travel", true)
	Sfx.play_first(["travel/car_start", "car/start"] if car else ["travel/depart", "ui/open"])
	if not instant and not skip_animation:
		_departure_card(id, TravelRules.HOME, car, t0)
		await game.map.play_leg(id, TravelRules.HOME, car, TravelRules.anim_seconds(minutes, car), t0, minutes)
	if minutes > 0:
		game._advance_clock(float(minutes))
	if s.dead:
		busy = false
		return "dead"
	GameLaunch.site = "home"
	GameLaunch.mode = "carry"
	GameLaunch.carry = {"state": s.to_dict(), "home": home_with_director(),
		"travel": {"from": id, "car": car, "minutes": minutes, "depart_at": t0, "leg": "back", "stops": stops() + [id]},
		"cargo": cargo.duplicate(), "poi": fin}
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
	last_report = OffscreenHome.resolve(game.world, s, int(s.run.get("seed", 0)) * 13 + int(s.total_minutes), _home_worlds())
	OffscreenHome.finish(s)
	last_cargo = _unload(cargo)
	var where := _places_text(stops())
	if where == "" and RegionLocations.has(str(info.get("from", ""))):
		where = RegionLocations.name_of(str(info.get("from", "")))
	game.toast("Back home from %s, %s." % [where, s.clock_text()] if where != "" else "Back home.", "good")
	_arrival_card("Home", "%s%s" % [TravelRules.day_clock(s.total_minutes), "  ·  back from " + where if where != "" else ""])
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


## "Corner Store", "Corner Store and Public Library", "A, B and C".
static func _places_text(ids: Array) -> String:
	var names := []
	for id in ids:
		names.append(RegionLocations.name_of(str(id)))
	if names.size() <= 1:
		return "" if names.is_empty() else str(names[0])
	return ", ".join(names.slice(0, names.size() - 1)) + " and " + str(names[-1])


## Every storey of the house (the ground floor first), for the security
## module's turrets on any storey.
func _home_worlds() -> Array:
	var out: Array = [game.world]
	var l: Variant = game.get("levels")
	if l is Object and is_instance_valid(l) and l.has_method("storeys") and l.has_method("world_of"):
		for st in l.storeys():
			var w: Variant = l.world_of(st)
			if w is HouseWorld and not out.has(w):
				out.append(w)
	return out


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

## Instantly to a place (no animation, no time on the road). Exp 008: from a
## POI straight on (in the mode Eli came with).
func dev_travel_to(id: String) -> String:
	if not RegionLocations.has(id) and DailySites.parse_test_id(id).is_empty():
		return "Unknown place."
	if not game.is_home() and id == game.site_id():
		return "Already here."
	game.state.region.discover(id)
	DailySites.force_available(game.state, id)      # Exp 009 (D): the developer tool goes even when it's overrun
	var why := ""
	if game.is_home():
		why = await depart(id, false, true)
	else:
		game.debug_kill_enemies()
		why = await travel_on(id, by_car(), true)
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
		if not stops().is_empty():
			t += " · after %s" % _places_text(stops())
	var n := OffscreenHome.events(game.state).size()
	if n > 0:
		t += " · %d thing%s happened at home" % [n, "" if n == 1 else "s"]
	return t
