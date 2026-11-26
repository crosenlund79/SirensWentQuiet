class_name Corpse
extends Node3D
## Experiment 012 (E), the user's §14 and §25: a dead psycho's body stays
## and is searchable. When an enemy (AIEnemy with keep_corpse) has collapsed
## and settled (SETTLE s), the game's corpse helper (src/ai/game_corpses.gd)
## turns it into a Corpse: the rig (and a brute's dropped club) moves under
## `visual`, the AIEnemy is freed, and nothing runs any more: no AI, no
## animation, no navigation, no physics, no collision; just a light static
## visual and a loot container.
##
## Its record `data` is the saved dictionary itself (live in
## state.home["corpses"] at home, or in the POI record's "corpses"):
##   pos    [x, y, z]  the feet (where the enemy stood when it died)
##   yaw    the facing it died with (rad)
##   fall   [x, z]     the topple axis (the shot's direction x up)
##   kind, app (the appearance seed), name
##   items  {item: n}  what is left on it (the loot panel takes from this
##                     very dictionary, so an interrupted search keeps the rest)
##   seed   the collapse's random seed (the same pose when rebuilt)
##   searched  true once Eli has looked
## Rebuilt on load in its lying pose (HumanoidRig.collapse at the end).
##
## For agent V: `visual` is the single node to hide while unseen; corpses
## are in the group GROUP. The prompt: "[E] Search Walter Briggs".

const GROUP := "corpses"
const SETTLE := 2.0               ## s after death: the body lies still (a brute's fall takes ~1.6 s)

## Loot tables (existing items only; Items.DEFS). Per kind: the chance of an
## empty body, the number of rolls and [item, weight, min, max] entries.
const LOOT := {
	"psycho": {"empty": 0.3, "rolls": Vector2i(1, 3), "items": [
		["snacks", 3.0, 1, 2], ["canned_food", 1.5, 1, 1], ["water", 2.5, 1, 1], ["nails", 1.5, 3, 8],
		["bandage", 1.0, 1, 1], ["ammo", 0.8, 1, 3], ["scrap", 0.8, 1, 1], ["hammer", 0.25, 1, 1], ["crowbar", 0.12, 1, 1]]},
	"runner": {"empty": 0.35, "rolls": Vector2i(1, 2), "items": [
		["snacks", 2.5, 1, 2], ["water", 2.5, 1, 1], ["bandage", 2.5, 1, 2], ["nails", 1.0, 2, 6],
		["flashlight", 0.3, 1, 1], ["drill", 0.12, 1, 1]]},
	"brute": {"empty": 0.2, "rolls": Vector2i(1, 3), "items": [
		["scrap", 2.5, 1, 3], ["iron", 1.2, 1, 2], ["wood", 2.0, 2, 4], ["nails", 2.0, 5, 12], ["canned_food", 1.0, 1, 1],
		["hammer", 0.7, 1, 1], ["crowbar", 0.5, 1, 1], ["shovel", 0.35, 1, 1], ["vest", 0.2, 1, 1]]},
	"bomber": {"empty": 0.25, "rolls": Vector2i(1, 3), "items": [
		["electronics", 3.0, 1, 3], ["scrap", 2.0, 1, 2], ["nails", 1.5, 4, 10], ["fuel", 0.5, 1, 1],
		["car_battery", 0.12, 1, 1], ["flashlight", 0.2, 1, 1]]},
}
## What a look's person carries more often (HumanoidLooks look "name": the
## person before the bracket): extra weight per item, and some always carry
## something (`sure`: never an empty body). The mechanic carries a tool.
const BIAS := {
	"Mechanic": {"sure": true, "hammer": 2.5, "scrap": 2.0, "nails": 1.5},
	"Labourer": {"sure": true, "hammer": 1.5, "nails": 2.5, "wood": 2.0},
	"Security guard": {"flashlight": 1.5, "ammo": 2.0},
	"Jogger": {"water": 3.0, "snacks": 1.0},
	"Office clerk": {"snacks": 2.0},
	"Shop assistant": {"snacks": 2.0, "canned_food": 1.5},
	"Pensioner in a parka": {"bandage": 1.5, "canned_food": 1.5},
	"Retired man": {"bandage": 1.5, "canned_food": 1.0},
	"Neighbour in a cardigan": {"canned_food": 1.5, "bandage": 1.0},
	"Hooded youth": {"snacks": 2.0},
	"Butcher": {"canned_food": 2.5},
	"Lumberjack": {"sure": true, "wood": 3.0, "shovel": 0.8},
	"Mover": {"wood": 1.5, "nails": 1.5},
	"Bouncer": {"vest": 0.6},
	"Delivery driver": {"fuel": 1.5, "car_battery": 0.3},
}

var data: Dictionary = {}
var items: Dictionary = {}        ## data["items"] (the same dictionary)
var kind := "psycho"
var display_name := ""
var appearance := 0
var visual: Node3D                ## the rig (and its props): one node to hide
var rig: VoxelRig

static var _mats := {}            ## enemy material instance id -> its copy without the x-ray pass


# --- records ------------------------------------------------------------------------------

## The saved record of `e` dying now (before the collapse): items rolled
## with `state` (one-of-a-kind items only when they may exist; null = any).
static func record_for(e: AIEnemy, state: GameState) -> Dictionary:
	var p := e.global_position
	var axis: Variant = e.get("_fall_axis")
	var ax: Vector3 = axis if axis is Vector3 else Vector3.RIGHT
	var seed := hash([e.appearance, e.display_name, snappedf(p.x, 0.01), snappedf(p.z, 0.01), Time.get_ticks_usec()])
	return {"pos": [p.x, p.y, p.z], "yaw": e.rig.rotation.y if e.rig != null else 0.0, "fall": [ax.x, ax.z],
		"kind": e.kind, "app": e.appearance, "name": e.display_name, "items": roll_loot(e.kind, e.appearance, seed, state),
		"seed": posmod(seed, 2147483647), "searched": false}


## Untrusted save data -> a clean record, or {} when it is unusable.
static func clean(v: Variant) -> Dictionary:
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = v
	var pos: Variant = d.get("pos")
	if not (pos is Array) or (pos as Array).size() < 3:
		return {}
	var p := Vector3(_num(pos[0]), _num(pos[1]), _num(pos[2]))
	if not p.is_finite():
		return {}
	var k := str(d.get("kind", "psycho"))
	if not EnemyDefs.has(k):
		k = "psycho"
	var app := int(_num(d.get("app"), 0.0))
	var fall: Variant = d.get("fall")
	var f := Vector2(_num(fall[0]), _num(fall[1])) if fall is Array and (fall as Array).size() >= 2 else Vector2(1.0, 0.0)
	if f.length() < 0.01:
		f = Vector2(1.0, 0.0)
	var n := str(d.get("name", ""))
	return {"pos": [p.x, p.y, p.z], "yaw": _num(d.get("yaw")), "fall": [f.x, f.y], "kind": k, "app": app,
		"name": n if n != "" else HumanNames.for_enemy(k, app), "items": FurnitureStorage.clean(d.get("items", {})),
		"seed": int(_num(d.get("seed"), 0.0)), "searched": d.get("searched", false) == true}


static func _num(v: Variant, fallback := 0.0) -> float:
	return float(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(v)) else fallback


## Looted clean: searched and nothing left (may be cleaned up).
static func is_spent(d: Dictionary) -> bool:
	return bool(d.get("searched", false)) and (d.get("items", {}) as Dictionary).is_empty()


# --- loot ---------------------------------------------------------------------------------

## What a body of `kind` with appearance `app` carries (deterministic for
## `seed`). Not every body has something; the look's person biases it.
static func roll_loot(k: String, app: int, seed: int, state: GameState = null) -> Dictionary:
	var t: Dictionary = LOOT.get(k, LOOT["psycho"])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var who := person_of(k, app)
	var bias: Dictionary = BIAS.get(who, {})
	var out := {}
	if not bias.get("sure", false) and rng.randf() < float(t["empty"]):
		return out
	var entries: Array = []
	var total := 0.0
	for it in t["items"]:
		var w := float(it[1]) + float(bias.get(str(it[0]), 0.0))
		entries.append([str(it[0]), w, int(it[2]), int(it[3])])
		total += w
	for id in bias:                       # a person's own things the archetype's table lacks
		if id != "sure" and Items.has(id) and not entries.any(func(x): return x[0] == id):
			entries.append([str(id), float(bias[id]), 1, 1])
			total += float(bias[id])
	var rolls: Vector2i = t["rolls"]
	for r in rng.randi_range(rolls.x, rolls.y):
		var pick := rng.randf() * total
		for it in entries:
			pick -= float(it[1])
			if pick > 0.0:
				continue
			var id: String = it[0]
			if Items.is_unique(id) and (out.has(id) or not may_carry(state, id)):
				break
			out[id] = int(out.get(id, 0)) + rng.randi_range(int(it[2]), int(it[3]))
			break
	return out


## A one-of-a-kind item may be on a body: not owned, nowhere in the region,
## not on another body (a state of null allows it: tests, tools).
static func may_carry(state: GameState, id: String) -> bool:
	if not Items.is_unique(id) or state == null:
		return true
	if ExpeditionData.owns(state, id) or PoiState.placed_elsewhere(state, id):
		return false
	for list in _all_lists(state):
		for d in list:
			if typeof(d) == TYPE_DICTIONARY and int((d.get("items", {}) as Dictionary).get(id, 0)) > 0:
				return false
	return true


static func _all_lists(state: GameState) -> Array:
	var out := []
	if typeof(state.home.get("corpses")) == TYPE_ARRAY:
		out.append(state.home["corpses"])
	if state.region != null and typeof(state.region.get("poi")) == TYPE_DICTIONARY:
		for pid in state.region.poi:
			var r: Variant = state.region.poi[pid]
			if typeof(r) == TYPE_DICTIONARY and typeof(r.get("corpses")) == TYPE_ARRAY:
				out.append(r["corpses"])
	return out


## The person of a look ("Mechanic" of "Mechanic (a)"), or "".
static func person_of(k: String, app: int) -> String:
	var l := HumanoidLooks.look(k, app)
	var n := str(l.get("name", ""))
	var i := n.find(" (")
	return n.substr(0, i) if i >= 0 else n


# --- the body -----------------------------------------------------------------------------

func _bind(d: Dictionary) -> void:
	data = d
	if typeof(d.get("items")) != TYPE_DICTIONARY:
		d["items"] = {}
	items = d["items"]
	kind = str(d.get("kind", "psycho"))
	appearance = int(d.get("app", 0))
	display_name = str(d.get("name", ""))
	name = "Corpse_" + (display_name.replace(" ", "_") if display_name != "" else kind)
	add_to_group(GROUP)
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)


## Takes over a settled enemy's body (call with this corpse in the tree, at
## the enemy's position): the rig and any dropped prop move under `visual`.
func adopt(e: AIEnemy, d: Dictionary) -> void:
	_bind(d)
	global_position = e.global_position
	for c in e.get_children():
		if not (c is Node3D) or c is CollisionShape3D or c is AudioStreamPlayer3D or c is Label3D:
			continue
		var g := (c as Node3D).global_transform
		e.remove_child(c)
		visual.add_child(c)
		(c as Node3D).global_transform = g
	rig = e.rig
	_finish()


## Rebuilds the body from its record in the lying pose (call in the tree).
func rebuild(d: Dictionary) -> void:
	_bind(d)
	var p: Array = d["pos"]
	global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	rig = HumanoidLooks.make_rig(kind, appearance)
	visual.add_child(rig)
	var extras := EnemyLooks.apply(rig, kind)
	for key in ["light"]:
		var l: Variant = extras.get(key)
		if l is Light3D:
			(l as Light3D).visible = false
	for key in ["pack_mat", "lamp_mat"]:
		var m: Variant = extras.get(key)
		if m is StandardMaterial3D:
			(m as StandardMaterial3D).emission_energy_multiplier = 0.0
	var f: Array = d["fall"]
	var axis := Vector3(float(f[0]), 0.0, float(f[1])).normalized()
	var yaw := float(d.get("yaw", 0.0))
	if rig is HumanoidRig:
		var hr := rig as HumanoidRig
		hr._rng.seed = int(d.get("seed", 0))
		hr.collapse(0.0, 4.0, axis, yaw)
		hr.collapse(0.0, 6.0, axis, yaw)          # a dropped prop (the brute's club) lands
	else:
		var s: Vector3 = EnemyDefs.get_def(kind)["scale"]
		rig.transform.basis = Basis(axis, -PI * 0.48) * Basis(Vector3.UP, yaw) * Basis.from_scale(s)
		rig.position.y = -0.1
	_finish()


## Centres the node on the body (the interaction is measured from here) and
## takes the x-ray pass off its materials (a body isn't seen through walls).
func _finish() -> void:
	var mid := global_position
	if rig is HumanoidRig and (rig as HumanoidRig).torso != null:
		var t := (rig as HumanoidRig).torso.global_position
		mid = Vector3(t.x, global_position.y, t.z)
	var off := mid - global_position
	global_position = mid
	visual.position -= off
	_strip_xray(visual)


static func _strip_xray(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var m: Material = mi.material_override
		if m == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
			m = mi.mesh.surface_get_material(0)
		if m is ShaderMaterial and (m as ShaderMaterial).next_pass != null:
			mi.material_override = _no_xray(m as ShaderMaterial)
	for c in n.get_children():
		_strip_xray(c)


static func _no_xray(m: ShaderMaterial) -> ShaderMaterial:
	var id := m.get_instance_id()
	if not _mats.has(id):
		var c := m.duplicate() as ShaderMaterial
		c.next_pass = null
		_mats[id] = [m, c]
	return _mats[id][1]


## Keeps the copies' night shading with their originals (the corpse helper, per frame).
static func sync_materials() -> void:
	for id in _mats.keys():
		var pair: Array = _mats[id]
		if not is_instance_valid(pair[0]):
			_mats.erase(id)
			continue
		var n: Variant = (pair[0] as ShaderMaterial).get_shader_parameter("night")
		if n != null:
			(pair[1] as ShaderMaterial).set_shader_parameter("night", n)


func plan_pos() -> Vector2:
	return Vector2(global_position.x, global_position.z)


func searched() -> bool:
	return bool(data.get("searched", false))


func spent() -> bool:
	return is_spent(data)


# --- interaction (the game's InteractionFinder duck type) -----------------------------------

func interact_prompt() -> String:
	if spent():
		return ""
	var who := display_name if display_name != "" else "the body"
	if not searched():
		return "[E] Search %s" % who
	return "[E] Search %s · %s" % [who, contents_hint(items)]


func interact(game: Node) -> void:
	var h: Variant = game.get("corpses") if game != null else null
	if h is Object and is_instance_valid(h) and h.has_method("search"):
		h.call("search", self)


## "2 canned food, 1 bottled water" (+ "and 2 more kinds").
static func contents_hint(its: Dictionary) -> String:
	var parts := []
	var more := 0
	for id in Items.DEFS:
		var n := int(its.get(id, 0))
		if n <= 0:
			continue
		if parts.size() < 2:
			parts.append(ExpeditionData.count_text(id, n))
		else:
			more += 1
	var t := ", ".join(parts)
	if more > 0:
		t += " and %d more %s" % [more, "kind" if more == 1 else "kinds"]
	return t
