class_name VoxelScenarios
extends RefCounted
## Showcase states for screenshots (`--scenario=<name>` on the command line).
## They only arrange the existing scene (place the player, fire real shots,
## spawn enemies, frame the camera); no extra gameplay.
##   overview   - zoomed out over the whole house
##   blasted    - south wall shot open in several places, close zoom
##   enemies    - psychos approaching the house, one bashing the wall
##   shooting   - the player firing at a wall, mid-burst
##   firefight  - night, enemies inside, player shooting

static var _state := {}


static func setup(d: Node, name: String) -> void:
	_state = {"t": 0.0, "shots": 0}
	d.spawner.enabled = false
	match name:
		"overview":
			d.camera.set_distance(26.0)
			d.camera.snap()


static func process(d: Node, name: String, delta: float) -> void:
	_state["t"] += delta
