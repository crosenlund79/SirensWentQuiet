class_name UiIcon
extends Control
## A Control that shows one UiIcons glyph. Owner: U.
##   var moon := UiTheme.make_icon("moon", 20)

@export var kind := "dot":
	set(v):
		kind = v
		queue_redraw()
@export var color := UiTheme.TEXT:
	set(v):
		color = v
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	# soft dark halo so the glyph reads over bright daylight
	UiIcons.paint(self, kind, Rect2(Vector2(0.6, 1.0), size), Color(0, 0, 0, 0.45 * color.a))
	UiIcons.paint(self, kind, Rect2(Vector2.ZERO, size), color)
