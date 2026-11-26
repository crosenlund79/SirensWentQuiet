class_name RigIntegrity
extends RefCounted
## Experiment 012 (§29): checks that a humanoid rig's body holds together.
##
## Every bone of a HumanoidRig is a Node3D pivot whose position in its
## parent is fixed by the skeleton (HumanoidBody.derive); only rotations
## animate it. A bone whose position drifts from that rest offset, whose
## scale is not 1 or whose transform is not finite shows as a detached or
## floating body part. measure() reports the worst of these per rig;
## stress() drives rigs through every state at random (idle, walk, run,
## turns, attacks, hits during attacks, deaths mid-animation, random lag
## spikes, background look builds finishing) and measures every frame.
## Used by tests/e12/test_characters.gd and F10 > Debug > Stress humanoids.

## A bone further than this from its rest offset (m at k = 1) counts as detached.
## Intended motion (breathing, shrugs) stays under ~4 cm.
const SEPARATED := 0.06


## {"sep": worst offset from the rest position (m), "bone": its name,
##  "scale": worst |scale - 1| of a bone, "nan": any non-finite transform}.
static func measure(rig: HumanoidRig) -> Dictionary:
	var out := {"sep": 0.0, "bone": "", "scale": 0.0, "nan": false}
	if rig == null or rig.pelvis == null:
		return out
	var k := float(rig.body.get("k", 1.0))
	for b: Node3D in rig.rest_positions():
		var t := b.transform
		if not t.is_finite():
			out["nan"] = true
			out["bone"] = b.name
			continue
		if b == rig.pelvis:
			continue                       # the root of the body: its position animates (bob, crouch, collapse)
		var d := (t.origin - (rig.rest_positions()[b] as Vector3)).length() / maxf(k, 0.5)
		if d > float(out["sep"]):
			out["sep"] = d
			out["bone"] = b.name
		var sc := t.basis.get_scale()
		out["scale"] = maxf(float(out["scale"]), maxf(absf(sc.x - 1.0), maxf(absf(sc.y - 1.0), absf(sc.z - 1.0))))
	if not rig.transform.is_finite():
		out["nan"] = true
	return out


static func intact(m: Dictionary) -> bool:
	return not bool(m["nan"]) and float(m["sep"]) < SEPARATED and float(m["scale"]) < 0.05


## Drives `rigs` (HumanoidRigs in the tree) through `frames` random frames.
## Returns {"frames", "worst": measure() of the worst frame, "rig": its look
## key, "bad": frames with a broken rig, "deaths", "attacks", "hits", "spikes"}.
static func stress(rigs: Array, frames: int, rng: RandomNumberGenerator) -> Dictionary:
	var res := {"frames": 0, "worst": {"sep": 0.0, "bone": "", "scale": 0.0, "nan": false}, "rig": "",
		"bad": 0, "deaths": 0, "attacks": 0, "hits": 0, "spikes": 0}
	var st := {}
	for r in rigs:
		st[r] = {"speed": 0.0, "yaw": 0.0, "t": 0.0, "dead": -1.0}
	for f in frames:
		var dt := 1.0 / 60.0
		if rng.randf() < 0.04:
			dt = rng.randf_range(0.12, 0.6)          # a lag spike
			res["spikes"] = int(res["spikes"]) + 1
		HumanoidSculpt.poll()                        # background looks finishing mid-animation
		for r: HumanoidRig in rigs:
			if not is_instance_valid(r):
				continue
			var s: Dictionary = st[r]
			if float(s["dead"]) >= 0.0:
				s["dead"] = float(s["dead"]) + dt
				r.collapse(dt, float(s["dead"]), Vector3.RIGHT.rotated(Vector3.UP, float(s["yaw"])), float(s["yaw"]))
				if float(s["dead"]) > 2.0 and rng.randf() < 0.05:
					_revive(r)                       # like the showroom replaying it
					s["dead"] = -1.0
			else:
				if rng.randf() < 0.02:
					s["speed"] = [0.0, 0.0, 1.2, 1.85, 3.3, 5.0][rng.randi() % 6]
				if rng.randf() < 0.03:
					s["yaw"] = float(s["yaw"]) + rng.randf_range(-2.5, 2.5)   # a sharp turn
				r.rotation.y = lerp_angle(r.rotation.y, float(s["yaw"]), 1.0 - exp(-dt * 6.0))
				var fwd := -r.global_transform.basis.z
				r.position += Vector3(fwd.x, 0.0, fwd.z) * float(s["speed"]) * dt
				r.speed = float(s["speed"])
				if rng.randf() < 0.015 and r.swing <= 0.0:
					r.swing = 1.0
					res["attacks"] = int(res["attacks"]) + 1
				if rng.randf() < 0.02:
					r.stagger = 1.0                  # a hit, often during an attack
					r.set_flash(1.0)
					res["hits"] = int(res["hits"]) + 1
				r.swing = maxf(r.swing - dt / 0.5, 0.0)
				r.animate(dt)
				if rng.randf() < 0.004:
					s["dead"] = 0.0                  # dies mid-animation
					res["deaths"] = int(res["deaths"]) + 1
			var m := measure(r)
			if not intact(m):
				res["bad"] = int(res["bad"]) + 1
			var w: Dictionary = res["worst"]
			if bool(m["nan"]) or float(m["sep"]) > float(w["sep"]) or float(m["scale"]) > float(w["scale"]):
				if bool(m["nan"]) or float(m["sep"]) >= float(w["sep"]):
					res["rig"] = str(r.look_data.get("key", ""))
				w["sep"] = maxf(float(w["sep"]), float(m["sep"]))
				w["scale"] = maxf(float(w["scale"]), float(m["scale"]))
				w["nan"] = bool(w["nan"]) or bool(m["nan"])
				if float(m["sep"]) >= float(w["sep"]):
					w["bone"] = m["bone"]
		res["frames"] = int(res["frames"]) + 1
	return res


## Back on its feet (the showroom's replay; stress tests).
static func _revive(r: HumanoidRig) -> void:
	r.dead = false
	r.transform = Transform3D(Basis.from_scale(r.scale), r.position * Vector3(1.0, 0.0, 1.0))
	if r.has_method("attach_club"):
		r.call("_club_back")
