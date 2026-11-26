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
## (only when you drove): its boot holds more. Exp 009 (X): "[E] Leave
## location" at the car (when you drove) or at the departure marker at the
## scene's edge (on foot), whenever you want: a small choice, Go home /
## Travel on (map) / Stay. An apartment's hallway fades into the dark at its
## end; walking into it asks "Leave this location?" once per time in.
##
## Exp 008 (L): searchable things show a small marker when Eli is near and
## can see them (PoiSpot.set_marker: not searched, locked, dark, something
## left, searched), and the prompt always says what a container holds now
## ("[E] Take from the shelf · 2 cans of food", "Shelf: searched · empty").
## The HUD shows "Pack 18 / 30" (and "· Boot 12 / 60" when Eli drove) while
## away; a take that fills the pack says so. One-of-a-kind items Eli takes or
## stows are noted (PoiState.note_found) so they never turn up again.
##
## Enemies (PoiWorld.encounter_plan by the visit's danger; often nobody):
## ordinary roster enemies that start unaware: hidden ones wait in a room,
## watchers stand outside a window looking in, wanderers walk about, others
## come in from the fog after a few minutes (sooner after a loud noise, and
## then to look at it) or walk in by a doorway. They notice you when you come
## close, when they see you (a watcher: through the glass), when they're
## hurt; noise draws them to look. Once hunting they act as at home, and lose
## interest when you get well away out of their sight. Nothing has to be
## cleared: every exit works at any time. Saving works while none hunts you;
## the encounters' progress is saved with the visit (Exp 008 (E)).
##
## Exp 009 (P): dormant psychos (plan mode "dormant", DormantMind) are busy
## at the layout's "dormant" spots: banging their head on a wall, circling a
## table, swaying, staring, tapping. Absorbed, they see little and hear less;
## noise makes them listen and look, and enough of it, or seeing Eli, turns
## them into ordinary hunters. They are saved with their spot and behaviour
## in "enc" and come back dormant on Continue. F10: dev_spawn_dormant(),
## dev_force_behaviour().

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
const MARK_KEEP := 0.8             ## Exp 012 (L, §24): m further a shown marker stays on (hysteresis)
const MARK_GRACE := 0.6            ## Exp 012 (L, §24): s a shown marker survives losing sight
const PROMPT_KINDS := 2            ## Exp 008 (L): item kinds named in a partly taken container's prompt
const INTERRUPT_HP := 1.0          ## Exp 012 (L, §25): health lost during a timed action that stops it (a hit)

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
var spawned := 0                   ## Exp 008 (E): enemies that came this visit (saved with it)
var killed := 0                    ## Exp 008 (E): of them, dead or gone

var _action := {}                  ## {"what", "spot", "door", "t", "dur", "minutes", "noise", "health"}
var _clock := 0.0
var _tick := 0.0
var _started := false
var _rng := RandomNumberGenerator.new()
var _seen_toast := false
var _full_said := false            ## Exp 008 (L): "your pack is full" said (until it has room again)
var _ui_tick := 0.0
var leave_dialog: PoiLeaveDialog     ## Exp 009 (X): Go home / Travel on / Stay
var _leave_via := ""               ## Exp 009 (X): "car" | "edge" | "dark" while the choice is open
var _in_dark := false              ## Exp 009 (X): Eli stands in the dark hallway end
var _dark_armed := false
var _exit_tick := 0.0
var _mark_on := {}                 ## Exp 012 (L, §24): "kind:id" -> clock when last seen (markers shown)

static var _noise_script: Variant = false     ## agent N's NoiseEvent script (looked up once; false = not yet)


func setup(g: Node) -> void:
	game = g
	name = "Poi"
	panel = PoiLootPanel.new()
	panel.name = "PoiLootPanel"
	add_child(panel)
	panel.closed.connect(_on_panel_closed)
	leave_dialog = PoiLeaveDialog.new()
	leave_dialog.name = "PoiLeaveDialog"
	add_child(leave_dialog)
	leave_dialog.chosen.connect(_on_leave_chosen)
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
		_begin_encounters()             # Exp 008 (E): or the saved progress (Continue)
	_clock += delta
	_step_action(delta)
	_tick_loot_ui(delta)              # Exp 008 (L): markers, the HUD's pack line
	_tick_exits(delta)                # Exp 009 (X): the dark hallway end
	for p in pending.duplicate():
		if _clock >= float(p["when"]) and _roster() != null:
			pending.erase(p)
			_spawn(p)
			_toast("Something is moving out in the fog.", "warn")
			_sync_encounters()
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
			var left := pickup_left(s)          # Exp 012 (L, §25): what a partial take left
			var what := ExpeditionData.count_text(str(s.data["item"]), left)
			var fit := _room_now(str(s.data["item"]))
			if fit <= 0:
				return "[E] Pick up %s · no room" % what
			if fit < left:
				return "[E] Pick up %s · room for %d" % [what, fit]
			return "[E] Pick up %s" % what
		"wood":
			var left := chops_left(s)
			return "[E] Chop wood (fallen tree · %d left)" % left if left > 0 else ""
		"exit":
			return "[E] Leave location"       # Exp 009 (X): the car, the departure marker
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
			open_leave(str(s.data.get("via", "edge")))      # Exp 009 (X): Go home / Travel on / Stay
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
	if state.health < float(_action["health"]) - INTERRUPT_HP:
		cancel_action("Interrupted!")       # Exp 012 (L, §25): a hit, not hunger or thirst slowly draining health
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


## Exp 012 (L, §25): takes as much of a loose item as the pack and the
## household caps allow; the rest stays where it lies (record "part": pickup
## id -> n left) until it is really gone. True if anything was taken.
func pick_up(s: PoiSpot) -> bool:
	if record["taken"].has(s.id):
		return false
	var item := str(s.data["item"])
	var n := pickup_left(s)
	if PoiState.room_for(item, PoiState.pack_load(state, pack), PoiState.pack_cap(state)) <= 0:
		_toast(full_text(), "warn")
		return false
	if state.inventory.space_for(item) <= 0:
		_toast("No room for more %s." % Items.name_of(item).to_lower() if not Items.is_unique(item) else "You already have one.", "warn")
		return false
	var k := state.inventory.add(item, mini(n, _room_now(item)))
	if k <= 0:
		return false
	pack_add(item, k)
	var part: Dictionary = _part()
	if k >= n:
		record["taken"][s.id] = state.day()
		part.erase(s.id)
	else:
		part[s.id] = n - k
	world.apply_record()
	Sfx.play_first(["poi/pickup", "ui/click"], Vector3(s.position.x, 0.3, s.position.z))
	if k >= n:
		_toast("Picked up %s." % ExpeditionData.count_text(item, k), "info")
	else:
		_toast("Picked up %s. %d left here: no room for more." % [ExpeditionData.count_text(item, k), n - k], "warn")
	return true


## Exp 012 (L, §25): how many of a loose item are still lying there.
func pickup_left(s: PoiSpot) -> int:
	var part: Variant = record.get("part", {})
	if typeof(part) == TYPE_DICTIONARY and (part as Dictionary).has(s.id):
		return maxi(int((part as Dictionary)[s.id]), 1)
	return int(s.data.get("n", 1))


func _part() -> Dictionary:
	if typeof(record.get("part")) != TYPE_DICTIONARY:
		record["part"] = {}
	return record["part"]


## What of `id` Eli can take now: the pack's room and the household caps.
func _room_now(id: String) -> int:
	return mini(PoiState.room_for(id, PoiState.pack_load(state, pack), PoiState.pack_cap(state)), state.inventory.space_for(id))


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
## Exp 012 (L, §24): no flicker: a marker comes on within MARK_RANGE in
## sight, and stays on until Eli is MARK_KEEP further away or out of sight
## for MARK_GRACE s (a pillar passing between them doesn't blink it).
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
		var d := at.distance_to(pp)
		var key: String = str(s.kind) + ":" + str(s.id)
		var was: bool = _mark_on.has(key)
		var on := false
		if d <= MARK_RANGE + (MARK_KEEP if was else 0.0) and not (s.kind == "container" and world.container_cut(s.id)):
			if can_see(pp, at):
				_mark_on[key] = _clock
				on = true
			elif was and _clock - float(_mark_on[key]) < MARK_GRACE:
				on = true
		if not on:
			_mark_on.erase(key)
		else:
			look = marker_for(s)
		s.set_marker(look[0], look[1], is_same(s, focus) and on)


## [look, tag] for a spot's marker (PoiSpot.set_marker).
func marker_for(s: PoiSpot) -> Array:
	if s.kind == "pickup":
		return ["", ""] if record["taken"].has(s.id) else ["pickup", ""]
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

## Exp 008 (T): the game's travel flow can go on from here to another place
## (the map at a POI, travel_flow.travel_on); the exits mention M then.
func can_travel_on() -> bool:
	var t: Variant = game.get("travel") if game != null else null
	return t is Object and is_instance_valid(t) and t.has_method("travel_on")


## "[E] Leave for home": asks the travel flow (agent T's
## game.travel.leave_poi()) to take Eli home; without it, ends the visit and
## emits leave_requested. (Exp 008: M opens the map to travel on to another
## place instead.) Exp 008 (T): with the travel flow, the visit ends
## (finish()) only once the departure is accepted, so a refused leave (an
## open panel, a wave at the door...) leaves the visit running.
func leave() -> void:
	cancel_action("")
	var t: Variant = game.get("travel") if game != null else null
	if t is Object and is_instance_valid(t) and t.has_method("leave_poi"):
		t.leave_poi()                      # checks first, then finish() and the road home
		return
	var out := finish()
	leave_requested.emit(poi_id)
	if out.is_empty():
		push_warning("GamePoi: leaving without a visit")


## Exp 009 (X): "[E] Leave location" (at the car or the departure marker;
## "Leave" in the dark hallway): Go home / Travel on (map) / Stay, with the
## world paused. A running search stops (leaving always works).
func open_leave(via := "edge") -> void:
	if not _can_act() or world == null:
		return
	cancel_action("")
	_leave_via = via
	if game.has_method("_set_modal"):
		game._set_modal("poi", true)
	leave_dialog.ask_leave(str(world.def.get("name", "")), can_travel_on() and game.has_method("open_map"), has_car)


## Exp 009 (X): walking into the dark hallway end: "Leave this location?".
func open_dark_leave() -> void:
	if not _can_act() or world == null:
		return
	cancel_action("")
	_leave_via = "dark"
	if game.has_method("_set_modal"):
		game._set_modal("poi", true)
	leave_dialog.ask_dark()


func _on_leave_chosen(what: String) -> void:
	var via := _leave_via
	_leave_via = ""
	if str(game.get("_modal")) == "poi" and game.has_method("_set_modal"):
		game._set_modal("", false)
	match what:
		"home":
			leave()
		"map":
			if game.has_method("open_map"):
				game.open_map()           # Exp 008 (T): the map from here; Travel goes straight on
			else:
				_toast("No map to hand here.", "warn")
		"leave":
			open_leave(via)
		_:
			if via == "dark":
				step_out_of_dark()


## Exp 009 (X): the dark hallway end asks once each time Eli walks in (not
## again while he stands in it, nor when he arrived inside it).
func _tick_exits(delta: float) -> void:
	_exit_tick -= delta
	if _exit_tick > 0.0 or world == null:
		return
	_exit_tick = 0.1
	var r: Rect2 = world.dark_exit()
	if r.size == Vector2.ZERO:
		return
	var pl: Variant = game.get("player")
	if not (pl is Node3D):
		return
	var inside := r.has_point(Vector2((pl as Node3D).global_position.x, (pl as Node3D).global_position.z))
	if not _dark_armed:
		_dark_armed = true
		_in_dark = inside
		return
	if inside == _in_dark:
		return
	_in_dark = inside
	if inside:
		open_dark_leave()


## Exp 009 (X): "Stay" in the dark: Eli steps back out toward the lit hallway.
func step_out_of_dark() -> void:
	var pl: Variant = game.get("player")
	var r: Rect2 = world.dark_exit() if world != null else Rect2()
	if not (pl is Node3D) or r.size == Vector2.ZERO:
		return
	var n := pl as Node3D
	var dir: Vector2 = world.dark_dir()
	var q := Vector2(n.global_position.x, n.global_position.z)
	for i in 80:
		if not r.grow(0.05).has_point(q):
			break
		q -= dir * 0.1
	q -= dir * 0.4
	n.global_position = Vector3(q.x, n.global_position.y, q.y)
	_in_dark = false


## Ends the visit once (PoiState.finish_visit: the map's stock, the visit
## count) and hands what comes home to the travel flow: GameLaunch.carry
## ["poi"] = {"site", "by_car", "cargo", "pack", "left"} when the carry exists.
## Returns that dictionary. Exp 008 (T): also before travelling on to another
## place; the boot ("cargo") and the pack then go along to the next visit.
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


## Exp 008 (E): the visit's encounters, on its first frame: the progress
## saved in the visit record when there is one (Continue at a POI: the killed
## stay dead, the calm ones stand where they stood, the arrivals keep their
## time), else a fresh plan.
func _begin_encounters() -> void:
	if not _restore_encounters():
		_start_encounters()
	_sync_encounters()


func _start_encounters() -> void:
	var seed := PoiState._seed(state, [poi_id, "encounter", int(record.get("visits", 0))])
	plan = world.encounter_plan(PoiDefs.danger_of(state, poi_id), seed)
	pending = []
	var app_rng := RandomNumberGenerator.new()
	app_rng.seed = hash([seed, "app"])
	for i in plan.size():                # Exp 011: each encounter's person (an appearance seed, saved)
		plan[i]["app"] = HumanoidLooks.pick_seed(str(plan[i]["kind"]), app_rng)
	for p in plan:
		if float(p["when"]) <= 0.0:
			_spawn(p)
		else:
			pending.append(p.duplicate())


func _spawn(p: Dictionary) -> Node:
	var r := _roster()
	if r == null:
		return null
	var mode := str(p["mode"])
	var mind := str(p.get("mind", "wander" if p.has("spot") else MIND_OF.get(mode, "wander")))
	if mind == "dormant" and typeof(p.get("dormant")) != TYPE_DICTIONARY:
		mind = "hidden"                    # Exp 009 (P): a dormant one without its spot just waits
	# "mode": agent N's roster spawns a calm straggler (hostile on noise, sight or damage)
	var opts := {"level": state.difficulty, "invasion": maxi(state.invasion_index(), 1), "mode": mind}
	if mind == "dormant":
		opts["dormant"] = p["dormant"]
	if p.has("app"):
		opts["appearance"] = int(p["app"])     # Exp 011: the same person after Continue
	var e: Node = r.spawn_type(str(p["kind"]), p["at"], opts)
	if not (e is AIEnemy):
		return e
	e.set_meta("poi_mode", mode)
	var w := {"e": e, "mode": mode, "state": "", "t": 0.0, "notice": 0.0, "lost": 0.0}
	watch.append(w)
	if not p.get("restored", false):
		spawned += 1
	if not own_awareness():
		w["state"] = "noise_ai"           # agent N's behaviours run it, with this helper's extras (_think_mind)
		if not p.get("restored", false):
			_plan_route(w, p)
		return e
	if p["mode"] == "hidden" or p["mode"] == "dormant":
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
	_prune()
	for w in watch.duplicate():
		var en := w["e"] as AIEnemy
		if en.has_meta("retreat"):
			continue
		if w["state"] == "noise_ai":
			_think_mind(w, en, pp, dt)
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
	_sync_encounters()


## Drops the dead and the gone from the watch list (counted in `killed`).
func _prune() -> void:
	for w in watch.duplicate():
		var e: Variant = w["e"]
		if not is_instance_valid(e) or not (e is AIEnemy) or not (e as AIEnemy).alive:
			watch.erase(w)
			killed += 1


## Voxel line of sight at head height (walls, closed glass and doors block).
func can_see(from: Vector2, to: Vector2) -> bool:
	if world == null or world.grid == null:
		return true
	return _clear_line(from, to, 1.5, 1.3, world._bullet_skip)


## A voxel line from `from` at height h0 to `to` at h1, `skip` the voxel kinds
## it passes; closed doors block it.
func _clear_line(from: Vector2, to: Vector2, h0: float, h1: float, skip: PackedByteArray) -> bool:
	var a := Vector3(from.x, h0, from.y)
	var b := Vector3(to.x, h1, to.y)
	var dist := a.distance_to(b)
	if dist < 0.05:
		return true
	var vh := world.grid.raycast(a, (b - a) / dist, dist, skip)
	if not vh.is_empty() and float(vh["dist"]) < dist - 0.3:
		return false
	for o in world.objects:
		if o.kind == "door" and not o.open and Geometry2D.segment_intersects_segment(from, to, o.footprint().position, o.footprint().end) != null:
			return false
	return true


# --- Exp 008 (E): encounters on top of agent N's calm minds ---------------------------------------
#
# Each spawned enemy has a StragglerMind ("wander" or "hidden"); this helper
# adds, per watch entry:
#   route   [{"p": Vector2, "door": bool}]: walk there one point at a time
#           (StragglerMind.walk_to); at a "door" point a closed, unlocked door
#           is opened (with its sound), then on into the room. Then "then":
#           "peek" (watch the window) or "wander" (a calm wanderer where it is).
#           Hearing or seeing something on the way ends the route (its own
#           mind goes to look instead).
#   peek    the point inside it watches through a window, "stay" s left; it
#           sees Eli through the glass (sees_through_window) for PEEK_NOTICE
#           s and comes in by the doorway nearest him; else it moves on.
# A hunting enemy that has lost Eli (out of its line, LOSE_RANGE_MIND m away,
# for LOSE_TIME s) calms down where it is: retreat and hiding work, and the
# game can be saved again.

## The calm mind (StragglerMind mode) a plan mode starts with.
const MIND_OF := {"hidden": "hidden", "peek": "hidden", "wander": "wander", "arrive": "wander", "enter": "wander",
	"dormant": "dormant"}
const PEEK_RANGE := 9.0           ## m it sees through a window
const PEEK_CONE := 1.13          ## rad (65 degrees): half the angle around where it looks
const PEEK_NOTICE := 1.0          ## s of seeing Eli before it comes round
const PEEK_STAY := Vector2(45.0, 120.0)   ## s at the window before it moves on
const LEG_TIME := 30.0            ## s on one route point before it gives up on it
const LOSE_RANGE_MIND := 10.0     ## m: a hunter this far without a line to Eli is losing him
const SOONER := [[3.5, Vector2(5.0, 10.0)], [2.5, Vector2(15.0, 30.0)], [2.0, Vector2(35.0, 60.0)]]   ## [min level, s from now] for arrivals

static var _see_skip := PackedByteArray()


## What a newly spawned (not restored) enemy does first.
func _plan_route(w: Dictionary, p: Dictionary) -> void:
	match str(p["mode"]):
		"peek":
			w["look"] = p["look"]
			if p.has("spot"):
				w["route"] = [_leg(p["spot"])]
				w["then"] = "peek"
			else:
				_start_peek(w)
		"enter":
			w["route"] = [_leg(p["door"], true), _leg(world.inside_of(p["door"]))]
			w["then"] = "wander"
		"arrive":
			w["route"] = [_leg(world.wander_point(_rng))]
			w["then"] = "wander"
	if p.get("drawn") is Vector2:
		_draw_to(w, p["drawn"])


static func _leg(p: Vector2, door := false) -> Dictionary:
	return {"p": p, "door": door}


## Sends it to look at `at`: through the doorway nearest to it when `at` is
## inside a room (layouts with "doorways"), else straight there.
func _draw_to(w: Dictionary, at: Vector2) -> void:
	var route := []
	var doors: Array = world.layout.get("doorways", [])
	if not doors.is_empty() and _indoors(at):
		route.append(_leg(PoiWorld.nearest_of(doors, at), true))
	route.append(_leg(at))
	w["route"] = route
	w["then"] = "wander"
	w["going"] = false
	w.erase("peek")


func _indoors(p: Vector2) -> bool:
	for r in world.rooms():
		if (r["rect"] as Rect2).has_point(p):
			return true
	return false


func _start_peek(w: Dictionary) -> void:
	w["peek"] = w["look"]
	w["stay"] = _rng.randf_range(PEEK_STAY.x, PEEK_STAY.y)
	w["notice"] = 0.0


## The extras on top of a calm mind, every TICK s (see the section header).
func _think_mind(w: Dictionary, en: AIEnemy, pp: Vector2, dt: float) -> void:
	var me := en.plan_pos()
	if not en.is_calm():
		w.erase("route")
		w.erase("peek")
		var away := me.distance_to(pp) > LOSE_RANGE_MIND and (en.nav == null or not en.nav.segment_clear(me, pp))
		w["lost"] = float(w["lost"]) + dt if away else 0.0
		if float(w["lost"]) >= LOSE_TIME:
			w["lost"] = 0.0
			en.set_calm_mode("wander", _rng.randi())
			_toast("It seems to have lost you.", "info")
		return
	w["lost"] = 0.0
	if w.has("route"):
		_follow(w, en, dt)
	elif w.has("peek"):
		_watch_window(w, en, pp, dt)


func _follow(w: Dictionary, en: AIEnemy, dt: float) -> void:
	var route: Array = w["route"]
	if route.is_empty():
		w.erase("route")
		_route_done(w, en)
		return
	var leg: Dictionary = route[0]
	if not bool(w.get("going", false)):
		var to := en.mind.walk_to(en, leg["p"])
		w["going"] = to != Vector2.INF
		w["goal"] = to
		w["leg_t"] = 0.0
		if to == Vector2.INF:
			route.pop_front()             # nowhere to stand there: the next point
		return
	w["leg_t"] = float(w["leg_t"]) + dt
	var goal: Vector2 = w["goal"]
	var mine := en.mind.goal.distance_to(goal) < 0.3
	if mine and (en.mind.linger >= 0.0 or en.plan_pos().distance_to(goal) < 0.6) or float(w["leg_t"]) > LEG_TIME:
		if bool(leg.get("door", false)):
			_open_door_near(leg["p"])
		route.pop_front()
		w["going"] = false
	elif not mine:
		w.erase("route")                  # it heard or saw something and went to look: its own mind carries on
		w.erase("then")
		w["going"] = false


func _route_done(w: Dictionary, en: AIEnemy) -> void:
	var then := str(w.get("then", "wander"))
	w.erase("then")
	w["going"] = false
	if then == "peek" and w.get("look") is Vector2:
		en.set_calm_mode("hidden", _rng.randi())   # stands at the window
		_start_peek(w)
	else:
		en.set_calm_mode("wander", _rng.randi())   # roams around where it got to


## Someone coming in by a doorway opens a closed (unlocked) door there.
func _open_door_near(p: Vector2) -> void:
	for o in world.objects:
		if o.kind == "door" and not o.open and not (o is PoiDoor and (o as PoiDoor).locked) and o.pos.distance_to(p) < 1.6:
			world.set_door_open(o, true)
			return


func _watch_window(w: Dictionary, en: AIEnemy, pp: Vector2, dt: float) -> void:
	var look: Vector2 = w["peek"]
	if en.mind.state == "lurk":
		en.mind.look = look
	w["stay"] = float(w["stay"]) - dt
	if float(w["stay"]) <= 0.0:
		w.erase("peek")
		en.set_calm_mode("wander", _rng.randi())   # it moves on
		return
	var me := en.plan_pos()
	if sees_through_window(me, look, pp):
		w["notice"] = float(w["notice"]) + dt * (2.0 if me.distance_to(pp) < 4.0 else 1.0)
		if float(w["notice"]) >= PEEK_NOTICE:
			_draw_to(w, pp)
			_toast("A face at the window. It saw you.", "warn")
	else:
		w["notice"] = maxf(float(w["notice"]) - dt * 0.5, 0.0)


## Can a watcher at `from`, looking in at `look`, see Eli at `to` through a
## window? Within PEEK_RANGE m and PEEK_CONE of where it looks, along a clear
## line at head height that glass doesn't stop (walls and closed doors do).
func sees_through_window(from: Vector2, look: Vector2, to: Vector2) -> bool:
	if world == null or world.grid == null:
		return false
	var d := from.distance_to(to)
	if d > PEEK_RANGE or d < 0.05:
		return false
	var dir := look - from
	if dir.length() > 0.01 and dir.normalized().dot((to - from) / d) < cos(PEEK_CONE):
		return false
	return _clear_line(from, to, 1.65, 1.35, see_skip())


## The voxel kinds a look passes: what bullets pass, and glass.
static func see_skip() -> PackedByteArray:
	if _see_skip.is_empty():
		_see_skip.resize(256)
		for i in 256:
			_see_skip[i] = 1 if (VoxelMat.FLAGS[i] & (VoxelMat.F_PASS | VoxelMat.F_GLASS)) != 0 else 0
	return _see_skip


# --- Exp 008 (E): saving with enemies about ---------------------------------------------------------

## "" when the game may save here, else why not (SurvivalGame.can_save() asks
## at a POI). Calm, unaware enemies don't stop a save: encounter_state() keeps
## them, as they are, in the visit record, which this brings up to date. An
## enemy hunting Eli does.
func save_check() -> String:
	if hunters() > 0:
		return "You can't save while they're after you."
	_prune()
	_sync_encounters()
	return ""


## Living enemies here that hunt Eli: every roster threat that isn't calm.
func hunters() -> int:
	var r := _roster()
	if r == null:
		return 0
	var n := 0
	for e in r.get("enemies"):
		if r.is_threat(e) and not (e is AIEnemy and (e as AIEnemy).is_calm()):
			n += 1
	return n


## The visit's encounter progress into the visit record (PoiState record
## "visit" > "enc", saved with the run); nothing once the visit is over.
func _sync_encounters() -> void:
	if not _started or world == null:
		return
	var v: Variant = record.get("visit")
	if typeof(v) == TYPE_DICTIONARY:
		v["enc"] = encounter_state()


## The encounters as they are now: {"v": 1, "pending": [plan entries with
## "in" (s still to come)], "calm": [{"kind", "at", "hp", "mode", "mind",
## "anchor", "alert", "yaw", "route", "then", "look", "peek", "stay", "app"}],
## "spawned", "killed"}. "app" (Exp 011) is the person's appearance seed. Vectors are [x, y]. Hunting enemies aren't in it
## (saving waits for them); the killed and the gone aren't either.
func encounter_state() -> Dictionary:
	var pend := []
	for p in pending:
		var q := {"kind": str(p["kind"]), "mode": str(p["mode"]), "at": _arr(p["at"]), "in": maxf(float(p["when"]) - _clock, 0.0)}
		if p.has("app"):
			q["app"] = int(p["app"])
		for k in ["look", "spot", "door", "drawn"]:
			if p.get(k) is Vector2:
				q[k] = _arr(p[k])
		pend.append(q)
	var calm := []
	for w in watch:
		var e: Variant = w["e"]
		if not is_instance_valid(e) or not (e is AIEnemy) or not (e as AIEnemy).alive or (e as AIEnemy).has_meta("retreat"):
			continue
		var en := e as AIEnemy
		if not en.is_calm():
			continue
		var c := {"kind": en.kind, "at": _arr(en.plan_pos()), "hp": en.hp, "mode": str(w["mode"]), "mind": en.mind.mode,
			"anchor": _arr(en.mind.anchor), "alert": en.mind.alert, "yaw": en.rig.rotation.y if en.rig != null else 0.0,
			"app": en.appearance}
		if w.has("route"):
			var legs := []
			for l in w["route"]:
				legs.append(_arr(l["p"]) + [1 if l.get("door", false) else 0])
			c["route"] = legs
			c["then"] = str(w.get("then", "wander"))
		for k in ["look", "peek"]:
			if w.get(k) is Vector2:
				c[k] = _arr(w[k])
		if w.has("stay"):
			c["stay"] = float(w["stay"])
		if en.mind is DormantMind:
			c["dormant"] = (en.mind as DormantMind).save_data()       # Exp 009 (P)
		calm.append(c)
	return {"v": 1, "pending": pend, "calm": calm, "spawned": spawned, "killed": killed}


## Continue at a POI: the encounters from the visit record's "enc" (see
## encounter_state). False when there is none (a fresh visit, or a save made
## before they began).
func _restore_encounters() -> bool:
	var v: Variant = record.get("visit")
	if typeof(v) != TYPE_DICTIONARY or typeof(v.get("enc")) != TYPE_DICTIONARY or _roster() == null:
		return false
	var enc: Dictionary = v["enc"]
	plan = []
	pending = []
	for q in _list(enc.get("pending")):
		var at := _vec(q.get("at"))
		if at == Vector2.INF:
			continue
		var p := {"kind": _kind(q.get("kind")), "mode": str(q.get("mode", "arrive")), "at": at, "when": _clock + clampf(_num(q.get("in")), 0.0, 600.0)}
		if typeof(q.get("app")) in [TYPE_INT, TYPE_FLOAT]:
			p["app"] = int(q["app"])
		for k in ["look", "spot", "door", "drawn"]:
			if _vec(q.get(k)) != Vector2.INF:
				p[k] = _vec(q[k])
		if p["mode"] == "peek" and not p.has("look") or p["mode"] == "enter" and not p.has("door"):
			p["mode"] = "arrive"
			p.erase("spot")
		pending.append(p)
	for c in _list(enc.get("calm")):
		var at := _vec(c.get("at"))
		if at == Vector2.INF:
			continue
		var mind := str(c.get("mind", "wander"))
		var q := {"kind": _kind(c.get("kind")), "at": at, "mode": str(c.get("mode", "wander")),
			"mind": mind if mind in ["hidden", "wander"] else "wander", "restored": true}
		if typeof(c.get("app")) in [TYPE_INT, TYPE_FLOAT]:
			q["app"] = int(c["app"])
		if mind == "dormant" and typeof(c.get("dormant")) == TYPE_DICTIONARY:
			q["mind"] = "dormant"            # Exp 009 (P): back at its spot, busy as it was
			q["dormant"] = c["dormant"]
		var e: Node = _spawn(q)
		if not (e is AIEnemy):
			continue
		var en := e as AIEnemy
		en.hp = clampi(int(_num(c.get("hp"), en.max_hp)), 1, en.max_hp)
		en.set_facing(_num(c.get("yaw")))
		var w: Dictionary = watch.back()
		if en.mind == null:
			continue
		var anchor := _vec(c.get("anchor"))
		if anchor != Vector2.INF:
			en.mind.anchor = anchor
		en.mind.alert = clampf(_num(c.get("alert")), 0.0, StragglerMind.PROVOKE - 0.01)
		var route := []
		for l in _list_raw(c.get("route")):
			var p := _vec(l)
			if p != Vector2.INF:
				route.append(_leg(p, (l as Array).size() > 2 and _num(l[2]) > 0.0))
		if not route.is_empty():
			w["route"] = route
			w["then"] = "peek" if str(c.get("then", "")) == "peek" else "wander"
		for k in ["look", "peek"]:
			if _vec(c.get(k)) != Vector2.INF:
				w[k] = _vec(c[k])
		if w.has("peek"):
			w["stay"] = clampf(_num(c.get("stay"), PEEK_STAY.x), 0.0, PEEK_STAY.y)
	spawned = maxi(int(_num(enc.get("spawned"))), watch.size())
	killed = maxi(int(_num(enc.get("killed"))), 0)
	return true


static func _arr(p: Vector2) -> Array:
	return [p.x, p.y]


## [x, y] (or a Vector2) as a Vector2; INF when it isn't one.
static func _vec(v: Variant) -> Vector2:
	if v is Vector2:
		return v if (v as Vector2).is_finite() else Vector2.INF
	if typeof(v) in [TYPE_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY] and v.size() >= 2 \
			and typeof(v[0]) in [TYPE_INT, TYPE_FLOAT] and typeof(v[1]) in [TYPE_INT, TYPE_FLOAT]:
		var p := Vector2(float(v[0]), float(v[1]))
		return p if p.is_finite() else Vector2.INF
	return Vector2.INF


static func _num(v: Variant, fallback := 0.0) -> float:
	return float(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(v)) else fallback


## The dictionaries of an Array (anything else: none).
static func _list(v: Variant) -> Array:
	return (v as Array).filter(func(x): return typeof(x) == TYPE_DICTIONARY) if typeof(v) == TYPE_ARRAY else []


static func _list_raw(v: Variant) -> Array:
	return (v as Array).filter(func(x): return typeof(x) == TYPE_ARRAY) if typeof(v) == TYPE_ARRAY else []


## A POI enemy kind (no bombers at POIs).
static func _kind(v: Variant) -> String:
	var k := str(v) if typeof(v) == TYPE_STRING else "psycho"
	return k if EnemyDefs.has(k) and k != "bomber" else "psycho"


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


## This visit's reaction to a noise: arrivals still out in the fog come
## sooner after a loud one (level 2+: within 35-60 s; 2.5+: 15-30 s; gunfire:
## 5-10 s) and come to look (Exp 008 (E): by the doorway nearest the noise);
## noise never adds anyone. While this helper runs the awareness itself
## (own_awareness), unaware enemies within level x NOISE_RADIUS m go to look
## (else agent N's NoiseEvent tells them).
func hear(at: Vector2, level: float) -> void:
	last_noise = {"at": at, "level": level}
	if own_awareness():
		for w in watch:
			var e: Variant = w["e"]
			if not is_instance_valid(e) or w["state"] in ["hunt", "noise_ai"]:
				continue
			if (e as AIEnemy).plan_pos().distance_to(at) <= level * NOISE_RADIUS:
				_investigate(w, at)
	for tier in SOONER:
		if level >= float(tier[0]):
			var span: Vector2 = tier[1]
			for p in pending:
				p["when"] = minf(float(p["when"]), _clock + _rng.randf_range(span.x, span.y))
				p["drawn"] = at
			break


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


## Exp 009 (P), F10 "POI generator": a dormant psycho at the layout's
## nearest free dormant spot to Eli (at least DEV_NEAR m away), with
## `behaviour` when given (else the spot's); without a fitting spot, one made
## from the geometry around him (dormant_spot_near).
func dev_spawn_dormant(behaviour := "") -> String:
	if world == null or _roster() == null:
		return "Not at a POI."
	if behaviour != "" and not (behaviour in DormantMind.BEHAVIOURS):
		return "Unknown behaviour '%s' (%s)." % [behaviour, ", ".join(DormantMind.BEHAVIOURS)]
	var pl: Node3D = game.get("player")
	var near := Vector2(pl.global_position.x, pl.global_position.z)
	var sp := dormant_spot_near(behaviour, near)
	if sp.is_empty():
		return "No room for a dormant psycho near Eli."
	var e: Node = _spawn({"kind": "psycho", "at": sp["at"], "when": 0.0, "mode": "dormant",
		"dormant": {"behaviour": sp["behaviour"], "spot": sp["at"], "target": sp.get("target", Vector2.INF),
			"radius": float(sp.get("radius", 1.2)), "sensitivity": snappedf(_rng.randf_range(0.5, 1.5), 0.01), "mumble": _rng.randf() < 0.6}})
	_sync_encounters()
	if not (e is AIEnemy) or not ((e as AIEnemy).mind is DormantMind):
		return "The roster refused."
	return "A dormant psycho at (%.1f, %.1f): %s." % [sp["at"].x, sp["at"].y, dormant_text(e)]


## Exp 009 (P), F10: the dormant enemy nearest Eli switches to `behaviour`
## (at a spot that suits it, near where it is; invalid -> the usual fallback).
func dev_force_behaviour(behaviour: String) -> String:
	if world == null:
		return "Not at a POI."
	if not (behaviour in DormantMind.BEHAVIOURS):
		return "Unknown behaviour '%s' (%s)." % [behaviour, ", ".join(DormantMind.BEHAVIOURS)]
	var pl: Node3D = game.get("player")
	var pp := Vector2(pl.global_position.x, pl.global_position.z)
	var best: AIEnemy = null
	for w in watch:
		var e: Variant = w["e"]
		if is_instance_valid(e) and e is AIEnemy and (e as AIEnemy).alive and (e as AIEnemy).mind is DormantMind:
			if best == null or (e as AIEnemy).plan_pos().distance_to(pp) < best.plan_pos().distance_to(pp):
				best = e
	if best == null:
		return "No dormant psycho here."
	var dm := best.mind as DormantMind
	var sp := dormant_spot_near(behaviour, best.plan_pos(), 0.0, false)
	if sp.is_empty():
		sp = {"at": best.plan_pos(), "behaviour": behaviour, "target": Vector2.INF, "radius": 1.2}
	dm.reconfigure(best, {"behaviour": behaviour, "spot": sp["at"], "target": sp.get("target", Vector2.INF),
		"radius": float(sp.get("radius", 1.2)), "sensitivity": dm.sensitivity, "mumble": dm.mumble})
	_sync_encounters()
	return "It %s." % dormant_text(best)


## "bangs its head on the wall (sensitivity 0.8, mumbles)" for F10.
static func dormant_text(e: AIEnemy) -> String:
	var dm := e.mind as DormantMind if e != null and e.mind is DormantMind else null
	if dm == null:
		return "is not dormant"
	var what := {"bang": "bangs its head against the wall", "circle": "circles something", "sway": "sways in place",
		"stare": "stares at nothing", "tap": {"tap": "taps at a cabinet", "scratch": "scratches at a door", "drawer": "works a drawer"}.get(dm.tap_kind, "taps")}
	var t := str(what.get(dm.behaviour, dm.behaviour))
	if dm.behaviour != dm.asked and dm.asked != "":
		t += " (asked: %s, no place for it)" % dm.asked
	return "%s · sensitivity %.2f%s" % [t, dm.sensitivity, " · mumbles" if dm.mumble else ""]


const DEV_NEAR := 3.0                ## m: a dev dormant spot at least this far from Eli
const DEV_FAR := 9.0                 ## m: and at most this far (when the geometry allows)


## Exp 009 (P): a spot {at, behaviour, target, radius} for a dormant psycho
## near `near`: the layout's nearest free "dormant" spot of that behaviour
## between `min_d` and DEV_FAR m (when `use_layout`), else one made from the
## nav grid: bang / tap / stare beside a wall or furniture (target: the
## surface), circle round furniture with room all round (or an open point),
## sway anywhere walkable. {} when nothing near is walkable.
func dormant_spot_near(behaviour: String, near: Vector2, min_d := DEV_NEAR, use_layout := true) -> Dictionary:
	if world == null or world.nav == null:
		return {}
	if use_layout:
		var best := {}
		var best_d := INF
		for d in world.dormant_spots():
			var at: Vector2 = d["at"]
			var dist := at.distance_to(near)
			if (behaviour != "" and str(d.get("behaviour", "")) != behaviour) or dist < min_d or dist > DEV_FAR or _occupied(at):
				continue
			if dist < best_d:
				best_d = dist
				best = d.duplicate()
		if not best.is_empty():
			return best
	var b: String = behaviour if behaviour != "" else str(DormantMind.BEHAVIOURS[_rng.randi() % DormantMind.BEHAVIOURS.size()])
	var nav: GridNav = world.nav
	var c0 := nav.cell_of(near)
	var lo := int(ceil(min_d / GridNav.CELL))
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var fallback := {}
	for r in range(maxi(lo, 1), int(DEV_FAR / GridNav.CELL) + 1):
		for dj in range(-r, r + 1):
			for di in range(-r, r + 1):
				if maxi(absi(di), absi(dj)) != r or (di + dj) % 2 != 0:
					continue
				var c := c0 + Vector2i(di, dj)
				if not nav.is_walkable(c) or _occupied(nav.center_of(c)):
					continue
				var at := nav.center_of(c)
				if fallback.is_empty():
					fallback = {"at": at, "behaviour": "sway", "target": Vector2.INF, "radius": 1.2}
				match b:
					"bang", "tap", "stare":
						for dv in dirs:
							var k: int = nav.get_raw(c + dv * 2)
							if k == GridNav.WALL or k == GridNav.SOLID:
								return {"at": at, "behaviour": b, "target": nav.center_of(c + dv * 2), "radius": 1.2}
					"circle":
						for dv in dirs:
							for step in [3, 4, 5]:
								var o: Vector2i = c + dv * step
								if nav.get_raw(o) == GridNav.SOLID and _ring_free(nav, nav.center_of(o), float(step) * GridNav.CELL):
									return {"at": at, "behaviour": b, "target": nav.center_of(o), "radius": float(step) * GridNav.CELL}
						var mid := at + Vector2(1.3, 0.0)
						if nav.is_walkable(nav.cell_of(mid)) and _ring_free(nav, mid, 1.3):
							return {"at": at, "behaviour": b, "target": mid, "radius": 1.3}
					_:
						return {"at": at, "behaviour": b, "target": Vector2.INF, "radius": 1.2}
	if not fallback.is_empty():
		fallback["behaviour"] = b            # DormantMind falls back to sway where b doesn't fit
	return fallback


static func _ring_free(nav: GridNav, at: Vector2, radius: float) -> bool:
	var n := 0
	for i in 8:
		if nav.is_walkable(nav.cell_of(at + Vector2.from_angle(TAU * i / 8.0) * radius)):
			n += 1
	return n >= 6


func _occupied(p: Vector2) -> bool:
	for w in watch:
		var e: Variant = w["e"]
		if is_instance_valid(e) and e is AIEnemy and (e as AIEnemy).alive and (e as AIEnemy).plan_pos().distance_to(p) < 1.0:
			return true
	return false


func dev_reveal() -> String:
	if world == null:
		return "Not at a POI."
	world.set_reveal(not world.is_revealed())
	return "Containers revealed." if world.is_revealed() else "Container labels hidden."


## Exp 009 (lead): F10 "Reveal stash": where the main stash is, what guards
## it, and whether it was looted; the container labels are shown.
func dev_reveal_stash() -> String:
	if world == null:
		return "Not at a POI."
	var sid := str(world.layout.get("stash", ""))
	var sp: PoiSpot = world.spot("container", sid) if sid != "" else null
	if sp == null:
		return "This place has no main stash."
	if not world.is_revealed():
		world.set_reveal(true)
	var box := PoiState.container(record, sid)
	var needs := str(sp.data.get("needs", ""))
	var p := sp.plan_pos()
	var left := FurnitureStorage.total(box["items"])
	return "Main stash: %s at (%.1f, %.1f)%s · %s" % [sp.label(), p.x, p.y,
		" · needs a %s" % needs if needs != "" else "",
		("searched, %d left" % left) if bool(box["searched"]) else "not searched yet"]


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
			var st := str(w["state"]) if w["state"] != "noise_ai" else (w["e"] as AIEnemy).state_name()   # Exp 008 (E): the mind's state
			modes[st] = int(modes.get(st, 0)) + 1
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
