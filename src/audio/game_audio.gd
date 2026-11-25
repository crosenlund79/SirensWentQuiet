extends Node
## Experiment 005 (A): the game's audio helper (created in SurvivalGame._assemble,
## the game_*.gd pattern). docs/experiment-005/AUDIO.md.
##
## Every frame it tells the Ambience where the player is (outside, inside,
## exposed room, basement), where the listener and the fireplace are, and
## plays:
##   - the player's footsteps on the gait (src/game/footsteps.gd), per surface;
##   - nearby enemies' footsteps on their gait, when recordings exist;
##   - the fireplace being lit or put out, when recordings exist;
##   - Eli's welcome after a new game's intro, or his line on Continue;
##   - the theme, softly, for a while after dawn (when it exists and no
##     invasion is on).
## F10: dev_status(), dev_toggle_layer(id), dev_play(name).

const Footsteps := preload("res://src/game/footsteps.gd")

const STEP_DB := -4.0
const SPRINT_SPEED := 4.6               ## m/s; faster steps land a little harder
const SPRINT_DB := 2.0
const ENEMY_STEP_DB := -2.0
const ENEMY_STEP_RANGE := 16.0
const ENEMY_STEP_MAX := 3               ## nearest enemies heard stepping
const VOICE_DELAY := 1.2                ## seconds after the fade-in / intro
const DAWN_DELAY := 6.0                 ## after the dawn stinger
const DAWN_SECONDS := 95.0              ## how long the theme plays at dawn
const PLACE_EVERY := 0.25               ## seconds between room look-ups

var game: Node
var steps := Footsteps.new()
var last_surface := ""
var steps_played := 0
var enemy_steps_played := 0
var voice_line := ""                    ## the line scheduled or said ("" none)
var _voice_in := -1.0
var _enemy_gait := {}                   ## enemy instance id -> Footsteps
var _place_t := 0.0
var _fire_lit = null
var _night_prev := -1.0
var _dawn_in := -1.0
var _dawn_left := -1.0


func setup(g: Node) -> void:
	game = g
	AudioInbox.prepare_all()          # load and measure the recordings now, not at the first door
	if game.has_signal("invasion_started"):
		game.invasion_started.connect(_on_invasion_started)
	var intro: Node = game.ui.get("intro") if game.get("ui") != null else null
	if GameLaunch.mode == "carry":
		pass                               # Exp 007 (T): arriving by travel, not a new game
	elif GameLaunch.mode == "continue":
		_schedule_voice("voice/eli_continue")
	elif intro != null and intro.has_signal("done"):
		intro.done.connect(_schedule_voice.bind("voice/eli_new_game"), CONNECT_ONE_SHOT)
	else:
		_schedule_voice("voice/eli_new_game")


func _process(delta: float) -> void:
	if game == null or not is_instance_valid(game) or game.get("player") == null:
		return
	var player: Node3D = game.player
	var amb: Ambience = game.get("ambience")
	var storey := player_storey()
	_place_t -= delta
	if amb != null and _place_t <= 0.0:
		_place_t = PLACE_EVERY
		amb.set_place(current_place())
	if amb != null:
		amb.set_listener(player.global_position + Vector3(0, 1.0, 0))
		_sync_fire(amb, storey)
	_player_steps(player, storey)
	_enemy_steps(player, storey)
	_voice_step(delta)
	_dawn_step(delta)


func _exit_tree() -> void:
	Voice.stop()


# --- where the player is ---------------------------------------------------------------

func player_storey() -> int:
	var l: Variant = game.get("levels")
	if l is Object and is_instance_valid(l) and "player_storey" in l:
		return int(l.player_storey)
	return 0


## "outside", "inside", "exposed" (a room open to the outside) or "basement".
func current_place() -> String:
	var storey := player_storey()
	if storey < 0:
		return "basement"
	var p: Vector2 = game.player.plan_pos()
	var comfort: Variant = game.get("comfort")
	if comfort is Object and is_instance_valid(comfort) and comfort.has_method("room_at"):
		var r: Variant = comfort.room_at(storey, p)     # Exp 005 (C), when present
		if r is Dictionary and not (r as Dictionary).is_empty():
			return "exposed" if bool(r.get("exposed", false)) else "inside"
	return "inside" if HousePlan.FOOTPRINT.has_point(p) else "outside"


# --- footsteps --------------------------------------------------------------------------

func _player_steps(player: Node3D, storey: int) -> void:
	var rig: VoxelRig = player.get("rig")
	if rig == null:
		return
	if not steps.gait(rig.walk_phase, rig.speed):
		return
	last_surface = Footsteps.surface(storey, Vector2(player.global_position.x, player.global_position.z))
	var db := STEP_DB + (SPRINT_DB if rig.speed > SPRINT_SPEED else 0.0)
	Sfx.play(Footsteps.sound_for(last_surface), null, db)
	steps_played += 1


func _enemy_steps(player: Node3D, storey: int) -> void:
	var roster: Variant = game.get("roster")
	if not (roster is Object and is_instance_valid(roster)) or not ("enemies" in roster):
		return
	var near := []
	for e in roster.enemies:
		if not is_instance_valid(e) or not bool(e.get("alive")) or e.get("rig") == null:
			continue
		if int(e.get("storey") if e.get("storey") != null else 0) != storey:
			continue
		var d: float = (e as Node3D).global_position.distance_to(player.global_position)
		if d <= ENEMY_STEP_RANGE:
			near.append([d, e])
	near.sort_custom(func(a, b): return a[0] < b[0])
	var seen := {}
	for i in mini(near.size(), ENEMY_STEP_MAX):
		var e: Node3D = near[i][1]
		var id := e.get_instance_id()
		seen[id] = true
		if not _enemy_gait.has(id):
			_enemy_gait[id] = Footsteps.new()
		var rig: VoxelRig = e.get("rig")
		if not (_enemy_gait[id] as Footsteps).gait(rig.walk_phase, rig.speed):
			continue
		var inside := storey != 0 or HousePlan.FOOTPRINT.has_point(Vector2(e.global_position.x, e.global_position.z))
		var n := "enemy/step_wood" if inside else "enemy/step_snow"
		if Sfx.available(n):
			Sfx.play(n, e.global_position + Vector3(0, 0.1, 0), ENEMY_STEP_DB)
			enemy_steps_played += 1
	for id in _enemy_gait.keys():
		if not seen.has(id):
			_enemy_gait.erase(id)


# --- the fireplace ----------------------------------------------------------------------

func _sync_fire(amb: Ambience, storey: int) -> void:
	var home: Variant = game.get("home")
	var fp: Node3D = home.get("fireplace") if home is Object and is_instance_valid(home) else null
	if fp == null or not is_instance_valid(fp):
		amb.set_fireplace(null, false)
		return
	var lit := bool(fp.get("lit"))
	amb.set_fireplace(fp, lit, storey == 0)
	if _fire_lit != null and lit != _fire_lit:
		var n := "home/fireplace_light" if lit else "home/fireplace_out"
		if Sfx.available(n):
			Sfx.play(n, fp.global_position + Vector3(0, 0.6, 0.4))
	_fire_lit = lit


# --- Eli -----------------------------------------------------------------------------

func _schedule_voice(line: String) -> void:
	voice_line = line
	_voice_in = VOICE_DELAY


func _voice_step(delta: float) -> void:
	if _voice_in < 0.0:
		return
	_voice_in -= delta
	if _voice_in <= 0.0:
		_voice_in = -1.0
		if Sfx.available(voice_line):
			Voice.say(voice_line)


# --- the theme at dawn -----------------------------------------------------------------

func _dawn_step(delta: float) -> void:
	var st: Variant = game.get("state")
	if st == null:
		return
	var n: float = st.night_amount()
	if _night_prev >= 0.5 and n < 0.5 and st.minute_of_day() < 720.0:
		_dawn_in = DAWN_DELAY
	_night_prev = n
	if _dawn_in >= 0.0:
		_dawn_in -= delta
		if _dawn_in < 0.0 and Sfx.available("music/dawn") and Sfx.current_music() == "" and not _invasion():
			Sfx.music("music/dawn")
			_dawn_left = DAWN_SECONDS
	if _dawn_left >= 0.0:
		_dawn_left -= delta
		if _dawn_left < 0.0 and Sfx.current_music() == "music/dawn":
			Sfx.music("")


func _invasion() -> bool:
	var d: Variant = game.get("director")
	return d is Object and bool(d.get("active"))


func _on_invasion_started() -> void:
	_dawn_in = -1.0
	_dawn_left = -1.0
	if Sfx.current_music() == "music/dawn":
		Sfx.music("")


# --- developer menu ----------------------------------------------------------------------

## One block of text for the F10 Audio section.
func dev_status() -> String:
	var amb: Ambience = game.get("ambience") if game != null else null
	var lines := PackedStringArray()
	if amb != null:
		var s := amb.layer_status()
		var on := PackedStringArray()
		for id in Ambience.LAYERS:
			on.append("%s %s" % [id, "on" if s["layers"][id] else "OFF"])
		lines.append("Place: %s (outdoor %.0f dB, low-pass %s)" % [s["place"], s["outdoor_db"],
				"off" if s["cutoff"] >= AudioMix.OPEN_CUTOFF - 1.0 else "%d Hz" % int(s["cutoff"])])
		lines.append("Layers: " + ", ".join(on))
		var beds := PackedStringArray()
		for id in amb.beds:
			var b: Dictionary = s[id]
			beds.append("%s %s" % [id, ("%.2f" % b["level"]) if b["available"] else "—"])
		lines.append("Beds: " + ", ".join(beds))
	lines.append("Steps: %s (%d played), enemy steps %d" % [last_surface if last_surface != "" else "—", steps_played, enemy_steps_played])
	lines.append("Music: %s; voice: %s" % [Sfx.current_music() if Sfx.current_music() != "" else "none",
			Voice.last_line if Voice.last_line != "" else "none yet"])
	return "\n".join(lines)


## Turns an ambience layer on or off; returns a line for the menu.
func dev_toggle_layer(id: String) -> String:
	var amb: Ambience = game.get("ambience")
	if amb == null or not amb.layers.has(id):
		return "No layer %s" % id
	amb.set_layer(id, not amb.layers[id])
	return "Ambience %s %s" % [id, "on" if amb.layers[id] else "off"]


## Plays a logical sound by name (voice lines through Voice, loops through
## Sfx.music, details at their place); returns a line for the menu.
func dev_play(name: String) -> String:
	if not Sfx.has(name):
		return "Unknown sound %s" % name
	if not Sfx.available(name):
		return "%s has no file yet" % name
	var src := Sfx.source_of(name)
	if name.begins_with("voice/"):
		Voice.stop()
		return "%s (%s)" % [name, src] if Voice.say(name) else "%s could not play" % name
	if Sfx.is_loop(name):
		if Sfx._def(Sfx.key_of(name))["bus"] == "Music":
			Sfx.music("" if Sfx.current_music() == name else name)
			return "Music: %s" % (Sfx.current_music() if Sfx.current_music() != "" else "off")
		return "%s is an ambience bed: toggle its layer" % name
	var at: Variant = null
	if game != null and game.get("player") != null:
		at = (game.player as Node3D).global_position + Vector3(0, 1.0, 0)
	Sfx.play(name, at)
	return "%s (%s)" % [name, src]
