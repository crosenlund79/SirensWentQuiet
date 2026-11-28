class_name EliRig
extends VoxelRig
## Experiment 010: Elias "Eli" Walker, a hand-sculpted voxel character
## (EliSculpt, 1.5 cm voxels) on a small skeleton of Node3D pivots, with
## procedural animation: idle with breathing, weight shifts and glances; a
## gait whose feet plant on the ground at the real speed (two-bone IK, heel
## strike and toe-off, walk -> jog -> run); arms that swing and pump; a
## two-handed pistol stance and a shouldered shotgun (arm IK onto the grips);
## the carry, held-item and use poses of VoxelRig.
##
## It is a VoxelRig for the game: same members (torso, head, arm_l, arm_r,
## leg_l, leg_r, gun, parts), same fields (speed, aiming, aim_pitch, recoil,
## carry, use_t) and methods (animate, set_held, hand_global, muzzle_global,
## set_flash, set_fade), so the player swaps it in without other changes.
## Faces -Z, the right side is +X, the soles at y 0, about 1.8 m tall.

const PELVIS_Y := 0.93
const WAIST := Vector3(0.0, 0.07, 0.0)          ## chest pivot in pelvis space
const NECK := Vector3(0.0, 0.45, 0.004)         ## head pivot in chest space
const SHOULDER := Vector3(0.162, 0.385, 0.01)   ## (x mirrored) in chest space
const HIP := Vector3(0.088, -0.035, 0.0)        ## (x mirrored) in pelvis space
const UPPER_ARM := 0.28
const FOREARM := 0.25
const THIGH := 0.405
const SHIN := 0.395
const ANKLE_Y := 0.095
const STANCE_X := 0.105

var variant := 0
var pelvis: Node3D
var forearm_l: Node3D
var forearm_r: Node3D
var hand_l: Node3D
var hand_r: Node3D
var shin_l: Node3D
var shin_r: Node3D
var foot_l: Node3D
var foot_r: Node3D
var _open := {}                 ## hand pivot -> [open mesh, fist mesh]
var _pistol: MeshInstance3D
var _phase := 0.0               ## gait cycle 0..1 (left foot plants at 0)
var _move := 0.0                ## 0 standing .. 1 moving (eased)
var _dir := Vector2(0.0, -1.0)  ## local move direction (x, z)
var _last := Vector3.INF
var _vel := Vector3.ZERO
var _glance := 0.0
var _glance_goal := 0.0
var _glance_t := 2.0
var _aim_blend := 0.0
var _two_blend := 0.0
## Exp 013 (gunplay): set by WeaponHandler each frame
var recoil_recovery := 9.0          ## recoil settles this much per s (per weapon)
var ads := 0.0                      ## 0..1 aiming down the sights (RMB): the gun comes up, steadier
var pump := 0.0                     ## 0..1 the pump / bolt stroke (the left hand works the pump)
var work := 0.0                     ## 1 while reloading: the gun tilts down to load it
var _work_blend := 0.0
var preview_dir := Vector2.ZERO ## showroom: a move direction when the rig itself does not move
static var _material: ShaderMaterial


## The player's character material (night uniform, x-ray pass) with a softer
## rim: at 1.5 cm every voxel step would catch the full rim light. Its
## `night` follows the shared material, which the game's lighting drives.
static func eli_material() -> ShaderMaterial:
	if _material == null:
		_material = VoxelRig.look_material(true).duplicate() as ShaderMaterial
		_material.set_shader_parameter("rim_day", Color(0.3, 0.32, 0.36))
		_material.set_shader_parameter("rim_night", Color(0.16, 0.22, 0.38))
	return _material


func _init(v := 0) -> void:
	look = Look.PLAYER
	walk_phase = PI * 0.5        # a footstep sound at each foot plant (_phase 0 and 0.5)
	variant = clampi(v, 0, EliSculpt.variant_count() - 1)


func _ready() -> void:
	hunch = 0.0
	pelvis = _bone(self, Vector3(0.0, PELVIS_Y, 0.0), "pelvis", "pelvis")
	torso = _bone(pelvis, WAIST, "chest", "chest")
	head = _bone(torso, NECK, "head", "head")
	arm_l = _bone(torso, _mx(SHOULDER, -1.0), "arm_l", "uarm_l")
	arm_r = _bone(torso, SHOULDER, "arm_r", "uarm_r")
	forearm_l = _bone(arm_l, Vector3(0.0, -UPPER_ARM, 0.0), "forearm_l", "farm_l")
	forearm_r = _bone(arm_r, Vector3(0.0, -UPPER_ARM, 0.0), "forearm_r", "farm_r")
	hand_l = _hand(forearm_l, "_l")
	hand_r = _hand(forearm_r, "_r")
	leg_l = _bone(pelvis, _mx(HIP, -1.0), "leg_l", "thigh_l")
	leg_r = _bone(pelvis, HIP, "leg_r", "thigh_r")
	shin_l = _bone(leg_l, Vector3(0.0, -THIGH, 0.0), "shin_l", "shin_l")
	shin_r = _bone(leg_r, Vector3(0.0, -THIGH, 0.0), "shin_r", "shin_r")
	foot_l = _bone(shin_l, Vector3(0.0, -SHIN, 0.0), "foot_l", "foot_l")
	foot_r = _bone(shin_r, Vector3(0.0, -SHIN, 0.0), "foot_r", "foot_r")
	# the gun node: weapon space (barrel -Y, grip +Z); child 0 is the pistol
	gun = Node3D.new()
	gun.name = "gun"
	torso.add_child(gun)
	_pistol = MeshInstance3D.new()
	_pistol.name = "Pistol"
	_pistol.mesh = EliSculpt.mesh(variant, "pistol", eli_material())
	gun.add_child(_pistol)
	parts.append(_pistol)
	_last = Vector3.INF
	animate(0.0)


static func _mx(v: Vector3, s: float) -> Vector3:
	return Vector3(v.x * s, v.y, v.z)


func _bone(parent: Node3D, pos: Vector3, nm: String, part: String) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	n.position = pos
	parent.add_child(n)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = EliSculpt.mesh(variant, part, eli_material())
	n.add_child(mi)
	parts.append(mi)
	return n


func _hand(parent: Node3D, sfx: String) -> Node3D:
	var n := Node3D.new()
	n.name = "hand" + sfx
	n.position = Vector3(0.0, -FOREARM, 0.0)
	parent.add_child(n)
	var a := MeshInstance3D.new()
	a.name = "Open"
	a.mesh = EliSculpt.mesh(variant, "hand" + sfx, eli_material())
	n.add_child(a)
	var b := MeshInstance3D.new()
	b.name = "Fist"
	b.mesh = EliSculpt.mesh(variant, "fist" + sfx, eli_material())
	b.visible = false
	n.add_child(b)
	parts.append(a)
	parts.append(b)
	_open[n] = [a, b]
	return n


func _fist(h: Node3D, on: bool) -> void:
	var m: Array = _open[h]
	(m[0] as MeshInstance3D).visible = not on
	(m[1] as MeshInstance3D).visible = on


## Rebuilds the meshes for another variation (showroom, settings).
func set_variant(v: int) -> void:
	v = clampi(v, 0, EliSculpt.variant_count() - 1)
	if v == variant:
		return
	variant = v
	var names := {pelvis: "pelvis", torso: "chest", head: "head", arm_l: "uarm_l", arm_r: "uarm_r",
		forearm_l: "farm_l", forearm_r: "farm_r", leg_l: "thigh_l", leg_r: "thigh_r", shin_l: "shin_l",
		shin_r: "shin_r", foot_l: "foot_l", foot_r: "foot_r"}
	for b in names:
		((b as Node3D).get_node("Mesh") as MeshInstance3D).mesh = EliSculpt.mesh(v, names[b], eli_material())
	for h in [hand_l, hand_r]:
		var sfx := "_l" if h == hand_l else "_r"
		var m: Array = _open[h]
		(m[0] as MeshInstance3D).mesh = EliSculpt.mesh(v, "hand" + sfx, eli_material())
		(m[1] as MeshInstance3D).mesh = EliSculpt.mesh(v, "fist" + sfx, eli_material())


## Held items sit in the right palm (hand space matches VoxelRig's arm space).
func set_held(kind: String) -> void:
	if kind == held and (_held_node != null) == (kind != ""):
		return
	held = kind
	if _held_node != null:
		_held_node.queue_free()
		_held_node = null
	if kind == "" or hand_r == null:
		return
	_held_node = held_model(kind)
	if _held_node != null:
		_held_node.name = "Held"
		_held_node.position = Vector3(-0.012, -0.085, 0.0)
		hand_r.add_child(_held_node)


func hand_global() -> Vector3:
	if hand_r == null or not hand_r.is_inside_tree():
		return global_position + Vector3(0, 1.0, 0)
	return hand_r.global_transform * Vector3(0.0, -0.2 if carry else -0.09, 0.0)


func muzzle_global() -> Vector3:
	if gun == null or not gun.is_inside_tree():
		return global_position + Vector3(0, Tuning.MUZZLE_HEIGHT, 0)
	return gun.global_transform * Vector3(0, -0.26, 0)


## The shotgun (or another long gun) is in hand: the weapon handler's model
## on the gun node is showing.
func two_handed() -> bool:
	if gun == null or not aiming:
		return false
	var m := gun.get_node_or_null("WeaponModel") as Node3D
	return m != null and m.visible


# --- animation --------------------------------------------------------------------------

func animate(delta: float) -> void:
	if pelvis == null:
		return
	_t += delta
	var night: Variant = VoxelRig.look_material(true).get_shader_parameter("night")
	eli_material().set_shader_parameter("night", float(night) if night != null else 0.0)
	# how fast and which way the body really moves (local), else `speed` forward
	var v := speed
	if is_inside_tree():
		var gp := global_position
		if _last != Vector3.INF and delta > 0.0:
			var w := (gp - _last) / delta
			if w.length() < 10.0:            # a teleport (stairs, waking, placing) is no step
				_vel = _vel.lerp(w, 1.0 - exp(-delta * 14.0))
		_last = gp
	var lv := Vector2.ZERO
	if _vel.length() > 0.15 and is_inside_tree():
		var l := global_transform.basis.inverse() * _vel
		lv = Vector2(l.x, l.z)
	if lv.length() > 0.1:
		_dir = _dir.lerp(lv.normalized(), 1.0 - exp(-delta * 10.0)).normalized()
	elif preview_dir != Vector2.ZERO:
		_dir = preview_dir.normalized()
	elif v > 0.05:
		_dir = _dir.lerp(Vector2(0.0, -1.0), 1.0 - exp(-delta * 4.0)).normalized()
	_move = move_toward(_move, 1.0 if v > 0.08 else 0.0, delta * (5.0 if v > 0.08 else 3.5))
	var run := smoothstep(2.2, 3.8, v)
	var sprint := smoothstep(4.6, 6.2, v)
	var duty := lerpf(0.62, 0.36, run) - 0.04 * sprint
	var reach := minf(0.32 + 0.42 * v, lerpf(0.9, 1.02, run))
	if v > 0.05:
		var dp := delta * duty * v / maxf(reach, 0.1)
		_phase = fposmod(_phase + dp, 1.0)
		walk_phase += TAU * dp    # VoxelRig's running phase: footstep sounds count its half-cycles
	var aim_target := 1.0 if aiming else 0.0
	_aim_blend = move_toward(_aim_blend, aim_target, delta * 7.0)
	_two_blend = move_toward(_two_blend, 1.0 if two_handed() else 0.0, delta * 7.0)

	# --- pelvis: height, bob, sway, twist ---------------------------------------
	var c2 := cos(TAU * (2.0 * _phase - duty))
	var bob := (0.018 * c2 * (1.0 - run) - 0.04 * c2 * run) * _move
	var idle := 1.0 - _move
	var shift := sin(_t * 0.55) * 0.5 + sin(_t * 0.23) * 0.5        # slow weight shift
	var breathe := sin(_t * 1.6)
	var drop := (0.025 + 0.035 * run + 0.02 * sprint) * _move + 0.008 * idle
	pelvis.position = Vector3(-0.018 * sin(TAU * _phase) * (1.0 - run) * _move + 0.016 * shift * idle,
		PELVIS_Y - drop + bob - absf(shift) * 0.006 * idle, 0.0)
	var twist := 0.11 * sin(TAU * _phase) * _move * (1.0 - 0.5 * _aim_blend)
	pelvis.rotation = Vector3(-0.04 * run * _move, twist, 0.05 * shift * idle + 0.035 * sin(TAU * _phase) * _move * (1.0 - run))
	# --- torso: lean, counter-twist, breathing ------------------------------------
	var lean := (0.05 + 0.13 * run + 0.16 * sprint) * _move
	lean += -stagger * 0.5 - recoil * (0.05 * (1.0 - _two_blend) + 0.06 * _two_blend)   # Exp 013: long guns kick the shoulders back
	torso.rotation = Vector3(-lean - 0.012 * breathe * idle + 0.04 * run * _move,
		-twist * (1.6 - 0.9 * _aim_blend) + 0.12 * _two_blend,
		-pelvis.rotation.z * 0.7)
	# Exp 012: breathing scales the chest's mesh, not the bone (its children,
	# the head and arms, were stretched and sheared with it)
	(torso.get_node("Mesh") as Node3D).scale = Vector3(1.0 + 0.008 * breathe, 1.0, 1.0 + 0.012 * breathe)
	torso.position = WAIST + Vector3(0.0, 0.004 * breathe, 0.0)
	# --- head: looks along the aim, glances around when idle ----------------------
	_glance_t -= delta
	if _glance_t <= 0.0:
		_glance_t = randf_range(2.5, 6.0)
		_glance_goal = randf_range(-0.5, 0.5) if randf() < 0.6 else 0.0
	_glance = lerpf(_glance, _glance_goal * idle * (1.0 - _aim_blend), 1.0 - exp(-delta * 3.0))
	head.rotation = Vector3(lean * 0.6 + aim_pitch * 0.45 * _aim_blend - 0.03 + 0.02 * sin(_t * 0.7) * idle - 0.1 * _two_blend,
		_glance - torso.rotation.y * 0.8, -pelvis.rotation.z * 0.5 - 0.05 * _two_blend)
	# --- legs ----------------------------------------------------------------------
	_leg(-1.0, _phase, duty, reach, run, shift)
	_leg(1.0, fposmod(_phase + 0.5, 1.0), duty, reach, run, shift)
	# --- arms ----------------------------------------------------------------------
	_arms(delta, run, sprint, breathe)
	recoil = maxf(recoil - delta * recoil_recovery, 0.0)
	_work_blend = move_toward(_work_blend, work, delta * 5.0)
	stagger = maxf(stagger - delta * 3.5, 0.0)
	if _flash > 0.0:
		set_flash(maxf(_flash - delta * 7.0, 0.0))


## One leg: the foot's target on the ground (rig space) from the gait cycle,
## then two-bone IK through the pelvis.
func _leg(s: float, ph: float, duty: float, reach: float, run: float, shift: float) -> void:
	var thigh := leg_l if s < 0.0 else leg_r
	var shin := shin_l if s < 0.0 else shin_r
	var foot := foot_l if s < 0.0 else foot_r
	var along := 0.0
	var lift := 0.0
	var pitch := 0.0
	if ph < duty:
		var u := ph / duty
		along = reach * (0.5 - u)
		pitch = 0.22 * (1.0 - smoothstep(0.0, 0.18, u)) * (1.0 - run) - 0.75 * pow(smoothstep(0.6, 1.0, u), 2.0)
	else:
		var w := (ph - duty) / (1.0 - duty)
		var e := w * w * (3.0 - 2.0 * w)
		along = reach * (-0.5 + e)
		lift = lerpf(0.075, 0.2, run) * sin(PI * w) * (1.0 + 0.6 * run * (1.0 - w))
		pitch = lerpf(-0.75, 0.22 * (1.0 - run) + 0.1, smoothstep(0.0, 0.85, w))
	var stand := Vector3(s * (STANCE_X + 0.012 * shift * s), 0.0, -0.03 * s * shift)
	var gait := Vector3(s * (STANCE_X - 0.012 * run), 0.0, 0.0) + Vector3(_dir.x, 0.0, _dir.y) * along
	var ground := stand.lerp(gait, _move)
	# heel / toe roll: the ankle rises over the ball when the heel lifts
	var roll := pitch * _move
	var ankle := ground + Vector3(0.0, ANKLE_Y + lift * _move + 0.13 * sin(maxf(-roll, 0.0)) + 0.05 * sin(maxf(roll, 0.0)), 0.0)
	ankle.z -= 0.13 * (1.0 - cos(minf(roll, 0.0)))
	# into pelvis space, solve, then keep the sole at the wanted pitch
	var pt := pelvis.transform
	var target := pt.affine_inverse() * ankle
	var hip := _mx(HIP, s)
	var knee_dir := Vector3(0.12 * s, 0.0, -1.0)
	var r := _ik(hip, target, THIGH, SHIN, knee_dir, 1.0)
	thigh.transform.basis = r[0]
	shin.transform.basis = (r[0] as Basis).inverse() * (r[1] as Basis)
	var want := pt.basis.inverse() * Basis(Vector3.RIGHT, roll)
	foot.transform.basis = (r[1] as Basis).inverse() * want


## Two-bone IK in the parent's space: root `a`, target `t`, bone lengths
## l1 and l2, `pole` the side the joint bends toward (bend +1, a knee) or
## away from (bend -1, an elbow). Returns [upper basis, lower basis], both
## with the bone along -Y and the hinge along X.
static func _ik(a: Vector3, t: Vector3, l1: float, l2: float, pole: Vector3, bend: float) -> Array:
	var d := t - a
	var dl := clampf(d.length(), absf(l1 - l2) + 0.01, (l1 + l2) * 0.999)
	var dir := d.normalized() if d.length() > 0.0001 else Vector3.DOWN
	var pp := pole - dir * pole.dot(dir)
	if pp.length() < 0.0001:
		pp = Vector3.BACK.cross(dir)
	pp = pp.normalized()
	var cos_a := clampf((l1 * l1 + dl * dl - l2 * l2) / (2.0 * l1 * dl), -1.0, 1.0)
	var al := acos(cos_a)
	var u := dir * cos(al) + pp * sin(al)
	var knee := a + u * l1
	var w := (a + dir * dl - knee).normalized()
	var x := dir.cross(pp).normalized() if bend > 0.0 else pp.cross(dir).normalized()
	var b1 := Basis(x, -u, x.cross(-u)).orthonormalized()
	var b2 := Basis(x, -w, x.cross(-w)).orthonormalized()
	return [b1, b2]


func _arms(delta: float, run: float, sprint: float, breathe: float) -> void:
	var lift := sin(clampf(use_t, 0.0, 1.0) * PI)
	use_t = maxf(use_t - delta * 1.6, 0.0)
	var swing := cos(TAU * _phase) * _move
	# free arms (FK): swing against the legs, bent elbows pumping when running
	var amp := lerpf(0.32, 0.62, run) + 0.15 * sprint
	var elbow := lerpf(0.22, 1.45, run)
	var idle := 1.0 - _move
	var sway := sin(_t * 1.1) * 0.025 * idle
	var free_l := [Vector3(-swing * amp + 0.06 * run + sway, 0.0, -0.09 - 0.05 * run),
		Vector3(elbow + 0.18 * maxf(-swing, 0.0) * (1.0 + run) + 0.05 * idle, 0.0, 0.0)]
	var free_r := [Vector3(swing * amp + 0.06 * run - sway, 0.0, 0.09 + 0.05 * run),
		Vector3(elbow + 0.18 * maxf(swing, 0.0) * (1.0 + run) + 0.05 * idle, 0.0, 0.0)]
	var fist_l := run > 0.5
	var fist_r := run > 0.5 or held != ""
	gun.visible = aiming
	if aiming or _aim_blend > 0.0:
		_aim_pose(free_l, free_r)
		_fist(hand_l, true)
		_fist(hand_r, true)
		return
	_pistol_hidden()
	# right hand: carry (flashlight forward), a held tool, or free
	var r_up: Vector3 = free_r[0]
	var r_lo: Vector3 = free_r[1]
	if carry:
		r_up = Vector3(1.25 + aim_pitch * 0.8, 0.0, 0.12)
		r_lo = Vector3(0.12, 0.0, 0.0)
		fist_r = true
	elif held != "":
		r_up = Vector3(0.18 + swing * 0.18 * amp, 0.0, 0.1)
		r_lo = Vector3(0.55 + 0.3 * run, 0.0, 0.0)
	# eating, drinking, bandaging: the hand comes up to the face once
	r_up = r_up.lerp(Vector3(0.55, 0.0, -0.12), lift)
	r_lo = r_lo.lerp(Vector3(2.2, 0.0, 0.0), lift)
	arm_l.rotation = free_l[0]
	forearm_l.rotation = free_l[1]
	arm_r.rotation = r_up
	forearm_r.rotation = r_lo
	hand_l.rotation = Vector3(-0.1 - 0.15 * run, 0.0, 0.05)
	hand_r.rotation = Vector3(-0.1 - 0.15 * run, 0.0, -0.05) if not carry else Vector3(0.0, 0.0, 0.0)
	_fist(hand_l, fist_l)
	_fist(hand_r, fist_r)


func _pistol_hidden() -> void:
	# without a weapon the gun node rides along at the right hand (nothing shows)
	if gun != null:
		gun.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), SHOULDER + Vector3(0.0, -0.4, -0.2))


## Weapon in hand: place the gun along the aim (in chest space, so the body
## may lean and twist under it), then reach both hands onto it with IK.
func _aim_pose(free_l: Array, free_r: Array) -> void:
	var two := _two_blend
	var ct := torso.transform
	var chest_rig := pelvis.transform * ct
	var pitch := clampf(aim_pitch, -0.9, 0.7) - 0.5 * _work_blend      # Exp 013: tilted down to reload
	var aim := Basis(Vector3.RIGHT, PI * 0.5 + pitch + recoil * (0.3 - 0.2 * two) * (1.0 - 0.3 * ads))
	var gb := chest_rig.basis.inverse() * aim         # gun basis in chest space
	var gun_t: Transform3D
	if two > 0.5:
		# shouldered: the butt (gun space 0, 0.33, 0.04) in the right shoulder pocket
		var pocket := Vector3(0.115, 0.36 + 0.025 * ads, -0.115) + Vector3(0.0, 0.0, 0.035) * recoil
		gun_t = Transform3D(gb, pocket - gb * Vector3(0.0, 0.33, 0.035))
	else:
		# pistol: both hands out in front, the gun swinging around the chest
		var pivot := Vector3(0.05 - 0.03 * ads, 0.37 + 0.07 * ads, -0.02)          # Exp 013: ADS brings the pistol up to the eye line
		var off := Vector3(0.0, -0.44 - 0.04 * ads, 0.015) + Vector3(0.0, 0.05, 0.0) * recoil
		gun_t = Transform3D(gb, pivot + gb * off)
	gun.transform = gun_t
	# hand targets in gun space: [grip point, hand basis in gun space]
	var r_grip: Vector3
	var l_grip: Vector3
	var r_b: Basis
	var l_b: Basis
	if two > 0.5:
		r_grip = Vector3(0.0, 0.0, 0.075)
		l_grip = Vector3(-0.004, -0.36 + 0.11 * pump, 0.06)          # Exp 013: works the pump
		r_b = Basis(Vector3.RIGHT, -0.55)
		l_b = Basis(Vector3.BACK, 0.5) * Basis(Vector3.UP, PI * 0.5)
	else:
		r_grip = Vector3(0.0, -0.075, 0.062)
		l_grip = Vector3(-0.03, -0.07, 0.075)
		r_b = Basis(Vector3.RIGHT, -0.3)
		l_b = Basis(Vector3.RIGHT, -0.45) * Basis(Vector3.BACK, 0.25)
	_reach(arm_r, forearm_r, hand_r, 1.0, gun_t, r_grip, r_b)
	_reach(arm_l, forearm_l, hand_l, -1.0, gun_t, l_grip, l_b)
	# blend in from the free pose while drawing
	if _aim_blend < 1.0:
		var k := _aim_blend
		arm_l.basis = Basis.from_euler(free_l[0]).slerp(arm_l.basis.orthonormalized(), k)
		forearm_l.basis = Basis.from_euler(free_l[1]).slerp(forearm_l.basis.orthonormalized(), k)
		arm_r.basis = Basis.from_euler(free_r[0]).slerp(arm_r.basis.orthonormalized(), k)
		forearm_r.basis = Basis.from_euler(free_r[1]).slerp(forearm_r.basis.orthonormalized(), k)


## Puts a hand on `grip` (gun space) with the hand basis `hb` (gun space).
func _reach(up: Node3D, lo: Node3D, hand: Node3D, s: float, gun_t: Transform3D, grip: Vector3, hb: Basis) -> void:
	var hand_basis := gun_t.basis * hb                 # chest space
	# the fist's grip centre sits 0.085 down the hand from the wrist
	var wrist := gun_t * grip - hand_basis * Vector3(-0.012 * s, -0.085, 0.0)
	var sh := _mx(SHOULDER, s)
	var pole := Vector3(0.9 * s, -0.7, 0.5)
	var r := _ik(sh, wrist, UPPER_ARM, FOREARM, pole, -1.0)
	up.transform.basis = r[0]
	lo.transform.basis = (r[0] as Basis).inverse() * (r[1] as Basis)
	hand.transform.basis = (r[1] as Basis).inverse() * hand_basis
