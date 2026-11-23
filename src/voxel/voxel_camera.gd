class_name VoxelCamera
extends Camera3D
## Angled follow camera shared spec (A and B): FOV 40, pitch -56 deg looking
## north, distance 20 m (zoom 11-32) to the player at 1 m height.

const PITCH_DEG := -56.0
const LOOK_HEIGHT := 1.0
const ZOOM_MIN := 11.0
const ZOOM_MAX := 32.0
const ZOOM_STEP := 1.6

var target: Node3D
var distance := 20.0
var _goal_distance := 20.0
var _focus := Vector3.ZERO
var _shake := 0.0
var _shake_t := 0.0


func _ready() -> void:
	fov = 40.0
	near = 0.5
	far = 120.0
	rotation_degrees = Vector3(PITCH_DEG, 0.0, 0.0)
	if target != null:
		_focus = target.global_position
	_place(0.0)


func zoom(steps: float) -> void:
	_goal_distance = clampf(_goal_distance + steps * ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)


func set_distance(d: float) -> void:
	distance = clampf(d, ZOOM_MIN, ZOOM_MAX)
	_goal_distance = distance


func nudge(amount: float) -> void:
	_shake = maxf(_shake, amount)


func snap() -> void:
	if target != null:
		_focus = target.global_position
	distance = _goal_distance
	_place(0.0)


## Unit vector from the look point toward the camera.
func back_dir() -> Vector3:
	var p := deg_to_rad(-PITCH_DEG)
	return Vector3(0.0, sin(p), cos(p))


func _process(delta: float) -> void:
	if target != null:
		_focus = _focus.lerp(target.global_position, 1.0 - exp(-delta * 6.0))
	distance = lerpf(distance, _goal_distance, 1.0 - exp(-delta * 8.0))
	_place(delta)


func _place(delta: float) -> void:
	var look := _focus + Vector3(0.0, LOOK_HEIGHT, 0.0)
	var off := Vector3.ZERO
	if _shake > 0.001:
		_shake_t += delta * 40.0
		off = Vector3(sin(_shake_t * 1.3), 0.0, cos(_shake_t * 1.7)) * _shake * 0.06
		_shake = maxf(_shake - delta * 4.0, 0.0)
	global_position = look + back_dir() * distance + off
