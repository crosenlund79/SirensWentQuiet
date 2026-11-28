class_name NoiseEvent
extends RefCounted
## Experiment 007 (N): event-based noise (the user's §12 and §22).
##
## Noise is a gameplay event, separate from audio. A loud action calls
##   NoiseEvent.emit(game_or_world, pos, level, source)
## (SPEC §3 calls it `Noise.emit`, but Godot has a native class `Noise`
## (FastNoiseLite's base) that can't be shadowed, so the class is NoiseEvent.
## From game code without the class: game.noise.emit(pos, level, source).)
## where `pos` is a world position, `level` a loudness (about 1 low,
## 2 moderate, 3 high, 4 very high, 5 extreme; see EVENTS) and `source` a
## short name ("gunfire", "hammer_wood", ...). It never plays a sound and never
## needs a sound file; a missing audio file never disables noise. Ordinary
## walking, eating, inventory use and ordinary door use make no noise events.
##
## What happens:
##   1. the place is classified (NoisePlace: outdoors, exterior room, central
##      room, upper interior, basement; open doors, broken windows and
##      breaches raise the exposure);
##   2. the hearing radius is RADIUS(level) x exposure;
##   3. every living, non-retreating enemy within it hears `heard` = level x
##      exposure x (1 - distance / radius); above ground the storeys don't
##      matter (the exposure counts the walls), between a basement and the
##      storey above the radius halves, and two storeys of earth stop it. Calm enemies (AIEnemy.is_calm()) may
##      investigate, check an entrance, wander away or turn hostile
##      (StragglerMind.hear); hostile enemies are already coming.
##      Noise never spawns enemies; scheduled hordes are separate.
##   4. the event is logged (game.noise when the game has the helper, else
##      NoiseEvent.log) and game.noise emits `noise_made(event)`.
##
## `game_or_world` may be the SurvivalGame, a HouseWorld (the home's storeys
## or a POI world), any node inside the game, or null (tests: classified
## and logged, nobody hears it).

const LOW := 1.0
const MODERATE := 2.0
const HIGH := 3.0
const VERY_HIGH := 4.0
const EXTREME := 5.0
const NAMES := ["none", "low", "moderate", "high", "very high", "extreme"]
## Hearing radius in metres outdoors (exposure 1) per whole level; between
## levels it interpolates, above 5 it keeps growing by the last step.
const RADIUS := [0.0, 6.0, 11.0, 17.0, 26.0, 38.0]
## Named events and their levels (callers may pass a number instead).
const EVENTS := {
	"hammer_wood": LOW,          ## wooden walls, barricades, boards, crates, repairs
	"dig": LOW,                  ## a shovel in earth
	"search": LOW,               ## rummaging through a container (agent P)
	"masonry": MODERATE,         ## stone walls and foundations
	"drill": MODERATE,           ## agent O's drill
	"force": MODERATE,           ## forcing a lock or a jammed door (agent P)
	"demolish": MODERATE,        ## taking down wood or stone
	"hammer_metal": HIGH,        ## iron plating, metal doors and barricades
	"smash_furniture": HIGH,     ## smashing or demolishing furniture
	"demolish_metal": HIGH,
	"alarm": HIGH,               ## a security alarm (agent S passes its own level)
	"gunfire": VERY_HIGH,        ## handgun, shotgun; turret fire by its weapon
	"explosion": EXTREME,
}
## Gunfire by weapon (handheld and agent S's turrets): weapon_level(id).
const WEAPON_LEVELS := {"handgun": 4.0, "shotgun": 4.4, "rifle": 4.6}
const STOREY_DAMP := 0.5          ## radius factor between a basement and the storey above
const LOG_MAX := 12

## Events when there is no game helper (tests, tools); newest last.
static var log: Array = []
## False switches noise off entirely (tests).
static var enabled := true


## Makes a noise. Returns the event: {"pos": Vector3, "level", "source",
## "place", "exposure", "radius", "storey", "room", "heard": n enemies,
## "provoked": n, "minute"} ({} if nothing was emitted).
static func emit(ctx: Variant, pos: Vector3, level: float, source := "noise") -> Dictionary:
	if not enabled or not pos.is_finite():
		return {}
	var lv := clampf(level, 0.0, 8.0)
	if lv <= 0.0:
		return {}
	var game := game_of(ctx)
	var world: HouseWorld = ctx if ctx is HouseWorld and is_instance_valid(ctx) else null
	var storey := storey_of(world, game, pos)
	if world == null or (world is LevelWorld) != (storey != 0):
		var w2 := world_of(game, storey)
		if w2 != null:
			world = w2
	var place := NoisePlace.classify(world, storey, Vector2(pos.x, pos.z), cache_of(game))
	var ev := {"pos": pos, "level": lv, "source": source, "place": place["place"], "exposure": place["exposure"],
		"radius": radius_for(lv) * float(place["exposure"]), "storey": storey, "room": place.get("label", ""),
		"notes": place.get("notes", []), "heard": 0, "provoked": 0,
		"minute": float(game.state.total_minutes) if game != null and game.get("state") != null else 0.0}
	_dispatch(game, ev)
	var helper = game.get("noise") if game != null else null
	if helper is Object and is_instance_valid(helper) and helper.has_method("record"):
		helper.call("record", ev)
	else:
		log.append(ev)
		while log.size() > LOG_MAX:
			log.pop_front()
	return ev


## A named event (EVENTS) at `pos`; unknown names are LOW.
static func emit_event(ctx: Variant, pos: Vector3, event: String) -> Dictionary:
	return emit(ctx, pos, level_of(event), event)


static func level_of(event: String) -> float:
	return float(EVENTS.get(event, LOW))


## The noise level of a shot from weapon `id` (VERY_HIGH for unknown ones).
static func weapon_level(id: String) -> float:
	return float(WEAPON_LEVELS.get(id, VERY_HIGH))


static func level_name(level: float) -> String:
	return NAMES[clampi(roundi(level), 0, NAMES.size() - 1)]


## Outdoor hearing radius of a level (m).
static func radius_for(level: float) -> float:
	if level <= 0.0:
		return 0.0
	var top := RADIUS.size() - 1
	if level >= float(top):
		return RADIUS[top] + (level - float(top)) * (RADIUS[top] - RADIUS[top - 1])
	var i := int(floor(level))
	return lerpf(RADIUS[i], RADIUS[i + 1], level - float(i))


## How much of the event an enemy at distance d (same storey) hears: 0 outside the radius.
static func heard_at(level: float, exposure: float, d: float, radius: float) -> float:
	if radius <= 0.0 or d > radius:
		return 0.0
	return level * exposure * (1.0 - d / radius)


# --- context -----------------------------------------------------------------------------

## The SurvivalGame that owns `ctx` (the game itself, or any node inside it), or null.
static func game_of(ctx: Variant) -> Node:
	if not (ctx is Node) or not is_instance_valid(ctx):
		return null
	var n: Node = ctx
	while n != null:
		if "roster" in n and "state" in n and "world" in n:
			return n
		n = n.get_parent()
	return null


## The storey of the event: a LevelWorld's own, else the height (with storeys), else 0.
static func storey_of(world: HouseWorld, game: Node, pos: Vector3) -> int:
	if world is LevelWorld:
		return (world as LevelWorld).storey
	if world != null and game == null:
		return 0
	if game != null and game.get("levels") != null:
		return Levels.storey_at(pos.y)
	return 0


static func world_of(game: Node, storey: int) -> HouseWorld:
	if game == null:
		return null
	var lv = game.get("levels")
	if lv is Object and is_instance_valid(lv) and lv.has_method("world_of"):
		var w = lv.call("world_of", storey)
		if w is HouseWorld:
			return w
	return game.get("world") if storey == 0 else null


## The game's shared RoomCache (the visibility helper's), or null (rooms are found once).
static func cache_of(game: Node) -> RoomCache:
	if game == null:
		return null
	var v = game.get("visibility")
	if v is Object and is_instance_valid(v) and v.get("cache") is RoomCache:
		return v.get("cache")
	var n = game.get("noise")
	if n is Object and is_instance_valid(n) and n.get("cache") is RoomCache:
		return n.get("cache")
	return null


# --- listeners ---------------------------------------------------------------------------

static func _dispatch(game: Node, ev: Dictionary) -> void:
	if game == null:
		return
	var roster = game.get("roster")
	if not (roster is Object) or not is_instance_valid(roster) or roster.get("enemies") == null:
		return
	var p: Vector3 = ev["pos"]
	var at := Vector2(p.x, p.z)
	var storey: int = ev["storey"]
	for e in roster.enemies:
		if not is_instance_valid(e) or not (e is AIEnemy):
			continue
		var a := e as AIEnemy
		if not a.alive or a.retreating or a.has_meta("retreat"):
			continue
		var gap := absi(a.storey - storey)
		var buried := mini(a.storey, storey) < 0      # through earth and a floor
		if buried and gap > 1:
			continue
		var r: float = ev["radius"] * (STOREY_DAMP if buried and gap > 0 else 1.0)
		var h := heard_at(ev["level"], ev["exposure"], a.plan_pos().distance_to(at), r)
		if h <= 0.0:
			continue
		ev["heard"] += 1
		if a.is_calm():
			a.hear(at, h, str(ev["source"]))
			if not a.is_calm():
				ev["provoked"] += 1
