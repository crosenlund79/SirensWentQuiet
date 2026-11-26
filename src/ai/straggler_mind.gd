class_name StragglerMind
extends RefCounted
## Experiment 007 (N): calm until provoked (the user's §13). An AIEnemy with a
## mind (AIEnemy.set_calm_mode) doesn't hunt Eli: it walks slowly, never
## swings and never bashes, and goes about one of a few small activities.
## Provoked, the mind goes away and the archetype's own behaviour takes over
## (a psycho, runner or brute chases, a bomber seeks a wall to blow), so the
## archetypes keep their differences. Invasion enemies never get a mind:
## horde nights stay deliberate and dangerous.
##
## Modes (set_calm_mode / the roster's spawn opts "mode"):
##   straggler  the home's night straggler: 2-3 of pass by the property,
##              approach a window, test a door, examine a damaged structure,
##              then lose interest and walk back into the fog (or, RESTLESS
##              of the time, turn on the house after all)
##   wander     (POIs) roams around where it was spawned
##   hidden     (POIs) stays put until something draws it
##   arrive     (POIs) heads for where Eli was when it arrived, then roams
## States: pass, wander, window, door, examine, investigate, lurk, leave.
##
## Provocation (-> hostile):
##   noise      hear(): alert += what it heard; at PROVOKE it turns
##              hostile; less draws it to investigate (outside a building:
##              the nearest entrance to the sound), a faint noise may also
##              make it wander away
##   sight      Eli within NOTICE m, or within SIGHT m on the same storey
##              with a clear line (GridNav.segment_clear: walls, closed doors
##              and furniture block it) for SEE_TIME s
##   harm       any damage (a shot, a blast, spikes)

const PROVOKE := 3.0              ## alert at which it turns hostile
const ALERT_DECAY := 0.1          ## alert lost per second
const INVESTIGATE_AT := 0.35      ## heard at least this much: it comes to look
const FAINT := 0.12               ## below this a noise is ignored
const SIGHT := 7.5                ## m
const NOTICE := 2.0               ## m: this close it notices Eli through anything on its storey
const SEE_TIME := 0.9             ## s of seeing Eli before it turns
const SENSE_EVERY := 0.2          ## s between looks
const ARRIVE := 0.55              ## m from a goal: arrived
const GIVE_UP := 20.0             ## s on one goal before it loses interest in it
const LINGER := {"window": Vector2(3.0, 5.5), "door": Vector2(3.0, 5.0), "examine": Vector2(2.5, 4.5),
	"investigate": Vector2(2.0, 4.0), "pass": Vector2(0.3, 1.2), "wander": Vector2(1.0, 3.5), "lurk": Vector2(4.0, 8.0)}
const PACE := {"pass": 0.55, "wander": 0.45, "window": 0.5, "door": 0.5, "examine": 0.5, "investigate": 0.62,
	"lurk": 0.4, "leave": 0.6}
const ACTIVITIES := ["pass", "window", "door", "examine"]
const WANDER_RANGE := 7.0         ## m around the anchor (POI modes)
const RATTLE_EVERY := 1.1         ## s between a door test's tugs (an animation, no damage)
const RESTLESS := 0.3             ## chance a straggler that ran out of things to do turns on the house instead of leaving

var mode := "straggler"
var state := "pass"
var goal := Vector2.INF
var look := Vector2.INF           ## what it faces while lingering
var anchor := Vector2.ZERO
var alert := 0.0
var seen_t := 0.0
var linger := -1.0                ## < 0: not arrived yet
var goal_t := 0.0
var plan: Array = []
var heard := 0                    ## noises heard (tests, F10)
var history: Array = []           ## states it went through (tests, F10)
var rng := RandomNumberGenerator.new()
var _sense_t := 0.0
var _rattle := 0.0


func setup(e: AIEnemy, m: String, seed: int) -> void:
	mode = m if m in ["straggler", "wander", "hidden", "arrive"] else "wander"
	rng.seed = seed
	anchor = e.plan_pos()
	_calm_brain(e)
	match mode:
		"straggler":
			var acts := ACTIVITIES.duplicate()
			for i in range(acts.size() - 1, 0, -1):
				var j := rng.randi_range(0, i)
				var t = acts[i]
				acts[i] = acts[j]
				acts[j] = t
			plan = acts.slice(0, rng.randi_range(2, 4))
			if not plan.has("pass") and rng.randf() < 0.5:
				plan.push_front("pass")
			_next(e)
		"hidden":
			_go(e, "lurk", anchor, Vector2.INF)
		"arrive":
			var pp := _player_pos(e)
			_go(e, "investigate", _snap(e, pp) if pp != Vector2.INF else anchor, pp)
		_:
			_go(e, "wander", _wander_point(e), Vector2.INF)


## The brain while calm: no swings at the goal, no bashing.
func _calm_brain(e: AIEnemy) -> void:
	e.brain.attack_goal = false
	e.brain.bash = false
	e.brain.arrive_radius = ARRIVE * 0.8
	e.brain.invalidate()


func pace() -> float:
	return float(PACE.get(state, 0.5))


## Where to walk this frame.
func goal_of(e: AIEnemy) -> Vector2:
	if goal == Vector2.INF or linger >= 0.0:
		return e.plan_pos()
	return goal


## Adjusts the brain's result: never a swing; stand and look while lingering.
func think(e: AIEnemy, delta: float, r: Dictionary) -> Dictionary:
	r["swing"] = ""
	alert = maxf(alert - ALERT_DECAY * delta, 0.0)
	_sense_t -= delta
	if _sense_t <= 0.0:
		_sense_t = SENSE_EVERY
		if _sense(e, SENSE_EVERY):
			return r
	goal_t += delta
	var me := e.plan_pos()
	if linger < 0.0:
		if goal == Vector2.INF or me.distance_to(goal) <= ARRIVE or bool(r.get("arrived", false)):
			var span: Vector2 = LINGER.get(state, Vector2(1.0, 2.0))
			linger = rng.randf_range(span.x, span.y)
			_rattle = 0.4
		elif goal_t > GIVE_UP:
			_next(e)
			return r
	if linger >= 0.0:
		linger -= delta
		r["move"] = Vector2.ZERO
		if look != Vector2.INF and look.distance_to(me) > 0.05:
			r["face"] = (look - me).normalized()
		if state == "door":
			_rattle -= delta
			if _rattle <= 0.0 and e.rig != null:
				_rattle = RATTLE_EVERY
				e.rig.swing = 1.0          # a tug at the handle: animation only
		if linger < 0.0:
			_next(e)
	return r


# --- events ---------------------------------------------------------------------------

## A noise reached it (NoiseEvent._dispatch): `loud` = level x exposure x fall-off.
func hear(e: AIEnemy, at: Vector2, loud: float, source := "") -> void:
	heard += 1
	alert += loud
	if alert >= PROVOKE:
		e.provoke("noise: " + source if source != "" else "noise")
		return
	if loud >= INVESTIGATE_AT or (loud >= FAINT and rng.randf() < 0.5):
		investigate(e, at)
	elif loud >= FAINT and rng.randf() < 0.35:
		_lose_interest(e)                  # it wanders away from the sound


## Exp 008 (E): walks straight to plan point p (snapped to the nearest
## walkable cell) and lingers there, without the entrance rule of
## investigate(): a POI enemy's route (a doorway, then into the room). Returns
## the goal, or INF when there is no walkable cell near p.
func walk_to(e: AIEnemy, p: Vector2, s := "investigate", at := Vector2.INF) -> Vector2:
	var to := _snap(e, p)
	if to != Vector2.INF:
		_go(e, s, to, at)
	return to


## Comes to look at plan point p (outside a building: the entrance nearest to it).
func investigate(e: AIEnemy, p: Vector2) -> void:
	var to := _entrance_near(e, p)
	if to == Vector2.INF:
		to = _snap(e, p)
	if to == Vector2.INF:
		return
	_go(e, "investigate", to, p)


# --- activities -----------------------------------------------------------------------

func _next(e: AIEnemy) -> void:
	match mode:
		"straggler":
			while not plan.is_empty():
				var act: String = plan.pop_front()
				var g := _target_for(e, act)
				if g[0] != Vector2.INF:
					_go(e, act, g[0], g[1])
					return
			if rng.randf() < RESTLESS:
				e.provoke("restless")
				return
			_leave(e)
		"hidden":
			_go(e, "lurk", _snap(e, anchor), Vector2.INF)
		_:
			_go(e, "wander", _wander_point(e), Vector2.INF)


func _go(e: AIEnemy, s: String, g: Vector2, at: Vector2) -> void:
	state = s
	goal = g
	look = at
	linger = -1.0
	goal_t = 0.0
	history.append(s)
	if history.size() > 12:
		history.pop_front()
	e.brain.invalidate()


func _lose_interest(e: AIEnemy) -> void:
	if mode == "straggler":
		plan.clear()
		_leave(e)
	else:
		_next(e)


## Back into the fog (home): the roster's retreat fades it out there.
func _leave(e: AIEnemy) -> void:
	state = "leave"
	history.append("leave")
	var pts := _fog_points(e)
	if pts.is_empty():
		mode = "wander"
		_go(e, "wander", _wander_point(e), Vector2.INF)
		return
	var me := e.plan_pos()
	var best: Vector2 = pts[0]
	for p in pts:
		if (p as Vector2).distance_to(me) < best.distance_to(me):
			best = p
	goal = best
	e.set_meta("calm_leave", true)
	e.set_meta("retreat", 0.0)
	e.set_meta("retreat_to", best)
	e.retreat_to(best)


## [goal, look] for an activity; goal INF when there is nothing to do it at.
func _target_for(e: AIEnemy, act: String) -> Array:
	var w := e.world
	var me := e.plan_pos()
	if w == null:
		return [Vector2.INF, Vector2.INF]
	match act:
		"pass":
			return [_pass_point(e), Vector2.INF]
		"window":
			var best := [Vector2.INF, Vector2.INF]
			var best_d := INF
			for win in HouseRooms.windows(w, e.storey):
				var c: Vector2 = win["centre"]
				var out := (c - (win["inside"] as Vector2)).normalized()
				var stand := w._stand_point(c, out)
				var d := stand.distance_to(me) + rng.randf() * 4.0 if stand != Vector2.INF else INF
				if d < best_d:
					best_d = d
					best = [stand, c]
			return best
		"door", "examine":
			var best := [Vector2.INF, Vector2.INF]
			var best_d := INF
			for wp in w.weak_points(me):
				var ok := false
				if act == "door":
					ok = wp["kind"] == "door"
				elif wp.get("object") != null:
					var o: WorldObject = wp["object"]
					ok = o.hp < o.max_hp
				elif wp["kind"] == "wall":
					ok = w.section_integrity(wp["seg"]) < 0.9
				if not ok:
					continue
				var d: float = (wp["pos"] as Vector2).distance_to(me) + rng.randf() * 4.0
				if d < best_d:
					best_d = d
					best = [wp["pos"], wp["target"]]
			return best
	return [Vector2.INF, Vector2.INF]


## Across the property: the spawn point mirrored through the house's middle.
func _pass_point(e: AIEnemy) -> Vector2:
	var mid := _middle(e)
	var me := e.plan_pos()
	var far := mid + (mid - me).rotated(rng.randf_range(-0.6, 0.6)) * rng.randf_range(0.6, 0.9)
	var p := _snap(e, far)
	return p if p != Vector2.INF else _wander_point(e)


func _middle(e: AIEnemy) -> Vector2:
	if e.world != null and not e.world.has_method("entry_point"):
		return HousePlan.FOOTPRINT.get_center()
	return e.nav.bounds.get_center() if e.nav != null else anchor


func _wander_point(e: AIEnemy) -> Vector2:
	for i in 8:
		var a := rng.randf() * TAU
		var p := _snap(e, anchor + Vector2(cos(a), sin(a)) * rng.randf_range(2.0, WANDER_RANGE))
		if p != Vector2.INF and p.distance_to(e.plan_pos()) > 1.0:
			return p
	return _snap(e, anchor)


## The nearest walkable nav cell centre to p (within 2 m), or INF.
func _snap(e: AIEnemy, p: Vector2) -> Vector2:
	var nav := e.nav
	if nav == null or not p.is_finite():
		return Vector2.INF
	var c := nav.cell_of(p)
	for r in 9:
		for dj in range(-r, r + 1):
			for di in range(-r, r + 1):
				if maxi(absi(di), absi(dj)) != r:
					continue
				var k := c + Vector2i(di, dj)
				if nav.is_walkable(k):
					return nav.center_of(k)
	return Vector2.INF


## A sound inside a building draws it to the nearest way in (door, boards,
## a window); a sound in the open draws it to the spot. INF: the spot itself.
func _entrance_near(e: AIEnemy, p: Vector2) -> Vector2:
	var w := e.world
	if w == null:
		return Vector2.INF
	var rects := HouseRooms.floor_rects(w, e.storey)
	var me := e.plan_pos()
	if not _in(rects, p) or _in(rects, me):
		return Vector2.INF                 # a sound in the open, or it is inside already: straight there
	var best := Vector2.INF
	var best_d := INF
	for wp in w.weak_points(me):
		if not wp["kind"] in ["door", "boards", "barricade"]:
			continue
		var d: float = (wp["target"] as Vector2).distance_to(p) + (wp["pos"] as Vector2).distance_to(me) * 0.25
		if d < best_d:
			best_d = d
			best = wp["pos"]
	for op in w.openings:                  # an open doorway leads straight in
		var mid := (float(op["from"]) + float(op["to"])) * 0.5
		var at := Vector2(mid, float(op["line"])) if int(op["axis"]) == 0 else Vector2(float(op["line"]), mid)
		var d := at.distance_to(p) + at.distance_to(me) * 0.25
		if d < best_d and w.object_at(at, 0.05) == null:
			best_d = d
			best = _snap(e, at)
	return best


static func _in(rects: Array, p: Vector2) -> bool:
	for r in rects:
		if (r as Rect2).has_point(p):
			return true
	return false


func _fog_points(e: AIEnemy) -> Array:
	if e.world == null or e.world.has_method("entry_point") or e.storey != 0:
		return []
	var out := []
	for p in HousePlan.SPAWN_POINTS:
		if not FogBoundary.LOT.has_point(p) and HousePlan.YARD.has_point(p):
			out.append(p)
	return out


# --- senses ---------------------------------------------------------------------------

func _player_pos(e: AIEnemy) -> Vector2:
	var pl = e.player
	if pl == null or not is_instance_valid(pl) or not (pl is Node3D):
		return Vector2.INF
	var g := (pl as Node3D).global_position
	return Vector2(g.x, g.z)


## Looks for Eli; true if it turned hostile.
func _sense(e: AIEnemy, dt: float) -> bool:
	var pl = e.player
	if pl == null or not is_instance_valid(pl) or not (pl is Node3D):
		return false
	var g := (pl as Node3D).global_position
	if absf(g.y - e.floor_y) > 1.5:
		seen_t = 0.0
		return false
	var me := e.plan_pos()
	var p := Vector2(g.x, g.z)
	var d := me.distance_to(p)
	if d <= NOTICE:
		e.provoke("saw Eli")
		return true
	if d <= SIGHT and e.nav != null and e.nav.segment_clear(me, p):
		seen_t += dt
		if state != "investigate" or look.distance_to(p) > 1.0:
			_go(e, "investigate", _snap(e, p), p)
		if seen_t >= SEE_TIME:
			e.provoke("saw Eli")
			return true
	else:
		seen_t = maxf(seen_t - dt, 0.0)
	return false
