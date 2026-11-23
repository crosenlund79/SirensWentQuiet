extends RefCounted
## Footstep rhythm: while the player walks, returns the next footstep sound at
## a speed-based interval, cycling through the four variants. Pure logic (the
## game plays the sound).

const VARIANTS := 4
const MIN_SPEED := 0.6          ## m/s; slower than this counts as standing
const CADENCE := 1.25           ## interval = CADENCE / speed, clamped
const INTERVAL := Vector2(0.28, 0.6)

var _t := 0.0
var _last := 0


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
