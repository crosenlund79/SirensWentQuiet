extends Node
## Combat wiring for the game root (Experiment 003). The game decides *when*
## (its modal state, build mode); this node does the *how*:
##   - the weapon runtime (K's WeaponHandler): firing, the weapon keys
##     (R reload, Q next, 1 / 2 primary / secondary), the "Out of ammo" toast;
##   - the enemies' blows (AI's roster signals): wall strikes, hits on the
##     player by archetype (`state.damage(enemy_damage() x damage_scale, kind)`);
##   - the bomber: an early notice when one appears, a HUD alert and a pulsing
##     ground marker while its fuse burns, and the blast on the player
##     (EnemyDefs.blast_damage_at, the vest applies in GameState.damage) with a
##     camera shake.
## Docs: docs/experiment-003/game.md.

const NUDGE_NEAR := 6.0                ## m: wall bashes this close shake the camera
const SILENT_REASONS := ["", "Full.", "Already reloading."]

var game: Node                         ## SurvivalGame
var weapons: WeaponHandler
var last_blast := {}                   ## {"at", "dist", "hurt", "taken"} (tests, playtest)
var blasts_on_player := 0
var _markers := {}                     ## bomber instance id -> marker node


func setup(g: Node) -> void:
	game = g
	weapons = WeaponHandler.new()
	weapons.name = "Weapons"
	add_child(weapons)
	weapons.empty.connect(_on_empty)
	var r: Node = game.roster
	r.wall_swing.connect(_on_wall_swing)
	r.player_swing.connect(_on_player_swing)
	r.detonated.connect(_on_detonated)
	r.fuse_started.connect(_on_fuse_started)
	r.enemy_spawned.connect(_on_enemy_spawned)
	r.enemy_died.connect(_on_enemy_died)
	reset()


## After a new run or a load: the handler reads the (new) state.
func reset() -> void:
	weapons.setup(game.state, game.world, game.player)


## One trigger pull at `aim` (world space) through the weapon in hand.
func fire(aim: Vector3) -> Dictionary:
	var r := weapons.try_fire(aim)
	if r.get("ok", false):
		game.shots_fired += 1
		if game.camera != null:       # Exp 013: a modest kick per weapon
			game.camera.nudge(float(WeaponDefs.get_def(str(r.get("id", ""))).get("cam_kick", 0.2)) * (0.7 if weapons.ads else 1.0))
	return r


## The weapon keys (outside build mode and panels). True if handled.
func handle_input(event: InputEvent) -> bool:
	var why := "~"
	if event.is_action_pressed("reload"):
		why = weapons.reload()
	elif event.is_action_pressed("weapon_next"):
		why = "" if weapons.next() != "" else _no_other_weapon()
	elif event.is_action_pressed("weapon_1"):
		why = weapons.select_slot("primary")
	elif event.is_action_pressed("weapon_2"):
		why = weapons.select_slot("secondary")
	if why == "~":
		return false
	if not why in SILENT_REASONS:
		game.toast(why, "warn")
	return true


func _no_other_weapon() -> String:
	var n := 0
	for slot in Equipment.WEAPON_SLOTS:
		if game.state.equipped(slot) != "":
			n += 1
	return "No other weapon equipped." if n < 2 else ""


func _on_empty(_id: String) -> void:
	var c := weapons.current()
	if int(c.get("reserve", 0)) <= 0 and not c.get("unlimited", false):
		game.toast("Out of ammo", "warn")
	else:
		game.toast("Reloading", "info")


# --- enemies ---------------------------------------------------------------------------

## The world bites the wall or bashes the door; once per strike (a brute's
## swing arrives as three).
func _on_wall_swing(e: VoxelEnemy, target: Vector2) -> void:
	# Experiment 004 (L): an enemy on another storey strikes that storey's world.
	var w: HouseWorld = (e as AIEnemy).world if e is AIEnemy and (e as AIEnemy).world != null else game.world
	w.enemy_strike(e.global_position, target)
	if e.global_position.distance_to(game.player.global_position) < NUDGE_NEAR:
		game.camera.nudge(0.35)


func _on_player_swing(e: VoxelEnemy) -> void:
	var s: GameState = game.state
	if s.dead:
		return
	if not _same_storey(e.global_position.y):      # Experiment 004 (L): never through a floor
		return
	Sfx.play("enemy/attack", e.global_position + Vector3(0, 1.2, 0))
	game.camera.nudge(1.6 if e is AIEnemy and (e as AIEnemy).kind == "brute" else 1.0)
	var kind: String = (e as AIEnemy).kind if e is AIEnemy else "psycho"
	var scale: float = (e as AIEnemy).damage_scale if e is AIEnemy else 1.0
	_hurt(s.enemy_damage() * scale, kind)


func _hurt(amount: float, cause: String) -> float:
	var s: GameState = game.state
	var before := s.health
	if amount > 0.0 and not s.dead:
		s.damage(amount, cause)
	var taken := before - s.health
	if taken > 0.0:
		Sfx.play("player/hurt")
		if game.hud != null:
			game.hud.flash_damage(clampf(taken / 25.0, 0.4, 1.0))
	return taken


## A blast (a bomber's detonation or its pop when shot mid-fuse): the player
## takes the fall-off damage, the camera shakes by distance.
func _on_detonated(at: Vector3, radius: float, damage: float) -> void:
	var d := Vector2(at.x, at.z).distance_to(game.player.plan_pos())
	var hurt := EnemyDefs.blast_damage_at(d, damage, radius) if _same_storey(at.y - 1.0) else 0.0
	var taken := _hurt(hurt, "blast")
	var shake := (2.6 if radius > 2.0 else 1.2) * clampf(1.4 - d / 14.0, 0.35, 1.4)
	game.camera.nudge(shake)
	last_blast = {"at": at, "dist": d, "hurt": hurt, "taken": taken, "radius": radius}
	if taken > 0.0:
		blasts_on_player += 1
		game.toast("Caught in the blast! (-%d)" % ceili(taken), "bad")
	if game.hud != null:
		game.hud.alert("")


func _on_fuse_started(e: VoxelEnemy, at: Vector3, seconds: float) -> void:
	if game.hud != null:
		game.hud.alert("Bomber at the wall · %.0f s" % seconds, seconds)
	var m := FuseMarker.new()
	m.name = "FuseMarker"
	m.life = seconds + 0.3
	game.add_child(m)
	m.global_position = Vector3(at.x, 0.03, at.z)
	_markers[e.get_instance_id()] = m


func _on_enemy_spawned(_e: VoxelEnemy, kind: String) -> void:
	if kind == "bomber":
		game.toast("A bomber! The glowing pack: shoot it before it reaches the house.", "warn")


func _on_enemy_died(e: VoxelEnemy, kind: String, cause: String) -> void:
	var m = _markers.get(e.get_instance_id())
	if m != null and is_instance_valid(m):
		m.queue_free()
	_markers.erase(e.get_instance_id())
	if kind == "bomber" and game.hud != null:
		game.hud.alert("")
		if cause == "shot" and game.get("corpses") == null:
			game.toast("The bomber is down.", "good")     # (Exp 012: the named "Downed" toast says it)
	if cause == "blast":
		Sfx.play("enemy/death", e.global_position)


## Experiment 004 (L): true if a body at height y stands on the player's storey.
func _same_storey(y: float) -> bool:
	return Levels.storey_at(y) == Levels.storey_at(game.player.global_position.y)


## Fuse markers on the ground now (tests, playtest).
func markers() -> Array:
	return _markers.values().filter(func(m): return is_instance_valid(m))


## A pulsing orange ring on the ground where a bomber's fuse burns, drawn over
## the walls so it can be seen through the house.
class FuseMarker extends Node3D:
	var life := 2.8
	var _t := 0.0
	var _mat: StandardMaterial3D

	func _ready() -> void:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.62
		torus.outer_radius = 0.8
		torus.rings = 24
		torus.ring_segments = 6
		ring.mesh = torus
		ring.scale = Vector3(1.0, 0.08, 1.0)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.no_depth_test = true
		_mat.render_priority = 8
		_mat.albedo_color = Color(1.0, 0.55, 0.12, 0.9)
		ring.material_override = _mat
		add_child(ring)

	func _process(delta: float) -> void:
		_t += delta
		var k := 0.5 + 0.5 * sin(_t * lerpf(8.0, 22.0, clampf(_t / maxf(life, 0.1), 0.0, 1.0)))
		_mat.albedo_color.a = 0.35 + 0.6 * k
		scale = Vector3.ONE * (1.0 + 0.12 * k)
		if _t >= life:
			queue_free()
