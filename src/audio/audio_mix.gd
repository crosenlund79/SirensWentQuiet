class_name AudioMix
extends RefCounted
## Experiment 005 (A): the extra buses the layered ambience and Eli's voice
## use, created at runtime so default_bus_layout.tres stays as it is.
##
##   Outdoor  -> Ambient   wind, forest, night bed, owls, wolves, distant noises;
##                         its volume and low-pass follow where the player is
##                         (outside / inside / basement), see Ambience
##   Voice    -> Master    Eli's lines (no slider; the Master slider scales it)
##   Ambient, Music get a "VoiceDuck" amplifier that Voice turns down a few dB
##                         while a line plays (the settings sliders own the bus
##                         volumes, so the duck never touches them)
##
## Static, no Autoload. ensure_buses() is idempotent; Sfx.attach calls it.

const OUTDOOR := "Outdoor"
const VOICE := "Voice"
const DUCK_NAME := "VoiceDuck"
const DUCKED := ["Ambient", "Music"]
const OPEN_CUTOFF := 20000.0          ## the outdoor filter is bypassed at or above this

static var _duck_db := 0.0
static var _duck_tween: Tween


## Creates the Outdoor and Voice buses and the duck amplifiers if missing.
static func ensure_buses() -> void:
	if AudioServer.get_bus_index(OUTDOOR) < 0:
		var i := AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, OUTDOOR)
		AudioServer.set_bus_send(i, &"Ambient" if AudioServer.get_bus_index("Ambient") >= 0 else &"Master")
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = OPEN_CUTOFF
		lp.resonance = 0.5
		AudioServer.add_bus_effect(i, lp, 0)
		AudioServer.set_bus_effect_enabled(i, 0, false)
	if AudioServer.get_bus_index(VOICE) < 0:
		var v := AudioServer.bus_count
		AudioServer.add_bus(v)
		AudioServer.set_bus_name(v, VOICE)
		AudioServer.set_bus_send(v, &"Master")
	for bus in DUCKED:
		if _duck_effect(bus) == null:
			var b := AudioServer.get_bus_index(bus)
			if b >= 0:
				var amp := AudioEffectAmplify.new()
				amp.resource_name = DUCK_NAME
				amp.volume_db = _duck_db
				AudioServer.add_bus_effect(b, amp)


## The Outdoor bus: volume (dB) and low-pass cutoff (Hz; >= OPEN_CUTOFF bypasses it).
static func set_outdoor(volume_db: float, cutoff_hz: float) -> void:
	ensure_buses()
	var i := AudioServer.get_bus_index(OUTDOOR)
	if i < 0:
		return
	AudioServer.set_bus_volume_db(i, volume_db)
	var lp := AudioServer.get_bus_effect(i, 0) as AudioEffectLowPassFilter
	if lp != null:
		var open := cutoff_hz >= OPEN_CUTOFF - 1.0
		lp.cutoff_hz = clampf(cutoff_hz, 20.0, OPEN_CUTOFF)
		if AudioServer.is_bus_effect_enabled(i, 0) == open:
			AudioServer.set_bus_effect_enabled(i, 0, not open)


static func outdoor_volume_db() -> float:
	var i := AudioServer.get_bus_index(OUTDOOR)
	return AudioServer.get_bus_volume_db(i) if i >= 0 else 0.0


static func outdoor_cutoff() -> float:
	var i := AudioServer.get_bus_index(OUTDOOR)
	if i < 0 or not AudioServer.is_bus_effect_enabled(i, 0):
		return OPEN_CUTOFF
	var lp := AudioServer.get_bus_effect(i, 0) as AudioEffectLowPassFilter
	return lp.cutoff_hz if lp != null else OPEN_CUTOFF


static func mute_outdoor(on: bool) -> void:
	ensure_buses()
	var i := AudioServer.get_bus_index(OUTDOOR)
	if i >= 0:
		AudioServer.set_bus_mute(i, on)


## Glides the voice duck on Ambient and Music to `db` over `seconds`.
static func duck(db: float, seconds := 0.4) -> void:
	ensure_buses()
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	_duck_tween = null
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or seconds <= 0.0:
		_set_duck(db)
		return
	_duck_tween = tree.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_duck_tween.tween_method(_set_duck, _duck_db, db, seconds)


static func duck_db() -> float:
	return _duck_db


static func _set_duck(db: float) -> void:
	_duck_db = db
	for bus in DUCKED:
		var amp := _duck_effect(bus)
		if amp != null:
			amp.volume_db = db


static func _duck_effect(bus: String) -> AudioEffectAmplify:
	var b := AudioServer.get_bus_index(bus)
	if b < 0:
		return null
	for k in AudioServer.get_bus_effect_count(b):
		var e := AudioServer.get_bus_effect(b, k)
		if e is AudioEffectAmplify and e.resource_name == DUCK_NAME:
			return e
	return null
