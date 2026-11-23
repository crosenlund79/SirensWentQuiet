class_name GameHud
extends CanvasLayer
## In-game HUD (SPEC §7.8). Owner: U. Foundation stub: plain labels.

var state: GameState
var _top: Label
var _prompt: Label
var _toast: Label
var _banner: Label
var _toast_t := 0.0
var mode := "play"


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_top = UiTheme.make_label("", 16)
	_top.position = Vector2(20, 14)
	add_child(_top)
	_prompt = UiTheme.make_label("", 18, UiTheme.ACCENT)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position += Vector2(-120, -120)
	add_child(_prompt)
	_toast = UiTheme.make_label("", 17)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position += Vector2(-160, 60)
	add_child(_toast)
	_banner = UiTheme.make_label("", 20, UiTheme.BAD)
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.position += Vector2(-160, 24)
	add_child(_banner)


func setup(s: GameState) -> void:
	state = s


func set_prompt(text: String) -> void:
	if _prompt != null:
		_prompt.text = text


func toast(text: String, _kind := "info") -> void:
	if _toast != null:
		_toast.text = text
		_toast_t = 3.0


func set_banner(text: String) -> void:
	if _banner != null:
		_banner.text = text


func set_mode(m: String) -> void:
	mode = m


func _process(delta: float) -> void:
	_toast_t -= delta
	if _toast_t <= 0.0 and _toast != null:
		_toast.text = ""
	if state != null and _top != null:
		var cheats := []
		for k in state.cheats:
			if state.cheats[k]:
				cheats.append(k)
		_top.text = "Day %d  %s   HP %d  Food %d  Water %d  Energy %d   Ammo %d%s" % [state.day(), state.clock_text(),
			state.health, state.hunger, state.hydration, state.energy, state.inventory.count("ammo"),
			("   CHEATS: " + ", ".join(cheats)) if not cheats.is_empty() else ""]
