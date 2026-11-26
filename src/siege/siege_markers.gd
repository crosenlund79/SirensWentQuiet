class_name SiegeMarkers
extends Node3D
## Exp 012 (G): F10 tactic debug markers. A line from each siege member to its
## goal and a small diamond at the goal, coloured by tactic, and a tag over
## the member's head. Developer only; never saved; drawn on top of everything.

const COLORS := {
	"encircle": Color(0.45, 0.7, 1.0), "breach": Color(1.0, 0.25, 0.2), "contain": Color(1.0, 0.85, 0.2),
	"trap": Color(0.8, 0.35, 1.0), "pressure": Color(1.0, 0.55, 0.1), "engage": Color(1.0, 1.0, 1.0),
	"wait": Color(0.6, 0.6, 0.6), "work": Color(0.3, 1.0, 0.5),
}
const Y := 0.12

var _mesh := ImmediateMesh.new()
var _tags := {}                  ## enemy instance id -> Label3D


func _ready() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Lines"
	mi.mesh = _mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = true
	m.render_priority = 10
	mi.material_override = m
	add_child(mi)


static func color_of(tactic: String) -> Color:
	return COLORS.get(tactic, Color(0.8, 0.8, 0.8))


## entries: [{"enemy": AIEnemy, "tactic": String, "goal": Vector2 (INF = none)}]
func draw(entries: Array) -> void:
	_mesh.clear_surfaces()
	var seen := {}
	var lines := []
	for en in entries:
		var e = en["enemy"]
		if not is_instance_valid(e) or not e.alive:
			continue
		var c := color_of(str(en["tactic"]))
		var p: Vector3 = e.global_position
		seen[e.get_instance_id()] = true
		_tag(e, str(en["tactic"]), c)
		var g: Vector2 = en["goal"]
		if g != Vector2.INF:
			var y := p.y + Y
			lines.append([Vector3(p.x, y, p.z), Vector3(g.x, y, g.y), c])
			for d in [Vector2(0.25, 0), Vector2(0, 0.25), Vector2(-0.25, 0), Vector2(0, -0.25)]:
				var d2 := Vector2(-d.y, d.x)
				lines.append([Vector3(g.x + d.x, y, g.y + d.y), Vector3(g.x + d2.x, y, g.y + d2.y), c])
	if not lines.is_empty():
		_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for l in lines:
			_mesh.surface_set_color(l[2])
			_mesh.surface_add_vertex(l[0])
			_mesh.surface_set_color(l[2])
			_mesh.surface_add_vertex(l[1])
		_mesh.surface_end()
	for id in _tags.keys():
		if not seen.has(id):
			var t: Node = _tags[id]
			if is_instance_valid(t):
				t.queue_free()
			_tags.erase(id)


func clear() -> void:
	draw([])


func tag_count() -> int:
	return _tags.size()


func _tag(e: Node3D, text: String, c: Color) -> void:
	var t: Label3D = _tags.get(e.get_instance_id())
	if t == null or not is_instance_valid(t):
		t = Label3D.new()
		t.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		t.no_depth_test = true
		t.font_size = 40
		t.pixel_size = 0.006
		t.outline_size = 8
		t.position = Vector3(0, 2.35, 0)
		e.add_child(t)
		_tags[e.get_instance_id()] = t
	t.text = text.to_upper()
	t.modulate = c
