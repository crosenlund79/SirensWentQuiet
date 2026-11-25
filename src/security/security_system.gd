class_name SecuritySystem
extends Node
## Exp 007 (S): the security runtime and its game side (the game_*.gd helper
## pattern: SurvivalGame creates it in _assemble as `security`). Rules are in
## Security, looks in SecurityObjects, the panel is SecurityPanel.
##
## Sensors (4x a second): an enabled, powered sensor looks for a hostile
## enemy on its storey in its cone (Security.SENSOR_RANGE, SENSOR_ARC) with a
## clear line from its eye. Only enemies from the roster are looked at, never
## Eli and never the world. On a detection (at most every SENSOR_COOLDOWN s):
##   - a toast names it: "Sensor at the back door: movement"
##   - a red "!" marks it on screen for MARK_TIME s (seen through walls)
##   - audible: an alarm sound and a noise event (Noise.emit, "alarm");
##     silent: only a soft beep
##   - its linked turret wakes (a standby turret fires only while awake) and
##     turns toward the movement
## Turrets (every physics frame): enabled, powered, with a gun and rounds in
## its magazine, a mount picks the nearest hostile within the gun's range
## (capped), its 120° arc and a clear line (5x a second, and only when an
## enemy is within range at all), turns its head, holds fire while Eli is in
## the line of fire, and fires through HouseWorld.shoot like Eli's weapon
## (pellets, spread, range, damage). Empty: with the auto-loader it reloads
## from its box (the weapon's reload x Security.RELOAD_SCALE); without it
## the player is told once to reload it by hand (E).
##
## Without a game (tests) setup_parts() gives the worlds, the enemies, Eli
## and the power directly; tick(delta) advances everything.

signal sensor_triggered(sensor: WorldObject, enemy: Node)
signal turret_fired(turret: WorldObject, hits: Array)
signal turret_empty(turret: WorldObject)

const SENSOR_STEP := 0.25
const SCAN_STEP := 0.2
const MARK_TIME := 5.0
const ALARM_SOUNDS := ["security/alarm", "ui/error"]
const BEEP_SOUNDS := ["security/sensor_beep", "ui/click"]
const RELOAD_SOUNDS := ["security/turret_reload", "weapon/reload", "weapon/dry_fire"]

var game: Node                         ## SurvivalGame, or null (tests)
var worlds_fn := Callable()            ## -> Array of HouseWorlds (the ground floor first)
var enemies_fn := Callable()           ## -> Array of enemies (the roster's list)
var power_fn := Callable()             ## -> bool (mains power)
var player: Node3D
var auto_tick := true
var rng := RandomNumberGenerator.new()
var panel: SecurityPanel
var time := 0.0                        ## s of security time (runs while the game runs)
var triggers := 0                      ## sensor detections (tests, F10)
var shots := 0                         ## turret shots (tests, F10)
var last_text := ""                    ## the last toast (tests)

var _sensor_t := 0.0
var _rt := {}                          ## object instance id -> runtime state
var _marks: Array = []                 ## [Label3D, seconds left]
var _busy := false


func _ready() -> void:
	rng.randomize()


## Wires the helper into the game.
func setup(g: Node) -> void:
	game = g
	worlds_fn = _game_worlds
	enemies_fn = func() -> Array:
		var r: Variant = game.get("roster")
		return r.enemies if r is Object and is_instance_valid(r) else []
	power_fn = _game_power
	player = game.get("player")
	panel = SecurityPanel.new()
	panel.name = "SecurityPanel"
	add_child(panel)
	panel.closed.connect(_on_panel_closed)


## Tests: the parts without a game.
func setup_parts(worlds: Callable, enemies: Callable, eli: Node3D = null, power := Callable()) -> void:
	worlds_fn = worlds
	enemies_fn = enemies
	player = eli
	power_fn = power


func _game_worlds() -> Array:
	var st: Variant = game.get("storage")
	if st is Object and is_instance_valid(st) and st.has_method("worlds"):
		return st.worlds()
	return [game.world] if game.get("world") != null else []


func _game_power() -> bool:
	var h: Variant = game.get("home")
	if h is Object and is_instance_valid(h) and h.has_method("mains_on"):
		return bool(h.mains_on())
	return Security.world_power(game.get("world"))


func worlds() -> Array:
	var w: Variant = worlds_fn.call() if worlds_fn.is_valid() else []
	return w if w is Array else []


func powered() -> bool:
	if power_fn.is_valid():
		return bool(power_fn.call())
	var ws := worlds()
	return Security.world_power(ws[0] if not ws.is_empty() else null)


## Every sensor and turret on every storey.
func objects(kind := "") -> Array:
	var out := []
	for w in worlds():
		for o in w.objects:
			if Security.is_kind(o.kind) and (kind == "" or o.kind == kind):
				out.append(o)
	return out


func _enemies() -> Array:
	var out := []
	var all: Variant = enemies_fn.call() if enemies_fn.is_valid() else []
	if all is Array:
		for e in all:
			if is_instance_valid(e) and e is VoxelEnemy and e.alive:
				out.append(e)
	return out


func _physics_process(delta: float) -> void:
	if auto_tick:
		tick(delta)


func _process(delta: float) -> void:
	_tick_marks(delta)


## Advances sensors and turrets by `delta` seconds.
func tick(delta: float) -> void:
	time += delta
	_sensor_t -= delta
	var sense := _sensor_t <= 0.0
	if sense:
		_sensor_t = SENSOR_STEP
	var power := powered()
	var enemies := _enemies()
	for w in worlds():
		var storey := Security.storey_of(w)
		for o in (w.objects as Array).duplicate():
			if not is_instance_valid(o):
				continue
			if o.kind == "motion_sensor":
				if sense:
					_sense(o, w, storey, enemies, power)
			elif o.kind == "turret_mount":
				_turret(o, w, storey, enemies, power, delta)


func _runtime(o: WorldObject) -> Dictionary:
	var id := o.get_instance_id()
	if not _rt.has(id):
		_rt[id] = {"last": -1e9, "cd": 0.0, "reload": 0.0, "scan": 0.0, "awake": -1e9, "target": null, "yaw": 0.0, "empty_said": false}
	return _rt[id]


# --- sensors ------------------------------------------------------------------------------

func _sense(o: WorldObject, w: HouseWorld, storey: int, enemies: Array, power: bool) -> void:
	var c := Security.config(o)
	SecurityObjects.set_led(o, "dark" if not power else ("ready" if bool(c["on"]) else "off"))
	if not bool(c["on"]) or not power:
		return
	var rt := _runtime(o)
	if time - float(rt["last"]) < Security.SENSOR_COOLDOWN:
		return
	var e := detect(o, w, storey, enemies)
	if e != null:
		trigger(o, e)


## The nearest enemy `o` sees now, or null.
func detect(o: WorldObject, w: HouseWorld, storey: int, enemies: Array) -> Node:
	var c := Security.config(o)
	var eye := o.global_position + Vector3(0, Security.SENSOR_HEIGHT, 0) if o.is_inside_tree() else Vector3(o.pos.x, Security.SENSOR_HEIGHT, o.pos.y)
	var best: Node = null
	var best_d := INF
	for e in enemies:
		if not Security.is_target(e, bool(c["hostile"])) or Security.storey_of(e) != storey:
			continue
		var p: Vector2 = e.plan_pos()
		var d := p.distance_to(o.pos)
		if d > Security.SENSOR_RANGE or d >= best_d or not Security.in_arc(o, p, Security.SENSOR_ARC):
			continue
		var chest := Vector3(p.x, eye.y - Security.SENSOR_HEIGHT + Security.CHEST, p.y)
		if not Security.clear_line(w, eye, chest):
			continue
		best = e
		best_d = d
	return best


## A detection by sensor `o` (`e` may be null: the F10 test trigger).
func trigger(o: WorldObject, e: Node = null) -> void:
	var c := Security.config(o)
	var rt := _runtime(o)
	rt["last"] = time
	triggers += 1
	var at := Vector3(o.pos.x, Security.SENSOR_HEIGHT, o.pos.y)
	if o.is_inside_tree():
		at = o.global_position + Vector3(0, Security.SENSOR_HEIGHT, 0)
	if bool(c["alarm"]):
		Sfx.play_first(ALARM_SOUNDS, at)
		Security.noise(game if game != null else o.world, at, Security.ALARM_NOISE, "alarm")
	else:
		Sfx.play_first(BEEP_SOUNDS, at)
	_mark(o)
	_toast("%s: movement%s." % [Security.title(o), "" if bool(c["alarm"]) else " (silent)"], "warn")
	var t := turret_by_uid(str(c["link"]))
	if t != null:
		var trt := _runtime(t)
		trt["awake"] = time + Security.WAKE_TIME
		if e != null and is_instance_valid(e):
			trt["target"] = e
			trt["scan"] = 0.0
	sensor_triggered.emit(o, e)


func _mark(o: WorldObject) -> void:
	if not o.is_inside_tree():
		return
	var old := o.get_node_or_null("SecurityMark") as Label3D
	if old != null:
		for m in _marks:
			if m[0] == old:
				m[1] = MARK_TIME
		return
	var l := Label3D.new()
	l.name = "SecurityMark"
	l.text = "!"
	l.font_size = 96
	l.outline_size = 18
	l.modulate = Color(1.0, 0.25, 0.18)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0009
	l.position = Vector3(0, Security.SENSOR_HEIGHT + 0.45, 0)
	o.add_child(l)
	_marks.append([l, MARK_TIME])


func _tick_marks(delta: float) -> void:
	for i in range(_marks.size() - 1, -1, -1):
		var m: Array = _marks[i]
		m[1] = float(m[1]) - delta
		var l: Variant = m[0]
		if not is_instance_valid(l) or float(m[1]) <= 0.0:
			if is_instance_valid(l):
				(l as Node).queue_free()
			_marks.remove_at(i)
		else:
			(l as Label3D).visible = fmod(float(m[1]), 0.6) > 0.18


## The turret with this uid on any storey, or null.
func turret_by_uid(uid: String) -> WorldObject:
	if uid == "":
		return null
	for o in objects("turret_mount"):
		if o.uid == uid:
			return o
	return null


## The sensors linked to turret `t`.
func sensors_of(t: WorldObject) -> Array:
	var out := []
	for o in objects("motion_sensor"):
		if str(Security.config(o)["link"]) == t.uid and t.uid != "":
			out.append(o)
	return out


# --- turrets ------------------------------------------------------------------------------

func _turret(o: WorldObject, w: HouseWorld, storey: int, enemies: Array, power: bool, delta: float) -> void:
	var c := Security.config(o)
	var rt := _runtime(o)
	SecurityObjects.sync_gun(o)
	rt["cd"] = maxf(float(rt["cd"]) - delta, 0.0)
	var id := str(c["gun"])
	var working := bool(c["on"]) and power and id != ""
	if not working:
		rt["target"] = null
		rt["reload"] = 0.0
		SecurityObjects.set_led(o, "dark" if not power else "off")
		return
	var d := WeaponDefs.get_def(id)
	# the auto-loader
	if float(rt["reload"]) > 0.0:
		rt["reload"] = float(rt["reload"]) - delta
		if float(rt["reload"]) <= 0.0:
			var k := Security.auto_step(o)
			var full := Security.mag(o) >= WeaponDefs.capacity(id)
			if k > 0 and not full and Security.box(o) > 0 and str(d.get("reload", "magazine")) == "shell":
				rt["reload"] = float(d["reload_time"]) * Security.RELOAD_SCALE
			else:
				rt["reload"] = 0.0
				Sfx.play_first(["weapon/reload_done"] + RELOAD_SOUNDS, _head_pos(o))
	if Security.mag(o) <= 0:
		if bool(c["auto"]) and Security.box(o) > 0:
			if float(rt["reload"]) <= 0.0:
				rt["reload"] = float(d["reload_time"]) * Security.RELOAD_SCALE
				Sfx.play_first(RELOAD_SOUNDS, _head_pos(o), -4.0)
		elif not bool(rt["empty_said"]):
			rt["empty_said"] = true
			turret_empty.emit(o)
			if Security.box(o) > 0:
				_toast("%s is empty: reload it by hand (E)." % Security.title(o), "warn")
			else:
				_toast("%s is out of ammunition: fill its ammo box (E)." % Security.title(o), "warn")
		SecurityObjects.set_led(o, "warn")
		return
	rt["empty_said"] = false
	SecurityObjects.set_led(o, "ready")
	if bool(c["standby"]) and time > float(rt["awake"]):
		rt["target"] = null
		return
	# targeting (a cheap distance check first)
	rt["scan"] = float(rt["scan"]) - delta
	var t: Variant = rt["target"]
	if not Security.is_target(t) or float(rt["scan"]) <= 0.0:
		rt["scan"] = SCAN_STEP
		t = pick_target(o, w, storey, enemies)
		rt["target"] = t
	if t == null:
		return
	var head := _head_pos(o)
	var aim := (t as Node3D).global_position + Vector3(0, Security.CHEST, 0)
	var want := Security.local_yaw(o, aim - head)
	if absf(want) > deg_to_rad(Security.TURRET_ARC) * 0.5 + 0.05:
		rt["target"] = null
		return
	rt["yaw"] = move_toward(float(rt["yaw"]), want, Security.TURN_SPEED * delta)
	SecurityObjects.set_head_yaw(o, float(rt["yaw"]))
	if absf(want - float(rt["yaw"])) > Security.AIM_TOLERANCE or float(rt["cd"]) > 0.0:
		return
	if not Security.clear_line(w, head, aim, _exclude(o)):
		rt["target"] = null
		return
	if player != null and is_instance_valid(player) and player.is_inside_tree() \
			and Security.blocks_eli(head, aim, player.global_position + Vector3(0, Security.CHEST, 0)):
		return
	if float(rt["reload"]) > 0.0:
		rt["reload"] = 0.0           # shells: a loaded round fires, the reload stops
	fire(o, w, aim)


## The nearest target `o` may engage now (range, arc, clear line), or null.
func pick_target(o: WorldObject, w: HouseWorld, storey: int, enemies: Array) -> Node:
	var rng_m := Security.turret_range(Security.gun(o))
	var head := _head_pos(o)
	var best: Node = null
	var best_d := INF
	for e in enemies:
		var p: Vector2 = e.plan_pos()
		var d := p.distance_to(o.pos)
		if d > rng_m or d >= best_d:
			continue
		if not Security.is_target(e) or Security.storey_of(e) != storey or not Security.in_arc(o, p, Security.TURRET_ARC):
			continue
		if not Security.clear_line(w, head, (e as Node3D).global_position + Vector3(0, Security.CHEST, 0), _exclude(o)):
			continue
		best = e
		best_d = d
	return best


## One shot of the installed gun toward `aim`, as Eli's weapon fires: one
## HouseWorld.shoot per pellet (spread, range), extra damage per hit. Returns the hits.
func fire(o: WorldObject, w: HouseWorld, aim: Vector3) -> Array:
	var id := Security.gun(o)
	var d := WeaponDefs.get_def(id)
	if d.is_empty() or not Security.spend(o):
		return []
	var rt := _runtime(o)
	rt["cd"] = float(d["interval"]) * Security.INTERVAL_SCALE
	shots += 1
	var origin := _head_pos(o)
	var dir := (aim - origin).normalized()
	var muzzle := origin + dir * 0.42
	var exclude := _exclude(o)
	var hits := []
	for pd in WeaponDefs.pellet_dirs(dir, int(d["pellets"]), float(d["spread"]) + Security.AIM_JITTER, rng):
		hits.append(_pellet(w, origin, pd, Security.turret_range(id), int(d["damage"]), exclude, muzzle))
	var fx: Variant = w.get("fx")
	if fx != null:
		fx.muzzle(muzzle)
	for n in d["fire_sound"]:
		if Sfx.available(n):
			Sfx.play(n, muzzle, float(d.get("fire_db", 0.0)))
			break
	var seen := {}
	for h in hits:
		var e: Variant = h.get("collider")
		if str(h.get("kind", "")) == "enemy" and is_instance_valid(e) and not seen.has(e):
			seen[e] = true
			Sfx.play("enemy/hit", h.get("pos", muzzle))
			if e.get("alive") == false:
				Sfx.play("enemy/death", (e as Node3D).global_position)
	Security.noise(game if game != null else w, muzzle, Security.gun_noise(id), "turret")
	turret_fired.emit(o, hits)
	return hits


func _pellet(w: HouseWorld, origin: Vector3, dir: Vector3, rng_m: float, dmg: int, exclude: Array, muzzle: Vector3) -> Dictionary:
	var r: Dictionary = w.shoot(origin, dir, exclude, muzzle, rng_m)
	if str(r.get("kind", "")) == "enemy" and dmg > 1:
		var e: Variant = r.get("collider")
		for i in dmg - 1:
			if is_instance_valid(e) and e.has_method("take_hit") and e.get("alive") != false:
				e.take_hit(dir)
	return r


func _head_pos(o: WorldObject) -> Vector3:
	if o.is_inside_tree():
		return o.global_position + Vector3(0, Security.TURRET_HEIGHT, 0)
	return Vector3(o.pos.x, Security.TURRET_HEIGHT, o.pos.y)


func _exclude(o: WorldObject) -> Array:
	return [o.body.get_rid()] if o.body != null and is_instance_valid(o.body) else []


## Reload progress 0..1 of a turret's auto-loader (0 = not reloading).
func reload_left(o: WorldObject) -> float:
	return maxf(float(_runtime(o)["reload"]), 0.0)


func is_awake(o: WorldObject) -> bool:
	return time <= float(_runtime(o)["awake"])


# --- interaction and the panel ---------------------------------------------------------------

## E on a sensor or turret: a hand reload when the turret needs one, else the panel.
func interact(o: WorldObject) -> void:
	if o == null or not is_instance_valid(o):
		return
	if o.kind == "turret_mount" and Security.needs_hand_reload(o):
		_toast(act_reload(o), "info")
		return
	open_object(o)


func open_object(o: WorldObject) -> void:
	if panel == null or _busy:
		return
	if game != null:
		if str(game.get("_modal")) != "" or bool(game.state.dead):
			return
		if game.build != null and game.build.active and game.has_method("_set_build"):
			game._set_build(false)
		game._set_modal("security", true)
	panel.open(self, o)


func close_panel() -> void:
	if panel != null and panel.is_open:
		panel.close_and_emit()


func _on_panel_closed() -> void:
	if game != null and str(game.get("_modal")) == "security":
		game._set_modal("", false)


func _state() -> GameState:
	return game.state if game != null else null


func _supply() -> Object:
	var b: Variant = game.get("build") if game != null else null
	return b.supply if b is Object and is_instance_valid(b) and b.get("supply") != null else null


func _threats() -> bool:
	return game != null and game.has_method("_threats") and bool(game._threats())


## Panel actions (each returns the line the panel shows).

func act_install(o: WorldObject, id: String, s: GameState = null) -> String:
	var st := s if s != null else _state()
	var why := Security.install_reason(st, o, id)
	if why == "" and _threats():
		why = "Not with them out there: mounting a gun takes a while."
	if why != "":
		return why
	why = Security.install_gun(st, o, id)
	if why != "":
		return why
	SecurityObjects.sync_gun(o)
	Sfx.play_first(["build/upgrade"], o.global_position if o.is_inside_tree() else null)
	_spend_time(Security.GUN_MINUTES, "Mounting the %s…" % WeaponDefs.name_of(id).to_lower())
	return "%s mounted (%d in the magazine). Fill its ammo box and switch it on." % [WeaponDefs.name_of(id), Security.mag(o)]


func act_remove(o: WorldObject, s: GameState = null) -> String:
	var st := s if s != null else _state()
	var r := Security.remove_gun(st, o)
	if r["ok"]:
		SecurityObjects.sync_gun(o)
		Sfx.ui("ui/click")
	return str(r["text"])


func act_fill(o: WorldObject, n: int, s: GameState = null) -> String:
	var st := s if s != null else _state()
	var a := Security.ammo_type(o)
	if a == "":
		return "Install a gun first: the box takes its ammunition."
	if Security.box_total(o) >= Security.BOX_CAP:
		return "The ammo box is full (%d)." % Security.BOX_CAP
	var k := Security.fill_box(st, _supply(), o, n)
	if k <= 0:
		return "You have no %s (carried or stored)." % Items.name_of(a).to_lower()
	Sfx.ui("ui/click")
	return "Put %d %s in the ammo box (%d in it)." % [k, Items.name_of(a).to_lower(), Security.box(o)]


func act_take(o: WorldObject, s: GameState = null) -> String:
	var st := s if s != null else _state()
	var got := Security.empty_box(st, o)
	if got.is_empty():
		return "The ammo box is empty."
	Sfx.ui("ui/click")
	return "Took %s out of the ammo box." % FurnitureStorage.contents_text(got)


func act_reload(o: WorldObject) -> String:
	if Security.gun(o) == "":
		return "No gun on this mount."
	if Security.mag(o) >= WeaponDefs.capacity(Security.gun(o)):
		return "The magazine is full."
	var k := Security.hand_reload(o)
	if k <= 0:
		return "Nothing to load: the ammo box is empty."
	_runtime(o)["empty_said"] = false
	Sfx.play_first(["weapon/reload_done"] + RELOAD_SOUNDS, _head_pos(o))
	return "%s reloaded: %d rounds (%d left in its box)." % [Security.title(o), Security.mag(o), Security.box(o)]


## Flips a switch: "on", "alarm", "hostile" (sensors), "standby" (turrets).
func act_toggle(o: WorldObject, key: String) -> String:
	var c := Security.config(o)
	if not c.has(key) or typeof(c[key]) != TYPE_BOOL:
		return ""
	c[key] = not bool(c[key])
	Sfx.ui("ui/click")
	match key:
		"on":
			return "%s switched %s." % [Security.title(o), "on" if c[key] else "off"]
		"alarm":
			return "Audible alarm: a siren, and anything nearby hears it." if c[key] else "Silent: only you are told."
		"hostile":
			return "Reacts to hostile movement only." if c[key] else "Reacts to any movement it sees."
		"standby":
			return "Waits for a linked sensor before it fires." if c[key] else "Always watching its arc."
	return ""


## Links sensor `o` to the next turret (nearest first; then none).
func act_link_next(o: WorldObject) -> String:
	var c := Security.config(o)
	var ts := objects("turret_mount")
	ts.sort_custom(func(a, b): return a.pos.distance_to(o.pos) < b.pos.distance_to(o.pos))
	var ids := [""]
	for t in ts:
		ids.append(t.uid)
	var i := ids.find(str(c["link"]))
	c["link"] = ids[(i + 1) % ids.size()] if i >= 0 else (ids[1] if ids.size() > 1 else "")
	Sfx.ui("ui/click")
	var t := turret_by_uid(str(c["link"]))
	return "Linked to %s." % Security.title(t) if t != null else "Not linked to a turret."


func act_link_nearest(o: WorldObject) -> String:
	var c := Security.config(o)
	var best: WorldObject = null
	for t in objects("turret_mount"):
		if best == null or t.pos.distance_to(o.pos) < best.pos.distance_to(o.pos):
			best = t
	c["link"] = best.uid if best != null else ""
	Sfx.ui("ui/click")
	return "Linked to %s." % Security.title(best) if best != null else "There is no turret to link."


## Turns a mount (or a sensor's eye) a quarter turn clockwise.
func act_turn(o: WorldObject) -> String:
	o.rot = (o.rot + 1) % 4
	var pv := o.get_node_or_null("Pivot") as Node3D
	if pv != null:
		pv.rotation.y = WorldObject.YAW[o.rot]
	_runtime(o)["yaw"] = 0.0
	SecurityObjects.set_head_yaw(o, 0.0)
	Sfx.ui("ui/click")
	return "Now facing %s." % {"N": "north", "E": "east", "S": "south", "W": "west"}[o.facing()]


func act_upgrade(o: WorldObject, s: GameState = null) -> String:
	var st := s if s != null else _state()
	var sup := _supply()
	var can := func(cost: Dictionary) -> bool:
		if sup != null and sup.has_method("can_pay"):
			return bool(sup.call("can_pay", cost))
		return st == null or st.can_pay(cost)
	var why := Security.upgrade_reason(st, o, can)
	if why == "" and _threats():
		why = "Not with them out there: fitting the auto-loader takes the better part of an hour."
	if why != "":
		return why
	var paid: bool = sup.call("pay", Security.AUTO_COST) if sup != null and sup.has_method("pay") else (st == null or st.pay(Security.AUTO_COST))
	if not paid:
		return "Needs %s." % BuildPieces.cost_text(Security.AUTO_COST)
	Security.config(o)["auto"] = true
	Sfx.play_first(["build/upgrade"], o.global_position if o.is_inside_tree() else null)
	_spend_time(Security.AUTO_MINUTES, "Fitting the auto-loader…")
	return "Auto-loader fitted: it reloads from the ammo box by itself."


## Spends game minutes with a short fade (like the car repair); the panel closes.
func _spend_time(minutes: float, text: String) -> void:
	if game == null or not game.has_method("_advance_clock"):
		return
	_busy = true
	close_panel()
	var fade: Variant = game.ui.fade if game.get("ui") != null else null
	var ft: float = float(game.get("fade_time")) if game.get("fade_time") != null else 0.0
	if fade != null and game.is_inside_tree() and ft > 0.0:
		await fade.fade_to(1.0, ft)
		fade.set_text(text)
	game._advance_clock(minutes)
	game.state.changed.emit()
	if fade != null and game.is_inside_tree() and ft > 0.0:
		fade.set_text("Day %d · %s" % [game.state.day(), game.state.clock_text()])
		await fade.fade_to(0.0, ft)
		fade.set_text("")
	_busy = false


func _toast(text: String, kind := "info") -> void:
	last_text = text
	if game != null and game.has_method("toast"):
		game.toast(text, kind)


# --- F10 "Security" -------------------------------------------------------------------------

func dev_give_components() -> String:
	var s := _state()
	var got := {}
	for k in {"electronics": 12, "scrap": 10, "iron": 8}:
		var n: int = s.inventory.add(k, {"electronics": 12, "scrap": 10, "iron": 8}[k])
		if n > 0:
			got[k] = n
	return "Added %s." % BuildPieces.cost_text(got) if not got.is_empty() else "No room for more."


func dev_unlock() -> String:
	var got := Research.learn_with_prerequisites(game.state, "automation")
	return "Learned: %s." % ", ".join(got.map(func(id): return Research.name_of(id))) if not got.is_empty() else "Both security skills are known."


func _player_world() -> HouseWorld:
	var l: Variant = game.get("levels")
	if l is Object and is_instance_valid(l) and l.has_method("active_world"):
		return l.active_world()
	return game.world


## The quarter turn the player faces (0..3 = N, E, S, W).
func _player_rot() -> int:
	var rig: Variant = player.get("rig") if player != null else null
	var f := Vector3.FORWARD
	if rig is Node3D and (rig as Node3D).is_inside_tree():
		f = -(rig as Node3D).global_transform.basis.z
	if absf(f.x) > absf(f.z):
		return 1 if f.x > 0.0 else 3
	return 2 if f.z > 0.0 else 0


## A free spot for `kind` near the player (lot, walls, objects, furniture, bodies).
func free_spot(w: HouseWorld, kind: String, at: Vector2, r: int) -> Vector2:
	for ring in range(1, 14):
		var dist := ring * 0.5
		var steps := maxi(8, ring * 6)
		for k in steps:
			var a := k * TAU / steps
			var p := at + Vector2(cos(a), sin(a)) * dist
			var s: Vector3 = WorldObject.DEFS[kind]["size"]
			var lo := ((p - Vector2(s.x, s.z) * 0.5) / 0.5).round() * 0.5
			var pos := lo + Vector2(s.x, s.z) * 0.5
			var fp := WorldObject.footprint_of(kind, pos, r)
			if not HouseWorld.LOT.encloses(fp):
				continue
			if w.design.any_struct_in(fp.position, fp.end, VoxelHouse.NAV_ROW_LO, VoxelHouse.NAV_ROW_HI) \
					or w.grid.any_struct_in(fp.position, fp.end, VoxelHouse.NAV_ROW_LO, VoxelHouse.NAV_ROW_HI):
				continue
			if not w.objects_in(fp.grow(0.1)).is_empty() or w.furniture_in(fp) or w.bodies_in(fp.grow(0.1)):
				continue
			return pos
	return Vector2.INF


func dev_place_sensor() -> String:
	var w := _player_world()
	var r := _player_rot()
	var p := free_spot(w, "motion_sensor", game.player.plan_pos(), r)
	if p == Vector2.INF:
		return "No room for a sensor here."
	var o := w.place_object("motion_sensor", p, r, true)
	return "%s placed, facing %s." % [Security.title(o), o.facing()]


func dev_place_turret() -> String:
	var w := _player_world()
	var r := _player_rot()
	var p := free_spot(w, "turret_mount", game.player.plan_pos(), r)
	if p == Vector2.INF:
		return "No room for a turret here."
	var o := w.place_object("turret_mount", p, r, true)
	var c := Security.config(o)
	c["gun"] = "handgun"
	c["mag"] = WeaponDefs.capacity("handgun")
	o.items["ammo"] = 20
	SecurityObjects.sync_gun(o)
	return "%s placed facing %s: a handgun (full) and 20 rounds in its box." % [Security.title(o), o.facing()]


func _nearest(kind: String) -> WorldObject:
	var best: WorldObject = null
	var pp: Vector2 = game.player.plan_pos()
	for o in objects(kind):
		if best == null or o.pos.distance_to(pp) < best.pos.distance_to(pp):
			best = o
	return best


## 30 rounds and 10 shells to Eli; the nearest turret's box topped up with its ammunition.
func dev_supply_ammo() -> String:
	var s := _state()
	s.inventory.add("ammo", 30)
	s.inventory.add("shells", 10)
	var t := _nearest("turret_mount")
	var text := "Added 30 rounds and 10 shells."
	if t != null and Security.gun(t) != "":
		var a := Security.ammo_type(t)
		var k := Security.BOX_CAP - Security.box_total(t)
		if k > 0:
			t.items[a] = Security.box(t, a) + k
		text += " %s: box %d." % [Security.title(t), Security.box(t)]
	return text


func dev_trigger_nearest() -> String:
	var o := _nearest("motion_sensor")
	if o == null:
		return "No sensor."
	trigger(o, null)
	return "Triggered %s." % Security.title(o)


## The fuse box back (repaired, or a new one where the house's was) and the mains on.
func dev_restore_power() -> String:
	var w: HouseWorld = game.world
	var fb := w.fuse_box()
	if fb == null:
		fb = w.place_object("fuse_box", HouseWorld.FUSE_BOX_AT, HouseWorld.FUSE_BOX_ROT, false)
	fb.restore()
	if not fb.mains_on:
		w.toggle_mains(fb)
	w.power_changed.emit()
	return "Power restored: the fuse box is whole and the mains are on."


func dev_info() -> String:
	var lines := PackedStringArray()
	lines.append("Power %s · triggers %d · turret shots %d" % ["on" if powered() else "OFF", triggers, shots])
	for o in objects():
		var c := Security.config(o)
		if o.kind == "motion_sensor":
			var t := turret_by_uid(str(c["link"]))
			lines.append("%s: %s, %s, %s%s · HP %d/%d" % [Security.title(o), "on" if c["on"] else "off", "alarm" if c["alarm"] else "silent",
				"hostile only" if c["hostile"] else "any movement", (" → " + Security.title(t)) if t != null else "", o.hp, o.max_hp])
		else:
			var id := Security.gun(o)
			lines.append("%s: %s, %s %d/%d, box %d, %s%s · HP %d/%d" % [Security.title(o), "on" if c["on"] else "off",
				WeaponDefs.name_of(id).to_lower() if id != "" else "no gun", Security.mag(o), WeaponDefs.capacity(id), Security.box(o),
				"auto-loader" if c["auto"] else "hand reload", ", standby" if c["standby"] else "", o.hp, o.max_hp])
	var off := Security.offscreen_strength(worlds())
	lines.append("Offscreen: %d turrets, %d rounds, %d sensors, score %.2f" % [off["turrets"], off["ammo"], off["sensors"], off["score"]])
	return "\n".join(lines)
