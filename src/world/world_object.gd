class_name WorldObject
extends Node3D
## A placeable object of the survival house (SPEC §7.3 d, §4): door,
## barricade, storage crate or rain collector. Kind, HP, footprint, a PropKit
## visual and the SPEC collision layers. Navigation and collision consistency
## are kept by HouseWorld, which owns every object.
##
## Wall-like objects (door, barricade) sit on a 1 m segment of an integer plan
## line: `seg` = Vector3i(axis, line, start) with axis 0 = along plan x on
## y = line, axis 1 = along plan y on x = line. Free-standing objects (crate,
## rain collector) sit on 0.5 m cells with a quarter-turn `rot`.

const FACINGS := ["N", "E", "S", "W"]
const YAW := [0.0, -PI * 0.5, PI, PI * 0.5]   ## node yaw that turns local -Z to N, E, S, W

## size = Vector3(width across the front, height, depth) before rotation.
const DEFS := {
	"door": {"name": "Door", "hp": 18, "size": Vector3(1.0, 2.1, 0.16), "segment": true, "layers": 1 | 2, "impact": VoxelMat.Impact.WOOD},
	"barricade": {"name": "Barricade", "hp": 12, "size": Vector3(1.0, 1.5, 0.22), "segment": true, "layers": 2, "impact": VoxelMat.Impact.WOOD},
	"crate": {"name": "Storage crate", "hp": 10, "size": Vector3(1.0, 0.75, 0.5), "segment": false, "layers": 1, "impact": VoxelMat.Impact.WOOD},
	"rain_collector": {"name": "Rain collector", "hp": 10, "size": Vector3(0.5, 1.1, 0.5), "segment": false, "layers": 1, "impact": VoxelMat.Impact.METAL},
}

var kind := ""
var hp := 1
var max_hp := 1
var pos := Vector2.ZERO          ## plan centre of the footprint
var rot := 0                     ## 0..3 = front faces N, E, S, W
var seg := Vector3i(-1, 0, 0)    ## wall-like objects only
var open := false                ## doors
var built := true                ## placed by the player (demolish refunds half)
var world: Node                  ## the owning HouseWorld
var visual: Node3D
var body: StaticBody3D

var _pivot: Node3D
var _shape: CollisionShape3D
var _leaf: Node3D
var _leaf_sign := -1.0
var _leaf_angle := 0.0
var _cut := false


static func is_segment_kind(k: String) -> bool:
	return DEFS.has(k) and DEFS[k]["segment"]


## Plan footprint used for navigation and overlap checks.
static func footprint_of(k: String, p: Vector2, r: int) -> Rect2:
	if is_segment_kind(k):
		var horiz := r % 2 == 0
		return Rect2(p.x - 0.5, p.y - 0.125, 1.0, 0.25) if horiz else Rect2(p.x - 0.125, p.y - 0.5, 0.25, 1.0)
	var s: Vector3 = DEFS[k]["size"]
	var ext := Vector2(s.x, s.z) if r % 2 == 0 else Vector2(s.z, s.x)
	return Rect2(p - ext * 0.5, ext)


## Segment of a wall-like object at plan centre `p` and rotation `r`.
static func segment_of(p: Vector2, r: int) -> Vector3i:
	if r % 2 == 0:
		return Vector3i(0, roundi(p.y), floori(p.x))
	return Vector3i(1, roundi(p.x), floori(p.y))


func setup(k: String, p: Vector2, r: int, w: Node, is_built := true) -> void:
	kind = k
	pos = p
	rot = posmod(r, 4)
	world = w
	built = is_built
	max_hp = DEFS[k]["hp"]
	hp = max_hp
	if is_segment_kind(k):
		seg = segment_of(p, rot)
	name = "%s_%d_%d" % [k, int(round(p.x * 10)), int(round(p.y * 10))]


func _ready() -> void:
	position = Vector3(pos.x, 0, pos.y)
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	_pivot.rotation.y = YAW[rot]
	add_child(_pivot)
	_refresh_visual()
	body = StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = DEFS[kind]["layers"]
	body.collision_mask = 0
	body.set_meta("impact", DEFS[kind]["impact"])
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	var s: Vector3 = DEFS[kind]["size"]
	box.size = Vector3(s.x - (0.02 if is_segment_kind(kind) else 0.0), s.y, maxf(s.z, 0.12))
	_shape.shape = box
	_shape.position.y = s.y * 0.5
	body.add_child(_shape)
	_pivot.add_child(body)
	_apply_open(true)


func footprint() -> Rect2:
	return footprint_of(kind, pos, rot)


func facing() -> String:
	return FACINGS[rot]


func damage_fraction() -> float:
	return clampf(1.0 - float(hp) / float(max_hp), 0.0, 1.0)


## Closed doors and barricades block bodies and count as WALL for navigation;
## crates and collectors are SOLID; an open door is OPEN (-1 = no mark).
func nav_kind() -> int:
	match kind:
		"door":
			return -1 if open else GridNav.WALL
		"barricade":
			return GridNav.WALL
	return GridNav.SOLID


## True for objects an enemy swing damages (SPEC: doors and barricades).
func bashable() -> bool:
	return kind == "barricade" or (kind == "door" and not open)


## Returns true when this hit destroyed the object.
func take_damage(n: int) -> bool:
	hp = maxi(hp - n, 0)
	_refresh_visual()
	return hp <= 0


func restore() -> void:
	hp = max_hp
	_refresh_visual()


func set_open(on: bool, instant := false) -> void:
	open = on
	_apply_open(instant)


func set_cut(on: bool) -> void:
	if on == _cut:
		return
	_cut = on
	_apply_cut()


func to_dict() -> Dictionary:
	return {"kind": kind, "x": pos.x, "y": pos.y, "rot": rot, "hp": hp, "open": open, "built": built}


# --- interactable duck type (SPEC §7.3) -------------------------------------------

func interact_prompt() -> String:
	match kind:
		"door":
			return "[E] Close door" if open else "[E] Open door"
		"crate":
			return "[E] Storage crate · +%d planks, +%d nails, +%d scrap" % [
				Items.DEFS["wood"]["cap_per_crate"], Items.DEFS["nails"]["cap_per_crate"], Items.DEFS["scrap"]["cap_per_crate"]]
		"rain_collector":
			return "[E] Rain collector · 1 water at dawn"
	return ""


func interact(game: Node) -> void:
	match kind:
		"door":
			if world != null and world.has_method("toggle_door"):
				var err: String = world.toggle_door(self)
				if err != "" and game != null and game.has_method("toast"):
					game.toast(err, "warn")
		"crate":
			if game != null and game.has_method("toast"):
				game.toast("Storage crate: holds %d more planks, %d more nails and %d more scrap." % [
					Items.DEFS["wood"]["cap_per_crate"], Items.DEFS["nails"]["cap_per_crate"], Items.DEFS["scrap"]["cap_per_crate"]], "info")
		"rain_collector":
			if game != null and game.has_method("toast"):
				game.toast("Rain collector: gathers 1 water at dawn.", "info")


# --- visuals -----------------------------------------------------------------------

func _refresh_visual() -> void:
	if _pivot == null:
		return
	if visual != null:
		visual.queue_free()
	var s: Vector3 = DEFS[kind]["size"]
	visual = PropKit.make(kind, s, {"facing": "N", "seed": hash(name) & 0xffff, "damage": damage_fraction()})
	visual.name = "Visual"
	_pivot.add_child(visual)
	_leaf = visual.find_child("Leaf", true, false) as Node3D
	if _leaf != null:
		_leaf_sign = _leaf_open_sign(_leaf)
		_leaf.rotation.y = _leaf_angle
	_apply_cut()


## The leaf opens toward the back (+Z, away from the front). Which way that
## is depends on the hinge side, so look at where the leaf's geometry lies.
static func _leaf_open_sign(leaf: Node3D) -> float:
	var sum := 0.0
	for n in leaf.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		var a := vi.get_aabb()
		var c := leaf.global_transform.affine_inverse() * (vi.global_transform * a.get_center()) if leaf.is_inside_tree() else (vi.transform * a.get_center())
		sum += c.x
	return -1.0 if sum >= 0.0 else 1.0


func _apply_open(instant: bool) -> void:
	if _shape != null:
		_shape.set_deferred("disabled", kind == "door" and open)
	if kind != "door":
		return
	var goal := deg_to_rad(95.0) * _leaf_sign if open else 0.0
	if _leaf == null or instant or not is_inside_tree():
		_leaf_angle = goal
		if _leaf != null:
			_leaf.rotation.y = goal
		return
	var tw := create_tween()
	tw.tween_method(func(a: float) -> void:
		_leaf_angle = a
		if is_instance_valid(_leaf):
			_leaf.rotation.y = a, _leaf_angle, goal, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _apply_cut() -> void:
	if visual != null:
		set_geometry_cut(visual, _cut)


## Cutaway for meshes: hidden from the camera but still casting shadows (as
## the voxel cutaway does); restores each part's own shadow setting.
static func set_geometry_cut(root: Node, on: bool) -> void:
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if on:
			if not gi.has_meta("cut_cs"):
				gi.set_meta("cut_cs", gi.cast_shadow)
			if gi.get_meta("cut_cs") == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				gi.visible = false
			else:
				gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		elif gi.has_meta("cut_cs"):
			var cs: int = gi.get_meta("cut_cs")
			if cs == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				gi.visible = true
			gi.cast_shadow = cs
			gi.remove_meta("cut_cs")
