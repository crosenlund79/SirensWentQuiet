class_name OffscreenHome
extends RefCounted
## Exp 007 (T): what happens to the house while Eli is away (the user's §9).
##
## One simple rule, no combat for an invisible house:
## - While Eli travels or is at a POI, every invasion that falls due and every
##   night straggler is recorded in a ledger in `state.run["away"]` (saved
##   with the run, so a save at a POI keeps it) instead of being fought. An
##   invasion is started and ended at once on the GameState, so the schedule
##   moves on exactly as if it had been fought. Dawns are recorded too (the
##   rain collectors still fill).
## - Back home, after the house is restored from its snapshot, each recorded
##   attack is resolved in order:
##     threat   invasion: its size (GameState.invasion_size at that time);
##              straggler: 1. Exp 008 (E): as at home, a straggler turns on the
##              house only PROWL_ATTACK of the time; else it prowls round and
##              leaves (driven off sooner by turrets with ammo, which spend a
##              couple of rounds): no blows, one short line
##     defence  `defence(world)["score"]`: closed doors and window boards and
##              barricades standing (by HP and material), spikes, raised
##              drawbridges (more with water in the moat), the outer walls'
##              integrity x material, open doors count against it, plus agent
##              S's Security.offscreen_strength(world)["score"] when present.
##              Exp 008 (E): the trenches themselves, water most (MOAT_*),
##              much less while a drawbridge over the water is lowered
##     strikes  round(threat x STRIKES_PER_THREAT x (1 - held)), held =
##              D / (D + threat x 1.5); an invasion always lands at least one.
##   The strikes go through the world's own API: `enemy_strike` at the
##   weakest `weak_points` (doors and boards first, then walls), so damage,
##   debris, navigation and the save are the real ones. Turrets spend ammo
##   through S's Security.consume_offscreen(world, rounds) when present.
## - The report is a few short lines ("While you were away: Day 3, 22:00:
##   they came, 5 of them. They broke a door. The walls took 4 blows."). A
##   trip on which nothing fell due reports nothing alarming: no attacks, at
##   most the rain collectors and someone who prowled round and left.

const STRIKES_PER_THREAT := 2.0
const MAX_STRIKES := 16
const STRIKE_STRENGTH := 2.0
const DAY_MIN := 1440.0
const DOOR_MAT := {"wood": 1.0, "iron": 1.6, "metal": 2.0}
const WALL_MAT := {"wood": 1.0, "frame": 1.0, "stone": 1.5}
## Exp 008 (E): a straggler turns on the empty house this often (StragglerMind.RESTLESS at home).
const PROWL_ATTACK := 0.3
const PROWL_ROUNDS := 2           ## rounds turrets spend driving a prowler off
## Exp 008 (E): trench cells around the house: per cell and at most, water and dry.
const MOAT_PER_CELL := 0.05
const MOAT_MAX := 2.5
const TRENCH_PER_CELL := 0.01
const TRENCH_MAX := 0.5
const MOAT_LOWERED := 0.4         ## x the moat's share while a drawbridge over water is lowered


# --- the ledger (recorded while away) ----------------------------------------------------

static func is_away(state: GameState) -> bool:
	return typeof(state.run.get("away")) == TYPE_DICTIONARY


## Opens the ledger (when Eli leaves home); kept if one is already open.
static func begin(state: GameState) -> void:
	if not is_away(state):
		state.run["away"] = {"since": state.total_minutes, "events": []}


static func events(state: GameState) -> Array:
	if not is_away(state):
		return []
	var e = (state.run["away"] as Dictionary).get("events", [])
	return e if typeof(e) == TYPE_ARRAY else []


## An invasion fell due while away: it happens at the house, offscreen. The
## schedule moves on (start + end on the state). Returns the ledger entry.
static func record_invasion(state: GameState, at := -1.0) -> Dictionary:
	begin(state)
	var e := {"type": "invasion", "at": at if at >= 0.0 else state.total_minutes, "size": state.invasion_size(),
		"index": state.invasion_index()}
	state.start_invasion()
	state.end_invasion(false)
	_append(state, e)
	return e


static func record_straggler(state: GameState, at: float) -> Dictionary:
	begin(state)
	var e := {"type": "straggler", "at": at, "size": 1}
	_append(state, e)
	return e


static func record_dawn(state: GameState, at: float) -> void:
	begin(state)
	_append(state, {"type": "dawn", "at": at})


static func _append(state: GameState, e: Dictionary) -> void:
	var a: Dictionary = state.run["away"]
	var l: Array = a.get("events", []) if typeof(a.get("events")) == TYPE_ARRAY else []
	l.append(e)
	while l.size() > 64:
		l.pop_front()
	a["events"] = l


## Closes the ledger (back home, after resolve()).
static func finish(state: GameState) -> void:
	state.run.erase("away")


# --- resolving it (back home) --------------------------------------------------------------

## The house's passive defence: {"score", "doors", "boards", "spikes",
## "bridges" (raised), "lowered" (drawbridges down), "moat" (wet cells),
## "trench" (dry cells), "walls" (0..1 integrity), "open_doors", "security"}.
static func defence(world: HouseWorld, worlds: Array = []) -> Dictionary:
	var out := {"score": 0.0, "doors": 0, "boards": 0, "spikes": 0, "bridges": 0, "lowered": 0, "moat": 0, "trench": 0,
		"walls": 0.0, "open_doors": 0, "security": 0.0}
	if world == null:
		return out
	var score := 0.0
	var wet := world.defense != null and world.defense.wet_count() > 0
	for o in world.objects:
		var hp := clampf(float(o.hp) / maxf(float(o.max_hp), 1.0), 0.0, 1.0)
		match o.kind:
			"door":
				if o.open:
					out["open_doors"] += 1
					score -= 0.75
				else:
					out["doors"] += 1
					score += 1.0 * hp * float(DOOR_MAT.get(o.mat, 1.0))
			"boards", "barricade":
				out["boards"] += 1
				score += 0.6 * hp * float(DOOR_MAT.get(o.mat, 1.0))
			"spikes_wood", "spikes_metal":
				out["spikes"] += 1
				score += (0.8 if o.kind == "spikes_metal" else 0.5) * hp
			"drawbridge_1", "drawbridge_2":
				if not o.open:
					out["bridges"] += 1
					score += (1.5 if wet else 0.5) * hp
				else:
					out["lowered"] += 1
	if world.defense != null:          # Exp 008 (E): the trenches and the moat themselves
		var wet_n: int = world.defense.wet_count()
		out["moat"] = wet_n
		out["trench"] = world.defense.cells.size() - wet_n
		var moat := minf(wet_n * MOAT_PER_CELL, MOAT_MAX) * (MOAT_LOWERED if wet_n > 0 and int(out["lowered"]) > 0 else 1.0)
		score += moat + minf(int(out["trench"]) * TRENCH_PER_CELL, TRENCH_MAX)
	var n := 0
	var sum := 0.0
	var mat_sum := 0.0
	for s in world.sections:
		if int(world.sections[s].get("design", 0)) <= 0 or not world._is_outer_wall(s):
			continue
		n += 1
		sum += clampf(world.section_integrity(s), 0.0, 1.0)
		var m := float(WALL_MAT.get(str(world.sections[s].get("material", "wood")), 1.0))
		if world.upgraded.has(s):
			m += 0.5
		mat_sum += m
	if n > 0:
		out["walls"] = sum / n
		score += 2.0 * (sum / n) * (mat_sum / n)
	var sec := security_strength(worlds if not worlds.is_empty() else world)
	out["security"] = float(sec.get("score", 0.0))
	score += out["security"]
	out["score"] = maxf(score, 0.0)
	return out


## Agent S's offscreen turret/sensor strength (Security.offscreen_strength:
## a world or an Array of the storeys).
static func security_strength(world: Variant) -> Dictionary:
	var r: Variant = Security.offscreen_strength(world)
	return r if typeof(r) == TYPE_DICTIONARY else {}


## How many blows one attack lands on the house.
static func strikes_for(threat: float, defence_score: float, invasion: bool) -> int:
	var held := defence_score / maxf(defence_score + threat * 1.5, 0.001)
	var n := roundi(threat * STRIKES_PER_THREAT * (1.0 - held))
	return clampi(n, 1 if invasion else 0, MAX_STRIKES)


## Resolves the ledger on the restored home world. Returns {"lines": [String],
## "strikes": n, "destroyed": [kinds], "water": n, "attacks": n, "prowlers": n
## (stragglers that only prowled round), "rounds": n (turret rounds spent)}.
## `seed` keeps it deterministic.
static func resolve(world: HouseWorld, state: GameState, seed := 0, worlds: Array = []) -> Dictionary:
	var out := {"lines": [], "strikes": 0, "destroyed": [], "water": 0, "attacks": 0, "prowlers": 0, "rounds": 0}
	var driven := 0
	var evs := events(state).duplicate()
	evs.sort_custom(func(a, b): return float(a.get("at", 0.0)) < float(b.get("at", 0.0)))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for e in evs:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var kind := str(e.get("type", ""))
		var at := float(e.get("at", state.total_minutes))
		if kind == "dawn":
			if world != null:
				var got: Dictionary = state.on_dawn(world.count_objects("rain_collector"), at)
				out["water"] += int(got.get("water", 0))
			continue
		if kind != "invasion" and kind != "straggler" or world == null:
			continue
		if kind == "straggler" and rng.randf() >= PROWL_ATTACK:     # Exp 008 (E): it only prowled round
			out["prowlers"] += 1
			var spent := _turret_rounds(world, worlds, PROWL_ROUNDS)
			out["rounds"] += spent
			if spent > 0:
				driven += 1
			continue
		out["attacks"] += 1
		var r := _attack(world, state, kind == "invasion", maxf(float(e.get("size", 1)), 1.0), rng, worlds)
		out["strikes"] += int(r["strikes"])
		out["rounds"] += int(r.get("rounds", 0))
		out["destroyed"].append_array(r["destroyed"])
		out["lines"].append(_line(kind, at, int(e.get("size", 1)), r))
	if int(out["prowlers"]) > 0:
		var n := int(out["prowlers"])
		var who := "Someone prowled round the house" if n == 1 else "Twice someone prowled round the house" if n == 2 else "Someone prowled round the house %d times" % n
		out["lines"].append(who + ("; the turrets drove them off." if driven > 0 else " and left."))
	if out["water"] > 0:
		out["lines"].append("The rain collectors gave %d water." % out["water"])
	return out


## Exp 008 (E): turrets with ammo spend up to `rounds` (0 without any).
static func _turret_rounds(world: HouseWorld, worlds: Array, rounds: int) -> int:
	var all: Variant = worlds if not worlds.is_empty() else world
	var strength := security_strength(all)
	if int(strength.get("turrets", 0)) <= 0:
		return 0
	var n := mini(int(strength.get("ammo", 0)), rounds)
	return Security.consume_offscreen(all, n) if n > 0 else 0


static func _attack(world: HouseWorld, state: GameState, invasion: bool, threat: float, rng: RandomNumberGenerator, worlds: Array = []) -> Dictionary:
	var d := defence(world, worlds)
	var n := strikes_for(threat, float(d["score"]), invasion)
	var before := int(world.damage_summary().get("missing_voxels", 0))
	var destroyed := []
	var listener := func(k: String, _at: Vector3): destroyed.append(k)
	world.object_destroyed.connect(listener)
	var from: Vector2 = HousePlan.SPAWN_POINTS[rng.randi() % HousePlan.SPAWN_POINTS.size()] if not HousePlan.SPAWN_POINTS.is_empty() else Vector2(-3, -2)
	for k in n:
		var pts := world.weak_points(from)
		if pts.is_empty():
			break
		var wp: Dictionary = pts[mini(rng.randi() % 3, pts.size() - 1)]
		var stand: Vector2 = wp["pos"]
		world.enemy_strike(Vector3(stand.x, 0.0, stand.y), wp["target"], STRIKE_STRENGTH if invasion else 1.0)
	world.object_destroyed.disconnect(listener)
	var rounds := _turret_rounds(world, worlds, int(ceil(threat * 2.0)))
	var after := int(world.damage_summary().get("missing_voxels", 0))
	return {"strikes": n, "destroyed": destroyed, "voxels": maxi(after - before, 0), "rounds": rounds, "defence": d["score"]}


static func _line(kind: String, at: float, size: int, r: Dictionary) -> String:
	var when := "Day %d, %s" % [int(floorf(at / DAY_MIN)) + 1, TravelRules.clock(at)]
	var who := ("they came, %d of them" % size) if kind == "invasion" else "one of them prowled around"
	var parts := []
	var broke := {}
	for k in r["destroyed"]:
		var nm := str(WorldObject.DEFS.get(k, {}).get("name", str(k).replace("_", " "))).to_lower()
		broke[nm] = int(broke.get(nm, 0)) + 1
	if not broke.is_empty():
		var names := []
		for nm in broke:
			names.append(("a " + nm) if broke[nm] == 1 else "%d %ss" % [broke[nm], nm])
		parts.append("they broke " + " and ".join(names))
	if int(r["voxels"]) > 0:
		parts.append("the walls took %d blow%s" % [r["strikes"], "" if r["strikes"] == 1 else "s"])
	elif int(r["strikes"]) > 0 and broke.is_empty():
		parts.append("the doors and boards took %d blow%s" % [r["strikes"], "" if r["strikes"] == 1 else "s"])
	if int(r.get("rounds", 0)) > 0:
		parts.append("the turrets fired %d rounds" % r["rounds"])
	if parts.is_empty():
		parts.append("the house held")
	return "%s: %s; %s." % [when, who, "; ".join(parts)]
