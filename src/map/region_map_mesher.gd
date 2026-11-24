class_name RegionMapMesher
extends RefCounted
## Turns a RegionTerrain into meshes (SPEC-003 §6). Owner: M.
##
## - Terrain: chunked (CHUNK x CHUNK columns), face-culled heightfield. One
##   top quad per column; side quads only where a neighbour is lower (an upper
##   "lip" band in the cover colour, the rest in earth or rock). Vertex colours
##   (sRGB) with per-cell variation; baked AO in COLOR.a (top corners from the
##   three neighbours, like VoxelMesher; side bottoms darker).
## - Props: every building box as five faces (no bottom), chunked the same way;
##   UV.x = 1 marks emissive (the house's warm windows).
## - Water: one mesh; surfaces per water cell plus falls where the river steps
##   down. COLOR = (depth, shore, sea) for the water shader.
## - Trees: five voxel tree variants (local meshes) for MultiMeshes; the
##   instance colour tints the canopy.
## build(terrain) caches the result for the session.

const CHUNK := 32
const AO_CURVE := [0.5, 0.68, 0.85, 1.0]
const SIDE_AO := 0.62
const PROP_AO := 0.58

## Experiment 004 (northern atmosphere): the region lies under snow. Covers
## are snow tones (shaded under the forest, trodden in towns), fields are
## snow with stubble rows, lanes and streets are slushy, roofs carry snow, the
## broadleaf and dead trees are pines, and the water freezes at its edges
## (map_water.gdshader).
const TOP := {
	RegionTerrain.C_GRASS: Color(0.86, 0.88, 0.9), RegionTerrain.C_MEADOW: Color(0.88, 0.89, 0.91),
	RegionTerrain.C_FOREST: Color(0.72, 0.76, 0.78), RegionTerrain.C_SAND: Color(0.82, 0.82, 0.81),
	RegionTerrain.C_ROCK: Color(0.52, 0.52, 0.53), RegionTerrain.C_SNOW: Color(0.93, 0.94, 0.96),
	RegionTerrain.C_PAVED: Color(0.68, 0.69, 0.7), RegionTerrain.C_YARD: Color(0.8, 0.81, 0.83),
	RegionTerrain.C_QUAY: Color(0.66, 0.67, 0.68), RegionTerrain.C_PARK: Color(0.86, 0.88, 0.9),
	RegionTerrain.C_BED: Color(0.62, 0.65, 0.68), RegionTerrain.C_QUARRY: Color(0.8, 0.8, 0.79),
	RegionTerrain.C_LAWN: Color(0.88, 0.89, 0.91), RegionTerrain.C_DIRT: Color(0.66, 0.63, 0.6),
}
const FIELDS := [Color(0.9, 0.9, 0.89), Color(0.83, 0.83, 0.82), Color(0.88, 0.89, 0.9), Color(0.85, 0.85, 0.83)]
const ROAD_COL := {RegionTerrain.R_LANE: Color(0.74, 0.73, 0.71), RegionTerrain.R_STREET: Color(0.46, 0.47, 0.49), RegionTerrain.R_MAIN: Color(0.4, 0.41, 0.43)}
const ROOF_SNOW := Color(0.9, 0.92, 0.95)
const DRY_GRASS := Color(0.62, 0.58, 0.45)
const PINE_TINTS := [Color(0.27, 0.38, 0.31), Color(0.24, 0.34, 0.3), Color(0.31, 0.41, 0.32), Color(0.22, 0.31, 0.27)]
const ROAD_WIDTH := {RegionTerrain.R_LANE: 0.3, RegionTerrain.R_STREET: 0.42, RegionTerrain.R_MAIN: 0.52}
const ROAD_LIFT := 0.03
const EARTH := Color(0.43, 0.36, 0.28)
const STONE := Color(0.5, 0.49, 0.47)
const PALE_STONE := Color(0.7, 0.68, 0.63)
const CONCRETE_SIDE := Color(0.52, 0.51, 0.49)
const SAND_SIDE := Color(0.64, 0.58, 0.46)

static var _cache := {}


const TRI_A := [0, 2, 1, 0, 3, 2]
const TRI_B := [0, 3, 1, 1, 3, 2]


class Builder:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var inds := PackedInt32Array()
	var n := 0

	func quad(c: Array, nrm: Vector3, k: Array, uv: Vector2) -> void:
		for j in 4:
			verts.append(c[j])
			norms.append(nrm)
			cols.append(k[j])
			uvs.append(uv)
		# split along the diagonal that keeps the AO gradient smooth
		var order: Array = TRI_A if k[0].a + k[2].a >= k[1].a + k[3].a else TRI_B
		for o in order:
			inds.append(n + o)
		n += 4

	func faces() -> int:
		return n / 4

	func mesh() -> ArrayMesh:
		var m := ArrayMesh.new()
		if n == 0:
			return m
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_COLOR] = cols
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = inds
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return m


const NORMALS := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]


## Corners of face d (0 +X, 1 -X, 2 +Y, 3 -Y, 4 +Z, 5 -Z) of the box lo..hi in
## the order (-u-v, +u-v, +u+v, -u+v) with u x v = normal (front = clockwise).
static func face_corners(lo: Vector3, hi: Vector3, d: int) -> Array:
	match d:
		0:
			return [Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, lo.y, hi.z)]
		1:
			return [Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, hi.y, lo.z)]
		2:
			return [Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z)]
		3:
			return [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z)]
		4:
			return [Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]
	return [Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, lo.y, lo.z)]


## A box: five faces (no bottom). Side bottoms get `ao`, tops are lit fully.
static func add_box(b: Builder, lo: Vector3, hi: Vector3, col: Color, glow := 0.0, ao := PROP_AO, with_top := true, snow := false) -> void:
	var top := Color(minf(col.r * 1.07, 1.0), minf(col.g * 1.07, 1.0), minf(col.b * 1.07, 1.0), 1.0)
	if snow:
		top = ROOF_SNOW      # Experiment 004: snow on every roof and box top
	var uv := Vector2(glow, 0.0)
	for d in [0, 1, 2, 4, 5]:
		if d == 2 and not with_top:
			continue
		var c := face_corners(lo, hi, d)
		if d == 2:
			b.quad(c, NORMALS[d], [top, top, top, top], uv)
		else:
			var k := []
			for p in c:
				k.append(Color(col.r, col.g, col.b, ao if (p as Vector3).y <= lo.y + 0.001 else 1.0))
			b.quad(c, NORMALS[d], k, uv)


# --- build ----------------------------------------------------------------------

## {terrain: [ArrayMesh], props: [ArrayMesh], water: ArrayMesh, tree_meshes: [ArrayMesh],
##  trees: [MultiMesh], faces: {terrain, props, water, trees}, ms: float}
static func build(t: RegionTerrain) -> Dictionary:
	var key := t.get_instance_id()
	if _cache.has(key):
		return _cache[key]
	var t0 := Time.get_ticks_usec()
	var out := {}
	var faces := {}
	var terrain := []
	var tf := 0
	var cx := int(ceil(float(RegionTerrain.W) / CHUNK))
	var cz := int(ceil(float(RegionTerrain.H) / CHUNK))
	var noise := FastNoiseLite.new()
	noise.seed = RegionTerrain.SEED + 7
	noise.frequency = 0.08
	for j in cz:
		for k in cx:
			var b := Builder.new()
			_terrain_chunk(t, b, Rect2i(k * CHUNK, j * CHUNK, CHUNK, CHUNK), noise)
			_road_strips(t, b, Rect2i(k * CHUNK, j * CHUNK, CHUNK, CHUNK))
			tf += b.faces()
			terrain.append(b.mesh())
	out["terrain"] = terrain
	faces["terrain"] = tf
	# props, chunked by box centre
	var pb := []
	for k in cx * cz:
		pb.append(Builder.new())
	for box in t.boxes:
		var lo: Vector3 = box[0]
		var hi: Vector3 = box[1]
		var c := (lo + hi) * 0.5
		var ci := clampi(int(c.z) / CHUNK, 0, cz - 1) * cx + clampi(int(c.x) / CHUNK, 0, cx - 1)
		add_box(pb[ci], lo, hi, box[2], box[3], PROP_AO, true, box[3] <= 0.0 and hi.y - lo.y > 0.06)
	var props := []
	var pf := 0
	for b in pb:
		pf += (b as Builder).faces()
		props.append((b as Builder).mesh())
	out["props"] = props
	faces["props"] = pf
	var wb := Builder.new()
	_water(t, wb)
	out["water"] = wb.mesh()
	faces["water"] = wb.faces()
	var tm := tree_meshes()
	out["tree_meshes"] = tm["meshes"]
	var mms := []
	var per := []
	for v in tm["meshes"].size():
		per.append([])
	for tr in t.trees:
		# Experiment 004: broadleaf trees become tall pines, dead ones small pines
		var item: Array = tr
		var v: int = item[1]
		if v == 2 or v == 4:
			var at: Vector3 = item[0]
			var k := int(_hash01(int(at.x * 7.0), int(at.z * 7.0)) * 3.99)
			item = [at, 0 if v == 2 else 1, item[2], PINE_TINTS[k], item[4]]
		per[item[1]].append(item)
	var tfaces := 0
	for v in per.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = tm["meshes"][v]
		mm.instance_count = per[v].size()
		for k in per[v].size():
			var tr: Array = per[v][k]
			var basis := Basis(Vector3.UP, tr[4] * PI * 0.5).scaled(Vector3.ONE * float(tr[2]))
			mm.set_instance_transform(k, Transform3D(basis, tr[0]))
			mm.set_instance_color(k, tr[3])
		tfaces += per[v].size() * int(tm["faces"][v])
		mms.append(mm)
	out["trees"] = mms
	faces["trees"] = tfaces
	out["faces"] = faces
	out["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	_cache[key] = out
	return out


static func _hash01(x: int, y: int) -> float:
	var h := (x * 374761393 + y * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0


static func top_color(t: RegionTerrain, x: int, y: int, noise: FastNoiseLite) -> Color:
	var i := y * RegionTerrain.W + x
	var cv := t.cover[i]
	var col: Color
	if cv == RegionTerrain.C_FIELD:
		col = FIELDS[t.field[i]]
		# furrows: every other row (or column) a little darker
		if ((y if t.field[i] % 2 == 0 else x) % 2) == 1:
			col = col.darkened(0.1)
	else:
		col = TOP.get(cv, TOP[RegionTerrain.C_GRASS])
	var h := t.height[i]
	if cv == RegionTerrain.C_ROCK:
		col = col.lightened(clampf((h - 20) * 0.012, 0.0, 0.2))
		# lichen and scree
		col = col.lerp(Color(0.44, 0.45, 0.4), clampf(noise.get_noise_2d(x * 2.0, y * 2.0) * 0.8, 0.0, 0.6))
		# snow on the heights and in the hollows of the rock
		col = col.lerp(TOP[RegionTerrain.C_SNOW], clampf((h - 16) * 0.05 + noise.get_noise_2d(x * 3.0, y * 3.0) * 0.6, 0.0, 0.9))
	elif cv == RegionTerrain.C_SNOW:
		col = col.lerp(Color(0.78, 0.82, 0.88), clampf(-noise.get_noise_2d(x * 2.0, y * 2.0), 0.0, 0.4))
	var n := noise.get_noise_2d(x, y)
	if cv in [RegionTerrain.C_GRASS, RegionTerrain.C_MEADOW, RegionTerrain.C_LAWN, RegionTerrain.C_PARK]:
		# dry grass poking through the snow in places, blue shade in the drifts
		col = col.lerp(DRY_GRASS, clampf(n * 0.7 - 0.2, 0.0, 0.3)).lerp(Color(0.76, 0.8, 0.87), clampf(-n * 0.5, 0.0, 0.25))
	elif cv == RegionTerrain.C_FOREST:
		col = col.lerp(Color(0.5, 0.55, 0.54), clampf(n * 0.6, 0.0, 0.3))
	var v := 0.95 + _hash01(x, y) * 0.08 + n * 0.03
	return Color(col.r * v, col.g * v, col.b * v)


static func _side_colors(t: RegionTerrain, i: int, top: Color) -> Array:
	var cv := t.cover[i]
	var h := t.height[i]
	var lip := top.darkened(0.12)
	var body := EARTH
	if cv == RegionTerrain.C_QUARRY:
		body = PALE_STONE
		lip = PALE_STONE
	elif cv in [RegionTerrain.C_ROCK, RegionTerrain.C_SNOW] or h > 22:
		body = STONE
	elif cv in [RegionTerrain.C_SAND, RegionTerrain.C_BED]:
		body = SAND_SIDE
	elif cv in [RegionTerrain.C_PAVED, RegionTerrain.C_QUAY, RegionTerrain.C_YARD] or t.road[i] != RegionTerrain.R_NONE:
		body = CONCRETE_SIDE
		lip = CONCRETE_SIDE.lightened(0.05)
	return [lip, body]


static func _terrain_chunk(t: RegionTerrain, b: Builder, r: Rect2i, noise: FastNoiseLite) -> void:
	var W := RegionTerrain.W
	var H := RegionTerrain.H
	var S := RegionTerrain.STEP
	var hs := t.height
	var curve := PackedFloat32Array(AO_CURVE)
	var uv := Vector2(0.0, 1.0)
	var dirs := [[0, Vector2i(1, 0)], [1, Vector2i(-1, 0)], [4, Vector2i(0, 1)], [5, Vector2i(0, -1)]]
	for y in range(r.position.y, mini(r.end.y, H)):
		for x in range(r.position.x, mini(r.end.x, W)):
			var i := y * W + x
			var h := hs[i]
			var top := h * S
			var col := top_color(t, x, y, noise)
			# AO for the four top corners: (x,y) (x,y+1) (x+1,y+1) (x+1,y)
			var occ := [
				_occ(t, x - 1, y, h), _occ(t, x + 1, y, h), _occ(t, x, y - 1, h), _occ(t, x, y + 1, h),
				_occ(t, x - 1, y - 1, h), _occ(t, x - 1, y + 1, h), _occ(t, x + 1, y + 1, h), _occ(t, x + 1, y - 1, h)]
			var a0 := _ao(occ[0], occ[2], occ[4])
			var a1 := _ao(occ[0], occ[3], occ[5])
			var a2 := _ao(occ[1], occ[3], occ[6])
			var a3 := _ao(occ[1], occ[2], occ[7])
			var lo := Vector3(x, top, y)
			var hi := Vector3(x + 1, top, y + 1)
			b.quad(face_corners(lo, hi, 2), NORMALS[2], [
				Color(col.r, col.g, col.b, curve[a0]), Color(col.r, col.g, col.b, curve[a1]),
				Color(col.r, col.g, col.b, curve[a2]), Color(col.r, col.g, col.b, curve[a3])], uv)
			var sc := []
			for dd in dirs:
				var nx: int = x + dd[1].x
				var ny: int = y + dd[1].y
				if nx < 0 or ny < 0 or nx >= W or ny >= H:
					continue   # the region edge dissolves into fog: no walls
				var nh := hs[ny * W + nx]
				if nh >= h:
					continue
				if sc.is_empty():
					sc = _side_colors(t, i, col)
				var d: int = dd[0]
				var lip: Color = sc[0]
				var body: Color = sc[1]
				if h - nh >= 2:
					_side(b, x, y, d, (h - 1) * S, top, lip, 1.0, 1.0)
					_side(b, x, y, d, nh * S, (h - 1) * S, body, SIDE_AO, 0.9)
				else:
					_side(b, x, y, d, nh * S, top, lip, SIDE_AO, 1.0)


## Roads as strips on top of their cells: a centre square plus an arm toward
## every neighbouring road cell (narrower than a cell, so the ground shows).
static func _road_strips(t: RegionTerrain, b: Builder, r: Rect2i) -> void:
	var W := RegionTerrain.W
	for y in range(r.position.y, mini(r.end.y, RegionTerrain.H)):
		for x in range(r.position.x, mini(r.end.x, W)):
			var i := y * W + x
			var kind := t.road[i]
			if kind == RegionTerrain.R_NONE or t.water[i] > 0:
				continue
			var top := t.height[i] * RegionTerrain.STEP + ROAD_LIFT
			var hw: float = ROAD_WIDTH[kind] * 0.5
			var col: Color = ROAD_COL[kind] * (0.97 + _hash01(x, y) * 0.05)
			col.a = 1.0
			var k := [col, col, col, col]
			var cx := x + 0.5
			var cz := y + 0.5
			b.quad(face_corners(Vector3(cx - hw, top, cz - hw), Vector3(cx + hw, top, cz + hw), 2), NORMALS[2], k, Vector2.ZERO)
			for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n := Vector2i(x, y) + dir
				if not RegionTerrain.in_bounds(n) or t.road[n.y * W + n.x] == RegionTerrain.R_NONE:
					continue
				var lo: Vector3
				var hi: Vector3
				match dir:
					Vector2i(1, 0):
						lo = Vector3(cx + hw, top, cz - hw)
						hi = Vector3(x + 1.0, top, cz + hw)
					Vector2i(-1, 0):
						lo = Vector3(x, top, cz - hw)
						hi = Vector3(cx - hw, top, cz + hw)
					Vector2i(0, 1):
						lo = Vector3(cx - hw, top, cz + hw)
						hi = Vector3(cx + hw, top, y + 1.0)
					_:
						lo = Vector3(cx - hw, top, y)
						hi = Vector3(cx + hw, top, cz - hw)
				b.quad(face_corners(lo, hi, 2), NORMALS[2], k, Vector2.ZERO)


static func _side(b: Builder, x: int, y: int, d: int, y0: float, y1: float, col: Color, ao_lo: float, ao_hi: float) -> void:
	var c := face_corners(Vector3(x, y0, y), Vector3(x + 1, y1, y + 1), d)
	var k := []
	for p in c:
		k.append(Color(col.r, col.g, col.b, ao_lo if (p as Vector3).y <= y0 + 0.001 else ao_hi))
	b.quad(c, NORMALS[d], k, Vector2(0.0, 1.0))


static func _occ(t: RegionTerrain, x: int, y: int, h: int) -> int:
	if x < 0 or y < 0 or x >= RegionTerrain.W or y >= RegionTerrain.H:
		return 0
	return 1 if t.height[y * RegionTerrain.W + x] > h else 0


static func _ao(s1: int, s2: int, c: int) -> int:
	return 0 if (s1 == 1 and s2 == 1) else 3 - (s1 + s2 + c)


static func _water(t: RegionTerrain, b: Builder) -> void:
	var W := RegionTerrain.W
	var H := RegionTerrain.H
	var S := RegionTerrain.STEP
	# per grid vertex: depth, shore, sea (averaged over the four cells around it)
	var vw := W + 1
	var depth := PackedFloat32Array()
	var shore := PackedFloat32Array()
	var sea := PackedFloat32Array()
	depth.resize(vw * (H + 1))
	shore.resize(vw * (H + 1))
	sea.resize(vw * (H + 1))
	for vy in H + 1:
		for vx in W + 1:
			var dsum := 0.0
			var ssum := 0.0
			var n := 0
			var dry := 0.0
			for c: Vector2i in [Vector2i(vx - 1, vy - 1), Vector2i(vx, vy - 1), Vector2i(vx - 1, vy), Vector2i(vx, vy)]:
				if not RegionTerrain.in_bounds(c):
					continue
				var i := c.y * W + c.x
				if t.water[i] > 0:
					dsum += clampf((t.water[i] - t.height[i]) / 5.0, 0.0, 1.0)
					ssum += 1.0 if t.waterkind[i] == 2 else 0.0
					n += 1
				else:
					dry = 1.0
			var vi := vy * vw + vx
			depth[vi] = dsum / maxf(n, 1)
			sea[vi] = ssum / maxf(n, 1)
			shore[vi] = dry
	for y in H:
		for x in W:
			var i := y * W + x
			var w := t.water[i]
			if w <= 0:
				continue
			var top := w * S
			var lo := Vector3(x, top, y)
			var hi := Vector3(x + 1, top, y + 1)
			var c := face_corners(lo, hi, 2)
			var k := []
			for p in c:
				var vi := int(p.z) * vw + int(p.x)
				k.append(Color(depth[vi], shore[vi], sea[vi], 1.0))
			b.quad(c, NORMALS[2], k, Vector2(0.0, 0.0))
			for dd in [[0, Vector2i(1, 0)], [1, Vector2i(-1, 0)], [4, Vector2i(0, 1)], [5, Vector2i(0, -1)]]:
				var n: Vector2i = Vector2i(x, y) + dd[1]
				if not RegionTerrain.in_bounds(n):
					continue
				var nw := t.water[n.y * W + n.x]
				if nw > 0 and nw < w:
					var fc := face_corners(Vector3(x, nw * S, y), Vector3(x + 1, top, y + 1), dd[0])
					var fk := Color(0.3, 1.0, 0.0, 1.0)
					b.quad(fc, NORMALS[dd[0]], [fk, fk, fk, fk], Vector2(0.0, 1.0))


# --- trees -------------------------------------------------------------------------

## {meshes: [ArrayMesh x5], faces: [int x5]}: 0 tall pine, 1 small pine,
## 2 broadleaf, 3 bush, 4 bare tree. About one world unit tall at scale 1.
static func tree_meshes() -> Dictionary:
	if _cache.has("trees"):
		return _cache["trees"]
	var trunk := Color(0.62, 0.52, 0.44)
	var specs := [
		[[0.05, 0.0, 0.2, trunk], [0.3, 0.14, 0.4, Color(0.9, 0.9, 0.9)], [0.23, 0.4, 0.62, Color(0.97, 0.97, 0.97)], [0.13, 0.62, 0.9, Color.WHITE]],
		[[0.05, 0.0, 0.14, trunk], [0.24, 0.1, 0.34, Color(0.92, 0.92, 0.92)], [0.15, 0.34, 0.54, Color.WHITE], [0.06, 0.54, 0.64, Color.WHITE]],
		[[0.05, 0.0, 0.28, trunk], [0.28, 0.24, 0.56, Color(0.92, 0.92, 0.92)], [0.2, 0.56, 0.7, Color.WHITE], [0.13, 0.32, 0.5, Color(0.88, 0.88, 0.88), Vector2(0.22, 0.05)]],
		[[0.22, 0.0, 0.22, Color(0.9, 0.9, 0.9)], [0.13, 0.22, 0.32, Color.WHITE]],
		[[0.04, 0.0, 0.62, Color.WHITE], [0.025, 0.3, 0.5, Color.WHITE, Vector2(0.12, 0.0)], [0.025, 0.4, 0.58, Color.WHITE, Vector2(-0.1, 0.06)], [0.02, 0.5, 0.66, Color.WHITE, Vector2(0.0, -0.11)]],
	]
	var meshes := []
	var faces := []
	for spec in specs:
		var b := Builder.new()
		for part in spec:
			var r: float = part[0]
			var off: Vector2 = part[4] if part.size() > 4 else Vector2.ZERO
			add_box(b, Vector3(off.x - r, part[1], off.y - r), Vector3(off.x + r, part[2], off.y + r), part[3], 0.0, 0.55, part[3] != trunk)
		meshes.append(b.mesh())
		faces.append(b.faces())
	var out := {"meshes": meshes, "faces": faces}
	_cache["trees"] = out
	return out
