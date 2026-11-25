extends RefCounted
## Experiment 004 household pieces for PropKit: electric light fixtures (the
## kinds in HousePlan.LIGHTS), a wall light switch and the living-room
## fireplace. Builder frame as in prop_furniture.gd: footprint centred, width
## w along x, depth d along z, FRONT toward +z, ground at y = 0. Glowing parts
## use L_GLOW, so PropKit.set_lit(node, 0..1) switches them.
##
## Fixtures hang from the ceiling: their mesh spans 0..h and the caller places
## the node at (ceiling - h).

const M := preload("res://src/props/prop_materials.gd")

const BRASS := Color(0.62, 0.52, 0.34)
const STEEL := Color(0.7, 0.71, 0.72)
const WARM_GLASS := Color(0.98, 0.9, 0.76)


static func build(mm: PropMesh, type: String, w: float, h: float, d: float, rng: RandomNumberGenerator, damage: float) -> bool:
	match type:
		"ceiling_light":
			_ceiling_light(mm, w, d, h)
		"range_hood":
			_range_hood(mm, w, d, h)
		"table_lamp":
			_table_lamp(mm, w, d, h)
		"bare_bulb":
			_bare_bulb(mm, w, d, h)
		"bulb":
			mm.set_mat(M.L_GLOW, WARM_GLASS)
			mm.blob(Vector3(0, h * 0.5, 0), Vector3(w * 0.5, h * 0.5, d * 0.5), 3, 8)
		"light_switch":
			_light_switch(mm, w, d, h)
		"fireplace":
			_fireplace(mm, w, d, h, rng, damage)
		"radio":                  # Exp 006 (B)
			_radio(mm, w, d, h)
		_:
			return false
	return true


## Exp 006 (B): a small mains radio: a two-tone cabinet, a speaker grille on
## the left of the front, a tuning dial on the right (glows while it plays:
## L_GLOW), a carrying handle and a telescopic antenna.
static func _radio(mm: PropMesh, w: float, d: float, h: float) -> void:
	var x := w * 0.5
	var z := d * 0.5
	mm.set_mat(M.L_GLOSSY, Color(0.36, 0.25, 0.18))
	mm.chamfer_box(Vector3(-x, 0, -z), Vector3(x, h * 0.82, z), 0.015)
	mm.set_mat(M.L_PLAIN, Color(0.83, 0.79, 0.68))
	mm.box(Vector3(-x + 0.012, 0.02, z), Vector3(x - 0.012, h * 0.82 - 0.02, z + 0.004), ["-z"])
	mm.set_mat(M.L_METAL, Color(0.25, 0.24, 0.22), 0.3)
	for i in 5:                   # grille slots
		var gy := 0.04 + i * (h * 0.6 / 5.0)
		mm.box(Vector3(-x + 0.03, gy, z + 0.004), Vector3(-0.01, gy + 0.012, z + 0.008), ["-z"])
	mm.set_mat(M.L_GLOW, Color(1.0, 0.78, 0.42))
	mm.box(Vector3(0.02, h * 0.38, z + 0.004), Vector3(x - 0.03, h * 0.62, z + 0.007), ["-z"])
	mm.set_mat(M.L_PLAIN, Color(0.12, 0.11, 0.1))
	mm.cylinder(Vector3(x - 0.05, 0.05, z + 0.004), 0.016, 0.016, 0.01, 8, true)
	mm.set_mat(M.L_METAL, Color(0.7, 0.71, 0.72), 0.15)
	mm.box(Vector3(-x * 0.6, h * 0.82, -0.008), Vector3(-x * 0.6 + 0.012, h, 0.008))
	mm.box(Vector3(x * 0.6 - 0.012, h * 0.82, -0.008), Vector3(x * 0.6, h, 0.008))
	mm.box(Vector3(-x * 0.6, h - 0.012, -0.008), Vector3(x * 0.6, h, 0.008))
	mm.cylinder(Vector3(x - 0.04, h * 0.82, -z + 0.02), 0.004, 0.003, h * 0.18, 5, false)


## A frosted glass bowl under a short stem and ceiling canopy.
static func _ceiling_light(mm: PropMesh, w: float, d: float, h: float) -> void:
	var r := minf(w, d) * 0.5
	mm.no_shadow = true          # the light sits in the canopy
	mm.set_mat(M.L_GLOW, WARM_GLASS)
	mm.cylinder(Vector3(0, 0.0, 0), r * 0.62, r, minf(0.11, h * 0.55), 12, true)
	mm.set_mat(M.L_METAL, BRASS, 0.1)
	var rim := minf(0.11, h * 0.55)
	mm.cylinder(Vector3(0, rim, 0), r, r * 0.96, 0.018, 12, true)
	mm.cylinder(Vector3(0, rim + 0.018, 0), 0.012, 0.012, maxf(h - rim - 0.04, 0.01), 6, false)
	mm.cylinder(Vector3(0, h - 0.022, 0), 0.07, 0.075, 0.022, 10, true)


## A stainless cooker hood against the wall behind (-z), its lamp underneath.
static func _range_hood(mm: PropMesh, w: float, d: float, h: float) -> void:
	var x := w * 0.5
	var z := d * 0.5
	mm.set_mat(M.L_METAL, STEEL, 0.15)
	mm.box(Vector3(-x, 0.0, -z), Vector3(x, 0.1, z))
	# the sloping canopy up to the duct
	var top := minf(0.32, h * 0.6)
	mm.quad(Vector3(-x, 0.1, z), Vector3(x, 0.1, z), Vector3(x * 0.42, top, -z + d * 0.45), Vector3(-x * 0.42, top, -z + d * 0.45), Vector3(0, 0.78, 0.62))
	mm.quad(Vector3(-x, 0.1, z), Vector3(-x * 0.42, top, -z + d * 0.45), Vector3(-x * 0.42, top, -z), Vector3(-x, 0.1, -z), Vector3(-0.8, 0.6, 0))
	mm.quad(Vector3(x, 0.1, z), Vector3(x, 0.1, -z), Vector3(x * 0.42, top, -z), Vector3(x * 0.42, top, -z + d * 0.45), Vector3(0.8, 0.6, 0))
	mm.box(Vector3(-x * 0.42, top - 0.001, -z), Vector3(x * 0.42, top + 0.001, -z + d * 0.45), ["-y"])
	mm.box(Vector3(-x * 0.3, top, -z), Vector3(x * 0.3, h, -z + d * 0.4))
	mm.set_mat(M.L_SCREEN, Color(0.12, 0.12, 0.13))
	mm.box(Vector3(-x + 0.04, -0.004, -z + 0.04), Vector3(x - 0.04, 0.0, z - 0.04), ["+y"])
	mm.set_mat(M.L_GLOW, WARM_GLASS)
	mm.box(Vector3(-x * 0.5, -0.008, z - 0.13), Vector3(x * 0.5, -0.003, z - 0.07), ["+y"])
	mm.set_mat(M.L_PLAIN, Color(0.15, 0.15, 0.16))
	for k in 3:
		mm.box(Vector3(-0.12 + k * 0.08, 0.035, z), Vector3(-0.1 + k * 0.08, 0.065, z + 0.008), ["-z"])


## A ceramic lamp with a pleated shade that glows when lit.
static func _table_lamp(mm: PropMesh, w: float, d: float, h: float) -> void:
	var r := minf(w, d) * 0.5
	mm.set_mat(M.L_GLOSSY, Color(0.36, 0.46, 0.5))
	mm.cylinder(Vector3.ZERO, r * 0.5, r * 0.55, 0.03, 10, true, true)
	mm.blob(Vector3(0, h * 0.28, 0), Vector3(r * 0.42, h * 0.22, r * 0.42), 4, 10)
	mm.set_mat(M.L_METAL, BRASS, 0.1)
	mm.cylinder(Vector3(0, h * 0.48, 0), 0.012, 0.012, h * 0.12, 6, false)
	mm.set_mat(M.L_GLOW, Color(0.86, 0.74, 0.56))
	mm.cylinder(Vector3(0, h * 0.55, 0), r, r * 0.66, h * 0.45, 12, false)
	mm.cylinder_inside(Vector3(0, h * 0.55 + 0.001, 0), r * 0.97, r * 0.64, h * 0.45 - 0.002, 12)


## A bare bulb on its cord.
static func _bare_bulb(mm: PropMesh, w: float, d: float, h: float) -> void:
	var r := minf(w, d) * 0.5
	mm.no_shadow = true          # the light sits on the cord
	mm.set_mat(M.L_PLAIN, Color(0.08, 0.08, 0.08))
	mm.cylinder(Vector3(0, r * 2.0, 0), 0.006, 0.006, maxf(h - r * 2.0, 0.01), 5, false)
	mm.cylinder(Vector3(0, r * 1.5, 0), r * 0.45, r * 0.45, r * 0.6, 8, true)
	mm.set_mat(M.L_GLOW, WARM_GLASS)
	mm.blob(Vector3(0, r * 0.85, 0), Vector3(r * 0.75, r * 0.85, r * 0.75), 3, 8)


## A wall plate with a rocker and a small amber indicator (lit = power on).
static func _light_switch(mm: PropMesh, w: float, d: float, h: float) -> void:
	var x := w * 0.5
	var z := d * 0.5
	mm.set_mat(M.L_GLOSSY, Color(0.86, 0.85, 0.8))
	mm.chamfer_box(Vector3(-x, 0, -z), Vector3(x, h, z * 0.2), 0.006, false)
	mm.set_mat(M.L_PLAIN, Color(0.8, 0.79, 0.74))
	mm.box(Vector3(-x * 0.45, h * 0.3, z * 0.2), Vector3(x * 0.45, h * 0.7, z), ["-z"])
	mm.set_mat(M.L_GLOW, Color(1.0, 0.62, 0.3))
	mm.box(Vector3(-0.006, h * 0.12, z * 0.2), Vector3(0.006, h * 0.2, z * 0.5), ["-z"])


## Brick fireplace with a stone hearth, a wooden mantel and the chimney breast
## up to the ceiling. The firebox opening faces the front (+z); logs on an
## ember bed (glows while lit). Flames, light and sparks are separate nodes.
static func _fireplace(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator, damage: float) -> void:
	var x := w * 0.5
	var z := d * 0.5
	var ox := minf(0.4, x * 0.55)          # half the firebox width
	var oh := minf(0.72, h * 0.35)         # firebox height
	var mantel := minf(1.0, h * 0.45)
	var hearth := 0.06
	# hearth slab, reaching 0.3 m into the room
	mm.set_mat(M.L_CONCRETE, Color(0.46, 0.45, 0.44), 0.2)
	mm.box(Vector3(-x, 0.0, -z), Vector3(x, hearth, z + 0.3))
	# brick body: piers, lintel, back, breast (mortar colour; bricks faced below)
	var mortar := Color(0.5, 0.45, 0.4)
	mm.set_mat(M.L_PLAIN, mortar, 0.25)
	mm.box(Vector3(-x, hearth, -z), Vector3(-ox, mantel, z))
	mm.box(Vector3(ox, hearth, -z), Vector3(x, mantel, z))
	mm.box(Vector3(-ox, oh, -z), Vector3(ox, mantel, z))
	mm.box(Vector3(-ox, hearth, -z), Vector3(ox, oh, -z + 0.12))
	var bx := x * 0.74
	mm.box(Vector3(-bx, mantel, -z), Vector3(bx, h, z - 0.08))
	# soot inside the firebox
	mm.set_mat(M.L_PLAIN, Color(0.07, 0.06, 0.06))
	mm.box(Vector3(-ox + 0.004, hearth, -z + 0.12), Vector3(ox - 0.004, oh - 0.004, -z + 0.124), ["-z"])
	mm.box(Vector3(-ox, hearth, -z + 0.12), Vector3(-ox + 0.004, oh, z), ["-x"])
	mm.box(Vector3(ox - 0.004, hearth, -z + 0.12), Vector3(ox, oh, z), ["+x"])
	mm.box(Vector3(-ox, oh - 0.004, -z + 0.12), Vector3(ox, oh, z), ["+y"])
	# brick faces on the front
	_bricks(mm, rng, -x, -ox, hearth, mantel, z)
	_bricks(mm, rng, ox, x, hearth, mantel, z)
	_bricks(mm, rng, -ox, ox, oh, mantel, z)
	_bricks(mm, rng, -bx, bx, mantel + 0.07, h, z - 0.08)
	# the mantel shelf
	mm.set_mat(M.L_WOOD, Color(0.42, 0.3, 0.2), 0.15)
	mm.chamfer_box(Vector3(-x, mantel, -z), Vector3(x, mantel + 0.07, z + 0.06), 0.01, false)
	# ember bed and logs
	mm.set_mat(M.L_GLOW, Color(0.9, 0.36, 0.1))
	mm.box(Vector3(-ox + 0.08, hearth, -z + 0.18), Vector3(ox - 0.08, hearth + 0.025, z - 0.06))
	mm.set_mat(M.L_BARK, Color(0.3, 0.22, 0.16), 0.2)
	mm.tube(Vector3(-ox + 0.1, hearth + 0.06, -z + 0.3), Vector3(ox - 0.12, hearth + 0.08, -z + 0.26), 0.05, 0.045, 7)
	mm.tube(Vector3(-ox + 0.16, hearth + 0.07, z - 0.12), Vector3(ox - 0.1, hearth + 0.05, z - 0.08), 0.045, 0.05, 7)
	mm.tube(Vector3(-0.1, hearth + 0.06, -z + 0.22), Vector3(0.08, hearth + 0.15, z - 0.14), 0.04, 0.035, 7)
	# a few spare logs on the hearth's corner and a poker against the pier
	mm.set_mat(M.L_BARK, Color(0.36, 0.28, 0.2), 0.15)
	for k in 3:
		var y := hearth + 0.05 + (0.08 if k == 2 else 0.0)
		var zz := z + 0.08 + (0.1 if k == 1 else 0.0) + (0.05 if k == 2 else 0.0)
		mm.tube(Vector3(-x + 0.06, y, zz), Vector3(-x + 0.38, y, zz + rng.randf_range(-0.02, 0.02)), 0.045, 0.045, 7)
	mm.set_mat(M.L_METAL, Color(0.12, 0.12, 0.12), 0.1)
	mm.tube(Vector3(x - 0.12, hearth, z + 0.06), Vector3(x - 0.1, hearth + 0.62, z + 0.02), 0.01, 0.01, 5)


## Running-bond brick faces on the plane z between x0..x1, y0..y1.
static func _bricks(mm: PropMesh, rng: RandomNumberGenerator, x0: float, x1: float, y0: float, y1: float, z: float) -> void:
	var course := 0.075
	var length := 0.22
	var rows := int((y1 - y0) / course)
	var reds := [Color(0.5, 0.26, 0.2), Color(0.56, 0.31, 0.23), Color(0.45, 0.24, 0.19), Color(0.6, 0.38, 0.28), Color(0.42, 0.3, 0.25)]
	for row in rows:
		var y := y0 + row * course
		var x := x0 - (length * 0.5 if row % 2 == 1 else 0.0)
		while x < x1:
			var a := maxf(x, x0) + 0.006
			var b := minf(x + length, x1) - 0.006
			if b - a > 0.02:
				mm.set_mat(M.L_PLAIN, (reds[rng.randi() % reds.size()] as Color).darkened(rng.randf_range(0.0, 0.15)), rng.randf_range(0.1, 0.35))
				mm.quad(Vector3(a, y + 0.006, z + 0.003), Vector3(b, y + 0.006, z + 0.003), Vector3(b, y + course - 0.006, z + 0.003), Vector3(a, y + course - 0.006, z + 0.003), Vector3.BACK)
			x += length
