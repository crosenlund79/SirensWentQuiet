class_name SiegeDirector
extends Node
## Exp 012 (G): coordinated sieges (ASSIGNMENT §9) and the game's whole-group
## horde wiring (§10); `game.siege`, home only (the game_*.gd helper pattern).
##
## Hordes: at every invasion start the game asks on_invasion_start(); it
## points the InvasionDirector at the world's nav and at in_view() (camera
## frustum and fog), so the whole wave spawns out of Eli's sight, and far
## members re-path less often (InvasionDirector.throttle).
##
## Sieges: an organised siege replaces a normal invasion at its slot when
## SiegeStory.eligible(state) (StoryState.siege_eligible: after Encounter 4
## and its delay), or at once from F10 (dev_siege: never counted as story
## progress). The attackers are ordinary psychos, runners, brutes and bombers
## (compose); he himself never attacks. All of them exist from the start
## (the InvasionDirector's whole-group plan), in 3-4 approach groups on
## different sides. Tactics, per group and member (AIEnemy.set_goal /
## clear_goal steer them; real navigation, bashing included):
##   encircle  each group walks to its own side of the house (rally spots
##             along the wall, RALLY_OUT m out) and gathers there;
##   breach    the brutes (and the bombers, by their own seek rules) go for
##             the weakest entrance they have SEEN on their side (doors,
##             barricades, boards, weak walls: HouseWorld.weak_points), the
##             psychos with them; once it is open they pour in (pressure);
##   contain   psychos hold outside the outer exits (doors, open doorways,
##             breaches), covering Eli's escape routes;
##   pressure  runners (and the psychos once a breach is open) harass in
##             waves: at Eli for HARASS_IN s or two blows, then FALL_BACK m
##             off for HARASS_BACK s, and again; the brutes just push;
##   trap      when Eli (as they perceive him) stays in an inner room, the
##             nearest members go to its exits: at an empty doorway one works
##             for WORK_TIME s (hammering) and puts up a wooden barricade
##             (EnemyBarricades), at a door one stands guard; after a while
##             the brutes break into the room.
## A holding member (encircle, contain, trap) that sees Eli within ENGAGE m
## attacks him (engage) and goes back to its post once he is gone.
## Perception: they never read Eli's position directly for tactics: a
## last-known position from sightings (a member within SIGHT m with a clear
## line on his storey) and noises (gunfire, building: game.noise), with an
## error, and the entrances some member has seen (OBSERVE m, clear line).
## Counterplay: everything they do is physical (bodies at posts, wooden
## barricades that bullets, swings and build mode break), the composition is
## the normal budget's plus a few, and dawn ends it like any invasion.
## Debug: markers (SiegeMarkers), tactics_text(), the F10 section (dev_*).

signal siege_started
signal siege_ended(reason: String)
signal barricade_placed(o: WorldObject)

const Director := preload("res://src/game/invasion_director.gd")

const TICK := 0.25               ## s between tactic updates
const SIGHT := 13.0              ## m a member sees Eli (clear line, same storey)
const HEAR_NEAR := 3.0           ## m: this close they know where he is anyway
const SIGHT_ERROR := 0.6         ## m of error in a sighting
const NOISE_ERROR := 1.8         ## m of error in a heard position
const OBSERVE := 11.0            ## m an entrance is seen from (clear line)
const ENGAGE := 5.5              ## m: a holder attacks Eli this close (seen)
const ENGAGE_TRAP := 2.2         ## m: a trap worker keeps at its job unless he's this close
const DISENGAGE := 10.0          ## m: and goes back to its post beyond this
const RALLY_OUT := 3.2           ## m outside the house's wall line
const RALLY_SPREAD := 3.5        ## m along the wall between rally spots
const GATHER := 0.6              ## share of a group at its rally spots before it goes on
const ENCIRCLE_MIN := 8.0        ## s a group gathers at least (so the sides push together)
const ENCIRCLE_MAX := 22.0       ## s at most before a group goes on to its tactic
const HARASS_IN := 6.0           ## s a harasser goes at Eli (or until it landed two blows) ...
const HARASS_BACK := 5.0         ## s ... before it falls back this long
const FALL_BACK := 6.0           ## m from Eli it falls back to
const HOLD_OUT := 1.6            ## m outside an outer exit
const TRAP_AFTER := 4.0          ## s Eli stays (perceived) in an inner room before they trap it
const FRESH := 25.0              ## s a sighting stays good enough for a trap
const WORK_TIME := 3.5           ## s of work before a barricade stands
const WORK_REACH := 0.9          ## m from the work spot
const WORK_OUT := 1.0            ## m from the doorway line, on the far side from Eli
const MAX_BARRICADES := 3        ## per siege
const BREAK_IN_AFTER := 35.0     ## s after the trap before the brutes break into the room
const ENTRANCES_EVERY := 2.0     ## s between entrance list refreshes
const BANNER := "They're coming — organised."
const MIN_MEMBERS := 6          ## (lead: 7 + one invasion ahead overwhelmed a prepared defender in testing)

var game: Node
var active := false              ## a siege is running
var forced := false              ## F10: the next invasion is a siege
var counted := false             ## this siege counted as story progress
var groups: Array = []           ## [{"id", "side", "role", "state", "members", "rally", "t", "target"}]
var last_known := Vector2.INF    ## where they believe Eli is
var known_age := 999.0           ## s since they last saw or heard him
var known_by := ""               ## "sight" | "noise" | "guess"
var observed := {}               ## entrance key -> entrance (weak point or exit)
var trap := {}                   ## {"room", "centre", "exits": [...], "t"} while trapping
var placed := 0                  ## barricades put up this siege
var markers_on := false
var log_lines: Array = []        ## recent events (F10)
var stats := {"sieges": 0, "barricades": 0, "engaged": 0, "breaches": 0}

var _pending := false
var _adopt: Array = []
var _t := 0.0
var _room_t := 0.0
var _room := -1
var _rooms := {}
var _rooms_rev := -1
var _rooms_t := 0.0
var _entrances: Array = []
var _entr_t := 0.0
var _member := {}                ## enemy instance id -> {"enemy", "group", "tactic", "post", "engaged", "work"}
var _markers: SiegeMarkers
var _watcher: Node3D
var _rng := RandomNumberGenerator.new()
var _throttle_t := 0.0


func setup(g: Node) -> void:
	game = g
	_rng.seed = int(g.state.run.get("seed", 0)) + 4051 if g.get("state") != null else 4051
	if g.has_signal("invasion_started"):
		g.invasion_started.connect(_on_invasion_started)
	if g.has_signal("invasion_ended"):
		g.invasion_ended.connect(_on_invasion_ended)
	var r = g.get("roster")
	if r != null and r.has_signal("enemy_spawned"):
		r.enemy_spawned.connect(_on_enemy_spawned)
	var n = g.get("noise")
	if n != null and n.has_signal("noise_made"):
		n.noise_made.connect(_on_noise)
	var w := _world()
	if w != null:
		w.structure_changed.connect(func(): EnemyBarricades.harden(w))     # their barricades stop bullets (also after a load)
		EnemyBarricades.harden(w)
	_markers = SiegeMarkers.new()
	_markers.name = "SiegeMarkers"
	add_child(_markers)


func _world() -> HouseWorld:
	return game.world if game != null else null


func _director() -> RefCounted:
	return game.director if game != null else null


func _eli() -> Vector2:
	return game.player.plan_pos()


func _eli_storey() -> int:
	var lv = game.get("levels")
	return int(lv.player_storey) if lv != null and lv.get("player_storey") != null else 0


# --- starting -------------------------------------------------------------------------

## The game is about to begin an invasion's wave with `kinds` ([] = the
## budget's). Every wave: spawn out of sight. A siege (story or F10): returns
## the siege's wave and arms the director's approach groups.
func on_invasion_start(kinds: Array, seed: int) -> Array:
	var d = _director()
	d.nav = _world().nav
	d.view_check = in_view
	d.side_of = []
	d.group_sides = []
	d.sides = 0
	var story := not forced and kinds.is_empty() and SiegeStory.eligible(game.state)
	if not (forced or story):
		return kinds
	var w := compose(game.state.difficulty, game.state.invasion_index(), seed) if kinds.is_empty() else kinds.duplicate()
	counted = story
	if story:
		SiegeStory.note(game.state)
	forced = false
	_plan_groups(w)
	active = true
	_pending = true
	_adopt = []
	placed = 0
	trap = {}
	observed = {}
	_member = {}
	_room = -1
	_room_t = 0.0
	known_age = 999.0
	last_known = HousePlan.FOOTPRINT.get_center() + Vector2(_rng.randf_range(-2.5, 2.5), _rng.randf_range(-1.5, 1.5))
	known_by = "guess"
	stats["sieges"] = int(stats["sieges"]) + 1
	_log("Siege: %d attackers in %d groups (%s)" % [w.size(), groups.size(), ", ".join(groups.map(func(g): return "%s %s" % [g["side"], g["role"]]))])
	return w


## The siege's wave: the normal budget of this invasion, at least
## MIN_MEMBERS, with at least one brute (to breach), two runners (to harass)
## and three psychos (to contain). Deterministic for the seed.
static func compose(lv: String, inv: int, seed: int) -> Array:
	var w: Array = Director.compose(lv, inv, seed)
	var cap := mini(Director.max_count(lv, inv) + 2, Director.MAX_COUNT)
	while w.size() < MIN_MEMBERS:
		w.append("psycho")
	if not w.has("brute"):
		_swap_psycho(w, "brute")
	while w.count("runner") < 2 and _swap_psycho(w, "runner"):
		pass
	while w.count("psycho") < 3 and w.size() < maxi(cap, MIN_MEMBERS + 2):
		w.append("psycho")
	return w


static func _swap_psycho(w: Array, to: String) -> bool:
	for i in range(w.size() - 1, 0, -1):
		if w[i] == "psycho" and w.count("psycho") > 3:
			w[i] = to
			return true
	if w.size() < Director.MAX_COUNT:
		w.append(to)
		return true
	return false


## Roles and sides: the breach group on the side of the weakest entrance
## (brutes and bombers), a pressure group (runners), the psychos spread over
## the contain groups and topping up the others.
func _plan_groups(w: Array) -> void:
	var world := _world()
	var sides := ["north", "east", "south", "west"]
	var weak := world.weak_points(HousePlan.FOOTPRINT.get_center()) if world != null else []
	var breach_side: String = Director.side_at((weak[0] as Dictionary)["target"]) if not weak.is_empty() else sides[_rng.randi_range(0, 3)]
	var rest := sides.filter(func(s): return s != breach_side)
	for i in range(rest.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t = rest[i]
		rest[i] = rest[j]
		rest[j] = t
	var gc := 4 if w.size() >= 9 else 3
	var roles := ["breach", "pressure", "contain", "contain"]
	groups = []
	for g in gc:
		var side: String = breach_side if g == 0 else rest[g - 1]
		groups.append({"id": g, "side": side, "role": roles[g], "state": "encircle", "members": [], "rally": rally_point(side), "t": 0.0, "target": {}})
	var of := []
	var count := []
	count.resize(gc)
	count.fill(0)
	for k in w:
		var g := -1
		match str(k):
			"brute", "bomber":
				g = 0
			"runner":
				g = 1
		of.append(g)
		if g >= 0:
			count[g] += 1
	for i in w.size():
		if of[i] >= 0:
			continue
		var best := gc - 1
		for g in range(gc - 1, -1, -1):
			if count[g] < count[best]:
				best = g
		of[i] = best
		count[best] += 1
	var d = _director()
	d.side_of = of
	d.group_sides = groups.map(func(g): return g["side"])
	d.sides = gc


## The middle of the house's `side`, RALLY_OUT m outside its wall.
static func rally_point(side: String) -> Vector2:
	var f := HousePlan.FOOTPRINT
	match side:
		"north":
			return Vector2(f.get_center().x, f.position.y - RALLY_OUT)
		"south":
			return Vector2(f.get_center().x, f.end.y + RALLY_OUT)
		"east":
			return Vector2(f.end.x + RALLY_OUT, f.get_center().y)
	return Vector2(f.position.x - RALLY_OUT, f.get_center().y)


func _on_invasion_started() -> void:
	if active and game.has_method("toast"):
		game.toast(BANNER, "bad")
		siege_started.emit()


func _on_enemy_spawned(e: Node, _kind: String) -> void:
	if _pending and e is AIEnemy:
		_adopt.append(e)


func _on_invasion_ended(reason: String) -> void:
	if active:
		end(reason)


## Ends the siege: everyone back to plain hunting (or the dawn retreat), the
## watcher leaves, the markers go. Enemy barricades stay until destroyed.
func end(reason := "") -> void:
	for id in _member.keys():
		var e = _member[id]["enemy"]
		if is_instance_valid(e) and e is AIEnemy:
			(e as AIEnemy).clear_goal()
	_member = {}
	groups = []
	trap = {}
	active = false
	_pending = false
	_adopt = []
	if _watcher != null and is_instance_valid(_watcher):
		_watcher.queue_free()
	_watcher = null
	_markers.clear()
	_log("Siege over (%s)" % reason)
	siege_ended.emit(reason)


# --- per frame -------------------------------------------------------------------------

func _process(delta: float) -> void:
	if game == null:
		return
	if not active:
		_throttle_t -= delta
		if _throttle_t <= 0.0 and game.director.active:      # a normal invasion: far members stay cheap too
			_throttle_t = 1.0
			Director.throttle(game.roster.threats(), _eli())
		return
	if _pending:
		var d = _director()
		if d.all_spawned() and _adopt.size() >= d.total:
			_take_members()
		elif not d.active:
			end("no wave")
		return
	_t += delta
	if _t < TICK:
		return
	var dt := _t
	_t = 0.0
	update(dt)


## Puts the spawned members in their groups (InvasionDirector.note_spawned
## left "horde_group" on each) and places the watcher.
func _take_members() -> void:
	_pending = false
	for e in _adopt:
		if not is_instance_valid(e) or not (e as AIEnemy).alive:
			continue
		var g := clampi(int(e.get_meta("horde_group", 0)), 0, groups.size() - 1)
		groups[g]["members"].append(e)
		_member[e.get_instance_id()] = {"enemy": e, "group": g, "tactic": "encircle", "post": Vector2.INF, "engaged": false, "work": 0.0}
	_adopt = []
	_place_watcher()


## One tactic step (`dt` s since the last).
func update(dt: float) -> void:
	var world := _world()
	if world == null:
		return
	_prune()
	_perceive(dt)
	_entr_t -= dt
	if _entr_t <= 0.0:
		_entr_t = ENTRANCES_EVERY
		_entrances = _list_entrances()
	_track_room(dt)
	for g in groups:
		_run_group(g, dt)
	if not trap.is_empty():
		_run_trap(dt)
	_engage()
	Director.throttle(_member.values().map(func(m): return m["enemy"]), _eli())
	if markers_on:
		_markers.draw(marker_entries())


func _prune() -> void:
	for id in _member.keys():
		var e = _member[id]["enemy"]
		if not is_instance_valid(e) or not e.alive or e.has_meta("retreat"):
			_member.erase(id)
	for g in groups:
		g["members"] = (g["members"] as Array).filter(func(e): return is_instance_valid(e) and e.alive and _member.has(e.get_instance_id()))


# --- perception -----------------------------------------------------------------------

func _perceive(dt: float) -> void:
	known_age += dt
	var eli := _eli()
	var storey := _eli_storey()
	var nav := _world().nav
	for m in _member.values():
		var e: AIEnemy = m["enemy"]
		var d := e.plan_pos().distance_to(eli)
		if e.storey == storey and (d <= HEAR_NEAR or (d <= SIGHT and (storey != 0 or nav.segment_clear(e.plan_pos(), eli)))):
			_know(eli, SIGHT_ERROR, "sight")
			break
	for en in _entrances:
		if observed.has(en["key"]):
			continue
		for m in _member.values():
			var e: AIEnemy = m["enemy"]
			if e.plan_pos().distance_to(en["pos"]) <= OBSERVE and nav.segment_clear(e.plan_pos(), en["pos"]):
				observed[en["key"]] = en
				break


func _know(at: Vector2, err: float, how: String) -> void:
	last_known = at + Vector2(_rng.randf_range(-err, err), _rng.randf_range(-err, err))
	known_age = 0.0
	known_by = how


## A noise (game.noise): loud ones tell them roughly where Eli is.
func _on_noise(ev: Dictionary) -> void:
	if not active or _pending:
		return
	var src := str(ev.get("source", ""))
	if src.begins_with("shout") or src.begins_with("enemy"):
		return
	var pos: Variant = ev.get("pos", null)
	if pos is Vector3 and float(ev.get("level", 0.0)) >= 0.4:
		var p := Vector2((pos as Vector3).x, (pos as Vector3).z)
		if p.distance_to(_eli()) >= 4.0:     # not his noise (a turret far off, a blast)
			return
		var r := float(ev.get("radius", 0.0))
		for m in _member.values():
			if (m["enemy"] as AIEnemy).plan_pos().distance_to(p) <= r:
				_know(p, NOISE_ERROR, "noise")    # someone heard it
				return


## Entrances (outside stand point -> target): the world's weak points and the
## outer exits; keys are stable per place.
func _list_entrances() -> Array:
	var out := []
	var world := _world()
	for w in world.weak_points(HousePlan.FOOTPRINT.get_center()):
		out.append({"key": "%s@%d,%d" % [w["kind"], roundi(w["target"].x * 4), roundi(w["target"].y * 4)], "pos": w["pos"], "target": w["target"],
			"kind": w["kind"], "strength": w["strength"], "side": Director.side_at(w["target"]), "weak": true})
	for x in outer_exits():
		out.append({"key": "exit@%d,%d" % [roundi(x["pos"].x * 4), roundi(x["pos"].y * 4)], "pos": x["post"], "target": x["pos"],
			"kind": x["kind"], "strength": 0.0, "side": Director.side_at(x["pos"]), "weak": false})
	return out


# --- rooms ----------------------------------------------------------------------------

func rooms() -> Dictionary:
	var world := _world()
	if _rooms.is_empty() or (_rooms_rev != world.nav.revision and _rooms_t <= 0.0):
		_rooms = HouseRooms.find(world, 0)
		_rooms_rev = world.nav.revision
		_rooms_t = 2.0
	return _rooms


## Doors and doorways of the ground floor that lead outside, each with a
## post HOLD_OUT m out: [{"pos", "post", "kind", "open"}].
func outer_exits() -> Array:
	var out := []
	var map := rooms()
	for ds in NoisePlace.door_sides(_world(), map):
		var a := int(ds["a"])
		var b := int(ds["b"])
		if (a < 0) == (b < 0):
			continue
		var p: Vector2 = ds["pos"]
		var o := _out_dir(p)
		out.append({"pos": p, "post": _walkable_near(p + o * HOLD_OUT), "kind": ds["kind"], "open": ds["open"]})
	for r in map.get("rooms", []):
		if r["exposed"] and r["exposed_at"] is Vector2:
			var q: Vector2 = r["exposed_at"]
			out.append({"pos": q, "post": _walkable_near(q + _out_dir(q) * HOLD_OUT), "kind": "breach", "open": true})
	return out


## Is room `i` an inner room: closed off from outside, every exit into another room?
func inner_room(i: int) -> bool:
	var map := rooms()
	if i < 0 or i >= (map.get("rooms", []) as Array).size():
		return false
	if map["rooms"][i]["exposed"]:
		return false
	var exits := 0
	for ds in NoisePlace.door_sides(_world(), map):
		if int(ds["a"]) == i or int(ds["b"]) == i:
			if int(ds["a"]) < 0 or int(ds["b"]) < 0:
				return false
			exits += 1
	return exits > 0


func _track_room(dt: float) -> void:
	_rooms_t -= dt
	if known_age > FRESH or _eli_storey() != 0:
		_room_t = 0.0
		_room = -1
		return
	var i := HouseRooms.room_index_at(rooms(), _world().nav, last_known, 3)
	if i != _room:
		_room = i
		_room_t = 0.0
	else:
		_room_t += dt
	if not trap.is_empty() and i != int(trap["room"]) and known_by == "sight" and known_age < 1.0:
		_log("He got out of the room.")
		_end_trap()
	if trap.is_empty() and _room >= 0 and _room_t >= TRAP_AFTER and inner_room(_room):
		_start_trap(_room)


# --- groups ---------------------------------------------------------------------------

func _run_group(g: Dictionary, dt: float) -> void:
	g["t"] = float(g["t"]) + dt
	var members: Array = g["members"]
	if members.is_empty():
		return
	match str(g["state"]):
		"encircle":
			var at := 0
			for k in members.size():
				var e: AIEnemy = members[k]
				var spot := _rally_spot(g, k, members.size())
				_post(e, spot, "encircle")
				if e.plan_pos().distance_to(spot) < 2.0:
					at += 1
			if (float(at) >= GATHER * members.size() and float(g["t"]) >= ENCIRCLE_MIN) or float(g["t"]) >= ENCIRCLE_MAX:
				g["state"] = g["role"]
				g["t"] = 0.0
				_log("%s group (%d): %s" % [str(g["side"]).capitalize(), members.size(), g["role"]])
		"breach":
			_run_breach(g)
		"pressure":
			for e in members:
				_harass(g, e, dt)
		"contain":
			_run_contain(g)


## Pressure: runners and psychos harass in waves (go at Eli, land a blow or
## two, fall back a few metres, come again); brutes just push.
func _harass(g: Dictionary, e: AIEnemy, dt: float) -> void:
	var m: Dictionary = _member.get(e.get_instance_id(), {})
	if m.is_empty() or m.get("trap", false):
		return
	if e.kind == "brute":
		_post(e, Vector2.INF, "pressure")
		return
	var h: Dictionary = m.get("harass", {})
	if h.is_empty():
		h = {"phase": "in", "t": 0.0, "sw": int(e.swings["player"])}
		m["harass"] = h
	h["t"] = float(h["t"]) + dt
	if h["phase"] == "in":
		_post(e, Vector2.INF, "pressure")
		if int(e.swings["player"]) >= int(h["sw"]) + 2 or float(h["t"]) >= HARASS_IN:
			var eli := _eli()
			var away := (e.plan_pos() - eli).normalized()
			if away == Vector2.ZERO:
				away = ((g["rally"] as Vector2) - eli).normalized()
			h["spot"] = _walkable_near(eli + away * FALL_BACK)
			h["phase"] = "back"
			h["t"] = 0.0
	else:
		_post(e, h["spot"], "pressure")
		if float(h["t"]) >= HARASS_BACK:
			h["phase"] = "in"
			h["t"] = 0.0
			h["sw"] = int(e.swings["player"])


func _rally_spot(g: Dictionary, k: int, n: int) -> Vector2:
	var side := str(g["side"])
	var along := Vector2(1, 0) if side == "north" or side == "south" else Vector2(0, 1)
	var off := (float(k) - (n - 1) * 0.5) * (RALLY_SPREAD / maxf(1.0, n * 0.5))
	return _walkable_near(g["rally"] + along * clampf(off, -5.0, 5.0))


## The breach group: the weakest SEEN entrance on (or nearest to) its side;
## brutes and psychos go through it, bombers seek on their own.
func _run_breach(g: Dictionary) -> void:
	var t: Dictionary = g["target"]
	if not t.is_empty() and not _still_closed(t):
		stats["breaches"] = int(stats["breaches"]) + 1
		_log("Breach at the %s (%s side): they pour in." % [t["kind"], g["side"]])
		g["state"] = "pressure"
		g["target"] = {}
		return
	if t.is_empty():
		t = _pick_breach(str(g["side"]))
		g["target"] = t
		if not t.is_empty():
			_log("%s group breaches the %s." % [str(g["side"]).capitalize(), t["kind"]])
	for e in g["members"]:
		if t.is_empty():
			_post(e, Vector2.INF, "breach")
		else:
			var inward: Vector2 = (t["target"] - t["pos"]).normalized()
			_post(e, t["target"] + inward * 0.9, "breach")


func _pick_breach(side: String) -> Dictionary:
	var best := {}
	var score := -INF
	for en in observed.values():
		if not en["weak"] or not _still_closed(en):
			continue
		var s: float = 1.0 / maxf(float(en["strength"]), 0.1) - (0.0 if en["side"] == side else 1.5)
		if s > score:
			score = s
			best = en
	return best


## Is an entrance still standing (in the current weak points)?
func _still_closed(en: Dictionary) -> bool:
	for w in _entrances:
		if w["key"] == en["key"]:
			return true
	return false


## Contain: the psychos spread over the outer exits (nearest first), holding
## posts outside them; without any, at their rally spots.
func _run_contain(g: Dictionary) -> void:
	var posts := []
	for x in outer_exits():
		posts.append(x["post"])
	var members: Array = g["members"]
	var rally: Vector2 = g["rally"]
	posts.sort_custom(func(a, b): return (a as Vector2).distance_to(rally) < (b as Vector2).distance_to(rally))
	for k in members.size():
		var e: AIEnemy = members[k]
		if posts.is_empty():
			_post(e, _rally_spot(g, k, members.size()), "contain")
		else:
			_post(e, posts[k % posts.size()], "contain")


# --- trap -----------------------------------------------------------------------------

func _start_trap(room: int) -> void:
	var map := rooms()
	var exits := []
	for ds in NoisePlace.door_sides(_world(), map):
		var a := int(ds["a"])
		var b := int(ds["b"])
		if a != room and b != room:
			continue
		var p: Vector2 = ds["pos"]
		var s := HouseWorld.nearest_seg(p)
		var n := Vector2(0, 1) if s.x == 0 else Vector2(1, 0)
		var away := n if a == room else -n          # from Eli's room to the other side
		exits.append({"pos": p, "seg": s, "kind": ds["kind"], "open": ds["open"], "spot": _walkable_near(p + away * WORK_OUT),
			"worker": null, "state": "pending", "work": 0.0})
	trap = {"room": room, "centre": map["rooms"][room]["centre"], "exits": exits, "t": 0.0}
	_log("He's in a room: trap its %d exit(s)." % exits.size())


func _end_trap() -> void:
	for m in _member.values():
		if m.get("trap", false):
			m["trap"] = false
			m["tactic"] = "contain"
	trap = {}


func _run_trap(dt: float) -> void:
	trap["t"] = float(trap["t"]) + dt
	var world := _world()
	for x in trap["exits"]:
		var e = x["worker"]
		if not (is_instance_valid(e) and e.alive and _member.has(e.get_instance_id())):
			x["worker"] = null
			x["work"] = 0.0
			e = _pick_worker(x)
			if e == null:
				continue
			x["worker"] = e
			_member[e.get_instance_id()]["trap"] = true
		var en: AIEnemy = e
		var m: Dictionary = _member[en.get_instance_id()]
		_post(en, x["spot"], "trap", true)
		if m["engaged"] or x["state"] != "pending" or x["kind"] != "doorway" or not x["open"]:
			continue
		if placed >= MAX_BARRICADES:
			x["state"] = "guard"
			continue
		if en.plan_pos().distance_to(x["spot"]) > WORK_REACH:
			x["work"] = 0.0
			m["tactic"] = "trap"
			continue
		var why := EnemyBarricades.why_not(world, x["seg"])
		if why != "" and why != "someone stands there":
			x["state"] = "guard"
			continue
		# at work: hammering, a swing now and then; nobody may stand in the way
		x["work"] = float(x["work"]) + dt
		m["tactic"] = "work"
		if fmod(float(x["work"]), 0.9) < dt:
			en.rig.swing = 1.0
			Sfx.play("build/hammer", Vector3(x["pos"].x, 1.0, x["pos"].y))
		if float(x["work"]) >= WORK_TIME and why == "":
			var o := EnemyBarricades.place(world, x["seg"])
			if o != null:
				placed += 1
				stats["barricades"] = int(stats["barricades"]) + 1
				x["state"] = "done"
				m["tactic"] = "trap"
				barricade_placed.emit(o)
				_log("A barricade went up in a doorway.")
				if placed == 1 and game.has_method("toast"):
					game.toast("They're barricading the doorway!", "bad")
	# after a while the brutes break into the room
	if float(trap["t"]) >= BREAK_IN_AFTER:
		for m in _member.values():
			var e2: AIEnemy = m["enemy"]
			if e2.kind == "brute":
				m["trap"] = true
				_post(e2, trap["centre"], "breach", true)


## The nearest free member for an exit: psychos and runners (no brutes, no bombers).
func _pick_worker(x: Dictionary) -> AIEnemy:
	var busy := {}
	for y in trap["exits"]:
		if is_instance_valid(y["worker"]):
			busy[y["worker"].get_instance_id()] = true
	var best: AIEnemy = null
	var bd := INF
	for m in _member.values():
		var e: AIEnemy = m["enemy"]
		if busy.has(e.get_instance_id()) or e.kind == "brute" or e.kind == "bomber" or m["engaged"]:
			continue
		var d := e.plan_pos().distance_to(x["spot"])
		if d < bd:
			bd = d
			best = e
	return best


# --- steering -------------------------------------------------------------------------

## Gives a member its post (INF = hunt Eli freely) and tactic, unless it is
## engaging Eli right now.
func _post(e: AIEnemy, at: Vector2, tactic: String, from_trap := false) -> void:
	var m: Dictionary = _member.get(e.get_instance_id(), {})
	if m.is_empty() or (m.get("trap", false) and not from_trap):
		return                               # a trap job outranks the group's orders
	if m["tactic"] != "work" or tactic != "trap":
		m["tactic"] = tactic
	m["post"] = at
	if m["engaged"] or e.kind == "bomber":
		return
	if at == Vector2.INF:
		e.clear_goal()
	else:
		e.set_goal(at, tactic)


## Holders that see Eli close attack him; they go back once he's gone.
func _engage() -> void:
	var eli := _eli()
	var storey := _eli_storey()
	var nav := _world().nav
	for m in _member.values():
		var e: AIEnemy = m["enemy"]
		if e.kind == "bomber" or m["post"] == Vector2.INF or m["tactic"] == "pressure":
			continue                         # harassers come and go on their own rhythm
		var d := e.plan_pos().distance_to(eli)
		if not m["engaged"]:
			var reach := ENGAGE_TRAP if m.get("trap", false) else ENGAGE
			if m["tactic"] != "work" and e.storey == storey and d <= reach and nav.segment_clear(e.plan_pos(), eli):
				m["engaged"] = true
				stats["engaged"] = int(stats["engaged"]) + 1
				e.clear_goal()
		elif d > DISENGAGE or e.storey != storey:
			m["engaged"] = false
			e.set_goal(m["post"], str(m["tactic"]))


# --- helpers --------------------------------------------------------------------------

## Unit plan vector from house point p toward the outside.
func _out_dir(p: Vector2) -> Vector2:
	var f := HousePlan.FOOTPRINT
	var dl := [absf(p.x - f.position.x), absf(f.end.x - p.x), absf(p.y - f.position.y), absf(f.end.y - p.y)]
	var dirs := [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]
	var best := 0
	for i in 4:
		if dl[i] < dl[best]:
			best = i
	return dirs[best]


## The nearest walkable nav cell centre to p (within ~1.5 m), else p.
func _walkable_near(p: Vector2) -> Vector2:
	var nav := _world().nav
	var c := nav.cell_of(p)
	if nav.is_walkable(c):
		return p
	for r in range(1, 7):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var q := c + Vector2i(dx, dy)
				if nav.is_walkable(q):
					return nav.center_of(q)
	return p


## Would Eli see a body appear at plan point p now? In the camera's view and
## not hidden in the fog bank (InvasionDirector.HIDDEN_IN_FOG).
func in_view(p: Vector2) -> bool:
	var cam: Camera3D = game.get("camera")
	var eli := _eli()
	if cam == null or not cam.is_inside_tree():
		return p.distance_to(eli) < 14.0
	var seen := false
	for h in [0.2, 1.0, 1.9]:
		if cam.is_position_in_frustum(Vector3(p.x, h, p.y)):
			seen = true
			break
	return seen


## He may watch from the fog (after the story introduced him): a figure, not
## an enemy, far from Eli on the breach side, gone when the siege ends.
func _place_watcher() -> void:
	if not SiegeStory.introduced(game.state) or groups.is_empty():
		return
	var side := str(groups[0]["side"])
	var best := Vector2.INF
	for q in Director.fog_points():
		if Director.side_at(q) == side or best == Vector2.INF:
			if best == Vector2.INF or (q as Vector2).distance_to(_eli()) > best.distance_to(_eli()):
				best = q
	var f := ArchitectFigure.new()
	f.name = "SiegeWatcher"
	f.add_to_group("fow_dynamic")          # drawn only while Eli can see him (Exp 012 (V))
	f.target = game.player
	game.add_child(f)
	f.global_position = Vector3(best.x, 0.0, best.y)
	f.set("_home", f.global_position)
	_watcher = f


func _log(text: String) -> void:
	log_lines.append(text)
	while log_lines.size() > 10:
		log_lines.pop_front()


# --- debug and F10 --------------------------------------------------------------------

## The members' tactics and goals (markers, tests).
func marker_entries() -> Array:
	var out := []
	for m in _member.values():
		var e: AIEnemy = m["enemy"]
		var t := "engage" if m["engaged"] else str(m["tactic"])
		out.append({"enemy": e, "tactic": t, "goal": e.directed_goal if e.has_goal() else Vector2.INF})
	return out


## Tactic -> how many members use it now.
func tactic_counts() -> Dictionary:
	var out := {}
	for en in marker_entries():
		out[en["tactic"]] = int(out.get(en["tactic"], 0)) + 1
	return out


func tactics_text() -> String:
	if not active:
		return "No siege. %d so far; %d enemy barricades standing." % [int(stats["sieges"]), EnemyBarricades.all_in(_world()).size()]
	var lines := []
	if _pending:
		lines.append("Siege starting: %d groups." % groups.size())
	for g in groups:
		var kinds := (g["members"] as Array).map(func(e): return (e as AIEnemy).kind)
		var tg := ""
		if not (g["target"] as Dictionary).is_empty():
			tg = " → %s" % g["target"]["kind"]
		lines.append("%s: %s (%s), %d alive %s%s" % [str(g["side"]).capitalize(), g["state"], g["role"], kinds.size(), kinds, tg])
	lines.append("Eli believed at %s (%s, %.0f s ago); %d entrances seen." % [last_known.snapped(Vector2(0.1, 0.1)), known_by, known_age, observed.size()])
	if not trap.is_empty():
		lines.append("Trap: room %d, %d exits, %.0f s; %d barricades." % [int(trap["room"]), (trap["exits"] as Array).size(), float(trap["t"]), placed])
	lines.append("Now: %s" % tactic_counts())
	if not log_lines.is_empty():
		lines.append("Last: " + str(log_lines[log_lines.size() - 1]))
	return "\n".join(lines)


func set_markers(on: bool) -> void:
	markers_on = on
	if not on:
		_markers.clear()
	elif active:
		_markers.draw(marker_entries())


## F10: the night's invasion now (the whole group).
func dev_invasion() -> String:
	if game.director.active:
		return "An invasion is already under way."
	game.dev_trigger_invasion()
	return "Invasion: %d attackers, all on their way." % game.director.total


## F10: a big horde (the budget three invasions ahead), the whole group.
func dev_horde() -> String:
	if game.director.active:
		return "An invasion is already under way."
	var s: GameState = game.state
	var kinds := Director.compose(s.difficulty, s.invasion_index() + 3, randi())
	while kinds.size() < 10:
		kinds.append("psycho" if kinds.size() % 3 else "runner")
	game.dev.dev_wave(kinds)
	return "Horde: %d attackers from several sides." % kinds.size()


## F10: an organised siege now (not counted as story progress).
func dev_siege() -> String:
	if game.director.active:
		return "An invasion is already under way."
	forced = true
	game.dev.dev_wave([])
	if not active:
		forced = false
		return "Could not start a siege here."
	return "Siege: %d attackers in %d groups." % [game.director.total, groups.size()]


func dev_toggle_markers() -> String:
	set_markers(not markers_on)
	return "Tactic markers %s." % ("on" if markers_on else "off")


func dev_clear_barricades() -> String:
	return "Removed %d enemy barricades." % EnemyBarricades.clear(_world())


## F10 and tests: an enemy barricade in the empty doorway nearest Eli.
func dev_barricade_nearest() -> String:
	var o := barricade_nearest(_eli())
	return "Enemy barricade at %s." % o.pos if o != null else "No empty doorway nearby."


func barricade_nearest(p: Vector2) -> WorldObject:
	var world := _world()
	var best: Variant = null
	var bd := INF
	for ds in NoisePlace.door_sides(world, rooms()):
		if ds["kind"] != "doorway" or not ds["open"]:
			continue
		var s := HouseWorld.nearest_seg(ds["pos"])
		if EnemyBarricades.why_not(world, s) != "":
			continue
		var d := p.distance_to(ds["pos"])
		if d < bd:
			bd = d
			best = s
	return EnemyBarricades.place(world, best) if best != null else null


func dev_text() -> String:
	return tactics_text()
