class_name WorldObject
extends Node3D
## A placeable object of the survival house (SPEC §7.3 d, §4): door,
## barricade, storage crate, rain collector or (Experiment 003) workbench.
## Kind, material, HP, footprint, a PropKit visual and the SPEC collision
## layers. Navigation and collision consistency are kept by HouseWorld,
## which owns every object. Doors and barricades come in "wood" and "iron"
## (a reinforced door, an iron barricade: same behaviour, more HP); `kind`
## stays "door" / "barricade" for both.
##
## Experiment 004: "boards" (window boards: planks over a window section,
## mounted at window height on the outside face; they stop bullets and
## bodies), a third door material "metal" (a steel door, 70 HP) and the
## "fuse_box" (wall-mounted main power switch, `mains_on`; HouseWorld emits
## power_changed). DEFS "y0" lifts the visual and collision above the floor,
## "out" moves them toward the front (outside) of the wall line.
##
## Wall-like objects (door, barricade, boards) sit on a 1 m segment of an integer plan
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
	"workbench": {"name": "Workbench", "hp": 14, "size": Vector3(1.0, 0.9, 0.5), "segment": false, "layers": 1, "impact": VoxelMat.Impact.WOOD},
	# Experiment 004
	"boards": {"name": "Window boards", "hp": 14, "size": Vector3(1.0, 1.3, 0.08), "segment": true, "layers": 1 | 2, "impact": VoxelMat.Impact.WOOD,
		"y0": 0.85, "out": 0.19},
	"fuse_box": {"name": "Fuse box", "hp": 20, "size": Vector3(0.5, 0.7, 0.16), "segment": false, "layers": 1, "impact": VoxelMat.Impact.METAL,
		"y0": 1.1},
}
## Material variants (Experiment 003). "wood" is DEFS itself; others override
## name, hp, the PropKit style and the impact kind.
const MATS := {
	"door": {"iron": {"name": "Reinforced door", "hp": 42, "style": "iron", "impact": VoxelMat.Impact.METAL},
		"metal": {"name": "Metal door", "hp": 70, "style": "metal", "impact": VoxelMat.Impact.METAL}},
	"barricade": {"iron": {"name": "Iron barricade", "hp": 30, "style": "iron", "impact": VoxelMat.Impact.METAL}},
}
const WOOD_TONES := [0x7a5c40, 0x8c6c4c, 0x5e4a36, 0x9a8466]
const IRON_TONES := [0x5d6266, 0x7a7f82, 0x4a4643, 0x7b4a2c]

var kind := ""
var hp := 1
var max_hp := 1
var pos := Vector2.ZERO          ## plan centre of the footprint
var rot := 0                     ## 0..3 = front faces N, E, S, W
var seg := Vector3i(-1, 0, 0)    ## wall-like objects only
var open := false                ## doors
var built := true                ## placed by the player (demolish refunds half)
var mat := "wood"                ## "wood" | "iron" (doors and barricades) | "metal" (doors)
var mains_on := true             ## fuse box: the main power switch (saved)
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


static func has_mat(k: String, m: String) -> bool:
	return DEFS.has(k) and (m == "wood" or (MATS.has(k) and MATS[k].has(m)))


static func _def(k: String, m: String, key: String) -> Variant:
	if m != "wood" and MATS.has(k) and MATS[k].has(m) and MATS[k][m].has(key):
		return MATS[k][m][key]
	return DEFS[k].get(key)


static func max_hp_of(k: String, m := "wood") -> int:
	return int(_def(k, m, "hp")) if DEFS.has(k) else 1


static func name_of(k: String, m := "wood") -> String:
	return str(_def(k, m, "name")) if DEFS.has(k) else k


## Plan direction of an object's front (the attacker's side of doors and
## barricades): rotation 0..3 = N, E, S, W.
static func front_dir(r: int) -> Vector2:
	return [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)][posmod(r, 4)]


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


func setup(k: String, p: Vector2, r: int, w: Node, is_built := true, m := "wood") -> void:
	kind = k
	pos = p
	rot = posmod(r, 4)
	world = w
	built = is_built
	mat = m if has_mat(k, m) else "wood"
	max_hp = max_hp_of(k, mat)
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
	body.set_meta("impact", _def(kind, mat, "impact"))
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	var s: Vector3 = DEFS[kind]["size"]
	box.size = Vector3(s.x - (0.02 if is_segment_kind(kind) else 0.0), s.y, maxf(s.z, 0.12))
	_shape.shape = box
	_shape.position = Vector3(0, base_y() + s.y * 0.5, -float(DEFS[kind].get("out", 0.0)))
	body.add_child(_shape)
	_pivot.add_child(body)
	_apply_open(true)


func footprint() -> Rect2:
	return footprint_of(kind, pos, rot)


## Height of the visual's and collision's bottom (window boards, fuse box).
func base_y() -> float:
	return float(DEFS[kind].get("y0", 0.0)) if DEFS.has(kind) else 0.0


func facing() -> String:
	return FACINGS[rot]


func display_name() -> String:
	return name_of(kind, mat)


## Debris colours when this object is hit or breaks (0xRRGGBB).
func debris_tones() -> Array:
	return IRON_TONES if mat != "wood" or kind == "fuse_box" else WOOD_TONES


func damage_fraction() -> float:
	return clampf(1.0 - float(hp) / float(max_hp), 0.0, 1.0)


## Closed doors and barricades block bodies and count as WALL for navigation;
## crates and collectors are SOLID; an open door is OPEN (-1 = no mark).
func nav_kind() -> int:
	match kind:
		"door":
			return -1 if open else GridNav.WALL
		"barricade", "boards":
			return GridNav.WALL
		"fuse_box":
			return -1
	return GridNav.SOLID


## True for objects an enemy swing damages (SPEC: doors and barricades;
## Experiment 004: window boards and the fuse box).
func bashable() -> bool:
	return kind in ["barricade", "boards", "fuse_box"] or (kind == "door" and not open)


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


## Experiment 004: a door's material changes in place (Reinforce: wood ->
## iron -> metal). The missing HP stay missing.
func set_mat(m: String) -> void:
	if not has_mat(kind, m) or m == mat:
		return
	var lost := max_hp - hp
	mat = m
	max_hp = max_hp_of(kind, mat)
	hp = clampi(max_hp - lost, 1, max_hp)
	if body != null:
		body.set_meta("impact", _def(kind, mat, "impact"))
	_refresh_visual()


func set_mains(on: bool) -> void:
	mains_on = on
	_refresh_visual()


func to_dict() -> Dictionary:
	var d := {"kind": kind, "x": pos.x, "y": pos.y, "rot": rot, "hp": hp, "open": open, "built": built, "mat": mat}
	if kind == "fuse_box":
		d["mains_on"] = mains_on
	return d


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
		"workbench":
			return "[E] Workbench · %d scrap → 1 iron" % Workbench.SCRAP_PER_IRON
		"fuse_box":
			return "[E] Switch the main power off" if mains_on else "[E] Switch the main power on"
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
		"workbench":
			var st: Variant = game.get("state") if game != null else null
			var r := Workbench.convert(st, 1)
			if r["ok"]:
				Sfx.play("build/hammer", Vector3(pos.x, 0.9, pos.y))
			if game != null and game.has_method("toast"):
				game.toast(r["text"], "info" if r["ok"] else "warn")
		"fuse_box":
			if world != null and world.has_method("toggle_mains"):
				world.toggle_mains(self)
			if game != null and game.has_method("toast"):
				game.toast("Main power on." if mains_on else "Main power off.", "info")


# --- visuals -----------------------------------------------------------------------

func _refresh_visual() -> void:
	if _pivot == null:
		return
	if visual != null:
		visual.queue_free()
	var s: Vector3 = DEFS[kind]["size"]
	var style := str(_def(kind, mat, "style") if mat != "wood" else "")
	if kind == "fuse_box" and not mains_on:
		style = "off"
	visual = PropKit.make(kind, s, {"facing": "N", "seed": hash(name) & 0xffff, "damage": damage_fraction(), "style": style})
	visual.name = "Visual"
	visual.position = Vector3(0, base_y(), -float(DEFS[kind].get("out", 0.0)))
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
