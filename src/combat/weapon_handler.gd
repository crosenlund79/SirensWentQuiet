class_name WeaponHandler
extends Node
## The weapon runtime (SPEC-003 §2). Owner: K. One per player: fires the weapon
## in hand through HouseWorld.shoot (once per pellet), times shots, reloads and
## switches, and shows the weapon on the rig. The magazines live in
## GameState.weapons (saved), the reserve is the inventory ammo item, the
## numbers are WeaponDefs. The game forwards input; see
## docs/experiment-003/equipment.md ("Integration").
##
##   setup(state, world, player)
##   try_fire(aim_point) -> {"ok", "id", "reason", "pellets", "hits", "reloading"}
##   reload() -> ""|reason     switch_to(id) / select_slot(slot) / next()
##   current() -> {id, name, loaded, capacity, reserve, ammo, ammo_name, reloading,
##                 reload_progress, mode, slot, unlimited}
##
## `world` is duck-typed (shoot, fx, aim_ray), `player` too (rig, get_rid,
## on_fired), so tests can pass light stand-ins.

signal fired(id: String, hits: Array)
signal empty(id: String)
signal reload_started(id: String)
signal reloaded(id: String)
signal reload_interrupted(id: String)
signal switched(id: String)

const SWITCH_DELAY := 0.3         ## s after a switch before the new weapon fires
const DRY_INTERVAL := 0.45        ## s between dry clicks (and `empty` signals)
const MODEL_NAME := "WeaponModel"

var state: GameState
var world: Node
var player: Node3D
var auto_tick := true             ## _physics_process advances the timers; tests call tick()
var auto_reload := true           ## pulling the trigger on an empty magazine starts a reload
var rng := RandomNumberGenerator.new()
var shots := 0                    ## trigger pulls that fired
var last := {}                    ## the last try_fire result

var _cooldown := 0.0
var _dry_cd := 0.0
var _reload_id := ""
var _reload_t := 0.0
var _shown := "-"                 ## weapon whose look is on the rig ("-" = none applied yet)
var _range_arg := -1              ## does world.shoot take a 5th (range) argument? -1 = not checked


func setup(s: GameState, w: Node, p: Node3D) -> void:
	state = s
	world = w
	player = p
	_reload_id = ""
	_reload_t = 0.0
	_cooldown = 0.0
	_dry_cd = 0.0
	_range_arg = -1
	_shown = "-"
	_apply_visual()


func _physics_process(delta: float) -> void:
	if auto_tick:
		tick(delta)


## Advances the shot timer, the reload and the rig visual by `delta` seconds.
func tick(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_dry_cd = maxf(_dry_cd - delta, 0.0)
	if _reload_id != "":
		_advance_reload(delta)
	if state != null and current_id() != _shown:
		_apply_visual()


# --- queries ---------------------------------------------------------------------------

## The weapon in hand ("" = none).
func current_id() -> String:
	return state.active_weapon() if state != null else ""


func current() -> Dictionary:
	var id := current_id()
	var unlimited: bool = state != null and state.cheats.get("unlimited", false)
	if id == "":
		return {"id": "", "name": "", "loaded": 0, "capacity": 0, "reserve": 0, "ammo": "", "ammo_name": "",
			"reloading": false, "reload_progress": 0.0, "mode": "", "slot": "", "unlimited": unlimited}
	var d := WeaponDefs.get_def(id)
	return {
		"id": id, "name": d["name"], "loaded": state.magazine(id), "capacity": int(d["capacity"]),
		"reserve": state.reserve(id), "ammo": d["ammo"], "ammo_name": Items.name_of(d["ammo"]),
		"reloading": is_reloading(), "reload_progress": reload_progress(), "mode": d["reload"],
		"slot": state.slot_of(id), "unlimited": unlimited,
	}


func is_reloading() -> bool:
	return _reload_id != "" and _reload_id == current_id()


## 0..1 through the current reload step (the magazine, or the shell going in).
func reload_progress() -> float:
	if not is_reloading():
		return 0.0
	return clampf(_reload_t / float(WeaponDefs.get_def(_reload_id)["reload_time"]), 0.0, 1.0)


## Seconds until the weapon in hand may fire again (0 = ready).
func cooldown() -> float:
	return _cooldown


# --- firing ----------------------------------------------------------------------------

## One trigger pull at `aim_point` (world space). Returns
## {"ok", "id", "reason": ""|"no_weapon"|"dead"|"reloading"|"cooldown"|"empty",
##  "pellets", "hits": [world.shoot results], "reloading"}.
## A shell-by-shell reload is interrupted when a shell is loaded; a magazine
## reload blocks firing. An empty magazine clicks (throttled), emits `empty`
## and starts a reload when there is a reserve (auto_reload).
func try_fire(aim_point: Vector3) -> Dictionary:
	var id := current_id()
	var res := {"ok": false, "id": id, "reason": "", "pellets": 0, "hits": [], "reloading": false}
	last = res
	if state == null or id == "":
		res["reason"] = "no_weapon"
		return res
	if state.dead:
		res["reason"] = "dead"
		return res
	var d := WeaponDefs.get_def(id)
	if is_reloading():
		if d["reload"] == "shell" and state.magazine(id) > 0:
			_stop_reload(false)
		else:
			res["reason"] = "reloading"
			res["reloading"] = true
			return res
	if _cooldown > 0.0:
		res["reason"] = "cooldown"
		return res
	if not state.spend_round(id):
		res["reason"] = "empty"
		_cooldown = maxf(_cooldown, float(d["interval"]))
		if _dry_cd <= 0.0:
			_dry_cd = DRY_INTERVAL
			_play("dry", _muzzle_global(d))
			empty.emit(id)
		if auto_reload and reload() == "":
			res["reloading"] = true
		return res
	_cooldown = float(d["interval"])
	shots += 1
	var origin := _origin()
	var dir := aim_point - origin
	if Vector2(dir.x, dir.z).length() < 0.3:
		dir = _facing()
		dir.y = -0.3
	dir = dir.normalized()
	var muzzle := _muzzle_global(d)
	var exclude := []
	if player != null and player.has_method("get_rid"):
		exclude.append(player.get_rid())
	var hits := []
	for pd in WeaponDefs.pellet_dirs(dir, int(d["pellets"]), float(d["spread"]), rng):
		hits.append(_pellet(origin, pd, float(d["range"]), int(d["damage"]), exclude, muzzle))
	var fx = world.get("fx") if world != null else null
	if fx != null:
		fx.muzzle(muzzle)
		fx.casing(muzzle - dir * float(d.get("casing_back", 0.15)), _side())
	if player != null and player.has_method("on_fired"):
		player.on_fired()
	_play_first(d["fire_sound"], muzzle, float(d.get("fire_db", 0.0)))
	_enemy_sounds(hits, muzzle)
	res["ok"] = true
	res["pellets"] = hits.size()
	res["hits"] = hits
	fired.emit(id, hits)
	return res


## One pellet. With a range shorter than HouseWorld's own (40 m), the range
## goes to world.shoot as a 5th argument when it takes one; otherwise the
## first hit is probed with world.aim_ray and a pellet whose hit lies beyond
## the range is spent (a short tracer, no damage, `{"kind": "spent"}`).
func _pellet(origin: Vector3, dir: Vector3, rng_m: float, dmg: int, exclude: Array, muzzle: Vector3) -> Dictionary:
	if world == null or not world.has_method("shoot"):
		return {"kind": "none", "pos": origin + dir * rng_m, "collider": null}
	var r: Dictionary
	if rng_m < Tuning.SHOT_RANGE - 0.01:
		if _shoot_takes_range():
			r = world.shoot(origin, dir, exclude, muzzle, rng_m)
		else:
			if world.has_method("aim_ray"):
				var p: Vector3 = world.aim_ray(origin, dir)
				if origin.distance_to(p) > rng_m:
					var end := origin + dir * rng_m
					var fx = world.get("fx")
					if fx != null:
						fx.tracer(muzzle, end)
					return {"kind": "spent", "pos": end, "collider": null}
			r = world.shoot(origin, dir, exclude, muzzle)
	else:
		r = world.shoot(origin, dir, exclude, muzzle)
	if str(r.get("kind", "")) == "enemy" and dmg > 1:
		var e = r.get("collider")
		for i in dmg - 1:
			if is_instance_valid(e) and e.has_method("take_hit") and e.get("alive") != false:
				e.take_hit(dir)
	return r


func _shoot_takes_range() -> bool:
	if _range_arg < 0:
		_range_arg = 1 if world.get_method_argument_count("shoot") >= 5 else 0
	return _range_arg == 1


func _enemy_sounds(hits: Array, muzzle: Vector3) -> void:
	var seen := {}
	for h in hits:
		if str(h.get("kind", "")) != "enemy":
			continue
		var e = h.get("collider")
		if not is_instance_valid(e) or seen.has(e):
			continue
		seen[e] = true
		Sfx.play("enemy/hit", h.get("pos", muzzle))
		if e.get("alive") == false and e is Node3D:
			Sfx.play("enemy/death", (e as Node3D).global_position)


# --- reloading -------------------------------------------------------------------------

## Starts a reload of the weapon in hand. Returns "" or a reason: "No weapon.",
## "You're dead.", "Already reloading.", "Full.", "No <ammo> left.".
func reload() -> String:
	var id := current_id()
	if state == null or id == "":
		return "No weapon."
	if state.dead:
		return "You're dead."
	if is_reloading():
		return "Already reloading."
	if state.magazine(id) >= WeaponDefs.capacity(id):
		return "Full."
	if state.reserve(id) <= 0 and not state.cheats.get("unlimited", false):
		return "No %s left." % Items.name_of(WeaponDefs.ammo_of(id)).to_lower()
	_reload_id = id
	_reload_t = 0.0
	_play("reload_start", _muzzle_global(WeaponDefs.get_def(id)))
	reload_started.emit(id)
	return ""


func _advance_reload(delta: float) -> void:
	var id := _reload_id
	if id != current_id() or state == null or state.dead:
		_stop_reload(false)
		return
	var d := WeaponDefs.get_def(id)
	var step := float(d["reload_time"])
	_reload_t += delta
	if d["reload"] == "magazine":
		if _reload_t >= step:
			state.load_rounds(id)
			_stop_reload(true)
		return
	while _reload_t >= step and _reload_id != "":
		_reload_t -= step
		var k := state.load_rounds(id, 1)
		if k > 0:
			_play("shell", _muzzle_global(d))
		var full := state.magazine(id) >= WeaponDefs.capacity(id)
		var dry := state.reserve(id) <= 0 and not state.cheats.get("unlimited", false)
		if k <= 0 or full or dry:
			_stop_reload(true)


func _stop_reload(done: bool) -> void:
	var id := _reload_id
	_reload_id = ""
	_reload_t = 0.0
	if id == "":
		return
	if done:
		_play("reload_done", _muzzle_global(WeaponDefs.get_def(id)))
		reloaded.emit(id)
	else:
		reload_interrupted.emit(id)


# --- switching -------------------------------------------------------------------------

## Takes the equipped weapon `id` in hand. Returns "" (also when it already is)
## or a reason. Cancels a reload; the new weapon fires after SWITCH_DELAY.
func switch_to(id: String) -> String:
	if state == null:
		return "No weapon."
	if state.dead:
		return "You're dead."
	var slot := state.slot_of(id)
	if not slot in Equipment.WEAPON_SLOTS:
		return "%s isn't equipped." % (WeaponDefs.name_of(id) if WeaponDefs.has(id) else "That")
	if id == current_id():
		return ""
	if _reload_id != "":
		_stop_reload(false)
	state.set_active_weapon_slot(slot)
	_cooldown = maxf(_cooldown, SWITCH_DELAY)
	_apply_visual()
	_play("switch", _muzzle_global(WeaponDefs.get_def(id)))
	switched.emit(id)
	return ""


## Weapon slot keys (1 = primary, 2 = secondary).
func select_slot(slot: String) -> String:
	if state == null or not slot in Equipment.WEAPON_SLOTS:
		return "No weapon."
	var id := state.equipped(slot)
	if id == "":
		return "Nothing in the %s slot." % str(Equipment.SLOT_NAMES[slot]).to_lower()
	return switch_to(id)


## Switches to the other equipped weapon. Returns its id, or "" if there is none.
func next() -> String:
	if state == null:
		return ""
	var cur := state.active_weapon_slot
	for slot in Equipment.WEAPON_SLOTS:
		if slot != cur and state.equipped(slot) != "":
			return state.equipped(slot) if switch_to(state.equipped(slot)) == "" else ""
	return ""


# --- the rig ---------------------------------------------------------------------------

func _rig() -> Node3D:
	return player.get("rig") if player != null else null


func _gun() -> Node3D:
	var rig := _rig()
	return rig.get("gun") if rig != null else null


func _origin() -> Vector3:
	var p := player.global_position if player != null and player.is_inside_tree() else Vector3.ZERO
	return Vector3(p.x, Tuning.MUZZLE_HEIGHT, p.z)


func _facing() -> Vector3:
	var rig := _rig()
	if rig != null and rig.is_inside_tree():
		return -rig.global_transform.basis.z
	return Vector3.FORWARD


func _side() -> Vector3:
	var rig := _rig()
	return rig.global_transform.basis.x if rig != null and rig.is_inside_tree() else Vector3.RIGHT


func _muzzle_global(d: Dictionary) -> Vector3:
	var gun := _gun()
	if gun != null and gun.is_inside_tree() and d.has("muzzle"):
		return gun.global_transform * (d["muzzle"] as Vector3)
	return _origin()


## Shows the weapon in hand on the rig's gun node: the rig's own pistol for the
## handgun, a placeholder model for the shotgun, nothing without a weapon.
func _apply_visual() -> void:
	var gun := _gun()
	if gun == null or gun.get_child_count() == 0:
		return
	var id := current_id()
	var base := gun.get_child(0) as Node3D
	var model := gun.get_node_or_null(MODEL_NAME) as Node3D
	if id == "shotgun" and model == null:
		model = shotgun_model()
		gun.add_child(model)
	if base != null and base != model:
		base.visible = id == "handgun"
	if model != null:
		model.visible = id == "shotgun"
	_shown = id


## The shotgun placeholder in gun-node space (barrel along -Y to the muzzle at
## y -0.8, stock towards the shoulder, pump under the barrel along +Z).
static func shotgun_model() -> Node3D:
	var root := Node3D.new()
	root.name = MODEL_NAME
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.15, 0.155, 0.165)
	metal.roughness = 0.55
	metal.metallic = 0.35
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.36, 0.23, 0.14)
	wood.roughness = 0.8
	for part in [
		[Vector3(0.042, 0.62, 0.042), Vector3(0, -0.49, -0.005), metal],     # barrel
		[Vector3(0.036, 0.5, 0.032), Vector3(0, -0.42, 0.036), metal],       # magazine tube
		[Vector3(0.056, 0.2, 0.07), Vector3(0, -0.36, 0.045), wood],         # pump
		[Vector3(0.055, 0.24, 0.08), Vector3(0, -0.08, 0.01), metal],        # receiver
		[Vector3(0.045, 0.06, 0.1), Vector3(0, 0.0, 0.08), wood],            # grip
		[Vector3(0.05, 0.3, 0.075), Vector3(0, 0.18, 0.04), wood],           # stock
	]:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part[0]
		mi.mesh = box
		mi.position = part[1]
		mi.material_override = part[2]
		root.add_child(mi)
	return root


# --- sound -----------------------------------------------------------------------------

func _play(kind: String, at: Vector3) -> void:
	_play_first(WeaponDefs.SOUNDS[kind], at, float(WeaponDefs.SOUND_DB.get(kind, 0.0)))


## Plays the first name in `names` that Sfx knows (preferred name, then fallbacks).
func _play_first(names: Array, at: Vector3, db := 0.0) -> void:
	for n in names:
		if Sfx.has(n):
			Sfx.play(n, at, db)
			return
