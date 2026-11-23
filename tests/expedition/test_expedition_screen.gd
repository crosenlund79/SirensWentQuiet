extends "res://tests/test_case.gd"
## ExpeditionScreen (E): the flow emits finished once, cancelled on Turn back,
## disabled entries and options explain themselves, the state is never mutated.

const D := preload("res://src/expedition/expedition_data.gd")


func _state(minute := 8 * 60.0, seed := 77) -> GameState:
	var s := GameState.new_run(seed)
	s.total_minutes = 1440.0 + minute
	return s


func _screen(instant := true) -> ExpeditionScreen:
	var sc := ExpeditionScreen.new()
	sc.instant = instant
	add(sc)
	return sc


func test_turn_back_emits_cancelled_once() -> void:
	var s := _state()
	var sc := _screen()
	var log := []
	sc.cancelled.connect(func(): log.append("cancelled"))
	sc.finished.connect(func(_r): log.append("finished"))
	sc.open(s)
	check_eq(sc.step, "list", "opens on the destination list")
	check(sc.visible and sc.is_open, "visible")
	check_eq(sc.destination_buttons.size(), 4, "four destinations listed")
	sc.back_button.pressed.emit()
	check_eq(log, ["cancelled"], "Turn back emits cancelled only")
	check(not sc.is_open, "closed")
	sc.cancel()
	check_eq(log.size(), 1, "no second emit once closed")


func test_full_flow_emits_finished_once_and_never_mutates_state() -> void:
	var s := _state()
	s.inventory.add("backpack", 1)
	var before := s.to_dict()
	var sc := _screen()
	var got := []
	sc.finished.connect(func(r): got.append(r))
	sc.cancelled.connect(func(): got.append("cancelled"))
	sc.open(s)
	sc.select_destination("homes")
	sc.primary_button.pressed.emit()
	check_eq(sc.step, "gear", "gear step")
	check(sc.ammo_slider != null and sc.ammo_slider.max_value == 9, "rounds 0..owned")
	sc.ammo_slider.value = 3
	check_eq(sc.brought_gear()["ammo"], 3, "slider sets the rounds")
	check(sc.tool_boxes["backpack"].button_pressed and not sc.tool_boxes["backpack"].disabled, "owned backpack offered and ticked")
	check(sc.tool_boxes["crowbar"].disabled, "a tool you don't own can't be ticked")
	sc.tool_boxes["backpack"].button_pressed = false
	check(not sc.brought_gear().has("backpack"), "unticking leaves it home")
	sc.tool_boxes["backpack"].button_pressed = true
	sc.primary_button.pressed.emit()
	check_eq(sc.step, "confirm", "confirm step")
	sc.primary_button.pressed.emit()
	check_eq(sc.step, "event", "the first event")
	var events := 0
	while sc.step == "event" and events < 4:
		events += 1
		var i := sc.run.first_available_option()
		check(not sc.option_buttons[i].disabled, "the available option's button is enabled")
		sc.option_buttons[i].pressed.emit()
		check_eq(sc.step, "outcome", "outcome after a choice")
		sc.primary_button.pressed.emit()
	check(events >= 1 and events <= 2, "one or two events (%d)" % events)
	check_eq(sc.step, "report", "the report")
	check_eq(got.size(), 0, "nothing emitted before Return home")
	sc.primary_button.pressed.emit()
	sc.return_home()
	sc.primary_button.pressed.emit()
	check_eq(got.size(), 1, "finished emitted exactly once")
	check_eq(s.to_dict(), before, "the screen never touches the GameState")
	if got.size() == 1:
		var r: Dictionary = got[0]
		check_eq(r["destination"], "homes", "destination")
		check_eq(r["brought"].get("ammo", 0), 3, "brought what was chosen")
		for k in ["id", "name", "minutes", "gained", "consumed", "lost", "left_behind", "damage", "events", "summary"]:
			check(r.has(k), "result has %s" % k)
		check_eq(r, ExpeditionRun.simulate(s, "homes", {"ammo": 3, "backpack": 1}, sc.run.choices), "same result as the resolver for the same choices")
		var n := s.apply_expedition(r)
		check(typeof(n) == TYPE_ARRAY, "the game can apply it")
		check_eq(int(s.run["expeditions"]), 1, "applied once")


func test_unavailable_destinations_explain_and_block() -> void:
	var s := _state(19 * 60.0)
	var sc := _screen()
	sc.open(s)
	for id in D.ORDER:
		sc.select_destination(id)
		check(sc.primary_button.disabled, "%s blocked at 19:00" % id)
		check(sc.destination_buttons[id].text.contains("Unavailable"), "the entry says so (%s)" % sc.destination_buttons[id].text)
	sc.select_destination("homes")
	sc.destination_buttons["homes"].pressed.emit()
	check_eq(sc.step, "list", "pressing a blocked entry stays on the list")
	var s2 := _state()
	sc.open(s2)
	sc.select_destination("clinic")
	check(sc.primary_button.disabled, "clinic blocked without a flashlight")
	check(sc.primary_button.tooltip_text.to_lower().contains("flashlight"), "with the reason (%s)" % sc.primary_button.tooltip_text)
	sc.select_destination("homes")
	check(not sc.primary_button.disabled, "homes open at 08:00")


func test_disabled_options_show_why() -> void:
	var s := _state()
	var sc := _screen()
	sc.open(s)
	sc.select_destination("grocery")
	sc.to_gear()
	sc.set_ammo(0)
	sc.to_confirm()
	sc.depart()
	# force a known event for the check
	sc.run.event_ids.assign(["storage_door"])
	sc.run.step = 0
	sc._show_event()
	check_eq(sc.option_buttons.size(), 3, "three options")
	check(sc.option_buttons[2].disabled, "forcing the door needs a crowbar")
	check(sc.option_buttons[2].text.contains("crowbar"), "the button says why (%s)" % sc.option_buttons[2].text)
	sc.choose_option(2)
	check_eq(sc.step, "event", "a disabled option can't be chosen")


func test_escape_steps_back() -> void:
	var s := _state()
	var sc := _screen()
	var cancelled := [0]
	sc.cancelled.connect(func(): cancelled[0] += 1)
	sc.open(s)
	sc.select_destination("homes")
	sc.to_gear()
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	tree.root.push_input(esc)
	check_eq(sc.step, "list", "Esc in the gear step goes back to the list")
	tree.root.push_input(esc)
	check_eq(cancelled[0], 1, "Esc on the list turns back")


func test_animated_flow_runs_while_paused() -> void:
	var s := _state()
	var sc := _screen(false)
	var got := []
	sc.finished.connect(func(r): got.append(r))
	tree.paused = true
	sc.open(s)
	await seconds(0.9)
	sc.select_destination("homes")
	sc.to_gear()
	await seconds(0.4)
	check_eq(sc.step, "gear", "gear while paused")
	sc.to_confirm()
	await seconds(0.4)
	sc.depart()
	var t := 0
	while sc.step != "report" and t < 400:
		if sc.step == "event":
			sc.choose_option(sc.run.first_available_option())
		elif sc.step == "outcome":
			sc.continue_on()
		await frames(1)
		t += 1
	check_eq(sc.step, "report", "reached the report with fades and the travel pause")
	await seconds(0.4)
	sc.return_home()
	await seconds(0.8)
	tree.paused = false
	check_eq(got.size(), 1, "finished once")
	check(not sc.visible, "faded out and hidden")
