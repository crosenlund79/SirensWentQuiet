class_name OverviewPlan
extends RefCounted
## Exp 007 (O): the house overview's plan of one storey, read from the real
## house state (no second simulation): sections and their integrity, windows,
## doorways and gaps, doors, barricades and boards, stairs, floor cells (and
## holes or damage in them), dug cells underground, pillars, foundations,
## observation holes, collapsed and strained roof zones. Pure data for the
## blueprint (blueprint_view.gd) and the overview's summary line.

const MIN_DESIGN := 30                 ## a section with fewer designed voxels is knocked out (HouseSupport.MIN_VOXELS)
const FLOOR_DAMAGED := 0.3             ## a cell missing this much of its floor finish is "damaged"


## The plan of `storey` in the game (`game.levels` for the storeys; the ground
## floor alone without it). {"exists": false, ...} for a storey not built.
static func collect(game: Node, storey: int) -> Dictionary:
	var lv: Node = game.get("levels")
	var w: HouseWorld = null
	if lv != null and lv.has_method("world_of"):
		w = lv.world_of(storey)
	elif storey == Levels.GROUND:
		w = game.world
	var out := {"storey": storey, "label": Levels.label(storey), "exists": w != null, "walls": [], "objects": [], "stairs": [],
		"floor": [], "no_floor": [], "floor_damaged": [], "dug": [], "pillars": [], "foundations": [], "holes": [],
		"collapsed": [], "strained": [], "stats": {}}
	if w == null:
		return out
	var st := {"sections": 0, "damaged": 0, "broken": 0, "missing": 0, "windows": 0, "doors": 0, "objects_damaged": 0,
		"floor_holes": 0, "floor_damaged": 0, "holes": 0, "collapsed": 0, "strained": 0}
	# walls
	for s in w.sections:
		var sec: Dictionary = w.sections[s]
		var a := Vector2(s.z, s.y) if s.x == 0 else Vector2(s.y, s.z)
		var b := a + (Vector2(1, 0) if s.x == 0 else Vector2(0, 1))
		var info := w.section_info(s)
		var kind := "wall"
		if info["glass"]:
			kind = "window"
		elif info["gap"]:
			kind = "gap"
		elif int(sec.get("design", 0)) < MIN_DESIGN:
			kind = "missing" if sec.get("orig", false) else "gap"
		var integ: float = info["integrity"]
		out["walls"].append({"a": a, "b": b, "kind": kind, "integrity": integ, "material": str(sec.get("material", "")),
			"plated": w.upgraded.has(s), "built": w.built.has(s), "seg": s})
		match kind:
			"wall":
				st["sections"] += 1
				if integ < 0.35:
					st["broken"] += 1
				elif integ < 0.92:
					st["damaged"] += 1
			"window":
				st["windows"] += 1
			"missing":
				st["missing"] += 1
	# doors, barricades, window boards
	for o in w.objects:
		if not is_instance_valid(o) or not (o.kind in ["door", "barricade", "boards"]):
			continue
		var s: Vector3i = o.seg
		var a := Vector2(s.z, s.y) if s.x == 0 else Vector2(s.y, s.z)
		var b := a + (Vector2(1, 0) if s.x == 0 else Vector2(0, 1))
		out["objects"].append({"kind": o.kind, "mat": o.mat, "a": a, "b": b, "pos": o.pos, "rot": o.rot, "open": o.open,
			"damage": o.damage_fraction()})
		if o.kind == "door":
			st["doors"] += 1
		if o.damage_fraction() > 0.08:
			st["objects_damaged"] += 1
	# floor cells
	var f := HousePlan.FOOTPRINT
	var stairs := []
	if lv != null and lv.get("stairs") is Array:
		for sx in lv.stairs:
			if Levels.joins(sx, storey):
				stairs.append(sx)
	for j in range(int(f.position.y), int(f.end.y)):
		for i in range(int(f.position.x), int(f.end.x)):
			var c := Vector2i(i, j)
			var on_stairs := false
			for sx in stairs:
				if Levels.stairs_rect(sx).has_point(Levels.cell_center(c)):
					on_stairs = true
			if on_stairs:
				continue
			var has := false
			if lv != null and lv.has_method("floor_at"):
				has = lv.floor_at(storey, c)
			else:
				has = Levels.floor_coverage(w, c) >= 0.5
			if storey < Levels.GROUND:
				if has:
					out["dug"].append(c)
				continue
			if has:
				out["floor"].append(c)
				if _floor_missing(w, c) >= FLOOR_DAMAGED:
					out["floor_damaged"].append(c)
					st["floor_damaged"] += 1
			else:
				out["no_floor"].append(c)
				st["floor_holes"] += 1
	# stairs
	for sx in stairs:
		var other := Levels.other_storey(sx, storey)
		out["stairs"].append({"rect": Levels.stairs_rect(sx), "from": Levels.exit_point(sx, storey), "to": Levels.exit_point(sx, other),
			"up": other > storey, "to_storey": other})
	# pillars and foundations
	if lv != null and lv.get("pillars") is Dictionary:
		for c in (lv.pillars as Dictionary).get(storey, {}):
			out["pillars"].append(c)
	if storey == Levels.GROUND:
		for s in w.foundations:
			out["foundations"].append({"rect": HouseWorld.seg_rect(s, HouseWorld.FOUNDATION_HALF), "timber": w.timber.has(s)})
	# observation holes
	for rec in HoleRules.holes_of(w):
		out["holes"].append(HoleRules.plan_point(w, rec))
		st["holes"] += 1
	# the roof and the decks: collapsed zones (on the top storey) and strained ones
	var sup: Variant = game.world.get("support") if game.world != null else null
	if sup is HouseSupport:
		var top := 0
		if lv != null and lv.has_method("roof_storey"):
			top = lv.roof_storey()
		if storey == top:
			for id in (sup as HouseSupport).roof_gone:
				var z := HouseSupport.zone(str(id))
				if not z.is_empty():
					out["collapsed"].append({"rect": z["rect"], "name": str(z.get("name", id))})
					st["collapsed"] += 1
		if storey >= Levels.GROUND:
			var states: Dictionary = (sup as HouseSupport).zone_states(w)
			for z in HouseSupport.ZONES:
				var zs: Dictionary = states.get(z["id"], {})
				if (sup as HouseSupport).roof_gone.has(z["id"]) and storey == top:
					continue
				if zs.get("fail", false) or int(zs.get("run", 0)) >= HouseSupport.FAIL_RUN - 1:
					out["strained"].append({"rect": z["rect"], "name": str(z.get("name", z["id"])), "fail": zs.get("fail", false)})
					st["strained"] += 1
	out["stats"] = st
	return out


## Fraction of a cell's floor finish (design) missing in the current grid.
static func _floor_missing(w: HouseWorld, c: Vector2i) -> float:
	var g := w.grid
	var r := Levels.cell_rect(c).grow(-0.05)
	var xr := g.centre_range(0, r.position.x, r.end.x)
	var zr := g.centre_range(2, r.position.y, r.end.y)
	var n := 0
	var gone := 0
	for z in range(zr.x, zr.y):
		for x in range(xr.x, xr.y):
			var i := g.idx(x, VoxelHouse.FLOOR_ROW, z)
			if w.design.mat[i] != VoxelMat.AIR:
				n += 1
				if g.mat[i] == VoxelMat.AIR:
					gone += 1
	return float(gone) / float(n) if n > 0 else 0.0


## One line for the overview's card ("12 wall sections, 2 damaged, 1 broken ·
## 1 floor hole · 2 observation holes · roof: kitchen collapsed").
static func summary(plan: Dictionary) -> String:
	if not plan.get("exists", false):
		return "Not built yet."
	var st: Dictionary = plan["stats"]
	var parts := PackedStringArray()
	var w := "%d wall sections" % int(st["sections"])
	if int(st["damaged"]) > 0 or int(st["broken"]) > 0:
		w += " (%d damaged, %d broken)" % [int(st["damaged"]), int(st["broken"])]
	parts.append(w)
	if int(st["missing"]) > 0:
		parts.append("%d knocked out" % int(st["missing"]))
	if int(st["doors"]) > 0:
		parts.append("%d door%s" % [int(st["doors"]), "" if int(st["doors"]) == 1 else "s"])
	if int(st["objects_damaged"]) > 0:
		parts.append("%d damaged door/barricade" % int(st["objects_damaged"]))
	if int(st["floor_holes"]) > 0:
		parts.append("%d m² without floor" % int(st["floor_holes"]))
	if int(st["floor_damaged"]) > 0:
		parts.append("%d m² floor damaged" % int(st["floor_damaged"]))
	if int(st["holes"]) > 0:
		parts.append("%d observation hole%s" % [int(st["holes"]), "" if int(st["holes"]) == 1 else "s"])
	if not (plan["collapsed"] as Array).is_empty():
		parts.append("roof down: " + ", ".join((plan["collapsed"] as Array).map(func(z): return str(z["name"]).to_lower())))
	if not (plan["strained"] as Array).is_empty():
		parts.append("strained: " + ", ".join((plan["strained"] as Array).map(func(z): return str(z["name"]).to_lower())))
	return " · ".join(parts)
