extends Node
## Exp 012 (G): screenshots and a behaviour log of hordes and sieges in the
## real game at home. With tools/capture.sh:
##   tools/capture.sh res://tools/siege_shot.tscn /abs/out.png 40 --mode=siege [--clock=23] [--pos=x,y] [--markers] [--zoom=n] [--after=s]
## or headless for the log only:
##   godot --headless --fixed-fps 60 --path . res://tools/siege_shot.tscn -- --mode=siege --quit=90
## --mode: horde (a big whole-group wave), siege (an organised siege), rush
## (the siege's members as a plain wave, to compare),
## invasion (the night's), barricade (an enemy barricade in the bedroom
## doorway with a worker beside it). --pos: where Eli stands (plan metres;
## default the living room); he is invulnerable and still. --markers shows
## the tactic markers. --log prints the siege's tactics every 5 s; --quit=s
## quits after that many seconds (headless runs). --rally puts the siege's
## members at their rally spots at once (a staged shot: the groups go on to
## their tactics). --shot=/abs.png saves the screenshot itself once the scene
## is set up and --settle=N frames have passed (use a long capture.sh time).
## --defend: Eli is mortal and fires (a handgun, every DEFEND_GAP s) at the
## nearest attacker he can see within DEFEND_RANGE m (a crude stand-in for a
## player holding a room); the log reports his health and the kills.

const SCENE := "res://src/game/game.tscn"

var game: Node
var mode := "siege"
var quit_after := -1.0
var log_on := false
var _t := 0.0
var _log_t := 0.0
var defend := false
var _fire_t := 0.0
var kills := 0
const DEFEND_GAP := 0.7
const DEFEND_RANGE := 9.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS       # keeps logging (and quits) on the death screen too
	var hour := 23.0
	var pos := Vector2(6.0, 7.0)
	var markers := false
	var zoom := 0.0
	var rally := false
	var shot := ""
	var settle := 60
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			mode = a.trim_prefix("--mode=")
		elif a.begins_with("--clock="):
			hour = float(a.trim_prefix("--clock="))
		elif a.begins_with("--pos="):
			var p := a.trim_prefix("--pos=").split(",")
			pos = Vector2(float(p[0]), float(p[1]))
		elif a == "--markers":
			markers = true
		elif a.begins_with("--zoom="):
			zoom = float(a.trim_prefix("--zoom="))
		elif a == "--rally":
			rally = true
		elif a.begins_with("--shot="):
			shot = a.trim_prefix("--shot=")
		elif a.begins_with("--settle="):
			settle = int(a.trim_prefix("--settle="))
		elif a == "--defend":
			defend = true
		elif a == "--log":
			log_on = true
		elif a.begins_with("--quit="):
			quit_after = float(a.trim_prefix("--quit="))
			log_on = true
	GameLaunch.seed = 8012
	GameLaunch.site = "home"
	GameLaunch.mode = "new"
	GameLaunch.carry = {}
	game = (load(SCENE) as PackedScene).instantiate()
	game.set("stay_in_scene", true)
	game.set("skip_intro", true)
	game.set("aim_with_mouse", false)
	get_tree().root.add_child.call_deferred(game)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = game
	for i in 6:
		await get_tree().process_frame
	while game.get("siege") == null or game.get("_staging") or not game.get("_ok"):    # the staged boot
		await get_tree().process_frame
	for i in 10:
		await get_tree().process_frame
	game.debug_kill_enemies()
	var s: GameState = game.debug_state()
	s.total_minutes = (s.day() - 1) * 1440.0 + hour * 60.0
	s.cheats["invulnerable"] = not defend
	game.roster.enemy_died.connect(func(_e, _k, _c): kills += 1)
	s.cheats["unlimited"] = true
	game.time_scale = 0.0                     # the clock stands still (no dawn mid-shot)
	game.debug_teleport_player(pos)
	game.player.input_enabled = false
	for i in 3:
		await get_tree().physics_frame          # the body moves in the physics world too
	if zoom != 0.0:
		game.camera.zoom(zoom)
	var siege: SiegeDirector = game.siege
	match mode:
		"horde":
			print(siege.dev_horde())
		"invasion":
			print(siege.dev_invasion())
		"siege":
			print(siege.dev_siege())
		"rush":                                   # the siege's members as a plain horde (a comparison)
			var w := SiegeDirector.compose(s.difficulty, s.invasion_index(), 31 * int(s.run.get("seed", 0)))
			game.dev.dev_wave(w)
			print("Rush: ", w)
		"barricade":
			_barricade_scene()
	siege.set_markers(markers)
	if rally and mode == "siege":
		while siege._pending:
			await get_tree().process_frame
		for gr in siege.groups:
			var n: int = (gr["members"] as Array).size()
			for k in n:
				var spot: Vector2 = siege._rally_spot(gr, k, n)
				(gr["members"][k] as Node3D).global_position = Vector3(spot.x, 0, spot.y)
			gr["t"] = SiegeDirector.ENCIRCLE_MIN
		siege.update(0.3)
		siege.update(0.3)
		print(siege.tactics_text())
	if shot != "":
		for i in settle:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img != null:
			img.save_png(shot)
			print("shot ", shot)
		print(siege.tactics_text())
		get_tree().quit(0)


## The bedroom doorway barricaded, a psycho beside it on the living-room
## side, Eli in the bedroom; the markers show its job.
func _barricade_scene() -> void:
	var seg := Vector3i(0, 4, 2)                  # the bedroom doorway
	print("why not: '%s'" % EnemyBarricades.why_not(game.world, seg))
	var o := EnemyBarricades.place(game.world, seg)
	print("barricade: ", o.pos if o != null else "none")
	if o == null:
		return
	var e: AIEnemy = game.roster.spawn_type("psycho", o.pos + Vector2(0.5, 1.1), {"mode": "hidden", "appearance": 31})
	e.set_facing(0.0)


func _process(delta: float) -> void:
	_t += delta
	if game == null or game.get("siege") == null:
		return
	if defend and game.director.active:
		_defend(delta)
	_log_t -= delta
	if log_on and _log_t <= 0.0:
		_log_t = 5.0
		var r = game.roster
		print("[%5.1f s] Eli %.0f hp, kills %d · alive %d · barricades %d\n%s" % [_t, game.debug_state().health, kills, r.invaders_alive() if r != null else 0,
			EnemyBarricades.all_in(game.world).size(), game.siege.tactics_text()])
		for en in game.siege.marker_entries():
			var e: AIEnemy = en["enemy"]
			print("   %-7s %-8s at %s goal %s swings %s hp %d" % [e.kind, en["tactic"], e.plan_pos().snapped(Vector2(0.1, 0.1)),
				(en["goal"] as Vector2).snapped(Vector2(0.1, 0.1)), e.swings, e.hp])
	if quit_after > 0.0 and _t >= quit_after:
		print("stats: ", game.siege.stats, " · Eli health %.0f, dead %s, kills %d" % [game.debug_state().health, game.debug_state().dead, kills])
		get_tree().quit(0)


func _defend(delta: float) -> void:
	_fire_t -= delta
	if _fire_t > 0.0 or game.debug_state().dead:
		return
	_fire_t = DEFEND_GAP
	var me: Vector2 = game.debug_player_pos()
	var best: AIEnemy = null
	for e in game.roster.threats():
		if e is AIEnemy and e.plan_pos().distance_to(me) <= DEFEND_RANGE and game.world.nav.segment_clear(me, e.plan_pos()):
			if best == null or e.plan_pos().distance_to(me) < best.plan_pos().distance_to(me):
				best = e
	if best != null:
		game.debug_fire_at(best.plan_pos())
