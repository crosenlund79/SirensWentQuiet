extends "res://tests/test_case.gd"
## Sanity of the shared floor plan all three versions build from.


func test_wall_spans_cover_each_wall() -> void:
	for w in HousePlan.WALLS:
		var spans := HousePlan.wall_spans(w)
		var horiz := HousePlan.is_horizontal(w)
		var start: float = minf(w["a"].x, w["b"].x) if horiz else minf(w["a"].y, w["b"].y)
		var end: float = maxf(w["a"].x, w["b"].x) if horiz else maxf(w["a"].y, w["b"].y)
		check(is_equal_approx(spans[0]["from"], start), "%s spans start at wall start" % w["id"])
		check(is_equal_approx(spans[-1]["to"], end), "%s spans end at wall end" % w["id"])
		for i in range(1, spans.size()):
			check(is_equal_approx(spans[i]["from"], spans[i - 1]["to"]), "%s spans contiguous" % w["id"])


func test_openings_lie_on_their_walls() -> void:
	for o in HousePlan.OPENINGS:
		var w := HousePlan.wall_by_id(o["wall"])
		check(not w.is_empty(), "%s has a wall" % o["id"])
		var r := HousePlan.span_rect(w, o["from"], o["to"])
		check(HousePlan.wall_rect(w).encloses(r), "%s inside wall %s" % [o["id"], o["wall"]])


func test_furniture_inside_rooms_and_props_outside() -> void:
	for f in HousePlan.FURNITURE:
		var room := {}
		for r in HousePlan.ROOMS:
			if r["id"] == f["room"]:
				room = r
		check(not room.is_empty(), "%s room exists" % f["id"])
		check((room["rect"] as Rect2).encloses(f["rect"]), "%s inside %s" % [f["id"], f["room"]])
	for p in HousePlan.PROPS:
		check(HousePlan.YARD.encloses(p["rect"]), "%s inside yard" % p["id"])
	var ext := 0
	for o in HousePlan.OPENINGS:
		if o["kind"] == "door" and HousePlan.wall_by_id(o["wall"])["exterior"]:
			ext += 1
	check(ext >= 2, "at least two external access points")
	check_eq(HousePlan.ROOMS.size(), 5, "five rooms")


func test_spawn_points_and_start_are_walkable() -> void:
	var nav := GridNav.new()
	HousePlan.rasterize_into(nav)
	for s in HousePlan.SPAWN_POINTS:
		check(HousePlan.YARD.has_point(s) and not HousePlan.FOOTPRINT.grow(0.5).has_point(s), "spawn %s outside house" % s)
		check(nav.is_walkable(nav.cell_of(s)), "spawn %s walkable" % s)
	check(nav.is_walkable(nav.cell_of(HousePlan.PLAYER_START)), "player start walkable")
