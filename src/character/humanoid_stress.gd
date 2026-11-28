class_name HumanoidStress
extends Node
## Experiment 012 (§29), F10 > Debug > Stress humanoids: spawns `count`
## people of every kind around Eli in the running game, then for `seconds`
## keeps throwing states at them on top of their own AI (attacks, hits
## during attacks, sharp turns, deaths mid-animation) and measures every
## rig every physics frame with RigIntegrity. The result is in `result`
## and the `finished` signal (the dev menu shows it).

signal finished(text: String)

const KINDS := ["psycho", "runner", "brute", "bomber"]

var game: Node
var count := 3
var seconds := 8.0
var result := {}
var _enemies: Array = []
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _worst := {"sep": 0.0, "bone": "", "scale": 0.0, "nan": false}
var _bad := 0
var _frames := 0
var _killed := 0


## Starts a stress run in `g` (a SurvivalGame); returns the node.
static func start(g: Node, per_kind := 3, secs := 8.0) -> HumanoidStress:
	var s := HumanoidStress.new()
	s.name = "HumanoidStress"
	s.game = g
	s.count = per_kind
	s.seconds = secs
	g.add_child(s)
	return s


func _ready() -> void:
	process_physics_priority = 100            # after the enemies' own frame
	_rng.seed = 1201
	var roster: Node = game.get("roster")
	var p: Variant = game.get("player")
	if roster == null or not (p is Node3D):
		_finish("No roster or player here")
		return
	var pp := Vector2((p as Node3D).global_position.x, (p as Node3D).global_position.z)
	var n := 0
	for k in KINDS:
		for i in count:
			var a := TAU * float(n) / float(KINDS.size() * count)
			var at := pp + Vector2(cos(a), sin(a)) * (3.0 + 1.5 * float(n % 3))
			var e: Node = roster.spawn_type(k, at, {"mode": "hidden", "appearance": _rng.randi() % 1000})
			if e is AIEnemy:
				_enemies.append(e)
			n += 1


func _physics_process(delta: float) -> void:
	if not result.is_empty():
		return
	_t += delta
	_frames += 1
	for e in _enemies:
		if not is_instance_valid(e):
			continue
		var en := e as AIEnemy
		var r := en.rig as HumanoidRig
		if r == null:
			continue
		if en.alive:
			if _rng.randf() < 0.03 and r.swing <= 0.0:
				r.swing = 1.0
			if _rng.randf() < 0.03:
				en.take_hit(Vector3(_rng.randf_range(-1, 1), 0.0, _rng.randf_range(-1, 1)).normalized())
			if _rng.randf() < 0.02:
				en.set_facing(en.rig.rotation.y + _rng.randf_range(-2.5, 2.5))
			if _t > seconds * 0.4 and _rng.randf() < 0.01 and en.kind != "bomber":
				en.take_damage(999, Vector3(_rng.randf_range(-1, 1), 0.0, 1.0).normalized())
				_killed += 1
		var m := RigIntegrity.measure(r)
		if not RigIntegrity.intact(m):
			_bad += 1
		if float(m["sep"]) >= float(_worst["sep"]):
			_worst["sep"] = m["sep"]
			_worst["bone"] = m["bone"]
		_worst["scale"] = maxf(float(_worst["scale"]), float(m["scale"]))
		_worst["nan"] = bool(_worst["nan"]) or bool(m["nan"])
	if _t >= seconds:
		_finish("")


func _finish(err: String) -> void:
	result = {"frames": _frames, "people": _enemies.size(), "killed": _killed, "bad": _bad, "worst": _worst, "error": err}
	var text := err
	if err == "":
		text = "Stress: %d people, %d frames, %d killed mid-animation: %s (worst offset %.3f m at %s, scale %.3f%s)" % [
			_enemies.size(), _frames, _killed, "intact" if _bad == 0 else "%d broken rig frames" % _bad,
			float(_worst["sep"]), str(_worst["bone"]), float(_worst["scale"]), ", NaN!" if _worst["nan"] else ""]
	finished.emit(text)
	queue_free()
