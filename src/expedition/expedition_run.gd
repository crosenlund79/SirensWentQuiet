class_name ExpeditionRun
extends RefCounted
## One simulated expedition, from departure to the result (SPEC §7.7). Owner: E.
##
## Pure and deterministic: it reads a GameState once at `create` (inventory
## snapshot, clock, seed) and never mutates it. The result is applied by the
## game through `GameState.apply_expedition`, exactly once.
##
## Randomness comes from `state.run.seed` and `state.run.expeditions` (plus the
## destination), in three independent streams so the events met do not depend
## on the gear chosen, and the loot does not depend on the order of choices:
##   events   which events happen
##   outcome  injury and loss rolls, event bonus loot
##   loot     the main search, the locked table, travel time

const D := preload("res://src/expedition/expedition_data.gd")

var dest_id := ""
var dest := {}
var gear := {}                 ## what was brought: {"ammo": n, tool: 1}
var depart_at := 0.0           ## GameState.total_minutes at departure
var event_ids: Array[String] = []
var step := 0                  ## index of the next unanswered event
var choices: Array[int] = []
var lines: Array[String] = []  ## the report's "what happened"

var _seed := 0
var _number := 0
var _owned := {}               ## inventory counts at departure
var _space := {}               ## space_for at departure
var _energy := 100.0
var _danger := 1.0
var _minutes_delta := 0
var _loot_mult := 1.0
var _damage := 0.0
var _ammo_left := 0
var _ammo_spent := 0
var _lost := {}
var _bonus := {}
var _rng_events := RandomNumberGenerator.new()
var _rng_outcome := RandomNumberGenerator.new()
var _rng_loot := RandomNumberGenerator.new()
var _result := {}


## Prepares a run. `gear` is clamped to what the player owns (required tools
## are always brought). Returns null when the destination is unavailable now.
static func create(state: GameState, destination_id: String, wanted_gear := {}) -> ExpeditionRun:
	if not D.availability(state, destination_id)["ok"]:
		return null
	var r := ExpeditionRun.new()
	r._setup(state, destination_id, D.sanitize_gear(state, destination_id, wanted_gear))
	return r


## Runs a whole expedition with a fixed policy (tests, dev tools):
## `picks` gives option indices per event; missing or unavailable entries take
## the first available option. Returns the result ({} if unavailable).
static func simulate(state: GameState, destination_id: String, wanted_gear := {}, picks := []) -> Dictionary:
	var r := create(state, destination_id, wanted_gear)
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


func _setup(state: GameState, destination_id: String, g: Dictionary) -> void:
	dest_id = destination_id
	dest = D.destination(destination_id)
	gear = g
	depart_at = state.total_minutes
	_seed = int(state.run.get("seed", 0))
	_number = int(state.run.get("expeditions", 0))
	_energy = state.energy
	for id in Items.DEFS:
		_owned[id] = state.inventory.count(id)
		_space[id] = state.inventory.space_for(id)
	_ammo_left = int(gear.get("ammo", 0))
	_danger = float(dest["danger"]) * (D.LOW_ENERGY_DANGER if _energy <= D.LOW_ENERGY else 1.0)
	_rng_events.seed = _stream_seed(_seed, _number, dest_id, "events")
	_rng_outcome.seed = _stream_seed(_seed, _number, dest_id, "outcome")
	_rng_loot.seed = _stream_seed(_seed, _number, dest_id, "loot")
	_pick_events()


func _pick_events() -> void:
	var count := 2 if _rng_events.randf() < float(dest.get("two_events", 0.5)) else 1
	var pool: Dictionary = dest["events"].duplicate()
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


func ammo_left() -> int:
	return _ammo_left


## {"ok": bool, "reason": String} for option `i` of the current event.
func option_state(i: int) -> Dictionary:
	var ev := current_event()
	var opts: Array = ev.get("options", [])
	if i < 0 or i >= opts.size():
		return {"ok": false, "reason": "No such option."}
	var needs: Dictionary = opts[i].get("needs", {})
	for id in needs:
		if id == "ammo":
			var n := int(needs[id])
			if _ammo_left < n:
				return {"ok": false, "reason": "Needs %d round%s (you have %d)" % [n, "" if n == 1 else "s", _ammo_left]}
		elif not has_tool(id):
			var nm := Items.name_of(id).to_lower()
			if _lost.has(id):
				return {"ok": false, "reason": "You lost the %s" % nm}
			if int(_owned.get(id, 0)) > 0:
				return {"ok": false, "reason": "You left the %s at home" % nm}
			return {"ok": false, "reason": "Needs a %s" % nm}
	return {"ok": true, "reason": ""}


func first_available_option() -> int:
	var opts: Array = current_event().get("options", [])
	for i in opts.size():
		if option_state(i)["ok"]:
			return i
	return -1


## Answers the current event. Returns {"ok", "text", "hurt": float, "lost": [ids], "ammo": n}.
## Draws a fixed number of random values per option so results stay stable.
func choose(i: int) -> Dictionary:
	if is_finished() or not option_state(i)["ok"]:
		return {"ok": false, "text": "", "hurt": 0.0, "lost": [], "ammo": 0}
	var ev := current_event()
	var tags: Array = ev.get("tags", [])
	var o: Dictionary = ev["options"][i]
	var text: String = o.get("outcome", "")
	var spent := 0
	var lost := []
	# rounds the option itself uses
	var use := mini(int(o.get("ammo", 0)), _ammo_left)
	if use > 0:
		_ammo_left -= use
		_ammo_spent += use
		spent += use
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
			if "fight" in tags and use == 0 and _ammo_left > 0:
				_ammo_left -= 1
				_ammo_spent += 1
				spent += 1
				hurt *= D.FIGHT_AMMO_SCALE
				text += " " + o.get("hurt_text", "You get hurt.") + " You fire once to get clear."
			else:
				text += " " + o.get("hurt_text", "You get hurt.")
			hurt = minf(hurt, D.MAX_DAMAGE - _damage)
			_damage += hurt
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
		_roll_into(_bonus, table, mult, _rng_outcome)
	var line: String = o.get("log", "")
	if hurt > 0.0:
		line += " Hurt (-%d health)." % int(round(hurt))
	if spent > 0:
		line += " %d round%s used." % [spent, "" if spent == 1 else "s"]
	for t in lost:
		line += " Lost the %s." % Items.name_of(t).to_lower()
	if line.strip_edges() != "":
		lines.append(line.strip_edges())
	choices.append(i)
	step += 1
	return {"ok": true, "text": text.strip_edges(), "hurt": hurt, "lost": lost, "ammo": spent}


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
## entry. Tools: chance scaled down by mult < 1, never more than one.
func _roll_into(into: Dictionary, table: Array, mult: float, rng: RandomNumberGenerator) -> void:
	for e in table:
		var id: String = e[0]
		var hit := rng.randf()
		var n := rng.randi_range(int(e[1]), int(e[2]))
		var frac := rng.randf()
		if not Items.has(id):
			continue
		if Items.category(id) == "tool":
			if hit < float(e[3]) * minf(mult, 1.0):
				into[id] = 1
			continue
		if hit >= float(e[3]):
			continue
		var x := float(n) * mult
		var k := int(floor(x)) + (1 if frac < x - floor(x) else 0)
		if k > 0:
			into[id] = int(into.get(id, 0)) + k


# --- result ---------------------------------------------------------------------------

## The SPEC §7.7 result. Built once (after the last event) and cached.
## Additive fields: "brought" (the gear taken) and "depart_at"/"return_at" (total minutes).
func result() -> Dictionary:
	if not _result.is_empty():
		return _result
	while not is_finished():
		choose(first_available_option())
	var found := {}
	var mult := clampf(_loot_mult, D.LOOT_MULT_RANGE.x, D.LOOT_MULT_RANGE.y)
	_roll_into(found, dest.get("loot", []), mult, _rng_loot)
	var locked := {}
	var locked_roll := {}
	_roll_into(locked_roll, dest.get("locked", []), 1.0, _rng_loot)
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
		if backpack and Items.category(id) != "tool":
			var x := float(found[id]) * (1.0 + D.BACKPACK_BONUS)
			found[id] = int(floor(x)) + (1 if frac < x - floor(x) else 0)
	# tools: one each, only when not already owned (or lost on this trip)
	for id in ids:
		if Items.category(id) == "tool":
			if int(_owned.get(id, 0)) - int(_lost.get(id, 0)) > 0:
				found.erase(id)
			else:
				found[id] = 1
	var gained := {}
	var left := {}
	for id in Items.DEFS:
		var n := int(found.get(id, 0))
		if n <= 0:
			continue
		var fit := mini(n, int(_space.get(id, 0)))
		if fit > 0:
			gained[id] = fit
		if n - fit > 0:
			left[id] = n - fit
	var consumed := {}
	if _ammo_spent > 0:
		consumed["ammo"] = mini(_ammo_spent, int(_owned.get("ammo", 0)))
	var lost := {}
	for id in _lost:
		if int(_owned.get(id, 0)) > 0:
			lost[id] = 1
	var minutes := clampi(int(dest["minutes"]) + jitter + _minutes_delta, D.MIN_MINUTES, int(dest["minutes"]) + 150)
	if not left.is_empty():
		lines.append("Storage full: left behind %s." % D.items_text(left))
	var dmg := snappedf(clampf(_damage, 0.0, D.MAX_DAMAGE), 0.1)
	_result = {
		"id": "exp-%d-%d-%s-%d" % [_seed, _number, dest_id, int(depart_at)],
		"destination": dest_id,
		"name": str(dest["name"]),
		"minutes": minutes,
		"gained": gained,
		"consumed": consumed,
		"lost": lost,
		"left_behind": left,
		"damage": dmg,
		"events": lines.duplicate(),
		"summary": _summary(minutes, gained, dmg, lost),
		"brought": gear.duplicate(),
		"depart_at": depart_at,
		"return_at": depart_at + minutes,
	}
	return _result


## "Back after 3 h 25 min with water, canned food and snacks. Hurt (-8 health)."
func _summary(minutes: int, gained: Dictionary, dmg: float, lost: Dictionary) -> String:
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
	return s
