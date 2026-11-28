extends "res://tools/site_shot.gd"
## Exp 012 (V): fog-of-war screenshots (tools/capture.sh res://tools/fow_shot.tscn out.png 400 [site_shot args] ...):
## it saves the shot itself once Eli stands and faces where asked (the 400 s is only capture.gd's fallback).
## Extra args:
##   --face=yaw          Eli faces this yaw (rad; 0 = north, PI/2 = west)
##   --look=x,y;x,y,...  before the shot Eli stands at each point in turn (facing --face) so it gets discovered
##   --fow-off           the fog of war off (for a before / after pair)
##   --fow-debug         the vision debug overlay
##   --walled=x,y        one more calm psycho at x,y (behind a wall)
##   --fow-states        draw the cells' states as colours (red discovered, green visible, blue undiscovered)

var _face := INF


func _ready() -> void:
	var looks := []
	var off := false
	var dbg := false
	var walled := Vector2.INF
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--face="):
			_face = float(a.trim_prefix("--face="))
		elif a.begins_with("--look="):
			for p in a.trim_prefix("--look=").split(";"):
				var q := p.split(",")
				looks.append(Vector2(float(q[0]), float(q[1])))
		elif a == "--fow-off":
			off = true
		elif a == "--fow-debug":
			dbg = true
		elif a.begins_with("--walled="):
			var q := a.trim_prefix("--walled=").split(",")
			walled = Vector2(float(q[0]), float(q[1]))
	await super._ready()
	game.set("aim_with_mouse", false)
	var fow: FogOfWar = game.visibility.fow
	var end: Vector2 = game.debug_player_pos()
	for p in looks:
		_stand(p)
		fow.refresh()
		await get_tree().process_frame
	_stand(end)
	if walled != Vector2.INF:
		var e: Node = game.roster.spawn_type("psycho", walled, {"mode": "hidden", "appearance": 3})
		if e is AIEnemy:
			(e as AIEnemy).set_facing(PI * 0.5)
	fow.refresh()
	if dbg:
		fow.dev_toggle_debug()
	if off:
		fow.enabled = false
	for a in OS.get_cmdline_user_args():
		if a == "--fow-states":            # the cells as colours: red = discovered, green = visible, blue = undiscovered
			(fow.get("_mat") as ShaderMaterial).set_shader_parameter("debug_mode", 1)
	for i in 6:
		await get_tree().process_frame
		_stand(end, false)
	fow.refresh()
	for i in 3:
		await get_tree().process_frame
		_stand(end, false)
	print("FOW ", fow.info())
	if game.world is PoiWorld:
		print("FOW site: building %s entry %s rooms %s" % [game.world.building_rect(), game.world.entry_point(), (game.world as PoiWorld).rooms().map(func(r): return r.get("rect", r))])
	print("FOW enemies: ", game.roster.enemies.map(func(e): return "%s %s" % [e.plan_pos(), e.rig.visible]))
	# Shoot it ourselves once everything is in place (capture.gd's timer is only a fallback: pass a long --at).
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	if out != "" and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out)
		print("FOW captured ", out)
		get_tree().quit(0)


func _stand(p: Vector2, move := true) -> void:
	if move:
		game.debug_teleport_player(p)
	if _face != INF:
		game.player.rig.rotation.y = _face
		game.player.aim_point = Vector3(p.x - sin(_face) * 4.0, 1.1, p.y - cos(_face) * 4.0)
