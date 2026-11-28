class_name GraphicsQuality
extends RefCounted
## Experiment 012 (§32, §33): graphics presets and the frame-rate display.
## Static (no Autoload): GameSettings stores the choice ("quality",
## "show_fps") and calls apply(); a small runtime node on the scene tree's
## root (made on the first apply, kept across scene changes) applies the
## preset to every light, environment, camera and the snowfall that enters
## the tree later, and draws the frame-rate overlay in the game and menus.
##
##   GraphicsQuality.set_preset("low")        # applies live and saves the setting
##   GraphicsQuality.set_show_fps(true)       # the overlay (Settings, F3, F10)
##   GraphicsQuality.preset()                 # "low" | "medium" | "high" | "ultra"
##
## What a preset changes: 3D render scale (FSR below 1), MSAA / FXAA,
## directional shadow atlas, distance and splits, soft-shadow filter
## quality, the positional shadow atlas, shadows of lamps and practicals
## (Low: off, except the flashlight's), SSAO and glow, the snowfall's
## density, camera far plane and mesh LOD. It never changes fog, light
## energies, the x-ray silhouettes, enemies, items or anything that decides
## what can be seen in play; the far plane stays well beyond the furthest
## ground the game camera shows (~45 m at the widest zoom).

const PRESETS := ["low", "medium", "high", "ultra"]
const NAMES := {"low": "Low", "medium": "Medium", "high": "High", "ultra": "Ultra"}
const DEFAULT := "high"

const P := {
	"low": {"scale": 0.75, "msaa": Viewport.MSAA_DISABLED, "fxaa": true, "dir_atlas": 2048, "shadow_dist": 30.0,
		"splits": DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, "soft": RenderingServer.SHADOW_QUALITY_HARD,
		"pos_atlas": 2048, "lamp_shadows": false, "ssao": false, "glow": false, "snow": 0.35, "far": 90.0, "lod": 2.0},
	"medium": {"scale": 0.9, "msaa": Viewport.MSAA_DISABLED, "fxaa": true, "dir_atlas": 4096, "shadow_dist": 40.0,
		"splits": DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "soft": RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
		"pos_atlas": 4096, "lamp_shadows": true, "ssao": false, "glow": true, "snow": 0.65, "far": 110.0, "lod": 1.5},
	"high": {"scale": 1.0, "msaa": Viewport.MSAA_4X, "fxaa": false, "dir_atlas": 4096, "shadow_dist": 48.0,
		"splits": DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "soft": RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		"pos_atlas": 4096, "lamp_shadows": true, "ssao": true, "glow": true, "snow": 1.0, "far": 120.0, "lod": 1.0},
	"ultra": {"scale": 1.0, "msaa": Viewport.MSAA_8X, "fxaa": false, "dir_atlas": 8192, "shadow_dist": 60.0,
		"splits": DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "soft": RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
		"pos_atlas": 8192, "lamp_shadows": true, "ssao": true, "glow": true, "snow": 1.3, "far": 140.0, "lod": 0.5},
}

static var _applied := ""
static var applies := 0                ## how many times a preset was applied (tests)


static func preset() -> String:
	var q := str(GameSettings.get_value("quality"))
	return q if P.has(q) else DEFAULT


static func settings() -> Dictionary:
	return P[preset()]


## Chooses a preset, applies it at once and saves the setting.
static func set_preset(q: String) -> void:
	if not P.has(q):
		return
	GameSettings.set_value("quality", q)
	GameSettings.save_settings()


static func show_fps() -> bool:
	return bool(GameSettings.get_value("show_fps"))


## The frame-rate overlay on or off (saved unless `save` is false: F3,
## kept for the session; the settings panel saves it when it closes).
static func set_show_fps(on: bool, save := true) -> void:
	GameSettings.set_value("show_fps", on)
	if save:
		GameSettings.save_settings()
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		_runtime(tree)


## Applies the current preset to the running engine and every node in the
## tree (GameSettings calls it; cheap enough to call again at any time).
static func apply() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var s := settings()
	var vp := tree.root
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if float(s["scale"]) < 0.999 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = float(s["scale"])
	vp.msaa_3d = s["msaa"]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if bool(s["fxaa"]) else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.positional_shadow_atlas_size = int(s["pos_atlas"])
	vp.mesh_lod_threshold = float(s["lod"])
	RenderingServer.directional_shadow_atlas_set_size(int(s["dir_atlas"]), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(s["soft"])
	RenderingServer.positional_soft_shadow_filter_set_quality(s["soft"])
	_applied = preset()
	applies += 1
	_runtime(tree)
	_walk(tree.root)


## The preset's changes to one node (lights, environments, cameras, snow).
static func apply_node(n: Node) -> void:
	var s := settings()
	if n is WorldEnvironment:
		var e := (n as WorldEnvironment).environment
		if e != null:
			if not e.has_meta("gq_ssao"):
				e.set_meta("gq_ssao", e.ssao_enabled)
				e.set_meta("gq_glow", e.glow_enabled)
			e.ssao_enabled = bool(e.get_meta("gq_ssao")) and bool(s["ssao"])
			e.glow_enabled = bool(e.get_meta("gq_glow")) and bool(s["glow"])
	elif n is DirectionalLight3D:
		var d := n as DirectionalLight3D
		if not d.has_meta("gq_dist"):
			d.set_meta("gq_dist", d.directional_shadow_max_distance)
			d.set_meta("gq_mode", d.directional_shadow_mode)
		d.directional_shadow_max_distance = float(d.get_meta("gq_dist")) * float(s["shadow_dist"]) / 48.0     # High = as made
		d.directional_shadow_mode = s["splits"] if int(d.get_meta("gq_mode")) != DirectionalLight3D.SHADOW_ORTHOGONAL else DirectionalLight3D.SHADOW_ORTHOGONAL
	elif n is OmniLight3D or n is SpotLight3D:
		var l := n as Light3D
		if not l.has_meta("gq_shadow"):
			l.set_meta("gq_shadow", l.shadow_enabled)
		# the flashlight (and the gun light in the demos) keeps its shadow: it shapes what Eli sees
		var beam := l is SpotLight3D and (str(l.name) == "Flashlight" or l.get_parent() is VoxelPlayer)
		l.shadow_enabled = bool(l.get_meta("gq_shadow")) and (bool(s["lamp_shadows"]) or beam)
	elif n is CPUParticles3D and str(n.name) == "Snowfall":
		var p := n as CPUParticles3D
		if not p.has_meta("gq_amount"):
			p.set_meta("gq_amount", p.amount)
		var want := maxi(int(round(float(p.get_meta("gq_amount")) * float(s["snow"]))), 16)
		if p.amount != want:
			p.amount = want
	elif n is VoxelCamera:
		(n as Camera3D).far = float(s["far"])


static func _walk(n: Node) -> void:
	apply_node(n)
	for c in n.get_children():
		_walk(c)


## The runtime node on the root: applies the preset to nodes entering the
## tree and draws the frame-rate overlay.
static func _runtime(tree: SceneTree) -> Node:
	var r := tree.root.get_node_or_null("GraphicsRuntime")
	if r == null:
		r = Runtime.new()
		r.name = "GraphicsRuntime"
		tree.root.add_child.call_deferred(r)
	return r


## The overlay's text (also F10): fps, this frame's time, the worst frame of the last ~2 s.
static func fps_text() -> String:
	return "%d fps · %.1f ms · worst %.0f ms" % [Engine.get_frames_per_second(), Runtime.frame_ms, Runtime.worst_ms]


class Runtime extends CanvasLayer:
	static var frame_ms := 0.0
	static var worst_ms := 0.0
	var _label: Label
	var _last := 0
	var _window: Array[float] = []
	var _t := 0.0

	func _ready() -> void:
		layer = 120
		process_mode = Node.PROCESS_MODE_ALWAYS
		get_tree().node_added.connect(_on_node_added)
		var panel := PanelContainer.new()
		panel.name = "Fps"
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		panel.anchor_left = 1.0
		panel.anchor_right = 1.0
		panel.offset_left = -236.0
		panel.offset_right = -8.0
		panel.offset_top = 54.0
		panel.offset_bottom = 78.0
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.06, 0.07, 0.72)
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		panel.add_theme_stylebox_override("panel", sb)
		_label = Label.new()
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_label.add_theme_font_size_override("font_size", 13)
		_label.add_theme_color_override("font_color", Color(0.86, 0.89, 0.9))
		_label.add_theme_font_override("font", UiTheme.font())
		panel.add_child(_label)
		add_child(panel)
		_last = Time.get_ticks_usec()

	func _on_node_added(n: Node) -> void:
		if n is WorldEnvironment or n is Light3D or n is VoxelCamera or (n is CPUParticles3D and str(n.name) == "Snowfall"):
			GraphicsQuality.apply_node(n)

	func _process(delta: float) -> void:
		var now := Time.get_ticks_usec()
		frame_ms = float(now - _last) / 1000.0
		_last = now
		_window.append(frame_ms)
		if _window.size() > 120:
			_window.pop_front()
		_t += delta
		var on := GraphicsQuality.show_fps()
		(_label.get_parent() as Control).visible = on
		if _t >= 0.25:
			_t = 0.0
			worst_ms = 0.0
			for f in _window:
				worst_ms = maxf(worst_ms, f)
			if on:
				_label.text = GraphicsQuality.fps_text()
