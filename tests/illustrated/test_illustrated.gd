extends "res://tests/test_case.gd"
## Module tests for Version C (illustrated 2D): art manifest, wall layout,
## destruction contract (collision + nav in the same frame), windows, bashing.

const Art := preload("res://src/illustrated/ill_art.gd")
const Walls := preload("res://src/illustrated/walls.gd")
const HouseView := preload("res://src/illustrated/house_view.gd")


func _walls() -> Array:
	var nav := GridNav.new()
	HousePlan.rasterize_into(nav)
	var shadows := Node2D.new()
	add(shadows)
	var w: Walls = Walls.new()
	add(w)
	w.build(nav, shadows)
	return [w, nav]


func test_every_manifest_texture_resolves() -> void:
	var n := 0
	for group in Art.MANIFEST:
		for name in Art.MANIFEST[group]:
			n += 1
			check(Art.tex(name) != null, "illustrated/%s resolves to a texture" % name)
	check(n > 60, "manifest lists the art (%d names)" % n)


func test_furniture_art_names_are_in_the_manifest() -> void:
	var known := []
	for group in Art.MANIFEST:
		known.append_array(Art.MANIFEST[group])
	for f in HousePlan.FURNITURE + HousePlan.PROPS:
		if HouseView.GROUND_PROPS.has(f["type"]):
			continue
		check(HouseView.art_name(f) in known, "%s has art in the manifest" % f["id"])


func test_sections_and_posts_cover_every_wall() -> void:
	var r := _walls()
	var w: Walls = r[0]
	check(w.sections.size() > 50, "house split into sections (%d)" % w.sections.size())
	for wall in HousePlan.WALLS:
		var horiz := HousePlan.is_horizontal(wall)
		var lo: float = minf(wall["a"].x, wall["b"].x) if horiz else minf(wall["a"].y, wall["b"].y)
		var hi: float = maxf(wall["a"].x, wall["b"].x) if horiz else maxf(wall["a"].y, wall["b"].y)
		var covered := 0.0
		for s in w.sections:
			if s.wall["id"] == wall["id"]:
				covered += s.to_m - s.from_m
				check(s.to_m - s.from_m <= 1.05, "%s is about 1 m or less" % s.name)
		for o in HousePlan.openings_on(wall["id"]):
			if o["kind"] == "door":
				covered += o["to"] - o["from"]
		for p in w.posts:
			if Walls._on_wall(wall, p.get_center()):
				var a: float = (p.position.x if horiz else p.position.y)
				var b: float = (p.end.x if horiz else p.end.y)
				covered += minf(b, hi) - maxf(a, lo)
		check(absf(covered - (hi - lo)) < 0.01, "%s fully covered by sections, doors and posts (%.2f of %.2f)" % [wall["id"], covered, hi - lo])


func test_destroying_a_section_opens_collision_and_nav_at_once() -> void:
	var r := _walls()
	var w: Walls = r[0]
	var nav: GridNav = r[1]
	var s = null
	for x in w.sections:
		if x.wall["id"] == "south" and x.from_m <= 8.5 and x.to_m >= 8.5:
			s = x
	check(s != null, "found the south section at x 8.5")
	if s == null:
		return
	var c := nav.cell_of(Vector2(8.5, 9.0))
	check(nav.get_raw(c) == GridNav.WALL, "nav cell starts as WALL")
	var hits := 0
	while not s.removed and hits < 50:
		s.hit(s.center(), 1, Vector2.DOWN)
		hits += 1
	check(s.removed, "section removed after %d hits" % hits)
	check(hits == s.max_hp, "takes exactly its HP in hits (%d, hp %d)" % [hits, s.max_hp])
	check(hits >= 8 and hits <= 11, "about Tuning.WALL_SECTION_HP hits for ~1 m (%d)" % hits)
	check(s.collision_layer == 0, "collision layer cleared in the same frame")
	check(nav.get_raw(c) == GridNav.OPEN, "nav cell OPEN in the same frame")
	check(nav.is_walkable(c), "cell walkable once a ~1 m section is gone")
	var torn := false
	for nb in s.neighbours:
		if nb != null and not nb.removed:
			torn = true
	check(torn, "a neighbour section remains to show the torn edge")


func test_window_glass_breaks_before_the_frame() -> void:
	var r := _walls()
	var w: Walls = r[0]
	var win = null
	for x in w.sections:
		if x.kind == "window":
			win = x
			break
	check(win != null, "has window sections")
	if win == null:
		return
	check_eq(win.hit(win.center(), 1, Vector2.DOWN), "glass", "first hit cracks the glass")
	check_eq(win.glass, 1, "glass cracked")
	check_eq(win.hit(win.center(), 1, Vector2.DOWN), "glass", "second hit shatters it")
	check_eq(win.glass, 2, "glass shattered")
	check_eq(win.hp, win.max_hp, "glass hits do not damage the frame")
	win.hit(win.center(), 1, Vector2.DOWN)
	check_eq(win.hp, win.max_hp - 1, "then the window takes damage like a wall")


func test_enemy_bash_damages_the_nearest_standing_section() -> void:
	var r := _walls()
	var w: Walls = r[0]
	var target := Vector2(12.5, 9.0)
	var before := 0
	var s = null
	for x in w.sections:
		if x.wall["id"] == "south" and x.from_m <= 11.5 and x.to_m >= 11.5:
			s = x
			before = x.hp
	var mat := w.bash_at(Vector2(11.5, 9.0), 1, Vector2.UP)
	check(mat != "none", "a bash lands on a wall (%s)" % mat)
	check(s != null and s.hp == before - 1, "the section at the swing point lost 1 HP")
	check_eq(w.bash_at(Vector2(4.5, 9.0) + Vector2(0, 3.0), 1, Vector2.UP), "none", "no wall far from the walls")
	check(target.x > 0.0, "sanity")
