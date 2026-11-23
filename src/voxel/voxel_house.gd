class_name VoxelHouse
extends RefCounted
## Builds the shared HousePlan as a 0.1 m voxel volume (Version A).
##
## Voxel centres sit on multiples of 0.1 m in plan X/Y, so every plan rect maps
## to voxels with the same "centre in [start, end)" rule GridNav uses: walls,
## doors, windows and furniture line up with the navigation raster exactly.
##
## Exterior walls (3 voxels): painted lap siding | studs + insulation | drywall.
## Interior walls (2 voxels): drywall (each side painted for its room), studs.
## Floors (3 voxels): foundation (never carved) | screed | finish (planks, tiles...).

const VS := 0.1
const ORIGIN := Vector3(-0.45, -0.4, -0.45)
const SIZE := Vector3i(149, 31, 99)
## Survival game: the grid covers the whole lot (SPEC §5 LOT, Rect2(-4.5, -3.5, 23, 16))
## so walls can be built anywhere on it. Same 0.1 m lattice as ORIGIN (voxel
## centres on multiples of 0.1 m), so the house builds identically.
const LOT_ORIGIN := Vector3(-4.75, -0.4, -3.75)
const LOT_SIZE := Vector3i(232, 31, 162)
const FOUNDATION_ROW := 1
const SCREED_ROW := 2
const FLOOR_ROW := 3          ## floor finish, top face at height 0
const BASE_ROW := 4           ## first wall row: heights [0, 0.1)
const WALL_ROWS := 26         ## 2.6 m
const TOP_ROW := BASE_ROW + WALL_ROWS - 1
## Rows whose height span intersects [0.15, CLEARANCE_HEIGHT): navigation and body collision.
const NAV_ROW_LO := BASE_ROW + 1
const NAV_ROW_HI := BASE_ROW + 15

const UP_BIT := 1 << 2
const ALL_BITS := 63

const ROOM_PAINT := {
	"bedroom": VoxelArt.Slot.PAINT_BEDROOM, "bathroom": VoxelArt.Slot.PAINT_BATHROOM,
	"kitchen": VoxelArt.Slot.PAINT_KITCHEN, "living": VoxelArt.Slot.PAINT_LIVING,
	"utility": VoxelArt.Slot.PAINT_UTILITY,
}
const ROOM_FLOOR := {
	"wood_light": "floor_wood_light", "tile": "floor_tile", "kitchen_tile": "floor_kitchen",
	"wood": "floor_wood", "concrete": "floor_concrete",
}
const RUG_ART := {"rug_living": "rug_living", "rug_bed": "rug_bed", "bath_mat": "rug_bath"}


static func create_grid(lot := false) -> VoxelGrid:
	var g := VoxelGrid.new(LOT_SIZE if lot else SIZE, VS, LOT_ORIGIN if lot else ORIGIN)
	g.cap_row = TOP_ROW
	g.cap_color = VoxelArt.pal(VoxelArt.Slot.CAP)
	return g


static func row_of(height: float) -> int:
	return BASE_ROW + int(floor(height / VS + 1e-4))


## Plan (x, y) of a voxel column centre.
static func column_plan(g: VoxelGrid, x: int, z: int) -> Vector2:
	return Vector2(g.origin.x + (x + 0.5) * g.vs, g.origin.z + (z + 0.5) * g.vs)


## `furniture` = false builds the structure only (floors, rugs, walls, openings,
## trim): the survival game draws furniture as meshes (PropKit) instead.
static func build(g: VoxelGrid, furniture := true) -> void:
	_floors(g)
	_rugs(g)
	_interior_walls(g)
	_exterior_walls(g)
	_openings(g)
	_baseboards(g)
	if furniture:
		VoxelFurniture.build_all(g)


# --- floors ------------------------------------------------------------------------

static func _floors(g: VoxelGrid) -> void:
	var xr := g.centre_range(0, -0.15, 14.15)
	var zr := g.centre_range(2, -0.15, 9.15)
	var found := VoxelArt.pal(VoxelArt.Slot.FOUNDATION)
	var screed := VoxelArt.pal(VoxelArt.Slot.SCREED)
	var biscuit := VoxelArt.pal(VoxelArt.Slot.TILE_BISCUIT)
	for z in range(zr.x, zr.y):
		for x in range(xr.x, xr.y):
			var p := column_plan(g, x, z)
			g.set_voxel(x, FOUNDATION_ROW, z, VoxelMat.FOUNDATION, VoxelArt.jitter(found, x, 1, z, 0.04))
			g.set_voxel(x, SCREED_ROW, z, VoxelMat.SCREED, VoxelArt.jitter(screed, x, 2, z, 0.05))
			var room := HousePlan.room_at(p) if HousePlan.FOOTPRINT.has_point(p) else {}
			if room.is_empty():
				g.set_voxel(x, FLOOR_ROW, z, VoxelMat.SCREED, VoxelArt.jitter(screed, x, 3, z, 0.05))
				continue
			var art: String = ROOM_FLOOR.get(room["floor"], "floor_wood")
			var top := VoxelArt.sample(art, x, z)
			var body := VoxelArt.scale(top, 0.72)
			if art == "floor_tile" or art == "floor_kitchen":
				body = VoxelArt.jitter(biscuit, x, 3, z, 0.05)
			g.set_voxel(x, FLOOR_ROW, z, VoxelMat.FLOOR, body, top, UP_BIT)


static func _rugs(g: VoxelGrid) -> void:
	for f in HousePlan.FURNITURE:
		if f["type"] != "rug":
			continue
		var r: Rect2 = f["rect"]
		var art: String = RUG_ART.get(f["id"], "rug_bed")
		var xr := g.centre_range(0, r.position.x, r.end.x)
		var zr := g.centre_range(2, r.position.y, r.end.y)
		for z in range(zr.x, zr.y):
			for x in range(xr.x, xr.y):
				var u := float(x - xr.x) / maxf(1.0, xr.y - xr.x)
				var v := float(z - zr.x) / maxf(1.0, zr.y - zr.x)
				var c := VoxelArt.sample_uv(art, u, v)
				g.set_voxel(x, FLOOR_ROW, z, VoxelMat.RUG, VoxelArt.scale(c, 0.8), c, UP_BIT)


# --- walls -------------------------------------------------------------------------

static func _room_paint(room_id: String) -> int:
	return VoxelArt.pal(ROOM_PAINT.get(room_id, VoxelArt.Slot.GYPSUM))


## Inner surface voxel of a wall facing `room_id` at wall row r, along-wall index u.
static func _inner_skin(g: VoxelGrid, x: int, y: int, z: int, r: int, room_id: String, bits: int, stud: bool) -> void:
	var gyp := VoxelArt.jitter(VoxelArt.pal(VoxelArt.Slot.GYPSUM), x, y, z, 0.03)
	var p := column_plan(g, x, z)
	if room_id == "bathroom" and r <= 11:
		var tile := VoxelArt.pal(VoxelArt.Slot.TILE_BATH)
		var t := VoxelArt.scale(tile, 1.0 + (VoxelArt.hash3((x + z) / 2, r / 2, 7) - 0.5) * 0.06)
		if r == 11:
			t = VoxelArt.scale(tile, 0.9)
		g.set_voxel(x, y, z, VoxelMat.WALL_TILE, VoxelArt.pal(VoxelArt.Slot.TILE_BISCUIT), t, bits)
		return
	if room_id == "kitchen" and r >= 9 and r <= 14 and p.y < 0.5 and p.x > 8.9 and p.x < 13.9:
		var sage := VoxelArt.pal(VoxelArt.Slot.TILE_KITCHEN)
		var brick := ((x + (r % 2)) / 2)
		var t := VoxelArt.scale(sage, 1.0 + (VoxelArt.hash3(brick, r, 11) - 0.5) * 0.1)
		g.set_voxel(x, y, z, VoxelMat.WALL_TILE, VoxelArt.pal(VoxelArt.Slot.TILE_BISCUIT), t, bits)
		return
	var paint := VoxelArt.jitter(_room_paint(room_id), x, y, z, 0.025)
	if stud:
		g.set_voxel(x, y, z, VoxelMat.STUD, VoxelArt.jitter(VoxelArt.pal(VoxelArt.Slot.STUD), x, y, z, 0.07), paint, bits)
	else:
		g.set_voxel(x, y, z, VoxelMat.DRYWALL, gyp, paint, bits)


static func _interior_walls(g: VoxelGrid) -> void:
	for w in HousePlan.WALLS:
		if w["exterior"]:
			continue
		var horiz := HousePlan.is_horizontal(w)
		var rect := HousePlan.wall_rect(w)
		var xr := g.centre_range(0, rect.position.x, rect.end.x)
		var zr := g.centre_range(2, rect.position.y, rect.end.y)
		var along := xr if horiz else zr
		for z in range(zr.x, zr.y):
			for x in range(xr.x, xr.y):
				var k := (z - zr.x) if horiz else (x - xr.x)       # 0 = -axis side
				var u := x if horiz else z
				var side_dir := (5 if k == 0 else 4) if horiz else (1 if k == 0 else 0)
				var probe := column_plan(g, x, z) + (Vector2(0, -0.3 if k == 0 else 0.3) if horiz else Vector2(-0.3 if k == 0 else 0.3, 0))
				var room: Dictionary = HousePlan.room_at(probe)
				var room_id: String = room.get("id", "")
				var bits := 1 << side_dir
				if u == along.x:
					bits |= 1 << (1 if horiz else 5)
				if u == along.y - 1:
					bits |= 1 << (0 if horiz else 4)
				var stud := posmod(u, 6) == 0
				for r in WALL_ROWS:
					_inner_skin(g, x, BASE_ROW + r, z, r, room_id, bits, stud or r == 0 or r == WALL_ROWS - 1)


## Outward face direction of an exterior wall (0 +X, 1 -X, 4 +Z, 5 -Z).
static func outward_dir(w: Dictionary) -> int:
	var c := ((w["a"] as Vector2) + (w["b"] as Vector2)) * 0.5
	var mid := HousePlan.FOOTPRINT.get_center()
	if HousePlan.is_horizontal(w):
		return 4 if c.y > mid.y else 5
	return 0 if c.x > mid.x else 1


## Layer of a column in an exterior wall: 0 = outside skin, 1 = core, 2 = inside skin.
static func _ext_layer(w: Dictionary, xr: Vector2i, zr: Vector2i, x: int, z: int) -> int:
	match outward_dir(w):
		5: return z - zr.x
		4: return zr.y - 1 - z
		1: return x - xr.x
		_: return xr.y - 1 - x


static func _exterior_walls(g: VoxelGrid) -> void:
	# Pass 1: per column, the minimum layer over all exterior walls + paint bits.
	var cols := {}   # column key -> [layer, out_bits, in_bits, u, walls_at_layer0, walls]
	for w in HousePlan.WALLS:
		if not w["exterior"]:
			continue
		var rect := HousePlan.wall_rect(w)
		var xr := g.centre_range(0, rect.position.x, rect.end.x)
		var zr := g.centre_range(2, rect.position.y, rect.end.y)
		var od := outward_dir(w)
		var horiz := HousePlan.is_horizontal(w)
		for z in range(zr.x, zr.y):
			for x in range(xr.x, xr.y):
				var l := _ext_layer(w, xr, zr, x, z)
				var key := z * g.sx + x
				var e: Array = cols.get(key, [9, 0, 0, 0, 0, 0])
				e[5] += 1
				if l < e[0]:
					e[0] = l
					e[3] = x if horiz else z
				if l == 0:
					e[1] |= 1 << od
					e[4] += 1
				if l == 2:
					e[2] |= 1 << (od ^ 1)
				cols[key] = e
	var siding_raw := VoxelArt.pal(VoxelArt.Slot.SIDING_RAW)
	var plinth := VoxelArt.pal(VoxelArt.Slot.PLINTH)
	var trim_ext := VoxelArt.pal(VoxelArt.Slot.TRIM_EXT)
	var stud_c := VoxelArt.pal(VoxelArt.Slot.STUD)
	# Corner boards: the outer corner column and its neighbours along each face.
	var corner_keys := {}
	for key in cols:
		if cols[key][4] >= 2:
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					corner_keys[key + dz * g.sx + dx] = true
	for key in cols:
		var e: Array = cols[key]
		var x: int = key % g.sx
		var z: int = key / g.sx
		var l: int = e[0]
		var u: int = e[3]
		var p := column_plan(g, x, z)
		for r in WALL_ROWS:
			var y := BASE_ROW + r
			if l == 0:
				if r <= 1:
					g.set_voxel(x, y, z, VoxelMat.PLINTH, VoxelArt.jitter(plinth, x, y, z, 0.06), VoxelArt.jitter(plinth, x, y, z, 0.04), e[1])
				elif corner_keys.has(key):
					g.set_voxel(x, y, z, VoxelMat.TRIM, VoxelArt.jitter(siding_raw, x, y, z, 0.05), VoxelArt.jitter(trim_ext, x, y, z, 0.03), e[1])
				else:
					var paint := VoxelArt.sample("siding", u, WALL_ROWS - 1 - r)
					g.set_voxel(x, y, z, VoxelMat.SIDING, VoxelArt.jitter(siding_raw, x, y, z, 0.07), paint, e[1])
			elif l == 1:
				var is_stud: bool = posmod(u, 6) == 0 or r == 0 or r >= WALL_ROWS - 2 or e[5] > 1
				if is_stud:
					g.set_voxel(x, y, z, VoxelMat.STUD, VoxelArt.jitter(stud_c, x, y, z, 0.08))
				else:
					g.set_voxel(x, y, z, VoxelMat.INSULATION, VoxelArt.sample("insulation", u, r))
			else:
				var room: Dictionary = HousePlan.room_at(p + _inward_probe(e[2]))
				_inner_skin(g, x, y, z, r, room.get("id", ""), e[2], r == 0 or r == WALL_ROWS - 1)


static func _inward_probe(in_bits: int) -> Vector2:
	var v := Vector2.ZERO
	if in_bits & 1:
		v.x += 0.3
	if in_bits & 2:
		v.x -= 0.3
	if in_bits & 16:
		v.y += 0.3
	if in_bits & 32:
		v.y -= 0.3
	return v


# --- doors and windows ----------------------------------------------------------------

static func _openings(g: VoxelGrid) -> void:
	var trim_int := VoxelArt.pal(VoxelArt.Slot.TRIM_INT)
	var trim_ext := VoxelArt.pal(VoxelArt.Slot.TRIM_EXT)
	var frame := VoxelArt.pal(VoxelArt.Slot.FRAME)
	var glass := VoxelArt.pal(VoxelArt.Slot.GLASS)
	var pine := VoxelArt.pal(VoxelArt.Slot.STUD)
	var sill_ext := VoxelArt.pal(VoxelArt.Slot.SILL_EXT)
	var thresh := VoxelArt.pal(VoxelArt.Slot.THRESHOLD)
	for o in HousePlan.OPENINGS:
		var w := HousePlan.wall_by_id(o["wall"])
		var horiz := HousePlan.is_horizontal(w)
		var rect := HousePlan.wall_rect(w)
		var tr := g.centre_range(2 if horiz else 0, rect.position.y if horiz else rect.position.x, rect.end.y if horiz else rect.end.x)
		var ar := g.centre_range(0 if horiz else 2, o["from"], o["to"])
		var ext: bool = w["exterior"]
		var is_door: bool = o["kind"] == "door"
		var r0 := 0 if is_door else int(round(HousePlan.window_sill(o) / VS))
		var r1 := int(round(HousePlan.WINDOW_HEAD / VS))   # first row above the opening
		var od := outward_dir(w) if ext else -1
		var outer_t := -1
		var inner_t := -1
		if ext:
			outer_t = tr.x if (od == 5 or od == 1) else tr.y - 1
			inner_t = tr.y - 1 if outer_t == tr.x else tr.x
		var put := func(a: int, t: int, r: int, m: int, c: int, pc: int, pm: int) -> void:
			var x := a if horiz else t
			var z := t if horiz else a
			g.set_voxel(x, BASE_ROW + r, z, m, c, pc, pm)
		# Clear the opening.
		for a in range(ar.x, ar.y):
			for t in range(tr.x, tr.y):
				for r in range(r0, r1):
					put.call(a, t, r, VoxelMat.AIR, 0, 0, 0)
		if is_door:
			var tc := trim_ext if ext else trim_int
			for t in range(tr.x, tr.y):
				for r in range(0, r1 + 1):
					put.call(ar.x - 1, t, r, VoxelMat.TRIM, VoxelArt.jitter(pine, ar.x - 1, r, t, 0.05), VoxelArt.jitter(tc, ar.x - 1, r, t, 0.02), ALL_BITS)
					put.call(ar.y, t, r, VoxelMat.TRIM, VoxelArt.jitter(pine, ar.y, r, t, 0.05), VoxelArt.jitter(tc, ar.y, r, t, 0.02), ALL_BITS)
				for a in range(ar.x, ar.y):
					put.call(a, t, r1, VoxelMat.TRIM, VoxelArt.jitter(pine, a, r1, t, 0.05), VoxelArt.jitter(tc, a, r1, t, 0.02), ALL_BITS)
					var x := a if horiz else t
					var z := t if horiz else a
					g.set_voxel(x, FLOOR_ROW, z, VoxelMat.THRESHOLD, VoxelArt.scale(thresh, 0.8), VoxelArt.jitter(thresh, a, 0, t, 0.06), UP_BIT)
			continue
		# Window: frame ring + glass in the middle layer, casings on both skins, sills.
		var mid_t := tr.x + 1
		var width := ar.y - ar.x
		var mullion := ar.x + width / 2 if width >= 15 else -100
		for a in range(ar.x, ar.y):
			for r in range(r0, r1):
				var ring := a == ar.x or a == ar.y - 1 or r == r0 or r == r1 - 1 or a == mullion
				if ring:
					put.call(a, mid_t, r, VoxelMat.FRAME, VoxelArt.jitter(frame, a, r, 3, 0.03), VoxelArt.jitter(frame, a, r, 3, 0.03), ALL_BITS)
				else:
					put.call(a, mid_t, r, VoxelMat.GLASS, glass, glass, 0)
		for skin in [[outer_t, trim_ext], [inner_t, trim_int]]:
			var t: int = skin[0]
			var tc: int = skin[1]
			for r in range(r0 - 1, r1 + 1):
				for a in [ar.x - 1, ar.y]:
					put.call(a, t, r, VoxelMat.TRIM, VoxelArt.jitter(pine, a, r, t, 0.05), VoxelArt.jitter(tc, a, r, t, 0.02), ALL_BITS)
			for a in range(ar.x - 1, ar.y + 1):
				put.call(a, t, r1, VoxelMat.TRIM, VoxelArt.jitter(pine, a, r1, t, 0.05), VoxelArt.jitter(tc, a, r1, t, 0.02), ALL_BITS)
				put.call(a, t, r0 - 1, VoxelMat.TRIM, VoxelArt.jitter(pine, a, r0 - 1, t, 0.05), VoxelArt.jitter(tc, a, r0 - 1, t, 0.02), ALL_BITS)
		# Sills protrude one voxel out of each face (decor: no collision).
		var out_step := -1 if outer_t == tr.x else 1
		for a in range(ar.x - 1, ar.y + 1):
			put.call(a, outer_t + out_step, r0 - 1, VoxelMat.SILL, VoxelArt.jitter(sill_ext, a, r0, 1, 0.03), VoxelArt.jitter(sill_ext, a, r0, 1, 0.03), ALL_BITS)
			put.call(a, inner_t - out_step, r0 - 1, VoxelMat.SILL, VoxelArt.jitter(trim_int, a, r0, 2, 0.02), VoxelArt.jitter(trim_int, a, r0, 2, 0.02), ALL_BITS)


static func _baseboards(g: VoxelGrid) -> void:
	var c := VoxelArt.pal(VoxelArt.Slot.BASEBOARD)
	var y := BASE_ROW
	var place := []
	for z in range(1, g.sz - 1):
		for x in range(1, g.sx - 1):
			var i := g.idx(x, y, z)
			if g.mat[i] != VoxelMat.DRYWALL and g.mat[i] != VoxelMat.STUD:
				continue
			for d in [[1, 0, 0], [-1, 0, 1], [0, 1, 4], [0, -1, 5]]:
				if (g.pmask[i] >> d[2]) & 1 == 0:
					continue
				var nx: int = x + d[0]
				var nz: int = z + d[1]
				if g.get_mat(nx, y, nz) == VoxelMat.AIR and g.get_mat(nx, FLOOR_ROW, nz) == VoxelMat.FLOOR:
					place.append(Vector2i(nx, nz))
	for p in place:
		g.set_voxel(p.x, y, p.y, VoxelMat.BASEBOARD, VoxelArt.jitter(c, p.x, y, p.y, 0.03), VoxelArt.jitter(c, p.x, y, p.y, 0.02), ALL_BITS)
