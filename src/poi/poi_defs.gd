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


static func has(id: String) -> bool:
	return RegionLocations.has(id) and ExpeditionData.has_destination(id)


static func ids() -> Array:
	return ExpeditionData.ORDER.filter(func(i): return has(i))


static func template_of(id: String) -> String:
	return str(HAND_MADE.get(id, "placeholder"))


static func is_placeholder(id: String) -> bool:
	return not HAND_MADE.has(id)


static func variant_of(id: String) -> String:
	return str(VARIANTS.get(str(RegionLocations.get_def(id).get("category", "")), "house"))


## The merged definition (cached; the layout is shared, never modify it). {} for unknown ids.
static func get_def(id: String) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
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


## The visit's danger: the place x its lasting flags x difficulty (as the
## simulated expeditions; no gear or approach effects).
static func danger_of(state: GameState, id: String) -> float:
	if state == null:
		return float(get_def(id).get("danger", 1.0))
	return ExpeditionData.trip_danger(state, id)


static func arrival_text(id: String) -> String:
	var d := get_def(id)
	if d.is_empty():
		return ""
	if d["placeholder"]:
		return "Placeholder layout: %s (a generic %s for now)." % [d["name"], PoiLayouts.VARIANT_NAMES.get(d["variant"], "building")]
	return str(ARRIVAL.get(id, d["name"]))
