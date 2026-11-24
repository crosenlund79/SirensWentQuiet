extends "res://tests/test_case.gd"
## Equipment slots and their effects (SPEC-003 §2): equip / unequip rules,
## auto-equip, losing gear, the vest, the backpack, the hammer, persistence
## and the Experiment 002 migration.


func _gear_run() -> GameState:
	var s := GameState.new_run(5)
	for id in ["shotgun", "vest", "backpack", "flashlight", "crowbar"]:
		s.inventory.add(id, 1)
	return s


func test_start_equipment() -> void:
	var s := GameState.new_run(5)
	check_eq(s.equipment, {"primary": "handgun"}, "only the handgun, as primary")
	check_eq(s.active_weapon(), "handgun", "in hand")
	check_eq(s.weapons, {"handgun": {"loaded": 9}}, "nine rounds in the magazine")
	check_eq(s.inventory.count("handgun"), 1, "the handgun is an owned item")
	check_eq(s.inventory.count("hammer"), 1, "the hammer is at home")
	check_eq(s.equipped("tool"), "", "but not carried")
	check_eq(s.can_build(), "", "owning the hammer is enough to build")


func test_equip_rules_and_reasons() -> void:
	var s := GameState.new_run(5)
	check_eq(s.equip("vest"), "You don't have a protective vest.", "must own it")
	check_eq(s.equip("ghost"), "Unknown item.", "unknown item")
	check_eq(s.equip("water"), "Bottled water can't be equipped.", "not gear")
	s.inventory.add("vest", 1)
	s.unequip("body")
	check_eq(s.equip("vest", "back"), "Protective vest doesn't go in the back slot.", "wrong slot")
	check_eq(s.equip("vest"), "", "equips")
	check_eq(s.equipped("body"), "vest", "in the body slot")
	check_eq(s.equip("vest"), "", "equipping again is fine")
	check(s.has_equipped("vest") and s.slot_of("vest") == "body", "has_equipped / slot_of")
	check(s.unequip("body"), "unequip")
	check(not s.unequip("body"), "nothing left to unequip")
	check(not s.unequip("pocket"), "unknown slot")
	check_eq(s.inventory.count("vest"), 1, "unequipped gear stays in the inventory")
	check_eq(s.equipped("pocket"), "", "unknown slot reads empty")
	var events := [0]
	s.equipment_changed.connect(func(): events[0] += 1)
	s.equip("vest")
	check_eq(events[0], 1, "equipment_changed on equip")
	s.dead = true
	check_eq(s.equip("handgun", "secondary"), "You're dead.", "not when dead")


func test_weapon_slots_swap_and_replace() -> void:
	var s := GameState.new_run(5)
	s.auto_equip = false
	s.inventory.add("shotgun", 1)
	check_eq(s.equipped("secondary"), "", "auto_equip off")
	check_eq(s.equip("shotgun"), "", "goes into the free weapon slot")
	check_eq(s.equipped("secondary"), "shotgun", "secondary")
	check_eq(s.equip("shotgun", "primary"), "", "moved to primary")
	check_eq([s.equipped("primary"), s.equipped("secondary")], ["shotgun", "handgun"], "the two swapped places")
	check_eq(s.active_weapon_slot, "primary", "the hand keeps the slot")
	check_eq(s.active_weapon(), "shotgun", "so the shotgun is now in hand")
	s.unequip("primary")
	check_eq(s.active_weapon(), "handgun", "the other weapon takes over the hand")
	check_eq(s.active_weapon_slot, "secondary", "active slot follows")
	check(not s.set_active_weapon_slot("primary"), "an empty slot can't be in hand")
	check(not s.set_active_weapon_slot("body"), "not a weapon slot")


func test_auto_equip_newly_acquired_gear() -> void:
	var s := _gear_run()
	check_eq(s.equipment, {"primary": "handgun", "secondary": "shotgun", "body": "vest", "back": "backpack",
		"utility": "flashlight", "tool": "crowbar"}, "each into its free slot")
	s.unequip("body")
	s.inventory.add("wood", 1)
	check_eq(s.equipped("body"), "", "a deliberate unequip sticks")
	var t := GameState.new_run(5)
	t.inventory.remove("hammer", 1)
	t.inventory.add("hammer", 1)
	check_eq(t.equipped("tool"), "", "the hammer is never auto-equipped (it only needs to be owned)")
	t.inventory.add("crowbar", 1)
	check_eq(t.equipped("tool"), "crowbar", "so the crowbar finds the tool slot free")
	check_eq(t.equip("hammer"), "", "the hammer can still be equipped by hand")
	check_eq(t.equipped("tool"), "hammer", "replacing the crowbar")
	check_eq(t.inventory.count("crowbar"), 1, "which stays in the inventory")


func test_losing_gear_keeps_state_consistent() -> void:
	var s := _gear_run()
	s.load_rounds("shotgun")
	s.inventory.add("shells", 4)
	check(s.load_rounds("shotgun") == 4 and s.magazine("shotgun") == 4, "shotgun loaded")
	var events := [0]
	s.equipment_changed.connect(func(): events[0] += 1)
	var rep := s.apply_expedition_report({"id": "lost1", "minutes": 30, "lost": {"vest": 1, "shotgun": 1, "crowbar": 1}})
	check_eq(rep["lost"], {"vest": 1, "shotgun": 1, "crowbar": 1}, "lost on the trip")
	check_eq(s.equipped("body"), "", "vest gone from its slot")
	check_eq(s.equipped("secondary"), "", "shotgun gone")
	check_eq(s.equipped("tool"), "", "crowbar gone")
	check(not s.weapons.has("shotgun"), "the magazine went with the gun")
	check(events[0] >= 1, "equipment_changed emitted")
	s.set_active_weapon_slot("primary")
	s.inventory.remove("handgun", 1)
	check_eq(s.active_weapon(), "", "no weapon in hand")
	check_eq(s.magazine("handgun"), 0, "no magazine without the gun")
	s.inventory.add("shotgun", 1)
	check_eq(s.equipped("primary"), "shotgun", "a weapon found later goes into the free primary slot")
	check_eq(s.magazine("shotgun"), 0, "with an empty magazine")
	check_eq(s.active_weapon(), "shotgun", "and into the hand")
	# direct counts edits (no signal) still read consistently
	s.inventory.counts.erase("backpack")
	check(not s.has_equipped("backpack"), "an item that isn't owned never reads as equipped")
	check_eq(s.carry_multiplier(), 1.0, "and has no effect")


func test_vest_reduces_blows_and_blasts_not_needs() -> void:
	var s := GameState.new_run(5)
	s.damage(20.0, "psycho")
	check_eq(s.health, 80.0, "no vest: full damage")
	s.inventory.add("vest", 1)
	check_eq(s.damage_factor("psycho"), 0.65, "factor")
	for cause in ["psycho", "blast", "brute", "expedition"]:
		s.health = 100.0
		s.damage(20.0, cause)
		check(absf(s.health - 87.0) < 1e-6, "%s: -35 %% (%s)" % [cause, s.health])
	check_eq(s.damage_factor("starvation"), 1.0, "starvation isn't a blow")
	check_eq(s.damage_factor("dehydration"), 1.0, "nor is thirst")
	s.health = 100.0
	s.hunger = 0.0
	s.advance(60.0)
	check(absf(s.health - (100.0 - SurvivalTuning.STARVING_DAMAGE)) < 1e-6, "starvation damage is not reduced (%s)" % s.health)
	s.health = 100.0
	s.hunger = 80.0
	var rep := s.apply_expedition_report({"id": "v1", "minutes": 10, "damage": 40.0})
	check_eq(rep["damage"], 40.0, "the trip's injury as reported")
	check(absf(rep["damage_taken"] - 26.0) < 1e-6, "health actually lost with the vest (%s)" % rep["damage_taken"])
	s.unequip("body")
	s.health = 100.0
	s.damage(20.0, "blast")
	check_eq(s.health, 80.0, "unequipped: full damage again")
	s.equip("vest")
	s.cheats["invulnerable"] = true
	s.damage(50.0, "psycho")
	check_eq(s.health, 80.0, "invulnerable still blocks everything")


func test_backpack_carry_multiplier() -> void:
	var s := GameState.new_run(5)
	check_eq(s.carry_multiplier(), 1.0, "no backpack")
	s.inventory.add("backpack", 1)
	check_eq(s.carry_multiplier(), 1.5, "equipped backpack")
	check_eq(s.inventory.cap("wood"), 40, "material caps are storage, unchanged")
	s.unequip("back")
	check_eq(s.carry_multiplier(), 1.0, "owned but not carried")


func test_hammer_is_needed_to_build() -> void:
	var s := GameState.new_run(5)
	check_eq(s.can_build(), "", "owned")
	s.inventory.remove("hammer", 1)
	check_eq(s.can_build(), "You need a hammer.", "lost")
	s.cheats["unlimited"] = true
	check_eq(s.can_build(), "", "the unlimited cheat builds without one")


func test_flashlight_and_crowbar_for_expeditions() -> void:
	var s := GameState.new_run(5)
	check(not s.has_equipped("flashlight") and not s.has_equipped("crowbar"), "none at the start")
	s.inventory.add("flashlight", 1)
	s.inventory.add("crowbar", 1)
	check(s.has_equipped("flashlight") and s.has_equipped("crowbar"), "carried once found")
	s.unequip("utility")
	check(not s.has_equipped("flashlight"), "left at home")


func test_equipment_and_magazines_round_trip() -> void:
	var s := _gear_run()
	s.inventory.add("shells", 3)
	s.load_rounds("shotgun", 2)
	s.set_active_weapon_slot("secondary")
	s.unequip("back")
	s.set_difficulty("hard")
	var t := GameState.from_dict(s.to_dict())
	check(t != null, "restored")
	check_eq(t.to_dict(), s.to_dict(), "identical")
	check_eq(t.equipment, s.equipment, "equipment")
	check_eq(t.magazine("shotgun"), 2, "shotgun magazine")
	check_eq(t.reserve("shotgun"), 1, "shell reserve")
	check_eq(t.active_weapon(), "shotgun", "weapon in hand")
	check_eq(t.difficulty, "hard", "difficulty")
	check_eq(t.equipped("back"), "", "an unequipped backpack stays unequipped after loading")
	t.inventory.add("water", 1)
	check_eq(t.equipped("back"), "", "and later inventory changes don't equip it")


func test_from_dict_cleans_equipment_and_weapons() -> void:
	var d := _gear_run().to_dict()
	d["equipment"] = {"primary": "vest", "secondary": "shotgun", "body": "vest", "back": 5, "utility": "flashlight",
		"tool": "flashlight", "pocket": "crowbar"}
	d["weapons"] = {"handgun": {"loaded": 99}, "shotgun": {"loaded": "3"}, "laser": {"loaded": 4}}
	d["active_weapon"] = "body"
	d["inventory"]["counts"].erase("flashlight")
	var s := GameState.from_dict(d)
	check(s != null, "usable")
	check_eq(s.equipment, {"secondary": "shotgun", "body": "vest"}, "only owned gear in a slot it fits, once")
	check_eq(s.weapons, {"handgun": {"loaded": 12}, "shotgun": {"loaded": 3}}, "magazines clamped, unknown weapons dropped")
	check_eq(s.active_weapon_slot, "secondary", "a bad active slot falls back, then follows the equipped weapon")
	d["equipment"] = "junk"
	d["weapons"] = []
	s = GameState.from_dict(d)
	check_eq(s.equipment, {}, "junk equipment: nothing equipped (no migration for a v2 dict)")
	check_eq(s.weapons, {"handgun": {"loaded": 0}, "shotgun": {"loaded": 0}}, "owned weapons get an empty magazine")
	d["difficulty"] = 7
	check_eq(GameState.from_dict(d).difficulty, "normal", "bad difficulty: Normal")


func test_experiment_002_dicts_get_the_handgun() -> void:
	var d := GameState.new_run(5).to_dict()
	for k in ["difficulty", "equipment", "weapons", "active_weapon", "region"]:
		d.erase(k)
	d["inventory"]["counts"].erase("handgun")
	d["inventory"]["counts"]["ammo"] = 15
	var s := GameState.from_dict(d)
	check(s != null, "restored")
	check_eq(s.difficulty, "normal", "Normal")
	check_eq(s.equipment, {"primary": "handgun"}, "handgun equipped")
	check_eq(s.inventory.count("handgun"), 1, "and owned")
	check_eq(s.magazine("handgun"), 12, "magazine filled from the inventory, up to 12")
	check_eq(s.inventory.count("ammo"), 3, "the rest stays in reserve")
	d["inventory"]["counts"]["ammo"] = 5
	s = GameState.from_dict(d)
	check_eq([s.magazine("handgun"), s.inventory.count("ammo")], [5, 0], "five rounds all go into the magazine")
	d["inventory"]["counts"].erase("ammo")
	s = GameState.from_dict(d)
	check_eq(s.magazine("handgun"), 0, "no rounds: an empty handgun")
	check_eq(s.run["next_invasion_at"], d["run"]["next_invasion_at"], "the schedule is kept")
	check_eq(GameState.from_dict(s.to_dict()).to_dict(), s.to_dict(), "and the migrated state round-trips")
