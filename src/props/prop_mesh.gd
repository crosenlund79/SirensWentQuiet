class_name PropMesh
extends RefCounted
## Small flat-shaded mesh builder for the hybrid props (forked from
## Experiment 001's modular kit builder). Every vertex carries:
##   COLOR.rgb  sRGB tint, COLOR.a  wear (0..1: grime, scuffs),
##   UV2.x      material layer (PropMaterials.L_*),
##   UV2.y      flags: 1 = thin two-sided sheet (leaf, tarp, paper),
##                     2 = grain runs vertically (upright planks),
##                     4 = casts no shadow (thin parts right next to a light).
## Faces are given with an outward normal; winding is fixed up automatically.

const FLAG_THIN := 1
const FLAG_GRAIN_V := 2
const FLAG_NO_SHADOW := 4

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var cols := PackedColorArray()
var uv2s := PackedVector2Array()

## Applied to everything added (save and restore it around local frames).
var xf := Transform3D.IDENTITY
var layer := 0
var color := Color.WHITE
var wear := 0.0
## Added to every vertex's wear (damage and outdoor exposure).
var wear_bias := 0.0
var thin := false
var grain_v := false
var no_shadow := false


func set_mat(l: int, c: Color = Color.WHITE, w: float = -1.0) -> PropMesh:
	layer = l
	color = c
	if w >= 0.0:
		wear = w
	return self


func is_empty() -> bool:
	return verts.is_empty()


func _flags() -> float:
	return float((FLAG_THIN if thin else 0) | (FLAG_GRAIN_V if grain_v else 0) | (FLAG_NO_SHADOW if no_shadow else 0))


func tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3 = Vector3.ZERO) -> void:
	a = xf * a
	b = xf * b
	c = xf * c
	var cr := (b - a).cross(c - a)
	if cr.length_squared() < 1e-14:
		return
	if n == Vector3.ZERO:
		n = cr.normalized()
	else:
		n = (xf.basis * n).normalized()
	# Godot front faces are clockwise as seen from the normal side.
	if cr.dot(n) > 0.0:
		var t := b
		b = c
		c = t
	verts.append(a)
	verts.append(b)
	verts.append(c)
	var col := Color(color.r, color.g, color.b, clampf(wear + wear_bias, 0.0, 1.0))
	var uv := Vector2(layer, _flags())
	for i in 3:
		norms.append(n)
		cols.append(col)
		uv2s.append(uv)


## Convex polygon (fan) with outward normal n.
func poly(pts: PackedVector3Array, n: Vector3 = Vector3.ZERO) -> void:
	if n == Vector3.ZERO and pts.size() >= 3:
		n = (pts[1] - pts[0]).cross(pts[2] - pts[0]).normalized()
	for i in range(1, pts.size() - 1):
		tri(pts[0], pts[i], pts[i + 1], n)


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3 = Vector3.ZERO) -> void:
	if n == Vector3.ZERO:
		n = (b - a).cross(c - a).normalized()
	tri(a, b, c, n)
	tri(a, c, d, n)


## Thin two-sided sheet (leaves, tarp, paper): a convex polygon flagged so the
## shader lights both sides instead of drawing the dark section colour.
func sheet(pts: PackedVector3Array, n: Vector3 = Vector3.ZERO) -> void:
	var keep := thin
	thin = true
	poly(pts, n)
	thin = keep


## Axis-aligned box from min corner to max corner. `skip` lists faces to omit
## ("+x", "-x", "+y", "-y", "+z", "-z").
func box(lo: Vector3, hi: Vector3, skip: Array = []) -> void:
	_box(lo, hi, skip, 1.0)


## The inside of a box (faces point inward): basins, tubs, open crates.
func box_inside(lo: Vector3, hi: Vector3, skip: Array = []) -> void:
	_box(lo, hi, skip, -1.0)


func _box(lo: Vector3, hi: Vector3, skip: Array, s: float) -> void:
	var x0 := lo.x
	var y0 := lo.y
	var z0 := lo.z
	var x1 := hi.x
	var y1 := hi.y
	var z1 := hi.z
	if not "+x" in skip:
		quad(Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x1, y0, z1), Vector3.RIGHT * s)
	if not "-x" in skip:
		quad(Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), Vector3.LEFT * s)
	if not "+y" in skip:
		quad(Vector3(x0, y1, z0), Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3.UP * s)
	if not "-y" in skip:
		quad(Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1), Vector3.DOWN * s)
	if not "+z" in skip:
		quad(Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3.BACK * s)
	if not "-z" in skip:
		quad(Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y0, z0), Vector3.FORWARD * s)


## Box by centre and size.
func cbox(center: Vector3, size: Vector3, skip: Array = []) -> void:
	box(center - size * 0.5, center + size * 0.5, skip)


## Oriented box: local transform t applied on top of xf.
func obox(t: Transform3D, size: Vector3, skip: Array = []) -> void:
	var keep := xf
	xf = xf * t
	cbox(Vector3.ZERO, size, skip)
	xf = keep


## Oriented chamfered box.
func ochamfer(t: Transform3D, size: Vector3, r: float) -> void:
	var keep := xf
	xf = xf * t
	chamfer_box(-size * 0.5, size * 0.5, r)
	xf = keep


## Box with chamfered edges (r = chamfer size). Reads as soft low-poly.
## `skip_bottom` omits only the flat underside.
func chamfer_box(lo: Vector3, hi: Vector3, r: float, skip_bottom := true) -> void:
	var c := (lo + hi) * 0.5
	var h := (hi - lo) * 0.5
	r = minf(r, minf(h.x, minf(h.y, h.z)) * 0.95)
	if r <= 0.0005:
		box(lo, hi, ["-y"] if skip_bottom else [])
		return
	var hi_in := h - Vector3(r, r, r)
	var p := {}
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			for sz in [-1, 1]:
				var k := "%d%d%d" % [sx, sy, sz]
				p[k + "x"] = c + Vector3(sx * h.x, sy * hi_in.y, sz * hi_in.z)
				p[k + "y"] = c + Vector3(sx * hi_in.x, sy * h.y, sz * hi_in.z)
				p[k + "z"] = c + Vector3(sx * hi_in.x, sy * hi_in.y, sz * h.z)
	for sx in [-1, 1]:
		_cface(c, [p["%d-1-1x" % sx], p["%d1-1x" % sx], p["%d11x" % sx], p["%d-11x" % sx]])
	for sy in [-1, 1]:
		if sy < 0 and skip_bottom:
			continue
		_cface(c, [p["-1%d-1y" % sy], p["1%d-1y" % sy], p["1%d1y" % sy], p["-1%d1y" % sy]])
	for sz in [-1, 1]:
		_cface(c, [p["-1-1%dz" % sz], p["1-1%dz" % sz], p["11%dz" % sz], p["-11%dz" % sz]])
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			_cface(c, [p["%d%d-1x" % [sx, sy]], p["%d%d1x" % [sx, sy]], p["%d%d1y" % [sx, sy]], p["%d%d-1y" % [sx, sy]]])
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_cface(c, [p["%d-1%dx" % [sx, sz]], p["%d1%dx" % [sx, sz]], p["%d1%dz" % [sx, sz]], p["%d-1%dz" % [sx, sz]]])
	for sy in [-1, 1]:
		for sz in [-1, 1]:
			_cface(c, [p["-1%d%dy" % [sy, sz]], p["1%d%dy" % [sy, sz]], p["1%d%dz" % [sy, sz]], p["-1%d%dz" % [sy, sz]]])
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			for sz in [-1, 1]:
				var k := "%d%d%d" % [sx, sy, sz]
				_cface(c, [p[k + "x"], p[k + "y"], p[k + "z"]])


func _cface(center: Vector3, pts: Array) -> void:
	var a: Vector3 = pts[0]
	var b: Vector3 = pts[1]
	var cc: Vector3 = pts[2]
	var n := (b - a).cross(cc - a)
	if n.length_squared() < 1e-12 and pts.size() > 3:
		n = (cc - a).cross(pts[3] - a)
	n = n.normalized()
	var mid := Vector3.ZERO
	for q in pts:
		mid += q
	mid /= pts.size()
	if n.dot(mid - center) < 0.0:
		n = -n
	poly(PackedVector3Array(pts), n)


## Vertical prism / frustum (low-poly cylinder) around the local Y axis.
func cylinder(base: Vector3, r0: float, r1: float, h: float, seg := 8, caps := true, smooth := false) -> void:
	var top := base + Vector3(0, h, 0)
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var p0 := base + d0 * r0
		var p1 := base + d1 * r0
		var q0 := top + d0 * r1
		var q1 := top + d1 * r1
		var nm := (d0 + d1).normalized()
		if smooth:
			_smooth_quad(p0, p1, q1, q0, d0, d1)
		else:
			quad(p0, p1, q1, q0, nm)
		if caps:
			if r1 > 0.0:
				tri(top, q0, q1, Vector3.UP)
			if r0 > 0.0:
				tri(base, p1, p0, Vector3.DOWN)


## The inside wall of an open vessel (faces point inward), plus its floor.
func cylinder_inside(base: Vector3, r0: float, r1: float, h: float, seg := 10) -> void:
	var top := base + Vector3(0, h, 0)
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		quad(base + d0 * r0, base + d1 * r0, top + d1 * r1, top + d0 * r1, -(d0 + d1).normalized())
		tri(base, base + d0 * r0, base + d1 * r0, Vector3.UP)


func _smooth_quad(p0: Vector3, p1: Vector3, q1: Vector3, q0: Vector3, n0: Vector3, n1: Vector3) -> void:
	var w0 := xf * p0
	var w1 := xf * p1
	var w2 := xf * q1
	var w3 := xf * q0
	var m0 := (xf.basis * n0).normalized()
	var m1 := (xf.basis * n1).normalized()
	var col := Color(color.r, color.g, color.b, clampf(wear + wear_bias, 0.0, 1.0))
	var uv := Vector2(layer, _flags())
	# clockwise when seen from outside: p0, q0, q1 / p0, q1, p1
	for v in [[w0, m0], [w2, m1], [w3, m0], [w0, m0], [w1, m1], [w2, m1]]:
		verts.append(v[0])
		norms.append(v[1])
		cols.append(col)
		uv2s.append(uv)


## Cylinder between two arbitrary points (limbs, branches, poles, handles).
func tube(a: Vector3, b: Vector3, r0: float, r1: float, seg := 6, caps := true) -> void:
	var dir := b - a
	var h := dir.length()
	if h < 1e-5:
		return
	var y := dir / h
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	var keep := xf
	xf = xf * Transform3D(Basis(x, y, z), a)
	cylinder(Vector3.ZERO, r0, r1, h, seg, caps)
	xf = keep


## Tubes along a polyline (ropes, handles, wires).
func polyline(pts: Array, r: float, seg := 5) -> void:
	for i in range(pts.size() - 1):
		tube(pts[i], pts[i + 1], r, r, seg, false)


## Low-poly sphere-ish blob (UV sphere with few rings), scaled per axis.
func blob(center: Vector3, radii: Vector3, rings := 4, seg := 7) -> void:
	for j in rings:
		var t0 := PI * j / rings - PI * 0.5
		var t1 := PI * (j + 1) / rings - PI * 0.5
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			var p00 := center + Vector3(cos(t0) * cos(a0), sin(t0), cos(t0) * sin(a0)) * radii
			var p01 := center + Vector3(cos(t0) * cos(a1), sin(t0), cos(t0) * sin(a1)) * radii
			var p10 := center + Vector3(cos(t1) * cos(a0), sin(t1), cos(t1) * sin(a0)) * radii
			var p11 := center + Vector3(cos(t1) * cos(a1), sin(t1), cos(t1) * sin(a1)) * radii
			var mid := (p00 + p01 + p10 + p11) * 0.25
			var n := (mid - center).normalized()
			if j == 0:
				tri(p00, p10, p11, n)
			elif j == rings - 1:
				tri(p00, p01, p10, n)
			else:
				quad(p00, p01, p11, p10, n)


## 2D polygon (x, y in the plane) at depth z, facing +z (nz = 1) or -z (nz = -1).
## Triangulated with Geometry2D; works for any simple polygon.
func flat_poly(pts: PackedVector2Array, z: float, nz: float) -> void:
	var idx := Geometry2D.triangulate_polygon(pts)
	var n := Vector3(0, 0, nz)
	for i in range(0, idx.size(), 3):
		var a := pts[idx[i]]
		var b := pts[idx[i + 1]]
		var c := pts[idx[i + 2]]
		tri(Vector3(a.x, a.y, z), Vector3(b.x, b.y, z), Vector3(c.x, c.y, z), n)


## A 2D polygon extruded along z between z0 and z1 (slabs with ragged edges).
func extrude(pts: PackedVector2Array, z0: float, z1: float) -> void:
	flat_poly(pts, z1, 1.0)
	flat_poly(pts, z0, -1.0)
	var n := pts.size()
	# outward side normals for a counter-clockwise or clockwise outline
	var area := 0.0
	for i in n:
		area += pts[i].x * pts[(i + 1) % n].y - pts[(i + 1) % n].x * pts[i].y
	var s := 1.0 if area > 0.0 else -1.0
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var e := b - a
		if e.length_squared() < 1e-10:
			continue
		var out := Vector3(e.y, -e.x, 0).normalized() * s
		quad(Vector3(a.x, a.y, z0), Vector3(b.x, b.y, z0), Vector3(b.x, b.y, z1), Vector3(a.x, a.y, z1), out)


func commit(mesh: ArrayMesh = null) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func triangle_count() -> int:
	return verts.size() / 3
