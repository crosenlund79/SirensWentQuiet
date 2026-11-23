extends Node3D
## Version A - True 3D Voxels: scene root.
##
## Builds the HousePlan as a 0.1 m voxel volume, renders it in chunks, and runs
## the shared scenario (player, psychos, handgun, day/night). Shots and enemy
## swings carve the voxel grid; collision and GridNav update in the same frame.
## Implements the smoke-test debug API (tests/test_versions_smoke.gd).

const SURFACE_SHADER := preload("res://src/voxel/shaders/voxel_surface.gdshader")
const GLASS_SHADER := preload("res://src/voxel/shaders/voxel_glass.gdshader")

## Bullet carve radii (m) by what was hit.
const WALL_CARVE := 0.23
## Bullet carves are stretched along the shot (they punch into the wall).
const PENETRATION := 1.5
const FLOOR_CARVE := 0.13
const FURNITURE_CARVE := 0.17
## Enemy wall bite.
const BITE_RADIUS := 0.2
const CUT_RADIUS := 2.1

var hud: DemoHud
var grid: VoxelGrid
var world: VoxelWorld
var nav: GridNav
var lighting: VoxelLighting
var camera: VoxelCamera
var player: VoxelPlayer
var fx: VoxelFx
var yard: VoxelYard
var spawner := EnemySpawner.new()
var enemies: Array[VoxelEnemy] = []
var surface_mat: ShaderMaterial
var glass_mat: ShaderMaterial
var cut_materials: Array[ShaderMaterial] = []

var _bullet_skip := PackedByteArray()
var _fire_cooldown := 0.0
var _rng := RandomNumberGenerator.new()
var _night_ready := false
var _shot_count := 0
var _scenario := ""
var _t := 0.0
var _cut_origin := Vector3(0, -100, 0)
var _cut_dir := Vector3.UP
var _cut_on := true
var _build_ms := 0.0


func _ready() -> void:
	_rng.seed = 1979
	hud = DemoHud.new()
	hud.title = "A  ·  True 3D Voxels"
	hud.subtitle = "0.1 m voxels · layered walls · every shot rebuilds the mesh"
	add_child(hud)

	lighting = VoxelLighting.new()
	add_child(lighting)
	surface_mat = _surface_material(VoxelHouse.ORIGIN, VoxelHouse.VS)
	glass_mat = ShaderMaterial.new()
	glass_mat.shader = GLASS_SHADER
	cut_materials.append(glass_mat)
	lighting.night_materials.append(glass_mat)

	var t0 := Time.get_ticks_usec()
	grid = VoxelHouse.create_grid()
	VoxelHouse.build(grid)
	world = VoxelWorld.new()
	world.name = "VoxelWorld"
	world.setup(grid, surface_mat, glass_mat)
	add_child(world)
	world.build_all()
	_build_ms = (Time.get_ticks_usec() - t0) / 1000.0

	nav = GridNav.new()
	HousePlan.rasterize_into(nav)
	_furniture_collision()

	yard = VoxelYard.new()
	yard.name = "Yard"
	yard.demo = self
	add_child(yard)

	fx = VoxelFx.new()
	fx.grid = grid
	add_child(fx)

	player = VoxelPlayer.new()
	player.name = "Player"
	add_child(player)
	player.global_position = Vector3(HousePlan.PLAYER_START.x, 0, HousePlan.PLAYER_START.y)
	player.aim_point = player.global_position + Vector3(0, 1, -3)
	lighting.night_materials.append(VoxelRig.shared_material())

	camera = VoxelCamera.new()
	camera.target = player
	add_child(camera)
	camera.make_current()
	camera.snap()

	_bullet_skip.resize(256)
	for i in 256:
		_bullet_skip[i] = 1 if (VoxelMat.FLAGS[i] & VoxelMat.F_PASS) != 0 else 0

	hud.night_changed.connect(_on_night_changed)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scenario="):
			_scenario = a.trim_prefix("--scenario=")
	if _scenario != "":
		VoxelScenarios.setup(self, _scenario)


func _surface_material(origin: Vector3, vs: float, model_space := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SURFACE_SHADER
	m.set_shader_parameter("grid_origin", origin)
	m.set_shader_parameter("voxel_size", vs)
	m.set_shader_parameter("model_space", 1.0 if model_space else 0.0)
	cut_materials.append(m)
	lighting.night_materials.append(m)
	return m


func _on_night_changed(night: bool) -> void:
	lighting.set_night(night, not _night_ready)
	_night_ready = true


func _furniture_collision() -> void:
	for f in HousePlan.FURNITURE:
		if not f["blocks"]:
			continue
		add_child(_box_body(f["rect"], maxf(f["height"], 0.4), 1 << 4))


## Static box over a plan rect. Furniture uses "low_obstacles" (layer 5): it
## blocks bodies; bullets interact with the furniture voxels instead.
func _box_body(rect: Rect2, height: float, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(rect.size.x, height, rect.size.y)
	cs.shape = box
	body.add_child(cs)
	body.position = Vector3(rect.get_center().x, height * 0.5, rect.get_center().y)
	return body


# --- frame -------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("zoom_in"):
		camera.zoom(-1.0)
	elif event.is_action_pressed("zoom_out"):
		camera.zoom(1.0)


func _process(delta: float) -> void:
	_t += delta
	player.set_night(lighting.night_amount)
	_update_cut()
	if yard != null:
		yard.update_roof(player.global_position, delta)
	var alive := debug_living_enemies()
	hud.stats_text = "voxels %s · chunks %d · faces %s\nchunk rebuild %.1f ms (worst %.1f) · debris %d · enemies %d" % [
		_thousands(grid.solid_count), world.chunk_count(), _thousands(world.face_count),
		world.last_rebuild_ms, world.worst_rebuild_ms, fx.debris_count, alive]
	if _scenario != "":
		VoxelScenarios.process(self, _scenario, delta)


func _physics_process(delta: float) -> void:
	_update_aim()
	_fire_cooldown -= delta
	if Input.is_action_pressed("fire") and _fire_cooldown <= 0.0 and player.input_enabled:
		_fire_cooldown = Tuning.FIRE_INTERVAL
		fire(player.aim_point)
	var spawn = spawner.tick(delta, debug_living_enemies(), player.plan_pos())
	if spawn != null:
		spawn_enemy(spawn)
	for i in range(enemies.size() - 1, -1, -1):
		if not is_instance_valid(enemies[i]):
			enemies.remove_at(i)


# --- cutaway and aiming ------------------------------------------------------------------

func _cut_radius() -> float:
	return CUT_RADIUS + (camera.distance - 20.0) * 0.03


func _update_cut() -> void:
	_cut_origin = player.global_position + Vector3(0, 1.0, 0)
	_cut_dir = (camera.global_position - _cut_origin).normalized()
	for m in cut_materials:
		m.set_shader_parameter("cut_origin", _cut_origin if _cut_on else Vector3(0, -100, 0))
		m.set_shader_parameter("cut_dir", _cut_dir)
		m.set_shader_parameter("cut_radius", _cut_radius())
		m.set_shader_parameter("cut_floor", 0.45)


## Same test as the shader (without its ragged dither band): is the voxel
## cell currently cut away for the camera?
func is_cut(c: Vector3i) -> bool:
	if not _cut_on:
		return false
	var p := grid.center(c)
	var rel := p - _cut_origin
	var t := rel.dot(_cut_dir)
	if t <= 0.45 or p.y <= 0.45:
		return false
	return (rel - _cut_dir * t).length() < _cut_radius() - 0.22


func _update_aim() -> void:
	if not is_inside_tree() or camera == null:
		return
	var mp := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	player.aim_point = aim_ray(from, dir)


## First visible thing under the cursor ray: voxels (ignoring cut-away and
## shot-through ones), enemies and props, or the ground plane.
func aim_ray(from: Vector3, dir: Vector3) -> Vector3:
	var best := 200.0
	var vh := grid.raycast(from, dir, best, _bullet_skip, is_cut)
	if not vh.is_empty():
		best = vh["dist"]
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * best, 1 | 8)
	var ph := get_world_3d().direct_space_state.intersect_ray(q)
	if not ph.is_empty():
		best = from.distance_to(ph["position"])
	if dir.y < -0.001:
		var tg := -from.y / dir.y
		if tg < best:
			best = tg
	return from + dir * best


# --- shooting ----------------------------------------------------------------------------

func fire(target: Vector3) -> void:
	_shot_count += 1
	var origin := Vector3(player.global_position.x, Tuning.MUZZLE_HEIGHT, player.global_position.z)
	var dir := target - origin
	if Vector2(dir.x, dir.z).length() < 0.3:
		dir = -player.rig.global_transform.basis.z
		dir.y = -0.3
	dir = dir.normalized()
	var best := Tuning.SHOT_RANGE
	var kind := ""
	var vh := grid.raycast(origin, dir, best, _bullet_skip)
	if not vh.is_empty():
		best = vh["dist"]
		kind = "voxel"
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * best, 1 | 8)
	q.exclude = [player.get_rid()]
	var ph := get_world_3d().direct_space_state.intersect_ray(q)
	if not ph.is_empty():
		best = origin.distance_to(ph["position"])
		kind = "body"
	if kind == "" and dir.y < -0.001:
		var tg := -origin.y / dir.y
		if tg < best:
			best = tg
			kind = "ground"
	var hit := origin + dir * best
	match kind:
		"voxel":
			_hit_voxels(vh, dir)
		"body":
			var col = ph["collider"]
			if col is VoxelEnemy:
				(col as VoxelEnemy).take_hit(dir)
				fx.flesh_hit(hit, -dir, VoxelArt.to_color(0x5a5550))
			else:
				var imp: int = col.get_meta("impact", VoxelMat.Impact.DUST) if col != null else VoxelMat.Impact.DUST
				fx.impact(imp, hit, ph["normal"], dir, {})
		"ground":
			fx.ground_hit(hit, dir)
	var muzzle := player.rig.muzzle_global()
	fx.tracer(muzzle, hit)
	fx.muzzle(muzzle)
	fx.casing(muzzle - dir * 0.15, player.rig.global_transform.basis.x)
	player.on_fired()


func _hit_voxels(vh: Dictionary, dir: Vector3) -> void:
	var m: int = vh["mat"]
	var pos: Vector3 = vh["pos"]
	var c: Vector3i = vh["cell"]
	var ch: Dictionary
	if m == VoxelMat.GLASS:
		ch = VoxelCarver.shatter_glass(grid, grid.idx(c.x, c.y, c.z))
	else:
		var r := WALL_CARVE
		if c.y <= VoxelHouse.FLOOR_ROW:
			r = FLOOR_CARVE
		elif not VoxelMat.is_struct(m):
			r = FURNITURE_CARVE
		ch = VoxelCarver.carve_sphere(grid, pos + dir * 0.07, r, _shot_count * 7919 + c.x, dir, PENETRATION if r == WALL_CARVE else 1.0)
	_apply(ch)
	fx.impact(VoxelMat.IMPACT[m], pos, vh["normal"], dir, ch)


func _apply(ch: Dictionary) -> void:
	world.apply_change(ch)
	VoxelCarver.sync_nav(nav, grid, ch["lo"], ch["hi"])


# --- enemies -----------------------------------------------------------------------------

func spawn_enemy(p: Vector2) -> VoxelEnemy:
	var e := VoxelEnemy.new()
	e.setup(nav, player, 1 + (enemies.size() + _rng.randi() % 4) % 4)
	add_child(e)
	e.global_position = Vector3(p.x, 0, p.y)
	e.rig.rotation.y = _rng.randf() * TAU
	e.wall_swing.connect(_on_wall_swing)
	e.player_swing.connect(_on_player_swing)
	enemies.append(e)
	return e


func _on_wall_swing(e: VoxelEnemy, target: Vector2) -> void:
	var h := _rng.randf_range(0.2, 1.5)
	var from := Vector3(e.global_position.x, h, e.global_position.z)
	var to := Vector3(target.x + _rng.randf_range(-0.18, 0.18), h, target.y + _rng.randf_range(-0.18, 0.18))
	var dir := (to - from).normalized()
	var vh := grid.raycast(from, dir, from.distance_to(to) + 0.4, _bullet_skip)
	var center := to
	var m := VoxelMat.DRYWALL
	var n := -dir
	if not vh.is_empty():
		center = (vh["pos"] as Vector3) + dir * 0.1
		m = vh["mat"]
		n = vh["normal"]
	var ch := VoxelCarver.carve_sphere(grid, center, BITE_RADIUS, _rng.randi())
	if (ch["cells"] as PackedInt32Array).is_empty():
		return
	_apply(ch)
	fx.impact(VoxelMat.IMPACT[m], center - dir * 0.1, n, dir, ch)
	if e.global_position.distance_to(player.global_position) < 6.0:
		camera.nudge(0.35)


func _on_player_swing(_e: VoxelEnemy) -> void:
	camera.nudge(1.0)


# --- debug API (tests/test_versions_smoke.gd) --------------------------------------------

func debug_hud() -> DemoHud:
	return hud


func debug_player_pos() -> Vector2:
	return player.plan_pos()


func debug_teleport_player(p: Vector2) -> void:
	player.global_position = Vector3(p.x, 0, p.y)
	player.velocity = Vector3.ZERO


func debug_fire_at(target: Vector2, height: float) -> void:
	fire(Vector3(target.x, height, target.y))


func debug_set_spawning(on: bool) -> void:
	spawner.enabled = on


func debug_spawn_enemy(p: Vector2) -> Node:
	return spawn_enemy(p)


func debug_living_enemies() -> int:
	var n := 0
	for e in enemies:
		if is_instance_valid(e) and e.alive:
			n += 1
	return n


func debug_enemy_positions() -> PackedVector2Array:
	var out := PackedVector2Array()
	for e in enemies:
		if is_instance_valid(e) and e.alive:
			out.append(e.plan_pos())
	return out


func debug_nav() -> GridNav:
	return nav


func debug_blocked_at(p: Vector2) -> bool:
	var space := get_world_3d().direct_space_state
	var y := 1.0
	for seg in [[Vector3(p.x, y, p.y - 0.25), Vector3(p.x, y, p.y + 0.25)], [Vector3(p.x - 0.25, y, p.y), Vector3(p.x + 0.25, y, p.y)]]:
		var q := PhysicsRayQueryParameters3D.create(seg[0], seg[1], 1 | 2 | 16)
		if not space.intersect_ray(q).is_empty():
			return true
		q = PhysicsRayQueryParameters3D.create(seg[1], seg[0], 1 | 2 | 16)
		if not space.intersect_ray(q).is_empty():
			return true
	return false


func debug_is_night() -> bool:
	return lighting.night


static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
