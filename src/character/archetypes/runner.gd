extends HumanoidArchetype
## Experiment 011: the runners. Starved people, disturbingly thin: long
## wasted limbs with knobbly knees and wrists, a shallow ribcage and a sunken
## belly, hollow cheeks and temples, deep dark sockets; the clothes of the
## people they were hang off them (HumanoidBody "gaunt", outfit "loose").
## Six people; one look each. Animation (RunnerRig): twitchy and fast, the
## head thrust forward; restless bouncing and snapping glances when idle; a
## loping, too-long sprint with flailing arms; a lunge; a jolting hit; a
## collapse like a puppet whose strings were cut.

const SKINS := [0xe4c0aa, 0xd8a184, 0xc78a68, 0xa8714f, 0x87573a]
const IRIS := [0x3a4a5c, 0x4a3626, 0x2a2420, 0x5c6c7c]

const PEOPLE := ["Patient in pyjamas", "Boy in a hoodie", "Woman in a cardigan", "Man in a shirt and tie",
	"Man in a torn vest", "Girl in a track jacket"]


func variety() -> int:
	return PEOPLE.size()


func make_look(i: int) -> Dictionary:
	var r := HumanoidArchetype.rng_for("runner", i)
	var l: Dictionary = call("_p%d" % i, r)
	l["name"] = PEOPLE[i]
	var b: Dictionary = l["body"]
	b.merge({"weight": 0.0, "muscle": 0.08, "gaunt": 0.92, "arms": 1.12, "legs": 1.05, "neck": 1.15,
		"hands": 1.08, "cheeks": 0.0, "brow": 1.2, "shoulders": 0.93}, false)
	l["body"] = HumanoidArchetype.jitter_body(r, b, 0.025)
	(l["body"] as Dictionary)["weight"] = 0.0
	(l["body"] as Dictionary)["cheeks"] = 0.0
	var f: Dictionary = l["face"]
	f["iris"] = f.get("iris", pick(r, IRIS))
	f["pallor"] = f.get("pallor", r.randf_range(0.55, 0.8))
	f["circles"] = f.get("circles", 1.0)
	f["grime"] = f.get("grime", r.randf_range(0.3, 0.6))
	f["bloodshot"] = f.get("bloodshot", r.randf_range(0.35, 0.6))
	f["look_dir"] = 1 if r.randf() < 0.5 else -1
	var s := {"hunch": 0.3, "head_up": 1.45, "stride": 1.1, "cadence": 0.97, "swing": 1.05, "walk_top": 1.7,
		"bob": 1.5, "twitch": 0.85, "tempo": 1.45, "attack": "lunge", "claw": 0.9, "sway": 0.15,
		"irregular": 0.5, "spread": 0.1, "arm_l": "swing", "arm_r": "swing"}
	s.merge(l.get("style", {}), true)
	s["twitch"] = float(s["twitch"]) * r.randf_range(0.85, 1.2)
	s["tilt"] = float(s.get("tilt", 0.0)) + r.randf_range(-0.1, 0.1)
	l["style"] = s
	return l


func new_rig(l: Dictionary) -> HumanoidRig:
	return RunnerRig.new(l)


static func skin(r: RandomNumberGenerator, lo: int, hi: int) -> int:
	return SKINS[r.randi_range(lo, hi)]


# --- the people ---------------------------------------------------------------------------

## A hospital patient: pale striped pyjamas far too big now, socks, a bandaged head.
func _p0(r: RandomNumberGenerator) -> Dictionary:
	return {
		"body": {"height": 1.88, "age": 0.45, "head_w": 0.97, "nose": 1.12, "jaw": 0.95, "ears": 1.08},
		"outfit": {"top": {"type": "shirt", "col": 0xb8c4cc, "col2": 0x8a9cac, "loose": 0.016, "sleeve": 0.72, "rolled": true},
			"legs": {"type": "sweatpants", "col": 0xa8b8c4, "loose": 0.008},
			"feet": [{"type": "sock", "sock": 0xc8c4b8}, {"type": "sock", "sock": 0xc8c4b8}],
			"acc": ["bandage_head", "bandage_r"], "dirt": 0.55, "tears": 0.3},
		"face": {"skin": skin(r, 0, 1), "eyes": "wide", "brows": "raised", "mouth": "slack"},
		"hair": {"style": "buzz", "col": 0x3a2a20, "beard": "stubble"},
		"style": {"arm_l": "swing", "arm_r": "fidget"},
	}


## A teenage boy in a grey hoodie and jeans that slide down his hips.
func _p1(r: RandomNumberGenerator) -> Dictionary:
	return {
		"body": {"height": 1.9, "age": 0.06, "head_w": 0.95, "chin": 0.3, "jaw": 0.9},
		"outfit": {"top": {"type": "tshirt", "col": 0xc8c4bc},
			"mid": {"type": "hoodie", "col": 0x5a5c60, "col2": 0x46484c, "hood": "down", "print": 0xb8b0a0, "loose": 0.018},
			"legs": {"type": "jeans", "col": 0x34405a, "loose": 0.01, "belt": 0x1e1a18},
			"feet": [{"type": "sneakers", "col": 0x8a8680, "col2": 0x2a2a2a}, {"type": "sneakers", "col": 0x8a8680, "col2": 0x2a2a2a}],
			"acc": ["torn_l"], "dirt": 0.6, "tears": 0.4},
		"face": {"skin": skin(r, 1, 4), "eyes": "stare", "brows": "flat", "mouth": "grin"},
		"hair": {"style": "messy", "col": 0x1c1816},
		"style": {"arm_l": "fidget", "twitch": 1.0},
	}


## A tall woman in a long cardigan over a blouse, a skirt over bare bony legs,
## lank long hair.
func _p2(r: RandomNumberGenerator) -> Dictionary:
	return {
		"body": {"height": 1.8, "sex": 1.0, "age": 0.35, "head_w": 0.95, "chin": 0.35, "nose": 1.02},
		"outfit": {"top": {"type": "blouse", "col": 0xd8d0c4, "loose": 0.01},
			"mid": {"type": "cardigan", "col": 0x6a5a6e, "col2": 0x54465a, "loose": 0.012, "sleeve": 0.8},
			"legs": {"type": "skirt", "col": 0x2e2a2c},
			"feet": [{"type": "shoes", "col": 0x2a201c}, {"type": "sock", "sock": 0x6a5e56}],
			"acc": ["bandage_l"], "dirt": 0.5, "tears": 0.35},
		"face": {"skin": skin(r, 0, 3), "eyes": "wide", "brows": "worried", "mouth": "grimace"},
		"hair": {"style": "long", "col": 0x5a4030, "grey": 0.15},
		"style": {"arm_r": "reach", "tilt": 0.18},
	}


## An office man: the shirt hangs off him, the tie loose, trousers cinched
## with a belt, one shoe; balding, cracked glasses.
func _p3(r: RandomNumberGenerator) -> Dictionary:
	return {
		"body": {"height": 1.84, "age": 0.6, "head_h": 1.04, "nose": 1.18, "ears": 1.1, "jaw": 0.96},
		"outfit": {"top": {"type": "shirt", "col": 0xc8ccd0, "tie": 0x5a2228, "loose": 0.018, "sleeve": 0.75, "rolled": true},
			"legs": {"type": "trousers", "col": 0x2c2e32, "belt": 0x1a1616, "loose": 0.01},
			"feet": [{"type": "shoes", "col": 0x1c1a1a, "sole": 0x141212}, {"type": "sock", "sock": 0x2a2a30}],
			"acc": ["glasses_cracked", "watch_l"], "dirt": 0.5, "tears": 0.35},
		"face": {"skin": skin(r, 0, 2), "eyes": "stare", "brows": "knit", "mouth": "thin", "lines": 0.8},
		"hair": {"style": "balding", "col": 0x6a645c, "grey": 0.7},
		"style": {"arm_l": "tight", "hunch": 0.38},
	}


## A man in a vest torn to rags (the ribs show through), cargo trousers, boots.
func _p4(r: RandomNumberGenerator) -> Dictionary:
	return {
		"body": {"height": 1.86, "age": 0.3, "head_w": 0.98, "jaw": 1.02, "brow": 1.35, "nose": 1.1, "gaunt": 1.0},
		"outfit": {"top": {"type": "tshirt", "col": 0xc8c0a8, "sleeve": 0.12, "loose": 0.014},
			"legs": {"type": "cargo", "col": 0x4a4a3a, "belt": 0x2a221c, "loose": 0.01},
			"feet": [{"type": "boots", "col": 0x3a2c22}, {"type": "boots", "col": 0x3a2c22}],
			"acc": ["torn_r"], "dirt": 0.8, "tears": 1.0},
		"face": {"skin": skin(r, 2, 4), "eyes": "wide", "brows": "uneven", "mouth": "grimace"},
		"hair": {"style": "buzz", "col": 0x1a1614, "beard": "stubble"},
		"style": {"arm_l": "swing", "arm_r": "swing", "spread": 0.16},
	}


## A teenage girl: a track jacket hanging open-shouldered, leggings over
## stick legs, sneakers, a ponytail.
func _p5(r: RandomNumberGenerator) -> Dictionary:
	return {
		"body": {"height": 1.74, "sex": 1.0, "age": 0.08, "head_w": 0.94, "chin": 0.4, "eyes": 1.05},
		"outfit": {"mid": {"type": "sport", "col": 0x6a2a4a, "col2": 0xd8d4d0, "loose": 0.016, "sleeve": 0.85},
			"legs": {"type": "leggings", "col": 0x1e1e22, "col2": 0x6a2a4a},
			"feet": [{"type": "sneakers", "col": 0xd8d4d0, "col2": 0x6a2a4a}, {"type": "sneakers", "col": 0xd8d4d0, "col2": 0x6a2a4a}],
			"dirt": 0.45, "tears": 0.3},
		"face": {"skin": skin(r, 0, 4), "eyes": "dart", "brows": "raised", "mouth": "mutter"},
		"hair": {"style": "ponytail", "col": 0x7a3e24, "tie": 0x2a2a2a},
		"style": {"arm_l": "fidget", "arm_r": "fidget", "tilt": -0.15},
	}


## The runner's body language (see the file header). Pose layers on top of
## HumanoidRig's gait; the AI, speeds and timings are the runner's as before.
class RunnerRig extends HumanoidRig:
	var _snap := Vector2.ZERO          ## jerky head turn (yaw, roll)
	var _snap_goal := Vector2.ZERO
	var _snap_t := 0.4
	var _clock := 0.0
	var _base_crouch := 0.0
	var _jolt_seed := 0.0

	func _ready() -> void:
		_base_crouch = st("crouch")
		super._ready()

	func animate(delta: float) -> void:
		if pelvis == null or dead:
			return
		_clock += delta
		# idle: bouncing on bent knees, restless (the gait's own crouch, so the feet stay planted)
		var idle := 1.0 - _move
		var b := pow(absf(sin(_clock * 5.2)), 3.0) * (0.6 + 0.4 * sin(_clock * 0.9))
		style["crouch"] = _base_crouch + (0.018 + 0.03 * b) * idle * _k + 0.02 * _move * _k
		super.animate(delta)

	func _run() -> float:
		var top := st("walk_top")
		return smoothstep(top, top + 1.4, maxf(speed, 0.0))

	func _style_pose(delta: float) -> void:
		var run := _run()
		var idle := 1.0 - _move
		# snapping glances: the goal jumps, the head follows almost at once
		_snap_t -= delta
		if _snap_t <= 0.0:
			_snap_t = _rng.randf_range(0.25, 1.3) * (1.6 if _move > 0.5 else 1.0)
			var reach := lerpf(0.9, 0.25, _move)
			_snap_goal = Vector2(_rng.randf_range(-reach, reach), _rng.randf_range(-0.35, 0.35) * idle)
		_snap = _snap.lerp(_snap_goal, 1.0 - exp(-delta * 28.0))
		head.rotation.y += _snap.x
		head.rotation.z += _snap.y
		# the head leads a turn; the shoulders snap after it
		head.rotation.y += clampf(_yaw_rate * 0.12, -0.7, 0.7)
		torso.rotation.y += clampf(_yaw_rate * 0.05, -0.3, 0.3)
		# idle: shoulders hitching with the bounce, hands twitching
		var b := pow(absf(sin(_clock * 5.2)), 3.0)
		arm_l.position.y += 0.008 * b * idle * _k
		arm_r.position.y += 0.008 * b * idle * _k
		# sprint: further over, chin out, loping twist, arms flung and flailing
		if run > 0.0:
			var ph := TAU * _phase
			torso.rotation.x -= 0.05 * run
			head.rotation.x += 0.12 * run
			torso.rotation.y += -0.18 * sin(ph) * run
			for s: float in [-1.0, 1.0]:
				var up := arm_l if s < 0.0 else arm_r
				var lo := forearm_l if s < 0.0 else forearm_r
				var hd := hand_l if s < 0.0 else hand_r
				var o := 0.0 if s < 0.0 else PI
				var fl := sin(ph + o)
				up.rotation.x += 0.55 * fl * run
				up.rotation.z += s * (0.45 + 0.35 * sin(2.0 * ph + o + 0.7)) * run
				up.rotation.y += s * 0.25 * sin(ph + o + 1.2) * run
				# limp forearms flapping behind the upper arm's motion
				lo.rotation.x = lerpf(lo.rotation.x, 0.35 + 0.75 * (0.5 + 0.5 * sin(ph + o - 1.4)), run)
				hd.rotation.x += 0.5 * sin(ph + o - 2.2) * run

	## A lunge: the whole body thrown forward, both clawed hands out, the face first.
	func _attack_pose(p: float) -> void:
		super._attack_pose(p)
		var up := smoothstep(0.0, 0.4, p)
		var hit := smoothstep(0.38, 0.5, p)
		var w := 1.0 - smoothstep(0.62, 1.0, p)
		torso.rotation.x -= (0.1 * up + 0.28 * hit) * w
		head.rotation.x += (0.1 * up + 0.2 * hit) * w
		pelvis.position.z -= 0.08 * _k * hit * w
		pelvis.position.y -= 0.05 * _k * up * w
		arm_l.rotation.z -= 0.22 * hit * w
		arm_r.rotation.z += 0.22 * hit * w
		hand_l.rotation.x -= 0.5 * hit * w
		hand_r.rotation.x -= 0.5 * hit * w

	## A jolt: the base hit, sharper, and a spasm through the limbs.
	func _hit_pose(k: float) -> void:
		super._hit_pose(minf(k * 1.25, 1.0))
		var j := sin(k * 48.0) * k * k
		head.rotation.y += 0.35 * j
		head.rotation.x -= 0.2 * j
		torso.rotation.z += 0.14 * j
		arm_l.rotation.x += 0.5 * j
		arm_r.rotation.x -= 0.5 * j
		forearm_l.rotation.x += 0.4 * absf(j)
		forearm_r.rotation.x += 0.4 * absf(j)

	## Strings cut: the knees fold at once and the body drops straight down,
	## folds over, then tips over along `axis`; the limbs bounce once as it lands.
	func collapse(delta: float, t: float, axis: Vector3, yaw: float) -> void:
		if pelvis == null:
			return
		if not dead:
			dead = true
			_coll_bend = -1.0 if _rng.randf() < 0.5 else 1.0
		_coll_t = t
		_sync_night()
		var drop := smoothstep(0.0, 0.17, t)
		var fold := smoothstep(0.06, 0.3, t)
		var fall := clampf((t - 0.24) / 0.36, 0.0, 1.0)
		fall = fall * fall
		var lie := smoothstep(0.4, 0.62, t)
		var lt := maxf(t - 0.6, 0.0)
		var bounce := exp(-lt * 7.0) * sin(lt * 26.0) * float(t > 0.6)
		var cb := _coll_bend
		pelvis.position = Vector3(0.03 * cb * _k * drop, _pelvis_y - 0.52 * _k * drop, 0.1 * _k * drop)
		pelvis.rotation = Vector3(0.15 * drop, 0.1 * cb * drop, 0.14 * cb * drop)
		var pt := pelvis.transform
		for s: float in [-1.0, 1.0]:
			var th := leg_l if s < 0.0 else leg_r
			var sh := shin_l if s < 0.0 else shin_r
			var ft := foot_l if s < 0.0 else foot_r
			# while dropping, the feet stay where they were (IK); lying, the legs fold askew
			var ankle := Vector3(s * (_stance + 0.03 * _k * drop), _ankle, 0.04 * _k * drop)
			var target := pt.affine_inverse() * ankle
			var hp := _mx(_hip, s)
			var r := EliRig._ik(hp, target, _th, _sh, Vector3(0.25 * s, 0.0, -1.0), 1.0)
			var q_th := (r[0] as Basis).get_rotation_quaternion()
			var q_sh := ((r[0] as Basis).inverse() * (r[1] as Basis)).get_rotation_quaternion()
			var own := s == cb
			var l_th := Quaternion.from_euler(Vector3(0.25 if own else 0.85, 0.0, s * (0.15 if own else 0.95)))   # the other knee falls aside
			var l_sh := Quaternion.from_euler(Vector3(-0.25 if own else -1.5, 0.0, 0.0))
			th.transform.basis = Basis(q_th.slerp(l_th, lie))
			sh.transform.basis = Basis(q_sh.slerp(l_sh, lie))
			ft.rotation = Vector3(0.5 * drop + 0.3 * lie, 0.0, s * 0.6 * lie)
		torso.rotation = Vector3(-0.95 * fold + 0.75 * lie + 0.12 * bounce, 0.3 * cb * fold, 0.35 * cb * fold - 0.1 * cb * lie)
		head.rotation = Vector3(-0.8 * fold + 0.55 * lie + 0.35 * bounce, 0.55 * cb * lie, 0.65 * cb * fold)
		for s: float in [-1.0, 1.0]:
			var u := arm_l if s < 0.0 else arm_r
			var f := forearm_l if s < 0.0 else forearm_r
			var hd := hand_l if s < 0.0 else hand_r
			var own := float(s == cb)
			# dangling (cancelling the fold), then flung out askew as it lands
			var hang := Vector3(0.95 * fold, 0.0, s * 0.06)
			var splay := Vector3(0.3 - 1.7 * own + 0.4 * bounce, 0.0, s * (0.3 + 1.1 * own))
			u.rotation = hang.lerp(splay, lie)
			f.rotation = Vector3(0.1 + 0.9 * lie * (1.0 - own) + 0.3 * bounce, 0.0, 0.0)
			hd.rotation = Vector3(0.4 * fold, 0.0, 0.0)
		var ang := fall * 1.45
		transform.basis = Basis(axis, -ang) * Basis(Vector3.UP, yaw)
		position.y = 0.06 * _k * fall
		if _flash > 0.0:
			set_flash(maxf(_flash - delta * 7.0, 0.0))
