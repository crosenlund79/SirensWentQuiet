extends RefCounted
## Survival pieces for PropKit: door, barricade, crate, rain_collector,
## candle, lantern and the wall_ghost preview block. New for Experiment 002.
## Experiment 003: style "iron" for doors (a reinforced door: riveted plate,
## straps, steel frame) and barricades (steel posts and flat bars).
## The builders other than `door` use the PropKit builder frame (front toward
## +z, turned to -Z by PropKit). `door` is built directly in the canonical
## frame because its "Leaf" is a separate node: the leaf's origin is the
## hinge and it extends along +X.

const M := preload("res://src/props/prop_materials.gd")

## Plank colours: raw pine, weathered grey, old brown, fence white, faded teal.
const PLANKS := [Color(0.76, 0.62, 0.43), Color(0.62, 0.59, 0.54), Color(0.55, 0.42, 0.3),
		Color(0.82, 0.8, 0.74), Color(0.45, 0.55, 0.53), Color(0.7, 0.54, 0.36)]
const DOOR_PAINT := [Color(0.84, 0.82, 0.76), Color(0.5, 0.56, 0.5), Color(0.36, 0.43, 0.5), Color(0.5, 0.25, 0.21)]
const TRIM := Color(0.85, 0.83, 0.78)
const NAIL := Color(0.2, 0.2, 0.21)

const JAMB := 0.045
const LEAF_T := 0.04


static func build(mm: PropMesh, type: String, w: float, h: float, d: float, rng: RandomNumberGenerator, damage: float, style: String) -> bool:
	match type:
		"barricade":
			if style == "iron":
				_iron_barricade(mm, w, h, d, rng, damage)
			else:
				_barricade(mm, w, h, d, rng, damage)
		"crate":
			_crate(mm, w, h, d, rng, damage)
		"rain_collector":
			_rain_collector(mm, w, h, d, rng, damage)
		"candle":
			_candle(mm, w, h, d, rng)
		"lantern":
			_lantern(mm, w, h, d, rng)
		"wall_ghost":
			mm.set_mat(M.L_PLAIN, Color(0.8, 0.8, 0.78))
			mm.chamfer_box(Vector3(-w * 0.5, 0, -d * 0.5), Vector3(w * 0.5, h, d * 0.5), minf(0.025, d * 0.2), false)
		_:
			return false
	return true


# --- door ------------------------------------------------------------------------------------------

## {"body": frame mesh, "leaf": leaf mesh (hinge at its origin, extends along
## +X, closed), "hinge": leaf position in the door's frame}. The frame fits
## the w x h opening and is d + 0.03 deep (a 15 mm lip on each wall face).
static func door(w: float, h: float, d: float, rng: RandomNumberGenerator, damage: float, style: String) -> Dictionary:
	var iron := style == "iron"
	var plank := style == "plank" or iron
	var fr := PropMesh.new()
	var fd := d + 0.03
	var x := w * 0.5
	# jambs and head (trim colour; grubby where hands push; steel angle for iron)
	if iron:
		fr.set_mat(M.L_METAL, Color(0.27, 0.28, 0.29), 0.3)
	else:
		fr.set_mat(M.L_PLAIN if not plank else M.L_ROUGH_WOOD, TRIM if not plank else PLANKS[2], 0.08)
	fr.grain_v = true
	fr.chamfer_box(Vector3(-x, 0, -fd * 0.5), Vector3(-x + JAMB, h, fd * 0.5), 0.006, false)
	fr.chamfer_box(Vector3(x - JAMB, 0, -fd * 0.5), Vector3(x, h, fd * 0.5), 0.006, false)
	fr.grain_v = false
	fr.chamfer_box(Vector3(-x, h - JAMB, -fd * 0.5), Vector3(x, h, fd * 0.5), 0.006, false)
	# stops behind the closed leaf
	fr.set_mat(M.L_PLAIN if not plank else M.L_ROUGH_WOOD, (TRIM if not plank else PLANKS[2]).darkened(0.08), 0.1)
	var sz0 := LEAF_T * 0.5 + 0.001
	fr.box(Vector3(-x + JAMB, 0.0, sz0), Vector3(-x + JAMB + 0.014, h - JAMB, sz0 + 0.03))
	fr.box(Vector3(x - JAMB - 0.014, 0.0, sz0), Vector3(x - JAMB, h - JAMB, sz0 + 0.03))
	fr.box(Vector3(-x + JAMB, h - JAMB - 0.014, sz0), Vector3(x - JAMB, h - JAMB, sz0 + 0.03))
	# threshold
	fr.set_mat(M.L_WOOD, Color(0.55, 0.43, 0.3), 0.3)
	fr.box(Vector3(-x + JAMB, 0.0, -fd * 0.5), Vector3(x - JAMB, 0.012, fd * 0.5))
	# hinge knuckles and the strike plate
	fr.set_mat(M.L_METAL, Color(0.42, 0.4, 0.36), 0.2)
	for f in [0.12, 0.5, 0.88]:
		fr.cylinder(Vector3(-x + JAMB + 0.004, h * f - 0.05, -LEAF_T * 0.5 - 0.004), 0.007, 0.007, 0.1, 6)
	fr.box(Vector3(x - JAMB - 0.002, 0.98, -0.012), Vector3(x - JAMB, 1.06, 0.012))
	if damage > 0.4:
		# a splintered jamb at the latch
		fr.set_mat(M.L_ROUGH_WOOD, Color(0.8, 0.66, 0.46), 0.2)
		for i in 3:
			fr.obox(Transform3D(Basis(Vector3.BACK, rng.randf_range(-0.5, 0.5)), Vector3(x - JAMB * 0.6, 0.95 + i * 0.05, -fd * 0.5 - 0.004)), Vector3(0.012, 0.07, 0.006))
	var lw := w - JAMB * 2.0 - 0.006
	var top := h - JAMB - 0.004
	var lf := PropMesh.new()
	if damage >= 0.95:
		# the top hinge gave: the leaf sags a little
		lf.xf = Transform3D(Basis(Vector3.BACK, -0.025), Vector3.ZERO)
	if iron:
		_iron_leaf(lf, lw, top, rng, damage)
	elif plank:
		_plank_leaf(lf, lw, top, rng, damage)
	else:
		_panel_leaf(lf, lw, top, rng, damage)
	return {"body": fr.commit(), "leaf": lf.commit(), "hinge": Vector3(-x + JAMB + 0.003, 0.0, 0.0)}


## A painted four-panel door. Leaf frame: x 0..lw from the hinge, y up, front -z.
static func _panel_leaf(mm: PropMesh, lw: float, top: float, rng: RandomNumberGenerator, damage: float) -> void:
	var paint: Color = DOOR_PAINT[rng.randi() % DOOR_PAINT.size()]
	var t := LEAF_T * 0.5
	var y0 := 0.008
	var st := minf(0.11, lw * 0.14)
	var mid_y := y0 + (top - y0) * 0.47
	mm.set_mat(M.L_PLAIN, paint, 0.06)
	mm.grain_v = true
	mm.chamfer_box(Vector3(0, y0, -t), Vector3(st, top, t), 0.005, false)
	mm.chamfer_box(Vector3(lw - st, y0, -t), Vector3(lw, top, t), 0.005, false)
	mm.chamfer_box(Vector3(lw * 0.5 - 0.035, y0 + 0.2, -t), Vector3(lw * 0.5 + 0.035, top - 0.11, t), 0.004, false)
	mm.grain_v = false
	mm.chamfer_box(Vector3(st, y0, -t), Vector3(lw - st, y0 + 0.2, t), 0.005, false)
	mm.chamfer_box(Vector3(st, mid_y - 0.07, -t), Vector3(lw - st, mid_y + 0.07, t), 0.005, false)
	mm.chamfer_box(Vector3(st, top - 0.11, -t), Vector3(lw - st, top, t), 0.005, false)
	# four recessed panels; damage cracks and then knocks them out
	var cells := [[st, lw * 0.5 - 0.035, y0 + 0.2, mid_y - 0.07], [lw * 0.5 + 0.035, lw - st, y0 + 0.2, mid_y - 0.07],
			[st, lw * 0.5 - 0.035, mid_y + 0.07, top - 0.11], [lw * 0.5 + 0.035, lw - st, mid_y + 0.07, top - 0.11]]
	var order := [0, 1, 2, 3]
	_shuffle(order, rng)
	for i in 4:
		var c: Array = cells[i]
		var rank := order.find(i)
		var broken := damage >= 0.5 + rank * 0.15
		var cracked := damage >= 0.2 + rank * 0.1
		if broken:
			_shards(mm, c[0], c[1], c[2], c[3], -t * 0.35, t * 0.35, paint, rng)
			continue
		mm.set_mat(M.L_PLAIN, paint.darkened(0.04), 0.06)
		mm.box(Vector3(c[0], c[2], -t * 0.35), Vector3(c[1], c[3], t * 0.35))
		# raised field
		mm.set_mat(M.L_PLAIN, paint.lightened(0.03), 0.06)
		mm.box(Vector3(c[0] + 0.04, c[2] + 0.04, -t * 0.55), Vector3(c[1] - 0.04, c[3] - 0.04, t * 0.55))
		if cracked:
			_crack(mm, Vector2(c[0] + 0.03, c[2] + 0.03), Vector2(c[1] - 0.03, c[3] - 0.03), -t * 0.55 - 0.001, rng)
			_crack(mm, Vector2(c[0] + 0.03, c[2] + 0.03), Vector2(c[1] - 0.03, c[3] - 0.03), t * 0.55 + 0.001, rng)
	# grime around the handle, lever handles on both faces
	mm.set_mat(M.L_PLAIN, paint.darkened(0.25), 0.5)
	mm.box(Vector3(lw - 0.15, 0.85, -t - 0.0015), Vector3(lw - 0.012, 1.2, -t - 0.001))
	mm.box(Vector3(lw - 0.15, 0.85, t + 0.001), Vector3(lw - 0.012, 1.2, t + 0.0015))
	_lever(mm, lw, t)
	if damage >= 0.75:
		# a split down the latch stile
		mm.set_mat(M.L_SCREEN, Color(0.03, 0.03, 0.03))
		mm.box(Vector3(lw - st * 0.55, 0.6, -t - 0.002), Vector3(lw - st * 0.55 + 0.006, 1.5, t + 0.002))


static func _lever(mm: PropMesh, lw: float, t: float) -> void:
	mm.set_mat(M.L_METAL, Color(0.55, 0.53, 0.5), 0.15)
	for s in [-1.0, 1.0]:
		var z: float = s * (t + 0.003)
		mm.tube(Vector3(lw - 0.065, 1.0, 0.0), Vector3(lw - 0.065, 1.0, s * (t + 0.05)), 0.008, 0.008, 6)
		mm.tube(Vector3(lw - 0.065, 1.0, z), Vector3(lw - 0.065, 1.0, z + s * 0.006), 0.028, 0.028, 8)
		mm.box(Vector3(lw - 0.18, 0.99, s * (t + 0.045) - 0.008), Vector3(lw - 0.06, 1.01, s * (t + 0.045) + 0.008))


## A player-built plank door: boards, battens and a Z brace on the back, a
## scrap-metal patch on the front, a rope pull.
static func _plank_leaf(mm: PropMesh, lw: float, top: float, rng: RandomNumberGenerator, damage: float) -> void:
	var t := LEAF_T * 0.5
	var n := maxi(3, int(round(lw / 0.18)))
	var pw := lw / n
	var y0 := 0.01
	var pf := -t
	var pb := -t + 0.024
	var order := range(n)
	_shuffle(order, rng)
	mm.grain_v = true
	for i in n:
		var rank: int = order.find(i)
		var x0 := i * pw + 0.003
		var x1 := (i + 1) * pw - 0.003
		var col: Color = (PLANKS[rng.randi() % PLANKS.size()] as Color).darkened(rng.randf_range(0.0, 0.12))
		mm.set_mat(M.L_ROUGH_WOOD, col, rng.randf_range(0.08, 0.25))
		var ytop := top - rng.randf_range(0.0, 0.03)
		if damage >= 0.55 + rank * 0.15:
			# the lower part of this board is broken away
			var cut := rng.randf_range(0.5, 1.0)
			mm.box(Vector3(x0, cut + 0.04, pf), Vector3(x1, ytop, pb))
			mm.extrude(PackedVector2Array([Vector2(x0, cut + 0.04), Vector2(x1, cut + 0.04), Vector2(x1, cut - 0.03),
					Vector2(lerpf(x0, x1, 0.6), cut + 0.01), Vector2(lerpf(x0, x1, 0.35), cut - 0.06), Vector2(x0, cut)]), pf, pb)
			mm.box(Vector3(x0, y0, pf), Vector3(x1, y0 + 0.12, pb))
		else:
			mm.box(Vector3(x0, y0, pf), Vector3(x1, ytop, pb))
			if damage >= 0.2 + rank * 0.1:
				_crack(mm, Vector2(x0 + 0.01, 0.3), Vector2(x1 - 0.01, top - 0.3), pf - 0.001, rng)
	mm.grain_v = false
	# battens and the brace on the back
	mm.set_mat(M.L_ROUGH_WOOD, PLANKS[2], 0.15)
	var b0 := 0.3
	var b1 := top - 0.35
	mm.box(Vector3(0.03, b0 - 0.05, pb), Vector3(lw - 0.03, b0 + 0.05, t))
	mm.box(Vector3(0.03, b1 - 0.05, pb), Vector3(lw - 0.03, b1 + 0.05, t))
	var a := Vector2(0.08, b0 + 0.05)
	var b := Vector2(lw - 0.08, b1 - 0.05)
	var dir := (b - a)
	mm.obox(Transform3D(Basis(Vector3.BACK, atan2(dir.y, dir.x)), Vector3((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, (pb + t) * 0.5)), Vector3(dir.length(), 0.09, t - pb))
	# nail heads where battens cross boards
	mm.set_mat(M.L_METAL, NAIL)
	for i in n:
		for by in [b0, b1]:
			mm.box(Vector3(i * pw + pw * 0.5 - 0.006, by - 0.006, pf - 0.003), Vector3(i * pw + pw * 0.5 + 0.006, by + 0.006, pf))
	# a scrap-metal patch with screws, and a rope pull
	var px := rng.randf_range(0.05, lw * 0.35)
	var py := rng.randf_range(0.5, 1.1)
	var patch := Transform3D(Basis(Vector3.BACK, rng.randf_range(-0.08, 0.08)), Vector3(px + 0.16, py + 0.18, pf - 0.003))
	mm.set_mat(M.L_RUST, Color(0.52, 0.55, 0.56), 0.35)
	mm.obox(patch, Vector3(0.32, 0.36, 0.004))
	# a bent-over edge and screws
	mm.set_mat(M.L_METAL, Color(0.44, 0.46, 0.47), 0.4)
	mm.obox(patch * Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0, 0.18, -0.012)), Vector3(0.32, 0.04, 0.004))
	mm.set_mat(M.L_METAL, NAIL)
	for sx in [-0.13, 0.13]:
		for sy in [-0.15, 0.13]:
			mm.obox(patch * Transform3D(Basis.IDENTITY, Vector3(sx, sy, -0.004)), Vector3(0.014, 0.014, 0.006))
	mm.set_mat(M.L_PLAIN, Color(0.62, 0.55, 0.42))
	mm.polyline([Vector3(lw - 0.09, 1.08, pf - 0.002), Vector3(lw - 0.11, 1.0, pf - 0.04), Vector3(lw - 0.09, 0.92, pf - 0.002)], 0.008, 4)
	mm.set_mat(M.L_METAL, Color(0.4, 0.4, 0.4))
	mm.box(Vector3(lw - 0.2, 0.98, t), Vector3(lw - 0.03, 1.02, t + 0.025))


## A reinforced door: a board core faced with two riveted steel plates, three
## iron straps across, a heavy pull. Damage dents and scorches the plate,
## then peels a corner back to the boards.
static func _iron_leaf(mm: PropMesh, lw: float, top: float, rng: RandomNumberGenerator, damage: float) -> void:
	var t := LEAF_T * 0.5
	var y0 := 0.01
	# board core (seen from the back) with two battens
	mm.grain_v = true
	mm.set_mat(M.L_ROUGH_WOOD, PLANKS[2], 0.2)
	mm.box(Vector3(0, y0, -t + 0.002), Vector3(lw, top, t))
	mm.grain_v = false
	mm.set_mat(M.L_ROUGH_WOOD, PLANKS[0].darkened(0.2), 0.2)
	for by in [0.35, top - 0.4]:
		mm.box(Vector3(0.04, by - 0.05, t), Vector3(lw - 0.04, by + 0.05, t + 0.018))
	# front plates
	var z0 := -t - 0.008
	var z1 := -t + 0.002
	var mid := top * 0.52
	var plate := Color(0.4, 0.42, 0.43).darkened(rng.randf_range(0.0, 0.08))
	mm.set_mat(M.L_METAL, plate, 0.3 + damage * 0.35)
	var peel := damage >= 0.7
	mm.box(Vector3(0.012, y0 + 0.01, z0), Vector3(lw - 0.012, mid - 0.004, z1))
	if peel:
		mm.box(Vector3(0.012, mid + 0.004, z0), Vector3(lw * 0.55, top - 0.012, z1))
		mm.box(Vector3(lw * 0.55, mid + 0.004, z0), Vector3(lw - 0.012, top - 0.32, z1))
		# the torn corner bent forward, boards showing behind it
		mm.set_mat(M.L_METAL, plate.darkened(0.15), 0.6)
		mm.obox(Transform3D(Basis(Vector3.RIGHT, -0.55), Vector3(lw * 0.775, top - 0.17, z0 - 0.07)), Vector3(lw * 0.43, 0.3, 0.008))
	else:
		mm.box(Vector3(0.012, mid + 0.004, z0), Vector3(lw - 0.012, top - 0.012, z1))
	# straps and rivets
	var straps := [0.22, mid, top - 0.26]
	mm.set_mat(M.L_RUST, Color(0.27, 0.25, 0.23), 0.45)
	for y in straps:
		mm.box(Vector3(-0.004, y - 0.035, z0 - 0.006), Vector3(lw + 0.004, y + 0.035, z0))
	mm.set_mat(M.L_METAL, Color(0.55, 0.55, 0.52), 0.25)
	var n := maxi(3, int(lw / 0.13))
	for y in straps:
		for i in n:
			var rx := 0.05 + i * (lw - 0.1) / float(n - 1)
			mm.box(Vector3(rx - 0.01, y - 0.01, z0 - 0.012), Vector3(rx + 0.01, y + 0.01, z0 - 0.006))
	# dents and soot
	if damage >= 0.3:
		mm.set_mat(M.L_SCREEN, Color(0.08, 0.075, 0.07))
		for i in int(damage * 6.0):
			var dx := rng.randf_range(0.08, lw - 0.16)
			var dy := rng.randf_range(0.3, top - 0.4)
			mm.box(Vector3(dx, dy, z0 - 0.001), Vector3(dx + rng.randf_range(0.04, 0.1), dy + rng.randf_range(0.03, 0.08), z0))
	# a heavy D pull
	mm.set_mat(M.L_METAL, Color(0.2, 0.2, 0.21), 0.3)
	mm.polyline([Vector3(lw - 0.09, 1.12, z0 - 0.002), Vector3(lw - 0.09, 1.1, z0 - 0.05), Vector3(lw - 0.09, 0.94, z0 - 0.05), Vector3(lw - 0.09, 0.92, z0 - 0.002)], 0.011, 5)


## Jagged remains of a knocked-out panel: shards along the edges of the opening.
static func _shards(mm: PropMesh, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, paint: Color, rng: RandomNumberGenerator) -> void:
	mm.set_mat(M.L_PLAIN, paint.darkened(0.06), 0.3)
	for side in 4:
		var count := 2 + rng.randi() % 2
		for k in count:
			var f := (k + rng.randf_range(0.2, 0.8)) / count
			var base: Vector2
			var tan: Vector2
			var inward: Vector2
			match side:
				0:
					base = Vector2(lerpf(x0, x1, f), y0)
					tan = Vector2(1, 0)
					inward = Vector2(0, 1)
				1:
					base = Vector2(lerpf(x0, x1, f), y1)
					tan = Vector2(1, 0)
					inward = Vector2(0, -1)
				2:
					base = Vector2(x0, lerpf(y0, y1, f))
					tan = Vector2(0, 1)
					inward = Vector2(1, 0)
				_:
					base = Vector2(x1, lerpf(y0, y1, f))
					tan = Vector2(0, 1)
					inward = Vector2(-1, 0)
			var span := minf(x1 - x0, y1 - y0)
			var hw := rng.randf_range(0.03, 0.07)
			var reach := rng.randf_range(0.04, 0.12) * minf(1.0, span / 0.3)
			var pts := PackedVector2Array([base - tan * hw, base + tan * hw, base + inward * reach + tan * rng.randf_range(-0.02, 0.02)])
			mm.extrude(pts, z0, z1)
	# splinters on the floor below
	mm.set_mat(M.L_ROUGH_WOOD, Color(0.8, 0.68, 0.5), 0.2)
	for i in 3:
		mm.obox(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(lerpf(x0, x1, rng.randf()), 0.006, rng.randf_range(-0.12, 0.12))), Vector3(rng.randf_range(0.04, 0.1), 0.01, 0.02))


## A jagged dark crack drawn on a flat face at depth z, inside a rectangle.
static func _crack(mm: PropMesh, lo: Vector2, hi: Vector2, z: float, rng: RandomNumberGenerator) -> void:
	var keep := mm.color
	var keep_l := mm.layer
	mm.set_mat(M.L_SCREEN, Color(0.05, 0.045, 0.04))
	var p := Vector2(lerpf(lo.x, hi.x, rng.randf_range(0.2, 0.8)), lerpf(lo.y, hi.y, rng.randf_range(0.2, 0.8)))
	var a := rng.randf() * TAU
	var nz := -1.0 if z < 0.0 else 1.0
	for i in 6:
		a += rng.randf_range(-0.7, 0.7)
		var q := p + Vector2(cos(a), sin(a)) * rng.randf_range(0.04, 0.09)
		q = q.clamp(lo, hi)
		var n := Vector2(-(q - p).y, (q - p).x).normalized() * 0.003
		mm.quad(Vector3(p.x - n.x, p.y - n.y, z), Vector3(q.x - n.x, q.y - n.y, z), Vector3(q.x + n.x, q.y + n.y, z), Vector3(p.x + n.x, p.y + n.y, z), Vector3(0, 0, nz))
		p = q
	mm.set_mat(keep_l, keep)


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t


# --- barricade -------------------------------------------------------------------------------------

## Planks nailed across a span between two uprights, front toward +z (the
## attacker's side). Damage cracks planks (they sag at the break), then breaks
## them (stubs stay nailed on, a piece lies at the foot). Gaps between planks
## let bullets through.
static func _barricade(mm: PropMesh, w: float, h: float, d: float, rng: RandomNumberGenerator, damage: float) -> void:
	var post := minf(0.07, d * 0.45)
	var px := w * 0.5 - post * 0.5
	var t := 0.024
	var zf := post * 0.5            # front face of the uprights
	mm.grain_v = true
	mm.set_mat(M.L_ROUGH_WOOD, Color(0.58, 0.47, 0.34), 0.2)
	for sx in [-1.0, 1.0]:
		mm.box(Vector3(sx * px - post * 0.5, 0, -post * 0.5), Vector3(sx * px + post * 0.5, h - rng.randf_range(0.0, 0.04), post * 0.5))
	mm.grain_v = false
	# kicker blocks behind the uprights
	mm.set_mat(M.L_ROUGH_WOOD, PLANKS[2], 0.3)
	for sx in [-1.0, 1.0]:
		mm.box(Vector3(sx * px - post * 0.5, 0, -d * 0.5), Vector3(sx * px + post * 0.5, 0.1, -post * 0.5))
	var n := clampi(int(round(h / 0.27)), 3, 9)
	var order := range(n)
	_shuffle(order, rng)
	var pitch := h / n
	var fallen := 0
	for i in n:
		var rank: int = order.find(i)
		var ph := minf(rng.randf_range(0.12, 0.17), pitch - 0.035)
		var yc := pitch * (i + 0.5) + rng.randf_range(-0.02, 0.02)
		yc = clampf(yc, ph * 0.5 + 0.05, h - ph * 0.5 - 0.02)
		var max_tilt := minf(0.11, (minf(yc - ph * 0.5, h - yc - ph * 0.5) - 0.01) / (w * 0.5))
		var tilt := rng.randf_range(-max_tilt, max_tilt) if max_tilt > 0.0 else 0.0
		var col: Color = (PLANKS[rng.randi() % PLANKS.size()] as Color).darkened(rng.randf_range(0.0, 0.1))
		var plank_wear := rng.randf_range(0.05, 0.3)
		var length := w - 0.012
		var z := zf + t * 0.5 + (0.0 if i % 2 == 0 else 0.002)
		var crack_at := 0.08 + 0.55 * rank / n
		var break_at := 0.3 + 0.7 * rank / n
		var frame := Transform3D(Basis(Vector3.BACK, tilt), Vector3(0, yc, z))
		mm.set_mat(M.L_ROUGH_WOOD, col, plank_wear)
		if damage >= break_at:
			# stubs nailed to each upright, ragged ends; a piece at the foot
			var l0 := rng.randf_range(0.12, 0.24)
			var l1 := rng.randf_range(0.08, 0.2)
			_plank_piece(mm, frame, -length * 0.5, -length * 0.5 + l0, ph, t, rng, false, true)
			_plank_piece(mm, frame, length * 0.5 - l1, length * 0.5, ph, t, rng, true, false)
			if fallen < 2:
				fallen += 1
				mm.set_mat(M.L_ROUGH_WOOD, col.darkened(0.08), plank_wear + 0.15)
				var fl := minf(length - l0 - l1, w * 0.8)
				mm.obox(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.12, 0.12)) * Basis(Vector3.RIGHT, PI * 0.5),
						Vector3(rng.randf_range(-0.05, 0.05), t * 0.5 + (fallen - 1) * t, zf + t * 2.0 + ph * 0.5 + 0.02)), Vector3(fl, ph, t))
			_nails(mm, frame, length, ph, t, true, true, l0, l1)
		elif damage >= crack_at:
			# cracked: both halves still nailed, sagging at the break
			var s := rng.randf_range(-length * 0.2, length * 0.2)
			var sag := rng.randf_range(0.06, 0.12)
			var left := frame * Transform3D(Basis(Vector3.BACK, -sag), Vector3(-length * 0.5, 0, 0))
			var right := frame * Transform3D(Basis(Vector3.BACK, sag), Vector3(length * 0.5, 0, 0))
			_plank_piece(mm, left, 0.0, s + length * 0.5 - 0.005, ph, t, rng, false, true)
			_plank_piece(mm, right, -(length * 0.5 - s) + 0.005, 0.0, ph, t, rng, true, false)
			_nails(mm, frame, length, ph, t, true, true, length, length)
		else:
			mm.obox(frame, Vector3(length, ph, t))
			_nails(mm, frame, length, ph, t, true, true, length, length)
	# a diagonal brace over the planks on taller barricades
	if h > 1.2 and damage < 0.85:
		var bw := 0.1
		var dx := w - 0.12
		var dy := h - 0.6
		var ang := atan2(dy, dx)
		var blen := (w - 0.06 - bw * sin(ang)) / cos(ang)
		mm.set_mat(M.L_ROUGH_WOOD, PLANKS[1], 0.2)
		mm.obox(Transform3D(Basis(Vector3.BACK, ang), Vector3(0.0, h * 0.5, zf + t * 1.5 + 0.003)), Vector3(blen, bw, t))


## An iron barricade, front toward +z: two square steel posts on foot plates,
## flat bars bolted across with gaps (bullets pass), a diagonal brace. Damage
## bends bars out of line, then tears them off (one lies at the foot).
static func _iron_barricade(mm: PropMesh, w: float, h: float, d: float, rng: RandomNumberGenerator, damage: float) -> void:
	var post := minf(0.06, d * 0.4)
	var px := w * 0.5 - post * 0.5
	var zf := post * 0.5
	var steel := Color(0.33, 0.35, 0.36)
	mm.set_mat(M.L_METAL, steel, 0.35)
	for sx in [-1.0, 1.0]:
		mm.box(Vector3(sx * px - post * 0.5, 0, -post * 0.5), Vector3(sx * px + post * 0.5, h, post * 0.5))
		# foot plate and a gusset behind
		var fx: float = sx * (w * 0.5 - 0.07)
		mm.box(Vector3(fx - 0.07, 0, -d * 0.5), Vector3(fx + 0.07, 0.012, d * 0.5))
		mm.obox(Transform3D(Basis(Vector3.RIGHT, -0.6), Vector3(sx * px, 0.09, -post * 0.5 - 0.035)), Vector3(0.012, 0.13, 0.012))
	var n := clampi(int(round(h / 0.22)), 4, 9)
	var pitch := h / n
	var order := range(n)
	_shuffle(order, rng)
	var fallen := false
	for i in n:
		var rank: int = order.find(i)
		var yc := pitch * (i + 0.5)
		var bh := minf(0.075, pitch * 0.45)
		var bar := Color(0.38, 0.4, 0.41) if i % 2 == 0 else Color(0.45, 0.33, 0.24)    # some rusted
		mm.set_mat(M.L_RUST if i % 2 == 1 else M.L_METAL, bar.darkened(rng.randf_range(0.0, 0.1)), rng.randf_range(0.2, 0.5))
		var gone_at := 0.45 + 0.55 * rank / n
		var bent_at := 0.15 + 0.5 * rank / n
		if damage >= gone_at:
			# torn off: a stub bolted to one post, the bar on the ground (once)
			mm.box(Vector3(-px - post * 0.5, yc - bh * 0.5, zf), Vector3(-px + 0.14, yc + bh * 0.5, zf + 0.012))
			if not fallen:
				fallen = true
				mm.obox(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.15, 0.15)), Vector3(0.0, 0.008, zf + 0.12)), Vector3(w * 0.8, 0.012, bh))
			continue
		var tilt := 0.0
		if damage >= bent_at:
			tilt = rng.randf_range(0.05, 0.12) * (1.0 if rng.randf() < 0.5 else -1.0)
		mm.obox(Transform3D(Basis(Vector3.BACK, tilt), Vector3(0, yc, zf + 0.006)), Vector3(w - 0.01, bh, 0.012))
		# bolt heads at the posts
		mm.set_mat(M.L_METAL, Color(0.55, 0.55, 0.52), 0.2)
		for sx in [-1.0, 1.0]:
			mm.box(Vector3(sx * px - 0.012, yc - 0.012, zf + 0.012), Vector3(sx * px + 0.012, yc + 0.012, zf + 0.022))
	if damage < 0.8:
		mm.set_mat(M.L_METAL, steel.darkened(0.1), 0.4)
		var dx := w - 0.12
		var dy := h - 0.4
		var ang := atan2(dy, dx)
		mm.obox(Transform3D(Basis(Vector3.BACK, ang), Vector3(0.0, h * 0.5, zf + 0.026)), Vector3(sqrt(dx * dx + dy * dy) - 0.1, 0.05, 0.01))


## One piece of a plank in a plank-local frame (x along the plank), from x0 to
## x1; ragged ends where `rag0` / `rag1`.
static func _plank_piece(mm: PropMesh, frame: Transform3D, x0: float, x1: float, ph: float, t: float, rng: RandomNumberGenerator, rag0: bool, rag1: bool) -> void:
	var y0 := -ph * 0.5
	var y1 := ph * 0.5
	var pts := PackedVector2Array()
	pts.append(Vector2(x0, y0))
	if rag1:
		pts.append(Vector2(x1 - rng.randf_range(0.0, 0.03), y0))
		pts.append(Vector2(x1 + rng.randf_range(0.0, 0.02), lerpf(y0, y1, 0.35)))
		pts.append(Vector2(x1 - rng.randf_range(0.02, 0.05), lerpf(y0, y1, 0.6)))
		pts.append(Vector2(x1, y1))
	else:
		pts.append(Vector2(x1, y0))
		pts.append(Vector2(x1, y1))
	if rag0:
		pts.append(Vector2(x0 + rng.randf_range(0.0, 0.03), y1))
		pts.append(Vector2(x0 - rng.randf_range(0.0, 0.02), lerpf(y0, y1, 0.6)))
		pts.append(Vector2(x0 + rng.randf_range(0.02, 0.05), lerpf(y0, y1, 0.3)))
	else:
		pts.append(Vector2(x0, y1))
	var keep := mm.xf
	mm.xf = mm.xf * frame
	mm.extrude(pts, -t * 0.5, t * 0.5)
	mm.xf = keep


static func _nails(mm: PropMesh, frame: Transform3D, length: float, ph: float, t: float, left: bool, right: bool, l0: float, l1: float) -> void:
	var keep_c := mm.color
	var keep_l := mm.layer
	mm.set_mat(M.L_METAL, NAIL)
	var keep := mm.xf
	mm.xf = mm.xf * frame
	for s in [-1.0, 1.0]:
		if (s < 0.0 and not left) or (s > 0.0 and not right):
			continue
		var x: float = s * (length * 0.5 - 0.035)
		for dy in [-ph * 0.25, ph * 0.25]:
			mm.box(Vector3(x - 0.006, dy - 0.006, t * 0.5), Vector3(x + 0.006, dy + 0.006, t * 0.5 + 0.004))
	mm.xf = keep
	mm.set_mat(keep_l, keep_c)


# --- crate -----------------------------------------------------------------------------------------

## A slatted storage crate of rough planks: corner posts, slats with gaps, a
## battened lid sitting slightly askew, rope handles, a stencilled mark.
## Damage knocks out slats and cracks the lid.
static func _crate(mm: PropMesh, w: float, h: float, d: float, rng: RandomNumberGenerator, damage: float) -> void:
	var post := clampf(minf(w, d) * 0.08, 0.03, 0.05)
	var t := 0.018
	var lid := 0.025
	var body := h - lid
	var x := w * 0.5
	var z := d * 0.5
	# dark interior seen through the gaps
	mm.set_mat(M.L_PLAIN, Color(0.15, 0.12, 0.09))
	mm.box(Vector3(-x + t, 0.02, -z + t), Vector3(x - t, body - 0.01, z - t))
	# corner posts
	mm.grain_v = true
	mm.set_mat(M.L_ROUGH_WOOD, Color(0.6, 0.48, 0.34), 0.2)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mm.box(Vector3(sx * x - (post if sx > 0 else 0.0), 0, sz * z - (post if sz > 0 else 0.0)), Vector3(sx * x + (0.0 if sx > 0 else post), body, sz * z + (0.0 if sz > 0 else post)))
	mm.grain_v = false
	# slats on all four sides
	var rows := maxi(2, int(round(body / 0.14)))
	var gap := 0.018
	var sh := (body - gap * (rows + 1)) / rows
	var missing := int(damage * 5.0)
	var holes := {}
	for k in missing:
		holes[Vector2i(rng.randi() % 4, rng.randi() % rows)] = true
	var base: Color = PLANKS[rng.randi() % 3]
	for side in 4:
		for r in rows:
			if holes.has(Vector2i(side, r)):
				continue
			var y0 := gap + r * (sh + gap)
			mm.set_mat(M.L_ROUGH_WOOD, base.darkened(rng.randf_range(-0.05, 0.12)), rng.randf_range(0.05, 0.2))
			match side:
				0:
					mm.box(Vector3(-x + post, y0, z - t), Vector3(x - post, y0 + sh, z))
				1:
					mm.box(Vector3(-x + post, y0, -z), Vector3(x - post, y0 + sh, -z + t))
				2:
					mm.box(Vector3(-x, y0, -z + post), Vector3(-x + t, y0 + sh, z - post))
				_:
					mm.box(Vector3(x - t, y0, -z + post), Vector3(x, y0 + sh, z - post))
	# lid: boards with two battens, nudged askew by the last person who looked inside
	var keep := mm.xf
	mm.xf = mm.xf * Transform3D(Basis(Vector3.UP, rng.randf_range(-0.05, 0.05)), Vector3(rng.randf_range(-0.02, 0.02), body, rng.randf_range(-0.02, 0.02)))
	var boards := maxi(2, int(round(d / 0.16)))
	var bd := (d - 0.01) / boards
	for i in boards:
		var bz := -d * 0.5 + 0.005 + i * bd
		mm.set_mat(M.L_ROUGH_WOOD, base.darkened(rng.randf_range(-0.04, 0.1)), 0.15)
		if damage > 0.5 and i == boards / 2:
			mm.box(Vector3(-x + 0.01, 0.0, bz + 0.003), Vector3(-0.05, lid * 0.7, bz + bd - 0.003))
			mm.obox(Transform3D(Basis(Vector3.BACK, 0.25), Vector3(x * 0.5, lid * 0.6, bz + bd * 0.5)), Vector3(x - 0.04, lid * 0.7, bd - 0.006))
		else:
			mm.box(Vector3(-x + 0.01, 0.0, bz + 0.003), Vector3(x - 0.01, lid * 0.7, bz + bd - 0.003))
	mm.set_mat(M.L_ROUGH_WOOD, PLANKS[2], 0.2)
	for sx in [-1.0, 1.0]:
		mm.box(Vector3(sx * (x - 0.1) - 0.035, lid * 0.7, -z + 0.03), Vector3(sx * (x - 0.1) + 0.035, lid, z - 0.03))
	mm.xf = keep
	# rope handles on the ends
	mm.set_mat(M.L_PLAIN, Color(0.66, 0.58, 0.44), 0.2)
	for sx in [-1.0, 1.0]:
		var hy := body * 0.72
		mm.polyline([Vector3(sx * x, hy, -0.08), Vector3(sx * (x + 0.012), hy - 0.04, -0.05), Vector3(sx * (x + 0.012), hy - 0.04, 0.05), Vector3(sx * x, hy, 0.08)], 0.008, 4)
	# a stencilled arrow and bar on the front
	mm.set_mat(M.L_PLAIN, Color(0.16, 0.16, 0.15), 0.3)
	var sy := gap + sh * 0.5
	mm.box(Vector3(-x * 0.45, sy - 0.015, z + 0.001), Vector3(x * 0.1, sy + 0.015, z + 0.002))
	mm.poly(PackedVector3Array([Vector3(x * 0.1, sy - 0.045, z + 0.002), Vector3(x * 0.3, sy, z + 0.002), Vector3(x * 0.1, sy + 0.045, z + 0.002)]), Vector3.BACK)


# --- rain collector --------------------------------------------------------------------------------

## A blue drum under a tarp stretched on four posts; the tarp sags into a
## cut-off funnel that drains into the drum. A tap and a tin can at the foot.
static func _rain_collector(mm: PropMesh, w: float, h: float, d: float, rng: RandomNumberGenerator, damage: float) -> void:
	var x := w * 0.5 - 0.035
	var z := d * 0.5 - 0.035
	var br := minf(w, d) * 0.28
	var bh := minf(0.9, h * 0.55)
	# drum with ribs and a dent when damaged
	mm.set_mat(M.L_GLOSSY, Color(0.26, 0.38, 0.5), 0.18)
	mm.cylinder(Vector3.ZERO, br, br, bh, 14, true, true)
	mm.set_mat(M.L_GLOSSY, Color(0.23, 0.35, 0.46), 0.2)
	for f in [0.33, 0.66]:
		mm.cylinder(Vector3(0, bh * f - 0.015, 0), br + 0.008, br + 0.008, 0.03, 14, false)
	mm.cylinder(Vector3(0, bh - 0.02, 0), br + 0.01, br + 0.01, 0.025, 14, false)
	if damage > 0.4:
		mm.set_mat(M.L_SCREEN, Color(0.05, 0.06, 0.07))
		mm.box(Vector3(br * 0.2, bh * 0.5, br - 0.006), Vector3(br * 0.4, bh * 0.56, br + 0.004))
	# tap, a can under it
	mm.set_mat(M.L_METAL, Color(0.6, 0.55, 0.42), 0.2)
	mm.tube(Vector3(0, 0.12, br - 0.01), Vector3(0, 0.12, br + 0.06), 0.012, 0.012, 6)
	mm.box(Vector3(-0.025, 0.13, br + 0.03), Vector3(0.025, 0.145, br + 0.045))
	mm.set_mat(M.L_METAL, Color(0.62, 0.62, 0.6), 0.3)
	mm.cylinder(Vector3(0.0, 0.0, minf(br + 0.1, d * 0.5 - 0.05)), 0.04, 0.04, 0.1, 8, false)
	# four posts and side rails
	mm.grain_v = true
	mm.set_mat(M.L_ROUGH_WOOD, Color(0.56, 0.46, 0.34), 0.25)
	var tilt := 0.0 if damage < 0.7 else 0.06
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var lean := tilt if (sx > 0.0 and sz > 0.0) else 0.0
			mm.obox(Transform3D(Basis(Vector3.BACK, -lean), Vector3(sx * x, h * 0.5, sz * z)), Vector3(0.05, h, 0.05))
	mm.grain_v = false
	mm.set_mat(M.L_ROUGH_WOOD, PLANKS[1], 0.25)
	for sx in [-1.0, 1.0]:
		mm.box(Vector3(sx * x - 0.012, h * 0.45, -z), Vector3(sx * x + 0.012, h * 0.45 + 0.07, z))
	mm.box(Vector3(-x, h * 0.55, -z - 0.012), Vector3(x, h * 0.55 + 0.07, -z + 0.012))
	# the tarp: corners on the post tops, sagging edges, a funnel in the middle
	var top := h - 0.02
	var fy := bh + 0.2
	var c := Vector3(0, fy + 0.06, 0)
	var corners := [Vector3(-x, top, -z), Vector3(x, top, -z), Vector3(x, top, z), Vector3(-x, top, z)]
	var sag := 0.1
	var tarp := Color(0.42, 0.52, 0.44) if rng.randf() < 0.5 else Color(0.44, 0.52, 0.6)
	var torn := -1 if damage < 0.25 else rng.randi() % 8
	var torn2 := -1 if damage < 0.6 else (torn + 3) % 8
	var tri_i := 0
	for i in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		var m := (a + b) * 0.5 - Vector3(0, sag, 0)
		for half in [[a, m], [m, b]]:
			if tri_i != torn and tri_i != torn2:
				mm.set_mat(M.L_TARP, tarp.darkened(rng.randf_range(0.0, 0.06)), 0.15)
				mm.sheet(PackedVector3Array([half[0], half[1], c]))
			else:
				# a torn flap hanging down
				mm.set_mat(M.L_TARP, tarp.darkened(0.1), 0.25)
				var p0: Vector3 = half[0]
				var p1: Vector3 = half[1]
				var hang := (p0 + p1) * 0.5 + Vector3(0, -0.25, 0)
				hang.y = maxf(hang.y, bh + 0.1)
				mm.sheet(PackedVector3Array([p0, p1.lerp(p0, 0.4), hang]))
			tri_i += 1
	# tie ropes at the corners, the funnel into the drum
	mm.set_mat(M.L_PLAIN, Color(0.68, 0.6, 0.45))
	for p in corners:
		mm.tube(p, p + Vector3(0, -0.12, 0), 0.006, 0.006, 4, false)
	mm.set_mat(M.L_PLAIN, Color(0.74, 0.46, 0.22), 0.1)
	mm.cylinder(Vector3(0, bh - 0.01, 0), 0.045, 0.2, fy + 0.07 - bh, 12, false)
	mm.cylinder_inside(Vector3(0, bh, 0), 0.04, 0.19, fy + 0.06 - bh, 12)


# --- candle and lantern ----------------------------------------------------------------------------

## Two or three pillar candles on a saucer, with drips, a wax puddle and a
## matchbox. Flames (L_FLAME) show only while `lit` > 0.
static func _candle(mm: PropMesh, w: float, h: float, d: float, rng: RandomNumberGenerator) -> void:
	var r := minf(w, d) * 0.45
	mm.set_mat(M.L_GLOSSY, Color(0.86, 0.84, 0.8), 0.05)
	mm.cylinder(Vector3.ZERO, r * 0.8, r, 0.014, 14)
	mm.set_mat(M.L_GLOSSY, Color(0.8, 0.78, 0.74), 0.08)
	mm.cylinder(Vector3(0, 0.014, 0), r, r * 1.0, 0.006, 14, false)
	mm.set_mat(M.L_WAX, Color(0.9, 0.86, 0.76))
	mm.cylinder(Vector3(0.01, 0.014, -0.01), r * 0.6, r * 0.62, 0.002, 10)
	var n := 2 + rng.randi() % 2
	var flame_h := minf(0.04, h * 0.22)
	for i in n:
		var a := TAU * i / n + rng.randf_range(-0.3, 0.3)
		var cr := rng.randf_range(0.016, 0.026) * clampf(r / 0.09, 0.6, 1.4)
		var off := (r - cr - 0.008) * (0.55 if n > 1 else 0.0)
		var p := Vector3(cos(a) * off, 0.016, sin(a) * off)
		var ch := (h - flame_h - 0.03) * rng.randf_range(0.45, 1.0)
		ch = maxf(ch, 0.02)
		var wax := Color(0.92, 0.88, 0.78) if rng.randf() < 0.7 else Color(0.86, 0.8, 0.7)
		mm.set_mat(M.L_WAX, wax)
		mm.cylinder(p, cr, cr * 0.98, ch, 10, true, true)
		# drips down the side
		for k in 2:
			var da := rng.randf() * TAU
			var dl := rng.randf_range(0.2, 0.6) * ch
			mm.blob(p + Vector3(cos(da) * cr, ch - dl * 0.5, sin(da) * cr), Vector3(0.004, dl * 0.5, 0.004), 3, 5)
		# wick and flame
		mm.set_mat(M.L_PLAIN, Color(0.08, 0.07, 0.06))
		mm.cylinder(p + Vector3(0, ch, 0), 0.0015, 0.001, 0.009, 4)
		mm.set_mat(M.L_FLAME, Color(1.0, 0.66, 0.28))
		mm.blob(p + Vector3(0, ch + 0.006 + flame_h * 0.42, 0), Vector3(flame_h * 0.2, flame_h * 0.42, flame_h * 0.2), 4, 7)
		mm.set_mat(M.L_FLAME, Color(1.0, 0.92, 0.72))
		mm.blob(p + Vector3(0, ch + 0.006 + flame_h * 0.3, 0), Vector3(flame_h * 0.1, flame_h * 0.26, flame_h * 0.1), 3, 6)
	# a matchbox beside the saucer
	if w > 0.12:
		mm.set_mat(M.L_PAPER, Color(0.7, 0.3, 0.2))
		mm.obox(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.6, 0.6)), Vector3(r * 0.55, 0.026, r * 0.55)), Vector3(0.05, 0.016, 0.035))


## A battery camping lantern: olive base with a switch, frosted diffuser
## (L_GLOW, glows while `lit`), guard bars, a cap and a folded wire handle.
static func _lantern(mm: PropMesh, w: float, h: float, d: float, rng: RandomNumberGenerator) -> void:
	var r := minf(w, d) * 0.42
	var body := Color(0.27, 0.32, 0.25) if rng.randf() < 0.6 else Color(0.62, 0.32, 0.18)
	var bh := h * 0.24
	var gh := h * 0.4
	var ch := h * 0.1
	mm.set_mat(M.L_PLAIN, Color(0.1, 0.1, 0.1))
	mm.cylinder(Vector3.ZERO, r * 0.98, r * 1.0, 0.012, 12)
	mm.set_mat(M.L_PLAIN, body, 0.12)
	mm.cylinder(Vector3(0, 0.012, 0), r, r * 0.92, bh - 0.012, 12, true, true)
	mm.set_mat(M.L_GLOSSY, Color(0.85, 0.55, 0.2))
	mm.box(Vector3(-0.012, bh * 0.45, r * 0.94), Vector3(0.012, bh * 0.75, r * 0.99))
	mm.set_mat(M.L_GLOW, Color(0.95, 0.92, 0.84))
	mm.cylinder(Vector3(0, bh, 0), r * 0.74, r * 0.74, gh, 12, false, true)
	mm.no_shadow = true
	mm.set_mat(M.L_PLAIN, body.darkened(0.25))
	for k in 4:
		var a := TAU * (k + 0.5) / 4.0
		mm.box(Vector3(cos(a) * r * 0.8 - 0.005, bh, sin(a) * r * 0.8 - 0.005), Vector3(cos(a) * r * 0.8 + 0.005, bh + gh, sin(a) * r * 0.8 + 0.005))
	mm.set_mat(M.L_PLAIN, body, 0.1)
	mm.cylinder(Vector3(0, bh + gh, 0), r * 0.85, r * 0.6, ch, 12, true, true)
	# folded wire handle up over the cap
	mm.set_mat(M.L_METAL, Color(0.18, 0.18, 0.19))
	var y0 := bh + gh + ch * 0.4
	var pts := []
	for k in 7:
		var a := PI * k / 6.0
		pts.append(Vector3(cos(a) * r * 0.7, y0 + sin(a) * (h - 0.006 - y0), 0))
	mm.polyline(pts, 0.004, 4)
	mm.no_shadow = false
