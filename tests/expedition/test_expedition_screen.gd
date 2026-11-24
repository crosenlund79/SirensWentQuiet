extends "res://tests/test_case.gd"
## ExpeditionScreen: the flow emits finished once, cancelled on Turn back,
## disabled entries and options explain themselves, the state is never mutated;
## Experiment 003: discovered places only, grouped, the plan step (approach,
## target, gear) and the map's planned destination preselected.

const D := preload("res://src/expedition/expedition_data.gd")


func _state(minute := 8 * 60.0, seed := 77) -> GameState:
	var s := GameState.new_run(seed)
	s.total_minutes = 1440.0 + minute
	s.inventory.add("handgun", 1)
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
	check_eq(sc.destination_buttons.size(), RegionState.START_KNOWN.size(), "the known places are listed")
	for id in sc.destination_buttons:
		check(s.region.is_discovered(id), "only discovered places (%s)" % id)
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
	for id in sc.destination_buttons.keys():
		sc.select_destination(id)
		check(sc.primary_button.disabled, "%s blocked at 19:00" % id)
		check(UiTheme.caption_of(sc.destination_buttons[id]).contains("unavailable"), "the entry says so (%s)" % UiTheme.caption_of(sc.destination_buttons[id]))
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


# --- Experiment 003 -----------------------------------------------------------------------

func test_list_is_grouped_and_grows_with_discovery() -> void:
	var s := _state()
	var sc := _screen()
	sc.open(s)
	var cats := []
	for id in sc.listed_ids():
		var c: String = D.destination(id)["category"]
		if cats.is_empty() or cats[-1] != c:
			check(not c in cats, "categories are grouped (%s)" % c)
			cats.append(c)
	check(not sc.destination_buttons.has("military"), "undiscovered places are not listed")
	sc.cancel()
	s.region.discover_all()
	sc.open(s)
	check_eq(sc.destination_buttons.size(), 24, "all 24 places once discovered")
	check_eq(sc.listed_ids(), D.ORDER, "display order")
	var sections := sc._panel.find_children("*", "HBoxContainer", true, false).filter(func(n): return n.has_meta("category"))
	check_eq(sections.map(func(n): return n.get_meta("category")), D.CATEGORY_ORDER, "one header per category, in order")


func test_planned_destination_and_purpose_are_preselected() -> void:
	var s := _state()
	s.region.plan("hardware", "targeted:wood")
	var sc := _screen()
	sc.open(s)
	check(sc.preselected_plan, "the plan is used")
	check_eq(sc.selected, "hardware", "planned destination selected")
	check_eq(sc.approach, "targeted", "planned approach")
	check_eq(sc.target, "wood", "planned target")
	check(UiTheme.caption_of(sc.destination_buttons["hardware"]).begins_with("planned"), "the entry says it's planned")
	sc.to_gear()
	check_eq(sc.step, "gear", "plan step")
	check(sc.approach_buttons["targeted"].has_theme_stylebox_override("normal"), "the planned approach is marked")
	check(sc.target_buttons.has("wood") and sc.target_buttons["wood"].has_theme_stylebox_override("normal"), "the planned target is marked")
	sc.to_confirm()
	sc.depart()
	check(sc.run != null and sc.run.approach == "targeted" and sc.run.target == "wood", "the run uses the plan")
	# an undiscovered plan is ignored
	var s2 := _state()
	s2.region.plan("military", "raid")
	sc.cancel()
	var sc2 := _screen()
	sc2.open(s2)
	check(not sc2.preselected_plan and sc2.selected != "military", "an undiscovered plan is not preselected")
	check_eq(sc2.approach, "general", "default approach")


func test_plan_step_approaches_and_gear() -> void:
	var s := _state()
	s.inventory.counts.erase("ammo")
	var sc := _screen()
	sc.open(s)
	sc.select_destination("grocery")
	sc.to_gear()
	check_eq(sc.approach_buttons.size(), 4, "four approaches")
	sc.select_approach("raid")
	check(not sc.plan_state()["ok"], "a raid needs rounds")
	check(sc.primary_button.disabled, "Continue is disabled")
	check(sc.primary_button.tooltip_text.contains("loaded weapon"), "with the reason (%s)" % sc.primary_button.tooltip_text)
	sc.to_confirm()
	check_eq(sc.step, "gear", "can't continue without rounds")
	sc.select_approach("careful")
	check(sc.plan_state()["ok"], "careful needs nothing")
	sc.select_approach("targeted")
	check(sc.target in D.targets("grocery") and not sc.target_buttons.is_empty(), "targets offered (%s)" % sc.target)
	sc.set_target("water")
	check_eq(sc.target, "water", "target set")
	sc.set_target("stone")
	check_eq(sc.target, "water", "a resource the place doesn't have is refused")
	# with rounds the raid opens
	var s2 := _state()
	s2.inventory.add("shotgun", 1)
	s2.inventory.add("shells", 4)
	var sc2 := _screen()
	sc2.open(s2)
	sc2.select_destination("grocery")
	sc2.to_gear()
	check(sc2.shells_slider != null and sc2.shells_slider.max_value == 4, "shells slider with the shotgun")
	sc2.select_approach("raid")
	check(sc2.plan_state()["ok"], "rounds brought: the raid is possible")
	sc2.set_ammo(0)
	sc2.set_shells(1)
	check(not sc2.plan_state()["ok"], "one shell is not enough for a raid")
	sc2.set_shells(2)
	check(sc2.plan_state()["ok"], "two shells count as four rounds")
	sc2.to_confirm()
	check_eq(sc2.step, "confirm", "confirm")
	sc2.depart()
	check(sc2.run != null and sc2.run.approach == "raid", "raid run")
	check_eq(sc2.run.gear.get("shells", 0), 2, "brought two shells")


func test_report_shows_discoveries_and_the_place() -> void:
	var s := _state(9 * 60.0, 5)
	var sc := _screen()
	var got := []
	sc.finished.connect(func(r): got.append(r))
	var found := false
	for seed in range(1, 40):
		s.run["seed"] = seed
		sc.open(s)
		sc.select_destination("homes")
		sc.to_gear()
		sc.select_approach("careful")
		sc.to_confirm()
		sc.depart()
		while sc.step == "event":
			sc.choose_option(0 if sc.run.option_state(0)["ok"] else sc.run.first_available_option())
			sc.continue_on()
		check_eq(sc.step, "report", "report")
		if not (sc.result["discovered"] as Array).is_empty():
			found = true
			var texts := []
			for l in sc._panel.find_children("*", "Label", true, false):
				texts.append((l as Label).text)
			var all := "\n".join(texts)
			check(all.contains(RegionLocations.name_of(sc.result["discovered"][0])), "the report names the new place")
			check(all.contains("NEW PLACES"), "in its own row")
			check(not s.region.is_discovered(sc.result["discovered"][0]), "the screen doesn't apply it")
			sc.return_home()
			break
		sc.return_home()
	check(found, "careful exploration found a place within 40 seeds")
	check(not got.is_empty(), "finished emitted")
