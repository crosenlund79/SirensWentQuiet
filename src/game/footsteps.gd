extends RefCounted
## Footstep rhythm: while the player walks, returns the next footstep sound at
## a speed-based interval, cycling through the four variants. Pure logic (the
## game plays the sound).
##
## Experiment 005 (A): steps follow the gait and the surface.
##   gait(walk_phase, speed) -> bool   true once per step: whenever the rig's
##                                     walk phase passes a heel strike
##                                     (PI/2 + k*PI, where a leg is furthest
##                                     forward and the body lowest), so steps
##                                     land with the animation and stop with it
##   surface(storey, plan_pos)         "snow" outside, "cement" in basements and
##                                     on concrete or tiled ground-floor rooms,
##                                     "wood" on the other floors
##   sound_for(surface)                player/step_<surface> when the audio inbox
##                                     (or custom/) has it, else the generated
##                                     player/footstep group
## tick() is the Experiment 002 timer, kept for callers without a rig.

const VARIANTS := 4
const MIN_SPEED := 0.6          ## m/s; slower than this counts as standing
const CADENCE := 1.25           ## interval = CADENCE / speed, clamped
const INTERVAL := Vector2(0.28, 0.6)
const SURFACES := ["snow", "wood", "cement"]
## HousePlan room floors -> step surface (anything else on a floor: wood).
const FLOOR_SURFACE := {"wood": "wood", "wood_light": "wood", "concrete": "cement", "tile": "cement",
		"kitchen_tile": "cement", "stone": "cement"}

var _t := 0.0
var _last := 0
var _strike := NAN               ## the heel-strike index last counted (NAN: not walking)


static func interval(speed: float) -> float:
	return clampf(CADENCE / maxf(speed, 0.01), INTERVAL.x, INTERVAL.y)


## Returns the logical sound to play now ("player/footstep_N"), or "".
func tick(delta: float, speed: float) -> String:
	if speed < MIN_SPEED:
		_t = 0.12               # the first step lands soon after setting off
		return ""
	_t -= delta
	if _t > 0.0:
		return ""
	_t = interval(speed)
	_last = _last % VARIANTS + 1
	return "player/footstep_%d" % _last


## True when a step lands this frame: the walk phase crossed a heel strike
## since the last call while moving at least MIN_SPEED. Standing still resets
## the count, so the first step after setting off lands at the first strike.
func gait(walk_phase: float, speed: float) -> bool:
	if speed < MIN_SPEED:
		_strike = NAN
		return false
	var k := floorf((walk_phase - PI * 0.5) / PI)
	if is_nan(_strike):
		_strike = k
		return false
	if k > _strike:
		_strike = k
		return true
	if k < _strike:           # the phase was reset (a new rig): follow it
		_strike = k
	return false


## The surface under a player on `storey` at `plan_pos` (plan metres).
static func surface(storey: int, plan_pos: Vector2) -> String:
	if storey < 0:
		return "cement"
	if not HousePlan.FOOTPRINT.has_point(plan_pos):
		return "snow" if storey == 0 else "wood"
	if storey > 0:
		return "wood"
	var room := HousePlan.room_at(plan_pos)
	return FLOOR_SURFACE.get(str(room.get("floor", "wood")), "wood")


## The logical sound for a surface: the inbox recording if there is one,
## else the generated wooden footsteps.
static func sound_for(surf: String) -> String:
	var n := "player/step_" + surf
	return n if Sfx.available(n) else "player/footstep"
