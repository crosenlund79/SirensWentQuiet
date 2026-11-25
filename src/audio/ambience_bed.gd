class_name AmbienceBed
extends Node
## Experiment 005 (A): one continuous ambience layer (the winter forest, the
## fireplace, a room tone) played from a pool of recordings.
##
## The recordings aren't seamless loops, so the bed never loops a file: near
## the end of one it cross-fades over XFADE seconds into another (a random
## one, or the same one again when there is only one). `gain` is the target
## level (linear 0..1, set by Ambience); the bed glides to it and stops its
## players while silent. Positional beds (the fireplace) are placed with
## `place()` and heard through the scene's AudioListener3D.

const XFADE := 3.0
const GLIDE := 1.5                     ## seconds to follow a gain change

var logical := ""
var bus := &"Ambient"
var positional := false
var gain := 0.0
var level_db := 0.0                    ## added to every clip (the layer's mix level)
var unit_size := 2.5
var max_distance := 18.0

var _g := 0.0
var _players: Array = []
var _fade := [0.0, 0.0]
var _fade_rate := [0.0, 0.0]           ## per second (+ in, - out)
var _clip_db := [0.0, 0.0]
var _main := -1
var _rng := RandomNumberGenerator.new()


func setup(name_: String, bus_: StringName, positional_ := false) -> AmbienceBed:
	logical = name_
	bus = bus_
	positional = positional_
	name = name_.get_file().capitalize().replace(" ", "")
	return self


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	for i in 2:
		var p: Node
		if positional:
			var p3 := AudioStreamPlayer3D.new()
			p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
			p3.unit_size = unit_size
			p3.max_distance = max_distance
			p3.max_db = 2.0
			p3.panning_strength = 0.6
			p3.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
			p = p3
		else:
			p = AudioStreamPlayer.new()
		p.name = "P%d" % i
		p.bus = bus if AudioServer.get_bus_index(bus) >= 0 else &"Master"
		add_child(p)
		_players.append(p)


## True when the layer has recordings to play.
func available() -> bool:
	return logical != "" and Sfx.available(logical)


func playing() -> bool:
	return _main >= 0 and (_players[_main] as Node).get("playing")


## The current smoothed level (linear).
func level() -> float:
	return _g


## World position of a positional bed.
func place(at: Vector3) -> void:
	for p in _players:
		if p is AudioStreamPlayer3D and p.is_inside_tree():
			(p as AudioStreamPlayer3D).global_position = at


func _process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	if _players.is_empty():
		return
	var k := 1.0 - exp(-delta * 3.0 / GLIDE)
	_g = lerpf(_g, gain, k)
	if absf(_g - gain) < 0.002:
		_g = gain
	if _g <= 0.001 and gain <= 0.0:
		if _main >= 0:
			for p in _players:
				p.stop()
			_main = -1
		return
	if _main < 0:
		if not available():
			return
		_start(0, true)
	else:
		var p: Node = _players[_main]
		var s: AudioStream = p.get("stream")
		var left := s.get_length() - float(p.get_playback_position()) if s != null else 0.0
		if not p.get("playing") or (left <= XFADE and _fade_rate[_main] >= 0.0):
			var other := 1 - _main
			_fade_rate[_main] = -1.0 / maxf(minf(left, XFADE), 0.1)
			_start(other, false)
	for i in 2:
		var p: Node = _players[i]
		if not p.get("playing"):
			continue
		_fade[i] = clampf(_fade[i] + _fade_rate[i] * delta, 0.0, 1.0)
		if _fade[i] <= 0.0 and _fade_rate[i] < 0.0:
			p.stop()
			continue
		p.set("volume_db", level_db + _clip_db[i] + linear_to_db(maxf(_g * _fade[i], 0.00001)))


func _start(i: int, first: bool) -> void:
	var c := Sfx.clip(logical)
	if c.is_empty():
		return
	var p: Node = _players[i]
	var s: AudioStream = c["stream"]
	p.set("stream", s)
	_clip_db[i] = float(c["db"])
	var from := float(c["from"])
	if first:
		# a random point, so the layer doesn't always begin the same way
		from = _rng.randf_range(0.0, maxf(s.get_length() - XFADE * 3.0, 0.0))
		_fade[i] = 1.0
		_fade_rate[i] = 0.0
	else:
		_fade[i] = 0.0
		_fade_rate[i] = 1.0 / XFADE
	p.set("volume_db", level_db + _clip_db[i] + linear_to_db(maxf(_g * _fade[i], 0.00001)))
	p.call("play", from)
	_main = i
