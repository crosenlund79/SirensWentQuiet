class_name FowGrid
extends RefCounted
## Exp 012 (V): the fog of war's data (the user's §15-17). Pure, no nodes:
## FogOfWar (fog_of_war.gd) owns one and draws it.
##
## Two coarse layers over the playable area, 0.5 m cells (AREA, offset by a
## quarter metre so a wall on a whole-metre line lies inside one cell row and
## the room behind it starts in the next one):
##   disc  discovered (0 / 255): seen at least once; static structures there
##         are remembered (drawn darkened)
##   vis   visible now (0 / 255): inside Eli's vision cone or his close ring,
##         with a clear line of sight
## Line of sight is cast on `occ`, a 0.25 m sight-blocking raster on the
## world's navigation lattice (GridNav cells), built from the voxels at eye
## height (three rows, 1.2 / 1.5 / 1.8 m above the storey's floor: a cell
## blocks sight when any of them holds an opaque structural voxel, so a bullet
## hole never opens a window but a breach does; glass, frames, sills and
## doorways don't block) plus closed doors and window boards (objects).
## `occ` is rebuilt only when the structure changes (FogOfWar debounces it);
## casting is a fan of rays marched in 0.25 m steps (cone rays every
## RAY_STEP_DEG out to the range, a sparse ring all round out to `ring`).

const CELL := 0.5
## HousePlan.YARD (-7, -6, 28, 21) grown by about 4 m, its corner on a quarter metre.
const AREA := Rect2(-11.25, -10.25, 37.0, 30.0)
const OCC_CELL := 0.25                      ## GridNav.CELL
const STEP := 0.25                          ## ray march step (m)
const RAY_STEP_DEG := 1.0                   ## cone rays (0.42 m apart at 24 m: finer than a cell)
const RING_STEP_DEG := 7.5                  ## ring rays (behind)
const EYE_ROWS := [1.2, 1.5, 1.8]           ## m above the storey's floor
const SKIP_NEAR := 0.3                      ## m: occluders this close to the eye are ignored (standing in a doorway)
## Voxel materials that block sight (structural walls, earth). Glass, frames,
## sills, trim at the jambs and decor don't.
const OPAQUE := [VoxelMat.PLINTH, VoxelMat.SIDING, VoxelMat.STUD, VoxelMat.INSULATION, VoxelMat.DRYWALL,
	VoxelMat.WALL_TILE, VoxelMat.METAL_SHEET, VoxelMat.MASONRY, VoxelMat.MORTAR, VoxelMat.EARTH]
const SAVE_V := 1

var w := int(AREA.size.x / CELL)            ## 74
var h := int(AREA.size.y / CELL)            ## 60
var disc := PackedByteArray()
var vis := PackedByteArray()
var occ := PackedByteArray()                ## 1 = blocks sight (nav lattice)
var occ_origin := Vector2.ZERO              ## centre of occ cell (0, 0)
var occ_size := Vector2i.ZERO
var touched := PackedInt32Array()           ## vis cells set by the last cast(s)
var rays := 0                               ## rays of the last cast (stats)
var steps := 0                              ## march steps of the last cast (stats)
var _opaque := PackedByteArray()            ## material -> 1


func _init() -> void:
	disc.resize(w * h)
	vis.resize(w * h)
	_opaque.resize(256)
	for m in OPAQUE:
		_opaque[m] = 1


# --- cells ---------------------------------------------------------------------------------

func index_of(p: Vector2) -> int:
	var i := int(floor((p.x - AREA.position.x) / CELL))
	var j := int(floor((p.y - AREA.position.y) / CELL))
	if i < 0 or j < 0 or i >= w or j >= h:
		return -1
	return j * w + i


func is_visible(p: Vector2) -> bool:
	var k := index_of(p)
	return k >= 0 and vis[k] != 0


func is_discovered(p: Vector2) -> bool:
	var k := index_of(p)
	return k >= 0 and disc[k] != 0


func discover_rect(r: Rect2) -> void:
	for j in h:
		var y := AREA.position.y + (j + 0.5) * CELL
		if y < r.position.y or y > r.end.y:
			continue
		for i in w:
			var x := AREA.position.x + (i + 0.5) * CELL
			if x >= r.position.x and x <= r.end.x:
				disc[j * w + i] = 255


func reveal_all() -> void:
	disc.fill(255)


func clear_discovered() -> void:
	disc.fill(0)


func discovered_count() -> int:
	var n := 0
	for b in disc:
		if b != 0:
			n += 1
	return n


# --- occlusion -----------------------------------------------------------------------------

## Rebuilds the sight blockers of `world` (its storey's eye rows, its closed doors and boards).
func build_occlusion(world: HouseWorld) -> void:
	var nav: GridNav = world.nav if world != null else null
	if nav == null:
		occ = PackedByteArray()
		occ_size = Vector2i.ZERO
		return
	occ_size = nav.size
	occ_origin = nav.bounds.position
	occ.resize(occ_size.x * occ_size.y)
	occ.fill(0)
	var g: VoxelGrid = world.grid
	if g != null:
		var floor_y := g.origin.y + 0.4                       # the grid's row layout: floor finish top at origin + 0.4
		var rows := []
		for e in EYE_ROWS:
			var r := int(floor((floor_y + float(e) - g.origin.y) / g.vs))
			if r > 0 and r < g.sy - 1:
				rows.append(r * g.sz)
		var half := OCC_CELL * 0.5
		var raw: PackedByteArray = nav.get("_raw")              # GridNav's raw cells, read directly (no call per cell)
		var nx := occ_size.x
		for j in occ_size.y:
			for i in nx:
				var k: int = raw[j * nx + i]
				if k != GridNav.WALL and k != GridNav.SOLID:
					continue
				var cx := occ_origin.x + i * OCC_CELL
				var cz := occ_origin.y + j * OCC_CELL
				var x0 := maxi(int(ceil((cx - half - g.origin.x) / g.vs - 0.5)), 1)
				var x1 := mini(int(floor((cx + half - g.origin.x) / g.vs - 0.5)), g.sx - 2)
				var z0 := maxi(int(ceil((cz - half - g.origin.z) / g.vs - 0.5)), 1)
				var z1 := mini(int(floor((cz + half - g.origin.z) / g.vs - 0.5)), g.sz - 2)
				if x0 > x1 or z0 > z1:
					continue
				var blocked := false
				for ro in rows:
					for z in range(z0, z1 + 1):
						var base: int = (int(ro) + z) * g.sx
						for x in range(x0, x1 + 1):
							if _opaque[g.mat[base + x]] != 0:
								blocked = true
								break
						if blocked:
							break
					if blocked:
						break
				if blocked:
					occ[j * occ_size.x + i] = 1
	for o in world.objects:
		if not is_instance_valid(o):
			continue
		if (o.kind == "door" and not o.open) or o.kind == "boards":
			for c in nav.cells_in_rect(o.footprint().grow(0.03)):
				occ[c.y * occ_size.x + c.x] = 1


func occ_at(p: Vector2) -> bool:
	if occ_size == Vector2i.ZERO:
		return false
	var i := int(round((p.x - occ_origin.x) / OCC_CELL))
	var j := int(round((p.y - occ_origin.y) / OCC_CELL))
	if i < 0 or j < 0 or i >= occ_size.x or j >= occ_size.y:
		return false
	return occ[j * occ_size.x + i] != 0


## True if no sight blocker lies between a and b (the ends themselves excluded).
func segment_clear(a: Vector2, b: Vector2) -> bool:
	var d := a.distance_to(b)
	var n := int(ceil(d / (STEP * 0.8)))
	for s in range(1, n):
		if occ_at(a.lerp(b, float(s) / float(n))):
			return false
	return true


# --- casting -------------------------------------------------------------------------------

## Clears `vis` (and `touched`) for a new update.
func begin() -> void:
	vis.fill(0)
	touched.clear()
	rays = 0
	steps = 0


## Marks what an eye at `eye` sees: a cone of `half_cone` (rad) either side
## of `fwd` out to `reach` m, and all round out to `ring` m. Adds to `vis`.
func cast(eye: Vector2, fwd: Vector2, half_cone: float, reach: float, ring: float) -> void:
	_mark(eye)
	var base := fwd.angle() if fwd.length() > 0.001 else 0.0
	var cone_n := maxi(int(ceil(2.0 * half_cone / deg_to_rad(RAY_STEP_DEG))), 1)
	for k in cone_n + 1:
		var a := base - half_cone + 2.0 * half_cone * float(k) / float(cone_n)
		_ray(eye, Vector2(cos(a), sin(a)), reach)
	if ring > 0.0 and half_cone < PI:
		var rest := TAU - 2.0 * half_cone
		var ring_n := maxi(int(ceil(rest / deg_to_rad(RING_STEP_DEG))), 1)
		for k in range(1, ring_n):
			var a := base + half_cone + rest * float(k) / float(ring_n)
			_ray(eye, Vector2(cos(a), sin(a)), ring)


## disc |= vis over the cells the last casts touched. Returns how many were new.
func commit() -> int:
	var n := 0
	for k in touched:
		if disc[k] == 0:
			disc[k] = 255
			n += 1
	return n


func _ray(eye: Vector2, d: Vector2, reach: float) -> void:
	rays += 1
	# Incremental march in cell units (no allocations, few calls: this is the hot loop).
	var inv := 1.0 / CELL
	var gx := (eye.x - AREA.position.x) * inv          # position in vis cells
	var gy := (eye.y - AREA.position.y) * inv
	var sx := d.x * STEP * inv
	var sy := d.y * STEP * inv
	var has_occ := occ_size != Vector2i.ZERO
	var inv_o := 1.0 / OCC_CELL
	var ox := (eye.x - occ_origin.x) * inv_o + 0.5     # position in occ cells (+0.5: round by truncating)
	var oy := (eye.y - occ_origin.y) * inv_o + 0.5
	var osx := d.x * STEP * inv_o
	var osy := d.y * STEP * inv_o
	var n := int(reach / STEP)
	var skip := int(SKIP_NEAR / STEP)
	var ow := occ_size.x
	var oh := occ_size.y
	for s in range(1, n + 1):
		gx += sx
		gy += sy
		ox += osx
		oy += osy
		if gx < 0.0 or gy < 0.0:
			steps += s
			return
		var i := int(gx)
		var j := int(gy)
		if i >= w or j >= h:
			steps += s
			return
		var k := j * w + i
		if vis[k] == 0:
			vis[k] = 255
			touched.append(k)
		if has_occ and s > skip and ox >= 0.0 and oy >= 0.0:
			var oi := int(ox)
			var oj := int(oy)
			if oi < ow and oj < oh and occ[oj * ow + oi] != 0:
				var fx := int(gx + sx)                     # the far half of the wall itself
				var fy := int(gy + sy)
				if fx >= 0 and fy >= 0 and fx < w and fy < h and vis[fy * w + fx] == 0:
					vis[fy * w + fx] = 255
					touched.append(fy * w + fx)
				steps += s
				return
	steps += n


func _mark(p: Vector2) -> void:
	var k := index_of(p)
	if k >= 0 and vis[k] == 0:
		vis[k] = 255
		touched.append(k)


# --- persistence ---------------------------------------------------------------------------

## A compact copy of `disc`: {"v", "w", "h", "k" (a layout key), "b" (base64 of the deflated bit set)}.
func save_seen(key := "") -> Dictionary:
	var bits := PackedByteArray()
	bits.resize((w * h + 7) >> 3)
	for k in w * h:
		if disc[k] != 0:
			bits[k >> 3] |= 1 << (k & 7)
	return {"v": SAVE_V, "w": w, "h": h, "k": key, "n": bits.size(),
		"b": Marshalls.raw_to_base64(bits.compress(FileAccess.COMPRESSION_DEFLATE))}


## Restores `disc` from save_seen(); false (and nothing changed) when it is
## missing, damaged or of another grid or layout key.
func load_seen(d: Variant, key := "") -> bool:
	if typeof(d) != TYPE_DICTIONARY:
		return false
	if int(d.get("v", 0)) != SAVE_V or int(d.get("w", 0)) != w or int(d.get("h", 0)) != h or str(d.get("k", "")) != key:
		return false
	var n := (w * h + 7) >> 3
	if typeof(d.get("b")) != TYPE_STRING:
		return false
	var raw := Marshalls.base64_to_raw(str(d["b"]))
	if raw.is_empty():
		return false
	var bits := raw.decompress(n, FileAccess.COMPRESSION_DEFLATE)
	if bits.size() != n:
		return false
	for k in w * h:
		disc[k] = 255 if (bits[k >> 3] >> (k & 7)) & 1 else 0
	return true
