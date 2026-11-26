class_name DormantMind
extends StragglerMind
## Experiment 009 (P): a dormant psycho (the user's §12). A calm mind
## (AIEnemy.set_calm_mode("dormant", seed, data)) for someone Eli finds busy
## with something at a spot inside a place: it doesn't know he is there, and
## a careful player can sneak past. Provoked, the mind goes away and the
## archetype's own behaviour hunts him, as for every calm enemy (StragglerMind),
## so saving, the POI helper's "lost him" rule and the F10 tools work as before.
##
## Behaviours (the layout's `dormant` spots: {at, behaviour, target, radius}):
##   bang    leans in and knocks its head against the surface at `target`, in
##           a rhythm (BANG_EVERY), a thud and a low noise; between bursts it
##           stops and listens
##   circle  walks round `target` at `radius` on the nav grid, sometimes
##           reversing or pausing
##   sway    rocks in place, now and then turning its head
##   stare   motionless, facing `target`; an occasional twitch toward nothing
##   tap     taps a cabinet, scratches at a door or works a drawer at `target`
##           in short bursts (sound and gesture)
##   mumble  layered on any of them: mumbling, humming or whispering through
##           a PsychoVoice (one line at a time, pauses, a global cap)
## An invalid spot falls back: bang or tap without a surface at `target` ->
## stare (or sway), circle without room around `target` -> sway, stare
## without a target -> sway (`asked` keeps what was asked for).
##
## Awareness (cheap: senses every SENSE_EVERY s, decisions at 1 / TICK Hz):
##   absorbed    sees only SIGHT_ABSORBED m (x sight factor), in front of it
##               (CONE_ABSORBED), for SEE_TIME_ABSORBED s -> suspicious;
##               hears Eli move within STEP_HEAR m (x sensitivity); notices him
##               within NOTICE_ABSORBED m -> hostile; hears noise at
##               EAR_ABSORBED; below LISTEN_AT (after ears) it ignores it
##   listen      a noise or a step: it stops (a startled silence), faces the
##               sound for LISTEN_TIME s; then investigates when alert >=
##               SUSPICIOUS, else goes back to what it was doing
##   suspicious  it saw something: faces it for SUSPECT_TIME s with open eyes
##               (StragglerMind SIGHT, SEE_TIME -> hostile), then looks there
##   investigate walks to the sound, lingers, then "return"s to its spot
##   hostile     alert >= PROVOKE, a loud noise within STARTLE_RANGE m, Eli
##               seen with open eyes, Eli bumping into it, or any harm
## `sensitivity` (0.5..1.5) scales its ears, the step range, the startle
## range and (a quarter of it) its sight: some are easier to disturb.

const BEHAVIOURS := ["bang", "circle", "sway", "stare", "tap"]
const TICK := 0.25                ## s between behaviour decisions
const SIGHT_ABSORBED := 3.2       ## m while absorbed (x sight factor)
const CONE_ABSORBED := 0.34       ## cos of the half angle it sees while absorbed (70 degrees)
const CONE_AWAKE := -0.2          ## cos of the half angle once its eyes are open (about 100 degrees)
const NOTICE_ABSORBED := 1.1      ## m (x sensitivity, at least BUMP): this close it notices Eli anyway
const BUMP := 0.8                 ## m: always noticed
const SEE_TIME_ABSORBED := 1.3    ## s of seeing Eli before it grows suspicious
const STEP_HEAR := 2.4            ## m (x sensitivity, x STEP_FAST when he runs) it hears Eli move
const STEP_FAST := 1.7
const STEP_ALERT := 0.6           ## alert per s while it hears him move
const MOVING := 0.35              ## m/s: Eli is moving
const RUNNING := 3.6              ## m/s: Eli runs
const EAR_ABSORBED := 0.7         ## noise heard while absorbed, x
const LISTEN_AT := 0.18           ## heard (after ears and sensitivity) at least this: it listens
const LISTEN_ALERT := 0.6         ## alert from steps at which it stops to listen
const SUSPICIOUS := 1.2           ## alert at which it goes to look
const STARTLE_LOUD := 1.3         ## a noise this loud (as heard) ...
const STARTLE_RANGE := 4.5        ## ... within this many m (x sensitivity) makes it attack
const LISTEN_TIME := Vector2(2.5, 4.5)
const SUSPECT_TIME := 1.6
const DORMANT_DECAY := 0.12       ## alert lost per s
const BANG_EVERY := Vector2(1.1, 1.5)     ## s between bangs
const BANGS := Vector2i(4, 9)             ## bangs per burst
const BANG_PAUSE := Vector2(3.0, 6.0)     ## s it stops and listens between bursts
const BANG_LEAN := 0.3                    ## s from the start of a bang to the impact
const BANG_NOISE := 0.6                   ## noise level of a burst's first bang
const TAPS := Vector2i(3, 6)
const TAP_EVERY := Vector2(0.32, 0.48)
const TAP_PAUSE := Vector2(2.0, 5.0)
const CIRCLE_STEP := 0.6                  ## rad per waypoint
const CIRCLE_REVERSE := 0.12
const CIRCLE_PAUSE := 0.15
const SWAY_TURN := Vector2(4.0, 9.0)      ## s between head turns
const STARE_TWITCH := Vector2(5.0, 12.0)  ## s between twitches
const VOICE_GAP := Vector2(7.0, 18.0)     ## s between its lines (after the line)
const SOUND_DB := {"bang": -4.0, "tap": -6.0, "scratch": -6.0}
const PACE_DORMANT := {"circle": 0.38, "return": 0.45, "investigate": 0.6}

var behaviour := "sway"
var asked := ""                   ## the behaviour asked for (before a fallback)
var spot := Vector2.INF           ## where it does it
var target := Vector2.INF         ## what it bangs, circles, stares at or taps
var radius := 1.2                 ## circle
var sensitivity := 1.0
var mumble := false
var tap_kind := ""                ## tap: "tap", "scratch" or "drawer"
var voice: PsychoVoice
var bangs := 0                    ## tests, F10
var taps := 0
var startled := 0

var _resume := ""                 ## the behaviour to go back to ("" = behaviour)
var _t := 0.0
var _tick := 0.0
var _beat := 0.0                  ## s to the next bang / tap / circle step
var _burst := 0                   ## bangs or taps left in this burst
var _first := true                ## the next bang starts a burst
var _pause := 0.0                 ## s of pause (listening between bursts, a circle stop)
var _impact := -1.0               ## s to a bang's impact
var _lean := 0.0                  ## the bang's lean (pose), 0..1
var _flick := 0.0                 ## the tap's flick (pose), 0..1
var _dir := 1.0                   ## circling direction
var _angle := 0.0                 ## circling angle around the target
var _turn := 0.0                  ## head yaw (pose)
var _turn_to := 0.0
var _turn_t := 0.0
var _listen_t := 0.0
var _last_pp := Vector2.INF
var _data := {}


## The spot before setup(): {behaviour, spot | at, target, radius,
## sensitivity | sens, mumble, tap, state}. Vectors may be [x, y].
func configure(data: Dictionary) -> void:
	_data = data.duplicate()
	asked = str(data.get("behaviour", "sway"))
	behaviour = asked
	spot = _v(data.get("spot", data.get("at")))
	target = _v(data.get("target"))
	radius = _num(data.get("radius"), 1.2)
	sensitivity = clampf(_num(data.get("sensitivity", data.get("sens")), 1.0), 0.5, 1.5)
	mumble = data.get("mumble", false) == true
	tap_kind = str(data.get("tap", "")) if str(data.get("tap", "")) in ["tap", "scratch", "drawer"] else ""


func setup(e: AIEnemy, _m: String, seed: int) -> void:
	mode = "dormant"
	rng.seed = seed
	anchor = e.plan_pos()
	voice = PsychoVoice.new(seed)
	_calm_brain(e)
	if not spot.is_finite():
		spot = e.plan_pos()
	if tap_kind == "":
		var r := rng.randf()
		tap_kind = "tap" if r < 0.45 else ("scratch" if r < 0.8 else "drawer")
	_validate(e)
	voice.pause = rng.randf_range(1.5, VOICE_GAP.x)
	var st := str(_data.get("state", ""))
	if e.plan_pos().distance_to(spot) > 0.8 and st != "":
		_go(e, "return", spot, Vector2.INF)      # restored away from its spot (it was looking at something)
	else:
		_resume_behaviour(e)


## Falls back to a simpler behaviour when the spot can't carry this one.
func _validate(e: AIEnemy) -> void:
	var s := _snap(e, spot)
	if s != Vector2.INF and s.distance_to(spot) <= 1.0:
		spot = s
	elif s == Vector2.INF:
		spot = e.plan_pos()
	if not (behaviour in BEHAVIOURS):
		behaviour = "sway"
	match behaviour:
		"bang", "tap":
			if not target.is_finite() or target.distance_to(spot) > 1.8 or target.distance_to(spot) < 0.15 or not _surface(e, target):
				behaviour = "stare" if target.is_finite() and target.distance_to(spot) > 0.15 else "sway"
		"circle":
			radius = clampf(radius, 0.8, 3.0)
			if not target.is_finite() or _ring_ok(e) < 4:
				behaviour = "sway"
			else:
				_angle = (spot - target).angle() if spot.distance_to(target) > 0.05 else 0.0
		"stare":
			if not target.is_finite() or target.distance_to(spot) < 0.1:
				behaviour = "sway"


## Something solid at p (a wall or furniture): the nav can't stand there.
func _surface(e: AIEnemy, p: Vector2) -> bool:
	return e.nav == null or not e.nav.is_walkable(e.nav.cell_of(p))


## How many of 8 points round the target it can walk to.
func _ring_ok(e: AIEnemy) -> int:
	var n := 0
	for i in 8:
		var q := target + Vector2.from_angle(TAU * i / 8.0) * radius
		var s := _snap(e, q)
		if s != Vector2.INF and s.distance_to(q) <= 0.6:
			n += 1
	return n


func is_absorbed() -> bool:
	return state in BEHAVIOURS


func pace() -> float:
	return float(PACE_DORMANT.get(state, 0.5))


## What it saves (GamePoi.encounter_state: "dormant"). Vectors are [x, y].
func save_data() -> Dictionary:
	return {"behaviour": behaviour, "asked": asked, "spot": [spot.x, spot.y],
		"target": [target.x, target.y] if target.is_finite() else [],
		"radius": radius, "sens": sensitivity, "mumble": mumble, "tap": tap_kind, "state": state}


## F10: switches to behaviour b at a new spot (same rules and fallbacks).
func reconfigure(e: AIEnemy, data: Dictionary) -> void:
	configure(data)
	_validate(e)
	if e.plan_pos().distance_to(spot) > 0.8:
		_resume = ""
		_go(e, "return", spot, Vector2.INF)
	else:
		_resume_behaviour(e)


# --- the frame ---------------------------------------------------------------------------

func think(e: AIEnemy, delta: float, r: Dictionary) -> Dictionary:
	r["swing"] = ""
	if state != "listen" and state != "suspicious":
		alert = maxf(alert - DORMANT_DECAY * delta, 0.0)      # it holds its breath while it listens
	_t += delta
	voice.tick(delta)
	_sense_t -= delta
	if _sense_t <= 0.0:
		_sense_t = SENSE_EVERY
		if _sense_dormant(e, SENSE_EVERY):
			return r
	if e.mind != self:
		return r
	goal_t += delta
	if is_absorbed():
		return _absorbed(e, delta, r)
	var me := e.plan_pos()
	match state:
		"listen", "suspicious":
			r["move"] = Vector2.ZERO
			if look.is_finite() and look.distance_to(me) > 0.05:
				r["face"] = (look - me).normalized()
			_listen_t -= delta
			if _listen_t <= 0.0:
				if state == "suspicious" or alert >= SUSPICIOUS:
					_go(e, "investigate", _snap_or(e, look), look)
				else:
					_back(e)
		_:   # investigate, return
			if linger < 0.0:
				if goal == Vector2.INF or me.distance_to(goal) <= ARRIVE or bool(r.get("arrived", false)):
					if state == "return":
						_resume_behaviour(e)
						return r
					linger = rng.randf_range(2.0, 4.0)
				elif goal_t > GIVE_UP:
					_back(e)
					return r
			if linger >= 0.0:
				linger -= delta
				r["move"] = Vector2.ZERO
				if look.is_finite() and look.distance_to(me) > 0.05:
					r["face"] = (look - me).normalized()
				if linger < 0.0:
					_back(e)
	return r


## Per frame while it is busy with its behaviour; decisions every TICK s.
func _absorbed(e: AIEnemy, delta: float, r: Dictionary) -> Dictionary:
	var me := e.plan_pos()
	_lean = maxf(_lean - delta * 2.2, 0.0) if _impact < 0.0 else minf(_lean + delta / BANG_LEAN, 1.0)
	_flick = maxf(_flick - delta * 5.0, 0.0)
	_turn = lerpf(_turn, _turn_to, 1.0 - exp(-delta * (10.0 if behaviour == "stare" else 3.0)))
	if _impact >= 0.0:
		_impact -= delta
		if _impact < 0.0:
			_bang_hit(e)
	_tick -= delta
	if _tick <= 0.0:
		_tick = TICK
		_decide(e, TICK)
	if behaviour == "circle" and goal != Vector2.INF:
		if me.distance_to(goal) <= ARRIVE or bool(r.get("arrived", false)) or goal_t > 6.0:
			_circle_next(e)
		var mv: Vector2 = r["move"]
		if mv.length() > 0.01:
			r["face"] = mv
		return r
	r["move"] = Vector2.ZERO
	var at := target if behaviour != "sway" and target.is_finite() else look
	if at.is_finite() and at.distance_to(me) > 0.05:
		r["face"] = (at - me).normalized()
	return r


func _decide(e: AIEnemy, dt: float) -> void:
	_turn_t -= dt
	match behaviour:
		"bang":
			if _pause > 0.0:
				_pause -= dt
				if _turn_t <= 0.0:
					_turn_t = rng.randf_range(0.8, 1.6)
					_turn_to = rng.randf_range(-0.7, 0.7)       # it listens, turning its head
				if _pause <= 0.0:
					_turn_to = 0.0
					_burst = rng.randi_range(BANGS.x, BANGS.y)
					_first = true
				return
			_beat -= dt
			if _beat <= 0.0 and _impact < 0.0:
				_beat = rng.randf_range(BANG_EVERY.x, BANG_EVERY.y)
				_impact = BANG_LEAN
		"tap":
			if _pause > 0.0:
				_pause -= dt
				if _pause <= 0.0:
					_burst = rng.randi_range(TAPS.x, TAPS.y)
					_burst_sound(e)
				return
			_beat -= dt
			if _beat <= 0.0:
				_beat = rng.randf_range(TAP_EVERY.x, TAP_EVERY.y)
				_flick = 1.0
				taps += 1
				_burst -= 1
				if _burst <= 0:
					if tap_kind == "drawer":
						Sfx.play_first(["door/close"], _sound_at(e), -12.0 + PsychoVoice.occlusion_db(e))
					_pause = rng.randf_range(TAP_PAUSE.x, TAP_PAUSE.y)
		"circle":
			if _pause > 0.0:
				_pause -= dt
				if _pause <= 0.0:
					_circle_next(e)
		"sway":
			if _turn_t <= 0.0:
				var turning := absf(_turn_to) < 0.05
				_turn_to = rng.randf_range(0.4, 0.8) * (1.0 if rng.randf() < 0.5 else -1.0) if turning else 0.0
				_turn_t = rng.randf_range(1.2, 2.0) if turning else rng.randf_range(SWAY_TURN.x, SWAY_TURN.y)
		"stare":
			if _turn_t <= 0.0:
				var twitching := absf(_turn_to) < 0.05
				_turn_to = rng.randf_range(0.5, 0.9) * (1.0 if rng.randf() < 0.5 else -1.0) if twitching else 0.0
				_turn_t = 0.25 if twitching else rng.randf_range(STARE_TWITCH.x, STARE_TWITCH.y)
	if mumble:
		_mumble(e)


func _bang_hit(e: AIEnemy) -> void:
	bangs += 1
	Sfx.play_first(["psycho/bang", "door/bash", "impact/wood"], _sound_at(e), SOUND_DB["bang"] + PsychoVoice.occlusion_db(e))
	_burst -= 1
	if _first:
		_first = false
		NoiseEvent.emit(e, _sound_at(e), BANG_NOISE, "psycho_bang")       # once a burst: the thuds carry a little
	if _burst <= 0:
		_pause = rng.randf_range(BANG_PAUSE.x, BANG_PAUSE.y)


func _burst_sound(e: AIEnemy) -> void:
	var at := _sound_at(e)
	var occ := PsychoVoice.occlusion_db(e)
	match tap_kind:
		"scratch":
			Sfx.play_first(["psycho/scratch"], at, SOUND_DB["scratch"] + occ)
		"drawer":
			Sfx.play_first(["psycho/tap", "door/open"], at, -12.0 + occ)
		_:
			Sfx.play_first(["psycho/tap", "impact/wood"], at, SOUND_DB["tap"] + occ - (0.0 if Sfx.available("psycho/tap") else 10.0))


func _sound_at(e: AIEnemy) -> Vector3:
	var p := target if target.is_finite() and behaviour in ["bang", "tap"] else e.plan_pos()
	return Vector3(p.x, e.floor_y + 1.3, p.y)


func _mumble(e: AIEnemy) -> void:
	if voice.pause > 0.0 or voice.speaking():
		return
	var r := rng.randf()
	var line := "psycho/mumble" if r < 0.5 else ("psycho/hum" if r < 0.8 else "psycho/whisper")
	var lines := [[line, 0.0, 1.0]]
	if line == "psycho/mumble":
		lines.append(["enemy/moan", -14.0, 0.2])     # until the recording exists: rarely a quiet moan
	voice.say(e, lines, VOICE_GAP)


func _circle_next(e: AIEnemy) -> void:
	if rng.randf() < CIRCLE_REVERSE:
		_dir = -_dir
	if rng.randf() < CIRCLE_PAUSE and _pause <= 0.0:
		goal = Vector2.INF                       # it stops a moment, facing the thing
		_pause = rng.randf_range(1.5, 3.5)
		return
	for i in 4:
		_angle += CIRCLE_STEP * _dir
		var q := target + Vector2.from_angle(_angle) * radius
		var s := _snap(e, q)
		if s != Vector2.INF and s.distance_to(q) <= 0.6:
			goal = s
			goal_t = 0.0
			e.brain.invalidate()
			return
	_dir = -_dir                                 # a blocked arc: back the other way
	goal = Vector2.INF
	_pause = 0.6


## Back to its spot (or straight to work when it is there).
func _back(e: AIEnemy) -> void:
	if e.plan_pos().distance_to(spot) > 0.8:
		_go(e, "return", _snap_or(e, spot), Vector2.INF)
	else:
		_resume_behaviour(e)


func _resume_behaviour(e: AIEnemy) -> void:
	state = behaviour
	history.append(state)
	if history.size() > 12:
		history.pop_front()
	linger = -1.0
	goal_t = 0.0
	look = target if target.is_finite() else Vector2.INF
	_turn_to = 0.0
	_pause = 0.0
	_impact = -1.0
	_beat = rng.randf_range(0.3, 1.2)
	match behaviour:
		"bang":
			_burst = rng.randi_range(BANGS.x, BANGS.y)
			_first = true
		"tap":
			_burst = rng.randi_range(TAPS.x, TAPS.y)
			_burst_sound(e)
		"circle":
			_angle = (e.plan_pos() - target).angle() if e.plan_pos().distance_to(target) > 0.05 else _angle
			_circle_next(e)
			return
		"sway":
			look = e.plan_pos() + Vector2(-sin(e.rig.rotation.y), -cos(e.rig.rotation.y)) if e.rig != null else Vector2.INF
	goal = Vector2.INF
	e.brain.invalidate()


func _snap_or(e: AIEnemy, p: Vector2) -> Vector2:
	var s := _snap(e, p)
	return s if s != Vector2.INF else e.plan_pos()


# --- senses and events -----------------------------------------------------------------------

## Stops what it does and listens toward `at` (a startled silence).
func _listen(e: AIEnemy, at: Vector2) -> void:
	if state == "listen" or state == "suspicious":
		look = at
		_listen_t = maxf(_listen_t, LISTEN_TIME.x)
		return
	if state in ["investigate", "return"]:
		_go(e, "investigate", _snap_or(e, at), at)        # a new sound: it goes there instead
		return
	var was_busy := is_absorbed()
	voice.stop()
	_go(e, "listen", Vector2.INF, at)
	_listen_t = rng.randf_range(LISTEN_TIME.x, LISTEN_TIME.y)
	_lean = 0.0
	_impact = -1.0
	if was_busy and rng.randf() < 0.6:
		startled += 1
		voice.say(e, [["psycho/startle", 0.0, 1.0]], Vector2(3.0, 6.0), true)


func _suspect(e: AIEnemy, at: Vector2) -> void:
	alert = maxf(alert, SUSPICIOUS)
	if state != "suspicious":
		voice.stop()
		_go(e, "suspicious", Vector2.INF, at)
	look = at
	_listen_t = SUSPECT_TIME


## A noise reached it (NoiseEvent._dispatch): `loud` = level x exposure x fall-off.
func hear(e: AIEnemy, at: Vector2, loud: float, source := "") -> void:
	if source == "shout":
		voice.stop()
		hear_shout(e, at, loud)            # Exp 012 (E): it goes to look (StragglerMind)
		return
	heard += 1
	if source.begins_with("psycho"):
		return                                   # its own (and its kind's) thuds
	if loud >= STARTLE_LOUD and e.plan_pos().distance_to(at) <= STARTLE_RANGE * sensitivity:
		alert = PROVOKE
		e.provoke("startled: " + source if source != "" else "startled")
		return
	var h := loud * sensitivity * (EAR_ABSORBED if is_absorbed() else 1.0)
	if h < LISTEN_AT:
		return                                   # distant activity: it carries on
	alert += h
	if alert >= PROVOKE:
		e.provoke("noise: " + source if source != "" else "noise")
		return
	_listen(e, at)


func investigate(e: AIEnemy, p: Vector2) -> void:
	_go(e, "investigate", _snap_or(e, p), p)


## Looks for Eli; true if it turned hostile.
func _sense_dormant(e: AIEnemy, dt: float) -> bool:
	var pl = e.player
	if pl == null or not is_instance_valid(pl) or not (pl is Node3D):
		return false
	var g := (pl as Node3D).global_position
	var p := Vector2(g.x, g.z)
	if absf(g.y - e.floor_y) > 1.5:
		seen_t = 0.0
		_last_pp = Vector2.INF
		return false
	var moved := 0.0 if _last_pp == Vector2.INF else _last_pp.distance_to(p) / maxf(dt, 0.01)
	_last_pp = p
	var me := e.plan_pos()
	var d := me.distance_to(p)
	var absorbed := is_absorbed()
	var s := sensitivity
	var notice := maxf(NOTICE_ABSORBED * s, BUMP) if absorbed else NOTICE
	if d <= notice:
		e.provoke("saw Eli")
		return true
	var sight := (SIGHT_ABSORBED if absorbed else SIGHT) * (0.75 + 0.25 * s)
	var fwd := Vector2(-sin(e.rig.rotation.y), -cos(e.rig.rotation.y)) if e.rig != null else Vector2.UP
	var in_cone := d < 0.05 or fwd.dot((p - me) / d) >= (CONE_ABSORBED if absorbed else CONE_AWAKE)
	if d <= sight and in_cone and (e.nav == null or e.nav.segment_clear(me, p)):
		seen_t += dt * (2.0 if d < 2.0 else 1.0)
		if absorbed:
			if seen_t >= SEE_TIME_ABSORBED:
				seen_t = 0.0
				_suspect(e, p)
		else:
			if state != "suspicious":
				_suspect(e, p)
			look = p
			if seen_t >= SEE_TIME:
				e.provoke("saw Eli")
				return true
	else:
		seen_t = maxf(seen_t - dt * 0.5, 0.0)
	if moved > MOVING:
		var fast := moved > RUNNING
		if d <= STEP_HEAR * s * (STEP_FAST if fast else 1.0):
			alert += STEP_ALERT * dt * s * (2.0 if fast else 1.0)
			if alert >= PROVOKE:
				e.provoke("heard Eli")
				return true
			if alert >= LISTEN_ALERT and (absorbed or state == "listen"):
				_listen(e, p)
	return false


# --- the pose (after VoxelRig.animate, per frame: a few rotations) ---------------------------

func pose(e: AIEnemy, _delta: float) -> void:
	var rig := e.rig
	if rig == null or rig.torso == null:
		return
	match state:
		"bang":
			var k := smoothstep(0.0, 1.0, _lean)
			rig.torso.rotation.x -= k * 0.55
			rig.head.rotation.x += k * 0.45
			rig.arm_l.rotation.x = 0.15 + k * 0.2
			rig.arm_r.rotation.x = 0.15 + k * 0.2
			rig.head.rotation.y = _turn
		"tap":
			var up := 0.95 if tap_kind != "scratch" else 1.15
			var wob := sin(_t * 9.0) * 0.25 if tap_kind == "scratch" and _pause <= 0.0 else 0.0
			rig.arm_r.rotation.x = up + _flick * (0.35 if tap_kind == "tap" else -0.3) + wob
			rig.arm_l.rotation.x = 0.2
		"sway":
			rig.torso.rotation.z += sin(_t * 1.7) * 0.13
			rig.torso.rotation.x += sin(_t * 0.85) * 0.06
			rig.head.rotation.y += _turn
		"stare":
			rig.head.rotation = Vector3(0.12, _turn, 0.0)
			rig.torso.rotation = Vector3(-rig.hunch * 0.7, 0.0, 0.0)
			rig.arm_l.rotation.x = 0.08
			rig.arm_r.rotation.x = 0.08
		"circle":
			rig.head.rotation.x += 0.15
		"listen", "suspicious":
			rig.torso.rotation.x += 0.18           # it straightens up
			rig.head.rotation = Vector3(-0.05, 0.0, 0.0)


func on_provoked(_e: AIEnemy) -> void:
	if voice != null:
		voice.stop()


# --- helpers -------------------------------------------------------------------------------------

static func _v(v: Variant) -> Vector2:
	if v is Vector2:
		return v if (v as Vector2).is_finite() else Vector2.INF
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 2 and typeof(v[0]) in [TYPE_INT, TYPE_FLOAT] and typeof(v[1]) in [TYPE_INT, TYPE_FLOAT]:
		var p := Vector2(float(v[0]), float(v[1]))
		return p if p.is_finite() else Vector2.INF
	return Vector2.INF


static func _num(v: Variant, fallback: float) -> float:
	return float(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(v)) else fallback
