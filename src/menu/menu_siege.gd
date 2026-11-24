class_name MenuSiege
extends Node3D
## The main menu's live background (Experiment 004, E): the real house
## (HouseWorld, VoxelLighting) under siege by a small horde (the game's enemy
## roster and AI), with no player. Each round varies the house lightly through
## the world's own API (added wooden or stone wall runs with a door, boarded
## windows, iron plating, blast and gunshot pre-damage), the time of day and
## the camera side. The enemies chase hidden stand-in targets that hop between
## the rooms and the far side of the house, so they keep bashing through walls
## and doors; their wall strikes go to HouseWorld.enemy_strike (harder than in
## the game: it's a show). When about 35 % of the wall sections are broken, or
## after ROUND_SECONDS, the view fades out and a new round is built.
## Cost: one HouseWorld build per round (about 0.5 s headless, behind the
## fade), at most MAX_ENEMIES enemies, a slow orbiting camera. Leaving the menu
## frees it with the menu. Docs: docs/experiment-004/e_bar_car_menu.md.

signal round_started(n: int)

const Roster := preload("res://src/game/enemy_roster.gd")
const Director := preload("res://src/game/invasion_director.gd")

const MAX_ENEMIES := 7
const ROUND_SECONDS := 240.0
const BROKEN_SHARE := 0.35
const BROKEN_BELOW := 0.55            ## a wall section under this integrity counts as broken
const STRIKE := 2.5                   ## wall strike strength (the game uses 1)
const FIRST_WAVE := 3
const SPAWN_GAP := Vector2(2.5, 6.0)
const CHECK_EVERY := 1.5
const FADE := 1.1
const RETARGET_SECONDS := Vector2(14.0, 26.0)
const KINDS := [["psycho", 6.0], ["runner", 2.0], ["brute", 1.4], ["bomber", 0.7]]
const ORBIT_SPEED := 0.03             ## rad/s
const TIMES := [0.0, 0.25, 0.6, 0.85, 1.0]   ## night amounts: overcast day .. full night
## Yard lines that can take a wall run: [axis, line, from, to] (HouseWorld segments).
const RUNS := [[0, 11, -3, 3], [1, -2, 1, 8], [0, -2, 0, 12], [1, 15, 1, 5], [0, 11, 6, 12]]

var seed := 0
var rng := RandomNumberGenerator.new()
var lighting: VoxelLighting
var world: HouseWorld
var roster: Node3D
var camera: Camera3D
var round := 0
var round_t := 0.0
var broken_share := 0.0
var last_build_ms := 0.0
var variation := {}                   ## what this round changed (debug, tests)
var spawned := 0
var auto_run := true                  ## false: tests drive new_round() and _process themselves

var _round_root: Node3D
var _targets := {}                    ## enemy instance id -> stand-in target
var _spawn_t := 0.0
var _check_t := 0.0
var _orbit := 0.0
var _orbit_dir := 1.0
var _dist := 21.0
var _height := 14.0
var _centre := Vector3.ZERO
var _phase := ""                      ## "" | "run" | "out" | "in"
var _fade_t := 0.0
var _layer: CanvasLayer
var _fade_rect: ColorRect
var _muted := false                   ## the SFX bus is muted while a round is prepared
var _was_muted := false


func _ready() -> void:
	if seed == 0:
		seed = int(Time.get_ticks_usec() & 0x7fffffff)
	rng.seed = seed
	var fp: Rect2 = HousePlan.FOOTPRINT
	_centre = Vector3(fp.get_center().x, 0.0, fp.get_center().y)
	camera = Camera3D.new()
	camera.name = "SiegeCamera"
	camera.fov = 40.0
	camera.near = 0.5
	camera.far = 140.0
	add_child(camera)
	camera.make_current()
	_layer = CanvasLayer.new()
	_layer.layer = -1                 # above the 3D view, under the menu
	add_child(_layer)
	var shade := TextureRect.new()
	shade.name = "MenuShade"
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	var grad := Gradient.new()
	grad.set_color(0, Color(0.0, 0.0, 0.0, 0.78))
	grad.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
	grad.add_point(0.42, Color(0.0, 0.0, 0.0, 0.45))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 256
	tex.height = 4
	tex.fill_to = Vector2(0.72, 0.0)
	shade.texture = tex
	_layer.add_child(shade)
	_fade_rect = ColorRect.new()
	_fade_rect.name = "SiegeFade"
	_fade_rect.color = Color(0.02, 0.02, 0.025, 1.0)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_fade_rect)
	if auto_run:
		new_round.call_deferred()


## Builds a fresh, varied house and starts the siege (behind the black fade).
func new_round() -> void:
	if not is_inside_tree():
		return
	var t0 := Time.get_ticks_usec()
	if _round_root != null:
		_round_root.queue_free()
		remove_child(_round_root)
	_targets.clear()
	_round_root = Node3D.new()
	_round_root.name = "Round"
	add_child(_round_root)
	round += 1
	round_t = 0.0
	spawned = 0
	broken_share = 0.0
	lighting = VoxelLighting.new()
	lighting.name = "Lighting"
	_round_root.add_child(lighting)
	world = HouseWorld.new()
	world.name = "World"
	world.setup(lighting)
	_round_root.add_child(world)
	world.build_new()
	lighting.night_materials.append(VoxelRig.look_material(true))
	lighting.night_materials.append(VoxelRig.look_material(false))
	roster = Roster.new()
	roster.name = "Enemies"
	roster.setup(world, null, seed + round)
	roster.level = ["easy", "normal", "hard"][rng.randi_range(0, 2)]
	roster.invasion = rng.randi_range(1, 4)
	_round_root.add_child(roster)
	roster.wall_swing.connect(_on_wall_swing)
	roster.player_swing.connect(_on_reached)
	_mute_sfx(true)                   # the pre-damage is not heard; unmuted as the view fades in
	_vary()
	world.chunks.flush(100000.0)
	if world.yard != null:
		world.yard.update_roof(_centre, 1.0, true)     # roof off: the destruction shows inside too
	_orbit = rng.randf() * TAU
	_orbit_dir = -1.0 if rng.randf() < 0.5 else 1.0
	_dist = rng.randf_range(19.0, 24.0)
	_height = rng.randf_range(12.0, 16.0)
	_place_camera(0.0)
	_spawn_t = 0.6
	for i in FIRST_WAVE:
		_spawn()
	last_build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	_phase = "in"
	_fade_t = 0.0
	round_started.emit(round)


## Light but real variation through the world's own API.
func _vary() -> void:
	variation = {"walls": 0, "doors": 0, "barricades": 0, "plated": 0, "blasts": 0, "shots": 0}
	var night: float = TIMES[rng.randi_range(0, TIMES.size() - 1)]
	lighting.set_amount(night)
	variation["night"] = night
	# wall runs in the yard (wood or stone), one with a door
	var runs := RUNS.duplicate()
	runs.shuffle()
	for r in runs.slice(0, rng.randi_range(0, 3)):
		var a: int = r[2] + rng.randi_range(0, maxi(0, (r[3] - r[2]) / 2))
		var b: int = mini(a + rng.randi_range(3, 7), r[3])
		var segs := []
		for k in range(a, b):
			segs.append(Vector3i(r[0], r[1], k))
		if segs.is_empty():
			continue
		world.build_walls(segs, "stone" if rng.randf() < 0.3 else "wood")
		variation["walls"] += segs.size()
		if segs.size() >= 3 and rng.randf() < 0.7:
			var s: Vector3i = segs[rng.randi_range(1, segs.size() - 2)]
			world.cut_opening(s)
			world.place_object("door", HouseWorld.seg_center(s), world.seg_rot(s), true, "iron" if rng.randf() < 0.3 else "wood")
			variation["doors"] += 1
	# boarded windows and iron plating on the outer walls
	for o in HousePlan.OPENINGS:
		if o["kind"] != "window" or rng.randf() > 0.45:
			continue
		for k in range(int(o["from"]), int(o["to"])):
			var s := _outer_seg(str(o["wall"]), k)
			if s.x < 0:
				continue
			world.place_object("barricade", HouseWorld.seg_center(s), world.seg_rot(s), true, "iron" if rng.randf() < 0.25 else "wood")
			variation["barricades"] += 1
	for i in rng.randi_range(0, 3):
		var s := _random_outer_seg()
		if s.x >= 0 and world.sections.has(s):
			world.upgrade_section(s)
			variation["plated"] += 1
	# pre-damage: a blast or two at the walls, a volley of shots
	for i in rng.randi_range(0, 2):
		var s := _random_outer_seg()
		if s.x < 0:
			continue
		var c := HouseWorld.seg_center(s)
		world.explode(Vector3(c.x, 1.0, c.y), rng.randf_range(0.9, 1.6), rng.randf_range(0.6, 1.0))
		variation["blasts"] += 1
	var shots := rng.randi_range(0, 16)
	for i in shots:
		var a := rng.randf() * TAU
		var from := _centre + Vector3(cos(a), 0.0, sin(a)) * 11.0 + Vector3(0, 1.2, 0)
		var aim := _centre + Vector3(rng.randf_range(-5, 5), rng.randf_range(0.3, 2.0), rng.randf_range(-3, 3))
		world.shoot(from, (aim - from).normalized(), [])
	variation["shots"] = shots


## A 1 m segment of an outer wall ("north", "south", "east", "west") at `k` m along it.
func _outer_seg(wall: String, k: int) -> Vector3i:
	var fp: Rect2 = HousePlan.FOOTPRINT
	match wall:
		"north":
			return Vector3i(0, int(fp.position.y), k)
		"south":
			return Vector3i(0, int(fp.end.y), k)
		"west":
			return Vector3i(1, int(fp.position.x), k)
		"east":
			return Vector3i(1, int(fp.end.x), k)
	return Vector3i(-1, 0, 0)


func _random_outer_seg() -> Vector3i:
	var fp: Rect2 = HousePlan.FOOTPRINT
	var wall: String = ["north", "south", "east", "west"][rng.randi_range(0, 3)]
	var n := int(fp.size.x) if wall in ["north", "south"] else int(fp.size.y)
	return _outer_seg(wall, rng.randi_range(0, maxi(n - 1, 0)))


# --- the horde ---------------------------------------------------------------------------

func _spawn() -> void:
	if roster == null or roster.living() >= MAX_ENEMIES:
		return
	var pts: Array = Director.fog_points()
	if pts.is_empty():
		return
	var p: Vector2 = pts[rng.randi_range(0, pts.size() - 1)] + Vector2(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5))
	var t := Node3D.new()
	t.name = "Target"
	_round_root.add_child(t)
	_move_target(t, true)
	roster.player = t
	var e = roster.spawn_type(_pick_kind(), p, {})
	roster.player = null
	if e == null:
		t.queue_free()
		return
	_targets[e.get_instance_id()] = {"node": t, "t": rng.randf_range(RETARGET_SECONDS.x, RETARGET_SECONDS.y), "enemy": e}
	spawned += 1


func _pick_kind() -> String:
	var total := 0.0
	for k in KINDS:
		total += float(k[1])
	var x := rng.randf() * total
	for k in KINDS:
		x -= float(k[1])
		if x < 0.0:
			return k[0]
	return "psycho"


## Moves a stand-in target: into a random room, or (once inside) out past the
## far wall, so the enemies keep breaking walls and doors.
func _move_target(t: Node3D, inside: bool) -> void:
	var p: Vector2
	if inside or rng.randf() < 0.6:
		var room: Dictionary = HousePlan.ROOMS[rng.randi_range(0, HousePlan.ROOMS.size() - 1)]
		var r: Rect2 = room["rect"]
		p = r.get_center() + Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3)) * r.size
	else:
		var a := rng.randf() * TAU
		var fp: Rect2 = HousePlan.FOOTPRINT
		p = fp.get_center() + Vector2(cos(a) * (fp.size.x * 0.5 + 1.5), sin(a) * (fp.size.y * 0.5 + 1.5))
	t.position = Vector3(p.x, 0.0, p.y)


func _on_wall_swing(e: VoxelEnemy, target: Vector2) -> void:
	if world != null and is_instance_valid(e):
		world.enemy_strike(e.global_position, target, STRIKE)


## An enemy reached its stand-in target: send it somewhere else.
func _on_reached(e: VoxelEnemy) -> void:
	var rec = _targets.get(e.get_instance_id())
	if rec != null:
		_move_target(rec["node"], false)
		rec["t"] = rng.randf_range(RETARGET_SECONDS.x, RETARGET_SECONDS.y)


# --- frame -------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if world == null:
		return
	_place_camera(delta)
	match _phase:
		"in":
			_fade_t += delta
			_fade_rect.color.a = 1.0 - clampf(_fade_t / FADE, 0.0, 1.0)
			if _fade_t >= FADE:
				_phase = "run"
				_mute_sfx(false)
		"out":
			_fade_t += delta
			_fade_rect.color.a = clampf(_fade_t / FADE, 0.0, 1.0)
			if _fade_t >= FADE:
				_phase = ""
				if auto_run:
					new_round()
			return
	round_t += delta
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = rng.randf_range(SPAWN_GAP.x, SPAWN_GAP.y)
		_spawn()
	for id in _targets.keys():
		var rec: Dictionary = _targets[id]
		if not is_instance_valid(rec["enemy"]):
			if is_instance_valid(rec["node"]):
				(rec["node"] as Node).queue_free()
			_targets.erase(id)
			continue
		rec["t"] -= delta
		if rec["t"] <= 0.0:
			rec["t"] = rng.randf_range(RETARGET_SECONDS.x, RETARGET_SECONDS.y)
			_move_target(rec["node"], false)
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = CHECK_EVERY
		broken_share = destroyed_share()
		if _phase == "run" and (broken_share >= BROKEN_SHARE or round_t >= ROUND_SECONDS):
			_phase = "out"
			_fade_t = 0.0


func _exit_tree() -> void:
	_mute_sfx(false)


func _mute_sfx(on: bool) -> void:
	var bus := AudioServer.get_bus_index("SFX")
	if bus < 0 or on == _muted:
		return
	if on:
		_was_muted = AudioServer.is_bus_mute(bus)
		AudioServer.set_bus_mute(bus, true)
	else:
		AudioServer.set_bus_mute(bus, _was_muted)
	_muted = on


## Share of the wall sections that are broken (integrity under BROKEN_BELOW).
func destroyed_share() -> float:
	if world == null or world.sections.is_empty():
		return 0.0
	var n := 0
	for s in world.sections:
		if world.section_integrity(s) < BROKEN_BELOW:
			n += 1
	return float(n) / float(world.sections.size())


func _place_camera(delta: float) -> void:
	_orbit += ORBIT_SPEED * _orbit_dir * delta
	var bob := sin(round_t * 0.12) * 0.8
	camera.position = _centre + Vector3(sin(_orbit) * _dist, _height + bob, cos(_orbit) * _dist)
	camera.look_at(_centre + Vector3(0, 0.8, 0), Vector3.UP)


## A line for debugging and tests.
func info() -> String:
	return "round %d · %.0f s · %d enemies (%d spawned) · %d %% broken · built in %.0f ms · %s" % [
		round, round_t, roster.living() if roster != null else 0, spawned, int(round(broken_share * 100.0)), last_build_ms, variation]
