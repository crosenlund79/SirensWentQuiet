class_name PoiDefs
extends RefCounted
## Experiment 007 (P): what each playable destination is. Pure data and pure
## helpers, no nodes.
##
## Every map location (RegionLocations, with gameplay data in ExpeditionData)
## is a POI. Six have hand-made layouts (PoiLayouts): Pine Woods ("forest"),
## the Corner Store ("convenience"), the Public Library ("library") and, since
## Experiment 008, the Hardware Store ("hardware"), Pike's Guns ("gun_shop")
## and the Medical Clinic ("clinic"). Every
## other location uses the reusable placeholder template: a generic small
## building whose containers and labels follow the location's category, filled
## from that location's own loot profile, with enemies by its danger. It says
## "Placeholder layout" on arrival.
##
## get_def(id) merges the location (name, category), its expedition data
## (danger, loot and locked tables, depletion and regen) and the layout:
##   id, name, desc, category, template, placeholder, variant, danger,
##   loot, locked, locked_name, regen, deplete, floor, dark (a flashlight is
##   needed to search: ExpeditionData "requires"; the placeholder uses it, a
##   hand-made layout marks its own dark rooms), layout (PoiLayouts dict).
## Danger for a visit at run time: ExpeditionData.trip_danger(state, id) (the
## place x lasting flags x difficulty), see danger_of.
##
## How to add a hand-made POI: write a layout function in PoiLayouts (copy
## one), add the id -> template pair to HAND_MADE and the template to
## PoiLayouts.build. Nothing else changes: containers, loot, encounters,
## exits and persistence all come from the layout dictionary.
##
## Experiment 009 (G): every other site is GENERATED (src/poigen/): its
## archetype comes from PoiArchetypes.for_site, its layout from
## PoiGenerator.generate(setup). get_def(id, state):
##   - the setup: the seed (and size, surroundings) recorded in the site's
##     PoiState record at its first visit ("gen": {seed, v, size,
##     surroundings}), so a revisit rebuilds the same building whatever the
##     daily setup says now; else DailySites.setup(state, id) when that class
##     exists; else PoiArchetypes.default_setup(id, run seed);
##   - cached by (id, seed, size, surroundings, PoiGenerator.VERSION);
##   - without a state: the setup last resolved for that id (the game always
##     resolves with its state first: PoiSite.build_world, PoiState), else the
##     default setup of run seed 0.
## Test sites gen:<archetype>:<seed> (F10) are generated from
## PoiArchetypes.test_setup with the loot tables of the archetype's
## loot_site. The placeholder template is only the last fallback (a site with
## no archetype).
## Generated defs add: generated true, archetype, setup, gen_key, seed.

const HAND_MADE := {"forest": "pine_woods", "convenience": "corner_store", "library": "library",
	"hardware": "hardware_store", "gun_shop": "gun_shop", "clinic": "clinic"}      # Exp 008 (H): + three places
## Placeholder variant by location category (PoiLayouts.placeholder).
const VARIANTS := {"residential": "house", "food": "shop", "medical": "clinic", "construction": "depot",
	"weapons": "armoury", "knowledge": "office"}
## Arrival lines (placeholder POIs say "Placeholder layout" instead).
const ARRIVAL := {
	"forest": "Pine Woods. Snow, deadfall and silence. Mostly silence.",
	"convenience": "The Corner Store. The windows are dark.",
	"library": "The Public Library. Quiet. Too quiet between the stacks.",
	"hardware": "The Hardware Store. Half the racks are bare, and the yard gate hangs open.",
	"gun_shop": "Pike's Guns. Empty racks, and a steel door nobody got through.",
	"clinic": "The Medical Clinic. Daylight in the waiting room; down the corridor, nothing.",
}

static var _cache := {}
static var _current := {}         ## Exp 009 (G): id -> the cache key last resolved


static func has(id: String) -> bool:
	if PoiArchetypes.is_test_id(id):
		return true
	return RegionLocations.has(id) and ExpeditionData.has_destination(id)


## Exp 009 (G): true if the site's building is generated (not hand-made, not the placeholder).
static func is_generated(id: String) -> bool:
	if HAND_MADE.has(id):
		return false
	return PoiArchetypes.has(PoiArchetypes.for_site(id))


static func ids() -> Array:
	return ExpeditionData.ORDER.filter(func(i): return has(i))


static func template_of(id: String) -> String:
	if is_generated(id):
		return "generated"
	return str(HAND_MADE.get(id, "placeholder"))


static func is_placeholder(id: String) -> bool:
	return not HAND_MADE.has(id) and not is_generated(id)


static func variant_of(id: String) -> String:
	return str(VARIANTS.get(str(RegionLocations.get_def(id).get("category", "")), "house"))


## The merged definition (cached; the layout is shared, never modify it). {} for unknown ids.
## Exp 009 (G): `state` picks a generated site's setup (see the header).
static func get_def(id: String, state: GameState = null) -> Dictionary:
	if _cache.has(id):
		return _cache[id]                  # hand-made, the placeholder, or a definition a test put in its place
	if is_generated(id):
		return _generated_def(id, state)
	if not has(id):
		return {}
	var dest := ExpeditionData.destination(id)
	var d := {
		"id": id, "name": str(dest["name"]), "desc": str(dest["desc"]), "category": str(dest["category"]),
		"template": template_of(id), "placeholder": is_placeholder(id), "variant": variant_of(id),
		"danger": float(dest.get("danger", 1.0)), "loot": dest.get("loot", []), "locked": dest.get("locked", []),
		"locked_name": str(dest.get("locked_name", "locked doors")),
		"regen": float(dest.get("regen", 0.02)), "deplete": float(dest.get("deplete", 0.2)), "floor": float(dest.get("floor", 0.1)),
		"dark": "flashlight" in dest.get("requires", []),
	}
	d["layout"] = PoiLayouts.build(d)
	_cache[id] = d
	return d


## Exp 009 (G): the setup a generated site is built from (see the header).
static func setup_for(id: String, state: GameState = null) -> Dictionary:
	var arch := PoiArchetypes.for_site(id)
	var s := {}
	if PoiArchetypes.is_test_id(id):
		s = PoiArchetypes.default_setup(id, 0)
	elif state != null:
		var ds := PoiGenerator.script_class("DailySites")
		if ds != null:
			var v: Variant = ds.call("setup", state, id)
			if typeof(v) == TYPE_DICTIONARY:
				s = (v as Dictionary).duplicate()
		if s.is_empty() or typeof(s.get("seed")) not in [TYPE_INT, TYPE_FLOAT]:
			s = PoiArchetypes.default_setup(id, int(state.run.get("seed", 0)))
		var rec: Variant = state.region.get("poi").get(id) if state.region != null and typeof(state.region.get("poi")) == TYPE_DICTIONARY else null
		if typeof(rec) == TYPE_DICTIONARY and typeof(rec.get("gen")) == TYPE_DICTIONARY:
			var g: Dictionary = rec["gen"]
			if typeof(g.get("seed")) in [TYPE_INT, TYPE_FLOAT]:
				s["seed"] = int(g["seed"])
				s["size"] = str(g.get("size", s.get("size", "m")))
				s["surroundings"] = str(g.get("surroundings", s.get("surroundings", "")))
				# Exp 012 (L, §22): a site first built before secured rooms keeps its building
				if not g.has("sec") and PoiState.generated(rec):
					s["secure"] = false
	else:
		s = PoiArchetypes.default_setup(id, 0)
	if not s.has("secure"):
		s["secure"] = true          # Exp 012 (L, §22): secured rooms behind crowbar doors
	s["id"] = id
	s["archetype"] = arch
	s["family"] = PoiArchetypes.family_of(arch)
	s["hand_made"] = false
	if not s.has("variant"):
		s["variant"] = PoiArchetypes.variant_for_site(id)
	return s


static func _gen_key(id: String, s: Dictionary) -> String:
	return "%s|%d|%s|%s|%d%s" % [id, int(s.get("seed", 0)), str(s.get("size", "m")), str(s.get("surroundings", "")), PoiGenerator.VERSION,
		"" if bool(s.get("secure", true)) else "|old"]


## Exp 009 (G): the cache key of the layout `id` stands for now (PoiWorld
## keys its built voxel grid and ground by it).
static func layout_key(id: String) -> String:
	if _cache.has(id):
		return id
	return str(_current.get(id, id))


static func _generated_def(id: String, state: GameState) -> Dictionary:
	if state == null and _current.has(id) and _cache.has(_current[id]):
		return _cache[_current[id]]
	var d := _gen_prepare(id, state)
	if d.is_empty() or d.has("layout"):
		return d
	return _gen_finish(d, PoiGenerator.generate(d["setup"]))


## Exp 009 (G): the definition of a generated site without its layout yet
## (or the cached one, with it). {} when the site has no loot profile.
static func _gen_prepare(id: String, state: GameState) -> Dictionary:
	var s := setup_for(id, state)
	var key := _gen_key(id, s)
	_current[id] = key
	if _cache.has(key):
		return _cache[key]
	var arch := str(s["archetype"])
	var a := PoiArchetypes.get_arch(arch, str(s.get("variant", "")))
	var src := id if ExpeditionData.has_destination(id) else str(a.get("loot_site", "homes"))
	var dest := ExpeditionData.destination(src)
	if dest.is_empty():
		return {}
	s["dark_hint"] = "flashlight" in dest.get("requires", [])
	var name := str(a.get("name", arch)) if PoiArchetypes.is_test_id(id) else str(dest["name"])
	var lines: Array = a.get("arrival", [])
	return {
		"id": id, "name": name, "desc": str(dest["desc"]), "category": str(dest["category"]),
		"template": "generated", "placeholder": false, "generated": true, "variant": variant_of(src),
		"danger": float(dest.get("danger", 1.0)), "loot": dest.get("loot", []), "locked": dest.get("locked", []),
		"locked_name": str(dest.get("locked_name", "locked doors")),
		"regen": float(dest.get("regen", 0.02)), "deplete": float(dest.get("deplete", 0.2)), "floor": float(dest.get("floor", 0.1)),
		"dark": false, "archetype": arch, "setup": s, "seed": int(s["seed"]), "gen_key": key, "loot_site": src,
		"arrival": str(lines[posmod(int(s["seed"]), lines.size())]) if not lines.is_empty() else name,
	}


static func _gen_finish(d: Dictionary, layout: Dictionary) -> Dictionary:
	d["layout"] = layout
	_cache[d["gen_key"]] = d
	_current[d["id"]] = d["gen_key"]
	return d


## Exp 009 (G): generation in steps for the loading screen (R). A generated
## site gives a context with step() -> bool (true = done), stage, progress
## 0..1, layout and def; once done, its definition is in the cache, so the
## get_def calls that follow (PoiWorld.configure, PoiState) don't generate
## again. An already cached site gives a context that is done at once. null
## for hand-made places, the placeholder and unknown ids (one get_def call).
static func begin_def(id: String, state: GameState = null) -> Object:
	if _cache.has(id) or not is_generated(id):
		return null
	var d := _gen_prepare(id, state)
	if d.is_empty():
		return null
	return DefCtx.new(d, null if d.has("layout") else PoiGenerator.begin(d["setup"]))


class DefCtx:
	extends RefCounted
	var def := {}
	var stage := "done"
	var progress := 1.0
	var layout := {}
	var done := true
	var _gen: Object = null

	func _init(d: Dictionary, gen: Object) -> void:
		def = d
		_gen = gen
		if gen == null:
			layout = d.get("layout", {})
		else:
			done = false
			stage = str(gen.get("stage"))
			progress = 0.0

	func step() -> bool:
		if done:
			return true
		var fin: bool = _gen.call("step")
		stage = str(_gen.get("stage"))
		progress = float(_gen.get("progress"))
		if fin:
			layout = _gen.get("layout")
			def = PoiDefs._gen_finish(def, layout)
			done = true
			progress = 1.0
		return fin


## The visit's danger: the place x its lasting flags x difficulty (as the
## simulated expeditions; no gear or approach effects).
static func danger_of(state: GameState, id: String) -> float:
	if state == null or not ExpeditionData.has_destination(id):
		return float(get_def(id, state).get("danger", 1.0))
	return ExpeditionData.trip_danger(state, id)


static func arrival_text(id: String) -> String:
	var d := get_def(id)
	if d.is_empty():
		return ""
	if d.get("generated", false):
		return str(d.get("arrival", d["name"]))
	if d["placeholder"]:
		return "Placeholder layout: %s (a generic %s for now)." % [d["name"], PoiLayouts.VARIANT_NAMES.get(d["variant"], "building")]
	return str(ARRIVAL.get(id, d["name"]))
