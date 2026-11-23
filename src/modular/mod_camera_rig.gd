class_name ModCameraRig
extends Node3D
## Fixed three-quarter camera shared in spirit with Version A: perspective,
## FOV 40, pitch -56 deg looking north, following the player at 20 m
## (zoom 11..32 m), look target = player at 1 m height.

const FOV := 40.0
const PITCH := -56.0
const DIST_MIN := 11.0
const DIST_MAX := 32.0

var distance := 20.0
var target := Vector3.ZERO
var camera: Camera3D
var _shake := 0.0
var _zoom_goal := 20.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = FOV
	camera.near = 0.3
	camera.far = 160.0
	camera.current = true
	add_child(camera)
	_apply()


func snap(to: Vector3) -> void:
	target = to
	_apply()


func follow(to: Vector3, delta: float) -> void:
	target = target.lerp(to, 1.0 - exp(-delta * 7.0))
	distance = lerpf(distance, _zoom_goal, 1.0 - exp(-delta * 10.0))
	_shake = maxf(_shake - delta * 2.5, 0.0)
	_apply()


func zoom(step: float) -> void:
	_zoom_goal = clampf(_zoom_goal * (1.0 + step), DIST_MIN, DIST_MAX)


func set_distance(d: float) -> void:
	_zoom_goal = clampf(d, DIST_MIN, DIST_MAX)
	distance = _zoom_goal
	_apply()


func nudge(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _apply() -> void:
	if camera == null:
		return
	var p := deg_to_rad(-PITCH)
	var off := Vector3(0, sin(p), cos(p)) * distance
	var jitter := Vector3.ZERO
	if _shake > 0.0:
		jitter = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.08
	camera.global_position = target + off + jitter
	camera.rotation_degrees = Vector3(PITCH, 0, 0)
