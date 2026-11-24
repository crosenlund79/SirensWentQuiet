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
##     (from invasion 2) upgrades psychos to runners;
##   - members arrive in groups (1, then 2-3 together from one fog point, a
##     second or two apart), groups 25-40 s apart; bombers come later in the wave.
## `begin(count, hp, speed, seed)` is the Experiment 002 call (that many
## psychos, one at a time) and still works.
##
## - Spawn points are HousePlan.SPAWN_POINTS in the fog band: outside the lot
##   (FogBoundary.LOT) but inside the navigable YARD.
## - `straggler_at()` decides, deterministically from the run seed and the day,
##   whether a lone psycho comes on a non-invasion night (from Day 2, 35 %,
##   between 23:00 and 03:00).

const T := preload("res://src/survival/survival_tuning.gd")
const DAY_MIN := 1440.0
const FIRST_DELAY := 2.5            ## s from the banner to the first invader
const MIN_SPAWN_DISTANCE := 7.0     ## m from the player
const STRAGGLER_FROM := 23.0 * 60.0
const STRAGGLER_SPAN := 4.0 * 60.0  ## 23:00 .. 03:00
const GROUP_GAP := Vector2(1.2, 2.6)   ## s between members of one group
const GROUP_JITTER := 0.9           ## m around the group's fog point
## Relative pick weights when composing a wave.
const WEIGHTS := {"psycho": 3.0, "runner": 2.0, "brute": 1.4, "bomber": 1.2}
const MAX_COUNT := 14

var active := false
var total := 0
var spawned := 0
var hp := Tuning.ENEMY_HP           ## legacy waves: every psycho's hp
var speed := 1.0                    ## legacy waves: every psycho's speed scale
## Tests and the playtest shorten the gaps; Vector2.ZERO = SurvivalTuning's.
var gap_override := Vector2.ZERO
var rng := RandomNumberGenerator.new()
var wave: Array = []                ## kinds in spawn order
var groups: Array = []              ## group sizes, in order
var level := "normal"
var invasion := 1
var budget := 0.0                   ## this wave's threat budget (0 = a legacy wave)
var last_kinds: Array = []          ## what the last tick released
var _legacy := true
var _timer := 0.0
var _group := 0                     ## index into groups
var _in_group := 0                  ## members of the current group already out
var _group_point := Vector2.INF
var _new_group := true              ## the last released member opened its group


## Experiment 002: `count` psychos with `enemy_hp` and `speed_scale`.
func begin(count: int, enemy_hp: int, speed_scale: float, seed: int) -> void:
	var kinds := []
	for i in maxi(count, 0):
		kinds.append("psycho")
	_start(kinds, [], seed)
	_legacy = true
	budget = 0.0
	hp = maxi(enemy_hp, 1)
	speed = speed_scale


## Experiment 003: a wave composed from the threat budget of `lv` and
## invasion `inv` (1-based), or exactly `kinds` if given (dev menu).
func begin_wave(lv: String, inv: int, seed: int, kinds: Array = []) -> void:
	level = Difficulty.valid(lv)
	invasion = maxi(inv, 1)
	var w := kinds.filter(func(k): return EnemyDefs.has(str(k))) if not kinds.is_empty() else compose(level, invasion, seed)
	_start(w, group_sizes(w.size()), seed)
	_legacy = false
	budget = threat_budget(level, invasion)
	var st := EnemyDefs.stats("psycho", level, invasion)
	hp = st["hp"]
	speed = st["speed_scale"]


func _start(kinds: Array, sizes: Array, seed: int) -> void:
	active = true
	wave = kinds.duplicate()
	total = wave.size()
	spawned = 0
	groups = sizes if not sizes.is_empty() else _ones(total)
	_group = 0
	_in_group = 0
	_group_point = Vector2.INF
	_new_group = true
	last_kinds = []
	rng.seed = seed
	_timer = minf(FIRST_DELAY, gap().x)


func finish() -> void:
	active = false


func gap() -> Vector2:
	return gap_override if gap_override != Vector2.ZERO else T.INVASION_SPAWN_GAP


func all_spawned() -> bool:
	return spawned >= total


func remaining_to_spawn() -> int:
	return maxi(total - spawned, 0)


## Real seconds elapse; returns how many invaders to spawn now (0 or 1).
## The kinds are in `last_kinds` (tick_kinds returns them directly).
func tick(delta: float) -> int:
	last_kinds = []
	if not active or spawned >= total:
		return 0
	_timer -= delta
	if _timer > 0.0:
		return 0
	last_kinds = [wave[spawned]]
	spawned += 1
	_in_group += 1
	_new_group = _in_group == 1
	if _in_group >= int(groups[_group]) and _group < groups.size() - 1:
		_group += 1
		_in_group = 0
		var g := gap()
		_timer = rng.randf_range(g.x, g.y)
	else:
		var g2 := gap()
		_timer = rng.randf_range(minf(GROUP_GAP.x, g2.x), minf(GROUP_GAP.y, g2.y)) if _in_group > 0 else rng.randf_range(g2.x, g2.y)
	return 1


## The kinds to spawn now ([] most frames).
func tick_kinds(delta: float) -> Array:
	tick(delta)
	return last_kinds


## Roster options for a member of this wave (roster.spawn_type's opts).
func spawn_opts(_kind := "psycho") -> Dictionary:
	if _legacy:
		return {"hp": hp, "speed": speed, "invader": true}
	return {"level": level, "invasion": invasion, "invader": true}


## Shortens the wait for the next invader (tests, playtest).
func hurry(seconds: float) -> void:
	_timer = minf(_timer, seconds)


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


## A random fog point at least MIN_SPAWN_DISTANCE from the player. Members of
## one group (Experiment 003 waves) share their group's point.
func pick_spawn(player: Vector2) -> Vector2:
	if not _legacy and not _new_group and _group_point != Vector2.INF:
		return _group_point + Vector2(rng.randf_range(-GROUP_JITTER, GROUP_JITTER), rng.randf_range(-GROUP_JITTER, GROUP_JITTER))
	var pts := fog_points()
	var options := pts.filter(func(q): return (q as Vector2).distance_to(player) >= MIN_SPAWN_DISTANCE)
	if options.is_empty():
		options = pts
	var p: Vector2 = options[rng.randi_range(0, options.size() - 1)]
	_group_point = p
	return p + Vector2(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4))


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
