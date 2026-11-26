extends RefCounted
## Experiment 009 (X): outdoor pieces for the generated places' surroundings
## (PoiExterior), in the kit's style: cheap boxes and tubes, northern winter
## (snow lying on every top), muted paint, rust and disrepair. Visual only;
## PoiWorld gives the large ones collision. Builder frame as in
## prop_furniture.gd: footprint centred, width w along x, depth d along z,
## FRONT toward +z, floor at y = 0. Colours vary with the seed.
##   ext_car, ext_police, ext_wreck   a parked hatchback, a police car (light
##                bar, dark band), a burnt-out wreck on its rims
##   ext_van, ext_ambulance   a boxy van (delivery), an ambulance (stripe,
##                light bar)
##   ext_fence    a steel mesh fence (span: the longer side), a post every 2.4 m
##   ext_fence_wood   a picket fence with boards missing (span)
##   ext_container    a shipping container, doors at the front
##   ext_dumpster, ext_bin, ext_medwaste   a big waste container, a wheelie
##                bin, a yellow medical waste bin
##   ext_pallets, ext_barrels, ext_scrap   stacked pallets, oil drums (one
##                tipped), a heap of rusted scrap and tyres
##   ext_trolley  two shopping trolleys nested, a third tipped by seed
##   ext_sign_shop, ext_sign_medical, ext_sign_police, ext_sign_dir   signs on
##                posts (a lettered board, a red cross, a blue band, an arrow)
##   ext_bike_rack, ext_bench, ext_lamp_post, ext_snowbank
##   ext_shed     a small garden shed (pitched roof, a door at the front)
##   ext_garage   a detached garage with a roller door at the front
##   ext_roller_door  a loading door panel to stand against a wall (span)
##   ext_barrier  a concrete barrier with faded red and white stripes
##   ext_machine, ext_forklift   a site generator on skids, a forklift
##   ext_toolbox, ext_portaloo

const M := preload("res://src/props/prop_materials.gd")

const TYPES := ["ext_car", "ext_police", "ext_wreck", "ext_van", "ext_ambulance", "ext_fence", "ext_fence_wood",
	"ext_container", "ext_dumpster", "ext_bin", "ext_medwaste", "ext_pallets", "ext_barrels", "ext_scrap",
	"ext_trolley", "ext_sign_shop", "ext_sign_medical", "ext_sign_police", "ext_sign_dir", "ext_bike_rack",
	"ext_bench", "ext_lamp_post", "ext_snowbank", "ext_shed", "ext_garage", "ext_roller_door", "ext_barrier",
	"ext_machine", "ext_forklift", "ext_toolbox", "ext_portaloo"]
## Spans: the longer horizontal side is the span (as PropKit.SPAN_TYPES).
const SPANS := ["ext_fence", "ext_fence_wood", "ext_roller_door"]
## Default sizes (w across the front, h, d front to back).
const SIZES := {
	"ext_car": Vector3(1.9, 1.45, 4.3), "ext_police": Vector3(1.9, 1.6, 4.5), "ext_wreck": Vector3(1.9, 1.25, 4.3),
	"ext_van": Vector3(2.0, 2.2, 5.0), "ext_ambulance": Vector3(2.1, 2.5, 5.4),
	"ext_fence": Vector3(4.8, 1.8, 0.2), "ext_fence_wood": Vector3(4.0, 1.0, 0.2),
	"ext_container": Vector3(2.4, 2.5, 6.0), "ext_dumpster": Vector3(1.9, 1.3, 1.1), "ext_bin": Vector3(0.6, 1.05, 0.7),
	"ext_medwaste": Vector3(0.7, 1.0, 0.6), "ext_pallets": Vector3(1.2, 0.8, 1.0), "ext_barrels": Vector3(1.4, 0.9, 1.2),
	"ext_scrap": Vector3(2.4, 1.1, 1.8), "ext_trolley": Vector3(0.6, 1.0, 1.4),
	"ext_sign_shop": Vector3(2.4, 3.0, 0.3), "ext_sign_medical": Vector3(1.4, 2.6, 0.3), "ext_sign_police": Vector3(1.6, 2.6, 0.3),
	"ext_sign_dir": Vector3(0.9, 1.9, 0.2), "ext_bike_rack": Vector3(2.2, 0.95, 1.8), "ext_bench": Vector3(1.6, 0.85, 0.6),
	"ext_lamp_post": Vector3(0.3, 4.2, 0.3), "ext_snowbank": Vector3(2.2, 0.55, 1.1), "ext_shed": Vector3(2.0, 2.3, 1.8),
	"ext_garage": Vector3(3.4, 2.7, 5.6), "ext_roller_door": Vector3(3.0, 2.5, 0.12), "ext_barrier": Vector3(2.0, 0.8, 0.6),
	"ext_machine": Vector3(1.0, 1.1, 1.8), "ext_forklift": Vector3(1.2, 2.1, 2.4), "ext_toolbox": Vector3(0.6, 0.35, 0.3),
	"ext_portaloo": Vector3(1.1, 2.3, 1.1),
}
## Reach beyond the size (PropKit.OVERHANG's layout): snow caps, the lamp's arm.
const OVERHANG := {
	"ext_lamp_post": [0.0, 0.05, 0.75, 0.0], "ext_dumpster": [0.0, 0.25, 0.0, 0.0],
	"ext_shed": [0.08, 0.15, 0.14, 0.14], "ext_garage": [0.14, 0.14, 0.14, 0.14],
}

const SNOW := Color(0.88, 0.9, 0.94)
const SNOW_SHADE := Color(0.8, 0.84, 0.9)
const TYRE := Color(0.08, 0.08, 0.09)
const GLASS := Color(0.13, 0.15, 0.17)
const STEEL := Color(0.55, 0.57, 0.58)
const DARK := Color(0.17, 0.17, 0.18)
const RUST := Color(0.42, 0.24, 0.15)
const CAR_PAINT := [Color(0.3, 0.34, 0.38), Color(0.34, 0.38, 0.32), Color(0.6, 0.56, 0.47), Color(0.22, 0.24, 0.27),
	Color(0.44, 0.22, 0.2), Color(0.55, 0.56, 0.55), Color(0.24, 0.3, 0.42)]
const CONTAINER_PAINT := [Color(0.48, 0.2, 0.15), Color(0.2, 0.32, 0.45), Color(0.24, 0.37, 0.28), Color(0.5, 0.5, 0.48), Color(0.62, 0.45, 0.2)]
const BIN_PAINT := [Color(0.2, 0.34, 0.24), Color(0.16, 0.17, 0.18), Color(0.22, 0.3, 0.45), Color(0.45, 0.32, 0.18)]
const WOOD := [Color(0.62, 0.5, 0.36), Color(0.55, 0.43, 0.3), Color(0.68, 0.56, 0.4)]


static func build(mm: PropMesh, type: String, w: float, h: float, d: float, rng: RandomNumberGenerator, _style := "") -> bool:
	match type:
		"ext_car", "ext_police", "ext_wreck":
			_sedan(mm, w, d, h, rng, type)
		"ext_van", "ext_ambulance":
			_boxy(mm, w, d, h, rng, type == "ext_ambulance")
		"ext_fence":
			_fence(mm, w, d, h, rng)
		"ext_fence_wood":
			_picket(mm, w, d, h, rng)
		"ext_container":
			_container(mm, w, d, h, rng)
		"ext_dumpster":
			_dumpster(mm, w, d, h, rng)
		"ext_bin", "ext_medwaste":
			_bin(mm, w, d, h, rng, type == "ext_medwaste")
		"ext_pallets":
			_pallets(mm, w, d, h, rng)
		"ext_barrels":
			_barrels(mm, w, d, h, rng)
		"ext_scrap":
			_scrap(mm, w, d, h, rng)
		"ext_trolley":
			_trolleys(mm, w, d, h, rng)
		"ext_sign_shop", "ext_sign_medical", "ext_sign_police", "ext_sign_dir":
			_sign(mm, w, d, h, rng, type.trim_prefix("ext_sign_"))
		"ext_bike_rack":
			_bike_rack(mm, w, d, h, rng)
		"ext_bench":
			_bench(mm, w, d, h, rng)
		"ext_lamp_post":
			_lamp_post(mm, w, d, h)
		"ext_snowbank":
			_snowbank(mm, w, d, h, rng)
		"ext_shed":
			_shed(mm, w, d, h, rng)
		"ext_garage":
			_garage(mm, w, d, h, rng)
		"ext_roller_door":
			_roller(mm, w, d, h, rng)
		"ext_barrier":
			_barrier(mm, w, d, h)
		"ext_machine":
			_machine(mm, w, d, h, rng)
		"ext_forklift":
			_forklift(mm, w, d, h)
		"ext_toolbox":
			_toolbox(mm, w, d, h)
		"ext_portaloo":
			_portaloo(mm, w, d, h)
		_:
			return false
	return true


static func _snow(mm: PropMesh, lo: Vector3, hi: Vector3) -> void:
	mm.set_mat(M.L_PLAIN, SNOW, 0.0)
	mm.box(lo, hi, ["-y"])


## A profile in the z-y plane (u = depth, v = height) extruded along x from x0 to x1.
static func _extrude_x(mm: PropMesh, pts: PackedVector2Array, x0: float, x1: float) -> void:
	var keep := mm.xf
	mm.xf = keep * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)
	mm.extrude(pts, x0, x1)
	mm.xf = keep


static func _wheel(mm: PropMesh, c: Vector3, r: float, wd: float, side: float, rim := STEEL) -> void:
	mm.set_mat(M.L_PLAIN, TYRE, 0.3)
	mm.tube(c + Vector3(-wd * 0.5, 0, 0), c + Vector3(wd * 0.5, 0, 0), r, r, 10)
	mm.set_mat(M.L_METAL, rim, 0.35)
	mm.tube(c + Vector3(side * wd * 0.5, 0, 0), c + Vector3(side * (wd * 0.5 + 0.005), 0, 0), r * 0.55, r * 0.55, 8)


# --- vehicles ------------------------------------------------------------------------------

static func _sedan(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator, type: String) -> void:
	var x := w * 0.47
	var z := d * 0.5
	var wreck := type == "ext_wreck"
	var police := type == "ext_police"
	var paint: Color = Color(0.86, 0.87, 0.86) if police else CAR_PAINT[rng.randi() % CAR_PAINT.size()]
	if wreck:
		paint = RUST.lerp(Color(0.2, 0.18, 0.17), rng.randf_range(0.2, 0.6))
	var low := 0.14 if wreck else 0.28
	var belt := low + 0.5
	var top := h - (0.2 if police else 0.04)
	var layer := M.L_RUST if wreck else M.L_GLOSSY
	mm.set_mat(layer, paint, 0.35 if wreck else 0.2)
	mm.chamfer_box(Vector3(-x, low, -z + 0.05), Vector3(x, belt, z - 0.05), 0.08)
	var cb := [Vector3(-x + 0.08, belt, -z + 1.0), Vector3(x - 0.08, belt, -z + 1.0), Vector3(x - 0.08, belt, z - 1.3), Vector3(-x + 0.08, belt, z - 1.3)]
	var ct := [Vector3(-x + 0.2, top, -z + 1.4), Vector3(x - 0.2, top, -z + 1.4), Vector3(x - 0.2, top, z - 1.85), Vector3(-x + 0.2, top, z - 1.85)]
	mm.set_mat(layer, paint.darkened(0.06), 0.25)
	mm.poly(PackedVector3Array([ct[0], ct[1], ct[2], ct[3]]), Vector3.UP)
	mm.set_mat(M.L_PLAIN if wreck else M.L_SCREEN, Color(0.03, 0.03, 0.03) if wreck else GLASS, 0.3)
	mm.quad(cb[0], cb[1], ct[1], ct[0])
	mm.quad(cb[2], cb[3], ct[3], ct[2])
	mm.quad(cb[1], cb[2], ct[2], ct[1])
	mm.quad(cb[3], cb[0], ct[0], ct[3])
	# snow on the roof and the bonnet, a drift against one side
	_snow(mm, Vector3(-x + 0.24, top, -z + 1.45), Vector3(x - 0.24, top + 0.07, z - 1.9))
	_snow(mm, Vector3(-x + 0.06, belt, z - 1.2), Vector3(x - 0.06, belt + 0.05, z - 0.12))
	_snow(mm, Vector3(-x + 0.06, belt, -z + 0.12), Vector3(x - 0.06, belt + 0.04, -z + 0.9))
	if police:
		mm.set_mat(M.L_PLAIN, Color(0.12, 0.18, 0.36), 0.2)
		mm.box(Vector3(-x - 0.005, low + 0.12, -z + 0.3), Vector3(x + 0.005, low + 0.3, z - 0.3))
		mm.set_mat(M.L_PLAIN, DARK, 0.1)
		mm.box(Vector3(-x + 0.35, top, -0.25), Vector3(x - 0.35, top + 0.06, 0.05))
		mm.set_mat(M.L_GLOSSY, Color(0.2, 0.3, 0.85))
		mm.box(Vector3(-x + 0.38, top + 0.06, -0.22), Vector3(-0.02, top + 0.16, 0.02))
		mm.set_mat(M.L_GLOSSY, Color(0.8, 0.14, 0.12))
		mm.box(Vector3(0.02, top + 0.06, -0.22), Vector3(x - 0.38, top + 0.16, 0.02))
	for sz in [-1.0, 1.0]:
		for sx in [-1.0, 1.0]:
			var c := Vector3(sx * (x - 0.1), 0.0, sz * (z - 0.75))
			if wreck:
				mm.set_mat(M.L_RUST, RUST.darkened(0.3), 0.5)
				mm.tube(c + Vector3(-0.06, 0.2, 0), c + Vector3(0.06, 0.2, 0), 0.2, 0.2, 8)
			else:
				var r := 0.33 if rng.randf() > 0.15 else 0.26
				c.y = r
				_wheel(mm, c, r, 0.22, sx)
	if not wreck:
		mm.set_mat(M.L_GLOSSY, Color(0.84, 0.82, 0.74))
		for sx in [-1.0, 1.0]:
			mm.box(Vector3(sx * x * 0.7 - 0.13, belt - 0.2, z - 0.06), Vector3(sx * x * 0.7 + 0.13, belt - 0.12, z - 0.02))
		mm.set_mat(M.L_GLOSSY, Color(0.5, 0.09, 0.07))
		for sx in [-1.0, 1.0]:
			mm.box(Vector3(sx * x * 0.7 - 0.14, belt - 0.2, -z + 0.02), Vector3(sx * x * 0.7 + 0.14, belt - 0.12, -z + 0.06))
	mm.set_mat(M.L_PLAIN, Color(0.15, 0.15, 0.16), 0.3)
	mm.box(Vector3(-x, low - 0.03, z - 0.1), Vector3(x, low + 0.12, z + 0.01))
	mm.box(Vector3(-x, low - 0.03, -z - 0.01), Vector3(x, low + 0.12, -z + 0.1))
	mm.set_mat(M.L_RUST, paint.darkened(0.3), 0.4)
	mm.box(Vector3(x - 0.002, low + 0.02, -z + 0.4), Vector3(x + 0.004, low + 0.1, -z + 1.3))


static func _boxy(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator, ambulance: bool) -> void:
	var x := w * 0.48
	var z := d * 0.5
	var paint: Color = Color(0.88, 0.88, 0.85) if ambulance else [Color(0.82, 0.82, 0.8), Color(0.5, 0.52, 0.53), Color(0.3, 0.36, 0.46)][rng.randi() % 3]
	var low := 0.32
	var cab := z - 1.5
	var cab_h := minf(h - 0.25, 1.85)
	mm.set_mat(M.L_GLOSSY, paint, 0.22)
	mm.chamfer_box(Vector3(-x, low, -z), Vector3(x, h - 0.05, cab), 0.06)            # the box
	mm.chamfer_box(Vector3(-x, low, cab), Vector3(x, low + 0.62, z - 0.05), 0.06)    # the bonnet
	mm.chamfer_box(Vector3(-x, low + 0.62, cab), Vector3(x, cab_h, cab + 0.45), 0.04)  # the cab roof's back
	mm.set_mat(M.L_SCREEN, GLASS, 0.3)
	mm.quad(Vector3(-x + 0.06, low + 0.62, z - 0.4), Vector3(x - 0.06, low + 0.62, z - 0.4), Vector3(x - 0.06, cab_h, cab + 0.45), Vector3(-x + 0.06, cab_h, cab + 0.45))
	mm.set_mat(M.L_GLOSSY, paint.darkened(0.05), 0.2)
	for sx in [-1.0, 1.0]:
		mm.poly(PackedVector3Array([Vector3(sx * x, low + 0.62, cab + 0.45), Vector3(sx * x, low + 0.62, z - 0.4), Vector3(sx * x, cab_h, cab + 0.45)]), Vector3(sx, 0, 0))
		mm.set_mat(M.L_SCREEN, GLASS, 0.3)
		mm.box(Vector3(sx * x - 0.004, low + 0.85, cab + 0.05), Vector3(sx * x + 0.004, cab_h - 0.12, cab + 0.42))
		mm.set_mat(M.L_GLOSSY, paint.darkened(0.05), 0.2)
	if ambulance:
		mm.set_mat(M.L_PLAIN, Color(0.75, 0.14, 0.12), 0.2)
		mm.box(Vector3(-x - 0.006, low + 0.55, -z + 0.1), Vector3(x + 0.006, low + 0.75, z - 0.2))
		mm.set_mat(M.L_PLAIN, Color(0.2, 0.42, 0.75), 0.15)
		mm.box(Vector3(-x + 0.3, cab_h, cab + 0.05), Vector3(x - 0.3, cab_h + 0.12, cab + 0.35))
		# a pale cross on each side of the box
		mm.set_mat(M.L_PLAIN, Color(0.75, 0.14, 0.12), 0.1)
		for sx in [-1.0, 1.0]:
			var cz := -z * 0.35
			mm.box(Vector3(sx * x - 0.006, h * 0.62 - 0.08, cz - 0.3), Vector3(sx * x + 0.006, h * 0.62 + 0.08, cz + 0.3))
			mm.box(Vector3(sx * x - 0.006, h * 0.62 - 0.3, cz - 0.08), Vector3(sx * x + 0.006, h * 0.62 + 0.3, cz + 0.08))
	else:
		mm.set_mat(M.L_PLAIN, paint.darkened(0.25), 0.3)
		for sx in [-1.0, 1.0]:
			mm.box(Vector3(sx * x - 0.005, low + 0.9, -z + 0.5), Vector3(sx * x + 0.005, h - 0.45, cab - 0.5))
	# rear doors, snow on top
	mm.set_mat(M.L_PLAIN, paint.darkened(0.3), 0.3)
	mm.box(Vector3(-0.01, low + 0.1, -z - 0.006), Vector3(0.01, h - 0.15, -z))
	_snow(mm, Vector3(-x + 0.05, h - 0.05, -z + 0.05), Vector3(x - 0.05, h + 0.03, cab - 0.05))
	_snow(mm, Vector3(-x + 0.05, low + 0.62, z - 0.45), Vector3(x - 0.05, low + 0.67, z - 0.1))
	for sz in [-1.0, 1.0]:
		for sx in [-1.0, 1.0]:
			_wheel(mm, Vector3(sx * (x - 0.12), 0.36, sz * (z - 0.9)), 0.36, 0.24, sx)
	mm.set_mat(M.L_GLOSSY, Color(0.84, 0.82, 0.74))
	for sx in [-1.0, 1.0]:
		mm.box(Vector3(sx * x * 0.72 - 0.13, low + 0.42, z - 0.06), Vector3(sx * x * 0.72 + 0.13, low + 0.52, z - 0.02))
	mm.set_mat(M.L_PLAIN, Color(0.15, 0.15, 0.16), 0.3)
	mm.box(Vector3(-x, low - 0.04, z - 0.1), Vector3(x, low + 0.14, z + 0.02))


# --- fences, doors, barriers ------------------------------------------------------------------

static func _fence(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var n := maxi(1, int(ceil(w / 2.4)))
	mm.set_mat(M.L_METAL, STEEL.darkened(0.15), 0.4)
	for i in n + 1:
		var px := -x + w * float(i) / float(n)
		mm.box(Vector3(px - 0.03, 0, -0.03), Vector3(px + 0.03, h, 0.03))
		_snow(mm, Vector3(px - 0.035, h, -0.035), Vector3(px + 0.035, h + 0.04, 0.035))
	mm.box(Vector3(-x, h - 0.06, -0.02), Vector3(x, h - 0.02, 0.02))
	mm.box(Vector3(-x, 0.08, -0.015), Vector3(x, 0.11, 0.015))
	# the mesh: thin wires, sagging (and torn open in one bay now and then)
	mm.set_mat(M.L_METAL, Color(0.6, 0.62, 0.62), 0.5)
	var torn := rng.randi() % (n * 3) if n > 0 else -1
	var k := 0
	var wx := -x + 0.08
	while wx < x - 0.04:
		var bay := int((wx + x) / maxf(w / float(n), 0.01))
		if bay != torn:
			mm.box(Vector3(wx - 0.006, 0.11, -0.006), Vector3(wx + 0.006, h - 0.06, 0.006))
		wx += 0.16
		k += 1
	for y in [h * 0.36, h * 0.68]:
		mm.box(Vector3(-x, y - 0.006, -0.006), Vector3(x, y + 0.006, 0.006))
	_snow(mm, Vector3(-x, 0, -0.12), Vector3(x, 0.09, 0.12))


static func _picket(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var paint: Color = Color(0.78, 0.76, 0.7) if rng.randf() < 0.6 else WOOD[rng.randi() % WOOD.size()]
	mm.set_mat(M.L_ROUGH_WOOD, paint.darkened(0.1), 0.45)
	var n := maxi(1, int(ceil(w / 2.0)))
	for i in n + 1:
		var px := clampf(-x + w * float(i) / float(n), -x + 0.045, x - 0.045)
		mm.box(Vector3(px - 0.045, 0, -0.045), Vector3(px + 0.045, h, 0.045))
	for y in [h * 0.25, h * 0.75]:
		mm.box(Vector3(-x, y - 0.035, -0.04), Vector3(x, y + 0.035, -0.0))
	mm.grain_v = true
	var px2 := -x + 0.06
	while px2 < x - 0.05:
		var r := rng.randf()
		if r > 0.12:
			var top := h - (0.0 if r > 0.3 else rng.randf_range(0.2, 0.45))
			mm.set_mat(M.L_ROUGH_WOOD, paint.darkened(rng.randf_range(0.0, 0.12)), 0.45)
			mm.box(Vector3(px2 - 0.04, 0.03, 0.0), Vector3(px2 + 0.04, top, 0.025))
			_snow(mm, Vector3(px2 - 0.042, top, -0.0), Vector3(px2 + 0.042, top + 0.03, 0.027))
		px2 += 0.15
	mm.grain_v = false
	_snow(mm, Vector3(-x, 0, -0.1), Vector3(x, 0.1, 0.1))


static func _roller(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	mm.set_mat(M.L_METAL, Color(0.36, 0.37, 0.38), 0.4)
	mm.box(Vector3(-x, 0, -d * 0.5), Vector3(-x + 0.12, h, d * 0.5))
	mm.box(Vector3(x - 0.12, 0, -d * 0.5), Vector3(x, h, d * 0.5))
	mm.box(Vector3(-x, h - 0.3, -d * 0.5), Vector3(x, h, d * 0.5))
	var c: Color = [Color(0.62, 0.62, 0.6), Color(0.5, 0.55, 0.6), Color(0.55, 0.5, 0.36)][rng.randi() % 3]
	var y := 0.0
	var k := 0
	while y < h - 0.3:
		mm.set_mat(M.L_METAL, c.darkened(0.08 if k % 2 == 0 else 0.0), 0.45)
		mm.box(Vector3(-x + 0.12, y, -d * 0.2), Vector3(x - 0.12, minf(y + 0.12, h - 0.3), d * 0.2))
		y += 0.12
		k += 1
	mm.set_mat(M.L_RUST, RUST, 0.5)
	mm.box(Vector3(-x + 0.12, 0, d * 0.2), Vector3(x - 0.12, 0.18, d * 0.22))


static func _barrier(mm: PropMesh, w: float, d: float, h: float) -> void:
	var x := w * 0.5
	var z := d * 0.5
	mm.set_mat(M.L_CONCRETE, Color(0.66, 0.65, 0.62), 0.35)
	_extrude_x(mm, PackedVector2Array([Vector2(-z, 0), Vector2(z, 0), Vector2(z * 0.4, h * 0.3), Vector2(z * 0.3, h), Vector2(-z * 0.3, h), Vector2(-z * 0.4, h * 0.3)]), -x, x)
	mm.set_mat(M.L_PLAIN, Color(0.66, 0.2, 0.16), 0.4)
	var n := int(w / 0.5)
	for i in n:
		if i % 2 == 0:
			var px := -x + 0.5 * i
			mm.box(Vector3(px, h * 0.55, -z * 0.36), Vector3(px + 0.5, h * 0.8, z * 0.36))
	_snow(mm, Vector3(-x, h, -z * 0.3), Vector3(x, h + 0.05, z * 0.3))


# --- containers and bins ----------------------------------------------------------------------

static func _container(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	var c: Color = CONTAINER_PAINT[rng.randi() % CONTAINER_PAINT.size()]
	mm.set_mat(M.L_METAL, c, 0.45)
	mm.box(Vector3(-x, 0, -z), Vector3(x, h, z))
	# ribs along the sides, the corner posts, the door bars at the front
	mm.set_mat(M.L_METAL, c.darkened(0.15), 0.5)
	var rz := -z + 0.2
	while rz < z - 0.2:
		for sx in [-1.0, 1.0]:
			mm.box(Vector3(sx * x - 0.03, 0.1, rz), Vector3(sx * x + 0.03, h - 0.1, rz + 0.12))
		rz += 0.3
	mm.set_mat(M.L_METAL, DARK, 0.4)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var cx: float = x - 0.12 if sx > 0.0 else -x
			var cz: float = z - 0.12 if sz > 0.0 else -z
			mm.box(Vector3(cx, 0, cz), Vector3(cx + 0.12, h, cz + 0.12))
	mm.set_mat(M.L_METAL, STEEL.darkened(0.2), 0.4)
	for bx in [-x * 0.6, -x * 0.2, x * 0.2, x * 0.6]:
		mm.box(Vector3(bx - 0.025, 0.1, z), Vector3(bx + 0.025, h - 0.1, z + 0.04))
	mm.set_mat(M.L_RUST, RUST, 0.6)
	mm.box(Vector3(-x - 0.004, 0.0, -z + rng.randf_range(0.3, 2.0)), Vector3(-x + 0.0, 0.5, -z + rng.randf_range(2.5, 4.0)))
	_snow(mm, Vector3(-x + 0.02, h, -z + 0.02), Vector3(x - 0.02, h + 0.1, z - 0.02))


static func _dumpster(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	var c: Color = BIN_PAINT[rng.randi() % BIN_PAINT.size()]
	mm.set_mat(M.L_METAL, c, 0.5)
	_extrude_x(mm, PackedVector2Array([Vector2(-z + 0.08, 0.15), Vector2(z, 0.15), Vector2(z, h - 0.1), Vector2(-z, h - 0.1)]), -x, x)
	mm.set_mat(M.L_METAL, c.darkened(0.2), 0.45)
	# the lid, propped half open
	mm.obox(Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(0, h - 0.02, 0.0)), Vector3(w - 0.02, 0.05, d))
	mm.set_mat(M.L_PLAIN, TYRE, 0.3)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mm.cylinder(Vector3(sx * (x - 0.15), 0, sz * (z - 0.15)), 0.07, 0.07, 0.15, 6)
	# a black bag spilling over the rim
	mm.set_mat(M.L_TARP, Color(0.07, 0.07, 0.08), 0.2)
	mm.blob(Vector3(x * 0.4, h - 0.05, z * 0.6), Vector3(0.25, 0.18, 0.22))
	_snow(mm, Vector3(-x + 0.05, h + 0.06, -z + 0.15), Vector3(x * 0.2, h + 0.12, z * 0.3))


static func _bin(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator, medical: bool) -> void:
	var x := w * 0.5
	var z := d * 0.5
	var c: Color = Color(0.86, 0.72, 0.16) if medical else BIN_PAINT[rng.randi() % BIN_PAINT.size()]
	mm.set_mat(M.L_PLAIN, c, 0.35)
	mm.chamfer_box(Vector3(-x * 0.9, 0.05, -z * 0.9), Vector3(x, h - 0.08, z), 0.03)
	mm.set_mat(M.L_PLAIN, c.darkened(0.15), 0.3)
	mm.chamfer_box(Vector3(-x - 0.02, h - 0.08, -z - 0.02), Vector3(x + 0.02, h, z + 0.04), 0.02)
	mm.set_mat(M.L_PLAIN, TYRE, 0.3)
	for sx in [-1.0, 1.0]:
		mm.tube(Vector3(sx * x * 0.7 - 0.03, 0.08, -z + 0.05), Vector3(sx * x * 0.7 + 0.03, 0.08, -z + 0.05), 0.08, 0.08, 8)
	if medical:
		mm.set_mat(M.L_PLAIN, Color(0.1, 0.1, 0.1))
		mm.box(Vector3(-0.1, h * 0.5, z + 0.002), Vector3(0.1, h * 0.5 + 0.2, z + 0.006))
		mm.set_mat(M.L_PLAIN, Color(0.85, 0.2, 0.15))
		mm.box(Vector3(-x * 0.9, h - 0.25, z + 0.002), Vector3(x * 0.9, h - 0.18, z + 0.006))
	_snow(mm, Vector3(-x + 0.03, h, -z + 0.03), Vector3(x - 0.03, h + 0.05, z - 0.03))


static func _toolbox(mm: PropMesh, w: float, d: float, h: float) -> void:
	var x := w * 0.5
	var z := d * 0.5
	mm.set_mat(M.L_METAL, Color(0.66, 0.16, 0.12), 0.35)
	mm.chamfer_box(Vector3(-x, 0, -z), Vector3(x, h * 0.75, z), 0.02)
	mm.set_mat(M.L_METAL, Color(0.6, 0.14, 0.1), 0.3)
	_extrude_x(mm, PackedVector2Array([Vector2(-z, h * 0.75), Vector2(z, h * 0.75), Vector2(z * 0.6, h * 0.92), Vector2(-z * 0.6, h * 0.92)]), -x, x)
	mm.set_mat(M.L_METAL, DARK, 0.2)
	mm.box(Vector3(-x * 0.5, h * 0.92, -0.015), Vector3(x * 0.5, h, 0.015))
	mm.set_mat(M.L_METAL, STEEL, 0.2)
	for sx in [-1.0, 1.0]:
		mm.box(Vector3(sx * x * 0.6 - 0.03, h * 0.55, z), Vector3(sx * x * 0.6 + 0.03, h * 0.68, z + 0.01))


# --- piles and clutter ----------------------------------------------------------------------

static func _pallets(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	var n := clampi(int(h / 0.15), 1, 8)
	for i in n:
		var y := 0.15 * i
		var off := Vector3(rng.randf_range(-0.04, 0.04), 0, rng.randf_range(-0.04, 0.04))
		mm.set_mat(M.L_ROUGH_WOOD, WOOD[rng.randi() % WOOD.size()].darkened(rng.randf_range(0.1, 0.3)), 0.5)
		for bx in [-x + 0.05, 0.0, x - 0.05]:
			mm.box(off + Vector3(bx - 0.05, y, -z), off + Vector3(bx + 0.05, y + 0.1, z))
		var pz := -z + 0.06
		while pz < z:
			mm.box(off + Vector3(-x, y + 0.1, pz - 0.05), off + Vector3(x, y + 0.14, pz + 0.05))
			pz += 0.2
	_snow(mm, Vector3(-x + 0.05, 0.15 * n, -z + 0.05), Vector3(x - 0.05, 0.15 * n + 0.06, z - 0.05))


static func _barrels(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var r := minf(0.3, minf(w, d) * 0.25)
	var spots := [Vector3(-w * 0.25, 0, -d * 0.2), Vector3(w * 0.22, 0, -d * 0.22), Vector3(-w * 0.05, 0, d * 0.22)]
	var cols := [Color(0.2, 0.32, 0.5), Color(0.5, 0.15, 0.12), Color(0.35, 0.36, 0.3), Color(0.62, 0.5, 0.15)]
	for p in spots:
		var c: Color = cols[rng.randi() % cols.size()]
		mm.set_mat(M.L_RUST if rng.randf() < 0.4 else M.L_METAL, c, 0.55)
		mm.cylinder(p, r, r, h, 10)
		mm.set_mat(M.L_METAL, c.darkened(0.3), 0.5)
		mm.cylinder(p + Vector3(0, h * 0.33, 0), r + 0.01, r + 0.01, 0.03, 10, false)
		mm.cylinder(p + Vector3(0, h * 0.66, 0), r + 0.01, r + 0.01, 0.03, 10, false)
		mm.set_mat(M.L_PLAIN, SNOW)
		mm.cylinder(p + Vector3(0, h, 0), r * 0.92, r * 0.8, 0.05, 10)
	# one on its side
	mm.set_mat(M.L_RUST, RUST, 0.6)
	mm.tube(Vector3(w * 0.5 - r, r, d * 0.1), Vector3(w * 0.5 - r, r, d * 0.5 - 0.02), r, r, 10)


static func _scrap(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	mm.set_mat(M.L_SOIL, Color(0.3, 0.27, 0.24), 0.5)
	_mound(mm, Vector3.ZERO, x * 0.85, z * 0.8, h * 0.35)
	for i in 14:
		var p := Vector3(rng.randf_range(-x * 0.6, x * 0.6), rng.randf_range(0.25, h * 0.6), rng.randf_range(-z * 0.5, z * 0.5))
		var size := Vector3(rng.randf_range(0.2, 0.7), rng.randf_range(0.04, 0.2), rng.randf_range(0.1, 0.4))
		mm.set_mat(M.L_RUST if rng.randf() < 0.7 else M.L_METAL, RUST.lerp(STEEL, rng.randf() * 0.5).darkened(rng.randf() * 0.3), 0.6)
		mm.obox(Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.35, 0.35), rng.randf() * TAU, rng.randf_range(-0.35, 0.35))), p), size)
	for i in 3:
		var p := Vector3(rng.randf_range(-x * 0.8, x * 0.8), 0.0, rng.randf_range(-z * 0.7, z * 0.7))
		mm.set_mat(M.L_PLAIN, TYRE, 0.4)
		mm.cylinder(p + Vector3(0, 0.12 * i, 0), 0.32, 0.32, 0.2, 10)
	mm.set_mat(M.L_METAL, STEEL.darkened(0.4), 0.6)
	mm.tube(Vector3(-x * 0.6, 0.2, -z * 0.2), Vector3(x * 0.4, h, z * 0.1), 0.04, 0.04, 6)
	mm.set_mat(M.L_PLAIN, SNOW)
	mm.blob(Vector3(0, h * 0.35, 0), Vector3(x * 0.55, h * 0.12, z * 0.5), 2, 7)


static func _trolleys(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.45
	var z := d * 0.5
	var n := 2 if rng.randf() < 0.6 else 1
	for k in n:
		var zo := -z + 0.45 + 0.28 * k
		_trolley_at(mm, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.05, 0.05)), Vector3(0, 0, zo)), x * 0.92, h)


static func _trolley_at(mm: PropMesh, t: Transform3D, x: float, h: float) -> void:
	var keep := mm.xf
	mm.xf = keep * t
	mm.set_mat(M.L_METAL, Color(0.7, 0.71, 0.72), 0.45)
	var base := 0.35
	var top := h - 0.1
	for y in [base, (base + top) * 0.5, top]:
		mm.box(Vector3(-x, y, -0.4), Vector3(x, y + 0.02, -0.38))
		mm.box(Vector3(-x, y, 0.38), Vector3(x, y + 0.02, 0.4))
		mm.box(Vector3(-x, y, -0.4), Vector3(-x + 0.02, y + 0.02, 0.4))
		mm.box(Vector3(x - 0.02, y, -0.4), Vector3(x, y + 0.02, 0.4))
	for px in [-x, -x * 0.33, x * 0.33, x - 0.02]:
		mm.box(Vector3(px, base, 0.38), Vector3(px + 0.02, top, 0.4))
	for pz in [-0.4, 0.0, 0.38]:
		mm.box(Vector3(-x, base, pz), Vector3(-x + 0.02, top, pz + 0.02))
		mm.box(Vector3(x - 0.02, base, pz), Vector3(x, top, pz + 0.02))
	mm.set_mat(M.L_PLAIN, Color(0.6, 0.16, 0.12), 0.3)
	mm.box(Vector3(-x, top + 0.05, -0.5), Vector3(x, top + 0.09, -0.46))
	mm.set_mat(M.L_METAL, STEEL, 0.4)
	for px in [-x + 0.03, x - 0.05]:
		mm.box(Vector3(px, 0.08, -0.4), Vector3(px + 0.02, base, -0.38))
		mm.box(Vector3(px, 0.08, 0.38), Vector3(px + 0.02, base, 0.4))
	mm.set_mat(M.L_PLAIN, TYRE, 0.3)
	for px in [-x + 0.04, x - 0.04]:
		for pz in [-0.39, 0.39]:
			mm.cylinder(Vector3(px, 0, pz), 0.05, 0.05, 0.08, 6)
	mm.xf = keep


## A low rounded heap on the ground (rx across x, rz across z, height ht):
## the upper half of a squashed sphere.
static func _mound(mm: PropMesh, c: Vector3, rx: float, rz: float, ht: float, rings := 3, seg := 10) -> void:
	var radii := Vector3(rx, ht, rz)
	for j in rings:
		var t0 := PI * 0.5 * j / rings
		var t1 := PI * 0.5 * (j + 1) / rings
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			var p00 := c + Vector3(cos(t0) * cos(a0), sin(t0), cos(t0) * sin(a0)) * radii
			var p01 := c + Vector3(cos(t0) * cos(a1), sin(t0), cos(t0) * sin(a1)) * radii
			var p10 := c + Vector3(cos(t1) * cos(a0), sin(t1), cos(t1) * sin(a0)) * radii
			var p11 := c + Vector3(cos(t1) * cos(a1), sin(t1), cos(t1) * sin(a1)) * radii
			var n := (((p00 + p01 + p10 + p11) * 0.25 - c) / (radii * radii)).normalized()
			if j == rings - 1:
				mm.tri(p00, p01, p10, n)
			else:
				mm.quad(p00, p01, p11, p10, n)


static func _snowbank(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var n := 3
	for i in n:
		var c := Vector3(lerpf(-w * 0.27, w * 0.27, float(i) / float(n - 1)), 0, 0)
		mm.set_mat(M.L_PLAIN, SNOW.lerp(SNOW_SHADE, rng.randf() * 0.5))
		_mound(mm, c, w * 0.23, d * rng.randf_range(0.4, 0.5), h * rng.randf_range(0.6, 1.0))


# --- signs, furniture, lights ------------------------------------------------------------------

static func _sign(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator, kind: String) -> void:
	var x := w * 0.5
	var board_h := clampf(h * 0.32, 0.35, 0.9)
	var y0 := h - board_h
	mm.set_mat(M.L_METAL, Color(0.32, 0.33, 0.34), 0.45)
	if kind == "dir":
		mm.box(Vector3(-0.035, 0, -0.035), Vector3(0.035, h, 0.035))
	else:
		for sx in [-1.0, 1.0]:
			mm.box(Vector3(sx * (x - 0.15) - 0.04, 0, -0.04), Vector3(sx * (x - 0.15) + 0.04, h - 0.05, 0.04))
	var face := {"shop": Color(0.2, 0.22, 0.25), "medical": Color(0.88, 0.88, 0.86), "police": Color(0.14, 0.22, 0.42), "dir": Color(0.14, 0.38, 0.27)}[kind] as Color
	mm.set_mat(M.L_PLAIN, face, 0.4)
	mm.box(Vector3(-x, y0, -0.05), Vector3(x, h, 0.05))
	var z1 := 0.052
	match kind:
		"shop":
			# a row of pale block letters, some fallen off
			mm.set_mat(M.L_PLAIN, Color(0.86, 0.8, 0.62), 0.3)
			var lx := -x + 0.2
			while lx < x - 0.25:
				if rng.randf() > 0.15:
					mm.box(Vector3(lx, y0 + board_h * 0.28, z1), Vector3(lx + 0.14, y0 + board_h * 0.72, z1 + 0.02))
				lx += 0.2
			mm.set_mat(M.L_PLAIN, Color(0.62, 0.2, 0.15), 0.3)
			mm.box(Vector3(-x, y0, z1), Vector3(x, y0 + 0.05, z1 + 0.01))
		"medical":
			var cy := y0 + board_h * 0.5
			var s := board_h * 0.32
			mm.set_mat(M.L_PLAIN, Color(0.78, 0.14, 0.12), 0.2)
			mm.box(Vector3(-x + 0.15, cy - s * 0.33, z1), Vector3(-x + 0.15 + s * 2.0, cy + s * 0.33, z1 + 0.01))
			mm.box(Vector3(-x + 0.15 + s * 0.67, cy - s, z1), Vector3(-x + 0.15 + s * 1.33, cy + s, z1 + 0.01))
			mm.set_mat(M.L_PLAIN, Color(0.25, 0.25, 0.27), 0.2)
			mm.box(Vector3(-x + 0.3 + s * 2.0, cy - 0.04, z1), Vector3(x - 0.12, cy + 0.04, z1 + 0.01))
		"police":
			mm.set_mat(M.L_PLAIN, Color(0.9, 0.9, 0.88), 0.25)
			mm.box(Vector3(-x, y0 + board_h * 0.4, z1), Vector3(x, y0 + board_h * 0.6, z1 + 0.01))
			mm.set_mat(M.L_PLAIN, Color(0.85, 0.72, 0.25), 0.25)
			mm.box(Vector3(-0.08, y0 + board_h * 0.72, z1), Vector3(0.08, y0 + board_h * 0.9, z1 + 0.01))
		"dir":
			mm.set_mat(M.L_PLAIN, Color(0.92, 0.92, 0.9), 0.2)
			var cy := y0 + board_h * 0.5
			mm.box(Vector3(-x + 0.12, cy - 0.04, z1), Vector3(x - 0.3, cy + 0.04, z1 + 0.01))
			mm.poly(PackedVector3Array([Vector3(x - 0.32, cy - 0.12, z1 + 0.01), Vector3(x - 0.1, cy, z1 + 0.01), Vector3(x - 0.32, cy + 0.12, z1 + 0.01)]), Vector3.BACK)
	_snow(mm, Vector3(-x, h, -0.06), Vector3(x, h + 0.05, 0.06))


static func _bike_rack(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	mm.set_mat(M.L_METAL, STEEL, 0.4)
	var n := maxi(2, int(w / 0.55))
	for i in n:
		var px := -x + 0.25 + (w - 0.5) * float(i) / float(n - 1)
		mm.polyline([Vector3(px, 0, -0.25), Vector3(px, h * 0.8, -0.25), Vector3(px, h, -0.1), Vector3(px, h, 0.1), Vector3(px, h * 0.8, 0.25), Vector3(px, 0, 0.25)], 0.025)
	# a bike or two left locked, one wheel gone
	var bikes := 1 + rng.randi() % 2
	for b in bikes:
		var px := -x + 0.4 + 0.6 * b
		var col := [Color(0.5, 0.15, 0.12), Color(0.15, 0.3, 0.45), Color(0.2, 0.2, 0.2)][rng.randi() % 3] as Color
		mm.set_mat(M.L_PLAIN, TYRE, 0.3)
		mm.tube(Vector3(px + 0.1, 0.33, -0.45), Vector3(px + 0.13, 0.33, -0.45), 0.33, 0.33, 12)
		if b == 0:
			mm.tube(Vector3(px + 0.1, 0.33, 0.55), Vector3(px + 0.13, 0.33, 0.55), 0.33, 0.33, 12)
		mm.set_mat(M.L_METAL, col, 0.35)
		mm.polyline([Vector3(px + 0.115, 0.33, -0.45), Vector3(px + 0.115, 0.6, 0.1), Vector3(px + 0.115, 0.33, 0.55)], 0.02)
		mm.polyline([Vector3(px + 0.115, 0.6, 0.1), Vector3(px + 0.115, 0.85, 0.38), Vector3(px + 0.115, 0.33, 0.55)], 0.02)
		mm.set_mat(M.L_PLAIN, DARK)
		mm.box(Vector3(px + 0.07, 0.7, -0.12), Vector3(px + 0.16, 0.75, 0.08))
	_snow(mm, Vector3(-x, 0, -0.35), Vector3(x, 0.06, 0.35))


static func _bench(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	mm.set_mat(M.L_METAL, DARK, 0.4)
	for sx in [-1.0, 1.0]:
		mm.box(Vector3(sx * (x - 0.12) - 0.03, 0, -z + 0.05), Vector3(sx * (x - 0.12) + 0.03, h * 0.5, z - 0.05))
		mm.box(Vector3(sx * (x - 0.12) - 0.03, h * 0.5, -z + 0.02), Vector3(sx * (x - 0.12) + 0.03, h, -z + 0.08))
	var c: Color = WOOD[rng.randi() % WOOD.size()].darkened(0.25)
	mm.set_mat(M.L_ROUGH_WOOD, c, 0.5)
	for i in 3:
		var pz := -z + 0.12 + i * (d - 0.2) / 3.0
		mm.box(Vector3(-x, h * 0.47, pz), Vector3(x, h * 0.5 + 0.02, pz + 0.1))
	for y in [h * 0.68, h * 0.88]:
		mm.box(Vector3(-x, y, -z + 0.02), Vector3(x, y + 0.08, -z + 0.06))
	_snow(mm, Vector3(-x + 0.02, h * 0.52, -z + 0.12), Vector3(x - 0.02, h * 0.52 + 0.06, z - 0.06))


static func _lamp_post(mm: PropMesh, w: float, d: float, h: float) -> void:
	mm.set_mat(M.L_METAL, Color(0.25, 0.27, 0.28), 0.45)
	mm.cylinder(Vector3.ZERO, 0.09, 0.06, h, 8)
	mm.box(Vector3(-0.03, h - 0.08, -0.03), Vector3(0.03, h - 0.02, 0.7))
	mm.box(Vector3(-0.12, h - 0.14, 0.55), Vector3(0.12, h - 0.02, 0.85))
	mm.set_mat(M.L_PLAIN, Color(0.75, 0.73, 0.62), 0.1)
	mm.box(Vector3(-0.1, h - 0.16, 0.57), Vector3(0.1, h - 0.14, 0.83))
	_snow(mm, Vector3(-0.12, h - 0.02, 0.55), Vector3(0.12, h + 0.02, 0.85))


# --- small buildings --------------------------------------------------------------------------

static func _shed(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	var c: Color = [Color(0.45, 0.2, 0.15), Color(0.32, 0.36, 0.3), Color(0.55, 0.47, 0.36)][rng.randi() % 3]
	var wall := h * 0.72
	mm.set_mat(M.L_ROUGH_WOOD, c, 0.5)
	mm.grain_v = true
	mm.box(Vector3(-x, 0, -z), Vector3(x, wall, z))
	mm.grain_v = false
	mm.extrude(PackedVector2Array([Vector2(-x, wall), Vector2(x, wall), Vector2(0, h)]), -z, z)
	mm.set_mat(M.L_ROUGH_WOOD, c.darkened(0.3), 0.5)
	mm.box(Vector3(-0.42, 0.02, z), Vector3(0.42, wall - 0.12, z + 0.03))
	mm.set_mat(M.L_METAL, STEEL, 0.3)
	mm.box(Vector3(0.28, wall * 0.5, z + 0.03), Vector3(0.34, wall * 0.5 + 0.12, z + 0.06))
	# the roof: felt with snow on both slopes
	var slope := atan2(h - wall, x)
	var run := sqrt(x * x + (h - wall) * (h - wall)) + 0.12
	for sx in [-1.0, 1.0]:
		var t := Transform3D(Basis(Vector3.BACK, -sx * slope), Vector3(sx * x * 0.5, (wall + h) * 0.5 + 0.04, 0))
		mm.set_mat(M.L_PLAIN, Color(0.2, 0.2, 0.21), 0.4)
		mm.obox(t, Vector3(run, 0.05, d + 0.25))
		mm.set_mat(M.L_PLAIN, SNOW)
		mm.obox(t * Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 0)), Vector3(run - 0.04, 0.06, d + 0.2))


static func _garage(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	mm.set_mat(M.L_CONCRETE, Color(0.62, 0.6, 0.56), 0.4)
	mm.box(Vector3(-x, 0, -z), Vector3(x, h - 0.2, z))
	mm.set_mat(M.L_PLAIN, Color(0.25, 0.25, 0.26), 0.4)
	mm.box(Vector3(-x - 0.12, h - 0.2, -z - 0.12), Vector3(x + 0.12, h, z + 0.12))
	_snow(mm, Vector3(-x - 0.1, h, -z - 0.1), Vector3(x + 0.1, h + 0.12, z + 0.1))
	# the roller door, a little open at the bottom
	var dx := x - 0.3
	var y := 0.25
	var k := 0
	while y < h - 0.55:
		mm.set_mat(M.L_METAL, Color(0.5, 0.52, 0.54).darkened(0.08 if k % 2 == 0 else 0.0), 0.45)
		mm.box(Vector3(-dx, y, z), Vector3(dx, minf(y + 0.14, h - 0.55), z + 0.04))
		y += 0.14
		k += 1
	mm.set_mat(M.L_PLAIN, Color(0.03, 0.03, 0.03))
	mm.box(Vector3(-dx, 0.0, z - 0.02), Vector3(dx, 0.25, z + 0.005))
	mm.set_mat(M.L_RUST, RUST, 0.5)
	mm.box(Vector3(-x - 0.004, 0, -z + rng.randf_range(0.5, 2.0)), Vector3(-x, 0.4, -z + rng.randf_range(2.5, 4.0)))


static func _portaloo(mm: PropMesh, w: float, d: float, h: float) -> void:
	var x := w * 0.5
	var z := d * 0.5
	mm.set_mat(M.L_PLAIN, Color(0.2, 0.36, 0.56), 0.4)
	mm.chamfer_box(Vector3(-x, 0, -z), Vector3(x, h - 0.12, z), 0.04)
	mm.set_mat(M.L_PLAIN, Color(0.85, 0.86, 0.85), 0.3)
	mm.chamfer_box(Vector3(-x - 0.02, h - 0.12, -z - 0.02), Vector3(x + 0.02, h, z + 0.02), 0.05)
	mm.set_mat(M.L_PLAIN, Color(0.16, 0.3, 0.48), 0.4)
	mm.box(Vector3(-x + 0.12, 0.1, z), Vector3(x - 0.12, h - 0.25, z + 0.03))
	_snow(mm, Vector3(-x, h, -z), Vector3(x, h + 0.05, z))


# --- machines -----------------------------------------------------------------------------

static func _machine(mm: PropMesh, w: float, d: float, h: float, rng: RandomNumberGenerator) -> void:
	var x := w * 0.5
	var z := d * 0.5
	var c: Color = [Color(0.78, 0.6, 0.12), Color(0.3, 0.42, 0.3), Color(0.62, 0.62, 0.6)][rng.randi() % 3]
	mm.set_mat(M.L_METAL, DARK, 0.4)
	for sx in [-1.0, 1.0]:
		mm.box(Vector3(sx * x * 0.8 - 0.05, 0, -z), Vector3(sx * x * 0.8 + 0.05, 0.1, z))
	mm.set_mat(M.L_METAL, c, 0.5)
	mm.chamfer_box(Vector3(-x, 0.1, -z + 0.05), Vector3(x, h - 0.06, z - 0.05), 0.04)
	mm.set_mat(M.L_METAL, DARK, 0.3)
	var gz := -z + 0.25
	while gz < z * 0.2:
		for sx in [-1.0, 1.0]:
			mm.box(Vector3(sx * x - 0.005, h * 0.35, gz), Vector3(sx * x + 0.005, h * 0.8, gz + 0.04))
		gz += 0.08
	mm.cylinder(Vector3(x * 0.4, h - 0.06, z * 0.5), 0.05, 0.05, 0.15, 6)
	mm.set_mat(M.L_PLAIN, Color(0.1, 0.1, 0.1))
	mm.box(Vector3(-x * 0.5, h * 0.5, z - 0.05), Vector3(x * 0.2, h * 0.75, z - 0.04))
	_snow(mm, Vector3(-x + 0.04, h - 0.06, -z + 0.08), Vector3(x - 0.04, h, z - 0.08))


static func _forklift(mm: PropMesh, w: float, d: float, h: float) -> void:
	var x := w * 0.5
	var z := d * 0.5
	var yel := Color(0.8, 0.6, 0.12)
	mm.set_mat(M.L_METAL, yel, 0.5)
	mm.chamfer_box(Vector3(-x, 0.2, -z), Vector3(x, 1.0, z - 0.7), 0.05)            # body and counterweight
	mm.set_mat(M.L_METAL, DARK, 0.4)
	mm.box(Vector3(-x, 0.2, -z - 0.05), Vector3(x, 0.9, -z + 0.25))
	mm.box(Vector3(-x * 0.7, 1.0, -z + 0.4), Vector3(x * 0.7, 1.15, -z + 0.8))      # the seat
	# the overhead guard on four posts
	for sx in [-1.0, 1.0]:
		for pz in [-z + 0.25, z - 0.85]:
			mm.box(Vector3(sx * (x - 0.06) - 0.03, 1.0, pz), Vector3(sx * (x - 0.06) + 0.03, h - 0.05, pz + 0.05))
	mm.box(Vector3(-x, h - 0.05, -z + 0.25), Vector3(x, h, z - 0.8))
	_snow(mm, Vector3(-x + 0.02, h, -z + 0.27), Vector3(x - 0.02, h + 0.06, z - 0.82))
	# the mast and the forks, lowered
	for sx in [-1.0, 1.0]:
		mm.box(Vector3(sx * x * 0.6 - 0.05, 0.1, z - 0.7), Vector3(sx * x * 0.6 + 0.05, h - 0.1, z - 0.6))
		mm.set_mat(M.L_METAL, STEEL.darkened(0.2), 0.4)
		mm.box(Vector3(sx * x * 0.4 - 0.05, 0.05, z - 0.6), Vector3(sx * x * 0.4 + 0.05, 0.1, z))
		mm.set_mat(M.L_METAL, DARK, 0.4)
	for sz in [-z + 0.4, z - 1.0]:
		for sx in [-1.0, 1.0]:
			_wheel(mm, Vector3(sx * (x - 0.08), 0.24, sz), 0.24, 0.18, sx, DARK)
