class_name ShotTraces
extends MeshInstance3D
## Exp 013: F10 "Shot trajectories": every pellet's line from the muzzle to
## where it stopped stays drawn for a few seconds (yellow: hit an enemy, white:
## a wall or object, grey: flew out of the area). One per world, reused.

const LIFE := 3.0
const MAX := 64

var _lines: Array = []            ## [from, to, colour, age]
var _mesh := ImmediateMesh.new()


static func add(world: Node3D, from: Vector3, to: Vector3, kind: String) -> void:
	if world == null or not world.is_inside_tree():
		return
	var t := world.get_node_or_null("ShotTraces") as ShotTraces
	if t == null:
		t = ShotTraces.new()
		t.name = "ShotTraces"
		world.add_child(t)
	var c := Color(1.0, 0.85, 0.2) if kind == "enemy" else (Color(0.55, 0.55, 0.6) if kind == "none" else Color(0.95, 0.95, 0.95))
	t._lines.append([from, to, c, 0.0])
	if t._lines.size() > MAX:
		t._lines.pop_front()


func _ready() -> void:
	top_level = true
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material_override = m


func _process(delta: float) -> void:
	_mesh.clear_surfaces()
	var keep := []
	for l in _lines:
		l[3] += delta
		if l[3] < LIFE:
			keep.append(l)
	_lines = keep
	if _lines.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for l in _lines:
		var c: Color = l[2]
		c.a = 1.0 - float(l[3]) / LIFE
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(l[0])
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(l[1])
	_mesh.surface_end()
