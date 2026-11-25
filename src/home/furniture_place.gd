class_name FurniturePlace
extends RefCounted
## Experiment 005 (F): BuildMode's furniture pieces and the Move tool (key 5
## "Furniture & storage"). BuildMode calls these at its evaluate / apply /
## ghost hooks; everything works on build mode's current `world`, so it is
## the same on every storey.
##
## Placing (FurnitureCatalog.PLACEABLE): a floor piece follows the floor point
## under the mouse (footprint snapped to 5 cm, R turns it); a painting aims at
## a wall and hangs on the player's side; a table lamp stands on a surface
## (a table, nightstand, dresser, counter... up to 1.1 m) or the floor.
## Refused: outside the lot, in a wall, overlapping furniture or objects,
## within 0.6 m of a doorway or door, on stairs, over a hole upstairs or undug
## earth below, where someone stands, or when it would seal the last way out.
##
## Move: click a piece (a placed one or the house's own, except the plumbed
## and wired fixtures and the old bed) to pick it up; it stays put while you
## choose the new spot (a ghost follows the mouse, R turns it); click to set
## it down (free). RMB, Esc or another tool puts it back. The piece keeps its
## HP, size, contents and lamp switch; a house piece becomes a placed object
## of the same type (demolishing it still gives salvage, not a full refund).
## It can be carried to another storey.

const DOOR_CLEAR := 0.6
const PICK_COLOR := Color(0.55, 0.85, 1.0, 0.34)


static func handles(id: String) -> bool:
	return id == "move" or FurnitureCatalog.is_placeable(id)


## True when the pointer should follow the floor plane (not the aimed surface).
static func uses_plane(bm: Node) -> bool:
	var id: String = bm.piece_id()
	if FurnitureCatalog.is_placeable(id):
		return not FurnitureCatalog.is_wall_hung(id)
	if id == "move" and not bm.carry.is_empty():
		return not FurnitureCatalog.is_wall_hung(bm.carry["kind"])
	return false


static func target_key(bm: Node, p: Vector2) -> String:
	var id: String = bm.piece_id()
	var kind := id if id != "move" else str(bm.carry.get("kind", ""))
	if kind == "":
		return "move|%s|%s" % [str((p * 10.0).round()), bm._ptr_furniture]
	if FurnitureCatalog.is_wall_hung(kind):
		return "%s|%s|%s|%s" % [id, kind, str(HouseWorld.nearest_seg(p)), str((p * 20.0).round())]
	return "%s|%s|%s|%d" % [id, kind, str(FurnitureCatalog.snap(_size(bm, kind), p, bm.rot)), bm.rot]


static func _size(bm: Node, kind: String) -> Vector3:
	if bm.piece_id() == "move" and not bm.carry.is_empty() and bm.carry["size"] != Vector3.ZERO:
		return bm.carry["size"]
	return WorldObject.DEFS[kind]["size"]


# --- evaluation ------------------------------------------------------------------------

static func evaluate(bm: Node, r: Dictionary, p: Vector2) -> void:
	var id: String = r["piece"]
	if id == "move":
		if bm.carry.is_empty():
			_eval_pick(bm, r, p)
			return
		r["moving"] = true
		_eval_spot(bm, r, str(bm.carry["kind"]), p, bm.carry)
		r["cost"] = {}
		return
	r["cost"] = BuildPieces.LIST[bm.piece]["cost"]
	_eval_spot(bm, r, id, p, {})


## Fills r with "pos", "rot", "kind", "lift" and the reason for `kind` at p.
static func _eval_spot(bm: Node, r: Dictionary, kind: String, p: Vector2, carry: Dictionary) -> void:
	r["kind"] = kind
	var w: HouseWorld = bm.world
	var size := _size(bm, kind)
	r["size"] = size
	if FurnitureCatalog.is_wall_hung(kind):
		_eval_wall(bm, r, kind, size, p, carry)
		return
	var pos := FurnitureCatalog.snap(size, p, bm.rot)
	r["pos"] = pos
	r["rot"] = bm.rot
	var res := check(w, kind, size, pos, bm.rot, carry.get("object"), str(carry.get("piece", "")) if carry.get("world") == w else "")
	r["lift"] = res["lift"]
	r["reason"] = res["reason"]
	if r["reason"] == "":
		r["reason"] = _level_reason(bm, FurnitureCatalog.footprint(size, pos, bm.rot))


## Why `kind` (of canonical `size`) can't stand at plan centre `pos` turned
## `rot` on world `w` ("" = it can), and the lift of a table lamp:
## {"reason", "lift"}. `ignore_obj` / `ignore_piece`: the piece being moved.
static func check(w: HouseWorld, kind: String, size: Vector3, pos: Vector2, rot: int, ignore_obj: Variant = null, ignore_piece := "") -> Dictionary:
	var out := {"reason": "", "lift": 0.0}
	var fp := FurnitureCatalog.footprint(size, pos, rot)
	if not HouseWorld.LOT.encloses(fp):
		out["reason"] = "Outside the lot: the fog starts there."
		return out
	var inner := fp.grow(-0.03)
	if w.design.any_struct_in(inner.position, inner.end, VoxelHouse.NAV_ROW_LO, VoxelHouse.NAV_ROW_HI) \
			or w.grid.any_struct_in(inner.position, inner.end, VoxelHouse.NAV_ROW_LO, VoxelHouse.NAV_ROW_HI):
		out["reason"] = "There's a wall in the way."
		return out
	if kind == "table_lamp":
		out["lift"] = surface_at(w, pos, ignore_obj, ignore_piece)
	var flat := FurnitureCatalog.is_flat(kind)
	for o in w.objects_in(inner):
		if o == ignore_obj or o.kind == "painting":
			continue
		if kind == "rug" and o.kind != "rug":
			continue          # a rug lies under things
		if kind != "rug" and o.kind == "rug":
			continue
		if kind == "table_lamp" and out["lift"] > 0.0 and FurnitureCatalog.is_furniture(o.kind) and o.footprint().has_point(pos):
			continue          # the surface it stands on
		out["reason"] = "Something is already standing here."
		return out
	if kind != "rug":
		var fid := _piece_in(w, inner, ignore_piece)
		if fid != "" and not (kind == "table_lamp" and out["lift"] > 0.0):
			out["reason"] = "Furniture is in the way."
			return out
		if _blocked_static(w, inner):
			out["reason"] = "Something is in the way."
			return out
	if not flat:
		if _blocks_door(w, fp):
			out["reason"] = "That would block a doorway."
			return out
		if w.bodies_in(fp.grow(0.05)):
			out["reason"] = "Someone is standing there."
			return out
		var extra := {}
		if ignore_obj is WorldObject:
			for c in w.nav.cells_in_rect((ignore_obj as WorldObject).footprint()):
				extra[c] = GridNav.OPEN
		elif ignore_piece != "" and w.furniture != null and w.furniture.pieces.has(ignore_piece):
			for c in w.nav.cells_in_rect(w.furniture.pieces[ignore_piece]["f"]["rect"]):
				extra[c] = GridNav.OPEN
		for c in w.nav.cells_in_rect(fp):
			extra[c] = GridNav.SOLID
		if not w.exit_path_exists(extra):
			out["reason"] = BuildMode.SEAL_REASON
	return out


## A standing original piece (other than `ignore`) whose blocking rect meets `rect`.
static func _piece_in(w: HouseWorld, rect: Rect2, ignore: String) -> String:
	if w.furniture == null:
		return ""
	for id in w.furniture.pieces:
		if id == ignore or not w.furniture.ok(id):
			continue
		var f: Dictionary = w.furniture.pieces[id]["f"]
		if f["blocks"] and (f["rect"] as Rect2).intersects(rect):
			return id
	return ""


## Fixed fittings (the fireplace and its clearance) and, on the ground, yard props.
static func _blocked_static(w: HouseWorld, rect: Rect2) -> bool:
	for b in w.static_blockers:
		if (b["reserve"] as Rect2).intersects(rect):
			return true
	if w is LevelWorld:
		return false
	for f in HousePlan.PROPS:
		if f["blocks"] and (f["rect"] as Rect2).intersects(rect):
			return true
	return false


## Within DOOR_CLEAR of a door or a doorway (the house's or cut ones).
static func _blocks_door(w: HouseWorld, fp: Rect2) -> bool:
	for o in w.objects:
		if o.kind == "door" and HouseWorld.seg_rect(o.seg, DOOR_CLEAR, -0.05).intersects(fp):
			return true
	for op in w.openings:
		var a := float(op["from"]) + 0.05
		var b := float(op["to"]) - 0.05
		var line := float(op["line"])
		var rect := Rect2(a, line - DOOR_CLEAR, b - a, DOOR_CLEAR * 2.0) if int(op["axis"]) == 0 else Rect2(line - DOOR_CLEAR, a, DOOR_CLEAR * 2.0, b - a)
		if rect.intersects(fp):
			return true
	return false


## The height of the surface under plan point p (a table, nightstand,
## dresser, counter... up to SURFACE_MAX), or 0 for the floor.
static func surface_at(w: HouseWorld, p: Vector2, ignore_obj: Variant = null, ignore_piece := "") -> float:
	var h := 0.0
	for o in w.objects:
		if o == ignore_obj or not FurnitureCatalog.is_furniture(o.kind) or FurnitureCatalog.is_flat(o.kind):
			continue
		var top: float = o.size3().y
		if top <= FurnitureCatalog.SURFACE_MAX and o.footprint().grow(-0.05).has_point(p):
			h = maxf(h, top)
	if w.furniture != null:
		for id in w.furniture.pieces:
			if id == ignore_piece or not w.furniture.ok(id):
				continue
			var f: Dictionary = w.furniture.pieces[id]["f"]
			if float(f["height"]) <= FurnitureCatalog.SURFACE_MAX and f["blocks"] and (f["rect"] as Rect2).grow(-0.05).has_point(p):
				h = maxf(h, float(f["height"]))
	return h


## Stairs and storey rules (LevelBuild's, through BuildMode.ext when present).
static func _level_reason(bm: Node, rect: Rect2) -> String:
	var ext: Object = bm.ext
	if ext != null and ext.has_method("_on_stairs") and ext.get("levels") != null:
		var storey: int = ext.levels.player_storey
		if ext._on_stairs(rect, storey):
			return "The stairs are in the way."
	if bm.world is LevelWorld and bm.world.has_method("level_block_reason"):
		return str(bm.world.level_block_reason(rect))
	return ""


## Paintings hang on a wall section, on the side the pointer (the player) is on.
static func _eval_wall(bm: Node, r: Dictionary, kind: String, size: Vector3, p: Vector2, carry: Dictionary) -> void:
	var w: HouseWorld = bm.world
	var s := HouseWorld.nearest_seg(p)
	var info := w.section_info(s)
	if not info["exists"] or not info["wall"] or info["glass"] or info["integrity"] < 0.5:
		r["reason"] = "Aim at a wall: it hangs on it."
		return
	var across := (p.y - s.y) if s.x == 0 else (p.x - s.y)
	var side := signf(across)
	if absf(across) < 0.02:
		side = -float(w.outer_sign(s))
		if bm.player != null:
			var pp := Vector2(bm.player.global_position.x, bm.player.global_position.z)
			side = signf(((pp.y - s.y) if s.x == 0 else (pp.x - s.y)) + 1e-4)
	var sec: Dictionary = w.sections.get(s, {})
	var half := 0.1
	if sec.get("material", "") == "stone" or (sec.get("orig", false) and w._is_outer_wall(s)):
		half = HouseWorld.STONE_HALF
	var n := Vector2(0, side) if s.x == 0 else Vector2(side, 0)
	var pos := HouseWorld.seg_center(s) + n * (half + size.z * 0.5 + 0.005)
	var rr := 0
	if n.x > 0.5:
		rr = 1
	elif n.y > 0.5:
		rr = 2
	elif n.x < -0.5:
		rr = 3
	r["pos"] = pos
	r["rot"] = rr
	var fp := FurnitureCatalog.footprint(size, pos, rr)
	if not HouseWorld.LOT.encloses(fp):
		r["reason"] = "Outside the lot: the fog starts there."
		return
	for o in w.objects_in(fp.grow(-0.01)):
		if o != carry.get("object") and o.kind in ["painting", "fuse_box", "door", "boards"]:
			r["reason"] = "Something is already hanging here."
			return


## Move, nothing carried: what the pointer is on.
static func _eval_pick(bm: Node, r: Dictionary, p: Vector2) -> void:
	var w: HouseWorld = bm.world
	var o: WorldObject = w.object_at(p, 0.2)
	if o != null:
		if o.kind == "loot_pile":
			r["reason"] = "Search the pile instead (E): it goes when it's empty."
			return
		if not FurnitureCatalog.is_furniture(o.kind):
			r["reason"] = "Only furniture can be moved."
			return
		r["object"] = o
		r["pick"] = {"world": w, "object": o, "piece": "", "kind": o.kind, "size": o.size_override, "rot": o.rot, "name": o.display_name()}
		return
	var fid: String = bm._ptr_furniture if bm._ptr_furniture != "" and bm.debug_pointer == Vector2.INF else ""
	if fid == "" and w.furniture != null:
		fid = w.furniture.piece_at(p, 0.0, false)
	if fid != "" and w.furniture != null and w.furniture.ok(fid):
		var f: Dictionary = w.furniture.pieces[fid]["f"]
		r["furniture"] = fid
		var why := FurnitureCatalog.move_block(f["type"])
		if why != "":
			r["reason"] = why
			return
		r["pick"] = {"world": w, "object": null, "piece": fid, "kind": f["type"],
			"size": FurnitureCatalog.size_of_rect(f["rect"], f["height"], f["facing"]), "rot": FurnitureCatalog.rot_of_facing(f["facing"]),
			"name": str(f["type"]).capitalize()}
		return
	r["reason"] = "Click a piece of furniture to pick it up."


# --- applying --------------------------------------------------------------------------

## Applies a valid evaluation (costs already paid). Returns the message.
static func apply(bm: Node, r: Dictionary) -> String:
	var id: String = r["piece"]
	var w: HouseWorld = bm.world
	var at := Vector3(r["pos"].x, 0.5, r["pos"].y) if r.get("pos", Vector2.INF) != Vector2.INF else Vector3.ZERO
	if id == "move" and r.has("pick"):
		bm.carry = r["pick"]
		bm.rot = int(r["pick"]["rot"])
		Sfx.ui("ui/click")
		return "Picked up the %s: click where it goes (R turns it, RMB puts it back)." % str(r["pick"]["name"]).to_lower()
	if id == "move":
		var text := _move(bm, r)
		Sfx.play("build/place", at)
		return text
	var o := w.place_object(r["kind"], r["pos"], r["rot"], true)
	if float(r.get("lift", 0.0)) > 0.0:
		o.set_lift(r["lift"])
	Sfx.play("build/place", at)
	Sfx.play("build/hammer", at)
	var cap := FurnitureStorage.capacity(r["kind"])
	return "%s placed%s." % [o.display_name(), (": holds %d" % cap) if cap > 0 else ""]


static func _move(bm: Node, r: Dictionary) -> String:
	var c: Dictionary = bm.carry
	bm.carry = {}
	var src: HouseWorld = c["world"]
	var w: HouseWorld = bm.world
	var hp := -1
	var built := false
	var items := {}
	var lamp := true
	var size: Vector3 = c["size"]
	if c["object"] != null:
		var o: WorldObject = c["object"]
		if not is_instance_valid(o) or not src.objects.has(o):
			return "It's gone."
		hp = o.hp
		built = o.built
		items = o.items.duplicate()
		o.items.clear()
		lamp = o.lamp_on
		src.remove_object(o)
	else:
		if src.furniture == null:
			return "It's gone."
		var d: Dictionary = src.furniture.take_out(c["piece"])
		if d.is_empty():
			return "It's gone."
		var max_hp := WorldObject.max_hp_of(c["kind"])
		hp = clampi(roundi(float(d["hp"]) / float(maxi(int(d["max_hp"]), 1)) * max_hp), 1, max_hp)
		items = d["items"]
	var n := w.place_object(c["kind"], r["pos"], r["rot"], built)
	if size != Vector3.ZERO and size != WorldObject.DEFS[c["kind"]]["size"]:
		n.set_size(size)
		w._index_objects()
		w._recompute_nav(n.footprint().grow(GridNav.CELL))
	if hp > 0:
		n.set_hp(hp)
	FurnitureStorage.merge(n.items, items)
	n.set_lamp(lamp)
	if float(r.get("lift", 0.0)) > 0.0:
		n.set_lift(r["lift"])
	if src != w:
		src.furniture_layout_changed.emit()
	w.furniture_layout_changed.emit()
	return "Moved the %s." % str(c["name"]).to_lower()


# --- preview ---------------------------------------------------------------------------

## BuildMode ghost items: [type, size, position, yaw, colour, style].
static func ghost_items(bm: Node, r: Dictionary, ok_col: Color, bad_col: Color) -> Array:
	var items := []
	var w: HouseWorld = bm.world
	if r["piece"] == "move" and not r.get("moving", false):
		var col := PICK_COLOR if r["ok"] else bad_col
		if r.get("object") != null:
			var o: WorldObject = r["object"]
			var s := o.size3()
			items.append(["wall_ghost", s + Vector3(0.1, 0.08, 0.1), Vector3(o.pos.x, o.base_y(), o.pos.y), WorldObject.YAW[o.rot], col, ""])
		elif r.has("furniture") and w.furniture != null and w.furniture.pieces.has(r["furniture"]):
			var f: Dictionary = w.furniture.pieces[r["furniture"]]["f"]
			var fr: Rect2 = f["rect"]
			items.append(["wall_ghost", Vector3(fr.size.x + 0.08, minf(float(f["height"]), 2.0) + 0.06, fr.size.y + 0.08),
				Vector3(fr.get_center().x, 0, fr.get_center().y), 0.0, col, ""])
		return items
	if r.get("pos", Vector2.INF) == Vector2.INF:
		return items
	var kind: String = r["kind"]
	var y := float(WorldObject.DEFS[kind].get("y0", 0.0)) + float(r.get("lift", 0.0))
	var size: Vector3 = r.get("size", WorldObject.DEFS[kind]["size"])
	items.append([kind, Vector3(size.x, maxf(size.y, 0.02), size.z), Vector3(r["pos"].x, y, r["pos"].y), WorldObject.YAW[int(r["rot"])],
		ok_col if r["ok"] else bad_col, ""])
	return items


## Palette status line for the furniture pieces and Move ("" = BuildMode's own).
static func status(bm: Node, r: Dictionary) -> String:
	if r.is_empty() or not r["ok"]:
		return ""
	if r["piece"] == "move":
		if r.has("pick"):
			return "Ready: pick up the %s." % str(r["pick"]["name"]).to_lower()
		return "Ready: set the %s down here (free)." % str(bm.carry.get("name", "piece")).to_lower()
	if float(r.get("lift", 0.0)) > 0.0:
		return "Ready: on the surface here."
	return ""


# --- lamps on surfaces ------------------------------------------------------------------

## Table lamps whose surface went (moved, destroyed) come down to the floor
## (or the next surface under them). Returns how many moved.
static func settle_lamps(w: HouseWorld) -> int:
	var n := 0
	for o in w.objects:
		if o.kind != "table_lamp" or o.lift <= 0.0:
			continue
		var h := surface_at(w, o.pos, o)
		if absf(h - o.lift) > 0.01:
			o.set_lift(h)
			n += 1
	return n
