class_name FogBoundary
extends Node3D
## The lot edge and its fog bank (SPEC §7.7). Owner: E.
## Foundation stub: invisible walls on layer 6 (player only) and the prompt.

signal exit_requested(at: Vector3)

const LOT := Rect2(-4.5, -3.5, 23.0, 16.0)
const PROMPT_DISTANCE := 0.7

var player: Node3D
var environment: Environment


func setup(p: Node3D, env: Environment) -> void:
	player = p
	environment = env


func _ready() -> void:
	var t := 1.0
	for r in [Rect2(LOT.position.x - t, LOT.position.y - t, LOT.size.x + 2 * t, t),
			Rect2(LOT.position.x - t, LOT.end.y, LOT.size.x + 2 * t, t),
			Rect2(LOT.position.x - t, LOT.position.y, t, LOT.size.y),
			Rect2(LOT.end.x, LOT.position.y, t, LOT.size.y)]:
		var body := StaticBody3D.new()
		body.collision_layer = 1 << 5
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(r.size.x, 3.0, r.size.y)
		cs.shape = box
		body.add_child(cs)
		body.position = Vector3(r.get_center().x, 1.5, r.get_center().y)
		add_child(body)


func set_night_amount(_t: float) -> void:
	pass


func _edge_distance(p: Vector2) -> float:
	return minf(minf(p.x - LOT.position.x, LOT.end.x - p.x), minf(p.y - LOT.position.y, LOT.end.y - p.y))


func prompt_text() -> String:
	if player == null:
		return ""
	var p := Vector2(player.global_position.x, player.global_position.z)
	return "[E] Head into the fog" if _edge_distance(p) < PROMPT_DISTANCE else ""


func request_exit() -> void:
	if prompt_text() != "":
		exit_requested.emit(player.global_position)


func return_point(at: Vector3) -> Vector3:
	var p := Vector2(at.x, at.z)
	var c := LOT.grow(-1.5)
	p = Vector2(clampf(p.x, c.position.x, c.end.x), clampf(p.y, c.position.y, c.end.y))
	return Vector3(p.x, 0, p.y)
