extends Node
## Experiment 007 (N): noise in the running game, `game.noise` (the
## game_*.gd helper pattern). NoiseEvent.emit does the work (src/noise/noise.gd);
## this node:
##   - wires the emitters N owns that live in the game: gunfire
##     (WeaponHandler.fired, at Eli's position, NoiseEvent.weapon_level). The
##     others call NoiseEvent directly: explosions (HouseWorld.explode), building,
##     repairing, upgrading and demolishing (BuildNoise from BuildMode.apply),
##     and agents O, P and S (drilling, searching, alarms, turrets);
##   - keeps the recent events (`events`, F10) and emits noise_made(event)
##     for anyone who wants to react (alarms, holes, the HUD);
##   - says so when a calm enemy turns hostile ("Something noticed you.");
##   - the F10 "Noise & visibility" tools (dev_*), with the visibility helper.
## No sound is played here: audio and noise are separate (§22).

signal noise_made(event: Dictionary)

const Director := preload("res://src/game/invasion_director.gd")

const LOG_MAX := 12
const PROVOKED_TOAST_GAP := 10.0       ## real seconds between "noticed" toasts

var game: Node
var events: Array = []                 ## newest last
var total := 0
var provoked := 0                      ## calm enemies that turned hostile (tests, F10)
var cache: RoomCache                   ## used when the game has no visibility helper
var _toast_t := 999.0


func setup(g: Node) -> void:
	game = g
	cache = RoomCache.new()
	var c = g.get("combat")
	if c != null and c.get("weapons") != null and c.weapons.has_signal("fired"):
		c.weapons.fired.connect(_on_fired)
	var r = g.get("roster")
	if r != null and r.has_signal("enemy_provoked"):
		r.connect("enemy_provoked", _on_provoked)


func _process(delta: float) -> void:
	_toast_t += delta


## Makes a noise at world position `pos` (NoiseEvent.emit for this game): the
## entry point for other helpers (drilling, searching, alarms, turrets).
func emit(pos: Vector3, level: float, source := "noise") -> Dictionary:
	return NoiseEvent.emit(game, pos, level, source)


## A named event (NoiseEvent.EVENTS: "drill", "search", "force", "alarm", ...).
func emit_event(pos: Vector3, event: String) -> Dictionary:
	return NoiseEvent.emit_event(game, pos, event)


## NoiseEvent.emit hands every event here.
func record(ev: Dictionary) -> void:
	events.append(ev)
	while events.size() > LOG_MAX:
		events.pop_front()
	total += 1
	noise_made.emit(ev)


func last() -> Dictionary:
	return events[events.size() - 1] if not events.is_empty() else {}


func _on_fired(id: String, _hits: Array) -> void:
	var pl = game.get("player")
	if pl is Node3D:
		NoiseEvent.emit(game, (pl as Node3D).global_position, NoiseEvent.weapon_level(id), "gunfire")


func _on_provoked(_e, _why: String) -> void:
	provoked += 1
	if _toast_t >= PROVOKED_TOAST_GAP and game.has_method("toast"):
		_toast_t = 0.0
		game.toast("Something noticed you.", "warn")


# --- F10: Noise & visibility --------------------------------------------------------------

## A sample noise at Eli's position: "low", "moderate", "high", "very high", "extreme".
func dev_sample(which: String) -> String:
	var lv := float(maxi(NoiseEvent.NAMES.find(which), 1))
	var pl = game.get("player")
	if not (pl is Node3D):
		return "No player."
	var ev := NoiseEvent.emit(game, (pl as Node3D).global_position, lv, "dev " + which)
	return describe(ev) if not ev.is_empty() else "Noise is switched off."


static func describe(ev: Dictionary) -> String:
	var notes: Array = ev.get("notes", [])
	return "%s noise (%s, %.1f): %s x%.2f%s, heard within %.1f m by %d enem%s%s." % [str(ev["source"]).capitalize(),
		NoiseEvent.level_name(ev["level"]), float(ev["level"]), ev["place"], float(ev["exposure"]),
		(" (" + ", ".join(notes) + ")") if not notes.is_empty() else "", float(ev["radius"]), int(ev["heard"]),
		"y" if int(ev["heard"]) == 1 else "ies", (", %d turned hostile" % int(ev["provoked"])) if int(ev["provoked"]) > 0 else ""]


## The recent noise events, newest first, and the calm enemies.
func dev_log_text() -> String:
	var lines := []
	for i in range(events.size() - 1, maxi(events.size() - 7, -1), -1):
		var ev: Dictionary = events[i]
		var m := int(ev.get("minute", 0.0))
		lines.append("%02d:%02d %s" % [(m / 60) % 24, m % 60, describe(ev)])
	if lines.is_empty():
		lines.append("No noise yet.")
	var calm := []
	var r = game.get("roster")
	if r != null:
		for e in r.enemies:
			if is_instance_valid(e) and e is AIEnemy and (e as AIEnemy).is_calm():
				var a := e as AIEnemy
				calm.append("%s %s (alert %.1f)" % [a.kind, a.state_name(), a.mind.alert])
	lines.append("Calm: " + (", ".join(calm) if not calm.is_empty() else "none") + " · %d provoked so far" % provoked)
	return "\n".join(lines)


## A calm straggler (home: from the nearest fog point; elsewhere: 8 m away).
func dev_spawn_calm(kind := "psycho") -> String:
	var r = game.get("roster")
	var pl = game.get("player")
	if r == null or not (pl is Node3D):
		return "No roster."
	var me := Vector2((pl as Node3D).global_position.x, (pl as Node3D).global_position.z)
	var home: bool = not game.has_method("is_home") or bool(game.call("is_home"))
	var at := Vector2.INF
	if home:
		var pts: Array = Director.nearest_fog_points(me, 6.0)
		if not pts.is_empty():
			at = pts[0]
	if at == Vector2.INF:
		var nav: GridNav = game.world.nav if game.get("world") != null else null
		for i in 16:
			var q := me + Vector2.from_angle(TAU * float(i) / 16.0) * 8.0
			if nav != null and nav.is_walkable(nav.cell_of(q)):
				at = q
				break
	if at == Vector2.INF:
		return "No room for a straggler here."
	var opts := {"mode": "straggler" if home else "wander"}
	if game.get("state") != null:
		opts["level"] = game.state.difficulty
	var e = r.spawn_type(kind, at, opts)
	return "A calm %s (%s) at (%.1f, %.1f): %s." % [kind, opts["mode"], at.x, at.y, (e as AIEnemy).state_name() if e is AIEnemy else "?"]
