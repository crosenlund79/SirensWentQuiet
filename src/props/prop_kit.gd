class_name PropKit
extends RefCounted
## Conventional stylized 3D meshes for furniture, doors, barricades, storage,
## lights, yard props and vegetation (SPEC §7.5). Owner: P.
##
## Visual only (no collision). Every piece is one MeshInstance3D ("Mesh",
## one surface, one shared material = one draw call); a door adds a second
## one under its "Leaf". Meshes are cached and shared.
##
## Frames and sizes:
## - The returned root's origin is the floor centre of the footprint.
## - The front faces -Z (north) for facing "N"; the root's basis turns it to
##   "E", "S" or "W". Set the root's position, not its whole transform.
## - `size` is the world footprint (plan rect width along X, height, plan rect
##   depth along Z), exactly as HousePlan gives it: a sofa facing E with a
##   0.95 x 2.4 rect is make("sofa", Vector3(0.95, 0.85, 2.4), {"facing": "E"}).
##   Span pieces (door, barricade, wall_ghost) accept either order: the longer
##   horizontal side is the span, the shorter one the wall thickness.
##   Zero or negative components fall back to default_size(type).
##
## opts: "facing" N|E|S|W (default N), "seed" int, "damage" 0..1, "lit" bool
## or 0..1; additive: "style" ("panel" | "plank" for doors), "ghost" (draw
## with the translucent preview material), "tint" (ghost colour), "light"
## (add a small OmniLight3D named "Light" to candles and lanterns, driven by
## set_lit).

const Furniture := preload("res://src/props/prop_furniture.gd")
const Yard := preload("res://src/props/prop_yard.gd")
const Survival := preload("res://src/props/prop_survival.gd")
const Home := preload("res://src/props/prop_home.gd")
const StorageProps := preload("res://src/props/prop_storage.gd")   # Exp 005 (F)

const FURNITURE_TYPES := [
	"tv_stand", "sofa", "coffee_table", "rug", "armchair", "floor_lamp", "bookshelf", "dining_table",
	"chair", "plant", "fridge", "counter", "sink_counter", "stove", "island", "stool", "bed",
	"nightstand", "wardrobe", "dresser", "bathtub", "toilet", "vanity", "water_heater", "workbench",
	"washer", "dryer", "shelves", "boxes",
]
const PROP_TYPES := [
	"deck", "path", "road", "driveway", "step", "car", "dead_tree", "trash_bin_tipped", "mailbox",
	"streetlight_dead", "pine",
]
const SURVIVAL_TYPES := ["door", "barricade", "crate", "rain_collector", "candle", "lantern", "bush", "wall_ghost",
	"boards", "fuse_box", "rubble"]   # Experiment 004
## Experiment 004: electric fixtures, the wall switch and the fireplace (prop_home.gd).
const HOME_TYPES := ["ceiling_light", "range_hood", "table_lamp", "bare_bulb", "bulb", "light_switch", "fireplace"]
## Exp 005 (F): new furniture and the loot pile (prop_storage.gd).
const STORAGE_TYPES := ["cupboard", "storage_chest", "tool_cabinet", "painting", "loot_pile"]

## Span pieces: the longer horizontal side of `size` is the span.
const SPAN_TYPES := ["door", "barricade", "wall_ghost", "boards"]
## Pieces that may legitimately be flat (height 0).
const FLAT_TYPES := ["rug", "path", "road", "driveway"]
## Outdoor pieces weather faster (extra grime).
const OUTDOOR := ["deck", "path", "road", "driveway", "step", "car", "dead_tree", "trash_bin_tipped",
		"mailbox", "streetlight_dead", "barricade", "rain_collector", "bush", "pine"]

## Sizes used when a component of `size` is missing (canonical w x h x d:
## w across the front, d front to back). Plan types use their HousePlan size.
const DEFAULT_SIZE := {
	"tv_stand": Vector3(2.0, 1.1, 0.45), "sofa": Vector3(2.4, 0.85, 0.95),
	"coffee_table": Vector3(1.1, 0.45, 0.6), "rug": Vector3(3.4, 0.01, 2.9),
	"armchair": Vector3(0.9, 0.85, 0.9), "floor_lamp": Vector3(0.4, 1.6, 0.4),
	"bookshelf": Vector3(1.4, 1.9, 0.4), "dining_table": Vector3(1.6, 0.75, 0.9),
	"chair": Vector3(0.45, 0.9, 0.42), "plant": Vector3(0.5, 1.1, 0.5),
	"fridge": Vector3(0.75, 1.85, 0.7), "counter": Vector3(1.0, 0.92, 0.62),
	"sink_counter": Vector3(1.0, 0.92, 0.62), "stove": Vector3(0.75, 0.92, 0.62),
	"island": Vector3(1.9, 0.92, 0.85), "stool": Vector3(0.4, 0.7, 0.4),
	"bed": Vector3(1.6, 0.6, 2.1), "nightstand": Vector3(0.45, 0.55, 0.42),
	"wardrobe": Vector3(1.5, 2.0, 0.62), "dresser": Vector3(1.2, 0.8, 0.5),
	"bathtub": Vector3(1.7, 0.55, 0.8), "toilet": Vector3(0.7, 0.8, 0.55),
	"vanity": Vector3(0.9, 0.85, 0.52), "water_heater": Vector3(0.6, 1.6, 0.6),
	"workbench": Vector3(1.8, 0.9, 0.65), "washer": Vector3(0.62, 0.85, 0.62),
	"dryer": Vector3(0.62, 0.85, 0.62), "shelves": Vector3(1.6, 1.9, 0.45),
	"boxes": Vector3(1.0, 0.6, 0.7),
	"deck": Vector3(4.0, 0.15, 1.3), "path": Vector3(1.0, 0.02, 3.05),
	"road": Vector3(28.0, 0.0, 1.5), "driveway": Vector3(3.0, 0.02, 5.5),
	"step": Vector3(1.2, 0.15, 0.6), "car": Vector3(2.0, 1.45, 4.4),
	"dead_tree": Vector3(0.6, 4.5, 0.6), "trash_bin_tipped": Vector3(0.6, 0.6, 0.9),
	"pine": Vector3(0.6, 6.0, 0.6),
	"mailbox": Vector3(0.3, 1.2, 0.3), "streetlight_dead": Vector3(0.25, 4.5, 0.25),
	"door": Vector3(1.0, 2.1, 0.2), "barricade": Vector3(1.0, 2.0, 0.2),
	"crate": Vector3(0.9, 0.6, 0.6), "rain_collector": Vector3(1.0, 1.6, 1.0),
	"candle": Vector3(0.2, 0.18, 0.2), "lantern": Vector3(0.2, 0.32, 0.2),
	"bush": Vector3(1.2, 0.9, 1.0), "wall_ghost": Vector3(1.0, 2.6, 0.2),
	"boards": Vector3(1.0, 1.3, 0.08), "fuse_box": Vector3(0.5, 0.7, 0.16), "rubble": Vector3(1.0, 0.2, 1.0),
	"ceiling_light": Vector3(0.42, 0.2, 0.42), "range_hood": Vector3(0.75, 0.55, 0.5),
	"table_lamp": Vector3(0.26, 0.42, 0.26), "bare_bulb": Vector3(0.12, 0.4, 0.12),
	"bulb": Vector3(0.1, 0.12, 0.1), "light_switch": Vector3(0.09, 0.13, 0.03),
	"fireplace": Vector3(1.5, 2.6, 0.55),
	"cupboard": Vector3(1.0, 0.92, 0.6), "storage_chest": Vector3(1.0, 0.6, 0.55), "tool_cabinet": Vector3(0.9, 1.8, 0.45),
	"painting": Vector3(0.8, 0.6, 0.05), "loot_pile": Vector3(0.8, 0.3, 0.8),
}

## Documented reach beyond the requested size, in the canonical frame:
## [each side across the front, above the height, toward the front, toward the back].
## Everything else stays inside the size (plus clutter up to ~0.1 m on tops).
const OVERHANG := {
	"bed": [0.03, 0.42, 0.0, 0.03],                 # headboard
	"sink_counter": [0.0, 0.36, 0.12, 0.0],         # faucet, a cabinet door ajar
	"vanity": [0.0, 1.1, 0.12, 0.06],               # mirror on the wall behind, a door ajar
	"workbench": [0.0, 1.0, 0.0, 0.05],             # pegboard on the wall behind
	"water_heater": [0.0, 0.36, 0.0, 0.08],         # pipes into the wall
	"streetlight_dead": [0.15, 0.25, 1.65, 0.15],   # arm over the road
	"dead_tree": [2.3, 0.3, 2.3, 2.3],              # crown (the size is the trunk)
	"pine": [1.25, 0.05, 1.25, 1.25],               # crown (the size is the trunk)
	"car": [0.75, 0.0, 0.05, 0.05],                 # driver door hanging open
	"trash_bin_tipped": [0.3, 0.0, 0.75, 0.1],      # spilled bags and litter
	"mailbox": [0.04, 0.08, 0.3, 0.14],             # leaning; box and open lid past the post
	"counter": [0.0, 0.0, 0.12, 0.0],               # a cabinet door left ajar
	"island": [0.0, 0.0, 0.12, 0.0],
	"wardrobe": [0.0, 0.0, 0.1, 0.0],               # a door ajar
	"dresser": [0.0, 0.0, 0.1, 0.0],                # a drawer pulled out
	"plant": [0.18, 0.0, 0.18, 0.18],               # drooping leaves
	"bush": [0.1, 0.05, 0.1, 0.1],
	"barricade": [0.0, 0.0, 0.2, 0.0],              # broken pieces at the foot
	"boards": [0.06, 0.0, 0.0, 0.0],                # planks run past the window
	"fuse_box": [0.0, 0.3, 0.12, 0.0],              # conduit up into the wall, the open lid
	"road": [0.0, 0.07, 0.0, 0.0],                  # curb
	"path": [0.0, 0.03, 0.0, 0.0],
	"driveway": [0.0, 0.03, 0.0, 0.0],
	"rug": [0.0, 0.06, 0.0, 0.0],                   # folded corner
	"fireplace": [0.0, 0.0, 0.3, 0.0],              # the hearth slab in front
}

const DOOR_SWING := 1.65          ## radians for set_door_open(node, ±1)
const DAMAGE_STEPS := 20          ## damage is quantised to 1/20 for the cache
const CACHE_LIMIT := 1024

## Optional light per emissive type (opts.light): colour, energy, range, height fraction.
const LIGHTS := {
	"candle": {"color": Color(1.0, 0.62, 0.3), "energy": 1.3, "range": 3.6, "y": 0.95},
	"lantern": {"color": Color(1.0, 0.84, 0.64), "energy": 1.6, "range": 5.5, "y": 0.5},
}

static var _cache := {}
static var _hits := 0
static var _builds := 0


static func types() -> PackedStringArray:
	return PackedStringArray(FURNITURE_TYPES + PROP_TYPES + SURVIVAL_TYPES + HOME_TYPES + STORAGE_TYPES)


static func has(type: String) -> bool:
	return type in FURNITURE_TYPES or type in PROP_TYPES or type in SURVIVAL_TYPES or type in HOME_TYPES or type in STORAGE_TYPES


## Canonical default size (w across the front, h, d front to back).
static func default_size(type: String) -> Vector3:
	return DEFAULT_SIZE.get(type, DEFAULT_SIZE["crate"])


static func make(type: String, size: Vector3, opts := {}) -> Node3D:
	var t := type if has(type) else "crate"
	var facing := _facing(opts)
	var dims := canonical_size(t, size, facing)
	var seed := int(opts.get("seed", 0))
	var damage := _quantise(float(opts.get("damage", 0.0)))
	var style := str(opts.get("style", ""))
	var root := Node3D.new()
	root.name = type.capitalize().replace(" ", "") if type != "" else "Prop"
	root.basis = facing_basis(facing)
	root.set_meta("prop_type", t)
	root.set_meta("prop_requested_type", type)
	root.set_meta("prop_dims", dims)
	root.set_meta("prop_seed", seed)
	root.set_meta("prop_style", style)
	root.set_meta("prop_damage", damage)
	root.set_meta("prop_facing", facing)
	var parts := _parts(t, dims, damage, seed, style)
	var ghost := bool(opts.get("ghost", false)) or t == "wall_ghost"
	var body := MeshInstance3D.new()
	body.name = "Mesh"
	body.mesh = parts["body"]
	_dress(body, t, ghost)
	root.add_child(body)
	if parts.has("leaf"):
		var leaf := Node3D.new()
		leaf.name = "Leaf"
		leaf.position = parts["hinge"]
		var lm := MeshInstance3D.new()
		lm.name = "Mesh"
		lm.mesh = parts["leaf"]
		_dress(lm, t, ghost)
		leaf.add_child(lm)
		root.add_child(leaf)
	if bool(opts.get("light", false)) and LIGHTS.has(t) and not ghost:
		var spec: Dictionary = LIGHTS[t]
		var o := OmniLight3D.new()
		o.name = "Light"
		o.light_color = spec["color"]
		o.omni_range = spec["range"]
		o.omni_attenuation = 1.4
		o.shadow_enabled = true
		o.shadow_bias = 0.05
		o.light_specular = 0.3
		o.position = Vector3(0, dims.y * float(spec["y"]) + 0.02, 0)
		o.set_meta("base_energy", spec["energy"])
		o.light_energy = 0.0
		o.visible = false
		root.add_child(o)
	if opts.has("lit"):
		var v = opts["lit"]
		set_lit(root, (1.0 if v else 0.0) if typeof(v) == TYPE_BOOL else float(v))
	if ghost and opts.has("tint"):
		set_tint(root, opts["tint"])
	return root


## Emissive parts (candle flames and wax, lantern diffusers) and the optional light.
static func set_lit(node: Node, amount: float) -> void:
	amount = clampf(amount, 0.0, 1.0)
	for g in _geometry(node):
		g.set_instance_shader_parameter("lit", amount)
	var light := node.get_node_or_null("Light") as Light3D
	if light != null:
		light.light_energy = float(light.get_meta("base_energy", 1.0)) * amount
		light.visible = amount > 0.01
	node.set_meta("prop_lit", amount)


## Preview colour for ghosts (wall_ghost or opts.ghost): rgb + alpha.
static func set_tint(node: Node, color: Color) -> void:
	for g in _geometry(node):
		g.set_instance_shader_parameter("tint", color)


## Swap in the meshes for a new damage value; keeps the node, its transform
## and the door leaf's current swing.
static func set_damage(node: Node3D, damage: float) -> void:
	if not node.has_meta("prop_type"):
		return
	var q := _quantise(damage)
	var parts := _parts(node.get_meta("prop_type"), node.get_meta("prop_dims"), q,
			node.get_meta("prop_seed"), node.get_meta("prop_style"))
	var body := node.get_node_or_null("Mesh") as MeshInstance3D
	if body != null:
		body.mesh = parts["body"]
	var leaf := node.get_node_or_null("Leaf/Mesh") as MeshInstance3D
	if leaf != null and parts.has("leaf"):
		leaf.mesh = parts["leaf"]
	node.set_meta("prop_damage", q)


## Door: amount 0 = closed, +1 swings the leaf to the front (-Z side before
## facing), -1 to the back. V may also rotate "Leaf" about Y directly.
static func set_door_open(node: Node3D, amount: float) -> void:
	var leaf := node.get_node_or_null("Leaf") as Node3D
	if leaf != null:
		leaf.rotation.y = clampf(amount, -1.0, 1.0) * DOOR_SWING


## Rotation that turns the canonical front (-Z) to the facing direction.
static func facing_basis(facing: String) -> Basis:
	match facing:
		"E":
			return Basis(Vector3.UP, -PI * 0.5)
		"S":
			return Basis(Vector3.UP, PI)
		"W":
			return Basis(Vector3.UP, PI * 0.5)
	return Basis.IDENTITY


## Canonical size (w across the front, h, d front to back) for a world-space size.
static func canonical_size(type: String, size: Vector3, facing := "N") -> Vector3:
	var def := default_size(type)
	var turned := facing == "E" or facing == "W"
	var sx := size.x
	var sz := size.z
	if sx <= 0.0 and sz <= 0.0:
		return def
	var w := sz if turned else sx
	var d := sx if turned else sz
	if type in SPAN_TYPES:
		var a := maxf(sx, sz)
		var b := minf(sx, sz)
		w = a if a > 0.0 else def.x
		d = b if b > 0.0 else def.z
	if w <= 0.0:
		w = def.x
	if d <= 0.0:
		d = def.z
	var h := size.y
	if h <= 0.0 and not type in FLAT_TYPES:
		h = def.y
	return Vector3(w, maxf(h, 0.0), d)


## The box a piece may occupy, in the root's parent frame (facing applied):
## the size plus the documented OVERHANG for its type.
static func max_bounds(type: String, size: Vector3, facing := "N") -> AABB:
	var t := type if has(type) else "crate"
	var c := canonical_size(t, size, facing)
	var o: Array = OVERHANG.get(t, [0.0, 0.0, 0.0, 0.0])
	var lo := Vector3(-c.x * 0.5 - o[0], 0.0, -c.z * 0.5 - o[2])
	var hi := Vector3(c.x * 0.5 + o[0], c.y + o[1], c.z * 0.5 + o[3])
	var b := facing_basis(facing)
	var out := AABB(b * lo, Vector3.ZERO)
	for i in 8:
		var p := Vector3(hi.x if i & 1 else lo.x, hi.y if i & 2 else lo.y, hi.z if i & 4 else lo.z)
		out = out.expand(b * p)
	return out


## Bounds of everything a made piece draws, in its parent's frame (doors as they stand).
static func node_bounds(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = m
		while n != null and n != node:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var a := node.transform * xf * m.mesh.get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	return out


static func triangle_count(node: Node) -> int:
	var n := 0
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m == null:
			continue
		for s in m.get_surface_count():
			n += (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


static func clear_cache() -> void:
	_cache.clear()


static func cache_stats() -> Dictionary:
	return {"entries": _cache.size(), "hits": _hits, "builds": _builds}


# --- internals --------------------------------------------------------------------------------

static func _facing(opts: Dictionary) -> String:
	var f := str(opts.get("facing", "N")).to_upper()
	return f if f in ["N", "E", "S", "W"] else "N"


static func _quantise(damage: float) -> float:
	return roundf(clampf(damage, 0.0, 1.0) * DAMAGE_STEPS) / DAMAGE_STEPS


static func _dress(mi: MeshInstance3D, type: String, ghost: bool) -> void:
	if ghost:
		mi.material_override = PropMaterials.ghost()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif type in FLAT_TYPES:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _geometry(node: Node) -> Array:
	var out: Array = []
	if node is GeometryInstance3D:
		out.append(node)
	out.append_array(node.find_children("*", "GeometryInstance3D", true, false))
	return out


## Cached {"body": ArrayMesh, ["leaf": ArrayMesh, "hinge": Vector3]}.
static func _parts(type: String, dims: Vector3, damage: float, seed: int, style: String) -> Dictionary:
	var key := "%s|%d|%d|%d|%d|%d|%s" % [type, roundi(dims.x * 1000.0), roundi(dims.y * 1000.0),
			roundi(dims.z * 1000.0), roundi(damage * DAMAGE_STEPS), seed, style]
	if _cache.has(key):
		_hits += 1
		return _cache[key]
	if _cache.size() >= CACHE_LIMIT:
		_cache.clear()
	_builds += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s#%d" % [type, seed])
	var parts := {}
	if type == "door":
		parts = Survival.door(dims.x, dims.y, dims.z, rng, damage, style)
	else:
		var mm := _new_mesh(type, damage)
		var done := Furniture.build(mm, type, dims.x, dims.y, dims.z, rng, damage)
		if not done:
			done = Yard.build(mm, type, dims.x, dims.y, dims.z, rng, damage)
		if not done:
			done = Survival.build(mm, type, dims.x, dims.y, dims.z, rng, damage, style)
		if not done:
			done = Home.build(mm, type, dims.x, dims.y, dims.z, rng, damage)
		if not done:
			done = StorageProps.build(mm, type, dims.x, dims.y, dims.z, rng, damage)
		if not done or mm.is_empty():
			mm = _new_mesh("crate", damage)
			Survival.build(mm, "crate", dims.x, dims.y, dims.z, rng, damage, "")
		parts["body"] = mm.commit()
	for k in ["body", "leaf"]:
		if parts.has(k):
			var mesh: ArrayMesh = parts[k]
			if mesh.get_surface_count() > 0:
				mesh.surface_set_material(0, PropMaterials.kit())
	_cache[key] = parts
	return parts


static func _new_mesh(type: String, damage: float) -> PropMesh:
	var mm := PropMesh.new()
	# Builders work with the front toward +Z; turn it to the canonical -Z.
	mm.xf = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	mm.wear_bias = damage * 0.45 + (0.12 if type in OUTDOOR else 0.0)
	return mm
