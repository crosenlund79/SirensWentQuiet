class_name PropKit
extends RefCounted
## Conventional stylized meshes for furniture, doors, barricades, storage,
## lights, yard props and vegetation (SPEC §7.5). Owner: P.
## Foundation stub: a plain box of the requested size for every type.

static func make(type: String, size: Vector3, opts := {}) -> Node3D:
	var root := Node3D.new()
	root.name = type.capitalize().replace(" ", "")
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(maxf(size.x, 0.05), maxf(size.y, 0.05), maxf(size.z, 0.05))
	mi.mesh = box
	mi.position.y = box.size.y * 0.5
	var m := StandardMaterial3D.new()
	m.albedo_color = opts.get("color", Color(0.55, 0.5, 0.45))
	mi.material_override = m
	root.add_child(mi)
	if type == "door":
		var leaf := Node3D.new()
		leaf.name = "Leaf"
		root.add_child(leaf)
	return root


static func has(_type: String) -> bool:
	return true


static func types() -> PackedStringArray:
	return PackedStringArray()
