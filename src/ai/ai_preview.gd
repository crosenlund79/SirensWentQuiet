extends Node3D
## Enemy AI preview harness (SPEC-003 §5; not used by the game): the real
## HouseWorld, the player (VoxelPlayer, invulnerable: swings only count) and
## the real roster and director.
##   godot --path . res://src/ai/ai_preview.tscn
## Keys: WASD move, mouse aim, LMB shoot; 1 psycho, 2 runner, 3 brute,
## 4 bomber (at the mouse if outside the house, else the nearest fog point);
## F1 / F2 / F3 a wave on Easy / Normal / Hard; + / - invasion index;
## G fast waves (5 s groups) on/off; O open/close the doors; B barricade the
## living-room window; K kill all; H repair the house; N day/night; wheel zoom.
##
## Captures (tools/capture.sh with --scenario=...): the scene fast-forwards
## with rendering off, freezes at the moment and writes the frame from the game
## camera to the capture's --out itself, then quits. Scenarios: lineup,
## close (--kind=...), runner_door, brute_barricade, bomber_walk, bomber_fuse,
## bomber_hole, wave (--level=..., --invasion=...). Add --night for night.

const Roster := preload("res://src/game/enemy_roster.gd")
const Director := preload("res://src/game/invasion_director.gd")
const KEYS := {KEY_1: "psycho", KEY_2: "runner", KEY_3: "brute", KEY_4: "bomber"}
const WARP := 3.0                      ## time scale while fast-forwarding a capture

var lighting: VoxelLighting
var world: HouseWorld
var player: VoxelPlayer
var camera: VoxelCamera
var roster: Node3D
var director := Director.new()
var focus: Node3D
var help: Label
var status: Label
var banner: Label
var scenario := ""
var kind := "brute"
var level := "normal"
var invasion := 3
var night := false
var out := ""
var fast_waves := false
var log_lines: Array = []
var _cond := Callable()
var _shot_taken := false
var _fire_cd := 0.0
var _t := 0.0
var _focus_cut := false
var _ref := {}                         ## scenario actors


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scenario="):
			scenario = a.trim_prefix("--scenario=")
		elif a.begins_with("--kind="):
			kind = a.trim_prefix("--kind=")
		elif a.begins_with("--level="):
			level = a.trim_prefix("--level=")
		elif a.begins_with("--invasion="):
			invasion = int(a.trim_prefix("--invasion="))
		elif a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a == "--night":
			night = true
	Sfx.attach(self)
	lighting = VoxelLighting.new()
	add_child(lighting)
	world = HouseWorld.new()
	world.setup(lighting)
	add_child(world)
	world.build_new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	player = VoxelPlayer.new()
	player.name = "Player"
	add_child(player)
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	lighting.night_materials.append(VoxelRig.look_material(true))
	lighting.night_materials.append(VoxelRig.look_material(false))
	focus = Node3D.new()
	focus.name = "Focus"
	add_child(focus)
	camera = VoxelCamera.new()
	camera.target = player
	add_child(camera)
	camera.process_mode = Node.PROCESS_MODE_PAUSABLE
	camera.make_current()
	roster = Roster.new()
	roster.name = "Enemies"
	roster.setup(world, player, 7)
	roster.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(roster)
	roster.wall_swing.connect(_on_wall_swing)
	roster.player_swing.connect(func(_e): pass)        # invulnerable
	roster.fuse_started.connect(_on_fuse)
	roster.detonated.connect(_on_detonated)
	_build_ui()
	lighting.set_amount(1.0 if night else 0.0)
	player.set_night(1.0 if night else 0.0)
	if scenario != "":
		player.input_enabled = false
		_scenario()
	else:
		player.global_position = Vector3(6.5, 0, 11.5)
	world.chunks.flush(100000.0)
	camera.snap()
	if scenario != "" and out != "":
		Engine.time_scale = WARP
		RenderingServer.render_loop_enabled = false


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	help = Label.new()
	help.position = Vector2(16, 12)
	help.add_theme_font_size_override("font_size", 15)
	help.add_theme_color_override("font_outline_color", Color.BLACK)
	help.add_theme_constant_override("outline_size", 5)
	help.text = "Enemy AI preview   WASD move · mouse aim · LMB shoot\n1 psycho · 2 runner · 3 brute · 4 bomber   F1/F2/F3 wave Easy/Normal/Hard   +/- invasion   G fast waves\nO doors · B barricade window · K kill all · H repair · N night · wheel zoom"
	layer.add_child(help)
	status = Label.new()
	status.position = Vector2(16, 90)
	status.add_theme_font_size_override("font_size", 15)
	status.add_theme_color_override("font_outline_color", Color.BLACK)
	status.add_theme_constant_override("outline_size", 5)
	layer.add_child(status)
	banner = Label.new()
	banner.add_theme_font_size_override("font_size", 26)
	banner.add_theme_color_override("font_color", Color(1.0, 0.55, 0.2))
	banner.add_theme_color_override("font_outline_color", Color.BLACK)
	banner.add_theme_constant_override("outline_size", 8)
	banner.position = Vector2(560, 40)
	banner.visible = false
	layer.add_child(banner)
	if scenario != "":
		help.text = _caption()
		status.visible = false


func _caption() -> String:
	match scenario:
		"lineup": return "Enemy archetypes: psycho · runner · brute · bomber"
		"close": return "Archetype: %s" % EnemyDefs.get_def(kind)["name"]
		"runner_door": return "Runner: detours to the open back door instead of bashing"
		"brute_barricade": return "Brute: three strikes a swing on a barricade"
		"bomber_walk": return "Bomber: walks past the player to a weak wall"
		"bomber_fuse": return "Bomber: fuse lit at the wall"
		"bomber_hole": return "Bomber: the hole after the blast"
		"wave": return "Wave: %s, invasion %d" % [Difficulty.name_of(level), invasion]
	return scenario


# --- scenarios -----------------------------------------------------------------------

func _place_player(p: Vector2, look_at: Vector2) -> void:
	player.global_position = Vector3(p.x, 0, p.y)
	player.aim_point = Vector3(look_at.x, 1.0, look_at.y)
	var to := player.aim_point - player.global_position
	player.rig.rotation.y = atan2(-to.x, -to.z)


func _frame(at: Vector2, dist: float, cut_at_focus := true) -> void:
	focus.global_position = Vector3(at.x, 0, at.y)
	camera.target = focus
	camera.set_distance(dist)
	_focus_cut = cut_at_focus


func _door(at: Vector2) -> WorldObject:
	for o in world.objects:
		if o.kind == "door" and o.pos.distance_to(at) < 0.1:
			return o
	return null


func _weaken_south_wall() -> void:
	for o in world.objects:
		if o.kind == "door":
			world.set_door_open(o, true)
	for k in 8:
		var from := Vector3(9.5, Tuning.MUZZLE_HEIGHT, 11.5)
		world.shoot(from, Vector3(9.2 + 0.1 * k, 0.6 + 0.12 * k, 9.0) - from, [])


func _scenario() -> void:
	match scenario:
		"lineup":
			_place_player(Vector2(12.0, 12.3), Vector2(8.0, 12.0))
			var i := 0
			for k in EnemyDefs.KINDS:
				var e: AIEnemy = roster.spawn_type(k, Vector2(3.2 + 2.2 * i, 11.8))
				e.set_physics_process(false)
				_ref[k] = e
				i += 1
			_frame(Vector2(7.4, 11.6), 12.5)
			_after(0.1, func(): _pose_lineup())
		"close":
			_place_player(Vector2(7.5, 12.2), Vector2(4.0, 12.2))
			var e: AIEnemy = roster.spawn_type(kind, Vector2(2.8, 12.6))
			_ref["e"] = e
			_frame(Vector2(5.6, 12.0), 11.0)
			if kind == "bomber":
				_cond = func(): return e.plan_pos().distance_to(Vector2(2.8, 12.6)) > 1.6
			else:
				_cond = func(): return e.swings["player"] >= 1 and e.rig.swing > 0.35 and e.rig.swing < 0.75
		"runner_door":
			var back := _door(Vector2(14.0, 6.5))
			world.set_door_open(back, true)
			_place_player(Vector2(11.6, 7.2), Vector2(14.0, 6.5))
			var r: AIEnemy = roster.spawn_type("runner", Vector2(10.0, -4.6))
			_ref["e"] = r
			_frame(Vector2(13.4, 6.6), 13.0)
			_cond = func(): return r.plan_pos().distance_to(Vector2(14.3, 6.5)) < 0.45
		"brute_barricade":
			# A yard wall (y = 11, x 3..10) with a barricade in it; the brute
			# behind it, the player in front of it.
			var segs := []
			for x in range(3, 10):
				if x != 6:
					segs.append(Vector3i(0, 11, x))
			world.build_walls(segs)
			var bar := world.place_object("barricade", Vector2(6.5, 11.0), 2)
			_ref["bar"] = bar
			_place_player(Vector2(6.6, 12.8), Vector2(6.5, 11.0))
			var b: AIEnemy = roster.spawn_type("brute", Vector2(6.0, 9.8))
			_ref["e"] = b
			_frame(Vector2(6.5, 11.6), 11.0, false)
			_cond = func(): return is_instance_valid(bar) and bar.hp <= bar.max_hp - 6 and b.rig.swing > 0.45 and b.rig.swing < 0.8
		"bomber_walk", "bomber_fuse", "bomber_hole":
			_weaken_south_wall()
			_place_player(Vector2(9.0, 11.2), Vector2(7.0, 13.0))
			var bm: AIEnemy = roster.spawn_type("bomber", Vector2(6.2, 13.9))
			_ref["e"] = bm
			_frame(Vector2(8.6, 10.6), 12.0)
			match scenario:
				"bomber_walk":
					_cond = func(): return is_instance_valid(bm) and bm.plan_pos().distance_to(player.plan_pos()) < 0.9 and bm.plan_pos().y < player.plan_pos().y + 0.3
				"bomber_fuse":
					_cond = func(): return is_instance_valid(bm) and bm.state_name() == "fuse" and bm.behaviour.fuse_left < 1.4
				"bomber_hole":
					_ref["blast_t"] = -1.0
					_cond = func(): return float(_ref["blast_t"]) >= 0.0 and _t - float(_ref["blast_t"]) > 1.6
		"wave":
			_place_player(Vector2(6.5, 7.8), Vector2(6.5, 11.0))
			director.gap_override = Vector2(4.0, 6.0)
			director.begin_wave(level, invasion, 1123)
			_frame(Vector2(6.5, 9.5), 22.0)
			_cond = func(): return director.all_spawned() and _t > 30.0
		_:
			push_warning("ai_preview: unknown scenario %s" % scenario)


func _after(secs: float, f: Callable) -> void:
	get_tree().create_timer(secs, false).timeout.connect(f)


func _pose_lineup() -> void:
	var yaws := {"psycho": 2.7, "runner": 2.5, "brute": 2.9, "bomber": 0.55}
	var phase := 0.0
	for k in _ref:
		var e: AIEnemy = _ref[k]
		e.set_facing(float(yaws.get(k, PI)))
		e.rig.speed = 1.1
		e.rig.walk_phase = phase
		e.rig.animate(0.0)
		phase += 1.3
	EnemyLooks.sync_night()
	_cond = func(): return true


# --- per frame ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	_t += delta
	player.set_night(lighting.night_amount)
	world.update_view(focus.global_position if _focus_cut else player.global_position, camera, delta)
	_run_director(delta)
	if scenario == "":
		_interactive(delta)
	elif not _shot_taken and _cond.is_valid() and _cond.call():
		_shot_taken = true
		_capture()


func _interactive(delta: float) -> void:
	var mp := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	player.aim_point = world.aim_ray(from, dir)
	_fire_cd = maxf(_fire_cd - delta, 0.0)
	if Input.is_action_pressed("fire") and _fire_cd <= 0.0:
		_fire_cd = Tuning.FIRE_INTERVAL
		var o := Vector3(player.global_position.x, Tuning.MUZZLE_HEIGHT, player.global_position.z)
		var d := (player.aim_point - o).normalized()
		var muzzle := player.rig.muzzle_global()
		world.shoot(o, d, [player.get_rid()], muzzle)
		world.fx.muzzle(muzzle)
		player.on_fired()
		Sfx.play("weapon/handgun_fire", muzzle)
	var by: Dictionary = roster.living_by_kind()
	var s := "Invasion %d · %s%s\nAlive: %s" % [invasion, Difficulty.name_of(level), " · fast waves" if fast_waves else "", str(by) if not by.is_empty() else "none"]
	if director.active:
		s += "\nWave: %d/%d spawned, budget %.1f: %s" % [director.spawned, director.total, director.budget, ", ".join(director.wave)]
	for l in log_lines:
		s += "\n" + str(l)
	if status.text != s:
		status.text = s


func _run_director(delta: float) -> void:
	if not director.active:
		return
	for k in director.tick_kinds(delta):
		roster.spawn_type(k, director.pick_spawn(player.plan_pos()), director.spawn_opts(k))
	if director.all_spawned() and roster.invaders_alive() == 0 and scenario == "":
		director.finish()
		_log("Wave cleared")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("zoom_in"):
		camera.zoom(-1.0)
	elif event.is_action_pressed("zoom_out"):
		camera.zoom(1.0)
	if scenario != "" or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = (event as InputEventKey).keycode
	if KEYS.has(k):
		var at := player.aim_point
		var p := Vector2(at.x, at.z)
		if HousePlan.FOOTPRINT.grow(0.6).has_point(p) or not HousePlan.YARD.grow(-0.5).has_point(p):
			p = Director.nearest_fog_points(player.plan_pos(), 6.0)[0]
		roster.spawn_type(KEYS[k], p, {"level": level, "invasion": invasion})
		_log("Spawned a %s" % KEYS[k])
	match k:
		KEY_F1, KEY_F2, KEY_F3:
			level = {KEY_F1: "easy", KEY_F2: "normal", KEY_F3: "hard"}[k]
			director.gap_override = Vector2(4.0, 6.0) if fast_waves else Vector2.ZERO
			director.begin_wave(level, invasion, randi())
			_log("Wave: %s" % ", ".join(director.wave))
		KEY_EQUAL, KEY_KP_ADD:
			invasion = mini(invasion + 1, 20)
		KEY_MINUS, KEY_KP_SUBTRACT:
			invasion = maxi(invasion - 1, 1)
		KEY_G:
			fast_waves = not fast_waves
		KEY_O:
			for o in world.objects:
				if o.kind == "door":
					world.set_door_open(o, not o.open)
		KEY_B:
			if world.object_at(Vector2(6.5, 9.0)) == null:
				world.place_object("barricade", Vector2(6.5, 9.0), 2)
		KEY_K:
			roster.kill_all()
		KEY_H:
			world.repair_all()
		KEY_N:
			night = not night
			lighting.set_amount(1.0 if night else 0.0)


func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 4:
		log_lines.pop_front()


func _on_wall_swing(e: VoxelEnemy, target: Vector2) -> void:
	world.enemy_strike(e.global_position, target)
	if e.global_position.distance_to(player.global_position) < 6.0:
		camera.nudge(0.35)


func _on_fuse(_e: VoxelEnemy, _at: Vector3, seconds: float) -> void:
	banner.text = "! BOMBER - fuse lit, %.1f s" % seconds
	banner.visible = true
	_log("Bomber fuse lit")


func _on_detonated(at: Vector3, radius: float, damage: float) -> void:
	banner.visible = false
	_ref["blast_t"] = _t
	var d := Vector2(at.x, at.z).distance_to(player.plan_pos())
	camera.nudge(2.0 if radius > 2.0 else 1.0)
	_log("Blast: %.0f damage to the player at %.1f m (invulnerable)" % [EnemyDefs.blast_damage_at(d, damage, radius), d])


# --- capture -------------------------------------------------------------------------------

func _capture() -> void:
	EnemyLooks.sync_night()
	world.update_view(focus.global_position if _focus_cut else player.global_position, camera, 0.0)
	world.chunks.flush(100000.0)
	camera.snap()
	get_tree().paused = true
	Engine.time_scale = 1.0
	RenderingServer.render_loop_enabled = true
	print("ai_preview: %s ready at %.1f s game time" % [scenario, _t])
	if out == "":
		if OS.get_cmdline_user_args().has("--check"):
			get_tree().quit(0)
		return
	for i in 4:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(out)
		print("captured ", out)
	get_tree().quit(0)
