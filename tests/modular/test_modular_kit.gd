extends "res://tests/test_case.gd"
## Version B (modular kit) module and integration tests.
##   godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd -- --filter=modular

const SCENE := "res://src/modular/modular_demo.tscn"


func _demo() -> Node:
	var v: Node = (load(SCENE) as PackedScene).instantiate()
	add(v)
	tree.current_scene = v
	await frames(3)
	v.debug_set_spawning(false)
	return v


func _solid_module(exterior := true) -> ModWall:
	var m := ModWall.new()
	m.kind = ModWall.Kind.SOLID
	m.exterior = exterior
	m.outside = 0 if exterior else -1
	m.thickness = HousePlan.EXTERIOR_THICKNESS if exterior else HousePlan.INTERIOR_THICKNESS
	m.seed = 7
	add(m)
	return m


## The kit covers every wall exactly once: modules + posts, no gaps, no overlaps.
func test_house_is_assembled_from_the_plan_on_the_grid() -> void:
	var v := await _demo()
	var house: ModHouse = v.house
	var total_len := 0.0
	for w in HousePlan.WALLS:
		total_len += (w["b"] as Vector2).distance_to(w["a"])
	check_eq(house.walls.size(), int(total_len), "one module per meter of wall")
	check_eq(house.posts.size(), 12, "posts at wall ends and T-junctions")
	var bad := 0
	for w in HousePlan.WALLS:
		var a: Vector2 = w["a"]
		var b: Vector2 = w["b"]
		var n := int(a.distance_to(b) / 0.05)
		for k in range(n):
			var p := a.lerp(b, (k + 0.5) / n)
			var hits := 0
			for m in house.walls:
				if m.plan_rect.grow(-0.001).has_point(p):
					hits += 1
			for post in house.posts:
				if Rect2(post.plan_pos - Vector2.ONE * post.size * 0.5, Vector2.ONE * post.size).grow(0.001).has_point(p):
					hits += 1
			if hits != 1:
				bad += 1
	check_eq(bad, 0, "every wall centre-line point lies in exactly one kit piece")
	for m in house.walls:
		check(m.length > 0.6 and m.length <= 1.0001, "module length within the 1 m grid (%s %.2f)" % [m.name, m.length])


func test_wall_module_damage_states() -> void:
	var m := _solid_module()
	await frames(1)
	var states := []
	for k in Tuning.WALL_SECTION_HP:
		m.take_hit(Vector3(0.5, 1.0, m.thickness * 0.5), 1, true)
		states.append(m.state)
	check_eq(states[1], ModWall.State.INTACT, "two hits: still intact (holes only)")
	check_eq(states[2], ModWall.State.DAMAGED, "third hit: damaged")
	check_eq(states[6], ModWall.State.HEAVY, "seventh hit: heavily damaged")
	check_eq(states[9], ModWall.State.DESTROYED, "tenth hit (WALL_SECTION_HP): destroyed")
	check_eq(m.collision_layer, 0, "destroyed module leaves the walls layer")
	var any_enabled := false
	for c in m.get_children():
		if c is CollisionShape3D and not c.disabled:
			any_enabled = true
	check(not any_enabled, "destroyed module has no active collision shapes")


func test_window_glass_breaks_before_the_frame_takes_damage() -> void:
	var m := ModWall.new()
	m.kind = ModWall.Kind.WINDOW
	m.exterior = true
	m.outside = 0
	add(m)
	await frames(1)
	var in_glass := Vector3(0.5, 1.5, 0.0)
	check_eq(m.take_hit(in_glass, 1, true), "glass", "first hit cracks the glass")
	check_eq(m.take_hit(in_glass, 1, true), "glass_shatter", "second hit shatters it")
	check_eq(m.hp, Tuning.WALL_SECTION_HP, "glass hits do not wear the frame")
	check(not m.is_glass_intact(), "glass gone")
	m.take_hit(Vector3(0.5, 0.5, m.thickness * 0.5), 1, true)
	check_eq(m.hp, Tuning.WALL_SECTION_HP - 1, "then the sill wall takes damage")


func test_doorways_are_not_destructible() -> void:
	var m := ModWall.new()
	m.kind = ModWall.Kind.DOOR
	m.door_style = "interior"
	add(m)
	await frames(1)
	for k in 20:
		m.take_hit(Vector3(0.5, 2.3, 0.1), 1, true)
	check_eq(m.state, ModWall.State.INTACT, "door module keeps its header")


## Destroying a module opens exactly its footprint: nav OPEN, collision gone,
## while the neighbouring post stays solid and blocked.
func test_destroyed_module_updates_nav_and_collision() -> void:
	var v := await _demo()
	var house: ModHouse = v.house
	var nav: GridNav = v.debug_nav()
	var m: ModWall = house.wall_near(Vector2(9.5, 9.0), 0.1)   # south wall, next to the post at x = 10
	check(m != null, "found the module")
	var mid := m.plan_rect.get_center()
	check(v.debug_blocked_at(mid), "blocked before")
	m.set_state(ModWall.State.DESTROYED)
	for c in nav.cells_in_rect(m.plan_rect):
		check_eq(nav.get_raw(c), GridNav.OPEN, "footprint cell %s open" % c)
	check(nav.is_walkable(nav.cell_of(Vector2(9.25, 9.0))), "walkable inside the breach")
	check(not v.debug_blocked_at(mid), "collision removed in the same frame")
	check_eq(nav.get_raw(nav.cell_of(Vector2(10.0, 9.0))), GridNav.WALL, "post cell stays WALL")
	check(v.debug_blocked_at(Vector2(10.0, 9.0)), "post still collides")


## Cutaway: modules between camera and player are lowered, and the aim ray
## treats their hidden upper part as see-through.
func test_cutaway_lowers_modules_in_front_of_the_player() -> void:
	var v := await _demo()
	var house: ModHouse = v.house
	house.instant = true
	v.debug_teleport_player(Vector2(8.5, 7.6))
	await frames(3)
	var front: ModWall = house.wall_near(Vector2(8.5, 9.0), 0.1)
	var back: ModWall = house.wall_near(Vector2(11.5, 0.0), 0.1)
	check(front.cut < 2.0, "south wall in front of the player is cut (%.2f)" % front.cut)
	check(back.cut > 50.0, "north wall behind the player is full height")
	check(house.is_hidden(front, front.to_global(Vector3(0.5, 2.0, 0.15))), "upper part of a cut module is hidden for aiming")
	check(not house.is_hidden(front, front.to_global(Vector3(0.5, 0.5, 0.15))), "lower part still solid")
	check(house.roof.fade > 0.99, "roof hidden while inside")
	var top_world := front.to_global(Vector3(0.5, 0.0, 0.0))
	var from := top_world + Vector3(0, 10, 6)
	var top: Variant = house.cut_top_hit(front, from, (Vector3(top_world.x, front.cut, top_world.z) - from).normalized())
	check(top != null and absf((top as Vector3).y - front.cut) < 0.01, "aiming at a cut module lands on its visible top")


func test_enemy_wall_swing_damages_the_nearest_module() -> void:
	var v := await _demo()
	var house: ModHouse = v.house
	var e: ModEnemy = v.debug_spawn_enemy(Vector2(2.0, 10.0))
	var m: ModWall = house.wall_near(Vector2(0.5, 9.0), 0.1)
	var before := m.hp
	v._on_enemy_swung(e, "wall", Vector2(0.5, 9.0))
	check_eq(m.hp, before - Tuning.ENEMY_WALL_DAMAGE, "the swing damaged the module at the target")
