extends "res://tests/test_case.gd"
## Sfx (SPEC §7.6): playback with and without an attached root, unknown names,
## cooldowns and instance caps, UI while paused, music cross-fade, listener.

const Catcher := preload("res://tests/audio/warning_catcher.gd")


func _root3d() -> Node3D:
	Sfx.reset()
	var root := add(Node3D.new()) as Node3D
	Sfx.attach(root)
	return root


func _host(root: Node) -> Node:
	return root.get_node_or_null("SfxHost")


func _players(host: Node, cls: String) -> Array:
	var out := []
	if host != null:
		for c in host.get_children():
			if c.is_class(cls) and c.has_meta("sfx_kind"):
				out.append(c)
	return out


func test_play_with_root_positional_and_flat() -> void:
	var root := _root3d()
	Sfx.play("impact/wood", Vector3(2, 1, 3))
	Sfx.play("player/eat")
	var host := _host(root)
	if not check(host != null, "players live under the attached root"):
		return
	var p3 := _players(host, "AudioStreamPlayer3D")
	check_eq(p3.size(), 1, "one positional player")
	if p3.size() == 1:
		var p: AudioStreamPlayer3D = p3[0]
		check(p.playing, "positional sound playing")
		check_eq(p.global_position, Vector3(2, 1, 3), "at the hit point")
		check_eq(String(p.bus), "SFX", "SFX bus")
		check(p.max_distance >= 30.0 and p.max_distance <= 40.0, "max distance 30-40 m")
		check(p.attenuation_filter_db < 0.0, "slight attenuation filter")
	var flat := _players(host, "AudioStreamPlayer")
	check_eq(flat.size(), 1, "one flat player")
	if flat.size() == 1:
		check(flat[0].playing, "flat sound playing")
	check_eq(Sfx.active_count("impact/wood"), 1, "active count")
	Sfx.play("impact/plaster", Vector2(5, 6))
	var placed := false
	for p in _players(host, "AudioStreamPlayer3D"):
		if p.get_meta("sfx_key") == "impact/plaster":
			placed = p.global_position.is_equal_approx(Vector3(5, Sfx.LISTENER_HEIGHT, 6))
	check(placed, "a plan Vector2 maps to (x, h, y)")


func test_play_without_root_falls_back_safely() -> void:
	Sfx.reset()
	var cat := Catcher.new()
	OS.add_logger(cat)
	Sfx.play("impact/metal", Vector3.ZERO)
	Sfx.play("impact/glass")
	OS.remove_logger(cat)
	check_eq(cat.count("no scene root attached"), 1, "warns once")
	var host := tree.root.get_node_or_null("SfxHost")
	check(host != null, "fell back to the SceneTree root")
	check_eq(Sfx.active_count("impact/metal"), 1, "still plays")
	# an attached root that is freed later: fall back again, never crash
	var root := add(Node3D.new())
	Sfx.attach(root)
	await frames(1)
	check(not is_instance_valid(host) or host.is_queued_for_deletion(), "attach() retires the fallback host")
	root.queue_free()
	await frames(2)
	Sfx.play("impact/wood", Vector3.ONE)
	check(tree.root.get_node_or_null("SfxHost") != null, "freed root -> SceneTree root")
	Sfx.reset()
	await frames(1)


func test_unknown_name_warns_once_and_plays_nothing() -> void:
	_root3d()
	var cat := Catcher.new()
	OS.add_logger(cat)
	Sfx.play("nope/nothing")
	Sfx.play("nope/nothing", Vector3.ONE)
	Sfx.ui("nope/nothing")
	Sfx.play("player/footstep_9")
	Sfx.music("nope/song")
	OS.remove_logger(cat)
	check_eq(cat.count("'nope/nothing'"), 1, "one warning per unknown name")
	check_eq(cat.count("'player/footstep_9'"), 1, "out-of-range variant is unknown")
	check_eq(int(Sfx.stats["played"]), 0, "nothing played")
	check_eq(Sfx.current_music(), "", "music unchanged")


func test_loops_are_refused_by_play() -> void:
	_root3d()
	var cat := Catcher.new()
	OS.add_logger(cat)
	Sfx.play("ambient/wind_day")
	OS.remove_logger(cat)
	check_eq(cat.count("is a loop"), 1, "warns")
	check_eq(int(Sfx.stats["played"]), 0, "not played as a one-shot")


func test_cooldown_and_cap_limit_repeats() -> void:
	_root3d()
	for i in 10:
		Sfx.play("player/footstep", Vector3.ZERO)
	check_eq(Sfx.active_count("player/footstep"), 1, "cooldown: one footstep")
	check(int(Sfx.stats["skipped"]) >= 9, "the rest were skipped")
	# impacts: short cooldown, cap of 4 simultaneous. Cooldowns and playback
	# run in real time (the test clock is a fixed 60 fps), so wait for real.
	for i in 8:
		Sfx.play("impact/wood", Vector3(i, 0, 0))
		OS.delay_msec(40)
	var n := Sfx.active_count("impact/wood")
	check(n >= 2 and n <= 4, "impact cap (got %d)" % n)
	check(int(Sfx.stats["stolen"]) >= 1, "the oldest impact was restarted")


func test_group_never_repeats_the_same_variant_twice() -> void:
	Sfx.reset()
	var prev := ""
	for i in 30:
		var v := Sfx._variant("player/footstep", "player/footstep")
		check(v != prev, "no immediate repeat (%s)" % v)
		check(Sfx.variants("player/footstep").has(v), "valid variant")
		prev = v


func test_ui_plays_on_ui_bus_while_paused() -> void:
	Sfx.reset()
	tree.paused = true
	Sfx.ui("ui/click")
	Sfx.play("ui/hover")
	var host := tree.root.get_node_or_null("SfxPersistent")
	var ok := host != null
	var buses := {}
	if ok:
		for c in host.get_children():
			if c.get_meta("sfx_kind", "") == "U" and c.playing:
				buses[c.get_meta("sfx_key")] = String(c.bus)
	await frames(2)
	tree.paused = false
	check(ok, "UI host on the SceneTree root")
	check_eq(buses.get("ui/click"), "UI", "click playing on the UI bus")
	check_eq(buses.get("ui/hover"), "UI", "hover (via play) playing on the UI bus")
	check(host != null and host.process_mode == Node.PROCESS_MODE_ALWAYS, "UI host runs while paused")


func test_music_crossfades_and_stops() -> void:
	Sfx.reset()
	Sfx.music("")
	await seconds(Sfx.MUSIC_FADE + 0.2)
	Sfx.music("music/menu")
	check_eq(Sfx.current_music(), "music/menu", "current track")
	var host := tree.root.get_node_or_null("SfxPersistent")
	var playing: AudioStreamPlayer = null
	for c in host.get_children():
		if c.get_meta("sfx_kind", "") == "M" and c.playing:
			playing = c
	if not check(playing != null, "music player started"):
		return
	check_eq(String(playing.bus), "Music", "Music bus")
	check((playing.stream as AudioStreamOggVorbis).loop, "looped")
	await seconds(0.5)
	check(playing.volume_linear > 0.05 and playing.volume_linear < 1.0, "fading in")
	Sfx.music("music/menu")
	check(playing.playing, "same track again: no restart")
	Sfx.music("")
	check_eq(Sfx.current_music(), "", "stopped")
	await seconds(Sfx.MUSIC_FADE + 0.3)
	check(not playing.playing, "faded out and stopped")


func test_listener_follows_the_camera_focus() -> void:
	var root := _root3d()
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.global_position = Vector3(4, 18, 14)
	cam.look_at(Vector3(4, 1, 2))
	cam.make_current()
	Sfx.play("impact/ground", Vector3(4, 0, 2))
	await frames(2)
	var host := _host(root)
	var listener: AudioListener3D = null
	for c in host.get_children():
		if c is AudioListener3D:
			listener = c
	if not check(listener != null, "scene host has a listener"):
		return
	check(listener.is_current(), "listener is current")
	check(listener.global_position.distance_to(Vector3(4, 1, 2)) < 0.05, "at the camera focus (%s)" % listener.global_position)
