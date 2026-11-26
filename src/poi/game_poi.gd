extends Node
## Experiment 007 (P): the POI helper of the survival game in site mode
## (`game.poi`; PoiSite.make_helper creates it). It owns the visit: the rules
## of the PoiWorld's spots (searching, forcing locks, chopping, pickups, the
## car's boot, the exits), the take-only loot panel, the pack limit, the
## encounters and their awareness, noise, the POI's F10 tools and the visit's
## save state (in GameState.region.poi, see PoiState).
##
## Player's view: walk up to a shelf, fridge, desk or box and press E:
## "Searching the shelf... 40 %" (stay close: walking away or getting hit
## stops it), a few minutes of game time pass, a quiet rustle (or a loud one
## for crates and forced locks) is heard, then the panel shows what was in it
## (maybe nothing) and you take what you want, as far as your pack allows
## ("Pack: 18 / 30"; a backpack carries more). Locked doors and crates need a
## crowbar ("[E] Force ..."), dark rooms a flashlight. Fallen trees: "[E]
## Chop wood" (planks, loud, 20 minutes). Loose items: "[E] Pick up". The car
## (only when you drove): its boot holds more. "[E] Leave for home" at the
## trail posts with the flares, whenever you want.
##
## Exp 008 (L): searchable things show a small marker when Eli is near and
## can see them (PoiSpot.set_marker: not searched, locked, dark, something
## left, searched), and the prompt always says what a container holds now
## ("[E] Take from the shelf · 2 cans of food", "Shelf: searched · empty").
## The HUD shows "Pack 18 / 30" (and "· Boot 12 / 60" when Eli drove) while
## away; a take that fills the pack says so. One-of-a-kind items Eli takes or
## stows are noted (PoiState.note_found) so they never turn up again.
##
## Enemies (PoiWorld.encounter_plan by the visit's danger): ordinary roster
## enemies that start unaware: hidden ones wait in a room, wanderers walk
## about, arrivals come in from the fog after a few minutes (sooner after a
## loud noise). They notice you when you come close, when they see you
## (voxel line of sight), when they're hurt; noise draws them to look. Once
## hunting they act as at home, and lose interest when you get well away.
## Nothing has to be cleared: every exit works at any time.

signal leave_requested(poi_id: String)
signal searched(spot_id: String, items: Dictionary)

const ACTION_REACH := 2.3
const TICK := 0.2
const NOTICE_TIME := 0.9
const SEE_RANGE := 9.0
const SEE_RANGE_IDLE := 6.0
const LOSE_RANGE := 18.0
const LOSE_TIME := 10.0
const CHOP_SECS := 3.0
const CHOP_MINUTES := 20
const FORCE_SECS := 2.6
const FORCE_MINUTES := 5
const NOISE_RADIUS := 4.5          ## m per noise level (my own hearing; agent N's Noise is called too)
const MARK_RANGE := 4.5            ## Exp 008 (L): m; markers show this close (and in sight)
const PROMPT_KINDS := 2            ## Exp 008 (L): item kinds named in a partly taken container's prompt

var game: Node
var world: PoiWorld
var state: GameState
var poi_id := ""
var record := {}
var pack := {}                     ## item -> n taken at this POI (the live visit record)
var cargo := {}                    ## the car's boot (the live visit record)
var has_car := false
var panel: PoiLootPanel
var open_spot: PoiSpot
var plan := []                     ## the encounter plan
var pending := []                  ## arrivals not yet here
var watch := []                    ## {"e", "mode", "state", "t", "notice", "lost"}
var last_noise := {}               ## the last noise heard (tests, F10)
var finished := {}                 ## finish() result once done

var _action := {}                  ## {"what", "spot", "door", "t", "dur", "minutes", "noise", "health"}
var _clock := 0.0
var _tick := 0.0
var _started := false
var _rng := RandomNumberGenerator.new()
var _seen_toast := false
var _full_said := false            ## Exp 008 (L): "your pack is full" said (until it has room again)
var _ui_tick := 0.0

static var _noise_script: Variant = false     ## agent N's NoiseEvent script (looked up once; false = not yet)


func setup(g: Node) -> void:
	game = g
	name = "Poi"
	panel = PoiLootPanel.new()
	panel.name = "PoiLootPanel"
	add_child(panel)
	panel.closed.connect(_on_panel_closed)
	_bind_world()


## Binds to the game's PoiWorld and starts (or continues) the visit.
func _bind_world() -> bool:
	if world != null:
		return true
	var w: Variant = game.get("world") if game != null else null
	var s: Variant = game.get("state") if game != null else null
	if not (w is PoiWorld) or not (s is GameState):
		return false
	world = w
	state = s
	poi_id = world.poi_id
	has_car = world.has_car
	record = PoiState.begin_visit(state, poi_id, has_car)
	if PoiState.in_visit(record):
		pack = record["visit"]["pack"]
		cargo = record["visit"]["cargo"]
		has_car = has_car or record["visit"]["car"]
	world.state = state
	world.record = record
	world.helper = self
	world.apply_record()
	_rng.seed = PoiState._seed(state, [poi_id, "helper", int(record.get("visits", 0))])
	var c: Variant = game.get("combat")
	if c is Object and is_instance_valid(c):
		var wh: Variant = c.get("weapons")
		if wh is Object and is_instance_valid(wh) and wh.has_signal("fired") and not wh.fired.is_connected(_on_fired):
			wh.fired.connect(_on_fired)
	return true


func _process(delta: float) -> void:
	if not _bind_world():
		return
	if not _started:
		_started = true
		_toast(PoiDefs.arrival_text(poi_id), "info")
		_start_encounters()
	_clock += delta
	_step_action(delta)
	_tick_loot_ui(delta)              # Exp 008 (L): markers, the HUD's pack line
	for p in pending.duplicate():
		if _clock >= float(p["when"]) and _roster() != null:
			pending.erase(p)
			_spawn(p)
			_toast("Something is moving out in the fog.", "warn")
	_tick -= delta
	if _tick <= 0.0:
		_tick = TICK
		_think(TICK)


# --- prompts ----------------------------------------------------------------------------

func prompt_for(s: PoiSpot) -> String:
	if _action.get("spot") == s:
		return "%s… %d %%" % [_action_label(), int(100.0 * float(_action["t"]) / float(_action["dur"]))]
	match s.kind:
		"container":
			var box := PoiState.container(record, s.id)
			if box["searched"]:
				if (box["items"] as Dictionary).is_empty():
					return "%s: searched · empty" % s.label().capitalize()
				return "[E] Take from the %s · %s" % [s.label(), left_text(box["items"])]
			var needs := str(s.data.get("needs", ""))
			if needs == "crowbar" and not record["forced"].has(s.id):
				return "[E] Force the %s open (crowbar)" % s.label() if owns("crowbar") else "The %s is locked · a crowbar would open it" % s.label()
			if needs == "flashlight" and not owns("flashlight"):
				return "The %s is in the dark · you need a flashlight" % s.label()
			return "[E] Search the %s" % s.label()
		"pickup":
			if record["taken"].has(s.id):
				return ""
			var what := ExpeditionData.count_text(str(s.data["item"]), int(s.data["n"]))
			if PoiState.room_for(str(s.data["item"]), PoiState.pack_load(state, pack), PoiState.pack_cap(state)) < int(s.data["n"]):
				return "[E] Pick up %s · no room in your pack" % what
			return "[E] Pick up %s" % what
		"wood":
			var left := chops_left(s)
			return "[E] Chop wood (fallen tree · %d left)" % left if left > 0 else ""
		"exit":
			return "[E] Leave for home"
		"cargo":
			return "[E] Car (cargo) · boot %s / %s" % [PoiState._num(PoiState.load_of(cargo)), PoiState._num(PoiState.CARGO_CAP)]
	return ""


func door_prompt(d: PoiDoor) -> String:
	if _action.get("door") == d:
		return "%s… %d %%" % [_action_label(), int(100.0 * float(_action["t"]) / float(_action["dur"]))]
	return "[E] Force the door open (crowbar)" if owns("crowbar") else "Locked door · a crowbar would open it"


## Exp 008 (L): what a partly taken container still holds, for its prompt:
## "2 cans of food, 1 bottle of water" (+ "and 3 more kinds").
static func left_text(items: Dictionary) -> String:
	var parts := []
	var more := 0
	for id in Items.DEFS:
		var n := int(items.get(id, 0))
		if n <= 0:
			continue
		if parts.size() < PROMPT_KINDS:
			parts.append(ExpeditionData.count_text(id, n))
		else:
			more += 1
	var t := ", ".join(parts)
	if more > 0:
		t += " and %d more %s" % [more, "kind" if more == 1 else "kinds"]
	return t


## Exp 008 (L): is the timed action on this spot or door (the finder keeps its progress prompt)?
func busy_with(o: Object) -> bool:
	return not _action.is_empty() and o != null and (_action.get("spot") == o or _action.get("door") == o)


func _action_label() -> String:
	match str(_action.get("what", "")):
		"force":
			return "Forcing it open"
		"chop":
			return "Chopping"
	var s: Variant = _action.get("spot")
	return "Searching the %s" % (s as PoiSpot).label() if s is PoiSpot else "Searching"


## Owned = carried (the household pool goes with Eli).
func owns(item: String) -> bool:
	return state != null and ExpeditionData.owns(state, item)


func chops_left(s: PoiSpot) -> int:
	return maxi(int(s.data.get("chops", 3)) - int(record["chop"].get(s.id, 0)), 0)


# --- interactions --------------------------------------------------------------------------

func _can_act() -> bool:
	return game != null and str(game.get("_modal")) == "" and not state.dead


func interact_spot(s: PoiSpot) -> void:
	if not _can_act() or world == null:
		return
	if not _action.is_empty():
		if s.kind != "exit":               # Exp 008 (L): leaving always works, mid-search too
			if _action.get("spot") != s:
				_toast("You're busy.", "warn")
			return
		cancel_action("")
	match s.kind:
		"container":
			_use_container(s)
		"pickup":
			pick_up(s)
		"wood":
			if chops_left(s) <= 0:
				return
			if PoiState.room_for("wood", PoiState.pack_load(state, pack), PoiState.pack_cap(state)) <= 0:
				_toast("Your pack is full. Leave something, or use the car.", "warn")
				return
			_begin("chop", s, null, CHOP_SECS, CHOP_MINUTES, 3.0)
			Sfx.play_first(["poi/chop", "build/hammer"], Vector3(s.position.x, 0.6, s.position.z))
		"exit":
			leave()
		"cargo":
			open_cargo()


func _use_container(s: PoiSpot) -> void:
	var box := PoiState.container(record, s.id)
	if box["searched"]:
		if (box["items"] as Dictionary).is_empty():
			_toast("You already searched the %s. Nothing left." % s.label(), "info")
			return
		_open_panel(s)
		return
	var needs := str(s.data.get("needs", ""))
	var force: bool = needs == "crowbar" and not record["forced"].has(s.id)
	if force and not owns("crowbar"):
		_toast("Locked. A crowbar would open it.", "warn")
		return
	if needs == "flashlight" and not owns("flashlight"):
		_toast("Too dark to search in here. You need a flashlight.", "warn")
		return
	var secs: float = float(s.data.get("secs", 1.6)) + (FORCE_SECS if force else 0.0)
	var minutes: float = float(s.data.get("minutes", 6)) + (float(FORCE_MINUTES) if force else 0.0)
	_begin("force" if force else "search", s, null, secs, minutes, 2.0 if force else float(s.data.get("noise", 1)))
	Sfx.play_first(["poi/force", "door/bash"] if force else ["poi/search", "door/open"], Vector3(s.position.x, 1.0, s.position.z))


func force_door(d: PoiDoor) -> void:
	if not _can_act() or not d.locked or not _action.is_empty():
		return
	if not owns("crowbar"):
		_toast("Locked. A crowbar would open it.", "warn")
		return
	_begin("force", null, d, FORCE_SECS, FORCE_MINUTES, 2.0)
	Sfx.play_first(["poi/force", "door/bash"], Vector3(d.pos.x, 1.0, d.pos.y))


func _begin(what: String, s: PoiSpot, d: PoiDoor, secs: float, minutes: float, noise: float) -> void:
	_action = {"what": what, "spot": s, "door": d, "t": 0.0, "dur": maxf(secs, 0.1), "minutes": minutes, "noise": noise,
		"health": state.health}


func _target_pos() -> Vector2:
	var s: Variant = _action.get("spot")
	if s is PoiSpot and is_instance_valid(s):
		return (s as PoiSpot).plan_pos()
	var d: Variant = _action.get("door")
	if d is PoiDoor and is_instance_valid(d):
		return (d as PoiDoor).pos
	return Vector2.INF


func _step_action(delta: float) -> void:
	if _action.is_empty():
		return
	var at := _target_pos()
	var pl: Variant = game.get("player")
	if at == Vector2.INF or not (pl is Node3D) or state.dead:
		cancel_action("")
		return
	if (pl as Node3D).global_position.distance_to(Vector3(at.x, 0, at.y)) > ACTION_REACH:
		cancel_action("You stopped.")
		return
	if state.health < float(_action["health"]) - 0.01:
		cancel_action("Interrupted!")
		return
	_action["t"] = float(_action["t"]) + delta
	if float(_action["t"]) >= float(_action["dur"]):
		complete_action()


func cancel_action(why: String) -> void:
	_action = {}
	if why != "":
		_toast(why, "warn")


## Finishes the running action now (the timer ran out; tests call it).
func complete_action() -> void:
	if _action.is_empty():
		return
	var a := _action
	_action = {}
	_advance(float(a["minutes"]))
	var at := _target_pos_of(a)
	emit_noise(Vector3(at.x, 1.0, at.y), float(a["noise"]), {"chop": "chop", "force": "force"}.get(str(a["what"]), "search"))
	match str(a["what"]):
		"chop":
			_chop_done(a["spot"])
		"force":
			if a["door"] is PoiDoor:
				_door_forced(a["door"])
			else:
				record["forced"][(a["spot"] as PoiSpot).id] = true
				_search_done(a["spot"])
		_:
			_search_done(a["spot"])


func _target_pos_of(a: Dictionary) -> Vector2:
	if a.get("spot") is PoiSpot:
		return (a["spot"] as PoiSpot).plan_pos()
	if a.get("door") is PoiDoor:
		return (a["door"] as PoiDoor).pos
	return Vector2.ZERO


func _search_done(s: PoiSpot) -> void:
	var box := PoiState.container(record, s.id)
	box["searched"] = true
	box["day"] = state.day()
	searched.emit(s.id, (box["items"] as Dictionary).duplicate())
	world._update_reveal()
	if (box["items"] as Dictionary).is_empty():
		_toast("Picked clean. Someone got here first." if s.data.get("picked", false) else "Nothing useful in the %s." % s.label(), "info")
		return
	_open_panel(s)


func _door_forced(d: PoiDoor) -> void:
	d.locked = false
	record["forced"][d.door_id] = true
	if world.objects.has(d) and not d.open:
		world.set_door_open(d, true)
	_toast("The crowbar bites, and the lock gives.", "info")


func _chop_done(s: PoiSpot) -> void:
	record["chop"][s.id] = int(record["chop"].get(s.id, 0)) + 1
	var want := _rng.randi_range(2, 4)
	var room := mini(PoiState.room_for("wood", PoiState.pack_load(state, pack), PoiState.pack_cap(state)), state.inventory.space_for("wood"))
	var k := state.inventory.add("wood", mini(want, room))
	if k > 0:
		pack_add("wood", k)
		_toast("+%d planks · %s" % [k, PoiState.pack_text(state, pack)], "info")
	else:
		_toast("No room for the planks.", "warn")


func pick_up(s: PoiSpot) -> bool:
	if record["taken"].has(s.id):
		return false
	var item := str(s.data["item"])
	var n := int(s.data["n"])
	if PoiState.room_for(item, PoiState.pack_load(state, pack), PoiState.pack_cap(state)) < n:
		_toast(full_text(), "warn")
		return false
	if state.inventory.space_for(item) < n:
		_toast("No room for more %s." % Items.name_of(item).to_lower() if not Items.is_unique(item) else "You already have one.", "warn")
		return false
	var k := state.inventory.add(item, n)
	pack_add(item, k)
	record["taken"][s.id] = state.day()
	world.apply_record()
	Sfx.play_first(["poi/pickup", "ui/click"], Vector3(s.position.x, 0.3, s.position.z))
	_toast("Picked up %s." % ExpeditionData.count_text(item, k), "info")
	return true


# --- panels --------------------------------------------------------------------------------

func _open_panel(s: PoiSpot) -> void:
	open_spot = s
	refresh_pack_line()
	if game.has_method("_set_modal"):
		game._set_modal("poi", true)
	panel.open_loot(state, PoiState.container(record, s.id)["items"], s.label().capitalize(), self)


func open_cargo() -> void:
	if not _can_act():
		return
	open_spot = world.spot("cargo", "car")
	refresh_pack_line()
	if game.has_method("_set_modal"):
		game._set_modal("poi", true)
	panel.open_cargo(state, cargo, self)


func close_panel() -> void:
	if panel.is_open:
		panel._close_and_emit()


func _on_panel_closed() -> void:
	open_spot = null
	refresh_pack_line()
	if world != null:
		world._update_reveal()
	if str(game.get("_modal")) == "poi" and game.has_method("_set_modal"):
		game._set_modal("", false)


func pack_add(id: String, n: int) -> void:
	if n > 0:
		pack[id] = int(pack.get(id, 0)) + n
		PoiState.note_found(state, poi_id, id)       # Exp 008 (L): a one-of-a-kind item never turns up again
		if pack_full() and not _full_said:
			_full_said = true
			_toast(full_text(), "warn")
		refresh_pack_line()


func pack_remove(id: String, n: int) -> void:
	PoiState.note_found(state, poi_id, id)          # Exp 008 (L): stowed in the boot, it still exists
	var k := mini(n, int(pack.get(id, 0)))
	if k <= 0:
		return
	if int(pack[id]) - k <= 0:
		pack.erase(id)
	else:
		pack[id] = int(pack[id]) - k
	refresh_pack_line()


## Exp 008 (L): true when the pack takes nothing more (within a nail's weight).
func pack_full() -> bool:
	return state != null and PoiState.pack_load(state, pack) >= PoiState.pack_cap(state) - 0.05


## Exp 008 (L): "Your pack is full (30 / 30). ..." with what Eli can do about it.
func full_text() -> String:
	var t := "Your pack is full (%s / %s)." % [PoiState._num(PoiState.pack_load(state, pack)), PoiState._num(PoiState.pack_cap(state))]
	if has_car:
		return t + " Stow things in the car's boot, or leave the rest here."
	return t + " Leave the rest here, or come back for it."


## Exp 008 (L): the HUD's line while away: "Pack 18 / 30", "· Boot 12 / 60"
## when Eli drove, "· full" when nothing more fits.
func pack_line() -> String:
	if state == null:
		return ""
	var t := "Pack %s / %s" % [PoiState._num(PoiState.pack_load(state, pack)), PoiState._num(PoiState.pack_cap(state))]
	if pack_full():
		t += " · full"
	if has_car:
		t += " · Boot %s / %s" % [PoiState._num(PoiState.load_of(cargo)), PoiState._num(PoiState.CARGO_CAP)]
	return t


# --- markers and the HUD (Exp 008 (L)) -----------------------------------------------------

func _tick_loot_ui(delta: float) -> void:
	_ui_tick -= delta
	if _ui_tick > 0.0:
		return
	_ui_tick = TICK
	update_markers()
	if _full_said and not pack_full():
		_full_said = false
	refresh_pack_line()


## The HUD's pack line now (each tick, and at once when the pack changes).
func refresh_pack_line() -> void:
	var hud: Variant = game.get("hud") if game != null else null
	if state != null and hud is Object and is_instance_valid(hud) and hud.has_method("set_pack_line"):
		var ld := PoiState.pack_load(state, pack)
		var cap := PoiState.pack_cap(state)
		hud.set_pack_line(pack_line(), 2 if pack_full() else (1 if ld >= cap * 0.8 else 0))


## The marker each container and loose item shows now: shown while Eli is
## within MARK_RANGE and can see it; the prompt's choice (game._focus) is hot.
func update_markers() -> void:
	if world == null or state == null:
		return
	var pl: Variant = game.get("player")
	if not (pl is Node3D):
		return
	var pp := Vector2((pl as Node3D).global_position.x, (pl as Node3D).global_position.z)
	var focus: Variant = game.get("_focus")
	for s in world.spots:
		if not (s.kind in ["container", "pickup"]):
			continue
		var look := ["", ""]
		var at: Vector2 = s.interact_point()
		if at.distance_to(pp) <= MARK_RANGE and not (s.kind == "container" and world.container_cut(s.id)) and can_see(pp, at):
			look = marker_for(s)
		s.set_marker(look[0], look[1], is_same(s, focus))


## [look, tag] for a spot's marker (PoiSpot.set_marker).
func marker_for(s: PoiSpot) -> Array:
	if s.kind == "pickup":
		return ["", ""] if record["taken"].has(s.id) else ["new", ""]
	if s.kind != "container":
		return ["", ""]
	var box := PoiState.container(record, s.id)
	if box["searched"]:
		var n := FurnitureStorage.total(box["items"])
		return ["left", "%d left" % n] if n > 0 else ["empty", "searched"]
	var needs := str(s.data.get("needs", ""))
	if needs == "crowbar" and not record["forced"].has(s.id):
		return ["locked", ""]
	if needs == "flashlight" and not owns("flashlight"):
		return ["dark", ""]
	return ["new", ""]


# --- leaving -------------------------------------------------------------------------------

## "[E] Leave for home": ends the visit and asks the travel flow (agent T's
## game.travel.leave_poi()) to take Eli home; without it, leave_requested.
func leave() -> void:
	cancel_action("")
	var out := finish()
	var t: Variant = game.get("travel") if game != null else null
	if t is Object and is_instance_valid(t) and t.has_method("leave_poi"):
		t.leave_poi()
	else:
		leave_requested.emit(poi_id)
	if out.is_empty():
		push_warning("GamePoi: leaving without a visit")


## Ends the visit once (PoiState.finish_visit: the map's stock, the visit
## count) and hands what comes home to the travel flow: GameLaunch.carry
## ["poi"] = {"site", "by_car", "cargo", "pack", "left"} when the carry exists.
## Returns that dictionary.
func finish() -> Dictionary:
	if not finished.is_empty() or state == null:
		return finished
	var r := PoiState.finish_visit(state, poi_id)
	finished = {"site": poi_id, "by_car": has_car, "cargo": r["cargo"], "pack": r["pack"], "left": r["left"]}
	var carry: Variant = launch_carry()
	if carry is Dictionary:
		carry["poi"] = finished
	return finished


## GameLaunch.carry (agent T) when it exists, else null.
static func launch_carry() -> Variant:
	var v: Variant = (GameLaunch as Script).get("carry")
	return v if typeof(v) == TYPE_DICTIONARY else null


## Did Eli come by car? GameLaunch.carry["travel"] (read defensively).
static func arrived_by_car() -> bool:
	var c: Variant = launch_carry()
	if not (c is Dictionary):
		return false
	var t: Variant = (c as Dictionary).get("travel", {})
	if typeof(t) != TYPE_DICTIONARY:
		return false
	for k in ["by_car", "car"]:
		if t.get(k) == true:
			return true
	return str(t.get("mode", t.get("by", ""))) == "car"


# --- encounters ------------------------------------------------------------------------------

func _roster() -> Node:
	var r: Variant = game.get("roster") if game != null else null
	return r if r is Node and is_instance_valid(r) and r.has_method("spawn_type") else null


func _start_encounters() -> void:
	plan = world.encounter_plan(PoiDefs.danger_of(state, poi_id), PoiState._seed(state, [poi_id, "encounter", int(record.get("visits", 0))]))
	pending = []
	for p in plan:
		if float(p["when"]) <= 0.0:
			_spawn(p)
		else:
			pending.append(p.duplicate())


func _spawn(p: Dictionary) -> Node:
	var r := _roster()
	if r == null:
		return null
	# "mode": agent N's roster spawns a calm straggler (hostile on noise, sight or damage)
	var e: Node = r.spawn_type(str(p["kind"]), p["at"], {"level": state.difficulty, "invasion": maxi(state.invasion_index(), 1), "mode": str(p["mode"])})
	if not (e is AIEnemy):
		return e
	e.set_meta("poi_mode", str(p["mode"]))
	var w := {"e": e, "mode": str(p["mode"]), "state": "", "t": 0.0, "notice": 0.0, "lost": 0.0}
	watch.append(w)
	if not own_awareness():
		w["state"] = "noise_ai"           # agent N's behaviours run it
		return e
	if p["mode"] == "hidden":
		_calm(w, "idle")
	elif p["mode"] == "arrive":
		_investigate(w, world.building_rect().get_center() if not world.layout.get("outdoor", false) else world.entry_point())
	else:
		_calm(w, "wander")
	return e


func _calm(w: Dictionary, st: String) -> void:
	var e: AIEnemy = w["e"]
	e.brain.attack_goal = false
	e.brain.bash = false
	w["state"] = st
	w["t"] = 0.0
	w["notice"] = 0.0
	if st == "idle":
		e.terrain_scale = 0.0
		e.goal_override = e.plan_pos()
	else:
		e.terrain_scale = 0.45
		e.goal_override = world.wander_point(_rng, e.plan_pos(), 3.0)


func _investigate(w: Dictionary, at: Vector2) -> void:
	var e: AIEnemy = w["e"]
	e.brain.attack_goal = false
	e.brain.bash = false
	e.terrain_scale = 0.7
	e.goal_override = at
	w["state"] = "investigate"
	w["t"] = 0.0


func _hunt(w: Dictionary) -> void:
	var e: AIEnemy = w["e"]
	e.goal_override = Vector2.INF
	e.brain.attack_goal = true
	e.brain.bash = int(e.def.get("wall_strikes", 1)) > 0
	e.terrain_scale = 1.0
	w["state"] = "hunt"
	w["lost"] = 0.0
	if not _seen_toast:
		_seen_toast = true
		_toast("It has seen you.", "bad")


## Awareness, every TICK s (see the header).
func _think(dt: float) -> void:
	var pl: Variant = game.get("player")
	if not (pl is Node3D):
		return
	var pp := Vector2((pl as Node3D).global_position.x, (pl as Node3D).global_position.z)
	for w in watch.duplicate():
		var e: Variant = w["e"]
		if not is_instance_valid(e) or not (e as AIEnemy).alive:
			watch.erase(w)
			continue
		var en := e as AIEnemy
		if en.has_meta("retreat") or w["state"] == "noise_ai":
			continue
		var me := en.plan_pos()
		var d := me.distance_to(pp)
		if w["state"] == "hunt":
			if en.goal_override != Vector2.INF and en.goal_override.distance_to(pp) > 3.0 and not en.brain.attack_goal:
				_calm(w, "wander")        # someone else (the stairs, noise) took it over: start again
				continue
			w["lost"] = float(w["lost"]) + dt if d > LOSE_RANGE else 0.0
			if float(w["lost"]) >= LOSE_TIME:
				_calm(w, "wander")
			continue
		if en.hp < en.max_hp or d < 2.2:
			_hunt(w)
			continue
		var reach := SEE_RANGE_IDLE if w["state"] == "idle" else SEE_RANGE
		if d < reach and can_see(me, pp):
			w["notice"] = float(w["notice"]) + dt * (2.0 if d < 5.0 else 1.0)
			if float(w["notice"]) >= NOTICE_TIME:
				_hunt(w)
				continue
		else:
			w["notice"] = maxf(float(w["notice"]) - dt * 0.5, 0.0)
		w["t"] = float(w["t"]) + dt
		match str(w["state"]):
			"wander":
				if me.distance_to(en.goal_override) < 0.8 or float(w["t"]) > 9.0:
					_calm(w, "wander")
			"investigate":
				if me.distance_to(en.goal_override) < 0.9 or float(w["t"]) > 14.0:
					_calm(w, "wander")


## Voxel line of sight at head height (walls, closed glass and doors block).
func can_see(from: Vector2, to: Vector2) -> bool:
	if world == null or world.grid == null:
		return true
	var a := Vector3(from.x, 1.5, from.y)
	var b := Vector3(to.x, 1.3, to.y)
	var dist := a.distance_to(b)
	if dist < 0.05:
		return true
	var vh := world.grid.raycast(a, (b - a) / dist, dist, world._bullet_skip)
	if not vh.is_empty() and float(vh["dist"]) < dist - 0.3:
		return false
	for o in world.objects:
		if o.kind == "door" and not o.open and Geometry2D.segment_intersects_segment(from, to, o.footprint().position, o.footprint().end) != null:
			return false
	return true


## A noise at `pos` (levels as agent N's table: search 1, force 2, smash
## and chopping 3, gunfire 4): agent N's noise system when it exists (the
## game's `noise` helper, else the NoiseEvent class), then hear().
func emit_noise(pos: Vector3, level: float, source: String) -> void:
	var nz: Variant = game.get("noise") if game != null else null
	if nz is Object and is_instance_valid(nz) and nz.has_method("emit"):
		nz.emit(pos, level, source)
	else:
		var n := noise_class()
		if n != null:
			n.call("emit", game, pos, level, source)
	hear(Vector2(pos.x, pos.z), level)


## This visit's reaction to a noise: arrivals come sooner after a loud one
## (2+), and, while this helper runs the awareness itself (own_awareness),
## unaware enemies within level x NOISE_RADIUS m go to look.
func hear(at: Vector2, level: float) -> void:
	last_noise = {"at": at, "level": level}
	if own_awareness():
		for w in watch:
			var e: Variant = w["e"]
			if not is_instance_valid(e) or w["state"] in ["hunt", "noise_ai"]:
				continue
			if (e as AIEnemy).plan_pos().distance_to(at) <= level * NOISE_RADIUS:
				_investigate(w, at)
	if level >= 2.0:
		for p in pending:
			p["when"] = minf(float(p["when"]), _clock + 8.0)


## True while agent N's straggler AI is absent: then this helper keeps POI
## enemies unaware until they notice the player (goal_override, no swings).
## With N's work merged (the NoiseEvent class), the roster's "mode" spawn
## option does that and this helper only watches.
static func own_awareness() -> bool:
	return noise_class() == null


func _on_fired(_id: String, _hits: Array) -> void:
	var pl: Variant = game.get("player")
	if pl is Node3D:
		hear(Vector2((pl as Node3D).global_position.x, (pl as Node3D).global_position.z), 4.0)


## Agent N's NoiseEvent class (a script with a static emit()), or null.
static func noise_class() -> Script:
	if typeof(_noise_script) == TYPE_BOOL:
		_noise_script = null
		for c in ProjectSettings.get_global_class_list():
			if str(c.get("class", "")) == "NoiseEvent":
				var s: Variant = load(str(c["path"]))
				if s is Script:
					for m in (s as Script).get_script_method_list():
						if str(m.get("name", "")) == "emit":
							_noise_script = s
	return _noise_script


# --- the game's clock and toasts -------------------------------------------------------------------

func _advance(minutes: float) -> void:
	if minutes <= 0.0:
		return
	if game.has_method("_advance_clock"):
		game._advance_clock(minutes)
	else:
		state.advance(minutes)


func _toast(text: String, kind := "info") -> void:
	if text != "" and game != null and game.has_method("toast"):
		game.toast(text, kind)


# --- F10 "POI" ---------------------------------------------------------------------------------------

func dev_restore_loot() -> String:
	if world == null:
		return "Not at a POI."
	cancel_action("")
	close_panel()
	PoiState.restore(state, poi_id)
	world.apply_record()
	return "%s: loot, pickups and wood restored (%d containers)." % [RegionLocations.name_of(poi_id), (record["c"] as Dictionary).size()]


func dev_spawn_straggler() -> String:
	if world == null or _roster() == null:
		return "Not at a POI."
	var pl: Node3D = game.get("player")
	var at := world.wander_point(_rng, Vector2(pl.global_position.x, pl.global_position.z), 6.0)
	_spawn({"kind": "psycho", "at": at, "when": 0.0, "mode": "wander"})
	return "A straggler wanders in at (%.1f, %.1f)." % [at.x, at.y]


func dev_reveal() -> String:
	if world == null:
		return "Not at a POI."
	world.set_reveal(not world.is_revealed())
	return "Containers revealed." if world.is_revealed() else "Container labels hidden."


func dev_state_text() -> String:
	if world == null:
		return "Not at a POI."
	var n := 0
	var done := 0
	var items := 0
	for cid in record["c"]:
		n += 1
		if record["c"][cid]["searched"]:
			done += 1
		items += FurnitureStorage.total(record["c"][cid]["items"])
	var modes := {}
	for w in watch:
		if is_instance_valid(w["e"]) and (w["e"] as AIEnemy).alive:
			modes[w["state"]] = int(modes.get(w["state"], 0)) + 1
	var d := PoiDefs.get_def(poi_id)
	return "%s (%s%s) · visit %d · danger %.2f\nContainers searched %d/%d · %d items left · pickups taken %d · wood chopped %d\n%s · boot %s/%s · enemies %s · arrivals due %d" % [
		d["name"], d["template"], ", placeholder" if d["placeholder"] else "", int(record.get("visits", 0)), PoiDefs.danger_of(state, poi_id),
		done, n, items, (record["taken"] as Dictionary).size(), _sum(record["chop"]),
		PoiState.pack_text(state, pack), PoiState._num(PoiState.load_of(cargo)), PoiState._num(PoiState.CARGO_CAP),
		str(modes) if not modes.is_empty() else "none", pending.size()]


static func _sum(d: Dictionary) -> int:
	var n := 0
	for k in d:
		n += int(d[k])
	return n
