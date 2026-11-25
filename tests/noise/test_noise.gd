extends "res://tests/test_case.gd"
## Experiment 007 (N): event-based noise. Levels and radii, exposure by place
## (outdoors, exterior and central rooms, open doors raising it), the event
## log without a game, construction noise classification, and enemies
## hearing a noise through a game-shaped root (calm ones investigate or turn
## hostile, hostile ones are left alone, nobody is spawned).

const Roster := preload("res://src/game/enemy_roster.gd")
const LIVING_ROOM := Vector2(6.0, 8.2)
const FRONT_YARD := Vector2(9.0, 11.2)


## Just enough of SurvivalGame for NoiseEvent.game_of() and the dispatch.
class FakeGame extends Node3D:
	var roster: Node3D
	var state: GameState
	var world: HouseWorld
	var player: VoxelPlayer


class FakeBuild extends Node:
	var t := "place"
	var m := "wood"
	var world: HouseWorld
	func tool() -> String:
		return t
	func _mat() -> String:
		return m


func _world() -> HouseWorld:
	var w := HouseWorld.new()
	add(w)
	w.build_new()
	return w


func test_levels_radii_and_events() -> void:
	check(is_equal_approx(NoiseEvent.radius_for(1.0), 6.0) and is_equal_approx(NoiseEvent.radius_for(4.0), 26.0)
		and is_equal_approx(NoiseEvent.radius_for(5.0), 38.0), "radii: low 6 m, very high 26 m, extreme 38 m")
	check(NoiseEvent.radius_for(4.5) > 26.0 and NoiseEvent.radius_for(4.5) < 38.0, "levels between whole steps interpolate")
	check(NoiseEvent.level_of("hammer_wood") < NoiseEvent.level_of("drill") and NoiseEvent.level_of("drill") < NoiseEvent.level_of("hammer_metal")
		and NoiseEvent.level_of("hammer_metal") < NoiseEvent.level_of("gunfire") and NoiseEvent.level_of("gunfire") < NoiseEvent.level_of("explosion"),
		"wood < drilling < metal < gunfire < explosions")
	check_eq(NoiseEvent.level_of("smash_furniture"), NoiseEvent.HIGH, "smashing furniture is high")
	check(NoiseEvent.weapon_level("shotgun") >= NoiseEvent.weapon_level("handgun") and NoiseEvent.weapon_level("handgun") == NoiseEvent.VERY_HIGH,
		"gunfire is very high, the shotgun a little louder")
	check(NoiseEvent.heard_at(4.0, 1.0, 0.0, 26.0) == 4.0 and NoiseEvent.heard_at(4.0, 1.0, 13.0, 26.0) == 2.0
		and NoiseEvent.heard_at(4.0, 1.0, 27.0, 26.0) == 0.0, "what a listener hears falls off to 0 at the radius")


func test_exposure_by_place_and_openings() -> void:
	var w := _world()
	var out := NoisePlace.classify(w, 0, FRONT_YARD)
	check(out["place"] == "outdoors" and out["exposure"] == NoisePlace.OUTDOORS, "the yard is outdoors (%s)" % [out])
	var map := HouseRooms.find(w, 0)
	var places := {}
	for r in map["rooms"]:
		var c := NoisePlace.classify(w, 0, r["centre"])
		places[c["place"]] = true
		check(c["exposure"] < NoisePlace.OUTDOORS, "room %d (%s) is quieter outside than the yard: %.2f" % [r["index"], c["place"], c["exposure"]])
	check(places.has("exterior room"), "rooms with outer walls are exterior rooms (%s)" % [places.keys()])
	var living := NoisePlace.classify(w, 0, LIVING_ROOM)
	check_eq(living["place"], "exterior room", "the living room has outer walls")
	# Open every door of the living room: more exposure.
	var opened := 0
	for d in NoisePlace.door_sides(w, map):
		if d["door"] != null and (int(d["a"]) == living["room"] or int(d["b"]) == living["room"]):
			w.set_door_open(d["door"], true)
			opened += 1
	check(opened > 0, "the living room has doors (%d)" % opened)
	var open := NoisePlace.classify(w, 0, LIVING_ROOM)
	check(open["exposure"] > living["exposure"] and open["notes"].has("open door"), "open doors raise the exposure (%.2f -> %.2f %s)" % [living["exposure"], open["exposure"], open["notes"]])
	check(open["exposure"] <= NoisePlace.OUTDOORS, "never above outdoors")
	# A basement and an upper storey are reduced
	check(NoisePlace.BASEMENT < NoisePlace.CENTRAL and NoisePlace.UPPER < NoisePlace.EXTERIOR, "basement strongly reduced, upper interior reduced")


func test_emit_without_a_game_logs_and_classifies() -> void:
	var w := _world()
	NoiseEvent.log.clear()
	var ev := NoiseEvent.emit(w, Vector3(LIVING_ROOM.x, 0.5, LIVING_ROOM.y), NoiseEvent.HIGH, "test")
	check(not ev.is_empty() and ev["place"] == "exterior room" and ev["heard"] == 0, "classified, nobody to hear it (%s)" % [ev])
	check(is_equal_approx(ev["radius"], NoiseEvent.radius_for(3.0) * ev["exposure"]), "radius = level radius x exposure")
	check_eq(NoiseEvent.log.size(), 1, "logged without a game")
	check(NoiseEvent.emit(null, Vector3.ZERO, 0.0, "silent").is_empty(), "level 0 emits nothing")
	var out := NoiseEvent.emit(null, Vector3.ZERO, 2.0, "nowhere")
	check(out["place"] == "outdoors" and is_equal_approx(out["radius"], NoiseEvent.radius_for(2.0)), "no world: outdoors")
	w.explode(Vector3(FRONT_YARD.x, 1.0, FRONT_YARD.y), 1.5, 4.0)
	check_eq(NoiseEvent.log[NoiseEvent.log.size() - 1]["source"], "explosion", "a blast is an extreme noise")
	check_eq(float(NoiseEvent.log[NoiseEvent.log.size() - 1]["level"]), NoiseEvent.EXTREME, "extreme")


func test_build_noise_by_material() -> void:
	var bm := FakeBuild.new()
	add(bm)
	check_eq(BuildNoise.event_for(bm, {"piece": "wall"}), "hammer_wood", "a wooden wall: hammering wood")
	check_eq(BuildNoise.event_for(bm, {"piece": "stone_wall"}), "masonry", "a stone wall: masonry")
	check_eq(BuildNoise.event_for(bm, {"piece": "metal_door"}), "hammer_metal", "a metal door: hammering metal")
	bm.m = "iron"
	check_eq(BuildNoise.event_for(bm, {"piece": "iron_barricade"}), "hammer_metal", "an iron barricade: metal")
	bm.m = "wood"
	bm.t = "upgrade"
	check_eq(BuildNoise.event_for(bm, {"piece": "upgrade", "object": null, "segs": []}), "hammer_metal", "iron plating: metal")
	bm.t = "repair"
	check_eq(BuildNoise.event_for(bm, {"piece": "repair", "object": null, "segs": []}), "hammer_wood", "repairing wood")
	bm.t = "demolish"
	check_eq(BuildNoise.event_for(bm, {"piece": "demolish", "furniture": "sofa", "object": null}), "smash_furniture", "smashing furniture")
	bm.t = "move"
	check_eq(BuildNoise.event_for(bm, {"piece": "move"}), "", "moving furniture is quiet")
	bm.t = "place"
	check_eq(BuildNoise.event_for(bm, {"piece": "rug"}), "", "a rug is quiet")


func test_enemies_hear_through_a_game_root() -> void:
	var g := FakeGame.new()
	add(g)
	g.state = GameState.new()
	g.world = HouseWorld.new()
	g.add_child(g.world)
	g.world.build_new()
	g.player = VoxelPlayer.new()
	g.player.input_enabled = false
	g.add_child(g.player)
	g.player.global_position = Vector3(LIVING_ROOM.x, 0, LIVING_ROOM.y)
	g.roster = Roster.new()
	g.roster.setup(g.world, g.player, 3)
	g.add_child(g.roster)
	await physics_frames(2)
	var calm: AIEnemy = g.roster.spawn_type("psycho", Vector2(9.0, 13.5), {"mode": "wander"})
	var far: AIEnemy = g.roster.spawn_type("psycho", Vector2(-6.0, -5.0), {"mode": "wander"})
	var hostile: AIEnemy = g.roster.spawn_type("psycho", Vector2(20.0, 4.0), {})
	check(calm.is_calm() and far.is_calm() and not hostile.is_calm(), "calm by mode, hostile without")
	var n0: int = g.roster.enemies.size()
	# A low noise inside the house: nobody that far hears it.
	var ev := NoiseEvent.emit(g.world, Vector3(4.0, 0.5, 6.0), NoiseEvent.LOW, "hammer_wood")
	check_eq(int(ev["heard"]), 0, "hammering wood indoors is heard by nobody out there (r %.1f m)" % ev["radius"])
	# Smashing in the front yard: the near calm one investigates or turns, the far one doesn't hear.
	ev = NoiseEvent.emit(g.world, Vector3(FRONT_YARD.x, 0.5, FRONT_YARD.y), NoiseEvent.HIGH, "smash_furniture")
	check(int(ev["heard"]) >= 1, "a high noise outdoors carries (%d heard, r %.1f m)" % [ev["heard"], ev["radius"]])
	check(calm.mind == null or calm.state_name() == "investigate", "the near one comes to look or turns (%s)" % calm.state_name())
	check(far.is_calm() and far.mind.heard == 0, "the far one heard nothing")
	check_eq(g.roster.enemies.size(), n0, "noise never spawns enemies")
	# An explosion next to it: provoked for sure.
	var ev2 := NoiseEvent.emit(g.world, calm.global_position + Vector3(1, 0, 0), NoiseEvent.EXTREME, "explosion")
	check(not calm.is_calm() and calm.state_name() == "chase", "an explosion next to it turns it hostile (%s)" % calm.state_name())
	check(int(ev2["provoked"]) >= 0, "counted")
	check(not hostile.is_calm(), "hostile enemies stay hostile")
