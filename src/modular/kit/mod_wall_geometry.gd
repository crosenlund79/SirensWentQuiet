class_name ModWallGeometry
extends RefCounted
## Builds the meshes for one wall module in each damage state.
##
## Module space: x along the wall (0..length), y up (0..2.6), z across the
## thickness with side A at +z and side B at -z. Intact meshes are shared
## between modules of the same shape; damaged, heavily damaged and destroyed
## meshes are built per module (seeded), centred where the module was hit.
##
## A damaged wall is modelled as two skins (exterior siding + sheathing, or
## drywall) around a stud cavity, optionally insulated, so the holes reveal
## believable construction rather than a solid block.

const M := preload("res://src/modular/kit/mod_materials.gd")
const H := HousePlan.WALL_HEIGHT
const SIDING_SKIN := 0.035
const DRYWALL_SKIN := 0.016
const STUD_W := 0.045
const PLATE_H := 0.045
const TOP_PLATE_H := 0.09

static var _shared := {}


# --- public ---------------------------------------------------------------------------

## Shared intact mesh for (kind, length, thickness, outside side, sill).
static func intact(w: ModWall) -> ArrayMesh:
	var key := "%d|%.3f|%.2f|%d|%.2f|%.2f|%s" % [w.kind, w.length, w.thickness, w.outside, w.sill, w.head, w.door_style]
	if _shared.has(key):
		return _shared[key]
	var mm := ModMesh.new()
	match w.kind:
		ModWall.Kind.SOLID:
			_solid_box(mm, w)
		ModWall.Kind.WINDOW:
			_window_intact(mm, w)
		ModWall.Kind.DOOR:
			_door(mm, w)
	var mesh := mm.commit()
	_shared[key] = mesh
	return mesh


static func glass_mesh(w: ModWall) -> ArrayMesh:
	var key := "glass|%.3f|%.2f|%d|%.2f" % [w.length, w.thickness, w.outside, w.sill]
	if _shared.has(key):
		return _shared[key]
	var o := _opening(w)
	var zg := _glass_z(w)
	var mm := ModMesh.new()
	mm.set_mat(M.L_MIRROR)
	var f := 0.045
	mm.quad(Vector3(o.position.x + f, o.position.y + f, zg), Vector3(o.end.x - f, o.position.y + f, zg),
		Vector3(o.end.x - f, o.end.y - f, zg), Vector3(o.position.x + f, o.end.y - f, zg), Vector3.BACK)
	var mesh := mm.commit()
	_shared[key] = mesh
	return mesh


## Intact geometry plus loose boards, chipped plaster and a missing board.
static func damaged(w: ModWall) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = w.seed * 31 + 7
	var mm := ModMesh.new()
	match w.kind:
		ModWall.Kind.SOLID:
			_solid_box(mm, w)
		ModWall.Kind.WINDOW:
			_window_intact(mm, w, true)
	var t := w.thickness
	for s in [0, 1]:
		var nz := 1.0 if s == 0 else -1.0
		var z := nz * (t * 0.5 + 0.002)
		var avoid := _opening(w) if w.kind == ModWall.Kind.WINDOW else Rect2()
		if s == w.outside:
			# one or two boards knocked off, one hanging loose
			var board := 2.0 / 14.0
			var count := 2
			for i in count:
				var bx := floorf((w.world_x0 + rng.randf_range(0.1, w.length - 0.25)) / board) * board - w.world_x0
				bx = clampf(bx, 0.02, w.length - board - 0.02)
				var y0 := rng.randf_range(0.35, 0.9)
				var y1 := y0 + rng.randf_range(0.5, 1.1)
				if avoid.size.x > 0.0 and y1 > avoid.position.y:
					y1 = avoid.position.y - 0.05
					y0 = minf(y0, y1 - 0.3)
				# bare sheathing where the board was
				mm.set_mat(M.L_TIMBER, M.SHEATHING_COLOR.darkened(0.25), s)
				mm.quad(Vector3(bx, y0, z), Vector3(bx + board, y0, z), Vector3(bx + board, y1, z), Vector3(bx, y1, z), Vector3(0, 0, nz))
				if i == 0:
					# the loose board hangs from its top nail, twisted outward
					var pivot := Vector3(bx + board * 0.5, y1 - 0.03, z + nz * 0.012)
					var tilt := rng.randf_range(0.35, 0.6) * (1.0 if rng.randf() < 0.5 else -1.0)
					var b := Basis(Vector3.FORWARD, tilt) * Basis(Vector3.RIGHT, -nz * rng.randf_range(0.25, 0.45))
					var size := Vector3(board * 0.92, (y1 - y0) * rng.randf_range(0.75, 1.0), 0.02)
					mm.set_mat(M.L_SIDING, Color(0.92, 0.94, 0.95), s)
					mm.obox(Transform3D(b, pivot) * Transform3D(Basis.IDENTITY, Vector3(0, -size.y * 0.5, 0)), size)
		else:
			# chipped plaster patches revealing grey gypsum
			for i in rng.randi_range(2, 3):
				var c := Vector2(rng.randf_range(0.15, w.length - 0.15), rng.randf_range(0.3, 2.2))
				if avoid.size.x > 0.0 and avoid.grow(0.12).has_point(c):
					continue
				var pts := _jagged(c, Vector2(rng.randf_range(0.05, 0.12), rng.randf_range(0.04, 0.09)), 9, rng, 0.35)
				mm.set_mat(M.L_GYPSUM, Color(0.72, 0.71, 0.68), s)
				mm.flat_poly(pts, z, nz)
	# a chunk knocked out of the wall top
	mm.set_mat(M.L_GYPSUM, Color(0.6, 0.58, 0.55), 0)
	var cx := rng.randf_range(0.2, w.length - 0.3)
	mm.cbox(Vector3(cx, H - 0.025, 0), Vector3(rng.randf_range(0.08, 0.16), 0.06, t * 0.6))
	return mm.commit()


## Big jagged hole through both skins around `center` (module x, y).
static func heavy(w: ModWall, center: Vector2) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = w.seed * 131 + 3
	var L := w.length
	var mx := 0.13
	center.x = clampf(center.x, mx + 0.3, L - mx - 0.3) if L > 0.9 else L * 0.5
	center.y = clampf(center.y, 0.62, 1.55)
	var ha := _jagged(center, Vector2(0.36, 0.46) * minf(1.0, L), 20, rng, 0.3)
	var hb := _jagged(center + Vector2(rng.randf_range(-0.08, 0.08), rng.randf_range(-0.12, 0.12)), Vector2(0.27, 0.36) * minf(1.0, L), 18, rng, 0.3)
	var hi := _jagged(center + Vector2(rng.randf_range(-0.05, 0.05), rng.randf_range(-0.05, 0.05)), Vector2(0.3, 0.4) * minf(1.0, L), 14, rng, 0.45)
	var grime := PackedVector2Array()
	for p in ha:
		grime.append(center + (p - center) * rng.randf_range(1.22, 1.4))
	var lim := Rect2(mx, 0.1, L - 2 * mx, H - 0.3)
	ha = _clip_to(ha, lim)
	hb = _clip_to(hb, lim)
	hi = _clip_to(hi, lim)
	if w.kind == ModWall.Kind.WINDOW:
		var o := _rect_poly(_opening(w))
		ha = _merge(ha, o)
		hb = _merge(hb, o)
		hi = _merge(hi, o)
	var mm := ModMesh.new()
	_skins(mm, w, ha, hb)
	_cavity(mm, w, rng, hi, center, false)
	# dirt and soot around the outside of the hole
	if w.kind != ModWall.Kind.WINDOW:
		for s in [0, 1]:
			var nz := 1.0 if s == 0 else -1.0
			var col := Color(0.5, 0.46, 0.4) if s == w.outside else Color(0.62, 0.6, 0.57)
			mm.set_mat(_side_layer(w, s), col, s)
			var hole := ha if s == 0 else hb
			var g := grime if s == 0 else _scaled(hb, 1.3)
			_ring(mm, _clip_to(g, Rect2(0.01, 0.01, L - 0.02, H - 0.02)), hole, nz * (w.thickness * 0.5 + 0.0015), nz)
	_cap_and_ends(mm, w)
	if w.kind == ModWall.Kind.WINDOW:
		# a twisted piece of window frame still hanging in the opening
		var o := _opening(w)
		mm.set_mat(M.L_METAL, M.FRAME_COLOR, 0)
		var zf := _glass_z(w)
		var pivot := Vector3(o.position.x + 0.03, o.end.y - 0.03, zf)
		mm.obox(Transform3D(Basis(Vector3.FORWARD, rng.randf_range(0.15, 0.4)), pivot) * Transform3D(Basis.IDENTITY, Vector3(0, -0.4, 0)), Vector3(0.045, 0.8, 0.05))
		mm.cbox(Vector3((o.position.x + o.end.x) * 0.5, o.end.y - 0.025, zf), Vector3(o.size.x, 0.05, 0.05))
	return mm.commit()


## Only stubs remain: jagged edges, a broken top plate with hanging studs,
## torn insulation. The opening is at least 1.9 m tall and ~0.8 m wide.
static func destroyed(w: ModWall) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = w.seed * 71 + 11
	var L := w.length
	var hole_a := _breach_outline(L, rng)
	var hole_b := _breach_outline(L, rng)
	var mm := ModMesh.new()
	_skins(mm, w, hole_a, hole_b)
	_cavity(mm, w, rng, PackedVector2Array(), Vector2(L * 0.5, 1.0), true)
	_cap_and_ends(mm, w)
	return mm.commit()


## Low rubble on both sides of a destroyed module (no collision).
static func rubble(w: ModWall) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = w.seed * 17 + 5
	var mm := ModMesh.new()
	var L := w.length
	var t := w.thickness
	# dust drifts
	mm.set_mat(M.L_SOIL, Color(0.62, 0.6, 0.56))
	for s in [-1.0, 1.0]:
		var pts := PackedVector3Array()
		var c := Vector3(L * 0.5 + rng.randf_range(-0.15, 0.15), 0.0, s * (t * 0.5 + 0.18))
		for k in 9:
			var a := TAU * k / 9.0
			pts.append(c + Vector3(cos(a) * rng.randf_range(0.35, 0.55), 0.0, sin(a) * rng.randf_range(0.15, 0.32)))
		var top := c + Vector3(0, rng.randf_range(0.05, 0.1), 0)
		for k in 9:
			mm.tri(pts[k], pts[(k + 1) % 9], top, Vector3.ZERO)
	# chunks: boards, drywall plates, studs, insulation tufts
	var outside := w.outside
	for i in 22:
		var s := -1.0 if rng.randf() < 0.5 else 1.0
		var side_out := (s > 0.0 and outside == 0) or (s < 0.0 and outside == 1)
		var p := Vector3(rng.randf_range(-0.1, L + 0.1), 0.0, s * (t * 0.5 + rng.randf_range(0.02, 0.75)))
		var kind := rng.randi_range(0, 3)
		var size: Vector3
		match kind:
			0:
				if side_out:
					mm.set_mat(M.L_SIDING, Color(0.95, 0.96, 0.97))
				else:
					mm.set_mat(M.L_GYPSUM, M.GYPSUM_COLOR.darkened(rng.randf_range(0.0, 0.15)))
				size = Vector3(rng.randf_range(0.12, 0.4), 0.02, rng.randf_range(0.08, 0.16))
			1:
				mm.set_mat(M.L_TIMBER, M.TIMBER_COLOR.darkened(rng.randf_range(0.0, 0.2)))
				size = Vector3(rng.randf_range(0.2, 0.55), 0.045, 0.09)
			2:
				mm.set_mat(M.L_GYPSUM, M.GYPSUM_COLOR.darkened(rng.randf_range(0.05, 0.25)))
				size = Vector3(rng.randf_range(0.05, 0.12), rng.randf_range(0.03, 0.07), rng.randf_range(0.05, 0.1))
			3:
				if w.exterior:
					mm.set_mat(M.L_INSULATION, M.INSULATION_COLOR)
					size = Vector3(rng.randf_range(0.12, 0.25), rng.randf_range(0.04, 0.08), rng.randf_range(0.1, 0.2))
				else:
					mm.set_mat(M.L_TIMBER, M.SHEATHING_COLOR)
					size = Vector3(rng.randf_range(0.06, 0.14), 0.02, rng.randf_range(0.05, 0.1))
		var b := Basis(Vector3.UP, rng.randf_range(0, TAU)) * Basis(Vector3.RIGHT, rng.randf_range(-0.25, 0.25))
		p.y = size.y * 0.5 + rng.randf_range(0.0, 0.03)
		mm.obox(Transform3D(b, p), size, ["-y"])
	return mm.commit()


# --- intact pieces -------------------------------------------------------------------

static func _side_layer(w: ModWall, s: int) -> int:
	return M.L_SIDING if s == w.outside else M.L_PAINT


static func _solid_box(mm: ModMesh, w: ModWall) -> void:
	var L := w.length
	var t := w.thickness * 0.5
	for s in [0, 1]:
		var nz := 1.0 if s == 0 else -1.0
		mm.set_mat(_side_layer(w, s), Color.WHITE, s)
		mm.quad(Vector3(0, 0, nz * t), Vector3(L, 0, nz * t), Vector3(L, H, nz * t), Vector3(0, H, nz * t), Vector3(0, 0, nz))
	_cap_and_ends(mm, w)


static func _cap_and_ends(mm: ModMesh, w: ModWall) -> void:
	var L := w.length
	var t := w.thickness * 0.5
	mm.set_mat(M.L_CAP, Color.WHITE, 0)
	mm.quad(Vector3(0, H, -t), Vector3(L, H, -t), Vector3(L, H, t), Vector3(0, H, t), Vector3.UP)
	mm.set_mat(M.L_TIMBER, M.SHEATHING_COLOR.lightened(0.1), 0)
	mm.quad(Vector3(0, 0, -t), Vector3(0, 0, t), Vector3(0, H, t), Vector3(0, H, -t), Vector3.LEFT)
	mm.quad(Vector3(L, 0, -t), Vector3(L, H, -t), Vector3(L, H, t), Vector3(L, 0, t), Vector3.RIGHT)


static func _opening(w: ModWall) -> Rect2:
	var inset := 0.05
	return Rect2(inset, w.sill, w.length - 2 * inset, w.head - w.sill)


static func _glass_z(w: ModWall) -> float:
	# frame and glass sit toward the outside face
	var t := w.thickness * 0.5
	var out_sign := 1.0 if w.outside == 0 else -1.0
	if w.outside < 0:
		return 0.0
	return out_sign * (t - 0.08)


static func _window_intact(mm: ModMesh, w: ModWall, skip_frame := false) -> void:
	var L := w.length
	var t := w.thickness * 0.5
	var o := _opening(w)
	var hole := _rect_poly(o)
	var inside := 1 - w.outside if w.outside >= 0 else 0
	for s in [0, 1]:
		var nz := 1.0 if s == 0 else -1.0
		mm.set_mat(_side_layer(w, s), Color.WHITE, s)
		_face_minus(mm, L, 0.0, H, hole, nz * t, nz)
	# reveals: painted jambs and head, white window board, metal outside sill
	var x0 := o.position.x
	var x1 := o.end.x
	var y0 := o.position.y
	var y1 := o.end.y
	mm.set_mat(M.L_PAINT, Color.WHITE, inside)
	mm.quad(Vector3(x0, y0, -t), Vector3(x0, y1, -t), Vector3(x0, y1, t), Vector3(x0, y0, t), Vector3.RIGHT)
	mm.quad(Vector3(x1, y0, -t), Vector3(x1, y0, t), Vector3(x1, y1, t), Vector3(x1, y1, -t), Vector3.LEFT)
	mm.quad(Vector3(x0, y1, -t), Vector3(x0, y1, t), Vector3(x1, y1, t), Vector3(x1, y1, -t), Vector3.DOWN)
	var in_sign := 1.0 if inside == 0 else -1.0
	var out_sign := -in_sign
	# window board (inside) and sill flashing (outside)
	mm.set_mat(M.L_TRIM, M.TRIM_COLOR, inside)
	mm.box(Vector3(x0 - 0.02, y0 - 0.02, minf(0.0, in_sign * (t + 0.03))), Vector3(x1 + 0.02, y0 + 0.01, maxf(0.0, in_sign * (t + 0.03))))
	if w.outside >= 0:
		mm.set_mat(M.L_METAL, Color(0.5, 0.52, 0.54), w.outside)
		var zs0 := out_sign * t * 0.1
		var zs1 := out_sign * (t + 0.05)
		mm.box(Vector3(x0 - 0.03, y0 - 0.04, minf(zs0, zs1)), Vector3(x1 + 0.03, y0 + 0.005, maxf(zs0, zs1)))
	if skip_frame:
		return
	# slim charcoal frame with a transom bar
	var zf := _glass_z(w)
	var f := 0.045
	var d := 0.06
	mm.set_mat(M.L_METAL, M.FRAME_COLOR, 0)
	mm.box(Vector3(x0, y0, zf - d * 0.5), Vector3(x0 + f, y1, zf + d * 0.5))
	mm.box(Vector3(x1 - f, y0, zf - d * 0.5), Vector3(x1, y1, zf + d * 0.5))
	mm.box(Vector3(x0, y0, zf - d * 0.5), Vector3(x1, y0 + f, zf + d * 0.5))
	mm.box(Vector3(x0, y1 - f, zf - d * 0.5), Vector3(x1, y1, zf + d * 0.5))
	if o.size.y > 0.9:
		var ty := y1 - 0.32
		mm.box(Vector3(x0, ty - 0.02, zf - d * 0.4), Vector3(x1, ty + 0.02, zf + d * 0.4))


static func _door(mm: ModMesh, w: ModWall) -> void:
	var L := w.length
	var t := w.thickness * 0.5
	var hd := HousePlan.DOOR_HEIGHT
	for s in [0, 1]:
		var nz := 1.0 if s == 0 else -1.0
		mm.set_mat(_side_layer(w, s), Color.WHITE, s)
		mm.quad(Vector3(0, hd, nz * t), Vector3(L, hd, nz * t), Vector3(L, H, nz * t), Vector3(0, H, nz * t), Vector3(0, 0, nz))
	_cap_and_ends(mm, w)
	# soffit, jamb linings, threshold
	mm.set_mat(M.L_TRIM, M.TRIM_COLOR, 0)
	mm.quad(Vector3(0, hd, -t), Vector3(0, hd, t), Vector3(L, hd, t), Vector3(L, hd, -t), Vector3.DOWN)
	mm.box(Vector3(0.0, 0.0, -t), Vector3(0.025, hd, t))
	mm.box(Vector3(L - 0.025, 0.0, -t), Vector3(L, hd, t))
	mm.set_mat(M.L_METAL if w.outside >= 0 else M.L_WOOD, Color(0.55, 0.52, 0.48) if w.outside >= 0 else Color(0.75, 0.6, 0.42), 0)
	mm.box(Vector3(0.025, 0.0, -t - 0.01), Vector3(L - 0.025, 0.018, t + 0.01))
	# casings on both faces (charcoal outside, white inside)
	for s in [0, 1]:
		var nz := 1.0 if s == 0 else -1.0
		var col := M.FRAME_COLOR if s == w.outside else M.TRIM_COLOR
		mm.set_mat(M.L_TRIM, col, s)
		var z0 := nz * t
		var z1 := nz * (t + 0.018)
		var lo := minf(z0, z1)
		var hi := maxf(z0, z1)
		mm.box(Vector3(-0.04, 0.0, lo), Vector3(0.03, hd + 0.07, hi))
		mm.box(Vector3(L - 0.03, 0.0, lo), Vector3(L + 0.04, hd + 0.07, hi))
		mm.box(Vector3(-0.04, hd, lo), Vector3(L + 0.04, hd + 0.07, hi))


## Door leaf in its own frame: hinge edge at x = 0, leaf along +x, faces +-z.
static func door_leaf(style: String, width: float) -> ArrayMesh:
	var key := "leaf|%s|%.2f" % [style, width]
	if _shared.has(key):
		return _shared[key]
	var mm := ModMesh.new()
	var h := HousePlan.DOOR_HEIGHT - 0.03
	var th := 0.042
	match style:
		"front":
			mm.set_mat(M.L_GLOSSY, Color(0.78, 0.55, 0.16))
			mm.box(Vector3(0, 0.01, -th * 0.5), Vector3(width, h, th * 0.5))
			mm.set_mat(M.L_SCREEN, Color(0.16, 0.2, 0.22))
			mm.box(Vector3(width * 0.62, 0.35, -th * 0.5 - 0.003), Vector3(width * 0.78, h - 0.3, th * 0.5 + 0.003))
			mm.set_mat(M.L_METAL, Color(0.15, 0.15, 0.16))
			mm.box(Vector3(width * 0.86, 0.7, -th * 0.5 - 0.05), Vector3(width * 0.89, 1.5, th * 0.5 + 0.05))
		"back":
			mm.set_mat(M.L_PLAIN, Color(0.24, 0.27, 0.27))
			mm.box(Vector3(0, 0.01, -th * 0.5), Vector3(width, h, th * 0.5))
			mm.set_mat(M.L_METAL, Color(0.7, 0.7, 0.68))
			mm.box(Vector3(width * 0.84, 0.98, -th * 0.5 - 0.06), Vector3(width * 0.9, 1.02, th * 0.5 + 0.06))
		_:
			mm.set_mat(M.L_PLAIN, Color(0.95, 0.94, 0.91))
			mm.box(Vector3(0, 0.01, -th * 0.5), Vector3(width, h, th * 0.5))
			mm.set_mat(M.L_PLAIN, Color(0.88, 0.87, 0.84))
			for zz in [-1.0, 1.0]:
				mm.box(Vector3(width * 0.15, 0.25, zz * th * 0.5 - 0.004), Vector3(width * 0.85, 0.95, zz * th * 0.5 + 0.004))
				mm.box(Vector3(width * 0.15, 1.1, zz * th * 0.5 - 0.004), Vector3(width * 0.85, h - 0.2, zz * th * 0.5 + 0.004))
			mm.set_mat(M.L_METAL, Color(0.75, 0.72, 0.66))
			mm.box(Vector3(width * 0.84, 0.98, -th * 0.5 - 0.05), Vector3(width * 0.92, 1.02, th * 0.5 + 0.05))
	var mesh := mm.commit()
	_shared[key] = mesh
	return mesh


# --- damaged construction ---------------------------------------------------------------

## Both skins with their holes, inner faces and splintered rims.
static func _skins(mm: ModMesh, w: ModWall, hole_a: PackedVector2Array, hole_b: PackedVector2Array) -> void:
	var t := w.thickness * 0.5
	for s in [0, 1]:
		var nz := 1.0 if s == 0 else -1.0
		var hole := hole_a if s == 0 else hole_b
		var is_out: bool = s == w.outside
		var skin := SIDING_SKIN if is_out else DRYWALL_SKIN
		var z_out := nz * t
		var z_in := nz * (t - skin)
		mm.set_mat(_side_layer(w, s), Color.WHITE, s)
		_face_minus(mm, w.length, 0.0, H, hole, z_out, nz)
		if is_out:
			mm.set_mat(M.L_TIMBER, M.SHEATHING_COLOR, s)
		else:
			mm.set_mat(M.L_GYPSUM, Color(0.76, 0.74, 0.7), s)
		_face_minus(mm, w.length, 0.0, H, hole, z_in, -nz)
		if is_out:
			mm.set_mat(M.L_TIMBER, M.TIMBER_COLOR.lightened(0.15), s)
		else:
			mm.set_mat(M.L_GYPSUM, M.GYPSUM_COLOR, s)
		_rim(mm, hole, z_in, z_out, Rect2(0, 0, w.length, H))
		if is_out:
			_splinters(mm, hole, z_out, nz, w.seed + s)


## Studs, plates and insulation inside the wall.
static func _cavity(mm: ModMesh, w: ModWall, rng: RandomNumberGenerator, ins_hole: PackedVector2Array, center: Vector2, destroyed: bool) -> void:
	var L := w.length
	var t := w.thickness * 0.5
	var za := t - (SIDING_SKIN if w.outside == 0 else DRYWALL_SKIN)
	var zb := -t + (SIDING_SKIN if w.outside == 1 else DRYWALL_SKIN)
	mm.set_mat(M.L_TIMBER, M.TIMBER_COLOR, 0)
	# top plates (double) stay in every state
	mm.box(Vector3(0, H - TOP_PLATE_H, zb), Vector3(L, H, za), ["+y"])
	# end studs (shared with neighbours in real framing)
	if destroyed:
		_broken_stud(mm, rng, Vector3(STUD_W * 0.5, 0, 0), zb, za, PLATE_H, rng.randf_range(0.2, 0.5), true)
		_broken_stud(mm, rng, Vector3(STUD_W * 0.5, 0, 0), zb, za, rng.randf_range(1.85, 2.1), H - TOP_PLATE_H, false)
		_broken_stud(mm, rng, Vector3(L - STUD_W * 0.5, 0, 0), zb, za, PLATE_H, rng.randf_range(0.15, 0.4), true)
		_broken_stud(mm, rng, Vector3(L - STUD_W * 0.5, 0, 0), zb, za, rng.randf_range(1.9, 2.15), H - TOP_PLATE_H, false)
	else:
		mm.box(Vector3(0.0, PLATE_H, zb), Vector3(STUD_W, H - TOP_PLATE_H, za))
		mm.box(Vector3(L - STUD_W, PLATE_H, zb), Vector3(L, H - TOP_PLATE_H, za))
	# bottom plate (broken through when destroyed)
	if destroyed:
		var gap0 := rng.randf_range(0.25, 0.4) * L
		var gap1 := gap0 + rng.randf_range(0.2, 0.35) * L
		mm.box(Vector3(0, 0, zb), Vector3(gap0, PLATE_H, za))
		mm.box(Vector3(gap1, 0, zb), Vector3(L, PLATE_H, za))
	else:
		mm.box(Vector3(0, 0, zb), Vector3(L, PLATE_H, za))
	# middle stud: snapped where the hole is
	var mid := Vector3(L * 0.5 + rng.randf_range(-0.06, 0.06), 0, 0)
	if destroyed:
		_broken_stud(mm, rng, mid, zb, za, PLATE_H, rng.randf_range(0.12, 0.3), true)
		_broken_stud(mm, rng, mid, zb, za, rng.randf_range(1.78, 2.0), H - TOP_PLATE_H, false)
	else:
		var g0 := center.y - rng.randf_range(0.18, 0.32)
		var g1 := center.y + rng.randf_range(0.18, 0.3)
		_broken_stud(mm, rng, mid, zb, za, PLATE_H, g0, true)
		_broken_stud(mm, rng, mid, zb, za, g1, H - TOP_PLATE_H, false)
	# insulation (exterior walls only), set back from the studs' faces
	if not w.exterior:
		return
	var zi0 := zb + 0.012
	var zi1 := za - 0.012
	var area := Rect2(STUD_W, PLATE_H, L - 2 * STUD_W, H - TOP_PLATE_H - PLATE_H)
	if destroyed:
		# torn batts hang from the top plate
		var pts := PackedVector2Array()
		pts.append(Vector2(area.position.x, area.end.y))
		var n := 9
		for k in range(n + 1):
			var x := area.position.x + area.size.x * k / n
			pts.append(Vector2(x, rng.randf_range(1.86, 2.2) - (0.12 if k % 2 == 0 else 0.0)))
		pts.append(Vector2(area.end.x, area.end.y))
		var poly := PackedVector2Array()
		for k in range(pts.size() - 1, -1, -1):
			poly.append(pts[k])
		mm.set_mat(M.L_INSULATION, M.INSULATION_COLOR, 0)
		mm.flat_poly(poly, zi1, 1.0)
		mm.flat_poly(poly, zi0, -1.0)
		_rim(mm, poly, zi0, zi1, Rect2(area.position.x, -10, area.size.x, area.end.y + 10), true)
		return
	mm.set_mat(M.L_INSULATION, M.INSULATION_COLOR, 0)
	var hole := _clip_to(ins_hole, area.grow(-0.02))
	_face_minus_rect(mm, area, hole, zi1, 1.0)
	_face_minus_rect(mm, area, hole, zi0, -1.0)
	mm.set_mat(M.L_INSULATION, M.INSULATION_COLOR.darkened(0.12), 0)
	_rim(mm, hole, zi0, zi1, area)


static func _broken_stud(mm: ModMesh, rng: RandomNumberGenerator, at: Vector3, zb: float, za: float, y0: float, y1: float, from_bottom: bool) -> void:
	if y1 - y0 < 0.03:
		return
	mm.set_mat(M.L_TIMBER, M.TIMBER_COLOR.darkened(rng.randf_range(0.0, 0.12)), 0)
	var x0 := at.x - STUD_W * 0.5
	var x1 := at.x + STUD_W * 0.5
	var split := rng.randf_range(0.05, 0.12)
	if from_bottom:
		mm.box(Vector3(x0, y0, zb), Vector3(x1, y1, za), ["+y"])
		# splintered end: two uneven spikes
		var tip := Vector3(lerpf(x0, x1, rng.randf_range(0.2, 0.8)), y1 + split, lerpf(zb, za, rng.randf_range(0.3, 0.7)))
		_spike(mm, Vector3(x0, y1, zb), Vector3(x1, y1, zb), Vector3(x1, y1, za), Vector3(x0, y1, za), tip)
	else:
		mm.box(Vector3(x0, y0, zb), Vector3(x1, y1, za), ["-y"])
		var tip := Vector3(lerpf(x0, x1, rng.randf_range(0.2, 0.8)), y0 - split, lerpf(zb, za, rng.randf_range(0.3, 0.7)))
		_spike(mm, Vector3(x0, y0, zb), Vector3(x1, y0, zb), Vector3(x1, y0, za), Vector3(x0, y0, za), tip)


static func _spike(mm: ModMesh, a: Vector3, b: Vector3, c: Vector3, d: Vector3, tip: Vector3) -> void:
	var base := (a + b + c + d) * 0.25
	for e in [[a, b], [b, c], [c, d], [d, a]]:
		var p: Vector3 = e[0]
		var q: Vector3 = e[1]
		var n := (q - p).cross(tip - p).normalized()
		var mid := (p + q + tip) / 3.0
		var out := mid - base
		out.y = 0.0
		if n.dot(out) < 0.0:
			n = -n
		mm.tri(p, q, tip, n)


## Thin splinters poking out of a siding hole edge.
static func _splinters(mm: ModMesh, hole: PackedVector2Array, z: float, nz: float, seed: int) -> void:
	if hole.size() < 3:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 13 + 1
	var c := Vector2.ZERO
	for p in hole:
		c += p
	c /= hole.size()
	mm.set_mat(M.L_TIMBER, M.TIMBER_COLOR.lightened(0.1), 0)
	for i in range(0, hole.size(), 3):
		var p := hole[i]
		var inward := (c - p).normalized()
		var tip := p + inward * rng.randf_range(0.04, 0.1)
		var side := Vector2(-inward.y, inward.x) * 0.012
		var tz := z + nz * rng.randf_range(0.01, 0.05)
		mm.tri(Vector3(p.x + side.x, p.y + side.y, z), Vector3(p.x - side.x, p.y - side.y, z), Vector3(tip.x, tip.y, tz), Vector3(0, 0, nz))


# --- 2D polygon helpers --------------------------------------------------------------------

## Star-shaped jagged polygon (counter-clockwise), alternating spikes.
static func _jagged(c: Vector2, r: Vector2, n: int, rng: RandomNumberGenerator, rough: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in n:
		var a := TAU * (k + rng.randf_range(-0.3, 0.3)) / n
		var f := 1.0 + rng.randf_range(-rough, rough) * 0.6
		if k % 2 == 1:
			f *= 1.0 - rough * rng.randf_range(0.2, 0.6)
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y) * f)
	return pts


## Breach outline for a destroyed module: thin jagged stubs at the sides and
## bottom, the lintel edge between 1.92 and 2.22 m.
static func _breach_outline(L: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var left := rng.randf_range(0.035, 0.1)
	var right := L - rng.randf_range(0.035, 0.1)
	var n := 7
	# bottom edge, left to right
	for k in range(n + 1):
		var x := lerpf(left, right, float(k) / n)
		pts.append(Vector2(clampf(x + rng.randf_range(-0.02, 0.02), left, right), rng.randf_range(0.035, 0.15)))
	# right edge up
	for k in range(1, 6):
		var y := lerpf(0.15, 1.95, float(k) / 6)
		pts.append(Vector2(right - rng.randf_range(0.0, 0.07) * (0.5 + 0.5 * (k % 2)), y))
	# lintel edge, right to left
	for k in range(n, -1, -1):
		var x := lerpf(left, right, float(k) / n)
		var y := rng.randf_range(1.94, 2.2) - (0.06 if k % 2 == 0 else 0.0)
		pts.append(Vector2(clampf(x + rng.randf_range(-0.02, 0.02), left, right), maxf(y, 1.92)))
	# left edge down
	for k in range(5, 0, -1):
		var y := lerpf(0.15, 1.95, float(k) / 6)
		pts.append(Vector2(left + rng.randf_range(0.0, 0.07) * (0.5 + 0.5 * (k % 2)), y))
	return pts


static func _scaled(poly: PackedVector2Array, k: float) -> PackedVector2Array:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	c /= maxf(1.0, poly.size())
	var out := PackedVector2Array()
	for p in poly:
		out.append(c + (p - c) * k)
	return out


## Flat ring between an outer and an inner polygon (split through the middle
## so each half is a simple polygon for the triangulator).
static func _ring(mm: ModMesh, outer: PackedVector2Array, inner: PackedVector2Array, z: float, nz: float) -> void:
	if outer.size() < 3 or inner.size() < 3:
		return
	var lo := INF
	var hi := -INF
	for p in inner:
		lo = minf(lo, p.x)
		hi = maxf(hi, p.x)
	var cx := (lo + hi) * 0.5
	for half in [Rect2(-10, -10, cx + 10, 30), Rect2(cx, -10, 20, 30)]:
		for part in Geometry2D.intersect_polygons(outer, _rect_poly(half)):
			for poly in Geometry2D.clip_polygons(part, inner):
				if poly.size() >= 3 and Geometry2D.is_polygon_clockwise(poly) == Geometry2D.is_polygon_clockwise(part):
					mm.flat_poly(poly, z, nz)


static func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


static func _clip_to(poly: PackedVector2Array, r: Rect2) -> PackedVector2Array:
	if poly.is_empty():
		return poly
	var res := Geometry2D.intersect_polygons(poly, _rect_poly(r))
	var best := PackedVector2Array()
	var best_a := 0.0
	for p in res:
		var a := absf(_area(p))
		if a > best_a:
			best_a = a
			best = p
	return best


static func _merge(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	var res := Geometry2D.merge_polygons(a, b)
	var best := PackedVector2Array()
	var best_a := 0.0
	for p in res:
		if Geometry2D.is_polygon_clockwise(p) != Geometry2D.is_polygon_clockwise(a):
			continue
		var ar := absf(_area(p))
		if ar > best_a:
			best_a = ar
			best = p
	return best if not best.is_empty() else a


static func _area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		var q := p[(i + 1) % p.size()]
		s += p[i].x * q.y - q.x * p[i].y
	return s * 0.5


## Rectangle [0, L] x [y0, y1] minus one hole polygon, as a flat face at depth z.
## The rect is split through the hole so each half is a simple polygon.
static func _face_minus(mm: ModMesh, L: float, y0: float, y1: float, hole: PackedVector2Array, z: float, nz: float) -> void:
	_face_minus_rect(mm, Rect2(0, y0, L, y1 - y0), hole, z, nz)


static func _face_minus_rect(mm: ModMesh, r: Rect2, hole: PackedVector2Array, z: float, nz: float) -> void:
	if hole.size() < 3:
		mm.quad(Vector3(r.position.x, r.position.y, z), Vector3(r.end.x, r.position.y, z), Vector3(r.end.x, r.end.y, z), Vector3(r.position.x, r.end.y, z), Vector3(0, 0, nz))
		return
	var cx := 0.0
	var lo := INF
	var hi := -INF
	for p in hole:
		lo = minf(lo, p.x)
		hi = maxf(hi, p.x)
	cx = (lo + hi) * 0.5
	cx = clampf(cx, r.position.x + 0.001, r.end.x - 0.001)
	for half in [Rect2(r.position.x, r.position.y, cx - r.position.x, r.size.y), Rect2(cx, r.position.y, r.end.x - cx, r.size.y)]:
		var res := Geometry2D.clip_polygons(_rect_poly(half), hole)
		for poly in res:
			if poly.size() >= 3:
				mm.flat_poly(poly, z, nz)


## Faces along the edges of a hole between depths z0 and z1, facing into the hole.
## Edges lying on the module boundary `bounds` are skipped.
static func _rim(mm: ModMesh, hole: PackedVector2Array, z0: float, z1: float, bounds: Rect2, outward := false) -> void:
	var n := hole.size()
	if n < 3:
		return
	var ccw := not Geometry2D.is_polygon_clockwise(hole)
	for i in n:
		var a := hole[i]
		var b := hole[(i + 1) % n]
		if _on_bound(a, b, bounds):
			continue
		var e := b - a
		if e.length_squared() < 1e-8:
			continue
		# interior (the empty hole) lies left of each edge of a CCW polygon
		var left := Vector2(-e.y, e.x).normalized()
		var into := left if ccw else -left
		if outward:
			into = -into
		var nrm := Vector3(into.x, into.y, 0.0)
		mm.quad(Vector3(a.x, a.y, z0), Vector3(b.x, b.y, z0), Vector3(b.x, b.y, z1), Vector3(a.x, a.y, z1), nrm)


static func _on_bound(a: Vector2, b: Vector2, r: Rect2) -> bool:
	const E := 0.002
	if absf(a.x - r.position.x) < E and absf(b.x - r.position.x) < E:
		return true
	if absf(a.x - r.end.x) < E and absf(b.x - r.end.x) < E:
		return true
	if absf(a.y - r.position.y) < E and absf(b.y - r.position.y) < E:
		return true
	if absf(a.y - r.end.y) < E and absf(b.y - r.end.y) < E:
		return true
	return false
