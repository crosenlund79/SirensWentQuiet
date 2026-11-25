class_name TravelSites
extends RefCounted
## Exp 007 (T): where a POI's world and helper come from.
##
## Agent P's `src/poi/poi_site.gd` when it is in the project; until then (and
## in a build without it) the local stand-in TravelTestSite. The provider is a
## script with
##   static func build_world(poi_id: String, game) -> HouseWorld   (a PoiWorld)
##   static func make_helper(game) -> Node      (the POI helper; it adds itself
##                                               as game.poi, or the game does)
## and optionally capacity_text(state, car) -> String for the map.

const POI_SITE := "res://src/poi/poi_site.gd"


## The provider script (the one line the lead wires at merge).
static func provider() -> Script:
	return load(POI_SITE) if ResourceLoader.exists(POI_SITE) else TravelTestSite


## A POI id the game can travel to: every place on the region map.
static func is_site(id: String) -> bool:
	return RegionLocations.has(id)


static func build_world(poi_id: String, game: Node) -> HouseWorld:
	var w: Variant = provider().call("build_world", poi_id, game)
	return w if w is HouseWorld else null


static func make_helper(game: Node) -> Node:
	var h: Variant = call_opt("make_helper", [game], null)
	return h if h is Node else null


## Calls an optional static function of the provider; `fallback` when it has none.
static func call_opt(method: String, args: Array, fallback: Variant) -> Variant:
	var p := provider()
	if p == null or not has_static(p, method):
		return fallback
	return p.callv(method, args)


static func has_static(s: Script, method: String) -> bool:
	for m in s.get_script_method_list():
		if str(m.get("name", "")) == method:
			return true
	return false
