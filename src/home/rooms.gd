class_name HouseRooms
extends RefCounted
## Experiment 005 (C): the rooms of one storey, found by flood fill over the
## storey world's navigation cells (GridNav, 0.25 m).
##
## Cell classes:
##   BARRIER - structural voxels between the nav rows (walls, the wall under a
##             window, earth in a basement), a door leaf (open or closed),
##             barricades, window boards, and every doorway in a standing wall
##             (both jambs present). Doors and doorways bound a room whatever
##             their state, so opening a door never changes the rooms.
##             Exception: an exterior doorway without a door leaf is open.
##   FLOOR   - inside the storey's floor: the house footprint and the stone
##             foundations on the ground floor; the footprint with a floor
##             upstairs; dug cells in a basement. Furniture, stairs and the
##             fireplace stand on FLOOR cells (they are inside rooms).
##   OUTSIDE - the lot (ground floor) or open air (upper storeys).
##   HOLE    - no floor inside the footprint upstairs (a stairwell): neither
##             room nor outside.
## A room is a 4-connected region of FLOOR cells of at least MIN_CELLS. A room
## touching OUTSIDE is `exposed` (a missing wall, a hole, an open doorway). A
## broken window is found separately (windows(); the wall under it still
## bounds the room). Basements are bounded by earth and never exposed.
## Recomputed on events only (game_comfort.gd); a storey takes a few ms.

enum { FLOOR, BARRIER, OUTSIDE, HOLE }

const MIN_CELLS := 16                ## 1 m²: smaller pockets (between walls) aren't rooms
const CELL := 0.25                   ## GridNav.CELL
const MARGIN := 1.0                  ## scan this far around the floor
const BLOCKING_OBJECTS := ["door", "barricade", "boards"]
const WINDOW_INSIDE := 0.5           ## m from a window's centre line to its room sample point


## The rooms of `world` (storey `storey`):
## {"storey", "origin": Vector2i (first cell), "w", "h", "room_of": PackedInt32Array
##  (room index per cell, -1 none), "rooms": [room]}. A room is
## {"index", "storey", "cells", "area", "bbox": Rect2, "centre": Vector2,
##  "exposed": bool, "exposed_at": Vector2, "neighbours": [index],
##  "sections": [Vector3i] (bounding wall segments), "points": PackedVector2Array}.
static func find(world: HouseWorld, storey: int) -> Dictionary:
	var out := {"storey": storey, "origin": Vector2i.ZERO, "w": 0, "h": 0, "room_of": PackedInt32Array(), "rooms": []}
	if world == null or world.nav == null:
		return out
	var nav: GridNav = world.nav
	var masks := floor_rects(world, storey)
	var scan := Rect2()
	for i in masks.size():
		scan = masks[i] if i == 0 else scan.merge(masks[i])
	scan = scan.grow(MARGIN)
	var a := nav.cell_of(scan.position).max(Vector2i.ZERO)
	var b := nav.cell_of(scan.end).min(nav.size - Vector2i.ONE)
	var w := b.x - a.x + 1
	var h := b.y - a.y + 1
	if w <= 0 or h <= 0:
		return out
	out["origin"] = a
	out["w"] = w
	out["h"] = h
	var is_level := world is LevelWorld
	var below := storey < 0
	var doorways := _doorway_cells(world, masks, is_level and below)
	var kind := PackedByteArray()
	kind.resize(w * h)
	for j in h:
		for i in w:
			kind[j * w + i] = _classify(world, nav, a + Vector2i(i, j), masks, is_level, below, doorways)
	var room_of := PackedInt32Array()
	room_of.resize(w * h)
	room_of.fill(-1)
	var rooms := []
	var touch := {}                  # barrier cell index -> {room: true}
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for start in w * h:
		if kind[start] != FLOOR or room_of[start] != -1:
			continue
		var idx := rooms.size()
		var queue := PackedInt32Array([start])
		room_of[start] = idx
		var k := 0
		var exposed := false
		var exposed_at := Vector2.INF
		var lo := Vector2i(w, h)
		var hi := Vector2i(-1, -1)
		var sum := Vector2.ZERO
		var barriers := {}
		while k < queue.size():
			var ci := queue[k]
			k += 1
			var c := Vector2i(ci % w, ci / w)
			lo = lo.min(c)
			hi = hi.max(c)
			sum += nav.center_of(a + c)
			for d in dirs:
				var n: Vector2i = c + d
				if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
					if not below:
						exposed = true
						exposed_at = nav.center_of(a + c)
					continue
				var ni := n.y * w + n.x
				var kn := kind[ni]
				if kn == FLOOR:
					if room_of[ni] == -1:
						room_of[ni] = idx
						queue.append(ni)
				elif kn == OUTSIDE:
					exposed = true
					if exposed_at == Vector2.INF:
						exposed_at = nav.center_of(a + n)
				elif kn == BARRIER:
					barriers[ni] = true
		if queue.size() < MIN_CELLS:
			for ci in queue:
				room_of[ci] = -2       # a pocket: not a room
			continue
		var p0 := nav.center_of(a + lo) - Vector2.ONE * CELL * 0.5
		var p1 := nav.center_of(a + hi) + Vector2.ONE * CELL * 0.5
		var pts := PackedVector2Array()
		for ci in queue:
			pts.append(nav.center_of(a + Vector2i(ci % w, ci / w)))
		var secs := {}
		for bi in barriers:
			if not touch.has(bi):
				touch[bi] = {}
			touch[bi][idx] = true
			var s := HouseWorld.nearest_seg(nav.center_of(a + Vector2i(bi % w, bi / w)))
			if world.sections.has(s):
				secs[s] = true
		rooms.append({"index": idx, "storey": storey, "cells": queue.size(), "area": queue.size() * CELL * CELL,
			"bbox": Rect2(p0, p1 - p0), "centre": sum / float(queue.size()), "exposed": exposed, "exposed_at": exposed_at,
			"neighbours": [], "sections": secs.keys(), "points": pts})
	for ci in w * h:
		if room_of[ci] == -2:
			room_of[ci] = -1
	# neighbours: rooms touching the same barrier cell, or barrier cells next to each other
	var pairs := {}
	for bi in touch:
		var group: Dictionary = touch[bi].duplicate()
		var c := Vector2i(bi % w, bi / w)
		for d in dirs:
			var n: Vector2i = c + d
			var ni := n.y * w + n.x
			if n.x >= 0 and n.y >= 0 and n.x < w and n.y < h and touch.has(ni):
				group.merge(touch[ni])
		var ids := group.keys()
		for x in ids:
			for y in ids:
				if x != y:
					pairs[Vector2i(x, y)] = true
	for p in pairs:
		var r: Dictionary = rooms[p.x]
		if not p.y in r["neighbours"]:
			r["neighbours"].append(p.y)
	out["room_of"] = room_of
	out["rooms"] = rooms
	return out


## The plan rects that have a floor on this storey (the cells that can be rooms).
static func floor_rects(world: HouseWorld, storey: int) -> Array:
	var out := [HousePlan.FOOTPRINT]
	if storey == 0 and not world is LevelWorld and world.has_method("_foundation_rects"):
		out.append_array(world.call("_foundation_rects"))
	return out


static func _in_rects(p: Vector2, rects: Array) -> bool:
	for r in rects:
		if (r as Rect2).has_point(p):
			return true
	return false


static func _classify(world: HouseWorld, nav: GridNav, c: Vector2i, masks: Array, is_level: bool, below: bool, doorways: Dictionary) -> int:
	if not nav.in_grid(c):
		return BARRIER if below else OUTSIDE
	var o = world._obj_cells.get(c)
	if o != null and is_instance_valid(o) and (o as WorldObject).kind in BLOCKING_OBJECTS:
		return BARRIER
	if doorways.has(c):
		return BARRIER
	var p := nav.center_of(c)
	if nav.get_raw(c) != GridNav.OPEN and world._cell_has_struct(c):
		return BARRIER
	var inside := _in_rects(p, masks)
	if not is_level:
		return FLOOR if inside else OUTSIDE
	if below:
		if not inside:
			return BARRIER             # earth around the basement
		return FLOOR
	if not inside:
		return OUTSIDE
	if world.has_method("has_floor_at") and not bool(world.call("has_floor_at", p)):
		return HOLE
	return FLOOR


## Nav cells of the doorways that bound rooms: door-like gaps (world.openings)
## whose two jambs still stand. An exterior doorway (one side outside the
## floor) without a door leaf is left open: it exposes the room.
static func _doorway_cells(world: HouseWorld, masks: Array, basement: bool) -> Dictionary:
	var out := {}
	var nav: GridNav = world.nav
	for op in world.openings:
		var f: float = op["from"]
		var t: float = op["to"]
		var line := float(op["line"])
		var horiz: bool = int(op["axis"]) == 0
		var on_line := Rect2(f, line - 0.125, t - f, 0.25) if horiz else Rect2(line - 0.125, f, 0.25, t - f)
		var j0 := Vector2(f - CELL, line) if horiz else Vector2(line, f - CELL)
		var j1 := Vector2(t, line) if horiz else Vector2(line, t)
		if not (world._cell_has_struct(nav.cell_of(j0)) and world._cell_has_struct(nav.cell_of(j1))):
			continue                   # the wall around it is gone
		var mid := (f + t) * 0.5
		var side_a := Vector2(mid, line - 0.5) if horiz else Vector2(line - 0.5, mid)
		var side_b := Vector2(mid, line + 0.5) if horiz else Vector2(line + 0.5, mid)
		var exterior := not basement and not (_in_rects(side_a, masks) and _in_rects(side_b, masks))
		var cells := nav.cells_in_rect(on_line)
		if exterior:
			var leaf := false
			for c in cells:
				var o = world._obj_cells.get(c)
				if o != null and is_instance_valid(o) and (o as WorldObject).kind == "door":
					leaf = true
			if not leaf:
				continue
		for c in cells:
			out[c] = true
	return out


## Room index at plan point p (-1 outside every room). Looks up to `reach`
## cells around p when p itself is on a wall or furniture-free pocket.
static func room_index_at(map: Dictionary, nav: GridNav, p: Vector2, reach := 2) -> int:
	if map.is_empty() or int(map.get("w", 0)) <= 0 or nav == null:
		return -1
	var a: Vector2i = map["origin"]
	var w: int = map["w"]
	var h: int = map["h"]
	var room_of: PackedInt32Array = map["room_of"]
	var c := nav.cell_of(p) - a
	var best := -1
	var best_d := INF
	for dj in range(-reach, reach + 1):
		for di in range(-reach, reach + 1):
			var n := c + Vector2i(di, dj)
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
				continue
			var r := room_of[n.y * w + n.x]
			if r < 0:
				continue
			var d := float(di * di + dj * dj)
			if d < best_d:
				best_d = d
				best = r
	return best


# --- windows -----------------------------------------------------------------------------

## The windows of a storey: [{"rect": Rect2, "centre", "inside": Vector2 (a point in
## its room), "state": "intact" | "broken" | "boarded"}]. Ground floor:
## HousePlan.OPENINGS; upper storeys: LevelWorld.UPPER_WINDOWS; basements have
## none. A window whose glass was built over or demolished is not listed.
static func windows(world: HouseWorld, storey: int) -> Array:
	var out := []
	if world == null or storey < 0:
		return out
	var defs := []
	var mid := HousePlan.FOOTPRINT.get_center()
	if world is LevelWorld:
		for s in LevelWorld.UPPER_WINDOWS:
			defs.append({"rect": HouseWorld.seg_rect(s, 0.2), "centre": HouseWorld.seg_center(s), "horiz": s.x == 0})
	else:
		for o in HousePlan.OPENINGS:
			if o["kind"] != "window":
				continue
			var wall := HousePlan.wall_by_id(o["wall"])
			var r := HousePlan.span_rect(wall, o["from"], o["to"])
			defs.append({"rect": r.grow_individual(0, 0.05, 0, 0.05) if HousePlan.is_horizontal(wall) else r.grow_individual(0.05, 0, 0.05, 0),
				"centre": r.get_center(), "horiz": HousePlan.is_horizontal(wall)})
	for d in defs:
		var r: Rect2 = d["rect"]
		var design_n := _glass(world.design, r)
		if design_n == 0:
			continue
		var now_n := _glass(world.grid, r)
		var c: Vector2 = d["centre"]
		var inward := Vector2(0, signf(mid.y - c.y)) if d["horiz"] else Vector2(signf(mid.x - c.x), 0)
		var state := "intact" if now_n >= design_n * 0.6 else "broken"
		for o in world.objects_in(r.grow(0.15)):
			if (o as WorldObject).kind == "boards":
				state = "boarded"
		out.append({"rect": r, "centre": c, "inside": c + inward * WINDOW_INSIDE, "state": state})
	return out


static func _glass(g: VoxelGrid, r: Rect2) -> int:
	if g == null:
		return 0
	var xr := g.centre_range(0, r.position.x, r.end.x)
	var zr := g.centre_range(2, r.position.y, r.end.y)
	var n := 0
	for y in range(VoxelHouse.BASE_ROW, mini(VoxelHouse.TOP_ROW + 1, g.sy)):
		for z in range(zr.x, zr.y):
			var base := (y * g.sz + z) * g.sx
			for x in range(xr.x, xr.y):
				if g.mat[base + x] == VoxelMat.GLASS:
					n += 1
	return n
