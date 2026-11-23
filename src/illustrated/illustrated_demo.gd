extends Node2D
## Version C - Illustrated top-down 2D (ink-and-wash, after The Witchening Tales).
##
## Scene root: builds the world from HousePlan, wires the player, enemies,
## gunfire, camera, day/night and the shared HUD, and implements the smoke-test
## debug API (plan meters). Extra user args for screenshots:
##   --scenario=overview|damage|breach|enemies|shooting
##   --slowmo-at=SECONDS   fire one shot then slow time to 3 % (catches the flash)

const Art := preload("res://src/illustrated/ill_art.gd")
const HouseView := preload("res://src/illustrated/house_view.gd")
const Walls := preload("res://src/illustrated/walls.gd")
const Fx := preload("res://src/illustrated/fx.gd")
const Lighting := preload("res://src/illustrated/lighting.gd")
const Player := preload("res://src/illustrated/player.gd")
const Enemy := preload("res://src/illustrated/enemy.gd")

const VIEW_DEFAULT_M := 22.0
const VIEW_MIN_M := 12.0
const VIEW_MAX_M := 34.0
const SHADOW_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float opacity = 0.5;
uniform float softness = 2.2;
uniform vec4 shade : source_color = vec4(0.03, 0.035, 0.07, 1.0);
void fragment() {
	float a = textureLod(screen_tex, SCREEN_UV, softness).a;
	COLOR = vec4(shade.rgb, a * opacity);
}
"""

var nav: GridNav
var hud: DemoHud
var house: HouseView
var walls: Walls
var fx: Fx
var lighting: Lighting
var player: Player
var camera: Camera2D
var spawner := EnemySpawner.new()
var enemies_node: Node2D
var shadow_group: CanvasGroup

var _cooldown := 0.0
var _view_m := VIEW_DEFAULT_M
var _view_target := VIEW_DEFAULT_M
var _shake := 0.0
var _scenario := ""
var _slowmo_at := -1.0
var _start_ms := 0
var _cam_focus = null          ## scenarios may pin the camera to a plan point
var _rng := RandomNumberGenerator.new()
var _variant_flip := false


func _ready() -> void:
	_start_ms = Time.get_ticks_msec()
	_rng.seed = 77
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scenario="):
			_scenario = a.trim_prefix("--scenario=")
		elif a.begins_with("--slowmo-at="):
			_slowmo_at = float(a.trim_prefix("--slowmo-at="))
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	nav = GridNav.new()
	HousePlan.rasterize_into(nav)

	shadow_group = CanvasGroup.new()
	shadow_group.name = "SoftShadows"
	shadow_group.z_index = Art.Z_SHADOWS
	shadow_group.z_as_relative = false
	shadow_group.use_mipmaps = true
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADOW_SHADER
	sm.shader = sh
	shadow_group.material = sm
	add_child(shadow_group)

	house = HouseView.new()
	house.name = "House"
	add_child(house)
	house.build(shadow_group)

	walls = Walls.new()
	walls.name = "Walls"
	walls.z_index = Art.Z_WALLS
	walls.z_as_relative = false
	add_child(walls)
	walls.build(nav, shadow_group)
	walls.section_destroyed.connect(_on_section_destroyed)

	fx = Fx.new()
	fx.name = "Fx"
	add_child(fx)
	fx.shake.connect(func(a: float): _shake = maxf(_shake, a))

	enemies_node = Node2D.new()
	enemies_node.name = "Enemies"
	add_child(enemies_node)

	player = Player.new()
	player.name = "Player"
	player.position = Art.w(HousePlan.PLAYER_START)
	add_child(player)

	lighting = Lighting.new()
	lighting.name = "Lighting"
	add_child(lighting)
	lighting.build(shadow_group, player)

	camera = Camera2D.new()
	camera.position = player.position
	add_child(camera)
	camera.make_current()
	_apply_zoom()

	hud = DemoHud.new()
	hud.title = "C - Illustrated 2D"
	hud.subtitle = "Hand-inked top-down house: walls crack, splinter and give way"
	add_child(hud)
	hud.night_changed.connect(_on_night_changed)
	lighting.set_night(hud.is_night, true)

	if _scenario != "":
		_setup_scenario.call_deferred()


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _on_night_changed(n: bool) -> void:
	lighting.set_night(n)


# --- frame -------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if Input.is_action_pressed("fire") and _cooldown <= 0.0:
		_fire(player.aim_point)
	var p = spawner.tick(delta, debug_living_enemies(), player.plan_pos())
	if p != null:
		spawn_enemy(p)


func _process(delta: float) -> void:
	_view_m = lerpf(_view_m, _view_target, clampf(delta * 8.0, 0.0, 1.0))
	_apply_zoom()
	var focus: Vector2 = player.global_position
	if _cam_focus != null:
		focus = Art.w(_cam_focus)
	else:
		var look: Vector2 = (player.aim_point - player.global_position) * 0.22
		focus += look.limit_length(Art.m(2.6))
	camera.position = camera.position.lerp(focus, clampf(delta * 6.0, 0.0, 1.0))
	_shake = move_toward(_shake, 0.0, delta * 30.0)
	camera.offset = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * _shake
	hud.stats_text = "wall sections %d/%d standing   %d practical lights   %d psychos" % [
		walls.intact_count(), walls.sections.size(), lighting.practical_count(), debug_living_enemies()]
	if _slowmo_at >= 0.0 and (Time.get_ticks_msec() - _start_ms) / 1000.0 >= _slowmo_at:
		_slowmo_at = -1.0
		_fire(player.aim_point)
		Engine.time_scale = 0.03


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("zoom_in"):
		_view_target = clampf(_view_target / 1.15, VIEW_MIN_M, VIEW_MAX_M)
	elif event.is_action_pressed("zoom_out"):
		_view_target = clampf(_view_target * 1.15, VIEW_MIN_M, VIEW_MAX_M)


func _apply_zoom() -> void:
	var vw := get_viewport_rect().size.x
	var z := vw / (_view_m * Art.PX_PER_M)
	camera.zoom = Vector2(z, z)


# --- gunfire ---------------------------------------------------------------------------

func _fire(target_world: Vector2) -> void:
	_cooldown = Tuning.FIRE_INTERVAL
	var origin := player.global_position
	var dir := target_world - origin
	dir = player.aim_dir if dir.length() < 1.0 else dir.normalized()
	player.aim_dir = dir
	var to := origin + dir * Art.m(Tuning.SHOT_RANGE)
	var q := PhysicsRayQueryParameters2D.create(origin, to, 1 | 2 | 8)
	q.exclude = [player.get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	var end := to
	if not hit.is_empty():
		end = hit["position"]
		var col: Object = hit["collider"]
		var normal: Vector2 = hit["normal"]
		if col.has_method("die"):
			col.hit(Tuning.SHOT_DAMAGE, dir)
			fx.body_hit(end, dir)
		elif col.has_method("stage"):
			var mat: String = col.hit(end, 1, dir)
			fx.impact(end, normal, mat)
		else:
			fx.impact(end, normal, col.get_meta("material", "wood") if col.has_meta("material") else "wood")
	var muzzle := player.muzzle_position()
	fx.muzzle(muzzle, dir, player.global_position + dir * Art.m(0.2))
	fx.tracer(muzzle, end)
	player.recoil()
	_shake = maxf(_shake, 1.6)


func _on_section_destroyed(s) -> void:
	fx.wall_removed(s)


# --- enemies ----------------------------------------------------------------------------

func spawn_enemy(p: Vector2) -> Node:
	var e: Enemy = Enemy.new()
	_variant_flip = not _variant_flip
	e.setup(nav, player.plan_pos, "a" if _variant_flip else "b")
	e.position = Art.w(p)
	e.swung.connect(_on_enemy_swung)
	enemies_node.add_child(e)
	return e


func _on_enemy_swung(e, kind: String, target: Vector2) -> void:
	var dir: Vector2 = (Art.w(target) - e.global_position).normalized()
	if kind == "wall":
		var mat := walls.bash_at(target, Tuning.ENEMY_WALL_DAMAGE, dir)
		if mat != "none":
			fx.impact(Art.w(target), -dir, mat)
	else:
		fx.swing(e.global_position, dir)
		_shake = maxf(_shake, 2.5)


# --- smoke-test debug API (plan meters) -------------------------------------------------------

func debug_hud() -> DemoHud:
	return hud


func debug_player_pos() -> Vector2:
	return player.plan_pos()


func debug_teleport_player(p: Vector2) -> void:
	player.global_position = Art.w(p)
	player.velocity = Vector2.ZERO
	camera.position = player.position


func debug_fire_at(target: Vector2, _height: float) -> void:
	player.aim_point = Art.w(target)
	_fire(Art.w(target))


func debug_set_spawning(on: bool) -> void:
	spawner.enabled = on


func debug_spawn_enemy(p: Vector2) -> Node:
	return spawn_enemy(p)


func debug_living_enemies() -> int:
	var n := 0
	for e in enemies_node.get_children():
		if e.alive:
			n += 1
	return n


func debug_enemy_positions() -> PackedVector2Array:
	var out := PackedVector2Array()
	for e in enemies_node.get_children():
		if e.alive:
			out.append(e.plan_pos())
	return out


func debug_nav() -> GridNav:
	return nav


func debug_blocked_at(p: Vector2) -> bool:
	var q := PhysicsShapeQueryParameters2D.new()
	var c := CircleShape2D.new()
	c.radius = Art.m(0.08)
	q.shape = c
	q.transform = Transform2D(0.0, Art.w(p))
	q.collision_mask = 1 | 2 | 16
	return not get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty()


func debug_is_night() -> bool:
	return lighting.night


# --- showcase scenarios (screenshots) -----------------------------------------------------------

func _section_at(wall_id: String, along: float):
	for s in walls.sections:
		if s.wall["id"] == wall_id and along >= s.from_m - 1e-3 and along <= s.to_m + 1e-3:
			return s
	return null


func _damage(wall_id: String, along: float, hits: int) -> void:
	var s = _section_at(wall_id, along)
	if s != null:
		walls.damage_section(s, hits)


func _place_enemy(p: Vector2, face: float, frozen := true) -> Node:
	var e = spawn_enemy(p)
	e.frozen = frozen
	e.token.facing = face
	return e


func _setup_scenario() -> void:
	spawner.enabled = false
	player.use_mouse = false
	match _scenario:
		"overview":
			_view_target = 30.0
			_view_m = 30.0
			_cam_focus = Vector2(7.0, 6.6)
			player.aim_point = Art.w(Vector2(4.5, 9.5))
			_damage("south", 8.5, 99)
			_damage("south", 9.4, 6)
			_damage("north", 2.0, 1)
			_place_enemy(Vector2(-2.5, 4.5), 0.2, false)
			_place_enemy(Vector2(16.4, 3.0), PI, false)
			_place_enemy(Vector2(8.4, 12.2), -PI * 0.5, false)
		"damage":
			_view_target = 12.0
			_view_m = 12.0
			_cam_focus = Vector2(10.2, 8.4)
			player.global_position = Art.w(Vector2(9.6, 7.0))
			player.aim_point = Art.w(Vector2(11.5, 9.0))
			_damage("south", 7.5, 2)       # window: glass shattered
			_damage("south", 8.5, 99)      # removed
			_damage("south", 9.4, 8)       # broken planks
			_damage("south", 10.5, 5)      # cracked
			_damage("south", 11.5, 2)      # bullet holes
			_damage("south", 12.5, 1)      # window: cracked glass
			_damage("living_utility", 6.5, 7)
		"breach":
			_view_target = 15.0
			_view_m = 15.0
			_cam_focus = Vector2(11.6, 0.6)
			player.global_position = Art.w(Vector2(10.6, -2.6))
			player.aim_point = Art.w(Vector2(12.6, 0.6))
			_damage("north", 12.5, 99)
			_damage("north", 13.4, 99)
			_damage("north", 10.5, 2)
			_damage("north", 11.5, 99)
			_damage("north", 9.5, 7)
			_damage("bath_kitchen", 2.5, 99)
			_place_enemy(Vector2(13.0, -3.6), PI * 0.75, true)
		"enemies":
			_view_target = 14.0
			_view_m = 14.0
			_cam_focus = Vector2(6.2, 7.4)
			player.global_position = Art.w(Vector2(6.6, 7.6))
			player.aim_point = Art.w(Vector2(4.5, 9.4))
			_place_enemy(Vector2(4.5, 9.6), -PI * 0.5 + 0.3, true)
			_place_enemy(Vector2(2.4, 10.6), -0.9, true)
			_place_enemy(Vector2(8.2, 10.4), -PI * 0.6, true)
			_place_enemy(Vector2(9.0, 5.4), PI * 0.9, true)
			var d = _place_enemy(Vector2(5.4, 4.95), 0.0, true)
			d.die(Vector2(0.3, -1.0).normalized())
			_damage("south", 2.5, 2)
		"shooting":
			_view_target = 12.5
			_view_m = 12.5
			_cam_focus = Vector2(8.0, 7.6)
			player.global_position = Art.w(Vector2(7.6, 7.2))
			player.aim_point = Art.w(Vector2(8.6, 9.0))
			_damage("south", 8.5, 7)
			_damage("south", 7.5, 2)
			_place_enemy(Vector2(10.6, 11.0), -PI * 0.7, true)
			_place_enemy(Vector2(5.2, 5.4), 0.3, true)
