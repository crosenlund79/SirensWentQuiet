class_name DefenseBuild
extends RefCounted
## Exp 006 (D): BuildMode's defence pieces (BuildPieces "cat": "defense"),
## like FurniturePlace: BuildMode calls handles() / uses_plane() / is_run() /
## target_key() / evaluate() / apply() / ghost_items() at a few hooks.
##
##   spikes_wood, spikes_metal  1 m segments on a wall line (drag for a run),
##                 placed like barricades (same checks and exit rule), not
##                 over a trench; metal spikes need Metalworking ("requires")
##   trench        a 1 m cell of the lot (drag for a straight run of up to
##                 12): a shovel, DIG_MINUTES and DIG_ENERGY a cell; next to
##                 water the new cells flood; refused if it would seal the
##                 last way out (water counts, drawbridges don't)
##   trench_water  floods the connected dry section under the pointer: free
##                 next to a rain collector, else 1 bottled water per 4 cells
##   backfill      fills a trench cell back in (a shovel, 2 minutes)
##   drawbridge_1/_2  across a 1 or 2 m wide trench, hinged on the house
##                 side, both ends on firm ground; placed lowered; R picks
##                 the axis (north-south or east-west)
## Every piece works only on the ground floor (not on another storey).
## Also: other pieces can't be built over a trench, and Demolish refuses a
## drawbridge whose removal would seal the last way out.

const IDS := ["spikes_wood", "spikes_metal", "trench", "trench_water", "backfill", "drawbridge_1", "drawbridge_2"]
const RUNS := ["spikes_wood", "spikes_metal", "trench"]
const NOT_HERE := "Defences go outside, on the ground floor."
const OVER_TRENCH := "Not over a trench (Backfill fills it in)."
const GHOST_DIG := Color(0.85, 0.6, 0.3, 0.34)
const GHOST_WATER := Color(0.3, 0.62, 1.0, 0.4)


static func handles(id: String) -> bool:
	return id in IDS


static func uses_plane(id: String) -> bool:
	return id in IDS


static func is_run(id: String) -> bool:
	return id in RUNS


## The pointer's re-evaluation key (BuildMode._target_key).
static func target_key(bm: Node, p: Vector2, from: Vector2) -> String:
	var id: String = bm.piece_id()
	var drag := from != Vector2.INF and from.distance_to(p) > 0.35
	if id == "spikes_wood" or id == "spikes_metal":
		return "%s|%s" % [id, str(bm._run(from, p)) if drag else str(HouseWorld.nearest_seg(p))]
	if id == "trench" and drag:
		return "%s|%s" % [id, str(cell_run(from, p))]
	return "%s|%s|%d" % [id, str(DefenseGrid.cell_of(p)), int(bm.rot)]


## The cells from the drag start to p along the longer axis (at most RUN_MAX).
static func cell_run(from: Vector2, p: Vector2) -> Array:
	var a := DefenseGrid.cell_of(from)
	var b := DefenseGrid.cell_of(p)
	var d := b - a
	var out := []
	var n := mini(maxi(absi(d.x), absi(d.y)), BuildMode.RUN_MAX - 1)
	var step := Vector2i(signi(d.x), 0) if absi(d.x) >= absi(d.y) else Vector2i(0, signi(d.y))
	for i in n + 1:
		out.append(a + step * i)
	return out


# --- evaluation ------------------------------------------------------------------------

## Called by BuildMode.evaluate for every piece (after its own evaluation).
static func evaluate(bm: Node, r: Dictionary, p: Vector2, from: Vector2) -> void:
	var id: String = r["piece"]
	var w: HouseWorld = bm.world
	var g: DefenseGrid = w.defense if w != null else null
	if id == "demolish":
		_check_demolish(w, g, r, p)
		return
	if not handles(id):
		_check_other(bm, g, r)
		return
	r["cost"] = BuildPieces.LIST[bm.piece]["cost"]
	if g == null or w is LevelWorld:
		r["reason"] = NOT_HERE
		return
	match id:
		"spikes_wood", "spikes_metal":
			_eval_spikes(bm, g, r, p, from)
		"trench":
			_eval_trench(bm, g, r, p, from)
		"trench_water":
			_eval_fill(g, r, p)
		"backfill":
			_eval_backfill(bm, g, r, p)
		"drawbridge_1", "drawbridge_2":
			var fit := g.bridge_fit(DefenseGrid.cell_of(p), DefenseGrid.span_of(id), int(bm.rot))
			r["pos"] = fit["pos"]
			r["rot"] = fit["rot"]
			r["kind"] = id
			r["cells"] = fit["cells"]
			r["reason"] = fit["reason"]


static func _no_shovel(bm: Node) -> bool:
	var s: GameState = bm.state
	return s != null and s.inventory.count("shovel") <= 0 and not s.cheats.get("unlimited", false)


static func _eval_spikes(bm: Node, g: DefenseGrid, r: Dictionary, p: Vector2, from: Vector2) -> void:
	var w: HouseWorld = bm.world
	var id: String = r["piece"]
	var segs := [HouseWorld.nearest_seg(p)]
	if from != Vector2.INF and from.distance_to(p) > 0.35:
		segs = bm._run(from, p)
	r["segs"] = segs
	r["kind"] = id
	r["cost"] = BuildPieces.times(BuildPieces.LIST[bm.piece]["cost"], segs.size())
	r["bad"] = []
	var extra := {}
	for s in segs:
		var why: String = bm._check_line_piece("barricade", s)
		if why == "" and _over_trench(g, HouseWorld.seg_rect(s, 0.3)):
			why = OVER_TRENCH
		if why != "":
			r["bad"].append(s)
			if r["reason"] == "":
				r["reason"] = why
		for c in w.nav.cells_in_rect(WorldObject.footprint_of(id, HouseWorld.seg_center(s), w.seg_rot(s))):
			extra[c] = GridNav.WALL
	if r["reason"] == "" and not w.exit_path_exists(extra):
		r["reason"] = BuildMode.SEAL_REASON
		r["bad"] = segs.duplicate()


static func _eval_trench(bm: Node, g: DefenseGrid, r: Dictionary, p: Vector2, from: Vector2) -> void:
	var cells := [DefenseGrid.cell_of(p)]
	if from != Vector2.INF and from.distance_to(p) > 0.35:
		cells = cell_run(from, p)
	r["tile"] = cells[0]
	r["cost"] = {}
	r["bad"] = []
	var dig := []
	for c in cells:
		if g.has(c):
			continue           # a run skips what is already dug
		var why := g.dig_reason(c)
		if why != "":
			r["bad"].append(c)
			if r["reason"] == "":
				r["reason"] = why
		else:
			dig.append(c)
	r["cells"] = dig
	var s: GameState = bm.state
	if _no_shovel(bm):
		r["reason"] = "You need a shovel to dig."
	elif r["reason"] == "" and dig.is_empty():
		r["reason"] = "Already dug."
	elif r["reason"] == "" and s != null and not s.cheats.get("invulnerable", false) \
			and s.energy < DefenseGrid.MIN_ENERGY + DefenseGrid.DIG_ENERGY * dig.size():
		r["reason"] = "Too tired to dig." if dig.size() == 1 else "Too tired to dig %d m." % dig.size()
	if r["reason"] != "":
		return
	var ch := g.dig_changes(dig)
	r["changes"] = ch
	if g.bodies_in_changes(ch):
		r["reason"] = "Someone is standing where the water would run."
	elif not g.keeps_exit(ch):
		r["reason"] = BuildMode.SEAL_REASON + " Water would cut you off."
		r["bad"] = dig.duplicate()


static func _eval_fill(g: DefenseGrid, r: Dictionary, p: Vector2) -> void:
	var c := DefenseGrid.cell_of(p)
	r["tile"] = c
	r["cost"] = {}
	r["cells"] = [c]
	if not g.has(c):
		r["reason"] = "Aim at a dry trench (Dig trench first)."
		return
	if g.is_wet(c):
		r["cells"] = g.section(c)
		r["reason"] = "Already full of water."
		return
	var ch := g.fill_changes(c)
	r["changes"] = ch
	r["cells"] = ch.keys()
	var near := g.collector_near(ch.keys())
	r["free"] = near
	r["cost"] = DefenseGrid.fill_cost(ch.size(), near)
	if g.bodies_in_changes(ch):
		r["reason"] = "Someone is standing in the trench."
	elif not g.keeps_exit(ch):
		r["reason"] = BuildMode.SEAL_REASON + " Build a drawbridge across first."


static func _eval_backfill(bm: Node, g: DefenseGrid, r: Dictionary, p: Vector2) -> void:
	var w: HouseWorld = bm.world
	var c := DefenseGrid.cell_of(p)
	r["tile"] = c
	r["cells"] = [c]
	r["cost"] = {}
	var rect := DefenseGrid.cell_rect(c)
	if not g.has(c):
		r["reason"] = "Aim at a trench to fill it in."
	elif _no_shovel(bm):
		r["reason"] = "You need a shovel to fill it in."
	elif g.bridge_over(c) != null:
		r["reason"] = "Take the drawbridge down first (Demolish)."
	elif not w.objects_in(rect.grow(-0.05)).is_empty():
		r["reason"] = "Something stands in the trench."
	elif w.is_inside_tree() and w.bodies_in(rect.grow(-0.02)):
		r["reason"] = "Someone is standing in it."


static func _over_trench(g: DefenseGrid, rect: Rect2) -> bool:
	if g == null or g.cells.is_empty():
		return false
	var inner := rect.grow(-0.04)
	for c in g.cells:
		if DefenseGrid.cell_rect(c).intersects(inner):
			return true
	return false


## Other pieces: nothing is built over a trench.
static func _check_other(bm: Node, g: DefenseGrid, r: Dictionary) -> void:
	if g == null or g.cells.is_empty() or r["reason"] != "" or bm.world is LevelWorld:
		return
	if BuildPieces.LIST[bm.piece]["tool"] != "place":
		return
	var rects := []
	for s in r.get("segs", []):
		rects.append(HouseWorld.seg_rect(s, HouseWorld.FOUNDATION_HALF if r["piece"] == "foundation" else 0.15))
	if r.get("pos", Vector2.INF) != Vector2.INF and WorldObject.DEFS.has(str(r.get("kind", ""))):
		rects.append(WorldObject.footprint_of(r["kind"], r["pos"], int(r.get("rot", 0))))
	for rect in rects:
		if _over_trench(g, rect):
			r["reason"] = OVER_TRENCH
			return


## Demolish: a drawbridge that is the last way over the water stays; a bare
## trench points at Backfill.
static func _check_demolish(w: HouseWorld, g: DefenseGrid, r: Dictionary, p: Vector2) -> void:
	if g == null or w is LevelWorld:
		return
	var o: Variant = r.get("object")
	if o is WorldObject and DefenseGrid.is_bridge((o as WorldObject).kind) and r["reason"] == "":
		var extra := {}
		for c in w.nav.cells_in_rect((o as WorldObject).footprint()):
			extra[c] = GridNav.WATER if g.state_at(w.nav.center_of(c)) == DefenseGrid.WET else GridNav.OPEN
		if not w.exit_path_exists(extra):
			r["reason"] = BuildMode.SEAL_REASON + " It's the only way over the water."
	elif o == null and not r.has("furniture") and str(r["reason"]).begins_with("Nothing to demolish") and g.has(DefenseGrid.cell_of(p)):
		r["reason"] = "A trench: Backfill fills it in."


# --- applying ----------------------------------------------------------------------------

static func apply(bm: Node, r: Dictionary) -> String:
	var w: HouseWorld = bm.world
	var g: DefenseGrid = w.defense
	var id: String = r["piece"]
	var s: GameState = bm.state
	var game: Node = bm.get_parent()
	match id:
		"spikes_wood", "spikes_metal":
			var at := Vector3.ZERO
			for sg in r["segs"]:
				var c := HouseWorld.seg_center(sg)
				at = Vector3(c.x, 0.5, c.y)
				w.place_object(id, c, w.seg_rot(sg), true)
			Sfx.play("build/place", at)
			Sfx.play("build/upgrade" if id == "spikes_metal" else "build/hammer", at)
			var nm := WorldObject.name_of(id)
			var n: int = r["segs"].size()
			return ("%s up: they hurt anything that pushes against them." % nm) if n == 1 else ("%d m of %s up." % [n, nm.to_lower()])
		"trench":
			var cells: Array = r["cells"]
			var ch := g.dig(cells)
			var minutes := DefenseGrid.DIG_MINUTES * cells.size()
			if s != null and not s.cheats.get("invulnerable", false):
				s.energy = maxf(s.energy - DefenseGrid.DIG_ENERGY * cells.size(), 0.0)
			if game != null and game.has_method("dev_advance"):
				game.dev_advance(minutes)
			var at := _cell_at(cells[0])
			Sfx.play("impact/ground", at)
			Sfx.play_first(["build/dig", "build/demolish"], at)
			var wet := false
			for c in ch:
				if ch[c] == DefenseGrid.WET:
					wet = true
			var txt := "Dug %d m of trench (%d min)." % [cells.size(), int(minutes)]
			if wet:
				txt += " Water runs in from the moat."
			return txt
		"trench_water":
			var ch := g.fill(r["tile"])
			Sfx.play("impact/ground", _cell_at(r["tile"]))
			if r.get("free", false):
				return "The rain collector's downpipe floods the trench (%d m)." % ch.size()
			return "You pour water into the trench (%d m, %s)." % [ch.size(), BuildPieces.cost_text(r["cost"])]
		"backfill":
			g.backfill(r["tile"])
			if game != null and game.has_method("dev_advance"):
				game.dev_advance(DefenseGrid.BACKFILL_MINUTES)
			Sfx.play_first(["build/dig", "build/demolish"], _cell_at(r["tile"]))
			return "Trench filled in."
		"drawbridge_1", "drawbridge_2":
			var o := w.place_object(id, r["pos"], int(r["rot"]), true)
			g.set_bridge(o, true, true)
			var at := Vector3(o.pos.x, 0.5, o.pos.y)
			Sfx.play("build/place", at)
			Sfx.play("build/hammer", at)
			return "%s built, lowered. E at it raises and lowers it." % WorldObject.name_of(id)
	return ""


static func _cell_at(c: Vector2i) -> Vector3:
	var cc := DefenseGrid.cell_center(c)
	return Vector3(cc.x, 0.2, cc.y)


# --- preview -----------------------------------------------------------------------------

## Ghost items (BuildMode format [type, size, position, yaw, colour, style]).
static func ghost_items(bm: Node, r: Dictionary) -> Array:
	var ok: bool = r["ok"]
	var out := []
	var id: String = r["piece"]
	match id:
		"spikes_wood", "spikes_metal":
			for s in r.get("segs", []):
				var bad: bool = not ok and (r.get("bad", []).has(s) or not r.has("bad"))
				var c := HouseWorld.seg_center(s)
				out.append(["wall_ghost", Vector3(1.0, 0.8, 0.5), Vector3(c.x, 0, c.y), 0.0 if s.x == 0 else PI * 0.5, BuildMode.GHOST_BAD if bad else BuildMode.GHOST_OK, ""])
		"trench":
			for c in r.get("cells", []):
				out.append(_tile(c, 0.08, 0.0, GHOST_DIG if ok else BuildMode.GHOST_BAD))
			for c in r.get("bad", []):
				out.append(_tile(c, 0.08, 0.0, BuildMode.GHOST_BAD))
			if out.is_empty() and r.has("tile"):
				out.append(_tile(r["tile"], 0.08, 0.0, BuildMode.GHOST_BAD))
		"trench_water":
			for c in r.get("cells", []):
				out.append(_tile(c, 0.05, DefenseGrid.WATER_Y, GHOST_WATER if ok else BuildMode.GHOST_BAD))
		"backfill":
			if r.has("tile"):
				out.append(_tile(r["tile"], 0.12, -0.1, BuildMode.GHOST_TOOL["demolish"] if ok else BuildMode.GHOST_BAD))
		"drawbridge_1", "drawbridge_2":
			var col: Color = BuildMode.GHOST_OK if ok else BuildMode.GHOST_BAD
			var span := float(DefenseGrid.span_of(id))
			var rr := int(r.get("rot", 0))
			var pos: Vector2 = r.get("pos", Vector2.ZERO)
			# the ghost's long side runs along x at yaw 0 (PropKit span pieces)
			var yaw := PI * 0.5 if rr % 2 == 0 else 0.0
			var size := Vector3(span, 0.1, 1.0) if span > 1.0 else Vector3(1.0, 0.1, 1.0)
			out.append(["wall_ghost", size, Vector3(pos.x, 0.0, pos.y), yaw, col, ""])
			var back := -WorldObject.front_dir(rr)
			var side := Vector2(-back.y, back.x)
			for sx in [-0.6, 0.6]:
				var q: Vector2 = pos + back * (span * 0.5 + 0.12) + side * sx
				out.append(["wall_ghost", Vector3(0.12, 1.45 if span < 1.5 else 2.3, 0.12), Vector3(q.x, 0.0, q.y), 0.0, col, ""])
	return out


static func _tile(c: Vector2i, h: float, y: float, col: Color) -> Array:
	var cc := DefenseGrid.cell_center(c)
	return ["wall_ghost", Vector3(1.0, h, 0.99), Vector3(cc.x, y, cc.y), 0.0, col, ""]
