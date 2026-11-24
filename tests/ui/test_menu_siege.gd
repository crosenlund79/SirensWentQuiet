extends "res://tests/test_case.gd"
## Experiment 004 (E): the main menu's live siege (MenuSiege): a varied house,
## a capped horde that breaks walls without a player, a new round when the
## house is broken enough, the menu flows on top, and nothing left behind.

const MENU := "res://src/menu/main_menu.tscn"


func test_the_siege_builds_attacks_and_starts_a_new_round() -> void:
	var m: Control = (load(MENU) as PackedScene).instantiate()
	m.transition_time = 0.0
	var changes := []
	m.scene_changer = func(path: String): changes.append(path)
	add(m)
	await frames(3)
	var sg: MenuSiege = m.siege
	if not check(sg != null and sg.round == 1, "the first round is built"):
		return
	check(sg.world != null and sg.world.is_inside_tree(), "a real house")
	check(sg.roster.living() >= MenuSiege.FIRST_WAVE, "the first enemies are there")
	check(not (m.get_node("Background") as CanvasItem).visible, "the live view replaced the painted background")
	var walls_before: int = sg.world.sections.size()
	var start := sg.destroyed_share()
	await seconds(8.0)
	check(sg.roster.living() <= MenuSiege.MAX_ENEMIES, "the horde is capped (%d)" % sg.roster.living())
	check(sg.roster.blasts > 0 or sg.destroyed_share() >= start, "the house takes damage")
	check(sg.world.sections.size() >= walls_before, "the sections are tracked")
	# a broken house fades out and a new, different round is built
	var first_world := sg.world
	sg.round_t = MenuSiege.ROUND_SECONDS
	var ok := false
	for i in 600:
		await frames(1)
		if sg.round >= 2 and sg.world != first_world:
			ok = true
			break
	check(ok, "a new round after the limit")
	check(not is_instance_valid(first_world) or not first_world.is_inside_tree(), "the old house is gone")
	# the menu still works on top
	m.open_settings()
	await frames(2)
	check(m.settings_panel().is_open, "Settings opens over the siege")
	m.settings_panel().close()
	m.open_experiments()
	check_eq(changes, [GameLaunch.EXPERIMENTS_SCENE], "Visual Experiments still leaves")
	m.queue_free()
	await frames(3)
	check(not is_instance_valid(sg), "leaving the menu frees the siege")
	var bus := AudioServer.get_bus_index("SFX")
	check(bus < 0 or not AudioServer.is_bus_mute(bus), "the sound is not left muted")
