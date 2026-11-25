class_name HouseSupport
extends RefCounted
## Refinement 01 (S): a lightweight structural-support model for the house's
## roof and upper floor (no physics, no per-voxel load).
##
## - The outer walls carry the roof (and the upper floor, once built). The
##   inner walls carry nothing: any of them can go without consequences.
## - The roof and the upper deck are divided into ZONES (the rooms; the
##   living room in two halves). A zone's outer sides lie on the footprint's
##   perimeter lines.
## - A 1 m section of a perimeter line bears if its wall section stands at
##   MIN_INTEGRITY or more of its design (doors and windows have lintels and
##   count; a knocked-out section doesn't), or if a wall the player built
##   runs parallel to it at most PROP_REACH m inside (a short wall run props
##   the roof up before an outer wall comes out).
## - A run of FAIL_RUN or more consecutive non-bearing metres on a perimeter
##   line fails the zones it overlaps by at least two metres (or by their
##   whole side): their roof comes down, and so does the upper floor over
##   them (its deck, the walls and objects on it). With an upper floor, the
##   upper storey's own perimeter carries the roof the same way. A run one
##   metre shorter "strains" the zone (a warning).
## - Evaluated only after a structural change (HouseWorld.structure_changed,
##   debounced to once per frame by HouseWorld._process), never continuously.
## - Saved: the zones whose roof is gone ("collapsed" in the world save).
##   The upper deck's loss is in the storey's own voxel save.
##
## Signals carry {"zone", "name", "rect", "roof": bool, "upper": bool,
## "storeys": [storeys whose bodies are hit], "text"}; the game shows the
## text and hurts whoever stands there (src/world/game_support.gd).
##
## Exp 005 (V): a chain of storeys 0, +1, +2 (`storeys`; `upper` is +1). Each
## storey's perimeter carries everything above it: when storey s fails over a
## zone, the decks of every storey above s fall there (with their walls and
## objects), and the roof (on the topmost storey) too. Pillars (GameLevels,
## `levels`) prop a perimeter line like a built wall: a standing pillar at
## most PROP_REACH + 0.5 m inside props the line's sections within 1 m of it.
## Upper storeys also keep a simple support grid of 1 m floor cells: a cell
## is held if it lies on the footprint's edge, or a wall or pillar of the
## storey below stands at its edges, or it joins a held cell; floor cells
## that aren't held fall (no floating rooms). tile_support_reason() is build
## mode's check for a new tile.

## Exp 006 (B), foundations: a wall the player built OUTSIDE a perimeter
## line (at most PROP_REACH m out, e.g. the outer wall of an extension after
## the house wall came out) props it too, but only when it stands on a
## foundation or footing (HouseWorld.is_founded); on bare ground it carries
## nothing. Inside, every wall stands on the house floor. Raising a third
## level (+2) needs a stone footing along the house: at least FOOTING_PER_SIDE
## metres of stone foundation within FOOTING_REACH m outside each outer wall
## (footing_reason; checked when the storey is built, not afterwards).

signal collapsed(info: Dictionary)
signal strained(info: Dictionary)

const FAIL_RUN := 3                ## metres of perimeter without a bearing section that bring a zone down
const PROP_REACH := 2              ## m inside a perimeter line where a built wall still props it
const MIN_INTEGRITY := 0.5
const MIN_VOXELS := 30             ## a section's design below this is no wall (a knocked-out section)
const ROOF_EAVES := 0.65           ## the roof overhangs the footprint by 0.55 m
const DECK_EDGE := 0.3             ## the upper deck and its outer walls past the footprint line
const MINOR_VOXELS := 1200         ## fewer fallen deck voxels (a few re-laid tiles) hurt nobody
const FOOTING_PER_SIDE := 2        ## Exp 006 (B): metres of stone footing per outer wall for a third level
const FOOTING_REACH := 1.6         ## Exp 006 (B): m outside the wall line a footing tile's centre may be
const ZONES := [
	{"id": "bedroom", "name": "the bedroom", "rect": Rect2(0, 0, 5, 4)},
	{"id": "bathroom", "name": "the bathroom", "rect": Rect2(5, 0, 3, 4)},
	{"id": "kitchen", "name": "the kitchen", "rect": Rect2(8, 0, 6, 4)},
	{"id": "living", "name": "the living room", "rect": Rect2(0, 4, 5, 5)},
	{"id": "dining", "name": "the dining area", "rect": Rect2(5, 4, 5, 5)},
	{"id": "utility", "name": "the utility room", "rect": Rect2(10, 4, 4, 5)},
]
## Footprint perimeter lines: axis and line of their sections, extent, inward step.
const LINES := {
	"north": {"axis": 0, "line": 0, "from": 0, "to": 14, "in": 1},
	"south": {"axis": 0, "line": 9, "from": 0, "to": 14, "in": -1},
	"west": {"axis": 1, "line": 0, "from": 0, "to": 9, "in": 1},
	"east": {"axis": 1, "line": 14, "from": 0, "to": 9, "in": -1},
}

var world: HouseWorld              ## the ground floor
var storeys := {}                  ## Exp 005 (V): storey (>= 1) -> its LevelWorld
var levels: Object = null          ## Exp 005 (V): GameLevels (pillars_on(w)); optional
var upper: HouseWorld:             ## the first upper storey (a LevelWorld) or null
	get:
		return storeys.get(1)
var roof_gone := {}                ## zone id -> true: that part of the roof collapsed (saved)
var strained_zones := {}           ## zone id -> true (warned once per strain)
var dirty := false
var collapses := 0                 ## collapse events (tests)
static var _ring: Array = []
static var _zone_ring := {}
var last_ms := 0.0


func _init(w: HouseWorld) -> void:
	world = w
	w.structure_changed.connect(mark_dirty)


func mark_dirty() -> void:
	dirty = true


## Links the upper storey (game_support.gd calls this when it is built or
## loaded); its changes count as structural changes too. Linking alone
## evaluates nothing (a loaded save stands as it was saved).
func set_upper(u: HouseWorld) -> void:
	set_storey(1, u)


## Exp 005 (V): links storey s (>= 1) or unlinks it (null).
func set_storey(s: int, u: HouseWorld) -> void:
	if storeys.get(s) == u:
		return
	if u == null:
		storeys.erase(s)
		return
	storeys[s] = u
	u.support = self
	if not u.structure_changed.is_connected(mark_dirty):
		u.structure_changed.connect(mark_dirty)


## The chain of storey worlds from the ground floor up, without gaps.
func chain() -> Array:
	var out := [world]
	var s := 1
	while storeys.has(s) and is_instance_valid(storeys[s]):
		out.append(storeys[s])
		s += 1
	return out


## HouseWorld._process: one evaluation per frame at most, only after changes.
func process() -> void:
	if dirty:
		evaluate()


# --- persistence -------------------------------------------------------------------------

func save_data() -> Array:
	var out := roof_gone.keys()
	out.sort()
	return out


## Restores the collapsed roof zones (unknown ids and bad data are ignored:
## an older save has everything standing).
func load_data(v: Variant) -> void:
	roof_gone.clear()
	if v is Array:
		for id in v:
			if id is String and zone(id).size() > 0:
				roof_gone[id] = true
	_update_roof()


# --- queries -----------------------------------------------------------------------------

static func zone(id: String) -> Dictionary:
	for z in ZONES:
		if z["id"] == id:
			return z
	return {}


static func zone_at(p: Vector2) -> Dictionary:
	for z in ZONES:
		if (z["rect"] as Rect2).has_point(p):
			return z
	return {}


## False under a collapsed part of the roof (ceiling lights fall with it).
func roof_intact_at(p: Vector2) -> bool:
	var z := zone_at(p)
	return z.is_empty() or not roof_gone.has(z["id"])


## Zone id -> {"fail": bool, "run": longest non-bearing run (m) on its outer sides}
## for one storey's perimeter. `skip`: a section treated as gone (previews).
func zone_states(w: HouseWorld, skip := Vector3i(-1, -1, -1)) -> Dictionary:
	var runs := _runs(w, skip)
	var out := {}
	for z in ZONES:
		var mine := _ring_of(z["id"])
		var worst := 0
		var fail := false
		for r in runs:
			var ov := 0
			for i in r:
				if mine.has(i):
					ov += 1
			if ov == 0:
				continue
			worst = maxi(worst, r.size())
			if r.size() >= FAIL_RUN and ov >= mini(2, mine.size()):
				fail = true
		out[z["id"]] = {"fail": fail, "run": worst}
	return out


## True if the perimeter section s carries load on storey world w (also
## through a built wall at most PROP_REACH m inside).
func line_bears(w: HouseWorld, key: String, k: int, skip := Vector3i(-1, -1, -1)) -> bool:
	var l: Dictionary = LINES[key]
	for d in PROP_REACH + 1:
		var s := Vector3i(l["axis"], l["line"] + d * int(l["in"]), k)
		if d > 0 and not w.built.has(s):
			continue
		if s != skip and section_bears(w, s):
			return true
	for d in range(1, PROP_REACH + 1):      # Exp 006 (B): founded walls outside the line
		var s := Vector3i(l["axis"], l["line"] - d * int(l["in"]), k)
		if s != skip and w.built.has(s) and section_bears(w, s) and w.is_founded(s):
			return true
	return _pillar_props(w, l, k)


## Exp 005 (V): a standing pillar inside line l, within reach of section k.
func _pillar_props(w: HouseWorld, l: Dictionary, k: int) -> bool:
	if levels == null or not levels.has_method("pillars_on"):
		return false
	for c in levels.pillars_on(w):
		var cc := Levels.cell_center(c)
		var across := (cc.y if int(l["axis"]) == 0 else cc.x) - float(l["line"])
		var along := (cc.x if int(l["axis"]) == 0 else cc.y) - (float(k) + 0.5)
		if across * float(l["in"]) > 0.0 and absf(across) <= PROP_REACH + 0.5 and absf(along) <= 1.01:
			return true
	return false


static func section_bears(w: HouseWorld, s: Vector3i) -> bool:
	var sec: Dictionary = w.sections.get(s, {})
	if sec.is_empty() or int(sec["design"]) < MIN_VOXELS:
		return false
	return float(sec["current"]) >= float(sec["design"]) * MIN_INTEGRITY


## True if section s on storey world w is part of what carries the roof
## (a perimeter section or a built wall propping one).
func is_bearing(w: HouseWorld, s: Vector3i) -> bool:
	for key in LINES:
		var l: Dictionary = LINES[key]
		if s.x != int(l["axis"]) or s.z < int(l["from"]) or s.z >= int(l["to"]):
			continue
		var d := (s.y - int(l["line"])) * int(l["in"])
		if d == 0 or (d > 0 and d <= PROP_REACH and w.built.has(s)):
			return true
		if d < 0 and d >= -PROP_REACH and w.built.has(s) and w.is_founded(s):      # Exp 006 (B)
			return true
	return false


## Build mode's demolish preview: "" or a warning about what removing
## section s of storey world w would bring down.
func demolish_warning(w: HouseWorld, s: Vector3i) -> String:
	if w == null or not chain().has(w) or not is_bearing(w, s) or not section_bears(w, s):
		return ""
	var before := zone_states(w)
	var after := zone_states(w, s)
	var names := []
	var strain := false
	for z in ZONES:
		var id: String = z["id"]
		if before[id]["fail"]:
			continue
		var lost: bool = roof_gone.has(id) and w == chain().back()
		if after[id]["fail"] and not lost:
			names.append(z["name"])
		elif after[id]["run"] == FAIL_RUN - 1 and before[id]["run"] < FAIL_RUN - 1 and not lost:
			strain = true
	if not names.is_empty():
		var what := "the storeys above and the roof" if w != chain().back() else "the roof"
		return "Load-bearing! %s over %s will come down." % [what.substr(0, 1).to_upper() + what.substr(1), " and ".join(names)]
	if strain:
		return "Load-bearing: the roof above will sag."
	return "Load-bearing wall (carries the roof)."


## Exp 006 (B): the outer walls (LINES keys) that lack a stone footing for a
## third level: fewer than FOOTING_PER_SIDE stone foundation tiles centred
## within FOOTING_REACH m outside the line, along it.
static func footing_missing(w: HouseWorld) -> Array:
	var out := []
	if w == null:
		return out
	for key in LINES:
		var l: Dictionary = LINES[key]
		var n := 0
		for t in w.foundations:
			if w.timber.has(t):
				continue
			var c := HouseWorld.seg_center(t)
			var across := (c.y if int(l["axis"]) == 0 else c.x) - float(l["line"])
			var along := c.x if int(l["axis"]) == 0 else c.y
			if across * float(l["in"]) < 0.0 and absf(across) <= FOOTING_REACH and along >= float(l["from"]) - 0.5 and along <= float(l["to"]) + 0.5:
				n += 1
		if n < FOOTING_PER_SIDE:
			out.append(key)
	return out


## Exp 006 (B): "" or why a third level can't go up yet (build mode).
static func footing_reason(w: HouseWorld) -> String:
	var miss := footing_missing(w)
	if miss.is_empty():
		return ""
	return "A third level needs a stone footing: lay %d m of stone foundation just outside the %s wall%s." % [
		FOOTING_PER_SIDE, ", ".join(miss), "s" if miss.size() > 1 else ""]


## One line per zone for the developer menu.
func status_text() -> String:
	var states := []
	for w in chain():
		states.append(zone_states(w))
	var parts := []
	for z in ZONES:
		var id: String = z["id"]
		var failing := false
		var run := 0
		for g in states:
			failing = failing or g[id]["fail"]
			run = maxi(run, g[id]["run"])
		var st := "standing"
		if roof_gone.has(id):
			st = "roof gone" + (", unsupported" if failing else "")
		elif failing:
			st = "UNSUPPORTED"
		elif run == FAIL_RUN - 1:
			st += ", strained"
		parts.append("%s: %s (gap %d m)" % [z["name"].trim_prefix("the "), st, run])
	if levels != null and levels.get("pillars") is Dictionary:
		var n := 0
		for s in levels.pillars:
			n += (levels.pillars[s] as Dictionary).size()
		if n > 0:
			parts.append("%d pillar%s" % [n, "" if n == 1 else "s"])
	return "; ".join(parts)


# --- evaluation --------------------------------------------------------------------------

## Brings down whatever lost its support (each zone at most once per
## part) and reports new strains.
func evaluate() -> void:
	dirty = false
	if world == null or world.grid == null:
		return
	var t0 := Time.get_ticks_usec()
	for s in storeys.keys():
		if not is_instance_valid(storeys[s]):
			storeys.erase(s)
	var ch := chain()
	var top := ch.size() - 1
	var states := []
	for w in ch:
		states.append(zone_states(w))
	var g: Dictionary = states[0]
	var fell := false
	for z in ZONES:
		var id: String = z["id"]
		var low := -1                    # the lowest storey whose walls fail over this zone
		for s in ch.size():
			if states[s][id]["fail"]:
				low = s
				break
		var info := {"zone": id, "name": z["name"], "rect": z["rect"], "roof": false, "upper": false, "storeys": []}
		var fallen := 0
		if low >= 0:
			for s in range(low + 1, ch.size()):
				fallen += _collapse_deck(ch[s], z, s)
		if fallen > 0:
			info["upper"] = true
			# a few tiles laid again over a zone that already came down: no harm done
			if fallen >= MINOR_VOXELS:
				info["storeys"] = range(low, top + 1)
		if low >= 0 and not roof_gone.has(id):
			roof_gone[id] = true
			_update_roof()
			_roof_fx(z)
			info["roof"] = true
			if info["storeys"].is_empty():
				info["storeys"] = [top]
		if info["roof"] or info["upper"]:
			strained_zones.erase(id)
			collapses += 1
			if info["upper"] and fallen < MINOR_VOXELS and not info["roof"]:
				info["text"] = "The new floor over %s has nothing to stand on: it fell." % z["name"]
			elif info["upper"]:
				info["text"] = "The floor%s above %s came down!" % ["s" if top - low > 1 else "", z["name"]]
			else:
				info["text"] = "The roof over %s gave way!" % z["name"]
			Sfx.play("structure/break", _centre(z, 2.4))
			Sfx.play("structure/crumble", _centre(z, 1.2))
			fell = true
			collapsed.emit(info)
			continue
		var run := 0
		for st in states:
			run = maxi(run, st[id]["run"])
		var at_risk := run == FAIL_RUN - 1 and not roof_gone.has(id)
		if at_risk and not strained_zones.has(id):
			strained_zones[id] = true
			info["text"] = "The outer wall of %s is failing: one more metre and the roof comes down." % z["name"]
			strained.emit(info)
		elif not at_risk:
			strained_zones.erase(id)
	for s in range(1, ch.size()):
		if _drop_unheld(ch[s], ch[s - 1], s) > 0:
			fell = true
	last_ms = (Time.get_ticks_usec() - t0) / 1000.0
	if fell:
		world.structure_changed.emit()        # the roof is part of the structure (lights, listeners)


## The perimeter as one closed ring of 1 m sections, clockwise from the
## north-west corner: [line key, k] (runs continue round the corners).
static func ring() -> Array:
	if _ring.is_empty():
		for k in range(0, 14):
			_ring.append(["north", k])
		for k in range(0, 9):
			_ring.append(["east", k])
		for k in range(13, -1, -1):
			_ring.append(["south", k])
		for k in range(8, -1, -1):
			_ring.append(["west", k])
	return _ring


## Ring indices of zone `id`'s outer sides (cached).
static func _ring_of(id: String) -> Dictionary:
	if not _zone_ring.has(id):
		var out := {}
		var sides := _sides(zone(id)["rect"])
		var rg := ring()
		for i in rg.size():
			for side in sides:
				if rg[i][0] == side[0] and int(rg[i][1]) >= int(side[1]) and int(rg[i][1]) < int(side[2]):
					out[i] = true
		_zone_ring[id] = out
	return _zone_ring[id]


## Maximal runs of non-bearing perimeter sections, as lists of ring indices
## (a run may wrap past the ring's start).
func _runs(w: HouseWorld, skip: Vector3i) -> Array:
	var rg := ring()
	var n := rg.size()
	var bears := []
	var first := -1
	for i in n:
		var b := line_bears(w, rg[i][0], int(rg[i][1]), skip)
		bears.append(b)
		if b and first < 0:
			first = i
	if first < 0:
		return [range(n)]                         # nothing bears at all
	var out := []
	var cur := []
	for j in range(1, n + 1):
		var i := (first + j) % n
		if bears[i]:
			if not cur.is_empty():
				out.append(cur)
				cur = []
		else:
			cur.append(i)
	return out


## The zone's outer sides: [line key, from, to] (metres along the line).
static func _sides(r: Rect2) -> Array:
	var f := HousePlan.FOOTPRINT
	var out := []
	if is_equal_approx(r.position.y, f.position.y):
		out.append(["north", int(r.position.x), int(r.end.x)])
	if is_equal_approx(r.end.y, f.end.y):
		out.append(["south", int(r.position.x), int(r.end.x)])
	if is_equal_approx(r.position.x, f.position.x):
		out.append(["west", int(r.position.y), int(r.end.y)])
	if is_equal_approx(r.end.x, f.end.x):
		out.append(["east", int(r.position.y), int(r.end.y)])
	return out


## The zone's rect grown by `by` on its outer sides only.
static func _outer_grown(r: Rect2, by: float) -> Rect2:
	var f := HousePlan.FOOTPRINT
	var lo := r.position
	var hi := r.end
	if is_equal_approx(lo.x, f.position.x):
		lo.x -= by
	if is_equal_approx(lo.y, f.position.y):
		lo.y -= by
	if is_equal_approx(hi.x, f.end.x):
		hi.x += by
	if is_equal_approx(hi.y, f.end.y):
		hi.y += by
	return Rect2(lo, hi - lo)


static func _centre(z: Dictionary, h: float) -> Vector3:
	var c: Vector2 = (z["rect"] as Rect2).get_center()
	return Vector3(c.x, h, c.y)


func _update_roof() -> void:
	if world == null or world.yard == null:
		return
	var rects := []
	for z in ZONES:
		if roof_gone.has(z["id"]):
			rects.append(_outer_grown(z["rect"], ROOF_EAVES))
	world.yard.set_roof_holes(rects)


## Removes storey s's deck over zone z with everything standing on it (the
## outer walls over its outer sides included); objects there fall. Returns
## the voxels removed (0 if it was already gone).
func _collapse_deck(u: HouseWorld, z: Dictionary, s := 1) -> int:
	var r := _outer_grown(z["rect"], DECK_EDGE)
	var xr := u.grid.centre_range(0, r.position.x, r.end.x)
	var zr := u.grid.centre_range(2, r.position.y, r.end.y)
	var lo := Vector3i(xr.x, VoxelHouse.FOUNDATION_ROW, zr.x)
	var hi := Vector3i(xr.y, u.grid.sy - 1, zr.y)
	var ch := VoxelCarver.empty_change()
	for y in range(lo.y, hi.y):
		for zz in range(lo.z, hi.z):
			for x in range(lo.x, hi.x):
				var i := u.grid.idx(x, y, zz)
				if u.design.mat[i] != 0:
					u.design.clear_index(i)
				if u.grid.mat[i] != 0:
					VoxelCarver._remove(u.grid, i, ch)
	var n := (ch["cells"] as PackedInt32Array).size()
	for o in u.objects_in(r).duplicate():
		u.damage_object(o, o.hp + 1, Vector3(o.pos.x, Levels.base_y(s) + 2.0, o.pos.y), true)
	if n == 0:
		return 0
	u._edited(lo, hi)
	u.settle(lo - Vector3i(3, 0, 3), hi + Vector3i(3, 0, 3), true)
	_fall_fx(u.fx, u.grid, ch, Levels.base_y(s))
	if world.fx != null:
		_dust(world.fx, z["rect"], 0.2)
	return n


## Debris from removed cells (capped), falling with a little spread.
static func _fall_fx(fx: VoxelFx, g: VoxelGrid, ch: Dictionary, _from_y: float) -> void:
	if fx == null:
		return
	var cells: PackedInt32Array = ch["cells"]
	var colors: PackedInt32Array = ch["colors"]
	var n := mini(cells.size(), 90)
	if n == 0:
		return
	var stride := maxi(1, cells.size() / n)
	var rng := RandomNumberGenerator.new()
	rng.seed = cells.size()
	var k := 0
	while k < cells.size() and n > 0:
		var p := g.center(g.coords(cells[k]))
		fx.debris(p, Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(-1.5, 0.5), rng.randf_range(-0.8, 0.8)),
			VoxelArt.to_color(colors[k]).darkened(rng.randf_range(0.0, 0.25)), rng.randf_range(0.8, 1.5) * fx.debris_scale)
		k += stride
		n -= 1


## The roof over zone z falls: chunks of roofing and snow from the roof's
## height into the room (on the upper floor if there is one), and dust.
func _roof_fx(z: Dictionary) -> void:
	var ch := chain()
	var fx: VoxelFx = ch.back().fx
	if fx == null:
		return
	var r: Rect2 = z["rect"]
	var base := Levels.base_y(ch.size() - 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(z["id"])
	var tones := [Color(0.89, 0.91, 0.93), Color(0.78, 0.8, 0.84), Color(0.3, 0.29, 0.28), Color(0.42, 0.36, 0.3)]
	var n := clampi(int(r.get_area() * 3.0), 24, 90)
	for k in n:
		var p := Vector3(rng.randf_range(r.position.x, r.end.x), base + rng.randf_range(2.45, 2.8), rng.randf_range(r.position.y, r.end.y))
		var shape := Vector3(rng.randf_range(1.0, 2.6), rng.randf_range(0.4, 0.8), rng.randf_range(1.0, 2.2))
		fx.debris(p, Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-2.0, 0.0), rng.randf_range(-0.6, 0.6)),
			tones[k % tones.size()], rng.randf_range(1.0, 1.8), shape)
	_dust(fx, r, base + 0.2)


static func _dust(fx: VoxelFx, r: Rect2, y: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(r.position.x * 31.0 + r.position.y * 7.0)
	for k in 16:
		var p := Vector3(rng.randf_range(r.position.x, r.end.x), y + rng.randf_range(0.0, 0.8), rng.randf_range(r.position.y, r.end.y))
		fx.puff(p, Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(0.2, 0.9), rng.randf_range(-0.8, 0.8)),
			Color(0.62, 0.6, 0.56, 0.75), 0.55, 2.0, rng.randf_range(1.8, 3.2))


# --- Exp 005 (V): the support grid of an upper storey's floor -------------------------------

## True if a wall or a pillar of storey world `below` stands at the edges of
## (or in) 1 m cell c: it carries the floor cell above.
static func carried_from_below(below: HouseWorld, c: Vector2i) -> bool:
	var r := Levels.cell_rect(c).grow(0.12)
	return below.grid.any_struct_in(r.position, r.end, VoxelHouse.NAV_ROW_LO + 4, VoxelHouse.NAV_ROW_HI)


## The floor cells of storey world u that are held: on the footprint's edge,
## carried from below, or joined (4-neighbours) to a held cell. Returns
## {"floor": {cell: true}, "held": {cell: true}}. Cheap: a floor sample per
## cell; the walls below are only looked at for cells the edges don't reach.
static func held_cells(u: HouseWorld, below: HouseWorld) -> Dictionary:
	var f := HousePlan.FOOTPRINT
	var floor := {}
	var held := {}
	var queue: Array[Vector2i] = []
	for j in range(int(f.position.y), int(f.end.y)):
		for i in range(int(f.position.x), int(f.end.x)):
			var c := Vector2i(i, j)
			if not _floor_sample(u, c):
				continue
			floor[c] = true
			if i == int(f.position.x) or j == int(f.position.y) or i == int(f.end.x) - 1 or j == int(f.end.y) - 1:
				held[c] = true
				queue.append(c)
	_flood(floor, held, queue)
	for c in floor:
		if not held.has(c) and carried_from_below(below, c):
			held[c] = true
			queue.append(c)
			_flood(floor, held, queue)
	return {"floor": floor, "held": held}


static func _flood(floor: Dictionary, held: Dictionary, queue: Array[Vector2i]) -> void:
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for d in Levels.DIRS:
			var n: Vector2i = c + d
			if floor.has(n) and not held.has(n):
				held[n] = true
				queue.append(n)


## True if the current grid has a floor finish in the middle of cell c (3 x 3 voxels).
static func _floor_sample(u: HouseWorld, c: Vector2i) -> bool:
	var cc := Levels.cell_center(c)
	var v := u.grid.cell_of(Vector3(cc.x, u.grid.origin.y + 0.35, cc.y))
	var n := 0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var m := u.grid.get_mat(v.x + dx, VoxelHouse.FLOOR_ROW, v.z + dz)
			if m != VoxelMat.AIR and m != VoxelMat.EARTH:
				n += 1
	return n >= 5


## Why a floor tile can't be laid in cell c of storey s (>= 1) whose world is
## u (maybe null: not built) over `below` ("" = it can): the walls below
## must carry the zone, and the cell needs a wall or pillar under its edges
## or a floor next to it.
func tile_support_reason(u: HouseWorld, below: HouseWorld, c: Vector2i) -> String:
	if below == null:
		return "There's nothing below to stand on."
	var z := zone_at(Levels.cell_center(c))
	if not z.is_empty() and zone_states(below)[z["id"]]["fail"]:
		return "The walls below can't carry a floor over %s." % z["name"]
	if carried_from_below(below, c):
		return ""
	if u != null:
		for d in Levels.DIRS:
			var n: Vector2i = c + d
			if Levels.in_house(n) and _floor_sample(u, n):
				return ""
	return "Nothing holds a floor here: build a wall or a pillar under it, or lay it next to floor."


## Floor cells of storey world u (storey s) that nothing holds fall: their
## floor and what stands inside them (objects, a pillar). Returns the cells
## dropped.
func _drop_unheld(u: HouseWorld, below: HouseWorld, s: int) -> int:
	if u == null or below == null or u.grid == null:
		return 0
	var hc := held_cells(u, below)
	var n := 0
	for c in hc["floor"]:
		if hc["held"].has(c):
			continue
		var r := Levels.cell_rect(c)
		for o in u.objects_in(r.grow(-0.1)).duplicate():
			u.damage_object(o, o.hp + 1, Vector3(o.pos.x, Levels.base_y(s) + 2.0, o.pos.y), true)
		var inner := r.grow(-0.1)
		var xr := u.grid.centre_range(0, inner.position.x, inner.end.x)
		var zr := u.grid.centre_range(2, inner.position.y, inner.end.y)
		var ch := VoxelCarver.empty_change()
		for y in range(VoxelHouse.BASE_ROW, u.grid.sy - 1):
			for z in range(zr.x, zr.y):
				for x in range(xr.x, xr.y):
					var i := u.grid.idx(x, y, z)
					if u.design.mat[i] != 0:
						u.design.clear_index(i)
					if u.grid.mat[i] != 0:
						VoxelCarver._remove(u.grid, i, ch)
		Levels.remove_floor(u, c)
		_fall_fx(u.fx, u.grid, ch, Levels.base_y(s))
		n += 1
	if n > 0:
		Sfx.play("structure/crumble", Vector3(7.0, Levels.base_y(s), 4.5))
	return n
