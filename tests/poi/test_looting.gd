extends "res://tests/test_case.gd"
## Exp 008 (L): looting that is worthwhile and understandable. Prompts and
## markers for unsearched, searched-empty and partly taken containers; one
## clear choice when two things are in reach (facing, actionable first, no
## flicker); weights and pack caps in the take-only panel and the boot's
## "Stow what you found"; the HUD's pack line; persistence (take -> leave ->
## revisit, take -> save at the POI -> Continue, items left in a box stay)
## and one-of-a-kind items (a learned or stored book never comes back).

const PREVIEW := "res://src/poi/poi_preview.tscn"
const SCENE := "res://src/game/game.tscn"
const SAVE := "user://test_looting.dat"
const Finder := preload("res://src/game/interaction_finder.gd")
const TravelFlow := preload("res://src/travel/travel_flow.gd")


func _harness(id: String, car := false, st: GameState = null) -> Node:
	var h: Node = (load(PREVIEW) as PackedScene).instantiate()
	h.configure(id, car, 4242)
	h.preset_state = st
	add(h)
	await physics_frames(3)
	return h


## A container with nothing needed to open it and something in it.
func _full_box(h: Node) -> PoiSpot:
	for s in (h.world as PoiWorld).spots_of("container"):
		if str(s.data.get("needs", "")) == "" and not bool(s.data.get("picked", false)) and not (h.poi.record["c"][s.id]["items"] as Dictionary).is_empty():
			return s
	return null


func _search(h: Node, s: PoiSpot) -> void:
	h.player.global_position = s.position
	h.poi.interact_spot(s)
	h.poi.complete_action()


func cleanup() -> void:
	tree.paused = false
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


# --- prompts and markers -------------------------------------------------------------------

func test_prompts_say_what_a_container_holds_now() -> void:
	var h: Node = await _harness("convenience")
	var s := _full_box(h)
	if not check(s != null, "a container with something in it"):
		return
	var items: Dictionary = h.poi.record["c"][s.id]["items"]
	items.clear()
	items["canned_food"] = 2
	items["water"] = 1
	items["bandage"] = 1
	check(s.interact_prompt().begins_with("[E] Search the "), "unsearched: %s" % s.interact_prompt())
	_search(h, s)
	h.poi.close_panel()
	var p := s.interact_prompt()
	check(p.begins_with("[E] Take from the ") and p.contains("2 cans of food") and p.contains("1 more kind"), "partly taken: %s" % p)
	h.poi.interact_spot(s)
	h.poi.panel.take("canned_food", 2)
	h.poi.panel.take("water", 1)
	h.poi.close_panel()
	p = s.interact_prompt()
	check(p.contains("bandage") and not p.contains("food"), "what's left: %s" % p)
	h.poi.interact_spot(s)
	h.poi.panel.take_everything()
	h.poi.close_panel()
	await frames(1)
	p = s.interact_prompt()
	check_eq(p, "%s: searched · empty" % s.label().capitalize(), "searched and empty")
	var n: int = h.toasts.size()
	h.poi.interact_spot(s)
	check(not h.poi.panel.is_open and h.toasts.size() == n + 1 and h.toasts.back().contains("Nothing left"), "E on an empty one says so, no panel (%s)" % str(h.toasts.back()))


func test_markers_show_what_is_searchable_near_eli() -> void:
	var h: Node = await _harness("convenience")
	var s := _full_box(h)
	if not check(s != null, "a container"):
		return
	h.player.global_position = s.position
	await frames(15)
	check_eq(s.marker_look, "new", "near and unsearched: the amber marker")
	check(s.marker != null and s.marker.visible, "the marker is shown")
	var far: PoiSpot = null
	for o in (h.world as PoiWorld).spots_of("container"):
		if o.interact_point().distance_to(s.plan_pos()) > float(h.poi.MARK_RANGE) + 1.0:
			far = o
			break
	if far != null:
		check_eq(far.marker_look, "", "far away: no marker")
	var items: Dictionary = h.poi.record["c"][s.id]["items"]
	items.clear()
	items["snacks"] = 3
	_search(h, s)
	h.poi.panel.take("snacks", 1)
	h.poi.close_panel()
	await frames(15)
	check_eq(s.marker_look, "left", "something left")
	check_eq((s.marker.get_node("Tag") as Label3D).text, "2 left", "the tag says how much")
	h.poi.interact_spot(s)
	h.poi.panel.take_everything()
	h.poi.close_panel()
	await frames(15)
	check_eq(s.marker_look, "empty", "searched: the faint tag")
	check_eq((s.marker.get_node("Tag") as Label3D).text, "searched", "it says searched")
	var woods: Node = await _harness("forest")
	var lock: PoiSpot = null
	for o in (woods.world as PoiWorld).spots_of("container"):
		if str(o.data.get("needs", "")) == "crowbar":
			lock = o
	if check(lock != null, "the woods have a locked tool cabinet"):
		check_eq(woods.poi.marker_for(lock)[0], "locked", "a locked one shows a lock")


## Two things in reach: the one Eli faces; something he can use before a note
## beside it; the choice doesn't flip for a few centimetres.
func test_one_clear_choice_when_two_spots_overlap() -> void:
	var h: Node = await _harness("convenience")
	var w: PoiWorld = h.world
	var a: PoiSpot = null
	var b: PoiSpot = null
	var cs: Array = w.spots_of("container").filter(func(x): return str(x.data.get("needs", "")) == "")
	for i in cs.size():
		for j in range(i + 1, cs.size()):
			var d: float = cs[i].plan_pos().distance_to(cs[j].plan_pos())
			if d > 0.6 and d < 2.4 and cs[i].front == cs[j].front:
				a = cs[i]
				b = cs[j]
				break
		if a != null:
			break
	if not check(a != null, "two containers side by side"):
		return
	var mid: Vector2 = (a.plan_pos() + b.plan_pos()) * 0.5
	var cands: Array = w.interactables()
	var to_a: Vector2 = (a.interact_point() - mid).normalized()
	var to_b: Vector2 = (b.interact_point() - mid).normalized()
	check(Finder.best(cands, mid, to_a) == a, "facing the first: the first")
	check(Finder.best(cands, mid, to_b) == b, "facing the second: the second")
	# no flicker: a few centimetres nearer the other one keeps the current choice
	var nudge: Vector2 = mid + (b.plan_pos() - mid).normalized() * 0.08
	check(Finder.best(cands, nudge, Vector2.ZERO, a) == a, "kept for a few centimetres")
	var closer: Vector2 = mid + (b.plan_pos() - mid).normalized() * 0.5
	check(Finder.best(cands, closer, Vector2.ZERO, a) == b, "but not when clearly nearer the other")
	# a searched, empty one beside an unsearched one: the one to use wins
	var box: Dictionary = PoiState.container(h.poi.record, a.id)
	box["items"].clear()
	box["searched"] = true
	check(a.interact_prompt().ends_with("searched · empty"), "the first is empty: %s" % a.interact_prompt())
	var near_a: Vector2 = mid + (a.plan_pos() - mid).normalized() * 0.2
	check(Finder.best(cands, near_a, Vector2.ZERO) == b, "the searchable one before the empty note")
	check(Finder.best(cands, a.plan_pos(), Vector2.ZERO) == a, "standing right at the empty one, its note shows")
	# the harness's own prompt follows the same rule (one prompt, never two)
	h.player.global_position = Vector3(near_a.x, 0, near_a.y)
	await frames(2)
	var want: Node3D = Finder.best(w.interactables(), near_a, Finder.facing_of(h.player), h._focus)
	check(h._focus == want and want != null, "the prompt's choice (%s)" % str(h._focus))
	check_eq(h.hud.debug_texts()["prompt"], str(want.interact_prompt()), "one prompt")


# --- the panel and the pack ----------------------------------------------------------------

func test_panel_weights_caps_and_the_boot() -> void:
	var h: Node = await _harness("convenience", true)
	var s := _full_box(h)
	var items: Dictionary = h.poi.record["c"][s.id]["items"]
	items.clear()
	items["water"] = 40
	items["snacks"] = 4
	_search(h, s)
	check(h.poi.panel.is_open, "the panel")
	var row: Control = h.poi.panel.find_child("Stored_water", true, false)
	if check(row != null, "a row for the water"):
		check_eq((row.get_node("Weight") as Label).text, "wt 40", "its weight")
		check_eq((row.get_node("Takeall") as Button).text, "Take 30", "Take all says what fits")
	check_eq(h.poi.panel.take("water", 40), 30, "the pack takes 30")
	check(h.poi.pack_full(), "full")
	check(h.poi.panel.last_text.contains("Your pack is full") and h.poi.panel.last_text.contains("boot"), "says so: %s" % h.poi.panel.last_text)
	row = h.poi.panel.find_child("Stored_snacks", true, false)
	check(row != null and (row.get_node("Takeall") as Button).disabled, "nothing more fits")
	check(h.toasts.back().begins_with("Your pack is full (30 / 30)"), "a clear message: %s" % h.toasts.back())
	h.poi.close_panel()
	# the boot: stow everything found here in one go
	h.poi.open_cargo()
	check(h.poi.panel.find_child("StowFound", true, false) != null, "the boot offers 'Stow what you found'")
	var got: Dictionary = h.poi.panel.stow_found()
	check_eq(int(got.get("water", 0)), 30, "into the boot")
	check_eq(int(h.poi.cargo.get("water", 0)), 30, "the boot holds it")
	check(not h.poi.pack_full() and PoiState.pack_load(h.state, h.poi.pack) == 0.0, "the pack is empty again")
	h.poi.close_panel()
	h.poi.interact_spot(s)
	check_eq(h.poi.panel.take("water", 10), 10, "room again")
	h.poi.close_panel()


func test_the_hud_pack_line() -> void:
	var h: Node = await _harness("convenience")
	await frames(15)
	check_eq(h.hud.debug_texts()["pack"], "Pack 0 / 30", "on arrival")
	h.state.inventory.add("water", 18)
	h.poi.pack_add("water", 18)
	await frames(15)
	check_eq(h.hud.debug_texts()["pack"], "Pack 18 / 30", "what was taken here")
	h.state.inventory.add("water", 12)
	h.poi.pack_add("water", 12)
	await frames(15)
	check_eq(h.hud.debug_texts()["pack"], "Pack 30 / 30 · full", "full")
	var h2: Node = await _harness("library", true)
	await frames(15)
	check_eq(h2.hud.debug_texts()["pack"], "Pack 0 / 30 · Boot 0 / 60", "with the car")


# --- persistence ------------------------------------------------------------------------------

func test_take_leave_revisit_still_taken_and_left_items_stay() -> void:
	var h: Node = await _harness("convenience")
	var s := _full_box(h)
	var cid := s.id
	var items: Dictionary = h.poi.record["c"][cid]["items"]
	items.clear()
	items["canned_food"] = 3
	items["nails"] = 10
	_search(h, s)
	h.poi.panel.take("canned_food", 3)
	h.poi.panel.take("nails", 4)
	h.poi.close_panel()
	var pick: PoiSpot = null
	for p in (h.world as PoiWorld).spots_of("pickup"):
		if not h.poi.record["taken"].has(p.id):
			pick = p
	if pick != null:
		check(h.poi.pick_up(pick), "picked something up")
	var have: int = h.state.inventory.count("canned_food")
	h.poi.finish()
	var st: GameState = h.state
	h.queue_free()
	await frames(2)
	# the same day: nothing back, the rest still there
	var h2: Node = await _harness("convenience", false, st)
	var box: Dictionary = h2.poi.record["c"][cid]
	check(box["searched"], "still searched")
	check_eq(int(box["items"].get("canned_food", 0)), 0, "the food stays taken")
	check_eq(int(box["items"].get("nails", 0)), 6, "the nails left behind are still there")
	check_eq(h2.state.inventory.count("canned_food"), have, "nothing doubled")
	if pick != null:
		check(h2.poi.record["taken"].has(pick.id) and not (h2.world as PoiWorld).spot("pickup", pick.id).visual.visible, "the pickup stays taken")
	h2.poi.finish()
	h2.queue_free()
	await frames(2)
	# weeks later (refills are likely): what was left is still there, at least
	st.total_minutes += 1440.0 * 30.0
	var r := PoiState.begin_visit(st, "convenience")
	check(int(r["c"][cid]["items"].get("nails", 0)) >= 6, "left items stay across a refill (%s)" % str(r["c"][cid]["items"]))
	PoiState.finish_visit(st, "convenience")


## Take -> save at the POI -> Continue, through the real game: the inventory
## and the pack come back once, the container keeps what was left, a take of
## the rest gives only the rest.
func test_save_at_the_poi_and_continue_takes_nothing_twice() -> void:
	SaveGame.path_override = SAVE
	TravelFlow.skip_animation = true
	var g: Node = await _boot("new")
	var s: GameState = g.debug_state()
	s.total_minutes = 9.0 * 60.0
	await g.travel.depart("convenience")
	g = await _next_scene(g)
	s = g.debug_state()
	g.debug_kill_enemies()
	await frames(15)
	check_eq(g.hud.debug_texts()["pack"], "Pack 0 / 30", "the HUD's pack line at the store")
	var shelf: PoiSpot = null
	for sp in g.world.spots_of("container"):
		if str(sp.data.get("needs", "")) == "" and not bool(sp.data.get("picked", false)):
			shelf = sp
			break
	var cid := shelf.id
	var items: Dictionary = g.poi.record["c"][cid]["items"]
	items.clear()
	items["canned_food"] = 2
	items["snacks"] = 3
	g.debug_teleport_player(shelf.plan_pos())
	await physics_frames(2)
	g.poi.interact_spot(shelf)
	g.poi.complete_action()
	check(g.poi.panel.is_open, "the panel")
	g.poi.panel.take("canned_food", 2)
	g.poi.panel.take("snacks", 1)
	g.poi.close_panel()
	await frames(2)
	var have: Dictionary = s.inventory.counts.duplicate()
	var pack: Dictionary = g.poi.pack.duplicate()
	check_eq(g.debug_save(), "", "saving at the POI")
	g.queue_free()
	await frames(3)
	g = await _boot("continue")
	s = g.debug_state()
	check(not g.is_home() and g.site_id() == "convenience", "Continue at the store")
	for id in have:
		check_eq(s.inventory.count(id), int(have[id]), "%s once" % id)
	check_eq(g.poi.pack, pack, "the pack came back")
	var box: Dictionary = g.poi.record["c"][cid]
	check(bool(box["searched"]), "still searched")
	check_eq(int(box["items"].get("canned_food", 0)), 0, "the food isn't back")
	check_eq(int(box["items"].get("snacks", 0)), 2, "the snacks left are still there")
	var sp2: PoiSpot = g.world.spot("container", cid)
	check(sp2.interact_prompt().contains("2 packs of snacks"), "the prompt says what's left: %s" % sp2.interact_prompt())
	g.debug_teleport_player(sp2.plan_pos())
	await physics_frames(2)
	g.poi.interact_spot(sp2)
	var got: Dictionary = g.poi.panel.take_everything()
	g.poi.panel.take_everything()
	g.poi.close_panel()
	check_eq(got, {"snacks": 2}, "only the rest")
	check_eq(s.inventory.count("snacks"), int(have.get("snacks", 0)) + 2, "and only once")
	g.leave_site()
	check(await _wait_until(func(): return g.left_to != "", 60), "leaves")
	g = await _next_scene(g)
	await frames(15)
	check(g.is_home(), "home")
	check_eq(g.hud.debug_texts()["pack"], "", "no pack line at home")


## Partial loot goes with Eli whenever he leaves, even mid-search.
func test_retreat_any_time_with_what_was_taken() -> void:
	var h: Node = await _harness("convenience")
	var s := _full_box(h)
	var items: Dictionary = h.poi.record["c"][s.id]["items"]
	items.clear()
	items["water"] = 2
	_search(h, s)
	h.poi.panel.take("water", 1)
	h.poi.close_panel()
	var other: PoiSpot = null
	for o in (h.world as PoiWorld).spots_of("container"):
		if o != s and str(o.data.get("needs", "")) == "" and not PoiState.container(h.poi.record, o.id)["searched"]:
			other = o
			break
	h.player.global_position = other.position
	h.poi.interact_spot(other)
	check(not h.poi._action.is_empty(), "searching the next one")
	h.poi.interact_spot((h.world as PoiWorld).spots_of("exit")[0])
	check(h.poi._action.is_empty() and h.left, "left at once")
	check_eq(int(h.poi.finished["pack"].get("water", 0)), 1, "with what was taken")
	check_eq(int(PoiState.container(h.poi.record, s.id)["items"].get("water", 0)), 1, "the rest stays")


# --- one-of-a-kind items ------------------------------------------------------------------------

func test_a_learned_or_stored_book_never_comes_back() -> void:
	var st := GameState.new_run(77)
	var r := PoiState.begin_visit(st, "library")
	var shelves: Array = (PoiDefs.get_def("library")["layout"]["containers"] as Array).filter(func(e): return not e["picked"])
	for e in shelves:                    # every shelf searched and emptied, two books found
		var box := PoiState.container(r, e["id"])
		box["items"].clear()
		box["searched"] = true
	for book in ["book_woodworking", "book_reinforced"]:
		st.inventory.add(book, 1)
		PoiState.note_found(st, "library", book)
	Research.learn(st, Research.book_skill("book_woodworking"))
	st.inventory.remove("book_woodworking", 1)        # read
	st.inventory.remove("book_reinforced", 1)         # stored at home: not carried, not learned
	check(not ExpeditionData.owns(st, "book_reinforced") and not Research.knows(st, "reinforced"), "the stored book is neither carried nor known")
	PoiState.finish_visit(st, "library")
	var seen := {}
	for k in 25:
		st.total_minutes += 1440.0 * 20.0                  # long gaps: refills at their most likely
		r = PoiState.begin_visit(st, "library")
		for e in shelves:
			var box := PoiState.container(r, e["id"])
			for id in box["items"]:
				seen[id] = true
			box["items"].clear()
			box["searched"] = true
		PoiState.finish_visit(st, "library")
	check(not seen.has("book_woodworking"), "a learned book never comes back")
	check(not seen.has("book_reinforced"), "a book found earlier never comes back, even stored at home")
	check(not seen.is_empty(), "the shelves do refill (%s)" % str(seen.keys()))
	# the developer's restore keeps the rule too
	PoiState.restore(st, "library")
	for cid in PoiState.record(st, "library")["c"]:
		var it: Dictionary = PoiState.record(st, "library")["c"][cid]["items"]
		check(not it.has("book_woodworking") and not it.has("book_reinforced"), "restored: no second copy in %s" % cid)
	# a one-of-a-kind item in a car's boot or another place's box isn't made again
	var st2 := GameState.new_run(78)
	st2.inventory.remove("crowbar", st2.inventory.count("crowbar"))
	var other := PoiState.begin_visit(st2, "forest")
	other["visit"]["cargo"]["crowbar"] = 1
	check(PoiState.placed_elsewhere(st2, "crowbar"), "the crowbar in the boot counts")
	check(not PoiState.may_find(st2, PoiState.record(st2, "convenience"), "crowbar"), "so no store makes another")
	other["visit"]["cargo"].erase("crowbar")
	var box0: Dictionary = PoiState.container(other, str((PoiDefs.get_def("forest")["layout"]["containers"] as Array)[0]["id"]))
	box0["items"]["shotgun"] = 1
	check(not PoiState.may_find(st2, PoiState.record(st2, "convenience"), "shotgun"), "nor a shotgun lying in the woods")


# --- the real game ------------------------------------------------------------------------------

func _boot(mode: String) -> Node:
	SaveGame.path_override = SAVE
	GameLaunch.mode = mode
	GameLaunch.seed = 8118
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
