extends "res://tests/test_case.gd"
## RegionMapScreen and MapInfo (SPEC-003 §6): opening and closing, planning,
## hidden undiscovered places, keyboard, layout check. Owner: M.

var _plans: Array = []
var _closed := 0
var _travels: Array = []           # Exp 007 (T)


func _screen(state: GameState) -> RegionMapScreen:
	var s := RegionMapScreen.new()
	add(s)
	s.destination_selected.connect(func(id, purpose): _plans.append([id, purpose]))
	s.closed.connect(func(): _closed += 1)
	s.travel_requested.connect(func(id, car): _travels.append([id, car]))     # Exp 007 (T)
	s.open(state)
	return s


func test_map_screen_opens_and_closes() -> void:
	var state := GameState.new_run(7)
	var s := _screen(state)
	await frames(2)
	check(s.is_open and s.visible, "open() shows the map")
	check(s.view != null and s.view.camera != null, "the 3D view is built")
	check(s.view.get_viewport() != s.get_viewport(), "the miniature renders in its own viewport")
	s.close()
	check(not s.is_open, "close() closes it")
	check_eq(_closed, 1, "closed is emitted once")
	s.close()
	check_eq(_closed, 1, "closing twice emits once")
	await seconds(0.3)
	check(not s.visible, "hidden after the fade")
	s.open(state)
	check(s.is_open and s.visible, "it opens again")
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	s._input(esc)
	check(not s.is_open, "Esc closes the map")
	check_eq(_closed, 2, "closed emitted again")


func test_map_plan_sets_region_state_and_emits_once() -> void:
	var state := GameState.new_run(8)
	var s := _screen(state)
	s.select("hardware")
	check_eq(s.selected, "hardware", "a known place can be selected")
	s._set_approach("careful", "")
	check(s.plan_selected(), "planning works")
	check_eq(state.region.planned, "hardware", "RegionState.planned set")
	check_eq(state.region.planned_purpose, "careful", "RegionState.planned_purpose set")
	check_eq(_plans.size(), 1, "destination_selected emitted once")
	if _plans.size() == 1:
		check_eq(_plans[0], ["hardware", "careful"], "with the id and the purpose")
	check(s.is_open, "planning doesn't close the map (the game decides)")
	check_eq(s.markers.planned, "hardware", "the pin shows the plan")
	# targeted collection: "targeted:<item>" when the place lists targets
	s.select("grocery")
	s._set_approach("targeted", "")
	s.plan_selected()
	var targets: Array = s._summary.get("targets", [])
	var expect := "targeted:" + str(targets[0]) if not targets.is_empty() else "targeted"
	check_eq(state.region.planned, "grocery", "a new plan replaces the old one")
	check_eq(state.region.planned_purpose, expect, "targeted purpose")
	check_eq(_plans.size(), 2, "one signal per plan")
	# home and nothing can't be planned
	s.select(MapInfo.HOME)
	check(not s.plan_selected(), "the house is not a destination")
	s.select("")
	check(not s.plan_selected(), "nothing selected, nothing planned")
	check_eq(_plans.size(), 2, "no extra signals")


func test_map_undiscovered_places_are_hidden() -> void:
	var state := GameState.new_run(9)
	var s := _screen(state)
	var shown := s.shown_ids()
	check(MapInfo.HOME in shown, "the house is always shown")
	for id in RegionLocations.ids():
		check_eq(id in shown, state.region.is_discovered(id), "%s shown only when discovered" % id)
	check(not ("military" in shown), "the outpost starts hidden")
	s.select("military")
	check_eq(s.selected, "", "an undiscovered place can't be selected")
	state.region.discover("military")
	s.open(state)
	check("military" in s.shown_ids(), "discovered places appear on reopening")
	s.select("military")
	check_eq(s.selected, "military", "and can be selected")


func test_map_opens_on_the_planned_place() -> void:
	var state := GameState.new_run(10)
	state.region.discover("quarry")
	MapInfo.plan(state, "quarry", "careful")
	var s := _screen(state)
	check_eq(s.selected, "quarry", "the planned place is preselected")
	check_eq(s.approach, "careful", "with its purpose")
	check(s.markers.route_world.size() > 3, "and the road there is drawn")


func test_map_keyboard() -> void:
	var state := GameState.new_run(11)
	var s := _screen(state)
	s._input(_key(KEY_H))
	check_eq(s.selected, MapInfo.HOME, "H finds the house")
	s._input(_key(KEY_TAB))
	var first := s.selected
	check(first != MapInfo.HOME and state.region.is_discovered(first), "Tab selects the nearest known place (%s)" % first)
	s._input(_key(KEY_TAB))
	check(s.selected != first, "Tab moves on")
	# Exp 007 (T): Enter travels (the map's purposes and "Plan" are gone); C picks the car when it runs
	s._input(_key(KEY_C))
	check(not s.by_car, "no car without a repaired car")
	s._input(_key(KEY_ENTER))
	check_eq(_travels.size(), 1, "Enter asks to travel once")
	check_eq(_travels[0][0] if not _travels.is_empty() else "", s.selected, "to the selected place")
	check(_plans.is_empty(), "no plan")
	state.car_repaired = true
	state.inventory.add("fuel", 1)
	s._input(_key(KEY_C))
	check(s.by_car, "C: by car")
	var m := InputEventAction.new()
	m.action = "open_map"
	m.pressed = true
	s._input(m)
	check(not s.is_open, "M closes the map")


func test_map_layout_check() -> void:
	var state := GameState.new_run(12)
	var s := _screen(state)
	check(s.layout_ok, "a fresh run matches the map layout (%s)" % RegionTerrain.LAYOUT_ID)
	check_eq(state.region.layout, RegionTerrain.LAYOUT_ID, "RegionState's default layout is this map")
	state.region.layout = "region-v0"
	s.open(state)
	check(not s.layout_ok, "a different layout is noticed")
	check(s._title_sub.text.contains("region-v0"), "and mentioned")


func test_map_markers_follow_the_camera() -> void:
	var state := GameState.new_run(13)
	var s := _screen(state)
	await frames(3)
	var p := s.markers.head_position("hardware")
	check(p != Vector2.INF, "the hardware store's pin is projected")
	if p != Vector2.INF:
		check_eq(s.markers.hit(p), "hardware", "and can be hit with the mouse")
	check_eq(s.markers.hit(Vector2(-500, -500)), "", "nothing far away")


func test_map_info_fallback_and_expedition_shape() -> void:
	var state := GameState.new_run(14)
	MapInfo.set_stock(state, "grocery", 0.4)
	for id in RegionLocations.ids():
		var f := MapInfo.fallback(id, state)
		for k in ["name", "category_name", "district_name", "travel_minutes", "risk_name", "risk_tier", "resources_text", "equipment", "approaches", "stock", "stock_text"]:
			check(f.has(k), "%s fallback has %s" % [id, k])
		check_eq(f["travel_minutes"], RegionLocations.travel_minutes(id), "%s travel time from RegionLocations" % id)
		check_eq((f["approaches"] as Array).size(), 4, "%s: four mission purposes" % id)
	check_eq(MapInfo.fallback("grocery", state)["stock_text"], "Mostly stripped", "stock from RegionState")
	check(absf(MapInfo.today_stock(state, "grocery") - 0.4) < 0.001, "today's stock on the day it was left")
	var s := MapInfo.summary("grocery", state)
	check(s.has("approaches") and s["name"] != "", "summary() always answers")
	var ed: Variant = ExpeditionData
	if (ed as Object).has_method("location_summary"):
		check_eq(s["source"], "expedition", "the expedition module's data is used when it exists")
		check(not (s["approaches"] as Array).is_empty() and s["travel_minutes"] > 0, "with approaches and travel time")
	# the expedition module's shape (X's location_summary) is read as documented
	var x := {"name": "Supermarket", "category": "food", "district": "centre", "risk_name": "High", "travel_minutes": 25,
		"search_minutes": 120, "minutes": 170, "rewards": "Lots of tins.", "resources": ["canned_food"], "targets": ["water", "canned_food"],
		"equipment": [{"id": "crowbar", "name": "Crowbar", "effect": "Opens the stockroom.", "have": true, "required": false}],
		"approaches": [{"id": "general", "name": "General scavenging", "available": true, "reason": "", "minutes": 170, "risk_name": "High"},
			{"id": "raid", "name": "High-risk raid", "available": false, "reason": "Needs 3 rounds."}],
		"stock": 0.4, "stock_text": "Mostly stripped", "notes": ["Visited 2 times, last on day 3."]}
	var n := MapInfo.normalize(x, MapInfo.fallback("grocery", state))
	check_eq(n["source"], "expedition", "marked as the expedition's data")
	check_eq(n["risk_tier"], 2, "risk name -> tier")
	check_eq(n["resources_text"], "Lots of tins.", "rewards text preferred")
	check_eq(n["targets"], ["water", "canned_food"], "targets kept")
	check_eq((n["approaches"] as Array).size(), 2, "approaches from the expedition data")
	check_eq(n["approaches"][1]["available"], false, "availability kept")
	check_eq(n["notes"], ["Visited 2 times, last on day 3."], "notes kept")
	check_eq(MapInfo.normalize({"risk_name": 5, "equipment": "junk", "approaches": [7]}, MapInfo.fallback("grocery", state))["risk_name"],
		MapInfo.fallback("grocery", state)["risk_name"], "garbage falls back")
	check_eq(MapInfo.split_purpose("targeted:wood"), ["targeted", "wood"], "purpose split")
	check_eq(MapInfo.split_purpose("nonsense")[0], "general", "unknown purpose -> general")


func test_map_clouds_drift_and_clear_around_the_cursor() -> void:
	var s := _screen(GameState.new_run(15))
	var v := s.view
	var mat: ShaderMaterial = v.cloud_mats[0]
	await frames(2)
	var a: Vector2 = mat.get_shader_parameter("cloud_offset")
	await seconds(0.5)
	var b: Vector2 = mat.get_shader_parameter("cloud_offset")
	check(b.distance_to(a) > 0.1, "the clouds drift (%s -> %s)" % [a, b])
	check_eq(v.surface_mat.get_shader_parameter("cloud_offset"), v.cloud_mats[0].get_shader_parameter("cloud_offset"), "shadows move with the clouds")
	v.set_clear_points(Vector2(800, 450), Vector3.INF)
	v._update_clouds()
	check((mat.get_shader_parameter("clear_a") as Vector2).x > -900.0, "the clouds clear around the cursor")
	v.set_view(Vector3(60, RegionMapView.GROUND_Y, 90), RegionMapView.DIST_MIN, true)
	v._update_clouds()
	check(float(mat.get_shader_parameter("opacity")) < 0.05, "zoomed in, the camera is below the clouds")
	s.find_home()
	check_eq(s.selected, MapInfo.HOME, "find my house selects it")
	check(v.focus_target.distance_to(v.terrain.anchor_of(MapInfo.HOME) * Vector3(1, 0, 1) + Vector3(0, RegionMapView.GROUND_Y, 0)) < 0.5, "and moves the camera there")


func test_map_prewarm_caches() -> void:
	RegionMapScreen.prewarm()
	var t0 := Time.get_ticks_usec()
	var m := RegionMapMesher.build(RegionTerrain.shared())
	check((Time.get_ticks_usec() - t0) / 1000.0 < 5.0, "after prewarm the meshes come from the cache")
	check(not (m["terrain"] as Array).is_empty(), "with terrain")


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	return e
