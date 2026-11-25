extends Node3D
## Experiment 007 (P): a small harness for the POIs outside the full game
## (agent T's site mode lives in SurvivalGame): the game-like members the
## POI code reads (state, lighting, world, player, camera, roster, combat,
## poi, travel, _modal, toast, _set_modal, _advance_clock) around
## PoiSite.build_world + PoiSite.make_helper. Tests use it; it also runs:
##   godot --path . res://src/poi/poi_preview.tscn -- --poi=library [--car] [--hour=22] [--player-at=x,y]
## WASD move, mouse aim, E use, LMB shoot (handgun), F1 restore loot, F2
## straggler, F3 reveal containers, Tab state, Esc quit.

const Roster := preload("res://src/game/enemy_roster.gd")
const Finder := preload("res://src/game/interaction_finder.gd")

var poi_id := "convenience"
var by_car := false
var preset_state: GameState = null     ## tests: continue a run (e.g. a reloaded save)
var hour := 13.0
var player_at := Vector2.INF
var state: GameState
var lighting: VoxelLighting
var world: HouseWorld
var player: VoxelPlayer
var camera: VoxelCamera
var roster: Node3D
var combat: Node = null
var travel: Node = null
var poi: Node
var hud: GameHud
var toasts: Array[String] = []
var left := false
var _modal := ""
var _focus: Node3D


## Tests set these before adding the node (else the command line decides).
func configure(id: String, car := false, seed := 7007) -> void:
	poi_id = id
	by_car = car
	set_meta("seed", seed)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--poi="):
			poi_id = a.trim_prefix("--poi=")
		elif a == "--car":
			by_car = true
		elif a.begins_with("--hour="):
			hour = float(a.trim_prefix("--hour="))
		elif a.begins_with("--player-at="):
			var xy := a.trim_prefix("--player-at=").split(",")
			if xy.size() == 2:
				player_at = Vector2(float(xy[0]), float(xy[1]))
	Sfx.attach(self)
	state = preset_state
	if state == null:
		state = GameState.new_run(int(get_meta("seed", 7007)))
		state.total_minutes = floorf(state.total_minutes / 1440.0) * 1440.0 + hour * 60.0
	lighting = VoxelLighting.new()
	lighting.name = "Lighting"
	add_child(lighting)
	if lighting.has_method("set_northern"):
		lighting.set_northern(true)
	world = PoiSite.build_world(poi_id, self, 1 if by_car else 0)
	player = VoxelPlayer.new()
	player.name = "Player"
	add_child(player)
	lighting.night_materials.append(VoxelRig.look_material(true))
	lighting.night_materials.append(VoxelRig.look_material(false))
	camera = VoxelCamera.new()
	camera.target = player
	add_child(camera)
	camera.make_current()
	roster = Roster.new()
	roster.name = "Enemies"
	roster.setup(world, player, 7)
	add_child(roster)
	roster.player_swing.connect(func(_e): state.damage(state.enemy_damage(), "psycho"))
	roster.wall_swing.connect(func(e, t): world.enemy_strike(e.global_position, t))
	hud = GameHud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.setup(state)
	poi = PoiSite.make_helper(self)
	poi.leave_requested.connect(func(_id): left = true)
	var at: Vector2 = player_at if player_at != Vector2.INF else (world as PoiWorld).entry_point()
	player.global_position = Vector3(at.x, 0, at.y)
	player.rig.rotation.y = 0.0
	player.aim_point = player.global_position + Vector3(0, 1.1, -3)
	lighting.set_amount(state.night_amount())
	player.set_night(state.night_amount())
	world.chunks.flush(100000.0)
	camera.snap()
	world.update_view(player.global_position, camera, 5.0)


func _process(delta: float) -> void:
	if world == null:
		return
	if _modal == "":
		state.advance(delta * SurvivalTuning.MINUTES_PER_SECOND)
	lighting.set_amount(state.night_amount())
	if is_inside_tree() and get_viewport().get_camera_3d() == camera:
		var mp := get_viewport().get_mouse_position()
		player.aim_point = world.aim_ray(camera.project_ray_origin(mp), camera.project_ray_normal(mp))
	world.update_view(player.global_position, camera, delta)
	_focus = Finder.nearest(world.interactables(), player.plan_pos()) if _modal == "" else null
	hud.set_prompt(str(_focus.interact_prompt()) if _focus != null else "")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and _modal == "":
		interact()
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_F1:
				toast(poi.dev_restore_loot())
			KEY_F2:
				toast(poi.dev_spawn_straggler())
			KEY_F3:
				toast(poi.dev_reveal())
			KEY_TAB:
				toast(poi.dev_state_text())
			KEY_ESCAPE:
				if _modal == "":
					get_tree().quit()
	if event.is_action_pressed("fire") and _modal == "":
		var o := player.global_position + Vector3(0, 1.3, 0)
		world.shoot(o, player.aim_point - o, [player.get_rid()])
		if poi.has_method("hear"):
			poi.hear(player.plan_pos(), 4.0)


func interact() -> void:
	_focus = Finder.nearest(world.interactables(), player.plan_pos())
	if _focus != null:
		_focus.interact(self)


# --- what the POI code calls on the game ---------------------------------------------------

func toast(text: String, kind := "info") -> void:
	toasts.append(text)
	if hud != null:
		hud.toast(text, kind)


func _set_modal(m: String, paused: bool) -> void:
	_modal = m
	if is_inside_tree():
		get_tree().paused = paused


func _advance_clock(minutes: float) -> void:
	state.advance(minutes)


func is_home() -> bool:
	return false


func site_id() -> String:
	return poi_id
