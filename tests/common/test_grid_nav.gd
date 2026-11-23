extends "res://tests/test_case.gd"
## GridNav: rasterisation, paths through doorways, reacting to new openings.


func _nav() -> GridNav:
	var nav := GridNav.new()
	HousePlan.rasterize_into(nav)
	return nav


func _length(path: PackedVector2Array) -> float:
	var l := 0.0
	for i in range(1, path.size()):
		l += path[i].distance_to(path[i - 1])
	return l


func _crosses_wall(nav: GridNav, path: PackedVector2Array) -> bool:
	for p in path:
		if nav.get_raw(nav.cell_of(p)) == GridNav.WALL:
			return true
	return false


func test_rasterised_plan() -> void:
	var nav := _nav()
	check_eq(nav.get_raw(nav.cell_of(Vector2(4.0, 4.0))), GridNav.WALL, "interior wall cell")
	check_eq(nav.get_raw(nav.cell_of(Vector2(4.5, 9.0))), GridNav.OPEN, "front door cell")
	check(nav.is_walkable(nav.cell_of(Vector2(2.5, 4.0))), "bedroom doorway walkable")
	check(nav.is_walkable(nav.cell_of(Vector2(9.0, 4.0))), "kitchen opening walkable")
	check_eq(nav.get_raw(nav.cell_of(Vector2(2.0, 1.0))), GridNav.SOLID, "bed is solid")
	check_eq(nav.get_raw(nav.cell_of(Vector2(2.0, 0.0))), GridNav.WALL, "window counts as wall")


func test_path_uses_doorway_without_crossing_walls() -> void:
	var nav := _nav()
	var path := nav.find_path(Vector2(2.5, 3.0), HousePlan.PLAYER_START)
	check(path.size() > 2, "path found")
	check(not _crosses_wall(nav, path), "path stays in openings")
	var through_door := false
	for p in path:
		if absf(p.y - 4.0) < 0.01 and p.x > 2.0 and p.x < 3.0:
			through_door = true
	check(through_door, "path goes through the bedroom door")


func test_new_opening_is_used() -> void:
	var nav := _nav()
	var a := Vector2(8.5, 12.0)
	var b := Vector2(8.5, 7.0)
	var before := nav.find_path(a, b)
	check(not _crosses_wall(nav, before), "initially routes via a door")
	var rev := nav.revision
	var hole := HousePlan.span_rect(HousePlan.wall_by_id("south"), 8.0, 9.0)
	nav.mark_rect(hole, GridNav.OPEN)
	nav.refresh_region(hole)
	check(nav.revision > rev, "revision bumps on change")
	var after := nav.find_path(a, b)
	check(_length(after) < _length(before) - 2.0, "shorter path through the new hole (%.1f vs %.1f)" % [_length(after), _length(before)])
	check(not _crosses_wall(nav, after), "new path crosses no wall")


func test_long_detour_prefers_bashing() -> void:
	var nav := _nav()
	var path := nav.find_path(Vector2(4.0, -2.0), Vector2(3.8, 2.7))
	check(_crosses_wall(nav, path), "outside north -> bedroom bashes through the north wall")
	var short := nav.find_path(Vector2(4.5, 11.0), Vector2(4.5, 7.9))
	check(not _crosses_wall(nav, short), "front lawn -> living room uses the front door")
