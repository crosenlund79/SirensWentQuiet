class_name ArchitectFigure
extends Node3D
## Experiment 011: the developer preview of "the Architect" in the running
## game (F10 > Character > "Show Architect (internal)"). A figure, not an
## enemy: no AIEnemy body, not in the roster, no collision, no sounds, not
## saved, invisible to invasions, noise and the director. He appears a few
## metres from Eli, turned away; he turns to face Eli in his controlled way
## (head first) and observes with his hands behind his back. If Eli moves
## away he follows a few measured steps (at most LEASH metres from where he
## appeared), then stands still again. Remove him with remove() (F10).

const NODE_NAME := "DevArchitectFigure"
const LEASH := 3.0              ## m he may walk from where he appeared
const KEEP := 4.5               ## m he lets Eli get before he follows
const WALK := 1.05              ## m/s, measured

var target: Node3D              ## Eli (the player)
var rig: ArchitectRig
var look_seed := 0
var _home := Vector3.ZERO


## Places the figure under `host` (the game) near `target` (the player); an
## earlier one is removed first. Returns null when there is no player.
static func show_near(host: Node, target: Node3D, seed := 0) -> ArchitectFigure:
	remove(host)
	if host == null or target == null or not target.is_inside_tree():
		return null
	var yaw := _facing(target)
	var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var f := ArchitectFigure.new()
	f.name = NODE_NAME
	f.target = target
	f.look_seed = seed
	host.add_child(f)
	f.global_position = target.global_position + dir * 3.2
	f._home = f.global_position
	f.rig.rotation.y = yaw + PI * 0.5               # side-on to Eli: the turn shows
	return f


## Removes the figure (true if there was one).
static func remove(host: Node) -> bool:
	if host == null:
		return false
	var f := host.get_node_or_null(NODE_NAME)
	if f == null:
		return false
	host.remove_child(f)
	f.queue_free()
	return true


static func find(host: Node) -> ArchitectFigure:
	return host.get_node_or_null(NODE_NAME) as ArchitectFigure if host != null else null


## The direction the player faces (VoxelPlayer turns its rig, not itself).
static func _facing(t: Node3D) -> float:
	var r: Variant = t.get("rig")
	if r is Node3D:
		return (r as Node3D).global_rotation.y
	return t.global_rotation.y


func _ready() -> void:
	rig = HumanoidLooks.make_rig(ArchitectIdentity.ID, look_seed) as ArchitectRig
	rig.name = "Rig"
	add_child(rig)
	rig.observe = true


func _process(delta: float) -> void:
	if rig == null:
		return
	var moved := false
	if target != null and is_instance_valid(target) and target.is_inside_tree():
		var d := target.global_position - global_position
		d.y = 0.0
		rig.face_yaw = atan2(-d.x, -d.z)
		var facing := absf(wrapf(rig.face_yaw - rig.rotation.y, -PI, PI)) < 0.25
		if d.length() > KEEP and facing:
			var step := d.normalized() * WALK * delta
			var next := global_position + step
			if (next - _home).length() <= LEASH:
				global_position = next
				moved = true
	rig.speed = WALK if moved else 0.0
	rig.animate(delta)
