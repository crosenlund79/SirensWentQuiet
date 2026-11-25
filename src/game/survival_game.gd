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
## Experiment 003 wiring lives in small helpers too: game_combat.gd (weapons,
## enemy blows, the bomber's fuse and blast), game_map.gd (the region map and
## its table), game_dev.gd (the new F10 tools).
## See docs/experiment-002/game.md and docs/experiment-003/game.md.

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
const Combat := preload("res://src/game/game_combat.gd")
const MapLink := preload("res://src/game/game_map.gd")
const Dev := preload("res://src/game/game_dev.gd")
const GameLevels := preload("res://src/levels/game_levels.gd")   # Experiment 004 storeys (L)
const HotbarCtl := preload("res://src/game/game_hotbar.gd")   # Experiment 004 (E)
const CarCtl := preload("res://src/game/game_car.gd")         # Experiment 004 (E)
const HomeLink := preload("res://src/home/game_home.gd")   # Experiment 004 (H): atmosphere, lights, household
const ComfortLink := preload("res://src/home/game_comfort.gd")   # Exp 005 (C): rooms, comfort, mood
const SupportLink := preload("res://src/world/game_support.gd")   # Refinement 01 (S): collapses
const StorageLink := preload("res://src/home/game_storage.gd")   # Exp 005 (F): storage furniture, placed lamps
const AudioLink := preload("res://src/audio/game_audio.gd")   # Exp 005 (A): footsteps, ambience layers, Eli
const ResearchLink := preload("res://src/research/game_research.gd")   # Exp 006 (R): skills, books, K
const BalanceLink := preload("res://src/home/game_balance.gd")   # Exp 006 (B): house supply, TV and radio, F10 House & balance
const DefenseLink := preload("res://src/defense/game_defense.gd")   # Exp 006 (D): trenches, moats, drawbridges, spikes
const NoiseLink := preload("res://src/noise/game_noise.gd")   # Exp 007 (N): event-based noise
const VisibilityLink := preload("res://src/visibility/game_visibility.gd")   # Exp 007 (N): room-based visibility

const DAY_MIN := 1440.0
const WAKE_OFFSET := Vector3(0, 0, 1.45)       ## from the bed to where you wake
const NOTICE_PREFIX := "The save could not be loaded: "

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
var combat: Node                       ## game_combat.gd (owns the WeaponHandler)
var map: Node                          ## game_map.gd (the region map and its table)
var dev: Node                          ## game_dev.gd (Experiment 003 F10 tools)
var levels: Node                       ## src/levels/game_levels.gd (Experiment 004 storeys, stairs, basement)
var bar: Node                          ## game_hotbar.gd (Experiment 004, E: the quick-access bar)
var car: Node                          ## game_car.gd (Experiment 004, E: the yard car)
var home: Node                         ## src/home/game_home.gd (Experiment 004: fireplace, lights, sink, fridge, sky)
var support: Node                      ## src/world/game_support.gd (Refinement 01: roof and upper-floor collapses)
var storage: Node                      ## src/home/game_storage.gd (Exp 005, F: storage panel, placed lamps, F10 Furniture)
var audio: Node                        ## src/audio/game_audio.gd (Exp 005, A: footsteps, ambience layers, voice)
var comfort: Node                      ## src/home/game_comfort.gd (Exp 005 (C): rooms, comfort, mood)
var research: Node                     ## src/research/game_research.gd (Exp 006 (R): K, book toasts, F10 Research)
var balance: Node                      ## src/home/game_balance.gd (Exp 006 (B): house supply, TV and radio)
var defense: Node                      ## src/defense/game_defense.gd (Exp 006 (D): the player in trenches, F10 Defences)
var security: Node                     ## src/security/security_system.gd (Exp 007 (S): sensors, turrets, their panel, F10 Security)
var noise: Node                        ## src/noise/game_noise.gd (Exp 007 (N): noise events, gunfire, F10 Noise & visibility)
var visibility: Node                   ## src/visibility/game_visibility.gd (Exp 007 (N): room-based visibility)
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
var _modal := ""                       ## "" | intro | pause | inventory | map | sleep | sleeping | expedition | death | storage (Exp 005)
var _loaded := {}
var _trigger := false
var _migrated_from := 0                ## schema of an older save that was loaded (re-saved at once)
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
var _backup_notice := ""


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
		state = GameState.new_run(GameLaunch.seed, Difficulty.valid(GameLaunch.difficulty))
		world.build_new()
		return ""
	var r: Dictionary = SaveGame.read()
	if not r.get("ok", false):
		return str(r.get("error", "unknown error"))
	if r.get("restored_from_backup", false):
		_backup_notice = "The save was damaged (%s), so the backup was loaded." % str(r.get("backup_reason", "unknown reason"))
		GameLaunch.notice = _backup_notice
	_migrated_from = int(r.get("migrated_from", 0))
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
	# settings_requested stays unconnected: the pause menu opens its own SettingsPanel.
	ui.inventory.closed.connect(_on_inventory_closed)
	ui.sleep_dialog.sleep_chosen.connect(_on_sleep_chosen)
	ui.sleep_dialog.closed.connect(_on_sleep_closed)
	ui.death_screen.main_menu_requested.connect(request_main_menu)
	ui.expedition.finished.connect(_on_expedition_finished)
	ui.expedition.cancelled.connect(_on_expedition_cancelled)
	combat = Combat.new()
	combat.name = "Combat"
	add_child(combat)
	combat.setup(self)
	hud.set_weapons(combat.weapons)
	map = MapLink.new()
	map.name = "Map"
	add_child(map)
	map.setup(self)
	dev = Dev.new()
	dev.name = "Dev"
	add_child(dev)
	dev.setup(self)
	levels = GameLevels.new()          # Experiment 004 (L): after build and combat, which it retargets
	levels.name = "Levels"
	add_child(levels)
	levels.setup(self)
	# Experiment 004 (E): the quick-access bar and the yard car.
	bar = HotbarCtl.new()
	bar.name = "Hotbar"
	add_child(bar)
	bar.setup(self)
	car = CarCtl.new()
	car.name = "Car"
	add_child(car)
	car.setup(self)
	# Experiment 004 (H): northern atmosphere, electric lights, household interactions.
	home = HomeLink.new()
	home.name = "Home"
	add_child(home)
	home.setup(self)
	support = SupportLink.new()        # Refinement 01 (S): structural support (collapse toasts, damage, F10)
	support.name = "Support"
	add_child(support)
	support.setup(self)
	storage = StorageLink.new()        # Exp 005 (F): after home (lamps follow its mains)
	storage.name = "Storage"
	add_child(storage)
	storage.setup(self)
	comfort = ComfortLink.new()        # Exp 005 (C): rooms, comfort and mood (after home and levels, which it reads)
	comfort.name = "Comfort"
	add_child(comfort)
	comfort.setup(self)
	audio = AudioLink.new()            # Exp 005 (A): after home and levels, which it reads
	audio.name = "Audio"
	add_child(audio)
	audio.setup(self)
	research = ResearchLink.new()      # Exp 006 (R): the Skills tab key, new-book toasts, F10 Research
	research.name = "Research"
	add_child(research)
	research.setup(self)
	balance = BalanceLink.new()        # Exp 006 (B): after build, storage and home (supply, TV and radio)
	balance.name = "Balance"
	add_child(balance)
	balance.setup(self)
	defense = DefenseLink.new()        # Exp 006 (D): after levels (the player's storey); the rules live in world.defense
	defense.name = "Defense"
	add_child(defense)
	defense.setup(self)
	security = SecuritySystem.new()    # Exp 007 (S): after storage (its storeys), home (power) and build (supply)
	security.name = "Security"
	add_child(security)
	security.setup(self)
	noise = NoiseLink.new()            # Exp 007 (N): after combat and roster (gunfire, provoked enemies)
	noise.name = "Noise"
	add_child(noise)
	noise.setup(self)
	visibility = VisibilityLink.new()  # Exp 007 (N): after levels, build and map (storeys, build mode, the map table)
	visibility.name = "Visibility"
	add_child(visibility)
	visibility.setup(self)
	sync_roster()
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
	levels.restore(_loaded.get("world", {}), int(_loaded.get("storey", 0)), pos)   # Experiment 004 (L)
	var g: Dictionary = _loaded.get("game", {})
	time_scale = clampf(float(g.get("time_scale", 1.0)), 0.0, 600.0)
	camera.set_turns(int(g.get("camera_turns", 0)) if typeof(g.get("camera_turns")) in [TYPE_INT, TYPE_FLOAT] else 0)   # Refinement 01
	levels.set_roofs_hidden(typeof(g.get("roofs_hidden")) == TYPE_BOOL and g["roofs_hidden"])
	var d = g.get("director", {})
	if typeof(d) == TYPE_DICTIONARY:
		for n in d.get("stragglers_done", []):
			_stragglers_done[int(n)] = true
	_update_cursor()
	if state.run.get("invasion_active", false):
		start_invasion()      # defensive: saves are refused during invasions
	toast("Day %d, %s" % [state.day(), state.clock_text()])
	if _backup_notice != "":
		toast(_backup_notice, "warn")
	if _migrated_from > 0 and _migrated_from < SaveGame.SCHEMA:
		# An older save (Experiment 002): loaded with defaults, re-saved in the current format.
		toast("Save from an earlier version loaded (%s difficulty)." % Difficulty.name_of(state.difficulty), "info")
		_autosave("migrated")


func _place_player(pos: Vector3, yaw: float) -> void:
	player.global_position = Vector3(pos.x, 0, pos.z)
	player.velocity = Vector3.ZERO
	player.rig.rotation.y = yaw
	player.aim_point = player.global_position + Vector3(-sin(yaw) * 3.0, 1.1, -cos(yaw) * 3.0)
	camera.snap()
	world.update_view(player.global_position, camera, 5.0)
	if levels != null:
		levels.on_player_placed()      # Experiment 004 (L): placed on the ground floor


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
	player.move_yaw = camera.yaw          # Refinement 01: WASD follows the turned view
	world.update_view(player.global_position, camera, delta)
	listener.global_position = player.global_position + Vector3(0, 1.7, 0)
	_update_prompt()
	_update_banner()
	# Exp 005 (A): footsteps follow the gait and the surface (src/audio/game_audio.gd)


func _physics_process(_delta: float) -> void:
	if not _ok:
		return
	if not Input.is_action_pressed("fire") or not _can_fire():
		_trigger = false
	if _modal == "" and aim_with_mouse and is_inside_tree():
		var mp := get_viewport().get_mouse_position()
		player.aim_point = levels.aim_ray(camera.project_ray_origin(mp), camera.project_ray_normal(mp))   # the player's storey
	if _trigger:
		combat.fire(player.aim_point)      # the weapon owns the fire interval and the dry clicks


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
		if _can_fire() and get_viewport().gui_get_hovered_control() == null:
			if not bar.on_fire_pressed():   # Experiment 004 (E): non-weapon items are used once
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
	elif event.is_action_pressed("open_map"):
		_handled()
		open_map()
	elif event.is_action_pressed("camera_left") or event.is_action_pressed("camera_right"):
		_handled()                          # Refinement 01: Z / C turn the view a quarter turn
		turn_camera(-1 if event.is_action_pressed("camera_left") else 1)
	elif event.is_action_pressed("toggle_roof"):
		_handled()                          # Refinement 01: V hides the roofs (and the storeys above you)
		toggle_roofs()
	elif research != null and research.handle_input(event):
		_handled()                          # Exp 006 (R): K opens the inventory's Skills tab
	elif not build.active and bar.handle_input(event):
		_handled()                          # 1-8, X, Q (Experiment 004, E: the quick-access bar)
	elif not build.active and combat.handle_input(event):
		_handled()                          # R, Q, 1, 2 (in build mode they belong to BuildMode)
	elif event.is_action_pressed("zoom_in"):
		camera.zoom(-1.0)
	elif event.is_action_pressed("zoom_out"):
		camera.zoom(1.0)


## Refinement 01: turns the view a quarter turn around the player (-1 left, +1 right).
func turn_camera(dir: int) -> void:
	camera.turn(dir)
	if build != null:
		build.set("_eval_key", "")


## Refinement 01: V. Hidden: the roof and the storeys above the player stay
## hidden, also from outside; automatic: they fade only while you're inside.
func toggle_roofs() -> void:
	levels.set_roofs_hidden(not levels.roofs_hidden)
	toast("Roofs hidden (V shows them)." if levels.roofs_hidden else "Roofs shown; they fade while you're inside (V hides them).", "info")


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
				_on_dawn(float(e.get("at", state.total_minutes)))
				save_reason = "dawn"
			"dusk":
				toast("Dusk. It will be dark soon.", "warn")
			"new_day":
				toast("Day %d" % (int(floor(float(e.get("at", state.total_minutes)) / DAY_MIN)) + 1), "info")
				if save_reason == "":
					save_reason = "new_day"
			"invasion_due":
				start_invasion()
	if save_reason != "":
		_autosave(save_reason)


func _on_dawn(at: float) -> void:
	var collectors := world.count_objects("rain_collector")
	var water := int(state.on_dawn(collectors, at).get("water", 0))
	if water > 0:
		toast("The rain collectors gave %d water." % water, "good")
	Sfx.play("stinger/dawn")
	# No enemies by day: everyone left walks back into the fog.
	roster.retreat_all(Director.fog_points())
	if director.active or state.run.get("invasion_active", false):
		_end_invasion("dawn")


# --- invasions and stragglers ----------------------------------------------------------

## The night's invasion: a threat-budget wave for the run's difficulty and
## invasion index, or exactly `kinds` (dev menu).
func start_invasion(kinds: Array = []) -> void:
	if director.active:
		return
	if not state.run.get("invasion_active", false):
		state.start_invasion()
	sync_roster()
	var seed := int(state.run.get("seed", 0)) * 31 + int(state.run.get("invasions_done", 0))
	director.begin_wave(state.difficulty, state.invasion_index(), seed, kinds)
	Sfx.play("stinger/invasion")
	ambience.set_tension(1.0)
	toast("They're coming.", "bad")
	invasion_started.emit()


func _run_director(delta: float) -> void:
	if not director.active:
		return
	for k in director.tick_kinds(delta):
		roster.spawn_type(k, director.pick_spawn(player.plan_pos()), director.spawn_opts(k))
	if director.all_spawned() and roster.invaders_alive() == 0:
		_end_invasion("cleared")


func _end_invasion(reason: String) -> void:
	director.finish()
	state.end_invasion(true)
	sync_roster()
	ambience.set_tension(0.0)
	if reason == "dawn":
		toast("Dawn. They slink back into the fog… for now.", "good")
	else:
		toast("They're gone… for now", "good")
	invasion_ended.emit(reason)
	_autosave("invasion_end")


## Straggler time (absolute minutes) for the night that starts on `day`, or -1.
func _straggler_time(day: int) -> float:
	return state.roll_straggler(day)


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
		roster.spawn_type("psycho", director.pick_spawn(player.plan_pos()), {"level": state.difficulty, "invasion": state.invasion_index(),
			"mode": "straggler"})          # Exp 007 (N): calm until provoked (src/ai/straggler_mind.gd)
		toast("Something is moving out there.", "warn")


# --- combat ----------------------------------------------------------------------------

func _can_fire() -> bool:
	if ui.intro != null and ui.intro.get("is_playing") == true:
		return false
	return _ok and _modal == "" and not state.dead and player.input_enabled and not build.handles_input()


## The roster's defaults for spawn_type follow the run (difficulty, invasion index).
func sync_roster() -> void:
	roster.level = state.difficulty
	roster.invasion = state.invasion_index()


# --- interactions ----------------------------------------------------------------------

func _update_prompt() -> void:
	var p := ""
	_focus = null
	if _modal == "" and not state.dead:
		_focus = Finder.nearest(levels.interactables(world.interactables() + map.interactables() + car.interactables() + home.interactables() + (balance.interactables() if balance != null else [])), player.plan_pos())   # + stairs, by storey (L); + the yard car (E); + home (H)
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
	var label: String = WorldObject.DEFS[kind]["name"] if WorldObject.DEFS.has(kind) else kind.replace("_", " ")
	toast("The %s gave way!" % label.to_lower(), "bad")


# --- modal state and panels ------------------------------------------------------------

func _set_modal(m: String, paused: bool) -> void:
	_modal = m
	_trigger = false
	if is_inside_tree():
		get_tree().paused = paused
	_update_cursor()
	if _ok:
		_update_prompt()      # hides the prompt now: _process doesn't run while paused


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
		"inventory":
			GameUI.close(ui.inventory)
			_on_inventory_closed()
		"sleep":
			GameUI.close(ui.sleep_dialog)
			_on_sleep_closed()
		"map":
			map.close()
		"storage":
			storage.close_panel()          # Exp 005 (F)
		"security":
			security.close_panel()         # Exp 007 (S)
		"":
			if build.active:
				_set_build(false)
			elif GameUI.is_open(ui.dev_menu):
				ui.dev_menu.toggle()
			elif not state.dead:
				_set_modal("pause", true)
				ui.pause_menu.open(can_save(), "%s difficulty · Day %d" % [Difficulty.name_of(state.difficulty), state.day()])


func _resume() -> void:
	GameUI.close(ui.pause_menu)
	if _modal == "pause":
		_set_modal("", false)


## Synchronous, so "Save and quit" knows the result before main_menu_requested.
func _on_save_requested() -> void:
	var r := save_now()
	if ui.pause_menu.has_method("report_save"):
		ui.pause_menu.report_save(r)
	else:
		toast("Game saved." if r == "" else r, "good" if r == "" else "warn")


func _open_inventory() -> void:
	_set_modal("inventory", true)
	ui.inventory.open(state)


func _on_inventory_closed() -> void:
	if _modal == "inventory":
		_set_modal("", false)


## The region map (M, or the map on the dining table). The world pauses while it is open.
func open_map() -> void:
	if not _ok or _modal != "" or state.dead:
		return
	if build.active:
		_set_build(false)
	_set_modal("map", true)
	map.open()


func _on_map_closed() -> void:
	if _modal == "map":
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
	return state.can_sleep()


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
	var t0 := state.total_minutes      # plan_sleep stops at invasions, stragglers and empty needs
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
			# GameState's own line for every reason ("needs": hunger or thirst, not the door).
			var line := str(plan.get("text", ""))
			if plan["reason"] == "invasion" or line == "":
				line = "You wake to something at the door."
			toast(line, "bad" if plan["reason"] != "needs" else "warn")
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
	apply_expedition_result(result)


## Applies an expedition result (the screen's `finished`, or F10's instant
## mission): the survival state once (by the result id), then the region
## (stock, discoveries, the used plan; once-only too), then home through the fog.
func apply_expedition_result(result: Dictionary) -> void:
	var t0 := state.total_minutes
	var events: Array = state.apply_expedition(result)
	var region_applied := ExpeditionData.apply_region(state, result)
	last_expedition = {"result": result, "from": t0, "to": state.total_minutes, "region_applied": region_applied}
	var back := boundary.return_point(_exit_at if _modal == "expedition" else player.global_position)
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
	map.close()
	ui.close_all()
	hud.set_mode("hidden")
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
	var extra := {"time_scale": time_scale, "director": {"stragglers_done": _stragglers_done.keys()},
		"camera_turns": camera.turns, "roofs_hidden": levels.roofs_hidden}      # Refinement 01
	var data: Dictionary = RunSave.compose(state, levels.world_save(world.save_data()), player.global_position, player.rig.rotation.y, extra,
		levels.player_storey)          # Experiment 004 (L): storeys in the world save, the player's in "game"
	var err := SaveGame.write(data)
	if err != OK:
		return "Saving failed: %s" % (SaveGame.last_error if SaveGame.last_error != "" else error_string(err))
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
	state.force_invasion_now()
	start_invasion()


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
		dev.info(),
		home.info(),
	]
	if comfort != null:
		lines.append(comfort.info())       # Exp 005 (C)
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


## Pulls the trigger at a plan point and height through the weapon in hand
## (respects ammo, like LMB). Waits out the weapon's shot interval first, as a
## player tapping the trigger would. Returns WeaponHandler.try_fire's result.
func debug_fire_at(target: Vector2, height := 1.1) -> Dictionary:
	player.aim_point = Vector3(target.x, height, target.y)
	if combat.weapons.cooldown() > 0.0:
		combat.weapons.tick(combat.weapons.cooldown())
	return combat.fire(player.aim_point)


func debug_spawn_enemy(p: Vector2, invader := false) -> Node:
	return roster.spawn(p, Tuning.ENEMY_HP, 1.0, invader)


func debug_living_enemies() -> int:
	return roster.living()


func debug_enemy_positions() -> PackedVector2Array:
	return roster.positions()


func debug_kill_enemies() -> int:
	return roster.kill_all()


## Opens "pause" | "inventory" | "map" | "sleep" | "settings" | "dev" | "build" as the keys would.
func debug_open(panel: String) -> void:
	match panel:
		"pause":
			if _modal == "":
				_on_escape()
		"inventory":
			if _modal == "":
				_open_inventory()
		"map":
			open_map()
		"sleep":
			open_sleep()
		"settings":
			if _modal == "":
				_on_escape()
			var b: Node = ui.pause_menu.find_child("Settings", true, false)
			if _modal == "pause" and b is BaseButton:
				(b as BaseButton).pressed.emit()
		"dev":
			if not GameUI.is_open(ui.dev_menu):
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
