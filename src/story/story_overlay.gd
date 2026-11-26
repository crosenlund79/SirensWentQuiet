class_name StoryOverlay
extends Node
## Exp 012 (S): what the story puts on the screen.
##   - the darkness of the night scenes (a near-black room with a vignette),
##     the gas's green tint and the disorientation (a wavering double image);
##   - subtitles: his lines (voice) and Eli's thoughts (italic, cold);
##   - the choice after the last encounter: keep the ropes or burn them
##     (a clear card, not a modal: the game goes on behind it).
## Three canvas layers: the darkness under the screen fade, the subtitles over
## it (readable on black), the choice card over the HUD.

signal keep_pressed
signal burn_pressed

const DARK_LAYER := 78                 ## under the dev menu (80) and the fade (85)
const SUB_LAYER := 86                  ## over the fade
const CHOICE_LAYER := 45               ## over the HUD (40), under the panels (70)
const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float dark = 0.0;
uniform float vignette = 0.0;
uniform vec4 tint : source_color = vec4(0.42, 0.72, 0.3, 1.0);
uniform float tint_amount = 0.0;
uniform float wobble = 0.0;
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 wv = vec2(sin(uv.y * 13.0 + TIME * 1.6), cos(uv.x * 10.0 + TIME * 1.2)) * 0.006 * wobble;
	vec3 c = texture(screen_tex, uv + wv).rgb;
	vec3 c2 = texture(screen_tex, uv + wv + vec2(0.014, 0.005) * wobble * (0.6 + 0.4 * sin(TIME * 0.9))).rgb;
	c = mix(c, c2, 0.4 * clamp(wobble, 0.0, 1.0));
	c = mix(c, c * tint.rgb * 1.7 + tint.rgb * 0.06, clamp(tint_amount, 0.0, 1.0));
	float d = distance(UV, vec2(0.5));
	float v = smoothstep(0.2, 0.75, d) * vignette;
	COLOR = vec4(c * (1.0 - dark) * (1.0 - v), 1.0);
}
"""

var subtitle := ""                     ## the line on screen now (tests)
var sub_kind := ""                     ## "voice" | "thought"
var said: Array[String] = []           ## every line shown (tests)
var dark := 0.0
var gas := 0.0
var wobble := 0.0
var _dark_layer: CanvasLayer
var _rect: ColorRect
var _mat: ShaderMaterial
var _sub_layer: CanvasLayer
var _sub_panel: PanelContainer
var _sub_label: Label
var _sub_until := -1.0
var _choice_layer: CanvasLayer
var _choice: PanelContainer
var _burn: Button
var _keep: Button
var _reason: Label
var _t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dark_layer = CanvasLayer.new()
	_dark_layer.layer = DARK_LAYER
	add_child(_dark_layer)
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_rect.material = _mat
	_rect.visible = false
	_dark_layer.add_child(_rect)
	_sub_layer = CanvasLayer.new()
	_sub_layer.layer = SUB_LAYER
	add_child(_sub_layer)
	var anchor := Control.new()
	anchor.set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub_layer.add_child(anchor)
	_sub_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_sub_panel.add_theme_stylebox_override("panel", sb)
	_sub_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub_panel.anchor_left = 0.5
	_sub_panel.anchor_right = 0.5
	_sub_panel.anchor_top = 1.0
	_sub_panel.anchor_bottom = 1.0
	_sub_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_sub_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_sub_panel.offset_bottom = -96
	_sub_panel.visible = false
	anchor.add_child(_sub_panel)
	_sub_label = UiTheme.make_label("", UiTheme.FONT_LARGE + 2, UiTheme.TEXT)
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub_label.custom_minimum_size.x = 640
	_sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub_panel.add_child(_sub_label)
	_build_choice()


# --- darkness, gas, disorientation -------------------------------------------------------------

func set_dark(a: float, vignette := 0.8) -> void:
	dark = clampf(a, 0.0, 1.0)
	_mat.set_shader_parameter("dark", dark)
	_mat.set_shader_parameter("vignette", vignette * (1.0 if dark > 0.0 else 0.0))
	_sync_rect()


func set_gas(a: float) -> void:
	gas = clampf(a, 0.0, 1.0)
	_mat.set_shader_parameter("tint_amount", gas)
	_sync_rect()


func set_wobble(a: float) -> void:
	wobble = clampf(a, 0.0, 1.5)
	_mat.set_shader_parameter("wobble", wobble)
	_sync_rect()


func reset() -> void:
	set_dark(0.0)
	set_gas(0.0)
	set_wobble(0.0)
	clear()


func _sync_rect() -> void:
	_rect.visible = dark > 0.001 or gas > 0.001 or wobble > 0.001


# --- subtitles ---------------------------------------------------------------------------------

## Shows a line: "voice" (his) or "thought" (Eli's); `seconds` > 0 clears it after.
func say(text: String, kind := "voice", seconds := -1.0) -> void:
	subtitle = text
	sub_kind = kind
	said.append(text)
	_sub_label.text = text
	var thought := kind == "thought"
	_sub_label.add_theme_color_override("font_color", UiTheme.FROST if thought else UiTheme.TEXT)
	_sub_label.add_theme_font_override("font", _italic() if thought else UiTheme.font("regular"))
	_sub_panel.visible = text != ""
	_sub_until = _t + seconds if seconds > 0.0 else -1.0


func clear() -> void:
	subtitle = ""
	_sub_panel.visible = false
	_sub_until = -1.0


static var _italic_font: Font


static func _italic() -> Font:
	if _italic_font == null:
		var f := FontVariation.new()
		f.base_font = UiTheme.font("regular")
		f.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(0.22, 1.0), Vector2.ZERO)
		_italic_font = f
	return _italic_font


# --- the ropes: keep or burn -------------------------------------------------------------------

func _build_choice() -> void:
	_choice_layer = CanvasLayer.new()
	_choice_layer.layer = CHOICE_LAYER
	add_child(_choice_layer)
	var anchor := Control.new()
	anchor.set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choice_layer.add_child(anchor)
	_choice = UiTheme.make_card()
	_choice.anchor_left = 0.5
	_choice.anchor_right = 0.5
	_choice.anchor_top = 1.0
	_choice.anchor_bottom = 1.0
	_choice.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_choice.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_choice.offset_bottom = -150
	_choice.visible = false
	anchor.add_child(_choice)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_choice.add_child(v)
	v.add_child(UiTheme.make_icon_label("rope", "The ropes", UiTheme.FONT_LARGE, UiTheme.TEXT, 24.0))
	v.add_child(UiTheme.make_caption("Four lengths of rope. Keep them, or burn them in the fireplace.", 380))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	_keep = UiTheme.make_button("Keep them")
	_keep.name = "KeepRopes"
	_keep.focus_mode = Control.FOCUS_NONE
	_keep.pressed.connect(func(): keep_pressed.emit())
	h.add_child(_keep)
	_burn = UiTheme.make_button("Burn them")
	_burn.name = "BurnRopes"
	_burn.focus_mode = Control.FOCUS_NONE
	_burn.pressed.connect(func(): burn_pressed.emit())
	h.add_child(_burn)
	_reason = UiTheme.make_caption("", 380, UiTheme.WARN)
	v.add_child(_reason)


## Shows (or updates) the choice; `why_not` = why burning isn't possible ("" = it is).
func show_choice(why_not: String) -> void:
	_choice.visible = true
	_burn.disabled = why_not != ""
	_reason.text = why_not
	_reason.visible = why_not != ""


func hide_choice() -> void:
	_choice.visible = false


func choice_visible() -> bool:
	return _choice.visible


func burn_enabled() -> bool:
	return _choice.visible and not _burn.disabled


func _process(delta: float) -> void:
	_t += delta
	if _sub_until > 0.0 and _t >= _sub_until:
		clear()
