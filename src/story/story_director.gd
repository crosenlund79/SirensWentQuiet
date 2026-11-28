class_name StoryDirector
extends Node
## Exp 012 (S): Chapter One, "Someone Is Watching" (ASSIGNMENT §2-8, §35-37).
## Created by the game at home and at POIs (src/game/survival_game.gd); its
## one hook there is the sleep: SurvivalGame._sleep asks takes_sleep() and
## lets run_sleep() have the night when an encounter is due.
##
## The four encounters:
##   1 The Visitor        asleep in his bed at night: the dark room, blankets on
##                        the window, the locked door, knocking, the voice, gas,
##                        unconscious; he wakes alone in the morning.
##   2 The Observer       awake at home at dusk or night: a man stands beyond
##                        the lot edge and watches; walks calmly away into the
##                        fog when approached (never vanishes in plain sight).
##   3 The Warning        asleep at night: his followers all around the house,
##                        his composed lines from outside the window.
##   4 The Last Courtesy  asleep at night: bound to the bed, the followers loud
##                        and chaotic, bat blows on the door (it jolts on every
##                        one), his speech, a sudden complete silence, gas; he
##                        wakes tied, struggles free and gets the four ropes:
##                        keep them or burn them in the fireplace (§7).
## Scheduling and saving: StoryState. Staging: StoryStage (temporary props,
## restored after). Sound: StoryAudio. Screen: StoryOverlay. The watcher:
## StoryFigure. While a night scene runs the game's modal is "sleeping" (no
## saves, the clock stands still, no invasion or straggler can start); input
## is off and Esc skips the scene to its end. Previews (F10) never write the
## state, the inventory, the house or the save.

signal tick
signal encounter_started(n: int, preview: bool)
signal encounter_finished(n: int, preview: bool)

const NIGHT_WINDOW := Vector2(40.0, 240.0)     ## minute of day: the night scenes happen 00:40..04:00
const DUSK := Vector2(19.0 * 60.0, 23.75 * 60.0)   ## the watcher stands there in this part of the evening
const BURN := 9                                ## `running` while the ropes are burned
const NEAR := 7.5                              ## m: closer than this and the watcher walks away
const WATCH := 45.0                            ## s he goes on watching after Eli's last thought
const WALK := 1.5                              ## m/s, Eli walking to the fireplace by himself
const EDGE_IN := 1.4                           ## m inside the lot edge where the watcher stands (the fog begins there)

var game: Node
var state: GameState
var audio: StoryAudio
var stage: StoryStage
var overlay: StoryOverlay
var figure: StoryFigure
var speed := 1.0                               ## scene clock scale (tests fast-forward)
var running := 0                               ## the encounter on screen (BURN: the ropes), 0 = none
var preview := false
var phase := ""                                ## what the scene is doing now (tests, F10)
var history: Array[String] = []
var _clock := 0.0
var _dt := 0.0
var _skip := false
var _lock := {}
var _obs := {}
var _obs_t := 1.0
var _choice_t := 0.0
var _rng := RandomNumberGenerator.new()


func setup(g: Node) -> void:
	game = g
	state = g.state
	name = "Story"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	audio = StoryAudio.new()
	audio.name = "StoryAudio"
	add_child(audio)
	stage = StoryStage.new()
	stage.setup(g)
	g.add_child(stage)
	overlay = StoryOverlay.new()
	overlay.name = "StoryOverlay"
	add_child(overlay)
	audio.impact.connect(stage.jolt)
	overlay.keep_pressed.connect(keep_ropes)
	overlay.burn_pressed.connect(func(): burn_ropes())
	StoryState.ch1(state)


func _exit_tree() -> void:
	# left mid-scene (menu, load, quit): nothing of the scene stays behind
	StoryAudio.stop_all(get_tree())
	if stage != null and is_instance_valid(stage):
		stage.restore()


func _process(delta: float) -> void:
	_dt = delta * speed
	_clock += _dt
	audio.speed = speed
	tick.emit()
	if running == BURN and phase == "throw":
		var r: Variant = game.player.rig
		r.set("aiming", false)
	if running == 0 and game != null and not get_tree().paused:
		_observer_process(delta)
		_choice_process(delta)


func _input(event: InputEvent) -> void:
	if running != 0 and running != 2 and event.is_action_pressed("pause"):
		_skip = true
		get_viewport().set_input_as_handled()


# --- the sleep hook ----------------------------------------------------------------------------

## SurvivalGame._sleep asks: does an encounter take this sleep over?
func takes_sleep(minutes: float) -> bool:
	if running != 0 or not game.is_home() or state.dead:
		return false
	if not StoryState.next_encounter(state) in [1, 3, 4]:
		return false
	return encounter_time(minutes) >= 0.0


## When tonight's scene would happen in a sleep of `minutes` starting now
## (a total minute), or -1: the next one's time has come, it falls in the
## night window, and the sleep (cut short by an invasion, a straggler or
## hunger) still lasts past it.
func encounter_time(minutes: float) -> float:
	var c := StoryState.ch1(state)
	var t0 := state.total_minutes
	var plan := state.plan_sleep(minutes)
	var end := t0 + float(plan["minutes"])
	var start := maxf(t0 + 20.0, float(c["next_at"]))
	var day0 := floorf(start / StoryState.DAY) * StoryState.DAY
	var m := start - day0
	var at := start
	if m < NIGHT_WINDOW.x:
		at = day0 + NIGHT_WINDOW.x
	elif m > NIGHT_WINDOW.y:
		at = day0 + StoryState.DAY + NIGHT_WINDOW.x
	return at if at + 10.0 < end else -1.0


## The night of an encounter (replaces SurvivalGame._sleep for this sleep):
## fade out, sleep until the scene, the scene, the rest of the sleep
## (unconscious), wake. Returns the sleep plan as _sleep does.
func run_sleep(minutes: float) -> Dictionary:
	var n := StoryState.next_encounter(state)
	var t0 := state.total_minutes
	var plan: Dictionary = state.plan_sleep(minutes).duplicate()
	var end := t0 + float(plan["minutes"])
	var at := encounter_time(minutes)
	_start(n, false)
	_lock_control("sleeping")
	Sfx.play("player/sleep")
	await _fade(1.0, game.fade_time)
	_advance(at - t0)
	await _cinematic(n)
	if n == 3:
		_advance(6.0)
		plan = {"minutes": state.total_minutes - t0, "interrupted": true, "reason": "story", "text": ""}
	else:
		_advance(end - state.total_minutes)
		if plan["interrupted"] and plan["reason"] == "invasion" and not state.run.get("invasion_active", false):
			var rest := float(state.run.get("next_invasion_at", INF)) - state.total_minutes
			if rest >= 0.0 and rest < 1.0:
				_advance(rest + 0.001)
	game.last_sleep = {"from": t0, "to": state.total_minutes, "plan": plan, "events": [], "story": n}
	await _wake(n, false)
	_finish(n, false)
	if plan["interrupted"] and plan["reason"] in ["invasion", "straggler", "needs"]:
		var line := str(plan.get("text", ""))
		game.toast(line if line != "" else "You wake to something at the door.", "bad" if plan["reason"] != "needs" else "warn")
	game._autosave("wake")
	game.sleep_finished.emit(plan)
	return plan


# --- F10 ---------------------------------------------------------------------------------------

## A real encounter now (saved progression; earlier ones count as done).
func trigger(n: int) -> String:
	return await _dev_run(n, false)


## The encounter on screen without any progression, rope, house or save change.
func preview_encounter(n: int) -> String:
	return await _dev_run(n, true)


func _dev_run(n: int, prev: bool) -> String:
	if running != 0 or figure != null:
		return "A story scene is already running."
	if not game.is_home():
		return "The story happens at home."
	if game._threats():
		return "Not with enemies around."
	if n == 2:
		return "Encounter 2: he stands outside, watching" if spawn_observer(prev) != null else "No place for him"
	_start(n, prev)
	_lock_control("sleeping")
	await _fade(1.0, 0.6)
	await _cinematic(n)
	await _wake(n, prev)
	_finish(n, prev)
	if not prev:
		game._autosave("story")
	return "Encounter %d %s" % [n, "previewed" if prev else "done"]


## Esc for the scene on screen: it runs to its end at once.
func skip() -> void:
	if running != 0:
		_skip = true


func _start(n: int, prev: bool) -> void:
	running = n
	preview = prev
	_skip = false
	phase = "start"
	history.append("%s %d" % ["preview" if prev else "run", n])
	encounter_started.emit(n, prev)


func _finish(n: int, prev: bool) -> void:
	if not prev:
		StoryState.complete(state, n)
	running = 0
	preview = false
	_skip = false
	phase = ""
	encounter_finished.emit(n, prev)


# --- the scenes ----------------------------------------------------------------------------------

## A night scene: it starts and ends in black; the stage is gone after
## (Encounter 4 leaves Eli bound in his bed for the aftermath).
func _cinematic(n: int) -> void:
	_place_at_bed()
	_frame_bed()
	match n:
		1:
			await _visitor()
		3:
			await _warning()
		4:
			await _last_courtesy()
	game.ui.fade.set_alpha(1.0)
	audio.stop()
	StoryAudio.release_duck(0.8)
	overlay.reset()
	stage.restore_except(["lying", "bound"] if n == 4 else [])


## §3 The Visitor.
func _visitor() -> void:
	stage.build({"blankets": true, "door": true, "dark": true, "lying": true})
	overlay.set_dark(0.5)
	StoryAudio.hold_duck(-18.0)
	phase = "silence"
	await _fade(0.0, 2.2)
	await _wait(3.5)
	phase = "knocking"
	for k in [0.5, 0.45, 1.3, 0.5, 0.0]:
		_knock()
		await _wait(k)
	await _wait(1.4)
	phase = "voice"
	var door := audio.door_at
	await _say("wakey", door)
	await _wait(1.6)
	phase = "breathing"
	audio.play_follower("story/follower_breath", door + Vector3(0.2, 0.0, 0.1), -6.0)
	await _wait(4.2)
	phase = "voice"
	await _say("there_you_are", door)
	await _wait(1.1)
	await _say("beginning", door)
	await _wait(3.4)
	await _say("watching", door)
	await _wait(3.6)
	await _say("night_nighty", door)
	await _wait(1.2)
	phase = "gas"
	stage.set_gas(1.0)
	await _ramp(7.0, func(x: float) -> void:
		overlay.set_gas(x * 0.7)
		overlay.set_wobble(clampf((x - 0.35) * 1.6, 0.0, 1.0))
		overlay.set_dark(0.5 + x * 0.25))
	phase = "unconscious"
	await _fade(1.0, 2.6)


## §5 The Warning.
func _warning() -> void:
	stage.build({"dark": true, "lying": true})
	overlay.set_dark(0.42)
	StoryAudio.hold_duck(-14.0)
	await _fade(0.0, 1.8)
	await _wait(2.0)
	phase = "followers"
	audio.set_level(3)
	await _wait(9.0)
	phase = "voice"
	var win := audio.window_at
	await _say("warn_progress", win)
	await _wait(1.5)
	await _say("warn_walls", win)
	await _wait(0.6)
	await _say("warn_impressive", win)
	await _wait(2.6)
	await _say("warn_watching", win)
	await _wait(1.4)
	await _say("warn_routine", win)
	await _wait(1.0)
	await _say("warn_routines", win)
	await _wait(0.9)
	await _say("warn_inconvenient", win)
	await _wait(3.2)
	await _say("enough", win)
	phase = "leaving"
	await _wait(1.0)
	audio.fade_out_followers(4.0)
	await _wait(5.5)
	await _fade(1.0, 1.6)


## §6 The Last Courtesy.
func _last_courtesy() -> void:
	stage.build({"blankets": true, "door": true, "dark": true, "lying": true, "bound": true})
	overlay.set_dark(0.48)
	StoryAudio.hold_duck(-20.0)
	await _fade(0.0, 1.6)
	await _wait(1.2)
	phase = "followers"
	audio.set_level(4)
	await _wait(6.5)
	phase = "door"
	var len := audio.play_bat(-1)
	await _wait(len * 0.9)
	len = audio.play_bat(-1)
	await _wait(len * 0.75)
	phase = "voice"
	await _say("final_patient")
	await _wait(1.8)
	await _say("final_walls")
	await _wait(1.9)
	await _say("final_still")
	phase = "door"
	len = audio.play_bat(-1)
	await _wait(minf(len, 5.0))                 # (a long pause)
	phase = "voice"
	await _say("final_asked")
	audio.silence()                             # at that moment: complete silence
	phase = "silence"
	await _wait(3.2)
	phase = "voice"
	await _say("final_courtesy")
	await _wait(2.0)
	await _say("final_run_out")
	await _wait(1.5)
	await _say("final_sleep_well")
	await _wait(0.6)
	await _say("final_while")
	await _wait(1.4)
	phase = "gas"
	stage.set_gas(1.0)
	await _ramp(5.0, func(x: float) -> void:
		overlay.set_gas(x * 0.7)
		overlay.set_wobble(clampf((x - 0.3) * 1.6, 0.0, 1.0))
		overlay.set_dark(0.48 + x * 0.3))
	phase = "unconscious"
	await _fade(1.0, 2.4)


## Waking after a scene: Encounter 1 alone and shaken; 3 still at night; 4
## tied to the bed (the ropes). Control comes back at the end.
func _wake(n: int, prev: bool) -> void:
	stage.build({"lying": true})
	_place_at_bed()
	match n:
		1:
			await _fade(0.0, 1.8)
			await _wait(1.0)
			phase = "thoughts"
			for t in StoryLines.THOUGHTS["wake"]:
				await _think(t, 2.7)
				await _wait(0.5)
		3:
			await _fade(0.0, 1.2)
			await _wait(1.6)
		4:
			stage.build({"bound": true})
			await _fade(0.0, 1.8)
			await _wait(1.4)
			phase = "struggle"
			stage.struggle(true)
			await _wait(3.8)
			stage.struggle(false)
			stage.loosen_ropes()
			await _wait(1.4)
			if not prev:
				_give_ropes()
	game.ui.fade.set_alpha(0.0)
	overlay.reset()
	stage.restore()
	_unlock_control()


## The game camera close on the bed (restored with the control).
func _frame_bed() -> void:
	var cam: Variant = game.get("camera")
	if cam is VoxelCamera:
		(cam as VoxelCamera).set("_goal_distance", VoxelCamera.ZOOM_MIN + 1.0)


func _place_at_bed() -> void:
	var p := stage.bed_side()
	game._place_player(p, PI)


# --- the ropes (§7) ------------------------------------------------------------------------------

## Four ropes for real (never twice for one night): into the inventory, any
## that don't fit in a pile beside the bed (house storage, saved).
func _give_ropes() -> void:
	var c := StoryState.ch1(state)
	if int(c["ropes"]) > 0:
		return
	var got := state.inventory.add("rope", 4)
	var rest := 4 - got
	c["pile"] = ""
	if rest > 0:
		var side := stage.bed_side()
		var w: Variant = game.get("world")
		var pile: Variant = w.drop_loot(Vector2(side.x + 1.0, side.z - 0.3), {"rope": rest}) if w != null and w.has_method("drop_loot") else null
		if pile is WorldObject:
			c["pile"] = (pile as WorldObject).uid
		game.toast("Rope ×%d. No room for %d: left in a pile by the bed." % [got, rest], "warn")
	else:
		game.toast("Rope ×4", "info")
	c["ropes"] = 4
	c["rope"] = ""


func ropes_pending() -> bool:
	var c := StoryState.ch1(state)
	return 4 in c["done"] and int(c["ropes"]) > 0 and c["rope"] == ""


func keep_ropes() -> void:
	if not ropes_pending() or running != 0:
		return
	var c := StoryState.ch1(state)
	c["rope"] = "kept"
	c["ropes"] = 0
	overlay.hide_choice()
	game.toast("You keep the ropes.", "info")
	game._autosave("story")


## Why the ropes can't be burned now ("" = they can).
func burn_block_reason() -> String:
	if not game.is_home():
		return "Only at home."
	var h: Variant = game.get("home")
	var fp: Variant = h.get("fireplace") if h != null else null
	if not (fp is Fireplace) or not is_instance_valid(fp):
		return "There is no fireplace."
	if not (fp as Fireplace).lit:
		return "The fire is out. Light it first."
	if ropes_available() < 4:
		return "The four ropes aren't all here any more."
	if fire_path().is_empty():
		return "You can't get to the fireplace from here."
	return ""


func ropes_available() -> int:
	var n := state.inventory.count("rope")
	var pile := _pile()
	if pile != null:
		n += int(pile.items.get("rope", 0))
	return n


func _pile() -> WorldObject:
	var uid := str(StoryState.ch1(state).get("pile", ""))
	var w: Variant = game.get("world")
	if uid == "" or w == null or w.get("objects") == null:
		return null
	for o in w.objects:
		if o is WorldObject and (o as WorldObject).uid == uid:
			return o
	return null


## Where Eli stands to throw (in front of the firebox).
func fire_stand() -> Vector2:
	var c := Fireplace.RECT.get_center()
	var nav: Variant = game.world.get("nav") if game.get("world") != null else null
	for off in [Vector2(0.0, 0.95), Vector2(-0.12, 1.0), Vector2(0.0, 1.15), Vector2(-0.2, 0.85), Vector2(0.15, 1.2), Vector2(-0.25, 1.3)]:
		var p: Vector2 = c + off
		if nav == null or (nav as GridNav).is_walkable((nav as GridNav).cell_of(p)):
			return p
	return c + Vector2(0.0, 1.0)


func fire_mouth() -> Vector3:
	var c := Fireplace.RECT.get_center()
	return Vector3(c.x, 0.35, Fireplace.RECT.end.y - 0.15)


## A real walking path from Eli to the fireplace (through doors, which he
## opens), or [] when there is none: no impossible pathfinding.
func fire_path() -> PackedVector2Array:
	var none := PackedVector2Array()
	var lv: Variant = game.get("levels")
	if lv != null and int(lv.get("player_storey")) != 0:
		return none
	var w: Variant = game.get("world")
	if w == null or w.get("nav") == null:
		return none
	var nav: GridNav = w.nav
	var to := fire_stand()
	var path := nav.find_path(game.player.plan_pos(), to)
	if path.is_empty() or path[path.size() - 1].distance_to(to) > 0.45:
		return none
	for p in path:
		if not nav.is_walkable(nav.cell_of(p)):
			var o: Variant = w.object_at(p, 0.35) if w.has_method("object_at") else null
			if not (o is WorldObject and (o as WorldObject).kind == "door"):
				return none
	return path


## Burn the ropes: Eli says so to himself, walks to the fire by himself,
## throws them in, watches them burn. Exactly four go. `prev` (F10): the same
## scene, nothing removed.
func burn_ropes(prev := false) -> String:
	if running != 0:
		return "A story scene is running."
	var why := burn_block_reason() if not prev else ("" if game.is_home() else "Only at home.")
	if why != "":
		game.toast(why, "warn")
		return why
	var path := fire_path()
	_start(BURN, prev)
	phase = "thoughts"
	overlay.hide_choice()
	_lock_control("story")
	_frame_bed()                                # the game camera closer
	var lines: Array = StoryLines.THOUGHTS["burn"]
	await _think(lines[0], 2.3)
	overlay.say(lines[1], "thought", 2.6 / speed)
	phase = "walk"
	if not path.is_empty():
		await _walk(path)
	var mouth := fire_mouth()
	var p: VoxelPlayer = game.player
	p.aim_point = mouth + Vector3(0.0, 0.6, 0.0)
	await _wait(0.6)
	phase = "throw"
	for k in 2:
		p.rig.aiming = false
		p.rig.use_t = 1.0
		await _wait(0.25)
		stage.throw_ropes(p.rig.hand_global(), mouth, 2)
		await _wait(0.6)
	await _wait(0.35)
	stage.flare(mouth)
	phase = "watch"
	await _wait(3.0)
	if not prev:
		_take_ropes(4)
		var c := StoryState.ch1(state)
		c["rope"] = "burned"
		c["ropes"] = 0
		c["pile"] = ""
	stage.restore()
	_unlock_control()
	running = 0
	preview = false
	_skip = false
	phase = ""
	encounter_finished.emit(BURN, prev)
	if not prev:
		game._autosave("story")
	return "The ropes burn." if not prev else "Rope burning previewed"


## Takes exactly `n` ropes: from the pile by the bed first, then the inventory.
func _take_ropes(n: int) -> void:
	var pile := _pile()
	if pile != null:
		var k := mini(n, int(pile.items.get("rope", 0)))
		if k > 0:
			pile.items["rope"] = int(pile.items["rope"]) - k
			if int(pile.items["rope"]) <= 0:
				pile.items.erase("rope")
			n -= k
		if pile.items.is_empty() and game.world.has_method("remove_object"):
			game.world.remove_object(pile)
	if n > 0:
		state.inventory.remove("rope", mini(n, state.inventory.count("rope")))


func _walk(path: PackedVector2Array) -> void:
	var p: VoxelPlayer = game.player
	for i in range(1, path.size()):
		var goal := Vector3(path[i].x, p.floor_y, path[i].y)
		while not _skip and is_inside_tree():
			_open_door_near(goal)
			var d := goal - p.global_position
			d.y = 0.0
			if d.length() < 0.04:
				break
			var step := minf(WALK * _dt, d.length())
			p.global_position += d.normalized() * step
			p.aim_point = p.global_position + d.normalized() * 3.0 + Vector3(0.0, 1.1, 0.0)
			await tick
	var last := path[path.size() - 1]
	p.global_position = Vector3(last.x, p.floor_y, last.y)


func _open_door_near(at: Vector3) -> void:
	var w: Variant = game.get("world")
	if w == null or not w.has_method("object_at"):
		return
	var o: Variant = w.object_at(Vector2(at.x, at.z), 0.5)
	if o is WorldObject and (o as WorldObject).kind == "door" and not (o as WorldObject).open:
		w.set_door_open(o, true)


func _choice_process(delta: float) -> void:
	_choice_t -= delta
	if _choice_t > 0.0:
		return
	_choice_t = 0.5
	if ropes_pending() and game.is_home() and game.debug_modal() == "" and not state.dead:
		overlay.show_choice(burn_block_reason())
	elif overlay.choice_visible():
		overlay.hide_choice()


# --- Encounter 2: the watcher (§4) -----------------------------------------------------------------

func observer_due() -> bool:
	if not StoryState.eligible(state, 2) or not game.is_home() or state.dead:
		return false
	if game.debug_modal() != "" or game._threats() or (game.build != null and game.build.active):
		return false
	var m := state.minute_of_day()
	return m >= DUSK.x and m <= DUSK.y and state.night_amount() > 0.1


func _observer_process(delta: float) -> void:
	if figure != null:
		_observer_step(delta)
		return
	_obs_t -= delta
	if _obs_t > 0.0:
		return
	_obs_t = 2.0
	if observer_due():
		spawn_observer(false)


## He stands out in the yard near the lot edge (outside the house, at the
## edge of the fog), in view, 8.5-16 m from Eli.
func spawn_observer(prev: bool) -> StoryFigure:
	if figure != null:
		return figure
	var spot := observer_spot()
	figure = StoryFigure.new()
	figure.name = "StoryWatcher"
	figure.target = game.player
	game.add_child(figure)
	figure.global_position = Vector3(spot.x, 0.0, spot.y)
	_obs = {"preview": prev, "seen": 0.0, "t": 0.0, "stage": 0, "next": 0.0, "howl": false, "left": -1.0}
	running = 0
	history.append("%s 2" % ("preview" if prev else "run"))
	encounter_started.emit(2, prev)
	return figure


func observer_spot() -> Vector2:
	var pp: Vector2 = game.player.plan_pos()
	var lot := FogBoundary.LOT.grow(-EDGE_IN)
	var keep_off := HousePlan.FOOTPRINT.grow(1.6)
	var best := Vector2.INF
	var best_score := INF
	var pts: Array = []
	var x := lot.position.x
	while x <= lot.end.x:
		pts.append(Vector2(x, lot.position.y))
		pts.append(Vector2(x, lot.end.y))
		x += 1.5
	var y := lot.position.y
	while y <= lot.end.y:
		pts.append(Vector2(lot.position.x, y))
		pts.append(Vector2(lot.end.x, y))
		y += 1.5
	for q in pts:
		if keep_off.has_point(q):
			continue
		var d: float = (q as Vector2).distance_to(pp)
		var seen := _on_screen(Vector3(q.x, 1.8, q.y), 70.0) and _on_screen(Vector3(q.x, 0.1, q.y), 70.0)
		var score := absf(d - 11.0) + (0.0 if seen else 60.0) + _off_centre(Vector3(q.x, 1.0, q.y)) * 4.0 + (0.0 if d <= 16.0 else 30.0) + (0.0 if d >= NEAR + 1.0 else 500.0) + _rng.randf() * 1.5
		if score < best_score:
			best_score = score
			best = q
	return best


func _on_screen(p: Vector3, margin := 20.0) -> bool:
	var cam: Variant = game.get("camera")
	if not (cam is Camera3D) or not (cam as Camera3D).is_inside_tree():
		return false
	if not (cam as Camera3D).is_position_in_frustum(p):
		return false
	var v := (cam as Camera3D).unproject_position(p)
	var r := get_viewport().get_visible_rect()
	return r.grow(-margin).has_point(v)


## 0 at the centre of the screen .. ~1 at its edges (keeps him clear of the HUD corners).
func _off_centre(p: Vector3) -> float:
	var cam: Variant = game.get("camera")
	if not (cam is Camera3D) or not (cam as Camera3D).is_inside_tree():
		return 0.0
	var r := get_viewport().get_visible_rect()
	var v := (cam as Camera3D).unproject_position(p) - r.get_center()
	return Vector2(v.x / maxf(r.size.x * 0.5, 1.0), v.y / maxf(r.size.y * 0.5, 1.0)).length()


static func _outside(p: Vector2) -> float:
	return -FogBoundary.edge_distance(p)


func _observer_step(delta: float) -> void:
	var f := figure
	var o := _obs
	o["t"] = float(o["t"]) + delta
	var t: float = o["t"]
	var modal: String = game.debug_modal()
	if modal in ["sleeping", "story", "travel", "loading", "death"] or state.dead:
		_observer_gone()                       # the screen is black or elsewhere: nobody sees him go
		return
	var pp: Vector2 = game.player.plan_pos()
	var dist := pp.distance_to(f.plan_pos())
	var vis := _on_screen(f.head_point()) and dist < 26.0
	if vis:
		o["seen"] = float(o["seen"]) + delta
	if not o["howl"] and t > 6.0:
		o["howl"] = true                       # one isolated, distant sound (§36: barely audible)
		var away := (f.plan_pos() - pp).normalized().rotated(_rng.randf_range(-0.8, 0.8)) * 26.0
		audio.play_follower("story/follower_howl" if _rng.randf() < 0.6 else "story/follower_bark",
			Vector3(pp.x + away.x, 1.5, pp.y + away.y), -14.0)
	if f.mode == "watch":
		var st := int(o["stage"])
		if st == 0 and float(o["seen"]) >= 1.0:
			o["stage"] = 1
			overlay.say(StoryLines.THOUGHTS["observer_seen"][0], "thought", 2.8)
			o["next"] = t + 3.6
		elif st == 1 and t >= float(o["next"]):
			o["stage"] = 2
			_observer_voice()
		elif st == 3 and t >= float(o["next"]):
			o["stage"] = 4
			overlay.say(StoryLines.THOUGHTS["observer_voice"][0], "thought", 2.8)
			o["next"] = t + 4.2
		elif st == 4 and t >= float(o["next"]):
			o["stage"] = 5
			overlay.say(StoryLines.THOUGHTS["observer_still"][0], "thought", 3.2)
			o["next"] = t + WATCH
		var go: bool = dist < NEAR or (st == 5 and t >= float(o["next"])) or game._threats() \
				or state.night_amount() < 0.05 or (st == 0 and t > 150.0)
		if go:
			f.leave(_exit_for(f))
			o["left"] = t
	else:
		var out := _outside(f.plan_pos())
		if (out >= 6.0 and not vis) or out >= 9.0 or (not vis and dist > 18.0) or t - float(o["left"]) > 40.0:
			_observer_gone()


## His three lines, from where he stands (the recording made for this encounter).
func _observer_voice() -> void:
	var at := figure.head_point() if figure != null else Vector3.ZERO
	for id in ["watching", "some_time", "comfortable"]:
		await _say(id, at, 2.0)
		await _wait(0.45)
	if not _obs.is_empty():
		_obs["stage"] = 3
		_obs["next"] = float(_obs["t"]) + 1.0


## Out into the fog: away from the house, a little to the side.
func _exit_for(f: StoryFigure) -> Vector3:
	var p := f.plan_pos()
	var c := FogBoundary.LOT.get_center()
	var dir := (p - c).normalized()
	if absf(dir.x) > absf(dir.y):
		dir = Vector2(signf(dir.x), dir.y * 0.4).normalized()
	else:
		dir = Vector2(dir.x * 0.4, signf(dir.y)).normalized()
	var to := p + dir * 11.0 + dir.orthogonal() * _rng.randf_range(-2.0, 2.0)
	return Vector3(to.x, 0.0, to.y)


func _observer_gone() -> void:
	if figure == null:
		return
	var o := _obs
	var prev := bool(o.get("preview", false))
	figure.queue_free()
	figure = null
	_obs = {}
	_obs_t = 4.0
	if not prev:
		if float(o.get("seen", 0.0)) >= 1.0:
			StoryState.complete(state, 2)
			game._autosave("story")
		else:                                   # nobody saw him: another evening
			var c := StoryState.ch1(state)
			c["next_at"] = (floorf(state.total_minutes / StoryState.DAY) + 1.0) * StoryState.DAY + float(StoryState.EVENING[2]) * 60.0
	encounter_finished.emit(2, prev)


## F10: he walks away now.
func dismiss_observer() -> String:
	if figure == null:
		return "He isn't here."
	figure.leave(_exit_for(figure))
	_obs["left"] = float(_obs["t"])
	return "He turns and walks away"


# --- helpers ---------------------------------------------------------------------------------------

func _lock_control(modal: String) -> void:
	if not _lock.is_empty():
		return
	var p: VoxelPlayer = game.player
	var cam: VoxelCamera = game.camera
	_lock = {"input": p.input_enabled, "hud": game.hud.visible, "dist": cam.get("_goal_distance")}
	if game.build != null and game.build.active:
		game._set_build(false)
	game._set_modal(modal, false)
	p.input_enabled = false
	p.velocity = Vector3.ZERO
	game.hud.visible = false


func _unlock_control() -> void:
	if _lock.is_empty():
		return
	var p: VoxelPlayer = game.player
	p.input_enabled = true
	game.hud.visible = bool(_lock["hud"])
	game.camera.set("_goal_distance", float(_lock["dist"]))
	p.set_night(state.night_amount())
	if game.debug_modal() in ["sleeping", "story"]:
		game._set_modal("", false)
	_lock = {}


func _advance(minutes: float) -> void:
	if minutes <= 0.0 or state.dead:
		return
	var t0 := state.total_minutes
	var ev: Array = state.advance(minutes, true)
	game._process_events(ev)
	game._check_stragglers(t0, state.total_minutes)


func _wait(s: float) -> void:
	var goal := _clock + s
	while _clock < goal and not _skip and is_inside_tree():
		await tick


func _fade(a: float, s: float) -> void:
	if _skip or s / speed < 0.02:
		game.ui.fade.set_alpha(a)
		return
	await game.ui.fade.fade_to(a, s / speed)


## Calls f(x) with x going 0..1 over `s` seconds.
func _ramp(s: float, f: Callable) -> void:
	var t0 := _clock
	while _clock - t0 < s and not _skip and is_inside_tree():
		f.call(clampf((_clock - t0) / s, 0.0, 1.0))
		await tick
	f.call(1.0)


func _knock() -> void:
	stage.knock()
	Sfx.play("door/bash", Vector3(StoryStage.DOOR_AT.x, 1.0, StoryStage.DOOR_AT.y), -17.0)


## A spoken cue with its subtitles; returns when it has been said.
func _say(id: String, at: Variant = null, volume_db := 0.0) -> void:
	var c: Dictionary = StoryLines.CUES[id]
	var length := audio.play_cue(id, at, volume_db)
	var from := float(c["from"]) if StoryAudio.custom_file(str(c["name"])) == "" else 0.0
	var subs: Array = c["subs"]
	var t0 := _clock
	for i in subs.size():
		var rel := clampf(float(subs[i][0]) - from, 0.0, length)
		var until := (clampf(float(subs[i + 1][0]) - from, 0.0, length) if i + 1 < subs.size() else length) + 0.7
		await _wait(t0 + rel - _clock)
		overlay.say(str(subs[i][1]), "voice", (until - rel) / speed)
	await _wait(t0 + length - _clock)


func _think(text: String, s: float) -> void:
	overlay.say(text, "thought")
	await _wait(s)
	overlay.clear()


# --- status --------------------------------------------------------------------------------------

func status_text() -> String:
	var s := StoryState.status_text(state)
	if running != 0:
		s += "\nOn screen: %s%s (%s)" % ["the ropes" if running == BURN else StoryState.NAMES.get(running, str(running)),
			" [preview]" if preview else "", phase]
	if figure != null:
		s += "\nThe watcher is outside (%s, seen %.0f s)" % [figure.mode, float(_obs.get("seen", 0.0))]
	if ropes_pending():
		s += "\nRopes waiting for a choice (burn: %s)" % (burn_block_reason() if burn_block_reason() != "" else "possible")
	return s
