class_name DailySites
extends RefCounted
## Experiment 009 (D): the daily opportunities (SPEC-009 "Stage A"). Pure
## data and pure helpers: no nodes, no geometry, no enemies.
##
## Every map site has a cheap SETUP (`setup(state, id)`): which archetype of
## building it is (never changes), its family, size, surroundings, what it is
## good for, its risk and its seed (stable for the run). G's PoiGenerator
## builds the actual place from it, only when Eli commits to going there.
##
## Each day only some of the known sites can be approached; the rest are
## OVERRUN ("too many hostiles to approach safely"): they stay on the map,
## dimmed, and travel there is refused (TravelRules.block_reason). Today's
## selection lives in `state.region.daily` and is saved with the region:
##   {"day": d, "available": [ids], "overrun": [ids],
##    "streak": {id: days left available, today included},
##    "since": {id: the day it became available},
##    "until": {id: the last day it stays overrun at least}}
## A save without it (older saves) gets one on first use (`today()`).
##
## The rules of `refresh(state, day)` (the game calls it at 00:00, see
## `on_new_day`):
## - GRACE_DAYS: on the first day every known place is open (the town hasn't
##   stirred yet; the player learns the map). The rules below start on day 2.
## - About PER_DAY (4..6, configurable) of the known places are available.
## - Pine Woods (EXEMPT) is always available: the low-risk wood near home.
##   It counts toward the 4..6.
## - Streaks: a place that opens stays open 1..3 days (STREAK_WEIGHTS); one
##   that closes stays overrun at least 1..2 days (OVERRUN_DAYS). Places that
##   were closed yesterday are picked first, so the selection rotates.
## - Balance: with FOOD_CHANCE a food source is open, and with
##   MATERIALS_CHANCE a building-materials source besides the woods (nails,
##   scrap, iron, stone), swapped in when the draw had none.
## - The site of a running expedition (`keep`: the POI Eli is at, the leg's
##   destination) is never removed: it stays available.
## - The game's midnight call may also bring word of one unknown place
##   (HEARD_CHANCE): it becomes known and open today (an opportunity).
## Places discovered during the day (not in either list) are available.
##
## Developer test sites use ids "gen:<archetype>:<seed>" (F10 "POI
## generator"). They have a setup, no map position and are never stored in
## the region (`forget_test` clears what a visit left on leaving).

const PER_DAY_DEFAULT := Vector2i(4, 6)
## Today's number of available places: a random count in [x, y].
static var PER_DAY := PER_DAY_DEFAULT
const GRACE_DAYS := 1
const EXEMPT := ["forest"]
const STREAK_WEIGHTS := [0.5, 0.3, 0.2]      ## stays available 1, 2 or 3 days
const OVERRUN_DAYS := Vector2i(1, 2)
const FOOD_CHANCE := 0.9
const MATERIALS_CHANCE := 0.85
const HEARD_CHANCE := 0.25
const FOOD := "Food and water"               ## MapInfo.good_for labels
const MATERIALS := "Building materials"
const MAX_STEPS := 14                        ## days replayed when the selection is behind
const TEST_PREFIX := "gen:"
const OVERRUN_LINE := "Overrun — too many hostiles to approach safely."

## Site -> archetype (SPEC-009 "Sites and archetypes"; PoiArchetypes.for_site
## is used when it exists). The six hand-made places keep their template.
const FALLBACK_ARCHETYPES := {
	"forest": "pine_woods", "convenience": "corner_store", "library": "library",
	"hardware": "hardware_store", "gun_shop": "gun_shop", "clinic": "clinic",
	"homes": "house_small", "cul_de_sac": "house_family", "farmhouse": "cottage", "trailer_park": "cottage",
	"apartments": "apartment",
	"grocery": "supermarket", "diner": "diner", "restaurant": "diner", "fast_food": "diner",
	"drugstore": "pharmacy", "office_block": "office",
	"workshop": "workshop", "auto_garage": "garage", "warehouse": "warehouse", "sawmill": "warehouse", "factory": "factory",
	"scrapyard": "yard", "quarry": "yard", "construction_site": "yard", "logging": "yard",
	"hospital": "hospital", "police": "police", "military": "police", "vet_clinic": "clinic_small",
	"shooting_range": "range", "fire_station": "fire_station",
}
const VARIANTS := {"military": "outpost"}
const FAMILIES := {
	"house_small": "residential", "house_family": "residential", "cottage": "residential", "apartment": "residential",
	"supermarket": "commercial", "diner": "commercial", "pharmacy": "commercial", "office": "commercial",
	"workshop": "light_industry", "garage": "light_industry", "warehouse": "light_industry", "factory": "light_industry",
	"yard": "outdoor_industrial",
	"hospital": "public", "police": "public", "clinic_small": "public", "range": "public", "fire_station": "public",
	"pine_woods": "outdoor", "corner_store": "commercial", "hardware_store": "commercial", "gun_shop": "commercial",
	"library": "public", "clinic": "public",
}
## Archetypes the F10 tool offers when PoiArchetypes has no list.
const TEST_ARCHETYPES := ["house_small", "house_family", "cottage", "apartment", "supermarket", "diner", "pharmacy", "office",
	"workshop", "garage", "warehouse", "factory", "yard", "clinic_small", "hospital", "police", "range", "fire_station"]
## Region district -> the kind of surroundings (X's PoiExterior decides the details).
const SURROUNDINGS := {"suburbs": "street", "centre": "town", "industrial": "industrial", "docks": "docks",
	"forest": "woods", "mountains": "rock", "hills": "hills", "farmland": "fields"}
## MapInfo.good_for label -> the setup's category key.
const CATEGORY_KEYS := {"Food and water": "food", "Building materials": "materials", "Medical": "medical",
	"Weapons and ammo": "weapons", "Books": "books", "Tools": "tools"}

static var _good := {}                       ## id -> MapInfo.good_for (cached, pure)
static var _arch: Variant = null             ## the PoiArchetypes script, or false when absent


# --- setups ---------------------------------------------------------------------------------

## The cheap setup of a site (SPEC-009 Stage A):
## {id, archetype, family, variant, size "s"|"m"|"l", surroundings,
##  categories [food, materials, medical, weapons, books, tools],
##  risk, seed, hand_made, available, overrun_until, like, test}.
## {} for an unknown id. `state` may be null (seed 0, available).
static func setup(state: GameState, id: String) -> Dictionary:
	if is_test_id(id):
		return _test_setup(id)
	if not RegionLocations.has(id):
		return {}
	var d := RegionLocations.get_def(id)
	var arch := archetype_of(id)
	var sz: Vector2 = d.get("size", Vector2(3, 3))
	var area := sz.x * sz.y
	var overrun := state != null and is_overrun(state, id)
	return {
		"id": id, "archetype": arch, "family": str(FAMILIES.get(arch, "commercial")), "variant": str(VARIANTS.get(id, "")),
		"size": "s" if area <= 6.0 else ("m" if area <= 20.0 else "l"),
		"surroundings": str(SURROUNDINGS.get(str(d.get("district", "")), "town")),
		"categories": categories_of(id), "risk": float(ExpeditionData.destination(id).get("danger", 1.0)),
		"seed": seed_of(state, id), "hand_made": PoiDefs.HAND_MADE.has(id),
		"available": not overrun, "overrun_until": overrun_until(state, id) if overrun else 0,
		"like": id, "test": false,
	}


## The site's seed: hash of the run seed and the id, stable for the run.
static func seed_of(state: GameState, id: String) -> int:
	var run_seed := int(state.run.get("seed", 0)) if state != null else 0
	return hash([run_seed, id]) & 0x7fffffff


## The site's archetype (G's PoiArchetypes.for_site when present, else the
## SPEC table). Never changes.
static func archetype_of(id: String) -> String:
	var a: Variant = _arch_call("for_site", [id])
	if typeof(a) == TYPE_DICTIONARY:
		a = (a as Dictionary).get("archetype", (a as Dictionary).get("id", ""))
	if typeof(a) in [TYPE_STRING, TYPE_STRING_NAME] and str(a) != "":
		return str(a)
	return str(FALLBACK_ARCHETYPES.get(id, "house_small"))


## Category keys from the place's loot profile (MapInfo.good_for).
static func categories_of(id: String) -> Array:
	return good_for(id).map(func(l): return str(CATEGORY_KEYS.get(l, str(l).to_lower())))


static func good_for(id: String) -> Array:
	if not _good.has(id):
		_good[id] = MapInfo.good_for(id)
	return _good[id]


# --- today's selection ----------------------------------------------------------------------

## Today's selection (state.region.daily), made or brought up to date first.
static func today(state: GameState) -> Dictionary:
	if state == null or state.region == null:
		return {}
	var day := state.day()
	var d: Dictionary = state.region.daily
	var at := int(d.get("day", 0)) if not d.is_empty() else 0
	if at == day:
		return d
	if at > 0 and at < day and day - at <= MAX_STEPS:
		for k in range(at + 1, day + 1):
			refresh(state, k)
	else:
		refresh(state, day)
	return state.region.daily


static func is_overrun(state: GameState, id: String) -> bool:
	if state == null or not RegionLocations.has(id):
		return false
	return id in (today(state).get("overrun", []) as Array)


static func is_available(state: GameState, id: String) -> bool:
	return RegionLocations.has(id) and not is_overrun(state, id)


static func available_ids(state: GameState) -> Array:
	return (today(state).get("available", []) as Array).duplicate()


static func overrun_ids(state: GameState) -> Array:
	return (today(state).get("overrun", []) as Array).duplicate()


## The last day an overrun place stays overrun at least (0 when it is open).
static func overrun_until(state: GameState, id: String) -> int:
	if not is_overrun(state, id):
		return 0
	return maxi(int((today(state).get("until", {}) as Dictionary).get(id, state.day())), state.day())


## The day an available place opened (0 = unknown or overrun).
static func since_day(state: GameState, id: String) -> int:
	if state == null or is_overrun(state, id):
		return 0
	return int((today(state).get("since", {}) as Dictionary).get(id, 0))


## Days the place stays open for sure (today included; 0 = no promise).
static func days_left(state: GameState, id: String) -> int:
	if state == null or is_overrun(state, id) or id in EXEMPT:
		return 0
	return int((today(state).get("streak", {}) as Dictionary).get(id, 0))


## One line for the map's panel: "Open since day 3 · may be gone tomorrow".
static func availability_text(state: GameState, id: String) -> String:
	if state == null or not RegionLocations.has(id):
		return ""
	if is_overrun(state, id):
		var u := overrun_until(state, id)
		return "Overrun today" + (", at least until day %d" % u if u > state.day() else "")
	if id in EXEMPT:
		return "Open (always quiet enough)"
	var t := "Open today"
	var since := since_day(state, id)
	if since > 0 and since < state.day():
		t = "Open since day %d" % since
	var left := days_left(state, id)
	if left == 1:
		t += " · may be gone tomorrow"
	elif left > 1:
		t += " · for a few days"
	return t


## Makes the selection for `day` from the previous one (see the header).
## `keep`: ids that must stay available (a running expedition). `heard`:
## allow word of one unknown place (the game's midnight call only). Returns
## {"day", "available", "overrun", "heard": id or ""}. Deterministic for the
## run seed, the day and the previous selection.
static func refresh(state: GameState, day: int, keep: Array = [], heard := false) -> Dictionary:
	if state == null or state.region == null:
		return {}
	day = maxi(day, 1)
	var region: RegionState = state.region
	var prev: Dictionary = region.daily
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(state.run.get("seed", 0)), day, "daily"])
	var known := []
	for id in RegionLocations.ids():
		if region.is_discovered(id):
			known.append(id)
	known.sort()
	var found := ""
	if heard and day > GRACE_DAYS and rng.randf() < HEARD_CHANCE:
		found = _pick_unknown(region, rng)
		if found != "":
			region.discover(found)
			known.append(found)
	var prev_ok := int(prev.get("day", 0)) == day - 1
	var prev_av: Array = prev.get("available", []) if prev_ok else []
	var prev_streak: Dictionary = prev.get("streak", {}) if prev_ok else {}
	var prev_since: Dictionary = prev.get("since", {}) if prev_ok else {}
	var until := {}
	for id in (prev.get("until", {}) as Dictionary):
		if int(prev["until"][id]) >= day and id in known:
			until[id] = int(prev["until"][id])
	var avail := []
	var streak := {}
	if day <= GRACE_DAYS:
		avail = known.duplicate()
		until.clear()
	else:
		var target := rng.randi_range(mini(PER_DAY.x, PER_DAY.y), maxi(PER_DAY.x, PER_DAY.y))
		var must := []
		for id in EXEMPT + keep + ([found] if found != "" else []):
			if RegionLocations.has(str(id)) and id in known and not id in must:
				must.append(str(id))
		avail = must.duplicate()
		for id in must:
			streak[id] = maxi(int(prev_streak.get(id, 1)) - 1, 1) if id in prev_av else _roll_streak(rng)
		# yesterday's places with days left (in a shuffled order, within the target)
		var carry := []
		for id in prev_av:
			if id in known and not id in avail and int(prev_streak.get(id, 0)) > 1:
				carry.append(id)
		_shuffle(carry, rng)
		for id in carry:
			if avail.size() >= target:
				break
			avail.append(id)
			streak[id] = int(prev_streak[id]) - 1
		# fresh picks: places closed yesterday first, then the rest; overrun-locked last
		var fresh := []
		var again := []
		var locked := []
		for id in known:
			if id in avail:
				continue
			if until.has(id):
				locked.append(id)
			elif id in prev_av:
				again.append(id)
			else:
				fresh.append(id)
		_shuffle(fresh, rng)
		_shuffle(again, rng)
		_shuffle(locked, rng)
		var pool := fresh + again
		while avail.size() < target and not pool.is_empty():
			var id: String = pool.pop_front()
			avail.append(id)
			streak[id] = _roll_streak(rng)
		while avail.size() < mini(PER_DAY.x, PER_DAY.y) and not locked.is_empty():
			var id: String = locked.pop_front()
			avail.append(id)
			streak[id] = 1
		# balance: food, and building materials besides the woods
		for need in [[FOOD, FOOD_CHANCE], [MATERIALS, MATERIALS_CHANCE]]:
			if _any_gives(avail, need[0]) or rng.randf() >= float(need[1]):
				continue
			var cand := []
			for id in pool + locked:
				if id in known and not id in avail and str(need[0]) in good_for(id):
					cand.append(id)
			if cand.is_empty():
				continue
			var add: String = cand[rng.randi_range(0, cand.size() - 1)]
			var drop := _droppable(avail, must, need[0])
			if avail.size() >= maxi(PER_DAY.x, PER_DAY.y) and drop != "":
				avail.erase(drop)
				streak.erase(drop)
			avail.append(add)
			streak[add] = _roll_streak(rng)
	var overrun := []
	for id in known:
		if id in avail:
			until.erase(id)
		else:
			overrun.append(id)
			if not until.has(id):
				until[id] = day + rng.randi_range(OVERRUN_DAYS.x, OVERRUN_DAYS.y) - 1
	var since := {}
	for id in avail:
		since[id] = int(prev_since.get(id, day)) if id in prev_av else day
	avail.sort()
	overrun.sort()
	region.daily = {"day": day, "available": avail, "overrun": overrun, "streak": streak, "since": since, "until": until}
	return {"day": day, "available": avail.duplicate(), "overrun": overrun.duplicate(), "heard": found}


## The game's midnight hook (SurvivalGame._process_events "new_day"): the
## new day's selection; the POI Eli is at stays available (never ejected).
## Word of a new place shows as a toast.
static func on_new_day(game: Node, day: int) -> Dictionary:
	var s: GameState = game.get("state")
	if s == null:
		return {}
	var keep := []
	if game.has_method("is_home") and not game.is_home() and game.has_method("site_id"):
		keep.append(str(game.site_id()))
	var t: Variant = game.get("travel")
	if t is Object and is_instance_valid(t) and typeof(t.get("info")) == TYPE_DICTIONARY:
		var to := str((t.get("info") as Dictionary).get("to", ""))
		if to != "" and not to in keep:
			keep.append(to)
	var r := refresh(s, day, keep, true)
	if str(r.get("heard", "")) != "" and game.has_method("toast"):
		game.toast("Word of a place you didn't know: %s. It's on your map, and quiet today." % RegionLocations.name_of(r["heard"]), "info")
	return r


## Developer tools and tests: `id` is available today (it stays so for the day).
static func force_available(state: GameState, id: String) -> void:
	if state == null or not RegionLocations.has(id):
		return
	var d := today(state)
	(d["overrun"] as Array).erase(id)
	(d["until"] as Dictionary).erase(id)
	if not id in d["available"]:
		(d["available"] as Array).append(id)
		(d["available"] as Array).sort()
		d["streak"][id] = 1
		d["since"][id] = state.day()


static func _roll_streak(rng: RandomNumberGenerator) -> int:
	var x := rng.randf()
	for i in STREAK_WEIGHTS.size():
		x -= float(STREAK_WEIGHTS[i])
		if x < 0.0:
			return i + 1
	return STREAK_WEIGHTS.size()


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t


## True when one of `ids` gives `label` (the woods don't count for materials).
static func _any_gives(ids: Array, label: String) -> bool:
	for id in ids:
		if label == MATERIALS and id in EXEMPT:
			continue
		if label in good_for(id):
			return true
	return false


## The last pick that may make way for a balance pick (not a must, not the
## only source of the other need), or "".
static func _droppable(avail: Array, must: Array, need: String) -> String:
	var other := MATERIALS if need == FOOD else FOOD
	for i in range(avail.size() - 1, -1, -1):
		var id: String = avail[i]
		if id in must:
			continue
		if other in good_for(id):
			var rest := avail.duplicate()
			rest.erase(id)
			if not _any_gives(rest, other):
				continue
		return id
	return ""


## An unknown place, the nearer to home the likelier; "" when all are known.
static func _pick_unknown(region: RegionState, rng: RandomNumberGenerator) -> String:
	var ids := region.undiscovered()
	ids.sort()
	if ids.is_empty():
		return ""
	var total := 0.0
	var w := []
	for id in ids:
		var x := 1.0 / (1.0 + RegionLocations.distance_km(id))
		w.append(x)
		total += x
	var r := rng.randf() * total
	for i in ids.size():
		r -= float(w[i])
		if r < 0.0:
			return ids[i]
	return ids[-1]


# --- developer test sites ("gen:<archetype>:<seed>") ------------------------------------------

static func is_test_id(id: String) -> bool:
	return id.begins_with(TEST_PREFIX)


static func test_id(archetype: String, seed: int) -> String:
	return "%s%s:%d" % [TEST_PREFIX, archetype, seed & 0x7fffffff]


## "gen:apartment:123" -> {"archetype": "apartment", "seed": 123} ({} if malformed).
static func parse_test_id(id: String) -> Dictionary:
	if not is_test_id(id):
		return {}
	var parts := id.trim_prefix(TEST_PREFIX).split(":")
	if parts.size() != 2 or parts[0] == "" or not parts[1].is_valid_int():
		return {}
	return {"archetype": parts[0], "seed": int(parts[1]) & 0x7fffffff}


static func test_name(id: String) -> String:
	var p := parse_test_id(id)
	if p.is_empty():
		return id
	return "Test site: %s #%d" % [str(p["archetype"]).replace("_", " ").capitalize(), int(p["seed"])]


## A real site with this archetype (its loot profile can stand in), or "".
static func site_like(archetype: String) -> String:
	for id in ExpeditionData.ORDER:
		if archetype_of(id) == archetype:
			return id
	return ""


static func _test_setup(id: String) -> Dictionary:
	var p := parse_test_id(id)
	if p.is_empty():
		return {}
	var arch := str(p["archetype"])
	var like := site_like(arch)
	return {
		"id": id, "archetype": arch, "family": str(FAMILIES.get(arch, "commercial")), "variant": "",
		"size": "m", "surroundings": str(SURROUNDINGS.get(str(RegionLocations.get_def(like).get("district", "")), "town")),
		"categories": categories_of(like) if like != "" else [], "risk": float(ExpeditionData.destination(like).get("danger", 1.0)) if like != "" else 1.0,
		"seed": int(p["seed"]), "hand_made": false, "available": true, "overrun_until": 0, "like": like, "test": true,
	}


## Leaving a test site: whatever its visit left in the region goes.
static func forget_test(state: GameState, id: String) -> void:
	if state == null or state.region == null or not is_test_id(id):
		return
	state.region.poi.erase(id)
	state.region.notes.erase(id)
	state.region.stock.erase(id)
	state.region.discovered.erase(id)


## The archetypes the F10 tool offers (PoiArchetypes' list when it has one).
static func test_archetypes() -> Array:
	for m in ["ids", "archetypes", "all"]:
		var v: Variant = _arch_call(m, [])
		if typeof(v) == TYPE_ARRAY and not (v as Array).is_empty():
			return (v as Array).map(func(x): return str(x))
	return TEST_ARCHETYPES.duplicate()


# --- G's PoiArchetypes, when it exists (no hard dependency) ------------------------------------

static func _arch_call(method: String, args: Array) -> Variant:
	var s := global_script("PoiArchetypes")
	if s == null:
		return null
	for m in s.get_script_method_list():
		if str(m.get("name", "")) == method:
			return s.callv(method, args)
	return null


## A global class's script by its class_name, or null when it doesn't exist.
static func global_script(cls: String) -> Script:
	if cls == "PoiArchetypes" and _arch != null:
		return _arch if _arch is Script else null
	var found: Script = null
	for c in ProjectSettings.get_global_class_list():
		if str(c.get("class", "")) == cls:
			found = load(str(c.get("path", ""))) as Script
			break
	if cls == "PoiArchetypes":
		_arch = found if found != null else false
	return found
