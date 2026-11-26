class_name FocusRing
extends Node3D
## Exp 012 (L, §24): the current interaction target's highlight: a soft,
## slowly breathing amber ring on the floor round the thing [E] acts on (at
## home and away), under the HUD's concise prompt. The searchable things'
## own markers (PoiSpot) are the subtle "nearby" cue; this is the strong one.
## It follows the finder's choice, which never sees through walls
## (InteractionFinder.in_sight), and the finder keeps its choice for a few
## centimetres (no flicker). The game calls FocusRing.show_for(game, focus).

const COLOR := Color(1.0, 0.72, 0.32)
const ALPHA := 0.62
const RADIUS := 0.42
const MAX_RADIUS := 1.1

var target: Node3D
var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _t := 0.0


## The game's one ring (created on first use, a child of `game`), shown for
## `focus` (null hides it).
static func show_for(game: Node, focus: Node3D) -> FocusRing:
	if game == null or not game.is_inside_tree():
		return null
	var ring := game.get_node_or_null("FocusRing") as FocusRing
	if ring == null:
		if focus == null:
			return null
		ring = FocusRing.new()
		ring.name = "FocusRing"
		game.add_child(ring)
	ring.follow(focus)
	return ring


func _ready() -> void:
	top_level = true
	_mesh = MeshInstance3D.new()
	_mesh.name = "Ring"
	var tor := TorusMesh.new()
	tor.inner_radius = 0.86
	tor.outer_radius = 1.0
	tor.rings = 40
	tor.ring_segments = 6
	_mesh.mesh = tor
	_mesh.scale = Vector3(RADIUS, 0.05, RADIUS)
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(COLOR, ALPHA)
	_mat.no_depth_test = false
	_mesh.material_override = _mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	visible = false


func follow(n: Node3D) -> void:
	if n != null and not is_instance_valid(n):
		n = null
	if n == target:
		return
	target = n
	visible = n != null
	if n != null:
		_place()


func _process(delta: float) -> void:
	if target == null:
		return
	if not is_instance_valid(target) or not target.is_inside_tree():
		follow(null)
		return
	_place()
	_t += delta
	_mat.albedo_color = Color(COLOR, ALPHA * (0.78 + 0.22 * sin(_t * 3.2)))


func _place() -> void:
	var g := target.global_position
	var at := Vector2(g.x, g.z)
	var r := RADIUS
	if target.has_method("interact_point"):
		at = target.interact_point()
	var data: Variant = target.get("data")
	if data is Dictionary and (data as Dictionary).get("rect") is Rect2:
		var rc: Rect2 = data["rect"]
		r = clampf(maxf(rc.size.x, rc.size.y) * 0.5 + 0.18, RADIUS, MAX_RADIUS)
	global_position = Vector3(at.x, g.y + 0.04, at.y)
	_mesh.scale = Vector3(r, 0.05, r)
