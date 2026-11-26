class_name TravelRules
extends RefCounted
## Exp 007 (T): the numbers and checks of visible travel (pure, no scene).
##
## Travel times are the existing ones: RegionLocations / ExpeditionData
## (`travel_minutes(id, car)`: on foot, or x CAR_TRAVEL by car). A trip by
## car burns ExpeditionData.CAR_FUEL fuel cans (one per round trip, paid when
## Eli drives off). The map shows `timing()` (there, a typical stay, back,
## and whether that is before dark) and `capacity_text()`. `block_reason()`
## is the one gate for setting out (the map's Travel button and F10 travel
## use it; the game adds its own "enemies around" check).
##
## The animation on the map takes `anim_seconds()` real seconds (4-8 s on
## foot, 3-5 s by car), never minutes.
##
## Exp 008 (T): legs between places. A trip can go on from one POI to the
## next before it comes home (Home -> Hardware Store -> Medical Clinic ->
## Home). `minutes_between(from, to, car)` is the road time of any leg (the
## same estimate as from home: straight km x ROAD_FACTOR x MINUTES_PER_KM,
## rounded to 5; x CAR_TRAVEL by car). The chain's rules:
##   mode   the car stays with Eli along the chain: he walks on if he walked
##          out, drives on if he drove (`mode_reason`)
##   fuel   `leg_fuel`: leaving home by car burns 1 can (there and back, as
##          before); each further stop by car (POI -> POI) 1 more; the way
##          home is already paid; walking is free
##   time   `leg_timing`: there, a typical stay, then home from THERE, and
##          whether that is before dark ("Back home by 18:40" / "You'd get
##          home after dark")
##   gate   `leg_block_reason` (the map at a POI, travel_flow.travel_on)

const T := preload("res://src/survival/survival_tuning.gd")

const ANIM_FOOT := Vector2(4.0, 8.0)       ## seconds: min, max
const ANIM_CAR := Vector2(3.0, 5.0)
const STAY_DEFAULT := 90                   ## minutes, when a place has no search time
const DARK_MINUTE := T.DUSK_MINUTE         ## 20:00
const LIGHT_MINUTE := T.DAWN_MINUTE        ## 06:00
const DAY_MIN := 1440.0
const HOME := "home"                       ## Exp 008 (T): MapInfo.HOME, the house as an end of a leg


## One-way travel minutes to a place (0 for an unknown id).
static func minutes(id: String, car := false) -> int:
	if ExpeditionData.has_destination(id):
		return ExpeditionData.travel_minutes(id, car)
	if not RegionLocations.has(id):
		return 0
	var m := RegionLocations.travel_minutes(id)
	return maxi(int(round(float(m) * ExpeditionData.CAR_TRAVEL / 5.0)) * 5, 5) if car else m


## Exp 008 (T): a place's position on the region (cells); "home" is the house.
static func pos_of(id: String) -> Vector2:
	if id == HOME:
		return RegionLocations.HOME
	return RegionLocations.get_def(id).get("pos", RegionLocations.HOME)


## Straight distance between two places (either may be "home") in km.
static func km_between(from: String, to: String) -> float:
	return pos_of(from).distance_to(pos_of(to)) * RegionLocations.CELL_M / 1000.0


## One-way road minutes of a leg (either end may be "home"; 0 for the same
## place or an unknown id). From or to home it is exactly minutes().
static func minutes_between(from: String, to: String, car := false) -> int:
	if from == to or not _place_ok(from) or not _place_ok(to):
		return 0
	if from == HOME:
		return minutes(to, car)
	if to == HOME:
		return minutes(from, car)
	var m := km_between(from, to) * RegionLocations.ROAD_FACTOR * RegionLocations.MINUTES_PER_KM
	var foot := maxi(int(round(m / 5.0)) * 5, 10)
	return maxi(int(round(float(foot) * ExpeditionData.CAR_TRAVEL / 5.0)) * 5, 5) if car else foot


static func _place_ok(id: String) -> bool:
	return id == HOME or RegionLocations.has(id)


## Fuel cans a leg burns (the chain rule in the header).
static func leg_fuel(from: String, to: String, car: bool) -> int:
	if not car or to == HOME or from == to:
		return 0
	return ExpeditionData.CAR_FUEL


## "" when Eli can make the next leg on foot (`car` false) or by car from
## `from`, else why not. At home: the car must run and have fuel. At a POI
## the mode is the one he came with (`car_here`: the car came along).
static func mode_reason(state: GameState, from: String, car: bool, car_here := false) -> String:
	if from == HOME:
		return car_reason(state) if car else ""
	if car and not car_here:
		return "The car is at home."
	if not car and car_here:
		return "The car comes with you."
	return ""


## A typical stay at the place (its general search time).
static func stay_minutes(id: String) -> int:
	if ExpeditionData.has_destination(id):
		return ExpeditionData.search_minutes(id, "general")
	return STAY_DEFAULT


## Real seconds the map animation takes for a leg of `mins` game minutes.
static func anim_seconds(mins: float, car := false) -> float:
	var r := ANIM_CAR if car else ANIM_FOOT
	return clampf(r.x + mins / 20.0, r.x, r.y)


static func fuel_needed(car: bool) -> int:
	return ExpeditionData.CAR_FUEL if car else 0


## "" when the car can be taken now, else why not (broken, no fuel).
static func car_reason(state: GameState) -> String:
	return ExpeditionData.car_state(state)


static func can_drive(state: GameState) -> bool:
	return car_reason(state) == ""


## {"minutes", "stay", "now", "arrive_at", "back_at" (total minutes),
##  "before_dark": bool, "text"}: setting out from home now, staying a
## typical while and coming back. Before dark: it is day now and Eli is back
## by 20:00. (leg_timing from home.)
static func timing(state: GameState, id: String, car := false) -> Dictionary:
	return leg_timing(state, HOME, id, car)


## Exp 008 (T): one leg from `from` to `to` now, then (for a place) a typical
## stay there and the way home from THERE. Keys as timing() plus "from",
## "to", "home_minutes" (the way home from `to`; 0 when `to` is home) and
## "home_at" (= "back_at"). The text: "Back home by 18:40, before dark." /
## "You'd get home after dark (around 21:10)." / "It's dark out there now..."
static func leg_timing(state: GameState, from: String, to: String, car := false) -> Dictionary:
	var m := minutes_between(from, to, car)
	var stay := 0 if to == HOME else stay_minutes(to)
	var home_m := 0 if to == HOME else minutes(to, car)
	var now := state.total_minutes
	var mod := state.minute_of_day()
	var back := now + float(m + stay + home_m)
	var day_end := floorf(now / DAY_MIN) * DAY_MIN + DARK_MINUTE
	var light := mod >= LIGHT_MINUTE and mod < DARK_MINUTE
	var ok := light and back <= day_end
	var text := ""
	if ok:
		text = ("Home by %s, before dark." if to == HOME else "Back home by %s, before dark.") % clock(back)
	elif not light:
		text = "It's dark out there now. Home around %s." % clock(back)
	else:
		text = "You'd get home after dark (around %s)." % clock(back)
	return {"minutes": m, "stay": stay, "home_minutes": home_m, "now": now, "arrive_at": now + m, "back_at": back, "home_at": back,
		"before_dark": ok, "text": text, "from": from, "to": to}


## What Eli can bring back, as a line for the map: agent P's pack and boot
## limits (PoiState; weights per item).
static func capacity_text(state: GameState, car := false) -> String:
	var t := "A pack of %d" % int(round(PoiState.pack_cap(state)))
	t += " (with your backpack)" if state != null and float(state.carry_multiplier()) > 1.0 else " (a backpack carries half again)"
	if car:
		t += ", plus the car's boot (%d)" % int(round(PoiState.CARGO_CAP))
	return t + "."


## Why Eli can't set out for `id` now ("" = he can). The game adds its own
## checks (enemies near, an open modal).
static func block_reason(state: GameState, id: String, car := false) -> String:
	if state == null or state.dead:
		return "You're dead."
	if not RegionLocations.has(id):
		return "Unknown place."
	if not state.region.is_discovered(id):
		return "You don't know where that is yet."
	if state.run.get("invasion_active", false) or state.run.get("invasion_announced", false):
		return "Not with them at the door."
	if car:
		var why := car_reason(state)
		if why != "":
			return why
	return _requires_reason(state, id)


## What the place itself asks for (a required piece of gear), "" = nothing.
static func _requires_reason(state: GameState, id: String) -> String:
	var d := ExpeditionData.destination(id)
	for item in d.get("requires", []):
		if not ExpeditionData.can_bring(state, str(item)):
			var nm := Items.name_of(str(item)).to_lower()
			if ExpeditionData.owns(state, str(item)):
				return "Needs a %s. Equip yours first." % nm
			return ("Needs a %s. %s" % [nm, str(d.get("requires_text", ""))]).strip_edges()
	return ""


## Exp 008 (T): why Eli can't make the leg `from` -> `to` now ("" = he can).
## From home it is block_reason(). From a POI: home is always open (in the
## mode he came with); another known place needs the mode he came with
## (`car_here`), the fuel of a further stop by car and the place's gear.
static func leg_block_reason(state: GameState, from: String, to: String, car := false, car_here := false) -> String:
	if from == HOME:
		return "You're already home." if to == HOME else block_reason(state, to, car)
	if state == null or state.dead:
		return "You're dead."
	if to == from:
		return "You're here."
	if to != HOME:
		if not RegionLocations.has(to):
			return "Unknown place."
		if not state.region.is_discovered(to):
			return "You don't know where that is yet."
	var why := mode_reason(state, from, car, car_here)
	if why != "":
		return why
	var need := leg_fuel(from, to, car)
	if need > 0 and not state.cheats.get("unlimited", false) and state.inventory.count("fuel") < need:
		return "No fuel for another stop (%d can). The way home is paid." % need
	return "" if to == HOME else _requires_reason(state, to)


## Discovery on the road (replaces the dialogue expeditions' "careful
## exploration" finds): each arrival at a place has DISCOVER_CHANCE to spot
## one unknown place, preferring places near it (the same weighting as
## ExpeditionRun). Returns the id or "". Deterministic for a seed.
const DISCOVER_CHANCE := 0.3


static func roll_discovery(state: GameState, dest: String, seed: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	if rng.randf() >= DISCOVER_CHANCE:
		return ""
	var here: Vector2 = RegionLocations.get_def(dest).get("pos", RegionLocations.HOME)
	var ids := []
	var weights := []
	var total := 0.0
	for id in RegionLocations.ids():
		if state.region.is_discovered(id) or id == dest:
			continue
		var w := 1.0 / pow(1.0 + (RegionLocations.get_def(id)["pos"] as Vector2).distance_to(here) / 20.0, 2.0)
		ids.append(id)
		weights.append(w)
		total += w
	if ids.is_empty():
		return ""
	var x := rng.randf() * total
	for i in ids.size():
		x -= weights[i]
		if x < 0.0:
			return ids[i]
	return ids[-1]


static func clock(total: float) -> String:
	var m := int(round(fposmod(total, DAY_MIN)))
	return "%02d:%02d" % [(m / 60) % 24, m % 60]


## "Day 3, 14:20".
static func day_clock(total: float) -> String:
	return "Day %d, %s" % [int(floorf(total / DAY_MIN)) + 1, clock(total)]
