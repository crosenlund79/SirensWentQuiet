extends "res://tests/test_case.gd"
## PropKit (SPEC §7.5): every type builds a non-empty mesh that fits its size,
## facing rotates, doors have a hinged Leaf, damage changes barricades,
## meshes are cached and shared, unknown types fall back, emissive parts and
## ghosts take their instance parameters, textures resolve through
## AssetResolver, and nothing depends on the Experiment 001 modular demo.

const TOL_XZ := 0.06     # small overhangs (handles, lips, chamfers)
const TOL_TOP := 0.12    # clutter on tops (books, mugs, a suitcase)


static func _plan_size(type: String) -> Array:
	for f in HousePlan.FURNITURE + HousePlan.PROPS:
		if f["type"] == type:
			var r: Rect2 = f["rect"]
			return [Vector3(r.size.x, f["height"], r.size.y), f["facing"]]
	return [PropKit.default_size(type), "N"]


func _fits(type: String, size: Vector3, facing: String, n: Node3D) -> bool:
	var b := PropKit.node_bounds(n)
	var m := PropKit.max_bounds(type, size, facing)
	var ok := check(b.position.x >= m.position.x - TOL_XZ and b.end.x <= m.end.x + TOL_XZ
			and b.position.z >= m.position.z - TOL_XZ and b.end.z <= m.end.z + TOL_XZ,
			"%s (%s, %s): footprint %s..%s outside %s..%s" % [type, size, facing, b.position, b.end, m.position, m.end])
	ok = check(b.end.y <= m.end.y + TOL_TOP and b.position.y >= -0.06,
			"%s: height %s..%s outside 0..%s" % [type, b.position.y, b.end.y, m.end.y]) and ok
	return ok


func test_every_type_builds_and_fits() -> void:
	var types := PropKit.types()
	for f in HousePlan.FURNITURE + HousePlan.PROPS:
		check(f["type"] in types and PropKit.has(f["type"]), "plan type %s is listed" % f["type"])
	for t in ["door", "barricade", "crate", "rain_collector", "candle", "lantern", "bush", "wall_ghost"]:
		check(t in types and PropKit.has(t), "%s is listed" % t)
	for t in types:
		var ps := _plan_size(t)
		var size: Vector3 = ps[0]
		var facing: String = ps[1]
		var n := PropKit.make(t, size, {"facing": facing, "seed": 7})
		add(n)
		var mi := n.get_node_or_null("Mesh") as MeshInstance3D
		if not check(mi != null and mi.mesh != null and mi.mesh.get_surface_count() == 1, "%s has one Mesh with one surface" % t):
			continue
		check(PropKit.triangle_count(n) > 0, "%s mesh is not empty" % t)
		check(n.find_children("*", "CollisionObject3D", true, false).is_empty(), "%s is visual only" % t)
		_fits(t, size, facing, n)
		# and it fills its box: no degenerate builders
		var b := PropKit.node_bounds(n)
		var c := PropKit.canonical_size(t, size, facing)
		var world := PropKit.facing_basis(facing) * Vector3(c.x, 0, c.z)
		for axis in [0, 2]:
			var want := absf(world[axis])
			if want > 0.15:
				check(b.size[axis] >= want * 0.4, "%s fills its footprint along %d (%.2f of %.2f)" % [t, axis, b.size[axis], want])
		if c.y > 0.15:
			check(b.size.y >= c.y * 0.4, "%s fills its height (%.2f of %.2f)" % [t, b.size.y, c.y])


func test_every_plan_piece_fits_its_rect() -> void:
	for f in HousePlan.FURNITURE + HousePlan.PROPS:
		var r: Rect2 = f["rect"]
		var size := Vector3(r.size.x, f["height"], r.size.y)
		var n := PropKit.make(f["type"], size, {"facing": f["facing"], "seed": hash(f["id"])})
		add(n)
		_fits(f["type"], size, f["facing"], n)


func test_facing_rotates() -> void:
	var expect := {"N": Vector3(0, 0, -1), "E": Vector3(1, 0, 0), "S": Vector3(0, 0, 1), "W": Vector3(-1, 0, 0)}
	var size := Vector3(0.45, 0.9, 0.42)
	for f in expect:
		var n := PropKit.make("chair", size, {"facing": f, "seed": 1})
		add(n)
		var front := n.basis * Vector3.FORWARD
		check(front.is_equal_approx(expect[f]), "facing %s turns the front to %s (got %s)" % [f, expect[f], front])
		# The backrest (everything above the seat) sits at the back, opposite the front.
		var mesh := (n.get_node("Mesh") as MeshInstance3D).mesh
		var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var c := Vector3.ZERO
		var k := 0
		for v in verts:
			if v.y > 0.6:
				c += v
				k += 1
		c = n.basis * (c / maxi(k, 1))
		check(c.dot(expect[f]) < -0.05, "facing %s: backrest is behind the front (centroid %s)" % [f, c])
	# A turned piece takes its plan rect as the world footprint and shares the mesh.
	var a := PropKit.make("sofa", Vector3(2.4, 0.85, 0.95), {"facing": "N", "seed": 3})
	var b := PropKit.make("sofa", Vector3(0.95, 0.85, 2.4), {"facing": "E", "seed": 3})
	add(a)
	add(b)
	check((a.get_node("Mesh") as MeshInstance3D).mesh == (b.get_node("Mesh") as MeshInstance3D).mesh, "N and E sofas share one mesh")
	var bb := PropKit.node_bounds(b)
	check(bb.size.x < 1.1 and bb.size.z > 2.2, "E sofa spans Z (%s)" % bb.size)


func test_door_has_hinged_leaf() -> void:
	for style in ["", "plank"]:
		var n := PropKit.make("door", Vector3(1.0, 2.1, 0.2), {"facing": "N", "style": style, "seed": 2})
		add(n)
		var leaf := n.get_node_or_null("Leaf") as Node3D
		if not check(leaf != null, "door (%s) has a child named Leaf" % style):
			continue
		check(leaf.get_parent() == n, "Leaf is a direct child")
		var lm := leaf.get_node_or_null("Mesh") as MeshInstance3D
		check(lm != null and lm.mesh != null and PropKit.triangle_count(leaf) > 0, "Leaf has a mesh")
		var la := lm.mesh.get_aabb()
		check(la.position.x > -0.02 and la.end.x > 0.85 and la.end.x < 0.95, "leaf extends ~0.9 m along +X from the hinge (%s..%s)" % [la.position.x, la.end.x])
		check(la.size.y > 1.98 and la.size.y < 2.1, "leaf is ~2.05 m tall (%.3f)" % la.size.y)
		check(absf(leaf.position.x + 0.45) < 0.03 and is_zero_approx(leaf.position.y), "hinge at the left jamb, on the floor (%s)" % leaf.position)
		var frame := (n.get_node("Mesh") as MeshInstance3D).mesh.get_aabb()
		check(frame.size.x <= 1.001 and frame.size.y <= 2.101, "frame fits the 1 x 2.1 m opening (%s)" % frame.size)
		check(frame.size.z >= 0.2 and frame.size.z <= 0.3, "frame spans the wall thickness (%.3f)" % frame.size.z)
		# Closed: the leaf stays inside the frame. Open: it swings out of the wall plane.
		check(PropKit.node_bounds(n).size.z <= frame.size.z + 0.01, "closed leaf stays in the frame")
		PropKit.set_door_open(n, 1.0)
		check(is_equal_approx(leaf.rotation.y, PropKit.DOOR_SWING), "set_door_open swings the leaf")
		var tip := leaf.transform * Vector3(0.9, 1.0, 0.0)
		check(tip.z < -0.7, "+1 opens toward the front (-Z) (tip %s)" % tip)
		PropKit.set_door_open(n, 0.0)
		check(is_zero_approx(leaf.rotation.y), "0 closes it")
	# Either span order works for span pieces.
	var turned := PropKit.make("door", Vector3(0.2, 2.1, 1.0), {"facing": "E"})
	add(turned)
	var tb := PropKit.node_bounds(turned)
	check(tb.size.z > 0.95 and tb.size.x < 0.35, "door facing E spans Z (%s)" % tb.size)


func test_barricade_damage_changes_mesh() -> void:
	var size := Vector3(1.0, 2.0, 0.2)
	var meshes := []
	var tris := []
	for dmg in [0.0, 0.5, 0.9]:
		var n := PropKit.make("barricade", size, {"seed": 4, "damage": dmg})
		add(n)
		meshes.append((n.get_node("Mesh") as MeshInstance3D).mesh)
		tris.append(PropKit.triangle_count(n))
		_fits("barricade", size, "N", n)
	check(meshes[0] != meshes[1] and meshes[1] != meshes[2], "each damage level has its own mesh")
	var v0: PackedVector3Array = (meshes[0] as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var v1: PackedVector3Array = (meshes[1] as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(v0 != v1, "damage 0.5 changes the geometry")
	# Broken planks leave gaps: less plank area facing the attacker at high damage.
	check(_front_area(meshes[2]) < _front_area(meshes[0]) * 0.8, "damage 0.9 removes planks (front area %.2f vs %.2f)" % [_front_area(meshes[2]), _front_area(meshes[0])])
	# set_damage swaps the mesh in place.
	var b := PropKit.make("barricade", size, {"seed": 4})
	add(b)
	PropKit.set_damage(b, 0.9)
	check((b.get_node("Mesh") as MeshInstance3D).mesh == meshes[2], "set_damage uses the cached damaged mesh")
	check(is_equal_approx(float(b.get_meta("prop_damage")), 0.9), "set_damage records the damage")


## Area of triangles facing the front (-Z) that lie in front of the uprights.
func _front_area(mesh: ArrayMesh) -> float:
	var arr := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var area := 0.0
	for i in range(0, v.size(), 3):
		if nrm[i].z < -0.9 and v[i].z < -0.04 and v[i].y > 0.15:
			area += (v[i + 1] - v[i]).cross(v[i + 2] - v[i]).length() * 0.5
	return area


func test_cache_returns_shared_meshes() -> void:
	PropKit.clear_cache()
	var before: int = PropKit.cache_stats()["hits"]
	var a := PropKit.make("crate", Vector3(0.9, 0.6, 0.6), {"seed": 9, "facing": "W"})
	var b := PropKit.make("crate", Vector3(0.6, 0.6, 0.9), {"seed": 9, "facing": "N"})
	var c := PropKit.make("crate", Vector3(0.9, 0.6, 0.6), {"seed": 10, "facing": "W"})
	for n in [a, b, c]:
		add(n)
	var ma := (a.get_node("Mesh") as MeshInstance3D).mesh
	var mb := (b.get_node("Mesh") as MeshInstance3D).mesh
	var mc := (c.get_node("Mesh") as MeshInstance3D).mesh
	check(ma == mb, "same piece, same mesh resource")
	check(ma != mc, "another seed builds another variant")
	check(int(PropKit.cache_stats()["hits"]) > before, "cache hit counted")
	check(ma.surface_get_material(0) == PropMaterials.kit() and mc.surface_get_material(0) == PropMaterials.kit(), "all pieces share the one kit material")
	var d1 := PropKit.make("door", Vector3(1, 2.1, 0.2), {"seed": 1})
	var d2 := PropKit.make("door", Vector3(1, 2.1, 0.2), {"seed": 1})
	add(d1)
	add(d2)
	check((d1.get_node("Leaf/Mesh") as MeshInstance3D).mesh == (d2.get_node("Leaf/Mesh") as MeshInstance3D).mesh, "door leaves are shared too")


func test_unknown_type_falls_back() -> void:
	check(not PropKit.has("spaceship"), "unknown type is not listed")
	var n := PropKit.make("spaceship", Vector3(0.8, 0.5, 0.6), {})
	if not check(n != null, "make never returns null"):
		return
	add(n)
	check(PropKit.triangle_count(n) > 0, "fallback has a mesh")
	check(n.get_meta("prop_type") == "crate", "fallback is a crate")
	_fits("crate", Vector3(0.8, 0.5, 0.6), "N", n)
	var z := PropKit.make("crate", Vector3.ZERO, {})
	add(z)
	check(PropKit.node_bounds(z).size.x > 0.3, "zero size falls back to the default size")


func test_lit_ghost_and_light() -> void:
	var c := PropKit.make("candle", Vector3(0.2, 0.18, 0.2), {"lit": true, "light": true})
	add(c)
	var mi := c.get_node("Mesh") as MeshInstance3D
	check(is_equal_approx(float(mi.get_instance_shader_parameter("lit")), 1.0), "opts.lit sets the instance parameter")
	var light := c.get_node_or_null("Light") as OmniLight3D
	check(light != null and light.visible and light.light_energy > 0.0, "opts.light adds a burning light")
	PropKit.set_lit(c, 0.0)
	check(is_zero_approx(float(mi.get_instance_shader_parameter("lit"))), "set_lit(0) puts it out")
	check(light != null and not light.visible, "the light goes out too")
	var g := PropKit.make("wall_ghost", Vector3(1, 2.6, 0.2), {})
	add(g)
	var gm := g.get_node("Mesh") as MeshInstance3D
	check(gm.material_override == PropMaterials.ghost(), "wall_ghost draws with the ghost material")
	check(gm.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "ghosts cast no shadow")
	PropKit.set_tint(g, Color(1, 0, 0, 0.4))
	check(gm.get_instance_shader_parameter("tint") == Color(1, 0, 0, 0.4), "set_tint sets the ghost colour")
	var gd := PropKit.make("door", Vector3(1, 2.1, 0.2), {"ghost": true})
	add(gd)
	check((gd.get_node("Leaf/Mesh") as MeshInstance3D).material_override == PropMaterials.ghost(), "opts.ghost previews any type")


func test_textures_resolve_and_override() -> void:
	var kit := PropMaterials.kit()
	for p in PropMaterials.TEXTURES:
		check(kit.get_shader_parameter(p) is Texture2D, "%s resolves" % p)
		var path := AssetResolver.fallback_path("props/" + PropMaterials.TEXTURES[p])
		check(ResourceLoader.exists(path), "template exists: %s" % path)
	# A creator override replaces a template after a restart (simulated by reset()).
	var dir := OS.get_user_data_dir().path_join("test_props_override")
	DirAccess.make_dir_recursive_absolute(dir.path_join("graphics/props"))
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 1))
	img.save_png(dir.path_join("graphics/props/wood_grain.png"))
	AssetResolver.set_override_root(dir)
	PropMaterials.reset()
	var tex: Texture2D = PropMaterials.kit().get_shader_parameter("t_wood")
	check(tex != null and tex.get_width() == 8, "override wood_grain is used")
	AssetResolver.set_override_root("")
	PropMaterials.reset()
	PropKit.clear_cache()
	DirAccess.remove_absolute(dir.path_join("graphics/props/wood_grain.png"))
	var t2: Texture2D = PropMaterials.kit().get_shader_parameter("t_wood")
	check(t2 != null and t2.get_width() > 8, "template is back after the override is removed")


func test_no_dependency_on_modular_demo() -> void:
	var d := DirAccess.open("res://src/props")
	for f in d.get_files():
		if not (f.ends_with(".gd") or f.ends_with(".gdshader") or f.ends_with(".tscn")):
			continue
		var text := FileAccess.get_file_as_string("res://src/props/" + f)
		check(not text.contains("res://src/modular") and not text.contains("graphics/modular") and not text.contains("modular/"),
				"%s does not reference the modular demo" % f)
		for cls in ["ModMesh", "ModMaterials", "ModFurnitureKit"]:
			check(not text.contains(cls), "%s does not use %s" % [f, cls])


## Experiment 003: the "iron" style of doors (reinforced door) and barricades.
func test_iron_styles() -> void:
	for dmg in [0.0, 0.5, 0.8]:
		var n := PropKit.make("door", Vector3(1.0, 2.1, 0.16), {"facing": "N", "style": "iron", "seed": 3, "damage": dmg})
		add(n)
		var leaf := n.get_node_or_null("Leaf") as Node3D
		check(leaf != null and PropKit.triangle_count(leaf) > 0, "reinforced door (%.1f) has a Leaf with a mesh" % dmg)
		var frame := (n.get_node("Mesh") as MeshInstance3D).mesh.get_aabb()
		check(frame.size.x <= 1.001 and frame.size.y <= 2.101, "its frame fits the opening (%s)" % frame.size)
		if dmg == 0.0:
			check(PropKit.node_bounds(n).size.z <= frame.size.z + 0.01, "closed, the plated leaf stays in the frame")
	var plain := PropKit.make("door", Vector3(1.0, 2.1, 0.16), {"style": "plank", "seed": 3})
	var iron := PropKit.make("door", Vector3(1.0, 2.1, 0.16), {"style": "iron", "seed": 3})
	add(plain)
	add(iron)
	check((plain.get_node("Leaf/Mesh") as MeshInstance3D).mesh != (iron.get_node("Leaf/Mesh") as MeshInstance3D).mesh, "the iron leaf is its own mesh")
	var size := Vector3(1.0, 1.5, 0.22)
	var meshes := []
	for dmg in [0.0, 0.5, 0.95]:
		var b := PropKit.make("barricade", size, {"style": "iron", "seed": 4, "damage": dmg})
		add(b)
		meshes.append((b.get_node("Mesh") as MeshInstance3D).mesh)
		check(PropKit.triangle_count(b) > 0, "iron barricade (%.2f) builds" % dmg)
		_fits("barricade", size, "N", b)
	check(meshes[0] != meshes[1] and meshes[1] != meshes[2], "damage changes the iron barricade")
	check(_front_area(meshes[2]) < _front_area(meshes[0]) * 0.8, "heavy damage tears bars off (%.2f vs %.2f)" % [_front_area(meshes[2]), _front_area(meshes[0])])
