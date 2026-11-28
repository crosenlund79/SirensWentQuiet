extends Node
## Experiment 012 (E): screenshots of enemy reactions, the downed toast and
## corpses in the real game scene at home. With tools/capture.sh (give it a
## long --at; this scene saves the picture itself at the right moment):
##   tools/capture.sh res://tools/enemy_shot.tscn /abs/out.png 600 --shot=scream|toast|corpses [--clock=h]
##   scream   a calm psycho north of Eli sees him: the shot is mid-scream
##   toast    a brute is shot down: the "Name — Brute — Downed" toast
##   corpses  four people downed around Eli at night; he stands by one: the search prompt
##   search   one body searched at home: the loot panel on its pockets
##   poi      at a POI (--site=id, default hardware): a body left there on an
##            earlier visit is rebuilt, a new one is downed and searched (the
##            POI loot panel under the pack limit)

const SCENE := "res://src/game/game.tscn"
const ELI := Vector2(16.5, 3.0)

var game: Node
var out := ""


func _ready() -> void:
	var shot := "scream"
	var hour := 11.0
	var site := "hardware"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot = a.trim_prefix("--shot=")
		elif a.begins_with("--clock="):
			hour = float(a.trim_prefix("--clock="))
		elif a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--site="):
			site = a.trim_prefix("--site=")
	GameLaunch.seed = 8008
	GameLaunch.site = "home"
	GameLaunch.mode = "new"
	GameLaunch.carry = {}
	if shot == "poi":
		var s := GameState.new_run(8008)
		s.total_minutes = hour * 60.0
		s.region.discover(site)
		var rec := PoiState.record(s, site)
		rec["corpses"] = [{"pos": [0.0, 0.0, 0.0], "yaw": 0.4, "fall": [1.0, 0.0], "kind": "brute", "app": 5,
			"name": "Left From Before", "items": {"scrap": 2}, "seed": 99, "searched": false}]     # placed near Eli below
		GameLaunch.site = site
		GameLaunch.mode = "carry"
		GameLaunch.carry = {"state": s.to_dict(), "home": {}, "travel": {"to": site, "car": false, "minutes": 0, "depart_at": s.total_minutes, "leg": "out"}}
	game = (load(SCENE) as PackedScene).instantiate()
	game.set("stay_in_scene", true)
	game.set("skip_intro", true)
	get_tree().root.add_child.call_deferred(game)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = game
	for i in 6:
		await get_tree().process_frame
	game.debug_kill_enemies()
	game.debug_state().total_minutes = hour * 60.0
	if shot == "poi":
		await _poi()
		await _save()
		return
	game.debug_teleport_player(ELI)
	game.player.rig.rotation.y = 0.0
	game.camera.set_distance(11.0)
	game.camera.snap()
	for i in 20:
		await get_tree().physics_frame
	match shot:
		"scream":
			await _scream()
		"toast":
			await _toast()
		"search":
			await _corpses()
			var c: Corpse = game.corpses.interactables()[0]
			if c.items.is_empty():
				c.items["snacks"] = 2
			game.corpses.search(c)
			await get_tree().create_timer(0.3, true, false, true).timeout
		_:
			await _corpses()
	await _save()


func _spawn(kind: String, at: Vector2, app: int) -> AIEnemy:
	var e: AIEnemy = game.roster.spawn_type(kind, at, {"mode": "hidden", "appearance": app})
	e.set_facing(atan2(-(ELI - at).x, -(ELI - at).y))
	return e


func _scream() -> void:
	var e := _spawn("psycho", ELI + Vector2(2.4, -3.0), 3)
	game.corpses.dev_toggle_debug()
	for i in 600:
		await get_tree().physics_frame
		if e.reaction != null and e.reaction.shouts > 0:
			break
	await get_tree().create_timer(0.42).timeout
	print("scream: %s provoked_by=%s phase=%s shouts=%d" % [e.display_name, e.provoked_by, e.reaction.phase, e.reaction.shouts])


func _toast() -> void:
	var e := _spawn("brute", ELI + Vector2(0.4, -3.6), 21)
	await get_tree().create_timer(0.5).timeout
	e.take_damage(99, Vector3(0.2, 0, -1.0), "shot")
	await get_tree().create_timer(0.9).timeout


func _corpses() -> void:
	var list := []
	var spots := [Vector2(-1.6, -2.4), Vector2(0.9, -3.4), Vector2(2.4, -1.6), Vector2(-0.4, -4.6)]
	var kinds := ["psycho", "runner", "brute", "bomber"]
	for i in 4:
		list.append(_spawn(kinds[i], ELI + spots[i], 40 + i))
	await get_tree().create_timer(0.6).timeout
	for e in list:
		var d: Vector3 = (e as AIEnemy).global_position - Vector3(ELI.x, 0, ELI.y)
		(e as AIEnemy).take_damage(99, d, "shot")
		await get_tree().create_timer(0.15).timeout
	await get_tree().create_timer(Corpse.SETTLE + 0.6).timeout
	var c: Corpse = game.corpses.bodies[0] if not game.corpses.bodies.is_empty() else null
	if c != null:
		game.debug_teleport_player(c.plan_pos() + Vector2(0.9, 0.9))
	await get_tree().create_timer(0.5).timeout
	print("corpses: %d bodies, prompt '%s', last toast '%s'" % [game.corpses.bodies.size(), game.get("_prompt"), game.corpses.last_downed])


## At a POI: the body recorded on an "earlier visit" (moved next to Eli
## before the scene was built, so it is rebuilt there) and a new one.
func _poi() -> void:
	var pp: Vector2 = game.debug_player_pos()
	var nav: GridNav = game.world.nav
	var at := Vector2.INF
	for i in 16:
		var q := pp + Vector2.from_angle(TAU * i / 16.0) * 2.4
		if nav.is_walkable(nav.cell_of(q)):
			at = q
			break
	var before: int = game.corpses.bodies.size()
	if before > 0:                         # the old body into view (the picture only)
		var b: Corpse = game.corpses.bodies[0]
		b.global_position = Vector3(pp.x - 1.4, b.global_position.y, pp.y + 1.2)
	var e := _spawn_at("psycho", at if at != Vector2.INF else pp + Vector2(2, 0), 7, pp)
	e.take_damage(99, Vector3(1, 0, 0), "shot")
	await get_tree().create_timer(Corpse.SETTLE + 0.5).timeout
	var rec := PoiState.record(game.debug_state(), game.world.poi_id)
	var c: Corpse = game.corpses.bodies.back()
	if c.items.is_empty():
		c.items["bandage"] = 1
	print("poi: rebuilt=%d bodies=%d record=%d names=%s" % [before, game.corpses.bodies.size(), (rec.get("corpses", []) as Array).size(),
		[game.corpses.bodies.map(func(b): return b.display_name)]])
	game.corpses.search(c)
	await get_tree().create_timer(0.3, true, false, true).timeout


func _spawn_at(kind: String, at: Vector2, app: int, look: Vector2) -> AIEnemy:
	var e: AIEnemy = game.roster.spawn_type(kind, at, {"mode": "hidden", "appearance": app})
	e.set_facing(atan2(-(look - at).x, -(look - at).y))
	return e


func _save() -> void:
	await RenderingServer.frame_post_draw
	var img := get_tree().root.get_texture().get_image()
	if img != null and out != "":
		img.save_png(out)
		print("captured ", out)
	get_tree().quit(0)
