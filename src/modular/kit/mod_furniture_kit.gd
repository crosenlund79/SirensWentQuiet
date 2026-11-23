class_name ModFurnitureKit
extends RefCounted
## Kit pieces: furniture and yard props, built from a few chamfered boxes,
## prisms and blobs with the shared kit shader. One mesh (one draw call) per
## piece. Canonical frame: footprint centred on the origin, width w along x,
## depth d along z, the FRONT facing +z, floor at y = 0.

const M := preload("res://src/modular/kit/mod_materials.gd")

# A small curated palette (sRGB).
const OAK := Color(0.78, 0.6, 0.4)
const WALNUT := Color(0.48, 0.33, 0.22)
const BLACK := Color(0.12, 0.12, 0.13)
const WHITE := Color(0.93, 0.92, 0.89)
const STEEL := Color(0.72, 0.74, 0.75)
const TEAL := Color(0.3, 0.45, 0.46)
const RUST := Color(0.66, 0.33, 0.2)
const MUSTARD := Color(0.8, 0.6, 0.22)
const SAGE := Color(0.5, 0.58, 0.5)
const SLATE := Color(0.34, 0.4, 0.5)
const CARDBOARD := Color(0.66, 0.52, 0.36)

static var _cache := {}


## Impact material for effects.
static func material_of(type: String) -> String:
	match type:
		"fridge", "stove", "washer", "dryer", "water_heater", "car", "streetlight_dead", "mailbox", "shelves", "floor_lamp":
			return "metal"
		"sofa", "armchair", "bed", "rug":
			return "fabric"
		"dead_tree", "deck":
			return "wood"
		"path", "driveway", "step", "road":
			return "ground"
		"trash_bin_tipped":
			return "plastic"
		_:
			return "wood"


static func build(item: Dictionary) -> ArrayMesh:
	var type: String = item["type"]
	var rect: Rect2 = item["rect"]
	var facing: String = item.get("facing", "S")
	var turned := facing == "E" or facing == "W"
	var w := rect.size.y if turned else rect.size.x
	var d := rect.size.x if turned else rect.size.y
	var h: float = item["height"]
	var key := "%s|%.2f|%.2f|%.2f|%s" % [type, w, d, h, item.get("id", "")]
	if _cache.has(key):
		return _cache[key]
	var mm := ModMesh.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(item.get("id", type))
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
			_washer(mm, w, d, h, rng)
		"dryer":
			_dryer(mm, w, d, h, rng)
		"shelves":
			_shelves(mm, w, d, h, rng)
		"boxes":
			_boxes(mm, w, d, h, rng)
		"deck":
			_deck(mm, w, d, h, rng)
		"path":
			_path(mm, w, d, h, rng)
		"road":
			_road(mm, w, d, h, rng)
		"driveway":
			_driveway(mm, w, d, h, rng)
		"step":
			_step(mm, w, d, h, rng)
		"car":
			_car(mm, w, d, h, rng)
		"dead_tree":
			_dead_tree(mm, w, d, h, rng)
		"trash_bin_tipped":
			_trash_bin_tipped(mm, w, d, h, rng)
		"mailbox":
			_mailbox(mm, w, d, h, rng)
		"streetlight_dead":
			_streetlight_dead(mm, w, d, h, rng)
		_:
			mm.set_mat(M.L_PLAIN, Color(0.6, 0.6, 0.6))
			mm.chamfer_box(Vector3(-w * 0.5, 0, -d * 0.5), Vector3(w * 0.5, h, d * 0.5), 0.03)
	var mesh := mm.commit()
	_cache[key] = mesh
	return mesh


## Rotation (about Y) that turns the canonical +z front to the plan facing.
static func facing_basis(facing: String) -> Basis:
	match facing:
		"N":
			return Basis(Vector3.UP, PI)
		"E":
			return Basis(Vector3.UP, PI * 0.5)
		"W":
			return Basis(Vector3.UP, -PI * 0.5)
	return Basis.IDENTITY


# --- helpers ------------------------------------------------------------------------------

static func _legs(mm: ModMesh, w: float, d: float, h: float, inset: float, r: float, col: Color, layer := M.L_METAL) -> void:
	mm.set_mat(layer, col)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mm.cylinder(Vector3(sx * (w * 0.5 - inset), 0, sz * (d * 0.5 - inset)), r * 0.8, r, h, 6)


static func _cbox(mm: ModMesh, lo: Vector3, hi: Vector3, r := 0.02) -> void:
	mm.chamfer_box(lo, hi, r)


# --- living room ------------------------------------------------------------------------------

static func _sofa(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	_legs(mm, w - 0.1, d - 0.1, 0.1, 0.04, 0.025, WALNUT, M.L_WOOD)
	mm.set_mat(M.L_FABRIC, TEAL)
	_cbox(mm, Vector3(-x, 0.1, -z), Vector3(x, 0.38, z), 0.04)
	# back and arms
	_cbox(mm, Vector3(-x, 0.36, -z), Vector3(x, h, -z + 0.24), 0.07)
	_cbox(mm, Vector3(-x, 0.36, -z), Vector3(-x + 0.2, 0.64, z), 0.06)
	_cbox(mm, Vector3(x - 0.2, 0.36, -z), Vector3(x, 0.64, z), 0.06)
	# seat cushions
	mm.set_mat(M.L_FABRIC, TEAL.lightened(0.06))
	var n := 3
	var sw := (w - 0.4) / n
	for i in n:
		var cx := -x + 0.2 + sw * i
		_cbox(mm, Vector3(cx + 0.008, 0.38, -z + 0.22), Vector3(cx + sw - 0.008, 0.5, z - 0.02), 0.05)
		_cbox(mm, Vector3(cx + 0.01, 0.5, -z + 0.06), Vector3(cx + sw - 0.01, h - 0.05, -z + 0.26), 0.06)
	# throw pillows and a blanket
	mm.set_mat(M.L_FABRIC, MUSTARD)
	mm.obox(Transform3D(Basis(Vector3.FORWARD, 0.25) * Basis(Vector3.RIGHT, -0.3), Vector3(-x + 0.38, 0.66, -z + 0.32)), Vector3(0.36, 0.34, 0.12))
	mm.set_mat(M.L_FABRIC, RUST.lightened(0.1))
	mm.obox(Transform3D(Basis(Vector3.FORWARD, -0.2) * Basis(Vector3.RIGHT, -0.3), Vector3(x - 0.4, 0.66, -z + 0.32)), Vector3(0.34, 0.32, 0.12))
	mm.set_mat(M.L_FABRIC, Color(0.85, 0.82, 0.76))
	mm.box(Vector3(x - 0.7, 0.5, -z + 0.25), Vector3(x - 0.22, 0.52, z + 0.02))
	mm.box(Vector3(x - 0.7, 0.22, z), Vector3(x - 0.22, 0.52, z + 0.02))


static func _armchair(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	_legs(mm, w - 0.08, d - 0.08, 0.12, 0.04, 0.022, WALNUT, M.L_WOOD)
	mm.set_mat(M.L_FABRIC, RUST)
	_cbox(mm, Vector3(-x, 0.12, -z), Vector3(x, 0.38, z), 0.04)
	_cbox(mm, Vector3(-x, 0.36, -z), Vector3(x, h, -z + 0.2), 0.07)
	_cbox(mm, Vector3(-x, 0.36, -z), Vector3(-x + 0.15, 0.62, z), 0.05)
	_cbox(mm, Vector3(x - 0.15, 0.36, -z), Vector3(x, 0.62, z), 0.05)
	mm.set_mat(M.L_FABRIC, RUST.lightened(0.08))
	_cbox(mm, Vector3(-x + 0.15, 0.38, -z + 0.18), Vector3(x - 0.15, 0.5, z - 0.02), 0.05)


static func _coffee_table(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	_legs(mm, w, d, h - 0.04, 0.06, 0.018, BLACK)
	mm.set_mat(M.L_WOOD, OAK)
	_cbox(mm, Vector3(-w * 0.5, h - 0.045, -d * 0.5), Vector3(w * 0.5, h, d * 0.5), 0.015)
	mm.box(Vector3(-w * 0.5 + 0.06, 0.12, -d * 0.5 + 0.06), Vector3(w * 0.5 - 0.06, 0.14, d * 0.5 - 0.06))
	# a stack of books and a mug
	var cols := [Color(0.7, 0.25, 0.2), Color(0.25, 0.35, 0.5), Color(0.85, 0.8, 0.7)]
	for i in 3:
		mm.set_mat(M.L_PLAIN, cols[i])
		var bw := 0.24 - i * 0.02
		mm.obox(Transform3D(Basis(Vector3.UP, 0.15 * i - 0.1), Vector3(-0.22, h + 0.015 + i * 0.03, -0.05)), Vector3(bw, 0.028, 0.17))
	mm.set_mat(M.L_GLOSSY, Color(0.9, 0.88, 0.84))
	mm.cylinder(Vector3(0.25, h, 0.08), 0.04, 0.045, 0.09, 8)


static func _tv_stand(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	_legs(mm, w - 0.1, d - 0.06, 0.12, 0.03, 0.02, BLACK)
	mm.set_mat(M.L_WOOD, WALNUT)
	_cbox(mm, Vector3(-x, 0.12, -z), Vector3(x, 0.5, z), 0.012)
	mm.set_mat(M.L_WOOD, WALNUT.darkened(0.25))
	for i in 3:
		var cx := -x + w / 3.0 * (i + 0.5)
		mm.box(Vector3(cx - w / 6.0 + 0.012, 0.15, z), Vector3(cx + w / 6.0 - 0.012, 0.47, z + 0.006))
	# television
	mm.set_mat(M.L_PLAIN, BLACK)
	mm.box(Vector3(-0.15, 0.5, -0.06), Vector3(0.15, 0.52, 0.1))
	mm.box(Vector3(-0.03, 0.52, -0.02), Vector3(0.03, 0.62, 0.02))
	var tw := minf(1.25, w * 0.7)
	mm.box(Vector3(-tw * 0.5, 0.56, -0.035), Vector3(tw * 0.5, h + 0.12, 0.0))
	mm.set_mat(M.L_SCREEN, Color(0.07, 0.08, 0.1))
	mm.box(Vector3(-tw * 0.5 + 0.015, 0.575, 0.0), Vector3(tw * 0.5 - 0.015, h + 0.105, 0.004))
	# a speaker and a small plant
	mm.set_mat(M.L_PLAIN, Color(0.2, 0.2, 0.21))
	_cbox(mm, Vector3(x - 0.3, 0.5, -0.1), Vector3(x - 0.12, 0.8, 0.1), 0.02)
	mm.set_mat(M.L_GLOSSY, WHITE)
	mm.cylinder(Vector3(-x + 0.2, 0.5, 0.0), 0.07, 0.09, 0.14, 8)
	mm.set_mat(M.L_PLAIN, Color(0.32, 0.4, 0.24))
	mm.blob(Vector3(-x + 0.2, 0.72, 0.0), Vector3(0.13, 0.12, 0.13), 3, 6)


static func _rug(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var y := 0.031
	var big := w > 1.5
	var base := Color(0.86, 0.8, 0.7) if big else Color(0.75, 0.84, 0.88)
	mm.set_mat(M.L_FABRIC, base)
	mm.quad(Vector3(-w * 0.5, y, -d * 0.5), Vector3(w * 0.5, y, -d * 0.5), Vector3(w * 0.5, y, d * 0.5), Vector3(-w * 0.5, y, d * 0.5), Vector3.UP)
	if not big:
		return
	var accent := Color(0.66, 0.38, 0.3) if w > 3.0 else Color(0.44, 0.5, 0.56)
	mm.set_mat(M.L_FABRIC, accent)
	var b := 0.12
	var y2 := y + 0.002
	for r in [[-w * 0.5 + 0.08, -d * 0.5 + 0.08, w * 0.5 - 0.08, -d * 0.5 + 0.08 + b], [-w * 0.5 + 0.08, d * 0.5 - 0.08 - b, w * 0.5 - 0.08, d * 0.5 - 0.08],
			[-w * 0.5 + 0.08, -d * 0.5 + 0.08, -w * 0.5 + 0.08 + b, d * 0.5 - 0.08], [w * 0.5 - 0.08 - b, -d * 0.5 + 0.08, w * 0.5 - 0.08, d * 0.5 - 0.08]]:
		mm.quad(Vector3(r[0], y2, r[1]), Vector3(r[2], y2, r[1]), Vector3(r[2], y2, r[3]), Vector3(r[0], y2, r[3]), Vector3.UP)
	# a few diamonds in the field
	mm.set_mat(M.L_FABRIC, accent.lightened(0.25))
	var n := 3 if w > 3.0 else 2
	for i in n:
		var cx := -w * 0.5 + w * (i + 0.5) / n
		var s := minf(d, w / n) * 0.22
		mm.poly(PackedVector3Array([Vector3(cx, y2, -s), Vector3(cx + s, y2, 0), Vector3(cx, y2, s), Vector3(cx - s, y2, 0)]), Vector3.UP)


static func _floor_lamp(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	mm.set_mat(M.L_METAL, BLACK)
	mm.cylinder(Vector3.ZERO, 0.16, 0.15, 0.03, 10)
	mm.cylinder(Vector3(0, 0.03, 0), 0.015, 0.015, h - 0.3, 6)
	mm.set_mat(M.L_EMISSIVE, Color(0.96, 0.88, 0.72))
	mm.cylinder(Vector3(0, h - 0.32, 0), 0.2, 0.13, 0.3, 10, false)
	mm.set_mat(M.L_EMISSIVE, Color(1.0, 0.85, 0.6))
	mm.blob(Vector3(0, h - 0.2, 0), Vector3(0.05, 0.06, 0.05), 3, 6)


static func _bookshelf(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	mm.set_mat(M.L_PLAIN, WHITE)
	mm.box(Vector3(-x, 0, -z), Vector3(x, h, -z + 0.02))
	mm.box(Vector3(-x, 0, -z), Vector3(-x + 0.025, h, z))
	mm.box(Vector3(x - 0.025, 0, -z), Vector3(x, h, z))
	var shelves := 5
	var book_cols := [Color(0.62, 0.22, 0.18), Color(0.2, 0.3, 0.45), Color(0.82, 0.74, 0.55), Color(0.3, 0.42, 0.33), Color(0.85, 0.83, 0.78), Color(0.45, 0.3, 0.42), Color(0.8, 0.55, 0.2)]
	for i in shelves + 1:
		var y := 0.06 + (h - 0.08) * i / shelves
		mm.set_mat(M.L_PLAIN, WHITE)
		mm.box(Vector3(-x, y - 0.025, -z), Vector3(x, y, z))
		if i == shelves:
			break
		var bx := -x + 0.04
		var top := (h - 0.08) / shelves - 0.05
		while bx < x - 0.1:
			var bw := rng.randf_range(0.025, 0.05)
			var bh := rng.randf_range(0.6, 0.95) * top
			if rng.randf() < 0.12:
				bx += rng.randf_range(0.05, 0.15)
				continue
			mm.set_mat(M.L_PLAIN, book_cols[rng.randi() % book_cols.size()].darkened(rng.randf_range(0, 0.2)))
			var lean := 0.0 if rng.randf() < 0.85 else 0.25
			mm.obox(Transform3D(Basis(Vector3.BACK, lean), Vector3(bx + bw * 0.5, y + bh * 0.5, 0.01)), Vector3(bw, bh, d * 0.75))
			bx += bw + 0.004
	mm.set_mat(M.L_GLOSSY, Color(0.75, 0.42, 0.3))
	mm.cylinder(Vector3(0, h, 0.0), 0.06, 0.08, 0.13, 8)
	mm.set_mat(M.L_PLAIN, Color(0.3, 0.38, 0.22))
	mm.blob(Vector3(0, h + 0.2, 0), Vector3(0.12, 0.12, 0.12), 3, 6)


static func _dining_table(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	mm.set_mat(M.L_WOOD, OAK)
	_cbox(mm, Vector3(-w * 0.5, h - 0.045, -d * 0.5), Vector3(w * 0.5, h, d * 0.5), 0.015)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mm.tube(Vector3(sx * (w * 0.5 - 0.12), h - 0.045, sz * (d * 0.5 - 0.1)), Vector3(sx * (w * 0.5 - 0.08), 0, sz * (d * 0.5 - 0.06)), 0.03, 0.02, 6)
	# bowl, candle, an abandoned plate
	mm.set_mat(M.L_GLOSSY, Color(0.3, 0.36, 0.4))
	mm.cylinder(Vector3(0, h, 0), 0.08, 0.14, 0.08, 10)
	mm.set_mat(M.L_PLAIN, Color(0.75, 0.32, 0.2))
	mm.blob(Vector3(0.03, h + 0.09, 0.02), Vector3(0.04, 0.04, 0.04), 3, 6)
	mm.blob(Vector3(-0.04, h + 0.09, -0.02), Vector3(0.04, 0.04, 0.04), 3, 6)
	mm.set_mat(M.L_GLOSSY, WHITE)
	mm.cylinder(Vector3(0.5, h, 0.2), 0.12, 0.13, 0.015, 12)


static func _chair(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	_legs(mm, w - 0.02, d - 0.02, 0.45, 0.03, 0.016, BLACK)
	mm.set_mat(M.L_WOOD, OAK.darkened(0.08))
	_cbox(mm, Vector3(-w * 0.5 + 0.02, 0.43, -d * 0.5 + 0.02), Vector3(w * 0.5 - 0.02, 0.47, d * 0.5 - 0.02), 0.012)
	mm.set_mat(M.L_METAL, BLACK)
	for sx in [-1.0, 1.0]:
		mm.box(Vector3(sx * (w * 0.5 - 0.04) - 0.012, 0.47, -d * 0.5 + 0.02), Vector3(sx * (w * 0.5 - 0.04) + 0.012, h, -d * 0.5 + 0.045))
	mm.set_mat(M.L_WOOD, OAK.darkened(0.08))
	mm.box(Vector3(-w * 0.5 + 0.03, h - 0.14, -d * 0.5 + 0.015), Vector3(w * 0.5 - 0.03, h - 0.02, -d * 0.5 + 0.05))


static func _plant(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	mm.set_mat(M.L_GLOSSY, Color(0.72, 0.4, 0.28))
	mm.cylinder(Vector3.ZERO, 0.15, 0.2, 0.38, 10)
	mm.set_mat(M.L_SOIL, Color(0.28, 0.22, 0.18))
	mm.cylinder(Vector3(0, 0.33, 0), 0.18, 0.18, 0.02, 10)
	# drooping leaves, some of them dying
	for i in 11:
		var a := TAU * i / 11.0 + rng.randf_range(-0.2, 0.2)
		var up := rng.randf_range(0.35, 0.75)
		var length := rng.randf_range(0.35, 0.6)
		var base := Vector3(0, 0.35, 0)
		var dir := Vector3(cos(a) * (1.0 - up), up, sin(a) * (1.0 - up)).normalized()
		var tip := base + dir * length
		tip.y -= rng.randf_range(0.0, 0.12)
		var dying := rng.randf() < 0.35
		mm.set_mat(M.L_PLAIN, Color(0.62, 0.55, 0.28) if dying else Color(0.24, 0.36, 0.2).lightened(rng.randf_range(0.0, 0.15)))
		var side := dir.cross(Vector3.UP).normalized() * rng.randf_range(0.06, 0.09)
		var mid := base.lerp(tip, 0.5) + Vector3(0, 0.05, 0)
		mm.tri(base, mid + side, tip, Vector3.ZERO)
		mm.tri(base, tip, mid - side, Vector3.ZERO)


# --- kitchen ------------------------------------------------------------------------------------

static func _fridge(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	mm.set_mat(M.L_METAL, STEEL)
	_cbox(mm, Vector3(-x, 0.02, -z), Vector3(x, h, z), 0.03)
	mm.set_mat(M.L_PLAIN, BLACK)
	mm.box(Vector3(-x + 0.02, h * 0.62, z), Vector3(x - 0.02, h * 0.62 + 0.012, z + 0.004))
	mm.set_mat(M.L_METAL, Color(0.55, 0.56, 0.57))
	mm.box(Vector3(x - 0.09, h * 0.67, z + 0.02), Vector3(x - 0.06, h * 0.95, z + 0.05))
	mm.box(Vector3(x - 0.09, h * 0.3, z + 0.02), Vector3(x - 0.06, h * 0.58, z + 0.05))
	# notes and a child's drawing held by magnets
	var notes := [Color(0.95, 0.9, 0.55), Color(0.95, 0.95, 0.93), Color(0.7, 0.85, 0.95)]
	for i in 3:
		mm.set_mat(M.L_PLAIN, notes[i])
		var nx := -x + 0.1 + i * 0.17
		var ny := h * 0.74 + rng.randf_range(-0.05, 0.08)
		mm.obox(Transform3D(Basis(Vector3.BACK, rng.randf_range(-0.2, 0.2)), Vector3(nx + 0.06, ny, z + 0.003)), Vector3(0.12, 0.15, 0.003))


static func _counter_body(mm: ModMesh, w: float, d: float, h: float, cab: Color, top: Color, top_layer: int, doors := 0) -> void:
	var x := w * 0.5
	var z := d * 0.5
	mm.set_mat(M.L_PLAIN, Color(0.15, 0.15, 0.16))
	mm.box(Vector3(-x, 0, -z), Vector3(x, 0.1, z - 0.06))
	mm.set_mat(M.L_PLAIN, cab)
	mm.box(Vector3(-x, 0.1, -z), Vector3(x, h - 0.04, z))
	mm.set_mat(top_layer, top)
	_cbox(mm, Vector3(-x - 0.005, h - 0.04, -z), Vector3(x + 0.005, h, z + 0.025), 0.008)
	# door / drawer fronts and handles
	var n := doors if doors > 0 else maxi(1, int(round(w / 0.5)))
	var dw := w / n
	for i in n:
		var cx := -x + dw * (i + 0.5)
		mm.set_mat(M.L_PLAIN, cab.darkened(0.12))
		mm.box(Vector3(cx - dw * 0.5 + 0.004, 0.11, z), Vector3(cx - dw * 0.5 + 0.008, h - 0.05, z + 0.004))
		mm.box(Vector3(cx - dw * 0.5, h - 0.24, z), Vector3(cx + dw * 0.5, h - 0.236, z + 0.004))
		mm.set_mat(M.L_METAL, Color(0.25, 0.25, 0.26))
		mm.box(Vector3(cx - 0.07, h - 0.15, z + 0.004), Vector3(cx + 0.07, h - 0.135, z + 0.025))
		mm.box(Vector3(cx + dw * 0.5 - 0.06, h - 0.45, z + 0.004), Vector3(cx + dw * 0.5 - 0.045, h - 0.3, z + 0.025))


static func _counter(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	_counter_body(mm, w, d, h, Color(0.9, 0.89, 0.85), Color(0.3, 0.31, 0.32), M.L_GLOSSY)
	# a few things left on the counter
	if w > 1.2:
		mm.set_mat(M.L_WOOD, OAK)
		mm.box(Vector3(-0.2, h, -0.15), Vector3(0.15, h + 0.02, 0.08))
		mm.set_mat(M.L_GLOSSY, Color(0.85, 0.3, 0.2))
		mm.cylinder(Vector3(0.45, h, -0.1), 0.06, 0.06, 0.18, 8)
	elif w > 0.9:
		mm.set_mat(M.L_GLOSSY, Color(0.92, 0.9, 0.86))
		mm.cylinder(Vector3(-0.1, h, -0.12), 0.05, 0.06, 0.12, 8)


static func _sink_counter(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	_counter_body(mm, w, d, h, Color(0.9, 0.89, 0.85), Color(0.3, 0.31, 0.32), M.L_GLOSSY, 2)
	mm.set_mat(M.L_METAL, STEEL)
	mm.box(Vector3(-0.32, h, -0.2), Vector3(0.32, h + 0.006, 0.2))
	mm.set_mat(M.L_METAL, Color(0.35, 0.36, 0.37))
	mm.box(Vector3(-0.28, h - 0.15, -0.17), Vector3(0.28, h + 0.007, 0.17), ["+y"])
	mm.set_mat(M.L_METAL, STEEL)
	mm.cylinder(Vector3(0, h, -0.24), 0.025, 0.02, 0.32, 6)
	mm.tube(Vector3(0, h + 0.32, -0.24), Vector3(0, h + 0.28, -0.06), 0.015, 0.015, 6)


static func _stove(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	mm.set_mat(M.L_METAL, STEEL)
	mm.box(Vector3(-x, 0.0, -z), Vector3(x, h - 0.03, z))
	mm.set_mat(M.L_SCREEN, Color(0.06, 0.06, 0.07))
	mm.box(Vector3(-x, h - 0.03, -z), Vector3(x, h, z))
	mm.set_mat(M.L_PLAIN, Color(0.35, 0.35, 0.36))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var c := Vector3(sx * w * 0.22, h + 0.002, sz * d * 0.22)
			mm.cylinder(c, 0.09, 0.09, 0.002, 10, true)
	mm.set_mat(M.L_SCREEN, Color(0.08, 0.09, 0.1))
	mm.box(Vector3(-x + 0.06, 0.15, z), Vector3(x - 0.06, h - 0.2, z + 0.006))
	mm.set_mat(M.L_METAL, Color(0.6, 0.6, 0.6))
	mm.box(Vector3(-x + 0.08, h - 0.17, z + 0.02), Vector3(x - 0.08, h - 0.15, z + 0.04))
	# range hood above (its light is a HousePlan light)
	mm.set_mat(M.L_METAL, STEEL)
	var hb := 1.62
	mm.box(Vector3(-x - 0.03, hb, -z), Vector3(x + 0.03, hb + 0.08, z - 0.05))
	mm.box(Vector3(-0.15, hb + 0.08, -z), Vector3(0.15, HousePlan.WALL_HEIGHT - 0.02, -z + 0.25))
	mm.set_mat(M.L_EMISSIVE, Color(1.0, 0.86, 0.62))
	mm.box(Vector3(-0.12, hb - 0.004, -z + 0.12), Vector3(0.12, hb, -z + 0.22))


static func _island(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	_counter_body(mm, w, d - 0.2, h, Color(0.42, 0.5, 0.44), OAK, M.L_WOOD, 3)
	mm.set_mat(M.L_WOOD, OAK)
	_cbox(mm, Vector3(-w * 0.5 - 0.02, h - 0.045, -d * 0.5), Vector3(w * 0.5 + 0.02, h, d * 0.5), 0.01)
	# fruit bowl, a bottle, an overturned glass
	mm.set_mat(M.L_GLOSSY, WHITE)
	mm.cylinder(Vector3(-0.4, h, 0.0), 0.08, 0.14, 0.07, 10)
	mm.set_mat(M.L_PLAIN, Color(0.6, 0.55, 0.2))
	mm.blob(Vector3(-0.38, h + 0.08, 0.01), Vector3(0.05, 0.04, 0.05), 3, 6)
	mm.set_mat(M.L_SCREEN, Color(0.15, 0.28, 0.18))
	mm.cylinder(Vector3(0.3, h, -0.1), 0.035, 0.035, 0.22, 8)
	mm.cylinder(Vector3(0.3, h + 0.22, -0.1), 0.012, 0.012, 0.08, 6)
	mm.set_mat(M.L_MIRROR, Color(0.75, 0.82, 0.85))
	mm.tube(Vector3(0.5, h + 0.03, 0.15), Vector3(0.62, h + 0.03, 0.2), 0.03, 0.035, 8)


static func _stool(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	mm.set_mat(M.L_METAL, BLACK)
	for k in 4:
		var a := TAU * (k + 0.5) / 4.0
		mm.tube(Vector3(cos(a) * 0.1, h - 0.04, sin(a) * 0.1), Vector3(cos(a) * 0.17, 0, sin(a) * 0.17), 0.012, 0.012, 5)
	mm.cylinder(Vector3(0, 0.25, 0), 0.15, 0.15, 0.015, 10, false)
	mm.set_mat(M.L_WOOD, OAK)
	mm.cylinder(Vector3(0, h - 0.04, 0), 0.17, 0.17, 0.04, 12)


# --- bedroom ------------------------------------------------------------------------------------

static func _bed(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	mm.set_mat(M.L_WOOD, OAK)
	_cbox(mm, Vector3(-x, 0.08, -z), Vector3(x, 0.3, z), 0.015)
	_legs(mm, w - 0.05, d - 0.05, 0.08, 0.04, 0.025, OAK.darkened(0.1), M.L_WOOD)
	# headboard
	_cbox(mm, Vector3(-x - 0.02, 0.08, -z - 0.02), Vector3(x + 0.02, 0.98, -z + 0.06), 0.02)
	mm.set_mat(M.L_FABRIC, Color(0.82, 0.8, 0.74))
	_cbox(mm, Vector3(-x + 0.05, 0.4, -z + 0.06), Vector3(x - 0.05, 0.9, -z + 0.1), 0.03)
	# mattress, duvet with a fold, pillows, blanket at the foot
	mm.set_mat(M.L_FABRIC, WHITE)
	_cbox(mm, Vector3(-x + 0.04, 0.3, -z + 0.06), Vector3(x - 0.04, 0.5, z - 0.04), 0.04)
	mm.set_mat(M.L_FABRIC, SLATE)
	_cbox(mm, Vector3(-x + 0.02, 0.32, -z + 0.68), Vector3(x - 0.02, 0.56, z - 0.02), 0.05)
	mm.set_mat(M.L_FABRIC, SLATE.lightened(0.15))
	_cbox(mm, Vector3(-x + 0.02, 0.5, -z + 0.56), Vector3(x - 0.02, 0.585, -z + 0.75), 0.03)
	mm.set_mat(M.L_FABRIC, Color(0.96, 0.95, 0.93))
	for sx in [-1.0, 1.0]:
		mm.obox(Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(sx * w * 0.24, 0.6, -z + 0.28)), Vector3(w * 0.4, 0.14, 0.34))
	mm.set_mat(M.L_FABRIC, MUSTARD)
	mm.box(Vector3(-x + 0.0, 0.56, z - 0.5), Vector3(x - 0.0, 0.59, z - 0.2))
	mm.box(Vector3(-x - 0.01, 0.25, z - 0.5), Vector3(-x + 0.01, 0.59, z - 0.2))
	mm.box(Vector3(x - 0.01, 0.25, z - 0.5), Vector3(x + 0.01, 0.59, z - 0.2))


static func _nightstand(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	_legs(mm, w, d, 0.12, 0.04, 0.015, OAK.darkened(0.1), M.L_WOOD)
	mm.set_mat(M.L_WOOD, OAK)
	_cbox(mm, Vector3(-w * 0.5, 0.12, -d * 0.5), Vector3(w * 0.5, h, d * 0.5), 0.012)
	mm.set_mat(M.L_WOOD, OAK.darkened(0.2))
	mm.box(Vector3(-w * 0.5 + 0.03, h - 0.17, d * 0.5), Vector3(w * 0.5 - 0.03, h - 0.165, d * 0.5 + 0.004))
	mm.set_mat(M.L_METAL, BLACK)
	mm.box(Vector3(-0.05, h - 0.1, d * 0.5), Vector3(0.05, h - 0.085, d * 0.5 + 0.02))


static func _wardrobe(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	mm.set_mat(M.L_PLAIN, Color(0.2, 0.2, 0.2))
	mm.box(Vector3(-x + 0.03, 0, -z), Vector3(x - 0.03, 0.08, z - 0.03))
	mm.set_mat(M.L_PLAIN, WHITE)
	_cbox(mm, Vector3(-x, 0.08, -z), Vector3(x, h, z), 0.012)
	mm.set_mat(M.L_PLAIN, WHITE.darkened(0.12))
	mm.box(Vector3(-0.004, 0.1, z), Vector3(0.004, h - 0.02, z + 0.004))
	mm.set_mat(M.L_WOOD, OAK)
	for sx in [-1.0, 1.0]:
		mm.box(Vector3(sx * 0.06 - 0.012, 0.9, z), Vector3(sx * 0.06 + 0.012, 1.35, z + 0.03))
	# a suitcase on top, half pulled out
	mm.set_mat(M.L_GLOSSY, Color(0.55, 0.22, 0.18))
	_cbox(mm, Vector3(-x + 0.1, h, -z + 0.05), Vector3(x - 0.3, h + 0.24, z - 0.02), 0.03)


static func _dresser(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	_legs(mm, w, d, 0.1, 0.04, 0.016, OAK.darkened(0.1), M.L_WOOD)
	mm.set_mat(M.L_WOOD, OAK)
	_cbox(mm, Vector3(-w * 0.5, 0.1, -d * 0.5), Vector3(w * 0.5, h, d * 0.5), 0.012)
	for row in 3:
		var y := 0.1 + (h - 0.1) * (row + 1) / 3.0
		mm.set_mat(M.L_WOOD, OAK.darkened(0.22))
		mm.box(Vector3(-w * 0.5 + 0.02, y - 0.006, d * 0.5), Vector3(w * 0.5 - 0.02, y, d * 0.5 + 0.004))
		mm.set_mat(M.L_METAL, BLACK)
		for sx in [-1.0, 1.0]:
			mm.box(Vector3(sx * w * 0.25 - 0.05, y - 0.12, d * 0.5), Vector3(sx * w * 0.25 + 0.05, y - 0.105, d * 0.5 + 0.02))
	# picture frame and a jewellery box
	mm.set_mat(M.L_PLAIN, BLACK)
	mm.obox(Transform3D(Basis(Vector3.RIGHT, -0.2), Vector3(-0.3, h + 0.12, -0.05)), Vector3(0.2, 0.25, 0.02))
	mm.set_mat(M.L_PLAIN, Color(0.8, 0.75, 0.62))
	mm.obox(Transform3D(Basis(Vector3.RIGHT, -0.2), Vector3(-0.3, h + 0.12, -0.038)), Vector3(0.15, 0.19, 0.005))
	mm.set_mat(M.L_GLOSSY, Color(0.3, 0.42, 0.45))
	mm.box(Vector3(0.2, h, -0.08), Vector3(0.38, h + 0.08, 0.06))


# --- bathroom -----------------------------------------------------------------------------------

static func _bathtub(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	mm.set_mat(M.L_GLOSSY, Color(0.95, 0.95, 0.94))
	_cbox(mm, Vector3(-x, 0, -z), Vector3(x, h, z), 0.04)
	mm.set_mat(M.L_GLOSSY, Color(0.86, 0.88, 0.9))
	mm.box(Vector3(-x + 0.08, 0.15, -z + 0.08), Vector3(x - 0.08, h + 0.002, z - 0.08), ["+y"])
	mm.set_mat(M.L_MIRROR, Color(0.55, 0.62, 0.6))
	mm.box(Vector3(-x + 0.08, 0.16, -z + 0.08), Vector3(x - 0.08, 0.2, z - 0.08))
	mm.set_mat(M.L_METAL, STEEL)
	mm.cylinder(Vector3(-x + 0.12, h, -z + 0.04), 0.02, 0.02, 0.15, 6)
	mm.tube(Vector3(-x + 0.12, h + 0.15, -z + 0.04), Vector3(-x + 0.12, h + 0.12, -z + 0.16), 0.015, 0.015, 6)


static func _toilet(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var z := d * 0.5
	mm.set_mat(M.L_GLOSSY, Color(0.95, 0.95, 0.94))
	mm.cylinder(Vector3(0, 0, 0.05), 0.13, 0.17, 0.38, 10)
	mm.cylinder(Vector3(0, 0.38, 0.05), 0.2, 0.2, 0.03, 12)
	_cbox(mm, Vector3(-w * 0.45, 0.38, -z), Vector3(w * 0.45, h, -z + 0.2), 0.03)
	mm.set_mat(M.L_METAL, STEEL)
	mm.box(Vector3(-0.04, h, -z + 0.08), Vector3(0.04, h + 0.01, -z + 0.12))


static func _vanity(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	_counter_body(mm, w, d, h - 0.03, OAK, Color(0.95, 0.95, 0.94), M.L_GLOSSY, 2)
	mm.set_mat(M.L_GLOSSY, Color(0.97, 0.97, 0.96))
	mm.cylinder(Vector3(0, h - 0.03, 0.02), 0.16, 0.18, 0.1, 12)
	mm.set_mat(M.L_MIRROR, Color(0.5, 0.56, 0.58))
	mm.cylinder(Vector3(0, h + 0.065, 0.02), 0.14, 0.14, 0.006, 12)
	mm.set_mat(M.L_METAL, STEEL)
	mm.cylinder(Vector3(0, h - 0.03, -d * 0.5 + 0.06), 0.02, 0.016, 0.24, 6)
	mm.tube(Vector3(0, h + 0.21, -d * 0.5 + 0.06), Vector3(0, h + 0.18, -d * 0.5 + 0.18), 0.012, 0.012, 6)
	# mirror on the wall behind
	var zb := -d * 0.5 - 0.025
	mm.set_mat(M.L_PLAIN, BLACK)
	mm.box(Vector3(-w * 0.36, h + 0.3, zb - 0.01), Vector3(w * 0.36, h + 1.05, zb + 0.012))
	mm.set_mat(M.L_MIRROR, Color(0.58, 0.64, 0.66))
	mm.box(Vector3(-w * 0.34, h + 0.32, zb + 0.012), Vector3(w * 0.34, h + 1.03, zb + 0.016))


# --- utility ------------------------------------------------------------------------------------

static func _water_heater(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	mm.set_mat(M.L_GLOSSY, Color(0.88, 0.88, 0.85))
	mm.cylinder(Vector3.ZERO, w * 0.42, w * 0.42, h - 0.12, 12, true, true)
	mm.cylinder(Vector3(0, h - 0.12, 0), w * 0.42, w * 0.3, 0.08, 12)
	mm.set_mat(M.L_METAL, Color(0.72, 0.45, 0.3))
	for sx in [-1.0, 1.0]:
		mm.cylinder(Vector3(sx * 0.08, h - 0.08, -0.05), 0.022, 0.022, HousePlan.WALL_HEIGHT - h + 0.05, 6)
	mm.set_mat(M.L_PLAIN, Color(0.85, 0.3, 0.2))
	mm.box(Vector3(-0.08, 0.5, w * 0.42 - 0.02), Vector3(0.08, 0.62, w * 0.42 + 0.005))


static func _workbench(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	_legs(mm, w, d, h - 0.05, 0.04, 0.025, Color(0.25, 0.27, 0.3))
	mm.set_mat(M.L_WOOD, OAK.darkened(0.1))
	_cbox(mm, Vector3(-x, h - 0.05, -z), Vector3(x, h, z), 0.01)
	mm.box(Vector3(-x + 0.05, 0.18, -z + 0.05), Vector3(x - 0.05, 0.2, z - 0.05))
	# toolbox, paint cans, a vice
	mm.set_mat(M.L_GLOSSY, Color(0.75, 0.2, 0.15))
	_cbox(mm, Vector3(-x + 0.15, h, -0.15), Vector3(-x + 0.6, h + 0.2, 0.08), 0.02)
	mm.set_mat(M.L_METAL, Color(0.5, 0.52, 0.55))
	mm.cylinder(Vector3(0.3, 0.2, 0.0), 0.09, 0.09, 0.2, 10)
	mm.cylinder(Vector3(0.55, 0.2, -0.05), 0.09, 0.09, 0.2, 10)
	mm.set_mat(M.L_METAL, Color(0.3, 0.35, 0.42))
	mm.box(Vector3(x - 0.3, h, z - 0.2), Vector3(x - 0.1, h + 0.12, z))
	# pegboard with tool silhouettes on the wall
	mm.set_mat(M.L_PLAIN, Color(0.72, 0.6, 0.45))
	mm.box(Vector3(-x + 0.05, h + 0.25, -z - 0.03), Vector3(x - 0.05, h + 0.95, -z - 0.012))
	mm.set_mat(M.L_METAL, Color(0.2, 0.2, 0.22))
	for i in 7:
		var tx := -x + 0.2 + i * (w - 0.4) / 6.0
		var th := rng.randf_range(0.2, 0.42)
		mm.box(Vector3(tx - 0.02, h + 0.4, -z - 0.012), Vector3(tx + 0.02, h + 0.4 + th, -z + 0.005))


static func _washer(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	mm.set_mat(M.L_GLOSSY, Color(0.92, 0.92, 0.9))
	_cbox(mm, Vector3(-x, 0, -z), Vector3(x, h, z), 0.025)
	mm.set_mat(M.L_METAL, Color(0.6, 0.62, 0.64))
	var c := Vector3(0, h * 0.45, z)
	var ring := PackedVector3Array()
	var inner := PackedVector3Array()
	for k in 14:
		var a := TAU * k / 14.0
		ring.append(c + Vector3(cos(a) * 0.21, sin(a) * 0.21, 0.004))
		inner.append(c + Vector3(cos(a) * 0.16, sin(a) * 0.16, 0.008))
	mm.poly(ring, Vector3.BACK)
	mm.set_mat(M.L_SCREEN, Color(0.12, 0.16, 0.18))
	mm.poly(inner, Vector3.BACK)
	mm.set_mat(M.L_PLAIN, Color(0.75, 0.76, 0.76))
	mm.box(Vector3(-x + 0.03, h - 0.1, z), Vector3(x - 0.03, h - 0.03, z + 0.006))


static func _dryer(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	_washer(mm, w, d, h, rng)


static func _shelves(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	mm.set_mat(M.L_METAL, Color(0.45, 0.47, 0.5))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mm.box(Vector3(sx * x - 0.015, 0, sz * z - 0.015), Vector3(sx * x + 0.015, h, sz * z + 0.015))
	var cols := [CARDBOARD, Color(0.25, 0.35, 0.55), Color(0.85, 0.85, 0.8), Color(0.75, 0.25, 0.2), Color(0.4, 0.45, 0.35)]
	for i in 5:
		var y := 0.1 + (h - 0.12) * i / 4.0
		mm.set_mat(M.L_METAL, Color(0.5, 0.52, 0.55))
		mm.box(Vector3(-x, y - 0.02, -z), Vector3(x, y, z))
		if i == 4:
			break
		var bx := -x + 0.05
		while bx < x - 0.15:
			var bw := rng.randf_range(0.18, 0.38)
			var bh := rng.randf_range(0.15, 0.3)
			var col: Color = cols[rng.randi() % cols.size()]
			if rng.randf() < 0.4:
				mm.set_mat(M.L_METAL, col)
				mm.cylinder(Vector3(bx + 0.09, y, 0), 0.08, 0.08, bh * 0.8, 8)
				bx += 0.2
			else:
				mm.set_mat(M.L_PLAIN, col)
				mm.box(Vector3(bx, y, -z + 0.03), Vector3(minf(bx + bw, x - 0.03), y + bh, z - 0.03))
				bx += bw + 0.03


static func _boxes(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var spots := [[Vector3(-w * 0.25, 0, 0), Vector3(0.48, 0.38, 0.5)], [Vector3(w * 0.24, 0, -0.05), Vector3(0.45, 0.32, 0.42)], [Vector3(-w * 0.22, 0.38, 0.02), Vector3(0.38, 0.22, 0.4)]]
	for s in spots:
		var p: Vector3 = s[0]
		var sz: Vector3 = s[1]
		var b := Basis(Vector3.UP, rng.randf_range(-0.25, 0.25))
		mm.set_mat(M.L_PLAIN, CARDBOARD.darkened(rng.randf_range(0.0, 0.15)))
		mm.obox(Transform3D(b, p + Vector3(0, sz.y * 0.5, 0)), sz)
		mm.set_mat(M.L_PLAIN, Color(0.75, 0.68, 0.52))
		mm.obox(Transform3D(b, p + Vector3(0, sz.y + 0.002, 0)), Vector3(0.06, 0.004, sz.z + 0.004))


# --- yard props -----------------------------------------------------------------------------------

static func _deck(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var top := 0.06
	mm.set_mat(M.L_WOOD, Color(0.55, 0.5, 0.44))
	var n := int(d / 0.14)
	for i in n:
		var z := -d * 0.5 + d * (i + 0.5) / n
		var col := Color(0.58, 0.52, 0.45).darkened(rng.randf_range(0.0, 0.15))
		mm.set_mat(M.L_WOOD, col)
		mm.box(Vector3(-w * 0.5, top - 0.03, z - d / n * 0.45), Vector3(w * 0.5, top, z + d / n * 0.45))
	mm.set_mat(M.L_WOOD, Color(0.4, 0.36, 0.32))
	mm.box(Vector3(-w * 0.5, 0.0, d * 0.5 - 0.05), Vector3(w * 0.5, top - 0.005, d * 0.5))
	# fallen leaves on the boards
	for i in 14:
		mm.set_mat(M.L_PLAIN, Color(0.55, 0.38, 0.2).darkened(rng.randf_range(0.0, 0.35)))
		var c := Vector3(rng.randf_range(-w * 0.5, w * 0.5), top + 0.004, rng.randf_range(-d * 0.5, d * 0.5))
		var a := rng.randf() * TAU
		var s := rng.randf_range(0.04, 0.07)
		mm.poly(PackedVector3Array([c + Vector3(cos(a), 0, sin(a)) * s, c + Vector3(cos(a + 1.7), 0, sin(a + 1.7)) * s * 0.5, c - Vector3(cos(a), 0, sin(a)) * s, c + Vector3(cos(a - 1.7), 0, sin(a - 1.7)) * s * 0.5]), Vector3.UP)


static func _path(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var n := int(d / 0.62)
	for i in n:
		var z := -d * 0.5 + d * (i + 0.5) / n
		mm.set_mat(M.L_CONCRETE_PLAIN, Color(0.8, 0.79, 0.76).darkened(rng.randf_range(0.0, 0.12)))
		var b := Basis(Vector3.UP, rng.randf_range(-0.04, 0.04))
		mm.obox(Transform3D(b, Vector3(rng.randf_range(-0.03, 0.03), 0.015, z)), Vector3(w * 0.9, 0.035, d / n * 0.82), ["-y"])


static func _road(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	# The plan strip is the near lane; the street continues beyond the yard
	# (two lanes, far curb, sidewalk, a dead hedge) so it never just ends.
	var ext := 40.0
	var x0 := -w * 0.5 - ext
	var x1 := w * 0.5 + ext
	var z0 := -d * 0.5
	var z1 := z0 + 5.6
	mm.set_mat(M.L_ASPHALT)
	mm.quad(Vector3(x0, 0.012, z0), Vector3(x1, 0.012, z0), Vector3(x1, 0.012, z1), Vector3(x0, 0.012, z1), Vector3.UP)
	# curbs
	mm.set_mat(M.L_CONCRETE_PLAIN, Color(0.72, 0.71, 0.68))
	mm.box(Vector3(x0, 0.0, z0 - 0.16), Vector3(x1, 0.07, z0), ["-y"])
	mm.box(Vector3(x0, 0.0, z1), Vector3(x1, 0.09, z1 + 0.16), ["-y"])
	# far sidewalk slabs
	var x := x0
	while x < x1:
		mm.set_mat(M.L_CONCRETE_PLAIN, Color(0.66, 0.65, 0.62).darkened(rng.randf_range(0.0, 0.1)))
		mm.box(Vector3(x + 0.02, 0.0, z1 + 0.16), Vector3(x + 1.48, 0.06, z1 + 1.6), ["-y"])
		x += 1.5
	# faded centre line
	mm.set_mat(M.L_ROAD_PAINT, Color(0.85, 0.8, 0.6))
	x = x0
	var zc := z0 + 2.8
	while x < x1:
		mm.quad(Vector3(x, 0.016, zc - 0.06), Vector3(x + 2.0, 0.016, zc - 0.06), Vector3(x + 2.0, 0.016, zc + 0.06), Vector3(x, 0.016, zc + 0.06), Vector3.UP)
		x += 4.0
	# manhole and leaves drifted against the curbs
	mm.set_mat(M.L_CONCRETE_PLAIN, Color(0.5, 0.5, 0.48))
	mm.cylinder(Vector3(3.0, 0.0, zc + 1.2), 0.36, 0.36, 0.016, 12)
	mm.set_mat(M.L_PLAIN, Color(0.3, 0.3, 0.29))
	mm.cylinder(Vector3(3.0, 0.0, zc + 1.2), 0.3, 0.3, 0.02, 12)
	for i in 120:
		mm.set_mat(M.L_PLAIN, Color(0.5, 0.34, 0.18).darkened(rng.randf_range(0.0, 0.45)))
		var near := rng.randf() < 0.5
		var c := Vector3(rng.randf_range(x0 * 0.5, x1 * 0.5), 0.02, (z0 + rng.randf_range(0.0, 0.45)) if near else (z1 - rng.randf_range(0.0, 0.4)))
		var a := rng.randf() * TAU
		var s := rng.randf_range(0.04, 0.08)
		mm.poly(PackedVector3Array([c + Vector3(cos(a), 0, sin(a)) * s, c + Vector3(cos(a + 1.7), 0, sin(a + 1.7)) * s * 0.5, c - Vector3(cos(a), 0, sin(a)) * s, c + Vector3(cos(a - 1.7), 0, sin(a - 1.7)) * s * 0.5]), Vector3.UP)
	# a dead hedge across the street
	x = x0
	var zh := z1 + 2.1
	while x < x1:
		var hw := rng.randf_range(0.7, 1.3)
		mm.set_mat(M.L_PLAIN, Color(0.32, 0.3, 0.22).lerp(Color(0.42, 0.33, 0.22), rng.randf()))
		mm.blob(Vector3(x + hw * 0.5, rng.randf_range(0.35, 0.55), zh + rng.randf_range(-0.15, 0.15)), Vector3(hw * 0.62, rng.randf_range(0.45, 0.7), 0.55), 3, 7)
		x += hw * 0.8


static func _driveway(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	mm.set_mat(M.L_CONCRETE)
	mm.quad(Vector3(-w * 0.5, 0.018, -d * 0.5), Vector3(w * 0.5, 0.018, -d * 0.5), Vector3(w * 0.5, 0.018, d * 0.5 + 0.2), Vector3(-w * 0.5, 0.018, d * 0.5 + 0.2), Vector3.UP)
	mm.set_mat(M.L_PLAIN, Color(0.4, 0.4, 0.4))
	for i in range(1, 4):
		var z := -d * 0.5 + d * i / 4.0
		mm.quad(Vector3(-w * 0.5, 0.02, z - 0.01), Vector3(w * 0.5, 0.02, z - 0.01), Vector3(w * 0.5, 0.02, z + 0.01), Vector3(-w * 0.5, 0.02, z + 0.01), Vector3.UP)
	mm.set_mat(M.L_PLAIN, Color(0.25, 0.24, 0.23))
	var pts := PackedVector3Array()
	for k in 9:
		var a := TAU * k / 9.0
		pts.append(Vector3(0.2 + cos(a) * rng.randf_range(0.3, 0.5), 0.021, 0.5 + sin(a) * rng.randf_range(0.2, 0.4)))
	mm.poly(pts, Vector3.UP)


static func _step(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	mm.set_mat(M.L_CONCRETE_PLAIN, Color(0.75, 0.74, 0.7))
	mm.chamfer_box(Vector3(-w * 0.5, 0, -d * 0.5), Vector3(w * 0.5, 0.06, d * 0.5), 0.01)


static func _car(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	# canonical: car is w wide (x) and d long (z), nose toward +z
	var paint := Color(0.4, 0.22, 0.2)
	var x := w * 0.45
	var z := d * 0.5
	var lean := Basis(Vector3.BACK, 0.035)   # flat tyre on one side
	var keep := mm.xf
	mm.xf = mm.xf * Transform3D(lean, Vector3.ZERO)
	mm.set_mat(M.L_GLOSSY, paint)
	_cbox(mm, Vector3(-x, 0.28, -z + 0.05), Vector3(x, 0.78, z - 0.05), 0.08)
	# cabin
	var cb := [Vector3(-x + 0.08, 0.78, -z + 1.05), Vector3(x - 0.08, 0.78, -z + 1.05), Vector3(x - 0.08, 0.78, z - 1.35), Vector3(-x + 0.08, 0.78, z - 1.35)]
	var ct := [Vector3(-x + 0.2, h - 0.02, -z + 1.45), Vector3(x - 0.2, h - 0.02, -z + 1.45), Vector3(x - 0.2, h - 0.02, z - 1.9), Vector3(-x + 0.2, h - 0.02, z - 1.9)]
	mm.set_mat(M.L_GLOSSY, paint.darkened(0.05))
	mm.poly(PackedVector3Array([ct[0], ct[1], ct[2], ct[3]]), Vector3.UP)
	mm.set_mat(M.L_SCREEN, Color(0.12, 0.15, 0.17))
	mm.quad(cb[0], cb[1], ct[1], ct[0])      # rear glass
	mm.quad(cb[2], cb[3], ct[3], ct[2])      # windscreen
	mm.quad(cb[1], cb[2], ct[2], ct[1])      # side
	mm.quad(cb[3], cb[0], ct[0], ct[3])
	# a pale crack across the windscreen
	mm.set_mat(M.L_PLAIN, Color(0.75, 0.8, 0.82))
	var wa: Vector3 = (cb[3] as Vector3).lerp(ct[3], 0.4)
	var wb: Vector3 = (cb[2] as Vector3).lerp(ct[2], 0.65)
	mm.tri(wa, wb, wa.lerp(wb, 0.5) + Vector3(0, 0.02, -0.01), Vector3(0, 0.6, 0.8))
	# wheels
	mm.set_mat(M.L_PLAIN, Color(0.08, 0.08, 0.09))
	for sz in [-1.0, 1.0]:
		for sx in [-1.0, 1.0]:
			var c := Vector3(sx * (x - 0.1), 0.0, sz * (z - 0.75))
			var r := 0.33 if not (sx > 0.0 and sz < 0.0) else 0.27
			mm.tube(c + Vector3(-0.11, r, 0), c + Vector3(0.11, r, 0), r, r, 10)
			mm.set_mat(M.L_METAL, Color(0.55, 0.56, 0.57))
			mm.tube(c + Vector3(sx * 0.11, r, 0), c + Vector3(sx * 0.115, r, 0), r * 0.55, r * 0.55, 8)
			mm.set_mat(M.L_PLAIN, Color(0.08, 0.08, 0.09))
	# lights and bumpers
	mm.set_mat(M.L_GLOSSY, Color(0.88, 0.86, 0.78))
	for sx in [-1.0, 1.0]:
		mm.box(Vector3(sx * x * 0.7 - 0.13, 0.6, z - 0.06), Vector3(sx * x * 0.7 + 0.13, 0.68, z - 0.02))
	mm.set_mat(M.L_GLOSSY, Color(0.55, 0.08, 0.06))
	for sx in [-1.0, 1.0]:
		mm.box(Vector3(sx * x * 0.7 - 0.14, 0.6, -z + 0.02), Vector3(sx * x * 0.7 + 0.14, 0.68, -z + 0.06))
	mm.set_mat(M.L_PLAIN, Color(0.15, 0.15, 0.16))
	mm.box(Vector3(-x, 0.25, z - 0.1), Vector3(x, 0.4, z + 0.01))
	mm.box(Vector3(-x, 0.25, -z - 0.01), Vector3(x, 0.4, -z + 0.1))
	# driver door hanging open
	mm.set_mat(M.L_GLOSSY, paint)
	var hinge := Vector3(-x, 0.35, 0.35)
	var door := Transform3D(Basis(Vector3.UP, -0.75), hinge)
	mm.obox(door * Transform3D(Basis.IDENTITY, Vector3(-0.04, 0.22, -0.55)), Vector3(0.07, 0.45, 1.1))
	mm.set_mat(M.L_SCREEN, Color(0.12, 0.15, 0.17))
	mm.obox(door * Transform3D(Basis.IDENTITY, Vector3(-0.04, 0.62, -0.6)), Vector3(0.03, 0.34, 0.9))
	mm.xf = keep


static func _dead_tree(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	mm.set_mat(M.L_BARK, Color(0.33, 0.3, 0.28))
	_branch(mm, rng, Vector3(0, -0.1, 0), Vector3(0, 1, 0), h * 0.45, 0.2, 0, h)
	# exposed roots
	for k in 4:
		var a := TAU * k / 4.0 + rng.randf_range(-0.4, 0.4)
		mm.tube(Vector3(0, 0.12, 0), Vector3(cos(a) * 0.6, -0.04, sin(a) * 0.6), 0.1, 0.03, 5)


static func _branch(mm: ModMesh, rng: RandomNumberGenerator, at: Vector3, dir: Vector3, length: float, r: float, depth: int, h: float) -> void:
	var tip := at + dir * length
	mm.tube(at, tip, r, r * 0.68, 6, depth > 0)
	if depth >= 3 or r < 0.02:
		return
	var n := 2 if depth > 0 else 3
	for i in n:
		var yaw := rng.randf() * TAU
		var tilt := rng.randf_range(0.35, 0.8)
		var nd := (dir * cos(tilt) + Vector3(cos(yaw), 0, sin(yaw)) * sin(tilt)).normalized()
		nd.y = maxf(nd.y, 0.15)
		nd = nd.normalized()
		_branch(mm, rng, tip, nd, length * rng.randf_range(0.5, 0.72), r * 0.6, depth + 1, h)
	if depth == 0:
		_branch(mm, rng, tip, dir, length * 0.7, r * 0.65, depth + 1, h)


static func _trash_bin_tipped(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	# canonical: bin lying along x with its open lid toward +x
	var col := Color(0.2, 0.3, 0.24)
	mm.set_mat(M.L_GLOSSY, col)
	var keep := mm.xf
	mm.xf = mm.xf * Transform3D(Basis(Vector3.UP, 0.15), Vector3(-0.05, 0, 0))
	_cbox(mm, Vector3(-0.45, 0.02, -0.28), Vector3(0.38, 0.56, 0.28), 0.04)
	mm.set_mat(M.L_SCREEN, Color(0.05, 0.05, 0.05))
	mm.box(Vector3(0.38, 0.06, -0.24), Vector3(0.385, 0.52, 0.24))
	mm.set_mat(M.L_GLOSSY, col.darkened(0.2))
	mm.obox(Transform3D(Basis(Vector3.FORWARD, -0.5), Vector3(0.5, 0.25, 0.0)), Vector3(0.04, 0.5, 0.6))
	mm.set_mat(M.L_PLAIN, Color(0.08, 0.08, 0.08))
	for sz in [-1.0, 1.0]:
		mm.tube(Vector3(-0.47, 0.05, sz * 0.2), Vector3(-0.47, 0.13, sz * 0.2), 0.08, 0.08, 8)
	mm.xf = keep
	# spilled bags and litter
	mm.set_mat(M.L_GLOSSY, Color(0.07, 0.07, 0.08))
	mm.blob(Vector3(0.7, 0.14, 0.15), Vector3(0.22, 0.15, 0.2), 3, 7)
	mm.blob(Vector3(0.95, 0.11, -0.2), Vector3(0.17, 0.12, 0.16), 3, 7)
	for i in 8:
		mm.set_mat(M.L_PLAIN, [Color(0.85, 0.83, 0.78), Color(0.7, 0.3, 0.2), Color(0.4, 0.55, 0.7)][i % 3])
		var c := Vector3(rng.randf_range(0.4, 1.4), 0.01, rng.randf_range(-0.5, 0.5))
		mm.obox(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), c), Vector3(rng.randf_range(0.05, 0.12), 0.01, rng.randf_range(0.04, 0.09)))


static func _mailbox(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var keep := mm.xf
	mm.xf = mm.xf * Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3.ZERO)
	mm.set_mat(M.L_WOOD, Color(0.45, 0.4, 0.34))
	mm.box(Vector3(-0.05, 0, -0.05), Vector3(0.05, h - 0.25, 0.05))
	mm.set_mat(M.L_METAL, Color(0.25, 0.28, 0.3))
	mm.box(Vector3(-0.11, h - 0.3, -0.24), Vector3(0.11, h - 0.1, 0.22))
	mm.tube(Vector3(0, h - 0.1, -0.24), Vector3(0, h - 0.1, 0.22), 0.11, 0.11, 8)
	mm.set_mat(M.L_GLOSSY, Color(0.75, 0.15, 0.12))
	mm.box(Vector3(0.11, h - 0.2, -0.05), Vector3(0.125, h + 0.05, -0.02))
	mm.box(Vector3(0.11, h - 0.02, -0.05), Vector3(0.125, h + 0.05, 0.08))
	mm.xf = keep


static func _streetlight_dead(mm: ModMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var keep := mm.xf
	mm.xf = mm.xf * Transform3D(Basis(Vector3.RIGHT, 0.06) * Basis(Vector3.BACK, -0.03), Vector3.ZERO)
	mm.set_mat(M.L_CONCRETE_PLAIN, Color(0.6, 0.6, 0.58))
	mm.cylinder(Vector3.ZERO, 0.16, 0.14, 0.3, 8)
	mm.set_mat(M.L_METAL, Color(0.6, 0.62, 0.62))
	mm.cylinder(Vector3(0, 0.3, 0), 0.08, 0.05, h - 0.3, 8)
	mm.tube(Vector3(0, h - 0.15, 0), Vector3(0, h + 0.1, 0.5), 0.04, 0.035, 6)
	mm.tube(Vector3(0, h + 0.1, 0.5), Vector3(0, h + 0.14, 1.0), 0.035, 0.03, 6)
	mm.set_mat(M.L_METAL, Color(0.52, 0.54, 0.55))
	mm.blob(Vector3(0, h + 0.12, 1.25), Vector3(0.16, 0.07, 0.32), 3, 8)
	mm.set_mat(M.L_SCREEN, Color(0.2, 0.22, 0.2))
	mm.blob(Vector3(0, h + 0.08, 1.27), Vector3(0.11, 0.03, 0.22), 2, 8)
	mm.xf = keep
