class_name PoiExterior
extends RefCounted
## Experiment 009 (X): the surroundings of a generated place, as pure data
## (SPEC-009 "Exteriors"). PoiGenerator calls decorate(L, setup, rng) in its
## exterior stage with the building in L["bounds"] (Rect2) and its front
## entrances in L["doorways"] (points just outside each). It adds, in the
## PoiLayouts format:
##   props, containers   reusable exterior modules per archetype family (below),
##                       PropKit pieces (prop_gen_exterior.gd and the yard
##                       ones); collision only on large blockers; a few are
##                       searchable, with ids "ext_*" (a car, a shed, bins, a
##                       toolbox, a container...)
##   trees, story        pines; pallets, planks, rubble (PoiDressing)
##   lights              wall lights by the doors, a lamp post or two (some dead)
##   paint               ground patches PoiWorld draws into the snow:
##                       {rect, art: "asphalt"|"paving"|"line"} and trodden
##                       paths {pts: [Vector2], r, art: "trodden"}
##   car                 {rect, facing, cargo, door}: where Eli's car stands
##                       when he drove (near the main entrance; the boot at
##                       "cargo", "[E] Leave location" at "door")
##   entry, exits        the arrival point and the departure marker at the
##                       scene edge (on foot: "[E] Leave location")
##   edges, wander       where arrivals come in from the fog; outdoor walks
##   exit_kind           "dark" for apartments (G's L["dark_exit"]), else "edge"
##   ground              "snow" (residential, yards) or "lot"
## Every path from the entry to each front door, the departure marker, the
## car's boot and its door stays clear (reserved first, checked last by
## validate()); everything stays inside the walkable lot (HousePlan.YARD less
## a margin; PoiWorld's invisible bounds stand 0.3 m inside it). Deterministic
## for the rng. The hand-made layouts keep their own surroundings.
##
## Families (family_of: the archetype, else setup["family"]) and their modules:
##   residential  garden fence with a gate gap, mailbox, bushes by the house,
##                driveway, a small shed (searchable), pines, wheelie bins,
##                a car left in the street, snowbanks, a porch light
##   apartment    parking bays with cars, bins and a dumpster, entrance steps,
##                a bike rack, wall lights and a lamp post, a small courtyard
##                (benches, bushes, a bare tree)
##   commercial   a parking lot with lines, cars and a wreck, a shop sign,
##                shopping trolleys, a delivery area (loading door, pallets,
##                a dumpster, a van), lamp posts
##   industrial   a mesh fence, shipping containers, scrap, barrels, pallets,
##                a generator and a forklift, a loading door, a wreck, a toolbox
##   medical      an ambulance by the entrance, an emergency sign, benches,
##                direction signs, medical waste bins, a few parked cars
##   police       police cars, a fenced yard with a garage, barriers, an
##                equipment container (locked), a sign
##   yard         a fenced site around the hut: containers, pallets and planks,
##                scrap, barrels, a generator, a portable toilet, a toolbox

const LOT := Rect2(-6.4, -5.4, 26.8, 19.8)     ## HousePlan.YARD.grow(-0.6)
const CELL := 0.5
const FREE := 0
const BLOCKED := 1
const RESERVED := 2                ## a kept-clear path (walkable)
const DECOR := 3                   ## something low stands here (walkable)

const FAMILIES := ["residential", "apartment", "commercial", "industrial", "medical", "police", "yard"]
const ARCHETYPE_FAMILY := {
	"house_small": "residential", "house_family": "residential", "cottage": "residential", "house": "residential",
	"apartment": "apartment",
	"supermarket": "commercial", "diner": "commercial", "pharmacy": "commercial", "office": "commercial", "shop": "commercial",
	"workshop": "industrial", "garage": "industrial", "warehouse": "industrial", "factory": "industrial",
	"yard": "yard",
	"hospital": "medical", "clinic_small": "medical", "clinic": "medical",
	"police": "police", "range": "police", "fire_station": "police",
}
const SETUP_FAMILY := {"residential": "residential", "commercial": "commercial", "light_industry": "industrial",
	"light industry": "industrial", "industrial": "industrial", "outdoor_industrial": "yard", "outdoor industrial": "yard",
	"public": "medical"}
## Plan sizes (w across the front, h, d) of the yard pieces used here; the
## ext_* pieces take PropKit's (prop_gen_exterior.gd).
const SIZES := {"mailbox": Vector3(0.3, 1.2, 0.3), "bush": Vector3(1.2, 0.9, 1.0), "dead_tree": Vector3(0.6, 4.5, 0.6),
	"streetlight_dead": Vector3(0.25, 4.5, 0.25), "step": Vector3(1.6, 0.15, 0.6), "trash_bin_tipped": Vector3(0.6, 0.6, 0.9)}
## Pieces that never get collision (low, or walked around by feel).
const NO_BLOCK := ["bush", "step", "ext_snowbank", "ext_trolley", "ext_toolbox", "ext_bin", "ext_medwaste", "ext_bench",
	"ext_bike_rack", "ext_pallets", "ext_barrels", "ext_sign_dir", "trash_bin_tipped", "ext_roller_door"]
const FOOD_JUNK := ["food", "water", "utility", "material"]
const CAR_JUNK := ["food", "water", "utility", "tool", "medical"]
const GEAR := ["ammo", "protective", "utility", "weapon", "medical"]
const WARM := 0xffd9a0
const COLD := 0xdfe8ff


class Site:
	var L: Dictionary
	var rng: RandomNumberGenerator
	var family := "residential"
	var arch := ""
	var B := Rect2()
	var doors: Array = []
	var main := Vector2.ZERO
	var grid := PackedByteArray()
	var nx := 0
	var nz := 0
	var count := {}
	var trails: Array = []          ## [Array of Vector2]: the kept-clear walks (trodden snow)


# --- the entry point -----------------------------------------------------------------------

static func family_of(L: Dictionary, setup := {}) -> String:
	var a := str(L.get("archetype", setup.get("archetype", "")))
	if ARCHETYPE_FAMILY.has(a):
		return ARCHETYPE_FAMILY[a]
	var f := str(setup.get("family", "")).to_lower()
	if f in FAMILIES:
		return f
	return str(SETUP_FAMILY.get(f, "residential"))


## Adds the surroundings to L (see the header). setup: DailySites.setup (its
## "archetype" / "family" are read when L has none).
static func decorate(L: Dictionary, setup: Dictionary, rng: RandomNumberGenerator) -> void:
	var S := Site.new()
	S.L = L
	S.rng = rng
	S.arch = str(L.get("archetype", setup.get("archetype", "")))
	S.family = family_of(L, setup)
	for k in ["props", "containers", "trees", "story", "lights", "paint", "wander"]:
		if not (L.get(k) is Array):
			L[k] = []
	S.B = L.get("bounds", Rect2()) if L.get("bounds") is Rect2 else Rect2()
	if S.B.size == Vector2.ZERO:
		S.B = walls_rect(L)
	if S.B.size == Vector2.ZERO:
		S.B = Rect2(3, 2, 8, 6)
	for d in L.get("doorways", []):
		if d is Vector2 and LOT.has_point(d):
			S.doors.append(d)
	if S.doors.is_empty():
		S.doors.append(Vector2(S.B.get_center().x, S.B.end.y + 0.7))
	S.main = S.doors[0]
	for d in S.doors:
		if d.y > S.main.y + 0.01 or (absf(d.y - S.main.y) <= 0.01 and absf(d.x - S.B.get_center().x) < absf(S.main.x - S.B.get_center().x)):
			S.main = d
	_build_grid(S)
	_arrival(S)
	_park(S)
	_ground(S)
	L["exit_kind"] = "dark" if (S.family == "apartment" and L.get("dark_exit") is Rect2) or str(L.get("exit_kind", "")) == "dark" else "edge"
	match S.family:
		"apartment":
			_apartment(S)
		"commercial":
			_commercial(S)
		"industrial":
			_industrial(S)
		"medical":
			_medical(S)
		"police":
			_police(S)
		"yard":
			_yard(S)
		_:
			_residential(S)
	_snowbanks(S, 2 + rng.randi() % 3)
	for t in S.trails:
		L["paint"].append({"pts": t, "r": 0.55, "art": "trodden"})
	_edges_and_wander(S)
	# anything searchable that ended up out of reach goes (its piece with it)
	var bad := unreachable_containers(L)
	if not bad.is_empty():
		L["containers"] = (L["containers"] as Array).filter(func(c): return not (str(c["id"]) in bad))


# --- the grid ------------------------------------------------------------------------------

static func walls_rect(L: Dictionary) -> Rect2:
	var out := Rect2()
	var first := true
	for w in L.get("walls", []):
		var a: Vector2 = w["a"]
		var b: Vector2 = w["b"]
		var r := Rect2(a.min(b), (b - a).abs())
		out = r if first else out.merge(r)
		first = false
	return out


static func _cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor((p.x - LOT.position.x) / CELL)), int(floor((p.y - LOT.position.y) / CELL)))


static func _centre(c: Vector2i) -> Vector2:
	return LOT.position + (Vector2(c) + Vector2(0.5, 0.5)) * CELL


static func _inside(S: Site, c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < S.nx and c.y < S.nz


static func _at(S: Site, c: Vector2i) -> int:
	return S.grid[c.y * S.nx + c.x] if _inside(S, c) else BLOCKED


static func _set_cell(S: Site, c: Vector2i, v: int) -> void:
	if _inside(S, c):
		S.grid[c.y * S.nx + c.x] = v


## The cells r overlaps (overlap), or those whose centres lie in r; at least
## the one holding its middle.
static func _cells(S: Site, r: Rect2, overlap := true) -> Array:
	var out := []
	var a := _cell(r.position)
	var b := _cell(r.end)
	for j in range(maxi(a.y, 0), mini(b.y, S.nz - 1) + 1):
		for i in range(maxi(a.x, 0), mini(b.x, S.nx - 1) + 1):
			var c := Vector2i(i, j)
			if overlap:
				var cr := Rect2(_centre(c) - Vector2(CELL, CELL) * 0.5, Vector2(CELL, CELL))
				if cr.intersects(r) and cr.intersection(r).get_area() > 0.0004:
					out.append(c)
			elif r.has_point(_centre(c)):
				out.append(c)
	if out.is_empty() and _inside(S, _cell(r.get_center())):
		out.append(_cell(r.get_center()))
	return out


static func _mark(S: Site, r: Rect2, v: int, overlap := true) -> void:
	for c in _cells(S, r, overlap):
		var now := _at(S, c)
		if v == BLOCKED or now == FREE or (v == RESERVED and now == DECOR):
			_set_cell(S, c, v)


static func _blank_grid(S: Site) -> void:
	S.nx = int(ceil(LOT.size.x / CELL))
	S.nz = int(ceil(LOT.size.y / CELL))
	S.grid.resize(S.nx * S.nz)
	S.grid.fill(FREE)


## The building and whatever already stands outside it block; the walls and
## pieces of the building itself are inside its bounds.
static func _build_grid(S: Site) -> void:
	_blank_grid(S)
	_mark(S, S.B.grow(0.25), BLOCKED, false)
	_mark_layout(S, S.L)


static func _mark_layout(S: Site, L: Dictionary, overlap := true) -> void:
	for p in L.get("props", []):
		_mark(S, p["rect"], BLOCKED if p.get("block", true) else DECOR, overlap)
	for c in L.get("containers", []):
		_mark(S, c["rect"], BLOCKED, overlap)
	for t in L.get("trees", []):
		_mark(S, Rect2(t - Vector2(0.3, 0.3), Vector2(0.6, 0.6)), BLOCKED, overlap)


## Cells along a walk from a to b (8 ways, no corner cutting) over anything
## but BLOCKED; [] when there is none. The end cells count as open.
static func _path(S: Site, a: Vector2, b: Vector2) -> Array:
	var s := _cell(a)
	var g := _cell(b)
	if not _inside(S, s) or not _inside(S, g):
		return []
	var prev := {s: s}
	var q := [s]
	var head := 0
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		if c == g:
			break
		for d in dirs:
			var n: Vector2i = c + d
			if prev.has(n) or not _inside(S, n):
				continue
			if n != g and _at(S, n) == BLOCKED:
				continue
			if d.x != 0 and d.y != 0 and (_at(S, Vector2i(c.x + d.x, c.y)) == BLOCKED or _at(S, Vector2i(c.x, c.y + d.y)) == BLOCKED):
				continue
			prev[n] = c
			q.append(n)
	if not prev.has(g):
		return []
	var out := [g]
	var c2: Vector2i = g
	while c2 != s:
		c2 = prev[c2]
		out.push_front(c2)
	return out


## Keeps a walk clear: its cells and a ring around them (about 1.5 m wide).
static func _reserve(S: Site, cells: Array, ring := 1) -> void:
	for c in cells:
		for dj in range(-ring, ring + 1):
			for di in range(-ring, ring + 1):
				var n: Vector2i = c + Vector2i(di, dj)
				if _at(S, n) != BLOCKED:
					_set_cell(S, n, RESERVED)


static func _reserve_disc(S: Site, p: Vector2, r: float) -> void:
	for c in _cells(S, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0)):
		if _centre(c).distance_to(p) <= r and _at(S, c) != BLOCKED:
			_set_cell(S, c, RESERVED)


static func _trail(S: Site, cells: Array) -> void:
	var pts := []
	for i in cells.size():
		if i % 2 == 0 or i == cells.size() - 1:
			pts.append(_centre(cells[i]))
	if pts.size() >= 2:
		S.trails.append(pts)


# --- arrival, the departure marker, the car ------------------------------------------------

static func _arrival(S: Site) -> void:
	var L := S.L
	var B := S.B
	var cands := []
	var south := LOT.end.y - B.end.y
	var west := B.position.x - LOT.position.x
	var east := LOT.end.x - B.end.x
	var off := 2.5 if S.rng.randf() < 0.5 else -2.5
	var sx := clampf(S.main.x + off, LOT.position.x + 1.0, LOT.end.x - 1.0)
	var s_pt := Vector2(sx, LOT.end.y - 0.45)
	var w_pt := Vector2(LOT.position.x + 0.45, clampf(S.main.y + 1.0, LOT.position.y + 1.0, LOT.end.y - 1.0))
	var e_pt := Vector2(LOT.end.x - 0.45, clampf(S.main.y + 1.0, LOT.position.y + 1.0, LOT.end.y - 1.0))
	if south >= 3.0:
		cands.append(s_pt)
	if west >= east:
		cands.append_array([w_pt, e_pt])
	else:
		cands.append_array([e_pt, w_pt])
	if south < 3.0:
		cands.append(s_pt)
	cands.append(Vector2(clampf(S.main.x, LOT.position.x + 1.0, LOT.end.x - 1.0), LOT.position.y + 0.45))
	var out := Vector2.INF
	var walk := []
	for c in cands:
		walk = _path(S, c, S.main)
		if not walk.is_empty():
			out = c
			break
	if out == Vector2.INF:
		out = s_pt
		walk = [_cell(s_pt), _cell(S.main)]
	# the entry: about 1.5 m in from the marker, on the walk to the door
	var entry := _centre(walk[mini(3, walk.size() - 1)])
	L["exits"] = [out]
	L["entry"] = entry
	_reserve(S, walk)
	_trail(S, walk)
	_reserve_disc(S, out, 1.0)
	_reserve_disc(S, entry, 1.0)
	for d in S.doors:
		_reserve_disc(S, d, 1.0)
		if d == S.main:
			continue
		var w2 := _path(S, entry, d)
		_reserve(S, w2)
		_trail(S, w2)


## The car's two use points: the boot behind its rear, the driver's door on
## its side (the side its mesh's open door is on, else the other side).
static func car_points(rect: Rect2, facing: String, other_side := false) -> Dictionary:
	var f: Vector2 = PoiLayouts.FRONT.get(facing, Vector2(1, 0))
	var c := rect.get_center()
	var long := maxf(rect.size.x, rect.size.y)
	var wide := minf(rect.size.x, rect.size.y)
	var side := Vector2(-f.y, f.x)            # E -> S, W -> N, N -> E, S -> W: where the car mesh's door hangs open
	if other_side:
		side = -side
	return {"cargo": c - f * (long * 0.5 + 0.45), "door": c + side * (wide * 0.5 + 0.65) + f * 0.2}


## A parking spot near the main entrance for Eli's car (empty when he walked).
## With no room at all the layout gets no car spot ({}): PoiWorld then keeps
## the departure markers even when he drove.
static func _park(S: Site) -> void:
	var L := S.L
	var entry: Vector2 = L["entry"]
	var want := Vector2(S.main.x + (3.6 if S.main.x < S.B.get_center().x + 0.01 else -3.6), S.main.y + 2.4)
	var start := _cell(want)
	for pass_i in 2:
		var clear := 0.3 if pass_i == 0 else 0.0
		var allow := [FREE, DECOR] if pass_i == 0 else [FREE, DECOR, RESERVED]
		for ring in 22:
			var cells := _ring(start, ring)
			_shuffle(S, cells)
			for c in cells:
				if _at(S, c) == BLOCKED:
					continue
				var at := _centre(c)
				var rect := Rect2(at.x - 2.2, at.y - 1.0, 4.4, 2.0)
				if not _free_rect(S, rect.grow(clear), allow):
					continue
				for facing in ["E", "W"]:
					for other in [false, true]:
						var pts := car_points(rect, facing, other)
						if not _walkable(S, pts["cargo"]) or not _walkable(S, pts["door"]):
							continue
						var keep := S.grid.duplicate()
						_mark(S, rect, BLOCKED)
						var p1 := _path(S, entry, pts["cargo"])
						var p2 := _path(S, entry, pts["door"])
						var cut := false
						for d in S.doors:
							cut = cut or _path(S, entry, d).is_empty()
						for e in L["exits"]:
							cut = cut or _path(S, entry, e).is_empty()
						if p1.is_empty() or p2.is_empty() or cut:
							S.grid = keep
							continue
						_reserve(S, p1, 0)
						_reserve(S, p2, 0)
						_reserve_disc(S, pts["cargo"], 0.7)
						_reserve_disc(S, pts["door"], 0.7)
						L["car"] = {"rect": rect, "facing": facing, "cargo": pts["cargo"], "door": pts["door"]}
						if S.family == "residential":
							# the driveway: from the car down to the street, kept clear
							var drive := Rect2(rect.position.x - 0.3, rect.position.y - 0.3, rect.size.x + 0.6, LOT.end.y - rect.position.y + 0.3)
							L["paint"].append({"rect": drive, "art": "paving"})
							_mark(S, drive, RESERVED)
						return
	L["car"] = {}


static func _walkable(S: Site, p: Vector2) -> bool:
	return LOT.grow(-0.2).has_point(p) and _at(S, _cell(p)) != BLOCKED


static func _free_rect(S: Site, r: Rect2, allow: Array) -> bool:
	if not LOT.encloses(r):
		return false
	for c in _cells(S, r):
		if not (_at(S, c) in allow):
			return false
	return true


static func _ring(c: Vector2i, k: int) -> Array:
	if k == 0:
		return [c]
	var out := []
	for i in range(-k, k + 1):
		out.append(c + Vector2i(i, -k))
		out.append(c + Vector2i(i, k))
	for j in range(-k + 1, k):
		out.append(c + Vector2i(-k, j))
		out.append(c + Vector2i(k, j))
	return out


static func _shuffle(S: Site, a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := S.rng.randi() % (i + 1)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t


# --- placing pieces ------------------------------------------------------------------------

static func size_of(type: String) -> Vector3:
	return SIZES.get(type, PropKit.default_size(type))


## The plan rect of `type` centred at c, its front toward `facing`.
static func rect_of(type: String, c: Vector2, facing: String, size := Vector3.ZERO) -> Rect2:
	var s := size if size != Vector3.ZERO else size_of(type)
	var ns := facing == "N" or facing == "S"
	var w := s.x if ns else s.z
	var d := s.z if ns else s.x
	return Rect2(c.x - w * 0.5, c.y - d * 0.5, w, d)


## Places `type` at c if its spot is free (opts: "size", "block", "margin",
## "box": container fields, "on_path": may stand on a kept-clear walk).
## Returns the rect, or Rect2() when it doesn't fit.
static func _put(S: Site, type: String, c: Vector2, facing: String, opts := {}) -> Rect2:
	var s: Vector3 = opts.get("size", size_of(type))
	var r := rect_of(type, c, facing, s)
	var block: bool = opts.get("block", not (type in NO_BLOCK))
	if opts.get("force", false):
		S.L["props"].append({"type": type, "rect": r, "facing": facing, "h": s.y, "block": block})
		return r
	var allow := [FREE, RESERVED] if opts.get("on_path", false) else [FREE]
	if not _free_rect(S, r.grow(float(opts.get("margin", 0.15))), allow):
		return Rect2()
	var box: Variant = opts.get("box")
	if box is Dictionary:
		var fp := PoiLayouts.front_point(r, facing)
		if not _walkable(S, fp) or _at(S, _cell(fp)) == DECOR:
			return Rect2()
	_mark(S, r, BLOCKED if block or box is Dictionary else DECOR)
	if box is Dictionary:
		var b: Dictionary = box
		var e := {"id": _uid(S, str(b.get("id", "ext_box"))), "type": type, "rect": r, "facing": facing, "h": s.y,
			"label": str(b.get("label", "box")), "holds": b.get("holds", []), "weight": float(b.get("weight", 0.8)),
			"table": str(b.get("table", "loot")), "picked": b.get("picked", false) == true, "needs": str(b.get("needs", "")),
			"noise": int(b.get("noise", 1)), "secs": float(b.get("secs", 2.0)), "minutes": int(b.get("minutes", 8)), "room": ""}
		S.L["containers"].append(e)
		_reserve_disc(S, PoiLayouts.front_point(r, facing), 0.45)
	else:
		S.L["props"].append({"type": type, "rect": r, "facing": facing, "h": s.y, "block": block})
	return r


## Finds a free spot for `type` in `zone`, nearest `near` first (rings of
## cells, shuffled per ring by the rng), trying each of `facings`.
static func _find(S: Site, type: String, zone: Rect2, near: Vector2, facings: Array, opts := {}, max_ring := 26) -> Rect2:
	if zone.size.x <= 0.0 or zone.size.y <= 0.0:
		return Rect2()
	var start := _cell(near)
	for k in max_ring:
		var cells := _ring(start, k)
		_shuffle(S, cells)
		for c in cells:
			var at := _centre(c)
			if not zone.has_point(at):
				continue
			for f in facings:
				var r := _put(S, type, at, f, opts)
				if r.size != Vector2.ZERO:
					return r
	return Rect2()


static func _uid(S: Site, base: String) -> String:
	var n := int(S.count.get(base, 0))
	S.count[base] = n + 1
	return base if n == 0 else "%s_%d" % [base, n + 1]


static func _pine(S: Site, zone: Rect2, near: Vector2) -> bool:
	var start := _cell(near)
	for k in 14:
		var cells := _ring(start, k)
		_shuffle(S, cells)
		for c in cells:
			var at := _centre(c) + Vector2(S.rng.randf_range(-0.15, 0.15), S.rng.randf_range(-0.15, 0.15))
			if not zone.has_point(at) or at.y > S.B.end.y + 0.5:
				continue                # none to the south (between the camera and Eli)
			var r := Rect2(at - Vector2(1.0, 1.0), Vector2(2.0, 2.0))
			if not _free_rect(S, r, [FREE, DECOR]):
				continue
			S.L["trees"].append(at)
			_mark(S, Rect2(at - Vector2(0.3, 0.3), Vector2(0.6, 0.6)), BLOCKED)
			_mark(S, r, DECOR)
			return true
	return false


static func _light(S: Site, at: Vector2, h: float, kind: String, color: int, energy: float, flicker := false, yaw := 0.0, rng_range := 5.0) -> void:
	S.L["lights"].append({"at": at, "h": h, "kind": kind, "color": color, "energy": energy, "flicker": flicker, "yaw": yaw, "range": rng_range})


## A wall light just outside a doorway, on the wall it opens through, facing out.
static func _door_light(S: Site, d: Vector2, color: int, energy: float, flicker := false) -> void:
	var B := S.B
	var ds := [absf(d.y - B.end.y), absf(d.y - B.position.y), absf(d.x - B.position.x), absf(d.x - B.end.x)]
	var side := ds.find(ds.min())
	var at := d
	var yaw := 0.0
	match side:
		0:
			at = Vector2(d.x + 0.9, B.end.y + 0.32)
		1:
			at = Vector2(d.x + 0.9, B.position.y - 0.32)
			yaw = PI
		2:
			at = Vector2(B.position.x - 0.32, d.y - 0.9)
			yaw = -PI * 0.5
		3:
			at = Vector2(B.end.x + 0.32, d.y - 0.9)
			yaw = PI * 0.5
	_light(S, at, 2.3, "emergency", color, energy, flicker, yaw, 5.5)


## A lamp post (its head reaches 0.7 m toward its front); lit or dead.
static func _lamp(S: Site, zone: Rect2, near: Vector2, lit: bool) -> void:
	var facing := "S" if near.y < S.B.get_center().y else "N"
	var r := _find(S, "ext_lamp_post", zone, near, [facing], {"block": true, "margin": 0.3})
	if r.size == Vector2.ZERO:
		return
	if lit:
		var head: Vector2 = r.get_center() + PoiLayouts.FRONT[facing] * 0.7
		_light(S, head, 3.95, "bulb", COLD if S.rng.randf() < 0.5 else WARM, 1.4, S.rng.randf() < 0.4, 0.0, 7.5)


## The zones around the building, clipped to the lot.
static func _zones(S: Site) -> Dictionary:
	var B := S.B
	return {
		"front": Rect2(LOT.position.x, B.end.y + 0.3, LOT.size.x, LOT.end.y - B.end.y - 0.3),
		"back": Rect2(LOT.position.x, LOT.position.y, LOT.size.x, B.position.y - 0.3 - LOT.position.y),
		"west": Rect2(LOT.position.x, LOT.position.y, B.position.x - 0.3 - LOT.position.x, LOT.size.y),
		"east": Rect2(B.end.x + 0.3, LOT.position.y, LOT.end.x - B.end.x - 0.3, LOT.size.y),
		"all": LOT,
	}


## The roomier of the two sides (west/east), and its middle.
static func _side(S: Site) -> String:
	return "west" if S.B.position.x - LOT.position.x >= LOT.end.x - S.B.end.x else "east"


static func _side_anchor(S: Site, side: String, y_frac := 0.5) -> Vector2:
	var z: Rect2 = _zones(S)[side]
	return Vector2(z.get_center().x, lerpf(S.B.position.y, S.B.end.y, y_frac))


static func _back_anchor(S: Site, x_frac := 0.5) -> Vector2:
	return Vector2(lerpf(S.B.position.x, S.B.end.x, x_frac), S.B.position.y - 1.6)


static func _front_anchor(S: Site, x_frac := 0.5, out := 2.2) -> Vector2:
	return Vector2(lerpf(S.B.position.x, S.B.end.x, x_frac), S.B.end.y + out)


## A line of fence from a to b (axis-aligned), in pieces of about `seg` m,
## with gaps wherever something else is or a walk is kept clear.
static func _fence_line(S: Site, a: Vector2, b: Vector2, type: String, seg := 2.4) -> int:
	var horiz := absf(a.y - b.y) < 0.01
	var length := absf(b.x - a.x) if horiz else absf(b.y - a.y)
	var n := maxi(1, int(round(length / seg)))
	var step := length / float(n)
	var sz := Vector3(step - 0.02, size_of(type).y, 0.2)
	var facing := "S" if horiz else "E"
	# all the pieces are checked against the grid as it was, so neighbours don't stop each other
	var ok := []
	for i in n:
		var c := a + (b - a).normalized() * (float(i) * step + step * 0.5)
		if _free_rect(S, rect_of(type, c, facing, sz).grow(-0.05), [FREE, DECOR]):
			ok.append(c)
	for c in ok:
		var r := _put(S, type, c, facing, {"size": sz, "block": true, "force": true})
		_mark(S, r, BLOCKED)
	return ok.size()


## Parking bays (2.6 x 5 m, painted, cars nose in) near `near`, one per
## entry of `kinds` (a vehicle type, "" = an empty bay), each next to the
## last where there is room; the `searchable` one is an "ext_car" container.
## Returns how many cars stand there.
static func _parking(S: Site, zone: Rect2, near: Vector2, kinds: Array, searchable := -1) -> int:
	var cars := 0
	var at := near
	var across: bool = zone.size.x >= zone.size.y or zone == _zones(S)["front"]   # bays side by side along x
	for i in kinds.size():
		var bay := _bay(S, zone, at, across, 12 if i > 0 else 30)
		if bay.size == Vector2.ZERO and i > 0:
			bay = _bay(S, zone, near, across, 30)
		if bay.size == Vector2.ZERO:
			break
		at = bay.get_center() + (Vector2(2.6, 0) if across else Vector2(0, 2.6))
		var t: String = kinds[i]
		if t == "":
			continue
		var c := bay.get_center() + Vector2(S.rng.randf_range(-0.12, 0.12), S.rng.randf_range(-0.12, 0.12))
		var facing: String = (["N", "S"] if across else ["E", "W"])[S.rng.randi() % 2]
		var opts := {"margin": -0.2, "on_path": true}
		if i == searchable:
			opts["box"] = {"id": "ext_car", "label": "abandoned car" if t != "ext_police" else "police car",
				"holds": CAR_JUNK if t != "ext_police" else GEAR, "weight": 0.7, "secs": 2.4, "minutes": 8}
		if _put(S, t, c, facing, opts).size != Vector2.ZERO:
			cars += 1
		elif opts.has("box") and _put(S, t, c, facing, {"margin": -0.2, "on_path": true}).size != Vector2.ZERO:
			cars += 1
	return cars


## One free bay (asphalt, a line each side) as RESERVED ground (a car may
## stand on it; nothing else does), or Rect2().
static func _bay(S: Site, zone: Rect2, near: Vector2, across: bool, max_ring := 12) -> Rect2:
	var size := Vector2(2.6, 5.0) if across else Vector2(5.0, 2.6)
	var start := _cell(near)
	for k in max_ring:
		var cells := _ring(start, k)
		_shuffle(S, cells)
		for c in cells:
			var at := _centre(c)
			if not zone.has_point(at) or _at(S, c) != FREE:
				continue
			var r := Rect2(at - size * 0.5, size)
			if not _free_rect(S, r.grow(0.1), [FREE]):
				continue
			S.L["paint"].append({"rect": r.grow(0.15), "art": "asphalt"})
			for e in ([r.position.x, r.end.x] if across else [r.position.y, r.end.y]):
				S.L["paint"].append({"rect": Rect2(e - 0.05, r.position.y + 0.3, 0.1, r.size.y - 0.6) if across else Rect2(r.position.x + 0.3, e - 0.05, r.size.x - 0.6, 0.1), "art": "line"})
			_mark(S, r, RESERVED)
			return r
	return Rect2()


## The street along the south edge Eli comes by (it runs on into the fog),
## a sidewalk around buildings that have one.
static func _ground(S: Site) -> void:
	var L := S.L
	L["ground"] = "snow"
	var road := Rect2(-40.0, LOT.end.y - 0.7, 100.0, 7.0)
	L["paint"].append({"rect": road, "art": "asphalt"})
	var x := -14.0
	while x < 30.0:
		L["paint"].append({"rect": Rect2(x, road.position.y + 3.4, 2.0, 0.12), "art": "line"})
		x += 4.5
	if not (S.family in ["residential", "yard"]):
		L["paint"].append({"rect": S.B.grow(1.2), "art": "paving"})


static func _snowbanks(S: Site, n: int) -> void:
	var z: Dictionary = _zones(S)
	var spots := [Vector2(LOT.position.x + 1.5, LOT.end.y - 1.0), Vector2(LOT.end.x - 1.5, LOT.end.y - 1.0),
		Vector2(LOT.position.x + 1.2, LOT.position.y + 1.2), Vector2(LOT.end.x - 1.2, LOT.position.y + 1.2),
		_front_anchor(S, 0.1, 1.2), _front_anchor(S, 0.9, 1.2)]
	_shuffle(S, spots)
	for i in mini(n, spots.size()):
		_find(S, "ext_snowbank", z["all"], spots[i], ["N", "E"], {"margin": 0.1}, 8)


static func _edges_and_wander(S: Site) -> void:
	var L := S.L
	var entry: Vector2 = L["entry"]
	var cand := [Vector2(LOT.position.x, LOT.position.y + LOT.size.y * S.rng.randf_range(0.15, 0.4)),
		Vector2(LOT.position.x, LOT.position.y + LOT.size.y * S.rng.randf_range(0.6, 0.9)),
		Vector2(LOT.end.x, LOT.position.y + LOT.size.y * S.rng.randf_range(0.15, 0.4)),
		Vector2(LOT.end.x, LOT.position.y + LOT.size.y * S.rng.randf_range(0.6, 0.9)),
		Vector2(LOT.position.x + LOT.size.x * S.rng.randf_range(0.2, 0.8), LOT.position.y),
		Vector2(LOT.position.x + LOT.size.x * S.rng.randf_range(0.2, 0.8), LOT.end.y)]
	var edges := []
	for p in cand:
		if p.distance_to(entry) >= 6.0 and _at(S, _cell(p.clamp(LOT.position + Vector2(0.1, 0.1), LOT.end - Vector2(0.1, 0.1)))) != BLOCKED:
			edges.append(p)
	if edges.size() < 3:
		edges = PoiLayouts.EDGES.duplicate()
	L["edges"] = edges
	var wander := []
	for k in ["front", "back", "west", "east"]:
		var r: Rect2 = _zones(S)[k]
		if r.size.x >= 1.6 and r.size.y >= 1.6:
			wander.append(r.grow(-0.4))
	L["wander"] = (L.get("wander", []) as Array) + wander


# --- the families ---------------------------------------------------------------------------

static func _residential(S: Site) -> void:
	var z := _zones(S)
	var rng := S.rng
	var B := S.B
	# the garden fence along the street, with gaps at the gate and the driveway
	var fy := LOT.end.y - 1.25
	if fy > B.end.y + 2.4:
		_fence_line(S, Vector2(maxf(B.position.x - 3.0, LOT.position.x + 0.2), fy), Vector2(minf(B.end.x + 3.0, LOT.end.x - 0.2), fy), "ext_fence_wood", 1.25)
		_find(S, "mailbox", z["front"], Vector2(S.main.x + 1.2, fy + 0.5), ["S"], {"block": false, "margin": 0.05}, 6)
	# bushes along the house front, between the doors
	for i in 2 + rng.randi() % 3:
		_find(S, "bush", z["front"], _front_anchor(S, rng.randf_range(0.05, 0.95), 0.9), ["S", "E"], {"margin": 0.05}, 4)
	# a small shed and the bins at the roomier side, pines behind
	var side := _side(S)
	if rng.randf() < 0.85:
		_find(S, "ext_shed", z[side] if (z[side] as Rect2).size.x >= 2.6 else z["back"], _side_anchor(S, side, 0.2),
			["S", "E", "W"], {"box": {"id": "ext_shed", "label": "garden shed", "holds": ["tool", "material", "utility"],
			"needs": "crowbar" if rng.randf() < 0.35 else "", "weight": 0.9, "secs": 2.4, "minutes": 10, "noise": 1}})
	var bins := 0
	for i in 2:
		var opts := {"margin": 0.05}
		if i == 0:
			opts["box"] = {"id": "ext_bins", "label": "wheelie bin", "holds": FOOD_JUNK, "weight": 0.4, "secs": 1.4, "minutes": 4}
		if _find(S, "ext_bin", z[side], _side_anchor(S, side, 0.75), ["S", "N"], opts, 10).size != Vector2.ZERO:
			bins += 1
	if bins == 0:
		_find(S, "trash_bin_tipped", z["front"], _front_anchor(S, 0.95, 1.2), ["W"], {}, 8)
	for i in 3 + rng.randi() % 4:
		var where: String = ["back", "back", "west", "east"][rng.randi() % 4]
		_pine(S, z[where], _back_anchor(S, rng.randf()) if where == "back" else _side_anchor(S, where, rng.randf_range(0.0, 0.6)))
	if rng.randf() < 0.5:
		_find(S, "dead_tree", z["back"], _back_anchor(S, rng.randf()), ["S"], {"block": true}, 10)
	# a car left in the street, sometimes still holding something
	if rng.randf() < 0.6:
		var opts := {"margin": 0.1}
		if rng.randf() < 0.6:
			opts["box"] = {"id": "ext_car", "label": "abandoned car", "holds": CAR_JUNK, "weight": 0.7, "secs": 2.4, "minutes": 8}
		_find(S, "ext_car" if rng.randf() < 0.75 else "ext_wreck", z["front"], Vector2(S.main.x + (6.0 if rng.randf() < 0.5 else -6.0), LOT.end.y - 1.6), ["E", "W"], opts, 16)
	if rng.randf() < 0.7:
		_door_light(S, S.main, WARM, 0.8, rng.randf() < 0.3)


static func _apartment(S: Site) -> void:
	var z := _zones(S)
	var rng := S.rng
	# steps at each entrance, a bike rack and the wall lights
	for d in S.doors:
		_entrance_steps(S, d)
		_door_light(S, d, COLD if rng.randf() < 0.6 else WARM, 0.9, rng.randf() < 0.35)
	_find(S, "ext_bike_rack", z["front"], S.main + Vector2(2.6, 0.6), ["S", "N"], {}, 8)
	# parking at the roomier side or the front
	var side := _side(S)
	var pz: Rect2 = z[side] if (z[side] as Rect2).size.x >= 5.6 else z["front"]
	var kinds := ["ext_car", "", "ext_car", "ext_wreck"]
	_shuffle(S, kinds)
	_parking(S, pz, _side_anchor(S, side, 0.6) if pz == z[side] else _front_anchor(S, 0.2, 3.5), kinds, kinds.find("ext_car"))
	# the bins
	_find(S, "ext_dumpster", z["all"], _side_anchor(S, "east" if side == "west" else "west", 0.3), ["S", "E", "W"],
		{"box": {"id": "ext_bins", "label": "dumpster", "holds": FOOD_JUNK, "weight": 0.5, "secs": 2.0, "minutes": 6}}, 14)
	for i in 2:
		_find(S, "ext_bin", z["all"], _side_anchor(S, "east" if side == "west" else "west", 0.45), ["S"], {"margin": 0.05}, 10)
	# a small courtyard: benches, bushes, a bare tree
	var cy: Vector2 = _back_anchor(S, rng.randf_range(0.2, 0.8)) if (z["back"] as Rect2).size.y >= 3.0 else _front_anchor(S, 0.85, 2.6)
	var cz: Rect2 = z["back"] if (z["back"] as Rect2).size.y >= 3.0 else z["front"]
	_find(S, "ext_bench", cz, cy, ["S", "N"], {}, 8)
	_find(S, "ext_bench", cz, cy + Vector2(2.2, 0), ["S", "N"], {}, 8)
	for i in 2:
		_find(S, "bush", cz, cy + Vector2(rng.randf_range(-3, 3), rng.randf_range(-1, 1)), ["S"], {"margin": 0.05}, 8)
	_find(S, "dead_tree", cz, cy + Vector2(-2.4, 0), ["S"], {"block": true}, 8)
	_lamp(S, z["front"], _front_anchor(S, 0.0, 2.8), true)
	for i in 2:
		_pine(S, z["back"], _back_anchor(S, rng.randf()))


static func _entrance_steps(S: Site, d: Vector2) -> void:
	var B := S.B
	var ds := [absf(d.y - B.end.y), absf(d.y - B.position.y), absf(d.x - B.position.x), absf(d.x - B.end.x)]
	var side := ds.find(ds.min())
	var facing: String = ["S", "N", "W", "E"][side]
	var at: Vector2 = d + [Vector2(0, -0.35), Vector2(0, 0.35), Vector2(0.35, 0), Vector2(-0.35, 0)][side]
	_put(S, "step", at, facing, {"force": true, "block": false})


static func _commercial(S: Site) -> void:
	var z := _zones(S)
	var rng := S.rng
	var pharmacy := S.arch == "pharmacy"
	var shop := S.arch in ["supermarket", "pharmacy", "shop", ""]
	# the customer lot in front (or at the side when the front is narrow)
	var front: Rect2 = z["front"]
	var side := _side(S)
	var lot_zone: Rect2 = front if front.size.y >= 6.0 else z[side]
	var kinds := ["ext_car", "", "ext_wreck", "", "ext_car"]
	_shuffle(S, kinds)
	var car_x: float = (S.L["car"]["rect"] as Rect2).get_center().x if S.L["car"].get("rect") is Rect2 else S.main.x
	_parking(S, lot_zone, Vector2(S.main.x + (5.5 if car_x < S.main.x else -5.5), S.B.end.y + 3.0) if lot_zone == front else _side_anchor(S, side, 0.7),
		kinds, kinds.find("ext_car") if rng.randf() < 0.7 else -1)
	# the sign by the road, lamp posts (one still burning)
	var sign_type := "ext_sign_medical" if pharmacy else ("ext_sign_shop" if S.arch != "office" else "ext_sign_dir")
	_find(S, sign_type, front, Vector2(S.B.position.x - 0.5 if S.main.x > S.B.get_center().x else S.B.end.x + 0.5, LOT.end.y - 1.2), ["S"], {"margin": 0.2}, 14)
	_lamp(S, front, _front_anchor(S, 0.0, 3.4), true)
	_lamp(S, front, _front_anchor(S, 1.0, 3.4), false)
	if shop:
		for i in 2 + rng.randi() % 2:
			_find(S, "ext_trolley", front, S.main + Vector2(rng.randf_range(-5, 5), rng.randf_range(1.5, 3.5)), ["E", "N", "W"], {}, 10)
	for d in S.doors:
		_door_light(S, d, COLD, 0.9, rng.randf() < 0.4)
	# the delivery area at the back (or the other side)
	_delivery(S)


## A loading door on a blank stretch of wall with pallets, a dumpster and a van.
static func _delivery(S: Site) -> void:
	var z := _zones(S)
	var rng := S.rng
	var back: Rect2 = z["back"]
	var where := "back" if back.size.y >= 3.4 else ("east" if _side(S) == "west" else "west")
	var anchor := _back_anchor(S, 0.75) if where == "back" else _side_anchor(S, where, 0.25)
	_loading_door(S, where)
	_find(S, "ext_dumpster", z[where], anchor + Vector2(-2.5, 0), ["S", "N", "E", "W"],
		{"box": {"id": "ext_bins", "label": "dumpster", "holds": FOOD_JUNK, "weight": 0.5, "secs": 2.0, "minutes": 6}}, 14)
	for i in 2 + rng.randi() % 2:
		_find(S, "ext_pallets", z[where], anchor + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-0.5, 0.5)), ["N", "E"], {"size": Vector3(1.2, 0.15 * (2 + rng.randi() % 4), 1.0)}, 10)
	var opts := {"margin": 0.2}
	if rng.randf() < 0.5:
		opts["box"] = {"id": "ext_van", "label": "delivery van", "holds": ["food", "water", "material", "utility"], "weight": 0.9, "secs": 2.6, "minutes": 10}
	_find(S, "ext_van", z[where], anchor + Vector2(2.5, -0.5), ["E", "W", "N", "S"], opts, 16)


## A roller door against the outside of the building on a stretch without openings.
static func _loading_door(S: Site, where: String) -> void:
	var B := S.B
	var length := 3.0
	var along := []
	var horiz := where == "back"
	var line := B.position.y if horiz else (B.position.x if where == "west" else B.end.x)
	var lo := (B.position.x if horiz else B.position.y) + 0.6
	var hi := (B.end.x if horiz else B.end.y) - 0.6 - length
	var t := lo
	while t <= hi:
		along.append(t)
		t += 0.5
	_shuffle(S, along)
	for t0 in along:
		if not _wall_blank(S.L, horiz, line, t0 - 0.2, t0 + length + 0.2):
			continue
		var c := Vector2(t0 + length * 0.5, line - 0.16) if horiz else Vector2(line + (-0.16 if where == "west" else 0.16), t0 + length * 0.5)
		var facing := "N" if horiz else ("W" if where == "west" else "E")
		S.L["props"].append({"type": "ext_roller_door", "rect": rect_of("ext_roller_door", c, facing, Vector3(length, 2.5, 0.12)),
			"facing": facing, "h": 2.5, "block": false})
		return


## True when the walls on that line have no opening between a and b (and a wall is there).
static func _wall_blank(L: Dictionary, horiz: bool, line: float, a: float, b: float) -> bool:
	var covered := false
	for w in L.get("walls", []):
		var p: Vector2 = w["a"]
		var q: Vector2 = w["b"]
		var wh := is_equal_approx(p.y, q.y)
		if wh != horiz or absf((p.y if wh else p.x) - line) > 0.15:
			continue
		var lo := minf(p.x, q.x) if wh else minf(p.y, q.y)
		var hi := maxf(p.x, q.x) if wh else maxf(p.y, q.y)
		if lo > a or hi < b:
			continue
		covered = true
		for g in w.get("gaps", []):
			if float(g["from"]) < b and float(g["to"]) > a:
				return false
	return covered


static func _industrial(S: Site) -> void:
	var z := _zones(S)
	var rng := S.rng
	var B := S.B
	# a mesh fence along the back and down the sides
	if B.position.y - LOT.position.y >= 2.0:
		_fence_line(S, Vector2(LOT.position.x + 0.3, LOT.position.y + 0.3), Vector2(LOT.end.x - 0.3, LOT.position.y + 0.3), "ext_fence")
	for x in [LOT.position.x + 0.3, LOT.end.x - 0.3]:
		if absf(x - B.get_center().x) > B.size.x * 0.5 + 2.0:
			_fence_line(S, Vector2(x, LOT.position.y + 2.7), Vector2(x, LOT.end.y - 3.3), "ext_fence")
	# containers at the back and the roomier side
	var side := _side(S)
	var n_cont := 1 + rng.randi() % 3
	for i in n_cont:
		var where := "back" if i % 2 == 0 and (z["back"] as Rect2).size.y >= 3.0 else side
		var opts := {"margin": 0.3}
		if i == 0:
			opts["box"] = {"id": "ext_container", "label": "shipping container", "holds": ["material", "tool", "utility"],
				"needs": "crowbar" if rng.randf() < 0.5 else "", "weight": 1.0, "secs": 2.8, "minutes": 12, "noise": 2}
		_find(S, "ext_container", z[where], _back_anchor(S, rng.randf()) if where == "back" else _side_anchor(S, where, rng.randf_range(0.0, 0.6)),
			["E", "W"] if where == "back" else ["N", "S"], opts, 20)
	_loading_door(S, "back" if (z["back"] as Rect2).size.y >= 3.0 else ("east" if side == "west" else "west"))
	# the yard's clutter
	for t in ["ext_scrap", "ext_barrels", "ext_barrels", "ext_pallets", "ext_machine", "ext_forklift"]:
		var where: String = ["back", side, "front"][rng.randi() % 3] if t != "ext_forklift" else side
		var anchor := _back_anchor(S, rng.randf()) if where == "back" else (_side_anchor(S, where, rng.randf()) if where != "front" else _front_anchor(S, rng.randf(), 2.0))
		_find(S, t, z[where], anchor, ["N", "E", "S", "W"], {"margin": 0.2}, 14)
	_find(S, "ext_toolbox", z["all"], _side_anchor(S, side, 0.4), ["S", "E"],
		{"box": {"id": "ext_toolbox", "label": "toolbox", "holds": ["tool", "material"], "weight": 0.6, "secs": 1.4, "minutes": 4}}, 14)
	_find(S, "ext_wreck", z["front"], _front_anchor(S, 0.9 if S.main.x < B.get_center().x else 0.1, 3.0), ["E", "W"], {"margin": 0.2}, 14)
	_tell(S, "rubble", z["all"], _side_anchor(S, side, 0.9))
	for d in S.doors:
		_door_light(S, d, COLD, 0.8, rng.randf() < 0.5)
	_lamp(S, z["front"], _front_anchor(S, 0.5, 3.2), rng.randf() < 0.5)


static func _medical(S: Site) -> void:
	var z := _zones(S)
	var rng := S.rng
	# the ambulance bay by the main entrance and its sign
	var right := S.main.x <= S.B.get_center().x
	var opts := {"margin": 0.2}
	if rng.randf() < 0.6:
		opts["box"] = {"id": "ext_ambulance", "label": "ambulance", "holds": ["medical", "utility", "water"], "weight": 0.9, "secs": 2.6, "minutes": 10}
	_find(S, "ext_ambulance", z["front"], S.main + Vector2(4.2 if right else -4.2, 2.2), ["E", "W"], opts, 16)
	_find(S, "ext_sign_medical", z["front"], S.main + Vector2(-2.4 if right else 2.4, 1.0), ["S"], {"margin": 0.2}, 10)
	for i in 1 + rng.randi() % 2:
		_find(S, "ext_sign_dir", z["all"], S.main + Vector2(rng.randf_range(-4, 4), rng.randf_range(2.5, 4.5)), ["S", "E", "W"], {}, 10)
	for i in 2:
		_find(S, "ext_bench", z["front"], _front_anchor(S, 0.15 + 0.7 * i, 0.9), ["S"], {}, 8)
	for i in 2:
		_find(S, "bush", z["front"], _front_anchor(S, rng.randf(), 0.8), ["S"], {"margin": 0.05}, 6)
	# medical waste at the side, a few cars
	var side := _side(S)
	_find(S, "ext_medwaste", z[side], _side_anchor(S, side, 0.3), ["S", "E", "W"],
		{"box": {"id": "ext_medwaste", "label": "medical waste bin", "holds": ["medical"], "weight": 0.6, "secs": 1.6, "minutes": 5}}, 14)
	_find(S, "ext_medwaste", z[side], _side_anchor(S, side, 0.35), ["S"], {}, 10)
	var kinds := ["ext_car", "ext_car", ""]
	_shuffle(S, kinds)
	_parking(S, z[side] if (z[side] as Rect2).size.x >= 5.6 else z["front"], _side_anchor(S, side, 0.75), kinds, -1)
	for d in S.doors:
		_door_light(S, d, COLD, 1.0, rng.randf() < 0.3)
	_lamp(S, z["front"], _front_anchor(S, 0.5, 3.6), true)


static func _police(S: Site) -> void:
	var z := _zones(S)
	var rng := S.rng
	var fire := S.arch == "fire_station"
	var veh := "ext_van" if fire else "ext_police"
	# vehicles out front
	for i in 2:
		var opts := {"margin": 0.2}
		if i == 0 and rng.randf() < 0.5:
			opts["box"] = {"id": "ext_car", "label": "police car" if not fire else "service van", "holds": GEAR if not fire else ["medical", "tool", "utility"],
				"weight": 0.8, "secs": 2.4, "minutes": 8}
		_find(S, veh if i == 0 or not fire else "ext_ambulance", z["front"], _front_anchor(S, 0.2 + 0.6 * i, 3.0), ["E", "W"], opts, 16)
	# barriers along the front
	for i in 2 + rng.randi() % 2:
		_find(S, "ext_barrier", z["front"], _front_anchor(S, rng.randf(), rng.randf_range(4.0, 6.0)), ["S", "E"], {"margin": 0.1}, 10)
	if not fire:
		_find(S, "ext_sign_police", z["front"], S.main + Vector2(2.6, 1.2), ["S"], {"margin": 0.2}, 10)
	# the fenced yard at the roomier side: a garage and the equipment container
	var side := _side(S)
	var sz: Rect2 = z[side]
	if sz.size.x >= 4.5:
		var fx := sz.position.x + 0.2 if side == "west" else sz.end.x - 0.2
		_fence_line(S, Vector2(fx, maxf(S.B.position.y - 1.5, LOT.position.y + 0.3)), Vector2(fx, minf(S.B.end.y, LOT.end.y - 2.5)), "ext_fence")
		_find(S, "ext_garage", sz, _side_anchor(S, side, 0.3), ["S"], {"margin": 0.3}, 12)
	var where := "back" if (z["back"] as Rect2).size.y >= 3.2 else side
	_find(S, "ext_container", z[where], _back_anchor(S, 0.7) if where == "back" else _side_anchor(S, side, 0.8), ["E", "W", "N", "S"],
		{"margin": 0.3, "box": {"id": "ext_equipment", "label": "equipment container", "holds": GEAR, "needs": "crowbar",
		"table": "locked", "weight": 1.0, "secs": 2.8, "minutes": 12, "noise": 2}}, 20)
	for d in S.doors:
		_door_light(S, d, COLD, 1.0, rng.randf() < 0.3)
	_lamp(S, z["front"], _front_anchor(S, 1.0, 3.4), true)


static func _yard(S: Site) -> void:
	var z := _zones(S)
	var rng := S.rng
	var B := S.B
	# a site fence along the back and the far sides
	_fence_line(S, Vector2(LOT.position.x + 0.3, LOT.position.y + 0.3), Vector2(LOT.end.x - 0.3, LOT.position.y + 0.3), "ext_fence")
	for x in [LOT.position.x + 0.3, LOT.end.x - 0.3]:
		_fence_line(S, Vector2(x, LOT.position.y + 2.7), Vector2(x, LOT.end.y - 3.3), "ext_fence")
	# containers, materials, machines and the rest of a stopped site
	var side := _side(S)
	for i in 1 + rng.randi() % 2:
		var where := side if i == 0 else "back"
		var opts := {"margin": 0.3}
		if i == 0:
			opts["box"] = {"id": "ext_container", "label": "site container", "holds": ["material", "tool", "utility"],
				"needs": "crowbar" if rng.randf() < 0.5 else "", "weight": 1.0, "secs": 2.8, "minutes": 12, "noise": 2}
		_find(S, "ext_container", z[where], _side_anchor(S, side, 0.2) if where == side else _back_anchor(S, rng.randf()), ["N", "S", "E", "W"], opts, 20)
	for t in ["ext_pallets", "ext_pallets", "ext_scrap", "ext_barrels", "ext_machine", "ext_portaloo", "ext_barrier"]:
		var where: String = ["back", side, "front", "west", "east"][rng.randi() % 5]
		var anchor := _back_anchor(S, rng.randf()) if where == "back" else (_side_anchor(S, where, rng.randf()) if where != "front" else _front_anchor(S, rng.randf(), 2.5))
		_find(S, t, z[where], anchor, ["N", "E", "S", "W"], {"margin": 0.2}, 14)
	_find(S, "ext_toolbox", z["all"], S.main + Vector2(2.2, 1.6), ["S", "E", "W"],
		{"box": {"id": "ext_toolbox", "label": "toolbox", "holds": ["tool", "material"], "weight": 0.6, "secs": 1.4, "minutes": 4}}, 14)
	_tell(S, "planks", z["all"], _side_anchor(S, side, 0.6), {"n": 5 + rng.randi() % 5, "len": 2.4})
	_tell(S, "pallet", z["all"], _back_anchor(S, rng.randf()), {"load": "bags"})
	if rng.randf() < 0.5:
		_find(S, "ext_wreck", z["front"], _front_anchor(S, rng.randf(), 3.0), ["E", "W"], {"margin": 0.2}, 14)
	for i in 2:
		_pine(S, z["back"], _back_anchor(S, rng.randf()))
	_lamp(S, z["all"], _side_anchor(S, side, 1.0), rng.randf() < 0.6)
	for d in S.doors:
		if rng.randf() < 0.6:
			_door_light(S, d, WARM, 0.8, true)


## A story piece (PoiDressing) on a free patch near `near`.
static func _tell(S: Site, type: String, zone: Rect2, near: Vector2, opts := {}) -> void:
	var start := _cell(near)
	for k in 10:
		var cells := _ring(start, k)
		_shuffle(S, cells)
		for c in cells:
			var at := _centre(c)
			var r := Rect2(at - Vector2(1.2, 0.8), Vector2(2.4, 1.6))
			if zone.has_point(at) and _free_rect(S, r, [FREE]):
				var e := {"type": type, "at": at, "yaw": S.rng.randf_range(-0.4, 0.4)}
				for k2 in opts:
					e[k2] = opts[k2]
				S.L["story"].append(e)
				_mark(S, r, DECOR)
				return


# --- checks ---------------------------------------------------------------------------------

## The grid of a finished layout: the building (its bounds, else its walls)
## and every blocking piece outside it.
static func _grid_of(L: Dictionary) -> Site:
	var S := Site.new()
	S.L = L
	S.B = L.get("bounds", Rect2()) if L.get("bounds") is Rect2 else walls_rect(L)
	_blank_grid(S)
	if S.B.size != Vector2.ZERO:
		_mark(S, S.B.grow(0.25), BLOCKED, false)
	_mark_layout(S, L, false)
	var car: Variant = L.get("car")
	if car is Dictionary and (car as Dictionary).get("rect") is Rect2:
		_mark(S, car["rect"], BLOCKED, false)
	return S


## Problems with the outside of a finished layout ([] = none): the entry, the
## departure points, every front door, the car's boot and door and every
## outdoor container's front must be reachable from the entry outside the
## building, and every outside piece must stand inside the walkable lot.
static func validate(L: Dictionary) -> Array:
	var out := []
	var S := _grid_of(L)
	var entry: Vector2 = L.get("entry", Vector2.INF)
	if not LOT.has_point(entry):
		return ["the entry is off the lot"]
	var goals := {}
	for e in L.get("exits", []):
		goals["exit %s" % str(e)] = e
	for d in L.get("doorways", []):
		goals["doorway %s" % str(d)] = d
	var car: Variant = L.get("car")
	if car is Dictionary and not (car as Dictionary).is_empty():
		goals["the car's boot"] = car["cargo"]
		if (car as Dictionary).has("door"):
			goals["the car's door"] = car["door"]
		if not LOT.encloses(car["rect"]):
			out.append("the car stands off the lot")
	for c in L.get("containers", []):
		if str(c["id"]).begins_with("ext_"):
			goals["container %s" % c["id"]] = PoiLayouts.front_point(c["rect"], c["facing"])
	for k in goals:
		var p: Vector2 = goals[k]
		if not LOT.grow(0.3).has_point(p):
			out.append("%s is off the lot" % k)
		elif _path(S, entry, p).is_empty():
			out.append("%s can't be reached from the entry" % k)
	for p in L.get("props", []):
		if not S.B.encloses(p["rect"]) and not LOT.grow(0.05).encloses(p["rect"]):
			out.append("%s stands off the lot" % p["type"])
	return out


## Ids of outdoor containers whose front can't be reached from the entry.
static func unreachable_containers(L: Dictionary) -> Array:
	var S := _grid_of(L)
	var out := []
	var entry: Vector2 = L.get("entry", Vector2.INF)
	for c in L.get("containers", []):
		if str(c["id"]).begins_with("ext_") and _path(S, entry, PoiLayouts.front_point(c["rect"], c["facing"])).is_empty():
			out.append(str(c["id"]))
	return out
