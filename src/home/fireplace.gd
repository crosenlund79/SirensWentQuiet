class_name Fireplace
extends Node3D
## Experiment 004: the living-room fireplace, a brick masonry heater standing
## against the living-room side of the x = 10 wall, south of the kitchen
## opening, its firebox open to the south (toward the camera). Independent of
## electricity. Lit at the start of a new game; [E] puts it out or lights it.
##
## The model is PropKit "fireplace" (bricks, hearth, mantel, logs and a
## glowing ember bed); this node adds the animated flames (flame.gdshader),
## rising sparks, a flickering warm OmniLight3D with shadows, a collision box,
## and a chimney stack with smoke above the roof (shown while the roof is).
## The duck-typed interactable (interact_prompt / interact) forwards to
## `owner_helper.on_fireplace()`, which owns the rules (cost, toast, save).

const RECT := Rect2(9.0, 4.15, 0.9, 0.8)     ## plan footprint (the hearth reaches 0.3 m further south)
const FACING := "S"
const HEIGHT := 2.6
const FLAME_SHADER := preload("res://src/home/shaders/flame.gdshader")
const SMOKE_SHADER := preload("res://src/home/shaders/snowfall.gdshader")
const LIGHT_COLOR := Color(1.0, 0.56, 0.26)
const LIGHT_ENERGY := 2.8
const LIGHT_RANGE := 7.5

var lit := true
var owner_helper: Object               ## gets on_fireplace() from interact()
var model: Node3D
var light: OmniLight3D
var flames: Array[MeshInstance3D] = []
var sparks: CPUParticles3D
var body: StaticBody3D
var chimney: Node3D
var smoke: CPUParticles3D
var _amount := 1.0                     ## fades the fire in and out
var _t := 0.0
var _smoke_mat: ShaderMaterial


func _ready() -> void:
	var c := RECT.get_center()
	position = Vector3(c.x, 0.0, c.y)
	model = PropKit.make("fireplace", Vector3(RECT.size.x, HEIGHT, RECT.size.y), {"facing": FACING, "seed": 4})
	model.name = "Model"
	add_child(model)
	# the firebox is centred, its mouth on the south face; everything below
	# is in this node's frame (x east, z south)
	var mouth := Vector3(0.0, 0.0, RECT.size.y * 0.5)
	var noise := FogBoundary.noise_texture()
	for k in 3:
		var q := QuadMesh.new()
		q.size = Vector2([0.5, 0.36, 0.3][k], [0.5, 0.4, 0.34][k])
		var m := ShaderMaterial.new()
		m.shader = FLAME_SHADER
		m.set_shader_parameter("noise_tex", noise)
		m.set_shader_parameter("seed", float(k) * 0.37)
		var mi := MeshInstance3D.new()
		mi.name = "Flame%d" % k
		mi.mesh = q
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = mouth + Vector3([0.0, -0.1, 0.11][k], 0.08 + q.size.y * 0.5, [-0.3, -0.22, -0.18][k])
		mi.rotation.y = [0.0, 0.5, -0.6][k]
		add_child(mi)
		flames.append(mi)
	sparks = CPUParticles3D.new()
	sparks.name = "Sparks"
	sparks.amount = 14
	sparks.lifetime = 1.4
	sparks.local_coords = false
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	sparks.emission_box_extents = Vector3(0.18, 0.03, 0.12)
	sparks.direction = Vector3(0, 1, 0.25)
	sparks.spread = 25.0
	sparks.initial_velocity_min = 0.35
	sparks.initial_velocity_max = 0.8
	sparks.gravity = Vector3(0, 0.15, 0)
	sparks.scale_amount_min = 0.5
	sparks.scale_amount_max = 1.0
	var sq := QuadMesh.new()
	sq.size = Vector2(0.025, 0.025)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.albedo_color = Color(1.0, 0.6, 0.2)
	sq.material = sm
	sparks.mesh = sq
	sparks.position = mouth + Vector3(0, 0.12, -0.25)
	add_child(sparks)
	light = OmniLight3D.new()
	light.name = "FireLight"
	light.light_color = LIGHT_COLOR
	light.omni_range = LIGHT_RANGE
	light.omni_attenuation = 1.4
	light.shadow_enabled = true
	light.shadow_bias = 0.06
	light.light_specular = 0.2
	light.position = mouth + Vector3(0, 0.45, 0.22)
	add_child(light)
	body = StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1           # tall: environment, stops bullets
	body.collision_mask = 0
	body.set_meta("impact", VoxelMat.Impact.CONCRETE)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(RECT.size.x, HEIGHT, RECT.size.y)
	cs.shape = box
	cs.position.y = HEIGHT * 0.5
	body.add_child(cs)
	add_child(body)
	_build_chimney()
	set_lit(lit, true)


## The stack above the roof (with a snow cap) and its smoke.
func _build_chimney() -> void:
	chimney = Node3D.new()
	chimney.name = "Chimney"
	add_child(chimney)
	var stack := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.6, 1.1, 0.55)
	stack.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.25, 0.2)
	mat.roughness = 0.95
	stack.material_override = mat
	stack.position = Vector3(0, 2.75 + 0.55, -0.05)
	chimney.add_child(stack)
	var cap := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(0.7, 0.08, 0.65)
	cap.mesh = cb
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.88, 0.9, 0.94)
	cm.roughness = 0.9
	cap.material_override = cm
	cap.position = Vector3(0, 2.75 + 1.14, -0.05)
	chimney.add_child(cap)
	smoke = CPUParticles3D.new()
	smoke.name = "Smoke"
	smoke.amount = 12
	smoke.lifetime = 5.0
	smoke.preprocess = 5.0
	smoke.local_coords = false
	smoke.direction = Vector3(0.25, 1, 0.1)
	smoke.spread = 10.0
	smoke.initial_velocity_min = 0.35
	smoke.initial_velocity_max = 0.55
	smoke.gravity = Vector3(0.08, 0.02, 0.03)
	smoke.scale_amount_min = 1.0
	smoke.scale_amount_max = 2.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.6))
	smoke.scale_amount_curve = curve
	var q := QuadMesh.new()
	q.size = Vector2(0.45, 0.45)
	_smoke_mat = ShaderMaterial.new()
	_smoke_mat.shader = SMOKE_SHADER
	_smoke_mat.set_shader_parameter("house", Vector4.ZERO)
	_smoke_mat.set_shader_parameter("opacity", 0.22)
	_smoke_mat.set_shader_parameter("tint", Color(0.6, 0.62, 0.66))
	q.material = _smoke_mat
	smoke.mesh = q
	smoke.position = Vector3(0, 2.75 + 1.2, -0.05)
	chimney.add_child(smoke)


func set_lit(on: bool, instant := false) -> void:
	lit = on
	if instant:
		_amount = 1.0 if on else 0.0
		_show(_amount)
	sparks.emitting = on
	smoke.emitting = on


## The chimney (and its smoke) only while the roof shows (the player is outside).
func set_roof_visible(on: bool) -> void:
	if chimney != null:
		chimney.visible = on


## Smoke tint for the time of day (0 day .. 1 night).
func set_night(t: float) -> void:
	if _smoke_mat != null:
		_smoke_mat.set_shader_parameter("tint", Color(0.6, 0.62, 0.66).lerp(Color(0.12, 0.13, 0.16), t))


func _show(a: float) -> void:
	PropKit.set_lit(model, a)
	for f in flames:
		(f.material_override as ShaderMaterial).set_shader_parameter("lit", a)
		f.visible = a > 0.01
	light.visible = a > 0.01


func _process(delta: float) -> void:
	_t += delta
	var goal := 1.0 if lit else 0.0
	if not is_equal_approx(_amount, goal):
		_amount = move_toward(_amount, goal, delta / (0.6 if lit else 1.6))
		_show(_amount)
	if light.visible:
		var f := 0.82 + 0.1 * sin(_t * 9.1) + 0.06 * sin(_t * 23.7 + 1.3) + 0.05 * sin(_t * 3.3)
		light.light_energy = LIGHT_ENERGY * _amount * f


# --- interactable (SPEC §7.3 duck type) ------------------------------------------------

func interact_prompt() -> String:
	return "[E] Put out the fire" if lit else "[E] Light the fire"


func interact(_game: Node) -> void:
	if owner_helper != null and owner_helper.has_method("on_fireplace"):
		owner_helper.on_fireplace()
