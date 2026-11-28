extends Node
## Exp 012 (S): screenshots of the story's key moments in the real game at
## home, for visual review. Used with tools/capture.sh:
##   tools/capture.sh res://tools/story_shot.tscn /abs/out.png 30 --moment=gas
## Moments: gas (the Visitor: the dark room, blankets, the door, the gas),
## observer (the watcher beyond the lot edge at dusk), warning (Eli awake in
## the dark, the lines from outside), door (the Last Courtesy: bound, the door
## jolting), bound (morning: tied to the bed), burn (the ropes flying into
## the fire). Poses are staged directly (StoryStage, StoryOverlay) so the
## picture is the moment, not a race against the script.

const SCENE := "res://src/game/game.tscn"

var game: Node
var moment := "gas"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--moment="):
			moment = a.trim_prefix("--moment=")
	GameLaunch.seed = 1212
	GameLaunch.site = "home"
	GameLaunch.mode = "new"
	GameLaunch.carry = {}
	game = (load(SCENE) as PackedScene).instantiate()
	game.set("stay_in_scene", true)
	game.set("skip_intro", true)
	get_tree().root.add_child.call_deferred(game)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = game
	for i in 6:
		await get_tree().process_frame
	var s: GameState = game.debug_state()
	s.run["next_invasion_at"] = 30 * 1440.0
	var st: StoryDirector = game.story
	var hours := {"gas": 2.5, "warning": 2.5, "door": 2.5, "observer": 20.4, "bound": 8.0, "burn": 9.0}
	var hour: float = float(hours.get(moment, 2.5))
	s.total_minutes = 3 * 1440.0 + float(hour) * 60.0
	game.time_scale = 0.0
	await get_tree().process_frame
	match moment:
		"gas":
			_bed()
			st.stage.build({"blankets": true, "door": true, "dark": true, "lying": true})
			st.stage.set_gas(1.0)
			st.overlay.set_dark(0.42)
			st.overlay.set_gas(0.45)
			st.overlay.set_wobble(0.35)
			st.overlay.say("Night nighty.", "voice")
		"warning":
			_bed()
			st.stage.build({"dark": true, "lying": true})
			st.overlay.set_dark(0.36)
			st.audio.set_level(3)
			st.overlay.say("But I've been watching.", "voice")
		"door":
			_bed()
			st.stage.build({"blankets": true, "door": true, "dark": true, "lying": true, "bound": true})
			st.overlay.set_dark(0.38)
			st.overlay.say("I've asked them to leave you alone.", "voice")
			_keep_jolting(st)
		"bound":
			_bed()
			st.stage.build({"lying": true, "bound": true})
			st.stage.struggle(true)
		"observer":
			game.debug_teleport_player(Vector2(6.0, 10.6))
			game.player.rig.rotation.y = PI
			await get_tree().process_frame
			st.spawn_observer(true)
			st.overlay.say("That's him...", "thought")
		"burn":
			var fs: Vector2 = st.fire_stand()
			game.debug_teleport_player(fs)
			game.player.aim_point = st.fire_mouth() + Vector3(0, 0.6, 0)
			_lock(st)
			st._frame_bed()
			game.camera.snap()
			_keep_throwing(st)
	for i in 4:
		await get_tree().physics_frame
	print("story_shot: %s staged at %d ms" % [moment, Time.get_ticks_msec()])


func _bed() -> void:
	game.story._place_at_bed()
	game.story._lock_control("sleeping")
	game.story._frame_bed()
	game.camera.snap()


func _lock(st: StoryDirector) -> void:
	st._lock_control("story")


func _keep_jolting(st: StoryDirector) -> void:
	while is_instance_valid(st):
		st.stage.jolt(1.0)
		await get_tree().create_timer(0.9).timeout


func _keep_throwing(st: StoryDirector) -> void:
	while is_instance_valid(st):
		game.player.rig.aiming = false
		game.player.rig.use_t = 1.0
		st.stage.throw_ropes(game.player.rig.hand_global(), st.fire_mouth(), 2)
		await get_tree().create_timer(0.45).timeout
		st.stage.flare(st.fire_mouth())
		await get_tree().create_timer(0.5).timeout
