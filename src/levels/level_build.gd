extends RefCounted
## Experiment 004 (owner L), generalised in Experiment 005 (V): BuildMode's
## extension for the storeys (BuildMode calls it through `ext` at a few
## hooks). It owns the "Floors & levels" pieces of palette key 0
## (BuildPieces: wood_floor, stairs_up, stairs_down, upper_floor = "Next
## storey", excavate, pillar; the stone foundation stays there too), adds
## stairs, pillars and floor tiles to Demolish, and on storeys other than the
## ground floor refuses pieces that would stand in mid-air or in solid earth.
##
## Every piece works on the storey being built on (GameLevels.view_storey:
## the player's own, or another picked with PageUp / PageDown in build
## mode), with one set of rules for -2..+2:
##   wooden floor  1 m tile where a cell has no floor (2 planks, 2 nails);
##                 below ground on dug cells; above ground where it is held
##                 (a wall or pillar under its edges, or floor next to it;
##                 HouseSupport.tile_support_reason)
##   stairs up     on the ground floor or higher (up to +1), 1 x 2 m + a free
##                 cell at the foot (R turns); they reach the storey above
##                 once it is built (8 planks, 10 nails)
##   stairs down   on the ground floor or lower (down to -1), over dug cells
##                 of the storey below: the two under the stairs and the one
##                 past their end (8 planks, 10 nails)
##   next storey   needs stairs up on the storey under it and outer walls
##                 that carry it: deck, outer walls, windows over the house
##                 (40 planks, 40 nails, 4 iron); +1, then +2 from +1
##   excavate      a shovel; from the ground floor any cell under the house
##                 (-1); in a basement a cell next to the dug space; the
##                 lower basement (-2) under dug basement cells (PageDown
##                 from -1) or next to its own dug space; 25 minutes, 6
##                 energy, +1 stone
##   pillar        a 0.4 m masonry column in the middle of a cell (4 stone):
##                 carries a floor tile above it and props an outer wall
##                 (HouseSupport)
##   demolish      stairs, pillars (full refund) and floor tiles (yours: full
##                 refund; the house's: 1 plank; packed earth: nothing)

const IDS := ["wood_floor", "stairs_up", "stairs_down", "upper_floor", "excavate", "pillar"]
const NOTHING := "Nothing to demolish here."
const ORIGINAL_TILE_REFUND := {"wood": 1}
const GHOST_DIG := Color(0.85, 0.6, 0.3, 0.34)
const STAIRS_FIRST := "Build stairs up first (this key, R turns them)."

var levels: Node                       ## game_levels.gd


func _init(l: Node) -> void:
	levels = l


## Pieces that aim at the floor plane of the storey being built on.
func uses_plane(id: String) -> bool:
	return id in IDS


## The storey being built on.
func _storey() -> int:
	return levels.view_storey


func _not_built(storey: int) -> String:
	if storey > Levels.GROUND:
		return "%s isn't built yet: Next storey (this key) builds it." % Levels.label(storey)
	return "%s isn't dug yet: Excavate (this key) digs it." % Levels.label(storey)


static func _cost(id: String) -> Dictionary:
	return BuildPieces.LIST[BuildPieces.index_of(id)]["cost"]


# --- evaluation ------------------------------------------------------------------------

## Called at the end of BuildMode.evaluate (before the cost check). Fills `r`
## for this extension's pieces; adds level rules to the others.
func post_evaluate(bm: Node, r: Dictionary, p: Vector2, _from: Vector2) -> void:
	var id: String = r["piece"]
	var e := _storey()
	if id in IDS:
		r["ext"] = true
		r["cost"] = _cost(id)
		r["storey"] = e
		match id:
			"wood_floor":
				_eval_floor(r, p)
			"stairs_up", "stairs_down":
				var up: bool = id == "stairs_up"
				var st := Levels.make_stairs(e if up else e - 1, Levels.cell_of(p), bm.rot)
				r["stairs"] = st
				if levels.world_of(e) == null:
					r["reason"] = _not_built(e)
				elif up and e < Levels.GROUND:
					r["reason"] = "Below ground, stairs go down (the next piece, Stairs down)."
				elif up and e >= Levels.HIGHEST:
					r["reason"] = "Nothing above %s: the house has five levels at most." % Levels.label(e)
				elif not up and e > Levels.GROUND:
					r["reason"] = "Above ground, stairs go up (the piece before, Stairs up)."
				elif not up and e <= Levels.LOWEST:
					r["reason"] = "Nothing below %s: the house has five levels at most." % Levels.label(e)
				else:
					r["reason"] = stairs_reason(st)
			"upper_floor":
				_eval_next_storey(r)
			"excavate":
				_eval_dig(bm, r, p)
			"pillar":
				_eval_pillar(r, p)
		return
	if id == "demolish":
		_eval_demolish(bm, r, p)
		return
	if levels.world_of(e) == null:
		r["reason"] = _not_built(e)
		return
	if r["reason"] != "":
		return
	# Every other piece: not on the stairs or a pillar; upstairs on the deck; downstairs in dug space.
	var rects := []
	for s in r.get("segs", []):
		rects.append(HouseWorld.seg_rect(s, 0.15 if id != "foundation" else HouseWorld.FOUNDATION_HALF))
	if r.get("pos", Vector2.INF) != Vector2.INF and r.has("kind"):
		rects.append(WorldObject.footprint_of(r["kind"], r["pos"], int(r.get("rot", 0))))
	for rect in rects:
		if BuildPieces.LIST[bm.piece]["tool"] == "place" and _on_stairs(rect, e):
			r["reason"] = "The stairs are in the way."
			return
		if BuildPieces.LIST[bm.piece]["tool"] == "place" and _on_pillar(rect, e):
			r["reason"] = "A pillar is in the way."
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


func _on_pillar(rect: Rect2, storey: int) -> bool:
	for c in levels.pillars.get(storey, {}):
		if Levels.pillar_rect(c).intersects(rect):
			return true
	return false


func _eval_floor(r: Dictionary, p: Vector2) -> void:
	var c := Levels.cell_of(p)
	r["tile"] = c
	var e := _storey()
	var w: HouseWorld = levels.world_of(e)
	if w == null:
		r["reason"] = _not_built(e)
	elif not Levels.in_house(c):
		r["reason"] = "Floors go inside the house."
	elif e < Levels.GROUND and not (w as LevelWorld).is_dug(c):
		r["reason"] = "Dig this cell out first."
	elif _on_stairs(Levels.cell_rect(c), e):
		r["reason"] = "The stairs are here."
	elif Levels.floor_coverage(w, c) >= 0.5:
		r["reason"] = "There's already a floor here (Demolish takes a tile up)."
	elif e > Levels.GROUND:
		var sup: HouseSupport = levels.game.world.support
		if sup != null:
			r["reason"] = sup.tile_support_reason(w, levels.world_of(e - 1), c)


## "Next storey": the storey above the one being built on (or the viewed one
## itself when it isn't built yet).
func _eval_next_storey(r: Dictionary) -> void:
	var e := _storey()
	var t := e if levels.world_of(e) == null and e > Levels.GROUND else e + 1
	r["target"] = t
	if t <= Levels.GROUND:
		r["reason"] = "Storeys go above ground (Excavate digs below)."
	elif t > Levels.HIGHEST:
		r["reason"] = "Nothing above %s: the house has five levels at most." % Levels.label(Levels.HIGHEST)
	elif levels.world_of(t) != null:
		r["reason"] = "%s is already built (PgUp or the stairs take you there)." % Levels.label(t)
	elif levels.world_of(t - 1) == null:
		r["reason"] = "Build %s first." % Levels.label(t - 1)
	elif levels.stairs.filter(func(s): return int(s["lo"]) == t - 1).is_empty():
		r["reason"] = STAIRS_FIRST if t - 1 == e else "Build stairs up on %s first." % Levels.label(t - 1)
	else:
		var sup: HouseSupport = levels.game.world.support
		if sup != null:
			var states := sup.zone_states(levels.world_of(t - 1))
			for z in HouseSupport.ZONES:
				if states[z["id"]]["fail"]:
					r["reason"] = "The outer walls of %s can't carry another storey over %s: rebuild them first." % [Levels.label(t - 1), z["name"]]
					return
		if t >= 2:      # Exp 006 (B): a third level needs a stone footing along the house
			var why := HouseSupport.footing_reason(levels.game.world)
			if why != "":
				r["reason"] = why


func _eval_dig(bm: Node, r: Dictionary, p: Vector2) -> void:
	var c := Levels.cell_of(p)
	r["tile"] = c
	r["cost"] = {}
	var e := _storey()
	var t := Levels.BASEMENT if e == Levels.GROUND else e
	r["dig"] = t
	var s: GameState = bm.state
	var tw: LevelWorld = levels.world_of(t) if t < Levels.GROUND else null
	var from_above: bool = levels.player_storey > t
	if s != null and s.inventory.count("shovel") <= 0 and not s.cheats.get("unlimited", false):
		r["reason"] = "You need a shovel to dig."
	elif e > Levels.GROUND:
		r["reason"] = "Dig from the ground floor or below."
	elif not Levels.in_house(c):
		r["reason"] = "A basement goes under the house."
	elif tw != null and tw.is_dug(c):
		r["reason"] = "Already dug out." + (" PgDn shows the level below to dig it." if t > Levels.LOWEST else " Nothing below the lower basement.")
	elif t == Levels.LOWER_BASEMENT and levels.world_of(Levels.BASEMENT) == null:
		r["reason"] = "Dig the basement first."
	elif t == Levels.LOWER_BASEMENT and not _next_to_dug(tw, c) and not (from_above and levels.world_of(Levels.BASEMENT).is_dug(c)):
		r["reason"] = "Dig the lower basement under the dug basement, or next to the space you've dug out."
	elif t == Levels.BASEMENT and not from_above and not _next_to_dug(tw, c):
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


func _eval_pillar(r: Dictionary, p: Vector2) -> void:
	var c := Levels.cell_of(p)
	r["tile"] = c
	var e := _storey()
	var w: HouseWorld = levels.world_of(e)
	var rect := Levels.pillar_rect(c)
	if w == null:
		r["reason"] = _not_built(e)
	elif not Levels.in_house(c):
		r["reason"] = "Pillars go inside the house."
	elif levels.pillars.get(e, {}).has(c):
		r["reason"] = "There's a pillar here already."
	elif _on_stairs(Levels.cell_rect(c), e):
		r["reason"] = "The stairs are here."
	elif e < Levels.GROUND and not (w as LevelWorld).is_dug(c):
		r["reason"] = "Dig this cell out first."
	elif e > Levels.GROUND and not (w as LevelWorld).has_floor_at(Levels.cell_center(c)):
		r["reason"] = "There's no floor there."
	elif w.grid.any_struct_in(rect.position, rect.end, VoxelHouse.NAV_ROW_LO, VoxelHouse.NAV_ROW_HI):
		r["reason"] = "A wall is in the way."
	elif not w.objects_in(rect.grow(0.05)).is_empty():
		r["reason"] = "Something is standing here."
	elif w.furniture_in(rect.grow(0.05)):
		r["reason"] = "Furniture is in the way."
	elif w.bodies_in(rect.grow(0.1)):
		r["reason"] = "Someone is standing there."


## Why stairs `st` can't be built ("" = they can): see the file header.
func stairs_reason(st: Dictionary) -> String:
	var lo := int(st["lo"])
	var ss := Levels.start_storey(st)
	var g: HouseWorld = levels.world_of(ss)
	if g == null:
		return _not_built(ss)
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
		if _on_pillar(rect, ss):
			return "A pillar is in the way."
		for o in levels.stairs:
			if not _shares_storey(o, st):
				continue
			if Levels.stairs_rect(o).grow(-0.05).intersects(rect) or Levels.cell_rect(Levels.foot_cell(o)).grow(-0.05).intersects(rect):
				return "Other stairs are in the way."
		if g.bodies_in(rect.grow(-0.1)):
			return "Someone is standing there."
		if not _floor_ok(g, ss, c):
			return "Stairs stand on a floor: lay one here first."
	if Levels.wall_on(g, foot) or g.furniture_in(Levels.cell_rect(foot).grow(-0.05)) or not _floor_ok(g, ss, foot):
		return "Keep the cell at the foot of the stairs free."
	for o in levels.stairs:
		if _shares_storey(o, st) and Levels.stairs_rect(o).grow(-0.05).intersects(Levels.cell_rect(foot)):
			return "Keep the cell at the foot of the stairs free."
	if Levels.is_up(st):
		if not Levels.in_house(far):
			return "The top of the stairs must end inside the house."
		var u: LevelWorld = levels.world_of(lo + 1)
		if u != null and (Levels.wall_on(u, far) or not u.has_floor_at(Levels.cell_center(far))):
			return "The top of the stairs must end on the floor above (%s)." % Levels.label(lo + 1)
	else:
		var b: LevelWorld = levels.world_of(lo)
		var need := "Dig out %s first: the two cells under the stairs and one past their end." % Levels.label(lo)
		if b == null:
			return need
		for c in cells + [far]:
			if not b.is_dug(c):
				return need
			if Levels.wall_on(b, c) or not b.objects_in(Levels.cell_rect(c).grow(-0.05)).is_empty() or _on_pillar(Levels.cell_rect(c), lo):
				return "Something stands on %s under the stairs." % Levels.label(lo)
	return ""


## True if stairs a and b touch a common storey (then they can't overlap).
static func _shares_storey(a: Dictionary, b: Dictionary) -> bool:
	return absi(int(a["lo"]) - int(b["lo"])) <= 1


## A walkable floor in cell c of storey world w: the ground floor always,
## above ground a floor finish, below ground a dug cell with its floor.
static func _floor_ok(w: HouseWorld, storey: int, c: Vector2i) -> bool:
	if storey == Levels.GROUND or not (w is LevelWorld):
		return true
	var lw := w as LevelWorld
	if storey < Levels.GROUND and not lw.is_dug(c):
		return false
	return lw.has_floor_at(Levels.cell_center(c))


func _eval_demolish(_bm: Node, r: Dictionary, p: Vector2) -> void:
	var storey := _storey()
	var w: HouseWorld = levels.world_of(storey)
	if w == null:
		r["reason"] = _not_built(storey)
		return
	var st: Dictionary = levels.stairs_at(p, storey)
	if not st.is_empty():
		_claim(r)
		r["stairs"] = st
		r["storey"] = storey
		r["refund"] = Levels.STAIRS_COST.duplicate()
		r["reason"] = "Someone is standing on the stairs." if w.bodies_in(Levels.stairs_rect(st).grow(-0.1)) else ""
		return
	var pc: Variant = levels.pillar_at(storey, p)
	if pc != null:
		_claim(r)
		r["pillar"] = pc
		r["storey"] = storey
		r["refund"] = Levels.PILLAR_COST.duplicate()
		return
	if r["reason"] != NOTHING:
		return
	var c := Levels.cell_of(p)
	if not Levels.in_house(c) or _on_stairs(Levels.cell_rect(c), storey) or Levels.floor_coverage(w, c) < 0.3:
		return
	if storey < Levels.GROUND and not (w as LevelWorld).is_dug(c):
		return
	_claim(r)
	r["tile"] = c
	r["storey"] = storey
	var mine: bool = levels.laid.get(storey, {}).has(c)
	if mine:
		r["refund"] = Levels.WOOD_FLOOR_COST.duplicate()
	else:
		r["refund"] = {} if storey < Levels.GROUND else ORIGINAL_TILE_REFUND.duplicate()


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
	var e: int = int(r.get("storey", _storey()))
	match r["piece"]:
		"wood_floor":
			var c: Vector2i = r["tile"]
			Levels.lay_wood_floor(levels.world_of(e), c)
			if not levels.laid.has(e):
				levels.laid[e] = {}
			levels.laid[e][c] = true
			Sfx.play("build/place", at)
			Sfx.play("build/hammer", at)
			return "Wooden floor laid on %s (%s)." % [Levels.label(e), BuildPieces.cost_text(r["cost"])]
		"stairs_up", "stairs_down":
			var st: Dictionary = r["stairs"]
			levels.add_stairs(st)
			Sfx.play("build/place", at)
			Sfx.play("build/hammer", at)
			var to := Levels.other_storey(st, e)
			if r["piece"] == "stairs_down":
				return "Stairs down to %s built. Walk onto them or press E." % Levels.label(to)
			if levels.world_of(to) == null:
				return "Stairs up built. They end at the ceiling until you build the next storey (0 again: Next storey)."
			return "Stairs up to %s built. Walk onto them or press E." % Levels.label(to)
		"upper_floor":
			var t: int = r["target"]
			levels.build_storey(t)
			Sfx.play("build/place", at)
			Sfx.play("build/hammer", at)
			return "%s is up: a deck, outer walls and windows. Take the stairs (or PgUp here) and build on it." % Levels.label(t)
		"excavate":
			var c: Vector2i = r["tile"]
			var t: int = r.get("dig", Levels.BASEMENT)
			var first: bool = levels.world_of(t) == null
			levels.dig(c, t)
			var s: GameState = bm.state
			var got := 0
			if s != null:
				s.energy = maxf(s.energy - Levels.DIG_ENERGY, 0.0)
				got = s.inventory.add("stone", Levels.DIG_STONE)
			if levels.game.has_method("dev_advance"):
				levels.game.dev_advance(Levels.DIG_MINUTES)
			Sfx.play("impact/ground", at)
			Sfx.play_first(["build/dig", "build/demolish"], at)     # Exp 005 (A): a recorded dig sound when the inbox has one
			var txt := "Dug out 1 m² of %s (%d min%s)." % [Levels.name_of(t).to_lower(), int(Levels.DIG_MINUTES), ", +1 stone" if got > 0 else ""]
			if first:
				txt = "You start the %s (%s). " % [Levels.name_of(t).to_lower(), Levels.label(t)] + txt + " Stairs down need 3 dug cells in a line."
			return txt
		"pillar":
			var c: Vector2i = r["tile"]
			levels.add_pillar(e, c)
			Sfx.play("build/place", at)
			Sfx.play("build/hammer", at)
			return "Stone pillar up (%s): it carries the floor above it and props an outer wall within 2 m." % BuildPieces.cost_text(r["cost"])
		"ext_demolish":
			var text := ""
			if r.has("stairs"):
				levels.remove_stairs(r["stairs"])
				text = "Stairs taken down."
			elif r.has("pillar"):
				levels.remove_pillar(e, r["pillar"])
				text = "Pillar taken down."
			else:
				var c: Vector2i = r["tile"]
				Levels.remove_floor(levels.world_of(e), c)
				if levels.laid.has(e):
					levels.laid[e].erase(c)
				text = "Floor tile taken up." if e <= Levels.GROUND else "Floor tile taken up: a hole to the floor below."
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
	var y := Levels.base_y(int(r.get("storey", _storey()))) + 0.5
	if r.has("tile"):
		var c := Levels.cell_center(r["tile"])
		return Vector3(c.x, y, c.y)
	if r.has("pillar"):
		var c := Levels.cell_center(r["pillar"])
		return Vector3(c.x, y, c.y)
	if r.has("stairs"):
		var c := Levels.stairs_rect(r["stairs"]).get_center()
		return Vector3(c.x, y, c.y)
	return Vector3(7.0, y, 4.5)


# --- preview -------------------------------------------------------------------------

## Ghost items (BuildMode format [type, size, position, yaw, colour, style];
## positions relative to the floor of the storey being built on).
func ghost_items(bm: Node, r: Dictionary) -> Array:
	var ok: bool = r["ok"]
	var col: Color = BuildMode.GHOST_OK if ok else BuildMode.GHOST_BAD
	match r["piece"]:
		"wood_floor":
			return [_tile_ghost(r["tile"], 0.06, col)]
		"excavate":
			var c: Color = GHOST_DIG if ok else BuildMode.GHOST_BAD
			if _storey() < Levels.GROUND:
				var cc := Levels.cell_center(r["tile"])
				return [["wall_ghost", Vector3(1.02, 2.64, 1.02), Vector3(cc.x, 0, cc.y), 0.0, c, ""]]
			return [_tile_ghost(r["tile"], 0.08, c)]
		"pillar":
			var cc := Levels.cell_center(r["tile"])
			return [["wall_ghost", Vector3(0.42, 2.6, 0.42), Vector3(cc.x, 0, cc.y), 0.0, col, ""]]
		"stairs_up", "stairs_down":
			var st: Dictionary = r["stairs"]
			var rc := Levels.stairs_rect(st).get_center()
			var h := 1.45 if Levels.is_up(st) else 0.08
			var yaw := PI * 0.5 if Levels.stairs_dir(st).x == 0 else 0.0     # the ghost's span runs along x at yaw 0
			var foot := Levels.cell_center(Levels.foot_cell(st))
			return [["wall_ghost", Vector3(0.98, h, 1.98), Vector3(rc.x, 0, rc.y), yaw, col, ""],
				["wall_ghost", Vector3(0.6, 0.04, 0.6), Vector3(foot.x, 0, foot.y), 0.0, col, ""]]
		"upper_floor":
			var f := HousePlan.FOOTPRINT
			var t: int = r.get("target", _storey() + 1)
			var y := Levels.base_y(t) - float(bm.plane_y) - 0.15
			return [["wall_ghost", Vector3(f.size.x + 0.3, 0.3, f.size.y + 0.3), Vector3(f.get_center().x, y, f.get_center().y), 0.0, col, ""]]
		"ext_demolish":
			var dc: Color = BuildMode.GHOST_TOOL["demolish"] if ok else BuildMode.GHOST_BAD
			if r.has("stairs"):
				var st: Dictionary = r["stairs"]
				var rc := Levels.stairs_rect(st).get_center()
				var yaw := PI * 0.5 if Levels.stairs_dir(st).x == 0 else 0.0     # the ghost's span runs along x at yaw 0
				var y0 := Levels.base_y(Levels.start_storey(st)) - float(bm.plane_y)
				return [["wall_ghost", Vector3(1.04, 1.5 if Levels.is_up(st) else 0.1, 2.04), Vector3(rc.x, y0, rc.y), yaw, dc, ""]]
			if r.has("pillar"):
				var cc := Levels.cell_center(r["pillar"])
				return [["wall_ghost", Vector3(0.48, 2.66, 0.48), Vector3(cc.x, 0, cc.y), 0.0, dc, ""]]
			if r.has("tile"):
				return [_tile_ghost(r["tile"], 0.1, dc)]
	return []


static func _tile_ghost(c: Vector2i, h: float, col: Color) -> Array:
	var cc := Levels.cell_center(c)
	return ["wall_ghost", Vector3(1.0, h, 0.99), Vector3(cc.x, 0, cc.y), 0.0, col, ""]
