class_name VoxelCamera
extends Camera3D
## Angled follow camera shared spec (A and B): FOV 40, pitch -56 deg looking
## north, distance 20 m (zoom 11-32) to the player at 1 m height.
## Refinement 01: the game can turn it around the target in quarter turns
## (`turn(dir)`, a short smooth swing; `yaw` 0 = looking north, as before).

const PITCH_DEG := -56.0
const LOOK_HEIGHT := 1.0
const ZOOM_MIN := 11.0
const ZOOM_MAX := 32.0
const ZOOM_STEP := 1.6
const TURN_RATE := 11.0            ## Refinement 01: how fast a quarter turn settles (1/s)

var target: Node3D
var distance := 20.0
var _goal_distance := 20.0
var _focus := Vector3.ZERO
var _shake := 0.0
var _shake_t := 0.0
var yaw := 0.0                     ## Refinement 01: current orbit angle (rad); 0 = from the south, looking north
var turns := 0                     ## the goal in quarter turns, 0..3 (1 = from the east, looking west)
var _goal_yaw := 0.0
## Exp 005 (V): metres the look point sits above the target (build mode
## looking at another storey: the camera lifts to that level).
var lift := 0.0


func _ready() -> void:
	fov = 40.0
	near = 0.5
	far = 120.0
	rotation = Vector3(deg_to_rad(PITCH_DEG), yaw, 0.0)
	if target != null:
		_focus = target.global_position
	_place(0.0)


func zoom(steps: float) -> void:
	_goal_distance = clampf(_goal_distance + steps * ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)


func set_distance(d: float) -> void:
	distance = clampf(d, ZOOM_MIN, ZOOM_MAX)
	_goal_distance = distance


## Refinement 01: a quarter turn around the target (+1 right / -1 left), smooth.
func turn(dir: int) -> void:
	turns = posmod(turns + dir, 4)
	_goal_yaw += float(dir) * PI * 0.5


## Refinement 01: sets the quarter turns at once (a loaded run).
func set_turns(n: int) -> void:
	turns = posmod(n, 4)
	_goal_yaw = float(turns) * PI * 0.5
	yaw = _goal_yaw
	_place(0.0)


func goal_yaw() -> float:
	return _goal_yaw


func nudge(amount: float) -> void:
	_shake = maxf(_shake, amount)


func snap() -> void:
	if target != null:
		_focus = target.global_position + Vector3(0.0, lift, 0.0)
	distance = _goal_distance
	yaw = _goal_yaw
	_place(0.0)


## Unit vector from the look point toward the camera.
func back_dir() -> Vector3:
	var p := deg_to_rad(-PITCH_DEG)
	return Vector3(sin(yaw) * cos(p), sin(p), cos(yaw) * cos(p))


func _process(delta: float) -> void:
	if target != null:
		_focus = _focus.lerp(target.global_position + Vector3(0.0, lift, 0.0), 1.0 - exp(-delta * 6.0))
	distance = lerpf(distance, _goal_distance, 1.0 - exp(-delta * 8.0))
	yaw = _goal_yaw if absf(_goal_yaw - yaw) < 0.001 else lerpf(yaw, _goal_yaw, 1.0 - exp(-delta * TURN_RATE))
	_place(delta)


func _place(delta: float) -> void:
	var look := _focus + Vector3(0.0, LOOK_HEIGHT, 0.0)
	var off := Vector3.ZERO
	if _shake > 0.001:
		_shake_t += delta * 40.0
		off = Vector3(sin(_shake_t * 1.3), 0.0, cos(_shake_t * 1.7)) * _shake * 0.06
		_shake = maxf(_shake - delta * 4.0, 0.0)
	rotation = Vector3(deg_to_rad(PITCH_DEG), yaw, 0.0)
	global_position = look + back_dir() * distance + off
