extends "res://tests/test_case.gd"
## Exp 008 (H): the three new hand-made places: the Hardware Store
## ("hardware"), Pike's Guns ("gun_shop") and the Medical Clinic ("clinic").
## Each builds in the POI harness (src/poi/poi_preview.tscn) and is no longer
## a placeholder; its rooms are there; the better loot sits behind a lock
## (the location's locked table); every container's front is walkable and
## reachable from the entry on the nav grid (doors opened, locked ones
## forced), and some without forcing anything; the layout has peek spots and
## doorways (SPEC-008), lights that burn and story details; the clinic's lit
## rooms can be searched without a flashlight and its dark ones can't; the
## gun shop's floor gives a firearm on few visits.

const PREVIEW := "res://src/poi/poi_preview.tscn"
const PLACES := {
	"hardware": ["sales", "storage", "stockroom"],
	"gun_shop": ["shop", "office", "back_room"],
	"clinic": ["waiting", "reception", "corridor", "exam_1", "exam_2", "exam_3", "staff", "storage"],
}


func _harness(id: String, car := false) -> Node:
	var h: Node = (load(PREVIEW) as PackedScene).instantiate()
	h.configure(id, car, 4242)
	add(h)
	await physics_frames(3)
	return h


## Nav cells reachable on foot from `from` (walkable cells, 4-connected).
static func _reach(nav: GridNav, from: Vector2) -> Dictionary:
	var seen := {}
	var start := nav.cell_of(from)
	if not nav.is_walkable(start):
		return seen
	var todo: Array[Vector2i] = [start]
	seen[start] = true
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not seen.has(n) and nav.is_walkable(n):
				seen[n] = true
				todo.append(n)
	return seen


## A walkable reached cell at p or within one cell of it.
static func _reached(nav: GridNav, seen: Dictionary, p: Vector2) -> bool:
	var c := nav.cell_of(p)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if seen.has(c + Vector2i(dx, dy)):
				return true
	return false


func test_layouts_are_sound_data() -> void:
	for id in PLACES:
		var d := PoiDefs.get_def(id)
		var L: Dictionary = d["layout"]
		check(not d["placeholder"] and d["template"] != "placeholder", "%s is hand-made" % id)
		check(not PoiDefs.arrival_text(id).begins_with("Placeholder"), "%s: its own arrival line (%s)" % [id, PoiDefs.arrival_text(id)])
		var rooms := (L["rooms"] as Array).map(func(r): return r["id"])
		for r in PLACES[id]:
			check(r in rooms, "%s: room %s" % [id, r])
		# walls on whole-metre lines, door gaps on whole-metre segments
		var walls: Array[Rect2] = []
		for w in L["walls"]:
			var a: Vector2 = w["a"]
			var b: Vector2 = w["b"]
			check(a == a.round() and b == b.round() and (a.x == b.x or a.y == b.y), "%s: wall %s-%s on whole metres" % [id, a, b])
			walls.append(Rect2(a.min(b), (b - a).abs()).grow(0.1))
			for g in w["gaps"]:
				if g["kind"] != "window":
					check(is_equal_approx(float(g["from"]), round(float(g["from"]))) and is_equal_approx(float(g["to"]), round(float(g["to"]))),
						"%s: a %s gap on whole metres (%s)" % [id, g["kind"], str(g)])
		# containers: unique ids, inside no wall and no other piece, on the lot
		var ids := {}
		var pieces: Array = (L["containers"] as Array) + (L["props"] as Array).filter(func(p): return p["block"])
		for c in L["containers"]:
			check(not ids.has(c["id"]), "%s: container id %s is unique" % [id, c["id"]])
			ids[c["id"]] = true
			var r: Rect2 = c["rect"]
			check(HousePlan.YARD.encloses(r), "%s: %s on the lot" % [id, c["id"]])
			for w in walls:
				check(not w.grow(-0.02).intersects(r), "%s: %s clear of the wall at %s" % [id, c["id"], w])
			for p in pieces:
				if p != c:
					check(not (p["rect"] as Rect2).grow(-0.02).intersects(r), "%s: %s clear of %s" % [id, c["id"], p.get("id", p["type"])])
			check(c["table"] in ["loot", "locked"] and c["needs"] in ["", "crowbar", "flashlight"], "%s: %s uses the generic rules" % [id, c["id"]])
		check((L["containers"] as Array).any(func(c): return c["picked"]), "%s: some containers were picked clean" % id)
		# the better loot behind a lock: a locked door into its room, or a crowbar on the container
		var locked_rooms := {}
		for dr in L["doors"]:
			if dr["locked"]:
				for rm in L["rooms"]:
					if (rm["rect"] as Rect2).grow(0.3).has_point(Vector2(dr["x"], dr["y"])):
						locked_rooms[rm["id"]] = true
		var behind := (L["containers"] as Array).filter(func(c): return c["table"] == "locked" and (c["needs"] == "crowbar" or locked_rooms.has(c["room"])))
		check(behind.size() >= 2, "%s: the locked table sits behind a lock (%d containers)" % [id, behind.size()])
		check(not (d["locked"] as Array).is_empty(), "%s: a locked table" % id)
		# enemies have places: hidden in rooms, wandering, peeking, coming in
		check((L["hide"] as Array).size() >= 3 and not (L["wander"] as Array).is_empty(), "%s: hiding and wandering places" % id)
		check(not (L.get("peek", []) as Array).is_empty() and not (L.get("doorways", []) as Array).is_empty(), "%s: peek spots and doorways" % id)
		for pk in L.get("peek", []):
			check(HousePlan.YARD.has_point(pk["at"]) and HousePlan.YARD.has_point(pk["look"]), "%s: peek %s on the lot" % [id, str(pk)])
		check((L.get("lights", []) as Array).size() >= 2 and (L.get("story", []) as Array).size() >= 4, "%s: lights and story details" % id)
		check(HousePlan.YARD.encloses(L["car"]["rect"]), "%s: the car stands on the lot" % id)
	var hw: Dictionary = PoiDefs.get_def("hardware")
	check((hw["locked"] as Array).any(func(e): return e[0] == "iron"), "the hardware stockroom may hold iron")
	check((hw["loot"] as Array).any(func(e): return e[0] == "nails") and (hw["loot"] as Array).any(func(e): return Research.is_book(e[0])),
		"the hardware store: nails and manuals")
	var back_room: Rect2 = Rect2()
	for rm in PoiDefs.get_def("gun_shop")["layout"]["rooms"]:
		if rm["id"] == "back_room":
			back_room = rm["rect"]
	check((PoiDefs.get_def("gun_shop")["layout"]["hide"] as Array).any(func(p): return back_room.grow(1.5).has_point(p)), "someone may wait by the back room")


func test_each_place_builds_and_is_reachable() -> void:
	for id in PLACES:
		var h: Node = await _harness(id, true)
		var w: PoiWorld = h.world
		if not check(w != null and w.is_inside_tree(), "%s: built" % id):
			continue
		check(h.toasts.size() >= 1 and h.toasts[0] == PoiDefs.ARRIVAL[id], "%s: arrival %s" % [id, str(h.toasts)])
		check(w.nav.is_walkable(w.nav.cell_of(w.entry_point())), "%s: the entry is walkable" % id)
		check(w.grid.solid_count > 10000 and not w.openings.is_empty(), "%s: voxel walls with doorways" % id)
		var spots := w.spots_of("container")
		check(spots.size() == (w.layout["containers"] as Array).size(), "%s: a spot per container (%d)" % [id, spots.size()])
		# without forcing anything: the unlocked doors open
		for o in w.objects:
			if o is PoiDoor and not (o as PoiDoor).locked and not o.open:
				w.set_door_open(o, true)
		var open_reach := _reach(w.nav, w.entry_point())
		var some := 0
		for s in spots:
			if _reached(w.nav, open_reach, s.plan_pos()):
				some += 1
		check(some >= 3, "%s: containers reachable from the entry without a crowbar (%d)" % [id, some])
		for e in w.exit_points():
			check(_reached(w.nav, open_reach, e), "%s: exit %s reachable" % [id, str(e)])
		check(_reached(w.nav, open_reach, w.layout["car"]["cargo"]), "%s: the car's boot reachable" % id)
		# with the locked doors forced: every container's front
		for o in w.objects:
			if o is PoiDoor and not o.open:
				(o as PoiDoor).locked = false
				w.set_door_open(o, true)
		var all := _reach(w.nav, w.entry_point())
		for s in spots:
			check(_reached(w.nav, all, s.plan_pos()), "%s: %s's front %s is reachable" % [id, s.id, str(s.plan_pos())])
		for p in w.spots_of("pickup"):
			check(_reached(w.nav, all, p.plan_pos()), "%s: pickup %s reachable" % [id, p.id])
		for pk in w.layout["peek"]:
			check(_reached(w.nav, all, pk["at"]), "%s: peek spot %s reachable" % [id, str(pk["at"])])
		for dw in w.layout["doorways"]:
			check(_reached(w.nav, all, dw), "%s: doorway %s reachable" % [id, str(dw)])
		for hp in w.layout["hide"]:
			check(_reached(w.nav, all, hp), "%s: hiding place %s reachable" % [id, str(hp)])
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		check(w.nav.is_walkable(w.nav.cell_of(w.wander_point(rng))), "%s: a wander point" % id)
		# lights burn (day and night), story details are drawn
		var lights: Array = w.night_lights.filter(func(l): return l.get("poi", false))
		check(lights.size() == (w.layout["lights"] as Array).size(), "%s: lights spawned (%d)" % [id, lights.size()])
		await frames(2)
		for l in lights:
			var o: OmniLight3D = l["light"]
			check(o.is_inside_tree() and not o.shadow_enabled, "%s: a cheap light" % id)
			if not l["flicker"]:
				check(o.visible and o.light_energy > 0.1, "%s: a light left on (%s)" % [id, o.get_parent().name])
		check(w.get_children().filter(func(n): return str(n.name).begins_with("Story_")).size() == (w.layout["story"] as Array).size(),
			"%s: story details drawn" % id)
		var on := 0
		for i in 200:
			if PoiDressing.flicker(i * 0.05, 1.3) > 0.5:
				on += 1
		check(on > 100 and on < 200, "a dying tube blinks now and then (%d / 200)" % on)
		h.queue_free()
		await frames(2)


func test_clinic_lit_rooms_need_no_flashlight() -> void:
	var s := GameState.new_run(5)
	check(not PoiDefs.get_def("clinic")["dark"], "the clinic as a whole isn't dark any more")
	s.inventory.remove("flashlight", s.inventory.count("flashlight"))
	check_eq(TravelRules.block_reason(s, "clinic"), "", "no flashlight needed to go")
	check(not "flashlight" in ExpeditionData.destination("clinic")["requires"], "nor for the simulated expedition")
	var h: Node = await _harness("clinic")
	var w: PoiWorld = h.world
	h.state.inventory.remove("flashlight", h.state.inventory.count("flashlight"))
	var dark := {}
	for rm in w.rooms():
		dark[rm["id"]] = rm["dark"]
	check(dark["exam_3"] and dark["storage"] and not dark["waiting"] and not dark["reception"] and not dark["staff"], "dark rooms: %s" % str(dark))
	for cid in ["reception_desk", "first_aid", "drinks", "staff_fridge", "lockers"]:
		var sp := w.spot("container", cid)
		check(sp != null and str(h.poi.prompt_for(sp)).begins_with("[E] Search"), "%s: %s" % [cid, h.poi.prompt_for(sp) if sp != null else "missing"])
	var ex := w.spot("container", "exam3_cupboard")
	check(str(h.poi.prompt_for(ex)).contains("flashlight"), "exam room 3 is dark: %s" % h.poi.prompt_for(ex))
	h.player.global_position = ex.position
	h.poi.interact_spot(ex)
	check(h.toasts.back().contains("flashlight") and not h.poi.record["c"]["exam3_cupboard"]["searched"], "too dark to search: %s" % h.toasts.back())
	h.state.inventory.add("flashlight", 1)
	check(str(h.poi.prompt_for(ex)).begins_with("[E] Search"), "with a flashlight: %s" % h.poi.prompt_for(ex))
	var door: PoiDoor = w.door("storage")
	check(door != null and door.locked, "the medical store is locked")
	var cage := w.spot("container", "drug_cage")
	check(cage.data["table"] == "locked" and cage.data["needs"] == "flashlight", "the drug cage: the locked table, in the dark")


func test_gun_shop_floor_rarely_gives_a_firearm() -> void:
	var L: Dictionary = PoiDefs.get_def("gun_shop")["layout"]
	var floor_visits := 0
	var back_visits := 0
	var n := 80
	for k in n:
		var s := GameState.new_run(900 + k)
		s.total_minutes = 8.0 * 60.0
		var r := PoiState.begin_visit(s, "gun_shop")
		var on_floor := false
		var in_back := false
		for c in L["containers"]:
			for item in r["c"][c["id"]]["items"]:
				if Items.category(item) == "weapon":
					if c["table"] == "locked":
						in_back = true
					else:
						on_floor = true
		floor_visits += int(on_floor)
		back_visits += int(in_back)
	check(floor_visits < n * 0.35, "a firearm on the shop floor on few visits (%d / %d)" % [floor_visits, n])
	check(back_visits > floor_visits and back_visits < n, "better in the back room, not certain (%d / %d)" % [back_visits, n])
	var gs: PoiWorld = PoiWorld.new()
	gs.configure("gun_shop", null)
	add(gs)
	gs.build_new()
	check(gs.door("back_room").locked and gs.door("back_room").mat == "metal", "the back room's steel door is locked")
	check(gs.spot("container", "gun_locker").data["needs"] == "crowbar", "the gun locker needs the crowbar too")
