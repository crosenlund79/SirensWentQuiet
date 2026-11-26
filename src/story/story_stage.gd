class_name StoryStage
extends Node3D
## Exp 012 (S): the temporary staging of the story's night scenes in Eli's own
## bedroom (ASSIGNMENT §3, §6, §7). Everything here is added for the scene and
## taken away by restore(); the house itself is never changed:
##   - blankets hung over the bedroom window (props, not construction);
##   - a closed, "locked" door in the bedroom doorway (a prop; a door the
##     player built there is only hidden meanwhile), which jolts on knocks and
##     bat impacts (jolt(): a short shove, a hinge and handle rattle, back to
##     rest; never damaged);
##   - the room's lights hidden (and given back exactly as they were);
##   - Eli lying in his bed (a second rig; the player's own is hidden), bound
##     with four ropes for the last encounter, the struggle that frees him;
##   - the greenish gas seeping in under the door (particles and a faint light);
##   - the ropes thrown into the fireplace and its brief flare.
## Nothing here is saved, and nothing touches the house's objects, nav or save.

const BED_TYPE := "bed"
const DOOR_AT := Vector2(2.5, 4.0)           ## the bedroom doorway (HousePlan: mid_west, x 2..3)
const WINDOW := Rect2(1.0, 0.0, 2.0, 0.0)    ## the bedroom window (north wall, x 1..3)
const DARK_RADIUS := 6.5                     ## lights this close to the bed go dark
const ROPE_COLOR := Color(0.58, 0.47, 0.31)
const GAS_COLOR := Color(0.5, 0.78, 0.32, 0.26)

var game: Node
var active := false
var built := {}                              ## what is staged now: "blankets", "door", "lying", "bound", "gas"
var door: Node3D                             ## the prop door (null when not staged)
var sleeper: Node3D                          ## pivot of the lying rig
var sleeper_rig: Node3D
var ropes: Array[Node3D] = []
var gas: CPUParticles3D
var jolts := 0                               ## door jolts so far (tests)
var struggling := false
var _gas_light: OmniLight3D
var _gas_goal := 0.0
var _hidden: Array = []                      ## [node, was_visible]
var _jolt := 0.0
var _jolt_t := 0.0
var _rattle := 0.0
var _door_leaf: Node3D
var _door_knob: Node3D
var _t := 0.0
var _struggle_t := 0.0
var _rng := RandomNumberGenerator.new()


func setup(g: Node) -> void:
	game = g
	name = "StoryStage"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()


## The bed's plan rect (HousePlan).
static func bed_rect() -> Rect2:
	for f in HousePlan.FURNITURE:
		if f["type"] == BED_TYPE:
			return f["rect"]
	return Rect2(1.2, 0.17, 1.6, 2.1)


## Where Eli stands beside the bed (the game's wake spot).
func bed_side() -> Vector3:
	var w: Variant = game.get("world") if game != null else null
	if w != null and w.has_method("bed_position"):
		return w.bed_position()
	var r := bed_rect()
	return Vector3(r.get_center().x, 0.0, r.end.y + 0.4)


## Stages the scene. opts: "blankets", "door", "dark", "lying", "bound" (bools).
func build(opts: Dictionary) -> void:
	active = true
	if opts.get("blankets", false) and not built.has("blankets"):
		_make_blankets()
	if opts.get("door", false) and not built.has("door"):
		_make_door()
	if opts.get("dark", false) and not built.has("dark"):
		_dark(true)
	if opts.get("lying", false) and not built.has("lying"):
		_make_sleeper()
	if opts.get("bound", false) and not built.has("bound"):
		_make_ropes()


## Takes everything away: the room is as it was.
func restore() -> void:
	for k in ["blankets", "door", "gas", "ropes_flying"]:
		var n: Variant = built.get(k)
		if n is Node and is_instance_valid(n):
			(n as Node).queue_free()
	_unbind()
	if sleeper != null and is_instance_valid(sleeper):
		sleeper.queue_free()
	sleeper = null
	sleeper_rig = null
	door = null
	gas = null
	_gas_light = null
	_gas_goal = 0.0
	for h in _hidden:
		if is_instance_valid(h[0]):
			(h[0] as Node3D).visible = h[1]
	_hidden.clear()
	_set_player_rig_visible(true)
	built.clear()
	struggling = false
	active = false


## Keeps only what `keep` names (the rest goes): the aftermath keeps the bed.
func restore_except(keep: Array) -> void:
	var lying := built.has("lying") and "lying" in keep
	var bound := built.has("bound") and "bound" in keep
	if lying:
		var s := sleeper
		var r := ropes.duplicate()
		sleeper = null
		ropes.clear()
		built.erase("lying")
		built.erase("bound")
		restore()
		sleeper = s
		sleeper_rig = s.get_child(0) if s.get_child_count() > 0 else null
		if bound:
			ropes.assign(r)
			built["bound"] = true
		else:
			for n in r:
				(n as Node).queue_free()
		built["lying"] = true
		_set_player_rig_visible(false)
		active = true
	else:
		restore()


# --- the window and the door -----------------------------------------------------------------

func _make_blankets() -> void:
	var root := Node3D.new()
	root.name = "StoryBlankets"
	add_child(root)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.17, 0.16, 0.19)
	mat.roughness = 1.0
	var mat2 := mat.duplicate() as StandardMaterial3D
	mat2.albedo_color = Color(0.22, 0.19, 0.17)
	var z := 0.2                                 # just inside the north wall (0.15)
	for i in 3:
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.82, 1.55 - 0.05 * i, 0.03)
		m.mesh = b
		m.material_override = mat if i != 1 else mat2
		m.position = Vector3(WINDOW.position.x - 0.1 + 0.36 + i * 0.75, 1.52 - 0.02 * i, z + 0.012 * i)
		m.rotation.z = [0.02, -0.015, 0.03][i]
		root.add_child(m)
	var rod := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(2.5, 0.04, 0.04)
	rod.mesh = rb
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.3, 0.25, 0.2)
	rod.material_override = rm
	rod.position = Vector3(WINDOW.get_center().x, 2.3, z)
	root.add_child(rod)
	built["blankets"] = root


func _make_door() -> void:
	var w: Variant = game.get("world") if game != null else null
	# a door the player built in this doorway is hidden while ours stands
	if w != null and w.has_method("object_at"):
		var o: Variant = w.object_at(DOOR_AT, 0.2)
		if o is WorldObject and (o as WorldObject).kind == "door" and (o as WorldObject).visual != null:
			_hide((o as WorldObject).visual)
	door = Node3D.new()
	door.name = "StoryDoor"
	door.position = Vector3(DOOR_AT.x, 0.0, DOOR_AT.y)
	add_child(door)
	var size: Vector3 = WorldObject.DEFS["door"]["size"]
	var model := PropKit.make("door", size, {"facing": "N", "seed": 11})
	model.name = "Model"
	door.add_child(model)
	_door_leaf = model.find_child("Leaf", true, false) as Node3D
	# a handle on both faces that rattles on every blow
	_door_knob = Node3D.new()
	_door_knob.name = "Handle"
	_door_knob.position = Vector3(0.36, 1.0, 0.0)
	(_door_leaf if _door_leaf != null else door).add_child(_door_knob)
	var km := StandardMaterial3D.new()
	km.albedo_color = Color(0.62, 0.6, 0.55)
	km.metallic = 0.7
	km.roughness = 0.35
	for side in [-1.0, 1.0]:
		var k := MeshInstance3D.new()
		var kb := BoxMesh.new()
		kb.size = Vector3(0.12, 0.025, 0.035)
		k.mesh = kb
		k.material_override = km
		k.position = Vector3(-0.04, 0.0, side * (size.z * 0.5 + 0.02))
		_door_knob.add_child(k)
	built["door"] = door


## A blow on the door (1 = a bat impact; ~0.3 = a knock): it jolts in its
## frame, the hinges and handle rattle, then it settles. Never damaged.
func jolt(strength := 1.0) -> void:
	jolts += 1
	_jolt = maxf(_jolt, clampf(strength, 0.0, 1.5))
	_jolt_t = 0.0
	_rattle = maxf(_rattle, strength)


func knock() -> void:
	jolt(0.22)


# --- the lights --------------------------------------------------------------------------------

func _dark(on: bool) -> void:
	if not on or game == null:
		return
	var c := bed_rect().get_center()
	for l in game.find_children("*", "Light3D", true, false):
		if l is DirectionalLight3D or is_ancestor_of(l) or not (l as Node3D).visible:
			continue
		var p := (l as Node3D).global_position
		var player: Variant = game.get("player")
		var on_player: bool = player is Node and (player as Node).is_ancestor_of(l)
		if on_player or Vector2(p.x, p.z).distance_to(c) < DARK_RADIUS:
			_hide(l)
	built["dark"] = true


func _hide(n: Node3D) -> void:
	for h in _hidden:
		if h[0] == n:
			return
	_hidden.append([n, n.visible])
	n.visible = false


# --- Eli in his bed ----------------------------------------------------------------------------

func _make_sleeper() -> void:
	var r := bed_rect()
	sleeper = Node3D.new()
	sleeper.name = "StorySleeper"
	add_child(sleeper)
	# lying on his back, the head on the pillow (north), the feet to the south
	sleeper.basis = Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, PI * 0.5)
	sleeper.position = Vector3(r.get_center().x, 0.74, r.end.y - 0.2)
	var player: Variant = game.get("player")
	var rig: Node3D
	if player is VoxelPlayer:
		var keep := (player as VoxelPlayer).character_key
		rig = (player as VoxelPlayer).make_rig()
		(player as VoxelPlayer).character_key = keep
	else:
		rig = EliRig.new(0)
	rig.name = "Rig"
	sleeper.add_child(rig)
	rig.set("aiming", false)
	sleeper_rig = rig
	_set_player_rig_visible(false)
	built["lying"] = true


func _set_player_rig_visible(on: bool) -> void:
	var player: Variant = game.get("player") if game != null else null
	if player is VoxelPlayer and (player as VoxelPlayer).rig != null:
		(player as VoxelPlayer).rig.visible = on


## Four ropes over him and the bed (chest, waist, knees, ankles), tied to the frame.
func _make_ropes() -> void:
	if sleeper == null:
		return
	var r := bed_rect()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = ROPE_COLOR
	mat.roughness = 0.95
	for i in 4:
		var z: float = r.end.y - [1.55, 1.15, 0.65, 0.32][i]
		var band := Node3D.new()
		band.name = "Rope%d" % i
		band.position = Vector3(r.get_center().x, 0.0, z)
		add_child(band)
		_box(band, Vector3(r.size.x + 0.08, 0.045, 0.07), Vector3(0, 0.9 - 0.03 * float(i == 3), 0), mat)
		for side in [-1.0, 1.0]:
			_box(band, Vector3(0.05, 0.62, 0.05), Vector3(side * (r.size.x * 0.5 + 0.03), 0.6, 0), mat)
			_box(band, Vector3(0.09, 0.08, 0.09), Vector3(side * (r.size.x * 0.5 + 0.04), 0.32, 0), mat)
		ropes.append(band)
	built["bound"] = true


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = mat
	m.position = pos
	parent.add_child(m)
	return m


func struggle(on: bool) -> void:
	struggling = on
	_struggle_t = 0.0


## The ropes slip off the bed onto the floor beside it.
func loosen_ropes() -> void:
	var r := bed_rect()
	for i in ropes.size():
		var band := ropes[i]
		if not is_instance_valid(band):
			continue
		var tw := band.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		var to := band.position + Vector3(r.size.x * 0.5 + 0.35 + 0.12 * i, -0.55, 0.1 * i)
		tw.tween_property(band, "position", to, 0.5 + 0.12 * i).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(band, "rotation", Vector3(0.0, 0.3 * (i - 1.5), 1.2), 0.5 + 0.12 * i)
		tw.parallel().tween_property(band, "scale", Vector3(0.35, 0.6, 1.0), 0.5 + 0.12 * i)


func _unbind() -> void:
	for n in ropes:
		if is_instance_valid(n):
			n.queue_free()
	ropes.clear()
	built.erase("bound")


## Eli gets up: the lying rig goes, the player's own shows again.
func rise() -> void:
	_unbind()
	if sleeper != null and is_instance_valid(sleeper):
		sleeper.queue_free()
	sleeper = null
	sleeper_rig = null
	built.erase("lying")
	_set_player_rig_visible(true)


# --- the gas -----------------------------------------------------------------------------------

## The gas seeps in under the door (amount 0..1 fades it in and out).
func set_gas(amount: float) -> void:
	if gas == null and amount > 0.0:
		_make_gas()
	_gas_goal = clampf(amount, 0.0, 1.0)
	if gas != null:
		gas.emitting = amount > 0.0


func _make_gas() -> void:
	var root := Node3D.new()
	root.name = "StoryGas"
	add_child(root)
	gas = CPUParticles3D.new()
	gas.name = "Gas"
	gas.amount = 70
	gas.lifetime = 7.0
	gas.preprocess = 0.0
	gas.local_coords = false
	gas.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	gas.emission_box_extents = Vector3(0.42, 0.04, 0.04)
	gas.direction = Vector3(0.0, 0.12, -1.0)
	gas.spread = 38.0
	gas.initial_velocity_min = 0.18
	gas.initial_velocity_max = 0.45
	gas.gravity = Vector3(0, 0.025, 0)
	gas.damping_min = 0.02
	gas.damping_max = 0.06
	gas.scale_amount_min = 0.7
	gas.scale_amount_max = 1.3
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.4))
	sc.add_point(Vector2(1.0, 2.6))
	gas.scale_amount_curve = sc
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.0))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	ramp.add_point(0.18, Color(1, 1, 1, 1.0))
	ramp.add_point(0.7, Color(1, 1, 1, 0.75))
	gas.color_ramp = ramp
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = GAS_COLOR
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	gt.width = 64
	gt.height = 64
	m.albedo_texture = gt
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m
	gas.mesh = q
	gas.position = Vector3(DOOR_AT.x, 0.08, DOOR_AT.y - 0.18)
	gas.emitting = false
	root.add_child(gas)
	_gas_light = OmniLight3D.new()
	_gas_light.light_color = Color(0.45, 0.85, 0.3)
	_gas_light.omni_range = 4.5
	_gas_light.light_energy = 0.0
	_gas_light.position = Vector3(DOOR_AT.x, 0.5, DOOR_AT.y - 1.0)
	root.add_child(_gas_light)
	built["gas"] = root


# --- the fireplace -----------------------------------------------------------------------------

## Four coils of rope fly from `from` into the fire at `to` (two at a time).
func throw_ropes(from: Vector3, to: Vector3, count := 2, delay := 0.0) -> void:
	var root: Node3D = built.get("ropes_flying")
	if root == null or not is_instance_valid(root):
		root = Node3D.new()
		root.name = "StoryRopesFlying"
		add_child(root)
		built["ropes_flying"] = root
	var mat := StandardMaterial3D.new()
	mat.albedo_color = ROPE_COLOR
	mat.roughness = 0.95
	for i in count:
		var coil := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 0.05
		t.outer_radius = 0.12
		coil.mesh = t
		coil.material_override = mat
		coil.position = from
		root.add_child(coil)
		var land := to + Vector3(_rng.randf_range(-0.15, 0.15), 0.0, _rng.randf_range(-0.1, 0.08))
		var dur := 0.55 + 0.08 * i
		var tw := coil.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.tween_interval(delay + 0.12 * i)
		tw.tween_method(func(x: float) -> void:
			if is_instance_valid(coil):
				coil.position = from.lerp(land, x) + Vector3(0, sin(x * PI) * 0.55, 0)
				coil.rotation = Vector3(x * 5.0, x * 2.0, 0.0), 0.0, 1.0, dur)
		tw.tween_property(coil, "scale", Vector3(0.6, 0.3, 0.6), 1.6)
		tw.tween_callback(coil.queue_free)


## The fire flares up briefly where the ropes landed.
func flare(at: Vector3) -> void:
	var root: Node3D = built.get("ropes_flying")
	if root == null or not is_instance_valid(root):
		root = Node3D.new()
		root.name = "StoryRopesFlying"
		add_child(root)
		built["ropes_flying"] = root
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.22)
	l.omni_range = 6.0
	l.light_energy = 0.0
	l.position = at + Vector3(0, 0.45, 0.25)
	root.add_child(l)
	var tw := l.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(l, "light_energy", 3.2, 0.25)
	tw.tween_property(l, "light_energy", 0.0, 1.6)
	var sp := CPUParticles3D.new()
	sp.one_shot = true
	sp.explosiveness = 0.75
	sp.amount = 40
	sp.lifetime = 1.3
	sp.direction = Vector3(0, 1, 0.2)
	sp.spread = 30.0
	sp.initial_velocity_min = 0.6
	sp.initial_velocity_max = 1.6
	sp.gravity = Vector3(0, 0.3, 0)
	var q := QuadMesh.new()
	q.size = Vector2(0.035, 0.035)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1.0, 0.62, 0.22)
	q.material = m
	sp.mesh = q
	sp.position = at + Vector3(0, 0.15, 0)
	root.add_child(sp)
	sp.emitting = true


# --- the frame ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if door != null and is_instance_valid(door):
		_jolt_t += delta
		var a := _jolt * exp(-_jolt_t * 9.0)
		var shake := sin(_jolt_t * 55.0) * a
		door.position = Vector3(DOOR_AT.x + shake * 0.006, 0.0, DOOR_AT.y - absf(a) * 0.035 + shake * 0.008)
		door.rotation = Vector3(shake * 0.012, shake * 0.02, shake * 0.006)
		if _door_leaf != null and is_instance_valid(_door_leaf):
			_door_leaf.rotation.y = sin(_jolt_t * 41.0) * a * 0.03
		_rattle = maxf(_rattle - delta * 2.4, 0.0)
		if _door_knob != null and is_instance_valid(_door_knob):
			_door_knob.rotation.z = sin(_t * 63.0) * _rattle * 0.35
	if _gas_light != null and is_instance_valid(_gas_light):
		_gas_light.light_energy = move_toward(_gas_light.light_energy, _gas_goal * 0.7, delta * 0.3)
	if sleeper_rig != null and is_instance_valid(sleeper_rig):
		sleeper_rig.set("speed", 0.0)
		sleeper_rig.call("animate", delta)
		if struggling:
			_struggle_t += delta
			var k := sin(_struggle_t * 2.1) * 0.5 + 0.5
			var jerk := sin(_struggle_t * 17.0 + sin(_struggle_t * 5.0) * 2.0) * k
			sleeper.rotation.z = jerk * 0.07
			for arm in ["arm_l", "arm_r"]:
				var a: Variant = sleeper_rig.get(arm)
				if a is Node3D:
					(a as Node3D).rotation.x += jerk * 0.5
					(a as Node3D).rotation.z += (0.25 if arm == "arm_l" else -0.25) * k
			for i in ropes.size():
				if is_instance_valid(ropes[i]):
					ropes[i].rotation.x = jerk * 0.05 * (1 + i % 2)
		elif sleeper != null:
			sleeper.rotation.z = move_toward(sleeper.rotation.z, 0.0, delta)
