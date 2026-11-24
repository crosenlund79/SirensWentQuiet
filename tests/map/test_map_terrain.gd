extends "res://tests/test_case.gd"
## The region map's terrain (SPEC-003 §6): determinism and the geography
## contracts with RegionLocations. Owner: M.


func test_map_terrain_is_deterministic() -> void:
	var a := RegionTerrain.new()
	a.build()
	var b := RegionTerrain.new()
	b.build()
	var ha := a.content_hash()
	check_eq(ha, b.content_hash(), "two builds hash the same")
	check_eq(ha, RegionTerrain.shared().content_hash(), "the shared region is the same region")
	check(ha.length() == 64, "a SHA-256 hex digest")
	check(a.boxes.size() > 1000 and a.trees.size() > 1000, "buildings and trees were generated")


func test_map_every_location_on_land_in_its_district() -> void:
	var t := RegionTerrain.shared()
	for id in RegionLocations.ids():
		var d := RegionLocations.get_def(id)
		var c := RegionTerrain.cell_of(d["pos"])
		check(not t.is_water(c), "%s is not under water" % id)
		check(t.height_at(c) > RegionTerrain.SEA, "%s is above the sea" % id)
		check_eq(t.district_at(c), d["district"], "%s lies in its district" % id)
		var dry := 0
		var cells := 0
		var r := RegionTerrain.footprint(id)
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				cells += 1
				if not t.is_water(Vector2i(x, y)):
					dry += 1
		check(dry == cells, "%s: the whole footprint is dry (%d of %d)" % [id, dry, cells])
	var home := RegionTerrain.cell_of(RegionLocations.HOME)
	check(not t.is_water(home) and t.district_at(home) == "suburbs", "the house stands in the suburbs")


func test_map_roads_connect_every_location_to_home() -> void:
	var t := RegionTerrain.shared()
	var reach := t.roads_reachable_from_home()
	check(reach.size() > 100, "a road network leaves the house (%d cells)" % reach.size())
	for id in RegionLocations.ids():
		check(t.connected_to_home(id), "%s has a road to the house" % id)
		var path := t.route_from_home(id)
		check(path.size() >= 3, "%s: a route can be drawn (%d points)" % [id, path.size()])
		if path.size() >= 3:
			# consecutive road cells are 4-neighbours (a continuous road)
			var ok := true
			for k in range(2, path.size() - 1):
				if path[k].distance_to(path[k - 1]) > 1.01:
					ok = false
			check(ok, "%s: the route is continuous" % id)


func test_map_river_runs_from_the_mountains_to_the_bay() -> void:
	var t := RegionTerrain.shared()
	var src := RegionTerrain.cell_of(t.river_path[0])
	check_eq(t.district_at(src), "mountains", "the river rises in the mountains")
	check(t.is_water(src), "the source is water (a tarn)")
	# flood fill over river water from the source until the sea is touched
	var seen := {src: true}
	var queue: Array[Vector2i] = [src]
	var head := 0
	var reached := false
	while head < queue.size() and not reached:
		var c := queue[head]
		head += 1
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := c + d
			if not RegionTerrain.in_bounds(n) or seen.has(n):
				continue
			var i := RegionTerrain.idx(n)
			if t.waterkind[i] == 2:
				reached = true
				break
			if t.waterkind[i] == 1:
				seen[n] = true
				queue.append(n)
	check(reached, "the river water connects to the bay (%d river cells walked)" % seen.size())
	var mouth := RegionTerrain.cell_of(t.river_path[t.river_path.size() - 1])
	check(mouth.x > 120, "the mouth is on the east coast")
	var downhill := true
	for k in range(1, t.river_level.size()):
		if t.river_level[k] > t.river_level[k - 1]:
			downhill = false
	check(downhill, "the water level never rises downstream")
	check(t.river_level[0] > t.river_level[t.river_level.size() - 1] + 10, "it falls from the mountains")
	check_eq(t.river_level[t.river_level.size() - 1], RegionTerrain.SEA, "it ends at sea level")


func test_map_water_never_stands_above_its_banks() -> void:
	var t := RegionTerrain.shared()
	var bad := 0
	for y in RegionTerrain.H:
		for x in RegionTerrain.W:
			var w := t.water_at(Vector2i(x, y))
			if w <= 0:
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n := Vector2i(x, y) + d
				if RegionTerrain.in_bounds(n) and not t.is_water(n) and t.height_at(n) < w:
					bad += 1
	check_eq(bad, 0, "dry neighbours of water are at least as high as the water")


func test_map_geography_follows_the_location_list() -> void:
	var t := RegionTerrain.shared()
	# the harbour and the docks are on the bay
	for id in ["restaurant", "warehouse"]:
		check(_near_sea(t, RegionTerrain.cell_of(RegionLocations.get_def(id)["pos"]), 8), "%s is by the bay" % id)
	# the sawmill is on the river
	check(_near_river(t, RegionTerrain.cell_of(RegionLocations.get_def("sawmill")["pos"]), 5), "the sawmill is on the river")
	# mountains in the north-west are the highest ground
	var nw := 0
	var rest := 0
	for y in RegionTerrain.H:
		for x in RegionTerrain.W:
			var h := t.height_at(Vector2i(x, y))
			if x < 45 and y < 40:
				nw = maxi(nw, h)
			elif x > 60 or y > 60:
				rest = maxi(rest, h)
	check(nw > rest + 10, "the north-west mountains (%d) tower over the rest (%d)" % [nw, rest])
	# the quarry is cut into the foothills: its floor lies below the land around it
	var q := RegionTerrain.footprint("quarry")
	var floor_h := t.height_at(q.get_center())
	var rim := 0
	for c in [q.position + Vector2i(-1, -1), Vector2i(q.end.x, q.position.y - 1), Vector2i(q.position.x - 1, q.end.y), q.end]:
		rim = maxi(rim, t.height_at(c))
	check(rim > floor_h, "the quarry floor (%d) is cut below its rim (%d)" % [floor_h, rim])
	# the house is south-west of the centre
	check(RegionLocations.HOME.x < 90 and RegionLocations.HOME.y > 70, "the house is on the south-western edge of town")
	# forests in the north, fields in the farmland
	var forest := 0
	var fields := 0
	for i in RegionTerrain.W * RegionTerrain.H:
		if t.cover[i] == RegionTerrain.C_FOREST and i / RegionTerrain.W < 50:
			forest += 1
		if t.cover[i] == RegionTerrain.C_FIELD and t.district[i] == RegionTerrain.DISTRICT_IDS.find("farmland"):
			fields += 1
	check(forest > 800, "the north is wooded (%d forest cells)" % forest)
	check(fields > 100, "the farmland has fields (%d)" % fields)


func test_map_performance_budget() -> void:
	var t := RegionTerrain.new()
	t.build()
	var m := RegionMapMesher.build(t)
	var faces: Dictionary = m["faces"]
	var total := int(faces["terrain"]) + int(faces["props"]) + int(faces["water"]) + int(faces["trees"])
	print("    map budget: terrain %.0f ms, meshes %.0f ms; faces terrain %d, props %d, water %d, trees %d, total %d; %d boxes, %d trees" % [
		t.build_ms, m["ms"], faces["terrain"], faces["props"], faces["water"], faces["trees"], total, t.boxes.size(), t.trees.size()])
	check(t.build_ms < 4000.0, "terrain builds in under 4 s headless (%.0f ms)" % t.build_ms)
	check(float(m["ms"]) < 4000.0, "meshes build in under 4 s headless (%.0f ms)" % m["ms"])
	check(total < 260000, "under 260k quads in total (%d)" % total)
	check(int(faces["terrain"]) < 60000, "terrain under 60k quads (%d)" % faces["terrain"])
	check((m["terrain"] as Array).size() == 20, "20 terrain chunks (32 x 32 columns)")


static func _near_sea(t: RegionTerrain, c: Vector2i, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var n := c + Vector2i(dx, dy)
			if RegionTerrain.in_bounds(n) and t.waterkind[RegionTerrain.idx(n)] == 2:
				return true
	return false


static func _near_river(t: RegionTerrain, c: Vector2i, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var n := c + Vector2i(dx, dy)
			if RegionTerrain.in_bounds(n) and t.waterkind[RegionTerrain.idx(n)] == 1:
				return true
	return false
