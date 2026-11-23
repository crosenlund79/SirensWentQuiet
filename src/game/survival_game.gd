class_name SurvivalGame
extends Node3D
## Survival game root (SPEC §7.9). Owner: G.
##
## Wires one run together and drives the loop: wake → assess → scavenge →
## build → survive the night → sleep → repeat. The modules own the mechanics
## (GameState, HouseWorld, BuildMode, FogBoundary/ExpeditionScreen, the UI,
## Sfx/Ambience); small helpers next to this file own the pacing (invasion
## director, enemy roster, footsteps, interaction finder, save composition,
## UI ownership, input forwarding, the sleep fade). This file decides *when*
## things happen: launch, the clock and its events, firing, interactions, the
## sleep / expedition / pause / death flows, saving and autosave, the developer
## menu API and a debug API for tests and the playtest.
## See docs/experiment-002/game.md.

signal sleep_finished(plan: Dictionary)
signal invasion_started
signal invasion_ended(reason: String)
signal autosaved(reason: String)

const Director := preload("res://src/game/invasion_director.gd")
const Roster := preload("res://src/game/enemy_roster.gd")
const Footsteps := preload("res://src/game/footsteps.gd")
const Finder := preload("res://src/game/interaction_finder.gd")
const RunSave := preload("res://src/game/run_save.gd")
const GameUI := preload("res://src/game/game_ui.gd")
const GameInput := preload("res://src/game/game_input.gd")

const DAY_MIN := 1440.0
const WAKE_OFFSET := Vector3(0, 0, 1.45)       ## from the bed to where you wake
const NOTICE_PREFIX := "The save could not be loaded: "
const DRY_FIRE_INTERVAL := 0.45
const NUDGE_NEAR := 6.0                        ## m: wall bashes this close shake the camera

var state: GameState
var lighting: VoxelLighting
var world: HouseWorld
var player: VoxelPlayer
var camera: VoxelCamera
var listener: AudioListener3D
var boundary: FogBoundary
var build: BuildMode
var ambience: Ambience
var roster: Node3D                     ## enemy_roster.gd
var director := Director.new()
var ui: Node                           ## game_ui.gd
var hud: GameHud
var time_scale := 1.0

# Set before the node enters the tree (tests, tools).
var stay_in_scene := false             ## record scene changes instead of doing them
var skip_intro := false
var aim_with_mouse := true
var fade_time := 0.6
var death_delay := 1.4

# Debug / test records.
var left_to := ""
var last_toast := ""
var autosave_log: Array[String] = []
var last_sleep := {}
var last_expedition := {}
var shots_fired := 0

var _ok := false
var _modal := ""                       ## "" | intro | pause | settings | inventory | sleep | sleeping | expedition | death
var _loaded := {}
var _trigger := false
var _fire_cd := 0.0
var _dry_cd := 0.0
var _ammo_toast_cd := 0.0
var _steps := Footsteps.new()
var _focus: Node3D
var _prompt := ""
var _banner := ""
var _cursor := ""
var _night := -1.0
var _exit_at := Vector3.ZERO
var _stragglers_done := {}             ## night (day number) -> true
var _death_handled := false
var _start_hour := -1.0


# --- launch ----------------------------------------------------------------------------

func _ready() -> void:
	_read_user_args()
	Sfx.attach(self)
	Sfx.music("")
	lighting = VoxelLighting.new()
	lighting.name = "Lighting"
	add_child(lighting)
	world = HouseWorld.new()
	world.name = "World"
	world.setup(lighting)
	add_child(world)
	var err := _launch()
	if err != "":
		_fail(err)
		return
	_assemble()
	_ok = true
	if GameLaunch.mode == "continue":
		_begin_continue()
	else:
		_begin_new()
	if _start_hour >= 0.0:
		dev_skip_to(_start_hour)


func _read_user_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--skip-intro":
			skip_intro = true
		elif a.begins_with("--save-path="):
			SaveGame.path_override = a.trim_prefix("--save-path=")
		elif a.begins_with("--hour="):
			_start_hour = float(a.trim_prefix("--hour="))
		elif a.begins_with("--seed="):
			GameLaunch.seed = int(a.trim_prefix("--seed="))


## Creates or loads the state and the house. Returns "" or a readable error.
func _launch() -> String:
	if GameLaunch.mode != "continue":
		state = GameState.new_run(GameLaunch.seed)
		world.build_new()
		return ""
	var r: Dictionary = SaveGame.read()
	if not r.get("ok", false):
		return str(r.get("error", "unknown error"))
	var p: Dictionary = RunSave.parse(r.get("data", {}))
	if not p["ok"]:
		return p["error"]
	state = p["state"]
	var wd: Dictionary = p["world"]
	if wd.is_empty():
		# Only a save written before HouseWorld had persistence has no house data.
		push_warning("SurvivalGame: the save has no house data; using the pristine house")
		world.build_new()
	elif not world.load_data(wd):
		return "the house could not be restored."
	_loaded = p
	return ""


func _fail(err: String) -> void:
	GameLaunch.notice = NOTICE_PREFIX + err
	push_warning("SurvivalGame: " + GameLaunch.notice)
	_leave_to(GameLaunch.MENU_SCENE)


func _assemble() -> void:
	var seed := int(state.run.get("seed", 0))
	player = VoxelPlayer.new()
	player.name = "Player"
	add_child(player)
	lighting.night_materials.append(VoxelRig.look_material(true))
	lighting.night_materials.append(VoxelRig.look_material(false))
	camera = VoxelCamera.new()
	camera.target = player
	add_child(camera)
	camera.make_current()
	listener = AudioListener3D.new()
	add_child(listener)
	listener.make_current()
	boundary = FogBoundary.new()
	boundary.name = "FogBoundary"
	boundary.setup(player, lighting.environment)
	add_child(boundary)
	boundary.exit_requested.connect(_on_exit_requested)
	roster = Roster.new()
	roster.name = "Enemies"
	roster.setup(world, player, seed)
	add_child(roster)
	roster.wall_swing.connect(_on_wall_swing)
	roster.player_swing.connect(_on_player_swing)
	build = BuildMode.new()
	build.name = "Build"
	build.setup(world, state, camera, player)
	add_child(build)
	build.message.connect(_on_build_message)
	build.changed.connect(_sync_build_mode)
	ambience = Ambience.new()
	ambience.name = "Ambience"
	add_child(ambience)
	ui = GameUI.new()
	ui.name = "UI"
	add_child(ui)
	ui.build(state, self, GameLaunch.mode != "continue" and not skip_intro)
	hud = ui.hud
	ui.pause_menu.resume_requested.connect(_resume)
	ui.pause_menu.save_requested.connect(_on_save_requested)
	ui.pause_menu.main_menu_requested.connect(request_main_menu)
	if ui.pause_menu.has_signal("settings_requested"):
		ui.pause_menu.connect("settings_requested", _open_settings)
	ui.settings.closed.connect(_on_settings_closed)
	ui.inventory.closed.connect(_on_inventory_closed)
	ui.sleep_dialog.sleep_chosen.connect(_on_sleep_chosen)
	ui.sleep_dialog.closed.connect(_on_sleep_closed)
	ui.death_screen.main_menu_requested.connect(request_main_menu)
	ui.expedition.finished.connect(_on_expedition_finished)
	ui.expedition.cancelled.connect(_on_expedition_cancelled)
	var input := GameInput.new()
	input.name = "Input"
	input.game = self
	add_child(input)
	world.structure_changed.connect(_on_structure_changed)
	world.object_destroyed.connect(_on_object_destroyed)
	state.died.connect(_on_died)
	_on_structure_changed()


func _begin_new() -> void:
	_place_player(world.bed_position() + WAKE_OFFSET, PI)
	if ui.intro == null:
		_on_intro_done()
		return
	_set_modal("intro", true)
	ui.intro.done.connect(_on_intro_done, CONNECT_ONE_SHOT)
	ui.intro.play()


## The moment a New Game replaces the previous run (the menu asked first).
func _on_intro_done() -> void:
	if _modal == "intro":
		_set_modal("", false)
	_update_cursor()
	toast("Day %d. Check your supplies." % state.day())
	_autosave("new_run")


func _begin_continue() -> void:
	var pos = _loaded.get("player_pos")
	_place_player(pos if pos != null else world.bed_position() + WAKE_OFFSET, float(_loaded.get("yaw", 0.0)))
	var g: Dictionary = _loaded.get("game", {})
	time_scale = clampf(float(g.get("time_scale", 1.0)), 0.0, 600.0)
	var d = g.get("director", {})
	if typeof(d) == TYPE_DICTIONARY:
		for n in d.get("stragglers_done", []):
			_stragglers_done[int(n)] = true
	_update_cursor()
	if state.run.get("invasion_active", false):
		_start_invasion()     # defensive: saves are refused during invasions
	toast("Day %d, %s" % [state.day(), state.clock_text()])


func _place_player(pos: Vector3, yaw: float) -> void:
	player.global_position = Vector3(pos.x, 0, pos.z)
	player.velocity = Vector3.ZERO
	player.rig.rotation.y = yaw
	player.aim_point = player.global_position + Vector3(-sin(yaw) * 3.0, 1.1, -cos(yaw) * 3.0)
	camera.snap()
	world.update_view(player.global_position, camera, 5.0)


func _leave_to(scene: String) -> void:
	left_to = scene
	if stay_in_scene or not is_inside_tree():
		return
	get_tree().paused = false
	get_tree().change_scene_to_file.call_deferred(scene)


func _exit_tree() -> void:
	Input.set_custom_mouse_cursor(null)
	if get_tree() != null:
		get_tree().paused = false


# --- frame -----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _ok:
		return
	if _modal == "" and not state.dead:
		_advance_clock(delta * SurvivalTuning.MINUTES_PER_SECOND * time_scale)
		_run_director(delta)
	var n := state.night_amount()
	if absf(n - _night) > 0.0005:
		_night = n
		lighting.set_amount(n)
		player.set_night(n)
		boundary.set_night_amount(n)
		ambience.set_night_amount(n)
	player.speed_scale = state.move_speed_scale()
	world.update_view(player.global_position, camera, delta)
	listener.global_position = player.global_position + Vector3(0, 1.7, 0)
	_update_prompt()
	_update_banner()
	var step := _steps.tick(delta, Vector2(player.velocity.x, player.velocity.z).length())
	if step != "":
		Sfx.play(step, null, -4.0)


func _physics_process(delta: float) -> void:
	if not _ok:
		return
	_fire_cd -= delta
	_dry_cd -= delta
	_ammo_toast_cd -= delta
	if not Input.is_action_pressed("fire") or not _can_fire():
		_trigger = false
	if _modal == "" and aim_with_mouse and is_inside_tree():
		var mp := get_viewport().get_mouse_position()
		player.aim_point = world.aim_ray(camera.project_ray_origin(mp), camera.project_ray_normal(mp))
	if _trigger and _fire_cd <= 0.0:
		_fire_cd = Tuning.FIRE_INTERVAL
		_fire(player.aim_point)


## All game input arrives here (game_input.gd), also while paused.
func _on_input(event: InputEvent) -> void:
	if not _ok:
		return
	if event.is_action_pressed("pause"):
		_handled()
		_on_escape()
		return
	if event.is_action_pressed("dev_menu"):
		_handled()
		ui.dev_menu.toggle()
		return
	if event.is_action_pressed("inventory") and _modal == "inventory":
		_handled()
		GameUI.close(ui.inventory)
		_on_inventory_closed()
		return
	if _modal != "" or state.dead:
		return
	if event.is_action_pressed("fire"):
		if _can_fire():
			_trigger = true
	elif event.is_action_pressed("interact"):
		_handled()
		_interact()
	elif event.is_action_pressed("inventory"):
		_handled()
		_open_inventory()
	elif event.is_action_pressed("build_mode"):
		_handled()
		_set_build(not build.active)
	elif event.is_action_pressed("zoom_in"):
		camera.zoom(-1.0)
	elif event.is_action_pressed("zoom_out"):
		camera.zoom(1.0)


func _handled() -> void:
	if is_inside_tree():
		get_viewport().set_input_as_handled()


# --- clock and events ------------------------------------------------------------------

## Moves game time outside sleep and expeditions (play, dev menu) and handles
## the events and stragglers it crosses.
func _advance_clock(minutes: float) -> void:
	if minutes <= 0.0 or state.dead:
		return
	var t0 := state.total_minutes
	var events: Array = state.advance(minutes)
	_process_events(events)
	_check_stragglers(t0, state.total_minutes)


func _process_events(events: Array) -> void:
	var save_reason := ""
	for e in events:
		match str(e.get("type", "")):
			"dawn":
				_on_dawn()
				save_reason = "dawn"
			"dusk":
				toast("Dusk. It will be dark soon.", "warn")
			"new_day":
				toast("Day %d" % (int(floor(float(e.get("at", state.total_minutes)) / DAY_MIN)) + 1), "info")
				if save_reason == "":
					save_reason = "new_day"
			"invasion_due":
				_start_invasion()
	if save_reason != "":
		_autosave(save_reason)


func _on_dawn() -> void:
	var collectors := world.count_objects("rain_collector")
	var water := 0
	if state.has_method("on_dawn"):
		var r = state.on_dawn(collectors)
		if typeof(r) == TYPE_INT or typeof(r) == TYPE_FLOAT:
			water = int(r)
		elif typeof(r) == TYPE_STRING and r != "":
			toast(r, "good")
	elif collectors > 0:
		water = state.inventory.add("water", collectors)
	if water > 0:
		toast("The rain collectors gave %d water." % water, "good")
	Sfx.play("stinger/dawn")
	# No enemies by day: everyone left walks back into the fog.
	roster.retreat_all(Director.fog_points())
	if director.active or state.run.get("invasion_active", false):
		_end_invasion("dawn")


# --- invasions and stragglers ----------------------------------------------------------

func _start_invasion() -> void:
	if director.active:
		return
	if not state.run.get("invasion_active", false):
		state.start_invasion()
	var seed := int(state.run.get("seed", 0)) * 31 + int(state.run.get("invasions_done", 0))
	director.begin(state.invasion_size(), state.invasion_enemy_hp(), state.invasion_speed_scale(), seed)
	Sfx.play("stinger/invasion")
	ambience.set_tension(1.0)
	toast("They're coming.", "bad")
	invasion_started.emit()


func _run_director(delta: float) -> void:
	if not director.active:
		return
	for i in director.tick(delta):
		roster.spawn(director.pick_spawn(player.plan_pos()), director.hp, director.speed, true)
	if director.all_spawned() and roster.invaders_alive() == 0:
		_end_invasion("cleared")


func _end_invasion(reason: String) -> void:
	director.finish()
	state.end_invasion(true)
	ambience.set_tension(0.0)
	if reason == "dawn":
		toast("Dawn. They slink back into the fog… for now.", "good")
	else:
		toast("They're gone… for now", "good")
	invasion_ended.emit(reason)
	_autosave("invasion_end")


## Straggler time (absolute minutes) for the night that starts on `day`, or -1.
func _straggler_time(day: int) -> float:
	var next := float(state.run.get("next_invasion_at", INF))
	var seed := int(state.run.get("seed", 0))
	if state.has_method("roll_straggler"):
		var r = state.roll_straggler(day)
		match typeof(r):
			TYPE_FLOAT, TYPE_INT:
				return float(r)
			TYPE_BOOL:
				return Director.straggler_at(seed, day, next, true) if r else -1.0
			TYPE_DICTIONARY:
				return float(r.get("at", -1.0))
	return Director.straggler_at(seed, day, next)


## The first straggler time in (t0, t1], or -1.
func _straggler_between(t0: float, t1: float) -> float:
	for d in range(int(floor(t0 / DAY_MIN)), int(floor(t1 / DAY_MIN)) + 2):
		if _stragglers_done.has(d):
			continue
		var s := _straggler_time(d)
		if s > t0 and s <= t1:
			return s
	return -1.0


func _check_stragglers(t0: float, t1: float) -> void:
	if state.dead:
		return
	for d in range(int(floor(t0 / DAY_MIN)), int(floor(t1 / DAY_MIN)) + 2):
		if _stragglers_done.has(d):
			continue
		var s := _straggler_time(d)
		if s < 0.0 or s <= t0 - 0.001 or s > t1 + 0.01:
			continue
		_stragglers_done[d] = true
		# Not during an invasion, and not if a long skip already ended the night.
		if state.run.get("invasion_active", false) or not state.is_night():
			continue
		roster.spawn(director.pick_spawn(player.plan_pos()), Tuning.ENEMY_HP, 1.0, false)
		toast("Something is moving out there.", "warn")


# --- combat ----------------------------------------------------------------------------

func _can_fire() -> bool:
	return _ok and _modal == "" and not state.dead and player.input_enabled and not build.handles_input()


## One trigger pull at `target`. Returns world.shoot's result, or {"kind": "dry"}.
func _fire(target: Vector3) -> Dictionary:
	if not state.use_ammo():
		if _dry_cd <= 0.0:
			_dry_cd = DRY_FIRE_INTERVAL
			Sfx.play("weapon/dry_fire")
		if _ammo_toast_cd <= 0.0:
			_ammo_toast_cd = 2.0
			toast("Out of ammo", "warn")
		return {"kind": "dry"}
	shots_fired += 1
	var origin := Vector3(player.global_position.x, Tuning.MUZZLE_HEIGHT, player.global_position.z)
	var dir := target - origin
	if Vector2(dir.x, dir.z).length() < 0.3:
		dir = -player.rig.global_transform.basis.z
		dir.y = -0.3
	dir = dir.normalized()
	var muzzle := player.rig.muzzle_global()
	var res: Dictionary = world.shoot(origin, dir, [player.get_rid()], muzzle)
	if world.fx != null:
		world.fx.muzzle(muzzle)
		world.fx.casing(muzzle - dir * 0.15, player.rig.global_transform.basis.x)
	player.on_fired()
	Sfx.play("weapon/handgun_fire", muzzle)
	if str(res.get("kind", "")) == "enemy":
		var e = res.get("collider")
		Sfx.play("enemy/hit", res.get("pos", muzzle))
		if e is VoxelEnemy and not (e as VoxelEnemy).alive:
			Sfx.play("enemy/death", (e as VoxelEnemy).global_position)
	return res


func _on_wall_swing(e: VoxelEnemy, target: Vector2) -> void:
	world.enemy_strike(e.global_position, target)
	var at := Vector3(target.x, 1.0, target.y)
	Sfx.play("door/bash" if _door_near(target) else "impact/wood", at)
	if e.global_position.distance_to(player.global_position) < NUDGE_NEAR:
		camera.nudge(0.35)


func _door_near(p: Vector2) -> bool:
	for n in world.interactables():
		if not is_instance_valid(n) or not (n is Node3D):
			continue
		var is_door: bool = (n.has_method("is_door") and n.is_door()) or str(n.get("kind")) == "door" or str(n.name).to_lower().contains("door")
		var q: Vector3 = n.global_position
		if is_door and p.distance_to(Vector2(q.x, q.z)) < 1.0:
			return true
	return false


func _on_player_swing(e: VoxelEnemy) -> void:
	if state.dead:
		return
	Sfx.play("enemy/attack", e.global_position + Vector3(0, 1.2, 0))
	camera.nudge(1.0)
	var before := state.health
	state.damage(state.enemy_damage(), "psycho")
	if state.health < before:
		Sfx.play("player/hurt")
		if hud.has_method("flash_damage"):
			hud.flash_damage()


# --- interactions ----------------------------------------------------------------------

func _update_prompt() -> void:
	var p := ""
	_focus = null
	if _modal == "" and not state.dead:
		_focus = Finder.nearest(world.interactables(), player.plan_pos())
		p = str(_focus.interact_prompt()) if _focus != null else boundary.prompt_text()
	if p != _prompt:
		_prompt = p
		hud.set_prompt(p)


func _interact() -> void:
	_update_prompt()
	if _focus != null and is_instance_valid(_focus):
		_focus.interact(self)
	elif boundary.prompt_text() != "":
		boundary.request_exit()


func _update_banner() -> void:
	var b := ""
	if director.active:
		var left: int = director.remaining_to_spawn() + roster.invaders_alive()
		b = "They're here · %d left" % left
	elif state.invasion_due_soon():
		b = "Something is coming tonight."
	if b != _banner:
		_banner = b
		hud.set_banner(b)


func _on_structure_changed() -> void:
	state.inventory.storage_crates = world.count_objects("crate")


func _on_object_destroyed(kind: String, _at: Vector3) -> void:
	if kind in ["door", "barricade"]:
		toast("A %s gave way!" % kind, "bad")


# --- modal state and panels ------------------------------------------------------------

func _set_modal(m: String, paused: bool) -> void:
	_modal = m
	_trigger = false
	if is_inside_tree():
		get_tree().paused = paused
	_update_cursor()


func _update_cursor() -> void:
	var want := "crosshair" if _ok and _modal == "" and not state.dead and not build.active else "arrow"
	if want == _cursor:
		return
	_cursor = want
	if want == "crosshair":
		var tex := AssetResolver.get_texture("common/crosshair")
		if tex != null:
			Input.set_custom_mouse_cursor(tex, Input.CURSOR_ARROW, tex.get_size() * 0.5)
	else:
		Input.set_custom_mouse_cursor(null)


func _on_escape() -> void:
	match _modal:
		"pause":
			_resume()
		"settings":
			GameUI.close(ui.settings)
			_on_settings_closed()
		"inventory":
			GameUI.close(ui.inventory)
			_on_inventory_closed()
		"sleep":
			GameUI.close(ui.sleep_dialog)
			_on_sleep_closed()
		"":
			if build.active:
				_set_build(false)
			elif ui.dev_menu.visible:
				ui.dev_menu.toggle()
			elif not state.dead:
				_set_modal("pause", true)
				ui.pause_menu.open(can_save())


func _resume() -> void:
	GameUI.close(ui.pause_menu)
	if _modal == "pause":
		_set_modal("", false)


func _on_save_requested() -> void:
	var r := save_now()
	toast("Game saved." if r == "" else r, "good" if r == "" else "warn")


func _open_settings() -> void:
	GameUI.close(ui.pause_menu)
	_set_modal("settings", true)
	ui.settings.open()


func _on_settings_closed() -> void:
	if _modal == "settings":
		_set_modal("pause", true)
		ui.pause_menu.open(can_save())


func _open_inventory() -> void:
	_set_modal("inventory", true)
	ui.inventory.open(state)


func _on_inventory_closed() -> void:
	if _modal == "inventory":
		_set_modal("", false)


func _set_build(on: bool) -> void:
	if on and (_modal != "" or state.dead):
		return
	build.set_active(on)
	_sync_build_mode()


func _sync_build_mode() -> void:
	if hud != null:
		hud.set_mode("build" if build.active else "play")
	_trigger = false
	_update_cursor()


func _on_build_message(text: String, ok: bool) -> void:
	if text != "":
		toast(text, "good" if ok else "warn")


# --- sleep -----------------------------------------------------------------------------

func _threats() -> bool:
	return roster.living() > 0 or director.active or state.run.get("invasion_active", false)


func _sleep_block_reason() -> String:
	if _threats():
		return "You can't sleep with them out there"
	if state.has_method("can_sleep"):
		var r = state.can_sleep()
		if typeof(r) == TYPE_STRING and r != "":
			return r
		if typeof(r) == TYPE_BOOL and not r:
			return "You can't sleep right now."
	return ""


## The bed calls this (SPEC §7.3).
func open_sleep() -> void:
	if not _ok or state.dead or _modal != "":
		return
	var why := _sleep_block_reason()
	if why != "":
		toast(why, "warn")
		return
	if build.active:
		_set_build(false)
	_set_modal("sleep", true)
	ui.sleep_dialog.open(state)


func _on_sleep_closed() -> void:
	if _modal == "sleep":
		_set_modal("", false)


func _on_sleep_chosen(minutes: float) -> void:
	if _modal not in ["sleep", ""] or state.dead:
		return
	_sleep(state.until_morning_minutes() if minutes < 0.0 else minutes)


## Fade out, skip the time in one advance (asleep), fade in. Truncated by an
## invasion (GameState.plan_sleep) or tonight's straggler.
func _sleep(minutes: float) -> Dictionary:
	var why := _sleep_block_reason()
	if why != "":
		toast(why, "warn")
		_set_modal("", false)
		return {}
	_set_modal("sleeping", true)
	var plan: Dictionary = state.plan_sleep(minutes).duplicate()
	var t0 := state.total_minutes
	var s := _straggler_between(t0, t0 + float(plan["minutes"]))
	if s >= 0.0:
		plan["minutes"] = s - t0
		plan["interrupted"] = true
		plan["reason"] = "straggler"
	Sfx.play("player/sleep")
	await ui.fade.fade_to(1.0, fade_time)
	var events: Array = state.advance(float(plan["minutes"]), true)
	if plan["interrupted"] and plan["reason"] == "invasion" and not state.run.get("invasion_active", false):
		var rest := float(state.run.get("next_invasion_at", INF)) - state.total_minutes
		if rest >= 0.0 and rest < 1.0:   # land exactly on the due minute
			events.append_array(state.advance(rest + 0.001, true))
	_process_events(events)
	_check_stragglers(t0, state.total_minutes)
	last_sleep = {"from": t0, "to": state.total_minutes, "plan": plan, "events": events.map(func(e): return e["type"])}
	ui.fade.set_text("Day %d · %s" % [state.day(), state.clock_text()])
	await ui.fade.fade_to(0.0, fade_time)
	ui.fade.set_text("")
	if not state.dead and _modal == "sleeping":
		_set_modal("", false)
		if plan["interrupted"]:
			toast("You wake to something at the door.", "bad")
		else:
			_autosave("wake")
	sleep_finished.emit(plan)
	return plan


# --- expeditions -----------------------------------------------------------------------

func _on_exit_requested(at: Vector3) -> void:
	if not _ok or _modal != "" or state.dead:
		return
	if _threats():
		toast("Not with them out there.", "warn")
		return
	if build.active:
		_set_build(false)
	_exit_at = at
	_set_modal("expedition", true)
	ui.expedition.open(state)


func _on_expedition_finished(result: Dictionary) -> void:
	if _modal != "expedition":
		return                         # applied exactly once, only while the screen is open
	var t0 := state.total_minutes
	var events: Array = state.apply_expedition(result)
	last_expedition = {"result": result, "from": t0, "to": state.total_minutes}
	var back := boundary.return_point(_exit_at)
	var c := FogBoundary.LOT.get_center()
	_place_player(back, atan2(-(c.x - back.x), -(c.y - back.z)))
	if state.dead:
		return                         # the death flow owns the screen now
	_set_modal("", false)
	_process_events(events)
	_check_stragglers(t0, state.total_minutes)
	var summary := str(result.get("summary", ""))
	toast("Back home. " + summary if summary != "" else "Back home.", "good")
	_autosave("expedition")


func _on_expedition_cancelled() -> void:
	if _modal != "expedition":
		return
	_set_modal("", false)
	var d := (FogBoundary.LOT.get_center() - player.plan_pos()).normalized()
	player.global_position += Vector3(d.x, 0, d.y)
	player.velocity = Vector3.ZERO


# --- death -----------------------------------------------------------------------------

func _on_died(cause: String) -> void:
	if _death_handled:
		return
	_death_handled = true
	player.input_enabled = false
	_trigger = false
	if build.active:
		build.set_active(false)
	ui.close_all()
	_set_modal("death", false)
	Sfx.play("player/death")
	SaveGame.delete_save()     # the run is over
	if is_inside_tree():
		await get_tree().create_timer(death_delay, true).timeout
	if not is_inside_tree():
		return
	ui.fade.set_alpha(0.0)
	get_tree().paused = true
	ui.death_screen.open(state.days_survived(), cause)


## Back to the main menu (pause menu, death screen).
func request_main_menu() -> void:
	Input.set_custom_mouse_cursor(null)
	_leave_to(GameLaunch.MENU_SCENE)


# --- saving ----------------------------------------------------------------------------

## "" if saving is allowed now, else the reason.
func can_save() -> String:
	if not _ok:
		return "The game is not ready."
	if state.dead:
		return "The run is over."
	if _modal == "sleeping":
		return "You can't save while asleep."
	if _modal == "expedition":
		return "You can't save during an expedition."
	if director.active or state.run.get("invasion_active", false):
		return "You can't save during an invasion."
	if roster.living() > 0:
		return "You can't save with enemies nearby."
	return ""


## Writes the save now. Returns "" or the reason it didn't.
func save_now() -> String:
	var why := can_save()
	if why != "":
		return why
	var extra := {"time_scale": time_scale, "director": {"stragglers_done": _stragglers_done.keys()}}
	var data: Dictionary = RunSave.compose(state, world.save_data(), player.global_position, player.rig.rotation.y, extra)
	var err := SaveGame.write(data)
	if err != OK:
		return "Saving failed (%s)." % error_string(err)
	return ""


## Autosave at a safe transition; skipped (and logged) when unsafe.
func _autosave(reason: String) -> bool:
	if can_save() != "" or _modal in ["intro", "death"]:
		autosave_log.append("skip:" + reason)
		return false
	var r := save_now()
	if r != "":
		autosave_log.append("fail:" + reason)
		toast(r, "warn")
		return false
	autosave_log.append(reason)
	if hud.has_method("show_saved"):
		hud.show_saved()
	autosaved.emit(reason)
	return true


func toast(text: String, kind := "info") -> void:
	last_toast = text
	if hud != null:
		hud.toast(text, kind)


# --- developer menu API (SPEC §7.8) ----------------------------------------------------

func dev_spawn(n: int) -> void:
	var pts := Director.nearest_fog_points(player.plan_pos(), 6.0)
	for i in maxi(n, 0):
		var p: Vector2 = pts[i % pts.size()]
		roster.spawn(p + Vector2(0.5 * (i / pts.size()), 0.0), Tuning.ENEMY_HP, 1.0, false)


func dev_trigger_invasion() -> void:
	if director.active:
		toast("An invasion is already under way.", "warn")
		return
	if state.has_method("force_invasion_now"):
		state.force_invasion_now()
	_start_invasion()


func dev_repair_house() -> void:
	world.repair_all()
	toast("House repaired (dev).", "good")


func dev_advance(minutes: float) -> void:
	_advance_clock(maxf(minutes, 0.0))


## Skips to the next occurrence of `hour` (0..24).
func dev_skip_to(hour: float) -> void:
	var d := fposmod(hour * 60.0 - state.minute_of_day(), DAY_MIN)
	if d < 0.01:
		d = DAY_MIN
	dev_advance(d)


func dev_set_time_scale(x: float) -> void:
	time_scale = clampf(x, 0.0, 600.0)


func dev_info() -> String:
	var next := float(state.run.get("next_invasion_at", -1.0))
	var tonight := _straggler_time(state.day() if state.minute_of_day() >= 720.0 else state.day() - 1)
	var dmg: Dictionary = world.damage_summary()
	var lines := [
		"Day %d %s · time x%.1f · %s" % [state.day(), state.clock_text(), time_scale, _modal if _modal != "" else "playing"],
		"Enemies %d · invasion %s" % [roster.living(), ("%d/%d spawned" % [director.spawned, director.total]) if director.active else "no"],
		"Next invasion: Day %d %s" % [int(next / DAY_MIN) + 1, _hhmm(next)],
		"Straggler tonight: %s" % (_hhmm(tonight) if tonight >= 0.0 else "none"),
		"House: %d voxels missing, %d objects damaged · crates %d" % [int(dmg.get("missing_voxels", 0)), int(dmg.get("damaged_objects", 0)), world.count_objects("crate")],
		"Save: %s" % (can_save() if can_save() != "" else "allowed"),
	]
	return "\n".join(lines)


static func _hhmm(total: float) -> String:
	var m := int(fposmod(total, DAY_MIN))
	return "%02d:%02d" % [m / 60, m % 60]


# --- debug API (tests and tools/survival_playtest.gd) ----------------------------------

func debug_state() -> GameState:
	return state


func debug_world() -> HouseWorld:
	return world


func debug_player() -> VoxelPlayer:
	return player


func debug_ui() -> Node:
	return ui


func debug_director() -> RefCounted:
	return director


func debug_roster() -> Node3D:
	return roster


func debug_modal() -> String:
	return _modal


func debug_prompt() -> String:
	return _prompt


func debug_player_pos() -> Vector2:
	return player.plan_pos()


func debug_teleport_player(p: Vector2) -> void:
	player.global_position = Vector3(p.x, 0, p.y)
	player.velocity = Vector3.ZERO


## Pulls the trigger at a plan point and height (respects ammo, like LMB).
func debug_fire_at(target: Vector2, height := 1.1) -> Dictionary:
	player.aim_point = Vector3(target.x, height, target.y)
	return _fire(player.aim_point)


func debug_spawn_enemy(p: Vector2, invader := false) -> Node:
	return roster.spawn(p, Tuning.ENEMY_HP, 1.0, invader)


func debug_living_enemies() -> int:
	return roster.living()


func debug_enemy_positions() -> PackedVector2Array:
	return roster.positions()


func debug_kill_enemies() -> int:
	return roster.kill_all()


## Opens "pause" | "inventory" | "sleep" | "settings" | "dev" | "build" as the keys would.
func debug_open(panel: String) -> void:
	match panel:
		"pause":
			if _modal == "":
				_on_escape()
		"inventory":
			if _modal == "":
				_open_inventory()
		"sleep":
			open_sleep()
		"settings":
			if _modal == "":
				_on_escape()
			if _modal == "pause":
				_open_settings()
		"dev":
			if not ui.dev_menu.visible:
				ui.dev_menu.toggle()
		"build":
			_set_build(true)


## What Esc does.
func debug_close() -> void:
	_on_escape()


func debug_interact() -> void:
	_interact()


## Chooses `minutes` in the sleep dialog (-1 = until morning) and waits until awake.
func debug_sleep(minutes: float) -> Dictionary:
	if _modal == "":
		open_sleep()
	if _modal != "sleep":
		return {}
	GameUI.close(ui.sleep_dialog)
	ui.sleep_dialog.sleep_chosen.emit(minutes)
	if _modal == "sleeping":
		await sleep_finished
	return last_sleep.get("plan", {})


func debug_start_expedition() -> void:
	_on_exit_requested(player.global_position)


## As if the expedition screen finished with `result` (SPEC §7.7).
func debug_finish_expedition(result: Dictionary) -> void:
	ui.expedition.finished.emit(result)


func debug_cancel_expedition() -> void:
	ui.expedition.cancelled.emit()


func debug_save() -> String:
	return save_now()


## Reloads the game scene from the save (as Continue does).
func debug_reload() -> void:
	GameLaunch.mode = "continue"
	_leave_to(GameLaunch.GAME_SCENE)


func debug_set_spawn_gap(gap: Vector2) -> void:
	director.gap_override = gap
	director.hurry(gap.y)


func debug_straggler_time(day: int) -> float:
	return _straggler_time(day)
