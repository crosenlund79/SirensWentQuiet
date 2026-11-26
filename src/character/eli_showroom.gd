class_name EliShowroom
extends Control
## Experiment 010: the character showroom. Eli on a neutral stage with good
## light; drag or A/D to turn him, wheel or W/S to zoom; animations (Idle,
## Walk, Jog, Run, Handgun, Two-handed), variations, a turnaround sheet, a
## face close-up, the gameplay camera (distance, pitch, FOV of VoxelCamera),
## night light, and the original character for comparison.
## Standalone (eli_showroom.tscn, from Visual Experiments) Esc returns to
## Visual Experiments; as an overlay (open_overlay, from F10) Esc closes it.
##
## Capture args (tools/capture.sh): --view=front|three|side|back|face|gameplay|sheet
## --anim=idle|walk|jog|run|handgun|shotgun|flashlight|tool --variant=N --yaw=deg --dist=m --ty=m --night --compare
## --moving --hide-ui
## Exp 011, people (HumanoidLooks): --people=<kind> shows that archetype's
## looks in a row (--seed=first, --count=n, --cols=n per row), with the
## people animations (idle, walk, jog, attack, hit, die).

const SCENE := "res://src/character/eli_showroom.tscn"
const LAUNCHER := "res://src/launcher/launcher.tscn"
const ANIMS := [["idle", "Idle"], ["walk", "Walk"], ["jog", "Jog (game pace)"], ["run", "Run (sprint)"],
	["handgun", "Handgun"], ["shotgun", "Two-handed"], ["flashlight", "Flashlight"], ["tool", "Hammer"]]
const SPEEDS := {"idle": 0.0, "walk": 1.4, "jog": 4.0, "run": 6.4, "handgun": 0.0, "shotgun": 0.0, "flashlight": 0.0, "tool": 1.4}
const PEOPLE_ANIMS := [["idle", "Idle"], ["walk", "Walk"], ["jog", "Hunt (game pace)"], ["run", "Run"],
	["attack", "Attack"], ["hit", "Hit"], ["die", "Collapse"]]
const PEOPLE_SPEEDS := {"idle": 0.0, "walk": 1.2, "jog": 1.85, "run": 3.3, "attack": 0.0, "hit": 0.0, "die": 0.0}
const VIEWS := [["three", "3/4"], ["front", "Front"], ["side", "Side"], ["back", "Back"], ["face", "Face"],
	["sheet", "Turnaround"], ["gameplay", "Gameplay distance"]]

var overlay := false
var anim := "idle"
var view := "three"
var variant := 0
var night := false
var compare := false
var moving := false         ## walk the gait across the stage (feet planted on the floor)
var people := ""            ## Exp 011: an archetype's looks instead of Eli ("" = Eli)
var people_seed := 0
var people_count := 1
var people_cols := 0
var _anim_t := 0.0

var _vp: SubViewport
var _stage: Node3D
var _cam: Camera3D
var _rigs: Array[VoxelRig] = []
var _orig: VoxelRig
var _yaw := 0.0
var _pitch := -0.12
var _dist := 3.2
var _target := Vector3(0.0, 1.0, 0.0)
var _drag := false
var _panel: Control
var _status: Label
var _key: DirectionalLight3D
var _lamp: OmniLight3D
var _env: Environment
var _was_paused := false
var _hide_ui := false
var _yaw_arg := INF
var _dist_arg := 0.0
var _ty_arg := INF


## Opens the showroom over the running game (F10); Esc closes it again.
static func open_overlay(tree: SceneTree) -> EliShowroom:
	var layer := CanvasLayer.new()
	layer.layer = 95
	layer.name = "EliShowroomLayer"
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var s: EliShowroom = (load(SCENE) as PackedScene).instantiate()
	s.overlay = true
	layer.add_child(s)
	tree.root.add_child(layer)
	return s


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	variant = clampi(int(GameSettings.get_value("eli_variant")), 0, EliSculpt.variant_count() - 1)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--view="):
			view = a.trim_prefix("--view=")
		elif a.begins_with("--anim="):
			anim = a.trim_prefix("--anim=")
		elif a.begins_with("--variant="):
			variant = clampi(int(a.trim_prefix("--variant=")), 0, EliSculpt.variant_count() - 1)
		elif a.begins_with("--yaw="):
			_yaw_arg = deg_to_rad(float(a.trim_prefix("--yaw=")))
		elif a.begins_with("--dist="):
			_dist_arg = float(a.trim_prefix("--dist="))
		elif a.begins_with("--ty="):
			_ty_arg = float(a.trim_prefix("--ty="))
		elif a == "--night":
			night = true
		elif a == "--compare":
			compare = true
		elif a == "--hide-ui":
			_hide_ui = true
		elif a == "--moving":
			moving = true
		elif a.begins_with("--people="):
			people = a.trim_prefix("--people=")
		elif a.begins_with("--seed="):
			people_seed = int(a.trim_prefix("--seed="))
		elif a.begins_with("--count="):
			people_count = maxi(int(a.trim_prefix("--count=")), 1)
		elif a.begins_with("--cols="):
			people_cols = maxi(int(a.trim_prefix("--cols=")), 1)
	if overlay:
		_was_paused = get_tree().paused
		get_tree().paused = true
	Sfx.attach(self) if not overlay else null
	_build_stage()
	_build_ui()
	_rebuild_rigs()
	_apply_view(view)
	if _yaw_arg != INF:
		_yaw = _yaw_arg
	if _dist_arg > 0.0:
		_dist = _dist_arg
	if _ty_arg != INF:
		_target.y = _ty_arg
	_apply_light()


func _exit_tree() -> void:
	if overlay and is_instance_valid(get_tree()):
		get_tree().paused = _was_paused
	var m := VoxelRig.look_material(true)
	m.set_shader_parameter("night", 0.0)


func close() -> void:
	if overlay:
		get_parent().queue_free()
	else:
		get_tree().change_scene_to_file(LAUNCHER)


# --- stage ------------------------------------------------------------------------------

func _build_stage() -> void:
	var box := SubViewportContainer.new()
	box.name = "View"
	box.stretch = true
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_2X
	_vp.process_mode = Node.PROCESS_MODE_ALWAYS
	box.add_child(_vp)
	_stage = Node3D.new()
	_stage.name = "Stage"
	_vp.add_child(_stage)
	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_exposure = 1.0
	we.environment = _env
	_stage.add_child(we)
	_key = DirectionalLight3D.new()
	_key.rotation = Vector3(deg_to_rad(-42.0), deg_to_rad(28.0), 0.0)
	_key.shadow_enabled = true
	_key.directional_shadow_max_distance = 30.0
	_stage.add_child(_key)
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.rotation = Vector3(deg_to_rad(-20.0), deg_to_rad(-120.0), 0.0)
	fill.light_color = Color(0.62, 0.72, 0.9)
	fill.light_energy = 0.35
	_stage.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.name = "Rim"
	rim.rotation = Vector3(deg_to_rad(-25.0), deg_to_rad(170.0), 0.0)
	rim.light_color = Color(0.85, 0.9, 1.0)
	rim.light_energy = 0.55
	_stage.add_child(rim)
	_lamp = OmniLight3D.new()
	_lamp.light_color = Color(1.0, 0.72, 0.42)
	_lamp.omni_range = 6.0
	_lamp.light_energy = 2.2
	_lamp.shadow_enabled = true
	_lamp.position = Vector3(1.2, 2.1, -1.1)
	_stage.add_child(_lamp)
	# floor: a large soft disc
	var floor_mi := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 40.0
	disc.bottom_radius = 40.0
	disc.height = 0.02
	disc.radial_segments = 64
	floor_mi.mesh = disc
	floor_mi.position.y = -0.01
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.36, 0.38, 0.41)
	fm.roughness = 0.95
	floor_mi.material_override = fm
	_stage.add_child(floor_mi)
	_cam = Camera3D.new()
	_cam.current = true
	_stage.add_child(_cam)


func _apply_light() -> void:
	var m := VoxelRig.look_material(true)
	m.set_shader_parameter("night", 1.0 if night else 0.0)
	VoxelRig.look_material(false).set_shader_parameter("night", 1.0 if night else 0.0)
	if night:
		_env.background_color = Color(0.035, 0.045, 0.07)
		_env.ambient_light_color = Color(0.3, 0.38, 0.6)
		_env.ambient_light_energy = 0.35
		_key.light_color = Color(0.55, 0.65, 0.95)
		_key.light_energy = 0.18
		_lamp.visible = true
	else:
		_env.background_color = Color(0.2, 0.215, 0.235)
		_env.ambient_light_color = Color(0.72, 0.76, 0.84)
		_env.ambient_light_energy = 0.55
		_key.light_color = Color(1.0, 0.95, 0.88)
		_key.light_energy = 1.15
		_lamp.visible = false


func _rebuild_rigs() -> void:
	for r in _rigs:
		r.queue_free()
	_rigs.clear()
	if _orig != null:
		_orig.queue_free()
		_orig = null
	if people != "":
		_rebuild_people()
		return
	var n := 4 if view == "sheet" else 1
	for i in n:
		var r := EliRig.new(variant)
		r.name = "Eli%d" % i
		if n > 1:
			r.position = Vector3((1.5 - i) * 0.95, 0.0, 0.0)
			r.rotation.y = [0.0, deg_to_rad(35.0), deg_to_rad(90.0), PI][i]
		_stage.add_child(r)
		_rigs.append(r)
	if compare and n == 1:
		_orig = VoxelRig.new(VoxelRig.Look.PLAYER)
		_orig.position = Vector3(0.6, 0.0, 0.0)
		_stage.add_child(_orig)
		_rigs[0].position = Vector3(-0.35, 0.0, 0.0)
	_apply_anim()


## Exp 011: a row (or grid) of an archetype's looks.
func _rebuild_people() -> void:
	var n := people_count if view != "sheet" else 4
	var cols := people_cols if people_cols > 0 else n
	var rows := ceili(float(n) / cols)
	for i in n:
		var seed := people_seed + (i if view != "sheet" else 0)
		var r := HumanoidLooks.make_rig(people, seed)
		r.name = "Person%d" % i
		var c := i % cols
		var row := i / cols
		r.position = Vector3((c - (cols - 1) * 0.5) * 0.95, 0.0, (row - (rows - 1) * 0.5) * 1.6)
		if view == "sheet":
			r.position = Vector3((1.5 - i) * 0.95, 0.0, 0.0)
			r.rotation.y = [0.0, deg_to_rad(35.0), deg_to_rad(90.0), PI][i]
		r.set_meta("yaw", r.rotation.y)
		_stage.add_child(r)
		_rigs.append(r)
	_anim_t = 0.0
	_apply_anim()


func _apply_anim() -> void:
	if people != "":
		for r in _rigs:
			r.speed = PEOPLE_SPEEDS.get(anim, 0.0)
			if r is HumanoidRig:
				(r as HumanoidRig).preview_dir = Vector2(0.0, -1.0)
		_anim_t = 0.0
		_say()
		return
	for r in _rigs + ([_orig] if _orig != null else []):
		r.speed = SPEEDS.get(anim, 0.0)
		r.aiming = anim == "handgun" or anim == "shotgun"
		r.carry = anim == "flashlight"
		r.set_held("flashlight" if anim == "flashlight" else ("hammer" if anim == "tool" else ""))
		if r is EliRig:
			(r as EliRig).preview_dir = Vector2(0.0, -1.0)
		var g: Node3D = r.gun
		if g == null:
			continue
		var model := g.get_node_or_null(WeaponHandler.MODEL_NAME) as Node3D
		if anim == "shotgun" and model == null:
			model = WeaponHandler.shotgun_model()
			g.add_child(model)
		if model != null:
			model.visible = anim == "shotgun"
		if g.get_child_count() > 0:
			(g.get_child(0) as Node3D).visible = anim != "shotgun"
	_say()


func _apply_view(v: String) -> void:
	var was_sheet := view == "sheet"
	view = v
	if (v == "sheet") != was_sheet or _rigs.is_empty():
		_rebuild_rigs()
	_cam.fov = 30.0
	_target = Vector3(0.0, 0.95, 0.0)
	match v:
		"front":
			_yaw = 0.0
			_pitch = -0.06
			_dist = 3.4
		"three":
			_yaw = deg_to_rad(35.0)
			_pitch = -0.1
			_dist = 3.4
		"side":
			_yaw = deg_to_rad(90.0)
			_pitch = -0.04
			_dist = 3.4
		"back":
			_yaw = PI
			_pitch = -0.08
			_dist = 3.4
		"face":
			_yaw = deg_to_rad(20.0)
			_pitch = -0.04
			_dist = 0.95
			_target = Vector3(0.0, 1.64, 0.0)
		"sheet":
			_yaw = 0.0
			_pitch = -0.05
			_dist = 6.6
		"gameplay":
			_cam.fov = 40.0
			_yaw = 0.0
			_pitch = deg_to_rad(VoxelCamera.PITCH_DEG)
			_dist = 20.0
			_target = Vector3(0.0, VoxelCamera.LOOK_HEIGHT, 0.0)
	_say()


func _process(delta: float) -> void:
	var rigs: Array = _rigs.duplicate()
	if _orig != null:
		rigs.append(_orig)
	_anim_t += delta
	for r in rigs:
		var sp: float = PEOPLE_SPEEDS.get(anim, 0.0) if people != "" else SPEEDS.get(anim, 0.0)
		if moving and sp > 0.0:
			r.position.z -= delta * sp
			if r.position.z < -6.0:
				r.position.z = 6.0
		if people != "" and r is HumanoidRig:
			var h := r as HumanoidRig
			if anim == "die":
				h.collapse(delta, fmod(_anim_t, 4.0), Vector3.RIGHT, _people_yaw(h))
				if fmod(_anim_t, 4.0) < delta * 1.5 and h.dead:
					h.dead = false
					h.transform.basis = Basis(Vector3.UP, _people_yaw(h))
					h.position.y = 0.0
				continue
			if anim == "attack" and fmod(_anim_t, 1.4) < delta:
				h.swing = 1.0
			if anim == "hit" and fmod(_anim_t, 1.6) < delta:
				h.stagger = 1.0
				h.set_flash(1.0)
			h.swing = maxf(h.swing - delta / 0.5, 0.0)
		r.animate(delta)
	if moving and not _rigs.is_empty():
		_target.z = _rigs[0].position.z
	if people != "" and view == "face" and not _rigs.is_empty() and _rigs[0].head != null:
		_target = _rigs[0].head.global_position + Vector3(0.0, 0.15, 0.0)
	# yaw 0: in front of him (he faces -Z); the gameplay view looks north like VoxelCamera
	var dir := Vector3(-sin(_yaw) * cos(_pitch), -sin(_pitch), -cos(_yaw) * cos(_pitch))
	if view == "gameplay":
		dir = Vector3(sin(_yaw) * cos(-_pitch), sin(-_pitch), cos(_yaw) * cos(-_pitch))
	_cam.position = _target + dir * _dist
	_cam.look_at(_target, Vector3.UP)
	var k := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		k -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		k += 1.0
	_yaw += k * delta * 1.6
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		_zoom(-delta * 2.0)
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		_zoom(delta * 2.0)


func _people_yaw(h: HumanoidRig) -> float:
	return h.get_meta("yaw", h.rotation.y)


func _zoom(f: float) -> void:
	var lo := 0.6 if view != "gameplay" else 8.0
	var hi := 9.0 if view != "gameplay" else 32.0
	_dist = clampf(_dist * (1.0 + f), lo, hi)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE or (overlay and event.physical_keycode == KEY_F10):
			get_viewport().set_input_as_handled()
			close()
			return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if _panel != null and _panel.get_global_rect().has_point(mb.position):
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(-0.1)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(0.1)
	elif event is InputEventMouseMotion and _drag:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.01
		if view != "gameplay":
			_pitch = clampf(_pitch - mm.relative.y * 0.006, -1.2, 0.6)


# --- ui ---------------------------------------------------------------------------------

func _build_ui() -> void:
	theme = UiTheme.theme()
	_panel = UiTheme.make_panel()
	_panel.name = "Panel"
	_panel.position = Vector2(20, 20)
	_panel.custom_minimum_size = Vector2(300, 0)
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_panel.add_child(col)
	col.add_child(UiTheme.make_title("Character Showroom", 20))
	col.add_child(UiTheme.make_caption("Elias \"Eli\" Walker, 41. Former carpenter.", 280, UiTheme.TEXT_DIM))
	col.add_child(UiTheme.make_section("Animation"))
	col.add_child(_grid(2, (ANIMS if people == "" else PEOPLE_ANIMS).map(func(a): return [a[1], func(): _set_anim(a[0])])))
	var walk := UiTheme.make_toggle("Walk across the stage", moving)
	walk.toggled.connect(func(on: bool):
		moving = on
		for r in _rigs:
			r.position.z = 0.0
		_target.z = 0.0)
	col.add_child(walk)
	col.add_child(UiTheme.make_section("View"))
	col.add_child(_grid(2, VIEWS.map(func(v): return [v[1], func(): _apply_view(v[0])])))
	col.add_child(UiTheme.make_section("People (Exp 011)"))
	col.add_child(_grid(2, [["Eli", func(): _set_people("", 0)], ["Psychos", func(): _set_people("psycho", 0)],
		["< Previous look", func(): _set_people(people, people_seed - maxi(people_count, 1))],
		["Next look >", func(): _set_people(people, people_seed + maxi(people_count, 1))]]))
	col.add_child(UiTheme.make_section("Variation"))
	var vs := []
	for i in EliSculpt.variant_count():
		vs.append([EliSculpt.variant_name(i), _set_variant.bind(i)])
	col.add_child(_grid(1, vs))
	col.add_child(UiTheme.make_section("Light"))
	col.add_child(_grid(2, [["Day", func(): _set_night(false)], ["Night + lamp", func(): _set_night(true)]]))
	var cmp := UiTheme.make_toggle("Beside the original character", compare)
	cmp.toggled.connect(func(on: bool):
		compare = on
		_rebuild_rigs())
	col.add_child(cmp)
	col.add_child(UiTheme.make_spacer(4))
	var back := UiTheme.make_button("Close" if overlay else "Back")
	back.name = "Back"
	back.pressed.connect(close)
	col.add_child(back)
	_status = UiTheme.make_label("", UiTheme.FONT_SMALL, UiTheme.TEXT_DIM)
	_status.anchor_top = 1.0
	_status.anchor_bottom = 1.0
	_status.position = Vector2(24, -40)
	_status.offset_top = -40
	_status.offset_left = 24
	add_child(_status)
	_panel.visible = not _hide_ui
	_status.visible = not _hide_ui


func _grid(cols: int, items: Array) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 5)
	g.add_theme_constant_override("v_separation", 5)
	for it in items:
		var b := UiTheme.make_button(it[0])
		b.name = (it[0] as String).validate_node_name().replace(" ", "_")
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 30)
		b.add_theme_font_size_override("font_size", UiTheme.px(UiTheme.FONT_SMALL))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(it[1])
		g.add_child(b)
	return g


func _set_anim(a: String) -> void:
	anim = a
	_apply_anim()


func _set_variant(i: int) -> void:
	variant = i
	for r in _rigs:
		if r is EliRig:
			(r as EliRig).set_variant(i)
	_say()


func _set_people(kind: String, seed: int) -> void:
	if kind != "" and HumanoidLooks.variety(kind) <= 0:
		return
	people = kind
	people_seed = posmod(seed, maxi(HumanoidLooks.variety(kind), 1)) if kind != "" else 0
	if kind != "" and anim not in PEOPLE_SPEEDS:
		anim = "idle"
	elif kind == "" and anim not in SPEEDS:
		anim = "idle"
	_rebuild_rigs()


func _set_night(on: bool) -> void:
	night = on
	_apply_light()


func _say() -> void:
	if _status == null:
		return
	var who := EliSculpt.variant_name(variant)
	if people != "":
		who = str(HumanoidLooks.look(people, people_seed).get("name", people))
	_status.text = "%s · %s · %s     Drag / A D: turn   Wheel / W S: zoom   Esc: %s" % [
		who, anim, view, "close" if overlay else "back"]


## Test access.
func rigs() -> Array:
	return _rigs
