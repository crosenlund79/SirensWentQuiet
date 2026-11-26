class_name EliShowroom
extends Control
## The character showroom (Exp 010, extended in Exp 011). One stage with good
## light for every humanoid: Eli and his variations, the ordinary psychos
## (browse their looks / seeds), the runner, brute and bomber (their
## archetype files, or the old figure until they exist), and the Architect
## (an internal name; developer tool only, see ArchitectIdentity).
## Drag or A/D to turn, wheel or W/S to zoom. Animations per character
## (idle, walk, jog, run, turn, attack, hit, collapse, the dormant poses;
## Eli's handgun, two-handed, flashlight, hammer; the Architect's observe),
## the Exp 010 views (3/4, front, side, back, face, turnaround, gameplay
## distance), day / night + lamp / flashlight light, and a comparison mode:
## the character side by side with Eli at the same scale, with a metre ruler,
## a floor grid and each figure's measured height (Eli alone: beside the
## original figure). Standalone (eli_showroom.tscn, from Visual Experiments)
## Esc returns to Visual Experiments; as an overlay (open_overlay, F10) Esc
## closes it. Meshes come from the per-look caches (EliSculpt, HumanoidSculpt):
## changing the animation, view or light never rebuilds a figure.
##
## Capture args (tools/capture.sh):
##   --char=eli|psycho|runner|brute|bomber|architect   the character
##   --compare=psycho|runner|brute|bomber|architect     that character beside Eli
##   --compare                                          (alone) Eli beside the original figure
##   --view=three|front|side|back|face|sheet|gameplay   --yaw=deg --dist=m --ty=m
##   --anim=idle|walk|jog|run|turn|attack|hit|die|observe (Eli: handgun|shotgun|flashlight|tool)
##   --dormant=bang|tap|sway|stare|listen   --pose=x (freeze attack / hit / die at x)
##   --light=day|night|flashlight (--night = night)   --variant=N (Eli)   --seed=N (look)
##   --people=<kind> --count=N --cols=N   a row / grid of an archetype's looks
##   --moving   --hide-ui

const SCENE := "res://src/character/eli_showroom.tscn"
const LAUNCHER := "res://src/launcher/launcher.tscn"
const ANIMS := [["idle", "Idle"], ["walk", "Walk"], ["jog", "Jog"], ["run", "Run"], ["turn", "Turn"],
	["handgun", "Handgun"], ["shotgun", "Two-handed"], ["flashlight", "Flashlight"], ["tool", "Hammer"]]
const SPEEDS := {"idle": 0.0, "walk": 1.4, "jog": 4.0, "run": 6.4, "turn": 0.0, "handgun": 0.0, "shotgun": 0.0,
	"flashlight": 0.0, "tool": 1.4}
const PEOPLE_ANIMS := [["idle", "Idle"], ["walk", "Walk"], ["jog", "Hunt"], ["run", "Run"], ["turn", "Turn"],
	["attack", "Attack"], ["hit", "Hit"], ["die", "Collapse"]]
const ARCHITECT_ANIMS := [["idle", "Still"], ["walk", "Walk"], ["jog", "Brisk"], ["run", "Run"], ["turn", "Turn"],
	["observe", "Observe"], ["attack", "Attack"], ["hit", "Hit"], ["die", "Collapse"]]
const DORMANT := [["bang", "Bang"], ["tap", "Tap"], ["sway", "Sway"], ["stare", "Stare"], ["listen", "Listen"]]
const PEOPLE_SPEEDS := {"idle": 0.0, "walk": 1.2, "jog": 1.85, "run": 3.3, "turn": 0.0, "observe": 0.0,
	"attack": 0.0, "hit": 0.0, "die": 0.0}
const VIEWS := [["three", "3/4"], ["front", "Front"], ["side", "Side"], ["back", "Back"], ["face", "Face"],
	["sheet", "Turnaround"], ["gameplay", "Game cam"]]
const CHARACTERS := [["", "Eli"], ["psycho", "Psycho"], ["runner", "Runner"], ["brute", "Brute"],
	["bomber", "Bomber"], ["architect", "Architect"]]
const LIGHTS := [["day", "Day"], ["night", "Night+lamp"], ["flashlight", "Flashlight"]]
const BODY_VIEWS := ["three", "front", "side", "back"]
const CAPTIONS := {
	"": "Elias \"Eli\" Walker, 41. Former carpenter.",
	"psycho": "Ordinary psychos: ten people, three variations each.",
	"runner": "The runner.",
	"brute": "The brute.",
	"bomber": "The bomber.",
	"architect": "Internal development name: never shown to the player. No spawning, no sounds.",
}

var overlay := false
var anim := "idle"
var view := "three"
var variant := 0
var night := false
var light := "day"          ## day | night | flashlight
var compare := false        ## beside Eli (Eli selected: beside the original figure)
var moving := false         ## walk the gait across the stage (feet planted on the floor)
var people := ""            ## the character: an archetype kind ("" = Eli)
var people_seed := 0
var people_count := 1
var people_cols := 0
var _anim_t := 0.0
var _pose := -1.0           ## people: freeze attack / hit / die at this progress (captures)
var _dormant := ""          ## people: a dormant pose (DormantMind.pose: bang, tap, sway, stare, listen)
var _dorm: Array = []       ## [DormantMind, AIEnemy stand-in] per rig

var _vp: SubViewport
var _stage: Node3D
var _cam: Camera3D
var _rigs: Array[VoxelRig] = []
var _orig: VoxelRig         ## the figure beside the character in comparison mode (Eli, or the original figure)
var _yaw := 0.0
var _pitch := -0.12
var _dist := 3.2
var _target := Vector3(0.0, 1.0, 0.0)
var _drag := false
var _panel: Control
var _col: VBoxContainer
var _scroll: ScrollContainer
var _status: Label
var _key: DirectionalLight3D
var _lamp: OmniLight3D
var _torch: SpotLight3D
var _env: Environment
var _ruler: Node3D
var _marks: Node3D
var _measure := 0           ## frames until the figures are measured (heights, framing)
var _was_paused := false
var _hide_ui := false
var _yaw_arg := INF
var _dist_arg := 0.0
var _ty_arg := INF
var _styles := {}
var _shift := 0.0           ## comparison framing: the camera moves left so the figures clear the panel


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
			light = "night"
		elif a.begins_with("--light="):
			light = a.trim_prefix("--light=")
		elif a == "--compare":
			compare = true
		elif a.begins_with("--compare="):
			compare = true
			people = _kind_arg(a.trim_prefix("--compare="))
		elif a.begins_with("--char="):
			people = _kind_arg(a.trim_prefix("--char="))
		elif a == "--hide-ui":
			_hide_ui = true
		elif a == "--moving":
			moving = true
		elif a.begins_with("--people="):
			people = _kind_arg(a.trim_prefix("--people="))
		elif a.begins_with("--seed="):
			people_seed = int(a.trim_prefix("--seed="))
		elif a.begins_with("--count="):
			people_count = maxi(int(a.trim_prefix("--count=")), 1)
		elif a.begins_with("--dormant="):
			_dormant = a.trim_prefix("--dormant=")
		elif a.begins_with("--pose="):
			_pose = float(a.trim_prefix("--pose="))
		elif a.begins_with("--cols="):
			people_cols = maxi(int(a.trim_prefix("--cols=")), 1)
	if not light in ["day", "night", "flashlight"]:
		light = "day"
	night = light != "day"
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


static func _kind_arg(k: String) -> String:
	return "" if k in ["eli", "", "original"] else k


func _exit_tree() -> void:
	_exit_tree_people()
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
	# Exp 011: a flashlight held by the viewer (follows the camera)
	_torch = SpotLight3D.new()
	_torch.name = "Flashlight"
	_torch.light_color = Color(1.0, 0.95, 0.84)
	_torch.light_energy = 7.0
	_torch.spot_range = 14.0
	_torch.spot_angle = 21.0
	_torch.spot_angle_attenuation = 1.6
	_torch.shadow_enabled = true
	_torch.visible = false
	_stage.add_child(_torch)
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
	_build_ruler()
	_marks = Node3D.new()
	_marks.name = "HeightMarks"
	_stage.add_child(_marks)
	_cam = Camera3D.new()
	_cam.current = true
	_stage.add_child(_cam)


## Exp 011: the height reference of the comparison mode: a metre ruler
## (ticks every 10 cm, labels every 50 cm) and a 50 cm floor grid.
func _build_ruler() -> void:
	_ruler = Node3D.new()
	_ruler.name = "Ruler"
	_ruler.visible = false
	_stage.add_child(_ruler)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.86, 0.84, 0.78)
	mat.roughness = 0.8
	var dim := StandardMaterial3D.new()
	dim.albedo_color = Color(0.27, 0.29, 0.32)
	dim.roughness = 1.0
	var post := Node3D.new()
	post.name = "Post"
	_ruler.add_child(post)
	_box(post, Vector3(0.0, 1.5, 0.0), Vector3(0.025, 3.0, 0.025), mat)
	for i in 31:
		var y := i * 0.1
		var big := i % 5 == 0
		_box(post, Vector3(0.05 if big else 0.03, y, 0.0), Vector3(0.1 if big else 0.06, 0.008 if big else 0.005, 0.012), mat)
		if big and i > 0:
			var l := _label("%.1f m" % y, Color(0.86, 0.84, 0.78))
			l.position = Vector3(-0.2, y, 0.0)
			post.add_child(l)
	var grid := Node3D.new()
	grid.name = "Grid"
	_ruler.add_child(grid)
	for i in 13:
		_box(grid, Vector3(-3.0 + i * 0.5, 0.002, 0.0), Vector3(0.012, 0.004, 4.0), dim)
	for i in 9:
		_box(grid, Vector3(0.0, 0.002, -2.0 + i * 0.5), Vector3(6.0, 0.004, 0.012), dim)


func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	parent.add_child(mi)
	return mi


func _label(text: String, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = UiTheme.font("regular")
	l.font_size = 32
	l.pixel_size = 0.0023
	l.modulate = col
	l.outline_size = 8
	l.outline_modulate = Color(0.0, 0.0, 0.0, 0.7)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.shaded = false
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return l


func _apply_light() -> void:
	night = light != "day"
	var m := VoxelRig.look_material(true)
	m.set_shader_parameter("night", 1.0 if night else 0.0)
	VoxelRig.look_material(false).set_shader_parameter("night", 1.0 if night else 0.0)
	if night:
		_env.background_color = Color(0.035, 0.045, 0.07) if light == "night" else Color(0.02, 0.025, 0.04)
		_env.ambient_light_color = Color(0.3, 0.38, 0.6)
		_env.ambient_light_energy = 0.35 if light == "night" else 0.2
		_key.light_color = Color(0.55, 0.65, 0.95)
		_key.light_energy = 0.18 if light == "night" else 0.1
		_lamp.visible = light == "night"
	else:
		_env.background_color = Color(0.2, 0.215, 0.235)
		_env.ambient_light_color = Color(0.72, 0.76, 0.84)
		_env.ambient_light_energy = 0.55
		_key.light_color = Color(1.0, 0.95, 0.88)
		_key.light_energy = 1.15
		_lamp.visible = false
	_torch.visible = light == "flashlight"
	_say()


func _rebuild_rigs() -> void:
	for r in _rigs:
		r.queue_free()
	_rigs.clear()
	if _orig != null:
		_orig.queue_free()
		_orig = null
	for c in _marks.get_children():
		c.queue_free()
	if people != "":
		_rebuild_people()
	else:
		var n := 4 if view == "sheet" else 1
		for i in n:
			var r := EliRig.new(variant)
			r.name = "Eli%d" % i
			if n > 1:
				r.position = Vector3((1.5 - i) * 0.95, 0.0, 0.0)
				r.rotation.y = [0.0, deg_to_rad(35.0), deg_to_rad(90.0), PI][i]
			r.set_meta("yaw", r.rotation.y)
			_stage.add_child(r)
			_rigs.append(r)
	if compare and _rigs.size() == 1:
		if people == "":
			_orig = VoxelRig.new(VoxelRig.Look.PLAYER)
			_orig.position = Vector3(0.6, 0.0, 0.0)
			_rigs[0].position = Vector3(-0.35, 0.0, 0.0)
		else:
			# Exp 011: seen from the front, Eli on the left (his right, +X), the
			# character on the right, the ruler beyond the character
			var gap := 0.62 if people == "brute" else 0.5
			_orig = EliRig.new(variant)
			_orig.name = "EliBeside"
			_orig.position = Vector3(gap, 0.0, 0.0)
			_rigs[0].position = Vector3(-gap, 0.0, 0.0)
		_orig.set_meta("yaw", 0.0)
		_stage.add_child(_orig)
	_ruler.visible = _orig != null and view != "gameplay"
	if _ruler.visible:
		(_ruler.get_node("Post") as Node3D).position = Vector3(minf(_rigs[0].position.x, _orig.position.x) - 0.75, 0.0, 0.0)
	_measure = 3
	_anim_t = 0.0
	_apply_anim()
	_measure_figures()


## Exp 011: a row (or grid) of an archetype's looks (one in comparison mode).
func _rebuild_people() -> void:
	var n := people_count if view != "sheet" else 4
	if compare and view != "sheet":
		n = 1
	var cols := people_cols if people_cols > 0 else n
	cols = mini(cols, n)
	var rows := ceili(float(n) / cols)
	for i in n:
		var seed := people_seed + (i if view != "sheet" else 0)
		var r := HumanoidLooks.make_rig(people, seed)
		r.name = "Person%d" % i
		var c := i % cols
		var row := i / cols
		var gap := 1.5 if people == "brute" else 0.95     # brutes are twice as broad
		r.position = Vector3((c - (cols - 1) * 0.5) * gap, 0.0, (row - (rows - 1) * 0.5) * 1.6)
		if view == "sheet":
			r.position = Vector3((1.5 - i) * gap, 0.0, 0.0)
			r.rotation.y = [0.0, deg_to_rad(35.0), deg_to_rad(90.0), PI][i]
		r.set_meta("yaw", r.rotation.y)
		_stage.add_child(r)
		var arch := HumanoidLooks.archetype(people)
		if arch != null and r is HumanoidRig:
			arch.extras(r)              # the brute's club, the bomber's pack (as in the game)
		_rigs.append(r)


func _all_rigs() -> Array:
	var rigs: Array = _rigs.duplicate()
	if _orig != null:
		rigs.append(_orig)
	return rigs


## Whether `r` plays Eli's animations (Eli, or the original figure beside him).
func _is_eli(r: VoxelRig) -> bool:
	return r is EliRig or (people == "" and r == _orig)


## The animation of Eli beside a person (comparison): the matching gait, else idle.
func _eli_anim() -> String:
	if people == "":
		return anim
	return anim if anim in ["idle", "walk", "jog", "run", "turn"] else "idle"


func _apply_anim() -> void:
	for r: VoxelRig in _all_rigs():
		r.rotation.y = r.get_meta("yaw", r.rotation.y)
		if _is_eli(r):
			var a := _eli_anim()
			r.speed = SPEEDS.get(a, 0.0)
			r.aiming = a == "handgun" or a == "shotgun"
			r.carry = a == "flashlight"
			r.set_held("flashlight" if a == "flashlight" else ("hammer" if a == "tool" else ""))
			if r is EliRig:
				(r as EliRig).preview_dir = Vector2(0.0, -1.0)
			_eli_gun(r, a)
			continue
		r.speed = PEOPLE_SPEEDS.get(anim, 0.0)
		r.swing = 0.0
		r.stagger = 0.0
		if r is HumanoidRig:
			var h := r as HumanoidRig
			h.preview_dir = Vector2(0.0, -1.0)
			if h.dead:
				h.dead = false
				h.transform.basis = Basis(Vector3.UP, _people_yaw(h))
				h.position.y = 0.0
		if r is ArchitectRig:
			var ar := r as ArchitectRig
			ar.observe = anim == "observe"
			ar.face_yaw = INF
	_anim_t = 0.0
	_say()


func _eli_gun(r: VoxelRig, a: String) -> void:
	var g: Node3D = r.gun
	if g == null:
		return
	var model := g.get_node_or_null(WeaponHandler.MODEL_NAME) as Node3D
	if a == "shotgun" and model == null:
		model = WeaponHandler.shotgun_model()
		g.add_child(model)
	if model != null:
		model.visible = a == "shotgun"
	if g.get_child_count() > 0:
		(g.get_child(0) as Node3D).visible = a != "shotgun"


func _apply_view(v: String) -> void:
	var was_sheet := view == "sheet"
	var was_game := view == "gameplay"
	view = v
	if (v == "sheet") != was_sheet or (v == "gameplay") != was_game or _rigs.is_empty():
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
	_measure_figures()
	_say()
	_refresh_panel()


## Exp 011: once the figures stand, measure them (the comparison's height
## marks) and, for tall figures or a comparison, frame the whole-body views.
func _measure_figures() -> void:
	var top := 0.0
	var x0 := INF
	var x1 := -INF
	for c in _marks.get_children():
		c.queue_free()
	for r: VoxelRig in _all_rigs():
		var h := _height(r)
		top = maxf(top, h)
		x0 = minf(x0, r.position.x - 0.35)
		x1 = maxf(x1, r.position.x + 0.35)
		if _ruler.visible:
			var mark := _box(_marks, Vector3(r.position.x, h, r.position.z), Vector3(0.42, 0.006, 0.006), _mark_mat())
			mark.name = "Top"
			var l := _label(_who(r) + "  %.2f m" % h, UiTheme.ACCENT)
			l.position = Vector3(r.position.x, h + 0.1, r.position.z)
			_marks.add_child(l)
	if _ruler.visible:
		x0 = minf(x0, (_ruler.get_node("Post") as Node3D).position.x - 0.35)
	# the panel covers the left of the screen: frame the comparison in the rest
	var pw := 0.0
	if _panel != null and _panel.visible and _ruler.visible and view in BODY_VIEWS:
		pw = (_panel.size.x + 16.0) / maxf(float(_vp.size.x), 1.0)
	var aspect0 := maxf(float(_vp.size.x) / maxf(float(_vp.size.y), 1.0), 1.0)
	_shift = pw * tan(deg_to_rad(_cam.fov * 0.5)) * aspect0
	if view in BODY_VIEWS and _dist_arg <= 0.0 and _ty_arg == INF and not _rigs.is_empty() and (top > 1.86 or _ruler.visible):
		var half := tan(deg_to_rad(_cam.fov * 0.5))
		var aspect := maxf(float(_vp.size.x) / maxf(float(_vp.size.y), 1.0), 1.0)
		var h_need := (top + (0.3 if _ruler.visible else 0.12)) * 0.5 / half
		var w_need := (x1 - x0 + 0.3) * 0.5 / (half * aspect * (1.0 - pw))
		_target.y = (top + (0.2 if _ruler.visible else 0.06)) * 0.5
		_target.x = (x0 + x1) * 0.5 if _ruler.visible else 0.0
		_dist = maxf(3.4, maxf(h_need, w_need)) * (1.12 if _ruler.visible else 1.0)


func _height(r: VoxelRig) -> float:
	var h := 0.0
	for mi: MeshInstance3D in r.parts:
		if is_instance_valid(mi) and mi.mesh != null and mi.is_inside_tree():
			h = maxf(h, (mi.global_transform * mi.get_aabb()).end.y)
	return h


func _who(r: VoxelRig) -> String:
	if r is EliRig:
		return "Eli"
	if r == _orig and people == "":
		return "Original"
	return _kind_name(people)


func _mark_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = UiTheme.ACCENT
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _process(delta: float) -> void:
	_anim_t += delta
	for r: VoxelRig in _all_rigs():
		var eli := _is_eli(r)
		var a := _eli_anim() if eli else anim
		var sp: float = SPEEDS.get(a, 0.0) if eli else PEOPLE_SPEEDS.get(a, 0.0)
		if moving and sp > 0.0:
			r.position.z -= delta * sp
			if r.position.z < -6.0:
				r.position.z = 6.0
		if a == "turn":
			_turn(r, delta)
		elif a == "observe" and r is ArchitectRig:
			(r as ArchitectRig).face_yaw = _yaw_to_camera(r) if view != "sheet" else INF
		if not eli:
			var h := r as HumanoidRig
			if h != null and _pose >= 0.0 and a in ["attack", "hit", "die"]:
				if a == "die":
					h.collapse(0.0, _pose, Vector3.LEFT, _people_yaw(h))
					continue
				h.swing = 1.0 - _pose if a == "attack" else 0.0
				h.stagger = 1.0 - _pose if a == "hit" else 0.0
				h.animate(delta)
				continue
			if _dormant != "":
				r.animate(delta)
				_pose_dormant(r, delta)
				continue
			if a == "die" and h != null:
				h.collapse(delta, fmod(_anim_t, 4.0), Vector3.LEFT, _people_yaw(h))
				if fmod(_anim_t, 4.0) < delta * 1.5 and h.dead:
					h.dead = false
					h.transform.basis = Basis(Vector3.UP, _people_yaw(h))
					h.position.y = 0.0
				continue
			if a == "attack" and fmod(_anim_t, 1.4) < delta:
				r.swing = 1.0
			if a == "hit" and fmod(_anim_t, 1.6) < delta:
				r.stagger = 1.0
				r.set_flash(1.0)
			r.swing = maxf(r.swing - delta / 0.5, 0.0)
		r.animate(delta)
	if _measure > 0:
		_measure -= 1
		if _measure == 0:
			_measure_figures()
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
	if _shift != 0.0:
		_cam.position -= _cam.transform.basis.x * _shift * _dist
	if _torch.visible:
		# held by the viewer: beside the camera, at most a few metres from the figures
		var hold := _target + dir * minf(_dist, 3.6)
		_torch.position = hold + _cam.transform.basis * Vector3(0.35, -0.25, 0.0)
		_torch.look_at(_target + Vector3(0.0, 0.25, 0.0), Vector3.UP)
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


## "Turn": a quarter turn and back every 5 s. The Architect turns his own
## controlled way (ArchitectRig.face_yaw); the others turn at a brisk rate
## (people shuffle their feet).
func _turn(r: VoxelRig, delta: float) -> void:
	var base: float = r.get_meta("yaw", 0.0)
	var goal := base + (deg_to_rad(100.0) if fmod(_anim_t, 5.0) < 2.5 else 0.0)
	if r is ArchitectRig:
		(r as ArchitectRig).face_yaw = goal
	else:
		r.rotation.y = move_toward(r.rotation.y, goal, delta * 3.0)


func _yaw_to_camera(r: Node3D) -> float:
	var d := _cam.position - r.position
	return atan2(-d.x, -d.z)


## The dormant behaviours' pose on a showroom person (a stand-in enemy body
## that only carries the rig; DormantMind.pose reads nothing else).
func _pose_dormant(h: VoxelRig, delta: float) -> void:
	var i := _rigs.find(h)
	if i < 0:
		return
	while _dorm.size() <= i:
		var m := DormantMind.new()
		var e := AIEnemy.new()
		_dorm.append([m, e])
	var m: DormantMind = _dorm[i][0]
	var e: AIEnemy = _dorm[i][1]
	e.rig = h
	m.state = _dormant
	m.tap_kind = "tap" if i % 2 == 0 else "scratch"
	m.set("_lean", 0.5 + 0.5 * sin(_anim_t * 2.4))
	m.set("_flick", maxf(sin(_anim_t * 5.0), 0.0))
	m.set("_t", _anim_t)
	m.pose(e, delta)


func _exit_tree_people() -> void:
	for d in _dorm:
		(d[1] as Node).free()
	_dorm.clear()


func _people_yaw(h: VoxelRig) -> float:
	return h.get_meta("yaw", h.rotation.y)


func _zoom(f: float) -> void:
	var lo := 0.6 if view != "gameplay" else 8.0
	var hi := 12.0 if view != "gameplay" else 32.0
	_dist = clampf(_dist * (1.0 + f), lo, hi)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE or (overlay and event.physical_keycode == KEY_F10):
			get_viewport().set_input_as_handled()
			close()
			return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if _panel != null and _panel.visible and _panel.get_global_rect().has_point(mb.position):
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
	_panel.position = Vector2(16, 16)
	add_child(_panel)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(_scroll)
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 5)
	_col.custom_minimum_size = Vector2(318, 0)
	_scroll.add_child(_col)
	_refresh_panel()
	_status = UiTheme.make_label("", UiTheme.FONT_SMALL, UiTheme.TEXT_DIM)
	_status.anchor_top = 1.0
	_status.anchor_bottom = 1.0
	_status.position = Vector2(24, -40)
	_status.offset_top = -40
	_status.offset_left = 24
	add_child(_status)
	_panel.visible = not _hide_ui
	_status.visible = not _hide_ui
	_say()


## Rebuilds the panel's contents for the current state (the selected
## buttons are highlighted). Cheap: no figure is rebuilt.
func _refresh_panel() -> void:
	if _col == null:
		return
	for c in _col.get_children():
		_col.remove_child(c)
		c.queue_free()
	_col.add_child(UiTheme.make_title("Character Showroom", 20))
	_col.add_child(UiTheme.make_caption(CAPTIONS.get(people, people.capitalize()), 310, UiTheme.TEXT_DIM))
	_col.add_child(UiTheme.make_section("Character"))
	_col.add_child(_grid(3, CHARACTERS.map(func(c): return [c[1], _set_people.bind(c[0], 0), c[0] == people])))
	if people == "" or HumanoidLooks.variety(people) > 1:
		_col.add_child(_grid(2, [["< Previous look", _step_look.bind(-1)], ["Next look >", _step_look.bind(1)]]))
	_col.add_child(UiTheme.make_section("Compare beside Eli"))
	var cmp := [["Off", _set_compare.bind(false, people), not compare]]
	for c in CHARACTERS.slice(1):
		cmp.append([c[1], _set_compare.bind(true, c[0]), compare and people == c[0]])
	cmp.append(["Original", _set_compare.bind(true, ""), compare and people == ""])
	_col.add_child(_grid(4, cmp))
	_col.add_child(UiTheme.make_section("Animation"))
	var list: Array = ANIMS if people == "" else (ARCHITECT_ANIMS if people == "architect" else PEOPLE_ANIMS)
	_col.add_child(_grid(3, list.map(func(a): return [a[1], _set_anim.bind(a[0]), anim == a[0] and _dormant == ""])))
	if people != "" and people != "architect":
		_col.add_child(UiTheme.make_caption("Dormant", 300, UiTheme.TEXT_FAINT))
		_col.add_child(_grid(3, DORMANT.map(func(d): return [d[1], _set_dormant.bind(d[0]), _dormant == d[0]])))
	var walk := UiTheme.make_toggle("Walk across the stage", moving)
	walk.custom_minimum_size.y = 30
	walk.toggled.connect(func(on: bool):
		moving = on
		for r: VoxelRig in _all_rigs():
			r.position.z = 0.0
		_target.z = 0.0)
	_col.add_child(walk)
	_col.add_child(UiTheme.make_section("View"))
	_col.add_child(_grid(3, VIEWS.map(func(v): return [v[1], _apply_view.bind(v[0]), view == v[0]])))
	_col.add_child(UiTheme.make_section("Light"))
	_col.add_child(_grid(3, LIGHTS.map(func(l): return [l[1], _set_light.bind(l[0]), light == l[0]])))
	_col.add_child(UiTheme.make_spacer(2))
	var back := UiTheme.make_button("Close" if overlay else "Back")
	back.name = "Back"
	back.custom_minimum_size.y = 32
	back.pressed.connect(close)
	_col.add_child(back)
	_fit_panel.call_deferred()


func _fit_panel() -> void:
	if _scroll == null or not is_inside_tree():
		return
	var vh := get_viewport_rect().size.y
	_scroll.custom_minimum_size = Vector2(326, minf(_col.get_combined_minimum_size().y, vh - 80.0))
	_panel.reset_size()


func _grid(cols: int, items: Array) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 4)
	for it in items:
		var b := Button.new()
		b.text = it[0]
		b.name = (it[0] as String).validate_node_name().replace(" ", "_")
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 28)
		b.add_theme_font_size_override("font_size", UiTheme.px(UiTheme.FONT_SMALL))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			b.add_theme_stylebox_override(st, _style(st))
		if it.size() > 2 and bool(it[2]):
			b.add_theme_stylebox_override("normal", _style("pressed"))
			b.add_theme_stylebox_override("hover", _style("pressed"))
			b.add_theme_color_override("font_color", UiTheme.TEXT)
		b.pressed.connect(it[1])
		g.add_child(b)
	return g


## Compact house-style button boxes (tighter margins than the menus').
func _style(state: String) -> StyleBoxFlat:
	if not _styles.has(state):
		var sb := UiTheme.button_style(state)
		sb.content_margin_left = 5
		sb.content_margin_right = 5
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		_styles[state] = sb
	return _styles[state]


func _set_anim(a: String) -> void:
	anim = a
	_dormant = ""
	_pose = -1.0
	_apply_anim()
	_refresh_panel()


func _set_dormant(d: String) -> void:
	anim = "idle"
	_dormant = d
	_apply_anim()
	_refresh_panel()


func _set_variant(i: int) -> void:
	variant = i
	for r: VoxelRig in _all_rigs():
		if r is EliRig:
			(r as EliRig).set_variant(i)
	_measure = 2
	_say()


func _step_look(d: int) -> void:
	if people == "":
		_set_variant(posmod(variant + d, EliSculpt.variant_count()))
	else:
		_set_people(people, people_seed + d * maxi(people_count if not compare else 1, 1))


## The character to show (an archetype kind; "" = Eli), from look `seed`.
## Kinds without an archetype file show their old figure.
func _set_people(kind: String, seed: int) -> void:
	if kind != "" and HumanoidLooks.variety(kind) <= 0 and not EnemyDefs.has(kind):
		return
	people = kind
	var n := HumanoidLooks.variety(kind) if kind != "" else 0
	people_seed = posmod(seed, n) if n > 0 else 0
	var list: Dictionary = SPEEDS if kind == "" else PEOPLE_SPEEDS
	if anim not in list or (anim == "observe" and kind != "architect"):
		anim = "idle"
	if kind == "" or kind == "architect":
		_dormant = ""
	_rebuild_rigs()
	_apply_view(view)


func _set_compare(on: bool, kind: String) -> void:
	compare = on
	if on:
		people_count = 1
	_set_people(kind, people_seed if kind == people else 0)


func _set_light(l: String) -> void:
	light = l
	_apply_light()
	_refresh_panel()


func _set_night(on: bool) -> void:
	_set_light("night" if on else "day")


func _kind_name(kind: String) -> String:
	if kind == "architect":
		return ArchitectIdentity.DEV_LABEL
	return "Eli" if kind == "" else kind.capitalize()


func _say() -> void:
	if _status == null:
		return
	var who := EliSculpt.variant_name(variant)
	if people != "":
		var l := HumanoidLooks.look(people, people_seed)
		who = _kind_name(people) + (" · " + str(l.get("name", "")) if not l.is_empty() else " · old figure")
		if HumanoidLooks.variety(people) > 1:
			who += " (look %d/%d)" % [people_seed + 1, HumanoidLooks.variety(people)]
	if compare:
		who += " · beside " + ("the original figure" if people == "" else "Eli")
	var a := anim if _dormant == "" else "dormant " + _dormant
	_status.text = "%s · %s · %s · %s     Drag / A D: turn   Wheel / W S: zoom   Esc: %s" % [
		who, a, view, light, "close" if overlay else "back"]


## Test access.
func rigs() -> Array:
	return _rigs


## The figure beside the character in comparison mode (null without one).
func beside() -> VoxelRig:
	return _orig
