class_name SurvivalGame
extends Node3D
## Survival game root (SPEC §7.9). Owner: G.
## Foundation skeleton: proves the stubs fit together (clock-driven light,
## house, player, camera, HUD, fog boundary, ammo-limited handgun, Esc to the
## menu). G replaces it with the full loop.

var state: GameState
var lighting: VoxelLighting
var world: HouseWorld
var player: VoxelPlayer
var camera: VoxelCamera
var hud: GameHud
var boundary: FogBoundary
var time_scale := 1.0
var _cooldown := 0.0


func _ready() -> void:
	state = GameState.new_run()
	lighting = VoxelLighting.new()
	add_child(lighting)
	world = HouseWorld.new()
	world.setup(lighting)
	add_child(world)
	world.build_new()
	player = VoxelPlayer.new()
	add_child(player)
	player.global_position = Vector3(HousePlan.PLAYER_START.x, 0, HousePlan.PLAYER_START.y)
	lighting.night_materials.append(VoxelRig.look_material(true))
	lighting.night_materials.append(VoxelRig.look_material(false))
	camera = VoxelCamera.new()
	camera.target = player
	add_child(camera)
	camera.make_current()
	camera.snap()
	boundary = FogBoundary.new()
	boundary.setup(player, lighting.environment)
	add_child(boundary)
	hud = GameHud.new()
	add_child(hud)
	hud.setup(state)
	Sfx.attach(self)


func _process(delta: float) -> void:
	state.advance(delta * SurvivalTuning.MINUTES_PER_SECOND * time_scale)
	lighting.set_amount(state.night_amount())
	player.set_night(state.night_amount())
	player.speed_scale = state.move_speed_scale()
	world.update_view(player.global_position, camera, delta)
	hud.set_prompt(boundary.prompt_text())


func _physics_process(delta: float) -> void:
	if camera == null:
		return
	var mp := get_viewport().get_mouse_position()
	player.aim_point = world.aim_ray(camera.project_ray_origin(mp), camera.project_ray_normal(mp))
	_cooldown -= delta
	if Input.is_action_pressed("fire") and _cooldown <= 0.0:
		_cooldown = Tuning.FIRE_INTERVAL
		if state.use_ammo():
			var origin := Vector3(player.global_position.x, Tuning.MUZZLE_HEIGHT, player.global_position.z)
			world.shoot(origin, player.aim_point - origin, [player.get_rid()], player.rig.muzzle_global())
			player.on_fired()
		else:
			hud.toast("Out of ammo", "warn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_file(GameLaunch.MENU_SCENE)
	elif event.is_action_pressed("zoom_in"):
		camera.zoom(-1.0)
	elif event.is_action_pressed("zoom_out"):
		camera.zoom(1.0)
