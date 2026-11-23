extends Node3D
## Version B - Modular 3D Construction.
##
## A modern single-storey house assembled at runtime from a small kit of
## reusable 1 m pieces (wall, window, door, post, floor tile, roof panel,
## furniture) on the HousePlan grid. Wall modules have four damage states;
## destroyed modules drop their collision and open their navigation cells in
## the same frame. See docs/experiment-001/modular.md.
##
## Extra command-line user args (after --), for screenshots:
##   --scenario=overview|exterior|damage|breach|enemies|shooting|kit

const ENEMY_LAYER := 8
const AIM_MASK := 1 | 2 | 8 | 16
const SHOT_MASK := 1 | 2 | 8

var hud: DemoHud
var nav: GridNav
var house: ModHouse
var lighting: ModLighting
var player: ModPlayer
var cam: ModCameraRig
var fx: ModFx
var spawner := EnemySpawner.new()
var enemies: Array[ModEnemy] = []
var aim_point := Vector3.ZERO
var scenario := ""

var _enemy_root: Node3D
var _cooldown := 0.0
var _night := false
var _variant := 0
var _stats_t := 0.0
var _shot_dir := Vector3.FORWARD
var _scenario_t := 0.0
var _scenario_fire := false
var _scenario_aim := Vector3.ZERO
var _build_ms := 0
var _quiet_changes := false
var _cam_override := Vector3.INF


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scenario="):
			scenario = a.trim_prefix("--scenario=")
	var t0 := Time.get_ticks_msec()
	lighting = ModLighting.new()
	lighting.name = "Lighting"
	add_child(lighting)
	nav = GridNav.new()
	HousePlan.rasterize_into(nav)
	house = ModHouse.new()
	house.name = "House"
	add_child(house)
	house.build(nav)
	house.module_changed.connect(_on_module_changed)
	lighting.lamps.append_array(house.lamp_meshes)
	fx = ModFx.new()
	fx.name = "Fx"
	add_child(fx)
	_enemy_root = Node3D.new()
	_enemy_root.name = "Enemies"
	add_child(_enemy_root)
	player = ModPlayer.new()
	player.name = "Player"
	add_child(player)
	player.global_position = Vector3(HousePlan.PLAYER_START.x, 0, HousePlan.PLAYER_START.y)
	cam = ModCameraRig.new()
	cam.name = "CameraRig"
	add_child(cam)
	cam.snap(player.global_position + Vector3(0, 1, 0))
	_build_ms = Time.get_ticks_msec() - t0

	hud = DemoHud.new()
	hud.title = "B - Modular 3D"
	hud.subtitle = "A reusable kit of 1 m pieces: walls, windows, doors, posts, floors, roof, furniture"
	add_child(hud)
	hud.night_changed.connect(_on_night_changed)
	_on_night_changed(hud.is_night)
	lighting.set_night(hud.is_night, true)
	if scenario != "":
		_setup_scenario()


func _on_night_changed(night: bool) -> void:
	_night = night
	lighting.set_night(night)
	player.set_night(night)
	for e in enemies:
		if is_instance_valid(e):
			e.figure.set_param("rim", 0.25 if night else 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("zoom_in"):
		cam.zoom(-0.1)
	elif event.is_action_pressed("zoom_out"):
		cam.zoom(0.1)


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	player.move_with(input, delta)
	if scenario == "" or _scenario_aim == Vector3.ZERO:
		aim_point = _compute_aim()
	else:
		aim_point = _scenario_aim
	var flat := Vector2(aim_point.x, aim_point.z) - player.plan_pos()
	player.face(flat, delta)
	player.aim_light_at(aim_point)
	_cooldown -= delta
	if (Input.is_action_pressed("fire") or _scenario_fire) and _cooldown <= 0.0:
		_cooldown = Tuning.FIRE_INTERVAL
		_fire_at(aim_point)
	var pp := player.plan_pos()
	var alive := 0
	for e in enemies:
		e.player_pos = pp
		if e.alive:
			alive += 1
	var sp: Variant = spawner.tick(delta, alive, pp)
	if sp != null:
		spawn_enemy(sp)


func _process(delta: float) -> void:
	cam.follow(player.global_position + Vector3(0, 1, 0) if _cam_override == Vector3.INF else _cam_override, delta)
	house.update_view(player.plan_pos(), delta)
	if scenario != "":
		_scenario_t += delta
		_scenario_tick()
	_stats_t -= delta
	if _stats_t <= 0.0:
		_stats_t = 0.25
		var d := house.damaged_counts()
		hud.stats_text = "%d kit modules: %d wall, %d post, %d floor, %d furniture\nwalls hit %d / heavy %d / destroyed %d\ndebris %d chips, %d chunks   build %d ms" % [
			house.module_count(), house.walls.size(), house.posts.size(), house.floor_tiles, house.furniture_pieces,
			d.x, d.y, d.z, fx.active_chips, fx.chunk_count(), _build_ms]


# --- aiming and shooting ---------------------------------------------------------------------------

## Camera ray through the cursor against visible geometry and enemies;
## pieces the cutaway currently hides are skipped.
func _compute_aim() -> Vector3:
	var mouse := get_viewport().get_mouse_position()
	var from := cam.camera.project_ray_origin(mouse)
	var dir := cam.camera.project_ray_normal(mouse)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 200.0, AIM_MASK)
	var ex: Array[RID] = [player.get_rid(), house.yard_edge_rid()]
	q.exclude = ex
	for i in 6:
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		if house.is_hidden(hit["collider"], hit["position"]):
			# aim at the visible cut top if the ray reaches it, else look past
			var top: Variant = house.cut_top_hit(hit["collider"], from, dir)
			if top != null:
				return top
			ex.append(hit["rid"])
			q.exclude = ex
			continue
		return hit["position"]
	if absf(dir.y) > 0.001:
		return from + dir * ((1.0 - from.y) / dir.y)
	return player.global_position + Vector3(player.aim_dir.x, 1, player.aim_dir.y)


func _fire_at(target: Vector3) -> void:
	var origin := player.global_position + Vector3(0, Tuning.MUZZLE_HEIGHT, 0)
	var d := target - origin
	if Vector2(d.x, d.z).length() < 0.45:
		d = Vector3(player.aim_dir.x, 0, player.aim_dir.y)
	var dir := d.normalized()
	_shot_dir = dir
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * Tuning.SHOT_RANGE, SHOT_MASK)
	q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	var end := origin + dir * Tuning.SHOT_RANGE
	if not hit.is_empty():
		end = hit["position"]
		_resolve_hit(hit, dir)
	player.fired()
	fx.tracer(player.muzzle_position(), end)
	cam.nudge(0.12)


func _resolve_hit(hit: Dictionary, dir: Vector3) -> void:
	var c: Object = hit["collider"]
	var p: Vector3 = hit["position"]
	var n: Vector3 = hit["normal"]
	if c is ModEnemy:
		(c as ModEnemy).hit(dir)
		fx.impact("enemy", p, -dir)
	elif c is ModWall:
		var m := c as ModWall
		var local := m.to_local(p - n * 0.01)
		var mat := m.take_hit(local, 1, true)
		if mat == "glass_shatter":
			_glass_burst(m)
		else:
			fx.impact(mat, p, n)
	elif c is ModPost:
		fx.impact((c as ModPost).material_at((c as ModPost).to_local(p)), p, n)
	elif c is Node:
		fx.impact(str((c as Node).get_meta("material", "wood")), p, n)


func _glass_burst(m: ModWall) -> void:
	var b := m.global_transform.basis
	var center := m.to_global(Vector3(m.length * 0.5, (m.sill + m.head) * 0.5, 0))
	fx.shatter(center, b.x.normalized(), m.length - 0.1, m.head - m.sill, b.z.normalized())


func _on_module_changed(m: ModWall, old_state: int) -> void:
	if m.state == ModWall.State.DAMAGED or _quiet_changes:
		return
	fx.wall_burst(m, m.state == ModWall.State.DESTROYED, _shot_dir)
	cam.nudge(0.5 if m.state == ModWall.State.DESTROYED else 0.25)


# --- enemies -------------------------------------------------------------------------------------------

func spawn_enemy(p: Vector2) -> ModEnemy:
	var e := ModEnemy.new()
	e.setup(nav, _variant)
	_variant += 1
	e.name = "Enemy%d" % _variant
	_enemy_root.add_child(e)
	e.global_position = Vector3(p.x, 0, p.y)
	e.player_pos = player.plan_pos()
	e.swung.connect(_on_enemy_swung)
	e.tree_exiting.connect(enemies.erase.bind(e))
	enemies.append(e)
	if _night:
		e.figure.set_param("rim", 0.25)
	return e


func _on_enemy_swung(e: ModEnemy, kind: String, target: Vector2) -> void:
	if kind == "player":
		cam.nudge(0.35)
		return
	var m := house.wall_near(target, 0.7)
	if m == null:
		return
	var ep := e.plan_pos()
	var hp := Vector3(target.x, randf_range(0.3, 1.5), target.y)
	var local := m.to_local(hp)
	local.x = clampf(local.x, 0.08, m.length - 0.08)
	var side := m.to_local(Vector3(ep.x, 1.0, ep.y)).z
	local.z = signf(side) * m.thickness * 0.5
	_shot_dir = (m.to_global(local) - Vector3(ep.x, local.y, ep.y)).normalized()
	var mat := m.take_hit(local, Tuning.ENEMY_WALL_DAMAGE, false)
	var wp := m.to_global(local)
	var nrm := (m.global_transform.basis.z * signf(side)).normalized()
	if mat == "glass_shatter":
		_glass_burst(m)
	else:
		fx.impact(mat, wp, nrm)


# --- debug / smoke-test contract (plan meters) ----------------------------------------------------------

func debug_hud() -> DemoHud:
	return hud


func debug_player_pos() -> Vector2:
	return player.plan_pos()


func debug_teleport_player(p: Vector2) -> void:
	player.global_position = Vector3(p.x, 0, p.y)
	player.velocity = Vector3.ZERO
	cam.snap(player.global_position + Vector3(0, 1, 0))


func debug_fire_at(target: Vector2, height: float) -> void:
	var t := Vector3(target.x, height, target.y)
	player.face(target - player.plan_pos(), 1.0)
	_fire_at(t)


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
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.12
	q.shape = s
	q.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, 0.9, p.y))
	q.collision_mask = 1 | 2 | 16
	return not space.intersect_shape(q, 1).is_empty()


func debug_is_night() -> bool:
	return _night


# --- screenshot scenarios ---------------------------------------------------------------------------------

func _setup_scenario() -> void:
	spawner.enabled = false
	house.instant = true
	match scenario:
		"overview":
			debug_teleport_player(Vector2(6.2, 6.9))
			cam.set_distance(24.0)
			_scenario_aim = Vector3(9.0, 1.0, 2.0)
			for p in [Vector2(-3.5, 3.0), Vector2(17.5, 6.5), Vector2(4.0, 12.0)]:
				spawn_enemy(p)
		"exterior":
			house.roof_mode = "shown"
			debug_teleport_player(Vector2(4.6, 11.6))
			cam.set_distance(24.0)
			_cam_override = Vector3(7.5, 1.0, 6.5)
			cam.snap(_cam_override)
			_scenario_aim = Vector3(4.6, 1.0, 9.0)
			for p in [Vector2(-2.5, 11.0), Vector2(13.0, 12.6)]:
				spawn_enemy(p)
		"damage":
			house.roof_mode = "hidden"
			debug_teleport_player(Vector2(10.2, 11.2))
			cam.set_distance(11.0)
			_scenario_aim = Vector3(10.0, 1.0, 9.0)
			_quiet_changes = true
			_damage_row()
			_quiet_changes = false
		"damage_inside":
			debug_teleport_player(Vector2(10.4, 6.4))
			cam.set_distance(12.5)
			house.cut_enabled = false
			_scenario_aim = Vector3(10.0, 1.0, 9.0)
			_damage_row()
		"breach":
			debug_teleport_player(Vector2(7.6, 6.7))
			cam.set_distance(13.0)
			_scenario_aim = Vector3(8.5, 0.9, 9.0)
			_quiet_changes = true
			_set_wall_state(Vector2(9.5, 9.0), ModWall.State.HEAVY)
			_set_wall_state(Vector2(7.5, 9.0), ModWall.State.DAMAGED)
			_quiet_changes = false
			# the killing shot: the module bursts outward, debris in the air
			debug_fire_at(Vector2(8.5, 9.0), 0.9)
			_shot_dir = Vector3(0.1, 0.25, 1.0).normalized()
			var m := house.wall_near(Vector2(8.5, 9.0), 0.1)
			m.set_state(ModWall.State.DESTROYED)
			_prewarm_fx(0.3)
		"enemies":
			debug_teleport_player(Vector2(7.0, 6.9))
			cam.set_distance(14.0)
			_quiet_changes = true
			_set_wall_state(Vector2(8.5, 9.0), ModWall.State.DESTROYED)
			_set_wall_state(Vector2(11.5, 9.0), ModWall.State.HEAVY)
			_quiet_changes = false
			for p in [Vector2(8.45, 9.7), Vector2(9.7, 11.2), Vector2(5.4, 10.4), Vector2(11.0, 3.3), Vector2(3.1, 9.8)]:
				var e := spawn_enemy(p)
				e.figure.speed = 1.4
			_scenario_aim = Vector3(8.45, 1.1, 9.7)
			var dead: ModEnemy = enemies[4]
			for k in 3:
				dead.hit(Vector3(-0.3, 0, 1))
			dead._dead_t = 1.0
			enemies[2].figure.swing = 0.5
			enemies[1].hit(Vector3(0.2, 0, 1))
			for e in enemies:
				e.figure.animate(0.0)
		"kit":
			var sheet := ModKitSheet.new()
			sheet.name = "KitSheet"
			sheet.position = Vector3(-6.0, 0, -15.5)
			add_child(sheet)
			debug_teleport_player(Vector2(1.0, -5.5))
			house.roof_mode = "shown"
			cam.set_distance(15.5)
			_cam_override = Vector3(1.3, 1.0, -12.0)
			cam.snap(_cam_override)
			_scenario_aim = Vector3(1.0, 1.0, -12.0)
		"shooting":
			debug_teleport_player(Vector2(6.3, 7.0))
			cam.set_distance(12.0)
			_quiet_changes = true
			_set_wall_state(Vector2(8.5, 9.0), ModWall.State.DESTROYED)
			_quiet_changes = false
			var e := spawn_enemy(Vector2(8.5, 9.4))
			e.set_physics_process(false)
			e.figure.rotation.y = PI * 0.85
			e.figure.speed = 1.4
			spawn_enemy(Vector2(10.2, 11.5)).figure.speed = 1.4
			_scenario_aim = Vector3(8.5, 1.25, 9.4)
			e.hp = 99
			for k in 4:
				debug_fire_at(Vector2(8.5, 9.4), 1.25)
			_prewarm_fx(0.12)


func _prewarm_fx(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		fx._process(1.0 / 60.0)
		t += 1.0 / 60.0


func _scenario_tick() -> void:
	if scenario == "shooting":
		# keep a fresh muzzle flash and tracer in every (slow) rendered frame
		_scenario_fire = true
		_cooldown = 0.0


func _set_wall_state(p: Vector2, s: int) -> void:
	var m := house.wall_near(p, 0.2)
	if m != null:
		for k in 5:
			m.impacts.append(Vector2(randf_range(0.3, 0.7) * m.length, randf_range(0.6, 1.5)))
		if s >= ModWall.State.DAMAGED:
			for k in 6:
				var lp := Vector3(randf_range(0.1, 0.9) * m.length, randf_range(0.4, 2.0), m.thickness * 0.5 * (1.0 if randf() < 0.5 else -1.0))
				m.take_hit(lp, 0, true)
		m.set_state(s)


func _damage_row() -> void:
	_set_wall_state(Vector2(9.5, 9.0), ModWall.State.DAMAGED)
	_set_wall_state(Vector2(10.6, 9.0), ModWall.State.HEAVY)
	_set_wall_state(Vector2(11.5, 9.0), ModWall.State.DESTROYED)
