class_name PoiSite
extends RefCounted
## Experiment 007 (P): the entry points for the game's POI site mode (agent
## T's SurvivalGame calls these; SPEC §1-2).
##
##   var w := PoiSite.build_world(poi_id, self)   # instead of HouseWorld + build_new
##   ...                                          # player, camera, roster, combat, UI...
##   PoiSite.make_helper(self)                    # sets game.poi
##
## build_world returns the PoiWorld already built and ready (as the house
## after build_new): configured with game.lighting, added to `game` as
## "World" (do not add it again) and holding the visit's record. Eli came by
## car when GameLaunch.carry["travel"] says so ("by_car" / "car" true, or
## "mode" == "car"): the car then stands by the entry with its boot. The
## player starts at world.entry_point() (also world.bed_position()).
## make_helper adds the POI helper (src/poi/game_poi.gd) to `game` as "Poi",
## sets game.poi when the game has that property, and starts the visit.

const HelperScript := preload("res://src/poi/game_poi.gd")


static func build_world(poi_id: String, game: Node, by_car := -1) -> HouseWorld:
	if not PoiDefs.has(poi_id):
		push_warning("PoiSite: unknown place '%s'" % poi_id)
		return null
	var w := PoiWorld.new()
	var light: Variant = game.get("lighting") if game != null else null
	var car := HelperScript.arrived_by_car() if by_car < 0 else by_car > 0
	w.configure(poi_id, light if light is VoxelLighting else null, car)
	var st: Variant = game.get("state") if game != null else null
	if st is GameState:
		w.state = st
		w.record = PoiState.record(st, poi_id)
	if game != null and w.get_parent() == null:
		game.add_child(w)
	w.build_new()
	return w


static func make_helper(game: Node) -> Node:
	var h: Node = HelperScript.new()
	h.name = "Poi"
	if game != null:
		game.add_child(h)
		if "poi" in game:
			game.set("poi", h)
		h.setup(game)
	return h
