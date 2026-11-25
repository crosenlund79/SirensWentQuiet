extends CanvasLayer
## Experiment 005 (V): the level indicator, a small HUD card at the top right
## that always says which storey you're on ("Level +1 · First upper floor").
## In build mode it grows prominent (amber border, larger) and names the
## storey being built on, with the PageUp / PageDown hint; when that isn't
## the player's own storey it says so ("you are on Level 0"). It sits under
## the HUD's CHEATS badge when that shows. Updates on the level helper's
## signals and build mode changes (cheap; a short check each frame for the
## badge's height and the mode).

var levels: Node                       ## game_levels.gd

var _card: PanelContainer
var _style: StyleBoxFlat
var _title: Label
var _sub: Label
var _key := ""


func _init() -> void:
	layer = 41


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_card = PanelContainer.new()
	_card.name = "LevelCard"
	_style = StyleBoxFlat.new()
	_style.bg_color = UiTheme.BG_SOFT
	_style.set_corner_radius_all(6)
	_style.set_border_width_all(1)
	_style.border_color = UiTheme.LINE
	_style.content_margin_left = 12
	_style.content_margin_right = 12
	_style.content_margin_top = 6
	_style.content_margin_bottom = 6
	_card.add_theme_stylebox_override("panel", _style)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_card.offset_right = -20
	_card.offset_left = -20
	_card.offset_top = 18
	root.add_child(_card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(col)
	_title = UiTheme.make_hud_label("", 15, UiTheme.TEXT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(_title)
	_sub = UiTheme.make_hud_label("", 12, UiTheme.TEXT_DIM)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(_sub)
	refresh()


func _process(_delta: float) -> void:
	refresh()


## Rebuilds the texts when the storey, the viewed storey or the mode changed.
func refresh() -> void:
	if levels == null or _card == null:
		return
	var hud = levels.game.get("hud") if levels.game != null else null
	var shown: bool = hud == null or not is_instance_valid(hud) or str(hud.get("mode")) != "hidden"
	if _card.visible != shown:
		_card.visible = shown
	var building: bool = levels._building()
	var p: int = levels.player_storey
	var v: int = levels.view_storey
	var built: bool = levels.world_of(v) != null
	_place_below_badge()
	var key := "%d|%d|%s|%s" % [p, v, building, built]
	if key == _key:
		return
	_key = key
	if not building:
		_title.text = Levels.label(p)
		_title.add_theme_font_size_override("font_size", UiTheme.px(15))
		_sub.visible = false
		_style.border_color = UiTheme.LINE
		_style.set_border_width_all(1)
		_title.add_theme_color_override("font_color", UiTheme.TEXT)
		return
	_title.text = "Building on " + Levels.label(v)
	_title.add_theme_font_size_override("font_size", UiTheme.px(19))
	_title.add_theme_color_override("font_color", UiTheme.ACCENT)
	_style.border_color = UiTheme.ACCENT
	_style.set_border_width_all(2)
	var lines := PackedStringArray()
	if not built:
		lines.append("Not built yet: " + ("Next storey (key 2, Floors) builds it" if v > 0 else "Excavate (key 2, Floors) digs it"))   # Exp 006 (U): the menu's Floors key
	if v != p:
		lines.append("You are on " + Levels.label(p))
	lines.append("PgUp / PgDn: change level")
	_sub.text = "\n".join(lines)
	_sub.visible = true


## Under the HUD's CHEATS badge when it shows (top right as well).
func _place_below_badge() -> void:
	var top := 18.0
	var hud = levels.game.get("hud") if levels.game != null else null
	if hud != null and is_instance_valid(hud):
		var badge = hud.get("_badge")
		if badge is Control and (badge as Control).visible:
			top = (badge as Control).get_global_rect().end.y + 8.0
	if absf(_card.offset_top - top) > 0.5:
		_card.offset_top = top


## Test access.
func text() -> String:
	return _title.text + ("\n" + _sub.text if _sub.visible else "")
