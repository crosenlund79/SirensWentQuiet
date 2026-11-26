extends Node
## Experiment 008 (lead): screenshots of the real game scene at a POI (or at
## home), with the HUD, for visual review. Used with tools/capture.sh:
##   tools/capture.sh res://tools/site_shot.tscn /abs/out.png 30 --site=hardware [--clock=11] [--pos=x,y] [--car] [--yaw=rad] [--panel=search|map|inventory] [--reveal] [--weapon=shotgun|none]
## --site: a POI id (RegionLocations) or "home". --pos: where Eli stands (plan
## metres; default the entry). --panel=search opens the take panel of the
## nearest container that holds something (after its search).

const SCENE := "res://src/game/game.tscn"

var game: Node


func _ready() -> void:
	var site := "home"
	var hour := 11.0
	var pos := Vector2.INF
	var car := false
	var yaw := INF
	var panel := ""
	var reveal := false
	var weapon := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--site="):
			site = a.trim_prefix("--site=")
		elif a.begins_with("--clock="):     # not --hour: the game reads that one itself (and skips a day to it)
			hour = float(a.trim_prefix("--clock="))
		elif a.begins_with("--pos="):
			var p := a.trim_prefix("--pos=").split(",")
			pos = Vector2(float(p[0]), float(p[1]))
		elif a == "--car":
			car = true
		elif a.begins_with("--yaw="):
			yaw = float(a.trim_prefix("--yaw="))
		elif a.begins_with("--panel="):
			panel = a.trim_prefix("--panel=")
		elif a == "--reveal":
			reveal = true
		elif a.begins_with("--weapon="):     # Exp 010: the shotgun in hand, or empty hands
			weapon = a.trim_prefix("--weapon=")
	var s := GameState.new_run(8008)
	s.total_minutes = hour * 60.0
	s.region.discover(site) if site != "home" else null
	GameLaunch.seed = 8008
	GameLaunch.site = site
	if site == "home":
		GameLaunch.mode = "new"
		GameLaunch.carry = {}
	else:
		GameLaunch.mode = "carry"
		GameLaunch.carry = {"state": s.to_dict(), "home": {}, "travel": {"to": site, "car": car, "minutes": 0, "depart_at": s.total_minutes, "leg": "out"}}
	game = (load(SCENE) as PackedScene).instantiate()
	game.set("stay_in_scene", true)
	game.set("skip_intro", true)
	get_tree().root.add_child.call_deferred(game)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = game
	for i in 6:
		await get_tree().process_frame
	if game.has_method("debug_kill_enemies"):
		game.debug_kill_enemies()
	if game.has_method("debug_state"):
		game.debug_state().total_minutes = hour * 60.0
	if pos != Vector2.INF:
		game.debug_teleport_player(pos)
	if yaw != INF:
		game.player.rig.rotation.y = yaw
	if weapon == "shotgun":
		game.debug_state().inventory.add("shotgun", 1)
		game.debug_state().equip("shotgun")
		game.combat.weapons.switch_to("shotgun")
	elif weapon == "none":
		game.combat.weapons.holstered = true
	if reveal and game.get("poi") != null:
		game.poi.dev_reveal()
	for i in 4:
		await get_tree().physics_frame
	match panel:
		"map", "inventory":
			game.debug_open(panel)
		"search":
			_open_search()


func _open_search() -> void:
	var poi: Variant = game.get("poi")
	if poi == null:
		return
	var best: PoiSpot = null
	var pp: Vector2 = game.debug_player_pos()
	for sp in game.world.spots_of("container"):
		if str(sp.data.get("needs", "")) == "" and not (poi.record["c"][sp.id]["items"] as Dictionary).is_empty():
			if best == null or sp.plan_pos().distance_to(pp) < best.plan_pos().distance_to(pp):
				best = sp
	if best == null:
		return
	game.debug_teleport_player(best.plan_pos() + best.front * 0.75)
	await get_tree().physics_frame
	poi.interact_spot(best)
	await get_tree().process_frame
	poi.complete_action()
