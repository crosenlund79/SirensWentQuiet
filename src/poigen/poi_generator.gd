class_name PoiGenerator
extends RefCounted
## Experiment 009 (G): builds a POI layout on demand (SPEC-009 "Stage B")
## from a site setup (DailySites.setup or PoiArchetypes.default_setup), in
## the PoiLayouts dictionary format, so PoiWorld / PoiState / game_poi.gd play
## it unchanged. Pure data: no nodes. Deterministic for setup.seed (and
## setup.size): the same setup always gives the same building.
##
## The steps (the staged API runs one per step):
##   layout       the footprint (archetype w / d ranges by size) and the room
##                programme (required rooms, optional ones by chance)
##   rooms        the partition: rows of rooms front to back ("bands"), or a
##                front row and a corridor with rooms either side
##                ("corridor"), or a fenced yard with a site hut ("yard");
##                whole-metre walls; floors by room
##   doors        a door tree from the entrance room (rooms open off hubs:
##                corridors, hallways, halls; private rooms are dead ends;
##                open-plan neighbours get open gaps), the entrance and a back
##                door, windows on outside walls (none behind tall furniture),
##                the walls; the stash room's door locked sometimes
##   furniture    by room type and archetype (PoiFurniture, src/poigen/furniture_catalog.gd): pieces against
##                walls facing in, free-standing pieces with room round them,
##                gondola / rack rows; never in a doorway, never across a
##                door-to-door path, a clear space in front of what Eli uses;
##                the main stash first
##   containers   the searchable ones: labels and what they hold, some picked
##                clean, the location's locked table behind a lock, dark rooms
##                (a flashlight), at least MIN_CONTAINERS; loose pickups
##   inhabitants  dormant spots (SPEC: bang / tap by a wall or shelf, circle
##                round a table, a machine or a vehicle, sway / stare
##                anywhere), hiding places, wander areas, window peek spots,
##                doorways, lights left burning and signs of who was here
##   exterior     exit_kind ("dark" for apartments: the shared hallway's far
##                end, dark_exit; else "car"), then PoiExterior.decorate (X)
##                or a small fallback (entry, exits, car, edges, outdoor
##                wander outside the bounds)
## Then validate(L): everything must be reachable from the entry on a coarse
## grid; a failed seed retries with seed + 1 up to TRIES times, then a simple
## fallback (the old placeholder building with a stash).
##
## New layout keys (SPEC): bounds, archetype, stash, dormant, exit_kind,
## dark_exit, diag {seed, rooms, furniture, containers, stash_at, ms,
## attempts, archetype, version, fallback}; rooms carry "type".
##
## API: generate(setup) -> layout; begin(setup) -> Ctx (step() -> bool done,
## stage, progress 0..1, layout once done); validate(L) -> {ok, problems}.

const VERSION := 1
const SOUTH := 9                  ## the front wall's line (z); the building lies north of it
const MID_X := 7                  ## the building's middle (x)
const MAX_D := 12
const MIN_X := -3
const MAX_X := 17
const TRIES := 8
const CELL := 0.25
const BODY := 0.15                ## a body's half width for reachability
const NAV_RECT := Rect2(-7, -6, 28, 21)
const MIN_CONTAINERS := 5
const STAGES := [["layout", 0.08], ["rooms", 0.1], ["doors", 0.14], ["furniture", 0.3], ["containers", 0.1], ["inhabitants", 0.18], ["exterior", 0.1]]
const STAGE_TEXT := {"layout": "Pacing out the building", "rooms": "Walls and rooms", "doors": "Doors and windows",
	"furniture": "Furniture", "containers": "What was left behind", "inhabitants": "Who is still there", "exterior": "Outside",
	"done": "Ready"}
## Rooms a back door may open from.
const BACK_OK := ["kitchen", "stockroom", "storage", "corridor", "hallway", "work_floor", "bay", "hall", "staff", "lanes", "living", "dining"]
const METAL_DOORS := ["police", "pharmacy", "range"]
const SIDES := ["N", "E", "S", "W"]
## Rooms that keep door-to-door aisles free (rows of shelves or racks).
const PATH_ROOMS := ["sales", "hall"]
const ROW_BOXES := 8                ## at most this many searchable row pieces per room
const INTO := {"N": "S", "S": "N", "E": "W", "W": "E"}       ## a piece against wall side X faces INTO[X]
const NORMAL := {"N": Vector2(0, -1), "S": Vector2(0, 1), "E": Vector2(1, 0), "W": Vector2(-1, 0)}


## The staged generation (SPEC): step() runs one stage; done when it returns true.
class Ctx:
	extends RefCounted
	var setup := {}
	var stage := "layout"
	var progress := 0.0
	var layout := {}
	var done := false
	var attempts := 0
	var ms := 0.0
	var _i := 0
	var _b := {}

	func step() -> bool:
		if done:
			return true
		var t0 := Time.get_ticks_usec()
		if _b.is_empty():
			_b = PoiGenerator._new_build(setup, attempts)
			_i = 0
		PoiGenerator._run(_b, _i)
		_i += 1
		if _i >= PoiGenerator.STAGES.size():
			var v := PoiGenerator.validate(_b["L"])
			if v["ok"]:
				layout = _b["L"]
			else:
				attempts += 1
				_b = {}
				if attempts >= PoiGenerator.TRIES:
					layout = PoiGenerator.fallback(setup)
		ms += (Time.get_ticks_usec() - t0) / 1000.0
		if not layout.is_empty():
			PoiGenerator._finish_diag(layout, setup, attempts, ms)
			done = true
			progress = 1.0
			stage = "done"
			return true
		var w := 0.0
		for k in _i:
			w += float(PoiGenerator.STAGES[k][1])
		progress = maxf(progress, minf(w + 0.02 * attempts, 0.97))
		stage = str(PoiGenerator.STAGES[_i][0]) if _i < PoiGenerator.STAGES.size() else "exterior"
		return false


# --- the API ----------------------------------------------------------------------------

static func begin(setup: Dictionary) -> Ctx:
	var c := Ctx.new()
	c.setup = _norm_setup(setup)
	return c


static func generate(setup: Dictionary) -> Dictionary:
	var c := begin(setup)
	while not c.step():
		pass
	return c.layout


static func stage_text(stage: String) -> String:
	return str(STAGE_TEXT.get(stage, stage.capitalize()))


static func _norm_setup(setup: Dictionary) -> Dictionary:
	var s := setup.duplicate()
	var id := str(s.get("id", ""))
	if str(s.get("archetype", "")) == "" or not PoiArchetypes.has(str(s.get("archetype", ""))):
		s["archetype"] = PoiArchetypes.for_site(id)
	if not PoiArchetypes.has(str(s["archetype"])):
		s["archetype"] = "house_small"
	if not s.has("variant"):
		s["variant"] = PoiArchetypes.variant_for_site(id)
	if not str(s.get("size", "")) in ["s", "m", "l"]:
		s["size"] = "m"
	if typeof(s.get("seed")) not in [TYPE_INT, TYPE_FLOAT]:
		s["seed"] = hash(id)
	s["seed"] = int(s["seed"])
	return s


# --- the build ----------------------------------------------------------------------------

static func _new_build(setup: Dictionary, attempt: int) -> Dictionary:
	var arch_id := str(setup["archetype"])
	var a := PoiArchetypes.get_arch(arch_id, str(setup.get("variant", "")))
	var rng := RandomNumberGenerator.new()
	var seed := int(setup["seed"]) + attempt
	rng.seed = hash([seed, arch_id, str(setup["size"]), VERSION])
	var L := PoiLayouts._base()
	L["archetype"] = arch_id
	L["floors"] = []
	L["hide"] = []
	L["wander"] = []
	L["peek"] = []
	L["doorways"] = []
	L["lights"] = []
	L["story"] = []
	L["dormant"] = []
	L["stash"] = ""
	return {"setup": setup, "arch_id": arch_id, "arch": a, "family": str(a.get("family", "")), "seed": seed, "rng": rng, "L": L,
		"rooms": [], "gaps": [], "windows": [], "rc": {}, "centres": [], "front": [], "back": {}, "hall_ends": [], "entry_room": "",
		"stash_room": "", "locked_room": "", "dark_hint": bool(setup.get("dark_hint", false))}


static func _run(b: Dictionary, i: int) -> void:
	match i:
		0:
			_stage_layout(b)
		1:
			_stage_rooms(b)
		2:
			_stage_doors(b)
		3:
			_stage_furniture(b)
		4:
			_stage_containers(b)
		5:
			_stage_inhabitants(b)
		6:
			_stage_exterior(b)


# --- 1. layout: the footprint and the programme -------------------------------------------------

static func _ranged(r: Array, size: String, rng: RandomNumberGenerator) -> int:
	var lo := int(r[0])
	var hi := int(r[1])
	var span := float(hi - lo)
	var a := lo
	var c := hi
	match size:
		"s":
			c = lo + int(round(span / 3.0))
		"m":
			a = lo + int(floor(span / 3.0))
			c = hi - int(floor(span / 3.0))
		"l":
			a = hi - int(round(span / 3.0))
	return rng.randi_range(a, maxi(a, c))


static func _choose(rooms: Array, rng: RandomNumberGenerator) -> Array:
	var out := []
	for r in rooms:
		if bool(r.get("req", false)) or bool(r.get("grow", false)) or rng.randf() < float(r.get("p", 0.5)):
			out.append(r)
	return out


static func _stage_layout(b: Dictionary) -> void:
	var a: Dictionary = b["arch"]
	var rng: RandomNumberGenerator = b["rng"]
	var size := str(b["setup"]["size"])
	b["W"] = _ranged(a["w"], size, rng)
	b["D"] = _ranged(a["d"], size, rng)
	b["mirror"] = rng.randf() < 0.5
	match str(a["plan"]):
		"corridor":
			b["band_rooms"] = [_choose(a["front"]["rooms"], rng)]
			b["col_rooms"] = [_choose(a["cols"][0], rng), _choose(a["cols"][1], rng)]
		"yard":
			var hut: Dictionary = a["hut"]
			b["hut_w"] = _ranged(hut["w"], size, rng)
			b["hut_d"] = _ranged(hut["d"], size, rng)
			b["band_rooms"] = []
			for band in hut["bands"]:
				b["band_rooms"].append(_choose(band["rooms"], rng))
		_:
			b["band_rooms"] = []
			for band in a["bands"]:
				b["band_rooms"].append(_choose(band["rooms"], rng))


# --- 2. rooms ------------------------------------------------------------------------------

## Splits `total` metres over `items` (each with a [lo, hi] range under `key`;
## one "grow" takes the rest). Drops optional items (then trailing required
## ones) when they don't fit. Returns [items kept, sizes].
static func _split(total: int, items: Array, key: String, rng: RandomNumberGenerator) -> Array:
	var keep := items.duplicate()
	if keep.is_empty():
		return [[], []]
	while true:
		var g := keep.size() - 1
		for i in keep.size():
			if bool(keep[i].get("grow", false)):
				g = i
				break
		var ws := []
		for it in keep:
			var r: Array = it.get(key, [3, 4])
			ws.append(rng.randi_range(int(r[0]), mini(int(r[1]), total)))
		var others := 0
		for i in ws.size():
			if i != g:
				others += int(ws[i])
		var need := maxi(int((keep[g].get(key, [2, 2]) as Array)[0]), 2)
		var deficit := need - (total - others)
		if deficit > 0:
			for i in range(keep.size() - 1, -1, -1):
				if i == g or deficit <= 0:
					continue
				var lo := maxi(int((keep[i].get(key, [2, 2]) as Array)[0]), 2)
				var t := mini(int(ws[i]) - lo, deficit)
				if t > 0:
					ws[i] = int(ws[i]) - t
					deficit -= t
		if deficit <= 0:
			others = 0
			for i in ws.size():
				if i != g:
					others += int(ws[i])
			ws[g] = total - others
			# a grow room far past its range hands the spare to the others (up to theirs)
			var gmax := int((keep[g].get(key, [2, 99]) as Array)[1]) + 1
			for i in keep.size():
				if i == g or int(ws[g]) <= gmax:
					continue
				var room_left := int((keep[i].get(key, [2, 2]) as Array)[1]) - int(ws[i])
				var t := mini(room_left, int(ws[g]) - gmax)
				if t > 0:
					ws[i] = int(ws[i]) + t
					ws[g] = int(ws[g]) - t
			return [keep, ws]
		if keep.size() == 1:
			return [keep, [total]]
		var drop := -1
		for i in range(keep.size() - 1, -1, -1):
			if i != g and not bool(keep[i].get("req", false)):
				drop = i
				break
		if drop < 0:
			for i in range(keep.size() - 1, -1, -1):
				if i != g:
					drop = i
					break
		keep.remove_at(drop)
	return [keep, []]


static func _add_room(b: Dictionary, spec: Dictionary, rect: Rect2, band: int) -> Dictionary:
	var t := str(spec["type"])
	var n := 1
	var id := t
	var used := {}
	for r in b["rooms"]:
		used[r["id"]] = true
	while used.has(id):
		n += 1
		id = "%s_%d" % [t, n]
	var rt := PoiArchetypes.room_type(t)
	var r := {"id": id, "type": t, "rect": rect, "band": band, "dark": false, "spec": spec,
		"hub": int(rt.get("hub", 0)), "private": bool(rt.get("private", false)), "shared": bool(spec.get("shared", false))}
	b["rooms"].append(r)
	return r


## Rows of rooms in the rectangle x0..x0+W, south..south-D, front (south) first.
static func _bands_in(b: Dictionary, x0: int, south: int, W: int, D: int, bands: Array, chosen: Array) -> int:
	var rng: RandomNumberGenerator = b["rng"]
	var depths := []
	var g := 0
	for k in bands.size():
		depths.append(rng.randi_range(int(bands[k]["d"][0]), int(bands[k]["d"][1])))
		if bool(bands[k].get("grow", false)):
			g = k
	var sum := 0
	for v in depths:
		sum += int(v)
	depths[g] = maxi(int(depths[g]) + D - sum, 2)
	sum = 0
	for v in depths:
		sum += int(v)
	while sum > MAX_D:
		var best := -1
		for k in depths.size():
			if int(depths[k]) > 2 and (best < 0 or int(depths[k]) > int(depths[best])):
				best = k
		if best < 0:
			break
		depths[best] = int(depths[best]) - 1
		sum -= 1
	var z := south
	for k in bands.size():
		var d := int(depths[k])
		var sp := _split(W, chosen[k], "w", rng)
		var keep: Array = sp[0]
		var ws: Array = sp[1]
		var order := range(keep.size())
		if b["mirror"]:
			order.reverse()
		var x := x0
		for i in order:
			_add_room(b, keep[i], Rect2(x, z - d, int(ws[i]), d), k)
			x += int(ws[i])
		z -= d
	return south - z


static func _stage_rooms(b: Dictionary) -> void:
	var a: Dictionary = b["arch"]
	var rng: RandomNumberGenerator = b["rng"]
	var W: int = b["W"]
	var D: int = b["D"]
	match str(a["plan"]):
		"corridor":
			var need := 0
			for col in b["col_rooms"]:
				var s := 0
				for r in col:
					if bool(r.get("req", false)) or bool(r.get("grow", false)):
						s += int(r["d"][0])
				need = maxi(need, s)
			var df := rng.randi_range(int(a["front"]["d"][0]), int(a["front"]["d"][1]))
			D = maxi(D, df + need)
			if D > MAX_D:
				df = maxi(int(a["front"]["d"][0]), MAX_D - need)
				D = mini(MAX_D, df + need)
			W = mini(W, MAX_X - MIN_X)
			var x0 := maxi(MID_X - W / 2, MIN_X)
			b["x0"] = x0
			b["W"] = W
			_bands_in(b, x0, SOUTH, W, df, [{"d": [df, df], "grow": true}], b["band_rooms"])
			var d1 := D - df
			var wl := maxi((W - 2) / 2 + rng.randi_range(-1, 0), 3)
			var cx := x0 + wl
			var cols: Array = b["col_rooms"]
			if b["mirror"]:
				cols = [cols[1], cols[0]]
			var col_x := [[x0, wl], [cx + 2, W - wl - 2]]
			for c in 2:
				var sp := _split(d1, cols[c], "d", rng)
				var z := SOUTH - df
				for i in (sp[0] as Array).size():
					var d := int(sp[1][i])
					_add_room(b, sp[0][i], Rect2(int(col_x[c][0]), z - d, int(col_x[c][1]), d), 1)
					z -= d
			_add_room(b, {"type": "corridor"}, Rect2(cx, SOUTH - D, 2, d1), 1)
			b["D"] = D
		"yard":
			W = mini(W, MAX_X - MIN_X)
			var x0 := maxi(MID_X - W / 2, MIN_X)
			b["x0"] = x0
			b["W"] = W
			var hw: int = b["hut_w"]
			var hd: int = b["hut_d"]
			var hx := x0 + 1 if b["mirror"] else x0 + W - 1 - hw
			var hz := SOUTH - D + 1
			_bands_in(b, hx, hz + hd, hw, hd, a["hut"]["bands"], b["band_rooms"])
			b["hut"] = Rect2(hx, hz, hw, hd)
		_:
			W = mini(W, MAX_X - MIN_X)
			var x0 := maxi(MID_X - W / 2, MIN_X)
			b["x0"] = x0
			b["W"] = W
			b["D"] = _bands_in(b, x0, SOUTH, W, D, a["bands"], b["band_rooms"])
	b["z0"] = SOUTH - int(b["D"])
	b["bounds"] = Rect2(int(b["x0"]), int(b["z0"]), int(b["W"]), int(b["D"]))
	var L: Dictionary = b["L"]
	var base := str(a.get("floor", "floor_wood"))
	if str(a["plan"]) == "yard":
		L["floors"].append({"rect": (b["bounds"] as Rect2).grow(-0.1), "art": "asphalt"})
		L["floors"].append({"rect": (b["hut"] as Rect2).grow(0.1), "art": base})
	else:
		L["floors"].append({"rect": (b["bounds"] as Rect2).grow(0.1), "art": base})
	for r in b["rooms"]:
		var art := str(PoiArchetypes.room_type(r["type"]).get("floor", ""))
		if art != "" and art != base:
			L["floors"].append({"rect": r["rect"], "art": art})
	# the entrance room: the front row's main room (the apartment: the shared hallway)
	var entry := ""
	for r in b["rooms"]:
		if int(r["band"]) == 0 and bool(r["spec"].get("grow", false)):
			entry = r["id"]
			break
	if entry == "":
		var best := -1
		for r in b["rooms"]:
			if int(r["band"]) == 0 and int(r["hub"]) > best:
				best = int(r["hub"])
				entry = r["id"]
	b["entry_room"] = entry


# --- 3. doors, windows, walls ----------------------------------------------------------------

static func _room(b: Dictionary, id: String) -> Dictionary:
	for r in b["rooms"]:
		if r["id"] == id:
			return r
	return {}


static func _seg_key(axis: int, line: int, s: int) -> String:
	return "%d|%d|%d" % [axis, line, s]


static func _segments(b: Dictionary) -> Dictionary:
	var segs := {}
	for r in b["rooms"]:
		var rc: Rect2 = r["rect"]
		var x0 := int(rc.position.x)
		var z0 := int(rc.position.y)
		var x1 := int(rc.end.x)
		var z1 := int(rc.end.y)
		for x in range(x0, x1):
			for line in [z0, z1]:
				var k := _seg_key(0, line, x)
				if not segs.has(k):
					segs[k] = []
				segs[k].append(r["id"])
		for z in range(z0, z1):
			for line in [x0, x1]:
				var k := _seg_key(1, line, z)
				if not segs.has(k):
					segs[k] = []
				segs[k].append(r["id"])
	return segs


## Contiguous shared runs between rooms: "a|b" -> [[axis, line, lo, hi]].
static func _adjacency(segs: Dictionary) -> Dictionary:
	var units := {}
	for k in segs:
		var ids: Array = segs[k]
		if ids.size() != 2:
			continue
		var p: PackedStringArray = str(k).split("|")
		var ab := [str(ids[0]), str(ids[1])]
		ab.sort()
		var key := "%s|%s" % ab
		if not units.has(key):
			units[key] = []
		units[key].append([int(p[0]), int(p[1]), int(p[2])])
	var out := {}
	for key in units:
		var us: Array = units[key]
		us.sort_custom(func(u, v): return u[0] < v[0] or (u[0] == v[0] and (u[1] < v[1] or (u[1] == v[1] and u[2] < v[2]))))
		var runs := []
		for u in us:
			if not runs.is_empty():
				var last: Array = runs.back()
				if last[0] == u[0] and last[1] == u[1] and last[3] == u[2]:
					last[3] = u[2] + 1
					continue
			runs.append([u[0], u[1], u[2], u[2] + 1])
		out[key] = runs
	return out


static func _runs_between(adj: Dictionary, a: String, c: String) -> Array:
	var ab := [a, c]
	ab.sort()
	return adj.get("%s|%s" % ab, [])


static func _longest(runs: Array) -> Array:
	var best: Array = []
	for r in runs:
		if best.is_empty() or int(r[3]) - int(r[2]) > int(best[3]) - int(best[2]):
			best = r
	return best


## A door's rotation: from the child room toward the parent side.
static func _rot_toward(axis: int, line: int, parent: Rect2) -> int:
	if axis == 0:
		return 0 if is_equal_approx(parent.end.y, line) else 2
	return 3 if is_equal_approx(parent.end.x, line) else 1


static func _add_gap(b: Dictionary, axis: int, line: int, from: float, to: float, kind: String, rooms: Array, extra := {}) -> Dictionary:
	var g := {"axis": axis, "line": line, "from": from, "to": to, "kind": kind, "rooms": rooms}
	for k in extra:
		g[k] = extra[k]
	b["gaps"].append(g)
	return g


static func _add_door(b: Dictionary, id: String, axis: int, line: int, start: int, rot: int, locked := false, open := false, mat := "") -> Dictionary:
	var L: Dictionary = b["L"]
	var used := {}
	for d in L["doors"]:
		used[d["id"]] = true
	var did := id
	var n := 2
	while used.has(did):
		did = "%s_%d" % [id, n]
		n += 1
	PoiLayouts._door(L, did, axis, line, start, rot, locked, open)
	if mat != "":
		L["doors"].back()["mat"] = mat
	return L["doors"].back()


## A whole-metre start in [lo, hi - w], away from the corners when there is room.
static func _pick_start(lo: int, hi: int, w: int, rng: RandomNumberGenerator, prefer := INF) -> int:
	var a := lo
	var c := hi - w
	if c - a >= 2:
		a += 1
		c -= 1
	if c < a:
		return lo
	if prefer != INF:
		var best := a
		for s in range(a, c + 1):
			if absf(s + w * 0.5 - prefer) < absf(best + w * 0.5 - prefer):
				best = s
		return best
	return rng.randi_range(a, c)


static func _stage_doors(b: Dictionary) -> void:
	var rng: RandomNumberGenerator = b["rng"]
	var a: Dictionary = b["arch"]
	var segs := _segments(b)
	b["segs"] = segs
	var adj := _adjacency(segs)
	# the door tree from the entrance room
	var in_tree := {b["entry_room"]: true}
	var children := {}
	var edges := []
	while in_tree.size() < (b["rooms"] as Array).size():
		var best := []
		var best_s := -INF
		for ra in b["rooms"]:
			if not in_tree.has(ra["id"]):
				continue
			for rb in b["rooms"]:
				if in_tree.has(rb["id"]):
					continue
				var runs := _runs_between(adj, ra["id"], rb["id"])
				var run := _longest(runs)
				if run.is_empty():
					continue
				var s := float(ra["hub"]) * 10.0 + minf(float(run[3] - run[2]), 3.0) + rng.randf()
				if ra["private"]:
					s -= 100.0
				if ra["shared"] and int(children.get(ra["id"], 0)) > 0:
					s -= 60.0
				if s > best_s:
					best_s = s
					best = [ra, rb, run]
		if best.is_empty():
			break                      # an unreachable room: validation fails this seed
		in_tree[best[1]["id"]] = true
		children[best[0]["id"]] = int(children.get(best[0]["id"], 0)) + 1
		edges.append(best)
	var connected := {}
	for e in edges:
		var pa: Dictionary = e[0]
		var ch: Dictionary = e[1]
		var run: Array = e[2]
		connected["%s|%s" % [pa["id"], ch["id"]]] = true
		connected["%s|%s" % [ch["id"], pa["id"]]] = true
		var len := int(run[3]) - int(run[2])
		var ta := PoiArchetypes.room_type(pa["type"])
		var tb := PoiArchetypes.room_type(ch["type"])
		var open_pair: bool = (bool(ta.get("open", false)) and bool(tb.get("open", false))) or \
			(int(pa["hub"]) >= 3 and int(ch["hub"]) >= 3 and not ch["private"] and not pa["shared"] and not ch["shared"])
		if open_pair and len >= 2:
			var w := mini(len - (1 if len >= 4 else 0), 3 if len >= 5 else 2)
			var s := _pick_start(int(run[2]), int(run[3]), w, rng, (run[2] + run[3]) * 0.5)
			_add_gap(b, run[0], run[1], s, s + w, "open", [pa["id"], ch["id"]])
		else:
			var s := _pick_start(int(run[2]), int(run[3]), 1, rng)
			var d := _add_door(b, "door_" + str(ch["id"]), run[0], run[1], s, _rot_toward(run[0], run[1], pa["rect"]), false, rng.randf() < 0.35)
			_add_gap(b, run[0], run[1], s, s + 1, "door", [pa["id"], ch["id"]], {"door": d["id"], "child": ch["id"]})
	# open-plan loops: open neighbours not joined yet
	for ra in b["rooms"]:
		for rb in b["rooms"]:
			if str(ra["id"]) >= str(rb["id"]) or connected.has("%s|%s" % [ra["id"], rb["id"]]):
				continue
			if not (bool(PoiArchetypes.room_type(ra["type"]).get("open", false)) and bool(PoiArchetypes.room_type(rb["type"]).get("open", false))):
				continue
			var run := _longest(_runs_between(adj, ra["id"], rb["id"]))
			if run.is_empty() or int(run[3]) - int(run[2]) < 3 or rng.randf() > 0.5:
				continue
			var s := _pick_start(int(run[2]), int(run[3]), 2, rng)
			_add_gap(b, run[0], run[1], s, s + 2, "open", [ra["id"], rb["id"]])
	if str(a["plan"]) == "yard":
		_yard_doors(b, segs)
	else:
		_entrance(b, segs)
		_back_door(b, segs)
	_stash_room(b)
	_windows(b, segs)
	_dark_rooms(b)
	_walls(b, segs)
	if str(a["plan"]) == "yard":
		_fence(b)


static func _exterior_units(b: Dictionary, segs: Dictionary, r: Dictionary, side: String) -> Array:
	var rc: Rect2 = r["rect"]
	var out := []
	match side:
		"S", "N":
			var line := int(rc.end.y) if side == "S" else int(rc.position.y)
			for x in range(int(rc.position.x), int(rc.end.x)):
				if (segs.get(_seg_key(0, line, x), []) as Array).size() == 1:
					out.append(x)
		"E", "W":
			var line := int(rc.end.x) if side == "E" else int(rc.position.x)
			for z in range(int(rc.position.y), int(rc.end.y)):
				if (segs.get(_seg_key(1, line, z), []) as Array).size() == 1:
					out.append(z)
	return out


static func _runs_of(units: Array) -> Array:
	var runs := []
	for u in units:
		if not runs.is_empty() and int(runs.back()[1]) == int(u):
			runs.back()[1] = int(u) + 1
		else:
			runs.append([int(u), int(u) + 1])
	return runs


static func _side_line(rc: Rect2, side: String) -> int:
	match side:
		"S":
			return int(rc.end.y)
		"N":
			return int(rc.position.y)
		"E":
			return int(rc.end.x)
	return int(rc.position.x)


static func _entrance(b: Dictionary, segs: Dictionary) -> void:
	var a: Dictionary = b["arch"]
	var rng: RandomNumberGenerator = b["rng"]
	var kind := str(a.get("entrance", "door"))
	var r := _room(b, b["entry_room"])
	if kind == "none" or r.is_empty():
		_apartment_hall(b)
		return
	var runs := _runs_of(_exterior_units(b, segs, r, "S"))
	var run: Array = []
	for rr in runs:
		if run.is_empty() or int(rr[1]) - int(rr[0]) > int(run[1]) - int(run[0]):
			run = rr
	if run.is_empty():
		return
	var line := _side_line(r["rect"], "S")
	var lo := int(run[0])
	var hi := int(run[1])
	var mid := (r["rect"] as Rect2).get_center().x
	for c in b["rooms"]:
		if c["type"] == "corridor":
			mid = (c["rect"] as Rect2).get_center().x
	var out := [r["id"], "out"]
	match kind:
		"double":
			var s := _pick_start(lo, hi, 2, rng, mid)
			var d1 := _add_door(b, "front", 0, line, s, 2, false, true)
			var d2 := _add_door(b, "front", 0, line, s + 1, 2, false, rng.randf() < 0.4)
			_add_gap(b, 0, line, s, s + 1, "door", out, {"door": d1["id"], "front": true})
			_add_gap(b, 0, line, s + 1, s + 2, "door", out, {"door": d2["id"], "front": true})
			b["front"] = [s, s + 2]
		"open":
			var s := _pick_start(lo, hi, 2, rng, mid)
			_add_gap(b, 0, line, s, s + 2, "open", out, {"front": true})
			b["front"] = [s, s + 2]
		"bay":
			var w := 3 if hi - lo >= 7 else 2
			var s := _pick_start(lo, hi, w, rng, mid)
			_add_gap(b, 0, line, s, s + w, "open", out, {"front": true, "bay": true})
			b["front"] = [s, s + w]
			# a side door beside the bay door when the wall is long enough
			var t := s + w + 2 if s + w + 3 <= hi - 1 else (s - 3 if s - 3 >= lo + 1 else -9999)
			if t != -9999:
				var d := _add_door(b, "side", 0, line, t, 2, false, rng.randf() < 0.3)
				_add_gap(b, 0, line, t, t + 1, "door", out, {"door": d["id"], "front": true})
		_:
			var s := _pick_start(lo, hi, 1, rng, mid)
			var d := _add_door(b, "front", 0, line, s, 2, false, false)
			_add_gap(b, 0, line, s, s + 1, "door", out, {"door": d["id"], "front": true})
			b["front"] = [s, s + 1]


## The apartment: the shared hallway's two ends, the entry (near the stairs) and
## the dark far end (dark_exit), away from the flat's own door.
static func _apartment_hall(b: Dictionary) -> void:
	var hall := _room(b, b["entry_room"])
	if hall.is_empty():
		return
	var rc: Rect2 = hall["rect"]
	var door_x := rc.get_center().x
	for g in b["gaps"]:
		if hall["id"] in g["rooms"]:
			door_x = (float(g["from"]) + float(g["to"])) * 0.5
	var far_west := door_x - rc.position.x > rc.end.x - door_x      # the flat's door is nearer the east end
	var inner := rc.grow(-0.1)
	var dark := Rect2()
	var near_x := 0.0
	if far_west:
		dark = Rect2(inner.position.x, inner.position.y, 1.4, inner.size.y)
		near_x = inner.end.x - 0.9
	else:
		dark = Rect2(inner.end.x - 1.4, inner.position.y, 1.4, inner.size.y)
		near_x = inner.position.x + 0.9
	b["dark_exit"] = dark
	b["apt_entry"] = Vector2(near_x, rc.get_center().y)
	b["hall_ends"] = [dark, Rect2(near_x - 0.8, inner.position.y, 1.6, inner.size.y)]


static func _back_door(b: Dictionary, segs: Dictionary) -> void:
	var a: Dictionary = b["arch"]
	var rng: RandomNumberGenerator = b["rng"]
	if str(a["plan"]) == "yard" or rng.randf() >= float(a.get("back_door", 0.0)):
		return
	var cands := []
	for r in b["rooms"]:
		if not str(r["type"]) in BACK_OK or r["shared"]:
			continue
		var runs := _runs_of(_exterior_units(b, segs, r, "N"))
		for rr in runs:
			if int(rr[1]) - int(rr[0]) >= 2:
				cands.append([r, rr])
	if cands.is_empty():
		return
	cands.sort_custom(func(p, q): return (10 if p[0]["type"] == "corridor" else 0) > (10 if q[0]["type"] == "corridor" else 0))
	var pick: Array = cands[0] if cands[0][0]["type"] == "corridor" else cands[rng.randi() % cands.size()]
	var r: Dictionary = pick[0]
	var line := _side_line(r["rect"], "N")
	var s := _pick_start(int(pick[1][0]), int(pick[1][1]), 1, rng, (r["rect"] as Rect2).get_center().x)
	var d := _add_door(b, "back", 0, line, s, 0, false, rng.randf() < 0.3)
	_add_gap(b, 0, line, s, s + 1, "door", [r["id"], "out"], {"door": d["id"], "back": true})
	b["back"] = {"x": s + 0.5, "z": float(line), "room": r["id"]}


## The main stash's room: the archetype's first listed type present (not the
## entrance room); its door locked sometimes, a steel one where fitting.
static func _stash_room(b: Dictionary) -> void:
	var a: Dictionary = b["arch"]
	var rng: RandomNumberGenerator = b["rng"]
	var st: Dictionary = a["stash"]
	var room := ""
	for t in st["rooms"]:
		var cands := (b["rooms"] as Array).filter(func(r): return r["type"] == t and r["id"] != b["entry_room"])
		if not cands.is_empty():
			room = cands[rng.randi() % cands.size()]["id"]
			break
	if room == "":
		for r in b["rooms"]:
			if r["private"] and r["id"] != b["entry_room"]:
				room = r["id"]
				break
	if room == "":
		room = b["entry_room"]
	b["stash_room"] = room
	if room == b["entry_room"] or rng.randf() >= float(st.get("lock_room", 0.3)):
		return
	var doors := (b["gaps"] as Array).filter(func(g): return g.has("door") and room in g["rooms"])
	if doors.size() != 1 or doors[0].get("front", false) or doors[0].get("back", false):
		return
	for d in b["L"]["doors"]:
		if d["id"] == doors[0]["door"]:
			d["locked"] = true
			d["open"] = false
			if b["arch_id"] in METAL_DOORS and rng.randf() < 0.5:
				d["mat"] = "metal"
	b["locked_room"] = room


static func _windows(b: Dictionary, segs: Dictionary) -> void:
	var a: Dictionary = b["arch"]
	var rng: RandomNumberGenerator = b["rng"]
	for r in b["rooms"]:
		var rt := PoiArchetypes.room_type(r["type"])
		var small: bool = r["type"] in ["bathroom", "toilet"]
		if not bool(rt.get("win", false)) and not small:
			continue
		var any := false
		for side in ["S", "W", "E", "N"]:
			var axis := 0 if side in ["S", "N"] else 1
			var line := _side_line(r["rect"], side)
			for run in _runs_of(_exterior_units(b, segs, r, side)):
				var avail := [[float(run[0]) + 0.5, float(run[1]) - 0.5]]
				for g in b["gaps"]:
					if int(g["axis"]) == axis and int(g["line"]) == line:
						avail = _cut(avail, float(g["from"]) - 0.5, float(g["to"]) + 0.5)
				for iv in avail:
					var p := float(iv[0])
					var q := float(iv[1])
					if q - p < 1.0:
						continue
					if small:
						if rng.randf() < 0.6:
							var c := (p + q) * 0.5
							_add_window(b, r, side, axis, line, c - 0.4, c + 0.4, 1.5, 2.0)
							any = true
						continue
					var store: bool = bool(a.get("storefront", false)) and side == "S" and r["id"] == b["entry_room"]
					if store:
						var n := 1 if q - p <= 5.5 else 2
						var step := (q - p) / float(n)
						for k in n:
							_add_window(b, r, side, axis, line, p + step * k + (0.0 if k == 0 else 0.3), p + step * (k + 1) - (0.3 if k < n - 1 else 0.0), 0.6, 2.2)
						any = true
						continue
					var n := maxi(1, int((q - p + 0.6) / 2.8))
					var step := (q - p) / float(n)
					for k in n:
						if any and rng.randf() < 0.25:
							continue
						var c := p + step * (k + 0.5)
						var half := minf(rng.randf_range(0.6, 0.9), step * 0.5 - 0.1)
						var sill := 0.9 if r["type"] != "office" else 1.0
						if b["family"] == "industry" or b["family"] == "outdoor":
							sill = 1.3
						_add_window(b, r, side, axis, line, c - half, c + half, sill, 2.1)
						any = true
		r["windows"] = any


static func _add_window(b: Dictionary, r: Dictionary, side: String, axis: int, line: int, from: float, to: float, sill: float, head: float) -> void:
	from = snappedf(from, 0.1)
	to = snappedf(to, 0.1)
	_add_gap(b, axis, line, from, to, "window", [r["id"], "out"], {"sill": sill, "head": head})
	b["windows"].append({"room": r["id"], "side": side, "axis": axis, "line": line, "from": from, "to": to, "sill": sill, "head": head})


## Interval list minus [a, c].
static func _cut(ivs: Array, a: float, c: float) -> Array:
	var out := []
	for iv in ivs:
		var p := float(iv[0])
		var q := float(iv[1])
		if c <= p or a >= q:
			out.append(iv)
			continue
		if a > p:
			out.append([p, a])
		if c < q:
			out.append([c, q])
	return out


static func _dark_rooms(b: Dictionary) -> void:
	var a: Dictionary = b["arch"]
	var rng: RandomNumberGenerator = b["rng"]
	var share := float(a.get("dark", 0.3)) + (0.3 if b["dark_hint"] else 0.0)
	var any := false
	for r in b["rooms"]:
		if r["id"] == b["entry_room"] or bool(r.get("windows", false)):
			continue
		if bool(PoiArchetypes.room_type(r["type"]).get("dark", false)) and rng.randf() < share:
			r["dark"] = true
			any = true
	if b["dark_hint"] and not any:
		var r := _room(b, b["stash_room"])
		if r.is_empty() or r["id"] == b["entry_room"]:
			for c in b["rooms"]:
				if c["private"]:
					r = c
					break
		if not r.is_empty() and r["id"] != b["entry_room"]:
			r["dark"] = true


static func _walls(b: Dictionary, segs: Dictionary) -> void:
	var a: Dictionary = b["arch"]
	var L: Dictionary = b["L"]
	var style := str(a.get("style", "brick"))
	var paint := int(a.get("paint", 0xcfc8bb))
	if str(a["plan"]) == "yard":
		style = "siding"
	var lines := {}
	for k in segs:
		var p: PackedStringArray = str(k).split("|")
		var lk := "%s|%s" % [p[0], p[1]]
		if not lines.has(lk):
			lines[lk] = []
		lines[lk].append([int(p[2]), (segs[k] as Array).size() == 1])
	for lk in lines:
		var p: PackedStringArray = str(lk).split("|")
		var axis := int(p[0])
		var line := int(p[1])
		var us: Array = lines[lk]
		us.sort_custom(func(u, v): return u[0] < v[0])
		var runs := []
		for u in us:
			if not runs.is_empty() and int(runs.back()[1]) == int(u[0]) and runs.back()[2] == u[1]:
				runs.back()[1] = int(u[0]) + 1
			else:
				runs.append([int(u[0]), int(u[0]) + 1, u[1]])
		for run in runs:
			var gaps := []
			for g in b["gaps"]:
				if int(g["axis"]) == axis and int(g["line"]) == line and float(g["from"]) >= run[0] - 0.01 and float(g["to"]) <= run[1] + 0.01:
					var e := {"from": float(g["from"]), "to": float(g["to"]), "kind": g["kind"]}
					if g["kind"] == "window":
						e["sill"] = g["sill"]
						e["head"] = g["head"]
					gaps.append(e)
			gaps.sort_custom(func(u, v): return u["from"] < v["from"])
			var pa := Vector2(run[0], line) if axis == 0 else Vector2(line, run[0])
			var pb := Vector2(run[1], line) if axis == 0 else Vector2(line, run[1])
			if run[2]:
				PoiLayouts._wall(L, pa, pb, style, gaps)
			else:
				PoiLayouts._wall(L, pa, pb, "drywall", gaps, paint)


## The yard: the gate (an open gap in the fence's south side, away from the
## hut) and the hut's door to the yard.
static func _yard_doors(b: Dictionary, segs: Dictionary) -> void:
	var rng: RandomNumberGenerator = b["rng"]
	var bo: Rect2 = b["bounds"]
	var hut: Rect2 = b["hut"]
	var x0 := int(bo.position.x)
	var x1 := int(bo.end.x)
	var gw := 3 if bo.size.x >= 14 else 2
	var mid := bo.get_center().x
	var gx := int(round(mid + (2.0 if hut.get_center().x < mid else -2.0) - gw * 0.5))
	gx = clampi(gx, x0 + 1, x1 - gw - 1)
	b["gate"] = [gx, gx + gw]
	b["front"] = [gx, gx + gw]
	_add_gap(b, 0, SOUTH, gx, gx + gw, "open", ["yard", "out"], {"front": true, "gate": true})
	var r := _room(b, b["entry_room"])
	if r.is_empty():
		return
	for side in ["S", "E", "W"]:
		for rr in _runs_of(_exterior_units(b, segs, r, side)):
			var axis := 0 if side == "S" else 1
			var line := _side_line(r["rect"], side)
			var s := _pick_start(int(rr[0]), int(rr[1]), 1, rng)
			var rot: int = {"S": 2, "E": 1, "W": 3}[side]
			var d := _add_door(b, "hut", axis, line, s, rot, false, rng.randf() < 0.5)
			_add_gap(b, axis, line, s, s + 1, "door", [r["id"], "yard"], {"door": d["id"], "hut_door": true})
			return


## The yard's plank fence round the lot, the gate left open.
static func _fence(b: Dictionary) -> void:
	var L: Dictionary = b["L"]
	var bo: Rect2 = b["bounds"]
	var x0 := int(bo.position.x)
	var x1 := int(bo.end.x)
	var z0 := int(bo.position.y)
	var gate: Array = b["gate"]
	PoiLayouts._wall(L, Vector2(x0, SOUTH), Vector2(x1, SOUTH), "plank", [PoiLayouts._open(gate[0], gate[1])])
	PoiLayouts._wall(L, Vector2(x0, z0), Vector2(x1, z0), "plank")
	PoiLayouts._wall(L, Vector2(x0, z0), Vector2(x0, SOUTH), "plank")
	PoiLayouts._wall(L, Vector2(x1, z0), Vector2(x1, SOUTH), "plank")


# --- 4. furniture ------------------------------------------------------------------------

## A room's placement state.
static func _rc(b: Dictionary, r: Dictionary) -> Dictionary:
	if b["rc"].has(r["id"]):
		return b["rc"][r["id"]]
	var rect: Rect2 = r["rect"]
	var rc := {"room": r, "inner": rect.grow(-0.1), "blocks": [], "clears": [], "reserved": [], "wins": {"N": [], "E": [], "S": [], "W": []},
		"points": [], "count": {}}
	for g in b["gaps"]:
		if g["kind"] == "window":
			continue
		var side := _gap_side(rect, g)
		if side == "":
			continue
		var f := float(g["from"])
		var t := float(g["to"])
		var zone := Rect2()
		var p := Vector2.ZERO
		match side:
			"N":
				zone = Rect2(f - 0.15, rect.position.y, t - f + 0.3, 1.1)
				p = Vector2((f + t) * 0.5, rect.position.y + 0.6)
			"S":
				zone = Rect2(f - 0.15, rect.end.y - 1.1, t - f + 0.3, 1.1)
				p = Vector2((f + t) * 0.5, rect.end.y - 0.6)
			"W":
				zone = Rect2(rect.position.x, f - 0.15, 1.1, t - f + 0.3)
				p = Vector2(rect.position.x + 0.6, (f + t) * 0.5)
			"E":
				zone = Rect2(rect.end.x - 1.1, f - 0.15, 1.1, t - f + 0.3)
				p = Vector2(rect.end.x - 0.6, (f + t) * 0.5)
		rc["reserved"].append(zone)
		rc["points"].append(p)
	# a stub in from every door; door-to-door paths (each door to the first) in
	# halls with rows, where an aisle must run from the entrance (elsewhere the
	# clearances keep the way round free, and validation checks it)
	var pts: Array = rc["points"]
	var c := rect.get_center()
	if pts.size() >= 2 and r["type"] in PATH_ROOMS:
		for k in range(1, pts.size()):
			_reserve_path(rc, pts[0], pts[k])
	else:
		for p0 in pts:
			_reserve_path(rc, p0, (p0 as Vector2) + (c - (p0 as Vector2)).limit_length(0.8))
	for e in b["hall_ends"]:
		if rect.intersects(e):
			rc["reserved"].append(e)
	for w in b["windows"]:
		if w["room"] == r["id"]:
			rc["wins"][w["side"]].append(w)
	b["rc"][r["id"]] = rc
	return rc


static func _gap_side(rect: Rect2, g: Dictionary) -> String:
	var line := float(g["line"])
	var f := float(g["from"])
	var t := float(g["to"])
	if int(g["axis"]) == 0:
		if t <= rect.position.x + 0.01 or f >= rect.end.x - 0.01:
			return ""
		if is_equal_approx(line, rect.position.y):
			return "N"
		if is_equal_approx(line, rect.end.y):
			return "S"
	else:
		if t <= rect.position.y + 0.01 or f >= rect.end.y - 0.01:
			return ""
		if is_equal_approx(line, rect.position.x):
			return "W"
		if is_equal_approx(line, rect.end.x):
			return "E"
	return ""


## Reserves an L-shaped 0.9 m path from p to q (first along the longer axis).
static func _reserve_path(rc: Dictionary, p: Vector2, q: Vector2) -> void:
	var w := 0.9
	var corner := Vector2(q.x, p.y) if absf(q.x - p.x) >= absf(q.y - p.y) else Vector2(p.x, q.y)
	for seg in [[p, corner], [corner, q]]:
		var a: Vector2 = seg[0]
		var c: Vector2 = seg[1]
		var r := Rect2(a.min(c), (c - a).abs()).grow(w * 0.5)
		rc["reserved"].append(r.intersection(rc["inner"]) if r.intersects(rc["inner"]) else r)


static func _plan_size(size: Vector3, facing: String) -> Vector2:
	return Vector2(size.x, size.z) if facing in ["N", "S"] else Vector2(size.z, size.x)


static func _clear_rect(rect: Rect2, facing: String, depth: float) -> Rect2:
	match facing:
		"S":
			return Rect2(rect.position.x, rect.end.y, rect.size.x, depth)
		"N":
			return Rect2(rect.position.x, rect.position.y - depth, rect.size.x, depth)
		"E":
			return Rect2(rect.end.x, rect.position.y, depth, rect.size.y)
	return Rect2(rect.position.x - depth, rect.position.y, depth, rect.size.y)


static func _hits(rects: Array, r: Rect2) -> bool:
	var s := r.grow(-0.015)
	for o in rects:
		if (o as Rect2).intersects(s):
			return true
	return false


static func _fits(rc: Dictionary, rect: Rect2, clear: Rect2) -> bool:
	var inner: Rect2 = rc["inner"]
	if not inner.grow(0.01).encloses(rect):
		return false
	if _hits(rc["blocks"], rect) or _hits(rc["reserved"], rect) or _hits(rc["clears"], rect):
		return false
	if clear.size.x > 0.0 and clear.size.y > 0.0:
		if not inner.grow(0.01).encloses(clear) or _hits(rc["blocks"], clear):
			return false
	return true


## Against a wall: the best free spot (corners and neighbours preferred).
static func _place_wall(b: Dictionary, rc: Dictionary, type: String, size: Vector3, e: Dictionary) -> Dictionary:
	var rng: RandomNumberGenerator = b["rng"]
	var inner: Rect2 = rc["inner"]
	var clear_d := maxf(float(PoiFurniture.piece(type).get("clear", 0.5)), 0.0)
	var sides: Array = e.get("side", SIDES)
	var tall := size.y >= 1.0
	var best := {}
	var best_s := -INF
	var near := Vector2.INF
	if str(e.get("near", "")) == "entrance" and not (b["front"] as Array).is_empty():
		near = Vector2((float(b["front"][0]) + float(b["front"][1])) * 0.5, SOUTH)
	for side in sides:
		var facing: String = INTO[side]
		var ps := _plan_size(size, facing)
		var along_lo := inner.position.x if side in ["N", "S"] else inner.position.y
		var along_hi := (inner.end.x if side in ["N", "S"] else inner.end.y) - (ps.x if side in ["N", "S"] else ps.y)
		if along_hi < along_lo - 0.001:
			continue
		var ts := []
		var tt := along_lo
		while tt < along_hi - 0.001:
			ts.append(tt)
			tt += 0.25
		ts.append(maxf(along_hi, along_lo))
		for t in ts:
			var rect := Rect2()
			match side:
				"N":
					rect = Rect2(t, inner.position.y, ps.x, ps.y)
				"S":
					rect = Rect2(t, inner.end.y - ps.y, ps.x, ps.y)
				"W":
					rect = Rect2(inner.position.x, t, ps.x, ps.y)
				"E":
					rect = Rect2(inner.end.x - ps.x, t, ps.x, ps.y)
			var clear := _clear_rect(rect, facing, clear_d) if clear_d > 0.0 else Rect2()
			if not _fits(rc, rect, clear):
				continue
			var span := Vector2(rect.position.x, rect.end.x) if side in ["N", "S"] else Vector2(rect.position.y, rect.end.y)
			var blocked := false
			for w in rc["wins"][side]:
				if size.y > float(w["sill"]) - 0.05 and span.x < float(w["to"]) + 0.1 and span.y > float(w["from"]) - 0.1:
					blocked = true
					break
			if blocked:
				continue
			var s := rng.randf()
			if absf(span.x - along_lo) < 0.05 or absf(span.x - along_hi) < 0.05:
				s += 1.5
			for o in rc["blocks"]:
				var orr: Rect2 = o
				if orr.grow(0.06).intersects(rect):
					s += 1.2
					break
			if tall and side == "S":
				s -= 1.2
			if near != Vector2.INF:
				s -= rect.get_center().distance_to(near) * 0.6
			if s > best_s:
				best_s = s
				best = {"rect": rect, "facing": facing, "clear": clear}
	return best


## Free-standing with `ring` metres free all round.
static func _place_centre(b: Dictionary, rc: Dictionary, type: String, size: Vector3, facing: String, ring: float, near := Vector2.INF) -> Dictionary:
	var rng: RandomNumberGenerator = b["rng"]
	var inner: Rect2 = rc["inner"]
	var ps := _plan_size(size, facing)
	var area := inner.grow(-ring)
	if area.size.x < ps.x or area.size.y < ps.y:
		return {}
	var c := inner.get_center()
	var best := {}
	var best_s := -INF
	var nx := int(floor((area.size.x - ps.x) / 0.25)) + 1
	var nz := int(floor((area.size.y - ps.y) / 0.25)) + 1
	for i in nx:
		for j in nz:
			var rect := Rect2(area.position.x + i * 0.25, area.position.y + j * 0.25, ps.x, ps.y)
			if _hits(rc["blocks"], rect.grow(ring)) or _hits(rc["reserved"], rect) or _hits(rc["clears"], rect):
				continue
			var s := rng.randf() * 1.5 - rect.get_center().distance_to(c if near == Vector2.INF else near) * (0.3 if near == Vector2.INF else 1.0)
			if s > best_s:
				best_s = s
				best = {"rect": rect, "facing": facing, "clear": Rect2()}
	return best


## Adds a placed piece: a container (box spec, by chance c) or a prop.
static func _put(b: Dictionary, rc: Dictionary, type: String, at: Dictionary, size: Vector3, box: Dictionary, chance := 1.0) -> Dictionary:
	var rng: RandomNumberGenerator = b["rng"]
	var L: Dictionary = b["L"]
	var r: Dictionary = rc["room"]
	var rect: Rect2 = at["rect"]
	var facing: String = at["facing"]
	var block := PoiFurniture.blocks(type)
	rc["blocks"].append(rect)
	var clear: Rect2 = at.get("clear", Rect2())
	if clear.size.x > 0.0 and clear.size.y > 0.0:
		rc["clears"].append(clear)
	if not box.is_empty() and rng.randf() < chance:
		var n := int(rc["count"].get(type, 0)) + 1
		rc["count"][type] = n
		var big := type in ["boxes", "storage_chest", "crate", "tool_cabinet", "wardrobe", "pallet", "pallet_rack", "locker", "safe", "lumber_rack"]
		var e := {"id": "%s_%s_%d" % [r["id"], type, n], "type": type, "rect": rect, "facing": facing, "h": size.y, "label": str(box["label"]),
			"holds": (box.get("holds", []) as Array).duplicate(), "weight": float(box.get("weight", 1.0)), "table": "loot", "picked": false,
			"needs": "", "noise": 1, "secs": 2.4 if big else 1.6, "minutes": 10 if big else 6, "room": r["id"]}
		L["containers"].append(e)
		return e
	var p := {"type": type, "rect": rect, "facing": facing, "h": size.y, "block": block, "room": r["id"]}
	L["props"].append(p)
	return p


static func _stage_furniture(b: Dictionary) -> void:
	var rng: RandomNumberGenerator = b["rng"]
	for r in b["rooms"]:
		_rc(b, r)
	# the main stash first, so it always has its place
	_place_stash(b)
	for r in b["rooms"]:
		var rc := _rc(b, r)
		var es := PoiFurniture.entries(r["type"], b["arch_id"], b["family"])
		for e in es:
			if str(e.get("place", "wall")) == "rows":
				_rows(b, rc, e)
		for e in es:
			var place := str(e.get("place", "wall"))
			if place == "rows" or rng.randf() >= float(e.get("p", 1.0)):
				continue
			var nr: Array = e.get("n", [1, 1])
			var n := rng.randi_range(int(nr[0]), int(nr[1]))
			for k in n:
				if not _place_entry(b, rc, e):
					break
	if str(b["arch"]["plan"]) == "yard":
		_furnish_yard(b)


static func _place_entry(b: Dictionary, rc: Dictionary, e: Dictionary) -> bool:
	var rng: RandomNumberGenerator = b["rng"]
	var type := str(e["piece"])
	if not PoiFurniture.fits_room(type, rc["room"]["type"]):
		return false
	var size: Vector3 = e.get("size", PoiFurniture.size_of(type))
	var place := str(e.get("place", "wall"))
	var at := {}
	if place == "centre":
		var facing := str(e.get("facing", "S" if rng.randf() < 0.5 else "E"))
		var ring := 0.9 if type in ["car", "machine"] else (0.75 if e.has("chairs") else 0.6)
		var near := Vector2.INF
		if str(e.get("near", "")) == "entrance" and not (b["front"] as Array).is_empty():
			near = Vector2((float(b["front"][0]) + float(b["front"][1])) * 0.5 + 2.5, SOUTH - 1.5)
		at = _place_centre(b, rc, type, size, facing, ring, near)
		if at.is_empty() and not e.has("facing"):
			at = _place_centre(b, rc, type, size, "E" if facing == "S" else "S", ring, near)
		if at.is_empty() and near != Vector2.INF:
			at = _place_wall(b, rc, type, size, e)
	else:
		at = _place_wall(b, rc, type, size, e)
	if at.is_empty():
		return false
	var put := _put(b, rc, type, at, size, e.get("box", {}), float(e.get("c", 1.0)))
	if place == "centre":
		b["centres"].append({"rect": at["rect"], "type": type, "room": rc["room"]["id"]})
		if e.has("chairs"):
			_chairs(b, rc, at["rect"], e["chairs"])
	return not put.is_empty()


static func _chairs(b: Dictionary, rc: Dictionary, table: Rect2, nr: Array) -> void:
	var rng: RandomNumberGenerator = b["rng"]
	var n := rng.randi_range(int(nr[0]), int(nr[1]))
	var size := PoiFurniture.size_of("chair")
	var long_x := table.size.x >= table.size.y
	var spots := []
	if long_x:
		for fx in [0.28, 0.72]:
			spots.append([Vector2(table.position.x + table.size.x * fx, table.position.y - 0.25), "S"])
			spots.append([Vector2(table.position.x + table.size.x * fx, table.end.y + 0.25), "N"])
	else:
		for fz in [0.28, 0.72]:
			spots.append([Vector2(table.position.x - 0.25, table.position.y + table.size.y * fz), "E"])
			spots.append([Vector2(table.end.x + 0.25, table.position.y + table.size.y * fz), "W"])
	var placed := 0
	for s in spots:
		if placed >= n:
			break
		var ps := _plan_size(size, s[1])
		var rect := Rect2((s[0] as Vector2) - ps * 0.5, ps)
		if not (rc["inner"] as Rect2).encloses(rect) or _hits(rc["blocks"], rect) or _hits(rc["reserved"], rect):
			continue
		b["L"]["props"].append({"type": "chair", "rect": rect, "facing": s[1], "h": size.y, "block": false, "room": rc["room"]["id"]})
		rc["blocks"].append(rect)
		placed += 1


## Gondolas / racks in rows running north-south (the camera looks down the aisles).
static func _rows(b: Dictionary, rc: Dictionary, e: Dictionary) -> void:
	var rng: RandomNumberGenerator = b["rng"]
	var type := str(e["piece"])
	var size: Vector3 = PoiFurniture.size_of(type)
	var pair := bool(e.get("pair", false))
	var depth := size.z * (2.0 if pair else 1.0)
	var aisle := 1.3 if pair else 1.6
	var inner: Rect2 = rc["inner"]
	var area := Rect2(inner.position.x + 1.9, inner.position.y + 1.6, inner.size.x - 3.8, inner.size.y - 3.6)
	if area.size.x < depth or area.size.y < size.x:
		return
	var units := mini(int(floor(area.size.y / size.x)), 3)
	var z0 := area.position.y + (area.size.y - units * size.x) * 0.5
	var rows := int(floor((area.size.x + aisle) / (depth + aisle)))
	var x := area.position.x + (area.size.x - (rows * (depth + aisle) - aisle)) * 0.5
	var n0 := (b["L"]["containers"] as Array).size()
	for i in rows:
		if (b["L"]["containers"] as Array).size() - n0 >= ROW_BOXES:
			e = e.duplicate()
			e["c"] = 0.0                # enough to search here: the rest are plain racks
		for u in units:
			var unit := Rect2(x, z0 + u * size.x, depth, size.x)
			if _hits(rc["reserved"], unit) or _hits(rc["blocks"], unit):
				continue
			if pair:
				var wr := Rect2(x, unit.position.y, size.z, size.x)
				var er := Rect2(x + size.z, unit.position.y, size.z, size.x)
				_put(b, rc, type, {"rect": wr, "facing": "W", "clear": _clear_rect(wr, "W", 0.6)}, size, e.get("box", {}), float(e.get("c", 1.0)))
				_put(b, rc, type, {"rect": er, "facing": "E", "clear": _clear_rect(er, "E", 0.6)}, size, e.get("box", {}), float(e.get("c", 1.0)))
			else:
				var facing := "W" if rng.randf() < 0.5 else "E"
				_put(b, rc, type, {"rect": unit, "facing": facing, "clear": _clear_rect(unit, facing, 0.7)}, size, e.get("box", {}), float(e.get("c", 1.0)))
		x += depth + aisle


static func _place_stash(b: Dictionary) -> void:
	var rng: RandomNumberGenerator = b["rng"]
	var st: Dictionary = b["arch"]["stash"]
	var kinds: Array = st["kinds"]
	var kind: Dictionary = kinds[rng.randi() % kinds.size()]
	var order := [b["stash_room"]]
	for r in b["rooms"]:
		if r["id"] != b["stash_room"] and r["private"]:
			order.append(r["id"])
	for r in b["rooms"]:
		if not r["id"] in order:
			order.append(r["id"])
	var type := str(kind["piece"])
	var size: Vector3 = PoiFurniture.size_of(type)
	for rid in order:
		var rc := _rc(b, _room(b, rid))
		var at := _place_wall(b, rc, type, size, {"side": ["N", "E", "W"]})
		if at.is_empty():
			at = _place_wall(b, rc, type, size, {})
		if at.is_empty():
			continue
		var e := _put(b, rc, type, at, size, {"label": kind["label"], "holds": kind.get("holds", [])})
		e["id"] = "stash"
		e["stash"] = true
		e["table"] = "stash"
		e["needs"] = "crowbar" if rng.randf() < float(st.get("needs", 0.85)) else ""
		e["noise"] = 2
		e["weight"] = 1.0
		b["L"]["stash"] = "stash"
		b["stash_room"] = rid
		return


## The yard's open ground: pieces along the fence and in the open.
static func _furnish_yard(b: Dictionary) -> void:
	var rng: RandomNumberGenerator = b["rng"]
	var bo: Rect2 = b["bounds"]
	var hut: Rect2 = b["hut"]
	var yard := {"id": "yard", "type": "yard", "rect": bo, "private": false, "hub": 3, "shared": false, "band": 0, "dark": false, "spec": {}}
	var rc := {"room": yard, "inner": bo.grow(-0.15), "blocks": [hut.grow(0.3)], "clears": [], "reserved": [], "wins": {"N": [], "E": [], "S": [], "W": []},
		"points": [], "count": {}}
	var gate: Array = b["gate"]
	rc["reserved"].append(Rect2(float(gate[0]) - 0.3, SOUTH - 2.2, float(gate[1]) - float(gate[0]) + 0.6, 2.2))
	for g in b["gaps"]:
		if g.get("hut_door", false):
			var side := _gap_side(hut, g)
			var c := Vector2((float(g["from"]) + float(g["to"])) * 0.5, float(g["line"])) if int(g["axis"]) == 0 else Vector2(float(g["line"]), (float(g["from"]) + float(g["to"])) * 0.5)
			var out: Vector2 = c + NORMAL.get(side, Vector2(0, 1)) * 1.0
			rc["reserved"].append(Rect2(out - Vector2(0.8, 0.8), Vector2(1.6, 1.6)))
			_reserve_path(rc, out, Vector2((float(gate[0]) + float(gate[1])) * 0.5, SOUTH - 1.0))
	b["rc"]["yard"] = rc
	for e in PoiFurniture.YARD_SET:
		if rng.randf() >= float(e.get("p", 1.0)):
			continue
		var nr: Array = e.get("n", [1, 1])
		for k in rng.randi_range(int(nr[0]), int(nr[1])):
			if not _place_entry(b, rc, e):
				break
	b["yard_rc"] = rc


# --- 5. containers and loot ---------------------------------------------------------------

const LOCKED_OK := ["stockroom", "storage", "office", "armoury", "pharmacy", "evidence", "lockers", "hut"]


static func _stage_containers(b: Dictionary) -> void:
	var rng: RandomNumberGenerator = b["rng"]
	var a: Dictionary = b["arch"]
	var L: Dictionary = b["L"]
	# a minimum to search: boxes where there is room
	var tries := 0
	while (L["containers"] as Array).size() < MIN_CONTAINERS and tries < 12:
		tries += 1
		var rooms: Array = (b["rooms"] as Array).duplicate()
		rooms.sort_custom(func(p, q): return (p["rect"] as Rect2).get_area() > (q["rect"] as Rect2).get_area())
		var placed := false
		for r in rooms:
			var type := "boxes" if b["family"] != "industry" else "crate"
			if _place_entry(b, _rc(b, r), {"piece": type, "box": {"label": "cardboard boxes" if type == "boxes" else "crate", "holds": []}}):
				placed = true
				break
		if not placed:
			break
	var dark := {}
	for r in b["rooms"]:
		if r["dark"]:
			dark[r["id"]] = true
	var any_locked := false
	for c in L["containers"]:
		if c.get("stash", false):
			if dark.has(c["room"]) and c["needs"] == "":
				c["needs"] = "flashlight"
			continue
		if c["room"] == b["locked_room"] and rng.randf() < 0.7:
			c["table"] = "locked"
			any_locked = true
		if dark.has(c["room"]):
			c["needs"] = "flashlight"
			c["weight"] = float(c["weight"]) * 1.4
	if not any_locked:
		var cands := (L["containers"] as Array).filter(func(c): return not c.get("stash", false) and _room(b, c["room"]).get("type", "") in LOCKED_OK)
		if not cands.is_empty():
			var c: Dictionary = cands[rng.randi() % cands.size()]
			c["table"] = "locked"
			if c["needs"] == "":
				c["needs"] = "crowbar"
				c["noise"] = 2
	# picked clean before Eli came
	var plain := (L["containers"] as Array).filter(func(c): return not c.get("stash", false) and c["table"] == "loot")
	var share := float(a.get("picked", 0.3))
	for c in plain:
		if rng.randf() < share:
			c["picked"] = true
	var left := plain.filter(func(c): return not c["picked"])
	if left.size() < 2 and plain.size() >= 2:
		for c in plain.slice(0, 2):
			c["picked"] = false
	if plain.size() >= 4 and plain.all(func(c): return not c["picked"]):
		plain[plain.size() - 1]["picked"] = true
	# loose pickups lying about
	var picks: Array = a.get("pickups", [])
	var k := 0
	for p in picks:
		if rng.randf() > 0.6:
			continue
		var at := _free_point(b, rng)
		if at == Vector2.INF:
			continue
		PoiLayouts._pickup(L, "loose_%d" % k, str(p[0]), int(p[1]), at)
		k += 1


## A free floor point in a random room (clear of furniture and doorways).
static func _free_point(b: Dictionary, rng: RandomNumberGenerator) -> Vector2:
	var rooms: Array = b["rooms"]
	for t in 30:
		var r: Dictionary = rooms[rng.randi() % rooms.size()]
		var rc := _rc(b, r)
		var inner: Rect2 = (rc["inner"] as Rect2).grow(-0.35)
		if inner.size.x <= 0.0 or inner.size.y <= 0.0:
			continue
		var p := Vector2(rng.randf_range(inner.position.x, inner.end.x), rng.randf_range(inner.position.y, inner.end.y))
		var probe := Rect2(p - Vector2(0.3, 0.3), Vector2(0.6, 0.6))
		if not _hits(rc["blocks"], probe) and not _hits(rc["reserved"], probe):
			return p
	return Vector2.INF


# --- 6. inhabitants: dormant spots, hiding, wander, peek, lights, story -------------------------------

static func _stage_inhabitants(b: Dictionary) -> void:
	var rng: RandomNumberGenerator = b["rng"]
	var a: Dictionary = b["arch"]
	var L: Dictionary = b["L"]
	var entry := _entry_guess(b)
	L["entry"] = entry
	var g := _grid(L)
	_flood(g, entry)
	b["grid"] = g
	var dz: Dictionary = a.get("danger", {})
	# hiding places: far from the entry, private and dark rooms first
	var rooms: Array = (b["rooms"] as Array).duplicate()
	rooms.sort_custom(func(p, q): return _hide_rank(p, entry) > _hide_rank(q, entry))
	var hide := []
	for r in rooms:
		if hide.size() >= int(dz.get("hide", 3)):
			break
		var p := _spot_in(b, g, r, rng, entry, 4.0, hide)
		if p != Vector2.INF:
			hide.append(p)
	L["hide"] = hide
	# wander areas: hubs big enough to walk about in
	for r in b["rooms"]:
		var rc: Rect2 = r["rect"]
		if (int(r["hub"]) >= 3 or r["type"] == "corridor") and rc.size.x >= 2.0 and rc.size.y >= 2.0:
			L["wander"].append(rc.grow(-0.6))
	if b.has("hut"):
		L["wander"].append((b["bounds"] as Rect2).grow(-1.0))
	if (L["wander"] as Array).is_empty():
		L["wander"].append(_room(b, b["entry_room"]).get("rect", b["bounds"]).grow(-0.6))
	_dormant(b, g, entry)
	_peeks(b)
	_doorways(b)
	_lights(b)
	_story(b, g, entry)


static func _hide_rank(r: Dictionary, entry: Vector2) -> float:
	return (r["rect"] as Rect2).get_center().distance_to(entry) * 0.2 + (2.0 if r["private"] else 0.0) + (1.5 if r["dark"] else 0.0)


## Where Eli will arrive (before the exterior stage knows): outside the front
## door, the apartment's stair end, or the yard gate.
static func _entry_guess(b: Dictionary) -> Vector2:
	if b.has("apt_entry"):
		return b["apt_entry"]
	if not (b["front"] as Array).is_empty():
		return Vector2((float(b["front"][0]) + float(b["front"][1])) * 0.5, SOUTH + 1.4)
	return Vector2((b["bounds"] as Rect2).get_center().x, SOUTH + 1.4)


## A reachable point inside room r with space round it, at least `away` from
## `from` and 1.5 m from `others`.
static func _spot_in(b: Dictionary, g: Dictionary, r: Dictionary, rng: RandomNumberGenerator, from: Vector2, away: float, others: Array) -> Vector2:
	var inner := (r["rect"] as Rect2).grow(-0.45)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return Vector2.INF
	for t in 24:
		var p := Vector2(rng.randf_range(inner.position.x, inner.end.x), rng.randf_range(inner.position.y, inner.end.y))
		if p.distance_to(from) < away or not _roomy(g, p):
			continue
		var ok := true
		for o in others:
			if (o as Vector2).distance_to(p) < 1.5:
				ok = false
				break
		if ok:
			return p
	return Vector2.INF


static func _pick_weighted(w: Dictionary, rng: RandomNumberGenerator) -> String:
	var sum := 0.0
	for k in w:
		sum += float(w[k])
	var x := rng.randf() * sum
	for k in w:
		x -= float(w[k])
		if x <= 0.0:
			return k
	return w.keys().back()


static func _dormant(b: Dictionary, g: Dictionary, entry: Vector2) -> void:
	var rng: RandomNumberGenerator = b["rng"]
	var dz: Dictionary = b["arch"].get("danger", {})
	var nr: Array = dz.get("dormant", [1, 3])
	var want := rng.randi_range(int(nr[0]), int(nr[1]))
	var weights: Dictionary = dz.get("behaviours", {"sway": 1, "stare": 1, "bang": 1, "tap": 1, "circle": 1})
	var out := []
	var used_rooms := {}
	var guard := 0
	while out.size() < want and guard < want * 6:
		guard += 1
		var beh := _pick_weighted(weights, rng)
		var s := _dormant_spot(b, g, beh, entry, out, used_rooms, rng)
		if s.is_empty() and beh != "sway":
			s = _dormant_spot(b, g, "sway", entry, out, used_rooms, rng)
		if s.is_empty():
			continue
		used_rooms[s["room"]] = int(used_rooms.get(s["room"], 0)) + 1
		out.append(s)
	b["L"]["dormant"] = out


static func _dormant_spot(b: Dictionary, g: Dictionary, beh: String, entry: Vector2, taken: Array, used: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var cands := []
	var L: Dictionary = b["L"]
	match beh:
		"circle":
			for c in b["centres"]:
				var r: Rect2 = c["rect"]
				var rad := maxf(r.size.x, r.size.y) * 0.5 + 0.65
				var ok := true
				for k in 12:
					var q := r.get_center() + Vector2.from_angle(TAU * k / 12.0) * rad
					if not _reach(g, q):
						ok = false
						break
				if ok:
					var at := r.get_center() + Vector2.from_angle(rng.randf() * TAU) * rad
					cands.append({"at": at, "target": r.get_center(), "radius": rad, "room": c["room"]})
		"tap", "bang":
			for c in (L["containers"] as Array) + (L["props"] as Array):
				var h := float(c["h"])
				if (beh == "tap" and h < 0.8) or (beh == "bang" and h < 1.2) or not c.has("facing"):
					continue
				var rect: Rect2 = c["rect"]
				var f: Vector2 = PoiLayouts.FRONT.get(str(c["facing"]), Vector2(0, 1))
				var half := (rect.size.y if f.y != 0.0 else rect.size.x) * 0.5
				var at := rect.get_center() + f * (half + 0.5)
				if _reach(g, at):
					cands.append({"at": at, "target": rect.get_center() + f * half, "radius": 0.0, "room": str(c.get("room", ""))})
			if beh == "bang":
				for r in b["rooms"]:
					var rc: Rect2 = (r["rect"] as Rect2).grow(-0.1)
					for side in SIDES:
						var t := rng.randf_range(0.25, 0.75)
						var wp := Vector2.ZERO
						match side:
							"N":
								wp = Vector2(lerpf(rc.position.x, rc.end.x, t), rc.position.y)
							"S":
								wp = Vector2(lerpf(rc.position.x, rc.end.x, t), rc.end.y)
							"W":
								wp = Vector2(rc.position.x, lerpf(rc.position.y, rc.end.y, t))
							"E":
								wp = Vector2(rc.end.x, lerpf(rc.position.y, rc.end.y, t))
						var at: Vector2 = wp - NORMAL[side] * 0.5
						if _reach(g, at) and not _on_gap(b, wp):
							cands.append({"at": at, "target": wp, "radius": 0.0, "room": r["id"]})
		"stare":
			for w in b["windows"]:
				var c := _gap_centre(w)
				var at: Vector2 = c - NORMAL[w["side"]] * 0.9
				if _reach(g, at):
					cands.append({"at": at, "target": c, "radius": 0.0, "room": w["room"]})
			for r in b["rooms"]:
				var rc: Rect2 = (r["rect"] as Rect2).grow(-0.1)
				var corner: Vector2 = [rc.position, Vector2(rc.end.x, rc.position.y), Vector2(rc.position.x, rc.end.y), rc.end][rng.randi() % 4]
				var at: Vector2 = corner + (rc.get_center() - corner).normalized() * 0.9
				if _reach(g, at):
					cands.append({"at": at, "target": corner, "radius": 0.0, "room": r["id"]})
		_:
			var rooms: Array = (b["rooms"] as Array).duplicate()
			if b.has("yard_rc"):
				rooms.append(b["yard_rc"]["room"])
			for r in rooms:
				var p := _spot_in(b, g, r, rng, entry, 0.0, [])
				if p != Vector2.INF:
					cands.append({"at": p, "target": p, "radius": 0.0, "room": r["id"]})
	var best := {}
	var best_s := -INF
	for c in cands:
		var at: Vector2 = c["at"]
		if at.distance_to(entry) < 3.5:
			continue
		var ok := true
		for o in taken:
			if (o["at"] as Vector2).distance_to(at) < 1.5:
				ok = false
				break
		if not ok:
			continue
		var s := rng.randf() - float(used.get(c["room"], 0)) * 1.5
		if s > best_s:
			best_s = s
			best = c
	if best.is_empty():
		return {}
	return {"at": best["at"], "behaviour": beh, "target": best["target"], "radius": float(best["radius"]), "room": best["room"]}


static func _gap_centre(w: Dictionary) -> Vector2:
	var m := (float(w["from"]) + float(w["to"])) * 0.5
	return Vector2(m, float(w["line"])) if int(w["axis"]) == 0 else Vector2(float(w["line"]), m)


static func _on_gap(b: Dictionary, p: Vector2) -> bool:
	for gp in b["gaps"]:
		var c := _gap_centre(gp)
		var half := (float(gp["to"]) - float(gp["from"])) * 0.5 + 0.4
		if int(gp["axis"]) == 0 and absf(p.y - float(gp["line"])) < 0.3 and absf(p.x - c.x) < half:
			return true
		if int(gp["axis"]) == 1 and absf(p.x - float(gp["line"])) < 0.3 and absf(p.y - c.y) < half:
			return true
	return false


static func _peeks(b: Dictionary) -> void:
	var L: Dictionary = b["L"]
	if b["arch"].get("apartment", false):
		return
	var yard := HousePlan.YARD.grow(-0.6)
	var hut: Rect2 = b.get("hut", Rect2())
	for w in b["windows"]:
		if (L["peek"] as Array).size() >= 6:
			break
		if float(w["sill"]) >= 1.4:
			continue                       # a small high window: nobody looks in by it
		var c := _gap_centre(w)
		var n: Vector2 = NORMAL[w["side"]]
		var at := c + n * 0.75
		var r: Rect2 = _room(b, w["room"])["rect"]
		var depth := r.size.y if n.y != 0.0 else r.size.x
		var look := c - n * minf(2.5, depth * 0.6)
		if yard.has_point(at) and (hut.size.x == 0.0 or not hut.has_point(at)):
			L["peek"].append({"at": at, "look": look})


static func _doorways(b: Dictionary) -> void:
	var L: Dictionary = b["L"]
	for g in b["gaps"]:
		if not ("out" in g["rooms"]) or g["kind"] == "window":
			continue
		var c := _gap_centre(g)
		var side := "S"
		if g.get("back", false):
			side = "N"
		elif int(g["axis"]) == 1:
			side = "E" if c.x > (b["bounds"] as Rect2).get_center().x else "W"
		L["doorways"].append(c + NORMAL[side] * 0.75)


static func _lights(b: Dictionary) -> void:
	var rng: RandomNumberGenerator = b["rng"]
	var L: Dictionary = b["L"]
	var main := _room(b, b["entry_room"])
	if not main.is_empty() and rng.randf() < 0.75:
		var rc: Rect2 = main["rect"]
		PoiLayouts._light(L, rc.get_center(), 2.5, "tube", 0xe4ecff, 1.2, rng.randf() < 0.6, {"yaw": 0.0 if rc.size.x >= rc.size.y else PI * 0.5})
	var sr := _room(b, b["stash_room"])
	if not sr.is_empty() and sr["id"] != b["entry_room"] and rng.randf() < 0.5:
		var rc: Rect2 = sr["rect"]
		var red := rng.randf() < 0.5
		PoiLayouts._light(L, Vector2(rc.get_center().x, rc.position.y + 0.2), 2.3, "emergency", 0xff3b2e if red else 0x55ff88, 0.6)
	for p in L["props"] + L["containers"]:
		if (L["lights"] as Array).size() >= 3:
			break
		if p["type"] in ["desk", "counter"] and rng.randf() < 0.35:
			var lamp: bool = p["type"] == "desk"
			PoiLayouts._light(L, (p["rect"] as Rect2).get_center(), float(p["h"]), "lamp" if lamp else "lantern", 0xffd7a0 if lamp else 0xffd29a, 0.8)


static func _story(b: Dictionary, g: Dictionary, entry: Vector2) -> void:
	var rng: RandomNumberGenerator = b["rng"]
	var L: Dictionary = b["L"]
	var a: Dictionary = b["arch"]
	if str(a.get("entrance", "")) == "open" or bool(a.get("storefront", false)):
		var f: Array = b["front"]
		if not f.is_empty():
			PoiLayouts._tell(L, "glass", Vector2((float(f[0]) + float(f[1])) * 0.5, SOUTH - 0.7), {"w": 2.0, "d": 0.8})
	for r in b["rooms"]:
		var t := str(r["type"])
		var kind := ""
		var opts := {}
		if t in ["office", "lobby", "evidence", "staff", "waiting"] and rng.randf() < 0.6:
			kind = "papers"
			opts = {"r": 0.6, "n": rng.randi_range(6, 14)}
		elif t in ["sales", "stockroom", "storage", "kitchen"] and rng.randf() < 0.45:
			kind = "spill"
			opts = {"yaw": rng.randf_range(-PI, PI)}
		elif t in ["living", "dining", "waiting", "lobby", "work_floor", "staff"] and rng.randf() < 0.45:
			kind = "toppled"
			opts = {"piece": "chair" if rng.randf() < 0.6 else "stool", "yaw": rng.randf_range(-PI, PI)}
		elif t in ["hall", "work_floor", "bay", "stockroom"] and rng.randf() < 0.4:
			kind = "pallet"
			opts = {"load": ["", "bags", "boxes"][rng.randi() % 3], "yaw": rng.randf_range(-0.4, 0.4)}
		elif r["private"] and rng.randf() < 0.15:
			kind = "camp"
		if kind == "":
			continue
		var p := _spot_in(b, g, r, rng, entry, 0.0, [])
		if p == Vector2.INF:
			continue
		var rc := _rc(b, r)
		var probe := Rect2(p - Vector2(0.7, 0.7), Vector2(1.4, 1.4))
		if _hits(rc["blocks"], probe) or _hits(rc["reserved"], probe) or _hits(rc["clears"], probe):
			continue
		rc["blocks"].append(probe)
		PoiLayouts._tell(L, kind, p, opts)
	# a barricade someone began at a window and gave up on
	if not (b["windows"] as Array).is_empty() and rng.randf() < 0.3:
		var w: Dictionary = b["windows"][rng.randi() % (b["windows"] as Array).size()]
		var c := _gap_centre(w)
		var at: Vector2 = c - NORMAL[w["side"]] * 0.32
		var rc := _rc(b, _room(b, w["room"]))
		var probe := Rect2(at - Vector2(0.6, 0.6), Vector2(1.2, 1.2))
		if not _hits(rc["blocks"], probe) and not _hits(rc["reserved"], probe):
			PoiLayouts._tell(L, "barricade", at, {"lean": w["side"], "len": minf(float(w["to"]) - float(w["from"]), 1.4)})


# --- 7. exterior --------------------------------------------------------------------------

static var _class_cache := {}


## A global script class by name, or null (agents' classes that may not exist yet).
static func script_class(name: String) -> Script:
	if _class_cache.has(name):
		return _class_cache[name]
	var s: Script = null
	for c in ProjectSettings.get_global_class_list():
		if str(c.get("class", "")) == name:
			s = load(str(c["path"])) as Script
			break
	_class_cache[name] = s
	return s


static func _stage_exterior(b: Dictionary) -> void:
	var L: Dictionary = b["L"]
	var rng: RandomNumberGenerator = b["rng"]
	L["bounds"] = b["bounds"]
	L["exit_kind"] = "dark" if b.has("dark_exit") else "car"
	if b.has("dark_exit"):
		L["dark_exit"] = b["dark_exit"]
	L["rooms"] = []
	for r in b["rooms"]:
		L["rooms"].append({"id": r["id"], "rect": r["rect"], "dark": r["dark"], "type": r["type"]})
	_fallback_exterior(b)
	var ext := script_class("PoiExterior")
	if ext != null:
		ext.call("decorate", L, b["setup"], rng)


## The small default outside (X's PoiExterior replaces it): the arrival point
## before the entrance, the way home, the car beside the entry, the street.
static func _fallback_exterior(b: Dictionary) -> void:
	var L: Dictionary = b["L"]
	var bo: Rect2 = b["bounds"]
	L["edges"] = PoiLayouts.EDGES.duplicate()
	if b.has("dark_exit"):
		L["entry"] = b["apt_entry"]
		L["exits"] = [(b["dark_exit"] as Rect2).get_center()]
		L["car"] = {}
		return
	var fx := bo.get_center().x
	if not (b["front"] as Array).is_empty():
		fx = (float(b["front"][0]) + float(b["front"][1])) * 0.5
	L["entry"] = Vector2(fx, SOUTH + 1.4)
	var cx := fx - 6.6 if fx - 6.6 >= -5.0 else fx + 2.2
	PoiLayouts._car(L, cx, SOUTH + 1.9)
	var ex := clampf(fx + (4.5 if cx < fx else -4.5), -4.0, 18.0)
	L["exits"] = [Vector2(ex, 12.9)]
	if not (b["back"] as Dictionary).is_empty() and float(b["back"]["z"]) - 1.3 > -5.4:
		L["exits"].append(Vector2(float(b["back"]["x"]), float(b["back"]["z"]) - 1.3))
	L["wander"].append(Rect2(-3.0, SOUTH + 1.3, 20.0, 2.2))


# --- validation ---------------------------------------------------------------------------

## The coarse walkability grid of a layout: walls (doors and open gaps
## passable, windows not), furniture that blocks, trees, the car.
static func _grid(L: Dictionary) -> Dictionary:
	var w := int(NAV_RECT.size.x / CELL)
	var h := int(NAV_RECT.size.y / CELL)
	var free := PackedByteArray()
	free.resize(w * h)
	free.fill(1)
	var g := {"w": w, "h": h, "free": free, "seen": PackedByteArray()}
	for wall in L.get("walls", []):
		var a: Vector2 = wall["a"]
		var c: Vector2 = wall["b"]
		var horiz := is_equal_approx(a.y, c.y)
		var line := a.y if horiz else a.x
		var ivs := [[minf(a.x, c.x) - 0.1 if horiz else minf(a.y, c.y) - 0.1, maxf(a.x, c.x) + 0.1 if horiz else maxf(a.y, c.y) + 0.1]]
		for gp in wall.get("gaps", []):
			if gp["kind"] != "window":
				ivs = _cut(ivs, float(gp["from"]), float(gp["to"]))
		for iv in ivs:
			var r := Rect2(iv[0], line - 0.1, iv[1] - iv[0], 0.2) if horiz else Rect2(line - 0.1, iv[0], 0.2, iv[1] - iv[0])
			_mark(g, r.grow(BODY))
	for p in L.get("props", []):
		if p.get("block", true):
			_mark(g, (p["rect"] as Rect2).grow(BODY))
	for c in L.get("containers", []):
		_mark(g, (c["rect"] as Rect2).grow(BODY))
	for t in L.get("trees", []):
		_mark(g, Rect2((t as Vector2) - Vector2(0.25, 0.25), Vector2(0.5, 0.5)).grow(BODY))
	var car: Dictionary = L.get("car", {})
	if not car.is_empty():
		_mark(g, (car["rect"] as Rect2).grow(BODY))
	for s in L.get("story", []):
		if s.get("type", "") == "empty_rack":
			_mark(g, (s["rect"] as Rect2).grow(BODY))
	return g


static func _mark(g: Dictionary, r: Rect2) -> void:
	var w: int = g["w"]
	var h: int = g["h"]
	var i0 := maxi(int(ceil((r.position.x - NAV_RECT.position.x) / CELL - 0.5)), 0)
	var i1 := mini(int(floor((r.end.x - NAV_RECT.position.x) / CELL - 0.5)), w - 1)
	var j0 := maxi(int(ceil((r.position.y - NAV_RECT.position.y) / CELL - 0.5)), 0)
	var j1 := mini(int(floor((r.end.y - NAV_RECT.position.y) / CELL - 0.5)), h - 1)
	var free: PackedByteArray = g["free"]
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			free[j * w + i] = 0
	g["free"] = free


static func _cell(g: Dictionary, p: Vector2) -> int:
	var i := int(floor((p.x - NAV_RECT.position.x) / CELL))
	var j := int(floor((p.y - NAV_RECT.position.y) / CELL))
	if i < 0 or j < 0 or i >= int(g["w"]) or j >= int(g["h"]):
		return -1
	return j * int(g["w"]) + i


static func _flood(g: Dictionary, from: Vector2) -> void:
	var w: int = g["w"]
	var h: int = g["h"]
	var free: PackedByteArray = g["free"]
	var seen := PackedByteArray()
	seen.resize(w * h)
	seen.fill(0)
	var start := _cell(g, from)
	if start < 0:
		g["seen"] = seen
		return
	if free[start] == 0:
		var found := -1
		for dj in range(-3, 4):
			for di in range(-3, 4):
				var c := start + dj * w + di
				if c >= 0 and c < w * h and free[c] == 1:
					found = c
					break
			if found >= 0:
				break
		if found < 0:
			g["seen"] = seen
			return
		start = found
	var q := PackedInt32Array([start])
	seen[start] = 1
	var k := 0
	while k < q.size():
		var c := q[k]
		k += 1
		var i := c % w
		var j := c / w
		if i > 0 and free[c - 1] == 1 and seen[c - 1] == 0:
			seen[c - 1] = 1
			q.append(c - 1)
		if i < w - 1 and free[c + 1] == 1 and seen[c + 1] == 0:
			seen[c + 1] = 1
			q.append(c + 1)
		if j > 0 and free[c - w] == 1 and seen[c - w] == 0:
			seen[c - w] = 1
			q.append(c - w)
		if j < h - 1 and free[c + w] == 1 and seen[c + w] == 0:
			seen[c + w] = 1
			q.append(c + w)
	g["seen"] = seen


## Reachable: the point's cell, or one next to it, was reached from the entry.
static func _reach(g: Dictionary, p: Vector2) -> bool:
	var c := _cell(g, p)
	if c < 0:
		return false
	var seen: PackedByteArray = g["seen"]
	var w: int = g["w"]
	for dj in [0, -1, 1]:
		for di in [0, -1, 1]:
			var k: int = c + dj * w + di
			if k >= 0 and k < seen.size() and seen[k] == 1:
				return true
	return false


## Reachable with the cells round it free too (somebody can stand there).
static func _roomy(g: Dictionary, p: Vector2) -> bool:
	var c := _cell(g, p)
	if c < 0:
		return false
	var seen: PackedByteArray = g["seen"]
	var w: int = g["w"]
	for k in [c, c - 1, c + 1, c - w, c + w]:
		if k < 0 or k >= seen.size() or seen[k] == 0:
			return false
	return true


## Every generated layout must pass: the exits, every room, every container's
## front, the stash, every dormant spot and pickup reachable from the entry;
## exactly one stash; unique container ids. {"ok": bool, "problems": [text]}.
static func validate(L: Dictionary) -> Dictionary:
	var problems := []
	var g := _grid(L)
	var entry: Vector2 = L.get("entry", Vector2(7, 11))
	_flood(g, entry)
	if not _reach(g, entry):
		problems.append("the entry %s is blocked" % entry)
	for e in L.get("exits", []):
		if not _reach(g, e):
			problems.append("exit %s unreachable" % e)
	var car: Dictionary = L.get("car", {})
	if not car.is_empty() and not _reach(g, car["cargo"]):
		problems.append("the car's boot unreachable")
	if L.has("dark_exit") and not _reach(g, (L["dark_exit"] as Rect2).get_center()):
		problems.append("the dark exit unreachable")
	for r in L.get("rooms", []):
		var rc: Rect2 = (r["rect"] as Rect2).grow(-0.2)
		var ok := false
		var y := rc.position.y + CELL * 0.5
		while y < rc.end.y and not ok:
			var x := rc.position.x + CELL * 0.5
			while x < rc.end.x:
				var c := _cell(g, Vector2(x, y))
				if c >= 0 and (g["seen"] as PackedByteArray)[c] == 1:
					ok = true
					break
				x += CELL
			y += CELL
		if not ok:
			problems.append("room %s unreachable" % r["id"])
	var ids := {}
	var stashes := 0
	for c in L.get("containers", []):
		if ids.has(c["id"]):
			problems.append("container id %s twice" % c["id"])
		ids[c["id"]] = true
		if c.get("stash", false):
			stashes += 1
		if not _reach(g, PoiLayouts.front_point(c["rect"], c["facing"])):
			problems.append("container %s: its front is unreachable" % c["id"])
	if stashes != 1:
		problems.append("%d stashes" % stashes)
	for d in L.get("dormant", []):
		if not _reach(g, d["at"]):
			problems.append("dormant spot %s unreachable" % d["at"])
	for p in L.get("pickups", []):
		if not _reach(g, p["at"]):
			problems.append("pickup %s unreachable" % p["id"])
	return {"ok": problems.is_empty(), "problems": problems}


# --- the fallback and diagnostics ---------------------------------------------------------------

const FALLBACK_VARIANT := {"residential": "house", "commercial": "shop", "industry": "depot", "public": "clinic", "outdoor": "depot"}


## The simple building every archetype falls back to (the old placeholder,
## with a stash and the new keys).
static func fallback(setup: Dictionary) -> Dictionary:
	var arch := str(setup.get("archetype", "house_small"))
	var fam := PoiArchetypes.family_of(arch)
	var L := PoiLayouts.build({"variant": FALLBACK_VARIANT.get(fam, "house")})
	for c in L["containers"]:
		if c["table"] == "locked":
			c["table"] = "stash"
			c["stash"] = true
			c["needs"] = "crowbar"
			L["stash"] = c["id"]
			break
	L["archetype"] = arch
	L["bounds"] = Rect2(3, 2, 8, 6)
	L["exit_kind"] = "car"
	L["dormant"] = [{"at": Vector2(5.0, 4.2), "behaviour": "sway", "target": Vector2(5.0, 4.2), "radius": 0.0, "room": "left"},
		{"at": Vector2(9.6, 3.0), "behaviour": "stare", "target": Vector2(10.9, 3.0), "radius": 0.0, "room": "right"}]
	for r in L["rooms"]:
		r["type"] = "storage"
	L["fallback"] = true
	return L


static func _finish_diag(L: Dictionary, setup: Dictionary, attempts: int, ms: float) -> void:
	var stash_at := Vector2.INF
	for c in L.get("containers", []):
		if c.get("stash", false):
			stash_at = (c["rect"] as Rect2).get_center()
	L["diag"] = {"seed": int(setup.get("seed", 0)), "rooms": (L.get("rooms", []) as Array).size(),
		"furniture": (L.get("props", []) as Array).size() + (L.get("containers", []) as Array).size(),
		"containers": (L.get("containers", []) as Array).size(), "stash_at": stash_at, "ms": ms, "attempts": attempts + 1,
		"archetype": str(setup.get("archetype", "")), "version": VERSION, "fallback": bool(L.get("fallback", false))}
