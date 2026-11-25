class_name UiStatBar
extends Control
## Compact stat row: icon, thin bar and number (0..max). Owner: U.
## Turns amber at `warn_level` and red when empty (health: red at warn_level),
## and pulses gently while warning. The bar eases toward new values.
##   var bar := UiTheme.make_stat_bar("food", "Food")
##   bar.set_value(state.hunger)

const ICON := 12.0      ## Exp 006 (U): the pixel icons' native size
const NUMBER_W := 30.0

@export var kind := "health":
	set(v):
		kind = v
		queue_redraw()
@export var label := ""
@export var max_value := 100.0
@export var warn_level := SurvivalTuning.WARN_LEVEL
@export var show_number := true

var value := 100.0
var _shown := 100.0
var _pulse := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(196, 18)


func set_value(v: float, instant := false) -> void:
	value = clampf(v, 0.0, max_value)
	if instant:
		_shown = value
	queue_redraw()


## "normal" | "warn" | "critical"
func level() -> String:
	if value <= 0.0 or (kind == "health" and value <= warn_level):
		return "critical"
	if value <= warn_level:
		return "warn"
	return "normal"


func level_color() -> Color:
	match level():
		"critical":
			return UiTheme.BAD
		"warn":
			return UiTheme.WARN
	return UiTheme.TEXT


func _process(delta: float) -> void:
	var redraw := false
	if absf(_shown - value) > 0.05:
		_shown = move_toward(_shown, value, maxf(absf(value - _shown) * 6.0, 8.0) * delta)
		redraw = true
	if level() != "normal":
		_pulse = fmod(_pulse + delta * 1.6, 1.0)
		redraw = true
	elif _pulse != 0.0:
		_pulse = 0.0
		redraw = true
	if redraw:
		queue_redraw()


func _draw() -> void:
	var h := size.y
	var col := level_color()
	var glow := 1.0
	if level() != "normal":
		glow = 0.7 + 0.3 * (0.5 + 0.5 * cos(_pulse * TAU))
	var icon_col := Color(col, glow) if level() != "normal" else Color(UiTheme.TEXT, 0.9)
	var ir := Rect2(Vector2(0, roundf((h - ICON) * 0.5)), Vector2(ICON, ICON))
	UiIcons.paint(self, kind, Rect2(ir.position + Vector2(1.0, 1.0), ir.size), Color(0, 0, 0, 0.5))   # Exp 006 (U): hard pixel shadow
	UiIcons.paint(self, kind, ir, icon_col)
	var x0 := ICON + 8.0
	var x1 := size.x - (NUMBER_W + 6.0 if show_number else 0.0)
	var bh := 6.0
	var y := roundf((h - bh) * 0.5)
	var track := Rect2(x0, y, maxf(x1 - x0, 4.0), bh)
	draw_rect(track.grow(1.0), Color(0, 0, 0, 0.35))
	draw_rect(track, Color(1, 1, 1, 0.1))
	var f := clampf(_shown / maxf(max_value, 0.001), 0.0, 1.0)
	if f > 0.0:
		var fill_col := Color(col, 0.9 * glow) if level() != "normal" else Color(UiTheme.TEXT, 0.82)
		draw_rect(Rect2(track.position, Vector2(track.size.x * f, bh)), fill_col)
	# warning tick at warn_level
	var tx := track.position.x + track.size.x * clampf(warn_level / maxf(max_value, 0.001), 0.0, 1.0)
	draw_line(Vector2(tx, y - 2), Vector2(tx, y + bh + 2), Color(1, 1, 1, 0.22), 1.0)
	if show_number:
		var font := UiTheme.font()          # Exp 006 (U): Pixel Operator
		var fs := UiTheme.FONT_SMALL
		var text := str(int(ceil(value)))
		var pos := Vector2(size.x - NUMBER_W, roundf(h * 0.5 + fs * 0.32))
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_RIGHT, NUMBER_W, fs, 4, Color(0, 0, 0, 0.6))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_RIGHT, NUMBER_W, fs, col if level() != "normal" else UiTheme.TEXT)
