class_name Ambience
extends Node
## Ambient loops and distant noises in the fog (SPEC §7.6). Owner: A.
##
## Add it to the game scene and feed it every frame (or on change):
##   ambience.set_night_amount(state.night_amount())
##   ambience.set_tension(1.0 if invasion_active else 0.0)
## The day wind and the night bed cross-fade with equal power; the tension
## drone fades in during invasions. Distant noises (a metal scrape, a far
## shriek, a dying siren) play every 25-70 s by day and more often at night,
## from a random direction just beyond the lot edge, so they come out of the
## fog. Loops start when the node enters the tree and keep playing while the
## tree is paused; the distant-noise timer pauses with the game.
##
## Experiment 005 (A): layers (docs/experiment-005/AUDIO.md §3).
##   1 outdoor   the winter forest bed (audio inbox), the wind / night loops,
##               owls, wolves and the distant noises, all on the Outdoor bus
##   2 indoor    room tone (inside) or basement tone; the Outdoor bus is turned
##               down and low-passed inside, more so in the basement
##   3 fireplace a positional bed at the hearth, only while it burns
##   4 details   owls and wolves at night, house creaks indoors, random intervals
##   5 threat    the tension drone during invasions (the outdoor beds dip a
##               little and the animals fall silent)
## The game tells it where the player is:
##   ambience.set_place("outside" | "inside" | "exposed" | "basement")
##   ambience.set_listener(player_position)
##   ambience.set_fireplace(fireplace_node, lit, same_storey)
## and the F10 menu toggles layers with set_layer(id, on). Music (6) and voice
## (7) are Sfx.music and Voice. Layers without recordings stay silent.

const LOT := Rect2(-4.5, -3.5, 23.0, 16.0)        ## SPEC §5 (same as FogBoundary.LOT)
const FADE_TIME := 1.5                             ## seconds to follow a change
const DISTANT_DAY := Vector2(25.0, 70.0)           ## seconds between distant noises by day
const DISTANT_NIGHT := Vector2(14.0, 40.0)         ## ... and at full night
const DISTANT_OUTSET := Vector2(2.0, 6.0)          ## metres beyond the lot edge
const DISTANT_HEIGHT := 1.6
const DISTANT_NAMES := ["ambient/distant_1", "ambient/distant_2", "ambient/distant_3"]
## Weights per distant noise (scrape, shriek, siren) by day and at night.
const DISTANT_WEIGHTS_DAY := [0.45, 0.15, 0.4]
const DISTANT_WEIGHTS_NIGHT := [0.35, 0.4, 0.25]
const BASE_DB := {"wind": 0.0, "night": 0.0, "tension": -2.0}

var night_amount := 0.0
var tension := 0.0
## False stops new distant noises (loops keep playing).
var distant_enabled := true

# --- Exp 005 (A): layers ---------------------------------------------------------------
const LAYERS := ["outdoor", "indoor", "fireplace", "details", "threat"]
## Per place: Outdoor bus volume (dB) and low-pass (Hz), room / basement tone gains.
const PLACES := {
	"outside": {"outdoor_db": 0.0, "cutoff": 20000.0, "room": 0.0, "basement": 0.0},
	"inside": {"outdoor_db": -9.0, "cutoff": 1500.0, "room": 1.0, "basement": 0.0},
	"exposed": {"outdoor_db": -4.0, "cutoff": 5000.0, "room": 0.5, "basement": 0.0},   # a room open to the outside
	"basement": {"outdoor_db": -18.0, "cutoff": 520.0, "room": 0.25, "basement": 1.0},
}
const THREAT_DIP_DB := -3.0                         ## outdoor beds during an invasion
const FOREST_NIGHT := 0.55                          ## forest bed gain at full night
const TEMPLATE_TRIM_DB := -6.0                      ## generated wind/night under a recorded forest
const FIRE_OTHER_STOREY := 0.3                      ## the fire heard through a floor
const OWL_EVERY := Vector2(35.0, 90.0)
const WOLF_EVERY := Vector2(70.0, 160.0)
const CREAK_EVERY := Vector2(30.0, 80.0)
const CREAK_HEIGHT := 2.3

var place := "outside"
var layers := {"outdoor": true, "indoor": true, "fireplace": true, "details": true, "threat": true}
var beds := {}                                      ## id -> AmbienceBed: forest, room, basement, fire
var details_played := {"owl": 0, "wolf": 0, "creak": 0}
var _listener := Vector3(7.0, 1.0, 4.5)
var _fire: Node3D
var _fire_lit := false
var _fire_same := true
var _outdoor_db := 0.0
var _cutoff := 20000.0
var _clip_db := {"wind": 0.0, "night": 0.0, "tension": 0.0}
var _trim_db := 0.0
var _next_detail := {}

var _players := {}
var _gain := {"wind": 0.0, "night": 0.0, "tension": 0.0}
var _next_distant := 0.0
var _last_distant := -1
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	AudioMix.ensure_buses()
	for id in ["wind", "night", "tension"]:
		var p := AudioStreamPlayer.new()
		p.name = id.capitalize()
		# Exp 005 (A): wind and night are outdoor sounds (muffled indoors); the drone is not
		var bus := "Ambient" if id == "tension" else AudioMix.OUTDOOR
		p.bus = StringName(bus) if AudioServer.get_bus_index(bus) >= 0 else &"Master"
		p.process_mode = Node.PROCESS_MODE_ALWAYS  # the wind doesn't stop for the pause menu
		var logical: String = {"wind": "ambient/wind_day", "night": "ambient/night", "tension": "ambient/tension"}[id]
		var c := Sfx.clip(logical)           # Exp 005 (A): custom/ > the audio inbox > the template
		p.stream = AudioInbox.looped(c["stream"]) if not c.is_empty() else null
		_clip_db[id] = float(c.get("db", 0.0))
		add_child(p)
		_players[id] = p
	_ready_layers()
	_next_distant = _interval()
	_start_loops()


func _enter_tree() -> void:
	if is_node_ready():
		_start_loops.call_deferred()


func set_night_amount(t: float) -> void:
	night_amount = clampf(t, 0.0, 1.0)


func set_tension(t: float) -> void:
	tension = clampf(t, 0.0, 1.0)


func _process(delta: float) -> void:
	_step(delta)
	_step_layers(delta)
	_step_details(delta)
	if distant_enabled and layers["details"]:
		_next_distant -= delta
		if _next_distant <= 0.0:
			play_distant()
			_next_distant = _interval()


## Plays one distant noise now; returns where (tests, dev menu).
func play_distant(index := -1) -> Vector3:
	if index < 0:
		index = _pick_distant()
	_last_distant = index
	var at := distant_point(_rng.randf() * TAU)
	Sfx.play(DISTANT_NAMES[index], at)
	return at


## A point beyond the lot edge in direction `angle` (radians, plan x/y).
func distant_point(angle: float) -> Vector3:
	var c := LOT.get_center()
	var dir := Vector2.from_angle(angle)
	var tx := LOT.size.x * 0.5 / absf(dir.x) if absf(dir.x) > 1e-4 else INF
	var ty := LOT.size.y * 0.5 / absf(dir.y) if absf(dir.y) > 1e-4 else INF
	var p := c + dir * (minf(tx, ty) + _rng.randf_range(DISTANT_OUTSET.x, DISTANT_OUTSET.y))
	return Vector3(p.x, DISTANT_HEIGHT, p.y)


## The current interval range in seconds (more frequent at night).
func distant_interval_range() -> Vector2:
	return DISTANT_DAY.lerp(DISTANT_NIGHT, night_amount)


## Seconds until the next distant noise.
func next_distant_in() -> float:
	return _next_distant


## Current (smoothed) linear gains: {"wind", "night", "tension"}.
func gains() -> Dictionary:
	return _gain.duplicate()


func player(id: String) -> AudioStreamPlayer:
	return _players.get(id)


func _targets() -> Dictionary:
	return {
		"wind": cos(night_amount * PI * 0.5),
		"night": sin(night_amount * PI * 0.5),
		"tension": tension if layers["threat"] else 0.0,
	}


func _step(delta: float) -> void:
	var k := 1.0 - exp(-delta * 3.0 / FADE_TIME)
	var targets := _targets()
	for id in _players:
		var g: float = lerpf(_gain[id], targets[id], k)
		if absf(g - targets[id]) < 0.001:
			g = targets[id]
		_gain[id] = g
		var p: AudioStreamPlayer = _players[id]
		var trim: float = _clip_db[id] + (_trim_db if id != "tension" else 0.0)
		p.volume_db = BASE_DB[id] + trim + linear_to_db(maxf(g, 0.0001))
		if id == "tension":
			if g > 0.001 and not p.playing and p.stream != null and p.is_inside_tree():
				p.play()
			elif g <= 0.001 and p.playing and targets[id] <= 0.0:
				p.stop()


func _start_loops() -> void:
	for id in ["wind", "night"]:
		var p: AudioStreamPlayer = _players[id]
		if p.stream != null and p.is_inside_tree() and not p.playing:
			p.volume_db = BASE_DB[id] + _clip_db[id] + _trim_db + linear_to_db(maxf(_gain[id], 0.0001))
			p.play()


func _interval() -> float:
	var r := distant_interval_range()
	return _rng.randf_range(r.x, r.y)


func _pick_distant() -> int:
	var w: Array = []
	var total := 0.0
	for i in DISTANT_NAMES.size():
		var v: float = lerpf(DISTANT_WEIGHTS_DAY[i], DISTANT_WEIGHTS_NIGHT[i], night_amount)
		if i == _last_distant:
			v *= 0.15  # rarely the same one twice in a row
		w.append(v)
		total += v
	var r := _rng.randf() * total
	for i in w.size():
		r -= w[i]
		if r <= 0.0:
			return i
	return w.size() - 1


# --- Exp 005 (A): layers ----------------------------------------------------------------

## Where the player is: "outside", "inside", "exposed" (a room open to the
## outside) or "basement" (the mix glides there).
func set_place(where: String) -> void:
	if PLACES.has(where):
		place = where


## The listener's world position (house creaks happen near it).
func set_listener(at: Vector3) -> void:
	_listener = at


## The fireplace: its node (for the position), whether it burns, and whether
## the player is on its storey.
func set_fireplace(node: Node3D, lit: bool, same_storey := true) -> void:
	_fire = node if node != null and is_instance_valid(node) else null
	_fire_lit = lit
	_fire_same = same_storey


## Turns one layer (LAYERS) on or off (developer menu).
func set_layer(id: String, on: bool) -> void:
	if layers.has(id):
		layers[id] = on
		if id == "outdoor":
			AudioMix.mute_outdoor(not on)


## The state of the layers for the developer menu and tests.
func layer_status() -> Dictionary:
	var out := {"place": place, "outdoor_db": _outdoor_db, "cutoff": _cutoff, "layers": layers.duplicate()}
	for id in beds:
		var b: AmbienceBed = beds[id]
		out[id] = {"available": b.available(), "playing": b.playing(), "level": b.level()}
	return out


## Plays one detail now ("owl", "wolf", "creak"); false if it has no recording.
func play_detail(id: String) -> bool:
	var name: String = {"owl": "ambient/owl", "wolf": "ambient/wolf", "creak": "ambient/house_creak"}.get(id, "")
	if name == "" or not Sfx.available(name):
		return false
	var at: Vector3
	if id == "creak":
		var off := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(2.0, 4.0)
		at = Vector3(_listener.x + off.x, _listener.y + CREAK_HEIGHT - 1.0, _listener.z + off.y)
	else:
		at = distant_point(_rng.randf() * TAU)
	Sfx.play(name, at)
	details_played[id] += 1
	return true


func _ready_layers() -> void:
	for spec in [["forest", "ambient/forest", AudioMix.OUTDOOR, false], ["room", "ambient/room_tone", "Ambient", false],
			["basement", "ambient/basement_tone", "Ambient", false], ["fire", "ambient/fireplace", "Ambient", true]]:
		var b := AmbienceBed.new().setup(spec[1], StringName(spec[2]), spec[3])
		add_child(b)
		beds[spec[0]] = b
		AudioInbox.prepare(spec[1])         # analyse the recordings now, not mid-game
	# a recorded forest takes the lead; the generated wind and night sit under it
	if beds["forest"].available() and Sfx.source_of("ambient/wind_day") == "template":
		_trim_db = TEMPLATE_TRIM_DB
	for id in ["owl", "wolf", "creak"]:
		_next_detail[id] = _detail_interval(id)


func _exit_tree() -> void:
	AudioMix.set_outdoor(0.0, AudioMix.OPEN_CUTOFF)    # menus hear the Outdoor bus unfiltered
	AudioMix.mute_outdoor(false)


func _step_layers(delta: float) -> void:
	var k := 1.0 - exp(-delta * 3.0 / FADE_TIME)
	var p: Dictionary = PLACES[place]
	var threat: bool = tension > 0.5 and layers["threat"]
	var want_db: float = p["outdoor_db"] + (THREAT_DIP_DB if threat else 0.0)
	_outdoor_db = lerpf(_outdoor_db, want_db, k)
	var lc := log(_cutoff) / log(2.0)
	_cutoff = pow(2.0, lerpf(lc, log(float(p["cutoff"])) / log(2.0), k))
	if absf(_cutoff - float(p["cutoff"])) < 5.0:
		_cutoff = float(p["cutoff"])
	AudioMix.set_outdoor(_outdoor_db, _cutoff)
	beds["forest"].gain = lerpf(1.0, FOREST_NIGHT, night_amount) if layers["outdoor"] else 0.0
	beds["room"].gain = float(p["room"]) if layers["indoor"] else 0.0
	beds["basement"].gain = float(p["basement"]) if layers["indoor"] else 0.0
	var fire: AmbienceBed = beds["fire"]
	var burning: bool = _fire != null and is_instance_valid(_fire) and _fire_lit and layers["fireplace"]
	fire.gain = (1.0 if _fire_same else FIRE_OTHER_STOREY) if burning else 0.0
	if burning:
		fire.place(_fire.global_position + Vector3(0.0, 0.6, 0.35))


func _step_details(delta: float) -> void:
	if not layers["details"] or tension > 0.2:
		return
	for id in _next_detail:
		_next_detail[id] -= delta
		if _next_detail[id] > 0.0:
			continue
		_next_detail[id] = _detail_interval(id)
		var ok := false
		match id:
			"owl":
				ok = night_amount >= 0.55
			"wolf":
				ok = night_amount >= 0.7
			"creak":
				ok = place != "outside"
		if ok:
			play_detail(id)


func _detail_interval(id: String) -> float:
	var r: Vector2 = {"owl": OWL_EVERY, "wolf": WOLF_EVERY, "creak": CREAK_EVERY}[id]
	return _rng.randf_range(r.x, r.y)
