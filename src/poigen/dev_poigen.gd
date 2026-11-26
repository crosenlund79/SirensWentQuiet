class_name DevPoigen
extends RefCounted
## Experiment 009 (D): the actions of F10 "POI generator" (DevMenu's section
## calls these; each returns a status line). Duck-typed on the game:
## `state`, `travel` (TravelFlow: dev_travel_to, dev_return_home), `poi`
## (the POI helper: P's dev_spawn_dormant(behaviour), dev_force_behaviour(
## behaviour), dev_reveal_stash() when they exist), `world` (PoiWorld:
## `layout`, G's `diag`) and dev_skip_to(hour).
##
## Test sites: "gen:<archetype>:<seed>" with a new seed each time, reached by
## instant travel. They need G's generator (a PoiGenerator class and
## PoiDefs routing test ids); without them the tool says so.

const BEHAVIOURS := ["bang", "circle", "sway", "stare", "tap"]


## Today's places: open (with streaks) and overrun (with their archetype).
static func today_text(game: Node) -> String:
	var s: GameState = game.get("state") if game != null else null
	if s == null:
		return "No game state."
	var d := DailySites.today(s)
	var av := []
	for id in d.get("available", []):
		var left := DailySites.days_left(s, id)
		av.append("%s%s" % [RegionLocations.name_of(id), " (%dd)" % left if left > 0 else ""])
	var ov := []
	for id in d.get("overrun", []):
		ov.append("%s [%s]" % [RegionLocations.name_of(id), DailySites.archetype_of(id)])
	return "Day %d · open %d: %s · overrun %d: %s" % [int(d.get("day", s.day())), av.size(), ", ".join(av), ov.size(),
		", ".join(ov) if not ov.is_empty() else "none"]


## Skips the clock to the next 00:00 (the game's day hook makes the new
## selection) and shows it.
static func next_day(game: Node) -> String:
	if game == null or not game.has_method("dev_skip_to"):
		return "The game has no dev_skip_to()."
	game.dev_skip_to(0.0)
	return today_text(game)


## A site's setup as one line of text.
static func inspect(game: Node, id: String) -> String:
	var s: GameState = game.get("state") if game != null else null
	var st := DailySites.setup(s, id)
	if st.is_empty():
		return "Unknown site %s." % id
	var keys := st.keys()
	keys.sort()
	var parts := []
	for k in keys:
		parts.append("%s=%s" % [k, st[k]])
	return "%s: %s" % [RegionLocations.name_of(id), ", ".join(parts)]


## "" when test sites can be generated here, else why not.
static func generator_reason() -> String:
	if DailySites.global_script("PoiGenerator") == null:
		return "Not available: this build has no POI generator (PoiGenerator)."
	if not PoiDefs.has(DailySites.test_id("house_small", 1)):
		return "Not available: PoiDefs doesn't route test sites yet."
	return ""


## A new test site of `archetype` with a new seed, and instant travel there.
static func generate(game: Node, archetype: String) -> String:
	var why := generator_reason()
	if why != "":
		return why
	var t: Variant = game.get("travel") if game != null else null
	if not (t is Object and is_instance_valid(t) and t.has_method("dev_travel_to")):
		return "The game has no travel.dev_travel_to()."
	var id := DailySites.test_id(archetype, int(Time.get_ticks_usec()) ^ randi())
	t.dev_travel_to(id)
	return "Generating %s (%s)" % [RegionLocations.name_of(id), id]


static func spawn_dormant(game: Node, behaviour: String) -> String:
	return _poi_call(game, "dev_spawn_dormant", [behaviour], "No dormant psychos here (not at a POI, or not in this build).")


static func force_behaviour(game: Node, behaviour: String) -> String:
	return _poi_call(game, "dev_force_behaviour", [behaviour], "Forcing a behaviour is not available here.")


static func reveal_stash(game: Node) -> String:
	return _poi_call(game, "dev_reveal_stash", [], "Revealing the stash is not available here.")


## The layout's diagnostics (G's `diag`) and the site's setup.
static func diagnostics(game: Node) -> String:
	if game == null or not game.has_method("is_home") or game.is_home():
		return "Not at a POI."
	var id := str(game.site_id())
	var L: Variant = null
	var w: Variant = game.get("world")
	if w is Object and is_instance_valid(w):
		L = w.get("layout")
	var diag: Variant = (L as Dictionary).get("diag", null) if typeof(L) == TYPE_DICTIONARY else null
	var t := "%s · seed %d · archetype %s" % [RegionLocations.name_of(id), int(DailySites.setup(game.get("state"), id).get("seed", 0)),
		DailySites.archetype_of(id) if not DailySites.is_test_id(id) else str(DailySites.parse_test_id(id).get("archetype", "?"))]
	if typeof(diag) != TYPE_DICTIONARY:
		return t + " · no generator diagnostics (a hand-made or placeholder layout)."
	var parts := []
	for k in (diag as Dictionary):
		parts.append("%s=%s" % [k, diag[k]])
	return t + " · " + ", ".join(parts)


static func return_home(game: Node) -> String:
	var t: Variant = game.get("travel") if game != null else null
	if not (t is Object and is_instance_valid(t) and t.has_method("dev_return_home")):
		return "The game has no travel.dev_return_home()."
	if game.is_home():
		return "Already home."
	t.dev_return_home()
	return "Going home"


static func _poi_call(game: Node, method: String, args: Array, missing: String) -> String:
	var p: Variant = game.get("poi") if game != null else null
	if not (p is Object and is_instance_valid(p) and p.has_method(method)):
		return missing
	return str(p.callv(method, args))
