class_name Security
extends RefCounted
## Exp 007 (S): electronic security, the rules (SPEC-007 §4, the user's
## §15-19). Two WorldObject kinds, built in the menu's Fortifications
## (BuildPieces "cat": "defense") and gated by the electronics research line
## (Research: Basic electronics -> Automated defences):
##
##   motion_sensor  a sensor head on a post. Its eye faces the object's `rot`
##                  and sees hostile movement in a SENSOR_ARC cone up to
##                  SENSOR_RANGE m, never through walls or closed doors.
##                  Needs mains power. o.sec:
##                    "name"     where it stands ("at the back door"; set once)
##                    "on"       enabled
##                    "alarm"    true = audible alarm (a noise event), false = silent
##                    "hostile"  true = hostile movement only
##                    "link"     uid of the turret it wakes ("" = none)
##   turret_mount   a powered mount that takes one of Eli's firearms. Any
##                  WeaponDefs weapon fits through the same data (ammo,
##                  capacity, interval, reload, range, pellets, spread).
##                  o.sec:
##                    "name", "on"
##                    "gun"      WeaponDefs id installed ("" = none)
##                    "mag"      rounds in that gun's magazine
##                    "auto"     the auto-loader upgrade is fitted
##                    "standby"  fires only while a linked sensor has woken it
##                  The ammo box is o.items (item -> count, BOX_CAP rounds).
##                  When the mount goes (destroyed or demolished) HouseWorld
##                  calls spill(): the gun and its magazine join the box in
##                  the "Pile of belongings" it drops. Nothing vanishes and
##                  nothing is duplicated: installing takes the gun out of the
##                  inventory with its magazine, removing gives both back.
##
## Reloading: a basic mount fires only what is in the gun's magazine; then
## Eli reloads it by hand from its ammo box (E). With the auto-loader it
## reloads itself from the box with the weapon's own reload (magazine: all
## at once; shells: one at a time), RELOAD_SCALE x slower than Eli.
## The runtime (SecuritySystem) ticks sensors 4x a second and turrets every
## physics frame (targeting 5x a second, only with an enemy within range).

const KINDS := ["motion_sensor", "turret_mount"]

const SENSOR_RANGE := 7.0
const SENSOR_ARC := 110.0              ## full cone, degrees
const SENSOR_HEIGHT := 1.85            ## the eye above the object's floor
const SENSOR_COOLDOWN := 8.0           ## s between two notifications of one sensor
const ALARM_NOISE := 3.5               ## Noise level of an audible alarm

const TURRET_ARC := 120.0              ## full firing arc, degrees, around its facing
const TURRET_RANGE_CAP := 20.0         ## the mount's sights: min(weapon range, this)
const TURRET_HEIGHT := 1.05            ## the gun's pivot above the object's floor
const TURN_SPEED := 2.6                ## rad/s
const AIM_TOLERANCE := 0.09            ## rad: fires once the head points this close
const AIM_JITTER := 2.5                ## degrees added to the weapon's spread
const INTERVAL_SCALE := 1.5            ## a mount fires this much slower than Eli
const RELOAD_SCALE := 1.5              ## the auto-loader reloads this much slower than Eli
const WAKE_TIME := 25.0                ## s a sensor keeps a standby turret awake
const BOX_CAP := 60                    ## rounds in a turret's ammo box
const CHEST := 1.0                     ## aim height on an enemy
## Noise levels of the guns (WeaponDefs "noise" wins when it exists).
const GUN_NOISE := {"handgun": 4.0, "shotgun": 5.0}

const AUTO_COST := {"electronics": 3, "iron": 2, "scrap": 2}
const AUTO_MINUTES := 45.0             ## game minutes to fit the auto-loader
const GUN_MINUTES := 8.0               ## game minutes to mount or change a gun

const SENSOR_DEFAULTS := {"name": "", "on": true, "alarm": true, "hostile": true, "link": ""}
const TURRET_DEFAULTS := {"name": "", "on": true, "gun": "", "mag": 0, "auto": false, "standby": false}

static var _see := PackedByteArray()
static var _noise: Variant = null       ## the Noise script when it exists, false when not


static func is_kind(k) -> bool:
	return typeof(k) in [TYPE_STRING, TYPE_STRING_NAME] and str(k) in KINDS


static func is_sensor(o) -> bool:
	return o is WorldObject and is_instance_valid(o) and (o as WorldObject).kind == "motion_sensor"


static func is_turret(o) -> bool:
	return o is WorldObject and is_instance_valid(o) and (o as WorldObject).kind == "turret_mount"


# --- configuration -----------------------------------------------------------------------

static func defaults(kind: String) -> Dictionary:
	return (SENSOR_DEFAULTS if kind == "motion_sensor" else TURRET_DEFAULTS).duplicate()


## A configuration from untrusted (saved) data: known keys, right types.
static func clean(kind: String, v: Variant) -> Dictionary:
	var out := defaults(kind)
	if typeof(v) != TYPE_DICTIONARY:
		return out
	for k in out:
		if not (v as Dictionary).has(k):
			continue
		var x: Variant = v[k]
		match typeof(out[k]):
			TYPE_BOOL:
				if typeof(x) == TYPE_BOOL:
					out[k] = x
			TYPE_STRING:
				if typeof(x) == TYPE_STRING and (x as String).length() <= 48:
					out[k] = x
			TYPE_INT:
				if typeof(x) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(x)):
					out[k] = clampi(int(x), 0, 999)
	if kind == "turret_mount":
		if not WeaponDefs.has(out["gun"]):
			out["gun"] = ""
		out["mag"] = clampi(int(out["mag"]), 0, WeaponDefs.capacity(out["gun"])) if out["gun"] != "" else 0
	return out


## The object's live configuration (defaults filled in, a name given once).
static func config(o: WorldObject) -> Dictionary:
	if o.sec.is_empty() or not o.sec.has("on"):
		var d := defaults(o.kind)
		for k in o.sec:
			d[k] = o.sec[k]
		o.sec = d
	if str(o.sec.get("name", "")) == "":
		o.sec["name"] = place_name(o)
	return o.sec


## "Sensor at the back door", "Turret in the front yard".
static func title(o: WorldObject) -> String:
	return "%s %s" % ["Sensor" if o.kind == "motion_sensor" else "Turret", str(config(o)["name"])]


## Where `o` stands, in words: by a door, in a room, or which side of the house.
static func place_name(o: WorldObject) -> String:
	var p := o.pos
	var storey := 0
	if o.world != null and o.world.get("storey") != null:
		storey = int(o.world.get("storey"))
	var pre := "" if storey == 0 else ("upstairs, " if storey > 0 else "in the basement, ")
	if storey < 0:
		return pre.trim_suffix(", ")
	for d in [["front door", Vector2(4.5, 9.0)], ["back door", Vector2(14.0, 6.5)]]:
		if p.distance_to(d[1]) <= 2.6:
			return pre + "at the " + str(d[0])
	if HousePlan.FOOTPRINT.has_point(p):
		var r := HousePlan.room_at(p)
		return pre + ("in the %s" % str(r["name"]).to_lower() if not r.is_empty() else "in the house")
	if p.y > HousePlan.FOOTPRINT.end.y:
		return pre + "in the front yard"
	if p.y < HousePlan.FOOTPRINT.position.y:
		return pre + "behind the house"
	return pre + ("on the east side" if p.x > HousePlan.FOOTPRINT.end.x else "on the west side")


# --- guns and ammunition -------------------------------------------------------------------

static func gun(o: WorldObject) -> String:
	return str(config(o)["gun"])


static func mag(o: WorldObject) -> int:
	return int(config(o)["mag"])


## The ammunition item the installed gun takes ("" without a gun).
static func ammo_type(o: WorldObject) -> String:
	return WeaponDefs.ammo_of(gun(o))


## Rounds of `ammo` in the ammo box (the installed gun's by default).
static func box(o: WorldObject, ammo := "") -> int:
	var a := ammo if ammo != "" else ammo_type(o)
	return int(o.items.get(a, 0)) if a != "" else 0


static func box_total(o: WorldObject) -> int:
	var n := 0
	for k in o.items:
		n += int(o.items[k])
	return n


## The weapons Eli carries that fit a mount (every WeaponDefs weapon does).
static func guns_carried(state: GameState) -> Array:
	var out := []
	for id in WeaponDefs.ids():
		if state != null and state.inventory.count(id) > 0:
			out.append(id)
	return out


## Why `id` can't be installed now ("" = it can).
static func install_reason(state: GameState, o: WorldObject, id: String) -> String:
	if not WeaponDefs.has(id):
		return "That doesn't fit a turret mount."
	if gun(o) != "":
		return "Take the %s off the mount first." % WeaponDefs.name_of(gun(o)).to_lower()
	if state == null or state.inventory.count(id) <= 0:
		return "You don't carry a %s." % WeaponDefs.name_of(id).to_lower()
	if state.dead:
		return "You're dead."
	return ""


## Moves `id` from Eli's inventory onto the mount with its magazine (it leaves
## the equipment slots and the quick bar). Returns "" or the reason.
static func install_gun(state: GameState, o: WorldObject, id: String) -> String:
	var why := install_reason(state, o, id)
	if why != "":
		return why
	var rounds := state.magazine(id)
	if not state.inventory.remove(id, 1):
		return "You don't carry a %s." % WeaponDefs.name_of(id).to_lower()
	_off_bar(state, id)
	var c := config(o)
	c["gun"] = id
	c["mag"] = clampi(rounds, 0, WeaponDefs.capacity(id))
	state.changed.emit()
	return ""


## Takes the gun off the mount: back into the inventory with its magazine,
## or, when Eli already carries one, into a pile at the mount's foot.
## Returns {"ok", "text", "pile"}.
static func remove_gun(state: GameState, o: WorldObject) -> Dictionary:
	var id := gun(o)
	if id == "":
		return {"ok": false, "text": "No gun on this mount.", "pile": false}
	var c := config(o)
	var rounds := int(c["mag"])
	c["gun"] = ""
	c["mag"] = 0
	if state != null and state.inventory.add(id, 1) > 0:
		state.set_magazine(id, rounds)
		return {"ok": true, "text": "%s taken off the mount (%d in the magazine)." % [WeaponDefs.name_of(id), rounds], "pile": false}
	var drop := {id: 1}
	if rounds > 0:
		drop[WeaponDefs.ammo_of(id)] = rounds
	if o.world != null and o.world.has_method("drop_loot"):
		o.world.drop_loot(o.pos + WorldObject.front_dir(o.rot + 2) * 0.7, drop)
	return {"ok": true, "text": "You already carry a %s: this one goes on the ground behind the mount." % WeaponDefs.name_of(id).to_lower(), "pile": true}


## The quick bar forgets the gun (so it comes back to the bar when it returns).
static func _off_bar(state: GameState, id: String) -> void:
	var bar = state.get("hotbar")
	if typeof(bar) != TYPE_DICTIONARY or not bar.has("slots"):
		return
	var slots: Array = bar["slots"]
	for i in slots.size():
		if str(slots[i]) == id:
			slots[i] = ""
	if bar.get("known") is Array:
		(bar["known"] as Array).erase(id)


## Puts up to `n` rounds of the installed gun's ammunition into the box: from
## what Eli carries, then (with a house supply) from storage. Returns how many.
static func fill_box(state: GameState, supply: Object, o: WorldObject, n: int) -> int:
	var a := ammo_type(o)
	if a == "" or state == null:
		return 0
	var k := mini(n, BOX_CAP - box_total(o))
	var have := int(supply.call("available", a)) if supply != null and supply.has_method("available") else state.inventory.count(a)
	k = mini(k, have)
	if k <= 0:
		return 0
	var paid: bool = supply.call("pay", {a: k}) if supply != null and supply.has_method("pay") else state.pay({a: k})
	if not paid:
		return 0
	o.items[a] = box(o, a) + k
	return k


## Empties the ammo box into the inventory (rounds have no cap). Returns what moved.
static func empty_box(state: GameState, o: WorldObject) -> Dictionary:
	var got := {}
	if state == null:
		return got
	for id in o.items.keys():
		var k := state.inventory.add(id, int(o.items[id]))
		if k > 0:
			got[id] = k
			o.items[id] = int(o.items[id]) - k
			if int(o.items[id]) <= 0:
				o.items.erase(id)
	return got


## Fills the magazine from the box (by hand). Returns the rounds loaded.
static func hand_reload(o: WorldObject) -> int:
	return _load(o, -1)


## One auto-loader step: the whole magazine (a "magazine" gun) or one shell.
static func auto_step(o: WorldObject) -> int:
	var d := WeaponDefs.get_def(gun(o))
	return _load(o, 1 if str(d.get("reload", "magazine")) == "shell" else -1)


static func _load(o: WorldObject, n: int) -> int:
	var id := gun(o)
	if id == "":
		return 0
	var c := config(o)
	var room := WeaponDefs.capacity(id) - int(c["mag"])
	var k := mini(room if n < 0 else mini(n, room), box(o))
	if k <= 0:
		return 0
	c["mag"] = int(c["mag"]) + k
	var a := ammo_type(o)
	o.items[a] = box(o, a) - k
	if int(o.items[a]) <= 0:
		o.items.erase(a)
	return k


## True when Eli has to reload this turret by hand (no auto-loader, an empty
## magazine, rounds in the box).
static func needs_hand_reload(o: WorldObject) -> bool:
	return gun(o) != "" and mag(o) <= 0 and box(o) > 0 and not bool(config(o)["auto"])


## Spends one round from the magazine (a shot). False when it is empty.
static func spend(o: WorldObject) -> bool:
	var c := config(o)
	if str(c["gun"]) == "" or int(c["mag"]) <= 0:
		return false
	c["mag"] = int(c["mag"]) - 1
	return true


## The mount's effective range with the installed gun.
static func turret_range(id: String) -> float:
	return minf(float(WeaponDefs.get_def(id).get("range", 0.0)), TURRET_RANGE_CAP) if WeaponDefs.has(id) else 0.0


## The gun's noise level for Noise.emit.
static func gun_noise(id: String) -> float:
	return float(WeaponDefs.get_def(id).get("noise", GUN_NOISE.get(id, 4.0)))


## HouseWorld.remove_object (destroyed or demolished): the gun and its
## magazine join the ammo box, which drops into a pile with them.
static func spill(o: WorldObject) -> void:
	if o.kind != "turret_mount" or o.sec.is_empty():
		return
	var id := str(o.sec.get("gun", ""))
	if not WeaponDefs.has(id):
		return
	o.items[id] = int(o.items.get(id, 0)) + 1
	var rounds := int(o.sec.get("mag", 0))
	if rounds > 0:
		var a := WeaponDefs.ammo_of(id)
		o.items[a] = int(o.items.get(a, 0)) + rounds
	o.sec["gun"] = ""
	o.sec["mag"] = 0


## Why the auto-loader can't be fitted ("" = it can). `can_pay` checks a cost.
static func upgrade_reason(state: GameState, o: WorldObject, can_pay: Callable) -> String:
	if bool(config(o)["auto"]):
		return "The auto-loader is already fitted."
	if state != null and not Research.knows(state, "automation"):
		return Research.skill_reason(state, "automation")
	if can_pay.is_valid() and not bool(can_pay.call(AUTO_COST)):
		return "Needs %s." % BuildPieces.cost_text(AUTO_COST)
	return ""


# --- geometry ------------------------------------------------------------------------------

## True when plan point `p` lies in `o`'s cone of full angle `arc` degrees.
static func in_arc(o: WorldObject, p: Vector2, arc: float) -> bool:
	var to := p - o.pos
	if to.length() < 0.3:
		return true
	return absf(WorldObject.front_dir(o.rot).angle_to(to)) <= deg_to_rad(arc) * 0.5


## The head yaw (relative to the object's facing) that points along `d`.
static func local_yaw(o: WorldObject, d: Vector3) -> float:
	return wrapf(atan2(-d.x, -d.z) - WorldObject.YAW[o.rot], -PI, PI)


## Voxels a sensor or a gun sight sees through: what bullets pass, and glass.
static func see_through() -> PackedByteArray:
	if _see.is_empty():
		var a := PackedByteArray()
		a.resize(256)
		for i in mini(256, VoxelMat.FLAGS.size()):
			a[i] = 1 if (VoxelMat.FLAGS[i] & VoxelMat.F_PASS) != 0 or i == VoxelMat.GLASS else 0
		_see = a
	return _see


## True when nothing solid lies between `from` and `to` in `world`: no
## voxels (walls, roofs, floors; glass doesn't count) and no bodies on layer 1
## (closed doors, boards, tall furniture, other mounts). `exclude` = RIDs.
static func clear_line(world: Node, from: Vector3, to: Vector3, exclude: Array = []) -> bool:
	var d := to - from
	var dist := d.length()
	if dist < 0.05 or world == null:
		return true
	d /= dist
	var g: VoxelGrid = world.get("grid")
	if g != null:
		var vh := g.raycast(from, d, dist, see_through())
		if not vh.is_empty() and float(vh["dist"]) < dist - 0.35:
			return false
	if not world.is_inside_tree():
		return true
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	q.exclude = exclude
	var hit := (world as Node3D).get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or from.distance_to(hit["position"]) >= dist - 0.35


## True when `eli` (Eli's chest) is within the line of fire from `from` to `to`.
static func blocks_eli(from: Vector3, to: Vector3, eli: Vector3) -> bool:
	var d := to - from
	var l2 := d.length_squared()
	if l2 < 1e-4:
		return false
	var t := (eli - from).dot(d) / l2
	if t < 0.0 or t > 1.05:
		return false
	return (from + d * t).distance_to(eli) < 0.75


## Hostility: a living, non-retreating enemy (and, when an enemy says whether
## it is hostile, a hostile one). `hostile_only` false: any living enemy.
static func is_target(e: Variant, hostile_only := true) -> bool:
	if not is_instance_valid(e) or not (e is VoxelEnemy) or not bool(e.get("alive")):
		return false
	if not hostile_only:
		return true
	if (e as Node).has_meta("retreat"):
		return false
	if (e as Object).has_method("is_hostile"):
		return bool(e.call("is_hostile"))
	var h: Variant = (e as Object).get("hostile")
	return h == null or bool(h)


static func storey_of(n: Object) -> int:
	var s: Variant = n.get("storey") if n != null else null
	return int(s) if typeof(s) in [TYPE_INT, TYPE_FLOAT] else 0


# --- power and noise -------------------------------------------------------------------------

## Mains power of a world without the game (its fuse box; none = no power).
static func world_power(world: Node) -> bool:
	if world == null or not world.has_method("fuse_box"):
		return true
	var fb: Variant = world.call("fuse_box")
	return fb != null and is_instance_valid(fb) and bool(fb.get("mains_on"))


## Noise.emit when agent N's class exists (SPEC-007 §3); nothing otherwise.
static func noise(src: Object, pos: Vector3, level: float, source: String) -> void:
	if _noise == null:
		_noise = false
		for c in ProjectSettings.get_global_class_list():
			if str(c.get("class", "")) == "Noise":
				var s: Variant = load(str(c.get("path", "")))
				if s is Script:
					for m in (s as Script).get_script_method_list():
						if str(m.get("name", "")) == "emit":
							_noise = s
				break
	if _noise is Script:
		(_noise as Script).call("emit", src, pos, level, source)


# --- offscreen defence (SPEC-007 §4, for agent T) ----------------------------------------------

## What the security of `world` (a HouseWorld, or an Array of them) is worth
## while Eli is away: {"turrets": working turrets, "ammo": rounds they can
## fire, "sensors": working sensors, "score": about how many attackers the
## turrets stop}. Working = a gun, enabled, the house powered. A basic mount
## counts only its magazine; with the auto-loader also its box.
static func offscreen_strength(world: Variant) -> Dictionary:
	var out := {"turrets": 0, "ammo": 0, "sensors": 0, "score": 0.0}
	for w in _worlds(world):
		if not world_power(_power_world(world, w)):
			continue
		for o in w.objects:
			if not is_instance_valid(o) or o.hp <= 0:
				continue
			if o.kind == "motion_sensor" and bool(config(o)["on"]):
				out["sensors"] += 1
			elif o.kind == "turret_mount" and bool(config(o)["on"]) and gun(o) != "":
				var n := usable_rounds(o)
				if n <= 0:
					continue
				out["turrets"] += 1
				out["ammo"] += n
				var d := WeaponDefs.get_def(gun(o))
				var per_shot := float(d.get("damage", 1)) * minf(float(d.get("pellets", 1)), 3.0)
				out["score"] += n * per_shot * 0.5 / float(Tuning.ENEMY_HP)
	if out["sensors"] > 0 and out["turrets"] > 0:
		out["score"] *= 1.15          # warned turrets waste less
	out["score"] = snappedf(out["score"], 0.01)
	return out


## Rounds a turret can fire without Eli: its magazine, plus the box with the auto-loader.
static func usable_rounds(o: WorldObject) -> int:
	if gun(o) == "":
		return 0
	return mag(o) + (box(o) if bool(config(o)["auto"]) else 0)


## Spends up to `rounds` from the working turrets (offscreen fighting), one at
## a time across them (auto-loaders refill from the box). Returns how many.
static func consume_offscreen(world: Variant, rounds: int) -> int:
	var guns := []
	for w in _worlds(world):
		if not world_power(_power_world(world, w)):
			continue
		for o in w.objects:
			if is_instance_valid(o) and o.kind == "turret_mount" and bool(config(o)["on"]) and usable_rounds(o) > 0:
				guns.append(o)
	var spent := 0
	while spent < rounds and not guns.is_empty():
		for o in guns.duplicate():
			if spent >= rounds:
				break
			if mag(o) <= 0 and bool(config(o)["auto"]):
				hand_reload(o)
			if spend(o):
				spent += 1
			if usable_rounds(o) <= 0:
				guns.erase(o)
	return spent


static func _worlds(world: Variant) -> Array:
	var out := []
	if world is Array:
		for w in world:
			if w is HouseWorld and is_instance_valid(w):
				out.append(w)
	elif world is HouseWorld and is_instance_valid(world):
		out.append(world)
	return out


## The world whose fuse box powers `w` (the first, ground floor, world of a list).
static func _power_world(world: Variant, w: Node) -> Node:
	if world is Array and not (world as Array).is_empty() and (world as Array)[0] is HouseWorld:
		return (world as Array)[0]
	return w
