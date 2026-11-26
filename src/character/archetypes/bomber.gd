extends HumanoidArchetype
## Experiment 011: the bombers. Ordinary, recognisable people, ill-kempt and
## fixated, with the abstract glowing pack of Experiment 003 (EnemyLooks._pack:
## a dark frame, two glowing canisters, a lamp and a pulsing light; fictional
## on purpose) on their backs, its shoulder and chest straps sculpted over
## their clothes (outfit acc "straps"). Four people; one look each.
## Animation (BomberRig): a stiff, hurried, fixated walk, head down, one hand
## clutching a strap and the other fist pressed to the chest, lips moving in
## muttered bursts; lit (the fuse), hunched over the chest and shaking.

const SKINS := [0xe4b8a0, 0xd8a184, 0xc78a68, 0xa8714f, 0x87573a, 0x5f3d29]
const IRIS := [0x3a4a5c, 0x4a3626, 0x2a2420, 0x4a5a3a]

const PEOPLE := ["Delivery driver", "Woman in a fleece", "Older man in a sweater", "Young man in a tracksuit"]


func variety() -> int:
	return PEOPLE.size()


func make_look(i: int) -> Dictionary:
	var r := HumanoidArchetype.rng_for("bomber", i)
	var l: Dictionary = call("_p%d" % i, r)
	l["name"] = PEOPLE[i]
	l["body"] = HumanoidArchetype.jitter_body(r, l["body"], 0.03)
	var o: Dictionary = l["outfit"]
	o["acc"] = (o.get("acc", []) as Array) + ["straps"]
	var f: Dictionary = l["face"]
	f["iris"] = f.get("iris", pick(r, IRIS))
	f["pallor"] = f.get("pallor", r.randf_range(0.2, 0.4))
	f["circles"] = f.get("circles", r.randf_range(0.6, 0.9))
	f["grime"] = f.get("grime", r.randf_range(0.15, 0.4))
	f["bloodshot"] = f.get("bloodshot", r.randf_range(0.3, 0.5))
	f["look_dir"] = 1 if r.randf() < 0.5 else -1
	var s := {"hunch": 0.3, "head_up": 0.35, "stride": 0.82, "cadence": 1.3, "swing": 0.25, "sway": 0.08,
		"irregular": 0.12, "twitch": 0.3, "tempo": 1.2, "attack": "flail", "claw": 0.95, "walk_top": 2.6,
		"arm_l": "tight", "arm_r": "tight"}
	s.merge(l.get("style", {}), true)
	l["style"] = s
	return l


func new_rig(l: Dictionary) -> HumanoidRig:
	return BomberRig.new(l)


## The pack and its light, built with the rig (BomberRig._ready); the names
## bomber_behaviour.gd pulses: "pack", "pack_mat", "lamp_mat", "light".
func extras(rig: HumanoidRig) -> Dictionary:
	if rig is BomberRig:
		return (rig as BomberRig).pack_extras
	return {}


static func skin(r: RandomNumberGenerator, lo: int, hi: int) -> int:
	return SKINS[r.randi_range(lo, hi)]


# --- the people ---------------------------------------------------------------------------

## A delivery driver: polo-style shirt, work jacket, cargo trousers, a cap, stubble.
func _p0(r: RandomNumberGenerator) -> Dictionary:
	return {
		"body": {"height": 1.8, "weight": 0.38, "muscle": 0.45, "age": 0.35, "jaw": 1.05, "nose": 1.05},
		"outfit": {"top": {"type": "tshirt", "col": 0x8a2a24},
			"outer": {"type": "work_jacket", "col": 0x2e3440, "col2": 0x22262e},
			"legs": {"type": "cargo", "col": 0x3a3c3e, "belt": 0x1e1a18},
			"feet": [{"type": "sneakers", "col": 0x2a2a2c, "col2": 0x8a2a24}, {"type": "sneakers", "col": 0x2a2a2c, "col2": 0x8a2a24}],
			"hat": {"type": "cap", "col": 0x8a2a24}, "dirt": 0.35, "tears": 0.1},
		"face": {"skin": skin(r, 0, 4), "eyes": "stare", "brows": "knit", "mouth": "mutter"},
		"hair": {"style": "short", "col": 0x2a201a, "beard": "stubble"},
		"style": {},
	}


## A woman in a fleece and jeans, a bob and glasses: someone's neighbour.
func _p1(r: RandomNumberGenerator) -> Dictionary:
	return {
		"body": {"height": 1.66, "sex": 1.0, "weight": 0.42, "muscle": 0.2, "age": 0.45, "chin": 0.45, "cheeks": 0.6},
		"outfit": {"top": {"type": "tshirt", "col": 0xd8d0c4},
			"mid": {"type": "fleece", "col": 0x3a5a7a, "col2": 0x2c4660},
			"legs": {"type": "jeans", "col": 0x2c3a58},
			"feet": [{"type": "shoes", "col": 0x3a2a20}, {"type": "shoes", "col": 0x3a2a20}],
			"acc": ["glasses", "watch_l"], "dirt": 0.25, "tears": 0.1},
		"face": {"skin": skin(r, 0, 5), "eyes": "vacant", "brows": "worried", "mouth": "mutter"},
		"hair": {"style": "bob", "col": 0x6a4a32, "grey": 0.2},
		"style": {"hunch": 0.36, "cadence": 1.4},
	}


## An older man: shirt and knitted sweater, belted slacks, polished shoes,
## combed grey hair and a moustache.
func _p2(r: RandomNumberGenerator) -> Dictionary:
	return {
		"body": {"height": 1.75, "weight": 0.4, "muscle": 0.25, "age": 0.75, "nose": 1.12, "ears": 1.08, "jaw": 1.0},
		"outfit": {"top": {"type": "shirt", "col": 0xd8d4cc, "tucked": true},
			"mid": {"type": "sweater", "col": 0x4a5a3a, "col2": 0x3a4830},
			"legs": {"type": "trousers", "col": 0x5a5448, "belt": 0x2a1e16},
			"feet": [{"type": "shoes", "col": 0x2a1c14}, {"type": "shoes", "col": 0x2a1c14}],
			"dirt": 0.2, "tears": 0.05},
		"face": {"skin": skin(r, 0, 3), "eyes": "stare", "brows": "flat", "mouth": "mutter", "lines": 0.85},
		"hair": {"style": "combed", "col": 0x8a8680, "grey": 0.8, "beard": "moustache"},
		"style": {"hunch": 0.38, "stride": 0.72},
	}


## A young man in a zipped tracksuit, sweatpants and white trainers, a buzz cut.
func _p3(r: RandomNumberGenerator) -> Dictionary:
	return {
		"body": {"height": 1.82, "weight": 0.25, "muscle": 0.5, "age": 0.12, "jaw": 1.0, "chin": 0.45},
		"outfit": {"mid": {"type": "sport", "col": 0x1e2a44, "col2": 0xd8d4d0},
			"legs": {"type": "sweatpants", "col": 0x1e2a44},
			"feet": [{"type": "sneakers", "col": 0xe0dcd8, "col2": 0x1e2a44}, {"type": "sneakers", "col": 0xe0dcd8, "col2": 0x1e2a44}],
			"acc": ["watch_r"], "dirt": 0.3, "tears": 0.15},
		"face": {"skin": skin(r, 1, 5), "eyes": "wide", "brows": "knit", "mouth": "thin"},
		"hair": {"style": "buzz", "col": 0x1a1614},
		"style": {"cadence": 1.2, "stride": 0.9},
	}


## The bomber's body language and its pack (see the file header).
class BomberRig extends HumanoidRig:
	var pack_extras := {}
	var _mutter := 0.0
	var _mutter_on := false
	var _mutter_t := 1.0
	var _fuse := 0.0
	var _clock := 0.0

	func _ready() -> void:
		super._ready()
		pack_extras = EnemyLooks._pack(self)
		var pack: Node3D = pack_extras["pack"]
		# sit the frame on this body's back, over its clothes
		var depth := float((body["chest_r"] as Vector3).z) + HumanoidSculpt.new(look_data).max_t
		pack.position = Vector3(0.0, 0.17 * float(body["T"]), depth + 0.072)

	func _style_pose(delta: float) -> void:
		_clock += delta
		# lit: the pack's light runs hot (bomber_behaviour's fuse pulse)
		var l: OmniLight3D = pack_extras.get("light")
		var hot := l != null and l.light_energy > 1.32
		_fuse = move_toward(_fuse, 1.0 if hot else 0.0, delta * (6.0 if hot else 0.8))
		var idle := 1.0 - _move
		# stiff: the shoulders don't counter the hips, the arms barely swing
		torso.rotation.y *= 0.3
		torso.rotation.z *= 0.5
		# muttering bursts: a quick nodding of the bowed head, then silence
		_mutter_t -= delta
		if _mutter_t <= 0.0:
			_mutter_on = not _mutter_on
			_mutter_t = _rng.randf_range(0.8, 2.0) if _mutter_on else _rng.randf_range(0.6, 2.6)
		_mutter = move_toward(_mutter, 1.0 if _mutter_on else 0.0, delta * 5.0)
		head.rotation.x -= 0.22 + 0.06 * idle
		head.rotation.x += 0.045 * sin(_clock * 13.0) * _mutter
		head.rotation.y = lerpf(head.rotation.y, 0.0, 0.6)     # fixated: no glancing around
		# the hands: the left clutches its strap, the right fist pressed to the sternum
		var bob := sin(TAU * _phase) * _move
		arm_l.rotation = Vector3(-0.3 + 0.05 * bob, 0.0, -0.03)
		forearm_l.rotation = Vector3(2.6 + 0.04 * sin(_clock * 2.3), 0.0, 0.0)
		hand_l.rotation = Vector3(0.1, 0.0, 0.0)
		arm_r.rotation = Vector3(-0.05 - 0.05 * bob, 0.75, 0.0)
		forearm_r.rotation = Vector3(2.2 + 0.03 * sin(_clock * 3.1), 0.0, 0.0)
		hand_r.rotation = Vector3(-0.35, -0.4, 0.0)
		# lit: hunched over the chest, both fists pressed in, shaking
		if _fuse > 0.0:
			var sh := sin(_clock * 47.0) * _fuse
			torso.rotation.x -= 0.32 * _fuse
			head.rotation.x -= 0.3 * _fuse
			arm_l.rotation.y -= 0.25 * _fuse
			arm_r.rotation.y -= 0.1 * _fuse
			torso.rotation.z += 0.03 * sh
			head.rotation.y += 0.06 * sh
			pelvis.position.y -= 0.04 * _k * _fuse

	## A shove with the shoulder and a flail of the free arm (the right stays on the chest).
	func _attack_pose(p: float) -> void:
		super._attack_pose(p)
		var w := 1.0 - smoothstep(0.65, 1.0, p)
		arm_r.rotation = Vector3(-0.05, 0.75, 0.0)
		forearm_r.rotation = Vector3(2.2, 0.0, 0.0)
		torso.rotation.y += 0.25 * smoothstep(0.35, 0.5, p) * w

	## Hit: thrown back, but the hands stay on the pack (the base hit, arms kept).
	func _hit_pose(k: float) -> void:
		var al := arm_l.rotation
		var ar := arm_r.rotation
		super._hit_pose(k)
		var e := k * k * (3.0 - 2.0 * k)
		arm_l.rotation = al + Vector3(-0.2, 0.0, -0.15) * e
		arm_r.rotation = ar + Vector3(-0.15, 0.0, 0.1) * e
