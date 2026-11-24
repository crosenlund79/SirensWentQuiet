extends "res://tests/test_case.gd"
## Refinement 01 (S): nothing is left floating after a demolition (issue 3),
## and the roof and the upper floor need their outer walls (issue 4):
## inner walls can all go, a whole outer side over a room brings that room's
## roof down, the upper floor over it falls with it, the build preview
## warns, and the collapsed state is saved.

const SCENE := "res://src/game/game.tscn"
const SAVE := "user://test_structure_support.dat"


func _world() -> HouseWorld:
	var w := HouseWorld.new()
	add(w)
	w.build_new()
	await physics_frames(2)
	return w


func _floating(w: HouseWorld, area: Rect2) -> int:
	var g := w.grid
	var xr := g.centre_range(0, area.position.x, area.end.x)
	var zr := g.centre_range(2, area.position.y, area.end.y)
	return VoxelSupport.unsupported(g, Vector3i(xr.x, 0, zr.x), Vector3i(xr.y, g.sy, zr.y)).size()


func _cut_wall(w: HouseWorld, id: String) -> void:
	var wd := HousePlan.wall_by_id(id)
	var horiz := HousePlan.is_horizontal(wd)
	var a: Vector2 = wd["a"]
	var b: Vector2 = wd["b"]
	var lo := int(minf(a.x, b.x)) if horiz else int(minf(a.y, b.y))
	var hi := int(maxf(a.x, b.x)) if horiz else int(maxf(a.y, b.y))
	for s in range(lo, hi):
		w.cut_opening(Vector3i(0 if horiz else 1, int(a.y) if horiz else int(a.x), s), true)


func test_bathroom_window_leaves_nothing_floating() -> void:
	var w: HouseWorld = await _world()
	var area := Rect2(3.5, -0.6, 6.0, 1.4)
	check_eq(_floating(w, area), 0, "the pristine house has nothing floating")
	w.cut_opening(Vector3i(0, 0, 5), true)
	w.cut_opening(Vector3i(0, 0, 7), true)
	check_eq(_floating(w, area), 0, "the walls beside the bathroom window are gone; the window pillar stands on the floor")
	w.cut_opening(Vector3i(0, 0, 6), true)
	check(w.settled > 0, "knocking out the window dropped its inner sill (%d voxels)" % w.settled)
	check_eq(_floating(w, area), 0, "nothing hangs in the air")
	var c := w.grid.cell_of(Vector3(6.5, 1.35, 0.2))
	check_eq(w.grid.get_mat(c.x, c.y, c.z), VoxelMat.AIR, "the inner sill is gone")
	check_eq(w.design.get_mat(c.x, c.y, c.z), VoxelMat.AIR, "from the design too (repair can't hang it back)")
	w.process_structure()
	check(w.support.roof_gone.has("bathroom"), "three metres of the bathroom's outer wall gone: its roof came down")


func test_lintel_door_and_fuse_box_fall_with_their_wall() -> void:
	var w: HouseWorld = await _world()
	var door: WorldObject = null
	for o in w.objects:
		if o.kind == "door" and o.seg == Vector3i(1, 14, 6):
			door = o
	check(door != null and w.is_mounted(door), "the back door hangs in its doorway")
	check(w.is_mounted(w.fuse_box()), "the fuse box hangs on the east wall")
	var gone := []
	w.object_destroyed.connect(func(kind: String, _at: Vector3) -> void: gone.append(kind))
	w.cut_opening(Vector3i(1, 14, 5), true)
	check(w.objects.has(door), "one jamb left: the door still hangs")
	w.cut_opening(Vector3i(1, 14, 7), true)
	var c := w.grid.cell_of(Vector3(14.0, 2.4, 6.5))
	check_eq(w.grid.get_mat(c.x, c.y, c.z), VoxelMat.AIR, "the lintel over the doorway fell")
	check(not w.objects.has(door), "the door fell with its wall")
	check_eq(_floating(w, Rect2(13.0, 4.0, 2.0, 5.5)), 0, "nothing hangs in the air")
	w.cut_opening(Vector3i(1, 14, 8), true)
	check(w.fuse_box() == null, "the fuse box fell with its wall")
	check(gone.has("door") and gone.has("fuse_box"), "object_destroyed told the game (%s)" % str(gone))
	check(not w.wall_at(Vector2(14.0, 8.5), 1.1), "no wall there for a switch")
	check(w.wall_at(Vector2(14.0, 3.5), 1.1), "the kitchen's east wall still stands")


func test_inner_walls_carry_nothing() -> void:
	var w: HouseWorld = await _world()
	for id in ["bed_bath", "bath_kitchen", "living_utility", "mid_west", "mid_east"]:
		_cut_wall(w, id)
	w.process_structure()
	check_eq(w.support.collapses, 0, "no collapse")
	check(w.support.roof_gone.is_empty(), "the whole roof stands")
	check_eq(_floating(w, HousePlan.FOOTPRINT.grow(0.5)), 0, "nothing floats")
	check_eq(w.bearing_warning(Vector3i(1, 10, 5)), "", "an inner wall carries nothing (no build warning)")


func test_an_outer_side_over_a_room_brings_its_roof_down() -> void:
	var w: HouseWorld = await _world()
	var events := []
	w.support.collapsed.connect(func(info: Dictionary) -> void: events.append(info))
	var strains := []
	w.support.strained.connect(func(info: Dictionary) -> void: strains.append(info))
	check(w.bearing_warning(Vector3i(0, 0, 9)).begins_with("Load-bearing wall"), "an outer wall section is load-bearing")
	w.cut_opening(Vector3i(0, 0, 8), true)
	w.process_structure()
	w.cut_opening(Vector3i(0, 0, 9), true)
	w.process_structure()
	check_eq(strains.size(), 1, "two metres gone: a strain warning for the kitchen")
	var warn := w.bearing_warning(Vector3i(0, 0, 10))
	check(warn.contains("kitchen") and warn.contains("come down"), "the demolish preview warns (%s)" % warn)
	check(w.support.roof_gone.is_empty(), "the roof still stands")
	for k in range(10, 14):
		w.cut_opening(Vector3i(0, 0, k), true)
	w.process_structure()
	check(w.support.roof_gone.has("kitchen"), "the kitchen's roof came down")
	check_eq(w.support.roof_gone.size(), 1, "only the kitchen's")
	check(events.size() == 1 and events[0]["text"] == "The roof over the kitchen gave way!", "one collapse event (%s)" % str(events))
	check(not w.yard.roof_covers(Vector2(11.0, 2.0)) and w.yard.roof_covers(Vector2(2.0, 2.0)), "the roof has a hole over the kitchen only")
	check(not w.ceiling_at(Vector2(11.0, 2.0)) and w.ceiling_at(Vector2(11.0, 6.0)), "the kitchen's ceiling light has nothing to hang on")
	w.process_structure()
	check_eq(events.size(), 1, "a collapse happens once")


func test_a_built_wall_props_the_roof() -> void:
	var w: HouseWorld = await _world()
	w.build_walls([Vector3i(0, 1, 0), Vector3i(0, 1, 1), Vector3i(0, 1, 2), Vector3i(0, 1, 3), Vector3i(0, 1, 4)], "wood")
	for k in range(0, 5):
		w.cut_opening(Vector3i(0, 0, k), true)
	w.process_structure()
	check(not w.support.roof_gone.has("bedroom"), "a wall run 1 m inside props the bedroom's roof")
	check(w.bearing_warning(Vector3i(0, 1, 2)).begins_with("Load-bearing"), "the prop is load-bearing")
	for k in range(1, 4):
		w.demolish_wall(Vector3i(0, 1, k))
	w.process_structure()
	check(w.support.roof_gone.has("bedroom"), "taking the prop away brings it down")


func test_upper_floor_falls_with_the_walls_under_it() -> void:
	var w: HouseWorld = await _world()
	var u := LevelWorld.new()
	u.configure(Levels.UPPER, null)
	add(u)
	u.build_new()
	await physics_frames(1)
	w.support.set_upper(u)
	u.place_object("crate", Vector2(11.0, 2.0), 0)
	check(u.has_floor_at(Vector2(11.0, 2.0)), "the upper floor has a deck over the kitchen")
	for k in range(8, 14):
		w.cut_opening(Vector3i(0, 0, k), true)
	w.process_structure()
	check(not u.has_floor_at(Vector2(11.0, 2.0)), "the deck over the kitchen came down")
	check(u.has_floor_at(Vector2(2.0, 2.0)) and u.has_floor_at(Vector2(11.0, 6.0)), "the rest of the upper floor stands")
	check(not HouseSupport.section_bears(u, Vector3i(0, 0, 10)), "the upper wall over the kitchen fell with it")
	check(u.count_objects("crate") == 0, "the crate up there fell")
	check(w.support.roof_gone.has("kitchen"), "and the roof over it")
	check_eq(_floating(u, Rect2(7.0, -0.5, 7.5, 5.0)), 0, "nothing of the upper floor hangs in the air")
	# the upper storey's own outer walls carry the roof
	for k in range(0, 5):
		u.cut_opening(Vector3i(0, 0, k), true)
	w.process_structure()
	check(w.support.roof_gone.has("bedroom"), "the roof over the bedroom fell when the upper walls under it went")
	check(u.has_floor_at(Vector2(2.0, 2.0)), "the upper floor over the bedroom still stands on the ground walls")


func test_collapsed_roof_is_saved() -> void:
	var w: HouseWorld = await _world()
	for k in range(0, 5):
		w.cut_opening(Vector3i(0, 0, k), true)
	w.process_structure()
	var d := w.save_data()
	check_eq(d.get("collapsed"), ["bedroom"], "the save lists the collapsed zone")
	var w2 := HouseWorld.new()
	add(w2)
	check(w2.load_data(d.duplicate(true)), "the save loads")
	await physics_frames(1)
	check(w2.support.roof_gone.has("bedroom"), "the bedroom's roof is still gone")
	check(not w2.yard.roof_covers(Vector2(2.0, 2.0)), "the roof mesh has the hole")
	d.erase("collapsed")
	var w3 := HouseWorld.new()
	add(w3)
	check(w3.load_data(d), "an older save without the field loads")
	await physics_frames(1)
	check(w3.support.roof_gone.is_empty(), "with the whole roof standing")


# --- the real game ---------------------------------------------------------------------

func test_collapse_in_the_game() -> void:
	SaveGame.path_override = SAVE
	GameLaunch.mode = "new"
	GameLaunch.seed = 101
	var g: Node = (load(SCENE) as PackedScene).instantiate()
	g.stay_in_scene = true
	g.skip_intro = true
	g.fade_time = 0.02
	g.aim_with_mouse = false
	add(g)
	tree.current_scene = g
	await frames(3)
	var w: HouseWorld = g.debug_world()
	g.debug_teleport_player(Vector2(9.5, 1.5))
	var h0: float = g.state.health
	var m: DevMenu = g.debug_ui().dev_menu
	m.toggle()
	await frames(2)
	check(m.button("Show support") != null and m.button("Collapse test") != null, "the F10 Structure section is there")
	m.button("Collapse test").pressed.emit()
	await frames(3)
	check(w.support.roof_gone.has("kitchen"), "the collapse test brought the kitchen's roof down")
	check(g.last_toast.begins_with("The roof over the kitchen gave way!"), "the player is told (%s)" % g.last_toast)
	check(g.state.health < h0, "the player under it was hurt (%.0f -> %.0f)" % [h0, g.state.health])
	check(not g.home.fixtures["kitchen_ceiling"].visible, "the kitchen's ceiling light fell")
	m.button("Show support").pressed.emit()
	check(m.last_status.contains("kitchen: roof gone"), "Show support lists the zones (%s)" % m.last_status)
	m.toggle()
	tree.paused = false
	SaveGame.delete_save()
	SaveGame.path_override = ""
	GameLaunch.mode = "new"
	GameLaunch.seed = 0
