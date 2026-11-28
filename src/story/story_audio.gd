class_name StoryAudio
extends Node
## Exp 012 (S): the sound of the story (ASSIGNMENT §35-37). The user's
## recordings for the man the story calls "him" (internally "The Architect":
## a development name, never shown) and his followers are played here and
## nowhere else. This file is the only one in src/story/ that reads those
## file names.
##
## Files (assets/audio/_inbox/, read only; never moved or rewritten):
##   voice/The Architect - Wakey wakey sunshine ... .mp3      -> story/architect_wakey
##   voice/The Architect - Comfortable ... .mp3               -> story/architect_comfortable
##   voice/The Architect - Random on encounter ... .mp3       -> story/architect_random
##   voice/The Architect - The final encounter ... .mp3       -> story/architect_final
##   Architect followers - human bark like a dog 1-4.wav      -> story/follower_bark
##   Architect followers - human howl like a dog 1-4.wav      -> story/follower_howl
##   Architect followers - human heavy breathing 1-3.wav      -> story/follower_breath
##   Architect followers - banging on tin trash can 1-4.wav   -> story/follower_bin
##   Architect followers - basebal bat hammers door ... 1-4   -> story/follower_bat
## AudioInbox holds every file with "architect" in its name back from the
## generic pools and refuses them in clip() (agent A guards that); this class
## scans them itself and loads each stream directly (stream_of: one place to
## swap the loader), never through Sfx or AudioInbox.clip(). A
## creator file custom/audio/<logical name>.ogg|.wav replaces a whole name
## (the voice slots story/architect_warning_01..07 have no recording yet and
## play only from there).
##
## The node plays: voice cues (StoryLines.CUES, a span of a recording), the
## followers' soundscape (levels 1-4 per §36, irregular, spatial players
## around the house, ducked under the voice, controlled silences) and the
## bat impacts with the door jolts in sync (door_impacts.json, §37). Every
## player is in the group "story_audio"; StoryAudio.stop_all() stops them all
## (menu return, load, the end of a cinematic).

signal impact(strength: float)          ## a bat impact on the bedroom door, now

const GROUP := "story_audio"                  ## every story player (a guard may stop and free them)
const HOST_GROUP := "story_audio_host"        ## the StoryAudio nodes themselves (never freed by a guard)
const RESERVED := "architect"
const FOLLOWERS := ["story/follower_bark", "story/follower_howl", "story/follower_breath", "story/follower_bin", "story/follower_bat"]
## File-name keywords of each follower name (lower case).
const FOLLOWER_KEYS := {"story/follower_bark": ["bark"], "story/follower_howl": ["howl"], "story/follower_breath": ["breathing"],
	"story/follower_bin": ["trash", "bin"], "story/follower_bat": ["bat"]}
const LABELS := {"story/follower_bark": "Barking", "story/follower_howl": "Howling", "story/follower_breath": "Heavy breathing",
	"story/follower_bin": "Metal (bins)", "story/follower_bat": "Bat on the door"}
const IMPACTS_PATH := "res://src/story/door_impacts.json"
const VOICE_BUS := "Voice"
const VOICE_DUCK_DB := -10.0           ## followers under the voice
## Per level (§36): category -> [min, max] seconds between sounds, base dB, max at once.
const SCAPES := {
	1: {"story/follower_breath": [9.0, 15.0, -10.0]},
	3: {"story/follower_bark": [3.0, 7.5, -5.0], "story/follower_howl": [7.0, 13.0, -7.0],
		"story/follower_bin": [4.5, 9.0, -6.0], "story/follower_breath": [8.0, 13.0, -9.0]},
	4: {"story/follower_bark": [0.6, 2.0, -1.0], "story/follower_howl": [2.2, 4.8, -3.0],
		"story/follower_bin": [1.0, 2.8, -2.0], "story/follower_breath": [2.5, 5.5, -4.0]},
}
const MAX_AT_ONCE := {1: 1, 3: 4, 4: 9}

static var _files := {}                ## logical name -> Array of paths, variant order
static var _scanned := false
static var _streams := {}              ## path -> AudioStream
static var _spans := {}                ## path -> Array of [from, to] (sound spans)
static var _impacts := {}              ## door_impacts.json (parsed)
static var _ducking := false           ## this class holds the AudioMix duck

var speed := 1.0                       ## clock scale (tests fast-forward)
var intensity := 1.0                   ## F10: background density and volume (0..1.5)
var level := 0                         ## the soundscape now (0 = none)
var silenced := false
var center := Vector3(7.0, 0.0, 4.5)   ## the house
var door_at := Vector3(2.5, 1.1, 4.3)  ## just beyond the bedroom door (living-room side)
var window_at := Vector3(2.0, 1.4, -1.3)   ## outside the bedroom window
var last_bat := {}                     ## {"variant", "onsets"} of the last bat recording played
var history: Array[String] = []        ## what played (tests, F10)
var _clock := 0.0
var _next := {}                        ## category -> clock time of its next sound
var _players: Array = []               ## {"p", "name", "variant", "db", "end", "fade_in", "fade_out", "t0", "voice"}
var _jolts: Array = []                 ## [clock time, strength]
var _duck := 0.0
var _voice_until := -1.0
var _rng := RandomNumberGenerator.new()
var _last_variant := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(HOST_GROUP)
	_rng.randomize()


func _exit_tree() -> void:
	stop()


# --- files ------------------------------------------------------------------------------------

## Finds the recordings (once per session, again with `force`).
static func scan(force := false) -> void:
	if _scanned and not force:
		return
	_scanned = true
	_files.clear()
	var found := {}
	for root in AudioInbox.roots():
		for path in AudioInbox.list_audio_files(root):
			var low := path.get_file().to_lower()
			if not low.contains(RESERVED):
				continue
			var n := classify(low)
			if n == "":
				push_warning("StoryAudio: '%s' matches no story sound" % path)
				continue
			if not found.has(n):
				found[n] = []
			found[n].append([int(AudioInbox.split_variant(path.get_file().get_basename())[1]), path])
	for n in found:
		var list: Array = found[n]
		list.sort_custom(func(a, b): return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
		_files[n] = list.map(func(x): return x[1])


## The logical name of a (lower-case) story file name, or "".
static func classify(low: String) -> String:
	if low.contains("followers"):
		for n in FOLLOWER_KEYS:
			for k in FOLLOWER_KEYS[n]:
				if AudioInbox.words(low).has(k) or low.contains(" " + k + " "):
					return n
		return ""
	for n in StoryLines.VOICE_FILES:
		for k in StoryLines.VOICE_FILES[n]:
			if low.contains(k):
				return n
	return ""


## The recordings of `name` (paths), plus a creator override if there is one.
static func files_of(name: String) -> Array:
	scan()
	var custom := custom_file(name)
	if custom != "":
		return [custom]
	return (_files.get(name, []) as Array).duplicate()


static func has_recording(name: String) -> bool:
	return not files_of(name).is_empty()


static func variants(name: String) -> int:
	return files_of(name).size()


## custom/audio/<name>.ogg|.wav next to the game (or in the project), or "".
static func custom_file(name: String) -> String:
	for ext in AssetResolver.audio_override_formats():
		var p := AssetResolver.audio_override_path(name, ext)
		if FileAccess.file_exists(p):
			return p
	return ""


static func stream_of(path: String) -> AudioStream:
	if path == "":
		return null
	if not _streams.has(path):
		var s: AudioStream = null
		if path.begins_with("res://"):
			s = AudioInbox.load_stream(path)
		elif path.get_extension().to_lower() == "ogg":
			s = AudioStreamOggVorbis.load_from_file(path)
		elif path.get_extension().to_lower() == "wav":
			s = AudioStreamWAV.load_from_file(path)
		_streams[path] = s
	return _streams[path]


## The stream of `name`'s variant (0-based; -1 = any, not the last one played).
func pick(name: String, variant := -1) -> Array:
	var files := files_of(name)
	if files.is_empty():
		return [-1, null]
	var i := variant
	if i < 0 or i >= files.size():
		i = _rng.randi() % files.size()
		if files.size() > 1 and i == int(_last_variant.get(name, -1)):
			i = (i + 1 + _rng.randi() % (files.size() - 1)) % files.size()
	_last_variant[name] = i
	return [i, stream_of(files[i])]


# --- analysis (no files are written) ----------------------------------------------------------

## Sound spans of a recording: [[from, to], ...] where the level is within
## `range_db` of its loudest 20 ms window; gaps shorter than `merge` join.
static func speech_spans(stream: AudioStream, range_db := 30.0, merge := 0.3) -> Array:
	var w := 0.02
	var env := AudioAnalysis.envelope(stream, w, 8.0)
	var loud := -INF
	for v in env:
		loud = maxf(loud, linear_to_db(maxf(v, 1e-7)))
	var out: Array = []
	var on := -1
	for i in env.size() + 1:
		var above := i < env.size() and linear_to_db(maxf(env[i], 1e-7)) >= loud - range_db
		if above and on < 0:
			on = i
		elif not above and on >= 0:
			if not out.is_empty() and on * w - float(out[-1][1]) < merge:
				out[-1][1] = i * w
			else:
				out.append([on * w, i * w])
			on = -1
	return out.filter(func(s): return float(s[1]) - float(s[0]) >= 0.06)


## Impact onsets of a bat recording (seconds): the start of each sharp rise
## (> 14 dB within 60 ms, to within 22 dB of the loudest), at least 0.25 s apart.
static func impact_onsets(stream: AudioStream) -> Array:
	var w := 0.005
	var env := AudioAnalysis.envelope(stream, w, 2.0)
	var db := PackedFloat32Array()
	var loud := -INF
	for v in env:
		db.append(linear_to_db(maxf(v, 1e-7)))
		loud = maxf(loud, db[-1])
	var out: Array = []
	var last := -10.0
	for i in db.size():
		var back := maxi(i - 12, 0)
		var floor_db := db[back]
		for k in range(back, i):
			floor_db = minf(floor_db, db[k])
		if db[i] > loud - 22.0 and db[i] - floor_db > 14.0 and i * w - last > 0.25:
			var j := i
			while j > 0 and db[j - 1] < db[j] - 0.5 and i - j < 12:
				j -= 1
			out.append(snappedf(j * w, 0.005))
			last = i * w
	return out


## The door-impact data (door_impacts.json): {"latency", "files": {"1": {"offset", "onsets"}, ...}}.
static func impacts() -> Dictionary:
	if _impacts.is_empty():
		var txt := FileAccess.get_file_as_string(IMPACTS_PATH)
		var d: Variant = JSON.parse_string(txt) if txt != "" else null
		_impacts = d if typeof(d) == TYPE_DICTIONARY else {"latency": 0.0, "files": {}}
	return _impacts


## Onsets of bat variant `i` (0-based): [[seconds, strength], ...] with its
## offset and the latency applied; detected at runtime when the data has none.
static func onsets_of(i: int, stream: AudioStream = null) -> Array:
	var f: Variant = (impacts().get("files", {}) as Dictionary).get(str(i + 1))
	var global := float(impacts().get("latency", 0.0))
	var out: Array = []
	if typeof(f) == TYPE_DICTIONARY and typeof(f.get("onsets")) == TYPE_ARRAY:
		var off := float(f.get("offset", 0.0)) + global
		for o in f["onsets"]:
			if typeof(o) == TYPE_ARRAY and (o as Array).size() >= 1:
				out.append([float(o[0]) + off, float(o[1]) if (o as Array).size() > 1 else 1.0])
			elif typeof(o) in [TYPE_INT, TYPE_FLOAT]:
				out.append([float(o) + off, 1.0])
		return out
	if stream != null:
		for t in impact_onsets(stream):
			out.append([float(t) + global, 1.0])
	return out


# --- playing ----------------------------------------------------------------------------------

## Plays voice cue `id` (StoryLines.CUES). `at`: a Vector3 makes it spatial
## (beyond a door, outside a window), null plays it flat and clear. Returns
## the seconds it lasts (a slot without a recording: its estimate, silent).
func play_cue(id: String, at: Variant = null, volume_db := 0.0) -> float:
	var c: Dictionary = StoryLines.CUES.get(id, {})
	if c.is_empty():
		return 0.0
	var name: String = c["name"]
	var custom := custom_file(name)
	var files := files_of(name)
	var stream: AudioStream = stream_of(files[0]) if not files.is_empty() else null
	var from := float(c["from"]) if custom == "" else 0.0
	var to := float(c["to"]) if custom == "" else -1.0
	if stream == null:
		history.append("cue %s (no recording: subtitle only)" % id)
		_voice_until = _clock + float(c.get("est", 2.0))
		return float(c.get("est", 2.0))
	if to < 0.0 or to > stream.get_length():
		to = stream.get_length()
	var p := _player(at, VOICE_BUS)
	p.stream = stream
	p.volume_db = volume_db
	if p is AudioStreamPlayer3D:
		(p as AudioStreamPlayer3D).unit_size = 9.0
		(p as AudioStreamPlayer3D).max_db = 3.0
	p.play(from)
	var length := maxf(to - from, 0.05)
	_players.append({"p": p, "name": name, "variant": 0, "db": volume_db, "t0": _clock, "end": _clock + length,
		"fade_in": 0.0, "fade_out": 0.06, "voice": true, "label": id})
	_voice_until = _clock + length
	history.append("cue %s" % id)
	return length


## Plays a whole voice recording (F10 preview). Returns its length.
func play_voice_file(name: String) -> float:
	var r := pick(name, 0)
	var s: AudioStream = r[1]
	if s == null:
		return 0.0
	var p := _player(null, VOICE_BUS)
	p.stream = s
	p.play()
	_players.append({"p": p, "name": name, "variant": 0, "db": 0.0, "t0": _clock, "end": _clock + s.get_length(),
		"fade_in": 0.0, "fade_out": 0.05, "voice": true, "label": name})
	_voice_until = _clock + s.get_length()
	return s.get_length()


func voice_active() -> bool:
	return _clock < _voice_until


## One follower sound (a short burst of the recording) at `at` (Vector3;
## null = flat). Returns its length.
func play_follower(name: String, at: Variant = null, volume_db := 0.0, variant := -1, whole := false) -> float:
	var r := pick(name, variant)
	var s: AudioStream = r[1]
	if s == null:
		return 0.0
	var from := 0.0
	var to := s.get_length()
	var fade_in := 0.03
	var fade_out := 0.2
	var path: String = files_of(name)[r[0]]
	if not whole:
		match name:
			"story/follower_bark", "story/follower_bin":
				var spans := _spans_of(path, s)
				if spans.size() > 0:
					var a := _rng.randi() % spans.size()
					var b := mini(a + _rng.randi_range(0, 2), spans.size() - 1)
					from = maxf(float(spans[a][0]) - 0.03, 0.0)
					to = minf(float(spans[b][1]) + 0.3, s.get_length())
			"story/follower_breath":
				var span := _rng.randf_range(3.0, 6.0)
				from = _rng.randf_range(0.2, maxf(s.get_length() - span - 0.2, 0.25))
				to = minf(from + span, s.get_length())
				fade_in = 0.7
				fade_out = 0.9
			"story/follower_howl":
				var spans := _spans_of(path, s)
				if spans.size() > 0:
					from = maxf(float(spans[0][0]) - 0.03, 0.0)
					to = minf(float(spans[-1][1]) + 0.3, s.get_length())
	var p := _player(at, "SFX")
	p.stream = s
	var pitch := _rng.randf_range(0.96, 1.04) if not whole else 1.0
	p.set("pitch_scale", pitch)
	if p is AudioStreamPlayer3D:
		(p as AudioStreamPlayer3D).unit_size = 7.0
		(p as AudioStreamPlayer3D).max_db = 4.0
	p.volume_db = -60.0 if fade_in > 0.0 else volume_db
	p.play(from)
	var length := (to - from) / pitch
	_players.append({"p": p, "name": name, "variant": r[0], "db": volume_db, "t0": _clock, "end": _clock + length,
		"fade_in": fade_in, "fade_out": fade_out, "voice": false, "label": "%s %d" % [LABELS.get(name, name), r[0] + 1]})
	history.append("%s %d" % [name, r[0] + 1])
	return length


## A bat recording on the bedroom door (whole), the door jolting on every
## impact in it (`impact` fires at each onset). Returns its length.
func play_bat(variant := -1, at: Variant = null, volume_db := 1.0) -> float:
	var r := pick("story/follower_bat", variant)
	var s: AudioStream = r[1]
	if s == null:
		return 0.0
	var p := _player(at if at != null else door_at, "SFX")
	p.stream = s
	if p is AudioStreamPlayer3D:
		(p as AudioStreamPlayer3D).unit_size = 10.0
		(p as AudioStreamPlayer3D).max_db = 6.0
	p.volume_db = volume_db
	p.play()
	var ons := onsets_of(r[0], s)
	for o in ons:
		_jolts.append([_clock + float(o[0]), float(o[1])])
	last_bat = {"variant": r[0], "onsets": ons}
	_players.append({"p": p, "name": "story/follower_bat", "variant": r[0], "db": volume_db, "t0": _clock,
		"end": _clock + s.get_length(), "fade_in": 0.0, "fade_out": 0.05, "voice": false, "label": "Bat on the door %d" % (r[0] + 1)})
	history.append("story/follower_bat %d" % (r[0] + 1))
	return s.get_length()


## The soundscape level (§36): 0 none, 1 Visitor, 2 Observer (one sound by
## hand), 3 Warning, 4 Last Courtesy.
func set_level(n: int) -> void:
	level = n
	_next.clear()
	if SCAPES.has(n):
		for cat in SCAPES[n]:
			_next[cat] = _clock + _rng.randf_range(0.2, float(SCAPES[n][cat][0]))


## Complete silence now: every follower sound stops at once (the voice goes on).
func silence() -> void:
	silenced = true
	_jolts.clear()
	for e in _players:
		if not e["voice"]:
			e["end"] = minf(float(e["end"]), _clock + 0.04)
			e["fade_out"] = 0.04
	history.append("silence")


func unsilence() -> void:
	silenced = false
	set_level(level)


## Lets the followers fade away over `seconds` (and stops the soundscape).
func fade_out_followers(seconds := 2.0) -> void:
	level = 0
	_next.clear()
	for e in _players:
		if not e["voice"]:
			e["end"] = minf(float(e["end"]), _clock + seconds)
			e["fade_out"] = seconds


## Stops everything this node plays.
func stop() -> void:
	for e in _players:
		var p: Node = e["p"]
		if is_instance_valid(p):
			p.call("stop")
			p.queue_free()
	_players.clear()
	_jolts.clear()
	_next.clear()
	level = 0
	silenced = false
	_voice_until = -1.0


## Stops every story player in the tree (menu return, load, a cinematic's end).
static func stop_all(tree: SceneTree = null) -> void:
	if tree == null:
		tree = Engine.get_main_loop() as SceneTree
	if tree != null:
		for n in tree.get_nodes_in_group(HOST_GROUP):
			(n as StoryAudio).stop()
		for n in tree.get_nodes_in_group(GROUP):
			if n is AudioStreamPlayer or n is AudioStreamPlayer3D:
				n.call("stop")
	release_duck()


## Ducks the game's ambience and music under the story (AudioMix).
static func hold_duck(db := -14.0, seconds := 0.6) -> void:
	_ducking = true
	AudioMix.duck(db, seconds)


static func release_duck(seconds := 0.0) -> void:
	if _ducking:
		_ducking = false
		AudioMix.duck(0.0, seconds)


## "playing now" (F10).
func playing_text() -> String:
	var names := []
	for e in _players:
		if is_instance_valid(e["p"]) and _clock < float(e["end"]):
			names.append(str(e["label"]))
	var head := "Level %d%s · intensity %.1f" % [level, " · SILENCE" if silenced else "", intensity]
	return head + (" · " + ", ".join(names) if not names.is_empty() else " · nothing playing")


func playing_count(voice := false) -> int:
	var n := 0
	for e in _players:
		if e["voice"] == voice and is_instance_valid(e["p"]) and _clock < float(e["end"]):
			n += 1
	return n


# --- the clock --------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_clock += delta * speed
	while not _jolts.is_empty() and float(_jolts[0][0]) <= _clock:
		var j: Array = _jolts.pop_front()
		impact.emit(float(j[1]))
	if level > 0 and not silenced and SCAPES.has(level):
		_schedule()
	var want := VOICE_DUCK_DB if voice_active() else 0.0
	_duck = move_toward(_duck, want, delta * 30.0)
	var keep: Array = []
	for e in _players:
		var p: Node = e["p"]
		if not is_instance_valid(p):
			continue
		var t := _clock - float(e["t0"])
		var left := float(e["end"]) - _clock
		if left <= 0.0:
			p.call("stop")
			p.queue_free()
			continue
		var g := 1.0
		if float(e["fade_in"]) > 0.0:
			g = minf(g, t / float(e["fade_in"]))
		if float(e["fade_out"]) > 0.0:
			g = minf(g, left / float(e["fade_out"]))
		var extra := 0.0 if e["voice"] else _duck + linear_to_db(maxf(intensity, 0.05))
		p.set("volume_db", float(e["db"]) + extra + linear_to_db(clampf(g, 0.001, 1.0)))
		keep.append(e)
	_players = keep


func _schedule() -> void:
	var cfg: Dictionary = SCAPES[level]
	for cat in cfg:
		if _clock < float(_next.get(cat, 0.0)):
			continue
		var c: Array = cfg[cat]
		_next[cat] = _clock + _rng.randf_range(float(c[0]), float(c[1])) / maxf(intensity, 0.1)
		if playing_count() >= int(MAX_AT_ONCE.get(level, 4)):
			continue
		play_follower(cat, _spot_for(cat), float(c[2]))


## Where a follower is heard: around the house, from several directions; the
## breathing close (beyond the door, under the window).
func _spot_for(cat: String) -> Vector3:
	if cat == "story/follower_breath":
		var near := [door_at, window_at] if level >= 3 else [door_at]
		return (near[_rng.randi() % near.size()] as Vector3) + Vector3(_rng.randf_range(-0.6, 0.6), 0.0, _rng.randf_range(-0.4, 0.4))
	var ang := _rng.randf_range(0.0, TAU)
	var r := _rng.randf_range(8.0, 13.0) if level >= 4 else _rng.randf_range(11.0, 16.0)
	return center + Vector3(cos(ang) * r, 1.2, sin(ang) * r * 0.8)


func _player(at: Variant, bus: String) -> Node:
	var p: Node
	if at is Vector3:
		var p3 := AudioStreamPlayer3D.new()
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.max_distance = 70.0
		p3.panning_strength = 1.0
		p = p3
	else:
		p = AudioStreamPlayer.new()
	p.set("bus", bus if AudioServer.get_bus_index(bus) >= 0 else "Master")
	p.add_to_group(GROUP)
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	if at is Vector3:
		(p as AudioStreamPlayer3D).global_position = at
	return p


static func _spans_of(path: String, s: AudioStream) -> Array:
	if not _spans.has(path):
		_spans[path] = speech_spans(s, 30.0, 0.12)
	return _spans[path]
