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

var _players := {}
var _gain := {"wind": 0.0, "night": 0.0, "tension": 0.0}
var _next_distant := 0.0
var _last_distant := -1
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	for id in ["wind", "night", "tension"]:
		var p := AudioStreamPlayer.new()
		p.name = id.capitalize()
		p.bus = &"Ambient" if AudioServer.get_bus_index("Ambient") >= 0 else &"Master"
		p.process_mode = Node.PROCESS_MODE_ALWAYS  # the wind doesn't stop for the pause menu
		var logical: String = {"wind": "ambient/wind_day", "night": "ambient/night", "tension": "ambient/tension"}[id]
		p.stream = AssetResolver.get_audio(logical)
		add_child(p)
		_players[id] = p
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
	if distant_enabled:
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
		"tension": tension,
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
		p.volume_db = BASE_DB[id] + linear_to_db(maxf(g, 0.0001))
		if id == "tension":
			if g > 0.001 and not p.playing and p.stream != null and p.is_inside_tree():
				p.play()
			elif g <= 0.001 and p.playing and targets[id] <= 0.0:
				p.stop()


func _start_loops() -> void:
	for id in ["wind", "night"]:
		var p: AudioStreamPlayer = _players[id]
		if p.stream != null and p.is_inside_tree() and not p.playing:
			p.volume_db = BASE_DB[id] + linear_to_db(maxf(_gain[id], 0.0001))
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
