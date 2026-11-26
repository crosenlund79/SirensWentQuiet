class_name PoiSpot
extends Node3D
## Experiment 007 (P): one thing to use at a POI (the SPEC §7.3 interactable
## duck type: interact_prompt / interact / interact_reach). It stands where
## the player stands to use it. Kinds:
##   container  searchable furniture (data: the layout's container entry)
##   pickup     a loose item lying around (data: the layout's pickup entry)
##   wood       a fallen tree to chop (data: the layout's wood entry)
##   exit       "[E] Leave for home"
##   cargo      the car's boot (only when Eli came by car)
## The game's POI helper (game.poi, game_poi.gd) owns the rules; a spot only
## asks it (world.helper) for its prompt and hands it the interaction.
##
## Exp 008 (L): containers and loose items carry a small marker in the HUD's
## pixel style, shown by the helper (update_markers) while Eli is near and
## can see them: an amber square (not searched yet), a lock (needs a
## crowbar), a flashlight (too dark), a pale square with "3 left" (searched,
## something left) or a faint "searched" (empty). The one the prompt points
## at is brighter. interact_point() is where the thing itself is (the
## interaction finder's facing test).

## Exp 012 (L, §24): larger, smoother icons (MarkIcons) in a restrained
## modern style; the prompt's choice ("hot") is brighter and a little larger.
const MARK_ICONS := {"new": "search", "left": "left", "locked": "lock", "dark": "dark", "empty": "empty", "pickup": "take"}
const MARK_PIXEL := 0.0085            ## m per texture px (64 px icons: about 0.55 m, ~46 px on screen)
const MARK_HOT_SCALE := 1.22

var kind := "container"
var id := ""
var data := {}
var world: Node                 ## the PoiWorld
var front := Vector2.ZERO       ## containers: the way the piece faces (use it from that side)
var visual: Node3D              ## pickups: the item's mesh (hidden when taken)
var marker: Node3D              ## Exp 008 (L): the small sign over it (set_marker)
var marker_look := ""           ## "", "new", "locked", "dark", "left", "empty"
var _mark_key := ""


func setup(k: String, spot_id: String, at: Vector2, d: Dictionary, w: Node) -> void:
	kind = k
	id = spot_id
	data = d
	world = w
	name = "Spot_%s_%s" % [k, spot_id]
	position = Vector3(at.x, 0, at.y)
	if k == "container":
		front = PoiLayouts.FRONT.get(str(d.get("facing", "S")), Vector2(0, 1))


func plan_pos() -> Vector2:
	return Vector2(position.x, position.z)


func label() -> String:
	return str(data.get("label", kind))


## Exp 008 (L): where the thing itself is (a container's middle, a log's), as
## opposed to where Eli stands to use it (plan_pos).
func interact_point() -> Vector2:
	if kind == "container" and data.get("rect") is Rect2:
		return (data["rect"] as Rect2).get_center()
	if kind == "wood" and data.get("at") is Vector2:
		return data["at"]
	return plan_pos()


## Exp 008 (L): shows the marker as `look` ("" hides it; see the header) with
## an optional short tag; `hot` = the prompt points at it.
func set_marker(look: String, text := "", hot := false) -> void:
	var key := "%s|%s|%s" % [look, text, hot]
	if key == _mark_key:
		return
	_mark_key = key
	marker_look = look
	if look == "":
		if marker != null:
			marker.visible = false
		return
	if marker == null:
		_make_marker()
	marker.visible = true
	var icon: Sprite3D = marker.get_node("Icon")
	var tag: Label3D = marker.get_node("Tag")
	var tint: Color = {"new": UiTheme.ACCENT, "pickup": UiTheme.ACCENT, "locked": UiTheme.WARN, "dark": UiTheme.FROST, "left": UiTheme.TEXT}.get(look, UiTheme.TEXT_DIM)
	icon.visible = MARK_ICONS.has(look)
	if icon.visible:
		icon.texture = MarkIcons.texture(str(MARK_ICONS[look]))
		var a := 1.0 if hot else (0.72 if look != "empty" else 0.5)
		icon.modulate = Color(tint.lightened(0.15) if hot else tint, a)
	tag.text = text
	tag.visible = text != "" and (hot or look != "empty")      # "searched" only on the one Eli points at
	tag.modulate = Color(UiTheme.TEXT if look == "left" else UiTheme.TEXT_DIM, 1.0 if hot else 0.8)
	tag.position.y = 0.36 if icon.visible else 0.0
	marker.scale = Vector3.ONE * (MARK_HOT_SCALE if hot else 1.0)


func _make_marker() -> void:
	marker = Node3D.new()
	marker.name = "Marker"
	var over := interact_point() - plan_pos()
	var h := float(data.get("h", 1.0)) + 0.32 if kind == "container" else 0.5
	marker.position = Vector3(over.x, h, over.y)
	add_child(marker)
	var icon := Sprite3D.new()
	icon.name = "Icon"
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	icon.no_depth_test = true
	icon.shaded = false
	icon.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	icon.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	icon.pixel_size = MARK_PIXEL
	icon.render_priority = 2
	marker.add_child(icon)
	var tag := Label3D.new()
	tag.name = "Tag"
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.shaded = false
	tag.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	tag.font = UiTheme.font("bold")
	tag.font_size = 30
	tag.outline_size = 10
	tag.outline_modulate = Color(0, 0.01, 0.02, 0.8)
	tag.pixel_size = MARK_PIXEL * 0.8
	tag.render_priority = 2
	tag.outline_render_priority = 1
	marker.add_child(tag)


func _helper() -> Object:
	var h: Variant = world.get("helper") if world != null else null
	return h if h is Object and is_instance_valid(h) else null


func interact_prompt() -> String:
	var h := _helper()
	if h != null and h.has_method("prompt_for"):
		return str(h.prompt_for(self))
	match kind:
		"exit":
			return "[E] Leave for home"
		"cargo":
			return "[E] Car (cargo)"
		"pickup":
			return "[E] Pick up %s" % Items.name_of(str(data.get("item", ""))).to_lower()
		"wood":
			return "[E] Chop wood"
	return "[E] Search the %s" % label()


## Exp 008 (L): true while the helper's timed action (search, force, chop) is on this.
func interact_busy() -> bool:
	var h := _helper()
	return h != null and h.has_method("busy_with") and bool(h.busy_with(self))


func interact(game: Node) -> void:
	var h := _helper()
	if h == null and game != null:
		var p: Variant = game.get("poi")
		h = p if p is Object and is_instance_valid(p) else null
	if h != null and h.has_method("interact_spot"):
		h.interact_spot(self)


## Containers are used from their front (not through the wall behind them).
func interact_reach(p: Vector2) -> bool:
	if kind != "container":
		return true
	return (p - plan_pos()).dot(front) > -0.45
