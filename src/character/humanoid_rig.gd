class_name HumanoidRig
extends VoxelRig
## Experiment 011: a voxel person (HumanoidSculpt meshes) on Eli's skeleton,
## with procedural animation shared by every humanoid and tuned per look by
## a STYLE dictionary (see STYLE below). It is a VoxelRig for the game: the
## AI drives it through the same members as before (speed, swing, stagger,
## hunch, set_flash, set_fade, animate; torso, head, arm_l, arm_r, leg_l,
## leg_r, parts) and the dormant poses (DormantMind.pose) rotate torso, head
## and the upper arms after animate() as they did on the old figure.
##
## Skeleton (pivots, all Node3D, Eli's layout from HumanoidBody.derive):
##   pelvis > chest (= torso) > head, arm_l / arm_r (upper arms) > forearm_l/r > hand_l/r
##   pelvis > leg_l / leg_r (thighs) > shin_l/r > foot_l/r
## Each pivot holds one MeshInstance3D "Mesh" (15 per person).
##
## Animation, in animate(): gait (two-bone leg IK, feet planted at the real
## ground speed: walk -> run), posture, arms, head, then the overlays:
## attack (`swing` 1 -> 0), hit (`stagger`), tics (style "twitch"). Turning
## on the spot shuffles the feet. collapse() replaces animate() once dead
## (AIEnemy._corpse calls it). Subclasses (phase-2 archetypes) override the
## hooks _style_pose(delta) (extra posing after the base pose), _attack_pose(p)
## and _hit_pose(k), or just change the style values.

## Style parameters (defaults; a look's "style" dictionary overrides them).
const STYLE := {
	"hunch": 0.22,       ## chest lean forward (rad)
	"head_up": 0.7,      ## share of the lean the head compensates (1 = eyes level, >1 chin jutting)
	"tilt": 0.0,         ## head roll bias (rad, + toward his right)
	"crouch": 0.0,       ## pelvis lowered (m): bent knees
	"stride": 1.0,       ## step length multiplier
	"cadence": 1.0,      ## > 1 quicker, shorter steps
	"swing": 0.6,        ## arm swing amplitude (Eli = 1)
	"arm_l": "swing",    ## swing | hang | tight | raised | fidget | reach | limp
	"arm_r": "swing",
	"spread": 0.0,       ## arms held away from the body (rad)
	"bob": 1.0,          ## vertical bounce
	"sway": 0.3,         ## side to side roll while walking / standing
	"limp": 0.0,         ## 0 .. 1, on limp_side (+1 right, -1 left)
	"limp_side": 1.0,
	"irregular": 0.3,    ## step-to-step variation of length and timing
	"twitch": 0.3,       ## how often and how hard tics come (0 = never)
	"tempo": 1.0,        ## idle speed (breathing, glances)
	"attack": "overhead",## overhead | swipe | lunge | flail
	"walk_top": 2.3,     ## m/s where the walk turns into a run
	"claw": 0.5,         ## finger curl (sculpt)
}

var look_data: Dictionary = {}
var style: Dictionary = {}
var body: Dictionary = {}           ## HumanoidBody.derive() of the look
var pelvis: Node3D
var forearm_l: Node3D
var forearm_r: Node3D
var hand_l: Node3D
var hand_r: Node3D
var shin_l: Node3D
var shin_r: Node3D
var foot_l: Node3D
var foot_r: Node3D
var dead := false
var preview_dir := Vector2.ZERO     ## showroom: a move direction when the rig itself does not move

var _phase := 0.0
var _move := 0.0
var _dir := Vector2(0.0, -1.0)
var _last := Vector3.INF
var _vel := Vector3.ZERO
var _last_yaw := INF
var _yaw_rate := 0.0
var _step_mul := 1.0
var _half := 0
var _rng := RandomNumberGenerator.new()
var _tic := ""
var _tic_t := 9.0
var _tic_k := 0.0
var _tic_side := 1.0
var _tic_next := 3.0
var _glance := 0.0
var _glance_goal := 0.0
var _glance_t := 1.5
var _hit_side := 1.0
var _hit_prev := 0.0
var _arm_lag := Vector2.ZERO
var _coll_t := 0.0
var _coll_bend := 1.0
# cached skeleton numbers
var _pelvis_y := 0.93
var _waist := Vector3.ZERO
var _neck := Vector3.ZERO
var _shoulder := Vector3.ZERO
var _hip := Vector3.ZERO
var _ua := 0.28
var _fa := 0.25
var _th := 0.405
var _sh := 0.395
var _ankle := 0.095
var _stance := 0.105
var _k := 1.0

static var _enemy_mat: ShaderMaterial
static var _night_frame := -1


## Character material for people (night uniform, the enemy x-ray pass) with
## Eli's softer rim. Its `night` follows the shared enemy material.
static func enemy_material() -> ShaderMaterial:
	if _enemy_mat == null:
		_enemy_mat = VoxelRig.look_material(false).duplicate() as ShaderMaterial
		_enemy_mat.set_shader_parameter("rim_day", Color(0.3, 0.32, 0.36))
		_enemy_mat.set_shader_parameter("rim_night", Color(0.2, 0.26, 0.42))
	return _enemy_mat


static func _sync_night() -> void:
	var f := Engine.get_process_frames()
	if f == _night_frame:
		return
	_night_frame = f
	var n: Variant = VoxelRig.look_material(false).get_shader_parameter("night")
	enemy_material().set_shader_parameter("night", float(n) if n != null else 0.0)


## `l`: a look (HumanoidLooks.look / an archetype's look()).
func _init(l: Dictionary = {}) -> void:
	look = Look.ENEMY_A
	look_data = l
	style = STYLE.duplicate()
	style.merge(l.get("style", {}), true)
	body = HumanoidBody.derive(l.get("body", {}))
	_rng.seed = hash(str(l.get("key", ""))) + 17


func _ready() -> void:
	_k = body["k"]
	_pelvis_y = body["pelvis_y"]
	_waist = body["waist"]
	_neck = body["neck"]
	_shoulder = body["shoulder"]
	_hip = body["hip"]
	_ua = body["upper_arm"]
	_fa = body["forearm"]
	_th = body["thigh"]
	_sh = body["shin"]
	_ankle = body["ankle_y"]
	_stance = body["stance_x"]
	hunch = float(style["hunch"])
	var m := HumanoidSculpt.meshes(look_data, material_for(look_data))
	pelvis = _bone(self, Vector3(0.0, _pelvis_y, 0.0), "pelvis", m["pelvis"])
	torso = _bone(pelvis, _waist, "chest", m["chest"])
	head = _bone(torso, _neck, "head", m["head"])
	arm_l = _bone(torso, _mx(_shoulder, -1.0), "arm_l", m["uarm_l"])
	arm_r = _bone(torso, _shoulder, "arm_r", m["uarm_r"])
	forearm_l = _bone(arm_l, Vector3(0.0, -_ua, 0.0), "forearm_l", m["farm_l"])
	forearm_r = _bone(arm_r, Vector3(0.0, -_ua, 0.0), "forearm_r", m["farm_r"])
	hand_l = _bone(forearm_l, Vector3(0.0, -_fa, 0.0), "hand_l", m["hand_l"])
	hand_r = _bone(forearm_r, Vector3(0.0, -_fa, 0.0), "hand_r", m["hand_r"])
	leg_l = _bone(pelvis, _mx(_hip, -1.0), "leg_l", m["thigh_l"])
	leg_r = _bone(pelvis, _hip, "leg_r", m["thigh_r"])
	shin_l = _bone(leg_l, Vector3(0.0, -_th, 0.0), "shin_l", m["shin_l"])
	shin_r = _bone(leg_r, Vector3(0.0, -_th, 0.0), "shin_r", m["shin_r"])
	foot_l = _bone(shin_l, Vector3(0.0, -_sh, 0.0), "foot_l", m["foot_l"])
	foot_r = _bone(shin_r, Vector3(0.0, -_sh, 0.0), "foot_r", m["foot_r"])
	_tic_next = _rng.randf_range(1.0, 4.0)
	_last = Vector3.INF
	animate(0.0)


## The material a look's meshes use (enemies: enemy_material()).
static func material_for(_l: Dictionary) -> Material:
	return enemy_material()


static func _mx(v: Vector3, s: float) -> Vector3:
	return Vector3(v.x * s, v.y, v.z)


func _bone(parent: Node3D, pos: Vector3, nm: String, mesh: Mesh) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	n.position = pos
	parent.add_child(n)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	n.add_child(mi)
	parts.append(mi)
	return n


func st(key: String) -> float:
	return float(style.get(key, STYLE.get(key, 0.0)))


func hand_global() -> Vector3:
	if hand_r == null or not hand_r.is_inside_tree():
		return global_position + Vector3(0, 1.0, 0)
	return hand_r.global_transform * Vector3(0.0, -0.09, 0.0)


## Held items go into the right hand (hand space matches VoxelRig's arm space).
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


# --- animation ---------------------------------------------------------------------------

func animate(delta: float) -> void:
	if pelvis == null or dead:
		return
	_sync_night()
	var tempo := st("tempo")
	_t += delta * tempo
	# real ground velocity (local) and the turn rate
	if is_inside_tree():
		var gp := global_position
		if _last != Vector3.INF and delta > 0.0:
			var w := (gp - _last) / delta
			if w.length() < 10.0:
				_vel = _vel.lerp(w, 1.0 - exp(-delta * 14.0))
		_last = gp
		var gy := global_rotation.y
		if _last_yaw != INF and delta > 0.0:
			_yaw_rate = lerpf(_yaw_rate, clampf(wrapf(gy - _last_yaw, -PI, PI) / delta, -12.0, 12.0), 1.0 - exp(-delta * 10.0))
		_last_yaw = gy
	var v := speed
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
	# turning on the spot: small shuffling steps
	var shuffle := clampf((absf(_yaw_rate) - 0.8) / 2.0, 0.0, 1.0) * (1.0 - clampf(v / 0.6, 0.0, 1.0))
	v = maxf(v, 0.55 * shuffle)
	_move = move_toward(_move, 1.0 if v > 0.08 else 0.0, delta * (5.0 if v > 0.08 else 3.0))
	var top := st("walk_top")
	var run := smoothstep(top, top + 1.5, v)
	var duty := lerpf(0.62, 0.38, run)
	var legs := (_th + _sh) / 0.8
	var reach := minf(0.3 + 0.4 * v, lerpf(0.86, 1.0, run)) * st("stride") * legs / maxf(st("cadence"), 0.3)
	reach *= _step_mul
	var limp := st("limp")
	var ls := st("limp_side")
	if v > 0.05:
		var dp := delta * duty * v / maxf(reach, 0.1)
		# the bad leg's stance is short: the cycle hurries through it
		var on_bad := (_phase < duty) if ls < 0.0 else (fposmod(_phase + 0.5, 1.0) < duty)
		if on_bad:
			dp *= 1.0 + 0.9 * limp
		else:
			dp *= 1.0 - 0.25 * limp
		_phase = fposmod(_phase + dp, 1.0)
	var half := int(_phase * 2.0)
	if half != _half:
		_half = half
		_step_mul = 1.0 + _rng.randf_range(-1.0, 1.0) * 0.3 * st("irregular")
	var idle := 1.0 - _move
	# --- pelvis --------------------------------------------------------------------
	var c2 := cos(TAU * (2.0 * _phase - duty))
	var bob := (0.02 * c2 * (1.0 - run) - 0.045 * c2 * run) * _move * st("bob")
	var shift := sin(_t * 0.5) * 0.5 + sin(_t * 0.21 + 1.3) * 0.5
	var breathe := sin(_t * 1.9)
	var drop := (0.025 + 0.04 * run) * _move + 0.008 * idle + st("crouch")
	# limping: the hip drops when the bad leg takes the weight
	var bad_stance := 0.0
	if limp > 0.0:
		var ph_bad := _phase if ls < 0.0 else fposmod(_phase + 0.5, 1.0)
		bad_stance = sin(PI * clampf(ph_bad / duty, 0.0, 1.0)) * float(ph_bad < duty) * _move
		drop += 0.05 * limp * bad_stance
	var sway := st("sway")
	pelvis.position = Vector3(-0.02 * sin(TAU * _phase) * (1.0 - run) * _move * (1.0 + sway) + 0.02 * shift * idle * sway * 2.0,
		_pelvis_y - drop + bob - absf(shift) * 0.006 * idle, 0.0)
	var twist := 0.12 * sin(TAU * _phase) * _move
	pelvis.rotation = Vector3(-0.04 * run * _move, twist,
		0.06 * shift * idle * (0.5 + sway) + 0.05 * sin(TAU * _phase) * _move * (1.0 - run) * (0.6 + sway) + 0.1 * limp * bad_stance * ls)
	# --- torso ---------------------------------------------------------------------
	var hn := st("hunch")
	var lean := hn + (0.04 + 0.16 * run) * _move
	torso.rotation = Vector3(-lean - 0.015 * breathe * idle,
		-twist * 1.4,
		-pelvis.rotation.z * 0.6 + sin(_t * 0.37) * 0.04 * sway)
	torso.position = _waist + Vector3(0.0, 0.004 * breathe, 0.0)
	torso.scale = Vector3(1.0 + 0.01 * breathe, 1.0, 1.0 + 0.014 * breathe)
	# --- head: compensates the lean, tilts, drifts, glances ------------------------------
	_glance_t -= delta * tempo
	if _glance_t <= 0.0:
		_glance_t = _rng.randf_range(1.2, 4.5)
		_glance_goal = _rng.randf_range(-0.6, 0.6) if _rng.randf() < 0.6 else 0.0
	_glance = lerpf(_glance, _glance_goal * (0.4 + 0.6 * idle), 1.0 - exp(-delta * 4.0))
	head.rotation = Vector3(lean * st("head_up") + 0.04 * sin(_t * 0.6),
		_glance - torso.rotation.y * 0.8 + clampf(_yaw_rate * 0.1, -0.5, 0.5),
		st("tilt") + 0.06 * sin(_t * 0.43) - pelvis.rotation.z * 0.4)
	# --- legs ------------------------------------------------------------------------
	_leg(-1.0, _phase, duty, reach, run, shift)
	_leg(1.0, fposmod(_phase + 0.5, 1.0), duty, reach, run, shift)
	# --- arms ------------------------------------------------------------------------
	_arms(delta, run)
	# --- overlays: archetype extras, attack, hit, tics -------------------------------------
	_style_pose(delta)
	if swing > 0.0:
		_attack_pose(1.0 - swing)
	if stagger > 0.0:
		if stagger > _hit_prev + 0.05:
			_hit_side = -1.0 if _rng.randf() < 0.5 else 1.0
		_hit_pose(stagger)
	_hit_prev = stagger
	_tics(delta)
	recoil = maxf(recoil - delta * 9.0, 0.0)
	stagger = maxf(stagger - delta * 3.5, 0.0)
	if _flash > 0.0:
		set_flash(maxf(_flash - delta * 7.0, 0.0))


## One leg from the gait cycle: the foot's ground target (rig space), then
## two-bone IK through the pelvis (EliRig's solver).
func _leg(s: float, ph: float, duty: float, reach: float, run: float, shift: float) -> void:
	var thigh := leg_l if s < 0.0 else leg_r
	var shin := shin_l if s < 0.0 else shin_r
	var foot := foot_l if s < 0.0 else foot_r
	var along := 0.0
	var lift := 0.0
	var pitch := 0.0
	var bad := st("limp") * float(signf(st("limp_side")) == s)
	if ph < duty:
		var u := ph / duty
		along = reach * (0.5 - u)
		pitch = 0.2 * (1.0 - smoothstep(0.0, 0.18, u)) * (1.0 - run) - 0.7 * pow(smoothstep(0.6, 1.0, u), 2.0)
	else:
		var w := (ph - duty) / (1.0 - duty)
		var e := w * w * (3.0 - 2.0 * w)
		along = reach * (-0.5 + e)
		# a shuffler barely lifts the feet; the bad leg drags
		lift = lerpf(0.06, 0.18, run) * sin(PI * w) * (1.0 + 0.6 * run * (1.0 - w)) * (1.0 - 0.7 * bad) * minf(st("stride") * 1.2, 1.0)
		pitch = lerpf(-0.7, 0.2 * (1.0 - run) + 0.1, smoothstep(0.0, 0.85, w)) * (1.0 - 0.6 * bad)
	var sx := _stance + 0.02 * st("crouch") / 0.1 * _k
	var stand := Vector3(s * (sx + 0.012 * shift * s), 0.0, -0.03 * s * shift)
	var gait := Vector3(s * (sx - 0.012 * run), 0.0, 0.0) + Vector3(_dir.x, 0.0, _dir.y) * along
	var ground := stand.lerp(gait, _move)
	var roll := pitch * _move
	var ankle := ground + Vector3(0.0, _ankle + lift * _move + 0.13 * _k * sin(maxf(-roll, 0.0)) + 0.05 * _k * sin(maxf(roll, 0.0)), 0.0)
	ankle.z -= 0.13 * _k * (1.0 - cos(minf(roll, 0.0)))
	var pt := pelvis.transform
	var target := pt.affine_inverse() * ankle
	var hp := _mx(_hip, s)
	var knee_dir := Vector3(0.12 * s, 0.0, -1.0)
	var r := EliRig._ik(hp, target, _th, _sh, knee_dir, 1.0)
	thigh.transform.basis = r[0]
	shin.transform.basis = (r[0] as Basis).inverse() * (r[1] as Basis)
	var want := pt.basis.inverse() * Basis(Vector3.RIGHT, roll)
	foot.transform.basis = (r[1] as Basis).inverse() * want


func _arms(delta: float, run: float) -> void:
	var sw := cos(TAU * _phase) * _move
	# the arms lag the body a little (they dangle)
	_arm_lag = _arm_lag.lerp(Vector2(sw, 0.0), 1.0 - exp(-delta * 7.0))
	var amp := st("swing") * (lerpf(0.32, 0.62, run))
	var idle := 1.0 - _move
	var sp := st("spread")
	for s: float in [-1.0, 1.0]:
		var up := arm_l if s < 0.0 else arm_r
		var lo := forearm_l if s < 0.0 else forearm_r
		var hd := hand_l if s < 0.0 else hand_r
		var mode := str(style.get("arm_l" if s < 0.0 else "arm_r", "swing"))
		var swing_s := -_arm_lag.x * s                  # the left arm swings against the left leg
		var u := Vector3(swing_s * amp + 0.06 * run, 0.0, s * (0.08 + sp + 0.05 * run))
		var f := Vector3(lerpf(0.2, 1.3, run) + 0.15 * maxf(swing_s, 0.0) + 0.05 * idle, 0.0, 0.0)
		var hr := Vector3(-0.15, 0.0, 0.05 * -s)
		var tt := _t + (0.0 if s < 0.0 else 1.7)
		match mode:
			"hang":
				u = Vector3(0.1 + swing_s * amp * 0.45 + 0.03 * sin(tt * 0.9), 0.0, s * (0.06 + sp))
				f = Vector3(0.12 + 0.05 * sin(tt * 1.3), 0.0, 0.0)
			"tight":
				u = Vector3(0.28 + swing_s * 0.05, 0.0, s * -0.02)
				f = Vector3(1.85 + 0.06 * sin(tt * 3.0), 0.0, 0.0)
				hr = Vector3(-0.3, s * -0.5, 0.0)
			"raised":
				u = Vector3(0.55 + swing_s * 0.1, 0.0, s * 0.12)
				f = Vector3(1.5 + 0.08 * sin(tt * 2.1), 0.0, 0.0)
				hr = Vector3(-0.6, 0.0, 0.0)
			"fidget":
				u = Vector3(0.1 + swing_s * amp * 0.5, 0.0, s * 0.07)
				f = Vector3(0.35 + 0.2 * maxf(sin(tt * 8.0), 0.0) * (0.4 + idle), 0.0, 0.0)
				hr = Vector3(-0.2 - 0.25 * sin(tt * 8.0 + 1.0), 0.0, 0.0)
			"reach":
				u = Vector3(0.75 + 0.15 * sin(tt * 1.1) + swing_s * 0.12, 0.0, s * 0.1)
				f = Vector3(0.45 + 0.1 * sin(tt * 1.7), 0.0, 0.0)
				hr = Vector3(-0.35, 0.0, 0.0)
			"limp":
				u = Vector3(0.05 + swing_s * 0.25, 0.0, s * (0.12 + sp))
				f = Vector3(0.05, 0.0, 0.0)
				hr = Vector3(0.05, 0.0, 0.0)
		up.rotation = u
		lo.rotation = f
		hd.rotation = hr


## Hook: extra posing per archetype after the base pose (before attacks and hits).
func _style_pose(_delta: float) -> void:
	pass


## Attack overlay, p = 0 (start) .. 1 (end). The impact lands near p 0.44
## (AIEnemy's wind-up 0.22 s of the 0.5 s swing).
func _attack_pose(p: float) -> void:
	var a := str(style.get("attack", "overhead"))
	var up := smoothstep(0.0, 0.42, p)                 # wind up
	var hit := smoothstep(0.4, 0.52, p)                # strike
	var back := smoothstep(0.65, 1.0, p)               # recover
	var w := 1.0 - back
	match a:
		"overhead":
			var ux := lerpf(lerpf(0.1, 2.75, up), 0.35, hit)
			var fx := lerpf(lerpf(0.2, 0.9, up), 0.15, hit)
			for s: float in [-1.0, 1.0]:
				var u := arm_l if s < 0.0 else arm_r
				var f := forearm_l if s < 0.0 else forearm_r
				u.rotation = u.rotation.lerp(Vector3(ux, 0.0, s * lerpf(0.25, 0.05, hit)), w)
				f.rotation = f.rotation.lerp(Vector3(fx, 0.0, 0.0), w)
			torso.rotation.x += (0.28 * up - 0.75 * hit) * w
			head.rotation.x += (0.15 * up - 0.25 * hit) * w
			pelvis.position.y -= 0.05 * hit * w
		"swipe":
			arm_r.rotation = arm_r.rotation.lerp(Vector3(lerpf(lerpf(0.1, -0.2, up), 1.25, hit), 0.0, lerpf(lerpf(0.1, 1.25, up), -0.25, hit)), w)
			forearm_r.rotation = forearm_r.rotation.lerp(Vector3(lerpf(lerpf(0.2, 1.2, up), 0.3, hit), 0.0, 0.0), w)
			arm_l.rotation = arm_l.rotation.lerp(Vector3(0.4 * up, 0.0, -0.3), w * 0.6)
			torso.rotation.y += (0.45 * up - 0.95 * hit) * w
			torso.rotation.x += (0.1 * up - 0.35 * hit) * w
		"lunge":
			for s: float in [-1.0, 1.0]:
				var u := arm_l if s < 0.0 else arm_r
				var f := forearm_l if s < 0.0 else forearm_r
				u.rotation = u.rotation.lerp(Vector3(lerpf(lerpf(0.2, 0.7, up), 1.45, hit), 0.0, s * lerpf(0.35, 0.12, hit)), w)
				f.rotation = f.rotation.lerp(Vector3(lerpf(1.3, 0.15, hit), 0.0, 0.0), w)
			torso.rotation.x += (0.2 * up - 0.6 * hit) * w
			pelvis.position.z -= 0.12 * _k * hit * w
			pelvis.position.y -= 0.06 * up * w
		_:      # flail: two quick alternating blows
			var b1 := sin(clampf(p / 0.5, 0.0, 1.0) * PI)
			var b2 := sin(clampf((p - 0.3) / 0.5, 0.0, 1.0) * PI)
			arm_r.rotation = arm_r.rotation.lerp(Vector3(0.3 + 2.2 * b1, 0.0, 0.15), w)
			arm_l.rotation = arm_l.rotation.lerp(Vector3(0.3 + 2.2 * b2, 0.0, -0.15), w)
			forearm_r.rotation.x = lerpf(forearm_r.rotation.x, 0.4 + 0.6 * b1, w)
			forearm_l.rotation.x = lerpf(forearm_l.rotation.x, 0.4 + 0.6 * b2, w)
			torso.rotation.x -= 0.3 * (b1 + b2) * 0.5 * w
			torso.rotation.z += 0.15 * (b1 - b2) * w


## Hit reaction overlay (k = stagger 1 -> 0): thrown back, twisted to one
## side, the head whipping, arms flung out.
func _hit_pose(k: float) -> void:
	var e := k * k * (3.0 - 2.0 * k)
	var s := _hit_side
	torso.rotation.x += 0.55 * e
	torso.rotation.z += 0.3 * s * e
	torso.rotation.y += 0.25 * s * e
	head.rotation.x += 0.45 * e
	head.rotation.z += 0.4 * s * e
	pelvis.position.y -= 0.05 * e * _k
	arm_l.rotation += Vector3(-0.5, 0.0, -0.55) * e
	arm_r.rotation += Vector3(-0.45, 0.0, 0.6) * e
	forearm_l.rotation.x += 0.5 * e
	forearm_r.rotation.x += 0.5 * e


## Tics: sudden head jerks, shoulder hitches, arm spasms, a shudder.
func _tics(delta: float) -> void:
	var tw := st("twitch")
	if tw <= 0.0:
		return
	_tic_next -= delta
	if _tic_next <= 0.0:
		_tic_next = _rng.randf_range(0.6, 4.5) / maxf(tw, 0.05)
		_tic = ["head", "head", "shoulder", "arm", "shudder"][_rng.randi() % 5]
		_tic_t = 0.0
		_tic_k = _rng.randf_range(0.5, 1.0) * minf(tw * 1.6, 1.4)
		_tic_side = -1.0 if _rng.randf() < 0.5 else 1.0
	if _tic == "":
		return
	_tic_t += delta
	var e := exp(-_tic_t * 9.0) * minf(_tic_t * 40.0, 1.0) * _tic_k
	if e < 0.01 and _tic_t > 0.2:
		_tic = ""
		return
	match _tic:
		"head":
			head.rotation.z += 0.55 * _tic_side * e
			head.rotation.y += 0.35 * _tic_side * e
			head.rotation.x -= 0.15 * e
		"shoulder":
			var a := arm_l if _tic_side < 0.0 else arm_r
			a.position.y += 0.035 * e * _k
			torso.rotation.z += 0.12 * _tic_side * e
			head.rotation.z += 0.25 * _tic_side * e
		"arm":
			var a := arm_l if _tic_side < 0.0 else arm_r
			var f := forearm_l if _tic_side < 0.0 else forearm_r
			a.rotation.x += 0.7 * e
			f.rotation.x += 0.9 * e
		"shudder":
			var j := sin(_tic_t * 70.0) * e
			torso.rotation.z += 0.07 * j
			head.rotation.y += 0.12 * j
			arm_l.rotation.z -= 0.08 * j
			arm_r.rotation.z += 0.08 * j


# --- death ----------------------------------------------------------------------------

## The collapse, instead of animate(), once dead (AIEnemy._corpse): the knees
## buckle and the body slumps (t < 0.35 s), then it topples along `axis`
## (the shot's direction) and lies still, limbs splayed. Sets the rig's own
## transform (yaw included); the caller may then sink it (position.y).
func collapse(delta: float, t: float, axis: Vector3, yaw: float) -> void:
	if pelvis == null:
		return
	if not dead:
		dead = true
		_coll_t = 0.0
		_coll_bend = -1.0 if _rng.randf() < 0.5 else 1.0
	_coll_t = t
	_sync_night()
	var buckle := smoothstep(0.0, 0.35, t)
	var fall := clampf((t - 0.18) / 0.5, 0.0, 1.0)
	fall = fall * fall
	var lie := smoothstep(0.55, 0.9, t)
	# knees give: the pelvis drops, the feet stay
	pelvis.position = Vector3(0.0, _pelvis_y - 0.32 * _k * buckle, 0.06 * _k * buckle)
	pelvis.rotation = Vector3(0.25 * buckle, 0.0, 0.08 * _coll_bend * buckle)
	for s: float in [-1.0, 1.0]:
		var th := leg_l if s < 0.0 else leg_r
		var sh := shin_l if s < 0.0 else shin_r
		var ft := foot_l if s < 0.0 else foot_r
		var bend := buckle * (1.0 if s == _coll_bend else 0.75)
		th.rotation = Vector3(1.1 * bend - 0.6 * lie * float(s != _coll_bend), 0.0, s * 0.12 * bend)
		sh.rotation = Vector3(-1.6 * bend + 1.0 * lie * float(s != _coll_bend), 0.0, 0.0)
		ft.rotation = Vector3(0.4 * bend, 0.0, 0.0)
	torso.rotation = Vector3(-0.55 * buckle + 0.35 * lie, 0.2 * _coll_bend * buckle, 0.15 * _coll_bend * lie)
	head.rotation = Vector3(-0.5 * buckle + 0.3 * lie, 0.5 * _coll_bend * lie, 0.4 * _coll_bend * lie)
	for s: float in [-1.0, 1.0]:
		var u := arm_l if s < 0.0 else arm_r
		var f := forearm_l if s < 0.0 else forearm_r
		u.rotation = Vector3(0.35 * buckle - 0.9 * lie * float(s == _coll_bend), 0.0, s * (0.15 + 0.9 * lie))
		f.rotation = Vector3(0.4 + 0.5 * lie * float(s != _coll_bend), 0.0, 0.0)
	# then the whole body tips over and comes to rest on the ground
	var ang := fall * 1.42
	transform.basis = Basis(axis, -ang) * Basis(Vector3.UP, yaw)
	position.y = (0.1 + 0.02 * weight_factor()) * _k * fall
	if _flash > 0.0:
		set_flash(maxf(_flash - delta * 7.0, 0.0))


func weight_factor() -> float:
	return float(body.get("weight", 0.3))
