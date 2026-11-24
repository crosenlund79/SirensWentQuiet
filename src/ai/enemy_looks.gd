class_name EnemyLooks
extends RefCounted
## Placeholder archetype visuals (SPEC-003 §5, no new art): the Experiment 002
## VoxelRig, scaled and tinted per EnemyDefs, plus a few attached simple
## meshes: the brute's plank club and the bomber's glowing pack with a
## pulsing light. The psycho keeps the Experiment 002 look exactly.
##
## Tinted materials share the voxel character shader's parameters through
## a copy (shaders/enemy_character.gdshader); `night` follows the standard
## enemy material, which the game's lighting drives (sync_night).

const SHADER := preload("res://src/ai/shaders/enemy_character.gdshader")
const XRAY_SHADER := preload("res://src/ai/shaders/enemy_xray.gdshader")
const PACK_GLOW := Color(1.0, 0.42, 0.12)

static var _materials := {}


## The body material of `kind` (null = the standard enemy look).
static func material(kind: String) -> ShaderMaterial:
	var d := EnemyDefs.get_def(kind)
	var tint: Color = d["tint"]
	if tint.a <= 0.0 and is_equal_approx(float(d["shade"]), 1.0) and kind == "psycho":
		return null
	if _materials.has(kind):
		return _materials[kind]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("shade", float(d["shade"]))
	var x := ShaderMaterial.new()
	x.shader = XRAY_SHADER
	x.set_shader_parameter("tint", d["xray"])
	x.set_shader_parameter("self_depth", 0.55 * maxf((d["scale"] as Vector3).x, (d["scale"] as Vector3).z) + (0.45 if kind == "brute" else 0.0))
	m.next_pass = x
	_materials[kind] = m
	return m


## Copies the night amount from the standard enemy material (driven by the
## lighting) to the archetype materials. Cheap; call once per frame.
static func sync_night() -> void:
	if _materials.is_empty():
		return
	var n: Variant = VoxelRig.look_material(false).get_shader_parameter("night")
	if n == null:
		return
	for k in _materials:
		(_materials[k] as ShaderMaterial).set_shader_parameter("night", n)


## Scale, hunch, materials and extras for an AIEnemy whose rig is in the tree.
## Returns the extra nodes by name ("club", "pack", "pack_mat", "lamp", "light").
static func apply(rig: VoxelRig, kind: String) -> Dictionary:
	var d := EnemyDefs.get_def(kind)
	rig.scale = d["scale"]
	rig.hunch = float(d["hunch"])
	var m := material(kind)
	if m != null:
		for p in rig.parts:
			p.material_override = m
	var extras := {}
	match kind:
		"brute":
			extras["club"] = _club(rig)
		"bomber":
			extras.merge(_pack(rig))
	return extras


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _flat(color: Color, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


## A heavy plank with a nail-studded end, held in the right hand.
static func _club(rig: VoxelRig) -> Node3D:
	var hold := Node3D.new()
	hold.name = "Club"
	hold.position = Vector3(0, -0.6, -0.02)
	hold.rotation = Vector3(-1.25, 0, 0)
	rig.arm_r.add_child(hold)
	_box(hold, Vector3(0.09, 0.82, 0.07), Vector3(0, -0.32, 0), _flat(Color(0.33, 0.24, 0.17)), "Plank")
	_box(hold, Vector3(0.13, 0.18, 0.11), Vector3(0, -0.66, 0), _flat(Color(0.25, 0.22, 0.21), 0.5), "Head")
	return hold


## The bomber's pack: a dark frame with two glowing canisters and a lamp on
## top, plus a pulsing orange light. Abstract and fictional on purpose.
static func _pack(rig: VoxelRig) -> Dictionary:
	var pack := Node3D.new()
	pack.name = "Pack"
	pack.position = Vector3(0, 0.3, 0.19)
	rig.torso.add_child(pack)
	_box(pack, Vector3(0.34, 0.4, 0.13), Vector3.ZERO, _flat(Color(0.2, 0.21, 0.19)), "Frame")
	var glow := StandardMaterial3D.new()
	glow.albedo_color = PACK_GLOW
	glow.emission_enabled = true
	glow.emission = PACK_GLOW
	glow.emission_energy_multiplier = 1.5
	for x in [-0.08, 0.08]:
		var c := MeshInstance3D.new()
		c.name = "Canister"
		var cm := CylinderMesh.new()
		cm.top_radius = 0.055
		cm.bottom_radius = 0.055
		cm.height = 0.34
		c.mesh = cm
		c.material_override = glow
		c.position = Vector3(x, 0.0, 0.08)
		pack.add_child(c)
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(1.0, 0.2, 0.1)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.15, 0.05)
	lamp_mat.emission_energy_multiplier = 2.0
	var lamp := MeshInstance3D.new()
	lamp.name = "Lamp"
	var sm := SphereMesh.new()
	sm.radius = 0.045
	sm.height = 0.09
	lamp.mesh = sm
	lamp.material_override = lamp_mat
	lamp.position = Vector3(0, 0.25, 0.02)
	pack.add_child(lamp)
	var light := OmniLight3D.new()
	light.name = "PackLight"
	light.light_color = Color(1.0, 0.4, 0.12)
	light.omni_range = 3.2
	light.light_energy = 0.8
	light.shadow_enabled = false
	light.position = Vector3(0, 0.2, 0.25)
	pack.add_child(light)
	return {"pack": pack, "pack_mat": glow, "lamp_mat": lamp_mat, "light": light}
