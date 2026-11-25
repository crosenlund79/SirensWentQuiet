class_name LevelWorld
extends HouseWorld
## Experiment 004 (owner L): an extra storey of the house, the upper floor or
## the basement, as its own HouseWorld so the existing construction, damage,
## repair, demolition, objects (doors, crates, workbench...) and navigation
## code work on it unchanged; BuildMode simply targets it while the player is
## on it.
##
## The node stays at the origin; its voxel grid sits at the storey's height
## (`origin.y` = base_y - 0.4, the ground grid's row layout), so voxels, rays,
## carving and the surface shader are in world space as on the ground floor.
## The grid covers the house footprint plus a 0.75 m margin. What differs from
## the ground floor is overridden here: the pristine design (an empty deck with
## outer walls and windows upstairs; solid earth under the house downstairs),
## no yard, furniture, bed or lights, object heights, the cutaway floor, body
## queries at the storey's height, navigation (no floor or undug earth is
## SOLID), the exit rule (always satisfied) and the save (a diff against the
## storey's own pristine grid, with the dug cells).

const LEVEL_SAVE_VERSION := 1
const LEVEL_LAYOUT := "swq-levels-1"
const ORIGIN_XZ := Vector2(-0.85, -0.85)
const SIZE := Vector3i(157, 31, 107)       ## 0.75 m around the footprint, plus the empty edge layer
const DECK := Rect2(-0.15, -0.15, 14.3, 9.3)
## Upper floor windows: outer wall segments (axis, line, start) glazed 0.9-2.0 m.
const UPPER_WINDOWS := [
	Vector3i(0, 0, 2), Vector3i(0, 0, 6), Vector3i(0, 0, 11), Vector3i(0, 9, 2), Vector3i(0, 9, 7), Vector3i(0, 9, 11),
	Vector3i(1, 0, 3), Vector3i(1, 0, 6), Vector3i(1, 14, 2), Vector3i(1, 14, 6),
]
const EARTH_TONES := [0x4f3f31, 0x56463a, 0x4a3b2e, 0x5c4b3c, 0x524234, 0x47382c, 0x5a4838, 0x4d3e30]
const DUG_FLOOR := 0x6a5e50
const SIDING_TONE := 0x8d8a80
const GYPSUM_TONE := 0xcfc8bb

static var _level_pristine := {}

var storey := Levels.UPPER
var base_y := Levels.HEIGHT
var dug := {}                  ## basement: Vector2i plan cell -> true


## Call before adding to the tree.
func configure(s: int, light: VoxelLighting) -> void:
	storey = s
	base_y = Levels.base_y(s)
	lighting = light
	name = "Level_%s" % ("Basement" if s == Levels.BASEMENT else "Upper")


static func create_grid(s: int) -> VoxelGrid:
	var g := VoxelGrid.new(SIZE, VoxelHouse.VS, Vector3(ORIGIN_XZ.x, VoxelHouse.LOT_ORIGIN.y + Levels.base_y(s), ORIGIN_XZ.y))
	g.cap_row = VoxelHouse.TOP_ROW
	g.cap_color = 0x2f271f if s == Levels.BASEMENT else VoxelArt.pal(VoxelArt.Slot.CAP)
	return g


## The storey as first built: the upper floor's deck and outer walls, or the
## basement's solid earth (cached; saves are diffs against it).
static func level_pristine(s: int) -> VoxelGrid:
	if not _level_pristine.has(s):
		var g := create_grid(s)
		if s == Levels.BASEMENT:
			_fill_earth(g)
		else:
			_build_deck(g)
			for w in _perimeter_lines():
				_stamp_outer_wall(g, w)
		_level_pristine[s] = g
	return _level_pristine[s]


func layout_id() -> String:
	return "%s|%d" % [LEVEL_LAYOUT, storey]


func build_new() -> void:
	var p := level_pristine(storey)
	_build_level(p.copy(), p.copy(), [], [], [], [], [], [], [])


# --- pristine designs ------------------------------------------------------------------

static func _fill_earth(g: VoxelGrid) -> void:
	var n := 0
	for y in range(VoxelHouse.FOUNDATION_ROW, VoxelHouse.TOP_ROW + 1):
		for z in range(1, g.sz - 1):
			var base := (y * g.sz + z) * g.sx
			for x in range(1, g.sx - 1):
				var i := base + x
				var c: int = EARTH_TONES[(x * 7 + y * 13 + z * 31 + (x * z) % 5) & 7]
				g.mat[i] = VoxelMat.EARTH
				g.col[i] = c
				g.pcol[i] = c
				n += 1
	g.solid_count += n


static func _build_deck(g: VoxelGrid) -> void:
	var xr := g.centre_range(0, DECK.position.x, DECK.end.x)
	var zr := g.centre_range(2, DECK.position.y, DECK.end.y)
	var screed := VoxelArt.pal(VoxelArt.Slot.SCREED)
	for z in range(zr.x, zr.y):
		for x in range(xr.x, xr.y):
			var j := VoxelArt.jitter(0x5a4632, x, 1, z, 0.06)
			g.set_voxel(x, VoxelHouse.FOUNDATION_ROW, z, VoxelMat.SCREED, j, j)
			var s := VoxelArt.jitter(screed, x, 2, z, 0.05)
			g.set_voxel(x, VoxelHouse.SCREED_ROW, z, VoxelMat.SCREED, s, s)
			var top := VoxelArt.sample("floor_wood", x, z)
			g.set_voxel(x, VoxelHouse.FLOOR_ROW, z, VoxelMat.FLOOR, VoxelArt.scale(top, 0.72), top, VoxelHouse.UP_BIT)


## The four outer wall lines: {"axis", "line", "from", "to"} (plan metres).
static func _perimeter_lines() -> Array:
	var f := HousePlan.FOOTPRINT
	return [
		{"axis": 0, "line": int(f.position.y), "from": f.position.x, "to": f.end.x},
		{"axis": 0, "line": int(f.end.y), "from": f.position.x, "to": f.end.x},
		{"axis": 1, "line": int(f.position.x), "from": f.position.y, "to": f.end.y},
		{"axis": 1, "line": int(f.end.x), "from": f.position.y, "to": f.end.y},
	]


static func perimeter_segments() -> Array:
	var out := []
	for w in _perimeter_lines():
		for s in range(int(w["from"]), int(w["to"])):
			out.append(Vector3i(w["axis"], w["line"], s))
	return out


## Two voxels thick (0.2 m) on the line, full height, 0.1 m past each end so
## corners close: weathered siding outside, gypsum inside, glazed windows.
static func _stamp_outer_wall(g: VoxelGrid, w: Dictionary) -> void:
	var horiz: bool = w["axis"] == 0
	var line := float(w["line"])
	var rect := Rect2(w["from"] - 0.1, line - 0.1, w["to"] - w["from"] + 0.2, 0.2) if horiz \
		else Rect2(line - 0.1, w["from"] - 0.1, 0.2, w["to"] - w["from"] + 0.2)
	var xr := g.centre_range(0, rect.position.x, rect.end.x)
	var zr := g.centre_range(2, rect.position.y, rect.end.y)
	var mid := HousePlan.FOOTPRINT.get_center()
	for z in range(zr.x, zr.y):
		for x in range(xr.x, xr.y):
			var p := VoxelHouse.column_plan(g, x, z)
			# voxel centres sit on multiples of 0.1 m: the wall's two are line - 0.1 and line
			var outer := (p.y - line + 0.05) * (line - mid.y) > 0.0 if horiz else (p.x - line + 0.05) * (line - mid.x) > 0.0
			var along := p.x if horiz else p.y
			var seg := Vector3i(0 if horiz else 1, int(line), floori(along))
			var glazed := UPPER_WINDOWS.has(seg)
			var u := along - floorf(along)
			for r in VoxelHouse.WALL_ROWS:
				var y := VoxelHouse.BASE_ROW + r
				if glazed and r >= 8 and r <= 20 and u > 0.1 and u < 0.9:
					if r == 8 or r == 20 or u < 0.2 or u > 0.8:
						var fc := VoxelArt.pal(VoxelArt.Slot.FRAME)
						g.set_voxel(x, y, z, VoxelMat.FRAME, fc, fc)
					else:
						var gc := VoxelArt.pal(VoxelArt.Slot.GLASS)
						g.set_voxel(x, y, z, VoxelMat.GLASS, gc, gc)
					continue
				if outer:
					var board := VoxelArt.scale(VoxelArt.jitter(SIDING_TONE, x, r / 2, z, 0.05), 0.88 if r % 2 == 0 else 1.0)
					g.set_voxel(x, y, z, VoxelMat.SIDING, board, board)
				else:
					var gy := VoxelArt.jitter(GYPSUM_TONE, x, y, z, 0.02)
					g.set_voxel(x, y, z, VoxelMat.DRYWALL, gy, gy)


# --- building the scene ----------------------------------------------------------------

func _build_level(g_design: VoxelGrid, g_cur: VoxelGrid, objs: Array, built_list: Array, upgraded_list: Array,
		cut_list: Array, stone_list: Array, foundation_list: Array, dug_list: Array) -> void:
	var t0 := Time.get_ticks_usec()
	design = g_design
	grid = g_cur
	surface_mat = _surface_material(grid.origin, grid.vs)
	glass_mat = ShaderMaterial.new()
	glass_mat.shader = GLASS_SHADER
	cut_materials.append(glass_mat)
	if lighting != null:
		lighting.night_materials.append(glass_mat)
	chunks = VoxelWorld.new()
	chunks.name = "VoxelWorld"
	chunks.setup(grid, surface_mat, glass_mat)
	add_child(chunks)
	chunks.build_all()
	nav = GridNav.new()
	_static_solid.resize(nav.size.x * nav.size.y)
	_static_solid.fill(0)
	_house_zone = HousePlan.FOOTPRINT.grow(0.5)
	for e in dug_list:
		dug[e] = true
	for e in foundation_list:
		foundations[Vector3i(int(e[0]), int(e[1]), int(e[2]))] = true
	fx = VoxelFx.new()
	fx.grid = grid
	fx.debris_scale = 1.0 + 0.45 * (damage_quantum - 1)
	add_child(fx)
	if storey == Levels.UPPER:
		for s in perimeter_segments():
			sections[s] = _new_section(true, "frame")
	var stone := {}
	for e in stone_list:
		stone[Vector3i(int(e[0]), int(e[1]), int(e[2]))] = true
	for e in built_list:
		var s := Vector3i(int(e[0]), int(e[1]), int(e[2]))
		built[s] = true
		if not sections.has(s) or sections[s]["orig"]:      # Refinement 01: a wall built where a house wall was knocked out
			sections[s] = _new_section(false, "stone" if stone.has(s) else "wood")
		_mark_struct_zone(s)
	for e in upgraded_list:
		upgraded[Vector3i(int(e[0]), int(e[1]), int(e[2]))] = true
	for e in cut_list:
		openings.append({"axis": int(e[0]), "line": int(e[1]), "from": float(e[2]), "to": float(e[3]), "orig": false})
	_index_openings()
	for e in objs:
		var o := _spawn_object(e["kind"], Vector2(e["x"], e["y"]), e["rot"], e.get("built", true), e["hp"], e["open"], e.get("mat", "wood"))
		o.apply_extra(e)        # Exp 005 (F): furniture contents, id, size, lamp switch
	_index_objects()
	_full_nav()
	for s in sections:
		_count_section(s)
	_scar_root = Node3D.new()
	_scar_root.name = "Scars"
	add_child(_scar_root)
	stats["build_ms"] = (Time.get_ticks_usec() - t0) / 1000.0


func _spawn_object(kind: String, p: Vector2, rot: int, is_built: bool, hp := -1, is_open := false, mat := "wood") -> WorldObject:
	var o := super(kind, p, rot, is_built, hp, is_open, mat)
	o.position.y = base_y
	return o


func _add_scar(_x: float, _z: float, _r: float) -> void:
	pass                       # scorch marks are a yard-ground decal


# --- persistence -----------------------------------------------------------------------

func save_data() -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var p := level_pristine(storey)
	var objs := []
	for o in objects:
		objs.append(o.to_dict())
	var cut := []
	for op in openings:
		if not op["orig"]:
			cut.append([op["axis"], op["line"], op["from"], op["to"]])
	var cells := []
	for c in dug:
		cells.append([c.x, c.y])
	var d := {
		"version": LEVEL_SAVE_VERSION, "layout": layout_id(), "storey": storey, "cells": p.mat.size(),
		"design": VoxelDiff.encode(design, p), "current": VoxelDiff.encode(grid, p),
		"objects": objs, "built": _keys(built), "upgraded": _keys(upgraded), "openings": cut,
		"stone": _keys(_stone_sections()), "foundations": _keys(foundations), "dug": cells,
	}
	stats["save_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	return d


## Restores a saved storey (instead of build_new). False, having built
## nothing, for invalid data or another layout.
func load_data(d: Dictionary) -> bool:
	if typeof(d.get("version")) != TYPE_INT or d["version"] != LEVEL_SAVE_VERSION:
		push_warning("LevelWorld: unsupported level save version %s" % str(d.get("version")))
		return false
	if d.get("layout") != layout_id():
		push_warning("LevelWorld: the save is for another level layout (%s)" % str(d.get("layout")))
		return false
	var p := level_pristine(storey)
	if typeof(d.get("cells")) != TYPE_INT or d["cells"] != p.mat.size():
		push_warning("LevelWorld: the save's voxel grid has another size")
		return false
	var dd := VoxelDiff.decode(d.get("design"), p)
	var dc := VoxelDiff.decode(d.get("current"), p)
	if dd.is_empty() or dc.is_empty():
		push_warning("LevelWorld: damaged voxel data in the save")
		return false
	var objs: Variant = _valid_objects(d.get("objects"))
	var b: Variant = _valid_segs(d.get("built"), 3)
	var u: Variant = _valid_segs(d.get("upgraded"), 3)
	var cut: Variant = _valid_segs(d.get("openings"), 4)
	var st: Variant = _valid_segs(d.get("stone", []), 3)
	var fd: Variant = _valid_segs(d.get("foundations", []), 3)
	var cells: Variant = Levels.cells_from_array(d.get("dug", []))
	if objs == null or b == null or u == null or cut == null or st == null or fd == null or cells == null:
		push_warning("LevelWorld: damaged object or section data in the save")
		return false
	var g_design := p.copy()
	VoxelDiff.apply(g_design, dd)
	var g_cur := p.copy()
	VoxelDiff.apply(g_cur, dc)
	_build_level(g_design, g_cur, objs, b, u, cut, st, fd, cells)
	furniture_layout_changed.emit()     # Exp 005 (F)
	return true


# --- basement ---------------------------------------------------------------------------

## Digs a 1 m basement cell (design and current): the earth in the wall rows
## goes, a packed-earth floor stays. Returns false if already dug.
func dig(c: Vector2i) -> bool:
	if storey != Levels.BASEMENT or dug.has(c):
		return false
	var xr := design.centre_range(0, c.x, c.x + 1.0)
	var zr := design.centre_range(2, c.y, c.y + 1.0)
	for z in range(zr.x, zr.y):
		for x in range(xr.x, xr.y):
			for y in range(VoxelHouse.BASE_ROW, VoxelHouse.TOP_ROW + 1):
				var i := design.idx(x, y, z)
				if design.mat[i] == VoxelMat.EARTH:
					design.clear_index(i)
				if grid.mat[i] == VoxelMat.EARTH:
					grid.clear_index(i)
			if design.get_mat(x, VoxelHouse.FLOOR_ROW, z) == VoxelMat.EARTH:
				var fc := VoxelArt.jitter(DUG_FLOOR, x, 3, z, 0.07)
				_put(x, VoxelHouse.FLOOR_ROW, z, VoxelMat.FLOOR, VoxelArt.scale(fc, 0.8), fc, VoxelHouse.UP_BIT)
	dug[c] = true
	_edited(Vector3i(xr.x, VoxelHouse.FLOOR_ROW, zr.x), Vector3i(xr.y, VoxelHouse.TOP_ROW + 1, zr.y))
	return true


func is_dug(c: Vector2i) -> bool:
	return dug.has(c)


# --- floors and navigation ---------------------------------------------------------------

## True if the current grid has a floor under plan point p (most of a 0.3 m patch).
func has_floor_at(p: Vector2) -> bool:
	var c := grid.cell_of(Vector3(p.x, base_y - 0.05, p.y))
	var n := 0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var m := grid.get_mat(c.x + dx, VoxelHouse.FLOOR_ROW, c.z + dz)
			if m != VoxelMat.AIR and m != VoxelMat.EARTH:
				n += 1
	return n >= 5


func _earth_at(p: Vector2) -> bool:
	var c := design.cell_of(Vector3(p.x, base_y + 0.6, p.y))
	return design.get_mat(c.x, VoxelHouse.NAV_ROW_LO, c.z) == VoxelMat.EARTH


## Basement: undug earth and everything outside the footprint is SOLID.
## Upper floor: cells without a floor (holes, stairwells, outside) are SOLID.
func _cell_kind(c: Vector2i) -> int:
	var p := nav.center_of(c)
	if not HousePlan.FOOTPRINT.has_point(p):
		return GridNav.SOLID
	if storey == Levels.BASEMENT:
		if _earth_at(p):
			return GridNav.SOLID
	elif not has_floor_at(p):
		return GridNav.SOLID
	return super(c)


## Marks plan rect `r` SOLID (stairs) or clears that mark, then refreshes nav.
func set_static_solid(r: Rect2, on: bool) -> void:
	for c in nav.cells_in_rect(r):
		_static_solid[c.y * nav.size.x + c.x] = 1 if on else 0
	_recompute_nav(r.grow(GridNav.CELL))


func exit_path_exists(_extra := {}) -> bool:
	return true                # the exit rule is the ground floor's


func furniture_in(_rect: Rect2) -> bool:
	return false


func bodies_in(rect: Rect2) -> bool:
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(rect.size.x, 0.01), 1.4, maxf(rect.size.y, 0.01))
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.transform = Transform3D(Basis(), Vector3(rect.get_center().x, base_y + 0.85, rect.get_center().y))
	q.collision_mask = 4 | 8
	return not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func is_blocked(p: Vector2) -> bool:
	var space := get_world_3d().direct_space_state
	var y := base_y + 1.0
	for seg in [[Vector3(p.x, y, p.y - 0.25), Vector3(p.x, y, p.y + 0.25)], [Vector3(p.x - 0.25, y, p.y), Vector3(p.x + 0.25, y, p.y)]]:
		for pair in [[seg[0], seg[1]], [seg[1], seg[0]]]:
			var q := PhysicsRayQueryParameters3D.create(pair[0], pair[1], 1 | 2 | 16)
			if not space.intersect_ray(q).is_empty():
				return true
	return false


## Why a piece can't stand on plan rect `r` on this storey ("" = it can):
## upstairs it needs the deck under it, in the basement dug ground.
func level_block_reason(r: Rect2) -> String:
	var probe := r.grow(-0.06)
	if probe.size.x <= 0.0 or probe.size.y <= 0.0:
		probe = Rect2(r.get_center(), Vector2.ZERO)
	for p in [probe.position, Vector2(probe.end.x, probe.position.y), Vector2(probe.position.x, probe.end.y), probe.end, probe.get_center()]:
		if not HousePlan.FOOTPRINT.grow(0.2).has_point(p):
			return "Not outside the house up here." if storey == Levels.UPPER else "That's solid earth."
		if storey == Levels.BASEMENT:
			if _earth_at(p) and not _near_wall_line(p):
				return "That's solid earth: dig it out first."
		elif not has_floor_at(p) and not _near_wall_line(p):
			return "There's no floor there."
	return ""


static func _near_wall_line(p: Vector2) -> bool:
	return absf(p.x - roundf(p.x)) < 0.16 or absf(p.y - roundf(p.y)) < 0.16


# --- view and aiming -------------------------------------------------------------------

func update_view(player_pos: Vector3, camera: Camera3D, delta: float) -> void:
	super(player_pos, camera, delta)
	# Refinement 01: seen from a storey below (the yard, with the camera turned
	# to any side), the cutaway goes through this storey's floor too.
	var floor_y := minf(base_y, Levels.base_y(Levels.storey_at(player_pos.y)))
	for m in cut_materials:
		m.set_shader_parameter("cut_floor", floor_y + 0.45)


func _update_mesh_cut() -> void:
	_hidden_bodies.clear()
	for o in objects:
		if o.kind == "crate":
			continue
		var h: float = WorldObject.DEFS[o.kind]["size"].y
		var cut := _in_cut(Vector3(o.pos.x, base_y + h * 0.5, o.pos.y), 0.5)
		o.set_cut(cut)
		if cut and o.body != null:
			_hidden_bodies.append(o.body.get_rid())


func is_cut(c: Vector3i) -> bool:
	if not _cut_on:
		return false
	var p := grid.center(c)
	var rel := p - _cut_origin
	var t := rel.dot(_cut_dir)
	if t <= 0.45 or p.y <= base_y + 0.45:
		return false
	return (rel - _cut_dir * t).length() < _cut_radius - 0.15


## As HouseWorld.aim_ray; in the basement the ray starts at its ceiling (the
## ground floor above is hidden and must not catch it), and the fallback plane
## is the basement floor.
func aim_ray(from: Vector3, dir: Vector3, low := false) -> Vector3:
	var start := from
	var top := base_y + 2.7
	if storey == Levels.BASEMENT and from.y > top and dir.y < -0.001:
		start = from + dir * ((top - from.y) / dir.y)
	var best := 200.0
	var vh := grid.raycast(start, dir, best, _bullet_skip, is_cut)
	if not vh.is_empty():
		best = vh["dist"]
	var q := PhysicsRayQueryParameters3D.create(start, start + dir * best, 1 | 8 | (16 if low else 0))
	q.exclude = _hidden_bodies
	var ph := get_world_3d().direct_space_state.intersect_ray(q)
	if not ph.is_empty():
		best = start.distance_to(ph["position"])
	var plane := base_y if storey == Levels.BASEMENT else 0.0
	if dir.y < -0.001:
		var tg := (plane - start.y) / dir.y
		if tg >= 0.0 and tg < best:
			best = tg
	return start + dir * best
