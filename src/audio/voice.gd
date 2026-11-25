class_name Voice
extends RefCounted
## Experiment 005 (A): Elias "Eli" Walker's voice lines.
##
##   Voice.say("voice/eli_new_game")    # -> false when it can't (no file, already speaking)
##
## One line at a time, never overlapping, on the Voice bus (AudioMix), flat.
## While a line plays, the ambience and the music duck by DUCK_DB (AudioMix's
## amplifiers, so the settings sliders are untouched) and come back after it.
## The file comes from Sfx.clip: custom/ > the audio inbox > nothing (there
## are no generated voice templates). The player lives under the SceneTree
## root, so a line survives a scene change unless stop() is called.

const DUCK_DB := -6.0
const DUCK_IN := 0.35
const DUCK_OUT := 1.2

static var last_line := ""
static var lines_said := 0
static var _player_id := 0


## Plays `name` now unless a line is already playing. True if it started.
static func say(name: String) -> bool:
	if speaking():
		return false
	var c := Sfx.clip(name)
	if c.is_empty():
		return false
	var p := _player()
	if p == null:
		return false
	p.stream = c["stream"]
	p.bus = AudioMix.VOICE if AudioServer.get_bus_index(AudioMix.VOICE) >= 0 else &"Master"
	p.volume_db = float(Sfx._def(Sfx.key_of(name))["vol"]) + float(c["db"])
	p.play(float(c["from"]))
	last_line = name
	lines_said += 1
	AudioMix.duck(DUCK_DB, DUCK_IN)
	return true


static func speaking() -> bool:
	var p := _existing()
	return p != null and p.playing


## Stops the current line and lifts the duck.
static func stop() -> void:
	var p := _existing()
	if p != null and p.playing:
		p.stop()
		AudioMix.duck(0.0, DUCK_OUT)


static func _existing() -> AudioStreamPlayer:
	if _player_id == 0:
		return null
	var o := instance_from_id(_player_id)
	if not is_instance_valid(o) or not (o as Node).is_inside_tree():
		return null
	return o as AudioStreamPlayer


static func _player() -> AudioStreamPlayer:
	var p := _existing()
	if p != null:
		return p
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	AudioMix.ensure_buses()
	p = AudioStreamPlayer.new()
	p.name = "Voice"
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	p.finished.connect(func(): AudioMix.duck(0.0, DUCK_OUT))
	tree.root.add_child(p)
	_player_id = p.get_instance_id()
	return p
