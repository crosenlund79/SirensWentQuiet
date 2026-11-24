class_name ExpeditionRun
extends RefCounted
## One simulated expedition, from departure to the result (SPEC-002 §7.7,
## SPEC-003 §3). Owner: X.
##
## Pure and deterministic: it reads a GameState once at `create` (inventory and
## equipment snapshot, clock, seed, difficulty, the region's stock and
## discoveries) and never mutates it. The result is applied by the game through
## `GameState.apply_expedition` and `ExpeditionData.apply_region`, each exactly
## once (guarded by the result id).
##
## Randomness comes from `state.run.seed` and `state.run.expeditions` (plus the
## destination), in four independent streams so the events met do not depend
## on the gear chosen, and the loot does not depend on the order of choices:
##   events    which events happen (the pool depends on the approach)
##   outcome   injury and loss rolls, event bonus loot
##   loot      the main search, the locked table, travel time
##   discover  new places found

const D := preload("res://src/expedition/expedition_data.gd")

var dest_id := ""
var dest := {}                 ## ExpeditionData.destination(dest_id)
var approach := "general"
var target := ""               ## targeted collection: the item gone for
var gear := {}                 ## what was brought: {"ammo": n, "shells": n, gear_id: 1}
var depart_at := 0.0           ## GameState.total_minutes at departure
var nominal_minutes := 0       ## travel both ways + the approach's search time
var event_ids: Array[String] = []
var step := 0                  ## index of the next unanswered event
var choices: Array[int] = []
var lines: Array[String] = []  ## the report's "what happened"

var _seed := 0
var _number := 0
var _owned := {}               ## counts at departure (rounds: reserve + magazine)
var _has := {}                 ## unique items owned at departure (inventory or equipped)
var _space := {}               ## space_for at departure
var _energy := 100.0
var _danger := 1.0
var _max_damage := D.MAX_DAMAGE
var _minutes_delta := 0
var _loot_mult := 1.0
var _damage := 0.0
var _rounds := {"ammo": 0, "shells": 0}   ## left
var _spent := {"ammo": 0, "shells": 0}
var _lost := {}
var _bonus := {}
var _marks := {}               ## flag -> days
var _discover_extra := 0
var _stock := 1.0
var _known := {}               ## places known at departure
var _loot_scale := 1.0         ## Difficulty loot
var _rng_events := RandomNumberGenerator.new()
var _rng_outcome := RandomNumberGenerator.new()
var _rng_loot := RandomNumberGenerator.new()
var _rng_discover := RandomNumberGenerator.new()
var _result := {}


## Prepares a run. `gear` is clamped to what the player owns (required gear is
## always brought). Returns null when the destination or the approach is
## unavailable now (or the approach's needs aren't met by the gear brought).
## `target` (targeted collection) defaults to the place's first target.
static func create(state: GameState, destination_id: String, wanted_gear := {}, approach_id := "general", target_id := "") -> ExpeditionRun:
	if not D.availability(state, destination_id, approach_id)["ok"]:
		return null
	var g := D.sanitize_gear(state, destination_id, wanted_gear)
	if not D.approach_state(state, destination_id, approach_id, g)["ok"]:
		return null
	var r := ExpeditionRun.new()
	r._setup(state, destination_id, g, approach_id, target_id)
	return r


## Runs a whole expedition with a fixed policy (tests, dev tools):
## `picks` gives option indices per event; missing or unavailable entries take
## the first available option. Returns the result ({} if unavailable).
static func simulate(state: GameState, destination_id: String, wanted_gear := {}, picks := [], approach_id := "general", target_id := "") -> Dictionary:
	var r := create(state, destination_id, wanted_gear, approach_id, target_id)
	if r == null:
		return {}
	while not r.is_finished():
		var want: int = picks[r.step] if r.step < picks.size() else -1
		if want < 0 or not r.option_state(want)["ok"]:
			want = r.first_available_option()
		r.choose(want)
	return r.result()


static func _stream_seed(seed: int, number: int, destination_id: String, stream: String) -> int:
	return ("swq|%d|%d|%s|%s" % [seed, number, destination_id, stream]).hash()


func _setup(state: GameState, destination_id: String, g: Dictionary, approach_id: String, target_id: String) -> void:
	dest_id = destination_id
	dest = D.destination(destination_id)
	approach = approach_id
	if approach == "targeted":
		var tg := D.targets(dest_id)
		target = target_id if target_id in tg else (str(tg[0]) if not tg.is_empty() else "")
	gear = g
	depart_at = state.total_minutes
	nominal_minutes = D.nominal_minutes(dest_id, approach)
	_seed = int(state.run.get("seed", 0))
	_number = int(state.run.get("expeditions", 0))
	_energy = state.energy
	for id in Items.DEFS:
		_owned[id] = state.inventory.count(id)
		_space[id] = state.inventory.space_for(id)
		if D.is_unique(id):
			_has[id] = D.owns(state, id)
			if _has[id]:
				_owned[id] = maxi(int(_owned[id]), 1)
	for a in D.AMMO_TYPES:
		_owned[a] = D.rounds_owned(state, a)
		_rounds[a] = int(gear.get(a, 0))
	_danger = D.trip_danger(state, dest_id, approach, gear)
	_max_damage = float(dest.get("max_damage", D.MAX_DAMAGE))
	_stock = D.stock_now(state, dest_id)
	_loot_scale = D.loot_scale(state)
	if state.region != null:
		_known = state.region.discovered.duplicate()
	_rng_events.seed = _stream_seed(_seed, _number, dest_id, "events")
	_rng_outcome.seed = _stream_seed(_seed, _number, dest_id, "outcome")
	_rng_loot.seed = _stream_seed(_seed, _number, dest_id, "loot")
	_rng_discover.seed = _stream_seed(_seed, _number, dest_id, "discover")
	_pick_events()


func _pick_events() -> void:
	var count := 2 if _rng_events.randf() < D.two_events_chance(dest_id, approach) else 1
	var pool := D.event_pool(dest_id, approach)
	for i in count:
		var total := 0.0
		for id in pool:
			total += float(pool[id])
		var x := _rng_events.randf() * total
		var picked := ""
		for id in pool:
			picked = id
			x -= float(pool[id])
			if x < 0.0:
				break
		if picked == "":
			break
		event_ids.append(picked)
		pool.erase(picked)


# --- event flow -----------------------------------------------------------------------

func is_finished() -> bool:
	return step >= event_ids.size()


## The current event with its text filled in, or {} when every event is answered.
func current_event() -> Dictionary:
	if is_finished():
		return {}
	var ev: Dictionary = D.event(event_ids[step]).duplicate(true)
	ev["id"] = event_ids[step]
	ev["text"] = ev["text"] % dest["place"] if "%s" in ev["text"] else ev["text"]
	return ev


func has_tool(id: String) -> bool:
	return int(gear.get(id, 0)) > 0 and not _lost.has(id)


## 9 mm rounds left (Experiment 002 name).
func ammo_left() -> int:
	return int(_rounds["ammo"])


func shells_left() -> int:
	return int(_rounds["shells"])


## Fight value left: rounds + SHELL_SHOTS per shell.
func shots_left() -> int:
	return D.shots_of(_rounds)


## The trip's danger (scales injury chances).
func danger() -> float:
	return _danger


## {"ok": bool, "reason": String} for option `i` of the current event.
func option_state(i: int) -> Dictionary:
	var ev := current_event()
	var opts: Array = ev.get("options", [])
	if i < 0 or i >= opts.size():
		return {"ok": false, "reason": "No such option."}
	var o: Dictionary = opts[i]
	var needs: Dictionary = o.get("needs", {})
	for id in needs:
		if id == "ammo" or id == "shots":
			continue
		if not has_tool(id):
			var nm := Items.name_of(id).to_lower()
			if _lost.has(id):
				return {"ok": false, "reason": "You lost the %s" % nm}
			if int(_owned.get(id, 0)) > 0:
				return {"ok": false, "reason": "You left the %s at home" % nm}
			return {"ok": false, "reason": "Needs a %s" % nm}
	var n := maxi(int(o.get("shots", 0)), int(needs.get("ammo", 0)))
	if n > 0 and shots_left() < n:
		if int(gear.get("shells", 0)) <= 0:
			return {"ok": false, "reason": "Needs %d round%s (you have %d)" % [n, "" if n == 1 else "s", ammo_left()]}
		return {"ok": false, "reason": "Needs %s (you have %d rounds, %d shells)" % [D.shots_text(n), ammo_left(), shells_left()]}
	return {"ok": true, "reason": ""}


func first_available_option() -> int:
	var opts: Array = current_event().get("options", [])
	for i in opts.size():
		if option_state(i)["ok"]:
			return i
	return -1


## Fires n shots' worth: 9 mm rounds first, then shells (SHELL_SHOTS each).
func _fire(n: int) -> Dictionary:
	var a := mini(int(_rounds["ammo"]), n)
	var s := mini(int(_rounds["shells"]), int(ceil(float(n - a) / D.SHELL_SHOTS)))
	_rounds["ammo"] -= a
	_rounds["shells"] -= s
	_spent["ammo"] += a
	_spent["shells"] += s
	return {"ammo": a, "shells": s}


## Answers the current event. Returns {"ok", "text", "hurt": float, "lost": [ids],
## "ammo": rounds used, "shells": shells used}. Draws a fixed number of random
## values per option so results stay stable.
func choose(i: int) -> Dictionary:
	if is_finished() or not option_state(i)["ok"]:
		return {"ok": false, "text": "", "hurt": 0.0, "lost": [], "ammo": 0, "shells": 0}
	var ev := current_event()
	var tags: Array = ev.get("tags", [])
	var o: Dictionary = ev["options"][i]
	var text: String = o.get("outcome", "")
	var used := {"ammo": 0, "shells": 0}
	var lost := []
	var shots := maxi(int(o.get("shots", 0)), int(o.get("ammo", 0)))
	if shots > 0:
		var f := _fire(shots)
		used["ammo"] += f["ammo"]
		used["shells"] += f["shells"]
	_minutes_delta += int(o.get("minutes", 0))
	_loot_mult *= float(o.get("loot", 1.0))
	# injury
	var hurt := 0.0
	var hurt_roll := _rng_outcome.randf()
	var dmg_roll := _rng_outcome.randf()
	if o.has("hurt"):
		var h: Array = o["hurt"]
		var chance := float(h[0]) * _danger
		if "dark" in tags and has_tool("flashlight"):
			chance *= D.DARK_FLASHLIGHT_SCALE
		if hurt_roll < clampf(chance, 0.0, 0.95):
			hurt = lerpf(float(h[1]), float(h[2]), dmg_roll)
			if "fight" in tags and shots == 0 and shots_left() > 0:
				var f := _fire(1)
				used["ammo"] += f["ammo"]
				used["shells"] += f["shells"]
				hurt *= D.FIGHT_AMMO_SCALE
				text += " " + o.get("hurt_text", "You get hurt.") + " You fire once to get clear."
			else:
				text += " " + o.get("hurt_text", "You get hurt.")
			if "fight" in tags and has_tool("vest"):
				hurt *= D.VEST_DAMAGE
			hurt = clampf(hurt, 0.0, maxf(_max_damage - _damage, 0.0))
			_damage += hurt
			_loot_mult *= float(o.get("hurt_loot", 1.0))
	# loss of a brought tool
	var lose_roll := _rng_outcome.randf()
	if o.has("lose"):
		var tool: String = o["lose"][0]
		if has_tool(tool) and lose_roll < float(o["lose"][1]):
			_lost[tool] = 1
			lost.append(tool)
			text += " " + o.get("lose_text", "You lose the %s." % Items.name_of(tool).to_lower())
	# bonus loot
	if o.has("bonus"):
		var table := _bonus_table(o["bonus"])
		var mult := 0.5 if typeof(o["bonus"]) == TYPE_STRING and o["bonus"] == "cache" else 1.0
		_roll_into(_bonus, table, mult * _loot_scale, _rng_outcome)
	# lasting consequences and discoveries
	if o.has("mark"):
		_set_mark(str(o["mark"][0]), int(o["mark"][1]))
	_discover_extra += maxi(int(o.get("discover", 0)), 0)
	var line: String = o.get("log", "")
	if hurt > 0.0:
		line += " Hurt (-%d health)." % int(round(hurt))
	line += _used_text(used)
	for t in lost:
		line += " Lost the %s." % Items.name_of(t).to_lower()
	if line.strip_edges() != "":
		lines.append(line.strip_edges())
	choices.append(i)
	step += 1
	return {"ok": true, "text": text.strip_edges(), "hurt": hurt, "lost": lost, "ammo": used["ammo"], "shells": used["shells"]}


func _set_mark(flag: String, days: int) -> void:
	for other in D.FLAGS.get(flag, {}).get("clears", []):
		_marks.erase(other)
	_marks[flag] = maxi(int(_marks.get(flag, 0)), days)


static func _used_text(used: Dictionary) -> String:
	var s := ""
	if int(used.get("ammo", 0)) > 0:
		s += " %d round%s used." % [used["ammo"], "" if used["ammo"] == 1 else "s"]
	if int(used.get("shells", 0)) > 0:
		s += " %d shell%s used." % [used["shells"], "" if used["shells"] == 1 else "s"]
	return s


func _bonus_table(b: Variant) -> Array:
	if typeof(b) == TYPE_ARRAY:
		return b
	match str(b):
		"locked":
			return dest.get("locked", [])
		"cache":
			return dest.get("loot", [])
	return D.BONUS_TABLES.get(str(b), [])


## Rolls a loot table into `into` (id -> int). Always draws three values per
## entry. `item_mults` scales single items (targeted collection), `min_chance`
## raises an item's chance. Unique items: chance x min(mult, 1.5) (capped);
## stackables: amount x mult with stochastic rounding.
func _roll_into(into: Dictionary, table: Array, mult: float, rng: RandomNumberGenerator, item_mults := {}, min_chance := {}) -> void:
	for e in table:
		var id: String = e[0]
		var hit := rng.randf()
		var n := rng.randi_range(int(e[1]), int(e[2]))
		var frac := rng.randf()
		if not Items.has(id):
			continue
		var m := maxf(mult * float(item_mults.get(id, 1.0)), 0.0)
		var chance := maxf(float(e[3]), float(min_chance.get(id, 0.0)))
		if D.is_unique(id):
			if hit < minf(chance * minf(m, 1.5), D.UNIQUE_CHANCE_MAX):
				into[id] = 1
			continue
		if hit >= chance:
			continue
		var x := float(n) * m
		var k := int(floor(x)) + (1 if frac < x - floor(x) else 0)
		if k > 0:
			into[id] = int(into.get(id, 0)) + k


## Picks a not-yet-known place, preferring ones near the destination.
func _pick_discovery(taken: Array) -> String:
	var here: Vector2 = RegionLocations.get_def(dest_id).get("pos", RegionLocations.HOME)
	var ids := []
	var weights := []
	var total := 0.0
	for id in RegionLocations.ids():
		if _known.get(id, false) == true or id in taken or id == dest_id:
			continue
		var dist := (RegionLocations.get_def(id)["pos"] as Vector2).distance_to(here)
		var w := 1.0 / pow(1.0 + dist / 20.0, 2.0)
		ids.append(id)
		weights.append(w)
		total += w
	var x := _rng_discover.randf() * total
	if ids.is_empty():
		return ""
	for i in ids.size():
		x -= weights[i]
		if x < 0.0:
			return ids[i]
	return ids[-1]


# --- result ---------------------------------------------------------------------------

## The SPEC-002 §7.7 result, built once (after the last event) and cached.
## Additive fields: "brought", "depart_at"/"return_at" (total minutes), and
## for SPEC-003: "location" (= destination), "approach", "target",
## "stock_before", "stock_after", "discovered" (new place ids), "marks"
## ({flag: until_day}) and "day" (the return day).
func result() -> Dictionary:
	if not _result.is_empty():
		return _result
	while not is_finished():
		choose(first_available_option())
	var a := D.approach_def(approach)
	var stock_mult := maxf(_stock, 0.05)
	var base := float(a.get("loot", 1.0)) * _loot_scale * stock_mult
	var item_mults := {}
	var min_chance := {}
	if approach == "targeted" and target != "":
		for table in [dest.get("loot", []), dest.get("locked", [])]:
			for e in table:
				item_mults[e[0]] = float(a.get("other_mult", 0.5))
		item_mults[target] = float(a.get("target_mult", 1.8))
		min_chance[target] = float(a.get("target_chance", 0.9))
	var found := {}
	var mult := clampf(_loot_mult, D.LOOT_MULT_RANGE.x, D.LOOT_MULT_RANGE.y) * base
	_roll_into(found, dest.get("loot", []), mult, _rng_loot, item_mults, min_chance)
	var locked := {}
	var locked_roll := {}
	_roll_into(locked_roll, dest.get("locked", []), base, _rng_loot, item_mults)
	if int(gear.get("crowbar", 0)) > 0:      # opened on arrival, before any event
		locked = locked_roll
		if not locked.is_empty():
			lines.append(str(dest.get("locked_text", "The crowbar opened a locked door.")))
	var jitter := _rng_loot.randi_range(D.TRAVEL_JITTER.x, D.TRAVEL_JITTER.y)
	for src in [locked, _bonus]:
		for id in src:
			found[id] = int(found.get(id, 0)) + int(src[id])
	# backpack: +50 % on stackables (stochastic rounding from the loot stream)
	var backpack := has_tool("backpack")
	var ids := found.keys()
	ids.sort()
	for id in ids:
		var frac := _rng_loot.randf()
		if backpack and not D.is_unique(id):
			var x := float(found[id]) * (1.0 + D.BACKPACK_BONUS)
			found[id] = int(floor(x)) + (1 if frac < x - floor(x) else 0)
	# unique items: one each, only when not already owned (or lost on this trip)
	for id in ids:
		if D.is_unique(id):
			if _has.get(id, false) and not _lost.has(id):
				found.erase(id)
			else:
				found[id] = 1
	var gained := {}
	var left := {}
	for id in Items.DEFS:
		var n := int(found.get(id, 0))
		if n <= 0:
			continue
		var space := int(_space.get(id, 0))
		if D.is_unique(id) and _lost.has(id):
			space = maxi(space, 1)
		var fit := mini(n, space)
		if fit > 0:
			gained[id] = fit
		if n - fit > 0:
			left[id] = n - fit
	var consumed := {}
	for am in D.AMMO_TYPES:
		var k := mini(int(_spent[am]), int(_owned.get(am, 0)))
		if k > 0:
			consumed[am] = k
	var lost := {}
	for id in _lost:
		if int(_owned.get(id, 0)) > 0:
			lost[id] = 1
	var lo := maxi(D.MIN_MINUTES, 2 * int(dest.get("travel", 0)) + 10)
	var minutes := clampi(nominal_minutes + jitter + _minutes_delta, lo, maxi(nominal_minutes + 150, lo))
	if not left.is_empty():
		lines.append("Storage full: left behind %s." % D.items_text(left))
	var return_at := depart_at + minutes
	var day := int(floor(return_at / 1440.0)) + 1
	# the place: depletion and consequences
	var dep := float(dest.get("deplete", 0.2)) * float(a.get("deplete", 1.0)) * clampf(_loot_mult, 0.5, 1.25)
	var stock_after := snappedf(maxf(_stock - dep, minf(float(dest.get("floor", 0.1)), _stock)), 0.001)
	if stock_after < 0.25 and _stock >= 0.25:
		lines.append("There's little left here now: the %s is picked clean." % dest.get("place", "place"))
	elif stock_after < 0.5 and _stock >= 0.5:
		lines.append("The %s is picked over now." % dest.get("place", "place"))
	if a.has("mark"):
		if not _marks.has(str(a["mark"][0])) and not _clears_flag(str(a["mark"][0])):
			_marks[str(a["mark"][0])] = int(a["mark"][1])
	var marks := {}
	for f in _marks:
		marks[f] = day + int(_marks[f])
		match f:
			"guarded":
				lines.append("They'll be ready for you here for a while.")
			"cleared":
				lines.append("It should be quieter here for a few days.")
	# discoveries
	var discovered := []
	for c in a.get("discover", []):
		if _rng_discover.randf() < float(c):
			var p := _pick_discovery(discovered)
			if p != "":
				discovered.append(p)
	for i in _discover_extra:
		var p := _pick_discovery(discovered)
		if p != "":
			discovered.append(p)
	for p in discovered:
		lines.append("You spotted the way to %s. It's on your map now." % RegionLocations.name_of(p))
	var dmg := snappedf(clampf(_damage, 0.0, _max_damage), 0.1)
	_result = {
		"id": "exp-%d-%d-%s-%s-%d" % [_seed, _number, dest_id, approach, int(depart_at)],
		"destination": dest_id,
		"name": str(dest["name"]),
		"minutes": minutes,
		"gained": gained,
		"consumed": consumed,
		"lost": lost,
		"left_behind": left,
		"damage": dmg,
		"events": lines.duplicate(),
		"summary": _summary(minutes, gained, dmg, lost, discovered),
		"brought": gear.duplicate(),
		"depart_at": depart_at,
		"return_at": return_at,
		"location": dest_id,
		"approach": approach,
		"target": target,
		"stock_before": snappedf(_stock, 0.001),
		"stock_after": stock_after,
		"discovered": discovered,
		"marks": marks,
		"day": day,
	}
	return _result


## True if a flag already set on this trip clears `flag` (e.g. "cleared" beats
## the raid's "guarded": you fought your way through).
func _clears_flag(flag: String) -> bool:
	for f in _marks:
		if flag in D.FLAGS.get(f, {}).get("clears", []):
			return true
	return false


## "Back after 3 h 25 min with water, canned food and snacks. Hurt (-8 health)."
func _summary(minutes: int, gained: Dictionary, dmg: float, lost: Dictionary, discovered: Array) -> String:
	var ids := gained.keys()
	ids.sort_custom(func(a, b): return int(gained[a]) > int(gained[b]) or (int(gained[a]) == int(gained[b]) and a < b))
	var names := []
	for id in ids.slice(0, 3):
		names.append(Items.name_of(id).to_lower())
	var s := "Back after %s" % D.duration(minutes)
	if names.is_empty():
		s += " with nothing."
	elif ids.size() > 3:
		s += " with %s and more." % ", ".join(names)
	elif names.size() == 1:
		s += " with %s." % names[0]
	else:
		s += " with %s and %s." % [", ".join(names.slice(0, names.size() - 1)), names[-1]]
	if dmg >= 1.0:
		s += " Hurt (-%d health)." % int(round(dmg))
	if not lost.is_empty():
		s += " Lost the %s." % " and the ".join(lost.keys().map(func(id): return Items.name_of(id).to_lower()))
	if not discovered.is_empty():
		s += " Found the way to %s." % " and ".join(discovered.map(func(id): return RegionLocations.name_of(id)))
	return s
