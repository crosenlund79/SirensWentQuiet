extends RefCounted
## Yard props for PropKit (every HousePlan.PROPS type, plus `bush`). Forked
## from Experiment 001's modular furniture kit. Builder frame as in
## prop_furniture.gd: footprint centred, width w along x, depth d along z,
## FRONT toward +z, ground at y = 0. Everything outdoors is weathered: the
## OUTDOOR wear bias in PropKit adds grime, and the pieces add leaves, rust
## and small damage. Flat pieces stay inside their plan rect.

const M := preload("res://src/props/prop_materials.gd")

const BARK := Color(0.33, 0.3, 0.27)
const LEAF_BROWN := Color(0.5, 0.35, 0.2)


static func build(mm: PropMesh, type: String, w: float, h: float, d: float, rng: RandomNumberGenerator, damage: float) -> bool:
	match type:
		"deck":
			_deck(mm, w, d, h, rng, damage)
		"path":
			_path(mm, w, d, h, rng)
		"road":
			_road(mm, w, d, h, rng)
		"driveway":
			_driveway(mm, w, d, h, rng)
		"step":
			_step(mm, w, d, h, rng)
		"car":
			_car(mm, w, d, h, rng, damage)
		"dead_tree":
			_dead_tree(mm, w, d, h, rng)
		"trash_bin_tipped":
			_trash_bin_tipped(mm, w, d, h, rng)
		"mailbox":
			_mailbox(mm, w, d, h, rng)
		"streetlight_dead":
			_streetlight_dead(mm, w, d, h, rng)
		"bush":
			_bush(mm, w, d, h, rng, damage)
		_:
			return false
	return true


## Dry leaves scattered over a rectangle at height y.
static func _leaves(mm: PropMesh, rng: RandomNumberGenerator, n: int, lo: Vector2, hi: Vector2, y: float) -> void:
	for i in n:
		mm.set_mat(M.L_FOLIAGE, LEAF_BROWN.lerp(Color(0.62, 0.5, 0.28), rng.randf()).darkened(rng.randf_range(0.0, 0.35)))
		var c := Vector3(rng.randf_range(lo.x, hi.x), y, rng.randf_range(lo.y, hi.y))
		var a := rng.randf() * TAU
		var s := rng.randf_range(0.035, 0.07)
		mm.sheet(PackedVector3Array([c + Vector3(cos(a), 0, sin(a)) * s, c + Vector3(cos(a + 1.7), 0, sin(a + 1.7)) * s * 0.5,
				c - Vector3(cos(a), 0, sin(a)) * s, c + Vector3(cos(a - 1.7), 0, sin(a - 1.7)) * s * 0.5]), Vector3.UP)


static func _deck(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator, damage: float) -> void:
	var top := maxf(h, 0.06)
	# joists underneath (visible at the open front edge)
	mm.set_mat(M.L_ROUGH_WOOD, Color(0.4, 0.36, 0.31), 0.3)
	mm.box(Vector3(-w * 0.5, 0.0, d * 0.5 - 0.05), Vector3(w * 0.5, top - 0.03, d * 0.5))
	for i in int(w / 0.6) + 1:
		var x := -w * 0.5 + 0.03 + i * (w - 0.06) / maxf(1.0, floorf(w / 0.6))
		mm.box(Vector3(x - 0.025, 0.0, -d * 0.5), Vector3(x + 0.025, top - 0.03, d * 0.5 - 0.05))
	var n := maxi(3, int(d / 0.14))
	var broken := rng.randi() % n if damage > 0.0 or rng.randf() < 0.6 else -1
	for i in n:
		var z := -d * 0.5 + d * (i + 0.5) / n
		var col := Color(0.58, 0.52, 0.44).darkened(rng.randf_range(0.0, 0.18))
		mm.set_mat(M.L_ROUGH_WOOD, col, rng.randf_range(0.1, 0.35))
		var hw := d / n * 0.44
		if i == broken:
			# a cracked board: one half sagging into the gap
			var bx := rng.randf_range(-w * 0.2, w * 0.2)
			mm.box(Vector3(-w * 0.5, top - 0.03, z - hw), Vector3(bx - 0.02, top, z + hw))
			mm.obox(Transform3D(Basis(Vector3.BACK, -0.06), Vector3((bx + w * 0.5) * 0.5 + 0.01, top - 0.035, z)), Vector3(w * 0.5 - bx - 0.03, 0.03, hw * 2.0))
		else:
			mm.box(Vector3(-w * 0.5, top - 0.03, z - hw), Vector3(w * 0.5, top, z + hw))
	_leaves(mm, rng, int(w * d * 4.0), Vector2(-w * 0.48, -d * 0.48), Vector2(w * 0.48, d * 0.48), top + 0.003)


static func _path(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var n := maxi(1, int(d / 0.62))
	for i in n:
		var z := -d * 0.5 + d * (i + 0.5) / n
		mm.set_mat(M.L_CONCRETE, Color(0.74, 0.73, 0.7).darkened(rng.randf_range(0.0, 0.14)), 0.2)
		var b := Basis(Vector3.UP, rng.randf_range(-0.04, 0.04))
		mm.obox(Transform3D(b, Vector3(rng.randf_range(-0.03, 0.03), 0.012, z)), Vector3(w * 0.86, 0.035, d / n * 0.8), ["-y"])
	_leaves(mm, rng, int(d * 3), Vector2(-w * 0.45, -d * 0.48), Vector2(w * 0.45, d * 0.48), 0.032)


static func _road(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	# The plan strip is the lane in front of the lot: asphalt, a low curb on the
	# lot side, a faded edge line, leaves drifted against the curb.
	var x0 := -w * 0.5
	var x1 := w * 0.5
	var z0 := -d * 0.5
	var z1 := d * 0.5
	mm.set_mat(M.L_ASPHALT, Color(1, 1, 1), 0.1)
	mm.quad(Vector3(x0, 0.01, z0 + 0.15), Vector3(x1, 0.01, z0 + 0.15), Vector3(x1, 0.01, z1), Vector3(x0, 0.01, z1), Vector3.UP)
	mm.set_mat(M.L_CONCRETE, Color(0.64, 0.63, 0.6), 0.25)
	mm.box(Vector3(x0, 0.0, z0), Vector3(x1, 0.06, z0 + 0.15), ["-y"])
	mm.set_mat(M.L_ROAD_PAINT, Color(0.86, 0.84, 0.74))
	var x := x0
	while x < x1:
		mm.quad(Vector3(x, 0.014, z1 - 0.3), Vector3(minf(x + 3.0, x1), 0.014, z1 - 0.3), Vector3(minf(x + 3.0, x1), 0.014, z1 - 0.2), Vector3(x, 0.014, z1 - 0.2), Vector3.UP)
		x += 4.5
	# a storm drain in the curb
	mm.set_mat(M.L_METAL, Color(0.22, 0.22, 0.22), 0.4)
	mm.box(Vector3(2.0, 0.011, z0 + 0.15), Vector3(2.7, 0.013, z0 + 0.45))
	_leaves(mm, rng, int(w * 2.5), Vector2(x0 * 0.6, z0 + 0.16), Vector2(x1 * 0.6, z0 + 0.5), 0.016)


static func _driveway(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var y := maxf(h, 0.012)
	mm.set_mat(M.L_CONCRETE, Color(0.76, 0.75, 0.72), 0.18)
	mm.quad(Vector3(-w * 0.5, y, -d * 0.5), Vector3(w * 0.5, y, -d * 0.5), Vector3(w * 0.5, y, d * 0.5), Vector3(-w * 0.5, y, d * 0.5), Vector3.UP)
	mm.set_mat(M.L_PLAIN, Color(0.4, 0.4, 0.39))
	for i in range(1, 4):
		var z := -d * 0.5 + d * i / 4.0
		mm.quad(Vector3(-w * 0.5, y + 0.002, z - 0.01), Vector3(w * 0.5, y + 0.002, z - 0.01), Vector3(w * 0.5, y + 0.002, z + 0.01), Vector3(-w * 0.5, y + 0.002, z + 0.01), Vector3.UP)
	# an oil stain where the car usually stood, weeds in the joints
	mm.set_mat(M.L_PLAIN, Color(0.42, 0.41, 0.39))
	var pts := PackedVector3Array()
	for k in 11:
		var a := TAU * k / 11.0
		pts.append(Vector3(0.2 + cos(a) * rng.randf_range(0.22, 0.4), y + 0.003, sin(a) * rng.randf_range(0.16, 0.3)))
	mm.poly(pts, Vector3.UP)
	for i in 10:
		mm.set_mat(M.L_FOLIAGE, Color(0.45, 0.43, 0.27).darkened(rng.randf_range(0.0, 0.3)))
		var z := -d * 0.5 + d * (rng.randi_range(1, 3)) / 4.0
		var c := Vector3(rng.randf_range(-w * 0.45, w * 0.45), y, z)
		var a := rng.randf() * TAU
		mm.sheet(PackedVector3Array([c + Vector3(cos(a), 0, sin(a)) * 0.04, c + Vector3(0, 0.08, 0), c - Vector3(cos(a), 0, sin(a)) * 0.04]))


static func _step(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	mm.set_mat(M.L_CONCRETE, Color(0.72, 0.71, 0.68), 0.25)
	mm.chamfer_box(Vector3(-w * 0.5, 0, -d * 0.5), Vector3(w * 0.5, maxf(h, 0.05), d * 0.5), 0.012)
	_leaves(mm, rng, 4, Vector2(-w * 0.4, -d * 0.4), Vector2(w * 0.4, d * 0.4), maxf(h, 0.05) + 0.002)


static func _car(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator, damage: float) -> void:
	# w wide (x) and d long (z), nose toward +z; a faded maroon hatchback,
	# dusty, one tyre flat, the driver's door hanging open.
	var paint := Color(0.46, 0.24, 0.21)
	var x := w * 0.45
	var z := d * 0.5
	var keep := mm.xf
	mm.xf = mm.xf * Transform3D(Basis(Vector3.BACK, 0.035), Vector3.ZERO)
	mm.set_mat(M.L_GLOSSY, paint, 0.2)
	_cbox(mm, Vector3(-x, 0.28, -z + 0.05), Vector3(x, 0.78, z - 0.05), 0.08)
	var cb := [Vector3(-x + 0.08, 0.78, -z + 1.05), Vector3(x - 0.08, 0.78, -z + 1.05), Vector3(x - 0.08, 0.78, z - 1.35), Vector3(-x + 0.08, 0.78, z - 1.35)]
	var ct := [Vector3(-x + 0.2, h - 0.04, -z + 1.45), Vector3(x - 0.2, h - 0.04, -z + 1.45), Vector3(x - 0.2, h - 0.04, z - 1.9), Vector3(-x + 0.2, h - 0.04, z - 1.9)]
	mm.set_mat(M.L_GLOSSY, paint.darkened(0.05), 0.25)
	mm.poly(PackedVector3Array([ct[0], ct[1], ct[2], ct[3]]), Vector3.UP)
	mm.set_mat(M.L_SCREEN, Color(0.13, 0.15, 0.17), 0.3)
	mm.quad(cb[0], cb[1], ct[1], ct[0])
	mm.quad(cb[2], cb[3], ct[3], ct[2])
	mm.quad(cb[1], cb[2], ct[2], ct[1])
	mm.quad(cb[3], cb[0], ct[0], ct[3])
	# a pale crack web on the windscreen
	mm.set_mat(M.L_PLAIN, Color(0.36, 0.4, 0.43))
	var wc: Vector3 = (cb[2] as Vector3).lerp(ct[3], 0.45)
	var wn: Vector3 = ((cb[2] as Vector3) - (cb[3] as Vector3)).cross((ct[2] as Vector3) - (cb[2] as Vector3)).normalized()
	if wn.z < 0.0:
		wn = -wn
	for k in 5:
		var a := TAU * k / 5.0 + rng.randf_range(-0.3, 0.3)
		var e := ((cb[2] as Vector3) - (cb[3] as Vector3)).normalized()
		var u := wn.cross(e).normalized()
		var q := wc + (e * cos(a) + u * sin(a)) * rng.randf_range(0.15, 0.35)
		var t := wn.cross(q - wc).normalized() * 0.003
		mm.quad(wc - t + wn * 0.004, q - t + wn * 0.004, q + t + wn * 0.004, wc + t + wn * 0.004, wn)
	# wheels (rear right flat)
	for sz in [-1.0, 1.0]:
		for sx in [-1.0, 1.0]:
			var c := Vector3(sx * (x - 0.1), 0.0, sz * (z - 0.75))
			var r := 0.33 if not (sx > 0.0 and sz < 0.0) else 0.27
			mm.set_mat(M.L_PLAIN, Color(0.08, 0.08, 0.09), 0.3)
			mm.tube(c + Vector3(-0.11, r, 0), c + Vector3(0.11, r, 0), r, r, 10)
			mm.set_mat(M.L_METAL, Color(0.52, 0.53, 0.54), 0.35)
			mm.tube(c + Vector3(sx * 0.11, r, 0), c + Vector3(sx * 0.115, r, 0), r * 0.55, r * 0.55, 8)
	# lights, bumpers, number plate
	mm.set_mat(M.L_GLOSSY, Color(0.84, 0.82, 0.74))
	for sx in [-1.0, 1.0]:
		mm.box(Vector3(sx * x * 0.7 - 0.13, 0.6, z - 0.06), Vector3(sx * x * 0.7 + 0.13, 0.68, z - 0.02))
	mm.set_mat(M.L_GLOSSY, Color(0.5, 0.09, 0.07))
	for sx in [-1.0, 1.0]:
		mm.box(Vector3(sx * x * 0.7 - 0.14, 0.6, -z + 0.02), Vector3(sx * x * 0.7 + 0.14, 0.68, -z + 0.06))
	mm.set_mat(M.L_PLAIN, Color(0.15, 0.15, 0.16), 0.3)
	mm.box(Vector3(-x, 0.25, z - 0.1), Vector3(x, 0.4, z + 0.01))
	mm.box(Vector3(-x, 0.25, -z - 0.01), Vector3(x, 0.4, -z + 0.1))
	mm.set_mat(M.L_PLAIN, Color(0.86, 0.85, 0.8))
	mm.box(Vector3(-0.2, 0.42, z - 0.05), Vector3(0.2, 0.52, z - 0.04))
	# the driver's door hangs open
	mm.set_mat(M.L_GLOSSY, paint, 0.2)
	var hinge := Vector3(-x, 0.35, 0.35)
	var door := Transform3D(Basis(Vector3.UP, -0.62), hinge)
	mm.obox(door * Transform3D(Basis.IDENTITY, Vector3(-0.04, 0.22, -0.55)), Vector3(0.07, 0.45, 1.1))
	mm.set_mat(M.L_SCREEN, Color(0.12, 0.15, 0.17))
	mm.obox(door * Transform3D(Basis.IDENTITY, Vector3(-0.04, 0.62, -0.6)), Vector3(0.03, 0.34, 0.9))
	# rust bloom on the sills, a bullet-starred side window when damaged
	mm.set_mat(M.L_RUST, paint.darkened(0.2), 0.3)
	mm.box(Vector3(x - 0.002, 0.3, -z + 0.4), Vector3(x + 0.004, 0.36, -z + 1.2))
	if damage > 0.3:
		mm.set_mat(M.L_PLAIN, Color(0.05, 0.05, 0.05))
		mm.box(Vector3(x - 0.06, 0.4, 0.2), Vector3(x + 0.004, 0.55, 0.6))
	mm.xf = keep
	_leaves(mm, rng, 12, Vector2(-x * 0.8, -z * 0.5), Vector2(x * 0.8, z * 0.3), h - 0.035)


static func _cbox(mm: PropMesh, lo: Vector3, hi: Vector3, r := 0.02) -> void:
	mm.chamfer_box(lo, hi, r)


static func _dead_tree(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	mm.set_mat(M.L_BARK, BARK, 0.1)
	var r := minf(w, d) * 0.35
	_branch(mm, rng, Vector3(0, -0.02, 0), Vector3(0, 1, 0), h * 0.45, r, 0, h)
	# exposed roots
	for k in 4:
		var a := TAU * k / 4.0 + rng.randf_range(-0.4, 0.4)
		mm.tube(Vector3(0, 0.14, 0), Vector3(cos(a) * minf(0.6, w + 0.3), 0.02, sin(a) * minf(0.6, w + 0.3)), r * 0.42, r * 0.12, 5)


static func _branch(mm: PropMesh, rng: RandomNumberGenerator, at: Vector3, dir: Vector3, length: float, r: float, depth: int, h: float) -> void:
	var tip := at + dir * length
	if tip.y > h:
		tip = at + dir * maxf(0.05, (h - at.y) / maxf(dir.y, 0.2))
		tip.y = minf(tip.y, h)
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


static func _trash_bin_tipped(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	# A wheelie bin on its side, lid hanging open toward the front, bags and
	# litter spilled out. The bin lies along the longer of w and d.
	var along_z := d >= w
	var length := minf(maxf(w, d), 0.95)
	var across := minf(minf(w, d), 0.6)
	var rad := minf(across, h) * 0.5
	var col := Color(0.22, 0.3, 0.25)
	var keep := mm.xf
	var base := Transform3D(Basis(Vector3.UP, -PI * 0.5) if along_z else Basis.IDENTITY, Vector3.ZERO)
	mm.xf = mm.xf * base * Transform3D(Basis(Vector3.UP, 0.08), Vector3.ZERO)
	# local: bin along x, open end toward +x
	var l0 := -length * 0.5
	var l1 := length * 0.5 - 0.06
	mm.set_mat(M.L_GLOSSY, col, 0.25)
	_cbox(mm, Vector3(l0, 0.02, -rad), Vector3(l1, rad * 2.0 - 0.01, rad), 0.04)
	mm.set_mat(M.L_SCREEN, Color(0.04, 0.04, 0.04))
	mm.box(Vector3(l1, 0.06, -rad + 0.04), Vector3(l1 + 0.004, rad * 2.0 - 0.05, rad - 0.04))
	mm.set_mat(M.L_GLOSSY, col.darkened(0.2), 0.3)
	mm.obox(Transform3D(Basis(Vector3.FORWARD, -0.5), Vector3(l1 + 0.1, rad * 0.9, 0.0)), Vector3(0.035, rad * 1.9, rad * 2.1))
	mm.set_mat(M.L_PLAIN, Color(0.08, 0.08, 0.08))
	for sz in [-1.0, 1.0]:
		mm.tube(Vector3(l0 - 0.01, 0.05, sz * rad * 0.7), Vector3(l0 - 0.01, 0.13, sz * rad * 0.7), 0.075, 0.075, 8)
	# spilled bags and litter in front of the opening
	mm.set_mat(M.L_GLOSSY, Color(0.07, 0.07, 0.08), 0.1)
	mm.blob(Vector3(l1 + 0.3, 0.13, 0.12), Vector3(0.2, 0.13, 0.18), 3, 7)
	mm.blob(Vector3(l1 + 0.5, 0.1, -0.18), Vector3(0.15, 0.1, 0.14), 3, 7)
	for i in 9:
		mm.set_mat(M.L_PAPER, [Color(0.85, 0.83, 0.78), Color(0.68, 0.3, 0.2), Color(0.4, 0.53, 0.66)][i % 3])
		var c := Vector3(rng.randf_range(l1 + 0.1, l1 + 0.75), 0.006, rng.randf_range(-0.45, 0.45))
		mm.obox(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), c), Vector3(rng.randf_range(0.05, 0.12), 0.01, rng.randf_range(0.04, 0.09)))
	mm.xf = keep


static func _mailbox(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var keep := mm.xf
	mm.xf = mm.xf * Transform3D(Basis(Vector3.RIGHT, 0.1), Vector3.ZERO)
	mm.set_mat(M.L_ROUGH_WOOD, Color(0.5, 0.45, 0.38), 0.2)
	mm.box(Vector3(-0.045, 0, -0.045), Vector3(0.045, h - 0.24, 0.045))
	mm.set_mat(M.L_METAL, Color(0.27, 0.3, 0.32), 0.25)
	mm.box(Vector3(-0.1, h - 0.3, -0.22), Vector3(0.1, h - 0.12, 0.2))
	mm.tube(Vector3(0, h - 0.12, -0.22), Vector3(0, h - 0.12, 0.2), 0.1, 0.1, 8)
	# lid open, letters nobody collected
	mm.set_mat(M.L_METAL, Color(0.24, 0.27, 0.29), 0.25)
	mm.obox(Transform3D(Basis(Vector3.RIGHT, 1.2), Vector3(0, h - 0.24, 0.24)), Vector3(0.2, 0.2, 0.012))
	mm.set_mat(M.L_PAPER, Color(0.9, 0.88, 0.82))
	mm.obox(Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(0.0, h - 0.17, 0.18)), Vector3(0.12, 0.004, 0.16))
	mm.set_mat(M.L_RUST, Color(0.6, 0.15, 0.12), 0.2)
	mm.box(Vector3(0.1, h - 0.2, -0.05), Vector3(0.115, h + 0.04, -0.02))
	mm.box(Vector3(0.1, h - 0.02, -0.05), Vector3(0.115, h + 0.04, 0.08))
	mm.xf = keep


static func _streetlight_dead(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var keep := mm.xf
	mm.xf = mm.xf * Transform3D(Basis(Vector3.RIGHT, 0.05) * Basis(Vector3.BACK, -0.025), Vector3.ZERO)
	var r := minf(w, d) * 0.5
	mm.set_mat(M.L_CONCRETE, Color(0.66, 0.66, 0.63), 0.3)
	mm.cylinder(Vector3.ZERO, r, r * 0.88, 0.3, 8)
	mm.set_mat(M.L_METAL, Color(0.56, 0.58, 0.58), 0.25)
	mm.cylinder(Vector3(0, 0.3, 0), r * 0.5, r * 0.32, h - 0.45, 8)
	mm.tube(Vector3(0, h - 0.2, 0), Vector3(0, h + 0.04, 0.5), 0.04, 0.035, 6)
	mm.tube(Vector3(0, h + 0.04, 0.5), Vector3(0, h + 0.08, 1.0), 0.035, 0.03, 6)
	mm.set_mat(M.L_METAL, Color(0.5, 0.52, 0.53), 0.3)
	mm.blob(Vector3(0, h + 0.06, 1.22), Vector3(0.15, 0.065, 0.3), 3, 8)
	mm.set_mat(M.L_SCREEN, Color(0.2, 0.22, 0.2))
	mm.blob(Vector3(0, h + 0.025, 1.24), Vector3(0.1, 0.025, 0.2), 2, 8)
	# a missing-pet flyer taped to the pole
	mm.set_mat(M.L_PAPER, Color(0.92, 0.9, 0.82))
	mm.obox(Transform3D(Basis(Vector3.UP, 0.0), Vector3(0, 1.4, r * 0.42 + 0.003)), Vector3(0.18, 0.24, 0.003))
	mm.xf = keep


static func _bush(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator, damage: float) -> void:
	# A dead or dry shrub: grey twiggy stems from one crown, small clusters of
	# dry leaves still clinging to the twig ends, a mat of dead growth at the
	# base and fallen leaves around it. Damage strips leaves and twigs.
	var rx := w * 0.5
	var rz := d * 0.5
	var stems := 7 + rng.randi() % 4
	var tips: Array[Vector3] = []
	mm.set_mat(M.L_BARK, Color(0.4, 0.36, 0.31), 0.15)
	for i in stems:
		var a := TAU * i / stems + rng.randf_range(-0.3, 0.3)
		var spread := rng.randf_range(0.5, 0.95)
		var top := Vector3(cos(a) * rx * spread, h * rng.randf_range(0.6, 0.98), sin(a) * rz * spread)
		var mid := Vector3(top.x * 0.4, top.y * 0.45, top.z * 0.4) + Vector3(rng.randf_range(-0.05, 0.05), 0, rng.randf_range(-0.05, 0.05))
		var base := Vector3(rng.randf_range(-0.06, 0.06), 0.0, rng.randf_range(-0.06, 0.06))
		mm.tube(base, mid, 0.02, 0.014, 5, false)
		mm.tube(mid, top, 0.014, 0.005, 4, false)
		tips.append(top)
		for k in 3:
			if rng.randf() < damage * 0.5:
				continue
			var from := mid.lerp(top, rng.randf_range(0.15, 0.75))
			var tw := from + Vector3(rng.randf_range(-0.28, 0.28), rng.randf_range(0.04, 0.22), rng.randf_range(-0.28, 0.28))
			tw.x = clampf(tw.x, -rx, rx)
			tw.z = clampf(tw.z, -rz, rz)
			tw.y = minf(tw.y, h)
			mm.tube(from, tw, 0.007, 0.0025, 3, false)
			tips.append(tw)
	# dry leaf clusters on the twig ends
	var cols := [Color(0.56, 0.45, 0.26), Color(0.47, 0.42, 0.25), Color(0.62, 0.5, 0.3), Color(0.42, 0.32, 0.2)]
	for t in tips:
		if rng.randf() < 0.25 + damage * 0.55:
			continue
		var n := 3 + rng.randi() % 4
		for k in n:
			mm.set_mat(M.L_FOLIAGE, (cols[rng.randi() % cols.size()] as Color).darkened(rng.randf_range(0.0, 0.2)), 0.05)
			var c := t + Vector3(rng.randf_range(-0.07, 0.07), rng.randf_range(-0.08, 0.02), rng.randf_range(-0.07, 0.07))
			c.x = clampf(c.x, -rx + 0.04, rx - 0.04)
			c.z = clampf(c.z, -rz + 0.04, rz - 0.04)
			var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.4, 0.6), rng.randf_range(-1, 1)).normalized()
			var side := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
			var l := rng.randf_range(0.05, 0.09)
			mm.sheet(PackedVector3Array([c - dir * l * 0.5, c + side * l * 0.25, c + dir * l * 0.5, c - side * l * 0.25]))
	# a mat of dead growth at the crown
	mm.set_mat(M.L_FOLIAGE, Color(0.36, 0.32, 0.22), 0.1)
	for k in 3:
		var c := Vector3(rng.randf_range(-rx, rx) * 0.3, 0.07, rng.randf_range(-rz, rz) * 0.3)
		mm.blob(c, Vector3(rx * rng.randf_range(0.25, 0.4), minf(0.1, h * 0.15), rz * rng.randf_range(0.25, 0.4)), 2, 7)
	_leaves(mm, rng, 12, Vector2(-rx, -rz), Vector2(rx, rz), 0.004)
