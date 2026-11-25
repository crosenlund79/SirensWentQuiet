extends Node
## Exp 007 (O): observation holes in the game (`game.holes`). The rules are
## HoleRules (src/holes/hole_rules.gd); this node does the player's side:
##
##   drill     the hand drill on the quick bar (LMB, game_hotbar.gd "drill"):
##             the aimed wooden wall, door, barricade or boards within reach.
##             Eli stands and drills for a few game minutes (HoleRules.MINUTES;
##             the clock runs on), with a sound (build/drill, else the hammer)
##             and moderate noise (Noise.emit, agent N, when that class exists).
##             Taking a hit interrupts it.
##   holes     every open hole has an invisible [E] spot in its world's
##             `hole_spots` (HouseWorld.interactables lists them): "[E] Look
##             through the hole · [F] Cover it". A door's peephole sits 0.3 m
##             off its centre so E at the centre still opens the door.
##   look      a narrow inspection view (`start_peek`): a camera just past the
##             hole looking away from Eli, 32 degrees wide, aimed a little with
##             the mouse (+/- 20 degrees, +/- 10 up and down), behind a keyhole mask
##             (peek_view.gd). The cutaway is off while it lasts, enemies inside
##             the view cone are shown, and the room visibility (agent N) is
##             asked to reveal only that cone (`visibility.set_peek(origin,
##             dir, half_angle_deg, range)` / `clear_peek()`, if it has them).
##             E or Esc stops; a hit, death or a panel stop it too. Time runs.
##   cover     F at the hole (or in the view): a plank, or two nails, fills
##             it (wall voxels from the design; an object's flag). The Repair
##             tool fills it too, and demolishing the wall removes it.
##   enemies   an enemy within 3 m of an open hole may notice it (a chance
##             every 2 s, higher while Eli is looking through it): it is sent to
##             investigate (`investigate(p)` if the enemy has it, else a low
##             Noise at the hole), and if it stands right at the hole it pokes
##             at it once (one blow on that spot, through world.enemy_strike).
##   F10       "Overview & holes" (dev_menu.gd): a drill, a hole in the
##             nearest wall now, the list of holes.

const Spot := preload("res://src/holes/hole_spot.gd")
const Peek := preload("res://src/holes/peek_view.gd")

const REACH := 1.4                     ## m from Eli to the hole's plan point
const AIM_SNAP := 0.7                  ## m from the aim point to a door / barricade / boards footprint
const PEEK_FOV := 32.0
const PEEK_YAW := 20.0                 ## degrees the mouse turns the view either way
const PEEK_PITCH := 10.0
const PEEK_RANGE := 24.0
const NOTICE_RANGE := 3.0
const NOTICE_EVERY := 2.0              ## s
const NOTICE_CHANCE := 0.12
const NOTICE_CHANCE_PEEK := 0.35
const POKE_RANGE := 1.4
const POKE_COOLDOWN := 20.0            ## s per hole

var game: Node                         ## SurvivalGame
var drilling := {}                     ## {} or {"world", "rec", "t0", "real", "minutes", "hp", "pos"}
var peeking := {}                      ## {} or {"world", "rec", "cam", "view", "yaw", "hp"}
var noticed := 0                       ## enemies that noticed a hole (tests, F10)
var pokes := 0
var last_text := ""
var rng := RandomNumberGenerator.new()

var _refresh_t := 0.0
var _notice_t := 0.0
var _sound_t := 0.0
var _poke_cd := {}                     ## hole key -> seconds
var _noise_script: Variant = false     ## false = not looked up yet; null = no Noise class


func setup(g: Node) -> void:
	game = g
	process_mode = Node.PROCESS_MODE_ALWAYS     # the look-through view's keys arrive before the game's
	process_priority = 100                      # after the game's and the levels' view updates
	rng.seed = int(g.state.run.get("seed", 0)) * 13 + 7 if g.state != null else 7
	refresh()


# --- worlds and spots --------------------------------------------------------------------

## The worlds holes can be in: the ground floor (or the site) and every storey.
func worlds() -> Array:
	var out: Array = []
	if game.world != null:
		out.append(game.world)
	var lv: Node = game.get("levels")
	if lv != null and lv.get("worlds") is Dictionary:
		for s in lv.worlds:
			if lv.worlds[s] != null and is_instance_valid(lv.worlds[s]):
				out.append(lv.worlds[s])
	return out


## Every open hole as [world, record].
func all_holes() -> Array:
	var out := []
	for w in worlds():
		for rec in HoleRules.holes_of(w):
			out.append([w, rec])
	return out


func count() -> int:
	return all_holes().size()


func busy() -> bool:
	return not drilling.is_empty() or not peeking.is_empty()


## Drops closed holes, (re)builds the [E] spots and the peephole marks on objects.
func refresh() -> void:
	for w in worlds():
		if w.get("holes") == null:
			continue
		HoleRules.prune(w)
		var spots: Array = w.hole_spots
		var recs := HoleRules.holes_of(w)
		var keep := []
		for sp in spots:
			if is_instance_valid(sp) and recs.has(sp.rec):
				keep.append(sp)
			elif is_instance_valid(sp):
				sp.queue_free()
		var have := keep.map(func(sp): return sp.rec)
		for rec in recs:
			if not have.has(rec):
				var sp := Spot.new()
				sp.name = "HoleSpot"
				sp.helper = self
				sp.world = w
				sp.rec = rec
				w.add_child(sp)
				keep.append(sp)
		for sp in keep:
			sp.global_position = HoleRules.point(w, sp.rec) * Vector3(1, 0, 1) + Vector3(0, HoleRules.floor_y(w), 0)
		w.hole_spots = keep
		for rec in recs:
			if not HoleRules.is_wall(rec):
				_mark_object(w, rec)


## A dark plug on a drilled door, barricade or boards (re-added when its visual is rebuilt).
func _mark_object(w: HouseWorld, rec: Dictionary) -> void:
	var o := HoleRules.object_of(w, rec)
	if o == null or o.visual == null or not is_instance_valid(o.visual):
		return
	var host: Node3D = o.visual.find_child("Leaf", true, false) as Node3D
	if host == null:
		host = o.visual
	if host.get_node_or_null("Peephole") != null:
		return
	var mi := MeshInstance3D.new()
	mi.name = "Peephole"
	var box := BoxMesh.new()
	box.size = Vector3(0.1, 0.2, o.size3().z + 0.05)
	mi.mesh = box
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.03, 0.025, 0.02)
	m.roughness = 1.0
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(mi)
	var pivot := o.visual.get_parent() as Node3D       # the object's turned pivot (its front is local -Z)
	var p := HoleRules.point(w, rec)
	mi.global_position = p + pivot.global_transform.basis * Vector3(0, 0, -float(WorldObject.DEFS[o.kind].get("out", 0.0)))
	mi.global_rotation = Vector3(0, pivot.global_rotation.y, 0)


# --- drilling ----------------------------------------------------------------------------

## LMB with the drill in hand (game_hotbar.gd). Returns {"text", "kind"}.
func use_drill() -> Dictionary:
	if busy():
		return {"text": "", "kind": "info"}
	if game.state.inventory.count("drill") <= 0:
		return {"text": "You need a drill.", "kind": "warn"}
	var w := _active_world()
	var t := find_target(w, game.player.plan_pos(), game.player.aim_point)
	if str(t.get("reason", "")) != "":
		Sfx.play("build/invalid")
		return {"text": t["reason"], "kind": "warn"}
	start_drill(w, t["rec"])
	return {"text": "Drilling a small hole… (%d minutes)" % roundi(HoleRules.minutes_for(t["rec"])), "kind": "info"}


func _active_world() -> HouseWorld:
	var lv: Node = game.get("levels")
	if lv != null and lv.has_method("active_world"):
		return lv.active_world()
	return game.world


## What the drill would go into from plan point `from` aiming at `aim`:
## {"rec": record} or {"reason": why not}.
func find_target(w: HouseWorld, from: Vector2, aim: Vector3) -> Dictionary:
	var a := Vector2(aim.x, aim.z)
	if from.distance_to(a) > 2.2:
		a = from + (a - from).normalized() * 0.8 if a != from else from
	# a door, barricade or boards being aimed at
	var best: WorldObject = null
	var best_d := AIM_SNAP
	for o in w.objects:
		if not is_instance_valid(o) or not (o.kind in HoleRules.OBJECT_KINDS) or from.distance_to(o.pos) > REACH + 0.4:
			continue
		var r := o.footprint()
		var d := a.distance_to(a.clamp(r.position, r.end))
		if d < best_d:
			best = o
			best_d = d
	if best != null:
		var why := HoleRules.object_reason(w, best)
		if why != "":
			return {"reason": why}
		var side := (a - best.pos).dot(HoleRules.along_dir(best.seg.x))
		return {"rec": HoleRules.object_record(best, side)}
	# else the nearest wall section within reach
	var bs := Vector3i(-1, 0, 0)
	var bd := INF
	for s in w.sections:
		var c := HouseWorld.seg_center(s)
		if from.distance_to(c) > REACH + 0.6:
			continue
		var r := HouseWorld.seg_rect(s, 0.15)
		var d := a.distance_to(a.clamp(r.position, r.end)) + 0.3 * from.distance_to(from.clamp(r.position, r.end))
		if d < bd:
			bd = d
			bs = s
	if bs.x < 0:
		return {"reason": "Get close to a wall, a door or window boards to drill."}
	var along := a.x if bs.x == 0 else a.y
	along = clampf(along, bs.z + HoleRules.MARGIN, bs.z + 1.0 - HoleRules.MARGIN)
	var p := Vector2(along, bs.y) if bs.x == 0 else Vector2(bs.y, along)
	if from.distance_to(p) > REACH + 0.3:
		return {"reason": "Get closer to the wall."}
	var why := HoleRules.wall_reason(w, bs, along)
	if why != "":
		return {"reason": why}
	return {"rec": HoleRules.wall_record(bs, along)}


## Starts drilling `rec` (checked) in world w: Eli stands still for its minutes.
func start_drill(w: HouseWorld, rec: Dictionary) -> void:
	var at := HoleRules.point(w, rec)
	drilling = {"world": w, "rec": rec, "t0": float(game.state.total_minutes), "real": 0.0,
		"minutes": HoleRules.minutes_for(rec), "hp": float(game.state.health), "pos": at}
	game.player.input_enabled = false
	game.player.velocity = Vector3.ZERO
	_sound_t = 0.0
	emit_noise(at, HoleRules.NOISE_LEVEL, "drill")


func _tick_drill(delta: float) -> void:
	if drilling.is_empty():
		return
	var s: GameState = game.state
	if s.dead or float(s.health) < float(drilling["hp"]) - 0.5:
		cancel_drill("Drilling interrupted." if not s.dead else "")
		return
	if game.debug_modal() != "":
		return                          # paused panels: the clock stands still too
	drilling["real"] = float(drilling["real"]) + delta
	_sound_t -= delta
	if _sound_t <= 0.0:
		_sound_t = 1.1
		Sfx.play_first(["build/drill", "build/hammer"], drilling["pos"])
		if game.player != null and game.player.rig != null:
			game.player.rig.use_t = 1.0
	var done := maxf(float(s.total_minutes) - float(drilling["t0"]), float(drilling["real"]))
	if done >= float(drilling["minutes"]):
		finish_drill()


## Makes the hole now (the end of the drilling time, or F10).
func finish_drill() -> String:
	if drilling.is_empty():
		return ""
	var w: HouseWorld = drilling["world"]
	var rec: Dictionary = drilling["rec"]
	drilling = {}
	game.player.input_enabled = true
	var text := make_hole(w, rec)
	game.toast(text, "good")
	return text


func cancel_drill(text := "") -> void:
	if drilling.is_empty():
		return
	drilling = {}
	if game.player != null and not game.state.dead:
		game.player.input_enabled = true
	if text != "":
		game.toast(text, "warn")


## Records and carves the hole (no time, no checks beyond the record's own).
func make_hole(w: HouseWorld, rec: Dictionary) -> String:
	HoleRules.make(w, rec)
	refresh()
	last_text = "A small hole at eye height. [E] there to look through."
	return last_text


# --- looking through ----------------------------------------------------------------------

func start_peek(w: HouseWorld, rec: Dictionary) -> bool:
	if busy() or game.debug_modal() != "" or game.state.dead:
		return false
	if game.build != null and game.build.active:
		return false
	if not HoleRules.is_open(w, rec):
		refresh()
		return false
	var o := HoleRules.object_of(w, rec)
	if o != null and o.kind == "door" and o.open:
		game.toast("The door is open.", "info")
		return false
	var at := HoleRules.point(w, rec)
	var n := HoleRules.normal(w, rec)
	var side: float = (game.player.plan_pos() - Vector2(at.x, at.z)).dot(n)
	var d := -n if side >= 0.0 else n            # away from Eli
	var depth := 0.26
	if o != null:
		depth = 0.42 if o.kind == "boards" else 0.3
	var cam := Camera3D.new()
	cam.name = "PeekCamera"
	cam.fov = PEEK_FOV
	cam.near = 0.03
	cam.far = 80.0
	cam.cull_mask = game.camera.cull_mask
	game.add_child(cam)
	cam.global_position = at + Vector3(d.x, 0.0, d.y) * depth
	var yaw := atan2(-d.x, -d.y)
	cam.rotation = Vector3(0.0, yaw, 0.0)
	cam.make_current()
	var view := Peek.new()
	view.name = "PeekView"
	add_child(view)
	peeking = {"world": w, "rec": rec, "cam": cam, "view": view, "yaw": yaw, "look": Vector2.ZERO, "hp": float(game.state.health), "dir": d}
	game.player.input_enabled = false
	game.player.velocity = Vector3.ZERO
	_set_vis_peek(true)
	_clear_cut()
	last_text = "Looking through the hole."
	return true


func stop_peek(text := "") -> void:
	if peeking.is_empty():
		return
	var cam: Camera3D = peeking["cam"]
	var view: Node = peeking["view"]
	peeking = {}
	if is_instance_valid(cam):
		cam.queue_free()
	if is_instance_valid(view):
		view.queue_free()
	if game.camera != null:
		game.camera.make_current()
	if game.player != null and not game.state.dead:
		game.player.input_enabled = true
	_set_vis_peek(false)
	if text != "":
		game.toast(text, "warn")


func _tick_peek() -> void:
	if peeking.is_empty():
		return
	var s: GameState = game.state
	if s.dead:
		stop_peek()
		return
	if float(s.health) < float(peeking["hp"]) - 0.5:
		stop_peek("You pull back from the hole.")
		return
	if game.debug_modal() not in ["", "pause"]:
		stop_peek()
		return
	if not HoleRules.is_open(peeking["world"], peeking["rec"]):
		stop_peek("The hole is gone.")
		refresh()
		return
	var cam: Camera3D = peeking["cam"]
	var off := Vector2.ZERO
	var vp := get_viewport()
	if vp != null and game.aim_with_mouse:
		var size := vp.get_visible_rect().size
		if size.x > 0.0 and size.y > 0.0:
			off = ((vp.get_mouse_position() - size * 0.5) / (size * 0.5)).clamp(Vector2(-1, -1), Vector2(1, 1))
	var look: Vector2 = (peeking["look"] as Vector2).lerp(off, 0.25)
	peeking["look"] = look
	cam.rotation = Vector3(deg_to_rad(-look.y * PEEK_PITCH), float(peeking["yaw"]) - deg_to_rad(look.x * PEEK_YAW), 0.0)
	_clear_cut()
	_show_enemies_in_view(cam)


## No cutaway while looking through (the hole's own wall would be cut open).
func _clear_cut() -> void:
	for w in worlds():
		if w.has_method("set_cut_view"):
			w.set_cut_view(Vector3(0, -100, 0), Vector3.UP, 0.0, 0.45)


func _show_enemies_in_view(cam: Camera3D) -> void:
	var r: Node = game.get("roster")
	if r == null:
		return
	var fwd := -cam.global_transform.basis.z
	var half := deg_to_rad(PEEK_FOV * 0.5 + 6.0)
	for e in r.get("enemies"):
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		var to: Vector3 = (e as Node3D).global_position + Vector3(0, 1.0, 0) - cam.global_position
		if to.length() < PEEK_RANGE and to.normalized().dot(fwd) > cos(half):
			(e as Node3D).visible = true


## Agent N's room visibility, if present: reveal only the view cone.
func _set_vis_peek(on: bool) -> void:
	var vis: Variant = game.get("visibility")
	if not (vis is Object) or not is_instance_valid(vis):
		return
	if on and vis.has_method("set_peek") and not peeking.is_empty():
		var cam: Camera3D = peeking["cam"]
		vis.set_peek(cam.global_position, -cam.global_transform.basis.z, PEEK_FOV * 0.5 + PEEK_YAW, PEEK_RANGE)
	elif not on and vis.has_method("clear_peek"):
		vis.clear_peek()


# --- covering -----------------------------------------------------------------------------

## Fills the hole for a plank (or two nails). Returns the feedback.
func cover(w: HouseWorld, rec: Dictionary) -> String:
	if not HoleRules.holes_of(w).has(rec):
		return ""
	var paid := false
	for cost in HoleRules.COVER_COSTS:
		if _can_pay(cost):
			paid = _pay(cost)
			if paid:
				break
	if not paid:
		last_text = "Covering the hole takes a plank or two nails."
		game.toast(last_text, "warn")
		return last_text
	if not peeking.is_empty() and peeking["rec"] == rec:
		stop_peek()
	HoleRules.fill(w, rec)
	refresh()
	Sfx.play_first(["build/place", "build/hammer"], HoleRules.point(w, rec))
	emit_noise(HoleRules.point(w, rec), 1.0, "build")
	last_text = "Hole covered."
	game.toast(last_text, "good")
	return last_text


func _can_pay(cost: Dictionary) -> bool:
	var b: Node = game.get("build")
	if b != null and b.has_method("state_can_pay"):
		return b.state_can_pay(cost)
	return game.state.can_pay(cost)


func _pay(cost: Dictionary) -> bool:
	var b: Node = game.get("build")
	if b != null and b.has_method("pay_cost"):
		return b.pay_cost(cost)
	return game.state.pay(cost)


## The hole the game's [E] focus points at (a HoleSpot), or null.
func _focused_spot() -> Node:
	var f: Variant = game.get("_focus")
	if f is Node and is_instance_valid(f) and f.get_script() == Spot:
		return f
	return null


# --- enemies -------------------------------------------------------------------------------

func _tick_notice(delta: float) -> void:
	for k in _poke_cd.keys():
		_poke_cd[k] -= delta
		if _poke_cd[k] <= 0.0:
			_poke_cd.erase(k)
	_notice_t -= delta
	if _notice_t > 0.0:
		return
	_notice_t = NOTICE_EVERY
	var r: Node = game.get("roster")
	if r == null:
		return
	for h in all_holes():
		var w: HouseWorld = h[0]
		var rec: Dictionary = h[1]
		var at := HoleRules.point(w, rec)
		var p := Vector2(at.x, at.z)
		var storey := Levels.storey_at(HoleRules.floor_y(w) + 0.1)
		for e in r.get("enemies"):
			if not is_instance_valid(e) or not (e is AIEnemy) or not (e as AIEnemy).alive or (e as AIEnemy).retreating:
				continue
			var a: AIEnemy = e
			if a.storey != storey or a.plan_pos().distance_to(p) > NOTICE_RANGE:
				continue
			var looking: bool = not peeking.is_empty() and peeking["rec"] == rec
			if rng.randf() < (NOTICE_CHANCE_PEEK if looking else NOTICE_CHANCE):
				notice(a, w, rec, looking)


## Enemy `a` noticed the hole: it investigates; right at the hole it pokes at it.
func notice(a: AIEnemy, w: HouseWorld, rec: Dictionary, looking := false) -> void:
	noticed += 1
	var at := HoleRules.point(w, rec)
	var p := Vector2(at.x, at.z)
	if a.has_method("investigate"):
		a.call("investigate", p)
	else:
		emit_noise(at, 1.0, "hole")
	var key := str(rec.hash())
	if a.plan_pos().distance_to(p) <= POKE_RANGE and not _poke_cd.has(key):
		_poke_cd[key] = POKE_COOLDOWN
		pokes += 1
		w.enemy_strike(a.global_position, p + (a.plan_pos() - p).normalized() * -0.05, 0.5)
	if looking:
		game.toast("Something on the other side noticed the hole!", "bad")


# --- noise (agent N) ---------------------------------------------------------------------

## Noise.emit(game, pos, level, source) when the Noise class exists; else nothing.
func emit_noise(pos: Vector3, level: float, source: String) -> bool:
	if typeof(_noise_script) == TYPE_BOOL:
		_noise_script = null
		for c in ProjectSettings.get_global_class_list():
			if str(c.get("class", "")) == "Noise":
				_noise_script = load(str(c.get("path", "")))
	if _noise_script == null:
		return false
	var names: Array = (_noise_script as Script).get_script_method_list().map(func(m): return str(m.get("name", "")))
	if not names.has("emit"):
		return false
	(_noise_script as Object).call("emit", game, pos, level, source)
	return true


# --- frame and input ----------------------------------------------------------------------

func _process(delta: float) -> void:
	if game == null or not game.get("_ok"):
		return
	var paused := get_tree() != null and get_tree().paused
	if not paused:
		_tick_drill(delta)
		_tick_notice(delta)
	_tick_peek()
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = 0.5
		refresh()


func _input(event: InputEvent) -> void:
	if peeking.is_empty() or not (event is InputEventKey or event is InputEventMouseButton):
		return
	if event.is_action_pressed("dev_menu"):
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not event.is_echo():
		var k: int = (event as InputEventKey).physical_keycode
		if event.is_action_pressed("pause") or event.is_action_pressed("interact"):
			stop_peek()
		elif k == KEY_F:
			cover(peeking["world"], peeking["rec"])
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not (event as InputEventKey).pressed or event.is_echo():
		return
	if (event as InputEventKey).physical_keycode != KEY_F or busy() or game.debug_modal() != "":
		return
	if game.build != null and game.build.active:
		return
	var sp := _focused_spot()
	if sp != null:
		cover(sp.world, sp.rec)
		get_viewport().set_input_as_handled()


# --- developer tools (F10 "Overview & holes") ----------------------------------------------

func dev_give_drill() -> String:
	var n: int = game.state.inventory.add("drill", 1)
	return "Dev: a hand drill (on the quick bar; LMB at a wooden wall or door)." if n > 0 else "Dev: you already carry a drill."


## A hole in the nearest drillable wall (or door, boards, barricade) around Eli, now.
func dev_hole_here() -> String:
	var w := _active_world()
	var from: Vector2 = game.player.plan_pos()
	var tries: Array = [game.player.aim_point]
	for k in 16:
		var ang := TAU * float(k) / 16.0
		tries.append(Vector3(from.x + cos(ang) * 0.9, 1.5, from.y + sin(ang) * 0.9))
	var first_reason := ""
	for aim in tries:
		var t := find_target(w, from, aim)
		if t.has("rec"):
			return "Dev: " + make_hole(w, t["rec"]) + " (" + HoleRules.describe(w, t["rec"]) + ")"
		if first_reason == "":
			first_reason = str(t.get("reason", ""))
	return "Dev: no drillable wall here (%s)" % first_reason


func dev_list_holes() -> String:
	var hs := all_holes()
	if hs.is_empty():
		return "No observation holes."
	var parts := PackedStringArray()
	for h in hs:
		parts.append("%s: %s" % [Levels.number(Levels.storey_at(HoleRules.floor_y(h[0]) + 0.1)), HoleRules.describe(h[0], h[1])])
	return "%d hole%s · %s" % [hs.size(), "" if hs.size() == 1 else "s", " · ".join(parts)]


func info() -> String:
	return "Holes %d · drilling %s · looking %s · noticed %d (pokes %d)" % [count(),
		"yes" if not drilling.is_empty() else "no", "yes" if not peeking.is_empty() else "no", noticed, pokes]
