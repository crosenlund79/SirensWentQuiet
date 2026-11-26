extends "res://tests/test_case.gd"
## Experiment 004 (E): the quick-access bar's rules (Hotbar on GameState.hotbar):
## the default filling (1 = primary, 2 = secondary, then owned items, stable),
## assigning swaps, the item in hand, the slot counts, and the save round trip.


func test_a_new_run_fills_weapons_first_then_items_in_a_stable_order() -> void:
	var s := GameState.new_run(5)
	Hotbar.fill(s.hotbar, s)
	var slots: Array = s.hotbar["slots"]
	check_eq(slots[0], "handgun", "slot 1: the primary weapon")
	check_eq(slots[1], "", "slot 2 waits for a second weapon")
	check(slots.slice(2).has("water") and slots.slice(2).has("canned_food") and slots.slice(2).has("hammer"), "owned items fill the rest (%s)" % [slots])
	check_eq(Hotbar.in_hand(s.hotbar, s), "handgun", "the handgun is in hand")
	var before := slots.duplicate()
	s.inventory.add("shotgun", 1)                # auto-equipped as the secondary weapon
	Hotbar.fill(s.hotbar, s)
	check_eq(s.hotbar["slots"][1], "shotgun", "a second weapon takes slot 2")
	for i in Hotbar.SIZE:
		if i != 1:
			check_eq(s.hotbar["slots"][i], before[i], "slot %d unchanged" % (i + 1))
	# an item the player removed is not put back by itself
	Hotbar.assign(s.hotbar, Hotbar.slot_of(s.hotbar, "water"), "")
	check(not Hotbar.fill(s.hotbar, s) and Hotbar.slot_of(s.hotbar, "water") < 0, "a removed item stays off the bar")


func test_assign_swaps_and_the_hand_follows_the_selection() -> void:
	var s := GameState.new_run(6)
	Hotbar.fill(s.hotbar, s)
	var b := s.hotbar
	var w := Hotbar.slot_of(b, "water")
	check_eq(Hotbar.assign(b, 7, "water"), "", "water into slot 8")
	check_eq(Hotbar.at(b, 7), "water", "slot 8 holds the water")
	check_eq(Hotbar.slot_of(b, "water"), 7, "only once on the bar")
	check(w == 7 or Hotbar.at(b, w) != "water", "its old slot got what was in slot 8")
	check(Hotbar.assign(b, 3, "wood") != "", "materials don't go on the bar")
	b["selected"] = 7
	check_eq(Hotbar.in_hand(b, s), "water", "the selected item is in hand")
	check_eq(Hotbar.count_for("water", s), s.inventory.count("water"), "consumables show their count")
	check_eq(Hotbar.count_for("handgun", s), s.magazine("handgun"), "weapons show the magazine")
	check_eq(Hotbar.count_for("hammer", s), -1, "gear shows no number")
	b["holstered"] = true
	check_eq(Hotbar.in_hand(b, s), "", "holstered: empty hands")
	b["holstered"] = false
	s.inventory.remove("water", s.inventory.count("water"))
	check_eq(Hotbar.in_hand(b, s), "", "an item that ran out leaves the hand empty")
	check_eq(Hotbar.at(b, 7), "water", "but keeps its slot")
	check_eq(Hotbar.use_kind("bandage"), "consume", "bandages are consumed")
	check_eq(Hotbar.use_kind("flashlight"), "flashlight", "the flashlight toggles")
	check_eq(Hotbar.use_kind("vest"), "gear", "worn gear equips")


func test_the_bar_and_the_car_survive_a_save_and_old_saves_load() -> void:
	var s := GameState.new_run(7)
	Hotbar.fill(s.hotbar, s)
	Hotbar.assign(s.hotbar, 5, "bandage")
	s.hotbar["selected"] = 5
	s.car_repaired = true
	var d := s.to_dict()
	var r := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	check(r != null, "restored")
	check_eq(r.hotbar["slots"], s.hotbar["slots"], "slots restored")
	check_eq(int(r.hotbar["selected"]), 5, "selection restored")
	check(r.car_repaired, "the car stays repaired")
	d.erase("hotbar")
	d.erase("car_repaired")
	var old := GameState.from_dict(d)
	check(old != null and not old.car_repaired, "an older save: the car is broken")
	check_eq(old.hotbar["slots"], Hotbar.new_bar()["slots"], "an older save: an empty bar (the game fills it)")
	var junk := Hotbar.clean({"slots": ["handgun", "handgun", 5, "nope", "water"], "selected": 99})
	check_eq(junk["slots"].slice(0, 5), ["handgun", "", "", "", "water"], "duplicates and junk dropped")
	check_eq(int(junk["selected"]), Hotbar.SIZE - 1, "selection clamped")


## Exp 008: a full bar (the flashlight slipped into the second weapon slot)
## still puts a newly found shotgun on key 2; the flashlight stays owned.
func test_a_found_gun_reclaims_the_weapon_slot_on_a_full_bar() -> void:
	var s := GameState.new_run(5)
	for id in ["crowbar", "flashlight"]:
		s.inventory.add(id, 1)
	Hotbar.fill(s.hotbar, s)
	check_eq(str(s.hotbar["slots"][1]), "flashlight", "a full bar put the flashlight on key 2")
	s.inventory.add("shotgun", 1)
	Hotbar.fill(s.hotbar, s)
	check_eq(str(s.hotbar["slots"][1]), "shotgun", "the shotgun takes key 2")
	check_eq(s.inventory.count("flashlight"), 1, "the flashlight is still owned")
