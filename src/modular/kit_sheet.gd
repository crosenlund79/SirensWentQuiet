class_name ModKitSheet
extends Node3D
## Presentation only (--scenario=kit): every kit piece laid out on the lawn
## outside the yard, labelled, including each wall damage state. The pieces
## are the same classes the house is assembled from, standing on their own.

const M := preload("res://src/modular/kit/mod_materials.gd")
const SPACING := 1.45


func _ready() -> void:
	var x := 0.0
	# row 1: exterior wall, window, doors
	for s in [ModWall.State.INTACT, ModWall.State.DAMAGED, ModWall.State.HEAVY, ModWall.State.DESTROYED]:
		_wall(Vector3(x, 0, 0), ModWall.Kind.SOLID, true, s, ["exterior wall", "damaged", "heavy damage", "destroyed"][s])
		x += SPACING
	_wall(Vector3(x, 0, 0), ModWall.Kind.WINDOW, true, ModWall.State.INTACT, "window")
	x += SPACING
	var broken := _wall(Vector3(x, 0, 0), ModWall.Kind.WINDOW, true, ModWall.State.INTACT, "glass shot out")
	broken.take_hit(Vector3(0.5, 1.5, 0), 1, true)
	broken.take_hit(Vector3(0.5, 1.5, 0), 1, true)
	x += SPACING
	_wall(Vector3(x, 0, 0), ModWall.Kind.WINDOW, true, ModWall.State.HEAVY, "window, heavy")
	x += SPACING
	_door(Vector3(x, 0, 0), "front", "front door")
	x += SPACING
	_door(Vector3(x, 0, 0), "interior", "interior door")
	# row 2: interior wall states, posts, floor tiles, roof panel
	x = 0.0
	var z := 3.0
	for s in [ModWall.State.INTACT, ModWall.State.DAMAGED, ModWall.State.HEAVY, ModWall.State.DESTROYED]:
		_wall(Vector3(x, 0, z), ModWall.Kind.SOLID, false, s, ["interior wall", "damaged", "heavy damage", "destroyed"][s])
		x += SPACING
	for size in [0.3, 0.2]:
		var p := ModPost.new()
		p.size = size
		p.plan_pos = Vector2(-50, -50)
		p.position = Vector3(x + 0.3, 0, z)
		add_child(p)
		_label(Vector3(x + 0.3, 0, z + 1.05), "post %.1f" % size)
		x += 0.9
	x += 0.3
	var finishes := [["wood", M.L_FLOOR_WOOD], ["ash", M.L_FLOOR_WOOD_LIGHT], ["tile", M.L_FLOOR_TILE], ["terracotta", M.L_FLOOR_KITCHEN], ["concrete", M.L_CONCRETE]]
	for f in finishes:
		var tile := MeshInstance3D.new()
		tile.mesh = ModFloorKit.tile_mesh(f[1])
		tile.material_override = M.kit()
		tile.position = Vector3(x, 0, z - 0.5)
		add_child(tile)
		_label(Vector3(x + 0.5, 0, z + 1.05), f[0])
		x += 1.4


func _wall(at: Vector3, kind: int, exterior: bool, state: int, text: String) -> ModWall:
	var m := ModWall.new()
	m.kind = kind
	m.exterior = exterior
	m.outside = 0 if exterior else -1
	m.thickness = HousePlan.EXTERIOR_THICKNESS if exterior else HousePlan.INTERIOR_THICKNESS
	m.tint_a = M.ROOM_PAINT["living"] if not exterior else Color.WHITE
	m.tint_b = M.ROOM_PAINT["kitchen"]
	m.seed = int(at.x * 10.0 + at.z * 100.0) + 3
	m.world_x0 = at.x
	m.position = at
	m.collision_layer = 0
	add_child(m)
	m.collision_layer = 0
	if state != ModWall.State.INTACT:
		for k in 6:
			m.take_hit(Vector3(randf_range(0.15, 0.85), randf_range(0.4, 2.0), m.thickness * 0.5), 0, true)
		m.set_state(state)
	_label(at + Vector3(0.5, 0, 1.05), text)
	return m


func _door(at: Vector3, style: String, text: String) -> void:
	var m := ModWall.new()
	m.kind = ModWall.Kind.DOOR
	m.exterior = style != "interior"
	m.outside = 0 if m.exterior else -1
	m.thickness = HousePlan.EXTERIOR_THICKNESS if m.exterior else HousePlan.INTERIOR_THICKNESS
	m.door_style = style
	m.door_swing = -1.0
	m.tint_b = M.ROOM_PAINT["living"]
	m.tint_a = M.ROOM_PAINT["bedroom"]
	m.position = at
	add_child(m)
	m.collision_layer = 0
	_label(at + Vector3(0.5, 0, 1.05), text)


func _label(at: Vector3, text: String) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 40
	l.pixel_size = 0.0042
	l.modulate = Color(0.92, 0.9, 0.84)
	l.outline_modulate = Color(0.05, 0.05, 0.06, 0.9)
	l.outline_size = 10
	l.rotation_degrees = Vector3(-90, 0, 0)
	l.position = at + Vector3(0, 0.03, 0)
	l.shaded = false
	add_child(l)
