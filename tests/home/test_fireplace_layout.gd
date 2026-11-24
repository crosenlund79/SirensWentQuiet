extends "res://tests/test_case.gd"
## Refinement 01: the fireplace no longer blocks the kitchen opening, bodies
## path around it, and construction can't wall it in.


func test_fireplace_leaves_the_kitchen_open_and_is_kept_clear() -> void:
	var w := HouseWorld.new()
	add(w)
	w.build_new()
	w.add_static_blocker(Fireplace.RECT, Fireplace.RESERVE)
	await physics_frames(1)
	var nav: GridNav = w.nav
	check(not nav.is_walkable(nav.cell_of(Fireplace.RECT.get_center())), "the fireplace is solid for navigation")
	for x in [8.4, 9.0, 9.6]:
		check(nav.is_walkable(nav.cell_of(Vector2(x, 4.0))), "the kitchen opening is walkable at x %.1f" % x)
	var path := nav.find_path(Vector2(5.0, 7.5), Vector2(11.0, 2.5))
	check(path.size() > 0, "a path from the living room into the kitchen")
	check(nav.find_path(Vector2(3.0, 7.5), Vector2(1.1, 5.6)).size() > 0, "the hearth can be reached")
	check(w.furniture_in(Rect2(1.0, 5.2, 0.4, 0.2)), "construction is refused right in front of the fire")
	check(not w.furniture_in(Rect2(9.0, 4.3, 0.4, 0.4)), "the old spot by the kitchen is free again")
	check(Fireplace.RECT.end.x < 2.0 and Fireplace.RECT.position.x > HousePlan.INTERIOR_THICKNESS, "west of the bedroom door, off the wall")
