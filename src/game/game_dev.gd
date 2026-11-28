extends Node
## Experiment 003 developer tools for the F10 menu, all through the real
## systems (no parallel logic): spawning each enemy type (roster.spawn_type),
## an invasion with a chosen composition (the director's begin_wave), an
## instant mission (ExpeditionRun.simulate, then the game's own expedition
## apply path), revealing the map (RegionState.discover_all), the difficulty
## (GameState.set_difficulty) and filling the magazines. The dev menu finds
## these through the game's `dev` property; the Experiment 002 dev API stays on
## the game root. Docs: docs/experiment-003/game.md.

const Director := preload("res://src/game/invasion_director.gd")

var game: Node                         ## SurvivalGame
var last_mission := {}                 ## the last instant mission's result (tests)
var _spawn_i := 0


func setup(g: Node) -> void:
	game = g


## One enemy of `kind` at the next fog point at least 6 m from the player,
## scaled for the run's difficulty and invasion index. Not a wave member.
func dev_spawn_type(kind: String) -> Node:
	if not EnemyDefs.has(kind):
		game.toast("Unknown enemy type '%s'." % kind, "warn")
		return null
	var pts := Director.nearest_fog_points(game.player.plan_pos(), 6.0)
	var p: Vector2 = pts[_spawn_i % mini(pts.size(), 3)]
	_spawn_i += 1
	var s: GameState = game.state
	var e: Node = game.roster.spawn_type(kind, p, {"level": s.difficulty, "invasion": s.invasion_index()})
	game.toast("Dev: a %s in the fog." % EnemyDefs.get_def(kind)["name"].to_lower(), "info")
	return e


## Starts the night's invasion now with exactly `kinds` (e.g. ["bomber",
## "brute"]); an empty list composes the wave from the threat budget.
func dev_wave(kinds: Array) -> bool:
	if game.director.active:
		game.toast("An invasion is already under way.", "warn")
		return false
	game.state.force_invasion_now()
	game.start_invasion(kinds)
	return true


## An instant expedition to `id` with `approach`: the real resolver with the
## default gear, then exactly what the expedition screen's `finished` does.
func dev_instant_mission(id: String, approach := "general", target := "") -> Dictionary:
	var s: GameState = game.state
	if not ExpeditionData.has_destination(id):
		game.toast("Unknown place '%s'." % id, "warn")
		return {}
	var r := ExpeditionRun.simulate(s, id, ExpeditionData.default_gear(s, id), [], approach, target, true)
	if r.is_empty():
		game.toast("That mission can't run now.", "warn")
		return {}
	last_mission = r
	game.apply_expedition_result(r)
	return r


func dev_reveal_map() -> int:
	var s: GameState = game.state
	var before := s.region.discovered.size()
	s.region.discover_all()
	s.changed.emit()
	game.toast("Every place is on the map now.", "info")
	return s.region.discovered.size() - before


func dev_set_difficulty(level: String) -> void:
	game.state.set_difficulty(level)
	game.sync_roster()
	game.toast("Difficulty: %s." % Difficulty.name_of(level), "info")


## Fills the magazine of every owned weapon (nothing taken from the reserve).
func dev_fill_magazines() -> int:
	var s: GameState = game.state
	var n := 0
	for id in WeaponDefs.ids():
		if s.inventory.count(id) > 0:
			n += WeaponDefs.capacity(id) - s.magazine(id)
			s.set_magazine(id, WeaponDefs.capacity(id))
	return n


## Exp 013: gives weapon `id` with a full magazine and some rounds, puts it on
## the quick bar and takes it in hand. Returns a line for F10.
func dev_give_weapon(id: String) -> String:
	var s: GameState = game.state
	if not WeaponDefs.has(id):
		return "No such weapon."
	if s.inventory.count(id) <= 0:
		s.inventory.add(id, 1)
	s.inventory.add(WeaponDefs.ammo_of(id), 20)
	s.set_magazine(id, WeaponDefs.capacity(id))
	s.changed.emit()
	var hb: Variant = game.get("bar")
	if hb is Object and is_instance_valid(hb):
		Hotbar.fill(hb.bar(), s)
		var i := Hotbar.slot_of(hb.bar(), id)
		if i >= 0:
			hb.select(i)
	return "%s in hand, %d %s" % [WeaponDefs.name_of(id), s.inventory.count(WeaponDefs.ammo_of(id)), Items.name_of(WeaponDefs.ammo_of(id)).to_lower()]


## Exp 013: tops every owned gun's magazine and its reserve up to 30 rounds.
func dev_refill_ammo() -> String:
	var s: GameState = game.state
	for id in WeaponDefs.ids():
		if s.inventory.count(id) > 0:
			s.set_magazine(id, WeaponDefs.capacity(id))
			var ammo := WeaponDefs.ammo_of(id)
			if s.inventory.count(ammo) < 30:
				s.inventory.add(ammo, 30 - s.inventory.count(ammo))
	s.changed.emit()
	return "Magazines full, 30 spare rounds of each"


func dev_kill_all() -> int:
	return game.roster.kill_all()


## A line for the dev menu's inspect panel.
func info() -> String:
	var r: Node = game.roster
	var d = game.director
	var kinds: Dictionary = r.living_by_kind()
	var wave := ", ".join(d.wave) if d.active else "none"
	return "Enemies by type %s · wave [%s] budget %.1f · difficulty %s · map %d/%d known · plan %s" % [
		kinds if not kinds.is_empty() else "{}", wave, d.budget, game.state.difficulty,
		game.state.region.discovered.size(), RegionLocations.ids().size(),
		game.state.region.planned if game.state.region.planned != "" else "none"]
