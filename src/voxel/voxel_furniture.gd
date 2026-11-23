class_name VoxelFurniture
extends RefCounted
## Procedural voxel furniture for the shared HousePlan, built into the house grid.
##
## Each type is a small implicit function of local coordinates:
##   a = across the front (0..A), d = depth from the front face (0..D), h = height.
## It returns (material << 24) | 0xRRGGBB, or -1 for empty. Pieces at least
## Tuning.TALL_THRESHOLD tall use the TALL material ids (they stop bullets and
## can be carved); lower pieces are shot over (bullets pass through).

const VS := 0.1
## Extra height some pieces draw above their plan height (decor: mirrors, faucets...).
const EXTRA := {"vanity": 1.0, "sink_counter": 0.3, "bed": 0.35, "workbench": 0.9, "tv_stand": 0.0, "nightstand": 0.0}

static var C: Dictionary = {}


static func _palette() -> void:
	var s := VoxelArt.Slot
	C = {
		"sofa": VoxelArt.pal(s.SOFA), "armchair": VoxelArt.pal(s.ARMCHAIR), "duvet": VoxelArt.pal(s.DUVET),
		"cabinet": VoxelArt.pal(s.CABINET), "worktop": VoxelArt.pal(s.WORKTOP), "wood_dark": VoxelArt.pal(s.WOOD_DARK),
		"wood_light": VoxelArt.pal(s.WOOD_LIGHT), "metal_dark": VoxelArt.pal(s.METAL_DARK),
		"white": 0xe4e2dc, "ceramic": 0xe8e8e4, "steel": 0xa9adb0, "black": 0x1c1d1f, "screen": 0x0f1214,
		"linen": 0xe9dcc0, "terracotta": 0x9c5b3e, "soil": 0x3a2c22, "leaf": 0x4b5a35, "leaf_dead": 0x7a6a3a,
		"ochre": 0xb08a3e, "cardboard": 0xa8865a, "tape": 0xc9b48a, "copper": 0xa8653c, "red": 0x8e2f2a,
		"pillow": 0xe6e1d6, "mattress": 0xd8d4ca, "glass_dark": 0x22313a,
	}


static func build_all(g: VoxelGrid) -> void:
	_palette()
	for f in HousePlan.FURNITURE:
		if f["type"] == "rug":
			continue
		build_piece(g, f)
	for l in HousePlan.LIGHTS:
		_fixture(g, l)


static func _enc(m: int, c: int) -> int:
	return (m << 24) | (c & 0xffffff)


static func build_piece(g: VoxelGrid, f: Dictionary) -> void:
	var rect: Rect2 = f["rect"]
	var facing: String = f["facing"]
	var H: float = f["height"]
	var tall := H >= Tuning.TALL_THRESHOLD
	var t: String = f["type"]
	var ns := facing == "N" or facing == "S"
	var A := rect.size.x if ns else rect.size.y
	var D := rect.size.y if ns else rect.size.x
	var xr := g.centre_range(0, rect.position.x, rect.end.x)
	var zr := g.centre_range(2, rect.position.y, rect.end.y)
	var rows := maxi(1, int(round((H + EXTRA.get(t, 0.0)) / VS)))
	var seed := hash(f["id"]) & 0xffff
	for z in range(zr.x, zr.y):
		for x in range(xr.x, xr.y):
			var p := VoxelHouse.column_plan(g, x, z)
			var a := 0.0
			var d := 0.0
			match facing:
				"S":
					a = p.x - rect.position.x
					d = rect.end.y - p.y
				"N":
					a = rect.end.x - p.x
					d = p.y - rect.position.y
				"E":
					a = rect.end.y - p.y
					d = rect.end.x - p.x
				_:
					a = p.y - rect.position.y
					d = p.x - rect.position.x
			for r in rows:
				var y := VoxelHouse.BASE_ROW + r
				if g.get_mat(x, y, z) != VoxelMat.AIR:
					continue
				var h := (r + 0.5) * VS
				var k := int(VoxelArt.hash3(x, y, z, seed) * 1000.0)
				var res := _eval(t, a, d, h, A, D, H, k, seed)
				if res < 0:
					continue
				var m := VoxelMat.furniture(res >> 24, tall)
				var c := res & 0xffffff
				g.set_voxel(x, y, z, m, c, c, 0)


static func _in(v: float, lo: float, hi: float) -> bool:
	return v >= lo and v < hi


static func _j(c: int, k: int, amt := 0.05) -> int:
	return VoxelArt.scale(c, 1.0 + (float(k % 100) / 100.0 - 0.5) * 2.0 * amt)


static func _eval(t: String, a: float, d: float, h: float, A: float, D: float, H: float, k: int, s: int) -> int:
	match t:
		"tv_stand": return _tv_stand(a, d, h, A, D, H, k)
		"sofa": return _sofa(a, d, h, A, D, H, k, C["sofa"])
		"armchair": return _sofa(a, d, h, A, D, H, k, C["armchair"])
		"coffee_table": return _table(a, d, h, A, D, H, k, C["wood_light"], C["black"], true)
		"dining_table": return _table(a, d, h, A, D, H, k, C["wood_light"], C["wood_light"], false)
		"floor_lamp": return _floor_lamp(a, d, h, A, D, H, k)
		"bookshelf": return _bookshelf(a, d, h, A, D, H, k, s)
		"chair": return _chair(a, d, h, A, D, H, k)
		"plant": return _plant(a, d, h, A, D, H, k, s)
		"fridge": return _fridge(a, d, h, A, D, H, k)
		"counter": return _counter(a, d, h, A, D, H, k, false)
		"sink_counter": return _counter(a, d, h, A, D, H, k, true)
		"island": return _island(a, d, h, A, D, H, k)
		"stove": return _stove(a, d, h, A, D, H, k)
		"stool": return _stool(a, d, h, A, D, H, k)
		"bed": return _bed(a, d, h, A, D, H, k, s)
		"nightstand": return _cabinet(a, d, h, A, D, H, k, C["wood_light"], 2)
		"dresser": return _cabinet(a, d, h, A, D, H, k, C["wood_light"], 3)
		"wardrobe": return _wardrobe(a, d, h, A, D, H, k)
		"bathtub": return _bathtub(a, d, h, A, D, H, k)
		"toilet": return _toilet(a, d, h, A, D, H, k)
		"vanity": return _vanity(a, d, h, A, D, H, k)
		"water_heater": return _water_heater(a, d, h, A, D, H, k)
		"workbench": return _workbench(a, d, h, A, D, H, k, s)
		"washer", "dryer": return _washer(a, d, h, A, D, H, k, t == "dryer")
		"shelves": return _shelves(a, d, h, A, D, H, k, s)
		"boxes": return _boxes(a, d, h, A, D, H, k, s)
	return _enc(VoxelMat.WOOD, _j(C["wood_light"], k))


# --- living room ----------------------------------------------------------------------

static func _tv_stand(a: float, d: float, h: float, A: float, D: float, H: float, k: int) -> int:
	if h < 0.45:
		if h < 0.1 and not ((a < 0.15 or a > A - 0.15) and (d < 0.15 or d > D - 0.15)):
			return -1
		var c: int = C["wood_dark"]
		if d < 0.1 and (absf(a - A * 0.5) < 0.05 or h > 0.35):
			c = VoxelArt.scale(c, 0.75)
		return _enc(VoxelMat.WOOD, _j(c, k, 0.04))
	if absf(a - A * 0.5) < 0.12 and _in(d, 0.15, 0.35) and h < 0.55:
		return _enc(VoxelMat.METAL, C["black"])
	if _in(d, 0.2, 0.3) and _in(a, 0.2, A - 0.2) and _in(h, 0.55, 1.1):
		var edge := a < 0.3 or a > A - 0.3 or h < 0.65 or h > 1.0
		return _enc(VoxelMat.SCREEN, 0x1b1d20 if edge else C["screen"])
	return -1


static func _sofa(a: float, d: float, h: float, A: float, D: float, H: float, k: int, fabric: int) -> int:
	var arm := a < 0.2 or a > A - 0.2
	var back := d > D - 0.25
	if h < 0.1:
		if (a < 0.15 or a > A - 0.15) and (d < 0.15 or d > D - 0.15):
			return _enc(VoxelMat.WOOD, C["wood_dark"])
		return -1
	if back and h < H:
		var c := VoxelArt.scale(fabric, 0.92)
		if h > H - 0.1:
			c = VoxelArt.scale(fabric, 1.05)
		return _enc(VoxelMat.FABRIC, _j(c, k, 0.04))
	if arm and h < 0.65:
		return _enc(VoxelMat.FABRIC, _j(VoxelArt.scale(fabric, 0.97 if h < 0.55 else 1.06), k, 0.04))
	if h < 0.45:
		return _enc(VoxelMat.FABRIC, _j(VoxelArt.scale(fabric, 0.85), k, 0.04))
	if h < 0.55:
		# seat cushions with seams
		var seam := A > 1.5 and absf(fmod(a - 0.2, (A - 0.4) / 3.0)) < 0.05
		return _enc(VoxelMat.FABRIC, _j(VoxelArt.scale(fabric, 0.78 if seam else 1.0), k, 0.05))
	# throw pillows leaning on the back
	if d > D - 0.38 and h < 0.75 and A > 1.5 and (_in(a, 0.25, 0.55) or _in(a, A - 0.55, A - 0.25)):
		return _enc(VoxelMat.FABRIC, _j(C["ochre"], k, 0.06))
	return -1


static func _table(a: float, d: float, h: float, A: float, D: float, H: float, k: int, top: int, leg: int, shelf: bool) -> int:
	if h >= H - 0.1:
		var c := top
		if absf(fmod(a, 0.2)) < 0.05:
			c = VoxelArt.scale(top, 0.94)
		return _enc(VoxelMat.WOOD, _j(c, k, 0.05))
	if (a < 0.1 or a > A - 0.1) and (d < 0.1 or d > D - 0.1):
		return _enc(VoxelMat.METAL if leg == C["black"] else VoxelMat.WOOD, leg)
	if shelf and _in(h, 0.1, 0.2) and _in(a, 0.1, A - 0.1) and _in(d, 0.1, D - 0.1):
		# a stack of magazines on the lower shelf
		if _in(a, 0.2, 0.5):
			return _enc(VoxelMat.PAPER, _j(0xb04a3a if k % 2 == 0 else 0xd8cfb8, k, 0.05))
		return _enc(VoxelMat.WOOD, _j(top, k, 0.05))
	return -1


static func _floor_lamp(a: float, d: float, h: float, A: float, D: float, H: float, k: int) -> int:
	var r := Vector2(a - A * 0.5, d - D * 0.5).length()
	if h < 0.05 + VS and r < 0.16:
		return _enc(VoxelMat.METAL, C["black"])
	if h < 1.25 and r < 0.06:
		return _enc(VoxelMat.METAL, C["black"])
	if _in(h, 1.25, 1.6) and r < 0.2 + (1.6 - h) * 0.12:
		return _enc(VoxelMat.GLOW, _j(C["linen"], k, 0.03))
	return -1


static func _bookshelf(a: float, d: float, h: float, A: float, D: float, H: float, k: int, s: int) -> int:
	var frame: int = C["wood_dark"]
	if a < 0.1 or a > A - 0.1 or h < 0.1 or h > H - 0.1 or d > D - 0.1:
		return _enc(VoxelMat.WOOD, _j(frame, k, 0.04))
	var shelf_h := fmod(h - 0.1, 0.45)
	if shelf_h < 0.1:
		return _enc(VoxelMat.WOOD, _j(frame, k, 0.04))
	# books: one per voxel column, random height and colour, some gaps
	var col := int(a / VS)
	var level := int((h - 0.1) / 0.45)
	var rnd := VoxelArt.hash3(col, level, s)
	if rnd < 0.12:
		return -1
	var book_h := 0.2 + rnd * 0.2
	if shelf_h > book_h + 0.1:
		return -1
	var hues := [0x6b2f2a, 0x2f4a5a, 0x7d6a3a, 0x3e4d38, 0x8a7d6a, 0x4a3b52, 0xb39a6a, 0x2c2c2c]
	return _enc(VoxelMat.PAPER, _j(hues[int(rnd * 97.0) % hues.size()], k, 0.04))


static func _chair(a: float, d: float, h: float, A: float, D: float, H: float, k: int) -> int:
	var wood: int = C["wood_dark"]
	if _in(h, 0.4, 0.5):
		return _enc(VoxelMat.WOOD, _j(wood, k, 0.04))
	if h < 0.4 and (a < 0.1 or a > A - 0.1) and (d < 0.1 or d > D - 0.1):
		return _enc(VoxelMat.WOOD, wood)
	if h >= 0.5 and d > D - 0.1 and (h > 0.75 or a < 0.1 or a > A - 0.1):
		return _enc(VoxelMat.WOOD, _j(wood, k, 0.04))
	return -1


static func _plant(a: float, d: float, h: float, A: float, D: float, H: float, k: int, s: int) -> int:
	var r := Vector2(a - A * 0.5, d - D * 0.5).length()
	if h < 0.4:
		if r < 0.2 - (0.4 - h) * 0.12:
			if h > 0.3 and r < 0.15:
				return _enc(VoxelMat.LEAF, C["soil"])
			return _enc(VoxelMat.CERAMIC, _j(C["terracotta"], k, 0.05))
		return -1
	var hh := h - 0.4
	var radius := 0.25 * sin(clampf(hh / 0.7, 0.0, 1.0) * PI) + 0.06
	var n := VoxelArt.hash3(int(a * 10.0), int(h * 10.0), int(d * 10.0), s)
	if r < radius * (0.6 + 0.6 * n):
		var c: int = C["leaf"] if n > 0.35 else C["leaf_dead"]
		return _enc(VoxelMat.LEAF, _j(c, k, 0.1))
	return -1


# --- kitchen -------------------------------------------------------------------------

static func _fridge(a: float, d: float, h: float, A: float, D: float, H: float, k: int) -> int:
	if h < 0.1 and d < 0.05:
		return _enc(VoxelMat.METAL, C["black"])
	if d < 0.1:
		if absf(h - 1.2) < 0.05:
			return _enc(VoxelMat.METAL, C["black"])
		if a > A - 0.15 and (_in(h, 0.85, 1.1) or _in(h, 1.3, 1.6)):
			return _enc(VoxelMat.METAL, C["metal_dark"])
	return _enc(VoxelMat.PAINTED, _j(C["steel"], k, 0.025))


static func _counter(a: float, d: float, h: float, A: float, D: float, H: float, k: int, sink: bool) -> int:
	var top_h := H - 0.1
	if sink:
		var basin := _in(a, 0.2, A - 0.2) and _in(d, 0.12, 0.5)
		if h >= top_h and h < H:
			if basin:
				return -1
			return _enc(VoxelMat.STONE, _j(C["worktop"], k, 0.03))
		if basin and _in(h, top_h - 0.3, top_h):
			if h < top_h - 0.2 or a < 0.3 or a > A - 0.3 or d < 0.22 or d > 0.4:
				return _enc(VoxelMat.METAL, _j(C["steel"], k, 0.03))
			return -1
		if h >= H:
			# faucet at the back, arching over the basin
			if absf(a - A * 0.5) < 0.05 and (_in(d, 0.5, 0.6) or (h > H + 0.15 and _in(d, 0.35, 0.6))):
				return _enc(VoxelMat.METAL, C["steel"])
			return -1
	if h >= top_h:
		return _enc(VoxelMat.STONE, _j(C["worktop"], k, 0.03))
	if h < 0.1:
		return -1 if d < 0.08 else _enc(VoxelMat.WOOD, C["black"])
	var c: int = C["cabinet"]
	if d < 0.1:
		var seam := absf(fmod(a, 0.5)) < 0.05 or absf(h - (top_h - 0.15)) < 0.05
		if seam:
			c = VoxelArt.scale(c, 0.72)
		elif absf(h - (top_h - 0.25)) < 0.05 and absf(fmod(a, 0.5) - 0.25) < 0.06:
			c = C["metal_dark"]
	return _enc(VoxelMat.WOOD, _j(c, k, 0.03))


static func _island(a: float, d: float, h: float, A: float, D: float, H: float, k: int) -> int:
	var top_h := H - 0.1
	if h >= top_h:
		return _enc(VoxelMat.STONE, _j(C["worktop"], k, 0.03))
	if d < 0.25:
		return -1   # overhang on the seating side
	if h < 0.1:
		return _enc(VoxelMat.WOOD, C["black"]) if d > 0.3 else -1
	var c: int = C["cabinet"]
	if d > D - 0.1 and absf(fmod(a, 0.6)) < 0.05:
		c = VoxelArt.scale(c, 0.72)
	return _enc(VoxelMat.WOOD, _j(c, k, 0.03))


static func _stove(a: float, d: float, h: float, A: float, D: float, H: float, k: int) -> int:
	var top_h := H - 0.1
	if h >= top_h:
		var bx := fmod(a, A * 0.5) - A * 0.25
		var bz := fmod(d, D * 0.5) - D * 0.25
		var ring := Vector2(bx, bz).length()
		if ring < 0.12 and ring > 0.04:
			return _enc(VoxelMat.METAL, 0x3a3c3f)
		return _enc(VoxelMat.SCREEN, C["black"])
	if d < 0.1:
		if h > top_h - 0.1:
			return _enc(VoxelMat.METAL, 0x3a3c3f if int(a / VS) % 2 == 0 else C["steel"])
		if _in(h, 0.2, 0.6) and _in(a, 0.12, A - 0.12):
			return _enc(VoxelMat.SCREEN, C["glass_dark"])
	return _enc(VoxelMat.PAINTED, _j(C["steel"], k, 0.02))


static func _stool(a: float, d: float, h: float, A: float, D: float, H: float, k: int) -> int:
	if h >= H - 0.1:
		return _enc(VoxelMat.WOOD, _j(C["wood_light"], k, 0.04))
	if (a < 0.1 or a > A - 0.1) and (d < 0.1 or d > D - 0.1):
		return _enc(VoxelMat.METAL, C["black"])
	return -1


# --- bedroom ------------------------------------------------------------------------

static func _bed(a: float, d: float, h: float, A: float, D: float, H: float, k: int, s: int) -> int:
	var head := d > D - 0.1
	if head:
		if h < H + 0.35:
			return _enc(VoxelMat.WOOD, _j(C["wood_dark"], k, 0.03))
		return -1
	if h < 0.1:
		if (a < 0.1 or a > A - 0.1) and (d < 0.1 or d > D - 0.2):
			return _enc(VoxelMat.WOOD, C["wood_dark"])
		return -1
	if h < 0.25:
		return _enc(VoxelMat.WOOD, _j(C["wood_light"], k, 0.04))
	if h < 0.45:
		return _enc(VoxelMat.FABRIC, _j(C["mattress"], k, 0.03))
	# pillows near the headboard, duvet over the rest (rumpled, pulled aside)
	if d > D - 0.55 and h < 0.62 and (_in(a, 0.12, A * 0.5 - 0.05) or _in(a, A * 0.5 + 0.05, A - 0.12)):
		return _enc(VoxelMat.FABRIC, _j(C["pillow"], k, 0.03))
	var rumple := VoxelArt.hash3(int(a * 10.0), 0, int(d * 10.0), s)
	if d < D - 0.6 and h < 0.55 + (0.1 if rumple > 0.7 else 0.0):
		if a > A - 0.35 and d < 0.6 and h > 0.5:
			return -1
		return _enc(VoxelMat.FABRIC, _j(C["duvet"], k, 0.05))
	return -1


static func _cabinet(a: float, d: float, h: float, A: float, D: float, H: float, k: int, wood: int, drawers: int) -> int:
	if h < 0.1 and d < 0.05:
		return -1
	var c := wood
	if d < 0.1 and h >= 0.1:
		var band := (H - 0.1) / drawers
		var f := fmod(h - 0.1, band)
		if f < 0.05:
			c = VoxelArt.scale(wood, 0.7)
		elif absf(f - band * 0.5) < 0.05 and absf(a - A * 0.5) < 0.1:
			c = C["metal_dark"]
	return _enc(VoxelMat.WOOD, _j(c, k, 0.04))


static func _wardrobe(a: float, d: float, h: float, A: float, D: float, H: float, k: int) -> int:
	if h < 0.1 and d < 0.05:
		return -1
	var c: int = C["white"]
	if d < 0.1:
		if absf(a - A * 0.5) < 0.05:
			c = VoxelArt.scale(c, 0.7)
		elif absf(a - A * 0.5) < 0.15 and _in(h, 0.9, 1.3):
			c = C["metal_dark"]
	if h > H - 0.1:
		c = C["wood_light"]
	return _enc(VoxelMat.WOOD, _j(c, k, 0.03))


# --- bathroom ------------------------------------------------------------------------

static func _bathtub(a: float, d: float, h: float, A: float, D: float, H: float, k: int) -> int:
	var inner := _in(a, 0.1, A - 0.1) and _in(d, 0.1, D - 0.1)
	if inner and h > 0.15:
		if absf(a - A * 0.5) < 0.05 and d > D - 0.2 and h > H - 0.1:
			return _enc(VoxelMat.METAL, C["steel"])
		return -1
	if inner and h > 0.1:
		return _enc(VoxelMat.CERAMIC, _j(0x6f7b72, k, 0.08))   # grimy water line
	return _enc(VoxelMat.CERAMIC, _j(C["ceramic"], k, 0.02))


static func _toilet(a: float, d: float, h: float, A: float, D: float, H: float, k: int) -> int:
	var tank := d > D - 0.2
	if tank:
		if h >= 0.35:
			return _enc(VoxelMat.CERAMIC, _j(C["ceramic"], k, 0.02))
		return _enc(VoxelMat.CERAMIC, _j(C["ceramic"], k, 0.02)) if absf(a - A * 0.5) < 0.12 else -1
	var r := Vector2((a - A * 0.5) / (A * 0.5), (d - (D - 0.2) * 0.5) / ((D - 0.2) * 0.5 + 0.05)).length()
	if h < 0.3 and r < 0.75:
		return _enc(VoxelMat.CERAMIC, _j(C["ceramic"], k, 0.02))
	if _in(h, 0.3, 0.45) and r < 1.0:
		if r < 0.6 and h > 0.35:
			return -1
		return _enc(VoxelMat.CERAMIC, _j(C["ceramic"], k, 0.02))
	return -1


static func _vanity(a: float, d: float, h: float, A: float, D: float, H: float, k: int) -> int:
	if h < H:
		if h >= H - 0.1:
			if _in(a, 0.2, A - 0.2) and _in(d, 0.1, 0.35):
				return -1 if h > H - 0.05 else _enc(VoxelMat.CERAMIC, C["ceramic"])
			return _enc(VoxelMat.CERAMIC, _j(C["ceramic"], k, 0.02))
		if h < 0.1:
			return -1 if d < 0.05 else _enc(VoxelMat.WOOD, C["wood_dark"])
		var c: int = C["wood_light"]
		if d < 0.1 and absf(a - A * 0.5) < 0.05:
			c = VoxelArt.scale(c, 0.7)
		return _enc(VoxelMat.WOOD, _j(c, k, 0.04))
	# mirror and faucet on the wall behind
	if d > D - 0.1 and _in(h, H + 0.25, H + 0.95) and _in(a, 0.1, A - 0.1):
		var edge := a < 0.2 or a > A - 0.2 or h < H + 0.35 or h > H + 0.85
		return _enc(VoxelMat.SCREEN, 0x2c3134 if edge else 0x7c8f96)
	if absf(a - A * 0.5) < 0.05 and _in(d, D - 0.3, D) and h < H + 0.2:
		return _enc(VoxelMat.METAL, C["steel"])
	return -1


# --- utility room -------------------------------------------------------------------

static func _water_heater(a: float, d: float, h: float, A: float, D: float, H: float, k: int) -> int:
	var r := Vector2(a - A * 0.5, d - D * 0.5).length()
	if r < 0.28:
		var c: int = C["white"]
		if h < 0.1 or h > H - 0.1:
			c = C["steel"]
		elif absf(h - 0.9) < 0.05 and d < 0.2:
			c = C["red"]
		return _enc(VoxelMat.PAINTED, _j(c, k, 0.03))
	return -1


static func _workbench(a: float, d: float, h: float, A: float, D: float, H: float, k: int, s: int) -> int:
	if h < H:
		if h >= H - 0.1:
			return _enc(VoxelMat.WOOD, _j(C["worktop"], k, 0.06))
		if (a < 0.1 or a > A - 0.1) and (d < 0.1 or d > D - 0.1):
			return _enc(VoxelMat.METAL, C["metal_dark"])
		if _in(h, 0.1, 0.2):
			return _enc(VoxelMat.WOOD, _j(C["worktop"], k, 0.06))
		if _in(h, 0.2, 0.4) and _in(a, 0.3, 0.8):
			return _enc(VoxelMat.PAINTED, _j(C["red"], k, 0.04))   # toolbox under the bench
		return -1
	# pegboard on the wall behind with a few tool silhouettes, a vise on top
	if d > D - 0.1 and _in(h, H + 0.1, H + 0.9) and _in(a, 0.1, A - 0.1):
		var tool := VoxelArt.hash3(int(a * 10.0), int(h * 10.0), 0, s)
		if tool > 0.86:
			return _enc(VoxelMat.METAL, C["metal_dark"])
		return _enc(VoxelMat.WOOD, _j(0x9c8462, k, 0.04))
	if h < H + 0.1 and _in(a, 0.15, 0.35) and _in(d, 0.05, 0.3):
		return _enc(VoxelMat.METAL, 0x3c4a56)
	return -1


static func _washer(a: float, d: float, h: float, A: float, D: float, H: float, k: int, dryer: bool) -> int:
	if h < 0.1 and d < 0.05:
		return -1
	if d < 0.1:
		var r := Vector2(a - A * 0.5, h - 0.42).length()
		if r < 0.18:
			return _enc(VoxelMat.SCREEN, 0x2a3135 if r < 0.12 else 0x8d9296)
		if h > H - 0.15 and a > A - 0.25:
			return _enc(VoxelMat.PLASTIC, 0x404448)
	var c: int = 0xdcdad3 if dryer else C["white"]
	return _enc(VoxelMat.PAINTED, _j(c, k, 0.02))


static func _shelves(a: float, d: float, h: float, A: float, D: float, H: float, k: int, s: int) -> int:
	if (a < 0.1 or a > A - 0.1) and (d < 0.1 or d > D - 0.1):
		return _enc(VoxelMat.METAL, C["metal_dark"])
	var level := fmod(h, 0.45)
	if level < 0.1:
		return _enc(VoxelMat.METAL, _j(C["steel"], k, 0.04))
	var slot := int(a / 0.3)
	var lv := int(h / 0.45)
	var rnd := VoxelArt.hash3(slot, lv, 5, s)
	if rnd < 0.25 or level > 0.1 + 0.12 + rnd * 0.2:
		return -1
	if rnd < 0.6:
		return _enc(VoxelMat.PAPER, _j(C["cardboard"], k, 0.06))
	var cans := [0x8d3b2f, 0x3f5d73, 0xc9b26a, 0x6f7f6d]
	return _enc(VoxelMat.METAL, _j(cans[int(rnd * 31.0) % cans.size()], k, 0.04))


static func _boxes(a: float, d: float, h: float, A: float, D: float, H: float, k: int, s: int) -> int:
	# two boxes side by side, a third one on top
	var c: int = C["cardboard"]
	var left := a < A * 0.5
	if h < 0.4:
		if absf(a - A * 0.5) < 0.05:
			return -1
		if absf(d - D * 0.5) < 0.05 and h > 0.3:
			return _enc(VoxelMat.PAPER, C["tape"])
		return _enc(VoxelMat.PAPER, _j(VoxelArt.scale(c, 0.95 if left else 1.05), k, 0.05))
	if h < H and _in(a, 0.2, 0.75) and _in(d, 0.1, D - 0.15):
		return _enc(VoxelMat.PAPER, _j(VoxelArt.scale(c, 1.1), k, 0.05))
	return -1


# --- light fixtures with geometry -----------------------------------------------------

static func _fixture(g: VoxelGrid, l: Dictionary) -> void:
	var p: Vector2 = l["pos"]
	var h: float = l["height"]
	match l["kind"]:
		"table_lamp":
			_blob(g, p, 0.55, 0.65, 0.05, VoxelMat.CERAMIC, 0x50605f)
			_blob(g, p, 0.65, h + 0.1, 0.12, VoxelMat.GLOW, C["linen"])
		"hood":
			# range hood on the north wall above the stove, glowing underside
			for x in range(g.centre_range(0, p.x - 0.4, p.x + 0.4).x, g.centre_range(0, p.x - 0.4, p.x + 0.4).y):
				for z in range(g.centre_range(2, 0.15, 0.65).x, g.centre_range(2, 0.15, 0.65).y):
					for y in range(VoxelHouse.row_of(h), VoxelHouse.row_of(1.85)):
						var c: int = C["steel"]
						var m := VoxelMat.METAL + VoxelMat.TALL
						if y == VoxelHouse.row_of(h) and z > g.centre_range(2, 0.15, 0.65).x:
							m = VoxelMat.GLOW + VoxelMat.TALL
							c = 0xf2e2c0
						g.set_voxel(x, y, z, m, VoxelArt.jitter(c, x, y, z, 0.02), c, 0)
			for x in range(g.centre_range(0, p.x - 0.15, p.x + 0.15).x, g.centre_range(0, p.x - 0.15, p.x + 0.15).y):
				for z in range(g.centre_range(2, 0.15, 0.4).x, g.centre_range(2, 0.15, 0.4).y):
					for y in range(VoxelHouse.row_of(1.85), VoxelHouse.TOP_ROW + 1):
						g.set_voxel(x, y, z, VoxelMat.METAL + VoxelMat.TALL, VoxelArt.jitter(C["steel"], x, y, z, 0.02), 0, 0)
		"bare_bulb":
			var c := g.cell_of(Vector3(p.x, h, p.y))
			g.set_voxel(c.x, c.y, c.z, VoxelMat.GLOW + VoxelMat.TALL, 0xfff0c8, 0xfff0c8, 0)
			for y in range(c.y + 1, VoxelHouse.TOP_ROW + 1):
				g.set_voxel(c.x, y, c.z, VoxelMat.PLASTIC + VoxelMat.TALL, 0x1a1a1a, 0, 0)


static func _blob(g: VoxelGrid, p: Vector2, h0: float, h1: float, r: float, m: int, c: int) -> void:
	var xr := g.centre_range(0, p.x - r, p.x + r)
	var zr := g.centre_range(2, p.y - r, p.y + r)
	for x in range(xr.x, xr.y):
		for z in range(zr.x, zr.y):
			for y in range(VoxelHouse.row_of(h0), VoxelHouse.row_of(h1)):
				if g.get_mat(x, y, z) == VoxelMat.AIR:
					g.set_voxel(x, y, z, m, VoxelArt.jitter(c, x, y, z, 0.03), c, 0)
