extends Node3D
## Weapon preview harness (not used by the game). The real house world, the
## player and two psychos (VoxelEnemy) on the front yard; a WeaponHandler with
## real input: WASD move, mouse aim, hold LMB to fire, R reload, Q next weapon,
## 1 / 2 weapon slots, U toggles the unlimited cheat. A small static label
## shows the weapon readout (it only changes when the readout does).
##   godot --path . res://src/combat/weapon_preview.tscn [-- --weapon=shotgun]
## Screenshot mode (tools/capture.sh): --weapon=handgun|shotgun --shot-at=<s>
## fires once at the nearest psycho after <s> seconds and then freezes the
## effects (muzzle flash, tracers, debris) so the capture shows the shot.
## Other args: --night, --still (psychos stand still).

var lighting: VoxelLighting
var world: HouseWorld
var player: VoxelPlayer
var camera: VoxelCamera
var state: GameState
var handler: WeaponHandler
var psychos: Array[VoxelEnemy] = []
var label: Label

var weapon := "handgun"
var shot_at := -1.0
var night := false
var still := false
var _t := 0.0
var _shot_done := false
var _text := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--weapon="):
			weapon = a.trim_prefix("--weapon=")
		elif a.begins_with("--shot-at="):
			shot_at = float(a.trim_prefix("--shot-at="))
		elif a == "--night":
			night = true
		elif a == "--still":
			still = true
	Sfx.attach(self)
	lighting = VoxelLighting.new()
	add_child(lighting)
	world = HouseWorld.new()
	world.setup(lighting)
	add_child(world)
	world.build_new()
	player = VoxelPlayer.new()
	player.name = "Player"
	add_child(player)
	player.global_position = Vector3(1.0, 0, 11.6)
	lighting.night_materials.append(VoxelRig.look_material(true))
	lighting.night_materials.append(VoxelRig.look_material(false))
	camera = VoxelCamera.new()
	camera.target = player
	add_child(camera)
	camera.make_current()
	camera.set_distance(11.0)

	state = GameState.new_run(17)
	state.inventory.add("shotgun", 1)
	state.inventory.add("shells", 12)
	state.inventory.add("ammo", 24)
	state.set_magazine("shotgun", 5)
	state.set_magazine("handgun", 12)
	handler = WeaponHandler.new()
	handler.name = "Weapons"
	add_child(handler)
	handler.setup(state, world, player)
	if weapon == "shotgun":
		handler.switch_to("shotgun")

	for at in [Vector3(5.2, 0, 11.2), Vector3(8.5, 0, 12.2)]:
		var e := VoxelEnemy.new()
		e.setup(world.nav, player, 1 + psychos.size())
		add_child(e)
		e.global_position = at
		e.rig.rotation.y = PI * 0.5
		e.wall_swing.connect(func(en: VoxelEnemy, target: Vector2) -> void: world.enemy_strike(en.global_position, target))
		if still or shot_at >= 0.0:
			e.set_physics_process(false)
			e.rig.animate(0.0)
		psychos.append(e)
	_aim_at(psychos[0])

	var layer := CanvasLayer.new()
	add_child(layer)
	label = Label.new()
	label.position = Vector2(16, 12)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.95, 0.93, 0.86))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 5)
	layer.add_child(label)
	_update_label()

	world.chunks.flush(100000.0)
	camera.snap()
	lighting.set_amount(1.0 if night else 0.0)
	player.set_night(1.0 if night else 0.0)
	if shot_at >= 0.0:
		player.input_enabled = false


func _aim_at(e: Node3D) -> void:
	player.aim_point = e.global_position + Vector3(0, 1.0, 0)
	var to := player.aim_point - player.global_position
	player.rig.rotation.y = atan2(-to.x, -to.z)


func _physics_process(delta: float) -> void:
	_t += delta
	if shot_at >= 0.0:
		if not _shot_done and _t >= shot_at:
			_shot_done = true
			_aim_at(psychos[0])
			handler.try_fire(player.aim_point)
			_update_label()
			world.fx.process_mode = Node.PROCESS_MODE_DISABLED   # hold the flash and tracers for the capture
		return
	var mp := get_viewport().get_mouse_position()
	player.aim_point = world.aim_ray(camera.project_ray_origin(mp), camera.project_ray_normal(mp))
	if Input.is_action_pressed("fire"):
		handler.try_fire(player.aim_point)


func _process(delta: float) -> void:
	world.update_view(player.global_position, camera, delta)
	if shot_at < 0.0:
		_update_label()


func _unhandled_input(event: InputEvent) -> void:
	if shot_at >= 0.0 or not event is InputEventKey or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_R:
			handler.reload()
		KEY_Q:
			handler.next()
		KEY_1:
			handler.select_slot("primary")
		KEY_2:
			handler.select_slot("secondary")
		KEY_U:
			state.cheats["unlimited"] = not state.cheats["unlimited"]


func _update_label() -> void:
	var c := handler.current()
	var t := "No weapon"
	if c["id"] != "":
		t = "%s   %d / %d   (%d %s)" % [c["name"], c["loaded"], c["capacity"], c["reserve"], c["ammo_name"]]
		if c["reloading"]:
			t += "   reloading %d %%" % int(c["reload_progress"] * 100.0)
		if c["unlimited"]:
			t += "   unlimited"
	t += "\nLMB fire · R reload · Q / 1 / 2 switch · U unlimited"
	if t != _text:
		_text = t
		label.text = t
