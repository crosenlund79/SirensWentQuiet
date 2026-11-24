extends Node
## The quick-access bar in the game (Experiment 004, E). The rules live in
## Hotbar (src/survival/hotbar.gd) on GameState.hotbar (saved); this node does
## the input, the item in hand and its use:
##   1-8         select a slot (outside build mode; 1 and 2 hold the
##               equipped weapons by default). Q: the next weapon on the bar.
##   X           holster: empty hands (again: take the selected item back).
##   LMB         use the item in hand: a weapon fires (WeaponHandler, R
##               reloads); food, water and medical items are consumed once per
##               click through GameState.use_item, with a toast; the hammer
##               opens build mode; the flashlight toggles its light; the
##               shovel opens build mode's excavate tool (or says how to
##               dig); the crowbar and worn gear explain or toggle themselves.
## Empty hands: the WeaponHandler is holstered (firing does nothing) and the
## rig's arms hang. The bar is hidden in build mode and while panels are open.
## Docs: docs/experiment-004/e_bar_car_menu.md.

const USE_SOUNDS := {"food": "player/eat", "water": "player/drink", "medical": "player/bandage"}
const HELD := {"food": "food", "water": "water", "medical": "medical"}
const DIG_TOOLS := ["excavate", "dig", "shovel"]

var game: Node                         ## SurvivalGame
var view: HotbarBar
var light: SpotLight3D
var light_on := false
var last_use := ""                     ## the last use's feedback (tests)
var _hand := "~"                       ## the item in hand last applied


func setup(g: Node) -> void:
	game = g
	process_mode = Node.PROCESS_MODE_ALWAYS     # hides the bar while paused panels are open
	view = HotbarBar.new()
	view.name = "HotbarBar"
	game.hud.add_child(view)
	light = SpotLight3D.new()
	light.name = "Flashlight"
	light.light_color = Color(1.0, 0.95, 0.82)
	light.spot_range = 16.0
	light.spot_angle = 22.0
	light.spot_angle_attenuation = 0.8
	light.light_energy = 3.2
	light.shadow_enabled = true
	light.shadow_bias = 0.05
	light.visible = false
	game.add_child(light)
	reset()


## After setup or a load: fill the bar from what the player owns, follow the state.
func reset() -> void:
	var s: GameState = game.state
	Hotbar.fill(s.hotbar, s)
	if not s.changed.is_connected(_on_state_changed):
		s.changed.connect(_on_state_changed)
	_hand = "~"
	apply_hand()


func bar() -> Dictionary:
	return game.state.hotbar


func selected() -> int:
	return int(bar().get("selected", 0))


## The item in hand ("" = empty hands).
func in_hand() -> String:
	return Hotbar.in_hand(bar(), game.state)


func _on_state_changed() -> void:
	Hotbar.fill(bar(), game.state)
	if in_hand() != _hand:
		apply_hand()
		return
	# the weapon changed elsewhere (inventory): follow it on the bar if it's there
	var w: WeaponHandler = game.combat.weapons if game.combat != null else null
	if w != null and WeaponDefs.has(_hand) and w.current_id() != "" and w.current_id() != _hand:
		var i := Hotbar.slot_of(bar(), w.current_id())
		if i >= 0:
			select(i)


# --- input -------------------------------------------------------------------------------

## Bar keys outside build mode and panels (the game calls this). True if handled.
func handle_input(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = (event as InputEventKey).physical_keycode
		if k >= KEY_1 and k <= KEY_8:
			select(k - KEY_1)
			return true
		if k == KEY_X:
			toggle_holster()
			return true
	if event.is_action_pressed("weapon_1"):
		select(0)
		return true
	if event.is_action_pressed("weapon_2"):
		select(1)
		return true
	if event.is_action_pressed("weapon_next"):
		next_weapon()
		return true
	if event.is_action_pressed("reload") and not WeaponDefs.has(in_hand()):
		game.toast("No weapon in hand (1-8 picks one).", "warn")
		return true
	return false


## Selects slot `i` and takes its item in hand (an empty slot: empty hands).
func select(i: int) -> void:
	if i < 0 or i >= Hotbar.SIZE:
		return
	var b := bar()
	var id := Hotbar.at(b, i)
	if id != "" and game.state.inventory.count(id) <= 0:
		game.toast("No %s left." % Items.name_of(id).to_lower(), "warn")
	b["selected"] = i
	b["holstered"] = false
	apply_hand()


## X: empty hands, or take the selected item again.
func toggle_holster() -> void:
	var b := bar()
	b["holstered"] = not b.get("holstered", false)
	apply_hand()


## Q: the next weapon on the bar after the selected slot.
func next_weapon() -> void:
	var i := Hotbar.next_weapon_slot(bar(), game.state, selected())
	if i < 0 or (i == selected() and WeaponDefs.has(in_hand())):
		game.toast("No other weapon on the bar.", "warn")
		return
	select(i)


## Makes the item in hand real: the weapon drawn or holstered, the rig's pose
## and held item, the flashlight.
func apply_hand() -> void:
	var s: GameState = game.state
	var id := in_hand()
	var w: WeaponHandler = game.combat.weapons if game.combat != null else null
	if WeaponDefs.has(id):
		if s.slot_of(id) == "":
			s.equip(id)                     # a weapon on the bar but not equipped: equip it
		if w != null:
			var why := w.switch_to(id)
			if why != "":
				game.toast(why, "warn")
	elif w != null:
		w.holstered = true
	if id != "flashlight":
		light_on = false
	var rig: VoxelRig = game.player.rig if game.player != null else null
	if rig != null:
		var kind := ""
		if id != "" and not WeaponDefs.has(id):
			kind = str(HELD.get(Items.category(id), id))
		rig.set_held(kind)
		rig.carry = id == "flashlight" and light_on
	light.visible = id == "flashlight" and light_on
	_hand = id
	_refresh_view(true)


# --- use ---------------------------------------------------------------------------------

## LMB with the bar's item in hand. Returns false when a weapon is in hand (the
## game then pulls the trigger), true otherwise (the click was used here).
func on_fire_pressed() -> bool:
	var id := in_hand()
	if id == "":
		return true
	if WeaponDefs.has(id):
		return false
	use(id)
	return true


## Uses `id` from the bar. Returns the feedback shown.
func use(id: String) -> String:
	var s: GameState = game.state
	var text := ""
	var kind := "info"
	match Hotbar.use_kind(id):
		"consume":
			var why := s.can_use(id)
			if why != "":
				text = why
				kind = "warn"
			else:
				text = s.use_item(id)
				kind = "good"
				Sfx.play(USE_SOUNDS.get(Items.category(id), "ui/click"))
				if game.player != null:
					game.player.rig.use_t = 1.0
		"hammer":
			game._set_build(true)
			text = "Build mode: B or Esc closes it."
		"flashlight":
			light_on = not light_on
			Sfx.play("ui/click")
			text = "Flashlight on." if light_on else "Flashlight off."
			apply_hand()
		"shovel":
			game._set_build(true)
			var tool := _dig_tool()
			if tool != "" and game.build.active:
				game.build.select_id(tool)
				text = "Pick where to dig."
			else:
				text = "Dig in build mode (B): the excavate tool."
		"crowbar":
			text = "The crowbar opens locked doors and stockrooms on expeditions (equip it in the inventory)."
		"gear":
			if s.has_equipped(id):
				s.unequip(s.slot_of(id))
				text = "%s taken off." % Items.name_of(id)
			else:
				var why := s.equip(id)
				text = why if why != "" else "%s on." % Items.name_of(id)
				kind = "warn" if why != "" else "good"
		_:
			text = "%s can't be used here." % Items.name_of(id)
			kind = "warn"
	last_use = text
	if text != "":
		game.toast(text, kind)
	return text


func _dig_tool() -> String:
	for t in DIG_TOOLS:
		if BuildPieces.index_of(t) >= 0:
			return t
	return ""


# --- frame -------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if game == null or not game._ok:
		return
	if light.visible and game.player != null:
		var rig: VoxelRig = game.player.rig
		var from := rig.hand_global()
		var to: Vector3 = game.player.aim_point
		if from.distance_to(to) > 0.3:
			light.global_position = from
			light.look_at(to, Vector3.UP)
	_refresh_view(false)


func _refresh_view(_force: bool) -> void:
	if view == null or game.hud == null:
		return
	var show: bool = game.hud.mode == "play" and game.debug_modal() == "" and not game.state.dead
	if view.visible != show:
		view.visible = show
	if not show:
		return
	var s: GameState = game.state
	var b := bar()
	var out := []
	for i in Hotbar.SIZE:
		var id := Hotbar.at(b, i)
		out.append({"id": id, "count": Hotbar.count_for(id, s), "owned": id != "" and s.inventory.count(id) > 0})
	view.show_slots(out, selected(), b.get("holstered", false) or in_hand() == "", light_on)


## A line for the dev menu's inspect panel.
func info() -> String:
	return "Bar %s · slot %d · hand %s" % [str(bar()["slots"]), selected() + 1, in_hand() if in_hand() != "" else "empty"]
