extends CanvasLayer
## Exp 007 (O): the look-through view's screen: a dark keyhole mask with a
## small soft round opening in the middle (the narrow view), and a hint line.
## The 3D view itself is the holes helper's own Camera3D at the hole.

const MASK := """
shader_type canvas_item;
uniform float radius = 0.26;      // of the screen height
uniform float soft = 0.06;
uniform float aspect = 1.777;
void fragment() {
	vec2 p = (UV - vec2(0.5)) * vec2(aspect, 1.0);
	float d = length(p);
	float a = smoothstep(radius - soft, radius + soft * 0.4, d);
	// a faint dark rim inside the opening: the hole's own edge
	float rim = smoothstep(radius - soft * 2.5, radius - soft, d) * 0.35;
	COLOR = vec4(0.0, 0.0, 0.0, clamp(max(a, rim), 0.0, 1.0));
}
"""

var mask: ColorRect
var hint: Label
var _mat: ShaderMaterial


func _ready() -> void:
	layer = 6
	process_mode = Node.PROCESS_MODE_ALWAYS
	mask = ColorRect.new()
	mask.name = "Keyhole"
	mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = MASK
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	mask.material = _mat
	add_child(mask)
	hint = UiTheme.make_hud_label("Looking through the hole · mouse: look around · E / Esc: stop · F: cover it", UiTheme.FONT_SMALL, UiTheme.TEXT_DIM)
	hint.name = "Hint"
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.offset_bottom = -28
	add_child(hint)
	_fit()


func _process(_delta: float) -> void:
	_fit()


func _fit() -> void:
	var vp := get_viewport()
	if vp == null or _mat == null:
		return
	var s := vp.get_visible_rect().size
	if s.y > 0.0:
		_mat.set_shader_parameter("aspect", s.x / s.y)
