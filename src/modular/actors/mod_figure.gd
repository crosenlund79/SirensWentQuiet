class_name ModFigure
extends Node3D
## Low-poly stylised human built from a handful of bevelled parts on pivots,
## animated procedurally (walk cycle, aim, swing, stagger, collapse).
## Faces +z. Feet at y = 0. About 1.75 m tall.

const M := preload("res://src/modular/kit/mod_materials.gd")

## Look: colours (sRGB) and build. Keys: skin, hair, top, top2, pants, shoes,
## accent, pack, hunch (rad), bald, gun.
var look := {}

var hips: Node3D
var spine: Node3D
var neck: Node3D
var leg := [null, null]
var knee := [null, null]
var arm := [null, null]
var elbow := [null, null]
var muzzle: Node3D
var parts: Array[MeshInstance3D] = []

var phase := 0.0
var speed := 0.0            ## current ground speed (m/s), drives the walk cycle
var aiming := false
var recoil := 0.0
var swing := -1.0           ## -1 idle, 0..1 swing progress
var stagger := 0.0
var dead := 0.0             ## 0 alive .. 1 fully collapsed
var fall_dir := 1.0
var limp := 0.0


func _ready() -> void:
	_build()


func _part(parent: Node3D, mm: ModMesh, name_: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name_
	mi.mesh = mm.commit()
	mi.material_override = M.figure()
	parent.add_child(mi)
	parts.append(mi)
	return mi


func _pivot(parent: Node3D, pos: Vector3, name_: String) -> Node3D:
	var n := Node3D.new()
	n.name = name_
	n.position = pos
	parent.add_child(n)
	return n


func _c(key: String, fallback: Color) -> Color:
	return look.get(key, fallback)


func _build() -> void:
	var skin := _c("skin", Color(0.86, 0.68, 0.55))
	var hair := _c("hair", Color(0.2, 0.15, 0.12))
	var top := _c("top", Color(0.2, 0.22, 0.26))
	var top2 := _c("top2", top.darkened(0.15))
	var pants := _c("pants", Color(0.25, 0.27, 0.32))
	var shoes := _c("shoes", Color(0.3, 0.22, 0.16))
	var accent := _c("accent", Color(0.9, 0.42, 0.14))
	var is_enemy: bool = look.get("enemy", false)

	hips = _pivot(self, Vector3(0, 0.92, 0), "Hips")
	var mm := ModMesh.new()
	mm.set_mat(M.L_PLAIN, pants)
	mm.chamfer_box(Vector3(-0.17, -0.1, -0.1), Vector3(0.17, 0.1, 0.1), 0.04, false)
	if not is_enemy:
		mm.set_mat(M.L_PLAIN, Color(0.15, 0.12, 0.1))
		mm.box(Vector3(-0.175, 0.04, -0.105), Vector3(0.175, 0.08, 0.105))
	_part(hips, mm, "Pelvis")

	for i in 2:
		var sx := -1.0 if i == 0 else 1.0
		leg[i] = _pivot(hips, Vector3(sx * 0.095, -0.05, 0), "Leg%d" % i)
		mm = ModMesh.new()
		mm.set_mat(M.L_PLAIN, pants)
		mm.chamfer_box(Vector3(-0.075, -0.43, -0.08), Vector3(0.075, 0.02, 0.08), 0.03, false)
		if is_enemy and i == 0:
			# torn trouser leg showing pale skin
			mm.set_mat(M.L_PLAIN, skin.darkened(0.1))
			mm.box(Vector3(-0.06, -0.36, 0.07), Vector3(0.05, -0.22, 0.083))
		_part(leg[i], mm, "Thigh%d" % i)
		knee[i] = _pivot(leg[i], Vector3(0, -0.43, 0), "Knee%d" % i)
		mm = ModMesh.new()
		mm.set_mat(M.L_PLAIN, pants.darkened(0.06))
		mm.chamfer_box(Vector3(-0.065, -0.4, -0.07), Vector3(0.065, 0.02, 0.07), 0.025, false)
		mm.set_mat(M.L_PLAIN, shoes)
		mm.chamfer_box(Vector3(-0.07, -0.46, -0.08), Vector3(0.07, -0.37, 0.16), 0.03, false)
		_part(knee[i], mm, "Shin%d" % i)

	spine = _pivot(hips, Vector3(0, 0.08, 0), "Spine")
	mm = ModMesh.new()
	mm.set_mat(M.L_PLAIN, top)
	_torso(mm, 0.3, 0.44, 0.52, 0.2)
	if is_enemy:
		# stains and a torn flap
		mm.set_mat(M.L_PLAIN, top.darkened(0.35))
		mm.box(Vector3(-0.1, 0.12, 0.105), Vector3(0.05, 0.28, 0.115))
		mm.set_mat(M.L_PLAIN, skin.darkened(0.15))
		mm.box(Vector3(0.06, 0.05, 0.1), Vector3(0.14, 0.17, 0.112))
	else:
		# jacket zip and pockets, scarf (warm accent), backpack with straps
		mm.set_mat(M.L_PLAIN, top2)
		mm.box(Vector3(-0.008, 0.02, 0.1), Vector3(0.008, 0.46, 0.112))
		mm.box(Vector3(-0.15, 0.1, 0.1), Vector3(-0.05, 0.2, 0.113))
		mm.box(Vector3(0.05, 0.1, 0.1), Vector3(0.15, 0.2, 0.113))
		mm.set_mat(M.L_PLAIN, accent)
		mm.chamfer_box(Vector3(-0.15, 0.44, -0.1), Vector3(0.15, 0.56, 0.13), 0.04, false)
		mm.box(Vector3(0.05, 0.25, 0.1), Vector3(0.12, 0.46, 0.125))
		mm.set_mat(M.L_PLAIN, _c("pack", Color(0.3, 0.3, 0.24)))
		mm.chamfer_box(Vector3(-0.15, 0.08, -0.25), Vector3(0.15, 0.44, -0.09), 0.04, false)
		mm.set_mat(M.L_PLAIN, accent.darkened(0.3))
		for sx in [-1.0, 1.0]:
			mm.box(Vector3(sx * 0.13 - 0.025, 0.1, 0.095), Vector3(sx * 0.13 + 0.025, 0.47, 0.11))
	_part(spine, mm, "Torso")

	neck = _pivot(spine, Vector3(0, 0.52, 0.0), "Neck")
	mm = ModMesh.new()
	mm.set_mat(M.L_PLAIN, skin)
	mm.cylinder(Vector3(0, -0.02, 0), 0.05, 0.05, 0.08, 6)
	mm.blob(Vector3(0, 0.16, 0.01), Vector3(0.11, 0.13, 0.12), 4, 8)
	# nose and ears give the head a readable direction
	mm.chamfer_box(Vector3(-0.018, 0.12, 0.11), Vector3(0.018, 0.17, 0.145), 0.01, false)
	if is_enemy:
		mm.set_mat(M.L_PLAIN, Color(0.12, 0.08, 0.08))
		for sx in [-1.0, 1.0]:
			mm.box(Vector3(sx * 0.045 - 0.022, 0.17, 0.1), Vector3(sx * 0.045 + 0.022, 0.2, 0.122))
		mm.set_mat(M.L_PLAIN, Color(0.2, 0.1, 0.1))
		mm.box(Vector3(-0.035, 0.08, 0.105), Vector3(0.035, 0.1, 0.118))
	else:
		mm.set_mat(M.L_PLAIN, Color(0.1, 0.08, 0.07))
		for sx in [-1.0, 1.0]:
			mm.box(Vector3(sx * 0.042 - 0.012, 0.175, 0.115), Vector3(sx * 0.042 + 0.012, 0.195, 0.125))
	if not look.get("bald", false):
		mm.set_mat(M.L_PLAIN, hair)
		mm.blob(Vector3(0, 0.205, -0.015), Vector3(0.118, 0.1, 0.128), 3, 8)
		if is_enemy:
			# messy strands hanging forward
			for k in 4:
				var a := -0.6 + k * 0.4
				mm.tri(Vector3(sin(a) * 0.11, 0.25, cos(a) * 0.08), Vector3(sin(a) * 0.13 + 0.03, 0.24, cos(a) * 0.1), Vector3(sin(a) * 0.12, 0.1, cos(a) * 0.12 + 0.02), Vector3.ZERO)
	_part(neck, mm, "Head")

	for i in 2:
		var sx := -1.0 if i == 0 else 1.0
		arm[i] = _pivot(spine, Vector3(sx * 0.215, 0.45, 0), "Arm%d" % i)
		mm = ModMesh.new()
		mm.set_mat(M.L_PLAIN, top)
		mm.chamfer_box(Vector3(-0.055, -0.3, -0.06), Vector3(0.055, 0.05, 0.06), 0.025, false)
		_part(arm[i], mm, "UpperArm%d" % i)
		elbow[i] = _pivot(arm[i], Vector3(0, -0.29, 0), "Elbow%d" % i)
		mm = ModMesh.new()
		if is_enemy and i == 1:
			mm.set_mat(M.L_PLAIN, skin.darkened(0.05))   # sleeve torn off
		else:
			mm.set_mat(M.L_PLAIN, top2)
		mm.chamfer_box(Vector3(-0.048, -0.27, -0.05), Vector3(0.048, 0.02, 0.05), 0.02, false)
		mm.set_mat(M.L_PLAIN, skin)
		mm.chamfer_box(Vector3(-0.045, -0.37, -0.04), Vector3(0.045, -0.26, 0.05), 0.02, false)
		if look.get("gun", false) and i == 1:
			# compact pistol held in the right hand, barrel along -y of the forearm
			mm.set_mat(M.L_METAL, Color(0.12, 0.12, 0.13))
			mm.box(Vector3(-0.022, -0.4, -0.03), Vector3(0.022, -0.31, 0.1))
			mm.box(Vector3(-0.024, -0.48, -0.04), Vector3(0.024, -0.4, 0.04))
			mm.set_mat(M.L_PLAIN, Color(0.2, 0.2, 0.21))
			mm.box(Vector3(-0.018, -0.37, 0.09), Vector3(0.018, -0.3, 0.13))
		_part(elbow[i], mm, "Forearm%d" % i)
	if look.get("gun", false):
		muzzle = _pivot(elbow[1], Vector3(0, -0.5, 0.0), "Muzzle")


## Tapered torso prism: waist width a, shoulder width b, height h, depth d.
func _torso(mm: ModMesh, a: float, b: float, h: float, d: float) -> void:
	var lo := [Vector3(-a * 0.5, 0, -d * 0.5), Vector3(a * 0.5, 0, -d * 0.5), Vector3(a * 0.5, 0, d * 0.5), Vector3(-a * 0.5, 0, d * 0.5)]
	var hi := [Vector3(-b * 0.5, h * 0.85, -d * 0.55), Vector3(b * 0.5, h * 0.85, -d * 0.55), Vector3(b * 0.5, h * 0.85, d * 0.55), Vector3(-b * 0.5, h * 0.85, d * 0.55)]
	var top := [Vector3(-b * 0.38, h, -d * 0.45), Vector3(b * 0.38, h, -d * 0.45), Vector3(b * 0.38, h, d * 0.45), Vector3(-b * 0.38, h, d * 0.45)]
	var c := Vector3(0, h * 0.5, 0)
	for ring in [[lo, hi], [hi, top]]:
		var r0: Array = ring[0]
		var r1: Array = ring[1]
		for k in 4:
			var p0: Vector3 = r0[k]
			var p1: Vector3 = r0[(k + 1) % 4]
			var q1: Vector3 = r1[(k + 1) % 4]
			var q0: Vector3 = r1[k]
			var n := (p1 - p0).cross(q0 - p0).normalized()
			if n.dot((p0 + q1) * 0.5 - c) < 0.0:
				n = -n
			mm.quad(p0, p1, q1, q0, n)
	mm.poly(PackedVector3Array(top), Vector3.UP)
	mm.poly(PackedVector3Array(lo), Vector3.DOWN)


## Shader parameter on every part (flash, fade, rim).
func set_param(p: String, v: Variant) -> void:
	for mi in parts:
		mi.set_instance_shader_parameter(p, v)


func set_shadows(on: bool) -> void:
	for mi in parts:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Advance the procedural animation. `aim_pitch` lifts the gun arms.
func animate(delta: float) -> void:
	var enemy: bool = look.get("enemy", false)
	var hunch: float = look.get("hunch", 0.0)
	var stride := clampf(speed / 3.0, 0.0, 1.0)
	phase += delta * (2.0 + speed * 2.6) * (0.8 if enemy else 1.0)
	var s := sin(phase)
	var c := cos(phase)
	recoil = maxf(recoil - delta * 7.0, 0.0)
	stagger = maxf(stagger - delta * 3.5, 0.0)

	# legs
	var amp := 0.55 * stride
	for i in 2:
		var sgn := 1.0 if i == 0 else -1.0
		var ls := sin(phase + (0.0 if i == 0 else PI))
		var a := amp * ls * sgn * sgn
		var drag := limp * (0.5 if i == 0 else 0.0)
		leg[i].rotation = Vector3(-a * (1.0 - drag), 0, 0)
		knee[i].rotation = Vector3(maxf(0.0, cos(phase + (0.0 if i == 0 else PI))) * 0.9 * stride * (1.0 - drag * 0.6), 0, 0)
	hips.position.y = 0.92 - absf(c) * 0.05 * stride - (0.04 if enemy else 0.0)
	hips.rotation = Vector3(0, s * 0.12 * stride, s * 0.03 * stride + limp * 0.04 * sin(phase))

	# upper body
	var breathe := sin(phase * 0.35) * 0.015
	spine.rotation = Vector3(hunch + breathe - stagger * 0.6, -s * 0.1 * stride, 0)
	neck.rotation = Vector3((0.35 if enemy else 0.0) - hunch * 0.6 + stagger * 0.3, 0, (sin(phase * 0.5) * 0.15 if enemy else 0.0))

	if aiming:
		# two-handed grip toward +z, with recoil kick
		var lift := -PI * 0.5 + 0.12 - recoil * 0.3
		arm[1].rotation = Vector3(lift, -0.08, 0.0)
		elbow[1].rotation = Vector3(-0.05 - recoil * 0.15, 0, 0)
		# support hand reaches across to the grip
		arm[0].rotation = Vector3(lift + 0.12, 0.62, 0.0)
		elbow[0].rotation = Vector3(-0.12, 0, 0)
	elif enemy:
		var reach := -0.55 - hunch * 0.5
		for i in 2:
			var sw := sin(phase * 0.9 + i * 1.7) * 0.25 * (0.4 + stride)
			arm[i].rotation = Vector3(reach + sw, 0, (0.15 if i == 0 else -0.15))
			elbow[i].rotation = Vector3(-0.5 + sin(phase + i) * 0.15, 0, 0)
		if swing >= 0.0:
			# raise, then slam down
			var t := swing
			var raise := -2.6 * smoothstep(0.0, 0.45, t) + 2.9 * smoothstep(0.45, 0.7, t)
			arm[1].rotation.x = reach + raise
			elbow[1].rotation.x = -0.9 * smoothstep(0.0, 0.4, t) * (1.0 - smoothstep(0.5, 0.8, t))
			spine.rotation.x += 0.25 * smoothstep(0.45, 0.65, t) * (1.0 - smoothstep(0.7, 1.0, t)) - 0.15 * smoothstep(0.0, 0.45, t) * (1.0 - smoothstep(0.45, 0.6, t))
	else:
		for i in 2:
			var sgn := 1.0 if i == 0 else -1.0
			arm[i].rotation = Vector3(amp * s * sgn * 0.8, 0, sgn * -0.08)
			elbow[i].rotation = Vector3(-0.25 - 0.25 * stride, 0, 0)

	if dead > 0.0:
		_apply_collapse()


func _apply_collapse() -> void:
	var t := dead
	var e := 1.0 - pow(1.0 - t, 3.0)
	# pivot near the feet: topple, knees buckle, arms splay
	rotation.x = fall_dir * e * (PI * 0.47)
	position.y = -0.04 * e
	for i in 2:
		knee[i].rotation.x = lerpf(knee[i].rotation.x, 0.4 + 0.3 * i, e)
		leg[i].rotation.x = lerpf(leg[i].rotation.x, -0.2 * fall_dir, e)
		arm[i].rotation = arm[i].rotation.lerp(Vector3(-1.2 * fall_dir - 0.6, 0.0, (0.9 if i == 0 else -0.9)), e)
	spine.rotation.x = lerpf(spine.rotation.x, 0.1 * fall_dir, e)
	neck.rotation.x = lerpf(neck.rotation.x, 0.3 * fall_dir, e)
