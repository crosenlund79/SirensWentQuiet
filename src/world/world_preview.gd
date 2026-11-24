extends Node3D
## Screenshot and review scenarios for the survival house and build mode (not
## used by the game). They only arrange the real world: place the player, fire
## real shots, build through BuildMode.apply, frame the camera.
##   godot --path . res://src/world/world_preview.tscn -- --scenario=<name> [--night] [--quantum=1|2] [--blast-at=<s>]
## Scenarios: house (default), build, build_bad, built, damaged, repaired, res;
## Experiment 003: materials (stone vs wood walls), iron (plating, reinforced
## door, iron barricade), foundation (a stone pad, a stone wall going up, the
## stone wall ghost), workbench, blast (a blast hole in a wooden and a stone
## wall, the aftermath), blast_fx (the same walls; the blasts go off at
## --blast-at seconds, default 1.6, so a capture just after shows the
## flash, fireball and debris), palette (build mode with the stone wall
## selected and its variant row).
## Experiment 004: exp004 (window boards, a metal front door, the fuse box,
## a voxel-damaged sofa, dining-room rubble).

var lighting: VoxelLighting
var world: HouseWorld
var player: VoxelPlayer
var camera: VoxelCamera
var build: BuildMode
var state: GameState
var scenario := "house"
var night := false
var quantum := -1
var blast_at := 1.6
var _t := 0.0
var _blasts_pending: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scenario="):
			scenario = a.trim_prefix("--scenario=")
		elif a == "--night":
			night = true
		elif a.begins_with("--quantum="):
			quantum = int(a.trim_prefix("--quantum="))
		elif a.begins_with("--blast-at="):
			blast_at = float(a.trim_prefix("--blast-at="))
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
		"exp004":
			build.select_id("window_boards")
			for x in [6.5, 7.5, 12.5]:
				build.apply(Vector2(x, 9.0))
			build.select_id("upgrade")
			build.apply(Vector2(4.5, 9.0))
			build.apply(Vector2(4.5, 9.0))
			world.furniture.destroy("dining_table")
			world.furniture.destroy("dining_chair_3")
			world.furniture.destroy("boxes")
			for k in 4:
				world.enemy_strike(Vector3(4.5, 0, 8.3), Vector2(4.4, 7.1))
			_place(Vector2(10.6, 7.6), Vector3(10.0, 1.0, 6.5), 17.0)
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
		"materials":
			_stone_and_wood()
			_place(Vector2(0.4, 12.6), Vector3(0.0, 1.0, 11.0), 11.0)
		"iron":
			world.build_walls(_segs(-3, 0))
			for s in _segs(-3, -1):
				world.upgrade_section(s)
			world.place_object("barricade", Vector2(0.5, 11.0), 2, true, "iron")
			world.place_object("barricade", Vector2(1.5, 11.0), 2, true, "wood")
			world.place_object("barricade", Vector2(2.5, 11.0), 2, true, "iron")
			var front: WorldObject = world.object_at(Vector2(4.5, 9.0))
			var rot := front.rot
			world.remove_object(front)
			world.place_object("door", Vector2(4.5, 9.0), rot, false, "iron")
			for s in [Vector3i(0, 9, 5), Vector3i(0, 9, 3)]:
				world.upgrade_section(s)
			_place(Vector2(1.4, 12.6), Vector3(1.5, 1.0, 10.0), 12.0)
		"foundation":
			for line in [10, 11, 12]:
				world.build_foundation(_segs(-3, 1, line))
			world.build_walls(_segs(-3, -1), "stone")
			build.set_active(true)
			build.select_id("stone_wall")
			build.debug_drag_from = Vector2(-1.0, 11.0)
			build.debug_pointer = Vector2(0.9, 11.05)
			_place(Vector2(-0.6, 12.9), Vector3(-1.0, 0.5, 10.8), 11.0)
		"workbench":
			world.place_object("workbench", Vector2(11.0, 10.25), 2)
			world.place_object("crate", Vector2(12.5, 10.25), 2)
			world.place_object("rain_collector", Vector2(9.25, 10.25), 2)
			_place(Vector2(11.0, 11.4), Vector3(11.0, 0.6, 10.25), 10.0)
		"blast", "blast_fx":
			_stone_and_wood()
			var shots := [[Vector3(-1.5, 1.0, 11.55), 1.6, 24.0], [Vector3(2.5, 1.0, 11.55), 1.6, 24.0]]
			if scenario == "blast":
				for b in shots:
					world.explode(b[0], b[1], b[2])
			else:
				_blasts_pending = shots
			_place(Vector2(0.4, 13.0), Vector3(0.5, 1.0, 11.0), 12.0)
		"palette":
			for line in [10, 11, 12]:
				world.build_foundation(_segs(-3, 1, line))
			world.build_walls(_segs(-3, -2), "stone")
			build.set_active(true)
			build.select_id("stone_wall")
			build.debug_pointer = Vector2(-1.5, 11.05)
			_place(Vector2(-1.0, 12.6), Vector3(-1.5, 0.5, 10.8), 11.0)


## Segments x in [from, to) on plan line y = `line` (axis 0).
func _segs(from: int, to: int, line := 11) -> Array:
	var out := []
	for x in range(from, to):
		out.append(Vector3i(0, line, x))
	return out


## A 3 m stone wall on a foundation (x -3..0) beside a 3 m wooden wall
## (x 1..4) on y = 11, a metre apart.
func _stone_and_wood() -> void:
	world.build_foundation(_segs(-3, 0))
	world.build_walls(_segs(-3, 0), "stone")
	world.build_walls(_segs(1, 4), "wood")


func _process(delta: float) -> void:
	_t += delta
	if not _blasts_pending.is_empty() and _t >= blast_at:
		for b in _blasts_pending:
			world.explode(b[0], b[1], b[2])
		_blasts_pending.clear()
	player.set_night(lighting.night_amount)
	world.update_view(player.global_position, camera, delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("zoom_in"):
		camera.zoom(-1.0)
	elif event.is_action_pressed("zoom_out"):
		camera.zoom(1.0)
