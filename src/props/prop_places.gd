extends RefCounted
## Experiment 008 (H): three pieces for the hand-made places (the hardware
## store, the gun shop and the clinic) where nothing existing could stand in,
## kept simple. Builder frame as in prop_furniture.gd: footprint centred,
## width w along x, depth d along z, FRONT toward +z, floor at y = 0.
##   gun_rack     a wall rack for long guns: a base cabinet, a dark backboard,
##                a butt ledge, a peg rail and a cable lock; a gun or two by
##                seed. style "empty": nothing on it but pale dust outlines
##   exam_bed     an examination couch: a steel frame, a padded top with a
##                raised head end, a strip of paper sheet and its roll
##   lumber_rack  a cantilever rack: blue uprights at the back, arms on three
##                levels, planks of mixed length on them

const M := preload("res://src/props/prop_materials.gd")

const DARK_WOOD := Color(0.33, 0.23, 0.16)
const BOARD := Color(0.24, 0.19, 0.15)
const GUN_METAL := Color(0.16, 0.16, 0.17)
const STOCK := Color(0.46, 0.3, 0.18)
const STEEL := Color(0.72, 0.73, 0.75)
const VINYL := Color(0.38, 0.52, 0.56)
const PAPER := Color(0.92, 0.92, 0.9)
const RACK_BLUE := Color(0.22, 0.36, 0.58)
const PINE := [Color(0.8, 0.66, 0.47), Color(0.74, 0.6, 0.42), Color(0.84, 0.72, 0.53), Color(0.69, 0.55, 0.38)]


static func build(mm: PropMesh, type: String, w: float, h: float, d: float, rng: RandomNumberGenerator, style: String) -> bool:
	match type:
		"gun_rack":
			_gun_rack(mm, w, d, h, rng, style == "empty")
		"exam_bed":
			_exam_bed(mm, w, d, h)
		"lumber_rack":
			_lumber_rack(mm, w, d, h, rng)
		_:
			return false
	return true


static func _gun_rack(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator, empty: bool) -> void:
	var x := w * 0.5
	var z := d * 0.5
	var base := minf(0.55, h * 0.3)
	# the base cabinet (drawers for the ammunition), the backboard and its crown
	mm.set_mat(M.L_WOOD, DARK_WOOD, 0.15)
	mm.chamfer_box(Vector3(-x, 0, -z), Vector3(x, base, z), 0.01)
	mm.set_mat(M.L_SCREEN, Color(0.05, 0.05, 0.05))
	mm.box(Vector3(-0.004, 0.06, z), Vector3(0.004, base - 0.05, z + 0.004))
	mm.set_mat(M.L_WOOD, BOARD, 0.1)
	mm.box(Vector3(-x, base, -z), Vector3(x, h - 0.05, -z + 0.05))
	mm.set_mat(M.L_WOOD, DARK_WOOD, 0.1)
	mm.box(Vector3(-x, h - 0.05, -z), Vector3(x, h, -z + 0.12))
	# the butt ledge and the peg rail
	mm.box(Vector3(-x + 0.04, base, -z + 0.05), Vector3(x - 0.04, base + 0.05, z - 0.04))
	var rail := h - 0.4
	mm.box(Vector3(-x + 0.04, rail, -z + 0.05), Vector3(x - 0.04, rail + 0.05, -z + 0.15))
	var n := maxi(3, int(floor((w - 0.1) / 0.3)))
	var step := (w - 0.2) / float(n)
	var any := false
	for i in n:
		var cx := -x + 0.1 + step * (i + 0.5)
		mm.set_mat(M.L_METAL, STEEL, 0.2)
		mm.box(Vector3(cx - 0.035, rail + 0.05, -z + 0.1), Vector3(cx - 0.02, rail + 0.09, -z + 0.2))
		mm.box(Vector3(cx + 0.02, rail + 0.05, -z + 0.1), Vector3(cx + 0.035, rail + 0.09, -z + 0.2))
		var gun := not empty and (rng.randf() < 0.3 or (not any and i == n - 1 and rng.randf() < 0.5))
		if gun:
			any = true
			var gz := -z + 0.13
			mm.set_mat(M.L_WOOD, STOCK.darkened(rng.randf_range(0.0, 0.2)), 0.1)
			mm.box(Vector3(cx - 0.03, base + 0.05, gz - 0.02), Vector3(cx + 0.03, base + 0.36, gz + 0.045))
			mm.set_mat(M.L_METAL, GUN_METAL, 0.1)
			mm.box(Vector3(cx - 0.022, base + 0.36, gz - 0.015), Vector3(cx + 0.022, base + 0.58, gz + 0.04))
			mm.box(Vector3(cx - 0.009, base + 0.58, gz), Vector3(cx + 0.009, rail + 0.12, gz + 0.018))
		elif empty:
			# where a gun hung for years: a paler outline on the board
			mm.set_mat(M.L_PLAIN, BOARD.lightened(0.18), 0.0)
			mm.box(Vector3(cx - 0.025, base + 0.08, -z + 0.05), Vector3(cx + 0.025, rail - 0.04, -z + 0.054))
	# the cable lock through the trigger guards, hanging loose when empty
	mm.set_mat(M.L_METAL, STEEL, 0.25)
	var cy := base + 0.44
	if empty:
		mm.obox(Transform3D(Basis(Vector3.BACK, 0.25), Vector3(-x * 0.5, cy - 0.12, -z + 0.11)), Vector3(x * 0.9, 0.012, 0.012))
	else:
		mm.box(Vector3(-x + 0.06, cy, -z + 0.12), Vector3(x - 0.06, cy + 0.012, -z + 0.135))
	mm.set_mat(M.L_METAL, Color(0.72, 0.6, 0.3), 0.1)
	mm.box(Vector3(x - 0.1, cy - 0.06, -z + 0.1), Vector3(x - 0.05, cy + 0.02, -z + 0.15))


static func _exam_bed(mm: PropMesh, w: float, d: float, h: float) -> void:
	var x := w * 0.5
	var z := d * 0.5
	var top := h - 0.07
	# the frame: four legs, a low shelf and the rails under the pad
	mm.set_mat(M.L_METAL, STEEL, 0.15)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var lx: float = sx * (x - 0.08)
			var lz: float = sz * (z - 0.07)
			mm.box(Vector3(lx - 0.02, 0, lz - 0.02), Vector3(lx + 0.02, top - 0.06, lz + 0.02))
	mm.box(Vector3(-x + 0.06, 0.14, -z + 0.05), Vector3(x - 0.06, 0.17, z - 0.05))
	mm.box(Vector3(-x + 0.04, top - 0.08, -z + 0.04), Vector3(x - 0.04, top - 0.04, z - 0.04))
	# the pad: a long flat part and the raised head end
	mm.set_mat(M.L_PLAIN, VINYL, 0.12)
	var head := minf(0.55, w * 0.3)
	mm.chamfer_box(Vector3(-x, top - 0.04, -z), Vector3(x - head, top, z), 0.02)
	mm.ochamfer(Transform3D(Basis(Vector3.BACK, 0.22), Vector3(x - head * 0.5, top + 0.0, 0)), Vector3(head * 0.95, 0.06, d), 0.02)
	# the paper sheet and its roll at the foot end
	mm.thin = true
	mm.set_mat(M.L_PAPER, PAPER, 0.05)
	mm.box(Vector3(-x + 0.05, top, -z * 0.6), Vector3(x - head - 0.02, top + 0.004, z * 0.6))
	mm.thin = false
	mm.tube(Vector3(-x + 0.05, top - 0.09, -z * 0.62), Vector3(-x + 0.05, top - 0.09, z * 0.62), 0.045, 0.045, 8)
	mm.set_mat(M.L_METAL, STEEL, 0.15)
	mm.box(Vector3(-x + 0.0, top - 0.1, -z * 0.68), Vector3(-x + 0.03, top - 0.06, z * 0.68))


static func _lumber_rack(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	var posts := [-x + 0.12, 0.0, x - 0.12] if w > 1.5 else [-x + 0.12, x - 0.12]
	var levels := [0.1, h * 0.38, h * 0.68]
	mm.set_mat(M.L_METAL, RACK_BLUE, 0.2)
	for px in posts:
		mm.box(Vector3(px - 0.05, 0, -z), Vector3(px + 0.05, h, -z + 0.1))
		mm.box(Vector3(px - 0.05, 0, -z), Vector3(px + 0.05, 0.08, z))
		for ly in levels.slice(1):
			mm.box(Vector3(px - 0.03, ly - 0.05, -z + 0.1), Vector3(px + 0.03, ly, z - 0.02))
	mm.set_mat(M.L_METAL, RACK_BLUE.darkened(0.25), 0.2)
	mm.box(Vector3(-x + 0.07, h - 0.08, -z), Vector3(x - 0.07, h - 0.02, -z + 0.08))
	# planks: a full bundle on the floor arms, fewer higher up (it was picked over)
	for li in levels.size():
		var ly: float = levels[li]
		var rows := 3 - li
		for r in rows:
			var zc := -z + 0.12
			while zc < z - 0.16:
				if rng.randf() < 0.25 + 0.15 * li:
					zc += 0.17
					continue
				var length := w * rng.randf_range(0.72, 0.98)
				var off := rng.randf_range(-(w - length) * 0.5, (w - length) * 0.5)
				mm.set_mat(M.L_WOOD, PINE[rng.randi() % PINE.size()], 0.15)
				mm.box(Vector3(off - length * 0.5, ly + r * 0.045, zc), Vector3(off + length * 0.5, ly + r * 0.045 + 0.04, zc + 0.15))
				zc += 0.17
