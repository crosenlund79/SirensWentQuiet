extends "res://tests/test_case.gd"
## Exp 012 (L): routes and the map vehicle's route (§20), secured rooms
## (§22), the kitchen walkway (§23), never through walls (§24), full
## inventory searching (§25), fixed-size item windows (§26-27) and "Mostly
## searched" (§28).

const PREVIEW := "res://src/poi/poi_preview.tscn"
const Finder := preload("res://src/game/interaction_finder.gd")


class Fake extends Node3D:
	func interact_prompt() -> String:
		return "[E] Use it"

	func interact(_g: Node) -> void:
		pass


class FakeGame extends Node:
	var player: Node3D
	var world: Node
	var levels: Variant = null


func _harness(id: String, car := false, st: GameState = null) -> Node:
	var h: Node = (load(PREVIEW) as PackedScene).instantiate()
	h.configure(id, car, 4242)
	h.preset_state = st
	add(h)
	await physics_frames(3)
	return h


func _plain_box(h: Node) -> PoiSpot:
	for s in (h.world as PoiWorld).spots_of("container"):
		if str(s.data.get("needs", "")) == "" and not bool(s.data.get("picked", false)):
			return s
	return null


# --- §20 routes ---------------------------------------------------------------------------------------

func test_routes_cut_across_open_land_and_the_shown_time_is_the_used_time() -> void:
	var t := RegionTerrain.shared()
	var shorter := 0
	for id in RegionLocations.ids():
		var f := RegionRouter.route("home", id, false)
		check(bool(f["ok"]), "%s: a route on foot" % id)
		var ro := RegionRouter.road_only("home", id, false)
		check(float(f["raw"]) <= ro + 0.01, "%s: never worse than the road route (%.1f vs %.1f)" % [id, f["raw"], ro])
		if float(f["raw"]) < ro - 3.0 and float(f["off_km"]) > 0.05:
			shorter += 1
		check_eq(TravelRules.minutes(id), int(f["minutes"]), "%s: travel uses the route's time" % id)
		check_eq(RegionLocations.travel_minutes(id), int(f["minutes"]), "%s: the list's time is the route's" % id)
		var c := RegionRouter.route("home", id, true)
		check(bool(c["ok"]) and int(c["minutes"]) <= int(f["minutes"]), "%s: the 4x4 gets there, no slower (%d vs %d)" % [id, c["minutes"], f["minutes"]])
		check_eq(TravelRules.minutes(id, true), int(c["minutes"]), "%s: by car too" % id)
		# the route never crosses water (bridges aside) or a building; the car not a garden or forest either
		for mode in [false, true]:
			var pts: PackedVector2Array = RegionRouter.route("home", id, mode)["pts"]
			var bad := ""
			for k in range(1, pts.size()):
				var steps := int(ceil(pts[k - 1].distance_to(pts[k]) / 0.25))
				for j in steps + 1:
					var c2 := RegionTerrain.cell_of(pts[k - 1].lerp(pts[k], float(j) / maxf(steps, 1)))
					var i := RegionTerrain.idx(c2)
					if RegionTerrain.footprint(id).has_point(c2) or RegionTerrain.footprint("home").has_point(c2):
						continue
					if t.water[i] > 0 and t.bridge[i] <= 0:
						bad = "water at %s" % c2
					elif not is_finite(RegionRouter.cell_cost(c2, mode)) and not _near_corner(pts, c2):
						bad = "impassable %s at %s" % ["car" if mode else "foot", c2]
			check(bad == "", "%s %s: %s" % [id, "by car" if mode else "on foot", bad if bad != "" else "clear"])
	check(shorter >= 5, "shortcuts across open land beat the roads for %d places" % shorter)
	# both ways are one route
	check_eq(TravelRules.minutes_between("library", "convenience"), TravelRules.minutes_between("convenience", "library"), "the same both ways")


## A diagonal step between two cells may graze a third one's corner.
func _near_corner(pts: PackedVector2Array, c: Vector2i) -> bool:
	for p in pts:
		if (Vector2(c) + Vector2(0.5, 0.5)).distance_to(p) < 1.0:
			return true
	return false


func test_the_map_draws_the_route_the_time_belongs_to() -> void:
	var s := GameState.new_run(77)
	s.total_minutes = 9.0 * 60.0
	s.region.discover("farmhouse")
	var map := RegionMapScreen.new()
	add(map)
	await frames(2)
	map.open(s)
	map.set_by_car(false)
	map.select("farmhouse", false)
	await frames(1)
	var want: PackedVector2Array = RegionRouter.route("home", "farmhouse", false)["pts"]
	check_eq(map.markers.route_world.size(), want.size(), "the drawn route is the router's (%d points)" % want.size())
	if map.markers.route_world.size() == want.size():
		var p0: Vector3 = map.markers.route_world[want.size() / 2]
		check(Vector2(p0.x, p0.z).distance_to(want[want.size() / 2]) < 0.01, "point for point")
	var tm := TravelRules.leg_timing(s, "home", "farmhouse", false)
	check_eq(int(tm["minutes"]), RegionRouter.minutes("home", "farmhouse"), "the panel's arrival is the route's time")
	map.close()


# --- §21 the map vehicle ---------------------------------------------------------------------------------

func test_the_map_car_is_a_small_4x4() -> void:
	var car := MapTraveller.new()
	add(car)
	car.setup(true)
	var aabb := AABB()
	var first := true
	for c in car.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.name == "Ground":
			continue
		var bb := mi.global_transform * mi.get_aabb()
		aabb = bb if first else aabb.merge(bb)
		first = false
	check(aabb.size.z < 2.0 and aabb.size.z > 1.2, "about half the old 3.4 long (%.2f)" % aabb.size.z)
	check(aabb.size.x < 1.0, "narrow (%.2f)" % aabb.size.x)
	check(car.find_child("Ground", true, false) != null, "a ground disc keeps it readable")


# --- §22 secured rooms ----------------------------------------------------------------------------------------

func test_secured_rooms_have_double_walls_and_no_weak_side() -> void:
	var found := 0
	for arch in PoiArchetypes.ids():
		for k in 14:
			var setup := PoiArchetypes.test_setup(arch, 900 + k * 7)
			var L := PoiGenerator.generate(setup)
			var lined := (L["walls"] as Array).filter(func(w): return int(w.get("lining", 0)) != 0)
			if lined.is_empty():
				continue
			found += 1
			var v := PoiGenerator.validate(L)
			check(v["ok"], "%s #%d: still valid with a secured room %s" % [arch, k, v["problems"]])
			var locked := (L["doors"] as Array).filter(func(d): return d["locked"])
			check(locked.size() >= 1 and locked.all(func(d): return str(d.get("mat", "")) == "metal"), "%s #%d: a steel door" % [arch, k])
			for w in lined:
				var gaps: Array = w.get("gaps", [])
				check(not gaps.any(func(g): return g["kind"] == "window" or g["kind"] == "open"), "%s #%d: no window or opening in a secured wall" % [arch, k])
				check(not PoiGenerator.lining_rects(w).is_empty(), "%s #%d: a lining" % [arch, k])
			if found == 1:
				_check_thickness(L, lined[0])
			# the same site as built before secured rooms: unchanged walls
			var old := setup.duplicate()
			old["secure"] = false
			var L0 := PoiGenerator.generate(old)
			check((L0["walls"] as Array).all(func(w): return int(w.get("lining", 0)) == 0), "%s #%d: an older site keeps its plain walls" % [arch, k])
			break
	check(found >= 3, "secured rooms turn up in %d archetypes" % found)


## Four solid voxels (0.4 m) across a secured wall at a solid point, two at a plain one.
func _check_thickness(L: Dictionary, w: Dictionary) -> void:
	var g := VoxelHouse.create_grid(true)
	PoiWorld._stamp_floors(g, L.get("floors", []))
	for wall in L["walls"]:
		PoiWorld._stamp_poi_wall(g, wall)
	var a: Vector2 = w["a"]
	var b: Vector2 = w["b"]
	var horiz := is_equal_approx(a.y, b.y)
	var line := a.y if horiz else a.x
	var lr: Rect2 = PoiGenerator.lining_rects(w)[0]
	var along := (lr.position.x + lr.end.x) * 0.5 if horiz else (lr.position.y + lr.end.y) * 0.5
	var solid := 0
	var y := VoxelHouse.BASE_ROW + 12
	for k in 9:
		var off := line - 0.4 + k * 0.1 + 0.05
		var p := Vector3(along, 0, off) if horiz else Vector3(off, 0, along)
		var c := g.cell_of(Vector3(p.x, 0, p.z))
		if g.get_mat(c.x, y, c.z) != VoxelMat.AIR:
			solid += 1
	check(solid >= 4, "a secured wall is at least 4 voxels thick across (%d)" % solid)
	check(VoxelMat.HARDNESS[VoxelMat.MASONRY] >= 0.8, "concrete is hard to shoot through")


# --- §23 the kitchen walkway --------------------------------------------------------------------------------------

func test_the_kitchen_island_leaves_a_walkway() -> void:
	var stools := HousePlan.FURNITURE.filter(func(f): return f["type"] == "stool")
	for f in stools:
		var r: Rect2 = f["rect"]
		check(3.9 - r.end.y >= 2.0 * Tuning.PLAYER_RADIUS + 0.15, "%s: %.2f m to the wall" % [f["id"], 3.9 - r.end.y])
	var w := HouseWorld.new()
	add(w)
	w.build_new()
	await physics_frames(2)
	var path := w.nav.find_path(Vector2(9.2, 3.6), Vector2(12.9, 3.6))
	var length := 0.0
	for k in range(1, path.size()):
		length += path[k - 1].distance_to(path[k])
	check(path.size() >= 2 and length < 5.0, "south of the island, not round it (%.1f m)" % length)


# --- §24 never through walls -----------------------------------------------------------------------------------------

func test_nothing_is_picked_through_a_wall() -> void:
	var w := HouseWorld.new()
	add(w)
	w.build_new()
	var g := FakeGame.new()
	add(g)
	g.world = w
	var pl := Node3D.new()
	add(pl)
	g.player = pl
	pl.global_position = Vector3(3.0, 0, 3.4)            # the bedroom
	var behind := Fake.new()
	add(behind)
	behind.global_position = Vector3(3.0, 0, 4.6)        # the living room, past the wall at y = 4
	var here := Fake.new()
	add(here)
	here.global_position = Vector3(3.6, 0, 2.6)          # the bedroom
	await physics_frames(1)
	var seen := Finder.in_sight([behind, here], g)
	check(not seen.has(behind), "the thing behind the wall is not offered")
	check(seen.has(here), "the one in the room is")
	check_eq(Finder.nearest(seen, Vector2(3.0, 3.4)), here, "E picks the one in the room")
	# hysteresis: the current choice stays for a few centimetres
	var a := Fake.new()
	var b := Fake.new()
	add(a)
	add(b)
	a.global_position = Vector3(1.0, 0, 1.0)
	b.global_position = Vector3(1.0, 0, 2.0)
	check_eq(Finder.nearest([a, b], Vector2(1.0, 1.55), Finder.RADIUS, a), a, "a slightly nearer one doesn't steal the focus")
	check_eq(Finder.nearest([a, b], Vector2(1.0, 1.8), Finder.RADIUS, a), b, "a clearly nearer one does")


# --- §25 full inventory ---------------------------------------------------------------------------------------------

func test_a_full_pack_never_leaves_a_container_unsearchable() -> void:
	var h: Node = await _harness("convenience")
	var s := _plain_box(h)
	if not check(s != null, "a container"):
		return
	var items: Dictionary = h.poi.record["c"][s.id]["items"]
	items.clear()
	items["water"] = 12
	items["snacks"] = 2
	h.state.inventory.add("stone", 13)
	h.poi.pack_add("stone", 13)              # 26 of 30: room for 4 water
	h.player.global_position = s.position
	# hunger and thirst slowly draining health don't interrupt a search
	h.poi.interact_spot(s)
	h.state.health -= 0.3
	await frames(3)
	check(h.poi.busy_with(s), "a slow drain doesn't stop the search")
	h.poi.complete_action()
	check(h.poi.panel.is_open, "searched: the panel")
	check_eq(h.poi.panel.take("water", 12), 4, "takes what fits")
	h.poi.close_panel()
	check(s.interact_prompt().begins_with("[E] Take from"), "still usable: %s" % s.interact_prompt())
	check_eq(h.poi.marker_for(s)[0], "left", "the marker says something is left")
	check(not PoiState.mostly_searched(h.state, "convenience") or PoiState.searched_share(h.poi.record) >= 0.8, "a half-full box is not 'searched'")
	# a save round-trip keeps the rest
	var st2: GameState = GameState.from_dict(h.state.to_dict())
	var box2: Dictionary = st2.region.poi["convenience"]["c"][s.id]
	check(bool(box2["searched"]) and int(box2["items"].get("water", 0)) == 8 and int(box2["items"].get("snacks", 0)) == 2, "saved: %s" % str(box2))
	# room again: the rest comes out
	h.poi.pack_remove("stone", 13)
	h.state.inventory.remove("stone", 13)
	h.poi.interact_spot(s)
	check(h.poi.panel.is_open, "opens again")
	var got: Dictionary = h.poi.panel.take_everything()
	check_eq(got, {"water": 8, "snacks": 2}, "the rest")
	h.poi.close_panel()
	check(s.interact_prompt().contains("empty"), "really empty now: %s" % s.interact_prompt())
	# a loose item: a partial pick-up leaves the rest lying there
	var pick: PoiSpot = null
	for p in (h.world as PoiWorld).spots_of("pickup"):
		if not h.poi.record["taken"].has(p.id) and int(p.data.get("n", 1)) >= 2 and not Items.is_unique(str(p.data["item"])):
			pick = p
			break
	if pick != null:
		var item := str(pick.data["item"])
		var room_left := 1
		var fill := PoiState.pack_cap(h.state) - PoiState.pack_load(h.state, h.poi.pack) - PoiState.weight_of(item) * room_left
		var k := int(floor(fill / PoiState.weight_of("stone")))
		h.state.inventory.add("stone", k)
		h.poi.pack_add("stone", k)
		var fits := PoiState.room_for(item, PoiState.pack_load(h.state, h.poi.pack), PoiState.pack_cap(h.state))
		if fits >= 1 and fits < int(pick.data["n"]):
			check(h.poi.pick_up(pick), "picks up what fits")
			check(not h.poi.record["taken"].has(pick.id) and h.poi.pickup_left(pick) == int(pick.data["n"]) - fits, "the rest stays (%d)" % h.poi.pickup_left(pick))


# --- §26-27 fixed-size windows and compact rows --------------------------------------------------------------------------

func test_item_windows_keep_their_size_and_rows_stay_compact() -> void:
	var s := GameState.new_run(5)
	var panel := PoiLootPanel.new()
	add(panel)
	var sizes := []
	for n in [0, 3, 40]:
		var items := {}
		var ids: Array = Items.DEFS.keys()
		for k in n:
			var id: String = ids[k % ids.size()]
			items[id] = int(items.get(id, 0)) + 1 + k
		if n == 40:
			for k in 40:
				items[ids[k % ids.size()]] = 3
		panel.open_items(s, "Test box", items, null)
		await frames(3)
		sizes.append(panel._panel.size)
		panel.close()
		await frames(2)
	check(sizes[0] == sizes[1] and sizes[1] == sizes[2], "the same size empty, with 3 and with many (%s)" % str(sizes))
	check(absf(sizes[0].y - StoragePanel.HEIGHT) < 1.0 and absf(sizes[0].x - StoragePanel.WIDTH) < 1.0, "the fixed size (%s)" % str(sizes[0]))
	# taking doesn't move the window; rows are one line with the description in a tooltip
	var items2 := {"water": 3, "canned_food": 2, "bandage": 1}
	panel.open_items(s, "Shelf", items2, null)
	await seconds(0.5)             # past the opening slide
	var pos: Vector2 = panel._panel.global_position
	var row: Control = panel.find_child("Stored_water", true, false)
	check(row != null and row.tooltip_text.contains(str(Items.DEFS["water"]["desc"])), "the description is the row's tooltip")
	check(row != null and row.size.y <= ItemRows.ROW_H + 2.0, "one compact line (%.0f px)" % (row.size.y if row != null else -1.0))
	var det: Label = panel.find_child("Details", true, false)
	check(det != null, "a details line for keyboard selection")
	var b: Button = row.get_node("Take1") if row != null else null
	if b != null:
		b.grab_focus()
		await frames(1)
		check(det.text.contains("Bottled water"), "focusing a row's button shows its description: %s" % det.text)
	panel.take("water", 3)
	await frames(3)
	check(panel._panel.global_position.is_equal_approx(pos), "the window didn't move")
	check(panel.find_child("Gone_water", true, false) != null, "the taken row stays, dimmed (nothing jumps)")
	var got := []
	panel.taken.connect(func(id, n): got.append([id, n]))
	panel.take_everything()
	check(got.size() == 2, "taken(id, n) for each take: %s" % str(got))
	panel.close()


# --- §28 mostly searched --------------------------------------------------------------------------------------------------

func test_mostly_searched_at_eighty_percent() -> void:
	var s := GameState.new_run(9)
	var r := PoiState.record(s, "hardware")
	for k in 10:
		r["c"]["c%d" % k] = {"items": {"nails": 2}, "searched": false, "day": 1}
	check(not PoiState.mostly_searched(s, "hardware"), "fresh")
	for k in 7:
		r["c"]["c%d" % k]["searched"] = true
		r["c"]["c%d" % k]["items"] = {}
	r["c"]["c7"]["searched"] = true                   # searched but left full: not done
	check(not PoiState.mostly_searched(s, "hardware"), "70 %% done (%.2f)" % PoiState.searched_share(r))
	r["c"]["c7"]["items"] = {}
	check(PoiState.mostly_searched(s, "hardware"), "80 %% done (%.2f)" % PoiState.searched_share(r))
	var s2: GameState = GameState.from_dict(s.to_dict())
	check(PoiState.mostly_searched(s2, "hardware"), "kept by the save")
	check(TravelRules.block_reason(s2, "hardware") == "" or not TravelRules.block_reason(s2, "hardware").contains("searched"), "never blocks travel")
	s2.region.discover("hardware")
	var map := RegionMapScreen.new()
	add(map)
	await frames(2)
	map.open(s2)
	var e: Array = map.markers.entries.filter(func(x): return x["id"] == "hardware")
	check(not e.is_empty() and bool(e[0].get("mostly", false)), "the map marks it")
	map.close()
