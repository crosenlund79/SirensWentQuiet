extends RefCounted
## Invasion director (SPEC-003 §5; Experiment 002 SPEC §6 "Invasions"). Pure
## logic: the game asks it what to spawn this frame and where, and spawns it
## through the roster. Docs: docs/experiment-003/ai.md.
##
## Threat budget (Experiment 003): `begin_wave(level, invasion, seed)` builds
## the wave from Difficulty.threat_budget + threat_budget_step x (invasion - 1)
## and the archetype costs (EnemyDefs: psycho 1, runner 1.5, brute 3,
## bomber 4), deterministically from the seed:
##   - every wave starts with one psycho, and never with a bomber;
##   - runners from `special_from_invasion`, brutes one invasion later at the
##     earliest (the very first wave stays light), bombers from
##     `bomber_from_invasion` (Easy: invasion 4, i.e. not in the opening days);
##   - per-wave caps: brutes 1 + (k - first) / 2, bombers likewise;
##   - a head-count cap from the Experiment 002 sizes x `enemy_count`
##     (3, 5, 7 ... on Normal), so the first waves stay small; leftover budget
##     (from invasion 2) upgrades psychos to runners.
## `begin(count, hp, speed, seed)` is the Experiment 002 call (that many
## psychos) and still works.
##
## Exp 012 (G), whole-group hordes (ASSIGNMENT §10): the WHOLE wave exists from
## the start. The first tick after begin releases every member at once
## (tick_kinds returns the whole wave); pick_spawn then hands out a planned
## start point per member, in wave order. A kill never spawns anyone.
##   - The plan (plan_spawns) splits the wave into 1-4 approach groups on
##     different sides of the house (road = south, woods = north, gardens =
##     east / west), each member at its own point and distance: the fog band
##     between the lot and the yard's edge, or a garden spot inside the lot
##     far from Eli and out of his view. Never within MIN_SPAWN_DISTANCE of
##     Eli; never where `view_check` (the game: the camera frustum, the fog)
##     says he would see it appear, when any hidden point is left.
##   - Arrival times vary naturally: the distances differ, and each member
##     waits a short start delay (`plan[i]["delay"]`, a few seconds per group
##     and member; bombers a little later). The game hands the spawned body to
##     note_spawned(); the director holds it in place (AIEnemy.set_goal) and
##     lets it go when its delay is over (tick).
##   - Distant members are cheap: a far member re-paths less often (tick).
##   - `side_of` (set by the siege, src/siege/) fixes each member's group;
##     `sides` forces the number of groups.
##
## - Fog points are HousePlan.SPAWN_POINTS in the fog band: outside the lot
##   (FogBoundary.LOT) but inside the navigable YARD.
## - `straggler_at()` decides, deterministically from the run seed and the day,
##   whether a lone psycho comes on a non-invasion night (from Day 2, 35 %,
##   between 23:00 and 03:00).

const T := preload("res://src/survival/survival_tuning.gd")
const DAY_MIN := 1440.0
const FIRST_DELAY := 2.5            ## s: the longest a member waits before the first one moves (kept for callers)
const MIN_SPAWN_DISTANCE := 7.0     ## m from the player
const STRAGGLER_FROM := 23.0 * 60.0
const STRAGGLER_SPAN := 4.0 * 60.0  ## 23:00 .. 03:00
const GROUP_GAP := Vector2(1.2, 2.6)   ## s between members of one group leaving (start delays)
const GROUP_JITTER := 0.9           ## m around a planned point
## Relative pick weights when composing a wave.
const WEIGHTS := {"psycho": 3.0, "runner": 2.0, "brute": 1.4, "bomber": 1.2}
const MAX_COUNT := 14
## Exp 012 (G): whole-group hordes.
const GROUP_DELAY := 7.0            ## s: group k waits up to k x this before it sets off
const BOMBER_DELAY := 5.0           ## s more for bombers (they come later in the wave)
const HIDDEN_IN_FOG := 10.0         ## m: a point in the fog band this far from Eli is hidden even in view
const FOG_DEEP := 1.2               ## m outside the lot: deep enough in the fog bank to hide a body
const LOT_SPAWN_MIN := 12.0         ## m: a garden spot inside the lot only this far from Eli
const SPREAD := 1.6                 ## m between two members' start points (at least)
const FAR := 16.0                   ## m: members farther from Eli re-path less often
const FAR_REPATH := 3.0             ## x their re-path interval while far
const SIDES := {"north": Vector2(0, -1), "east": Vector2(1, 0), "south": Vector2(0, 1), "west": Vector2(-1, 0)}
const ZONE_OF_SIDE := {"north": "woods", "east": "gardens", "south": "road", "west": "gardens"}

var active := false
var total := 0
var spawned := 0
var hp := Tuning.ENEMY_HP           ## legacy waves: every psycho's hp
var speed := 1.0                    ## legacy waves: every psycho's speed scale
## Tests and the playtest shorten the start delays (scaled to gap.y / 40 s);
## Vector2.ZERO = the normal delays.
var gap_override := Vector2.ZERO
var rng := RandomNumberGenerator.new()
var wave: Array = []                ## kinds in spawn order
var groups: Array = []              ## approach group sizes, in order (filled by the plan)
var level := "normal"
var invasion := 1
var budget := 0.0                   ## this wave's threat budget (0 = a legacy wave)
var last_kinds: Array = []          ## what the last tick released
## Exp 012 (G): the start plan, one entry per wave member, made when the wave
## is released: {"kind", "pos", "group", "side", "zone", "delay"}.
var plan: Array = []
## (Vector2 plan point) -> bool: would Eli see a body appear there now? The
## game sets it (camera frustum, fog); empty = nothing is "in view".
var view_check: Callable
## Optional: start points must be walkable on this nav (the game's world nav).
var nav: GridNav = null
## Optional, from the siege: the group index per wave member, and their sides
## ("north" ...). Empty = the director groups the wave itself.
var side_of: Array = []
var group_sides: Array = []
var sides := 0                      ## >0: exactly this many approach groups
var released := []                  ## [{"enemy", "i", "left"}]: members still waiting to set off
var _legacy := true
var _cursor := 0                    ## next plan entry pick_spawn hands out
var _released_all := false


## Experiment 002: `count` psychos with `enemy_hp` and `speed_scale`.
func begin(count: int, enemy_hp: int, speed_scale: float, seed: int) -> void:
	var kinds := []
	for i in maxi(count, 0):
		kinds.append("psycho")
	_start(kinds, seed)
	_legacy = true
	budget = 0.0
	hp = maxi(enemy_hp, 1)
	speed = speed_scale


## Experiment 003: a wave composed from the threat budget of `lv` and
## invasion `inv` (1-based), or exactly `kinds` if given (dev menu, sieges).
func begin_wave(lv: String, inv: int, seed: int, kinds: Array = []) -> void:
	level = Difficulty.valid(lv)
	invasion = maxi(inv, 1)
	var w := kinds.filter(func(k): return EnemyDefs.has(str(k))) if not kinds.is_empty() else compose(level, invasion, seed)
	_start(w, seed)
	_legacy = false
	budget = threat_budget(level, invasion)
	var st := EnemyDefs.stats("psycho", level, invasion)
	hp = st["hp"]
	speed = st["speed_scale"]


func _start(kinds: Array, seed: int) -> void:
	active = true
	wave = kinds.duplicate()
	total = wave.size()
	spawned = 0
	groups = []
	plan = []
	released = []
	_cursor = 0
	_released_all = false
	last_kinds = []
	rng.seed = seed


## Ends the wave. Members still waiting to set off are let go.
func finish() -> void:
	active = false
	for r in released:
		var e = r["enemy"]
		if is_instance_valid(e) and e.has_method("clear_goal") and str(e.get("directed_why")) == "wait":
			e.clear_goal()
	released = []
	side_of = []
	group_sides = []
	sides = 0


## Kept for callers: the start-delay scale's reference (s).
func gap() -> Vector2:
	return gap_override if gap_override != Vector2.ZERO else T.INVASION_SPAWN_GAP


func all_spawned() -> bool:
	return spawned >= total


func remaining_to_spawn() -> int:
	return maxi(total - spawned, 0)


## Real seconds elapse. The first call after begin releases the whole wave
## (returns its size, the kinds in `last_kinds`); later calls release no one
## and only count down the start delays of the members handed to note_spawned.
func tick(delta: float) -> int:
	last_kinds = []
	_tick_holds(delta)
	if not active or spawned >= total:
		return 0
	last_kinds = wave.slice(spawned)
	var n := total - spawned
	spawned = total
	return n


## The kinds to spawn now: the whole wave on the first tick, [] afterwards.
func tick_kinds(delta: float) -> Array:
	tick(delta)
	return last_kinds


## Roster options for a member of this wave (roster.spawn_type's opts).
func spawn_opts(_kind := "psycho") -> Dictionary:
	if _legacy:
		return {"hp": hp, "speed": speed, "invader": true}
	return {"level": level, "invasion": invasion, "invader": true}


## Lets every waiting member go within `seconds` (tests, playtest).
func hurry(seconds: float) -> void:
	for r in released:
		r["left"] = minf(float(r["left"]), seconds)


## The game spawned the member pick_spawn last placed (or member `i`): it
## waits there for its start delay, then sets off (AIEnemy.set_goal "wait").
func note_spawned(e: Node, i := -1) -> void:
	if i < 0:
		i = _cursor - 1
	if e == null or i < 0 or i >= plan.size():
		return
	var d := float(plan[i]["delay"]) * _delay_scale()
	e.set_meta("horde_group", int(plan[i]["group"]))
	e.set_meta("horde_side", str(plan[i]["side"]))
	if d > 0.05 and e.has_method("set_goal"):
		e.call("set_goal", plan[i]["pos"], "wait")
		released.append({"enemy": e, "i": i, "left": d})


func _delay_scale() -> float:
	return clampf(gap().y / T.INVASION_SPAWN_GAP.y, 0.0, 1.0) if gap_override != Vector2.ZERO else 1.0


func _tick_holds(delta: float) -> void:
	for k in range(released.size() - 1, -1, -1):
		var r: Dictionary = released[k]
		var e = r["enemy"]
		if not is_instance_valid(e):
			released.remove_at(k)
			continue
		r["left"] = float(r["left"]) - delta
		if float(r["left"]) <= 0.0 or not bool(e.get("alive")):
			if str(e.get("directed_why")) == "wait":
				e.call("clear_goal")
			released.remove_at(k)


## Exp 012 (G): far members re-path less often (cheap distant processing).
## `members` are AIEnemy bodies, `eli` Eli's plan position.
static func throttle(members: Array, eli: Vector2) -> int:
	var n := 0
	for e in members:
		if not is_instance_valid(e) or not (e is AIEnemy) or not e.alive or e.brain == null:
			continue
		var a := e as AIEnemy
		if not a.has_meta("base_repath"):
			a.set_meta("base_repath", a.brain.repath_interval)
		var base := float(a.get_meta("base_repath"))
		var far := a.plan_pos().distance_to(eli) > FAR
		a.brain.repath_interval = base * (FAR_REPATH if far else 1.0)
		if far:
			n += 1
	return n


# --- composition -----------------------------------------------------------------------

static func threat_budget(lv: String, inv: int) -> float:
	var base := float(Difficulty.get_value(lv, "threat_budget"))
	var step := float(Difficulty.get_value(lv, "threat_budget_step"))
	return base + step * float(maxi(inv, 1) - 1)


## Head-count cap: Experiment 002's invasion sizes (3, 5, 7 ...) x enemy_count.
static func max_count(lv: String, inv: int) -> int:
	var base := float(T.INVASION_BASE_SIZE + T.INVASION_SIZE_STEP * (maxi(inv, 1) - 1))
	return clampi(roundi(base * float(Difficulty.get_value(lv, "enemy_count"))), 2, MAX_COUNT)


## First invasion index at which `kind` may appear on `lv`.
static func first_invasion(lv: String, kind: String) -> int:
	var special := int(Difficulty.get_value(lv, "special_from_invasion"))
	match kind:
		"runner":
			return special
		"brute":
			return maxi(special, 2)
		"bomber":
			return int(Difficulty.get_value(lv, "bomber_from_invasion"))
	return 1


static func allowed(lv: String, inv: int) -> Array:
	return EnemyDefs.KINDS.filter(func(k): return inv >= first_invasion(lv, k))


static func kind_cap(lv: String, inv: int, kind: String) -> int:
	if kind == "brute" or kind == "bomber":
		return 1 + int(floorf(maxi(inv - first_invasion(lv, kind), 0) / 2.0))
	return MAX_COUNT


static func wave_cost(kinds: Array) -> float:
	var c := 0.0
	for k in kinds:
		c += EnemyDefs.cost(str(k))
	return c


## The wave for (lv, inv, seed), in spawn order. Pure and deterministic.
static func compose(lv: String, inv: int, seed: int) -> Array:
	lv = Difficulty.valid(lv)
	inv = maxi(inv, 1)
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed, lv, inv, "wave"])
	var left := threat_budget(lv, inv)
	var cap := max_count(lv, inv)
	var kinds := allowed(lv, inv)
	var out := ["psycho"]
	left -= EnemyDefs.cost("psycho")
	var counts := {"psycho": 1}
	while out.size() < cap:
		var opts := []
		var total_w := 0.0
		for k in kinds:
			if EnemyDefs.cost(k) <= left + 1e-6 and int(counts.get(k, 0)) < kind_cap(lv, inv, k):
				opts.append(k)
				total_w += WEIGHTS[k]
		if opts.is_empty():
			break
		var x := r.randf() * total_w
		var pick: String = opts[opts.size() - 1]
		for k in opts:
			x -= WEIGHTS[k]
			if x <= 0.0:
				pick = k
				break
		out.append(pick)
		counts[pick] = int(counts.get(pick, 0)) + 1
		left -= EnemyDefs.cost(pick)
	# Leftover budget (later waves): psychos become runners.
	if inv >= 2 and kinds.has("runner"):
		var up := EnemyDefs.cost("runner") - EnemyDefs.cost("psycho")
		for i in range(1, out.size()):
			if left < up - 1e-6:
				break
			if out[i] == "psycho":
				out[i] = "runner"
				left -= up
	return _order(out, r)


## Shuffled, the anchor psycho first, bombers not before a third of the wave.
static func _order(kinds: Array, r: RandomNumberGenerator) -> Array:
	var rest := kinds.slice(1)
	for i in range(rest.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var t = rest[i]
		rest[i] = rest[j]
		rest[j] = t
	var bombers := rest.filter(func(k): return k == "bomber")
	rest = rest.filter(func(k): return k != "bomber")
	var out := [kinds[0]] + rest
	var earliest := maxi(1, int(floorf(kinds.size() / 3.0)))
	for b in bombers:
		var at := r.randi_range(mini(earliest, out.size()), out.size())
		out.insert(at, b)
	return out


## Group sizes for a wave of n: one alone first, then pairs (n <= 7) or threes.
static func group_sizes(n: int) -> Array:
	if n <= 3:
		return _ones(n)
	var g := 2 if n <= 7 else 3
	var out := [1]
	var left := n - 1
	while left > 0:
		out.append(mini(g, left))
		left -= g
	return out


static func _ones(n: int) -> Array:
	var out := []
	for i in maxi(n, 1):
		out.append(1)
	return out


# --- spawn points --------------------------------------------------------------------

static func fog_points() -> Array:
	var out := []
	for p in HousePlan.SPAWN_POINTS:
		if not FogBoundary.LOT.has_point(p) and HousePlan.YARD.has_point(p):
			out.append(p)
	return out


## Fog points sorted nearest first, at least `min_d` m from `p` (all of them if none qualify).
static func nearest_fog_points(p: Vector2, min_d := 6.0) -> Array:
	var pts := fog_points()
	var far := pts.filter(func(q): return (q as Vector2).distance_to(p) >= min_d)
	if far.is_empty():
		far = pts
	far.sort_custom(func(a, b): return (a as Vector2).distance_to(p) < (b as Vector2).distance_to(p))
	return far


## The start point of the next wave member (in wave order): the first call
## after a release makes the plan (plan_spawns) around `player`. Calls beyond
## the wave get a random fog point at least MIN_SPAWN_DISTANCE away.
func pick_spawn(player: Vector2) -> Vector2:
	if _cursor == 0 and plan.size() != wave.size() and not wave.is_empty():
		plan = plan_spawns(player)
	if _cursor < plan.size():
		_cursor += 1
		return plan[_cursor - 1]["pos"]
	var pts := fog_points()
	var options := pts.filter(func(q): return (q as Vector2).distance_to(player) >= MIN_SPAWN_DISTANCE)
	if options.is_empty():
		options = pts
	var p: Vector2 = options[rng.randi_range(0, options.size() - 1)]
	return p + Vector2(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4))


## Exp 012 (G): the whole wave's start plan around Eli at `player` (see the
## header). Deterministic for the seed, the wave and the inputs.
func plan_spawns(player: Vector2) -> Array:
	var n := wave.size()
	var out := []
	if n == 0:
		return out
	var cands := candidates(player)
	var gn := sides if sides > 0 else (1 if n <= 1 else (2 if n <= 3 else (3 if n <= 7 else 4)))
	gn = clampi(gn, 1, mini(n, 4))
	var gs: Array = group_sides.slice(0, gn)
	var free := SIDES.keys().filter(func(k): return not gs.has(k))
	for i in range(free.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = free[i]
		free[i] = free[j]
		free[j] = t
	# sides with hidden points first, so a group is never stuck in view
	free.sort_custom(func(x, y): return _unseen_count(cands, x) > _unseen_count(cands, y))
	while gs.size() < gn and not free.is_empty():
		gs.append(free.pop_front())
	var group_delay := []
	for g in gn:
		group_delay.append(0.0 if g == 0 else rng.randf_range(0.35, 1.0) * g * GROUP_DELAY)
	var in_group := {}
	groups = []
	for g in gn:
		groups.append(0)
	var taken: Array = []
	for i in n:
		var g: int = int(side_of[i]) if side_of.size() == n else i % gn
		g = clampi(g, 0, gn - 1)
		groups[g] = int(groups[g]) + 1
		var side: String = gs[g]
		var c := _pick_point(cands, side, taken, player)
		taken.append(c["pos"])
		var k := int(in_group.get(g, 0))
		in_group[g] = k + 1
		var delay: float = group_delay[g] + (rng.randf_range(GROUP_GAP.x, GROUP_GAP.y) * k if k > 0 else 0.0)
		if str(wave[i]) == "bomber":
			delay += BOMBER_DELAY
		out.append({"kind": wave[i], "pos": c["pos"], "group": g, "side": side, "zone": c["zone"], "delay": delay, "hidden": c["hidden"], "unseen": c["unseen"]})
	return out


## Start-point candidates on a 1 m lattice: the fog band (outside the lot,
## inside the yard) and garden spots inside the lot away from the house.
## [{"pos", "side", "zone", "hidden", "d"}], only points at least
## MIN_SPAWN_DISTANCE from `player` (walkable on `nav` when set).
func candidates(player: Vector2) -> Array:
	var out := []
	var lot := FogBoundary.LOT
	var yard := HousePlan.YARD.grow(-0.4)
	var house := HousePlan.FOOTPRINT.grow(3.0)
	var y := yard.position.y + 0.5
	while y < yard.end.y:
		var x := yard.position.x + 0.5
		while x < yard.end.x:
			var p := Vector2(x, y)
			x += 1.0
			var in_fog := not lot.grow(0.3).has_point(p)
			if not in_fog and (not lot.grow(-0.6).has_point(p) or house.has_point(p)):
				continue
			if nav != null and not nav.is_walkable(nav.cell_of(p)):
				continue
			var d := p.distance_to(player)
			if d < MIN_SPAWN_DISTANCE:
				continue
			var seen := view_check.is_valid() and bool(view_check.call(p))
			# deep in the fog bank and far off counts as hidden, out of view is better
			var deep := not lot.grow(FOG_DEEP).has_point(p)
			var hidden := (not seen or (deep and d >= HIDDEN_IN_FOG)) if in_fog else (not seen and d >= LOT_SPAWN_MIN)
			if not in_fog and not hidden:
				continue
			var side := side_at(p)
			out.append({"pos": p, "side": side, "zone": ZONE_OF_SIDE[side] if in_fog else "lot", "hidden": hidden, "unseen": not seen, "d": d})
		y += 1.0
	return out


## "north" | "east" | "south" | "west": the side of the house a plan point is on.
static func side_at(p: Vector2) -> String:
	var c := HousePlan.FOOTPRINT.get_center()
	var h := HousePlan.FOOTPRINT.size * 0.5
	var v := Vector2((p.x - c.x) / h.x, (p.y - c.y) / h.y)
	if absf(v.x) > absf(v.y):
		return "east" if v.x > 0.0 else "west"
	return "south" if v.y > 0.0 else "north"


static func _unseen_count(cands: Array, side: String) -> int:
	var n := 0
	for c in cands:
		if c["unseen"] and c["side"] == side:
			n += 1
	return n


func _pick_point(cands: Array, side: String, taken: Array, player: Vector2) -> Dictionary:
	# passes: out of view on the side (spread out), the same closer together,
	# out of view anywhere, hidden in the fog on the side, hidden anywhere, any
	for pass_i in 6:
		var need := "unseen" if pass_i < 3 else ("hidden" if pass_i < 5 else "")
		var opts := []
		for c in cands:
			if need != "" and not c[need]:
				continue
			if (pass_i < 2 or pass_i == 3) and c["side"] != side:
				continue
			if pass_i == 0 or pass_i == 3:
				var near := false
				for q in taken:
					if (q as Vector2).distance_to(c["pos"]) < SPREAD:
						near = true
						break
				if near:
					continue
			opts.append(c)
		if not opts.is_empty():
			var c: Dictionary = opts[rng.randi_range(0, opts.size() - 1)]
			var j := Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3))
			return {"pos": c["pos"] + j, "zone": c["zone"], "hidden": c["hidden"], "unseen": c["unseen"]}
	# nothing on the lattice (a test without a house): the farthest fog point
	var pts := nearest_fog_points(player, MIN_SPAWN_DISTANCE)
	var p: Vector2 = pts[pts.size() - 1] if not pts.is_empty() else HousePlan.SPAWN_POINTS[0]
	return {"pos": p + Vector2(rng.randf_range(-GROUP_JITTER, GROUP_JITTER), rng.randf_range(-GROUP_JITTER, GROUP_JITTER)), "zone": "road", "hidden": true, "unseen": true}


# --- stragglers ------------------------------------------------------------------------

## Is the night that starts on `day` (20:00 that day .. 06:00 next) an invasion night?
static func is_invasion_night(day: int, next_invasion_at: float) -> bool:
	var noon := (day - 1) * DAY_MIN + 12.0 * 60.0
	return next_invasion_at >= noon and next_invasion_at < noon + DAY_MIN


## Absolute minute (GameState.total_minutes) of the straggler on the night that
## starts on `day`, or -1. Deterministic for (seed, day). `force` skips the
## chance roll (when the survival state already decided there is one).
static func straggler_at(seed: int, day: int, next_invasion_at: float, force := false) -> float:
	if day < T.STRAGGLER_FROM_DAY or is_invasion_night(day, next_invasion_at):
		return -1.0
	var r := RandomNumberGenerator.new()
	r.seed = int(seed) * 1000003 + day * 7919 + 17
	if r.randf() >= T.STRAGGLER_CHANCE and not force:
		return -1.0
	return (day - 1) * DAY_MIN + STRAGGLER_FROM + r.randf_range(0.0, STRAGGLER_SPAN)
