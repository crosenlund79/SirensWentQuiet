class_name HoleRules
extends RefCounted
## Exp 007 (O): observation holes, the rules (pure data on a HouseWorld; no
## nodes). The game helper is src/holes/game_holes.gd.
##
##   where     a wooden wall section (the house's own timber-frame walls and
##             player-built wood walls), a wooden door, a barricade or window
##             boards. Not stone or mortar, not iron-plated sections, not
##             iron or metal doors and barricades, not glass, not earth.
##   wall      a 0.1 m wide, 0.2 m high tunnel (1 x 2 voxels) straight through
##             the wall at eye height (1.4-1.6 m above the storey's floor),
##             carved out of the current grid only: the design still has the
##             wall, so the Repair tool (design -> current) fills it, and the
##             world save's voxel diff carries the geometry.
##   object    a door, barricade or boards: a hole flag recorded by position;
##             drilling costs the object 1 HP, and a full repair (HP back to
##             the maximum) or reinforcing it closes the hole.
##   record    {"type": "wall", "seg": [axis, line, start], "a": plan
##             coordinate along the line, "h": height above the floor} or
##             {"type": "object", "kind", "x", "y", "side": metres from the
##             centre along it, "h"}. Saved in the world save as "holes"
##             (HouseWorld and LevelWorld, optional).
##   open      a wall hole exists while its section exists, the design has
##             wall there and the hole's voxels are still missing; an object
##             hole while its object is there, wooden, and not fully repaired.

const EYE_HEIGHT := 1.5            ## m above the storey's floor (walls, doors, boards)
const BARRICADE_HEIGHT := 1.1      ## a barricade is 1.5 m high
const ROWS := [VoxelHouse.BASE_ROW + 14, VoxelHouse.BASE_ROW + 15]   ## 1.4-1.6 m: the hole's two voxel rows
const ACROSS := 0.24               ## m either side of the wall line that the tunnel goes through
const MARGIN := 0.15               ## m kept from a section's ends (corners, jambs)
const OBJECT_KINDS := ["door", "barricade", "boards"]
const OBJECT_SIDE := 0.3           ## m from a door's centre to its peephole (E at the centre still opens the door)
const MINUTES := {"wall": 4.0, "door": 3.0, "barricade": 2.0, "boards": 2.0}   ## game minutes of drilling
const NOISE_LEVEL := 2.0           ## "moderate" on agent N's noise scale
const COVER_COSTS := [{"wood": 1}, {"nails": 2}]   ## a plank, or two nails and a wad of something
const SAME_SPOT := 0.3             ## m: two holes closer than this on one wall are the same hole
const MAX_PER_WORLD := 64
## Wall voxels the drill goes through (everything else in the tunnel stops it).
const SOFT := [VoxelMat.SIDING, VoxelMat.STUD, VoxelMat.INSULATION, VoxelMat.DRYWALL, VoxelMat.WALL_TILE, VoxelMat.TRIM]
const SKIP := [VoxelMat.AIR, VoxelMat.SILL, VoxelMat.BASEBOARD]


static func seg_of(rec: Dictionary) -> Vector3i:
	var s: Array = rec.get("seg", [0, 0, 0])
	return Vector3i(int(s[0]), int(s[1]), int(s[2]))


static func is_wall(rec: Dictionary) -> bool:
	return str(rec.get("type", "")) == "wall"


## The storey's floor height of a world (0 for the ground floor's HouseWorld).
static func floor_y(w: HouseWorld) -> float:
	var b: Variant = w.get("base_y")
	return float(b) if typeof(b) in [TYPE_FLOAT, TYPE_INT] else 0.0


## Unit plan vector along a section's line (axis 0: along x; axis 1: along plan y).
static func along_dir(axis: int) -> Vector2:
	return Vector2(1, 0) if axis == 0 else Vector2(0, 1)


## Unit plan normal of a section's line.
static func normal_of(axis: int) -> Vector2:
	return Vector2(0, 1) if axis == 0 else Vector2(1, 0)


## The object a record belongs to, or null.
static func object_of(w: HouseWorld, rec: Dictionary) -> WorldObject:
	if is_wall(rec):
		return null
	var p := Vector2(float(rec.get("x", 0.0)), float(rec.get("y", 0.0)))
	for o in w.objects:
		if is_instance_valid(o) and o.kind == str(rec.get("kind", "")) and o.pos.distance_to(p) < 0.05:
			return o
	return null


## Plan point of the hole (on the wall line or on the object).
static func plan_point(w: HouseWorld, rec: Dictionary) -> Vector2:
	if is_wall(rec):
		var s := seg_of(rec)
		var a := float(rec.get("a", s.z + 0.5))
		return Vector2(a, s.y) if s.x == 0 else Vector2(s.y, a)
	var o := object_of(w, rec)
	var p := Vector2(float(rec.get("x", 0.0)), float(rec.get("y", 0.0)))
	var axis := o.seg.x if o != null else 0
	return p + along_dir(axis) * float(rec.get("side", 0.0))


## World position of the hole's centre.
static func point(w: HouseWorld, rec: Dictionary) -> Vector3:
	var p := plan_point(w, rec)
	return Vector3(p.x, floor_y(w) + float(rec.get("h", EYE_HEIGHT)), p.y)


## Plan normal through the hole (either way).
static func normal(w: HouseWorld, rec: Dictionary) -> Vector2:
	if is_wall(rec):
		return normal_of(seg_of(rec).x)
	var o := object_of(w, rec)
	return normal_of(o.seg.x) if o != null else Vector2(0, 1)


## Grid indices of a wall hole's tunnel (both rows, every cell across the wall).
static func wall_cells(w: HouseWorld, rec: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	var g := w.grid
	if g == null:
		return out
	var s := seg_of(rec)
	var horiz := s.x == 0
	var a := float(rec.get("a", s.z + 0.5))
	var line := float(s.y)
	var c := g.cell_of(Vector3(a, 0.0, line) if horiz else Vector3(line, 0.0, a))
	var ai := c.x if horiz else c.z
	var tr := g.centre_range(2 if horiz else 0, line - ACROSS, line + ACROSS)
	for r in ROWS:
		for t in range(tr.x, tr.y):
			var x := ai if horiz else t
			var z := t if horiz else ai
			if x < 0 or z < 0 or x >= g.sx or z >= g.sz or r >= g.sy:
				continue
			out.append(g.idx(x, r, z))
	return out


## "" if a hole can be drilled into section s of world w at plan coordinate
## `along`, else the reason (shown to the player).
static func wall_reason(w: HouseWorld, s: Vector3i, along: float) -> String:
	if not w.sections.has(s):
		return "There's no wall there to drill."
	if w.upgraded.has(s):
		return "The iron plating stops the drill."
	if str(w.sections[s].get("material", "")) == "stone":
		return "Stone: far too hard for a hand drill."
	var rec := {"type": "wall", "seg": [s.x, s.y, s.z], "a": along, "h": EYE_HEIGHT}
	var cells := wall_cells(w, rec)
	var design_wall := 0
	var current_wall := 0
	for i in cells:
		var m := w.design.mat[i]
		if m == VoxelMat.GLASS or m == VoxelMat.FRAME:
			return "That's a window: you can already see out."
		if m == VoxelMat.MASONRY or m == VoxelMat.MORTAR:
			return "Stone: far too hard for a hand drill."
		if m == VoxelMat.METAL_SHEET:
			return "The iron plating stops the drill."
		if m == VoxelMat.EARTH:
			return "That's solid earth."
		if not (m in SKIP) and not (m in SOFT) and VoxelMat.is_struct(m):
			return "The drill won't go through that."
		if m in SOFT:
			design_wall += 1
		if VoxelMat.is_struct(w.grid.mat[i]):
			current_wall += 1
	if design_wall == 0:
		return "There's no wall there to drill (a doorway or a gap)."
	if current_wall == 0:
		return "It's already open there."
	for h in holes_of(w):
		if is_wall(h) and seg_of(h) == s and absf(float(h.get("a", 0.0)) - along) < SAME_SPOT:
			return "There's already a hole here."
	return ""


## "" if object o can get a peephole, else the reason.
static func object_reason(w: HouseWorld, o: WorldObject) -> String:
	if o == null or not (o.kind in OBJECT_KINDS):
		return "The drill is for walls, doors, barricades and window boards."
	if o.mat != "wood":
		return "The drill won't bite into %s." % ("iron" if o.mat == "iron" else "a metal door")
	if o.kind == "door" and o.open:
		return "Close the door first."
	if o.hp <= 1:
		return "It's too badly damaged to drill."
	for h in holes_of(w):
		if not is_wall(h) and object_of(w, h) == o:
			return "There's already a peephole in it."
	return ""


static func object_height(kind: String) -> float:
	return BARRICADE_HEIGHT if kind == "barricade" else EYE_HEIGHT


static func object_record(o: WorldObject, side_sign: float) -> Dictionary:
	return {"type": "object", "kind": o.kind, "x": o.pos.x, "y": o.pos.y,
		"side": OBJECT_SIDE * (1.0 if side_sign >= 0.0 else -1.0) if o.kind == "door" else 0.0,
		"h": object_height(o.kind)}


static func wall_record(s: Vector3i, along: float) -> Dictionary:
	return {"type": "wall", "seg": [s.x, s.y, s.z], "a": snappedf(along, 0.05), "h": EYE_HEIGHT}


## Drill minutes for a record.
static func minutes_for(rec: Dictionary) -> float:
	return float(MINUTES.get("wall" if is_wall(rec) else str(rec.get("kind", "door")), 3.0))


## The holes recorded on a world (its `holes` array; [] for a world without one).
static func holes_of(w: HouseWorld) -> Array:
	var v: Variant = w.get("holes")
	return v if v is Array else []


## True while the hole is there (see the header).
static func is_open(w: HouseWorld, rec: Dictionary) -> bool:
	if is_wall(rec):
		var s := seg_of(rec)
		if not w.sections.has(s):
			return false
		var cells := wall_cells(w, rec)
		var designed := false
		for i in cells:
			if VoxelMat.is_struct(w.grid.mat[i]):
				return false
			if VoxelMat.is_struct(w.design.mat[i]):
				designed = true
		return designed
	var o := object_of(w, rec)
	return o != null and o.mat == "wood" and o.hp < o.max_hp


## Makes the hole (no checks). Returns the voxels removed (walls) or 1 (objects).
static func make(w: HouseWorld, rec: Dictionary) -> int:
	var n := 0
	if is_wall(rec):
		var ch := VoxelCarver.empty_change()
		for i in wall_cells(w, rec):
			var m := w.grid.mat[i]
			if m != VoxelMat.AIR and not (m in [VoxelMat.MASONRY, VoxelMat.MORTAR, VoxelMat.METAL_SHEET, VoxelMat.EARTH, VoxelMat.FOUNDATION]):
				VoxelCarver._remove(w.grid, i, ch)
				n += 1
		if n > 0:
			w._apply_damage(ch)
	else:
		var o := object_of(w, rec)
		if o == null:
			return 0
		o.set_hp(o.hp - 1)          # a hole weakens it a little; a full repair closes it
		n = 1
	var list := holes_of(w)
	if list.size() < MAX_PER_WORLD:
		list.append(rec)
	return n


## Fills a wall hole from the design (covering it). Returns the voxels put back.
static func fill(w: HouseWorld, rec: Dictionary) -> int:
	var n := 0
	if is_wall(rec):
		var lo := Vector3i(1 << 20, 1 << 20, 1 << 20)
		var hi := -lo
		for i in wall_cells(w, rec):
			var m := w.design.mat[i]
			if m == VoxelMat.AIR or w.grid.mat[i] == m:
				continue
			var c := w.grid.coords(i)
			w.grid.set_voxel(c.x, c.y, c.z, m, w.design.col[i], w.design.pcol[i], w.design.pmask[i])
			lo = lo.min(c)
			hi = hi.max(c + Vector3i.ONE)
			n += 1
		if n > 0:
			w._edited(lo, hi)
	holes_of(w).erase(rec)
	return n


## Drops the records that are no longer open. Returns how many went.
static func prune(w: HouseWorld) -> int:
	var list := holes_of(w)
	var gone := 0
	for k in range(list.size() - 1, -1, -1):
		if not (list[k] is Dictionary) or not is_open(w, list[k]):
			list.remove_at(k)
			gone += 1
	return gone


## Saved records from untrusted data: malformed entries are dropped.
static func clean(v: Variant) -> Array:
	var out := []
	if not (v is Array):
		return out
	for e in v:
		if not (e is Dictionary) or out.size() >= MAX_PER_WORLD:
			continue
		var h: Variant = e.get("h", EYE_HEIGHT)
		if typeof(h) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(h)) or float(h) < 0.2 or float(h) > 2.5:
			continue
		if str(e.get("type", "")) == "wall":
			var s: Variant = e.get("seg")
			var a: Variant = e.get("a")
			if not (s is Array) or (s as Array).size() != 3 or typeof(a) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(a)):
				continue
			var good := true
			for x in s:
				if typeof(x) not in [TYPE_INT, TYPE_FLOAT] or absf(float(x)) > 100.0:
					good = false
			if not good or int(s[0]) not in [0, 1] or absf(float(a)) > 100.0:
				continue
			out.append({"type": "wall", "seg": [int(s[0]), int(s[1]), int(s[2])], "a": float(a), "h": float(h)})
		elif str(e.get("type", "")) == "object":
			var k: Variant = e.get("kind")
			var x: Variant = e.get("x")
			var y: Variant = e.get("y")
			var sd: Variant = e.get("side", 0.0)
			if not (k is String) or not (k in OBJECT_KINDS) or typeof(x) not in [TYPE_INT, TYPE_FLOAT] or typeof(y) not in [TYPE_INT, TYPE_FLOAT]:
				continue
			if not is_finite(float(x)) or not is_finite(float(y)) or absf(float(x)) > 100.0 or absf(float(y)) > 100.0:
				continue
			out.append({"type": "object", "kind": k, "x": float(x), "y": float(y),
				"side": clampf(float(sd), -0.45, 0.45) if typeof(sd) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(sd)) else 0.0, "h": float(h)})
	return out


## A short description ("wall at 3.4 m on line y = 9", "door at (4.5, 9.0)").
static func describe(w: HouseWorld, rec: Dictionary) -> String:
	var p := plan_point(w, rec)
	if is_wall(rec):
		var s := seg_of(rec)
		var mat := str(w.sections.get(s, {}).get("material", "?"))
		return "%s wall (%d,%d,%d) at (%.1f, %.1f)" % ["house" if mat == "frame" else mat, s.x, s.y, s.z, p.x, p.y]
	return "%s at (%.1f, %.1f)" % [WorldObject.name_of(str(rec.get("kind", "door"))).to_lower(), p.x, p.y]
