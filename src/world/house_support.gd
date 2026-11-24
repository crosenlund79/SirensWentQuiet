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

signal collapsed(info: Dictionary)
signal strained(info: Dictionary)

const FAIL_RUN := 3                ## metres of perimeter without a bearing section that bring a zone down
const PROP_REACH := 2              ## m inside a perimeter line where a built wall still props it
const MIN_INTEGRITY := 0.5
const MIN_VOXELS := 30             ## a section's design below this is no wall (a knocked-out section)
const ROOF_EAVES := 0.65           ## the roof overhangs the footprint by 0.55 m
const DECK_EDGE := 0.3             ## the upper deck and its outer walls past the footprint line
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
var upper: HouseWorld              ## the upper storey (a LevelWorld) or null
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
	if u == upper:
		return
	upper = u
	if u != null:
		u.support = self
		if not u.structure_changed.is_connected(mark_dirty):
			u.structure_changed.connect(mark_dirty)


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
	return false


## Build mode's demolish preview: "" or a warning about what removing
## section s of storey world w would bring down.
func demolish_warning(w: HouseWorld, s: Vector3i) -> String:
	if w == null or (w != world and w != upper) or not is_bearing(w, s) or not section_bears(w, s):
		return ""
	var before := zone_states(w)
	var after := zone_states(w, s)
	var names := []
	var strain := false
	for z in ZONES:
		var id: String = z["id"]
		if before[id]["fail"]:
			continue
		var lost: bool = roof_gone.has(id) and not (w == world and upper != null)
		if after[id]["fail"] and not lost:
			names.append(z["name"])
		elif after[id]["run"] == FAIL_RUN - 1 and before[id]["run"] < FAIL_RUN - 1 and not lost:
			strain = true
	if not names.is_empty():
		var what := "the upper floor and the roof" if w == world and upper != null else "the roof"
		return "Load-bearing! %s over %s will come down." % [what.substr(0, 1).to_upper() + what.substr(1), " and ".join(names)]
	if strain:
		return "Load-bearing: the roof above will sag."
	return "Load-bearing wall (carries the roof)."


## One line per zone for the developer menu.
func status_text() -> String:
	var g := zone_states(world)
	var u := zone_states(upper) if upper != null else {}
	var parts := []
	for z in ZONES:
		var id: String = z["id"]
		var failing: bool = g[id]["fail"] or (u.has(id) and u[id]["fail"])
		var st := "standing"
		if roof_gone.has(id):
			st = "roof gone" + (", unsupported" if failing else "")
		elif failing:
			st = "UNSUPPORTED"
		elif g[id]["run"] == FAIL_RUN - 1 or (u.has(id) and u[id]["run"] == FAIL_RUN - 1):
			st += ", strained"
		parts.append("%s: %s (gap %d m)" % [z["name"].trim_prefix("the "), st, maxi(g[id]["run"], u.get(id, {}).get("run", 0))])
	return "; ".join(parts)


# --- evaluation --------------------------------------------------------------------------

## Brings down whatever lost its support (each zone at most once per
## part) and reports new strains.
func evaluate() -> void:
	dirty = false
	if world == null or world.grid == null:
		return
	var t0 := Time.get_ticks_usec()
	if upper != null and not is_instance_valid(upper):
		upper = null
	var g := zone_states(world)
	var u := zone_states(upper) if upper != null else {}
	var fell := false
	for z in ZONES:
		var id: String = z["id"]
		var ground_fail: bool = g[id]["fail"]
		var upper_fail: bool = u.has(id) and u[id]["fail"]
		var info := {"zone": id, "name": z["name"], "rect": z["rect"], "roof": false, "upper": false, "storeys": []}
		if ground_fail and upper != null and _collapse_deck(z) > 0:
			info["upper"] = true
			info["storeys"] = [Levels.GROUND, Levels.UPPER]
		if (ground_fail or upper_fail) and not roof_gone.has(id):
			roof_gone[id] = true
			_update_roof()
			_roof_fx(z)
			info["roof"] = true
			if info["storeys"].is_empty():
				info["storeys"] = [Levels.UPPER if upper != null else Levels.GROUND]
		if info["roof"] or info["upper"]:
			strained_zones.erase(id)
			collapses += 1
			if info["upper"]:
				info["text"] = "The upper floor over %s came down!" % z["name"]
			else:
				info["text"] = "The roof over %s gave way!" % z["name"]
			Sfx.play("structure/break", _centre(z, 2.4))
			Sfx.play("structure/crumble", _centre(z, 1.2))
			fell = true
			collapsed.emit(info)
			continue
		var run := maxi(g[id]["run"], u.get(id, {}).get("run", 0))
		var at_risk := run == FAIL_RUN - 1 and not roof_gone.has(id)
		if at_risk and not strained_zones.has(id):
			strained_zones[id] = true
			info["text"] = "The outer wall of %s is failing: one more metre and the roof comes down." % z["name"]
			strained.emit(info)
		elif not at_risk:
			strained_zones.erase(id)
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


## Removes the upper deck over zone z with everything standing on it (the
## outer walls over its outer sides included); objects there fall. Returns
## the voxels removed (0 if it was already gone).
func _collapse_deck(z: Dictionary) -> int:
	var u := upper
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
		u.damage_object(o, o.hp + 1, Vector3(o.pos.x, Levels.HEIGHT + 2.0, o.pos.y), true)
	if n == 0:
		return 0
	u._edited(lo, hi)
	u.settle(lo - Vector3i(3, 0, 3), hi + Vector3i(3, 0, 3), true)
	_fall_fx(u.fx, u.grid, ch, Levels.HEIGHT)
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
	var fx: VoxelFx = upper.fx if upper != null and is_instance_valid(upper) else world.fx
	if fx == null:
		return
	var r: Rect2 = z["rect"]
	var base := Levels.HEIGHT if upper != null else 0.0
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
