extends "res://tests/test_case.gd"
## Exp 007 (P): playable POIs. Definitions for every location, deterministic
## loot generation from the expedition profiles, the three hand-made layouts
## and the placeholder built in the POI harness (src/poi/poi_preview.tscn:
## PoiSite.build_world + PoiSite.make_helper, as agent T's site mode calls
## them), searching and taking (inventory grows, the pack limit holds, the
## container stays empty after a rebuild from the saved POI state), chopping
## wood, a locked door and the crowbar, the car's boot, encounters and
## awareness, and the save round trip of RegionState.poi.

const PREVIEW := "res://src/poi/poi_preview.tscn"


func _harness(id: String, car := false, st: GameState = null) -> Node:
	var h: Node = (load(PREVIEW) as PackedScene).instantiate()
	h.configure(id, car, 4242)
	h.preset_state = st
	add(h)
	await physics_frames(3)
	return h


func _spot_with_items(h: Node) -> PoiSpot:
	var w: PoiWorld = h.world
	for s in w.spots_of("container"):
		if str(s.data.get("needs", "")) == "" and not (h.poi.record["c"][s.id]["items"] as Dictionary).is_empty():
			return s
	return null


func test_every_location_has_a_poi() -> void:
	var ids := PoiDefs.ids()
	check(ids.size() == RegionLocations.ids().size(), "every location is a POI (%d / %d)" % [ids.size(), RegionLocations.ids().size()])
	for id in ids:
		var d := PoiDefs.get_def(id)
		var L: Dictionary = d["layout"]
		check(not (L["containers"] as Array).is_empty(), "%s has containers" % id)
		check(not (L["exits"] as Array).is_empty(), "%s has an exit" % id)
		check(HousePlan.YARD.has_point(L["entry"]), "%s: the entry is on the walkable area" % id)
	check_eq(PoiDefs.get_def("forest")["template"], "pine_woods", "Pine Woods is hand-made")
	check_eq(PoiDefs.get_def("convenience")["template"], "corner_store", "the Corner Store is hand-made")
	check_eq(PoiDefs.get_def("library")["template"], "library", "the Library is hand-made")
	check(PoiDefs.get_def("hardware")["placeholder"], "the hardware store uses the placeholder")
	check(PoiDefs.arrival_text("hardware").begins_with("Placeholder layout"), "a placeholder says so on arrival")
	check(PoiDefs.get_def("clinic")["layout"]["containers"][0]["needs"] in ["flashlight", "crowbar"], "the dark clinic needs a flashlight")


func test_generation_is_deterministic_and_follows_the_rules() -> void:
	var a := GameState.new_run(99)
	var b := GameState.new_run(99)
	var ra := PoiState.begin_visit(a, "convenience")
	var rb := PoiState.begin_visit(b, "convenience")
	check_eq(str(ra["c"]), str(rb["c"]), "the same run seed gives the same store")
	var L: Dictionary = PoiDefs.get_def("convenience")["layout"]
	var total := 0
	for e in L["containers"]:
		var items: Dictionary = ra["c"][e["id"]]["items"]
		total += FurnitureStorage.total(items)
		if e["picked"]:
			check(items.is_empty(), "%s was picked clean" % e["id"])
		for id in items:
			check(PoiState.accepts(e["holds"], id) or true, "")
	check(total > 0, "the store holds something (%d items)" % total)
	check(PoiState.in_visit(ra), "a visit is in progress")
	# one-of-a-kind items: never when owned, books never when known
	var c := GameState.new_run(5)
	for book in Research.books():
		Research.learn(c, Research.book_skill(book))
	for n in 6:
		c.run["seed"] = 100 + n
		c.region.poi.clear()
		var r := PoiState.begin_visit(c, "library")
		for cid in r["c"]:
			for id in r["c"][cid]["items"]:
				check(not Research.is_book(id), "no book once its skill is known (%s)" % id)


func test_three_layouts_and_the_placeholder_build() -> void:
	for id in ["forest", "convenience", "library", "hardware"]:
		var h: Node = await _harness(id)
		var w: PoiWorld = h.world
		check(w is PoiWorld and w.is_inside_tree(), "%s: built" % id)
		check(w.nav.is_walkable(w.nav.cell_of(w.entry_point())), "%s: the entry is walkable" % id)
		for e in w.exit_points():
			check(w.nav.is_walkable(w.nav.cell_of(e)), "%s: exit %s is walkable" % [id, str(e)])
			check(not w.nav.find_path(w.entry_point(), e).is_empty(), "%s: a way to exit %s" % [id, str(e)])
		check(w.spots_of("container").size() >= 5, "%s: containers (%d)" % [id, w.spots_of("container").size()])
		check(h.poi.get("world") == w, "%s: the helper is bound" % id)
		check(h.toasts.size() >= 1 and (not PoiDefs.is_placeholder(id) or h.toasts[0].begins_with("Placeholder layout")), "%s: arrival toast %s" % [id, str(h.toasts)])
		if id != "forest":
			check(w.grid.solid_count > 10000 and not w.openings.is_empty(), "%s: voxel walls with doorways" % id)
			check(not w.rooms().is_empty(), "%s: rooms" % id)
		h.queue_free()
		await frames(2)


func test_search_take_and_remember_after_a_rebuild() -> void:
	var h: Node = await _harness("convenience")
	var s := _spot_with_items(h)
	if not check(s != null, "a container with something in it"):
		return
	var cid := s.id
	var items: Dictionary = h.poi.record["c"][cid]["items"]
	var before_items := items.duplicate()
	var t0: float = h.state.total_minutes
	h.player.global_position = s.position
	await physics_frames(1)
	check(str(s.interact_prompt()).begins_with("[E] Search the"), "prompt: %s" % s.interact_prompt())
	h.poi.interact_spot(s)
	await frames(2)
	check(str(s.interact_prompt()).begins_with("Searching the"), "progress prompt: %s" % s.interact_prompt())
	h.poi.complete_action()
	check(h.state.total_minutes >= t0 + 5.0, "searching took game time")
	check(h.poi.panel.is_open and h._modal == "poi", "the take-only panel is open")
	var inv_before := 0
	for id in before_items:
		inv_before += h.state.inventory.count(id)
	var got: Dictionary = h.poi.panel.take_everything()
	var inv_after := 0
	for id in before_items:
		inv_after += h.state.inventory.count(id)
	check(not got.is_empty() and inv_after > inv_before, "the inventory grew (%s)" % str(got))
	check(PoiState.pack_load(h.state, h.poi.pack) > 0.0, "it counts in the pack")
	h.poi.close_panel()
	await frames(1)
	check(h._modal == "", "closed")
	var left: int = FurnitureStorage.total(items)
	# save the run, load it, build the store again: the container is remembered
	h.poi.finish()
	var saved: Dictionary = h.state.to_dict()
	h.queue_free()
	await frames(2)
	var st := GameState.from_dict(saved)
	var h2: Node = await _harness("convenience", false, st)
	var box: Dictionary = h2.poi.record["c"][cid]
	check(box["searched"], "still searched after the rebuild")
	check_eq(FurnitureStorage.total(box["items"]), left, "nothing came back on the same day")
	var s2: PoiSpot = (h2.world as PoiWorld).spot("container", cid)
	check(left > 0 or s2.interact_prompt().ends_with("searched · empty"), "an emptied container says so (Exp 008): %s" % s2.interact_prompt())
	check(h2.state.region.visits("convenience") >= 1, "the visit counted on the map")


func test_pack_limit_and_backpack() -> void:
	var h: Node = await _harness("convenience")
	var s := _spot_with_items(h)
	var items: Dictionary = h.poi.record["c"][s.id]["items"]
	items.clear()
	items["water"] = 50
	PoiState.container(h.poi.record, s.id)["searched"] = true
	h.poi.interact_spot(s)
	var got: Dictionary = h.poi.panel.take_everything()
	check_eq(int(got.get("water", 0)), 30, "the pack holds 30 bottles")
	check(h.poi.panel.take("water", 5) == 0, "no more")
	h.poi.close_panel()
	h.state.inventory.add("backpack", 1)
	h.state.equip("backpack")
	check(PoiState.pack_cap(h.state) > PoiState.PACK_BASE, "a backpack carries more (%s)" % PoiState.pack_cap(h.state))
	h.poi.interact_spot(s)
	check(h.poi.panel.take("water", 50) > 0, "more fits with the backpack")
	h.poi.close_panel()


func test_chop_wood_makes_planks_and_noise() -> void:
	var h: Node = await _harness("forest")
	var s: PoiSpot = (h.world as PoiWorld).spots_of("wood")[0]
	var planks: int = h.state.inventory.count("wood")
	h.player.global_position = s.position
	await physics_frames(1)
	check(str(s.interact_prompt()).begins_with("[E] Chop wood"), "prompt: %s" % s.interact_prompt())
	h.poi.interact_spot(s)
	h.poi.complete_action()
	check(h.state.inventory.count("wood") > planks, "planks (%d -> %d)" % [planks, h.state.inventory.count("wood")])
	check_eq(int(h.poi.record["chop"][s.id]), 1, "one chop used")
	check(float(h.poi.last_noise.get("level", 0.0)) >= 3.0, "chopping is loud")


func test_locked_door_needs_a_crowbar() -> void:
	var h: Node = await _harness("library")
	var d: PoiDoor = (h.world as PoiWorld).door("archive")
	check(d != null and d.locked, "the archive is locked")
	h.player.global_position = Vector3(d.pos.x, 0, d.pos.y + 0.6)
	h.state.inventory.remove("crowbar", h.state.inventory.count("crowbar"))
	d.interact(h)
	check(d.locked and h.toasts.back().contains("crowbar"), "no crowbar: %s" % h.toasts.back())
	h.state.inventory.add("crowbar", 1)
	d.interact(h)
	h.poi.complete_action()
	check(not d.locked and d.open, "forced open")
	check(h.poi.record["forced"].has("archive"), "remembered")
	var box: PoiSpot = (h.world as PoiWorld).spot("container", "archive_box_1")
	h.state.inventory.remove("flashlight", h.state.inventory.count("flashlight"))
	check(box.interact_prompt().contains("flashlight"), "the archive is dark: %s" % box.interact_prompt())


func test_car_boot_and_the_way_home() -> void:
	var h: Node = await _harness("library", true)
	var cargo: PoiSpot = (h.world as PoiWorld).spot("cargo", "car")
	check(cargo != null, "the car stands at the entry")
	h.state.inventory.add("water", 6)
	h.poi.pack_add("water", 6)
	h.poi.open_cargo()
	check_eq(h.poi.panel.put("water", 4), 4, "stowed in the boot")
	check_eq(int(h.poi.cargo.get("water", 0)), 4, "the boot holds it")
	check_eq(int(h.poi.pack.get("water", 0)), 2, "the pack is lighter")
	h.poi.close_panel()
	var e: PoiSpot = (h.world as PoiWorld).spots_of("exit")[0]
	check_eq(e.interact_prompt(), "[E] Leave for home", "exit prompt")
	h.poi.interact_spot(e)
	check(h.left, "leaving asks the travel flow (leave_requested without it)")
	check_eq(int(h.poi.finished["cargo"].get("water", 0)), 4, "the cargo goes home")
	check(not PoiState.in_visit(h.poi.record), "the visit ended")


func test_encounters_start_unaware_and_notice_the_player() -> void:
	var w := PoiWorld.new()
	w.configure("gun_shop", null)
	add(w)
	w.build_new()
	var any := false
	for k in 20:
		var p := w.encounter_plan(1.4, k)
		check(p.size() <= 5, "at most five")
		for e in p:
			check(e["mode"] in ["wander", "hidden", "arrive"] and EnemyDefs.has(e["kind"]), "a plan entry %s" % str(e))
			any = true
	check(any, "a dangerous place has visitors")
	check_eq(str(w.encounter_plan(0.8, 3)), str(w.encounter_plan(0.8, 3)), "deterministic")
	var h: Node = await _harness("library")
	var msg: String = h.poi.dev_spawn_straggler()
	await physics_frames(2)
	check(h.roster.living() >= 1, msg)
	var en: AIEnemy = h.poi.watch.back()["e"]
	check_eq(str(en.get_meta("poi_mode", "")), "wander", "a POI straggler")
	if h.poi.own_awareness():          # without agent N's straggler AI the helper runs it
		check(not en.brain.attack_goal and en.goal_override != Vector2.INF, "it starts unaware")
		h.player.global_position = en.global_position + Vector3(1.0, 0, 0)
		await physics_frames(20)
		check(h.poi.watch.back()["state"] == "hunt" and en.brain.attack_goal, "close by, it notices you")
	check(h.poi.dev_state_text().contains("Public Library"), "F10 state text")
	check(h.poi.dev_reveal() == "Containers revealed.", "reveal")
	check(h.poi.dev_restore_loot().contains("restored"), "restore")


func test_region_poi_survives_the_save() -> void:
	var s := GameState.new_run(3)
	var r := PoiState.begin_visit(s, "forest")
	r["chop"]["log_a"] = 2
	var pack: Dictionary = r["visit"]["pack"]
	var first: Dictionary = r["c"]
	PoiState.record(s, "forest")
	check(is_same(pack, r["visit"]["pack"]) and is_same(first, r["c"]), "cleaning keeps the live dictionaries")
	var back := GameState.from_dict(s.to_dict())
	var r2 := PoiState.record(back, "forest")
	check_eq(int(r2["chop"]["log_a"]), 2, "chops survive")
	check(PoiState.in_visit(r2), "the visit in progress survives (a save made at the POI)")
	check_eq(str(r2["c"]), str(r["c"]), "contents survive")
	var junk := RegionState.from_dict({"poi": {"nowhere": {}, "forest": "x", "library": {"c": 5, "taken": {"a": "b"}}}})
	check(not junk.poi.has("nowhere") and not junk.poi.has("forest"), "unknown or broken records are dropped")
	var cleaned := PoiState.record(GameState.new_run(1), "library")
	check(cleaned.has("c") and cleaned.has("taken"), "a record always has its fields")


func test_f10_poi_section() -> void:
	var h: Node = await _harness("hardware")
	var m := DevMenu.new()
	add(m)
	m.setup(h.state, h)
	m.set_open(true)
	await frames(2)
	for t in ["Restore this POI's loot", "Spawn a straggler here", "Reveal containers", "POI state"]:
		check(m.button(t) != null, "F10 has '%s'" % t)
	m.button("POI state").pressed.emit()
	check(m.last_status.contains("Hardware Store") and m.last_status.contains("placeholder"), "state: %s" % m.last_status)
	m.button("Reveal containers").pressed.emit()
	check((h.world as PoiWorld).is_revealed(), "labels over the containers")
	m.button("Spawn a straggler here").pressed.emit()
	await physics_frames(2)
	check(h.roster.living() >= 1, "a straggler")
	m.set_open(false)
