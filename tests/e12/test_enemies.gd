extends "res://tests/test_case.gd"
## Experiment 012 (E): enemy identity, reactions and bodies. Names are
## stable for a seed and unique within a scene; a shout (a real noise event)
## draws a calm enemy to look near its origin without telling it where Eli
## is, and an enemy that sees Eli startles, screams and charges; a killed
## enemy leaves a named body with loot that persists through a home save and
## a POI record round trip; a full inventory leaves the rest on the body.

const Roster := preload("res://src/game/enemy_roster.gd")
const LIVING_ROOM := Vector2(6.0, 8.2)
const FRONT_YARD := Vector2(9.0, 11.2)


class FakeWorld extends Node:
	var poi_id := ""


class FakeGame extends Node3D:
	var roster: Node3D
	var state: GameState
	var world: Variant
	var player: VoxelPlayer
	var corpses: GameCorpses
	var home := true
	var toasts: Array = []
	var _modal := ""

	func is_home() -> bool:
		return home

	func toast(text: String, _kind := "info") -> void:
		toasts.append(text)


## A game root with a house, Eli at `at` and a roster; `poi` != "": a POI game
## (the corpse records go to that POI's record) on the same house geometry.
func _game(s: GameState, at: Vector2, poi := "") -> FakeGame:
	var g := FakeGame.new()
	add(g)
	g.state = s
	var hw := HouseWorld.new()
	g.add_child(hw)
	hw.build_new()
	if poi != "":
		var fw := FakeWorld.new()
		fw.poi_id = poi
		g.add_child(fw)
		g.world = fw
		g.home = false
	else:
		g.world = hw
	g.player = VoxelPlayer.new()
	g.player.input_enabled = false
	g.add_child(g.player)
	g.player.global_position = Vector3(at.x, 0, at.y)
	g.roster = Roster.new()
	g.roster.setup(hw, g.player, 5)
	g.add_child(g.roster)
	g.corpses = GameCorpses.new()
	g.add_child(g.corpses)
	g.corpses.setup(g)
	await physics_frames(2)
	return g


static func _saved(s: GameState) -> GameState:
	return GameState.from_dict(bytes_to_var(var_to_bytes(s.to_dict())))      # as SaveGame stores it


func test_names_are_stable_and_unique() -> void:
	var a := HumanNames.for_enemy("psycho", 4711)
	check(a != "" and a.contains(" "), "a first and a last name (%s)" % a)
	check_eq(HumanNames.for_enemy("psycho", 4711), a, "the same seed, the same name")
	check(HumanNames.MALE.size() >= 150 and HumanNames.FEMALE.size() >= 150 and HumanNames.SURNAMES.size() >= 150, "large pools")
	var fem := 0
	for seed in 60:
		if HumanNames.is_female("psycho", seed):
			fem += 1
			check(HumanNames.FEMALE.has(HumanNames.for_enemy("psycho", seed).split(" ")[0]), "a woman's look gets a woman's name")
	check(fem > 0, "some looks are women (%d of 60)" % fem)
	check_eq(HumanNames.kind_label("brute"), "Brute", "the kind label")
	var g := await _game(GameState.new(), LIVING_ROOM)
	var names := {}
	var v := HumanoidLooks.variety("psycho")
	for i in 14:
		var e: AIEnemy = g.roster.spawn_type("psycho", Vector2(-6.0 + i * 0.6, -5.0), {"mode": "hidden", "appearance": 777})
		check(not names.has(e.display_name), "no duplicate full names (%s)" % e.display_name)
		names[e.display_name] = true
		check_eq(e.appearance % v, 777 % v, "the same look, another name")
		check_eq(e.display_name, HumanNames.for_enemy("psycho", e.appearance), "the name follows the saved seed")
	check_eq(g.roster.enemies[0].kind_label(), "Psycho", "kind_label()")


func test_a_shout_draws_listeners_who_only_hunt_on_sight() -> void:
	var g := await _game(GameState.new(), LIVING_ROOM)
	var listener: AIEnemy = g.roster.spawn_type("psycho", Vector2(17.0, 6.0), {"mode": "wander"})
	var origin := Vector3(15.0, 1.5, 12.0)
	var ev := NoiseEvent.emit(g.world, origin, EnemyReaction.SHOUT_LEVEL, "shout")
	check(int(ev.get("heard", 0)) >= 1, "the shout is a noise event others hear (%s)" % [ev.get("heard")])
	check(listener.is_calm(), "a shout alone never turns it (%s)" % listener.provoked_by)
	check_eq(listener.state_name(), "investigate", "it goes to look")
	check_eq(listener.mind.shouts, 1, "it counted the shout")
	var goal: Vector2 = listener.mind.goal
	check(goal.distance_to(Vector2(origin.x, origin.z)) <= StragglerMind.SHOUT_FUZZ + 1.0, "near the shout's origin (%s)" % goal)
	check(goal.distance_to(LIVING_ROOM) > 4.0, "not to Eli, whom it hasn't seen (%s)" % goal)
	check(listener.mind.alert < StragglerMind.PROVOKE, "alert but not hostile (%.2f)" % listener.mind.alert)
	# Eli steps out in front of it: it sees him, startles, screams and charges.
	var shouts0 := EnemyReaction.shouts_total
	g.player.global_position = Vector3(19.5, 0, 11.5)
	for i in 300:
		await physics_frames(1)
		if not listener.is_calm() and listener.reaction.phase != "react":
			break
	check(not listener.is_calm() and listener.provoked_by == "saw Eli", "seeing Eli turns it (%s)" % listener.provoked_by)
	check(listener.reaction.reactions >= 1 and EnemyReaction.shouts_total > shouts0, "it reacted and screamed")
	check(listener.reaction.phase in ["charge", "done"], "then it runs at him (%s)" % listener.reaction.phase)
	# An invader sees Eli for the first time: the same reaction, without a mind.
	var inv: AIEnemy = g.roster.spawn_type("runner", Vector2(19.5, 4.5), {"invader": true})
	inv.set_facing(PI)
	for i in 30:
		await physics_frames(1)
	check(inv.reaction.reactions >= 1, "a hostile runner reacts on first sight too (%s)" % inv.reaction.phase)
	var bomber: AIEnemy = g.roster.spawn_type("bomber", Vector2(20.0, 14.0), {"mode": "wander"})
	check(bomber.reaction == null, "the bomber keeps its own behaviour")


func test_a_body_persists_with_name_and_loot() -> void:
	var s := GameState.new()
	var g := await _game(s, LIVING_ROOM)
	var e: AIEnemy = g.roster.spawn_type("brute", FRONT_YARD + Vector2(3.0, 1.0), {"mode": "hidden"})
	var who := e.display_name
	e.take_damage(99, Vector3.RIGHT, "shot")
	await physics_frames(2)
	check_eq(g.corpses.last_downed, "%s — Brute — Downed" % who, "the downed toast")
	check(g.toasts.has(g.corpses.last_downed), "shown in the HUD's toasts")
	check_eq((s.home["corpses"] as Array).size(), 1, "the body is recorded at home when it dies")
	await seconds(Corpse.SETTLE + 0.4)
	check(not is_instance_valid(e), "the enemy itself is gone")
	check_eq(g.corpses.bodies.size(), 1, "a Corpse took its place")
	var c: Corpse = g.corpses.bodies[0]
	check_eq(c.display_name, who, "it keeps its name")
	check(c.visual != null and c.rig != null and c.rig.get_parent() == c.visual, "the rig is under the single visual node")
	check(c.is_in_group(Corpse.GROUP), "in the corpses group")
	c.items.clear()
	c.items["canned_food"] = 2
	c.items["nails"] = 7
	check_eq(c.interact_prompt(), "[E] Search %s" % who, "the prompt names it")
	# A home save and load: the body is rebuilt with its name and loot.
	var s2 := _saved(s)
	g.queue_free()
	await physics_frames(2)
	var g2 := await _game(s2, LIVING_ROOM)
	check_eq(g2.corpses.bodies.size(), 1, "rebuilt after loading")
	var c2: Corpse = g2.corpses.bodies[0]
	check_eq(c2.display_name, who, "same name")
	check_eq(c2.kind, "brute", "same kind")
	check_eq(c2.items, {"canned_food": 2, "nails": 7}, "same loot")
	check(c2.rig is HumanoidRig and (c2.rig as HumanoidRig).dead, "lying in its collapse pose")
	# At a POI: the record keeps it between visits and through a save.
	g2.queue_free()
	await physics_frames(2)
	var g3 := await _game(s2, LIVING_ROOM, "convenience")
	var p: AIEnemy = g3.roster.spawn_type("psycho", FRONT_YARD + Vector2(3.0, 1.0), {"mode": "hidden"})
	var pn := p.display_name
	p.kill_quietly()
	await seconds(Corpse.SETTLE + 0.4)
	var rec := PoiState.record(s2, "convenience")
	check_eq((rec.get("corpses", []) as Array).size(), 1, "recorded in the POI record")
	check_eq(g3.corpses.bodies.size(), 1, "the home's body isn't at the POI")
	g3.corpses.bodies[0].items["water"] = 1
	var s3 := _saved(s2)
	g3.queue_free()
	await physics_frames(2)
	var g4 := await _game(s3, LIVING_ROOM, "convenience")
	check_eq(g4.corpses.bodies.size(), 1, "back at the POI: the body is still there")
	check_eq((g4.corpses.bodies[0] as Corpse).display_name, pn, "with its name")
	check(int((g4.corpses.bodies[0] as Corpse).items.get("water", 0)) >= 1, "and what was left on it")


func test_full_inventory_leaves_the_rest_on_the_body() -> void:
	var s := GameState.new()
	var room := s.inventory.space_for("wood")
	s.inventory.add("wood", room - 1)
	var d := Corpse.clean({"pos": [1.0, 0.0, 1.0], "kind": "psycho", "app": 3, "items": {"wood": 3, "snacks": 1}})
	var panel := StoragePanel.new()
	add(panel)
	panel.open(s, "corpse", d["items"], "Test")
	d["searched"] = true
	var got := panel.take_everything()
	check_eq(int(got.get("wood", 0)), 1, "only what fits is taken")
	check_eq(d["items"], {"wood": 2}, "the rest stays on the body")
	check(not Corpse.is_spent(d), "it stays searchable")
	var c := Corpse.new()
	add(c)
	c.rebuild(d)
	check(c.interact_prompt().begins_with("[E] Search") and c.interact_prompt().contains("2 planks"), "the prompt says what is left (%s)" % c.interact_prompt())
	panel.close()
	s.inventory.remove("wood", 10)
	panel.open(s, "corpse", d["items"], "Test")
	panel.take_everything()
	check(Corpse.is_spent(d) and c.interact_prompt() == "", "emptied: nothing more to search")
	var loot_bodies := 0
	for seed in 200:
		if not Corpse.roll_loot("runner", seed, seed).is_empty():
			loot_bodies += 1
		for id in Corpse.roll_loot("brute", seed, seed):
			check(Items.has(id), "existing items only (%s)" % id)
	check(loot_bodies > 80 and loot_bodies < 200, "not every body has loot (%d of 200 runners)" % loot_bodies)
