extends Node3D
## Screenshot and review scenarios for the survival house and build mode (not
## used by the game). They only arrange the real world: place the player, fire
## real shots, build through BuildMode.apply, frame the camera.
##   godot --path . res://src/world/world_preview.tscn -- --scenario=<name> [--night] [--quantum=1|2]
## Scenarios: house (default), build, build_bad, built, damaged, repaired, res.

var lighting: VoxelLighting
var world: HouseWorld
var player: VoxelPlayer
var camera: VoxelCamera
var build: BuildMode
var state: GameState
var scenario := "house"
var night := false
var quantum := -1


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scenario="):
			scenario = a.trim_prefix("--scenario=")
		elif a == "--night":
			night = true
		elif a.begins_with("--quantum="):
			quantum = int(a.trim_prefix("--quantum="))
	Sfx.attach(self)
	lighting = VoxelLighting.new()
	add_child(lighting)
	world = HouseWorld.new()
	world.setup(lighting)
	if quantum > 0:
		world.damage_quantum = quantum
	add_child(world)
	world.build_new()
	player = VoxelPlayer.new()
	player.name = "Player"
	add_child(player)
	player.input_enabled = false
	lighting.night_materials.append(VoxelRig.look_material(true))
	lighting.night_materials.append(VoxelRig.look_material(false))
	camera = VoxelCamera.new()
	camera.target = player
	add_child(camera)
	camera.make_current()
	state = GameState.new_run(3)
	state.cheats["unlimited"] = true
	build = BuildMode.new()
	build.setup(world, state, camera, player)
	add_child(build)
	_scenario()
	world.chunks.flush(100000.0)     # every dirty chunk meshed before the first frame
	camera.snap()
	lighting.set_amount(1.0 if night else 0.0)
	player.set_night(1.0 if night else 0.0)


func _place(p: Vector2, aim: Vector3, dist: float) -> void:
	player.global_position = Vector3(p.x, 0, p.y)
	player.aim_point = aim
	var to := aim - player.global_position
	player.rig.rotation.y = atan2(-to.x, -to.z)
	camera.set_distance(dist)


func _shoot(from: Vector2, targets: Array) -> void:
	var o := Vector3(from.x, Tuning.MUZZLE_HEIGHT, from.y)
	for t in targets:
		world.shoot(o, (t as Vector3) - o, [])


func _hole_pattern(from: Vector2, at: Vector2) -> void:
	var pattern := [Vector2(-0.3, 0.3), Vector2(0.0, 0.3), Vector2(0.3, 0.3), Vector2(-0.3, 0.75), Vector2(0.0, 0.75), Vector2(0.3, 0.75),
		Vector2(-0.3, 1.2), Vector2(0.0, 1.2), Vector2(0.3, 1.2), Vector2(-0.3, 1.6), Vector2(0.0, 1.6), Vector2(0.3, 1.6)]
	var t := []
	for k in pattern:
		t.append(Vector3(at.x + k.x, k.y, at.y))
	_shoot(from, t)


func _scenario() -> void:
	match scenario:
		"house":
			_place(Vector2(6.0, 6.9), Vector3(9.0, 1.0, 2.0), 23.0)
		"build":
			build.set_active(true)
			build.select_id("wall")
			build.debug_drag_from = Vector2(-2.2, 11.0)
			build.debug_pointer = Vector2(2.8, 11.1)
			_place(Vector2(3.4, 9.9), Vector3(0.0, 1.0, 11.0), 15.0)
		"build_bad":
			build.set_active(true)
			build.select_id("barricade")
			build.debug_pointer = Vector2(2.5, 4.0)
			_place(Vector2(3.0, 5.9), Vector3(2.5, 1.0, 4.0), 13.0)
		"built":
			build.select_id("wall")
			build.apply(Vector2(3.8, 11.05), Vector2(-1.8, 11.0))
			build.apply(Vector2(-2.0, 8.2), Vector2(-2.05, 10.8))
			build.select_id("door")
			build.apply(Vector2(0.5, 11.0))
			build.select_id("barricade")
			build.apply(Vector2(4.5, 11.0))
			build.select_id("crate")
			build.apply(Vector2(10.5, 10.25))
			build.select_id("rain_collector")
			build.apply(Vector2(7.25, 9.75))
			build.select_id("upgrade")
			build.apply(Vector2(9.5, 9.1))
			build.apply(Vector2(10.5, 9.1))
			_place(Vector2(3.0, 12.2), Vector3(3.0, 1.0, 9.0), 17.0)
		"damaged", "repaired":
			_hole_pattern(Vector2(8.6, 10.8), Vector2(8.6, 9.0))
			_shoot(Vector2(10.6, 10.6), [Vector3(10.4, 1.5, 9.0), Vector3(10.9, 1.1, 9.0), Vector3(11.0, 1.9, 9.0)])
			_shoot(Vector2(6.8, 10.8), [Vector3(6.9, 1.6, 9.0)])
			if scenario == "repaired":
				build.select_id("repair")
				for x in [6.5, 7.5, 8.5, 9.5, 10.5, 11.5]:
					build.apply(Vector2(x, 9.05))
			_place(Vector2(8.8, 11.6), Vector3(8.6, 1.2, 9.0), 12.0)
		"res":
			_hole_pattern(Vector2(8.6, 10.8), Vector2(8.6, 9.0))
			_shoot(Vector2(10.6, 10.6), [Vector3(10.4, 1.5, 9.0), Vector3(10.9, 1.1, 9.0), Vector3(11.0, 1.9, 9.0)])
			_shoot(Vector2(6.8, 10.8), [Vector3(6.9, 1.6, 9.0), Vector3(6.4, 0.9, 9.0)])
			_place(Vector2(8.8, 11.6), Vector3(8.6, 1.2, 9.0), 11.0)


func _process(delta: float) -> void:
	player.set_night(lighting.night_amount)
	world.update_view(player.global_position, camera, delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("zoom_in"):
		camera.zoom(-1.0)
	elif event.is_action_pressed("zoom_out"):
		camera.zoom(1.0)
