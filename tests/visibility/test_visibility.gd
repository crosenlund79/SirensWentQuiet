extends "res://tests/test_case.gd"
## Experiment 007 (N): room-based visibility. The pure rules (full, near
## through doorways, partial through open doors, hidden; outdoors), passages
## found in a real house, and one smoke run in the real game scene: a closed
## door hides the bedroom's furniture and an enemy in it, opening it shows
## them, changing room swaps what hides, build mode and "Reveal all" show
## everything, gunfire is a noise event, a calm straggler, the F10 buttons.

const SCENE := "res://src/game/game.tscn"
const SAVE := "user://test_visibility.dat"
const LIVING_ROOM := Vector2(6.0, 8.2)
const BEDROOM := Vector2(2.5, 2.0)
const BEDROOM_DOOR := Vector3i(0, 4, 2)          ## the bedroom's doorway (no leaf in the plan)

const RV := preload("res://src/visibility/room_visibility.gd")


func _map(n: int, exposed := []) -> Dictionary:
	var rooms := []
	for i in n:
		rooms.append({"index": i, "exposed": i in exposed})
	return {"rooms": rooms}


func test_rules() -> void:
	var lk := {"pairs": [[0, 2, "doorway"], [1, 2, "door"]], "outside": {1: "door"}}
	var s := RV.compute(_map(4), lk, 2)
	check(s[2] == RV.FULL and s[0] == RV.NEAR and s[1] == RV.PARTIAL and s[3] == RV.HIDDEN, "Eli's room full, doorway near, open door partial, closed hidden (%s)" % [s])
	s = RV.compute(_map(4), lk, 0)
	check(s[0] == RV.FULL and s[2] == RV.NEAR and s[1] == RV.HIDDEN and s[3] == RV.HIDDEN, "only direct neighbours show (%s)" % [s])
	s = RV.compute(_map(4, [3]), lk, -1)
	check(s[3] == RV.NEAR and s[1] == RV.PARTIAL and s[0] == RV.HIDDEN and s[2] == RV.HIDDEN, "outdoors: open to the outside near, behind an open outer door partial (%s)" % [s])
	check(RV.compute({"rooms": []}, lk, 0).is_empty(), "no rooms: nothing to hide")
	check(RV.DIM[RV.HIDDEN] > RV.DIM[RV.PARTIAL] and RV.DIM[RV.PARTIAL] > RV.DIM[RV.NEAR] and RV.DIM[RV.FULL] == 0.0, "darker the less you see")


func test_passages_in_the_house() -> void:
	var w := HouseWorld.new()
	add(w)
	w.build_new()
	var map := HouseRooms.find(w, 0)
	var living := HouseRooms.room_index_at(map, w.nav, LIVING_ROOM)
	var bed := HouseRooms.room_index_at(map, w.nav, BEDROOM)
	check(living >= 0 and bed >= 0 and living != bed, "two rooms (%d, %d)" % [living, bed])
	var lk := RV.links(w, map)
	var joined: bool = lk["pairs"].any(func(p): return (p[0] == living and p[1] == bed or p[0] == bed and p[1] == living) and p[2] == "doorway")
	check(joined, "the bedroom's doorway joins it to the living room (%s)" % [lk])
	var door := w.place_object("door", HouseWorld.seg_center(BEDROOM_DOOR), w.seg_rot(BEDROOM_DOOR), true)
	check(door != null and not door.open, "a closed door hung in the doorway")
	map = HouseRooms.find(w, 0)
	lk = RV.links(w, map)
	var s := RV.compute(map, lk, living)
	check_eq(s[bed], RV.HIDDEN, "behind a closed door the bedroom hides")
	w.set_door_open(door, true)
	s = RV.compute(map, RV.links(w, map), living)
	check_eq(s[bed], RV.PARTIAL, "through the open door it shows, dimmed")
	var cache := RoomCache.new()
	var m1 := cache.map_of(w, 0)
	check(cache.map_of(w, 0) == m1 and cache.runs == 1, "rooms are kept until the structure changes")
	w.set_door_open(door, false)
	cache.map_of(w, 0)
	check_eq(cache.runs, 2, "a door change finds them again")


# --- the real game ------------------------------------------------------------------------

func _boot() -> Node:
	SaveGame.path_override = SAVE
	GameLaunch.mode = "new"
	GameLaunch.seed = 707
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


func _bed_node(w: HouseWorld) -> Node3D:
	for id in w.furniture.pieces:
		var p: Dictionary = w.furniture.pieces[id]
		if p["f"]["type"] == "bed" and (p["f"]["rect"] as Rect2).has_point(Vector2(2.4, 1.6)) or p["f"]["room"] == "bedroom" and p["f"]["type"] == "bed":
			return p["node"]
	return null


func test_game_smoke_visibility_noise_and_stragglers() -> void:
	var g := await _boot()
	var vis: Node = g.visibility
	var w: HouseWorld = g.world
	check(vis != null and g.noise != null, "the game has the visibility and noise helpers")
	g.debug_teleport_player(LIVING_ROOM)
	vis.refresh("test")
	check(vis.here >= 0 and vis.states[vis.here] == RV.FULL, "Eli's room is fully visible (%s)" % vis.info())
	var bed := _bed_node(w)
	check(bed != null and bed.visible and not vis.is_hidden(bed), "the bedroom shows through its open doorway")
	# A closed door hides the bedroom, its furniture and an enemy in it.
	var door := w.place_object("door", HouseWorld.seg_center(BEDROOM_DOOR), w.seg_rot(BEDROOM_DOOR), true)
	var lurker: AIEnemy = g.roster.spawn_type("psycho", BEDROOM + Vector2(0.8, 0.9), {"mode": "hidden"})
	await seconds(0.5)
	check_eq(vis.state_at(BEDROOM), "hidden", "a closed door hides the bedroom (%s)" % vis.info())
	check(not bed.visible and vis.is_hidden(bed), "its bed is hidden")
	check(not lurker.rig.visible and vis.is_hidden(lurker), "so is the enemy in it")
	check(lurker.is_physics_processing() and lurker.alive, "hidden, it keeps simulating")
	check(int(vis.stats["hidden_nodes"]) > 0 and g.debug_world().get_node_or_null("../Visibility/RoomShade") != null, "the floor overlay exists")
	w.set_door_open(door, true)
	await seconds(0.5)
	check_eq(vis.state_at(BEDROOM), "partial", "the open door shows it, dimmed")
	check(bed.visible and lurker.rig.visible, "bed and enemy show again")
	w.set_door_open(door, false)
	await seconds(0.5)
	# Eli walks into the bedroom: it shows, the living room hides.
	g.debug_teleport_player(BEDROOM)
	await seconds(0.3)
	check(vis.state_at(BEDROOM) == "full" and vis.state_at(LIVING_ROOM) == "hidden", "changing room swaps what hides (%s)" % vis.info())
	check(bed.visible, "the bed shows in Eli's room")
	# Build mode and Reveal all show everything.
	g.state.cheats["unlimited"] = true
	g.build.set_active(true)
	await seconds(0.3)
	check(vis.states.is_empty() and int(vis.stats["hidden_nodes"]) == 0, "build mode shows every room")
	g.build.set_active(false)
	await seconds(0.3)
	check(not vis.states.is_empty(), "rooms again after build mode")
	var said: String = vis.dev_toggle_reveal()
	check(not vis.enabled and int(vis.stats["hidden_nodes"]) == 0 and "Reveal all" in said, "Reveal all (%s)" % said)
	vis.dev_toggle_reveal()
	check(vis.enabled and "Room boundaries" in vis.dev_toggle_bounds() and vis.show_bounds, "room boundaries on")
	check("Visibility" in vis.dev_toggle_diagnostics(), "diagnostics")
	# Noise: gunfire is an event; a calm straggler from F10.
	lurker.kill_quietly()
	g.debug_teleport_player(Vector2(9.0, 11.2))
	var n0: int = g.noise.total
	g.debug_fire_at(Vector2(12.0, 11.2))
	check(g.noise.total > n0 and g.noise.last()["source"] == "gunfire", "a shot is a noise event (%s)" % [g.noise.last()])
	check(g.noise.last()["place"] == "outdoors", "fired in the yard: outdoors")
	var txt: String = g.noise.dev_spawn_calm("psycho")
	check(g.roster.calm_count() == 1, "F10 calm straggler (%s)" % txt)
	check("gunfire" in g.noise.dev_log_text().to_lower(), "the noise log lists it")
	var m: DevMenu = g.debug_ui().dev_menu
	m.toggle()
	await frames(2)
	for b in ["Noise: low", "Noise: high", "Noise: extreme", "Last noises", "Calm straggler", "Room boundaries", "Visibility diagnostics", "Reveal all"]:
		check(m.button(b) != null, "F10 has \"%s\"" % b)
	m.button("Noise: extreme").pressed.emit()
	check(g.noise.last()["level"] == NoiseEvent.EXTREME, "the F10 sample noise (%s)" % m.last_status)
	m.toggle()
