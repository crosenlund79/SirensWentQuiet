extends "res://tests/test_case.gd"
## Experiment 005 (F): storage furniture (transfers without duplication or
## loss, capacities, categories, weapons' magazines), contents per piece
## saved with the world, loot piles from destroyed and demolished storage,
## furniture_items / furniture_layout_changed for comfort, placing and moving
## furniture in build mode (validation, Move with contents, salvage vs full
## refund), placed lamps, and one smoke run in the real game (E at the fridge,
## the panel, F10 Furniture).


func _world() -> HouseWorld:
	var w := HouseWorld.new()
	add(w)
	w.build_new()
	await physics_frames(2)
	return w


func _build_mode(w: HouseWorld, unlimited := true) -> Array:
	var s := GameState.new_run(7)
	s.cheats["unlimited"] = unlimited
	var b := BuildMode.new()
	b.setup(w, s, null, null)
	add(b)
	await physics_frames(1)
	return [s, b]


static func _sum(s: GameState, items: Dictionary, id: String) -> int:
	return s.inventory.count(id) + int(items.get(id, 0))


func test_transfers_never_duplicate_or_lose() -> void:
	var s := GameState.new_run(3)
	var box := {}
	s.inventory.add("canned_food", 5)
	var total := _sum(s, box, "canned_food")
	check_eq(FurnitureStorage.store(s, box, "fridge", "canned_food", 3), 3, "three cans into the fridge")
	check_eq(_sum(s, box, "canned_food"), total, "no can appears or vanishes")
	check_eq(FurnitureStorage.store(s, box, "fridge", "canned_food", 99), total - 3, "put all moves only what is carried")
	check_eq(s.inventory.count("canned_food"), 0, "the pool is empty of cans")
	check_eq(FurnitureStorage.store(s, box, "fridge", "nails", 5), 0, "nails don't go in the fridge")
	check(FurnitureStorage.accepts("storage_chest", "nails") and FurnitureStorage.accepts("storage_chest", "shotgun"), "a chest takes anything")
	check_eq(FurnitureStorage.take(s, box, "canned_food", 2), 2, "two taken out")
	check_eq(_sum(s, box, "canned_food"), total, "still the same total")
	# capacity
	var small := {}
	s.inventory.add("bandage", 20)
	check_eq(FurnitureStorage.store(s, small, "nightstand", "bandage", 20), 8, "a nightstand holds 8")
	check_eq(FurnitureStorage.space_left("nightstand", small), 0, "and is full")
	check_eq(FurnitureStorage.store(s, small, "nightstand", "bandage", 1), 0, "nothing more fits")
	# the pool's caps limit taking out; the rest stays stored
	var shelf := {"wood": 30}
	s.inventory.add("wood", 1000)
	var room := s.inventory.space_for("wood")
	check_eq(room, 0, "the plank cap is reached")
	check_eq(FurnitureStorage.take(s, shelf, "wood", 30), 0, "nothing comes out over the cap")
	check_eq(int(shelf["wood"]), 30, "and nothing is lost")
	s.inventory.remove("wood", 5)
	check_eq(FurnitureStorage.take_all(s, shelf), {"wood": 5}, "take everything stops at the cap")
	check_eq(int(shelf["wood"]), 25, "25 stay on the shelf")
	# a stored weapon unloads its magazine into the pool first
	check(s.inventory.count("handgun") == 1 and s.magazine("handgun") > 0, "the start handgun is loaded (%d)" % s.magazine("handgun"))
	var rounds := s.rounds_carried("ammo")
	var wardrobe := {}
	check_eq(FurnitureStorage.store(s, wardrobe, "wardrobe", "handgun", 1), 1, "the handgun goes in the wardrobe")
	check_eq(s.rounds_carried("ammo"), rounds, "its rounds stay in the pool (%d)" % rounds)
	check_eq(FurnitureStorage.take(s, wardrobe, "handgun", 1), 1, "and comes back out")
	# eating straight from storage
	s.hunger = 40.0
	box["snacks"] = 1
	var r := FurnitureStorage.use_from(s, box, "snacks")
	check(r["ok"] and s.hunger > 40.0 and not box.has("snacks"), "eaten from the fridge (%s)" % r["text"])
	s.hunger = 100.0
	box["snacks"] = 1
	var snacks := s.inventory.count("snacks")
	check(not FurnitureStorage.use_from(s, box, "snacks")["ok"], "full: refused")
	check(int(box.get("snacks", 0)) == 1 and s.inventory.count("snacks") == snacks, "and nothing moved")
	check_eq(FurnitureStorage.clean({"water": 2.0, "bogus": 4, "nails": -3, "wood": "x"}), {"water": 2}, "save data is cleaned")


func test_contents_per_piece_saved_with_the_world() -> void:
	var w: HouseWorld = await _world()
	check_eq(w.storage_of("fridge"), {"canned_food": 1, "water": 1}, "a new house has a little in the fridge")
	check(w.storage_of("wardrobe").is_empty(), "the wardrobe starts empty")
	var spots := w.furniture.storage_spots()
	check(spots.size() >= 10, "the house's storage pieces are interactables (%d)" % spots.size())
	check(w.interactables().has(w.furniture.pieces["wardrobe"]["spot"]), "the wardrobe's spot is one of the world's interactables")
	check_eq(w.furniture.spot_prompt("fridge"), "[E] Open the fridge (2/24)")
	w.storage_of("wardrobe")["vest"] = 1
	w.storage_of("counter_a")["snacks"] = 3
	var layout := [0]
	w.furniture_layout_changed.connect(func() -> void: layout[0] += 1)
	var chest := w.place_object("storage_chest", Vector2(-2.0, 5.0), 1, true)
	check(layout[0] >= 1, "placing furniture emits furniture_layout_changed")
	chest.items["nails"] = 12
	var lamp := w.place_object("floor_lamp", Vector2(-2.0, 3.0), 0, true)
	lamp.set_lamp(false)
	check(chest.uid != "" and w.storage_of(chest.uid) == {"nails": 12}, "storage_of(uid) is the chest's contents")
	check_eq(chest.interact_prompt(), "[E] Open the storage chest (12/80)")
	var types := {}
	for it in w.furniture_items():
		types[it["type"]] = true
		check(it.has("rect") and it.has("rot") and it.has("state") and it.has("id"), "item %s has the SPEC fields" % it["type"])
	for t in ["sofa", "bed", "rug", "storage_chest", "floor_lamp", "fridge", "wardrobe"]:
		check(types.has(t), "furniture_items lists %s" % t)
	var d := w.save_data()
	var w2 := HouseWorld.new()
	add(w2)
	check(w2.load_data(d), "the save loads")
	await physics_frames(1)
	check_eq(w2.storage_of("wardrobe"), {"vest": 1}, "the wardrobe's vest is back")
	check_eq(w2.storage_of("counter_a"), {"snacks": 3}, "the counter's snacks are back")
	check_eq(w2.storage_of("fridge"), {"canned_food": 1, "water": 1}, "the fridge too")
	var c2 := w2.object_by_uid(chest.uid)
	check(c2 != null and c2.kind == "storage_chest" and c2.rot == 1, "the placed chest is back with its id")
	check(c2 != null and c2.items == {"nails": 12}, "with its nails")
	var l2: WorldObject = null
	for o in w2.objects:
		if o.kind == "floor_lamp":
			l2 = o
	check(l2 != null and not l2.lamp_on, "the lamp's own switch is saved")
	var n := WorldObject.new_uid()
	check(n != chest.uid, "new ids don't repeat loaded ones")


func test_destroyed_and_demolished_storage_drop_a_loot_pile() -> void:
	var w: HouseWorld = await _world()
	w.storage_of("wardrobe")["vest"] = 1
	w.storage_of("wardrobe")["medkit"] = 2
	w.furniture.destroy("wardrobe")
	check(w.storage_of("wardrobe").is_empty(), "the wrecked wardrobe holds nothing")
	var piles := w.objects.filter(func(o): return o.kind == "loot_pile")
	check_eq(piles.size(), 1, "a pile lies where it broke")
	var pile: WorldObject = piles[0] if not piles.is_empty() else null
	check(pile != null and pile.items == {"vest": 1, "medkit": 2}, "with everything that was inside")
	check_eq(pile.interact_prompt() if pile != null else "", "[E] Search the pile")
	w.damage_object(pile, 50)
	check(w.objects.has(pile), "a pile can't be shot or smashed away")
	# a placed chest demolished next to it: its contents join the pile
	var chest := w.place_object("storage_chest", Vector2(-2.0, 5.0), 0, true)
	chest.items["water"] = 3
	w.remove_object(chest)
	var piles2 := w.objects.filter(func(o): return o.kind == "loot_pile")
	check_eq(piles2.size(), 2, "the demolished chest leaves its own pile")
	var total := {}
	for p in piles2:
		FurnitureStorage.merge(total, p.items)
	check_eq(total, {"vest": 1, "medkit": 2, "water": 3}, "nothing vanished")
	# demolishing an original drawer with something in it
	w.storage_of("dresser")["bandage"] = 1
	w.demolish_furniture("dresser")
	var all := {}
	for p in w.objects.filter(func(o): return o.kind == "loot_pile"):
		FurnitureStorage.merge(all, p.items)
	check_eq(int(all.get("bandage", 0)), 1, "a demolished dresser drops its bandage")
	# piles are saved
	var w2 := HouseWorld.new()
	add(w2)
	check(w2.load_data(w.save_data()), "the save loads")
	var back := {}
	for p in w2.objects.filter(func(o): return o.kind == "loot_pile"):
		FurnitureStorage.merge(back, p.items)
	check_eq(back, all, "the piles and their contents are saved")


func test_place_validate_move_and_demolish_furniture() -> void:
	var w: HouseWorld = await _world()
	var sb: Array = await _build_mode(w, false)
	var s: GameState = sb[0]
	var b: BuildMode = sb[1]
	s.inventory.add("wood", 40)
	s.inventory.add("nails", 80)
	s.inventory.add("scrap", 20)
	check_eq(BuildPieces.SLOTS[4]["name"], "Furniture & storage")
	var v := BuildPieces.variants(4)
	check(v.size() >= 15, "key 5 holds the crate and the furniture (%d)" % v.size())   # Exp 006 (U): Move is a tool, decor and lamps elsewhere
	b.select_id("cupboard")
	check_eq(b.slot(), 4, "the cupboard is on key 5")
	var r := b.evaluate(Vector2(-2.0, 5.0))
	check(r["ok"], "a cupboard in the yard is fine (%s)" % r["reason"])
	check_eq(r["cost"], {"wood": 4, "nails": 6, "scrap": 1}, "it costs planks, nails and scrap")
	check_eq(b.evaluate(Vector2(7.0, 9.0))["reason"], "There's a wall in the way.", "not inside a wall")
	check_eq(b.evaluate(Vector2(4.5, 8.5))["reason"], "That would block a doorway.", "not in front of the front door")
	check_eq(b.evaluate(Vector2(4.5, 7.0))["reason"], "Furniture is in the way.", "not on the sofa")
	b.select_id("rug")
	check(b.evaluate(Vector2(4.5, 8.0))["ok"] or b.evaluate(Vector2(-2.0, 2.0))["ok"], "a rug lies flat")
	b.select_id("cupboard")
	var wood := s.inventory.count("wood")
	check(b.apply(Vector2(-2.0, 5.0)), "placed")
	check_eq(s.inventory.count("wood"), wood - 4, "paid")
	var cup: WorldObject = w.object_at(Vector2(-2.0, 5.0), 0.0)
	check(cup != null and cup.kind == "cupboard" and cup.built, "a placed kitchen cupboard")
	check_eq(b.evaluate(Vector2(-2.0, 5.0))["reason"], "Something is already standing here.", "no overlap")
	check_eq(w.nav.get_raw(w.nav.cell_of(Vector2(-2.0, 5.0))), GridNav.WALL, "enemies bash through it like the house's furniture")
	cup.items["canned_food"] = 2
	# Move: the placed cupboard with its contents
	b.select_id("move")
	var pick := b.evaluate(Vector2(-2.0, 5.0))
	check(pick["ok"] and pick.has("pick"), "Move picks the cupboard up (%s)" % pick["reason"])
	b.apply(Vector2(-2.0, 5.0))
	check(not b.carry.is_empty() and b.carry["kind"] == "cupboard", "it is carried")
	b.rotate_piece()
	var put := b.evaluate(Vector2(-2.0, 2.5))
	check(put["ok"] and put["cost"].is_empty(), "free to set down (%s)" % put["reason"])
	b.apply(Vector2(-2.0, 2.5))
	check(b.carry.is_empty(), "set down")
	check(w.object_at(Vector2(-2.0, 5.0), 0.0) == null, "gone from the old spot")
	var moved: WorldObject = w.object_at(Vector2(-2.0, 2.5), 0.0)
	check(moved != null and moved.kind == "cupboard" and moved.rot == (cup.rot + 1) % 4, "standing at the new spot, turned")
	check(moved != null and moved.items == {"canned_food": 2}, "its contents travelled with it")
	check(w.objects.filter(func(o): return o.kind == "loot_pile").is_empty(), "no pile from a move")
	# Move an original piece: the armchair keeps its HP fraction
	w.furniture.hurt("armchair", 2)
	var hp_frac := float(w.furniture.pieces["armchair"]["hp"]) / float(w.furniture.pieces["armchair"]["max_hp"])
	b.apply(Vector2(1.85, 5.75))
	check(not b.carry.is_empty() and b.carry["piece"] == "armchair", "the house's armchair is picked up")
	check(w.furniture_ok("armchair"), "it stays until set down")
	b.cancel_carry()
	check(b.carry.is_empty() and w.furniture_ok("armchair"), "RMB puts it back")
	b.apply(Vector2(1.85, 5.75))
	var arm_ok := b.apply(Vector2(-2.5, 7.5))
	check(arm_ok, "and set down in the yard (%s)" % b.last_eval.get("reason", ""))
	check_eq(w.furniture.state_of("armchair"), "removed", "the original piece is gone")
	var arm: WorldObject = w.object_at(Vector2(-2.5, 7.5), 0.1)
	check(arm != null and arm.kind == "armchair" and not arm.built, "a placed armchair (not the player's own)")
	if arm != null:
		check(absf(float(arm.hp) / arm.max_hp - hp_frac) < 0.15, "keeping its HP (%d/%d)" % [arm.hp, arm.max_hp])
		check(arm.size3().is_equal_approx(Vector3(0.9, 0.85, 0.9)), "and its size")
	# fixtures stay
	check_eq(b.evaluate(Vector2(11.0, 0.5))["reason"], "It's plumbed in.", "the sink stays")
	# demolish: the player's piece refunds in full, the moved original gives salvage
	b.select_id("demolish")
	var rd := b.evaluate(Vector2(-2.0, 2.5))
	check_eq(rd["refund"], {"wood": 4, "nails": 6, "scrap": 1}, "a placed cupboard refunds in full")
	if arm != null:
		var ra := b.evaluate(Vector2(-2.5, 7.5))
		check(ra["refund"].size() > 0 and int(ra["refund"].get("wood", 0)) <= 1, "a moved armchair gives salvage (%s)" % str(ra["refund"]))
	b.apply(Vector2(-2.0, 2.5))
	var pile := w.objects.filter(func(o): return o.kind == "loot_pile")
	check(pile.size() == 1 and pile[0].items == {"canned_food": 2}, "a demolished full cupboard leaves its cans in a pile")
	check_eq(b.evaluate(pile[0].pos)["reason"], "Search the pile instead (E): it goes when it's empty.", "piles aren't demolished")


func test_wall_painting_and_table_lamp_on_a_table() -> void:
	var w: HouseWorld = await _world()
	var sb: Array = await _build_mode(w)
	var b: BuildMode = sb[1]
	b.select_id("painting")
	var r := b.evaluate(Vector2(3.5, 0.15))      # the bedroom's north wall, aimed from inside
	check(r["ok"], "a painting on a wall (%s)" % r["reason"])
	check(r["pos"].y > 0.1 and r["rot"] == 2, "on the room's side, facing in (%s, %d)" % [str(r["pos"]), r["rot"]])
	check(not b.evaluate(Vector2(-2.0, 5.0))["ok"], "not in mid-air")
	b.apply(Vector2(3.5, 0.15))
	var p: WorldObject = null
	for o in w.objects:
		if o.kind == "painting":
			p = o
	check(p != null and is_equal_approx(p.base_y(), 1.25), "it hangs at 1.25 m")
	b.select_id("table_lamp")
	var t := b.evaluate(Vector2(7.8, 5.65))         # the dining table
	check(t["ok"] and absf(float(t["lift"]) - 0.75) < 0.01, "a table lamp stands on the dining table (%s, %.2f)" % [t["reason"], float(t.get("lift", 0.0))])
	b.apply(Vector2(7.8, 5.65))
	var lamp: WorldObject = null
	for o in w.objects:
		if o.kind == "table_lamp":
			lamp = o
	check(lamp != null and absf(lamp.base_y() - 0.75) < 0.01, "at table height")
	check(lamp != null and not lamp.is_lit(), "dark without power")
	if lamp != null:
		lamp.set_powered(true)
		check(lamp.is_lit(), "lit with power and its switch on")
		lamp.interact(null)
		check(not lamp.lamp_on and not lamp.is_lit(), "E switches it off")
		w.furniture.destroy("dining_table")
		check_eq(FurniturePlace.settle_lamps(w), 1, "the table went: the lamp comes down")
		check(is_zero_approx(lamp.lift), "to the floor")


const SCENE := "res://src/game/game.tscn"
const SAVE := "user://test_storage_exp005.save"


func _boot() -> Node:
	SaveGame.path_override = SAVE
	GameLaunch.mode = "new"
	GameLaunch.seed = 4242
	var g: Node = (load(SCENE) as PackedScene).instantiate()
	g.stay_in_scene = true
	g.skip_intro = true
	g.fade_time = 0.02
	g.aim_with_mouse = false
	add(g)
	tree.current_scene = g
	await frames(3)
	return g


func cleanup() -> void:
	tree.paused = false
	if SaveGame.path_override == SAVE:
		SaveGame.delete_save()
	SaveGame.path_override = ""
	GameLaunch.mode = "new"
	GameLaunch.seed = 0
	await super.cleanup()


func test_game_fridge_panel_and_f10() -> void:
	var g: Node = await _boot()
	var s: GameState = g.debug_state()
	g.debug_teleport_player(Vector2(8.6, 1.5))
	await frames(2)
	check_eq(g.debug_prompt(), "[E] Open the fridge (2/24)", "E at the fridge opens it")
	g.debug_interact()
	await frames(1)
	check_eq(g.debug_modal(), "storage", "the storage panel is open (paused)")
	var panel: StoragePanel = g.storage.panel
	check(panel.is_open and panel.type == "fridge", "on the fridge")
	var cans := s.inventory.count("canned_food")
	check_eq(panel.take("canned_food", 1), 1, "take a can")
	check_eq(s.inventory.count("canned_food"), cans + 1, "into the pool")
	check_eq(panel.put("canned_food", 2), 2, "put two back")
	check_eq(int(g.debug_world().storage_of("fridge").get("canned_food", 0)), 2, "the fridge holds them")
	s.hunger = 30.0
	check(panel.use("canned_food") != "" and s.hunger > 50.0, "eat straight from the fridge")
	g.storage.close_panel()
	await frames(1)
	check_eq(g.debug_modal(), "", "closed")
	g.debug_open("dev")
	var dm: Node = g.debug_ui().dev_menu
	for label in ["Furniture kit", "Storage items", "Show containers"]:
		check(dm.button(label) != null, "F10 has '%s'" % label)
	g.debug_teleport_player(Vector2(-2.0, 5.0))
	await physics_frames(2)
	var n0: int = g.debug_world().objects.size()
	var kit: String = g.storage.dev_furniture_kit()
	check(g.debug_world().objects.size() >= n0 + 7, "the kit places pieces near the player (%s)" % kit)
	check(str(g.storage.dev_containers_text()).contains("Fridge"), "containers are listed")
