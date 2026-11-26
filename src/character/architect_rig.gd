class_name ArchitectRig
extends HumanoidRig
## Experiment 011: the animation of "the Architect" (internal name; see
## ArchitectIdentity). Stillness: his look's style already removes the tics,
## the sway and most idle motion and slows his breathing; on top of the
## shared HumanoidRig this rig
##   * never glances around: the head holds still unless it has a reason;
##   * turns in a controlled way (face_yaw): the head leads, the chest
##     follows a little, and only then does the body come round, easing in
##     and out at a measured rate (small deliberate steps on the spot);
##   * observes (observe = true): hands clasped behind the back, upright,
##     the head tilted slightly, watching (also while walking).
## The walk is the shared gait with his style: upright, measured, short arm
## swing. Attack, hit and collapse are the shared overlays. Silent: the rig
## makes no sounds.

const HEAD_LEAD := 1.05        ## rad the head turns before the body must follow
const LEAD_TIME := 0.45        ## s the head leads before the body starts
const TILT := 0.13             ## head roll while observing (rad)

var face_yaw := INF            ## the yaw (parent space) to turn toward; INF: hold
var observe := false           ## hands behind the back, the head tilted, watching
var turn_speed := 1.25         ## rad/s at most for the body
var _obs := 0.0
var _head_yaw := 0.0
var _lead := 0.0
var _body_rate := 0.0


func _style_pose(delta: float) -> void:
	_turn(delta)
	_obs = move_toward(_obs, 1.0 if observe else 0.0, delta * 0.9)
	var o := smoothstep(0.0, 1.0, _obs)
	# no glances, no drift: the base head pose minus its idle wander
	_glance = 0.0
	_glance_goal = 0.0
	var twist := torso.rotation.y                                 # the gait's chest twist
	torso.rotation.y += 0.25 * _head_yaw                          # the chest follows the head a little
	head.rotation = Vector3(head.rotation.x - 0.04 * sin(_t * 0.6) + 0.06 * o,
		0.75 * _head_yaw - twist * 0.8,
		head.rotation.z - 0.06 * sin(_t * 0.43) + TILT * o)
	if o > 0.0:
		for s: float in [-1.0, 1.0]:
			_clasp(s, o)


## The controlled turn toward face_yaw: the head leads, then the body.
func _turn(delta: float) -> void:
	if face_yaw == INF or dead:
		_head_yaw = lerpf(_head_yaw, 0.0, 1.0 - exp(-delta * 2.0))
		_body_rate = 0.0
		return
	var diff := wrapf(face_yaw - rotation.y, -PI, PI)
	_head_yaw = lerpf(_head_yaw, clampf(diff, -HEAD_LEAD, HEAD_LEAD), 1.0 - exp(-delta * 3.2))
	_lead = _lead + delta if absf(diff) > 0.04 else 0.0
	var want := 0.0
	if _lead > LEAD_TIME * (0.6 if absf(diff) > HEAD_LEAD else 1.0):     # a big turn: the body follows sooner
		want = signf(diff) * minf(turn_speed, absf(diff) * 1.6)
	_body_rate = move_toward(_body_rate, want, delta * 2.4)
	var step := _body_rate * delta
	if absf(step) >= absf(diff):
		step = diff
		_body_rate = 0.0
	rotation.y += step


## Hands clasped behind the back (blend w): the upper arm back and in, the
## forearm across the small of the back. Directions in chest space.
func _clasp(s: float, w: float) -> void:
	var up := arm_l if s < 0.0 else arm_r
	var lo := forearm_l if s < 0.0 else forearm_r
	var hd := hand_l if s < 0.0 else hand_r
	var d1 := Vector3(s * 0.08, -1.0, 0.4).normalized()          # shoulder -> elbow
	var d2 := Vector3(-s * 0.86, -0.1, 0.3).normalized()         # elbow -> wrist
	var y := -d1
	var z := -(d2 - d1 * d2.dot(d1)).normalized()                # the forearm bends toward local -Z
	var b := Basis(y.cross(z), y, z).orthonormalized()
	up.transform.basis = up.transform.basis.slerp(b, w)
	lo.rotation = lo.rotation.lerp(Vector3(acos(clampf(d2.dot(d1), -1.0, 1.0)), 0.0, 0.0), w)
	hd.rotation = hd.rotation.lerp(Vector3(-0.15, 0.0, s * 0.35), w)
