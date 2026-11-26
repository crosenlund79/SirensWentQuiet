class_name EnemyReaction
extends RefCounted
## Experiment 012 (E), the user's §11: psychos are not zombies. When one
## first sees Eli (a calm one provoked by sight, noise or harm; a hostile one,
## e.g. an invader, the first time it has him in view) it reacts visibly: a
## startled jerk (the rig's hit overlay), it turns to him, then screams
## (the scream pose below, a voice line and a real gameplay noise event,
## NoiseEvent "shout") and runs at him. Per archetype (STYLE):
##   psycho  a variable hesitation (0.35-1.4 s), the scream, then a short
##           sprint at him (x1.35 its speed for 2.5-4 s, then its usual pace)
##   runner  almost immediate (0.05-0.2 s): a shriek as it is already running
##   brute   a heavy, determined approach: a slow turn and a roar (0.55-0.85
##           s), then a slightly quickened stride (x1.12 for 2-3 s)
##   bomber  none: it keeps its own behaviour (bomber_behaviour.gd)
## The speeds, hit points and damage of EnemyDefs are unchanged; the sprint
## factor applies only during the charge (AIEnemy.speed()), so a psycho at
## 1.85 m/s runs at 2.5 m/s for a few seconds (the rig's run gait starts at
## 2.3 m/s), still well under Eli's 4 m/s walk.
##
## Shouts are noise (src/noise/): level SHOUT_LEVEL (high: about 17 m in the
## open, less from inside). Calm enemies that hear one go to look roughly
## where it came from (StragglerMind.hear_shout: the origin is fuzzed by up
## to SHOUT_FUZZ m) and only hunt Eli once they see him themselves.
##
## Audio: plays the first available of SHOUT_SOUNDS ("psycho/shout",
## "psycho/scream", then the existing enemy vocals "enemy/moan"). Never a
## story/* sound. The user's recordings have no shout or scream yet.

const SIGHT := 9.0                ## m: a hostile enemy's first sight of Eli (same storey, a clear line)
const CONE := -0.2                ## cos of the half angle it sees (about 100 degrees)
const LOOK_EVERY := 0.25          ## s between those looks
const SHOUT_LEVEL := 3.0          ## NoiseEvent level of a shout (HIGH)
const SHOUT_SOUNDS := ["psycho/shout", "psycho/scream", "enemy/moan"]
const SHOUT_DB := 4.0
const SCREAM_TIME := 0.9          ## s of the scream pose
const STYLE := {
	"psycho": {"hesitate": Vector2(0.35, 1.4), "jerk": 0.75, "sprint": 1.35, "sprint_time": Vector2(2.5, 4.0), "shout": 1.0},
	"runner": {"hesitate": Vector2(0.05, 0.2), "jerk": 0.35, "sprint": 1.0, "sprint_time": Vector2(0.0, 0.0), "shout": 0.8},
	"brute": {"hesitate": Vector2(0.55, 0.85), "jerk": 0.2, "sprint": 1.12, "sprint_time": Vector2(2.0, 3.0), "shout": 1.0},
}

static var shouts_total := 0      ## shouts in this session (tests, F10)

var phase := ""                   ## "" not yet, "react" (hesitating, screaming), "charge", "done"
var t := 0.0
var hesitate := 0.0
var sprint := 1.0
var sprint_left := 0.0
var shouted := false
var shouts := 0
var reactions := 0
var why := ""                     ## what started the last reaction
var rng := RandomNumberGenerator.new()
var _look_t := 0.0
var _scream := 0.0


func _init(seed := 0) -> void:
	rng.seed = seed


static func applies(kind: String) -> bool:
	return STYLE.has(kind)


func active() -> bool:
	return phase == "react" or phase == "charge"


## AIEnemy.provoke: a calm enemy turned (any reason but the spawn mode).
func on_provoked(e: AIEnemy, reason: String) -> void:
	if reason == "mode" or reason == "":
		return
	start(e, reason, reason.begins_with("hurt"))


## Starts the reaction (once at a time). `hurt`: no hesitation, just the scream.
func start(e: AIEnemy, reason := "saw Eli", hurt := false) -> void:
	if not applies(e.kind) or not e.alive or active():
		return
	var st: Dictionary = STYLE[e.kind]
	phase = "react"
	why = reason
	reactions += 1
	t = 0.0
	shouted = false
	var h: Vector2 = st["hesitate"]
	hesitate = 0.08 if hurt else rng.randf_range(h.x, h.y)
	sprint = float(st["sprint"])
	var span: Vector2 = st["sprint_time"]
	sprint_left = rng.randf_range(span.x, span.y)
	if e.rig != null and not hurt:
		e.rig.stagger = maxf(e.rig.stagger, float(st["jerk"]))      # the startle: a jerk back


## Speed multiplier now (AIEnemy.speed()).
func speed_factor() -> float:
	return sprint if phase == "charge" else 1.0


## Adjusts the brain's result while hostile (AIEnemy._physics_process).
func think(e: AIEnemy, delta: float, r: Dictionary) -> Dictionary:
	_scream = maxf(_scream - delta, 0.0)
	if not applies(e.kind):
		return r
	if phase == "" or phase == "done":
		_look_t -= delta
		if phase == "" and _look_t <= 0.0:
			_look_t = LOOK_EVERY
			if sees_eli(e):
				start(e, "saw Eli")
	match phase:
		"react":
			t += delta
			if not shouted and t >= minf(0.22, hesitate * 0.4):
				shout(e)
			r["move"] = Vector2.ZERO
			r["swing"] = ""
			var p := _player_pos(e)
			var me := e.plan_pos()
			if p != Vector2.INF and p.distance_to(me) > 0.05:
				r["face"] = (p - me).normalized()
			if t >= hesitate:
				phase = "charge" if sprint_left > 0.0 else "done"
		"charge":
			sprint_left -= delta
			if sprint_left <= 0.0:
				phase = "done"
	return r


## The scream: a voice line and a noise event the others hear.
func shout(e: AIEnemy) -> void:
	shouted = true
	if rng.randf() > float(STYLE.get(e.kind, {}).get("shout", 1.0)):
		return                                      # a runner sometimes just goes
	shouts += 1
	shouts_total += 1
	_scream = SCREAM_TIME
	var at := e.global_position + Vector3(0.0, 1.55, 0.0)
	Sfx.play_first(SHOUT_SOUNDS, at, SHOUT_DB + PsychoVoice.occlusion_db(e))
	NoiseEvent.emit(e, at, SHOUT_LEVEL, "shout")


## Eli in view: same storey, within SIGHT m, in front, a clear line on the nav grid.
func sees_eli(e: AIEnemy) -> bool:
	var pl = e.player
	if pl == null or not is_instance_valid(pl) or not (pl is Node3D):
		return false
	var g := (pl as Node3D).global_position
	if absf(g.y - e.floor_y) > 1.5:
		return false
	var me := e.plan_pos()
	var p := Vector2(g.x, g.z)
	var d := me.distance_to(p)
	if d > SIGHT:
		return false
	if d > 1.0 and e.rig != null:
		var fwd := Vector2(-sin(e.rig.rotation.y), -cos(e.rig.rotation.y))
		if fwd.dot((p - me) / d) < CONE:
			return false
	return e.nav == null or e.nav.segment_clear(me, p)


func _player_pos(e: AIEnemy) -> Vector2:
	var pl = e.player
	if pl == null or not is_instance_valid(pl) or not (pl is Node3D):
		return Vector2.INF
	var g := (pl as Node3D).global_position
	return Vector2(g.x, g.z)


## The scream pose after VoxelRig.animate (rotations on top of the frame's pose):
## chest out, head thrown back and shaking, arms flung out, hands clawed.
func pose(e: AIEnemy, _delta: float) -> void:
	if _scream <= 0.0 or not (e.rig is HumanoidRig):
		return
	var rig := e.rig as HumanoidRig
	if rig.torso == null or rig.dead:
		return
	var u := 1.0 - _scream / SCREAM_TIME
	var k := sin(clampf(u, 0.0, 1.0) * PI)
	k = minf(k * 1.6, 1.0)
	var shake := sin(_scream * 47.0) * 0.06 * k
	rig.torso.rotation.x += 0.25 * k
	rig.head.rotation.x += 0.42 * k
	rig.head.rotation.z += shake
	rig.arm_l.rotation += Vector3(-0.35, 0.0, -0.6) * k
	rig.arm_r.rotation += Vector3(-0.35, 0.0, 0.6) * k
	if rig.forearm_l != null:
		rig.forearm_l.rotation.x += 0.7 * k
		rig.forearm_r.rotation.x += 0.7 * k
