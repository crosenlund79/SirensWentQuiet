extends RefCounted
## Experiment 004 (owner L): BuildMode's extension for the storeys (BuildMode
## calls it through `ext` at a few hooks). It owns the "Floors & levels"
## pieces of palette key 0 (BuildPieces: wood_floor, stairs_up, stairs_down,
## upper_floor, excavate; the stone foundation stays there too), adds stairs
## and floor tiles to Demolish, and on the upper floor and in the basement
## refuses pieces that would stand in mid-air or in solid earth.
##
##   wooden floor  1 m tile where a cell has no floor (2 planks, 2 nails)
##   stairs up     ground floor, 1 x 2 m + a free cell at the foot (R turns);
##                 they reach the upper floor once it is built (8 planks, 10 nails)
##   stairs down   ground floor over dug basement cells: the two under the
##                 stairs and the one past their end (8 planks, 10 nails)
##   upper floor   needs stairs up: deck, outer walls, windows (40 planks,
##                 40 nails, 4 iron)
##   excavate      a shovel; from the ground floor any cell under the house,
##                 in the basement a cell next to the dug space; 25 minutes,
##                 6 energy, +1 stone
##   demolish      stairs (full refund) and floor tiles (yours: full refund;
##                 the house's: 1 plank)

const IDS := ["wood_floor", "stairs_up", "stairs_down", "upper_floor", "excavate"]
const NOTHING := "Nothing to demolish here."
const ORIGINAL_TILE_REFUND := {"wood": 1}
const GHOST_DIG := Color(0.85, 0.6, 0.3, 0.34)

var levels: Node                       ## game_levels.gd


func _init(l: Node) -> void:
	levels = l


## Pieces that aim at the floor plane of the player's storey.
func uses_plane(id: String) -> bool:
	return id in IDS


func _storey() -> int:
	return levels.player_storey


# --- evaluation ------------------------------------------------------------------------

## Called at the end of BuildMode.evaluate (before the cost check). Fills `r`
## for this extension's pieces; adds level rules to the others.
func post_evaluate(bm: Node, r: Dictionary, p: Vector2, _from: Vector2) -> void:
	var id: String = r["piece"]
	if id in IDS:
		r["ext"] = true
		r["cost"] = BuildPieces.LIST[BuildPieces.index_of(id)]["cost"]
		match id:
			"wood_floor":
				_eval_floor(bm, r, p)
			"stairs_up", "stairs_down":
				var st := Levels.make_stairs(Levels.GROUND if id == "stairs_up" else Levels.BASEMENT, Levels.cell_of(p), bm.rot)
				r["stairs"] = st
				r["reason"] = "Stairs start on the ground floor." if _storey() != Levels.GROUND else stairs_reason(st)
			"upper_floor":
				if levels.upper != null:
					r["reason"] = "The upper floor is already built."
				elif levels.stairs.filter(func(s): return int(s["lo"]) == Levels.GROUND).is_empty():
					r["reason"] = "Build stairs up first (this key, R turns them)."
			"excavate":
				_eval_dig(bm, r, p)
		return
	if id == "demolish":
		_eval_demolish(bm, r, p)
		return
	if r["reason"] != "":
		return
	# Every other piece: not on the stairs; upstairs on the deck; downstairs in dug space.
	var rects := []
	for s in r.get("segs", []):
		rects.append(HouseWorld.seg_rect(s, 0.15 if id != "foundation" else HouseWorld.FOUNDATION_HALF))
	if r.get("pos", Vector2.INF) != Vector2.INF and r.has("kind"):
		rects.append(WorldObject.footprint_of(r["kind"], r["pos"], int(r.get("rot", 0))))
	for rect in rects:
		if BuildPieces.LIST[bm.piece]["tool"] == "place" and _on_stairs(rect, _storey()):
			r["reason"] = "The stairs are in the way."
			return
		if bm.world is LevelWorld and BuildPieces.LIST[bm.piece]["tool"] == "place":
			var why: String = (bm.world as LevelWorld).level_block_reason(rect)
			if why != "":
				r["reason"] = why
				return


func _on_stairs(rect: Rect2, storey: int) -> bool:
	for st in levels.stairs:
		if Levels.joins(st, storey) and Levels.stairs_rect(st).grow(-0.05).intersects(rect):
			return true
	return false


func _eval_floor(bm: Node, r: Dictionary, p: Vector2) -> void:
	var c := Levels.cell_of(p)
	r["tile"] = c
	var w: HouseWorld = bm.world
	if not Levels.in_house(c):
		r["reason"] = "Floors go inside the house."
	elif _storey() == Levels.BASEMENT and not (w as LevelWorld).is_dug(c):
		r["reason"] = "Dig this cell out first."
	elif _on_stairs(Levels.cell_rect(c), _storey()):
		r["reason"] = "The stairs are here."
	elif Levels.floor_coverage(w, c) >= 0.5:
		r["reason"] = "There's already a floor here (Demolish takes a tile up)."


func _eval_dig(bm: Node, r: Dictionary, p: Vector2) -> void:
	var c := Levels.cell_of(p)
	r["tile"] = c
	r["cost"] = {}
	var s: GameState = bm.state
	var b: LevelWorld = levels.basement
	if s != null and s.inventory.count("shovel") <= 0 and not s.cheats.get("unlimited", false):
		r["reason"] = "You need a shovel to dig."
	elif _storey() == Levels.UPPER:
		r["reason"] = "Dig from the ground floor or in the basement."
	elif not Levels.in_house(c):
		r["reason"] = "A basement goes under the house."
	elif b != null and b.is_dug(c):
		r["reason"] = "Already dug out."
	elif _storey() == Levels.BASEMENT and not _next_to_dug(b, c):
		r["reason"] = "Dig next to the space you've dug out."
	elif s != null and s.energy < Levels.DIG_MIN_ENERGY and not s.cheats.get("invulnerable", false):
		r["reason"] = "Too tired to dig."


static func _next_to_dug(b: LevelWorld, c: Vector2i) -> bool:
	if b == null:
		return false
	for d in Levels.DIRS:
		if b.is_dug(c + d):
			return true
	return false


## Why stairs `st` can't be built ("" = they can): see the file header.
func stairs_reason(st: Dictionary) -> String:
	var g: HouseWorld = levels.game.world
	var cells: Array = Levels.stairs_cells(st)
	var foot := Levels.foot_cell(st)
	var far := Levels.far_cell(st)
	for c in cells + [foot]:
		if not Levels.in_house(c):
			return "Stairs need room inside the house: 2 m plus 1 m to step on."
	for c in cells:
		var rect := Levels.cell_rect(c)
		if Levels.wall_on(g, c):
			return "There's a wall in the way."
		if g.furniture_in(rect.grow(-0.05)):
			return "Furniture is in the way."
		if not g.objects_in(rect.grow(-0.05)).is_empty():
			return "Something is standing here."
		for o in levels.stairs:
			if Levels.stairs_rect(o).grow(-0.05).intersects(rect) or Levels.cell_rect(Levels.foot_cell(o)).grow(-0.05).intersects(rect):
				return "Other stairs are in the way."
		if g.bodies_in(rect.grow(-0.1)):
			return "Someone is standing there."
	if Levels.wall_on(g, foot) or g.furniture_in(Levels.cell_rect(foot).grow(-0.05)):
		return "Keep the cell at the foot of the stairs free."
	for o in levels.stairs:
		if Levels.stairs_rect(o).grow(-0.05).intersects(Levels.cell_rect(foot)):
			return "Keep the cell at the foot of the stairs free."
	if int(st["lo"]) == Levels.GROUND:
		if not Levels.in_house(far):
			return "The top of the stairs must end inside the house."
		var u: LevelWorld = levels.upper
		if u != null and (Levels.wall_on(u, far) or not u.has_floor_at(Levels.cell_center(far))):
			return "The top of the stairs must end on the upper floor's deck."
	else:
		var b: LevelWorld = levels.basement
		if b == null:
			return "Dig out the basement first: the two cells under the stairs and one past their end."
		for c in cells + [far]:
			if not b.is_dug(c):
				return "Dig out the basement first: the two cells under the stairs and one past their end."
			if Levels.wall_on(b, c) or not b.objects_in(Levels.cell_rect(c).grow(-0.05)).is_empty():
				return "Something stands in the basement under the stairs."
	return ""


func _eval_demolish(bm: Node, r: Dictionary, p: Vector2) -> void:
	var storey := _storey()
	var st: Dictionary = levels.stairs_at(p, storey) if storey == Levels.GROUND else {}
	if not st.is_empty():
		_claim(r)
		r["stairs"] = st
		r["refund"] = Levels.STAIRS_COST.duplicate()
		r["reason"] = "Someone is standing on the stairs." if bm.world.bodies_in(Levels.stairs_rect(st).grow(-0.1)) else ""
		return
	if r["reason"] != NOTHING:
		return
	var c := Levels.cell_of(p)
	var w: HouseWorld = bm.world
	if not Levels.in_house(c) or _on_stairs(Levels.cell_rect(c), storey) or Levels.floor_coverage(w, c) < 0.3:
		return
	if storey == Levels.BASEMENT and not (w as LevelWorld).is_dug(c):
		return
	_claim(r)
	r["tile"] = c
	var mine: bool = levels.laid.get(storey, {}).has(c)
	r["refund"] = Levels.WOOD_FLOOR_COST.duplicate() if mine else ORIGINAL_TILE_REFUND.duplicate()


## Takes a Demolish result over (its piece becomes "ext_demolish", so
## BuildMode's own demolish code leaves it alone).
func _claim(r: Dictionary) -> void:
	r["ext"] = true
	r["piece"] = "ext_demolish"
	r["reason"] = ""
	r["segs"] = []
	r["object"] = null
	r["foundation"] = false
	r["opening"] = false


# --- applying ----------------------------------------------------------------------------

## Called by BuildMode.apply after paying, for results with "ext". Returns the message.
func apply(bm: Node, r: Dictionary) -> String:
	var at := _where(r)
	match r["piece"]:
		"wood_floor":
			var c: Vector2i = r["tile"]
			Levels.lay_wood_floor(bm.world, c)
			if not levels.laid.has(_storey()):
				levels.laid[_storey()] = {}
			levels.laid[_storey()][c] = true
			Sfx.play("build/place", at)
			Sfx.play("build/hammer", at)
			return "Wooden floor laid (%s)." % BuildPieces.cost_text(r["cost"])
		"stairs_up", "stairs_down":
			levels.add_stairs(r["stairs"])
			Sfx.play("build/place", at)
			Sfx.play("build/hammer", at)
			if r["piece"] == "stairs_down":
				return "Stairs down to the basement built. Walk onto them or press E."
			if levels.upper == null:
				return "Stairs up built. They end at the ceiling until you build the upper floor (0 again)."
			return "Stairs up built. Walk onto them or press E."
		"upper_floor":
			levels.build_upper()
			Sfx.play("build/place", at)
			Sfx.play("build/hammer", at)
			return "The upper floor is up: a deck, outer walls and windows. Take the stairs and build on it."
		"excavate":
			var c: Vector2i = r["tile"]
			var first: bool = levels.basement == null
			levels.dig(c)
			var s: GameState = bm.state
			var got := 0
			if s != null:
				s.energy = maxf(s.energy - Levels.DIG_ENERGY, 0.0)
				got = s.inventory.add("stone", Levels.DIG_STONE)
			if levels.game.has_method("dev_advance"):
				levels.game.dev_advance(Levels.DIG_MINUTES)
			Sfx.play("impact/ground", at)
			Sfx.play("build/demolish", at)
			var txt := "Dug out 1 m² of basement (%d min%s)." % [int(Levels.DIG_MINUTES), ", +1 stone" if got > 0 else ""]
			if first:
				txt = "You start a basement under the house. " + txt + " Stairs down need 3 dug cells in a line."
			return txt
		"ext_demolish":
			var text := ""
			if r.has("stairs"):
				levels.remove_stairs(r["stairs"])
				text = "Stairs taken down."
			else:
				var c: Vector2i = r["tile"]
				Levels.remove_floor(bm.world, c)
				if levels.laid.has(_storey()):
					levels.laid[_storey()].erase(c)
				text = "Floor tile taken up." if _storey() != Levels.UPPER else "Floor tile taken up: a hole to the floor below."
			var s: GameState = bm.state
			var refund: Dictionary = r.get("refund", {})
			if s != null and not refund.is_empty() and not s.cheats.get("unlimited", false):
				var got := {}
				for k in refund:
					var n := s.inventory.add(k, refund[k])
					if n > 0:
						got[k] = n
				if not got.is_empty():
					text += " Got back %s." % BuildPieces.cost_text(got)
			Sfx.play("build/demolish", at)
			return text
	return ""


func _where(r: Dictionary) -> Vector3:
	var y := Levels.base_y(_storey()) + 0.5
	if r.has("tile"):
		var c := Levels.cell_center(r["tile"])
		return Vector3(c.x, y, c.y)
	if r.has("stairs"):
		var c := Levels.stairs_rect(r["stairs"]).get_center()
		return Vector3(c.x, y, c.y)
	return Vector3(7.0, y, 4.5)


# --- preview -------------------------------------------------------------------------

## Ghost items (BuildMode format [type, size, position, yaw, colour, style];
## positions relative to the storey's floor).
func ghost_items(bm: Node, r: Dictionary) -> Array:
	var ok: bool = r["ok"]
	var col: Color = BuildMode.GHOST_OK if ok else BuildMode.GHOST_BAD
	match r["piece"]:
		"wood_floor":
			return [_tile_ghost(r["tile"], 0.06, col)]
		"excavate":
			var c: Color = GHOST_DIG if ok else BuildMode.GHOST_BAD
			if _storey() == Levels.BASEMENT:
				var cc := Levels.cell_center(r["tile"])
				return [["wall_ghost", Vector3(1.02, 2.64, 1.02), Vector3(cc.x, 0, cc.y), 0.0, c, ""]]
			return [_tile_ghost(r["tile"], 0.08, c)]
		"stairs_up", "stairs_down":
			var st: Dictionary = r["stairs"]
			var rc := Levels.stairs_rect(st).get_center()
			var h := 1.45 if st["lo"] == Levels.GROUND else 0.08
			var yaw := PI * 0.5 if Levels.stairs_dir(st).x == 0 else 0.0     # the ghost's span runs along x at yaw 0
			var foot := Levels.cell_center(Levels.foot_cell(st))
			return [["wall_ghost", Vector3(0.98, h, 1.98), Vector3(rc.x, 0, rc.y), yaw, col, ""],
				["wall_ghost", Vector3(0.6, 0.04, 0.6), Vector3(foot.x, 0, foot.y), 0.0, col, ""]]
		"upper_floor":
			var f := HousePlan.FOOTPRINT
			return [["wall_ghost", Vector3(f.size.x + 0.3, 0.3, f.size.y + 0.3), Vector3(f.get_center().x, Levels.HEIGHT - 0.3, f.get_center().y), 0.0, col, ""]]
		"ext_demolish":
			var dc: Color = BuildMode.GHOST_TOOL["demolish"] if ok else BuildMode.GHOST_BAD
			if r.has("stairs"):
				var st: Dictionary = r["stairs"]
				var rc := Levels.stairs_rect(st).get_center()
				var yaw := PI * 0.5 if Levels.stairs_dir(st).x == 0 else 0.0     # the ghost's span runs along x at yaw 0
				return [["wall_ghost", Vector3(1.04, 1.5 if st["lo"] == Levels.GROUND else 0.1, 2.04), Vector3(rc.x, 0, rc.y), yaw, dc, ""]]
			if r.has("tile"):
				return [_tile_ghost(r["tile"], 0.1, dc)]
	return []


static func _tile_ghost(c: Vector2i, h: float, col: Color) -> Array:
	var cc := Levels.cell_center(c)
	return ["wall_ghost", Vector3(1.0, h, 0.99), Vector3(cc.x, 0, cc.y), 0.0, col, ""]
