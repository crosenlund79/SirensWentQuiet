extends "res://tests/test_case.gd"
## Developer menu: edits GameState directly and calls the game's dev API.

const U := preload("res://tests/ui/ui_test_util.gd")


class FakeGame extends Node:
	var calls := []
	func dev_spawn(n: int) -> void: calls.append(["spawn", n])
	func dev_trigger_invasion() -> void: calls.append(["invasion"])
	func dev_repair_house() -> void: calls.append(["repair"])
	func dev_advance(minutes: float) -> void: calls.append(["advance", minutes])
	func dev_skip_to(hour: int) -> void: calls.append(["skip", hour])
	func dev_set_time_scale(x: float) -> void: calls.append(["scale", x])
	func dev_info() -> String: return "fake game: 0 enemies"


func _press(m: DevMenu, text: String) -> void:
	var b := m.button(text)
	if check(b != null, "button '%s' exists" % text):
		b.pressed.emit()


func test_dev_menu_calls_game_and_edits_state() -> void:
	var state := GameState.new_run(2)
	var game: FakeGame = add(FakeGame.new())
	var m: DevMenu = add(DevMenu.new())
	m.setup(state, game)
	check(not m.visible, "hidden until F10")
	m.toggle()
	await frames(2)
	check(m.visible and m.is_open, "toggle opens")
	check(m.process_mode == Node.PROCESS_MODE_ALWAYS, "works while paused")
	_press(m, "+1 hour")
	_press(m, "Night 20:00")
	_press(m, "Morning 06:00")
	_press(m, "Next invasion")
	_press(m, "Spawn 1 psycho")
	_press(m, "Spawn 3 psychos")
	_press(m, "Repair house")
	_press(m, "×4")
	_press(m, "×10")
	_press(m, "×1")
	check_eq(game.calls, [["advance", 60.0], ["skip", 20], ["skip", 6], ["invasion"], ["spawn", 1], ["spawn", 3], ["repair"],
		["scale", 4.0], ["scale", 10.0], ["scale", 1.0]], "dev API calls")
	# cheats
	m.button("Invulnerable").button_pressed = true
	check(state.cheats["invulnerable"], "invulnerable on")
	m.button("Unlimited resources").button_pressed = true
	check(state.cheats["unlimited"], "unlimited on")
	m.button("Unlimited resources").button_pressed = false
	check(not state.cheats["unlimited"], "unlimited off")
	# supplies
	var ammo := state.inventory.count("ammo")
	_press(m, "+ 10 ammo")
	check_eq(state.inventory.count("ammo"), ammo + 10, "+10 ammo")
	var water := state.inventory.count("water")
	_press(m, "+ Food & water")
	check(state.inventory.count("water") > water, "food and water added")
	_press(m, "+ Materials")
	check_eq(state.inventory.count("wood"), 26, "planks added")
	_press(m, "+ Materials")
	check_eq(state.inventory.count("wood"), 40, "capped at 40")
	check(m.last_status.contains("storage full"), "says when storage is full")
	_press(m, "All tools")
	check(state.inventory.count("crowbar") == 1 and state.inventory.count("hammer") == 1, "tools, no duplicate hammer")
	# needs
	(m.find_child("Need_hunger_25", true, false) as Button).pressed.emit()
	check_eq(state.hunger, 25.0, "hunger set to 25")
	(m.find_child("Need_hydration_0", true, false) as Button).pressed.emit()
	check_eq(state.hydration, 0.0, "hydration set to 0")
	(m.find_child("Need_energy_100", true, false) as Button).pressed.emit()
	check_eq(state.energy, 100.0, "energy set to 100")
	# inspect
	var text := m.inspect_text()
	for part in ["Day 1", "next invasion", "fake game: 0 enemies", "save", "inventory"]:
		check(text.contains(part), "inspect shows '%s'" % part)
	m.toggle()
	check(not m.visible, "toggle closes")


func test_dev_menu_without_game_methods_does_not_crash() -> void:
	var state := GameState.new_run(2)
	var bare: Node = add(Node.new())
	var m: DevMenu = add(DevMenu.new())
	m.setup(state, bare)
	m.toggle()
	await frames(1)
	_press(m, "Spawn 3 psychos")
	check(m.last_status.contains("dev_spawn"), "explains the missing method")
	check(m.next_invasion_text().contains("Day 3 22:00"), "next invasion computed from run.next_invasion_at")
