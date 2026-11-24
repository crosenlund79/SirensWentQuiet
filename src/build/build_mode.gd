class_name BuildMode
extends Node3D
## Construction mode (SPEC-002 §6, §7.4; SPEC-003 §4).
##
## Palette slots (BuildPieces): 1 walls (wood | stone; click-drag runs of 1 m
## segments on integer plan lines), 2 barricades (wood | iron), 3 doors (wood
## | reinforced), 4 doorway, 5 storage crate, 6 equipment (rain collector |
## workbench), 7 repair, 8 iron plating, 9 demolish, 0 stone foundation
## (runs of 1 m tiles). Pressing a slot's key again cycles its material
## variants. A ghost preview is green when valid, red with a reason when not.
## Costs (wood, stone, iron, nails, scrap) go through GameState.pay (the
## unlimited cheat makes them free); building needs a hammer. Every change
## keeps a way out (the exit rule). Stone walls need a foundation.
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
const SEAL_REASON := "That would seal the last way out."
const FOUNDATION_REASON := "Stone walls need a foundation: the house floor or a stone foundation."
## Pieces placed by dragging along a line, and pieces that follow the ground
## point under the mouse (the rest follow the aimed surface).
const RUN_PIECES := ["wall", "stone_wall", "barricade", "iron_barricade", "foundation"]
const FREE_PIECES := ["crate", "rain_collector", "workbench"]

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

var _dragging := false
var _drag_from := Vector2.INF
var _ghost_root: Node3D
var _ghosts: Array[Node3D] = []
var _ghost_key := ""
var _eval_key := ""
var _eval_age := 0.0
var _mats := {}
var _slot_pick := {}            # palette slot -> LIST index last used in it


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
	palette.slot_pressed.connect(select_slot)
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
	_dragging = false
	_eval_key = ""
	_ghost_key = ""
	Sfx.ui("ui/click")
	changed.emit()


func select_id(id: String) -> void:
	select(BuildPieces.index_of(id))


## A palette slot (0-9; keys 1-9 and 0): its last-used variant, or the next
## variant when the slot is already selected.
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
		if k >= KEY_1 and k <= KEY_9:
			select_slot(k - KEY_1)
			get_viewport().set_input_as_handled()
			return
		if k == KEY_0:
			select_slot(9)
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
	return piece_id() in RUN_PIECES


## Ground point under the mouse for free placement; the aimed surface (walls,
## objects, respecting the cutaway) for doors, doorways and tools.
func _pointer() -> Vector2:
	if camera == null or not is_inside_tree() or world == null:
		return Vector2.INF
	var mp := get_viewport().get_mouse_position()
	var o := camera.project_ray_origin(mp)
	var d := camera.project_ray_normal(mp)
	if piece_id() in RUN_PIECES or piece_id() in FREE_PIECES:
		if d.y > -0.001:
			return Vector2.INF
		var g := o + d * (-o.y / d.y)
		return Vector2(g.x, g.z)
	var hit := world.aim_ray(o, d)
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
	var s := HouseWorld.nearest_seg(p)
	if from != Vector2.INF and from.distance_to(p) > 0.35:
		return "%s|%s" % [id, str(_run(from, p))]
	var o: WorldObject = world.object_at(p, 0.2) if tool() != "place" else null
	return "%s|%s|%s" % [id, str(s), str(o.get_instance_id()) if o != null else ""]


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
		"wall", "stone_wall", "barricade", "iron_barricade", "foundation":
			var segs := [HouseWorld.nearest_seg(p)]
			if from != Vector2.INF and from.distance_to(p) > 0.35:
				segs = _run(from, p)
			if id == "foundation":
				_eval_foundation(r, segs)
			else:
				_eval_run(r, id, segs)
		"door", "iron_door":
			_eval_door(r, HouseWorld.nearest_seg(p))
		"doorway":
			_eval_doorway(r, HouseWorld.nearest_seg(p))
		"crate", "rain_collector", "workbench":
			_eval_object(r, _kind(), _snap_pos(_kind(), p, rot))
		"repair":
			_eval_repair(r, p)
		"upgrade":
			_eval_upgrade(r, HouseWorld.nearest_seg(p))
		"demolish":
			_eval_demolish(r, p)
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
	return cost.is_empty() or state == null or state.can_pay(cost)


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
	r["segs"] = segs
	r["cost"] = BuildPieces.times(BuildPieces.LIST[piece]["cost"], segs.size())
	r["bad"] = []
	var extra := {}
	for s in segs:
		var why := _check_line_piece(id, s)
		if why != "":
			r["bad"].append(s)
			if r["reason"] == "":
				r["reason"] = why
		var is_wall := id == "wall" or id == "stone_wall"
		var cells := world.nav.cells_in_rect(HouseWorld.seg_rect(s, 0.125, 0.125) if is_wall else WorldObject.footprint_of("barricade", HouseWorld.seg_center(s), world.seg_rot(s)))
		for c in cells:
			extra[c] = GridNav.WALL
	if r["reason"] == "" and not world.exit_path_exists(extra):
		r["reason"] = SEAL_REASON
		r["bad"] = segs.duplicate()


func _check_line_piece(id: String, s: Vector3i) -> String:
	var rect := HouseWorld.seg_rect(s, HouseWorld.STONE_HALF if id == "stone_wall" else 0.1)
	if not HouseWorld.LOT.encloses(rect):
		return "Outside the lot: the fog starts there."
	var info := world.section_info(s)
	if info["glass"]:
		return "There's a window here."
	if info["coverage"] >= 0.3:
		return "There's already a wall here." if id == "wall" or id == "stone_wall" else "There's a wall here."
	if not world.objects_in(HouseWorld.seg_rect(s, 0.12)).is_empty():
		return "Something is already standing here."
	if world.furniture_in(rect):
		return "Furniture is in the way."
	if world.bodies_in(rect.grow(0.05)):
		return "Someone is standing there."
	if id == "stone_wall" and not info["founded"]:
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


func _eval_upgrade(r: Dictionary, s: Vector3i) -> void:
	r["segs"] = [s]
	r["cost"] = BuildPieces.LIST[piece]["cost"]
	var info := world.section_info(s)
	if not info["exists"] or not info["wall"]:
		r["reason"] = "Aim at a wall."
	elif info["glass"]:
		r["reason"] = "Windows can't be plated."
	elif info["upgraded"]:
		r["reason"] = "Already plated with iron."


func _eval_demolish(r: Dictionary, p: Vector2) -> void:
	var o := world.object_at(p, 0.2)
	if o != null:
		r["object"] = o
		r["refund"] = BuildPieces.refund(BuildPieces.object_cost(o.kind, o.mat)) if o.built else {}
		return
	var s := HouseWorld.nearest_seg(p)
	r["segs"] = [s]
	if world.built.has(s):
		r["refund"] = BuildPieces.refund(BuildPieces.wall_cost(world.sections.get(s, {}).get("material", "wood")))
		return
	var info := world.section_info(s)
	if info["exists"] and info["wall"]:
		r["opening"] = true
		if world.bodies_in(HouseWorld.seg_rect(s, 0.2)):
			r["reason"] = "Someone is standing there."
		return
	var f := world.foundation_at(p)
	if f.x >= 0:
		r["segs"] = [f]
		r["foundation"] = true
		r["refund"] = BuildPieces.refund(BuildPieces.FOUNDATION_COST)
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
	if not r["cost"].is_empty() and state != null and not state.pay(r["cost"]):
		message.emit("Needs %s." % BuildPieces.cost_text(r["cost"]), false)
		Sfx.play("build/invalid")
		return false
	var at := _where(r)
	var text := ""
	match r["piece"]:
		"wall", "stone_wall":
			var stone: bool = r["piece"] == "stone_wall"
			world.build_walls(r["segs"], "stone" if stone else "wood")
			text = "Built %d m of %s wall (%s)." % [r["segs"].size(), "stone" if stone else "wooden", BuildPieces.cost_text(r["cost"])]
			Sfx.play("build/place", at)
			Sfx.play("build/hammer", at)
		"foundation":
			world.build_foundation(r["segs"])
			text = "Laid %d m² of stone foundation (%s)." % [r["segs"].size(), BuildPieces.cost_text(r["cost"])]
			Sfx.play("build/place", at)
		"barricade", "iron_barricade":
			for s in r["segs"]:
				world.place_object("barricade", HouseWorld.seg_center(s), world.seg_rot(s), true, _mat())
			var bname := "Iron barricade" if _mat() == "iron" else "Barricade"
			text = "%s up." % bname if r["segs"].size() == 1 else "%d m of %ss up." % [r["segs"].size(), bname.to_lower()]
			Sfx.play("build/place", at)
			Sfx.play("build/upgrade" if _mat() == "iron" else "build/hammer", at)
		"door", "iron_door":
			var s: Vector3i = r["segs"][0]
			if r.get("cut", false):
				world.cut_opening(s)
			world.place_object("door", HouseWorld.seg_center(s), world.seg_rot(s), true, _mat())
			text = ("Reinforced door" if _mat() == "iron" else "Door") + " hung. E opens and closes it."
			Sfx.play("build/place", at)
			Sfx.play("build/upgrade" if _mat() == "iron" else "build/hammer", at)
		"doorway":
			world.cut_opening(r["segs"][0])
			text = "Doorway cut."
			Sfx.play("build/demolish", at)
		"crate", "rain_collector", "workbench":
			world.place_object(r["kind"], r["pos"], r["rot"])
			match r["piece"]:
				"crate":
					text = "Storage crate built: room for more materials."
				"rain_collector":
					text = "Rain collector set up: a bottle of water every dawn."
				_:
					text = "Workbench set up: E turns 3 scrap into 1 iron."
			Sfx.play("build/place", at)
		"repair":
			if r["object"] != null:
				world.repair_object(r["object"])
				text = "%s repaired (%s)." % [r["object"].display_name(), BuildPieces.cost_text(r["cost"])]
			else:
				var n := world.repair_section(r["segs"][0])
				text = "Wall repaired: %d voxels (%s)." % [n, BuildPieces.cost_text(r["cost"])]
			Sfx.play("build/hammer", at)
		"upgrade":
			world.upgrade_section(r["segs"][0])
			text = "Plated with iron (%s)." % BuildPieces.cost_text(r["cost"])
			Sfx.play("build/upgrade", at)
		"demolish":
			var refund: Dictionary = r.get("refund", {})
			if r["object"] != null:
				var name: String = r["object"].display_name()
				world.remove_object(r["object"])
				text = "%s taken down." % name
			elif r.get("foundation", false):
				world.remove_foundation(r["segs"][0])
				text = "Foundation taken up."
			elif r.get("opening", false):
				world.cut_opening(r["segs"][0], true)
				text = "Wall section knocked out."
			else:
				world.demolish_wall(r["segs"][0])
				text = "Wall taken down."
			if not refund.is_empty() and state != null and not state.cheats.get("unlimited", false):
				var got := {}
				for k in refund:
					var n := state.inventory.add(k, refund[k])
					if n > 0:
						got[k] = n
				if not got.is_empty():
					text += " Got back %s." % BuildPieces.cost_text(got)
			Sfx.play("build/demolish", at)
	_eval_key = ""
	message.emit(text, true)
	changed.emit()
	return true


func _where(r: Dictionary) -> Vector3:
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
	var style := "iron" if _mat() == "iron" else ""
	match id:
		"wall", "stone_wall", "barricade", "iron_barricade", "door", "iron_door", "doorway", "foundation":
			for s in r["segs"]:
				var bad: bool = not r["ok"] and (r.get("bad", []).has(s) or not r.has("bad"))
				var c := HouseWorld.seg_center(s)
				var yaw := 0.0 if s.x == 0 else PI * 0.5
				var type := "wall_ghost"
				var size := Vector3(1.0, 2.6, 0.2)
				match id:
					"stone_wall":
						size = Vector3(1.0, 2.6, 0.3)
					"foundation":
						size = Vector3(1.0, 0.06, 0.98)
					"barricade", "iron_barricade":
						type = "barricade"
						size = WorldObject.DEFS["barricade"]["size"]
						yaw = WorldObject.YAW[world.seg_rot(s)]
					"door", "iron_door":
						type = "door"
						size = WorldObject.DEFS["door"]["size"]
						yaw = WorldObject.YAW[world.seg_rot(s)]
					"doorway":
						size = Vector3(1.0, 2.1, 0.42)
				items.append([type, size, Vector3(c.x, 0, c.y), yaw, GHOST_BAD if bad else col_ok, style])
		"crate", "rain_collector", "workbench":
			if r["pos"] != Vector2.INF:
				items.append([_kind(), WorldObject.DEFS[_kind()]["size"], Vector3(r["pos"].x, 0, r["pos"].y), WorldObject.YAW[rot], col_ok if r["ok"] else GHOST_BAD, ""])
		_:
			var o: WorldObject = r["object"]
			if o != null:
				var s: Vector3 = WorldObject.DEFS[o.kind]["size"]
				items.append(["wall_ghost", s + Vector3(0.12, 0.08, 0.12), Vector3(o.pos.x, 0, o.pos.y), WorldObject.YAW[o.rot], col_ok if r["ok"] else GHOST_BAD, ""])
			elif r.get("foundation", false):
				var s: Vector3i = r["segs"][0]
				var c := HouseWorld.seg_center(s)
				items.append(["wall_ghost", Vector3(1.04, 0.1, 1.02), Vector3(c.x, 0, c.y), 0.0 if s.x == 0 else PI * 0.5, col_ok if r["ok"] else GHOST_BAD, ""])
			elif not r["segs"].is_empty():
				var s: Vector3i = r["segs"][0]
				var c := HouseWorld.seg_center(s)
				items.append(["wall_ghost", Vector3(1.04, 2.68, 0.44), Vector3(c.x, 0, c.y), 0.0 if s.x == 0 else PI * 0.5, col_ok if r["ok"] else GHOST_BAD, ""])
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
		g.position = items[k][2] + Vector3(0, 0.005, 0)
		g.rotation.y = items[k][3]
		var m := _ghost_material(items[k][4])
		for gi in g.find_children("*", "GeometryInstance3D", true, false):
			(gi as GeometryInstance3D).material_override = m


func _refresh_palette() -> void:
	if palette == null:
		return
	var p: Dictionary = BuildPieces.LIST[piece]
	var cost: Dictionary = last_eval.get("cost", p["cost"])
	var cost_txt := ""
	match tool():
		"place":
			cost_txt = BuildPieces.cost_text(p["cost"]) + (" per metre" if p.get("per_m", false) and piece_id() != "foundation" else " per tile" if piece_id() == "foundation" else "")
			var n: int = last_eval.get("segs", []).size()
			if n > 1:
				cost_txt += ("  ·  %d tiles: %s" if piece_id() == "foundation" else "  ·  run %d m: %s") % [n, BuildPieces.cost_text(cost)]
		"repair":
			cost_txt = BuildPieces.cost_text(cost) if not cost.is_empty() else "paid in the damaged material"
		"upgrade":
			cost_txt = BuildPieces.cost_text(p["cost"]) + " per section"
		"demolish":
			var rf: Dictionary = last_eval.get("refund", {})
			cost_txt = "refund %s" % BuildPieces.cost_text(rf) if not rf.is_empty() else "free"
	var mats := "no inventory"
	if state != null:
		var inv := state.inventory
		mats = "Planks %d · Stone %d · Iron %d · Nails %d · Scrap %d" % [inv.count("wood"), inv.count("stone"), inv.count("iron"), inv.count("nails"), inv.count("scrap")]
		if state.cheats.get("unlimited", false):
			mats += "  (unlimited)"
	var status := "Ready: click to %s." % ("build" if tool() == "place" else tool())
	if not last_eval.is_empty() and not last_eval["ok"]:
		status = last_eval["reason"]
	elif last_eval.get("opening", false):
		status = "Ready: knocks out this original wall section."
	palette.show_state(piece, p["name"], cost_txt, mats, status, last_eval.get("ok", true), p["hint"])
