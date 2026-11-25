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

const T := preload("res://src/survival/survival_tuning.gd")

const ANIM_FOOT := Vector2(4.0, 8.0)       ## seconds: min, max
const ANIM_CAR := Vector2(3.0, 5.0)
const STAY_DEFAULT := 90                   ## minutes, when a place has no search time
const DARK_MINUTE := T.DUSK_MINUTE         ## 20:00
const LIGHT_MINUTE := T.DAWN_MINUTE        ## 06:00
const DAY_MIN := 1440.0


## One-way travel minutes to a place (0 for an unknown id).
static func minutes(id: String, car := false) -> int:
	if ExpeditionData.has_destination(id):
		return ExpeditionData.travel_minutes(id, car)
	if not RegionLocations.has(id):
		return 0
	var m := RegionLocations.travel_minutes(id)
	return maxi(int(round(float(m) * ExpeditionData.CAR_TRAVEL / 5.0)) * 5, 5) if car else m


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
##  "before_dark": bool, "text"}: setting out now, staying a typical while
## and coming back. Before dark: it is day now and Eli is back by 20:00.
static func timing(state: GameState, id: String, car := false) -> Dictionary:
	var m := minutes(id, car)
	var stay := stay_minutes(id)
	var now := state.total_minutes
	var mod := state.minute_of_day()
	var back := now + 2.0 * m + stay
	var day_end := floorf(now / DAY_MIN) * DAY_MIN + DARK_MINUTE
	var light := mod >= LIGHT_MINUTE and mod < DARK_MINUTE
	var ok := light and back <= day_end
	var text := ""
	if ok:
		text = "Back around %s, before dark." % clock(back)
	elif not light:
		text = "It's dark out there now. Back around %s." % clock(back)
	else:
		text = "Not enough daylight: back around %s, after dark." % clock(back)
	return {"minutes": m, "stay": stay, "now": now, "arrive_at": now + m, "back_at": back, "before_dark": ok, "text": text}


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
	var d := ExpeditionData.destination(id)
	for item in d.get("requires", []):
		if not ExpeditionData.can_bring(state, str(item)):
			var nm := Items.name_of(str(item)).to_lower()
			if ExpeditionData.owns(state, str(item)):
				return "Needs a %s. Equip yours first." % nm
			return ("Needs a %s. %s" % [nm, str(d.get("requires_text", ""))]).strip_edges()
	return ""


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
