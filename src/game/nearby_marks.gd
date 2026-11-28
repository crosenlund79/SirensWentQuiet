class_name NearbyMarks
extends Node3D
## Exp 012 (§24): the subtle "something usable is near" cue at home: a faint,
## still ring on the floor under each interactable within reach that Eli can
## see (the finder's in_sight list, so never through walls), except the
## current target, which has the stronger FocusRing. POIs have their own
## searchable markers (PoiSpot), so this is used at home only.

const COLOR := Color(0.92, 0.9, 0.84)
const ALPHA := 0.16
const RADIUS := 0.3
const MAX := 8

var _rings: Array[MeshInstance3D] = []
var _mat: StandardMaterial3D


## Shows faint rings under `nodes` (Node3D interactables near Eli) other than
## `focus`, within `reach` m of `from`; creates the game's one NearbyMarks.
static func show_for(game: Node, nodes: Array, focus: Node3D, from: Vector2, reach: float) -> void:
	if game == null or not game.is_inside_tree():
		return
	var m := game.get_node_or_null("NearbyMarks") as NearbyMarks
	if m == null:
		m = NearbyMarks.new()
		m.name = "NearbyMarks"
		game.add_child(m)
	m.place(nodes, focus, from, reach)


func _ready() -> void:
	top_level = true
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(COLOR, ALPHA)


func _ring() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.8
	tor.outer_radius = 1.0
	tor.rings = 28
	tor.ring_segments = 4
	mi.mesh = tor
	mi.scale = Vector3(RADIUS, 0.04, RADIUS)
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func place(nodes: Array, focus: Node3D, from: Vector2, reach: float) -> void:
	var used := 0
	for n in nodes:
		if used >= MAX:
			break
		if n == focus or not is_instance_valid(n) or not (n is Node3D) or not (n as Node3D).is_inside_tree():
			continue
		var g := (n as Node3D).global_position
		var at := Vector2(g.x, g.z)
		if n.has_method("interact_point"):
			at = n.interact_point()
		if at.distance_to(from) > reach:
			continue
		if used >= _rings.size():
			_rings.append(_ring())
		var r := _rings[used]
		r.global_position = Vector3(at.x, g.y + 0.035, at.y)
		r.visible = true
		used += 1
	for i in range(used, _rings.size()):
		_rings[i].visible = false
