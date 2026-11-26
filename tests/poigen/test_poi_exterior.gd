extends "res://tests/test_case.gd"
## Exp 009 (X): the surroundings of generated places and the ways out.
## PoiExterior.decorate() for every family (a car spot, the entry, the
## departure marker, outdoor pieces and searchable "ext_*" containers; the
## walks to every front door kept clear, inside the lot; deterministic), the
## same in a built PoiWorld (its own navigation), "[E] Leave location" at the
## parked car and at the departure marker (Go home / Travel on (map) / Stay)
## in the real game scene, and an apartment's dark hallway end (asks once
## per time in; Stay steps Eli back out; Leave asks where to).

const PREVIEW := "res://src/poi/poi_preview.tscn"
const SCENE := "res://src/game/game.tscn"
const SAVE := "user://test_poi_exterior.dat"
const TravelFlow := preload("res://src/travel/travel_flow.gd")
const STAND_IN := "warehouse"       ## a placeholder site whose cached definition the world tests borrow

const FAMILY_ARCH := {"residential": "house_small", "apartment": "apartment", "commercial": "supermarket",
	"industrial": "warehouse", "medical": "hospital", "police": "police", "yard": "yard"}

var _borrowed := false


func cleanup() -> void:
	tree.paused = false
	if _borrowed:
		PoiDefs._cache.erase(STAND_IN)
		PoiWorld._pristine_poi.erase(STAND_IN)
		PoiWorld._ground_tex.erase(STAND_IN)
		_borrowed = false
	if SaveGame.path_override == SAVE:
		SaveGame.delete_save()
	SaveGame.path_override = ""
	GameLaunch.mode = "new"
	GameLaunch.seed = 0
	GameLaunch.notice = ""
	GameLaunch.site = "home"
	GameLaunch.carry = {}
	TravelFlow.skip_animation = false
	await super.cleanup()


# --- a stand-in for the building generator ------------------------------------------------

## A plain building in the PoiLayouts format as G's generator hands it over:
## walls on the bounds with a front door (and a back one for "wide"), a room,
## one shelf, "bounds" and the front entrances in "doorways".
static func building(arch: String, shape := "small") -> Dictionary:
	var L := PoiLayouts._base()
	L["archetype"] = arch
	var B := {"small": Rect2(3, 2, 8, 6), "wide": Rect2(0, -1, 15, 9), "deep": Rect2(-2, -4, 12, 13), "hut": Rect2(5, 3, 4, 3),
		"block": Rect2(1, 0, 13, 8)}[shape] as Rect2
	var x0 := int(B.position.x)
	var x1 := int(B.end.x)
	var z0 := int(B.position.y)
	var z1 := int(B.end.y)
	var door := x0 + int(B.size.x / 2.0) - 1
	L["floors"].append({"rect": B.grow(0.1), "art": "floor_concrete"})
	PoiLayouts._wall(L, Vector2(x0, z1), Vector2(x1, z1), "brick", [PoiLayouts._dgap(door, door + 1), PoiLayouts._win(x0 + 0.6, x0 + 2.4)])
	PoiLayouts._wall(L, Vector2(x0, z0), Vector2(x1, z0), "brick", [PoiLayouts._dgap(x1 - 3, x1 - 2)] if shape == "wide" else [])
	PoiLayouts._wall(L, Vector2(x0, z0), Vector2(x0, z1), "brick")
	PoiLayouts._wall(L, Vector2(x1, z0), Vector2(x1, z1), "brick")
	PoiLayouts._door(L, "front", 0, z1, door, 2)
	L["doorways"] = [Vector2(door + 0.5, z1 + 0.7)]
	if shape == "wide":
		PoiLayouts._door(L, "rear", 0, z0, x1 - 3, 0)
		L["doorways"].append(Vector2(x1 - 2.5, z0 - 0.7))
	PoiLayouts._room(L, "main", B)
	PoiLayouts._box(L, "shelf", "shelves", Vector2(x0 + 1.2, z0 + 0.4), "S", "shelf", PoiLayouts.ANY, {"room": "main"})
	if shape == "block":
		# an apartment floor: the hallway runs east into the dark
		L["dark_exit"] = Rect2(x1 - 2.4, z0 + 3.0, 2.2, 1.6)
	L["bounds"] = B
	return L


static func _decorated(arch: String, shape: String, seed: int) -> Dictionary:
	var L := building(arch, shape)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	PoiExterior.decorate(L, {"archetype": arch}, rng)
	return L


static func _outside(L: Dictionary, r: Rect2) -> bool:
	return not (L["bounds"] as Rect2).grow(0.2).intersects(r)


# --- pure data ---------------------------------------------------------------------------

func test_every_family_gets_surroundings_a_car_spot_and_clear_ways() -> void:
	var ext_boxes := 0
	for fam in FAMILY_ARCH:
		check_eq(PoiExterior.family_of({"archetype": FAMILY_ARCH[fam]}), fam, "%s's family" % FAMILY_ARCH[fam])
		for shape in (["hut"] if fam == "yard" else (["block"] if fam == "apartment" else ["small", "wide", "deep"])):
			for seed in [1, 77, 4242]:
				var tag := "%s/%s/%d" % [fam, shape, seed]
				var t0 := Time.get_ticks_usec()
				var L := _decorated(FAMILY_ARCH[fam], shape, seed)
				var ms := (Time.get_ticks_usec() - t0) / 1000.0
				check(ms < 400.0, "%s: decorate is quick (%.0f ms)" % [tag, ms])
				var car: Dictionary = L["car"]
				check(car.get("rect") is Rect2 and car.get("cargo") is Vector2 and car.get("door") is Vector2, "%s: a car spot with its boot and door (%s)" % [tag, car])
				check(PoiExterior.LOT.has_point(L["entry"]), "%s: the entry is on the lot" % tag)
				check((L["exits"] as Array).size() >= 1, "%s: a departure point" % tag)
				for e in L["exits"]:
					check(HousePlan.YARD.grow(-0.3).has_point(e), "%s: the departure point %s is inside the walkable area" % [tag, e])
				var outside := (L["props"] as Array).filter(func(p): return _outside(L, p["rect"]))
				check(outside.size() >= 4, "%s: outdoor pieces (%d)" % [tag, outside.size()])
				for p in outside:
					check(PoiExterior.LOT.grow(0.05).encloses(p["rect"]), "%s: %s stays on the lot (%s)" % [tag, p["type"], p["rect"]])
					check(PropKit.has(str(p["type"])), "%s: %s is a PropKit piece" % [tag, p["type"]])
				var probs := PoiExterior.validate(L)
				check(probs.is_empty(), "%s: everything reachable (%s)" % [tag, probs])
				var boxes := (L["containers"] as Array).filter(func(c): return str(c["id"]).begins_with("ext_"))
				ext_boxes += boxes.size()
				for c in boxes:
					check(PropKit.has(str(c["type"])) and (c["holds"] as Array).size() > 0, "%s: %s is searchable" % [tag, c["id"]])
				check(not (L["wander"] as Array).is_empty() and (L["edges"] as Array).size() >= 3, "%s: outdoor walks and fog edges" % tag)
				check_eq(L["exit_kind"], "dark" if fam == "apartment" else "edge", "%s: the exit kind" % tag)
	check(ext_boxes >= 20, "searchable things outside (%d over all sites)" % ext_boxes)


func test_decorate_is_deterministic_and_varies_with_the_seed() -> void:
	for arch in ["house_family", "office", "factory"]:
		var a := _decorated(arch, "wide", 99)
		var b := _decorated(arch, "wide", 99)
		var c := _decorated(arch, "wide", 100)
		check_eq(var_to_str(a), var_to_str(b), "%s: the same seed, the same surroundings" % arch)
		check(var_to_str(a) != var_to_str(c), "%s: another seed, other surroundings" % arch)
	# and the building's own walls, rooms and containers are left alone
	var L := building("diner", "small")
	var walls := var_to_str(L["walls"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	PoiExterior.decorate(L, {}, rng)
	check_eq(var_to_str(L["walls"]), walls, "the walls are untouched")
	check(L["containers"][0]["id"] == "shelf", "the inside's containers come first, as they were")


# --- in a built world (its own navigation) ----------------------------------------------

## Builds STAND_IN's world from layout L (the preview harness), by car or not.
func _world_of(L: Dictionary, car: bool) -> Node:
	var d := PoiDefs.get_def(STAND_IN).duplicate()
	d["layout"] = L
	PoiDefs._cache[STAND_IN] = d
	PoiWorld._pristine_poi.erase(STAND_IN)
	PoiWorld._ground_tex.erase(STAND_IN)
	_borrowed = true
	var h: Node = (load(PREVIEW) as PackedScene).instantiate()
	h.configure(STAND_IN, car, 4242)
	add(h)
	await physics_frames(3)
	return h


func test_the_ways_stay_open_in_the_built_world() -> void:
	for arch in ["house_small", "supermarket", "police", "factory"]:
		var L := _decorated(arch, "wide", 31)
		var h: Node = await _world_of(L, true)
		var w: PoiWorld = h.world
		if not check(w != null and w.is_inside_tree(), "%s: built" % arch):
			continue
		var e := w.entry_point()
		check(w.nav.is_walkable(w.nav.cell_of(e)), "%s: the entry is walkable" % arch)
		for d in L["doorways"]:
			check(not w.nav.find_path(e, d).is_empty(), "%s: a way to the door at %s" % [arch, d])
		check(not w.nav.find_path(e, L["car"]["cargo"]).is_empty(), "%s: a way to the boot" % arch)
		var leave: PoiSpot = w.spot("exit", "car")
		if check(leave != null, "%s: by car, the car is the way out" % arch):
			check(not w.nav.find_path(e, leave.plan_pos()).is_empty(), "%s: a way to the car's door" % arch)
			check_eq(leave.interact_prompt(), "[E] Leave location", "%s: the car's prompt" % arch)
		check_eq(w.spots_of("exit").size(), 1, "%s: no trail posts when Eli drove" % arch)
		for c in w.spots_of("container"):
			if str(c.id).begins_with("ext_"):
				check(not w.nav.find_path(e, c.plan_pos()).is_empty(), "%s: a way to %s" % [arch, c.id])
		check(w.get_node_or_null("Car") != null, "%s: the car stands there" % arch)
		h.queue_free()
		await frames(2)
	# on foot: the departure marker at the edge
	var L2 := _decorated("house_family", "small", 12)
	var h2: Node = await _world_of(L2, false)
	var w2: PoiWorld = h2.world
	var marks := w2.spots_of("exit")
	check(marks.size() == (L2["exits"] as Array).size() and marks[0].get_node_or_null("ExitMarker/Board") != null, "on foot: a departure marker with its board")
	check(not w2.nav.find_path(w2.entry_point(), marks[0].plan_pos()).is_empty(), "on foot: a way to it")
	check(w2.get_node_or_null("Car") == null, "on foot: no car")


# --- leaving in the real game scene -------------------------------------------------------

func _boot(mode: String) -> Node:
	SaveGame.path_override = SAVE
	GameLaunch.mode = mode
	GameLaunch.seed = 9009
	var g: Node = (load(SCENE) as PackedScene).instantiate()
	g.stay_in_scene = true
	g.skip_intro = true
	g.fade_time = 0.02
	g.death_delay = 0.05
	g.aim_with_mouse = false
	add(g)
	tree.current_scene = g
	await frames(3)
	return g


func _next_scene(g: Node) -> Node:
	check(g.left_to == GameLaunch.GAME_SCENE, "changes scene (left_to '%s')" % g.left_to)
	g.queue_free()
	await frames(2)
	return await _boot(GameLaunch.mode)


func _wait_until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await frames(1)
	return cond.call()


func _press(g: Node, what: String) -> bool:
	var b: Button = g.poi.leave_dialog.button(what)
	if not check(b != null and not b.disabled, "the choice offers %s" % what):
		return false
	b.pressed.emit()
	await frames(1)
	return true


func test_on_foot_the_marker_offers_home_the_map_or_staying() -> void:
	TravelFlow.skip_animation = true
	var g: Node = await _boot("new")
	g.debug_state().total_minutes = 9.0 * 60.0
	await g.travel.depart("convenience", false)
	g = await _next_scene(g)
	check(not g.is_home() and not g.world.has_car, "at the Corner Store, on foot")
	var exits: Array = g.world.spots_of("exit")
	check_eq(exits.size(), (g.world.layout["exits"] as Array).size(), "the hand-made exits are the departure markers")
	var ex: PoiSpot = exits[0]
	check_eq(ex.interact_prompt(), "[E] Leave location", "the marker's prompt")
	g.debug_teleport_player(ex.plan_pos())
	await physics_frames(2)
	await frames(2)
	check_eq(g.debug_prompt(), "[E] Leave location", "the HUD shows it at the marker")
	# Stay: nothing happens
	g.debug_interact()
	check(g.poi.leave_dialog.is_open and g.poi.leave_dialog.mode == "leave", "E opens the choice")
	check_eq(g.debug_modal(), "poi", "the world waits")
	await _press(g, "stay")
	check(not g.poi.leave_dialog.is_open and g.debug_modal() == "" and g.left_to == "", "Stay: still here")
	check(PoiState.in_visit(g.poi.record), "the visit goes on")
	# Travel on: the map, from here
	g.debug_interact()
	await _press(g, "map")
	check_eq(g.debug_modal(), "map", "Travel on opens the map")
	check_eq(g.map.screen.origin, "convenience", "from the Corner Store")
	g.map.close()
	await frames(2)
	check_eq(g.debug_modal(), "", "the map closes")
	# Go home
	g.debug_interact()
	await _press(g, "home")
	check(await _wait_until(func(): return g.left_to != "", 30), "Go home leaves")
	check_eq(GameLaunch.site, "home", "for home")
	g = await _next_scene(g)
	check(g.is_home(), "home")
	check_eq(g.debug_state().region.visits("convenience"), 1, "the visit is counted once")


func test_by_car_the_car_is_the_way_out_with_its_boot() -> void:
	TravelFlow.skip_animation = true
	var g: Node = await _boot("new")
	var s: GameState = g.debug_state()
	s.total_minutes = 10.0 * 60.0
	s.car_repaired = true
	s.inventory.add("fuel", 2 - s.inventory.count("fuel"))
	await g.travel.depart("hardware", true)
	g = await _next_scene(g)
	s = g.debug_state()
	check(g.world.has_car and g.travel.by_car(), "at the Hardware Store by car")
	var exits: Array = g.world.spots_of("exit")
	check(exits.size() == 1 and exits[0].id == "car", "one way out: the car (%s)" % [exits.map(func(e): return e.id)])
	check(g.world.find_children("ExitMarker", "", true, false).is_empty(), "no trail posts")
	check_eq(g.world.get_children().filter(func(n): return n.name == "Car").size(), 1, "one car")
	var boot: PoiSpot = g.world.spot("cargo", "car")
	var leave: PoiSpot = exits[0]
	var car_r: Rect2 = g.world.layout["car"]["rect"]
	check(boot != null and leave.plan_pos().distance_to(car_r.get_center()) < 3.2, "the way out is at the same car as the boot")
	check(leave.plan_pos().distance_to(boot.plan_pos()) > 1.6, "and apart from the boot, so E picks one")
	g.poi.cargo["stone"] = 3
	g.debug_teleport_player(leave.plan_pos())
	await physics_frames(2)
	await frames(2)
	check_eq(g.debug_prompt(), "[E] Leave location", "the HUD shows it at the car")
	g.debug_interact()
	check(g.poi.leave_dialog.is_open, "E at the car opens the choice")
	var home_b: Button = g.poi.leave_dialog.button("home")
	check(home_b != null and UiTheme.caption_of(home_b) == "by car", "by car")
	await _press(g, "home")
	check(await _wait_until(func(): return g.left_to != "", 30), "Go home drives off")
	g = await _next_scene(g)
	check(g.is_home(), "home")
	check_eq(int(g.travel.last_cargo.get("stone", 0)), 3, "with the boot")


# --- the apartment's dark hallway end ----------------------------------------------------

func test_the_dark_hallway_asks_once_and_stay_keeps_eli_inside() -> void:
	var L := _decorated("apartment", "block", 8)
	var h: Node = await _world_of(L, false)
	var w: PoiWorld = h.world
	var r: Rect2 = L["dark_exit"]
	check(w.get_node_or_null("Dark") != null, "the hallway end is drawn dark")
	check_eq(w.dark_dir(), Vector2(1, 0), "it gets darker toward the east end")
	await frames(12)
	check(not h.poi.leave_dialog.is_open, "nothing asked at the entry")
	# walk in
	h.player.global_position = Vector3(r.get_center().x, 0, r.get_center().y)
	await frames(12)
	check(h.poi.leave_dialog.is_open and h.poi.leave_dialog.mode == "dark", "walking into the dark asks")
	check_eq(h._modal, "poi", "and the world waits")
	var title: Label = h.poi.leave_dialog.find_child("Title", true, false)
	check(title != null and title.text.to_lower().contains("leave this location"), "Leave this location? (%s)" % (title.text if title != null else "?"))
	# Stay: one step back out, and no second question
	h.poi.leave_dialog.button("stay").pressed.emit()
	await frames(2)
	var p := Vector2(h.player.global_position.x, h.player.global_position.z)
	check(not r.has_point(p) and p.x < r.position.x, "Stay steps Eli back toward the lit hallway (%s)" % p)
	check(w.nav.is_walkable(w.nav.cell_of(p)), "onto the hallway floor")
	await frames(20)
	check(not h.poi.leave_dialog.is_open and h._modal == "", "asked only once")
	check(PoiState.in_visit(h.poi.record) and not h.left, "Eli stays")
	# standing in it asks only once
	h.player.global_position = Vector3(r.get_center().x, 0, r.get_center().y)
	await frames(12)
	check(h.poi.leave_dialog.is_open, "walking in again asks again")
	h.poi.leave_dialog.choose("leave")
	await frames(2)
	check(h.poi.leave_dialog.is_open and h.poi.leave_dialog.mode == "leave", "Leave asks where to")
	h.poi.leave_dialog.choose("home")
	await frames(2)
	check(h.left, "and Go home leaves")


func test_the_hand_made_places_keep_their_ways_out() -> void:
	for id in PoiDefs.HAND_MADE:
		var h: Node = (load(PREVIEW) as PackedScene).instantiate()
		h.configure(id, true, 4242)
		add(h)
		await physics_frames(3)
		var w: PoiWorld = h.world
		var out: Array = w.spots_of("exit")
		if check(out.size() == 1 and out[0].id == "car", "%s by car: the car is the way out" % id):
			var p: Vector2 = out[0].plan_pos()
			check(HousePlan.YARD.grow(-0.6).has_point(p) and w.nav.is_walkable(w.nav.cell_of(p)), "%s: by the car's door, on open ground (%s)" % [id, p])
			check(not w.nav.find_path(w.entry_point(), p).is_empty(), "%s: reachable from the entry" % id)
		h.queue_free()
		await frames(2)
		var f: Node = (load(PREVIEW) as PackedScene).instantiate()
		f.configure(id, false, 4242)
		add(f)
		await physics_frames(3)
		check_eq((f.world as PoiWorld).spots_of("exit").size(), (f.world.layout["exits"] as Array).size(), "%s on foot: a departure marker at each exit" % id)
		f.queue_free()
		await frames(2)


func test_a_building_that_fills_the_lot_still_gets_a_way_out() -> void:
	for arch in ["warehouse", "hospital", "house_family"]:
		var L := building(arch, "small")
		L["bounds"] = Rect2(-5, -4, 24, 16)
		L["doorways"] = [Vector2(7.5, 12.7)]
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		PoiExterior.decorate(L, {}, rng)
		check((L["exits"] as Array).size() == 1 and PoiExterior.LOT.has_point(L["entry"]), "%s: an entry and a departure point" % arch)
		check(PoiExterior.validate(L).is_empty(), "%s: still reachable (%s)" % [arch, PoiExterior.validate(L)])
		var car: Dictionary = L["car"]
		check(car.is_empty() or PoiExterior.LOT.encloses(car["rect"]), "%s: a car spot on the lot, or none" % arch)
