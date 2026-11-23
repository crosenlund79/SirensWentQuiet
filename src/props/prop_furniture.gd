extends RefCounted
## Interior furniture for PropKit (every HousePlan.FURNITURE type). Forked from
## Experiment 001's modular furniture kit: chamfered boxes, prisms and blobs,
## one mesh per piece. Builder frame: footprint centred on the origin, width w
## along x, depth d along z, the FRONT toward +z, floor at y = 0 (PropKit
## turns the result so the front faces -Z). Palette: Version A's voxel colours
## (sage kitchen, slate sofa, rust armchair, mauve bedding, oak), slightly
## desaturated, plus small signs of a hurried departure.

const M := preload("res://src/props/prop_materials.gd")

const OAK := Color(0.74, 0.6, 0.44)
const OAK_DARK := Color(0.6, 0.47, 0.33)
const WALNUT := Color(0.42, 0.3, 0.21)
const BLACK := Color(0.13, 0.13, 0.14)
const WHITE := Color(0.86, 0.84, 0.79)
const CERAMIC := Color(0.9, 0.89, 0.86)
const STEEL := Color(0.64, 0.65, 0.64)
const SLATE := Color(0.34, 0.4, 0.43)
const RUST := Color(0.56, 0.31, 0.21)
const MAUVE := Color(0.68, 0.56, 0.55)
const SAGE := Color(0.47, 0.53, 0.46)
const WORKTOP := Color(0.74, 0.62, 0.45)
const MUSTARD := Color(0.72, 0.56, 0.27)
const LINEN := Color(0.88, 0.84, 0.75)
const TERRACOTTA := Color(0.62, 0.37, 0.26)
const CARDBOARD := Color(0.64, 0.51, 0.35)
const LEAF_GREEN := Color(0.33, 0.39, 0.24)
const LEAF_DEAD := Color(0.55, 0.46, 0.27)
const BOOKS := [Color(0.58, 0.24, 0.2), Color(0.24, 0.32, 0.42), Color(0.8, 0.73, 0.56), Color(0.32, 0.41, 0.33),
		Color(0.83, 0.81, 0.76), Color(0.44, 0.31, 0.4), Color(0.74, 0.53, 0.24), Color(0.2, 0.2, 0.22)]


static func build(mm: PropMesh, type: String, w: float, h: float, d: float, rng: RandomNumberGenerator, damage: float) -> bool:
	match type:
		"sofa":
			_sofa(mm, w, d, h, rng)
		"armchair":
			_armchair(mm, w, d, h, rng)
		"coffee_table":
			_coffee_table(mm, w, d, h, rng)
		"tv_stand":
			_tv_stand(mm, w, d, h, rng)
		"rug":
			_rug(mm, w, d, h, rng)
		"floor_lamp":
			_floor_lamp(mm, w, d, h, rng)
		"bookshelf":
			_bookshelf(mm, w, d, h, rng)
		"dining_table":
			_dining_table(mm, w, d, h, rng)
		"chair":
			_chair(mm, w, d, h, rng)
		"plant":
			_plant(mm, w, d, h, rng)
		"fridge":
			_fridge(mm, w, d, h, rng)
		"counter":
			_counter(mm, w, d, h, rng)
		"sink_counter":
			_sink_counter(mm, w, d, h, rng)
		"stove":
			_stove(mm, w, d, h, rng)
		"island":
			_island(mm, w, d, h, rng)
		"stool":
			_stool(mm, w, d, h, rng)
		"bed":
			_bed(mm, w, d, h, rng)
		"nightstand":
			_nightstand(mm, w, d, h, rng)
		"wardrobe":
			_wardrobe(mm, w, d, h, rng)
		"dresser":
			_dresser(mm, w, d, h, rng)
		"bathtub":
			_bathtub(mm, w, d, h, rng)
		"toilet":
			_toilet(mm, w, d, h, rng)
		"vanity":
			_vanity(mm, w, d, h, rng)
		"water_heater":
			_water_heater(mm, w, d, h, rng)
		"workbench":
			_workbench(mm, w, d, h, rng)
		"washer":
			_washer(mm, w, d, h, rng, false)
		"dryer":
			_washer(mm, w, d, h, rng, true)
		"shelves":
			_shelves(mm, w, d, h, rng)
		"boxes":
			_boxes(mm, w, d, h, rng)
		_:
			return false
	if damage > 0.25 and type != "rug":
		_splinters(mm, w, d, rng, damage)
	return true


# --- helpers ------------------------------------------------------------------------------

static func _legs(mm: PropMesh, w: float, d: float, h: float, inset: float, r: float, col: Color, layer := M.L_METAL) -> void:
	mm.set_mat(layer, col)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mm.cylinder(Vector3(sx * (w * 0.5 - inset), 0, sz * (d * 0.5 - inset)), r * 0.8, r, h, 6)


static func _cbox(mm: PropMesh, lo: Vector3, hi: Vector3, r := 0.02) -> void:
	mm.chamfer_box(lo, hi, r)


## Small flat object lying on a surface (paper, book, rag).
static func _flat(mm: PropMesh, at: Vector3, size: Vector2, yaw: float, thick := 0.004) -> void:
	mm.obox(Transform3D(Basis(Vector3.UP, yaw), at + Vector3(0, thick * 0.5, 0)), Vector3(size.x, thick, size.y))


## Splinters and chips on the floor around a damaged piece.
static func _splinters(mm: PropMesh, w: float, d: float, rng: RandomNumberGenerator, damage: float) -> void:
	var n := int(4 + damage * 10)
	for i in n:
		mm.set_mat(M.L_ROUGH_WOOD if rng.randf() < 0.6 else M.L_PLAIN, Color(0.7, 0.58, 0.42).darkened(rng.randf_range(0.0, 0.35)), 0.3)
		var p := Vector3(rng.randf_range(-w * 0.48, w * 0.48), 0.0, rng.randf_range(-d * 0.48, d * 0.48))
		_flat(mm, p, Vector2(rng.randf_range(0.03, 0.12), rng.randf_range(0.01, 0.03)), rng.randf() * TAU, 0.012)


# --- living room ------------------------------------------------------------------------------

static func _sofa(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	var arm := minf(0.2, w * 0.1)
	_legs(mm, w - 0.1, d - 0.1, 0.1, 0.04, 0.025, WALNUT, M.L_WOOD)
	mm.set_mat(M.L_FABRIC, SLATE, 0.05)
	_cbox(mm, Vector3(-x, 0.1, -z), Vector3(x, 0.38, z), 0.04)
	# back and arms
	_cbox(mm, Vector3(-x, 0.36, -z), Vector3(x, h, -z + 0.24), 0.07)
	_cbox(mm, Vector3(-x, 0.36, -z), Vector3(-x + arm, 0.64, z), 0.06)
	_cbox(mm, Vector3(x - arm, 0.36, -z), Vector3(x, 0.64, z), 0.06)
	# seat and back cushions; one seat cushion pushed askew
	var n := 3 if w > 1.6 else 2
	var sw := (w - arm * 2.0) / n
	var odd := rng.randi() % n
	for i in n:
		var cx := -x + arm + sw * i
		mm.set_mat(M.L_FABRIC, SLATE.lightened(0.05 + rng.randf_range(-0.02, 0.02)), 0.05)
		if i == odd:
			var c := Vector3(cx + sw * 0.5 + rng.randf_range(-0.04, 0.04), 0.45, 0.08)
			mm.ochamfer(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.14, 0.14)) * Basis(Vector3.BACK, 0.05), c), Vector3(sw - 0.03, 0.12, d - 0.3), 0.045)
		else:
			_cbox(mm, Vector3(cx + 0.008, 0.38, -z + 0.22), Vector3(cx + sw - 0.008, 0.5, z - 0.02), 0.05)
		_cbox(mm, Vector3(cx + 0.01, 0.5, -z + 0.06), Vector3(cx + sw - 0.01, h - 0.05, -z + 0.26), 0.06)
	# throw pillows and a blanket half on the floor
	mm.set_mat(M.L_FABRIC, MUSTARD)
	mm.ochamfer(Transform3D(Basis(Vector3.FORWARD, 0.25) * Basis(Vector3.RIGHT, -0.3), Vector3(-x + arm + 0.18, 0.66, -z + 0.32)), Vector3(0.36, 0.34, 0.12), 0.04)
	mm.set_mat(M.L_FABRIC, RUST.lightened(0.1))
	mm.ochamfer(Transform3D(Basis(Vector3.FORWARD, -0.6) * Basis(Vector3.RIGHT, -1.2), Vector3(x - arm - 0.25, 0.55, -z + 0.45)), Vector3(0.34, 0.32, 0.11), 0.04)
	mm.set_mat(M.L_FABRIC, LINEN, 0.1)
	var bx := x - 0.75 if w > 1.4 else 0.0
	mm.box(Vector3(bx, 0.5, -z + 0.25), Vector3(bx + 0.5, 0.52, z))
	mm.box(Vector3(bx, 0.03, z - 0.02), Vector3(bx + 0.5, 0.52, z))
	mm.box(Vector3(bx - 0.02, 0.0, z - 0.2), Vector3(bx + 0.52, 0.03, z))


static func _armchair(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	_legs(mm, w - 0.08, d - 0.08, 0.12, 0.04, 0.022, WALNUT, M.L_WOOD)
	mm.set_mat(M.L_FABRIC, RUST, 0.06)
	_cbox(mm, Vector3(-x, 0.12, -z), Vector3(x, 0.38, z), 0.04)
	_cbox(mm, Vector3(-x, 0.36, -z), Vector3(x, h, -z + 0.2), 0.07)
	_cbox(mm, Vector3(-x, 0.36, -z), Vector3(-x + 0.15, 0.62, z), 0.05)
	_cbox(mm, Vector3(x - 0.15, 0.36, -z), Vector3(x, 0.62, z), 0.05)
	mm.set_mat(M.L_FABRIC, RUST.lightened(0.08), 0.04)
	_cbox(mm, Vector3(-x + 0.15, 0.38, -z + 0.18), Vector3(x - 0.15, 0.5, z - 0.02), 0.05)
	# a folded newspaper on the arm, a mug on the floor beside it
	mm.set_mat(M.L_PAPER, Color(0.82, 0.8, 0.74))
	_flat(mm, Vector3(x - 0.075, 0.62, 0.05), Vector2(0.13, 0.28), rng.randf_range(-0.1, 0.1), 0.02)
	mm.set_mat(M.L_GLOSSY, Color(0.72, 0.42, 0.3))
	mm.cylinder(Vector3(-x + 0.08, 0.0, z - 0.08), 0.04, 0.045, 0.09, 8)


static func _coffee_table(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	_legs(mm, w, d, h - 0.04, 0.06, 0.018, BLACK)
	mm.set_mat(M.L_WOOD, OAK)
	_cbox(mm, Vector3(-w * 0.5, h - 0.045, -d * 0.5), Vector3(w * 0.5, h, d * 0.5), 0.015)
	mm.box(Vector3(-w * 0.5 + 0.06, 0.12, -d * 0.5 + 0.06), Vector3(w * 0.5 - 0.06, 0.14, d * 0.5 - 0.06))
	# books, a mug knocked over, loose papers, a road map
	for i in 2:
		mm.set_mat(M.L_PLAIN, BOOKS[(i * 3 + rng.randi()) % BOOKS.size()])
		var bw := 0.24 - i * 0.02
		mm.obox(Transform3D(Basis(Vector3.UP, 0.15 * i - 0.1), Vector3(-w * 0.22, h + 0.015 + i * 0.03, -0.05)), Vector3(bw, 0.028, 0.17))
	mm.set_mat(M.L_GLOSSY, CERAMIC)
	mm.tube(Vector3(w * 0.2, h + 0.045, 0.06), Vector3(w * 0.2 + 0.08, h + 0.045, 0.1), 0.04, 0.045, 8)
	mm.set_mat(M.L_PLAIN, Color(0.28, 0.2, 0.14))
	mm.poly(PackedVector3Array([Vector3(w * 0.2 + 0.1, h + 0.002, 0.08), Vector3(w * 0.2 + 0.22, h + 0.002, 0.04),
			Vector3(w * 0.2 + 0.24, h + 0.002, 0.14), Vector3(w * 0.2 + 0.12, h + 0.002, 0.17)]), Vector3.UP)
	mm.set_mat(M.L_PAPER, Color(0.86, 0.82, 0.68))
	_flat(mm, Vector3(0.02, h, -0.04), Vector2(0.34, 0.24), rng.randf_range(-0.4, 0.4), 0.003)
	mm.set_mat(M.L_PAPER, Color(0.9, 0.89, 0.86))
	_flat(mm, Vector3(0.08, 0.14, 0.02), Vector2(0.2, 0.28), rng.randf_range(-0.5, 0.5), 0.003)


static func _tv_stand(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	var top := minf(0.5, h * 0.45)
	_legs(mm, w - 0.1, d - 0.06, 0.12, 0.03, 0.02, BLACK)
	mm.set_mat(M.L_WOOD, WALNUT)
	_cbox(mm, Vector3(-x, 0.12, -z), Vector3(x, top, z), 0.012)
	for i in 3:
		var cx := -x + w / 3.0 * (i + 0.5)
		if i == 2:
			# this cabinet was emptied: door gone, dark inside
			mm.set_mat(M.L_SCREEN, Color(0.05, 0.05, 0.05))
		else:
			mm.set_mat(M.L_WOOD, WALNUT.darkened(0.25))
		mm.box(Vector3(cx - w / 6.0 + 0.012, 0.15, z), Vector3(cx + w / 6.0 - 0.012, top - 0.03, z + 0.006))
	# television (dark, a crack across the screen)
	var tw := minf(1.25, w * 0.7)
	var ty0 := top + 0.06
	mm.set_mat(M.L_PLAIN, BLACK)
	mm.box(Vector3(-0.15, top, -0.06), Vector3(0.15, top + 0.02, 0.1))
	mm.box(Vector3(-0.03, top + 0.02, -0.02), Vector3(0.03, ty0 + 0.04, 0.02))
	mm.box(Vector3(-tw * 0.5, ty0, -0.035), Vector3(tw * 0.5, h, 0.0))
	mm.set_mat(M.L_SCREEN, Color(0.06, 0.07, 0.08))
	mm.box(Vector3(-tw * 0.5 + 0.015, ty0 + 0.015, 0.0), Vector3(tw * 0.5 - 0.015, h - 0.015, 0.004))
	mm.set_mat(M.L_PLAIN, Color(0.42, 0.45, 0.48))
	var p := Vector3(rng.randf_range(-tw * 0.2, tw * 0.2), lerpf(ty0, h, 0.6), 0.0045)
	for k in 4:
		var a := rng.randf() * TAU
		var q := p + Vector3(cos(a), sin(a) * 0.6, 0) * rng.randf_range(0.12, 0.3)
		q.x = clampf(q.x, -tw * 0.5 + 0.02, tw * 0.5 - 0.02)
		q.y = clampf(q.y, ty0 + 0.02, h - 0.02)
		mm.quad(p + Vector3(0, -0.002, 0), q + Vector3(0, -0.002, 0), q + Vector3(0, 0.002, 0), p + Vector3(0, 0.002, 0), Vector3.BACK)
	# a speaker, a toppled photo frame and a dead plant
	mm.set_mat(M.L_PLAIN, Color(0.2, 0.2, 0.21))
	_cbox(mm, Vector3(x - 0.3, top, -0.1), Vector3(x - 0.12, minf(top + 0.3, h), 0.1), 0.02)
	mm.set_mat(M.L_PLAIN, BLACK)
	_flat(mm, Vector3(x - 0.5, top, 0.08), Vector2(0.16, 0.2), 0.3, 0.015)
	mm.set_mat(M.L_GLOSSY, WHITE)
	mm.cylinder(Vector3(-x + 0.2, top, 0.0), 0.07, 0.09, 0.14, 8)
	mm.set_mat(M.L_FOLIAGE, LEAF_DEAD)
	mm.blob(Vector3(-x + 0.2, top + 0.2, 0.0), Vector3(0.12, 0.08, 0.12), 3, 6)


static func _rug(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var y := 0.006
	var big := w > 1.5
	var field := Color(0.55, 0.34, 0.26) if w > 3.0 else (Color(0.42, 0.47, 0.53) if big else Color(0.6, 0.68, 0.7))
	var fold := 0.0 if not big else rng.randf_range(0.25, 0.4)
	# the field, with one corner kicked over (folded back on itself)
	mm.set_mat(M.L_FABRIC, field, 0.12)
	var c := Vector3(w * 0.5, y, d * 0.5)
	if fold > 0.0:
		mm.poly(PackedVector3Array([Vector3(-w * 0.5, y, -d * 0.5), Vector3(w * 0.5, y, -d * 0.5), Vector3(w * 0.5, y, d * 0.5 - fold),
				Vector3(w * 0.5 - fold, y, d * 0.5), Vector3(-w * 0.5, y, d * 0.5)]), Vector3.UP)
		mm.set_mat(M.L_FABRIC, field.darkened(0.25), 0.2)
		mm.sheet(PackedVector3Array([c + Vector3(0, 0.004, -fold), c + Vector3(-fold, 0.004, 0), c + Vector3(-fold * 0.9, 0.035, -fold * 0.9)]))
	else:
		mm.poly(PackedVector3Array([Vector3(-w * 0.5, y, -d * 0.5), Vector3(w * 0.5, y, -d * 0.5), Vector3(w * 0.5, y, d * 0.5), Vector3(-w * 0.5, y, d * 0.5)]), Vector3.UP)
	if not big:
		return
	var border := Color(0.3, 0.22, 0.18) if w > 3.0 else Color(0.27, 0.3, 0.34)
	mm.set_mat(M.L_FABRIC, border, 0.1)
	var b := 0.14
	var y2 := y + 0.002
	var lim := d * 0.5 - fold - 0.02
	for r in [[-w * 0.5 + 0.08, -d * 0.5 + 0.08, w * 0.5 - 0.08, -d * 0.5 + 0.08 + b],
			[-w * 0.5 + 0.08, d * 0.5 - 0.08 - b, w * 0.5 - 0.08 - fold, d * 0.5 - 0.08],
			[-w * 0.5 + 0.08, -d * 0.5 + 0.08, -w * 0.5 + 0.08 + b, d * 0.5 - 0.08],
			[w * 0.5 - 0.08 - b, -d * 0.5 + 0.08, w * 0.5 - 0.08, minf(d * 0.5 - 0.08, lim)]]:
		mm.quad(Vector3(r[0], y2, r[1]), Vector3(r[2], y2, r[1]), Vector3(r[2], y2, r[3]), Vector3(r[0], y2, r[3]), Vector3.UP)
	# muted cream diamonds in the field (Version A's rug motif)
	mm.set_mat(M.L_FABRIC, Color(0.76, 0.66, 0.52), 0.15)
	var n := 3 if w > 3.0 else 2
	for i in n:
		var cx := -w * 0.5 + w * (i + 0.5) / n
		var s := minf(d, w / n) * 0.14
		mm.poly(PackedVector3Array([Vector3(cx, y2, -s * 1.4), Vector3(cx + s, y2, 0), Vector3(cx, y2, s * 1.4), Vector3(cx - s, y2, 0)]), Vector3.UP)
	# a few faint stains
	for i in 3:
		mm.set_mat(M.L_FABRIC, field.darkened(rng.randf_range(0.12, 0.22)), 0.25)
		var sc := Vector3(rng.randf_range(-w * 0.35, w * 0.35), y2 + 0.0005, rng.randf_range(-d * 0.35, d * 0.3))
		var pts := PackedVector3Array()
		var sr := rng.randf_range(0.1, 0.22)
		for k in 7:
			var a := TAU * k / 7.0
			pts.append(sc + Vector3(cos(a), 0, sin(a)) * sr * rng.randf_range(0.6, 1.0))
		mm.poly(pts, Vector3.UP)


static func _floor_lamp(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var r := minf(w, d) * 0.5
	mm.set_mat(M.L_METAL, BLACK)
	mm.cylinder(Vector3.ZERO, r * 0.8, r * 0.75, 0.03, 10)
	mm.cylinder(Vector3(0, 0.03, 0), 0.015, 0.015, h - 0.3, 6)
	# no power: the shade is plain fabric, sitting a little askew
	var keep := mm.xf
	mm.xf = mm.xf * Transform3D(Basis(Vector3.BACK, rng.randf_range(0.08, 0.14)), Vector3(0, h - 0.32, 0))
	mm.set_mat(M.L_FABRIC, Color(0.82, 0.76, 0.64), 0.1)
	mm.cylinder(Vector3.ZERO, r * 0.98, r * 0.65, 0.3, 12, false)
	mm.cylinder_inside(Vector3(0, 0.001, 0), r * 0.96, r * 0.63, 0.298, 12)
	mm.set_mat(M.L_GLOSSY, Color(0.75, 0.73, 0.68))
	mm.blob(Vector3(0, 0.12, 0), Vector3(0.045, 0.055, 0.045), 3, 6)
	mm.xf = keep


static func _bookshelf(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	mm.set_mat(M.L_PLAIN, WHITE)
	mm.box(Vector3(-x, 0, -z), Vector3(x, h, -z + 0.02))
	mm.box(Vector3(-x, 0, -z), Vector3(-x + 0.025, h, z))
	mm.box(Vector3(x - 0.025, 0, -z), Vector3(x, h, z))
	var shelves := clampi(int(round(h / 0.38)), 2, 6)
	for i in shelves + 1:
		var y := 0.06 + (h - 0.08) * i / shelves
		mm.set_mat(M.L_PLAIN, WHITE)
		mm.box(Vector3(-x, y - 0.025, -z), Vector3(x, y, z))
		if i == shelves:
			break
		var bx := -x + 0.04
		var top := (h - 0.08) / shelves - 0.05
		var gap_left := rng.randf() < 0.35     # a shelf someone already went through
		while bx < x - 0.1:
			var bw := rng.randf_range(0.025, 0.05)
			var bh := rng.randf_range(0.6, 0.95) * top
			if rng.randf() < (0.35 if gap_left else 0.1):
				bx += rng.randf_range(0.05, 0.18)
				continue
			mm.set_mat(M.L_PLAIN, (BOOKS[rng.randi() % BOOKS.size()] as Color).darkened(rng.randf_range(0, 0.2)))
			if rng.randf() < 0.08 and bx < x - 0.3:
				# a book lying flat
				mm.obox(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.2, 0.2)), Vector3(bx + 0.11, y + 0.014, 0.0)), Vector3(0.2, 0.028, d * 0.62))
				bx += 0.24
				continue
			var lean := 0.0 if rng.randf() < 0.85 else 0.3
			mm.obox(Transform3D(Basis(Vector3.BACK, lean), Vector3(bx + bw * 0.5 + lean * bh * 0.5, y + bh * 0.5 * cos(lean), 0.01)), Vector3(bw, bh, d * 0.72))
			bx += bw + 0.004 + lean * bh
	# a few books lying on top
	for i in 2:
		mm.set_mat(M.L_PLAIN, BOOKS[rng.randi() % BOOKS.size()])
		mm.obox(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)), Vector3(rng.randf_range(-x * 0.5, x * 0.5), h + 0.015 + i * 0.03, 0)), Vector3(0.22, 0.028, d * 0.55))


static func _dining_table(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	mm.set_mat(M.L_WOOD, OAK)
	_cbox(mm, Vector3(-w * 0.5, h - 0.045, -d * 0.5), Vector3(w * 0.5, h, d * 0.5), 0.015)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mm.tube(Vector3(sx * (w * 0.5 - 0.12), h - 0.045, sz * (d * 0.5 - 0.1)), Vector3(sx * (w * 0.5 - 0.08), 0, sz * (d * 0.5 - 0.06)), 0.03, 0.02, 6)
	# a bowl of shrivelled fruit, an abandoned plate, a candle stub, a note
	mm.set_mat(M.L_GLOSSY, Color(0.3, 0.36, 0.4))
	mm.cylinder(Vector3(0, h, 0), 0.08, 0.14, 0.08, 10)
	mm.set_mat(M.L_PLAIN, Color(0.48, 0.32, 0.18))
	mm.blob(Vector3(0.03, h + 0.085, 0.02), Vector3(0.035, 0.03, 0.035), 3, 6)
	mm.blob(Vector3(-0.04, h + 0.085, -0.02), Vector3(0.035, 0.03, 0.035), 3, 6)
	mm.set_mat(M.L_GLOSSY, CERAMIC)
	mm.cylinder(Vector3(w * 0.3, h, d * 0.2), 0.12, 0.13, 0.015, 12)
	mm.set_mat(M.L_METAL, STEEL)
	_flat(mm, Vector3(w * 0.3 + 0.16, h, d * 0.2), Vector2(0.02, 0.18), 0.2, 0.004)
	mm.set_mat(M.L_WAX, Color(0.9, 0.86, 0.76))
	mm.cylinder(Vector3(-w * 0.3, h, -d * 0.15), 0.025, 0.025, 0.05, 8)
	mm.set_mat(M.L_PAPER, Color(0.92, 0.9, 0.84))
	_flat(mm, Vector3(-w * 0.15, h, d * 0.22), Vector2(0.15, 0.21), rng.randf_range(-0.6, 0.6), 0.002)


static func _chair(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var keep := mm.xf
	mm.xf = mm.xf * Transform3D(Basis(Vector3.UP, rng.randf_range(-0.12, 0.12)), Vector3.ZERO)
	var cw := w - 0.03
	var cd := d - 0.03
	_legs(mm, cw - 0.02, cd - 0.02, 0.45, 0.03, 0.016, BLACK)
	mm.set_mat(M.L_WOOD, OAK_DARK)
	_cbox(mm, Vector3(-cw * 0.5 + 0.02, 0.43, -cd * 0.5 + 0.02), Vector3(cw * 0.5 - 0.02, 0.47, cd * 0.5 - 0.02), 0.012)
	mm.set_mat(M.L_METAL, BLACK)
	for sx in [-1.0, 1.0]:
		mm.box(Vector3(sx * (cw * 0.5 - 0.04) - 0.012, 0.47, -cd * 0.5 + 0.02), Vector3(sx * (cw * 0.5 - 0.04) + 0.012, h, -cd * 0.5 + 0.045))
	mm.set_mat(M.L_WOOD, OAK_DARK)
	mm.box(Vector3(-cw * 0.5 + 0.03, h - 0.14, -cd * 0.5 + 0.015), Vector3(cw * 0.5 - 0.03, h - 0.02, -cd * 0.5 + 0.05))
	if rng.randf() < 0.4:
		# a coat left over the back
		mm.set_mat(M.L_FABRIC, Color(0.36, 0.38, 0.3), 0.1)
		mm.box(Vector3(-cw * 0.5 + 0.02, h - 0.34, -cd * 0.5 - 0.005), Vector3(cw * 0.5 - 0.02, h + 0.01, -cd * 0.5 + 0.06))
	mm.xf = keep


static func _plant(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var r := minf(w, d) * 0.5
	var ph := minf(0.38, h * 0.36)
	mm.set_mat(M.L_GLOSSY, TERRACOTTA)
	mm.cylinder(Vector3.ZERO, r * 0.62, r * 0.8, ph, 10)
	mm.set_mat(M.L_SOIL, Color(0.28, 0.22, 0.18))
	mm.cylinder(Vector3(0, ph - 0.05, 0), r * 0.74, r * 0.74, 0.02, 10)
	# drooping leaves, most of them dying; some fallen around the pot
	var leaf_len := clampf(h - ph, 0.25, 0.75) * 0.75
	for i in 12:
		var a := TAU * i / 12.0 + rng.randf_range(-0.2, 0.2)
		var up := rng.randf_range(0.35, 0.8)
		var length := leaf_len * rng.randf_range(0.6, 1.0)
		var base := Vector3(0, ph - 0.03, 0)
		var dir := Vector3(cos(a) * (1.0 - up), up, sin(a) * (1.0 - up)).normalized()
		var tip := base + dir * length
		tip.y = minf(tip.y - rng.randf_range(0.0, 0.12), h)
		var dying := rng.randf() < 0.55
		mm.set_mat(M.L_FOLIAGE, LEAF_DEAD.darkened(rng.randf_range(0.0, 0.2)) if dying else LEAF_GREEN.lightened(rng.randf_range(0.0, 0.12)))
		var side := dir.cross(Vector3.UP).normalized() * rng.randf_range(0.05, 0.08)
		var mid := base.lerp(tip, 0.5) + Vector3(0, 0.05, 0)
		mm.sheet(PackedVector3Array([base, mid + side, tip]))
		mm.sheet(PackedVector3Array([base, tip, mid - side]))
	for i in 3:
		mm.set_mat(M.L_FOLIAGE, LEAF_DEAD.darkened(rng.randf_range(0.1, 0.3)))
		var a := rng.randf() * TAU
		var c := Vector3(cos(a), 0, sin(a)) * (r * 0.9 + 0.05)
		mm.sheet(PackedVector3Array([c + Vector3(-0.06, 0.003, 0), c + Vector3(0, 0.003, 0.025), c + Vector3(0.07, 0.003, 0.01), c + Vector3(0, 0.003, -0.02)]), Vector3.UP)


# --- kitchen ------------------------------------------------------------------------------------

static func _fridge(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	mm.set_mat(M.L_METAL, Color(0.78, 0.78, 0.76), 0.08)
	_cbox(mm, Vector3(-x, 0.02, -z), Vector3(x, h, z), 0.03)
	mm.set_mat(M.L_PLAIN, BLACK)
	mm.box(Vector3(-x + 0.02, h * 0.62, z), Vector3(x - 0.02, h * 0.62 + 0.012, z + 0.004))
	mm.box(Vector3(-x + 0.02, 0.02, z - 0.03), Vector3(x - 0.02, 0.1, z + 0.002))
	mm.set_mat(M.L_METAL, Color(0.5, 0.51, 0.52))
	mm.box(Vector3(x - 0.09, h * 0.67, z + 0.004), Vector3(x - 0.06, h * 0.95, z + 0.04))
	mm.box(Vector3(x - 0.09, h * 0.3, z + 0.004), Vector3(x - 0.06, h * 0.58, z + 0.04))
	# notes, a list, a child's drawing held by magnets; dark water stain at the foot
	var notes := [Color(0.92, 0.86, 0.52), Color(0.93, 0.92, 0.9), Color(0.68, 0.8, 0.88), Color(0.9, 0.7, 0.62)]
	for i in 4:
		mm.set_mat(M.L_PAPER, notes[i])
		var nx := -x + 0.08 + i * minf(0.15, (w - 0.25) / 4.0)
		var ny := h * 0.74 + rng.randf_range(-0.06, 0.1)
		mm.obox(Transform3D(Basis(Vector3.BACK, rng.randf_range(-0.25, 0.25)), Vector3(nx + 0.05, ny, z + 0.003)), Vector3(0.1, 0.13, 0.003))
	mm.set_mat(M.L_SOIL, Color(0.25, 0.22, 0.2))
	mm.poly(PackedVector3Array([Vector3(-x + 0.05, 0.002, z - 0.02), Vector3(x - 0.1, 0.002, z - 0.02), Vector3(x - 0.2, 0.002, z), Vector3(-x + 0.15, 0.002, z)]), Vector3.UP)


static func _counter_body(mm: PropMesh, w: float, d: float, h: float, cab: Color, top: Color, top_layer: int, doors := 0, rng: RandomNumberGenerator = null) -> void:
	var x := w * 0.5
	var z := d * 0.5
	mm.set_mat(M.L_PLAIN, Color(0.15, 0.15, 0.16))
	mm.box(Vector3(-x, 0, -z), Vector3(x, 0.1, z - 0.06))
	mm.set_mat(M.L_PLAIN, cab, 0.06)
	mm.box(Vector3(-x, 0.1, -z), Vector3(x, h - 0.04, z - 0.02))
	mm.set_mat(top_layer, top)
	_cbox(mm, Vector3(-x - 0.005, h - 0.04, -z), Vector3(x + 0.005, h, z + 0.02), 0.008)
	# door and drawer fronts, handles; a door left ajar by whoever searched it
	var n := doors if doors > 0 else maxi(1, int(round(w / 0.5)))
	var dw := w / n
	var ajar := rng.randi() % (n * 2) if rng != null else -1
	for i in n:
		var cx := -x + dw * (i + 0.5)
		mm.set_mat(M.L_PLAIN, cab.lightened(0.04), 0.06)
		mm.box(Vector3(cx - dw * 0.5 + 0.006, h - 0.235, z - 0.02), Vector3(cx + dw * 0.5 - 0.006, h - 0.055, z))
		if i == ajar:
			mm.set_mat(M.L_SCREEN, Color(0.05, 0.05, 0.05))
			mm.box(Vector3(cx - dw * 0.5 + 0.01, 0.11, z - 0.025), Vector3(cx + dw * 0.5 - 0.01, h - 0.25, z - 0.02))
			mm.set_mat(M.L_PLAIN, cab.lightened(0.04), 0.06)
			var hinge := Vector3(cx - dw * 0.5 + 0.006, 0.0, z)
			mm.obox(Transform3D(Basis(Vector3.UP, -0.22), hinge) * Transform3D(Basis.IDENTITY, Vector3((dw - 0.012) * 0.5, (h - 0.25 + 0.11) * 0.5, -0.01)), Vector3(dw - 0.012, h - 0.25 - 0.11, 0.02))
		else:
			mm.box(Vector3(cx - dw * 0.5 + 0.006, 0.11, z - 0.02), Vector3(cx + dw * 0.5 - 0.006, h - 0.25, z))
			mm.set_mat(M.L_METAL, Color(0.25, 0.25, 0.26))
			mm.box(Vector3(cx + dw * 0.5 - 0.06, h - 0.45, z), Vector3(cx + dw * 0.5 - 0.045, h - 0.3, z + 0.02))
		mm.set_mat(M.L_METAL, Color(0.25, 0.25, 0.26))
		mm.box(Vector3(cx - 0.07, h - 0.15, z), Vector3(cx + 0.07, h - 0.135, z + 0.02))


static func _counter(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	_counter_body(mm, w, d, h, SAGE, WORKTOP, M.L_WOOD, 0, rng)
	# a few things left on the counter
	if w > 1.2:
		mm.set_mat(M.L_WOOD, OAK_DARK)
		mm.box(Vector3(-0.2, h, -0.15), Vector3(0.15, h + 0.02, 0.08))
		mm.set_mat(M.L_METAL, Color(0.6, 0.6, 0.58))
		mm.cylinder(Vector3(w * 0.3, h, -0.1), 0.04, 0.04, 0.1, 8)
		mm.set_mat(M.L_PAPER, Color(0.84, 0.34, 0.24))
		mm.cylinder(Vector3(w * 0.3, h + 0.02, -0.1), 0.041, 0.041, 0.06, 8, false)
	elif w > 0.9:
		mm.set_mat(M.L_GLOSSY, CERAMIC)
		mm.cylinder(Vector3(-0.1, h, -0.12), 0.05, 0.06, 0.1, 8)
	else:
		mm.set_mat(M.L_PAPER, Color(0.9, 0.88, 0.82))
		_flat(mm, Vector3(0, h, -0.05), Vector2(0.14, 0.2), rng.randf_range(-0.5, 0.5), 0.003)


static func _sink_counter(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	_counter_body(mm, w, d, h, SAGE, WORKTOP, M.L_WOOD, 2, rng)
	var sw := minf(0.32, w * 0.34)
	mm.set_mat(M.L_METAL, STEEL)
	mm.box(Vector3(-sw, h, -0.2), Vector3(sw, h + 0.006, 0.2), ["-y"])
	mm.set_mat(M.L_METAL, Color(0.42, 0.43, 0.43))
	mm.box_inside(Vector3(-sw + 0.04, h - 0.15, -0.17), Vector3(sw - 0.04, h + 0.007, 0.17), ["+y"])
	mm.set_mat(M.L_METAL, STEEL)
	mm.cylinder(Vector3(0, h, -0.24), 0.025, 0.02, 0.32, 6)
	mm.tube(Vector3(0, h + 0.32, -0.24), Vector3(0, h + 0.28, -0.06), 0.015, 0.015, 6)
	# a dish rack with a plate and a glass
	mm.set_mat(M.L_METAL, Color(0.7, 0.7, 0.68))
	mm.box(Vector3(sw + 0.02, h, -0.18), Vector3(minf(w * 0.5 - 0.02, sw + 0.3), h + 0.03, 0.12))
	mm.set_mat(M.L_GLOSSY, CERAMIC)
	mm.obox(Transform3D(Basis(Vector3.BACK, 0.2), Vector3(minf(w * 0.5 - 0.15, sw + 0.15), h + 0.1, -0.03)), Vector3(0.012, 0.2, 0.2))


static func _stove(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	mm.set_mat(M.L_METAL, Color(0.72, 0.72, 0.7), 0.1)
	mm.box(Vector3(-x, 0.0, -z), Vector3(x, h - 0.03, z))
	mm.set_mat(M.L_SCREEN, Color(0.06, 0.06, 0.07))
	mm.box(Vector3(-x, h - 0.03, -z), Vector3(x, h, z))
	mm.set_mat(M.L_PLAIN, Color(0.33, 0.33, 0.34))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mm.cylinder(Vector3(sx * w * 0.22, h + 0.001, sz * d * 0.22), 0.09, 0.09, 0.002, 10, true)
	mm.set_mat(M.L_SCREEN, Color(0.08, 0.09, 0.1))
	mm.box(Vector3(-x + 0.06, 0.15, z), Vector3(x - 0.06, h - 0.2, z + 0.006))
	mm.set_mat(M.L_METAL, Color(0.58, 0.58, 0.58))
	mm.box(Vector3(-x + 0.08, h - 0.17, z + 0.006), Vector3(x - 0.08, h - 0.15, z + 0.035))
	for i in 4:
		var kx := -x + 0.12 + i * (w - 0.24) / 3.0
		mm.tube(Vector3(kx, h - 0.1, z), Vector3(kx, h - 0.1, z + 0.02), 0.018, 0.018, 6)
	# a pot left on a cold burner, its lid beside it
	mm.set_mat(M.L_METAL, Color(0.36, 0.37, 0.38))
	mm.cylinder(Vector3(-w * 0.22, h + 0.003, -d * 0.22), 0.1, 0.1, 0.1, 10, false)
	mm.cylinder_inside(Vector3(-w * 0.22, h + 0.01, -d * 0.22), 0.095, 0.095, 0.092, 10)
	mm.set_mat(M.L_METAL, Color(0.45, 0.46, 0.47))
	mm.cylinder(Vector3(w * 0.22, h + 0.003, d * 0.18), 0.1, 0.09, 0.012, 10)


static func _island(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	_counter_body(mm, w, d - 0.2, h, SAGE.darkened(0.08), OAK, M.L_WOOD, 3, rng)
	mm.set_mat(M.L_WOOD, WORKTOP)
	_cbox(mm, Vector3(-w * 0.5, h - 0.045, -d * 0.5), Vector3(w * 0.5, h, d * 0.5), 0.01)
	# fruit bowl, a tipped bottle, a glass, a torch with a dead battery
	mm.set_mat(M.L_GLOSSY, CERAMIC)
	mm.cylinder(Vector3(-w * 0.2, h, 0.0), 0.08, 0.14, 0.07, 10)
	mm.set_mat(M.L_PLAIN, Color(0.5, 0.44, 0.2))
	mm.blob(Vector3(-w * 0.2 + 0.02, h + 0.08, 0.01), Vector3(0.05, 0.04, 0.05), 3, 6)
	mm.set_mat(M.L_SCREEN, Color(0.15, 0.27, 0.18))
	mm.tube(Vector3(w * 0.12, h + 0.036, -0.1), Vector3(w * 0.12 + 0.22, h + 0.036, -0.05), 0.035, 0.035, 8)
	mm.tube(Vector3(w * 0.12 + 0.22, h + 0.036, -0.05), Vector3(w * 0.12 + 0.3, h + 0.03, -0.035), 0.013, 0.013, 6)
	mm.set_mat(M.L_MIRROR, Color(0.75, 0.8, 0.82))
	mm.cylinder(Vector3(w * 0.32, h, 0.18), 0.03, 0.035, 0.1, 8, false)
	mm.set_mat(M.L_PLAIN, Color(0.75, 0.32, 0.18))
	mm.tube(Vector3(-w * 0.38, h + 0.02, 0.2), Vector3(-w * 0.38 + 0.16, h + 0.02, 0.24), 0.02, 0.022, 6)


static func _stool(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var r := minf(w, d) * 0.42
	mm.set_mat(M.L_METAL, BLACK)
	for k in 4:
		var a := TAU * (k + 0.5) / 4.0
		mm.tube(Vector3(cos(a) * r * 0.6, h - 0.04, sin(a) * r * 0.6), Vector3(cos(a) * r, 0, sin(a) * r), 0.012, 0.012, 5)
	mm.cylinder(Vector3(0, 0.25, 0), r * 0.85, r * 0.85, 0.015, 10, false)
	mm.set_mat(M.L_WOOD, OAK)
	mm.cylinder(Vector3(0, h - 0.04, 0), r, r, 0.04, 12)


# --- bedroom ------------------------------------------------------------------------------------

static func _bed(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	var frame := minf(0.3, h * 0.5)
	mm.set_mat(M.L_WOOD, OAK)
	_cbox(mm, Vector3(-x, 0.08, -z), Vector3(x, frame, z), 0.015)
	_legs(mm, w - 0.05, d - 0.05, 0.08, 0.04, 0.025, OAK_DARK, M.L_WOOD)
	# headboard
	_cbox(mm, Vector3(-x - 0.02, 0.08, -z - 0.02), Vector3(x + 0.02, h + 0.38, -z + 0.06), 0.02)
	mm.set_mat(M.L_FABRIC, Color(0.78, 0.74, 0.66))
	_cbox(mm, Vector3(-x + 0.05, frame + 0.1, -z + 0.06), Vector3(x - 0.05, h + 0.3, -z + 0.1), 0.03)
	# mattress, a duvet thrown back, pillows, a blanket over the foot
	mm.set_mat(M.L_FABRIC, Color(0.84, 0.82, 0.77), 0.05)
	_cbox(mm, Vector3(-x + 0.04, frame, -z + 0.06), Vector3(x - 0.04, h - 0.1, z - 0.04), 0.04)
	mm.set_mat(M.L_FABRIC, MAUVE, 0.05)
	var fold := -z + d * rng.randf_range(0.42, 0.55)
	mm.ochamfer(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.06, 0.06)), Vector3(0.04, h - 0.06, (fold + z - 0.02) * 0.5)), Vector3(w - 0.06, 0.1, z - 0.02 - fold), 0.05)
	mm.set_mat(M.L_FABRIC, MAUVE.lightened(0.12), 0.05)
	mm.ochamfer(Transform3D(Basis(Vector3.BACK, 0.05), Vector3(0.0, h - 0.02, fold - 0.06)), Vector3(w - 0.04, 0.1, 0.2), 0.04)
	mm.set_mat(M.L_FABRIC, Color(0.92, 0.91, 0.88), 0.04)
	for sx in [-1.0, 1.0]:
		mm.ochamfer(Transform3D(Basis(Vector3.RIGHT, -0.35) * Basis(Vector3.UP, rng.randf_range(-0.2, 0.2)), Vector3(sx * w * 0.24, h + 0.0, -z + 0.28)), Vector3(w * 0.4, 0.14, 0.34), 0.05)
	mm.set_mat(M.L_FABRIC, MUSTARD, 0.06)
	mm.box(Vector3(-x, h - 0.04, z - 0.45), Vector3(x, h - 0.01, z - 0.18))
	mm.box(Vector3(-x - 0.012, frame - 0.05, z - 0.45), Vector3(-x + 0.003, h - 0.01, z - 0.18))
	mm.box(Vector3(x - 0.003, frame - 0.05, z - 0.45), Vector3(x + 0.012, h - 0.01, z - 0.18))


static func _nightstand(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	_legs(mm, w, d, 0.12, 0.04, 0.015, OAK_DARK, M.L_WOOD)
	mm.set_mat(M.L_WOOD, OAK)
	_cbox(mm, Vector3(-w * 0.5, 0.12, -d * 0.5), Vector3(w * 0.5, h, d * 0.5), 0.012)
	mm.set_mat(M.L_WOOD, OAK_DARK)
	mm.box(Vector3(-w * 0.5 + 0.03, h - 0.17, d * 0.5), Vector3(w * 0.5 - 0.03, h - 0.165, d * 0.5 + 0.004))
	mm.set_mat(M.L_METAL, BLACK)
	mm.box(Vector3(-0.05, h - 0.1, d * 0.5), Vector3(0.05, h - 0.085, d * 0.5 + 0.02))
	# a paperback face down and a glass of water
	mm.set_mat(M.L_PLAIN, BOOKS[rng.randi() % BOOKS.size()])
	mm.obox(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.4, 0.4)) * Basis(Vector3.FORWARD, 0.0), Vector3(-w * 0.15, h + 0.015, 0.02)), Vector3(0.12, 0.03, 0.18))
	mm.set_mat(M.L_MIRROR, Color(0.78, 0.83, 0.85))
	mm.cylinder(Vector3(w * 0.25, h, -d * 0.18), 0.03, 0.033, 0.1, 8, false)


static func _wardrobe(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	mm.set_mat(M.L_PLAIN, Color(0.2, 0.2, 0.2))
	mm.box(Vector3(-x + 0.03, 0, -z), Vector3(x - 0.03, 0.08, z - 0.03))
	mm.set_mat(M.L_PLAIN, WHITE, 0.04)
	_cbox(mm, Vector3(-x, 0.08, -z), Vector3(x, h, z), 0.012)
	# one door ajar: a dark gap and the door edge standing proud
	mm.set_mat(M.L_SCREEN, Color(0.04, 0.04, 0.04))
	mm.box(Vector3(-0.006, 0.1, z), Vector3(0.012, h - 0.02, z + 0.004))
	mm.set_mat(M.L_PLAIN, WHITE.darkened(0.06), 0.04)
	mm.obox(Transform3D(Basis(Vector3.UP, 0.08), Vector3(x * 0.5, (h + 0.1) * 0.5, z + 0.012)), Vector3(x - 0.02, h - 0.12, 0.018))
	mm.set_mat(M.L_WOOD, OAK)
	for sx in [-1.0, 1.0]:
		mm.box(Vector3(sx * 0.06 - 0.012, h * 0.45, z + (0.01 if sx < 0 else 0.03)), Vector3(sx * 0.06 + 0.012, h * 0.68, z + (0.04 if sx < 0 else 0.06)))
	# a sleeve hanging out, a suitcase lying on top
	mm.set_mat(M.L_FABRIC, Color(0.4, 0.45, 0.52))
	mm.obox(Transform3D(Basis(Vector3.BACK, 0.2), Vector3(0.05, h * 0.42, z + 0.02)), Vector3(0.08, 0.35, 0.03))
	mm.set_mat(M.L_GLOSSY, Color(0.5, 0.24, 0.2))
	_cbox(mm, Vector3(-x + 0.1, h, -z + 0.06), Vector3(x - 0.25, h + 0.1, z - 0.04), 0.025)


static func _dresser(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	_legs(mm, w, d, 0.1, 0.04, 0.016, OAK_DARK, M.L_WOOD)
	mm.set_mat(M.L_WOOD, OAK)
	_cbox(mm, Vector3(-w * 0.5, 0.1, -d * 0.5), Vector3(w * 0.5, h, d * 0.5), 0.012)
	var open_row := rng.randi() % 3
	for row in 3:
		var y0 := 0.1 + (h - 0.1) * row / 3.0
		var y := 0.1 + (h - 0.1) * (row + 1) / 3.0
		var out := 0.05 if row == open_row else 0.0
		if out > 0.0:
			mm.set_mat(M.L_WOOD, OAK.lightened(0.04))
			mm.box(Vector3(-w * 0.5 + 0.02, y0 + 0.01, d * 0.5 - 0.02), Vector3(w * 0.5 - 0.02, y - 0.008, d * 0.5 + out))
			mm.set_mat(M.L_FABRIC, Color(0.6, 0.62, 0.66))
			mm.blob(Vector3(rng.randf_range(-w * 0.3, w * 0.3), y - 0.01, d * 0.5 + out - 0.03), Vector3(0.14, 0.03, 0.04), 2, 6)
		mm.set_mat(M.L_WOOD, OAK_DARK)
		mm.box(Vector3(-w * 0.5 + 0.02, y - 0.006, d * 0.5 + out), Vector3(w * 0.5 - 0.02, y, d * 0.5 + out + 0.004))
		mm.set_mat(M.L_METAL, BLACK)
		for sx in [-1.0, 1.0]:
			mm.box(Vector3(sx * w * 0.25 - 0.05, y - 0.12, d * 0.5 + out), Vector3(sx * w * 0.25 + 0.05, y - 0.105, d * 0.5 + out + 0.02))
	# a picture frame knocked flat and a jewellery box
	mm.set_mat(M.L_PLAIN, BLACK)
	_flat(mm, Vector3(-w * 0.25, h, -0.04), Vector2(0.2, 0.25), rng.randf_range(-0.3, 0.3), 0.018)
	mm.set_mat(M.L_GLOSSY, Color(0.3, 0.4, 0.42))
	mm.box(Vector3(w * 0.18, h, -0.08), Vector3(w * 0.18 + 0.18, h + 0.08, 0.06))


# --- bathroom -----------------------------------------------------------------------------------

static func _bathtub(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	mm.set_mat(M.L_GLOSSY, CERAMIC)
	_cbox(mm, Vector3(-x, 0, -z), Vector3(x, h, z), 0.04)
	mm.set_mat(M.L_GLOSSY, Color(0.84, 0.85, 0.85), 0.05)
	mm.box_inside(Vector3(-x + 0.08, 0.15, -z + 0.08), Vector3(x - 0.08, h + 0.002, z - 0.08), ["+y"])
	# a grey ring where the water stood (stored water, then drained)
	mm.set_mat(M.L_PLAIN, Color(0.55, 0.53, 0.48))
	mm.box_inside(Vector3(-x + 0.081, 0.28, -z + 0.081), Vector3(x - 0.081, 0.3, z - 0.081), ["+y", "-y"])
	mm.set_mat(M.L_MIRROR, Color(0.5, 0.55, 0.52))
	mm.box(Vector3(-x + 0.08, 0.15, -z + 0.08), Vector3(x - 0.08, 0.2, z - 0.08))
	mm.set_mat(M.L_METAL, STEEL)
	mm.cylinder(Vector3(-x + 0.12, h, -z + 0.04), 0.02, 0.02, 0.1, 6)
	mm.tube(Vector3(-x + 0.12, h + 0.1, -z + 0.04), Vector3(-x + 0.12, h + 0.08, -z + 0.14), 0.015, 0.015, 6)
	# a towel over the edge
	mm.set_mat(M.L_FABRIC, Color(0.55, 0.66, 0.68), 0.08)
	mm.box(Vector3(x * 0.2, h - 0.25, z - 0.005), Vector3(x * 0.2 + 0.35, h + 0.012, z + 0.012))
	mm.box(Vector3(x * 0.2, h - 0.2, z - 0.08), Vector3(x * 0.2 + 0.35, h + 0.012, z - 0.06))
	mm.box(Vector3(x * 0.2, h, z - 0.08), Vector3(x * 0.2 + 0.35, h + 0.012, z + 0.012))


static func _toilet(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var z := d * 0.5
	var bw := minf(w * 0.5, 0.42)
	mm.set_mat(M.L_GLOSSY, CERAMIC, 0.05)
	mm.cylinder(Vector3(0, 0, 0.05), bw * 0.32, bw * 0.42, 0.38, 10)
	mm.cylinder(Vector3(0, 0.38, 0.05), bw * 0.48, bw * 0.48, 0.03, 12)
	_cbox(mm, Vector3(-bw * 0.55, 0.38, -z), Vector3(bw * 0.55, h, -z + 0.2), 0.03)
	# seat lid up against the tank
	mm.set_mat(M.L_GLOSSY, Color(0.92, 0.91, 0.88))
	mm.obox(Transform3D(Basis(Vector3.RIGHT, -1.4), Vector3(0, 0.6, -z + 0.23)), Vector3(bw * 0.9, 0.4, 0.025))
	mm.set_mat(M.L_METAL, STEEL)
	mm.box(Vector3(-0.04, h, -z + 0.08), Vector3(0.04, h + 0.01, -z + 0.12))
	# a toilet roll on the floor
	mm.set_mat(M.L_PAPER, Color(0.93, 0.92, 0.89))
	mm.tube(Vector3(w * 0.32, 0.055, z - 0.05), Vector3(w * 0.32 + 0.1, 0.055, z - 0.08), 0.055, 0.055, 8)


static func _vanity(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	_counter_body(mm, w, d, h - 0.03, OAK, CERAMIC, M.L_GLOSSY, 2, rng)
	mm.set_mat(M.L_GLOSSY, Color(0.95, 0.95, 0.94))
	mm.cylinder(Vector3(0, h - 0.03, 0.02), 0.16, 0.18, 0.1, 12, false)
	mm.cylinder_inside(Vector3(0, h - 0.02, 0.02), 0.14, 0.16, 0.09, 12)
	mm.set_mat(M.L_METAL, STEEL)
	mm.cylinder(Vector3(0, h - 0.03, -d * 0.5 + 0.06), 0.02, 0.016, 0.24, 6)
	mm.tube(Vector3(0, h + 0.21, -d * 0.5 + 0.06), Vector3(0, h + 0.18, -d * 0.5 + 0.18), 0.012, 0.012, 6)
	# cracked mirror on the wall behind, a toothbrush mug
	var zb := -d * 0.5 - 0.025
	mm.set_mat(M.L_PLAIN, BLACK)
	mm.box(Vector3(-w * 0.36, h + 0.3, zb - 0.01), Vector3(w * 0.36, h + 1.05, zb + 0.012))
	mm.set_mat(M.L_MIRROR, Color(0.58, 0.63, 0.64))
	mm.box(Vector3(-w * 0.34, h + 0.32, zb + 0.012), Vector3(w * 0.34, h + 1.03, zb + 0.016))
	mm.set_mat(M.L_PLAIN, Color(0.85, 0.87, 0.88))
	var c := Vector3(rng.randf_range(-w * 0.15, w * 0.15), h + rng.randf_range(0.55, 0.8), zb + 0.0165)
	for k in 5:
		var a := TAU * k / 5.0 + rng.randf_range(-0.3, 0.3)
		var q := c + Vector3(cos(a), sin(a), 0) * rng.randf_range(0.1, 0.28)
		q.x = clampf(q.x, -w * 0.34 + 0.01, w * 0.34 - 0.01)
		q.y = clampf(q.y, h + 0.33, h + 1.02)
		var t := Vector3(-(q - c).y, (q - c).x, 0).normalized() * 0.002
		mm.quad(c - t, q - t, q + t, c + t, Vector3.BACK)
	mm.set_mat(M.L_GLOSSY, Color(0.62, 0.74, 0.7))
	mm.cylinder(Vector3(-w * 0.3, h - 0.03, -d * 0.2), 0.03, 0.035, 0.09, 8)


# --- utility ------------------------------------------------------------------------------------

static func _water_heater(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var r := minf(w, d) * 0.42
	mm.set_mat(M.L_GLOSSY, Color(0.86, 0.86, 0.83), 0.1)
	mm.cylinder(Vector3.ZERO, r, r, h - 0.12, 12, true, true)
	mm.cylinder(Vector3(0, h - 0.12, 0), r, r * 0.72, 0.08, 12)
	mm.set_mat(M.L_METAL, Color(0.7, 0.45, 0.3))
	for sx in [-1.0, 1.0]:
		mm.cylinder(Vector3(sx * 0.08, h - 0.08, -0.05), 0.022, 0.022, 0.32, 6)
		mm.tube(Vector3(sx * 0.08, h + 0.22, -0.05), Vector3(sx * 0.08, h + 0.22, -d * 0.5 - 0.06), 0.022, 0.022, 6)
	mm.set_mat(M.L_PLAIN, Color(0.8, 0.3, 0.2))
	mm.box(Vector3(-0.08, 0.5, r - 0.02), Vector3(0.08, 0.62, r + 0.005))
	mm.set_mat(M.L_RUST, Color(0.5, 0.5, 0.48))
	mm.cylinder(Vector3(0, 0.0, 0), r * 1.02, r * 1.02, 0.06, 12, false)


static func _workbench(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	_legs(mm, w, d, h - 0.05, 0.04, 0.025, Color(0.25, 0.27, 0.3))
	mm.set_mat(M.L_ROUGH_WOOD, OAK, 0.25)
	_cbox(mm, Vector3(-x, h - 0.05, -z), Vector3(x, h, z), 0.01)
	mm.box(Vector3(-x + 0.05, 0.18, -z + 0.05), Vector3(x - 0.05, 0.2, z - 0.05))
	# toolbox (lid open), paint cans, a vice, shavings
	mm.set_mat(M.L_GLOSSY, Color(0.7, 0.22, 0.16), 0.15)
	_cbox(mm, Vector3(-x + 0.15, h, -0.15), Vector3(-x + 0.6, h + 0.16, 0.08), 0.02)
	mm.obox(Transform3D(Basis(Vector3.RIGHT, -1.2), Vector3(-x + 0.375, h + 0.2, -0.18)), Vector3(0.45, 0.2, 0.02))
	mm.set_mat(M.L_METAL, Color(0.5, 0.52, 0.55), 0.2)
	mm.cylinder(Vector3(w * 0.15, 0.2, 0.0), 0.09, 0.09, 0.2, 10)
	mm.cylinder(Vector3(w * 0.3, 0.2, -0.05), 0.09, 0.09, 0.2, 10)
	mm.set_mat(M.L_METAL, Color(0.3, 0.35, 0.42))
	mm.box(Vector3(x - 0.3, h, z - 0.2), Vector3(x - 0.1, h + 0.1, z))
	for i in 6:
		mm.set_mat(M.L_ROUGH_WOOD, Color(0.82, 0.68, 0.48))
		_flat(mm, Vector3(rng.randf_range(-x * 0.2, x * 0.6), h, rng.randf_range(-z * 0.6, z * 0.6)), Vector2(0.06, 0.015), rng.randf() * TAU, 0.006)
	# pegboard on the wall: some tools gone, their outlines left behind
	mm.set_mat(M.L_PLAIN, Color(0.7, 0.58, 0.43))
	mm.box(Vector3(-x + 0.05, h + 0.25, -z - 0.03), Vector3(x - 0.05, h + 0.95, -z - 0.012))
	for i in 7:
		var tx := -x + 0.2 + i * (w - 0.4) / 6.0
		var th := rng.randf_range(0.2, 0.42)
		if rng.randf() < 0.4:
			mm.set_mat(M.L_PLAIN, Color(0.45, 0.36, 0.26))
			mm.box(Vector3(tx - 0.025, h + 0.4, -z - 0.012), Vector3(tx + 0.025, h + 0.4 + th, -z - 0.011))
		else:
			mm.set_mat(M.L_METAL, Color(0.2, 0.2, 0.22))
			mm.box(Vector3(tx - 0.02, h + 0.4, -z - 0.012), Vector3(tx + 0.02, h + 0.4 + th, -z + 0.005))


static func _washer(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator, dryer: bool) -> void:
	var x := w * 0.5
	var z := d * 0.5
	mm.set_mat(M.L_GLOSSY, Color(0.88, 0.88, 0.86), 0.08)
	_cbox(mm, Vector3(-x, 0, -z), Vector3(x, h, z), 0.025)
	var c := Vector3(0, h * 0.45, z)
	var ring := PackedVector3Array()
	var inner := PackedVector3Array()
	var rr := minf(0.21, w * 0.34)
	for k in 14:
		var a := TAU * k / 14.0
		ring.append(c + Vector3(cos(a) * rr, sin(a) * rr, 0.004))
		inner.append(c + Vector3(cos(a) * rr * 0.76, sin(a) * rr * 0.76, 0.008))
	mm.set_mat(M.L_METAL, Color(0.6, 0.62, 0.64) if not dryer else Color(0.32, 0.33, 0.35))
	mm.poly(ring, Vector3.BACK)
	mm.set_mat(M.L_SCREEN, Color(0.12, 0.16, 0.18) if not dryer else Color(0.07, 0.07, 0.08))
	mm.poly(inner, Vector3.BACK)
	mm.set_mat(M.L_PLAIN, Color(0.74, 0.75, 0.75))
	mm.box(Vector3(-x + 0.03, h - 0.1, z), Vector3(x - 0.03, h - 0.03, z + 0.006))
	mm.set_mat(M.L_PLAIN, Color(0.3, 0.3, 0.32))
	mm.tube(Vector3(x - 0.1, h - 0.065, z), Vector3(x - 0.1, h - 0.065, z + 0.018), 0.025, 0.025, 8)
	if dryer:
		mm.box(Vector3(-x + 0.06, h - 0.085, z + 0.006), Vector3(-x + 0.2, h - 0.045, z + 0.008))
		# a heap of laundry nobody folded
		mm.set_mat(M.L_FABRIC, Color(0.55, 0.6, 0.66), 0.05)
		mm.blob(Vector3(-0.05, h + 0.04, 0.0), Vector3(w * 0.3, 0.05, d * 0.3), 3, 7)
		mm.set_mat(M.L_FABRIC, Color(0.82, 0.78, 0.7))
		mm.blob(Vector3(0.1, h + 0.06, -0.05), Vector3(0.12, 0.04, 0.1), 3, 6)
	else:
		mm.set_mat(M.L_PLAIN, Color(0.4, 0.55, 0.62))
		mm.box(Vector3(-x + 0.05, h, -z + 0.05), Vector3(-x + 0.25, h + 0.1, -z + 0.18))


static func _shelves(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	mm.set_mat(M.L_METAL, Color(0.45, 0.47, 0.5), 0.15)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mm.box(Vector3(sx * x - 0.015 - sx * 0.015, 0, sz * z - 0.015 - sz * 0.015), Vector3(sx * x + 0.015 - sx * 0.015, h, sz * z + 0.015 - sz * 0.015))
	var cols := [CARDBOARD, Color(0.25, 0.35, 0.5), Color(0.82, 0.8, 0.74), Color(0.68, 0.26, 0.2), Color(0.4, 0.45, 0.35)]
	var levels := clampi(int(round(h / 0.45)), 2, 6)
	for i in levels + 1:
		var y := 0.1 + (h - 0.12) * i / levels
		mm.set_mat(M.L_METAL, Color(0.5, 0.52, 0.55), 0.12)
		mm.box(Vector3(-x, y - 0.02, -z), Vector3(x, y, z))
		if i == levels:
			break
		var bx := -x + 0.05
		var room := (h - 0.12) / levels - 0.05
		while bx < x - 0.15:
			if rng.randf() < 0.3:
				bx += rng.randf_range(0.15, 0.35)     # already taken
				continue
			var bw := rng.randf_range(0.18, 0.36)
			var bh := minf(rng.randf_range(0.15, 0.3), room)
			var col: Color = cols[rng.randi() % cols.size()]
			if rng.randf() < 0.4:
				mm.set_mat(M.L_METAL, col)
				if rng.randf() < 0.3:
					mm.tube(Vector3(bx + 0.05, y + 0.07, -0.05), Vector3(bx + 0.15, y + 0.07, 0.06), 0.07, 0.07, 8)
				else:
					mm.cylinder(Vector3(bx + 0.09, y, 0), 0.08, 0.08, bh * 0.8, 8)
				bx += 0.2
			else:
				mm.set_mat(M.L_PAPER if col == CARDBOARD else M.L_PLAIN, col)
				mm.box(Vector3(bx, y, -z + 0.03), Vector3(minf(bx + bw, x - 0.03), y + bh, z - 0.03))
				bx += bw + 0.03


static func _boxes(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var b1 := Vector3(minf(0.5, w * 0.48), minf(0.38, h * 0.63), minf(0.5, d * 0.75))
	var b2 := Vector3(minf(0.45, w * 0.45), minf(0.32, h * 0.55), minf(0.42, d * 0.62))
	var b3 := Vector3(minf(0.38, w * 0.4), minf(0.22, h - b1.y), minf(0.4, d * 0.6))
	var spots := [[Vector3(-w * 0.24, 0, 0), b1, false], [Vector3(w * 0.24, 0, -0.04), b2, true], [Vector3(-w * 0.22, b1.y, 0.02), b3, false]]
	for s in spots:
		var p: Vector3 = s[0]
		var sz: Vector3 = s[1]
		var b := Basis(Vector3.UP, rng.randf_range(-0.2, 0.2))
		var col := CARDBOARD.darkened(rng.randf_range(0.0, 0.15))
		mm.set_mat(M.L_PAPER, col, 0.12)
		if s[2]:
			# opened and rummaged: flaps up, dark inside
			var t := Transform3D(b, p)
			var keep := mm.xf
			mm.xf = mm.xf * t
			mm.box(Vector3(-sz.x * 0.5, 0, -sz.z * 0.5), Vector3(sz.x * 0.5, sz.y, sz.z * 0.5), ["+y"])
			mm.set_mat(M.L_PAPER, col.darkened(0.45))
			mm.box_inside(Vector3(-sz.x * 0.5 + 0.004, 0.004, -sz.z * 0.5 + 0.004), Vector3(sz.x * 0.5 - 0.004, sz.y, sz.z * 0.5 - 0.004), ["+y"])
			mm.set_mat(M.L_PAPER, col.lightened(0.05))
			mm.obox(Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0, sz.y + sin(0.5) * sz.z * 0.25, -sz.z * 0.5 - cos(0.5) * 0.004)), Vector3(sz.x - 0.01, 0.004, sz.z * 0.5))
			mm.obox(Transform3D(Basis(Vector3.RIGHT, 0.6), Vector3(0, sz.y + sin(0.6) * sz.z * 0.2, sz.z * 0.5 - 0.02)), Vector3(sz.x - 0.01, 0.004, sz.z * 0.4))
			mm.xf = keep
		else:
			mm.obox(Transform3D(b, p + Vector3(0, sz.y * 0.5, 0)), sz)
			mm.set_mat(M.L_PLAIN, Color(0.72, 0.65, 0.5))
			mm.obox(Transform3D(b, p + Vector3(0, sz.y + 0.002, 0)), Vector3(0.06, 0.004, sz.z + 0.004))
			mm.set_mat(M.L_PLAIN, Color(0.15, 0.15, 0.16))
			mm.obox(Transform3D(b, p + Vector3(sz.x * 0.15, sz.y * 0.55, sz.z * 0.5 + 0.002)), Vector3(sz.x * 0.4, 0.05, 0.002))
