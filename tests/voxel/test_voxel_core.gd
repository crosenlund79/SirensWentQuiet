extends "res://tests/test_case.gd"
## Version A (voxel) modules: mesher, traversal, carving rules, house build
## versus the shared navigation raster, and GridNav synchronisation.


func _small_grid() -> VoxelGrid:
	return VoxelGrid.new(Vector3i(8, 8, 8), 0.1, Vector3.ZERO)


func _faces(a: Array) -> int:
	return 0 if a.is_empty() else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 4


func test_mesher_culls_hidden_faces() -> void:
	var g := _small_grid()
	g.set_voxel(3, 3, 3, VoxelMat.DRYWALL, 0xffffff)
	check_eq(_faces(VoxelMesher.build_arrays(g, Vector3i.ONE, Vector3i(7, 7, 7))), 6, "one voxel: 6 faces")
	g.set_voxel(4, 3, 3, VoxelMat.DRYWALL, 0xffffff)
	check_eq(_faces(VoxelMesher.build_arrays(g, Vector3i.ONE, Vector3i(7, 7, 7))), 10, "two neighbours share no faces")
	# Chunk borders: meshing two halves separately gives the same total.
	var left := _faces(VoxelMesher.build_arrays(g, Vector3i.ONE, Vector3i(4, 7, 7)))
	var right := _faces(VoxelMesher.build_arrays(g, Vector3i(4, 1, 1), Vector3i(7, 7, 7)))
	check_eq(left + right, 10, "faces across a chunk border are culled too")


func test_glass_is_a_separate_surface_and_does_not_hide_walls() -> void:
	var g := _small_grid()
	g.set_voxel(3, 3, 3, VoxelMat.DRYWALL, 0xffffff)
	g.set_voxel(4, 3, 3, VoxelMat.GLASS, 0x88aacc)
	check_eq(_faces(VoxelMesher.build_arrays(g, Vector3i.ONE, Vector3i(7, 7, 7))), 6, "wall keeps its face toward the glass")
	check_eq(_faces(VoxelMesher.build_arrays(g, Vector3i.ONE, Vector3i(7, 7, 7), true)), 5, "glass hides its face against the wall")


func test_ambient_occlusion_darkens_corners() -> void:
	var g := _small_grid()
	g.set_voxel(3, 2, 3, VoxelMat.FLOOR, 0xffffff)
	g.set_voxel(4, 2, 3, VoxelMat.FLOOR, 0xffffff)
	g.set_voxel(4, 3, 3, VoxelMat.DRYWALL, 0xffffff)   # a wall standing next to the floor voxel
	var a := VoxelMesher.build_arrays(g, Vector3i.ONE, Vector3i(7, 7, 7))
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = a[Mesh.ARRAY_COLOR]
	var lit := 0
	var dark := 0
	for i in verts.size():
		# top face of voxel (3,2,3): y = 0.3, x in [0.3, 0.4]
		if is_equal_approx(verts[i].y, 0.3) and verts[i].x < 0.41 and verts[i].z > 0.29 and verts[i].z < 0.41:
			if is_equal_approx(verts[i].x, 0.4):
				dark += 1 if cols[i].a < 1.0 else 0
			else:
				lit += 1 if is_equal_approx(cols[i].a, 1.0) else 0
	check(dark >= 2 and lit >= 2, "floor corners next to the wall get AO (dark %d, lit %d)" % [dark, lit])


func test_raycast_hits_first_solid_and_skips_pass_through() -> void:
	var g := _small_grid()
	g.set_voxel(5, 3, 3, VoxelMat.DRYWALL, 0)
	g.set_voxel(3, 3, 3, VoxelMat.FABRIC, 0)   # low furniture: bullets pass
	var skip := PackedByteArray()
	skip.resize(256)
	skip[VoxelMat.FABRIC] = 1
	var from := Vector3(0.15, 0.35, 0.35)
	var hit := g.raycast(from, Vector3.RIGHT, 5.0)
	check(not hit.is_empty() and hit["cell"] == Vector3i(3, 3, 3), "first solid along the ray")
	hit = g.raycast(from, Vector3.RIGHT, 5.0, skip)
	check(not hit.is_empty() and hit["cell"] == Vector3i(5, 3, 3), "pass-through material skipped")
	check(not hit.is_empty() and hit["normal"] == Vector3(-1, 0, 0), "entry face normal")
	check(is_equal_approx(hit.get("dist", 0.0), 0.35), "distance to the face (%s)" % hit.get("dist", -1.0))
	hit = g.raycast(from, Vector3.RIGHT, 5.0, skip, func(c: Vector3i) -> bool: return c.x == 5)
	check(hit.is_empty(), "cells can be skipped (cutaway)")


func test_carve_removes_a_ragged_ball_but_never_the_foundation() -> void:
	var g := VoxelGrid.new(Vector3i(20, 20, 20), 0.1, Vector3.ZERO)
	for y in range(1, 19):
		for z in range(1, 19):
			for x in range(1, 19):
				g.set_voxel(x, y, z, VoxelMat.FOUNDATION if y == 1 else VoxelMat.DRYWALL, 0xcccccc)
	var before := g.solid_count
	var ch := VoxelCarver.carve_sphere(g, Vector3(1.0, 1.0, 1.0), 0.3, 1)
	var removed := (ch["cells"] as PackedInt32Array).size()
	check(removed > 40 and removed < 260, "a ball of voxels went (%d)" % removed)
	check_eq(g.solid_count, before - removed, "solid count tracks removals")
	ch = VoxelCarver.carve_sphere(g, Vector3(1.0, 0.15, 1.0), 0.4, 2)
	var foundation_left := 0
	for z in range(1, 19):
		for x in range(1, 19):
			if g.get_mat(x, 1, z) == VoxelMat.FOUNDATION:
				foundation_left += 1
	check_eq(foundation_left, 18 * 18, "foundation row untouched")


func test_floating_fragments_fall_and_thin_strips_crumble() -> void:
	var g := VoxelGrid.new(Vector3i(20, 20, 20), 0.1, Vector3.ZERO)
	g.set_voxel(10, 10, 10, VoxelMat.DRYWALL, 0)
	g.set_voxel(10, 11, 10, VoxelMat.DRYWALL, 0)
	g.set_voxel(11, 10, 10, VoxelMat.DRYWALL, 0)
	var ch := VoxelCarver.remove_floating(g, PackedInt32Array([g.idx(9, 10, 10)]))
	check_eq((ch["cells"] as PackedInt32Array).size(), 3, "a fragment touching nothing falls")
	# A big connected slab stays.
	for z in range(1, 19):
		for x in range(1, 19):
			for y in range(1, 4):
				g.set_voxel(x, y, z, VoxelMat.SCREED, 0)
	g.set_voxel(10, 4, 10, VoxelMat.DRYWALL, 0)
	ch = VoxelCarver.remove_floating(g, PackedInt32Array([g.idx(10, 5, 10)]))
	check_eq((ch["cells"] as PackedInt32Array).size(), 0, "a stub standing on the slab is anchored")
	# A 1-voxel-tall strip spanning a gap breaks; a stud (vertical) stays.
	for x in range(2, 18):
		g.set_voxel(x, 10, 10, VoxelMat.SIDING, 0)
	for y in range(2, 15):
		g.set_voxel(5, y, 12, VoxelMat.STUD, 0)
	for y in range(15, 18):
		for x in range(2, 9):
			g.set_voxel(x, y, 12, VoxelMat.STUD, 0)   # top plate holds the stud
	ch = VoxelCarver.crumble_strips(g, Vector3i(1, 1, 1), Vector3i(19, 19, 19))
	check_eq(g.get_mat(9, 10, 10), VoxelMat.AIR, "thin horizontal strip crumbles")
	check_eq(g.get_mat(5, 10, 12), VoxelMat.STUD, "vertical stud stands")


func test_glass_pane_shatters_as_a_whole() -> void:
	var g := _small_grid()
	for x in range(2, 6):
		for y in range(2, 5):
			g.set_voxel(x, y, 3, VoxelMat.GLASS, 0)
	g.set_voxel(6, 3, 3, VoxelMat.FRAME, 0)
	var ch := VoxelCarver.shatter_glass(g, g.idx(3, 3, 3))
	check_eq((ch["cells"] as PackedInt32Array).size(), 12, "whole pane removed")
	check_eq(g.get_mat(6, 3, 3), VoxelMat.FRAME, "frame stays")


func test_house_volume_matches_navigation_raster() -> void:
	var g := VoxelHouse.create_grid()
	VoxelHouse.build(g)
	var nav := GridNav.new()
	HousePlan.rasterize_into(nav)
	var half := Vector2.ONE * GridNav.CELL * 0.5
	var doors := []
	for o in HousePlan.OPENINGS:
		if o["kind"] == "door":
			doors.append(HousePlan.span_rect(HousePlan.wall_by_id(o["wall"]), o["from"], o["to"]).grow(0.2))
	var wall_bad := 0
	var open_bad := 0
	for c in nav.cells_in_rect(HousePlan.FOOTPRINT.grow(0.5)):
		var p := nav.center_of(c)
		var has := g.any_struct_in(p - half, p + half, VoxelHouse.NAV_ROW_LO, VoxelHouse.NAV_ROW_HI)
		var raw := nav.get_raw(c)
		if raw == GridNav.WALL and not has:
			wall_bad += 1
		elif raw == GridNav.OPEN and has:
			var near_door := false
			for r in doors:
				near_door = near_door or (r as Rect2).has_point(p)
			if not near_door:
				open_bad += 1
	check_eq(wall_bad, 0, "every WALL cell has wall voxels")
	check_eq(open_bad, 0, "no wall voxels under OPEN cells (apart from door jambs)")
	check(g.solid_count > 80000, "a real volume (%d voxels)" % g.solid_count)


func test_sync_nav_opens_cells_only_when_columns_are_clear() -> void:
	var g := VoxelHouse.create_grid()
	VoxelHouse.build(g)
	var nav := GridNav.new()
	HousePlan.rasterize_into(nav)
	var cell := nav.cell_of(Vector2(8.5, 9.0))
	check_eq(nav.get_raw(cell), GridNav.WALL, "south wall cell starts as WALL")
	# Remove only the inner skin: still a wall.
	var lo := g.cell_of(Vector3(8.38, 0.0, 8.86))
	var hi := g.cell_of(Vector3(8.62, 2.0, 8.94)) + Vector3i.ONE
	for y in range(lo.y, hi.y):
		for x in range(lo.x, hi.x):
			g.set_voxel(x, y, lo.z, VoxelMat.AIR, 0)
	VoxelCarver.sync_nav(nav, g, lo, hi)
	check_eq(nav.get_raw(cell), GridNav.WALL, "partly eroded wall still blocks")
	# Remove the whole thickness of the cell's columns up to 1.6 m (keep 0-0.1 m).
	var rev := nav.revision
	lo = g.cell_of(Vector3(8.38, 0.1, 8.86))
	hi = g.cell_of(Vector3(8.62, 1.65, 9.14)) + Vector3i.ONE
	for y in range(lo.y, hi.y):
		for z in range(lo.z, hi.z):
			for x in range(lo.x, hi.x):
				g.set_voxel(x, y, z, VoxelMat.AIR, 0)
	VoxelCarver.sync_nav(nav, g, lo, hi)
	check_eq(nav.get_raw(cell), GridNav.OPEN, "cleared columns open the cell")
	check(nav.revision > rev, "pursuers are told to repath")
