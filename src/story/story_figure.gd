class_name StoryFigure
extends Node3D
## Exp 012 (S): the watcher of Encounter 2, "The Observer" (ASSIGNMENT §4). He
## uses the look and the rig made for him in Exp 011 (ArchitectRig: stillness,
## the controlled head-first turn, observing with the hands behind his back).
## Not an enemy: no AIEnemy body, not in the roster, no collision, not saved,
## invisible to invasions, noise and the director. He makes no sound himself
## (StoryAudio plays the story's sounds).
##
## "watch": motionless, turned toward Eli. "leave": he turns away in his
## controlled way and walks calmly out into the fog and the dark; the director
## removes him only once he is out of view or deep in the fog, never in plain
## sight.

const WALK := 1.05                     ## m/s, measured

var target: Node3D                     ## Eli
var look_seed := 0
var mode := "watch"                    ## "watch" | "leave"
var exit_at := Vector3.ZERO
var rig: Node3D
var walked := 0.0


func _ready() -> void:
	rig = HumanoidLooks.make_rig(ArchitectIdentity.ID, look_seed)
	rig.name = "Rig"
	add_child(rig)
	rig.set("observe", true)


## Turns away and walks to `to` (calmly, never running).
func leave(to: Vector3) -> void:
	if mode == "leave":
		return
	mode = "leave"
	exit_at = Vector3(to.x, 0.0, to.z)
	rig.set("observe", false)


func plan_pos() -> Vector2:
	return Vector2(global_position.x, global_position.z)


## Where his head is (visibility checks).
func head_point() -> Vector3:
	return global_position + Vector3(0.0, 1.7, 0.0)


func _process(delta: float) -> void:
	if rig == null:
		return
	var moved := false
	if mode == "watch":
		if target != null and is_instance_valid(target):
			var d := target.global_position - global_position
			d.y = 0.0
			if d.length() > 0.3:
				rig.set("face_yaw", atan2(-d.x, -d.z))
	else:
		var d := exit_at - global_position
		d.y = 0.0
		if d.length() > 0.2:
			var yaw := atan2(-d.x, -d.z)
			rig.set("face_yaw", yaw)
			if absf(wrapf(yaw - rig.rotation.y, -PI, PI)) < 0.35:
				var step := minf(WALK * delta, d.length())
				global_position += d.normalized() * step
				walked += step
				moved = true
	rig.set("speed", WALK if moved else 0.0)
	rig.call("animate", delta)
