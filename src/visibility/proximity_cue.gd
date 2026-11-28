extends CanvasLayer
## Exp 012 (V): the proximity sense (the user's §17). A very close enemy that
## Eli can't see (behind him, beside him) darkens one edge of the screen in a
## slow, soft pulse: the side it is on, never where it stands. FogOfWar sets
## `side` (a screen direction, roughly quantised) and `strength` (0..1); the
## pulse eases in and out. Purely visual; the enemy's own sounds still play.

const SHADER := """
shader_type canvas_item;
uniform vec2 side = vec2(0.0, 1.0);
uniform float amount = 0.0;
uniform vec4 tint : source_color = vec4(0.16, 0.0, 0.02, 1.0);
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float edge = clamp(max(abs(p.x), abs(p.y)), 0.0, 1.0);
	float toward = clamp(dot(normalize(p + vec2(0.0001)), side), -1.0, 1.0);
	float lobe = smoothstep(0.15, 1.0, toward);
	float rim = smoothstep(0.45, 1.0, edge) * (0.35 + 0.65 * smoothstep(0.7, 1.0, edge));
	COLOR = vec4(tint.rgb, amount * lobe * rim * 0.85);
}
"""

var side := Vector2(0, 1)              ## screen direction (x right, y down) of the sensed enemy
var strength := 0.0                    ## 0..1 wanted
var shown := 0.0                       ## eased
var pulses := 0                        ## times the cue became noticeable (tests)
var _rect: ColorRect
var _mat: ShaderMaterial
var _t := 0.0
var _on := false


func _ready() -> void:
	layer = 6
	_rect = ColorRect.new()
	_rect.name = "ProximityCue"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	_mat.shader = sh
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)


func _process(delta: float) -> void:
	_t += delta
	shown = move_toward(shown, strength, delta * (1.6 if strength > shown else 0.9))
	var on := shown > 0.02
	if on and not _on:
		pulses += 1
	_on = on
	_rect.visible = on
	if not on:
		return
	var pulse := 0.62 + 0.38 * sin(_t * 4.2)
	_mat.set_shader_parameter("side", side.normalized() if side.length() > 0.01 else Vector2(0, 1))
	_mat.set_shader_parameter("amount", shown * pulse)
