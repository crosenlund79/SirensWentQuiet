extends RefCounted
## Invasion pacing and spawn choice (SPEC §6 "Invasions"). Pure logic: the game
## asks it how many invaders to spawn this frame and where, and spawns them.
##
## - `begin()` starts a wave of `total` invaders; the first appears after
##   FIRST_DELAY, the rest staggered by SurvivalTuning.INVASION_SPAWN_GAP
##   (real seconds, independent of the dev time scale).
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

var active := false
var total := 0
var spawned := 0
var hp := Tuning.ENEMY_HP
var speed := 1.0
## Tests and the playtest shorten the gaps; Vector2.ZERO = SurvivalTuning's.
var gap_override := Vector2.ZERO
var rng := RandomNumberGenerator.new()
var _timer := 0.0


func begin(count: int, enemy_hp: int, speed_scale: float, seed: int) -> void:
	active = true
	total = maxi(count, 0)
	spawned = 0
	hp = maxi(enemy_hp, 1)
	speed = speed_scale
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
func tick(delta: float) -> int:
	if not active or spawned >= total:
		return 0
	_timer -= delta
	if _timer > 0.0:
		return 0
	spawned += 1
	var g := gap()
	_timer = rng.randf_range(g.x, g.y)
	return 1


## Shortens the wait for the next invader (tests, playtest).
func hurry(seconds: float) -> void:
	_timer = minf(_timer, seconds)


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


## A random fog point at least MIN_SPAWN_DISTANCE from the player.
func pick_spawn(player: Vector2) -> Vector2:
	var pts := fog_points()
	var options := pts.filter(func(q): return (q as Vector2).distance_to(player) >= MIN_SPAWN_DISTANCE)
	if options.is_empty():
		options = pts
	var p: Vector2 = options[rng.randi_range(0, options.size() - 1)]
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
