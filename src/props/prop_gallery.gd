extends Node3D
## Every PropKit type laid out on voxel-style ground under Version A's
## lighting (VoxelLighting, instantiated, not modified). Dev tool for P.
##
## User args (after `--`):
##   --night            night (VoxelLighting.set_amount(1.0)); candles and lanterns burn
##   --lit              light candles and lanterns by day too
##   --view=game|close|all   game camera (pitch -56°, FOV 40, distance 20),
##                      a close view, or the whole gallery
##   --group=<name>     centre on one group: living, kitchen, bedroom, survival, yard
##   --focus=<type>     centre on the first piece of that type (implies close unless --view)
##   --nolabels         hide the type labels
##   --dist=<m>         override the camera distance
##   --house            the hybrid look in place: the foundation HouseWorld (Version A's
##                      voxel house) with its voxel furniture swapped for PropKit pieces,
##                      doors in the doorways, barricaded windows, survival props
##   --look=x,z         (house) where the camera looks (default the living room)
## Example: tools/capture.sh res://src/props/prop_gallery.tscn /tmp/g.png 6 --group=survival --night

const PITCH := -56.0
const FOV := 40.0
const GAP := 0.7
const ROW_GAP := 1.7
const MAX_ROW := 15.0

## Groups (rows from back to front). Entries: [type, opts, label].
const GROUPS := {
	"living": [
		["bookshelf"], ["tv_stand"], ["sofa"], ["coffee_table"], ["armchair"], ["floor_lamp"],
		["dining_table"], ["chair"], ["plant"], ["rug"],
	],
	"kitchen": [
		["fridge"], ["counter"], ["sink_counter"], ["stove"], ["island"], ["stool"],
		["bathtub"], ["toilet"], ["vanity"],
	],
	"bedroom": [
		["wardrobe"], ["bed"], ["nightstand"], ["dresser"], ["water_heater"], ["workbench"],
		["washer"], ["dryer"], ["shelves"], ["boxes"],
	],
	"survival": [
		["door", {}, "door"], ["door", {"open": 0.55}, "door open"], ["door", {"damage": 0.8}, "door 0.8"],
		["door", {"style": "plank", "seed": 2}, "plank door"], ["door", {"style": "plank", "damage": 0.75, "seed": 2}, "plank 0.75"],
		["barricade", {}, "barricade"], ["barricade", {"damage": 0.45}, "barricade 0.45"], ["barricade", {"damage": 0.85}, "barricade 0.85"],
		["crate"], ["crate", {"damage": 0.7, "seed": 5}, "crate 0.7"], ["rain_collector"], ["rain_collector", {"damage": 0.7}, "collector 0.7"],
		["candle"], ["lantern"], ["bush"], ["bush", {"seed": 4}, "bush"],
		["wall_ghost", {"tint": Color(0.35, 0.95, 0.45, 0.45)}, "ghost ok"], ["wall_ghost", {"tint": Color(1.0, 0.3, 0.25, 0.45)}, "ghost blocked"],
	],
	"yard": [
		["dead_tree"], ["streetlight_dead"], ["mailbox"], ["trash_bin_tipped"], ["car"], ["step"],
		["deck"], ["path"], ["driveway"],
	],
	# Exp 005 (F): new furniture and the loot pile
	"storage": [
		["cupboard"], ["storage_chest"], ["tool_cabinet"], ["painting"], ["loot_pile"], ["table_lamp", {"lit": true}, "table lamp lit"],
		["storage_chest", {"damage": 0.7, "seed": 3}, "chest 0.7"],
	],
}
const ORDER := ["survival", "living", "kitchen", "bedroom", "yard", "storage"]
## Floor swatch under each group (Version A's voxel art, read-only).
const FLOORS := {"living": "floor_wood", "kitchen": "floor_kitchen", "bedroom": "floor_wood_light", "survival": "", "yard": "", "storage": "floor_wood"}

var lighting: VoxelLighting
var camera: Camera3D
var placed := {}           # type -> Node3D (first instance)
var group_centre := {}     # group -> Vector3
var lights: Array[Node3D] = []
var world: HouseWorld
var view_target := Vector3(5.5, 0.0, 6.5)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var night := "--night" in args
	var labels := not "--nolabels" in args
	var view := ""
	var group := ""
	var focus := ""
	var dist := -1.0
	for a in args:
		if a.begins_with("--view="):
			view = a.trim_prefix("--view=")
		elif a.begins_with("--group="):
			group = a.trim_prefix("--group=")
		elif a.begins_with("--focus="):
			focus = a.trim_prefix("--focus=")
		elif a.begins_with("--dist="):
			dist = float(a.trim_prefix("--dist="))
	lighting = VoxelLighting.new()
	add_child(lighting)
	# The house's practical lights are not part of the gallery (and there is no power).
	for o in lighting.practicals:
		o.set_meta("night_energy", 0.0)
	lighting.set_amount(1.0 if night else 0.0)
	if "--house" in args:
		for a in args:
			if a.begins_with("--look="):
				var p := a.trim_prefix("--look=").split(",")
				view_target = Vector3(float(p[0]), 0.0, float(p[1]))
		_house()
		group = "house"
	else:
		_ground()
		_layout(labels)
	var lit := night or "--lit" in args
	for n in lights:
		PropKit.set_lit(n, 1.0 if lit else 0.0)
	camera = Camera3D.new()
	camera.fov = FOV
	camera.near = 0.05
	camera.far = 200.0
	add_child(camera)
	var target := Vector3(0, 0, 0)
	var d := 20.0
	var pitch := PITCH
	if focus != "" and placed.has(focus):
		target = (placed[focus] as Node3D).position + Vector3(0, 0.4, 0)
		if view == "":
			view = "close"
	elif group_centre.has(group):
		target = group_centre[group]
	elif world != null:
		target = view_target
	if view == "close":
		d = 6.5
		pitch = -38.0
	elif view == "all":
		d = 58.0
		target = Vector3(0, 0, 0)
	if dist > 0.0:
		d = dist
	var dir := Vector3(0, sin(deg_to_rad(-pitch)), cos(deg_to_rad(-pitch)))
	camera.position = target + dir * d
	camera.look_at(target, Vector3.UP)
	var hud := Label.new()
	hud.text = "PropKit gallery  ·  %s  ·  %s" % ["night" if night else "day", group if group != "" else (focus if focus != "" else "all")]
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 18)
	hud.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)


func _ground() -> void:
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(160, 160)
	plane.mesh = pm
	plane.material_override = _swatch_material("ground", 12.8, 12.8)
	plane.position.y = -0.001
	add_child(plane)


func _swatch_material(logical: String, sx: float, sz: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var tex := AssetResolver.get_texture("voxel/" + logical, true)
	m.albedo_texture = tex
	if tex == null:
		m.albedo_color = Color(0.4, 0.38, 0.3)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(1.0 / sx, 1.0 / sx, 1.0 / sz)
	m.roughness = 0.95
	return m


static func _canonical(type: String) -> Vector3:
	for f in HousePlan.FURNITURE + HousePlan.PROPS:
		if f["type"] == type:
			var r: Rect2 = f["rect"]
			return PropKit.canonical_size(type, Vector3(r.size.x, f["height"], r.size.y), f["facing"])
	return PropKit.default_size(type)


func _layout(labels: bool) -> void:
	# Pack each group into rows no wider than MAX_ROW; groups follow ORDER from back to front.
	var rows: Array = []          # [{"group", "items": [[it, c, w]], "total", "depth"}]
	for g in ORDER:
		var row := {"group": g, "items": [], "total": 0.0, "depth": 0.0}
		for it in GROUPS[g]:
			var c := _canonical(it[0])
			var w := maxf(c.x, 1.6) if it[0] in ["dead_tree", "streetlight_dead"] else c.x
			if row["total"] + w > MAX_ROW and not row["items"].is_empty():
				rows.append(row)
				row = {"group": g, "items": [], "total": 0.0, "depth": 0.0}
			row["items"].append([it, c, w])
			row["total"] += w + GAP
			row["depth"] = maxf(row["depth"], c.z)
		rows.append(row)
	var z := 0.0
	var seed := 11
	var span := {}
	for row in rows:
		var g: String = row["group"]
		z += row["depth"] * 0.5
		var x: float = -row["total"] * 0.5
		for entry in row["items"]:
			var it: Array = entry[0]
			var c: Vector3 = entry[1]
			var w: float = entry[2]
			var type: String = it[0]
			var opts: Dictionary = (it[1] if it.size() > 1 else {}).duplicate()
			opts["facing"] = "S"
			if not opts.has("seed"):
				seed += 1
				opts["seed"] = seed
			if type == "candle" or type == "lantern":
				opts["light"] = true
			var n := PropKit.make(type, c, opts)
			n.position = Vector3(x + w * 0.5, 0, z)
			if type == "candle":
				# on a crate, as a survivor would place it
				var stand := PropKit.make("crate", Vector3(0.5, 0.45, 0.45), {"facing": "S", "seed": 77})
				stand.position = n.position
				add_child(stand)
				n.position.y = 0.45
			if opts.has("open"):
				PropKit.set_door_open(n, float(opts["open"]))
			add_child(n)
			if type == "candle" or type == "lantern":
				lights.append(n)
			if not placed.has(type):
				placed[type] = n
			if labels:
				var l := Label3D.new()
				l.text = it[2] if it.size() > 2 else type
				l.font_size = 36
				l.pixel_size = 0.004
				l.outline_size = 8
				l.modulate = Color(0.96, 0.93, 0.86)
				l.outline_modulate = Color(0, 0, 0, 0.75)
				l.rotation_degrees = Vector3(-90, 0, 0)
				l.position = Vector3(x + w * 0.5, 0.02, z + c.z * 0.5 + 0.3)
				add_child(l)
			x += w + GAP
		var sp: Array = span.get(g, [z - row["depth"] * 0.5, z + row["depth"] * 0.5, 0.0])
		sp[1] = z + row["depth"] * 0.5
		sp[2] = maxf(sp[2], row["total"])
		span[g] = sp
		z += row["depth"] * 0.5 + ROW_GAP
	for g in span:
		var sp: Array = span[g]
		group_centre[g] = Vector3(0, 0, (sp[0] + sp[1]) * 0.5)
		if FLOORS[g] != "":
			var pad := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(sp[2] + 0.6, 0.02, sp[1] - sp[0] + 1.6)
			pad.mesh = bm
			pad.position = Vector3(0, -0.009, (sp[0] + sp[1]) * 0.5 + 0.25)
			var sw := {"floor_wood": [6.4, 4.8], "floor_wood_light": [6.4, 4.8], "floor_kitchen": [3.6, 3.6]}
			var s: Array = sw[FLOORS[g]]
			pad.material_override = _swatch_material(FLOORS[g], s[0], s[1])
			add_child(pad)
	# the road across the back of the yard, beyond everything
	var road := PropKit.make("road", Vector3(28, 0, 1.5), {"facing": "S", "seed": 3})
	road.position = Vector3(0, 0, z + 1.0)
	add_child(road)
	# centre the whole gallery on the origin
	for c in get_children():
		if c is Node3D and c != lighting:
			(c as Node3D).position.z -= z * 0.5
	for g in group_centre:
		group_centre[g].z -= z * 0.5


func _process(delta: float) -> void:
	if world != null and camera != null:
		world.update_view(view_target, camera, delta)


# --- house mode ---------------------------------------------------------------------

## Version A's house from the foundation HouseWorld (public API only, plus a
## read of its voxel grid to take the voxel furniture out), dressed with
## PropKit: the plan furniture, doors in the five doorways, barricaded living
## room windows, a crate, a rain collector, bushes, a candle and a lantern.
func _house() -> void:
	world = HouseWorld.new()
	world.name = "HouseWorld"
	world.setup(lighting)
	add_child(world)
	world.build_new()
	# Swap the voxel furniture and fixtures (material ids 32..77) for meshes.
	# (Reads VoxelGrid internals; skipped if V reshapes them.)
	var g = world.grid
	if g != null and "mat" in g and g.has_method("clear_index") and world.chunks != null and world.chunks.has_method("build_all"):
		var mats: PackedByteArray = g.mat
		for i in mats.size():
			var m := mats[i]
			if m >= 32 and m <= 77:
				g.clear_index(i)
		world.chunks.build_all()
	else:
		push_warning("prop gallery: could not take the voxel furniture out")
	for m in PropMaterials.cut_materials():
		world.cut_materials.append(m)
	for f in HousePlan.FURNITURE:
		if f["type"] == "rug":
			continue    # the voxel floor keeps its rugs
		_put(f["type"], f["rect"], f["height"], f["facing"], {"seed": hash(f["id"])})
	# doors: [centre x, centre z, facing, wall thickness, opts, open]
	var doors := [
		[4.5, 9.0, "S", 0.3, {"seed": 1}, 0.0],
		[14.0, 6.5, "E", 0.3, {"seed": 2, "style": "plank"}, 0.55],
		[2.5, 4.0, "S", 0.2, {"seed": 3}, -0.85],
		[6.5, 4.0, "S", 0.2, {"seed": 4, "damage": 0.6}, 0.0],
		[10.0, 7.5, "W", 0.2, {"seed": 5}, 0.9],
	]
	for dd in doors:
		var o: Dictionary = (dd[4] as Dictionary).duplicate()
		o["facing"] = dd[2]
		var size := Vector3(1.0, 2.1, dd[3])
		var n := PropKit.make("door", size, o)
		n.position = Vector3(dd[0], 0, dd[1])
		PropKit.set_door_open(n, dd[5])
		add_child(n)
	# the living room's west window, boarded from inside (planks toward the outside)
	for z in [6.5, 7.5]:
		var b := PropKit.make("barricade", Vector3(0.2, 2.0, 1.0), {"facing": "W", "seed": int(z * 10), "damage": 0.4 if z == 7.5 else 0.0})
		b.position = Vector3(0.26, 0, z)
		add_child(b)
	var extra := [
		["crate", Rect2(11.7, 5.9, 0.9, 0.6), 0.6, "W", {}],
		["crate", Rect2(12.0, 7.05, 0.6, 0.6), 0.5, "N", {"seed": 3}],
		["rain_collector", Rect2(15.1, 3.0, 1.0, 1.0), 1.6, "W", {}],
		["bush", Rect2(-1.8, 2.0, 1.2, 1.0), 0.9, "N", {"seed": 1}],
		["bush", Rect2(8.2, 9.4, 1.1, 0.9), 0.8, "N", {"seed": 2}],
		["bush", Rect2(-1.6, 9.3, 1.0, 1.0), 0.7, "N", {"seed": 3}],
		["wall_ghost", Rect2(-3.1, 5.0, 0.2, 1.0), 2.6, "E", {"tint": Color(0.35, 0.95, 0.45, 0.45)}],
		["wall_ghost", Rect2(-3.1, 6.0, 0.2, 1.0), 2.6, "E", {"tint": Color(0.35, 0.95, 0.45, 0.45)}],
	]
	for e in extra:
		_put(e[0], e[1], e[2], e[3], e[4])
	var candle := _put("candle", Rect2(7.6, 5.55, 0.2, 0.2), 0.18, "N", {"light": true})
	candle.position.y = 0.75
	var lantern := _put("lantern", Rect2(4.3, 5.55, 0.2, 0.2), 0.32, "N", {"light": true})
	lantern.position.y = 0.45
	lights.append(candle)
	lights.append(lantern)
	if world.get("yard") != null and world.yard.has_method("update_roof"):
		world.yard.update_roof(view_target, 0.0, true)


func _put(type: String, rect: Rect2, height: float, facing: String, opts: Dictionary) -> Node3D:
	var o := opts.duplicate()
	o["facing"] = facing
	var n := PropKit.make(type, Vector3(rect.size.x, height, rect.size.y), o)
	var c := rect.get_center()
	n.position = Vector3(c.x, 0, c.y)
	add_child(n)
	return n
