class_name DevLooting
extends RefCounted
## Exp 012 (L): the F10 tools of looting, POIs and travel (the dev menu's
## _build_e12_l_section calls these; each returns a status line).
##   route_text   the routes from where Eli is: on foot and by car, the
##                minutes the map shows and travel uses, road vs off-road km,
##                and the old road-only route's cost for comparison
##   mark_mostly  the POI Eli is at: searches and empties containers until
##                80 % are done (the map's "Mostly searched")
##   fill_pack    fills the pack (at a POI) or the household caps (at home)
##                with heavy stone / materials, to test full-inventory searching

const SAMPLES := ["convenience", "hardware", "farmhouse", "military", "library", "quarry"]


static func route_text(game: Node) -> String:
	var s: GameState = game.call("debug_state") if game != null and game.has_method("debug_state") else null
	var here := "home"
	var poi: Variant = game.get("poi") if game != null else null
	if poi is Object and is_instance_valid(poi) and str(poi.get("poi_id")) != "" and RegionLocations.has(str(poi.get("poi_id"))):
		here = str(poi.get("poi_id"))
	var lines := ["Routes from %s (minutes: route on foot / road-only on foot / by car; km road + off-road):" % ("home" if here == "home" else RegionLocations.name_of(here))]
	var targets: Array = SAMPLES.duplicate()
	if s != null and s.region.planned != "" and not targets.has(s.region.planned):
		targets.push_front(s.region.planned)
	if here != "home":
		targets.push_front("home")
	for id in targets:
		if id == here:
			continue
		var f := RegionRouter.route(here, id, false)
		var c := RegionRouter.route(here, id, true)
		var ro := RegionRouter.road_only(here, id, false)
		lines.append("%s: %d / %s / %d min · %.2f + %.2f km%s" % ["Home" if id == "home" else RegionLocations.name_of(id),
			int(f["minutes"]), ("%.0f" % ro) if ro >= 0.0 else "-", int(c["minutes"]), float(f["road_km"]), float(f["off_km"]),
			"" if bool(f["ok"]) and bool(c["ok"]) else " (fallback)"])
	return "\n".join(lines)


## Searches and empties this POI's containers (unsearched ones first, in
## order) until at least 80 % are done.
static func mark_mostly(game: Node) -> String:
	var poi: Variant = game.get("poi") if game != null else null
	if not (poi is Object and is_instance_valid(poi)):
		return "Not at a POI."
	var r: Dictionary = poi.get("record")
	var c: Dictionary = r.get("c", {})
	if c.is_empty():
		return "This place has no containers."
	var ids: Array = c.keys()
	ids.sort()
	for cid in ids:
		if PoiState.searched_share(r) >= PoiState.MOSTLY_SEARCHED:
			break
		var e: Dictionary = c[cid]
		e["searched"] = true
		(e["items"] as Dictionary).clear()
	var w: Variant = poi.get("world")
	if w is Object and is_instance_valid(w) and w.has_method("_update_reveal"):
		w._update_reveal()
	return "%d %% of the containers searched and empty: the map says \"%s\"." % [int(round(PoiState.searched_share(r) * 100.0)), PoiState.MOSTLY_TEXT]


## Fills the pack (away) or the household caps (home) to test searching with no room.
static func fill_pack(game: Node) -> String:
	var s: GameState = game.call("debug_state") if game != null and game.has_method("debug_state") else null
	if s == null:
		return "No game."
	var poi: Variant = game.get("poi") if game != null else null
	if poi is Object and is_instance_valid(poi) and poi.has_method("pack_add"):
		var room := PoiState.room_for("stone", PoiState.pack_load(s, poi.get("pack")), PoiState.pack_cap(s))
		var k := s.inventory.add("stone", mini(room, s.inventory.space_for("stone")))
		poi.pack_add("stone", k)
		return "Pack filled with %d stone (%s)." % [k, PoiState.pack_text(s, poi.get("pack"))]
	var n := 0
	for id in ["wood", "nails", "scrap", "stone", "iron", "water", "canned_food", "snacks", "bandage", "ammo"]:
		n += s.inventory.add(id, s.inventory.space_for(id) if s.inventory.cap(id) > 0 else 30)
	return "Household supplies filled to their caps (+%d)." % n
