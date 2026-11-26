extends RefCounted
## Experiment 009 (G): interior pieces for the generated buildings
## (src/poigen/) where nothing existing could stand in. Cheap meshes, one
## surface each (PropKit). Builder frame as in prop_furniture.gd: footprint
## centred, width w along x, depth d along z, FRONT toward +z, floor at y = 0.
##   water_dispenser  an office water cooler: a white cabinet, a blue bottle
##   filing_cabinet   a grey steel cabinet with four drawers, one pulled out
##   tool_rack        a pegboard on the wall with hand tools and a low shelf
##   pallet           a wooden pallet with a load of boxes or bags (style
##                    "bags" | "boxes" | "" = by seed)
##   machine          an industrial machine (a lathe or a press by seed): a
##                    heavy base, a housing, guards and a control box
##   locker           a bank of steel lockers (one door per ~0.4 m), one ajar
##   hospital_bed     a hospital bed: a steel frame on castors, side rails, a
##                    raised head end, a thin mattress and a sheet
##   desk             an office desk: a top, a drawer pedestal, a monitor and
##                    papers
##   safe             a squat steel safe with a dial and a handle
##   pallet_rack      warehouse racking: orange beams, blue uprights, three
##                    levels with boxes and wrapped loads

const M := preload("res://src/props/prop_materials.gd")

const WHITE := Color(0.86, 0.86, 0.83)
const BLUE_WATER := Color(0.42, 0.62, 0.82)
const STEEL_GREY := Color(0.5, 0.52, 0.54)
const DARK := Color(0.12, 0.12, 0.13)
const PEG := Color(0.62, 0.52, 0.38)
const PALLET_WOOD := Color(0.66, 0.54, 0.38)
const CARDBOARD := Color(0.64, 0.51, 0.35)
const SACK := Color(0.78, 0.74, 0.62)
const MACHINE_GREEN := Color(0.32, 0.42, 0.36)
const MACHINE_GREY := Color(0.46, 0.48, 0.47)
const WARN := Color(0.85, 0.68, 0.16)
const LOCKER := Color(0.42, 0.5, 0.58)
const SHEET := Color(0.85, 0.88, 0.9)
const MATTRESS := Color(0.6, 0.72, 0.76)
const DESK_TOP := Color(0.62, 0.5, 0.36)
const SAFE := Color(0.24, 0.27, 0.25)
const RACK_BLUE := Color(0.2, 0.32, 0.55)
const RACK_ORANGE := Color(0.86, 0.46, 0.14)
const WRAP := Color(0.8, 0.82, 0.84)
const PAPER := Color(0.92, 0.91, 0.87)


static func build(mm: PropMesh, type: String, w: float, h: float, d: float, rng: RandomNumberGenerator, style: String) -> bool:
	match type:
		"water_dispenser":
			_water_dispenser(mm, w, d, h)
		"filing_cabinet":
			_filing_cabinet(mm, w, d, h, rng)
		"tool_rack":
			_tool_rack(mm, w, d, h, rng)
		"pallet":
			_pallet(mm, w, d, h, rng, style)
		"machine":
			_machine(mm, w, d, h, rng)
		"locker":
			_locker(mm, w, d, h, rng)
		"hospital_bed":
			_hospital_bed(mm, w, d, h)
		"desk":
			_desk(mm, w, d, h, rng)
		"safe":
			_safe(mm, w, d, h)
		"pallet_rack":
			_pallet_rack(mm, w, d, h, rng)
		_:
			return false
	return true


static func _water_dispenser(mm: PropMesh, w: float, d: float, h: float) -> void:
	var x := w * 0.5
	var z := d * 0.5
	var body := h * 0.68
	mm.set_mat(M.L_GLOSSY, WHITE, 0.15)
	mm.chamfer_box(Vector3(-x, 0, -z), Vector3(x, body, z), 0.02)
	mm.set_mat(M.L_PLAIN, DARK)
	mm.box(Vector3(-x * 0.6, body * 0.55, z), Vector3(x * 0.6, body * 0.75, z + 0.03))
	mm.set_mat(M.L_GLOSSY, Color(0.8, 0.2, 0.18))
	mm.box(Vector3(-x * 0.4, body * 0.7, z + 0.02), Vector3(-x * 0.1, body * 0.74, z + 0.06))
	mm.set_mat(M.L_GLOSSY, BLUE_WATER)
	mm.box(Vector3(x * 0.1, body * 0.7, z + 0.02), Vector3(x * 0.4, body * 0.74, z + 0.06))
	mm.set_mat(M.L_SCREEN, BLUE_WATER.lightened(0.2))
	mm.cylinder(Vector3(0, body, 0), minf(x, z) * 0.85, minf(x, z) * 0.85, h - body - 0.04, 10)
	mm.cylinder(Vector3(0, h - 0.04, 0), minf(x, z) * 0.35, minf(x, z) * 0.3, 0.04, 8)


static func _filing_cabinet(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	mm.set_mat(M.L_METAL, STEEL_GREY, 0.2)
	mm.chamfer_box(Vector3(-x, 0, -z), Vector3(x, h, z), 0.01)
	var n := 4
	var out := rng.randi() % n
	for i in n:
		var y0 := 0.04 + (h - 0.06) * float(i) / float(n)
		var y1 := 0.04 + (h - 0.06) * float(i + 1) / float(n) - 0.02
		var pull := 0.22 if i == out else 0.0
		mm.set_mat(M.L_METAL, STEEL_GREY.lightened(0.06), 0.15)
		mm.box(Vector3(-x + 0.03, y0, z - 0.02 + pull), Vector3(x - 0.03, y1, z + 0.01 + pull))
		mm.set_mat(M.L_METAL, DARK)
		mm.box(Vector3(-0.07, y1 - 0.07, z + 0.01 + pull), Vector3(0.07, y1 - 0.05, z + 0.035 + pull))
		if pull > 0.0:
			mm.set_mat(M.L_PAPER, PAPER)
			mm.box(Vector3(-x + 0.06, y0 + 0.02, z - 0.02), Vector3(x - 0.06, y1 - 0.03, z + pull - 0.02))


static func _tool_rack(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	var shelf := minf(0.9, h * 0.5)
	# the low cabinet, the pegboard behind it
	mm.set_mat(M.L_METAL, Color(0.55, 0.16, 0.14), 0.25)
	mm.chamfer_box(Vector3(-x, 0, -z), Vector3(x, shelf, z), 0.01)
	mm.set_mat(M.L_PLAIN, DARK)
	mm.box(Vector3(-x + 0.04, shelf * 0.5, z), Vector3(x - 0.04, shelf * 0.5 + 0.01, z + 0.004))
	mm.set_mat(M.L_WOOD, PEG, 0.1)
	mm.box(Vector3(-x, shelf, -z), Vector3(x, h, -z + 0.03))
	# hand tools on the hooks
	var n := maxi(3, int(w / 0.22))
	for i in n:
		if rng.randf() < 0.25:
			continue
		var cx := -x + 0.12 + (w - 0.24) * float(i) / float(maxi(n - 1, 1))
		var cy := shelf + 0.25 + rng.randf() * (h - shelf - 0.5)
		var long := rng.randf_range(0.18, 0.38)
		mm.set_mat(M.L_METAL, Color(0.6, 0.62, 0.64), 0.2)
		mm.box(Vector3(cx - 0.012, cy - long * 0.5, -z + 0.03), Vector3(cx + 0.012, cy + long * 0.5, -z + 0.06))
		mm.set_mat(M.L_PLAIN, [Color(0.75, 0.2, 0.15), Color(0.2, 0.3, 0.6), Color(0.85, 0.65, 0.15), DARK][rng.randi() % 4])
		mm.box(Vector3(cx - 0.022, cy - long * 0.5, -z + 0.03), Vector3(cx + 0.022, cy - long * 0.5 + 0.1, -z + 0.07))


static func _pallet(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator, style: String) -> void:
	var x := w * 0.5
	var z := d * 0.5
	var ph := minf(0.14, h * 0.3)
	mm.set_mat(M.L_ROUGH_WOOD, PALLET_WOOD, 0.2)
	for i in 3:
		var bx := -x + 0.05 + (w - 0.15) * float(i) / 2.0
		mm.box(Vector3(bx, 0, -z), Vector3(bx + 0.1, ph - 0.025, z))
	for i in 5:
		var bz := -z + (d - 0.12) * float(i) / 4.0
		mm.box(Vector3(-x, ph - 0.025, bz), Vector3(x, ph, bz + 0.12))
	if h <= ph + 0.05:
		return
	var load := style if style in ["bags", "boxes"] else ("bags" if rng.randf() < 0.35 else "boxes")
	var top := h - ph
	if load == "bags":
		mm.set_mat(M.L_FABRIC, SACK, 0.2)
		var layers := maxi(1, int(top / 0.16))
		for j in layers:
			for i in 2:
				var y := ph + j * 0.16
				mm.chamfer_box(Vector3(-x + 0.04 + i * (w * 0.5 - 0.02), y, -z + 0.06), Vector3(-x + (i + 1) * (w * 0.5 - 0.02), y + 0.15, z - 0.06), 0.04)
	else:
		var layers := maxi(1, int(top / 0.32))
		for j in layers:
			for i in 2:
				for k in 2:
					if j == layers - 1 and rng.randf() < 0.3:
						continue
					var y := ph + j * 0.32
					var c := CARDBOARD.darkened(rng.randf_range(0.0, 0.15))
					mm.set_mat(M.L_PAPER, c, 0.1)
					mm.box(Vector3(-x + 0.04 + i * (w * 0.5 - 0.02), y, -z + 0.04 + k * (d * 0.5 - 0.02)),
						Vector3(-x + (i + 1) * (w * 0.5 - 0.02), y + 0.3, -z + (k + 1) * (d * 0.5 - 0.02)))


static func _machine(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	var col := MACHINE_GREEN if rng.randf() < 0.5 else MACHINE_GREY
	# the heavy base and the bed
	mm.set_mat(M.L_METAL, col.darkened(0.2), 0.35)
	mm.chamfer_box(Vector3(-x, 0, -z), Vector3(x, h * 0.45, z), 0.02)
	mm.set_mat(M.L_METAL, Color(0.55, 0.57, 0.58), 0.3)
	mm.box(Vector3(-x + 0.05, h * 0.45, -z * 0.4), Vector3(x - 0.05, h * 0.5, z * 0.4))
	if rng.randf() < 0.5:
		# a lathe: the headstock, the tailstock, the chuck and the work
		mm.set_mat(M.L_METAL, col, 0.3)
		mm.chamfer_box(Vector3(-x, h * 0.5, -z * 0.6), Vector3(-x + w * 0.28, h * 0.85, z * 0.6), 0.02)
		mm.chamfer_box(Vector3(x - w * 0.16, h * 0.5, -z * 0.4), Vector3(x - 0.04, h * 0.72, z * 0.4), 0.02)
		mm.set_mat(M.L_METAL, Color(0.7, 0.7, 0.72), 0.15)
		mm.tube(Vector3(-x + w * 0.28, h * 0.66, 0), Vector3(x - w * 0.16, h * 0.66, 0), 0.035, 0.035, 6)
	else:
		# a press: the column, the head and the ram
		mm.set_mat(M.L_METAL, col, 0.3)
		mm.chamfer_box(Vector3(-x * 0.5, h * 0.5, -z), Vector3(x * 0.5, h, -z + d * 0.35), 0.02)
		mm.chamfer_box(Vector3(-x * 0.6, h * 0.78, -z), Vector3(x * 0.6, h, z * 0.5), 0.02)
		mm.set_mat(M.L_METAL, Color(0.7, 0.7, 0.72), 0.15)
		mm.box(Vector3(-0.08, h * 0.55, -0.08), Vector3(0.08, h * 0.78, 0.08))
	# hazard stripes and the control box
	mm.set_mat(M.L_PLAIN, WARN, 0.3)
	mm.box(Vector3(-x, h * 0.38, z), Vector3(x, h * 0.43, z + 0.005))
	mm.set_mat(M.L_METAL, Color(0.75, 0.72, 0.6), 0.2)
	mm.box(Vector3(x - 0.3, h * 0.5, z - 0.12), Vector3(x - 0.06, h * 0.75, z))
	mm.set_mat(M.L_GLOSSY, Color(0.8, 0.12, 0.1))
	mm.cylinder(Vector3(x - 0.18, h * 0.66, z), 0.035, 0.035, 0.02, 8)


static func _locker(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	mm.set_mat(M.L_METAL, LOCKER, 0.2)
	mm.box(Vector3(-x, 0, -z), Vector3(x, h, z - 0.02))
	var n := maxi(1, int(round(w / 0.4)))
	var step := w / float(n)
	var ajar := rng.randi() % (n + 1)
	for i in n:
		var x0 := -x + step * i + 0.012
		var x1 := -x + step * (i + 1) - 0.012
		var t := LOCKER.lightened(0.05 + 0.04 * float(i % 2))
		mm.set_mat(M.L_METAL, t, 0.2)
		if i == ajar:
			mm.obox(Transform3D(Basis(Vector3.UP, -0.7), Vector3(x0 + 0.12, h * 0.5 + 0.02, z + 0.12)), Vector3(x1 - x0, h - 0.1, 0.02))
			mm.set_mat(M.L_PLAIN, DARK)
			mm.box(Vector3(x0, 0.06, z - 0.03), Vector3(x1, h - 0.04, z - 0.02))
			continue
		mm.box(Vector3(x0, 0.05, z - 0.02), Vector3(x1, h - 0.03, z))
		mm.set_mat(M.L_PLAIN, DARK)
		for k in 3:
			mm.box(Vector3(x0 + 0.05, h - 0.2 - k * 0.04, z), Vector3(x1 - 0.05, h - 0.19 - k * 0.04, z + 0.004))
		mm.set_mat(M.L_METAL, Color(0.75, 0.75, 0.75))
		mm.box(Vector3(x1 - 0.06, h * 0.5, z), Vector3(x1 - 0.04, h * 0.5 + 0.1, z + 0.02))


static func _hospital_bed(mm: PropMesh, w: float, d: float, h: float) -> void:
	var x := w * 0.5
	var z := d * 0.5
	var top := h * 0.62
	mm.set_mat(M.L_METAL, Color(0.72, 0.74, 0.76), 0.15)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mm.box(Vector3(sx * x - 0.03, 0.06, sz * z - 0.03), Vector3(sx * x + 0.03 * -sx, top, sz * z + 0.03 * -sz))
			mm.cylinder(Vector3(sx * (x - 0.04), 0, sz * (z - 0.04)), 0.04, 0.04, 0.06, 6)
	mm.box(Vector3(-x, top - 0.08, -z), Vector3(x, top - 0.03, z))
	# the head end raised (at the back, -z), the foot board, the side rails
	mm.set_mat(M.L_GLOSSY, Color(0.85, 0.85, 0.82), 0.1)
	mm.box(Vector3(-x, top - 0.05, -z), Vector3(x, h + 0.3, -z + 0.05))
	mm.box(Vector3(-x, top - 0.05, z - 0.05), Vector3(x, h, z))
	mm.set_mat(M.L_METAL, Color(0.72, 0.74, 0.76), 0.15)
	for sx in [-1.0, 1.0]:
		mm.box(Vector3(sx * x - 0.015, top + 0.12, -z + 0.3), Vector3(sx * x + 0.015, top + 0.15, -z * 0.1))
	mm.set_mat(M.L_FABRIC, MATTRESS, 0.15)
	mm.chamfer_box(Vector3(-x + 0.04, top - 0.03, -z + 0.06), Vector3(x - 0.04, top + 0.1, z - 0.06), 0.03)
	mm.set_mat(M.L_FABRIC, SHEET, 0.1)
	mm.box(Vector3(-x + 0.03, top + 0.06, -z * 0.1), Vector3(x - 0.03, top + 0.12, z - 0.08))
	mm.chamfer_box(Vector3(-x * 0.6, top + 0.08, -z + 0.08), Vector3(x * 0.6, top + 0.2, -z + 0.42), 0.04)


static func _desk(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	mm.set_mat(M.L_WOOD, DESK_TOP, 0.12)
	mm.box(Vector3(-x, h - 0.04, -z), Vector3(x, h, z))
	mm.set_mat(M.L_METAL, STEEL_GREY.darkened(0.2), 0.2)
	mm.box(Vector3(-x + 0.02, 0, -z + 0.03), Vector3(-x + 0.06, h - 0.04, z - 0.03))
	mm.box(Vector3(-x + 0.02, 0.6, -z + 0.03), Vector3(x - 0.02, 0.64, -z + 0.06))
	# the drawer pedestal on the right
	mm.set_mat(M.L_METAL, STEEL_GREY, 0.2)
	mm.box(Vector3(x - 0.45, 0, -z + 0.04), Vector3(x - 0.02, h - 0.04, z - 0.04))
	mm.set_mat(M.L_PLAIN, DARK)
	for k in 3:
		var y := 0.1 + k * (h - 0.16) / 3.0
		mm.box(Vector3(x - 0.3, y + 0.12, z - 0.04), Vector3(x - 0.17, y + 0.14, z - 0.02))
	# a monitor at the back, papers and a mug on the top
	mm.set_mat(M.L_PLAIN, DARK)
	mm.box(Vector3(-0.05, h, -z + 0.12), Vector3(0.05, h + 0.12, -z + 0.2))
	mm.box(Vector3(-0.28, h + 0.1, -z + 0.12), Vector3(0.28, h + 0.42, -z + 0.16))
	mm.set_mat(M.L_SCREEN, Color(0.08, 0.09, 0.1))
	mm.box(Vector3(-0.26, h + 0.12, -z + 0.16), Vector3(0.26, h + 0.4, -z + 0.165))
	mm.set_mat(M.L_PAPER, PAPER)
	mm.obox(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.4, 0.4)), Vector3(-x * 0.5, h + 0.004, z * 0.3)), Vector3(0.3, 0.008, 0.22))
	mm.set_mat(M.L_GLOSSY, Color(0.8, 0.78, 0.72))
	mm.cylinder(Vector3(x * 0.45, h, z * 0.2), 0.04, 0.04, 0.1, 8)


static func _safe(mm: PropMesh, w: float, d: float, h: float) -> void:
	var x := w * 0.5
	var z := d * 0.5
	mm.set_mat(M.L_METAL, SAFE, 0.25)
	mm.chamfer_box(Vector3(-x, 0, -z), Vector3(x, h, z), 0.03)
	mm.set_mat(M.L_METAL, SAFE.lightened(0.08), 0.2)
	mm.box(Vector3(-x + 0.05, 0.05, z), Vector3(x - 0.05, h - 0.05, z + 0.02))
	mm.set_mat(M.L_METAL, Color(0.75, 0.72, 0.6), 0.1)
	mm.obox(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-x * 0.3, h * 0.6, z + 0.04)), Vector3(0.12, 0.04, 0.12))
	mm.box(Vector3(x * 0.2, h * 0.45, z + 0.02), Vector3(x * 0.55, h * 0.5, z + 0.06))


static func _pallet_rack(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	mm.set_mat(M.L_METAL, RACK_BLUE, 0.25)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var px: float = sx * (x - 0.04)
			var pz: float = sz * (z - 0.04)
			mm.box(Vector3(px - 0.04, 0, pz - 0.04), Vector3(px + 0.04, h, pz + 0.04))
		mm.box(Vector3(sx * (x - 0.04) - 0.02, 0.3, -z + 0.04), Vector3(sx * (x - 0.04) + 0.02, 0.34, z - 0.04))
	var levels := 3
	for k in levels:
		var y := 0.12 + (h - 0.2) * float(k) / float(levels)
		mm.set_mat(M.L_METAL, RACK_ORANGE, 0.2)
		mm.box(Vector3(-x, y, -z), Vector3(x, y + 0.08, -z + 0.06))
		mm.box(Vector3(-x, y, z - 0.06), Vector3(x, y + 0.08, z))
		var room := (h - 0.2) / float(levels) - 0.16
		for i in 2:
			if rng.randf() < 0.3:
				continue
			var lx0 := -x + 0.1 + i * (w * 0.5 - 0.05)
			var lx1 := lx0 + w * 0.5 - 0.2
			var lh := room * rng.randf_range(0.5, 0.95)
			if rng.randf() < 0.5:
				mm.set_mat(M.L_TARP, WRAP, 0.1)
				mm.chamfer_box(Vector3(lx0, y + 0.08, -z + 0.08), Vector3(lx1, y + 0.08 + lh, z - 0.08), 0.03)
			else:
				mm.set_mat(M.L_PAPER, CARDBOARD.darkened(rng.randf_range(0.0, 0.15)), 0.1)
				mm.box(Vector3(lx0, y + 0.08, -z + 0.08), Vector3(lx1, y + 0.08 + lh, z - 0.08))
