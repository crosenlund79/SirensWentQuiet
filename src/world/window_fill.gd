class_name WindowFill
extends RefCounted
## Exp 006 (B): "Remove window" (the user's §8). A tool in build mode (slot
## 9 Demolish's variant; category "tools"): aim at a window and its whole
## opening (the glazed 1 m sections next to each other on that line, at most
## MAX_SPAN) becomes solid wall.
##
## The new wall copies the house's own wall build from a plain section of the
## same wall line (the nearest one without glass, doors, plating or the
## player's walls), voxel column by voxel column with the 0.5 m stud rhythm:
## siding and trim outside, framing, insulation, gypsum inside on the ground
## floor; siding and gypsum upstairs. Window frames, glass, casings and sills
## go. Design and current grid both change, so the section is simply a wall:
## it blocks movement and sight, takes blows and blasts, repairs (B 7) to the
## new design, takes iron plating (B 8), can be demolished, carries load in
## HouseSupport (more voxels than the window had) and stops counting as a
## window for rooms and comfort (HouseRooms.windows reads the design glass).
## It persists through the world's voxel diffs (no extra save field).
##
## Cost per metre: BuildPieces.WINDOW_FILL_COST; the frame gives back
## WINDOW_FRAME_SALVAGE per metre (glass breaks). Window boards must come
## down first (Demolish refunds them).

const MAX_SPAN := 3
const REACH := 8                       ## metres along the line searched for a plain reference section
const PERIOD := 5                      ## voxels: the studs' 0.5 m rhythm
const ACROSS := 0.26                   ## m either side of the line (wall, casings and sills)


static func handles(id: String) -> bool:
	return id == "remove_window"


## True if segment s of world w is part of a window (glass in its design core).
static func is_window(w: HouseWorld, s: Vector3i) -> bool:
	if w == null or not w.sections.has(s):
		return false
	var r := HouseWorld.seg_rect(s, 0.2, -0.1)
	var b := w._box_of(w.design, r, VoxelHouse.BASE_ROW, VoxelHouse.TOP_ROW)
	for y in range(b[0].y, b[1].y):
		for z in range(b[0].z, b[1].z):
			for x in range(b[0].x, b[1].x):
				if w.design.mat[w.design.idx(x, y, z)] == VoxelMat.GLASS:
					return true
	return false


## The window's 1 m sections around segment s, sorted along the line ([] = no window).
static func window_segments(w: HouseWorld, s: Vector3i) -> Array:
	if not is_window(w, s):
		return []
	var out := [s]
	for dir in [-1, 1]:
		var k: int = s.z + dir
		while out.size() < MAX_SPAN and is_window(w, Vector3i(s.x, s.y, k)):
			out.append(Vector3i(s.x, s.y, k))
			k += dir
	out.sort_custom(func(a, b): return a.z < b.z)
	return out


## A plain section on the same line to copy (nearest first), or Vector3i(-1, 0, 0).
static func reference_section(w: HouseWorld, segs: Array) -> Vector3i:
	var first: Vector3i = segs[0]
	var last: Vector3i = segs[segs.size() - 1]
	for d in range(1, REACH + 1):
		for k in [first.z - d, last.z + d]:
			var c := Vector3i(first.x, first.y, k)
			if not w.sections.has(c) or w.built.has(c) or w.upgraded.has(c) or is_window(w, c):
				continue
			var info := w.section_info(c)
			if info["coverage"] >= 0.95 and info["objects"].is_empty():
				return c
	return Vector3i(-1, 0, 0)


## Why the window at segment s can't be walled up ("" = it can).
static func block_reason(w: HouseWorld, segs: Array) -> String:
	if segs.is_empty():
		return "Aim at a window."
	for s in segs:
		for o in w.objects_in(HouseWorld.seg_rect(s, 0.3)):
			if (o as WorldObject).kind == "boards":
				return "Take the window boards down first (Demolish refunds them)."
		if w.bodies_in(HouseWorld.seg_rect(s, 0.2)):
			return "Someone is standing there."
	if reference_section(w, segs).x < 0:
		return "No plain wall on this line to match."
	return ""


## Fills the window's sections with the reference section's wall build
## (design and current grid). Returns the voxels changed.
static func fill(w: HouseWorld, segs: Array) -> int:
	var ref := reference_section(w, segs)
	if ref.x < 0 or segs.is_empty():
		return 0
	var first: Vector3i = segs[0]
	var last: Vector3i = segs[segs.size() - 1]
	var horiz := first.x == 0
	var span := Rect2(first.z - 0.1, first.y - ACROSS, (last.z + 1 - first.z) + 0.2, 2.0 * ACROSS) if horiz \
		else Rect2(first.y - ACROSS, first.z - 0.1, 2.0 * ACROSS, (last.z + 1 - first.z) + 0.2)
	var b := w._box_of(w.design, span, VoxelHouse.BASE_ROW, VoxelHouse.TOP_ROW)
	var a0: int = b[0].x if horiz else b[0].z
	var a1: int = b[1].x if horiz else b[1].z
	var t0: int = b[0].z if horiz else b[0].x
	var t1: int = b[1].z if horiz else b[1].x
	# the reference: PERIOD voxels in the middle of the plain section, in phase with the target
	var rc := HouseWorld.seg_center(ref)
	var rv := w.design.cell_of(Vector3(rc.x, w.design.origin.y + 1.0, rc.y))
	var r_lo: int = (rv.x if horiz else rv.z) - 2
	var d := w.design
	var g := w.grid
	var n := 0
	for y in range(b[0].y, b[1].y):
		for a in range(a0, a1):
			var ar := r_lo + posmod(a - r_lo, PERIOD)
			for t in range(t0, t1):
				var x := a if horiz else t
				var z := t if horiz else a
				var rx := ar if horiz else t
				var rz := t if horiz else ar
				var ri := d.idx(rx, y, rz)
				var i := d.idx(x, y, z)
				var rm := d.mat[ri]
				var m := d.mat[i]
				if VoxelMat.is_struct(rm) or rm == VoxelMat.BASEBOARD:
					if m != rm or d.col[i] != d.col[ri] or d.pcol[i] != d.pcol[ri] or d.pmask[i] != d.pmask[ri]:
						d.set_voxel(x, y, z, rm, d.col[ri], d.pcol[ri], d.pmask[ri])
						n += 1
					if g.mat[i] != rm or g.col[i] != d.col[ri]:
						g.set_voxel(x, y, z, rm, d.col[ri], d.pcol[ri], d.pmask[ri])
				elif m == VoxelMat.GLASS or m == VoxelMat.FRAME or m == VoxelMat.SILL or m == VoxelMat.TRIM:
					d.clear_index(i)
					if g.mat[i] != 0:
						g.clear_index(i)
					n += 1
	w._edited(b[0], b[1])
	return n


# --- build mode ------------------------------------------------------------------------

## BuildMode.evaluate for "remove_window": fills r["segs"], "cost", "refund".
static func evaluate(bm: Node, r: Dictionary, p: Vector2) -> void:
	var w: HouseWorld = bm.world
	var s := HouseWorld.nearest_seg(p)
	var segs := window_segments(w, s)
	r["segs"] = segs if not segs.is_empty() else [s]
	r["window_fill"] = true
	if segs.is_empty():
		r["reason"] = "Aim at a window."
		return
	r["cost"] = BuildPieces.times(BuildPieces.WINDOW_FILL_COST, segs.size())
	r["refund"] = BuildPieces.times(BuildPieces.WINDOW_FRAME_SALVAGE, segs.size())
	r["reason"] = block_reason(w, segs)


## BuildMode.apply for "remove_window" (costs already paid). Returns the message.
static func apply(bm: Node, r: Dictionary) -> String:
	var w: HouseWorld = bm.world
	var segs: Array = r["segs"]
	fill(w, segs)
	var at := HouseWorld.seg_center(segs[0])
	Sfx.play("build/demolish", Vector3(at.x, bm.plane_y + 1.4, at.y))
	Sfx.play("build/hammer", Vector3(at.x, bm.plane_y + 1.2, at.y))
	var text := "Window walled up (%d m, %s)." % [segs.size(), BuildPieces.cost_text(r["cost"])]
	return text + bm.call("_give_back", r.get("refund", {}))


## Ghost boxes over the window's sections.
static func ghost_items(bm: Node, r: Dictionary, ok_col: Color, bad_col: Color) -> Array:
	var out := []
	for s in r.get("segs", []):
		var c := HouseWorld.seg_center(s)
		out.append(["wall_ghost", Vector3(1.04, 2.66, 0.46), Vector3(c.x, 0, c.y), 0.0 if s.x == 0 else PI * 0.5,
			ok_col if r["ok"] else bad_col, ""])
	return out


static func status(r: Dictionary) -> String:
	if r.is_empty() or not r.get("ok", false):
		return ""
	return "Ready: walls up this %d m window (pay %s, the frame gives back %s)." % [r["segs"].size(),
		BuildPieces.cost_text(r["cost"]), BuildPieces.cost_text(r.get("refund", {}))]
