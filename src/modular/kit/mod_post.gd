class_name ModPost
extends StaticBody3D
## Kit piece: structural post where walls meet (corners and T-junctions).
## Indestructible. Outside faces read as charcoal corner boards; inside faces
## take the paint of the room they face. Slightly proud of the wall faces.

const M := preload("res://src/modular/kit/mod_materials.gd")

var size := 0.3                 ## footprint (m) = thickest wall at this node
var plan_pos := Vector2.ZERO
var cut := 100.0
var cut_target := 100.0

var _mesh: MeshInstance3D


func _ready() -> void:
	collision_layer = ModWall.LAYER_WALLS
	collision_mask = 0
	var s := size + 0.02
	var h := HousePlan.WALL_HEIGHT + 0.012
	var mm := ModMesh.new()
	var e := s * 0.5
	# four vertical faces, each split in two so a T-junction shows both rooms' paint
	var faces := [[Vector3.RIGHT, Vector3.BACK], [Vector3.LEFT, Vector3.FORWARD], [Vector3.BACK, Vector3.LEFT], [Vector3.FORWARD, Vector3.RIGHT]]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		for half in [-1.0, 1.0]:
			var a := n * e + u * (-e if half < 0.0 else 0.0)
			var b := n * e + u * (0.0 if half < 0.0 else e)
			var mid := (a + b) * 0.5 + n * 0.35
			var room := HousePlan.room_at(plan_pos + Vector2(mid.x, mid.z))
			if room.is_empty():
				mm.set_mat(M.L_TRIM, M.FRAME_COLOR)
			else:
				mm.set_mat(M.L_PAINT, M.ROOM_PAINT.get(room["id"], Color.WHITE))
			mm.quad(a, b, b + Vector3(0, h, 0), a + Vector3(0, h, 0), n)
	mm.set_mat(M.L_CAP, Color.WHITE)
	mm.quad(Vector3(-e, h, -e), Vector3(e, h, -e), Vector3(e, h, e), Vector3(-e, h, e), Vector3.UP)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = mm.commit()
	_mesh.material_override = M.kit()
	add_child(_mesh)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size, HousePlan.WALL_HEIGHT, size)
	cs.shape = box
	cs.position = Vector3(0, HousePlan.WALL_HEIGHT * 0.5, 0)
	add_child(cs)


func set_cut(h: float) -> void:
	cut = h
	if _mesh != null:
		_mesh.set_instance_shader_parameter("cut_height", h)


func material_at(local: Vector3) -> String:
	var room := HousePlan.room_at(plan_pos + Vector2(local.x, local.z) * 3.0)
	return "plaster" if not room.is_empty() else "trim"
