class_name PsychoVoice
extends RefCounted
## Experiment 009 (P): one dormant psycho's voice (the user's §13): mumbling,
## humming, whispering, the startled silence. A small spatial player of its
## own (an AudioStreamPlayer3D on the enemy, so the voice follows it) with:
##   - one line at a time per enemy, and a pause after each (`gap`);
##   - a global cap: at most CAP voices at once in the whole scene;
##   - distance: inverse-distance fall-off (UNIT, MAX_DISTANCE); no line is
##     started when Eli is farther than RANGE m;
##   - light wall attenuation: WALL_DB and a low-pass when no clear line runs
##     from the enemy to Eli on the nav grid (occlusion_db());
##   - fallbacks: say() takes [name, db, chance] entries and plays the first
##     one that has a file (Sfx.clip: custom/ > the audio inbox > a template).
## Streams come through Sfx.clip, so creator overrides and the inbox apply.
## No sound is generated; a name without a file is simply skipped.

const CAP := 2                    ## voices at once, scene-wide
const RANGE := 20.0               ## m: farther from Eli, no line starts
const UNIT := 5.0                 ## AudioStreamPlayer3D.unit_size
const MAX_DISTANCE := 28.0
const WALL_DB := -6.0             ## through a wall
const WALL_CUTOFF := 1800.0       ## Hz, through a wall
const OPEN_CUTOFF := 7000.0
const HEAD := 1.55                ## m: where the voice comes from

static var _speaking := {}        ## enemy instance id -> end of its line (ms)
static var started := 0           ## lines started (tests, F10)
static var refused := 0           ## lines held back by the cap (tests, F10)

var pause := 0.0                  ## s before this voice may start a line
var line := ""                    ## the last line started
var rng := RandomNumberGenerator.new()
var _end := 0                     ## ms
var _owner_id := 0
var _player: AudioStreamPlayer3D


func _init(seed := 0) -> void:
	rng.seed = seed


## Voices speaking now, scene-wide.
static func active() -> int:
	var now := Time.get_ticks_msec()
	var n := 0
	for id in _speaking.keys():
		if int(_speaking[id]) <= now or instance_from_id(id) == null:
			_speaking.erase(id)
		else:
			n += 1
	return n


## Tests: forget every voice and the counters.
static func reset() -> void:
	_speaking.clear()
	started = 0
	refused = 0


## dB to add for a sound at enemy e when walls stand between it and Eli.
static func occlusion_db(e: Node) -> float:
	return WALL_DB if occluded(e) else 0.0


static func occluded(e: Node) -> bool:
	if not (e is AIEnemy) or not is_instance_valid(e):
		return false
	var en := e as AIEnemy
	var pl = en.player
	if en.nav == null or pl == null or not is_instance_valid(pl) or not (pl is Node3D):
		return false
	var g := (pl as Node3D).global_position
	return not en.nav.segment_clear(en.plan_pos(), Vector2(g.x, g.z))


func speaking() -> bool:
	return _end > Time.get_ticks_msec()


func tick(delta: float) -> void:
	pause = maxf(pause - delta, 0.0)
	if _end != 0 and not speaking():
		_end = 0
		if _player != null and is_instance_valid(_player) and _player.playing:
			_player.stop()                 # a trimmed clip ends here


## Stops the line now (it was startled, or it turned on Eli).
func stop() -> void:
	_end = 0
	_speaking.erase(_owner_id)
	if _player != null and is_instance_valid(_player) and _player.playing:
		_player.stop()


## Says the first of `lines` ([name, db, chance]) that has a file, at enemy
## e; `gap` the pause after it (s). `urgent` ignores this voice's pause (not
## the cap). Returns the name started, or "".
func say(e: AIEnemy, lines: Array, gap := Vector2(7.0, 18.0), urgent := false) -> String:
	if e == null or not is_instance_valid(e) or not e.is_inside_tree() or speaking() or (pause > 0.0 and not urgent):
		return ""
	var pl = e.player
	if pl is Node3D and is_instance_valid(pl) and (pl as Node3D).global_position.distance_to(e.global_position) > RANGE:
		pause = rng.randf_range(2.0, 4.0)
		return ""
	if active() >= CAP:
		refused += 1
		pause = rng.randf_range(1.0, 3.0)
		return ""
	for entry in lines:
		var name := str(entry[0])
		var db := float(entry[1]) if entry.size() > 1 else 0.0
		var chance := float(entry[2]) if entry.size() > 2 else 1.0
		if not Sfx.has(name) or not Sfx.available(name) or (chance < 1.0 and rng.randf() >= chance):
			continue
		var c := Sfx.clip(name)
		if c.is_empty() or c.get("stream") == null:
			continue
		var secs := _length(c)
		_play(e, name, c, db)
		_owner_id = e.get_instance_id()
		_end = Time.get_ticks_msec() + int(secs * 1000.0)
		_speaking[_owner_id] = _end
		pause = secs + rng.randf_range(gap.x, gap.y)
		line = name
		started += 1
		return name
	pause = rng.randf_range(gap.x, gap.y) * 0.5      # nothing to say yet: try again later
	return ""


static func _length(c: Dictionary) -> float:
	var from := float(c.get("from", 0.0))
	var to := float(c.get("to", 0.0))
	if to > from:
		return to - from
	var s: AudioStream = c["stream"]
	return maxf(s.get_length() - from, 0.2)


func _play(e: AIEnemy, name: String, c: Dictionary, db: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = AudioStreamPlayer3D.new()
		_player.name = "PsychoVoice"
		_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		_player.unit_size = UNIT
		_player.max_distance = MAX_DISTANCE
		_player.max_db = 0.0
		_player.panning_strength = 0.8
		_player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		_player.position = Vector3(0, HEAD, 0)
		e.add_child(_player)
	var def: Dictionary = Sfx.DEFS.get(Sfx.key_of(name), {})
	var behind := occluded(e)
	_player.stop()
	_player.stream = c["stream"]
	_player.bus = &"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master"
	_player.volume_db = float(def.get("vol", 0.0)) + db + float(c.get("db", 0.0)) + (WALL_DB if behind else 0.0)
	_player.attenuation_filter_cutoff_hz = WALL_CUTOFF if behind else OPEN_CUTOFF
	var spread := float(def.get("pitch", 0.0))
	_player.pitch_scale = 1.0 + rng.randf_range(-spread, spread) if spread > 0.0 else 1.0
	_player.play(float(c.get("from", 0.0)))
