class_name BuildMode
extends Node3D
## Construction mode (SPEC-002 §6, §7.4; SPEC-003 §4).
##
## Palette slots (BuildPieces): 1 walls (wood | stone; click-drag runs of 1 m
## segments on integer plan lines), 2 barricades (wood | iron), 3 doors (wood
## | reinforced), 4 doorway, 5 storage crate, 6 equipment (rain collector |
## workbench), 7 repair, 8 iron plating, 9 demolish, 0 stone foundation
## (runs of 1 m tiles). Pressing a slot's key again cycles its material
## variants. Experiment 004: 2 also has window boards (on a window section),
## 3 the metal door, 6 the fuse box (on a wall, only one); 8 reinforces
## doors (wood -> reinforced -> metal); 9 demolishes furniture and original
## walls, windows and doors for salvage, and the player's pieces refund in
## full. A ghost preview is green when valid, red with a reason when not.
## Costs (wood, stone, iron, nails, scrap) go through GameState.pay (the
## unlimited cheat makes them free); building needs a hammer. Every change
## keeps a way out (the exit rule). Stone walls need a foundation.
##
## Exp 005 (F): 5 is "Furniture & storage": the crate, Move and the
## furniture pieces (FurniturePlace, src/home/furniture_place.gd: placing,
## moving with `carry`, validation, ghosts); Demolish keeps the salvage of a
## moved house piece and leaves loot piles alone.
##
## Exp 006 (U): the palette is a category menu (BuildCatalog): keys 1-8 pick
## a category (its last-used piece; the same key again steps to the next
## piece), F / X / G pick Repair / Demolish / Move directly, Q goes back to
## the previous piece; `recent` lists the last pieces picked.
##
## Input while active (handles_input() is true, so the game doesn't fire):
## LMB place / apply (drag for runs), RMB (`secondary`) cancels a drag,
## `build_rotate` (R) rotates, number keys select. Esc is the game's: it
## calls set_active(false). evaluate() / apply() take plan points directly
## (tests, scripted scenarios).

signal message(text: String, ok: bool)
signal changed

const RUN_MAX := 12
const GHOST_OK := Color(0.35, 1.0, 0.5, 0.36)
const GHOST_BAD := Color(1.0, 0.28, 0.22, 0.4)
const GHOST_TOOL := {"repair": Color(1.0, 0.72, 0.3, 0.32), "upgrade": Color(0.55, 0.75, 1.0, 0.34), "demolish": Color(1.0, 0.45, 0.25, 0.34)}
const GHOST_REPLACE := Color(0.35, 0.85, 1.0, 0.4)      ## Refinement 01: a wall segment that replaces another
const SEAL_REASON := "That would seal the last way out."
## Exp 006 (B): the foundation rules in one line (build menu status).
const FOUNDATION_HINT := "Walls on a foundation or the house floor are sturdier; outside the house only founded walls prop the roof; a third level needs a stone footing along the house."
const FOUNDATION_REASON := "Stone walls need a foundation: the house floor or a stone foundation (a timber footing is too weak)."
## Pieces placed by dragging along a line, and pieces that follow the ground
## point under the mouse (the rest follow the aimed surface).
const RUN_PIECES := ["wall", "stone_wall", "barricade", "iron_barricade", "foundation", "timber_footing"]   # Exp 006 (B): + timber footing
const FREE_PIECES := ["crate", "rain_collector", "workbench", "motion_sensor", "turret_mount"]   # Exp 007 (S): + security

var active := false
var world: HouseWorld
var state: GameState
var camera: Camera3D
var player: Node3D
var piece := 0                  ## index in BuildPieces.LIST
var rot := 0                    ## quarter turns for crates and collectors
var palette: BuildPalette
var last_eval := {}
## Scripted pointer (plan metres) for previews and screenshots; INF = the mouse.
var debug_pointer := Vector2.INF
var debug_drag_from := Vector2.INF
## Experiment 004 storeys (owner L, src/levels/level_build.gd): an optional
## extension (uses_plane, post_evaluate, apply, ghost_items) and the floor
## height of the storey being built on (the game's level helper sets both and
## swaps `world` to that storey's HouseWorld).
var ext: Object = null
var plane_y := 0.0

var _dragging := false
var _drag_from := Vector2.INF
var _ghost_root: Node3D
var _ghosts: Array[Node3D] = []
var _ghost_key := ""
var _eval_key := ""
var _eval_age := 0.0
var _mats := {}
var _slot_pick := {}            # menu category -> LIST index last used in it
## Exp 006 (U): ids of the last pieces picked, newest first (the menu's Recent row).
var recent: Array[String] = []
var _ptr_furniture := ""        # furniture piece under the demolish pointer (aim ray)
var _ghost_label: Label3D       # Refinement 01: "Replace wood → stone" over a replacing ghost
## Exp 005 (F): the furniture piece the Move tool holds ({} = none): {"world",
## "object" | null, "piece" (house piece id), "kind", "size", "rot", "name"}.
var carry := {}
## Exp 006 (B): the house supply (HouseSupply: the pool plus the house's
## storage furniture; the game's balance helper sets it). null = the pool only.
var supply: Object = null


func setup(w: HouseWorld, s: GameState, cam: Camera3D, p: Node3D) -> void:
	world = w
	state = s
	camera = cam
	player = p
	if state != null and not state.changed.is_connected(_on_state_changed):
		state.changed.connect(_on_state_changed)


func _on_state_changed() -> void:
	_eval_key = ""


func _ready() -> void:
	_ghost_root = Node3D.new()
	_ghost_root.name = "Ghosts"
	add_child(_ghost_root)
	palette = BuildPalette.new()
	palette.visible = false
	palette.build = self                                    # Exp 006 (U): the menu reads costs, locks, level
	palette.slot_pressed.connect(select_slot)
	palette.category_pressed.connect(select_category)       # Exp 006 (U)
	palette.variant_pressed.connect(select)
	add_child(palette)


## Shows and hides the palette. Without a hammer (and no unlimited cheat) it
## refuses with a message.
func set_active(on: bool) -> void:
	if on == active:
		return
	if on and not _has_hammer():
		message.emit("You need a hammer to build.", false)
		Sfx.play("build/invalid")
		return
	active = on
	_dragging = false
	_eval_key = ""
	carry = {}          # Exp 005 (F): leaving puts a carried piece back
	if palette != null:
		palette.visible = on
	if _ghost_root != null:
		_ghost_root.visible = on
	Sfx.ui("ui/open" if on else "ui/close")
	changed.emit()


func handles_input() -> bool:
	return active


func select(i: int) -> void:
	if i < 0 or i >= BuildPieces.LIST.size():
		return
	piece = i
	_slot_pick[BuildPieces.slot_of(i)] = i
	_note_recent(BuildPieces.LIST[i]["id"])     # Exp 006 (U)
	_dragging = false
	carry = {}          # Exp 005 (F)
	_eval_key = ""
	_ghost_key = ""
	Sfx.ui("ui/click")
	changed.emit()


func select_id(id: String) -> void:
	select(BuildPieces.index_of(id))


## A menu category (0-7; keys 1-8; Exp 006): its last-used piece, or the next
## piece when the category is already selected.
func select_slot(slot: int) -> void:
	var v := BuildPieces.variants(slot)
	if v.is_empty():
		return
	if BuildPieces.slot_of(piece) == slot:
		select(v[(v.find(piece) + 1) % v.size()])
	else:
		select(int(_slot_pick.get(slot, v[0])))


func slot() -> int:
	return BuildPieces.slot_of(piece)


## Exp 006 (U): a category tab: its last-used piece (no stepping).
func select_category(cat: int) -> void:
	var v := BuildPieces.variants(cat)
	if v.is_empty():
		return
	if BuildPieces.slot_of(piece) != cat:
		select(int(_slot_pick.get(cat, v[0])))


## Exp 006 (U): back to the piece picked before this one (Q).
func select_previous() -> void:
	for id in recent:
		if id != piece_id() and BuildPieces.index_of(id) >= 0:
			select_id(id)
			return


func _note_recent(id: String) -> void:
	recent.erase(id)
	recent.push_front(id)
	if recent.size() > BuildCatalog.RECENT_MAX:
		recent.resize(BuildCatalog.RECENT_MAX)


func rotate_piece() -> void:
	rot = (rot + 1) % 4
	_eval_key = ""
	changed.emit()


func piece_id() -> String:
	return BuildPieces.LIST[piece]["id"]


func tool() -> String:
	return BuildPieces.LIST[piece]["tool"]


# --- input ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = (event as InputEventKey).keycode
		if k >= KEY_1 and k < KEY_1 + BuildCatalog.count():      # Exp 006 (U): 1-8 categories
			select_slot(k - KEY_1)
			get_viewport().set_input_as_handled()
			return
		for q in BuildCatalog.QUICK:                              # Exp 006 (U): F / X / G tools
			if k == int(q["keycode"]):
				select_id(str(q["id"]))
				get_viewport().set_input_as_handled()
				return
		if k == KEY_Q:                                            # Exp 006 (U): previous piece
			select_previous()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("build_rotate"):
		rotate_piece()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("secondary"):
		if _dragging:
			_dragging = false
			_eval_key = ""
			message.emit("Cancelled.", true)
		elif not carry.is_empty():          # Exp 005 (F)
			cancel_carry()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("fire"):
		var p := _pointer()
		if p != Vector2.INF:
			if _is_run_piece():
				_dragging = true
				_drag_from = p
			else:
				apply(p)
		get_viewport().set_input_as_handled()
	elif event.is_action_released("fire"):
		if _dragging:
			_dragging = false
			var p := _pointer()
			if p != Vector2.INF:
				apply(p, _drag_from)
			_eval_key = ""
		get_viewport().set_input_as_handled()


func _is_run_piece() -> bool:
	return piece_id() in RUN_PIECES or DefenseBuild.is_run(piece_id())      # Exp 006 (D): spikes, trenches


## Exp 005 (F): drops what the Move tool holds (it never left its spot).
func cancel_carry() -> void:
	if carry.is_empty():
		return
	carry = {}
	_eval_key = ""
	message.emit("Put back.", true)
	changed.emit()


## Ground point under the mouse for free placement; the aimed surface (walls,
## objects, respecting the cutaway) for doors, doorways and tools.
func _pointer() -> Vector2:
	if camera == null or not is_inside_tree() or world == null:
		return Vector2.INF
	return pointer_at(get_viewport().get_mouse_position())


## The plan point `_pointer()` picks for screen point `mp` (Refinement 01:
## split out so tests can aim through the real camera).
func pointer_at(mp: Vector2) -> Vector2:
	if camera == null or world == null:
		return Vector2.INF
	var o := camera.project_ray_origin(mp)
	var d := camera.project_ray_normal(mp)
	if piece_id() in RUN_PIECES or piece_id() in FREE_PIECES or (ext != null and ext.uses_plane(piece_id())) or FurniturePlace.uses_plane(self) \
			or DefenseBuild.uses_plane(piece_id()):      # Exp 006 (D)
		if d.y > -0.001:
			return Vector2.INF
		var g := o + d * ((plane_y - o.y) / d.y)
		return Vector2(g.x, g.z)
	var low := tool() == "demolish" or tool() == "move"      # Exp 005 (F): Move picks low furniture too
	var hit := world.aim_ray(o, d, low)
	_ptr_furniture = world.aim_furniture if low else ""
	return Vector2(hit.x, hit.z)


func _process(delta: float) -> void:
	if not active or world == null:
		return
	_eval_age += delta
	var p := _pointer() if debug_pointer == Vector2.INF else debug_pointer
	if p == Vector2.INF:
		return
	var from := _drag_from if _dragging else debug_drag_from
	var key := _target_key(p, from)
	if key != _eval_key or _eval_age > 0.3:
		_eval_key = key
		_eval_age = 0.0
		last_eval = evaluate(p, from)
		_show_ghost(last_eval)
		_refresh_palette()


func _target_key(p: Vector2, from: Vector2) -> String:
	var id := piece_id()
	if id in FREE_PIECES:
		return "%s|%s|%d" % [id, str(_snap_pos(_kind(), p, rot)), rot]
	if FurniturePlace.handles(id):          # Exp 005 (F)
		return FurniturePlace.target_key(self, p)
	if DefenseBuild.handles(id):            # Exp 006 (D)
		return DefenseBuild.target_key(self, p, from)
	var s := HouseWorld.nearest_seg(p)
	if from != Vector2.INF and from.distance_to(p) > 0.35:
		return "%s|%s" % [id, str(_run(from, p))]
	var o: WorldObject = world.object_at(p, 0.2) if tool() != "place" else null
	return "%s|%s|%s|%s" % [id, str(s), str(o.get_instance_id()) if o != null else "", _ptr_furniture]


# --- evaluation ----------------------------------------------------------------------

## What applying the current piece or tool at plan point `p` (dragged from
## `from` for runs) would do: {"ok", "reason", "cost", "segs" | "pos" | "object", ...}.
func evaluate(p: Vector2, from := Vector2.INF) -> Dictionary:
	var id := piece_id()
	var r := {"ok": false, "reason": "", "cost": {}, "piece": id, "segs": [], "pos": Vector2.INF, "object": null}
	if world == null:
		r["reason"] = "No house."
		return r
	if not _has_hammer():
		r["reason"] = "You need a hammer."
		return r
	match id:
		"wall", "stone_wall", "barricade", "iron_barricade", "foundation", "timber_footing":
			var segs := [HouseWorld.nearest_seg(p)]
			if from != Vector2.INF and from.distance_to(p) > 0.35:
				segs = _run(from, p)
			if id == "foundation" or id == "timber_footing":
				_eval_foundation(r, segs)
			else:
				_eval_run(r, id, segs)
		"door", "iron_door", "metal_door":
			_eval_door(r, HouseWorld.nearest_seg(p))
		"window_boards":
			_eval_boards(r, HouseWorld.nearest_seg(p))
		"fuse_box":
			_eval_fuse_box(r, p)
		"doorway":
			_eval_doorway(r, HouseWorld.nearest_seg(p))
		"crate", "rain_collector", "workbench", "motion_sensor", "turret_mount":      # Exp 007 (S): + security
			_eval_object(r, _kind(), _snap_pos(_kind(), p, rot))
		"repair":
			_eval_repair(r, p)
		"upgrade":
			_eval_upgrade(r, p)
		"demolish":
			_eval_demolish(r, p)
	if FurniturePlace.handles(id):      # Exp 005 (F): furniture and Move
		FurniturePlace.evaluate(self, r, p)
	if WindowFill.handles(id):          # Exp 006 (B): wall up a window
		WindowFill.evaluate(self, r, p)
	DefenseBuild.evaluate(self, r, p, from)      # Exp 006 (D): defences; nothing over a trench; bridge demolish rule
	if ext != null:      # Experiment 004 (L): the level pieces, stairs and floor tiles, level rules
		ext.post_evaluate(self, r, p, from)
	Research.gate(state, BuildPieces.LIST[piece], r)      # Exp 006 (R): locked recipes and Reinforce steps ("locked": true)
	if r["reason"] == "" and not state_can_pay(r["cost"]):
		r["reason"] = "Needs %s." % BuildPieces.cost_text(r["cost"])
	r["ok"] = r["reason"] == ""
	return r


## WorldObject kind and material of the selected piece ("" for walls and tools).
func _kind() -> String:
	return str(BuildPieces.LIST[piece].get("kind", ""))


func _mat() -> String:
	return str(BuildPieces.LIST[piece].get("mat", "wood"))


func state_can_pay(cost: Dictionary) -> bool:
	if supply != null and supply.has_method("can_pay"):      # Exp 006 (B): carried + stored in the house
		return cost.is_empty() or supply.can_pay(cost)
	return cost.is_empty() or state == null or state.can_pay(cost)


## Exp 006 (B): pays a cost from the pool and then the house's storage
## (atomic; the pool alone without a supply).
func pay_cost(cost: Dictionary) -> bool:
	if cost.is_empty():
		return true
	if supply != null and supply.has_method("pay"):
		return supply.pay(cost)
	return state == null or state.pay(cost)


## Exp 006 (B): carried + stored in the house (the build menu's counts; U).
func available(item: String) -> int:
	if supply != null and supply.has_method("available"):
		return supply.available(item)
	return state.inventory.count(item) if state != null else 0


## Exp 006 (B): how much of `item` is stored in the house's furniture.
func stored(item: String) -> int:
	return supply.stored(item) if supply != null and supply.has_method("stored") else 0


## Segments from the drag start to p along one axis (the larger drag), on the
## line through the start segment.
func _run(from: Vector2, p: Vector2) -> Array:
	var d := p - from
	var horiz := absf(d.x) >= absf(d.y)
	var out := []
	if horiz:
		var line := roundi(from.y)
		var a := floori(minf(from.x, p.x))
		var b := floori(maxf(from.x, p.x))
		for x in range(a, mini(b, a + RUN_MAX - 1) + 1):
			out.append(Vector3i(0, line, x))
	else:
		var line := roundi(from.x)
		var a := floori(minf(from.y, p.y))
		var b := floori(maxf(from.y, p.y))
		for y in range(a, mini(b, a + RUN_MAX - 1) + 1):
			out.append(Vector3i(1, line, y))
	return out


func _eval_run(r: Dictionary, id: String, segs: Array) -> void:
	var is_wall := id == "wall" or id == "stone_wall"
	if is_wall:
		segs = _wall_actions(r, id, segs)      # Refinement 01: replace other walls, skip doors and windows
	r["segs"] = segs
	r["cost"] = BuildPieces.times(BuildPieces.LIST[piece]["cost"], segs.size())
	r["bad"] = []
	var extra := {}
	var reps: Dictionary = r.get("replace", {})
	for s in segs:
		var why := _check_line_piece(id, s, reps.has(s))
		if why != "":
			r["bad"].append(s)
			if r["reason"] == "":
				r["reason"] = why
		var cells := world.nav.cells_in_rect(HouseWorld.seg_rect(s, 0.125, 0.125) if is_wall else WorldObject.footprint_of("barricade", HouseWorld.seg_center(s), world.seg_rot(s)))
		for c in cells:
			extra[c] = GridNav.WALL
	if r["reason"] == "" and not world.exit_path_exists(extra):
		r["reason"] = SEAL_REASON
		r["bad"] = segs.duplicate()
	if is_wall and not reps.is_empty():
		_net_replace_cost(r)


## Refinement 01, direct wall replacement: sorts a wall run's segments. An
## empty line is built as before; a wall of another material (the player's
## own wood or stone, or an original house wall) is replaced in the same
## action; windows, doors and other objects on the line and walls of the
## same material are skipped in a run (a single segment says why). Fills
## r["replace"] (segment -> {"from", "refund", "plated"}) and r["skipped"];
## returns the segments to build on.
func _wall_actions(r: Dictionary, id: String, segs: Array) -> Array:
	var mat := "stone" if id == "stone_wall" else "wood"
	var out := []
	var reps := {}
	var skip_reason := ""
	var skipped := 0
	for s in segs:
		var why := ""
		var info := world.section_info(s)
		if not HouseWorld.LOT.encloses(HouseWorld.seg_rect(s, 0.1)):
			out.append(s)                      # _check_line_piece says why
			continue
		if info["glass"]:
			why = "There's a window here."
		elif not info["objects"].is_empty():
			why = "Something is already standing here."
		elif info["coverage"] >= 0.3:
			var from := wall_material(s)
			if from == "":
				why = "There's already a wall here."
			elif from == mat:
				why = "There's already a %s wall here (Repair mends it)." % ("stone" if mat == "stone" else "wooden")
			else:
				reps[s] = {"from": from, "refund": wall_refund(s), "plated": info["upgraded"]}
		if why != "":
			skipped += 1
			if skip_reason == "":
				skip_reason = why
			continue
		out.append(s)
	r["replace"] = reps
	r["skipped"] = skipped
	if out.is_empty() and skip_reason != "":
		r["reason"] = skip_reason
		r["bad"] = segs.duplicate()
		return segs
	return out


## "wood" or "stone" for the player's own wall on segment s, "house" for an
## original wall section, "" if no wall section stands there.
func wall_material(s: Vector3i) -> String:
	if world.built.has(s):
		return str(world.sections.get(s, {}).get("material", "wood"))
	return "house" if world.sections.has(s) else ""


## What taking wall section s down gives back (Demolish, and the wall it
## replaces): the player's own wall its full cost; an original wall or window
## section salvage by its integrity (BuildPieces.original_salvage).
func wall_refund(s: Vector3i) -> Dictionary:
	if world.built.has(s):
		return BuildPieces.wall_cost(world.sections.get(s, {}).get("material", "wood")).duplicate()
	var info := world.section_info(s)
	return BuildPieces.original_salvage("window" if info["glass"] else "wall", info["integrity"])


## Replacement pays the new walls minus what the old ones give back, per
## resource: r["cost"] is what is still paid, r["refund"] what comes back,
## r["gross_cost"] / r["gross_refund"] the two sides.
func _net_replace_cost(r: Dictionary) -> void:
	var back := {}
	for s in r["replace"]:
		back = BuildPieces.add(back, r["replace"][s]["refund"])
	r["gross_cost"] = r["cost"]
	r["gross_refund"] = back
	var pay := {}
	var got := {}
	for k in BuildPieces.add(r["cost"], back):
		var n := int(r["cost"].get(k, 0)) - int(back.get(k, 0))
		if n > 0:
			pay[k] = n
		elif n < 0:
			got[k] = -n
	r["cost"] = pay
	r["refund"] = got


func _check_line_piece(id: String, s: Vector3i, replacing := false) -> String:
	var rect := HouseWorld.seg_rect(s, HouseWorld.STONE_HALF if id == "stone_wall" else 0.1)
	if not HouseWorld.LOT.encloses(rect):
		return "Outside the lot: the fog starts there."
	var info := world.section_info(s)
	if info["glass"]:
		return "There's a window here."
	if info["coverage"] >= 0.3 and not replacing:
		return "There's already a wall here." if id == "wall" or id == "stone_wall" else "There's a wall here."
	if not world.objects_in(HouseWorld.seg_rect(s, 0.12)).is_empty():
		return "Something is already standing here."
	if world.furniture_in(rect):
		return "Furniture is in the way."
	if world.bodies_in(rect.grow(0.05)):
		return "Someone is standing there."
	if id == "stone_wall" and not world.is_stone_founded(s):      # Exp 006 (B): not on a timber footing
		return FOUNDATION_REASON
	return ""


## Stone foundation tiles (1 m x 1 m on each segment): on open ground in the
## lot, not under walls, furniture or objects, and not where there is a floor.
func _eval_foundation(r: Dictionary, segs: Array) -> void:
	r["segs"] = segs
	r["cost"] = BuildPieces.times(BuildPieces.LIST[piece]["cost"], segs.size())
	r["bad"] = []
	for s in segs:
		var rect := HouseWorld.seg_rect(s, HouseWorld.FOUNDATION_HALF)
		var why := ""
		if not HouseWorld.LOT.encloses(rect):
			why = "Outside the lot: the fog starts there."
		elif world.floor_coverage(s) >= 0.5:
			why = "There's already a floor here."
		elif world.design.any_struct_in(rect.position, rect.end, VoxelHouse.BASE_ROW, VoxelHouse.TOP_ROW):
			why = "There's a wall in the way."
		elif world.furniture_in(rect.grow(-0.05)):
			why = "Something is in the way."
		elif not world.objects_in(rect.grow(-0.05)).is_empty():
			why = "Something is already standing here."
		if why != "":
			r["bad"].append(s)
			if r["reason"] == "":
				r["reason"] = why


func _eval_door(r: Dictionary, s: Vector3i) -> void:
	r["segs"] = [s]
	r["cost"] = BuildPieces.LIST[piece]["cost"]
	var info := world.section_info(s)
	if not HouseWorld.LOT.encloses(HouseWorld.seg_rect(s, 0.1)):
		r["reason"] = "Outside the lot: the fog starts there."
	elif not info["objects"].is_empty():
		r["reason"] = "There's already something in this opening."
	elif info["glass"]:
		r["reason"] = "Not in a window."
	elif info["wall"]:
		r["cut"] = true
		if world.bodies_in(HouseWorld.seg_rect(s, 0.15)):
			r["reason"] = "Someone is standing there."
	elif info["gap"]:
		r["cut"] = false
		if world.bodies_in(HouseWorld.seg_rect(s, 0.15)):
			r["reason"] = "Someone is standing in the doorway."
	else:
		r["reason"] = "A door needs a wall or a 1 m doorway."


## Experiment 004: planks over a window section (one 1 m segment with glass).
func _eval_boards(r: Dictionary, s: Vector3i) -> void:
	r["segs"] = [s]
	r["cost"] = BuildPieces.LIST[piece]["cost"]
	var info := world.section_info(s)
	if not HouseWorld.LOT.encloses(HouseWorld.seg_rect(s, 0.1)):
		r["reason"] = "Outside the lot: the fog starts there."
	elif not info["glass"]:
		r["reason"] = "Window boards go over a window."
	elif not info["objects"].is_empty():
		r["reason"] = "This window is already boarded up."


## Experiment 004: the fuse box hangs on a wall, on the side the pointer (the
## player) is on; only one may exist.
func _eval_fuse_box(r: Dictionary, p: Vector2) -> void:
	r["cost"] = BuildPieces.LIST[piece]["cost"]
	r["kind"] = "fuse_box"
	if world.fuse_box() != null:
		r["reason"] = "There's already a fuse box."
		return
	var s := HouseWorld.nearest_seg(p)
	var info := world.section_info(s)
	if not info["exists"] or not info["wall"] or info["glass"] or info["integrity"] < 0.5:
		r["reason"] = "Aim at a wall: the fuse box hangs on it."
		return
	var across := (p.y - s.y) if s.x == 0 else (p.x - s.y)
	var side := signf(across)
	if absf(across) < 0.02:
		side = -float(world.outer_sign(s))
		if player != null:
			var pp := Vector2(player.global_position.x, player.global_position.z)
			side = signf(((pp.y - s.y) if s.x == 0 else (pp.x - s.y)) + 1e-4)
	var sec: Dictionary = world.sections.get(s, {})
	var half := 0.1
	if sec.get("material", "") == "stone" or (sec.get("orig", false) and world._is_outer_wall(s)):
		half = HouseWorld.STONE_HALF
	var depth: float = WorldObject.DEFS["fuse_box"]["size"].z
	var n := Vector2(0, side) if s.x == 0 else Vector2(side, 0)
	var pos := HouseWorld.seg_center(s) + n * (half + depth * 0.5 + 0.005)
	var rr := 0
	if n.x > 0.5:
		rr = 1
	elif n.y > 0.5:
		rr = 2
	elif n.x < -0.5:
		rr = 3
	r["pos"] = pos
	r["rot"] = rr
	var fp := WorldObject.footprint_of("fuse_box", pos, rr)
	if not HouseWorld.LOT.encloses(fp):
		r["reason"] = "Outside the lot: the fog starts there."
	elif not world.objects_in(fp.grow(-0.02)).is_empty():
		r["reason"] = "Something is already hanging here."
	elif world.furniture_in(fp.grow(-0.02)):
		r["reason"] = "Furniture is in the way."


func _eval_doorway(r: Dictionary, s: Vector3i) -> void:
	r["segs"] = [s]
	var info := world.section_info(s)
	if not info["exists"] or not info["wall"]:
		r["reason"] = "Aim at a wall."
	elif info["glass"]:
		r["reason"] = "Not through a window."
	elif not info["objects"].is_empty():
		r["reason"] = "Something is in the way."


func _snap_pos(id: String, p: Vector2, r: int) -> Vector2:
	var s: Vector3 = WorldObject.DEFS[id]["size"]
	var ext := Vector2(s.x, s.z) if r % 2 == 0 else Vector2(s.z, s.x)
	var lo := ((p - ext * 0.5) / 0.5).round() * 0.5
	return lo + ext * 0.5


func _eval_object(r: Dictionary, id: String, pos: Vector2) -> void:
	r["pos"] = pos
	r["rot"] = rot
	r["cost"] = BuildPieces.LIST[piece]["cost"]
	r["kind"] = id
	var fp := WorldObject.footprint_of(id, pos, rot)
	if not HouseWorld.LOT.encloses(fp):
		r["reason"] = "Outside the lot: the fog starts there."
	elif world.design.any_struct_in(fp.position, fp.end, VoxelHouse.NAV_ROW_LO, VoxelHouse.NAV_ROW_HI) \
			or world.grid.any_struct_in(fp.position, fp.end, VoxelHouse.NAV_ROW_LO, VoxelHouse.NAV_ROW_HI):
		r["reason"] = "There's a wall in the way."
	elif not world.objects_in(fp).is_empty():
		r["reason"] = "Something is already standing here."
	elif world.furniture_in(fp):
		r["reason"] = "Furniture is in the way."
	elif world.bodies_in(fp.grow(0.05)):
		r["reason"] = "Someone is standing there."
	else:
		var extra := {}
		for c in world.nav.cells_in_rect(fp):
			extra[c] = GridNav.SOLID
		if not world.exit_path_exists(extra):
			r["reason"] = SEAL_REASON


func _eval_repair(r: Dictionary, p: Vector2) -> void:
	var o := world.object_at(p, 0.25)
	if o != null:
		r["object"] = o
		if o.hp >= o.max_hp:
			r["reason"] = "The %s is in good shape." % o.display_name().to_lower()
		r["cost"] = BuildPieces.object_repair_cost(o.kind, o.hp, o.max_hp, o.mat)
		return
	var s := HouseWorld.nearest_seg(p)
	r["segs"] = [s]
	var tile := world.foundation_at(p)      # Exp 006 (B): a blasted foundation tile (when the wall here is fine)
	if tile.x >= 0 and (not world.sections.has(s) or world.section_missing(s) <= 0):
		var lost := world.foundation_missing(tile)
		if lost > 0:
			r["segs"] = [tile]
			r["foundation_repair"] = true
			var wood := world.foundation_material(tile) == "wood"
			r["cost"] = {"wood": ceili(lost / BuildPieces.REPAIR_RATE["wood"])} if wood else {"stone": ceili(lost / BuildPieces.REPAIR_RATE["stone"])}
			return
	if not world.sections.has(s):
		r["reason"] = "Aim at a damaged wall or door."
		return
	var missing := world.section_missing(s)
	r["missing"] = missing
	if missing <= 0:
		r["reason"] = "This wall is intact."
		return
	r["missing_by"] = world.section_missing_by(s)
	r["cost"] = BuildPieces.section_repair_cost_by(r["missing_by"])
	if world.bodies_in(HouseWorld.seg_rect(s, 0.25, 0.1)):
		r["reason"] = "Someone is standing in the wall."


func _eval_upgrade(r: Dictionary, p: Vector2) -> void:
	# Experiment 004: a door is reinforced (wood -> iron -> metal)
	var o := world.object_at(p, 0.2)
	if o != null and o.kind == "door":
		r["object"] = o
		var step := BuildPieces.reinforce_step(o.kind, o.mat)
		if step.is_empty():
			r["reason"] = "Already a metal door."
			return
		r["to_mat"] = step["to"]
		r["cost"] = step["cost"]
		return
	var s := HouseWorld.nearest_seg(p)
	r["segs"] = [s]
	r["cost"] = BuildPieces.LIST[piece]["cost"]
	var info := world.section_info(s)
	if not info["exists"] or not info["wall"]:
		r["reason"] = "Aim at a wall."
	elif info["glass"]:
		r["reason"] = "Windows can't be plated."
	elif info["upgraded"]:
		r["reason"] = "Already plated with iron."


## Experiment 004: the player's pieces refund their full cost; original
## objects, walls and windows and furniture give salvage.
func _eval_demolish(r: Dictionary, p: Vector2) -> void:
	var o := world.object_at(p, 0.2)
	if o != null:
		r["object"] = o
		r["refund"] = BuildPieces.object_refund(o.kind, o.mat, o.built)
		# Exp 005 (F): a moved house piece still gives salvage; piles go when searched empty
		if FurnitureCatalog.is_furniture(o.kind) and not o.built and o.kind != "workbench":
			r["refund"] = FurnitureCatalog.original_salvage(o.kind, o.hp, o.max_hp)
		if o.kind == "loot_pile":
			r["reason"] = "Search the pile instead (E): it goes when it's empty."
		return
	var fid := _ptr_furniture if _ptr_furniture != "" and debug_pointer == Vector2.INF else ""
	if fid == "" and world.furniture != null:
		fid = world.furniture.piece_at(p, 0.0)
	if fid != "" and world.furniture != null and world.furniture.state_of(fid) in ["intact", "damaged", "destroyed"]:
		r["furniture"] = fid
		r["refund"] = world.furniture.salvage(fid)
		return
	var s := HouseWorld.nearest_seg(p)
	r["segs"] = [s]
	var bearing: String = world.bearing_warning(s) if world.has_method("bearing_warning") else ""   # Refinement 01 (S)
	if world.built.has(s):
		r["bearing"] = bearing
		r["refund"] = wall_refund(s)
		return
	var info := world.section_info(s)
	if info["exists"] and (info["wall"] or info["glass"]):
		r["opening"] = true
		r["bearing"] = bearing
		r["window"] = info["glass"]
		r["refund"] = wall_refund(s)
		if world.bodies_in(HouseWorld.seg_rect(s, 0.2)):
			r["reason"] = "Someone is standing there."
		return
	var f := world.foundation_at(p)
	if f.x >= 0:
		r["segs"] = [f]
		r["foundation"] = true
		r["refund"] = (BuildPieces.TIMBER_FOOTING_COST if world.foundation_material(f) == "wood" else BuildPieces.FOUNDATION_COST).duplicate()   # Exp 006 (B)
		var tile := HouseWorld.seg_rect(f, HouseWorld.FOUNDATION_HALF)
		for b in world.built:
			if world.sections.get(b, {}).get("material", "") == "stone" and HouseWorld.seg_rect(b, 0.15).intersects(tile):
				r["reason"] = "Take the stone wall down first."
				break
		return
	r["reason"] = "Nothing to demolish here."


# --- applying ------------------------------------------------------------------------

## Validates, pays and applies at plan point `p`. Emits `message` either way.
func apply(p: Vector2, from := Vector2.INF) -> bool:
	var r := evaluate(p, from)
	last_eval = r
	if not r["ok"]:
		message.emit(r["reason"], false)
		Sfx.play("build/invalid")
		return false
	if not r["cost"].is_empty() and state != null and not pay_cost(r["cost"]):      # Exp 006 (B): + house storage
		message.emit("Needs %s." % BuildPieces.cost_text(r["cost"]), false)
		Sfx.play("build/invalid")
		return false
	var at := _where(r)
	var text := ""
	match r["piece"]:
		"wall", "stone_wall":
			var stone: bool = r["piece"] == "stone_wall"
			var reps: Dictionary = r.get("replace", {})
			# Refinement 01: walls of another material come down first, through
			# the demolish path (the player's own: demolish_wall; the house's:
			# knocked out), and the new walls go up over all segments at once.
			var froms := PackedStringArray()
			for s in reps:
				var fname: String = {"wood": "wooden wall", "stone": "stone wall"}.get(reps[s]["from"], "house wall")
				if not froms.has(fname):
					froms.append(fname)
				if world.built.has(s):
					world.demolish_wall(s)
				else:
					world.cut_opening(s, true)
			world.build_walls(r["segs"], "stone" if stone else "wood")
			for s in reps:
				if reps[s]["plated"]:
					world.upgrade_section(s)       # the iron plating stays on the new wall
			if reps.is_empty():
				text = "Built %d m of %s wall (%s)." % [r["segs"].size(), "stone" if stone else "wooden", BuildPieces.cost_text(r["cost"])]
			else:
				var fresh: int = r["segs"].size() - reps.size()
				text = "Replaced %d m of %s with %s wall%s (paid %s)." % [reps.size(), " and ".join(froms), "stone" if stone else "wooden",
					(", built %d m" % fresh) if fresh > 0 else "", BuildPieces.cost_text(r["cost"])]
				text += _give_back(r.get("refund", {}))
			if int(r.get("skipped", 0)) > 0:
				text += " Skipped %d m (doors, windows, walls already of that kind)." % int(r["skipped"])
			Sfx.play("build/place", at)
			Sfx.play("build/hammer", at)
		"foundation", "timber_footing":
			var wood: bool = r["piece"] == "timber_footing"      # Exp 006 (B)
			world.build_foundation(r["segs"], "wood" if wood else "stone")
			text = "Laid %d m² of %s (%s)." % [r["segs"].size(), "timber footing" if wood else "stone foundation", BuildPieces.cost_text(r["cost"])]
			Sfx.play("build/place", at)
			if wood:
				Sfx.play("build/hammer", at)
		"barricade", "iron_barricade":
			for s in r["segs"]:
				world.place_object("barricade", HouseWorld.seg_center(s), world.seg_rot(s), true, _mat())
			var bname := "Iron barricade" if _mat() == "iron" else "Barricade"
			text = "%s up." % bname if r["segs"].size() == 1 else "%d m of %ss up." % [r["segs"].size(), bname.to_lower()]
			Sfx.play("build/place", at)
			Sfx.play("build/upgrade" if _mat() == "iron" else "build/hammer", at)
		"door", "iron_door", "metal_door":
			var s: Vector3i = r["segs"][0]
			if r.get("cut", false):
				world.cut_opening(s)
			world.place_object("door", HouseWorld.seg_center(s), world.seg_rot(s), true, _mat())
			text = WorldObject.name_of("door", _mat()) + " hung. E opens and closes it."
			Sfx.play("build/place", at)
			Sfx.play("build/upgrade" if _mat() != "wood" else "build/hammer", at)
		"window_boards":
			var s: Vector3i = r["segs"][0]
			world.place_object("boards", HouseWorld.seg_center(s), world.seg_rot(s), true)
			text = "Window boarded up."
			Sfx.play("build/place", at)
			Sfx.play("build/hammer", at)
		"fuse_box":
			world.place_object("fuse_box", r["pos"], r["rot"], true)
			text = "Fuse box mounted: E switches the main power."
			Sfx.play("build/place", at)
			Sfx.play("build/upgrade", at)
		"doorway":
			world.cut_opening(r["segs"][0])
			text = "Doorway cut."
			Sfx.play("build/demolish", at)
		"crate", "rain_collector", "workbench", "motion_sensor", "turret_mount":
			world.place_object(r["kind"], r["pos"], r["rot"])
			match r["piece"]:
				"crate":
					text = "Storage crate built: room for more materials."
				"rain_collector":
					text = "Rain collector set up: a bottle of water every dawn."
				"motion_sensor":      # Exp 007 (S)
					text = "Motion sensor set up: it needs power. E sets alarm, silence and a linked turret."
				"turret_mount":
					text = "Turret mount set up: E to install a gun and fill its ammo box. It needs power."
				_:
					text = "Workbench set up: E turns 3 scrap into 1 iron."
			Sfx.play("build/place", at)
		"repair":
			if r.get("foundation_repair", false):      # Exp 006 (B)
				var n := world.repair_foundation(r["segs"][0])
				text = "Foundation relaid: %d voxels (%s)." % [n, BuildPieces.cost_text(r["cost"])]
			elif r["object"] != null:
				world.repair_object(r["object"])
				text = "%s repaired (%s)." % [r["object"].display_name(), BuildPieces.cost_text(r["cost"])]
			else:
				var n := world.repair_section(r["segs"][0])
				text = "Wall repaired: %d voxels (%s)." % [n, BuildPieces.cost_text(r["cost"])]
			Sfx.play("build/hammer", at)
		"upgrade":
			if r["object"] != null:
				world.reinforce_object(r["object"], r["to_mat"])
				text = "Now a %s (%s)." % [r["object"].display_name().to_lower(), BuildPieces.cost_text(r["cost"])]
			else:
				world.upgrade_section(r["segs"][0])
				text = "Plated with iron (%s)." % BuildPieces.cost_text(r["cost"])
			Sfx.play("build/upgrade", at)
		"demolish":
			var refund: Dictionary = r.get("refund", {})
			if r["object"] != null:
				var name: String = r["object"].display_name()
				world.remove_object(r["object"])
				text = "%s taken down." % name
			elif r.has("furniture"):
				var fid: String = r["furniture"]
				var rubble: bool = world.furniture.state_of(fid) == "destroyed"
				var fname := world.furniture.display_name(fid)
				world.demolish_furniture(fid)
				text = "Rubble cleared." if rubble else "%s taken apart." % fname
			elif r.get("window", false):
				world.cut_opening(r["segs"][0], true)
				text = "Window knocked out."
			elif r.get("foundation", false):
				world.remove_foundation(r["segs"][0])
				text = "Foundation taken up."
			elif r.get("opening", false):
				world.cut_opening(r["segs"][0], true)
				text = "Wall section knocked out."
			else:
				world.demolish_wall(r["segs"][0])
				text = "Wall taken down."
			text += _give_back(refund)
			Sfx.play("build/demolish", at)
	if r.get("ext", false) and ext != null:      # Experiment 004 (L)
		text = ext.apply(self, r)
	if FurniturePlace.handles(r["piece"]):      # Exp 005 (F)
		text = FurniturePlace.apply(self, r)
	if WindowFill.handles(r["piece"]):          # Exp 006 (B)
		text = WindowFill.apply(self, r)
	if DefenseBuild.handles(r["piece"]):      # Exp 006 (D)
		text = DefenseBuild.apply(self, r)
	if supply != null and not r["cost"].is_empty():      # Exp 006 (B): say what came out of storage
		var took: Dictionary = supply.get("last_paid").get("stored", {})
		if not took.is_empty():
			text += " (%s from storage)" % BuildPieces.cost_text(took)
	_eval_key = ""
	message.emit(text, true)
	changed.emit()
	return true


## Adds a refund to the inventory (not with the unlimited cheat). Returns
## " Got back ..." for what fitted, or "".
func _give_back(refund: Dictionary) -> String:
	if refund.is_empty() or state == null or state.cheats.get("unlimited", false):
		return ""
	if supply != null and supply.has_method("give"):      # Exp 006 (B): overflow into a container
		var g: Dictionary = supply.give(refund)
		var t := " Got back %s." % BuildPieces.cost_text(g["inv"]) if not g["inv"].is_empty() else ""
		if not g["stored"].is_empty():
			t += " %s went into storage." % BuildPieces.cost_text(g["stored"])
		return t
	var got := {}
	for k in refund:
		var n := state.inventory.add(k, refund[k])
		if n > 0:
			got[k] = n
	return " Got back %s." % BuildPieces.cost_text(got) if not got.is_empty() else ""


func _where(r: Dictionary) -> Vector3:
	if r.has("furniture") and world.furniture != null and world.furniture.pieces.has(r["furniture"]):
		var c: Vector2 = world.furniture.pieces[r["furniture"]]["f"]["rect"].get_center()
		return Vector3(c.x, 0.6, c.y)
	if r["object"] != null:
		var o: WorldObject = r["object"]
		return Vector3(o.pos.x, 1.0, o.pos.y)
	if r["pos"] != Vector2.INF:
		return Vector3(r["pos"].x, 0.5, r["pos"].y)
	if not r["segs"].is_empty():
		var c := HouseWorld.seg_center(r["segs"][0])
		return Vector3(c.x, 1.0, c.y)
	return Vector3.ZERO


## The survival core's rule when it has one (GameState.can_build: a hammer
## owned, or the unlimited cheat); the same rule locally otherwise.
func _has_hammer() -> bool:
	if state == null:
		return true
	if state.has_method("can_build"):
		return state.call("can_build") == ""
	return state.cheats.get("unlimited", false) or state.inventory.count("hammer") > 0


# --- preview -------------------------------------------------------------------------

func _ghost_material(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	_mats[key] = m
	return m


func _show_ghost(r: Dictionary) -> void:
	var id: String = r["piece"]
	var items := []   # [type, size, position, yaw, colour, style]
	var t := tool()
	var col_ok: Color = GHOST_TOOL.get(t, GHOST_OK)
	var style := _mat() if _mat() in ["iron", "metal"] else ""
	match id:
		"window_boards", "fuse_box":
			var kind := "boards" if id == "window_boards" else "fuse_box"
			var d: Dictionary = WorldObject.DEFS[kind]
			var at := Vector2.INF
			var rr := 0
			if id == "window_boards" and not r["segs"].is_empty():
				var s: Vector3i = r["segs"][0]
				rr = world.seg_rot(s)
				at = HouseWorld.seg_center(s) + WorldObject.front_dir(rr) * float(d.get("out", 0.0))
			elif r["pos"] != Vector2.INF:
				rr = int(r.get("rot", 0))
				at = r["pos"]
			if at != Vector2.INF:
				items.append([kind, d["size"], Vector3(at.x, float(d.get("y0", 0.0)), at.y), WorldObject.YAW[rr], col_ok if r["ok"] else GHOST_BAD, ""])
		"wall", "stone_wall", "barricade", "iron_barricade", "door", "iron_door", "metal_door", "doorway", "foundation", "timber_footing":
			var reps: Dictionary = r.get("replace", {})
			for s in r["segs"]:
				var bad: bool = not r["ok"] and (r.get("bad", []).has(s) or not r.has("bad"))
				var c := HouseWorld.seg_center(s)
				var yaw := 0.0 if s.x == 0 else PI * 0.5
				var type := "wall_ghost"
				var size := Vector3(1.0, 2.6, 0.2)
				var col := GHOST_BAD if bad else col_ok
				match id:
					"wall", "stone_wall":
						if id == "stone_wall":
							size = Vector3(1.0, 2.6, 0.3)
						if reps.has(s):            # Refinement 01: over the old wall, so it shows
							size = Vector3(1.02, 2.66, maxf(size.z, 0.3) + 0.08)
							if not bad:
								col = GHOST_REPLACE
					"foundation", "timber_footing":
						size = Vector3(1.0, 0.06, 0.98)
					"barricade", "iron_barricade":
						type = "barricade"
						size = WorldObject.DEFS["barricade"]["size"]
						yaw = WorldObject.YAW[world.seg_rot(s)]
					"door", "iron_door", "metal_door":
						type = "door"
						size = WorldObject.DEFS["door"]["size"]
						yaw = WorldObject.YAW[world.seg_rot(s)]
					"doorway":
						size = Vector3(1.0, 2.1, 0.42)
				items.append([type, size, Vector3(c.x, 0, c.y), yaw, col, style])
		"crate", "rain_collector", "workbench", "motion_sensor", "turret_mount":      # Exp 007 (S): + security
			if r["pos"] != Vector2.INF:
				items.append([_kind(), WorldObject.DEFS[_kind()]["size"], Vector3(r["pos"].x, 0, r["pos"].y), WorldObject.YAW[rot], col_ok if r["ok"] else GHOST_BAD, ""])
		_:
			var o: WorldObject = r["object"]
			if o != null:
				var s: Vector3 = WorldObject.DEFS[o.kind]["size"]
				items.append(["wall_ghost", s + Vector3(0.12, 0.08, 0.12), Vector3(o.pos.x, o.base_y(), o.pos.y), WorldObject.YAW[o.rot], col_ok if r["ok"] else GHOST_BAD, ""])
			elif r.has("furniture") and world.furniture != null:
				var f: Dictionary = world.furniture.pieces[r["furniture"]]["f"]
				var fr: Rect2 = f["rect"]
				var fh := minf(float(f["height"]), 2.0) if world.furniture.ok(r["furniture"]) else HouseFurniture.RUBBLE_HEIGHT
				items.append(["wall_ghost", Vector3(fr.size.x + 0.08, fh + 0.06, fr.size.y + 0.08), Vector3(fr.get_center().x, 0, fr.get_center().y), 0.0, col_ok if r["ok"] else GHOST_BAD, ""])
			elif r.get("foundation", false):
				var s: Vector3i = r["segs"][0]
				var c := HouseWorld.seg_center(s)
				items.append(["wall_ghost", Vector3(1.04, 0.1, 1.02), Vector3(c.x, 0, c.y), 0.0 if s.x == 0 else PI * 0.5, col_ok if r["ok"] else GHOST_BAD, ""])
			elif not r["segs"].is_empty():
				var s: Vector3i = r["segs"][0]
				var c := HouseWorld.seg_center(s)
				items.append(["wall_ghost", Vector3(1.04, 2.68, 0.44), Vector3(c.x, 0, c.y), 0.0 if s.x == 0 else PI * 0.5, col_ok if r["ok"] else GHOST_BAD, ""])
	if r.get("ext", false) and ext != null:      # Experiment 004 (L)
		items = ext.ghost_items(self, r)
	if FurniturePlace.handles(id):      # Exp 005 (F)
		items = FurniturePlace.ghost_items(self, r, col_ok, GHOST_BAD)
	if WindowFill.handles(id):          # Exp 006 (B)
		items = WindowFill.ghost_items(self, r, GHOST_TOOL["upgrade"], GHOST_BAD)
	if DefenseBuild.handles(id):      # Exp 006 (D)
		items = DefenseBuild.ghost_items(self, r)
	var key := ""
	for it in items:
		key += "%s%s%s;" % [it[0], str(it[1]), it[5]]
	if key != _ghost_key:
		_ghost_key = key
		for g in _ghosts:
			g.queue_free()
		_ghosts.clear()
		for it in items:
			var g := PropKit.make(it[0], it[1], {"facing": "N", "seed": 1, "style": it[5]})
			for gi in g.find_children("*", "GeometryInstance3D", true, false):
				(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_ghost_root.add_child(g)
			_ghosts.append(g)
	for k in items.size():
		var g := _ghosts[k]
		g.position = items[k][2] + Vector3(0, 0.005 + plane_y, 0)
		g.rotation.y = items[k][3]
		var m := _ghost_material(items[k][4])
		for gi in g.find_children("*", "GeometryInstance3D", true, false):
			(gi as GeometryInstance3D).material_override = m
	_show_replace_label(r)


## Refinement 01: a floating "Replace wood → stone" over the first wall a run replaces.
func _show_replace_label(r: Dictionary) -> void:
	var reps: Dictionary = r.get("replace", {})
	if reps.is_empty() or not r["piece"] in ["wall", "stone_wall"]:
		if _ghost_label != null:
			_ghost_label.visible = false
		return
	if _ghost_label == null:
		_ghost_label = Label3D.new()
		_ghost_label.name = "ReplaceLabel"
		_ghost_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_ghost_label.no_depth_test = true
		_ghost_label.pixel_size = 0.01
		_ghost_label.font_size = 26
		_ghost_label.outline_size = 8
		_ghost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_ghost_label.modulate = Color(0.85, 0.97, 1.0)
		_ghost_root.add_child(_ghost_label)
	_ghost_label.text = replace_text(r).replace(": ", "\n")
	_ghost_label.modulate = Color(0.85, 0.97, 1.0) if r["ok"] else Color(1.0, 0.6, 0.55)
	var first: Vector3i = reps.keys()[0]
	var c := HouseWorld.seg_center(first)
	_ghost_label.position = Vector3(c.x, plane_y + 3.0, c.y)
	_ghost_label.visible = true


## "Replace wood → stone" for a wall run that replaces walls (with its net cost).
func replace_text(r: Dictionary) -> String:
	var reps: Dictionary = r.get("replace", {})
	if reps.is_empty():
		return ""
	var froms := PackedStringArray()
	for s in reps:
		var f: String = {"wood": "wood", "stone": "stone"}.get(reps[s]["from"], "house wall")
		if not froms.has(f):
			froms.append(f)
	var to := "stone" if r["piece"] == "stone_wall" else "wood"
	var t := "Replace %s → %s" % ["/".join(froms), to]
	if reps.size() > 1:
		t += " (%d m)" % reps.size()
	var parts := PackedStringArray()
	parts.append("pay " + BuildPieces.cost_text(r["cost"]) if not r["cost"].is_empty() else "nothing to pay")
	if not r.get("refund", {}).is_empty():
		parts.append("back " + BuildPieces.cost_text(r["refund"]))
	return t + ": " + ", ".join(parts)


func _refresh_palette() -> void:
	if palette == null:
		return
	var p: Dictionary = BuildPieces.LIST[piece]
	var cost: Dictionary = last_eval.get("gross_cost", last_eval.get("cost", p["cost"]))   # Refinement 01: a replacing run's own cost
	var cost_txt := ""
	match tool():
		"place":
			var tiles := piece_id() == "foundation" or piece_id() == "timber_footing"      # Exp 006 (B): + timber footing
			cost_txt = BuildPieces.cost_text(p["cost"]) + (" per metre" if p.get("per_m", false) and not tiles else " per tile" if tiles else "")
			var n: int = last_eval.get("segs", []).size()
			if n > 1:
				cost_txt += ("  ·  %d tiles: %s" if tiles else "  ·  run %d m: %s") % [n, BuildPieces.cost_text(cost)]
		"repair":
			cost_txt = BuildPieces.cost_text(cost) if not cost.is_empty() else "paid in the damaged material"
		"upgrade":
			if last_eval.get("object") != null and not cost.is_empty():
				cost_txt = BuildPieces.cost_text(cost) + " (door)"
			else:
				cost_txt = BuildPieces.cost_text(p["cost"]) + " per section"
		"demolish":
			var rf: Dictionary = last_eval.get("refund", {})
			cost_txt = "refund %s" % BuildPieces.cost_text(rf) if not rf.is_empty() else "free"
		"move":
			cost_txt = "free" + ("  ·  holding: %s" % str(carry["name"]).to_lower() if not carry.is_empty() else "")
		"remove_window":      # Exp 006 (B)
			cost_txt = BuildPieces.cost_text(p["cost"]) + " per metre · the frame gives back " + BuildPieces.cost_text(BuildPieces.WINDOW_FRAME_SALVAGE)
	var mats := "no inventory"
	if state != null:
		var inv := state.inventory
		mats = "Planks %d · Stone %d · Iron %d · Nails %d · Scrap %d" % [inv.count("wood"), inv.count("stone"), inv.count("iron"), inv.count("nails"), inv.count("scrap")]
		if supply != null and supply.has_method("count_text"):      # Exp 006 (B): "12 + 30 stored"
			var parts := PackedStringArray()
			for k in ["wood", "stone", "iron", "nails", "scrap"]:
				parts.append("%s %s" % [Items.name_of(k), supply.count_text(k)])
			mats = " · ".join(parts)
		if state.cheats.get("unlimited", false):
			mats += "  (unlimited)"
	var status := "Ready: click to %s." % ("build" if tool() == "place" else tool())
	if not last_eval.is_empty() and not last_eval["ok"]:
		status = last_eval["reason"]
	elif not last_eval.get("replace", {}).is_empty():
		status = "Ready: " + replace_text(last_eval) + "."        # Refinement 01
		if int(last_eval.get("skipped", 0)) > 0:
			status += " Skips %d m (doors, windows, walls already of that kind)." % int(last_eval["skipped"])
	elif last_eval.get("window", false):
		status = "Ready: knocks out this window."
	elif last_eval.get("opening", false):
		status = "Ready: knocks out this original wall section."
	elif last_eval.has("furniture"):
		status = "Ready: takes the %s apart." % world.furniture.display_name(last_eval["furniture"]).to_lower()
	if tool() == "demolish" and str(last_eval.get("bearing", "")) != "":
		status += "  " + str(last_eval["bearing"])      # Refinement 01 (S): what the wall carries
	if FurniturePlace.handles(piece_id()) and FurniturePlace.status(self, last_eval) != "":
		status = FurniturePlace.status(self, last_eval)      # Exp 005 (F)
	if WindowFill.handles(piece_id()) and WindowFill.status(last_eval) != "":
		status = WindowFill.status(last_eval)      # Exp 006 (B)
	if piece_id() in ["foundation", "timber_footing"] and last_eval.get("ok", false):
		status += "  " + FOUNDATION_HINT      # Exp 006 (B)
	palette.show_state(piece, p["name"], cost_txt, mats, status, last_eval.get("ok", true), p["hint"])
