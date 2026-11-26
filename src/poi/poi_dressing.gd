class_name PoiDressing
extends RefCounted
## Experiment 008 (H): what PoiWorld draws from a layout's optional "lights"
## and "story" keys (SPEC-008). Cheap, visual only (a story piece that stands
## tall gets a collision box through PoiWorld._block).
##
## lights  [{at, h, color, energy, flicker, kind, range, yaw}]: a small
##         OmniLight3D (no shadow) with its fixture. kind "tube" (a hanging
##         fluorescent tube), "emergency" (a wall-mounted emergency light),
##         "lamp" (a desk lamp left on, standing at h), "lantern" (a battery
##         lantern at h) or "bulb" (a bare bulb hanging to h; the default).
##         Always on, day and night (batteries and a failing inverter, not
##         the grid); flicker: a dying tube that blinks out now and then.
##         They join HouseWorld.night_lights (flagged "poi"), so room
##         visibility hides them with their room; PoiWorld._process drives them.
## story   [{type, at, yaw, ...}]: signs of the people who were here first.
##         toppled     a PropKit piece on its side ("piece", default chair)
##         spill       a cardboard box on its side, its contents strewn ("r")
##         papers      loose sheets and a folder or two ("r", "n")
##         glass       broken glass ("w", "d": the area)
##         planks      loose planks on the floor ("n", "len")
##         pallet      a wooden pallet ("load": "" | "bags" | "boxes")
##         camp        a sleeping bag, a lantern long dead, empty cans
##         barricade   a barricade someone began and gave up on ("len")
##         empty_rack  a gun rack with nothing on it ("rect", "facing", "h";
##                     it blocks)
##         rubble      a heap of debris

const LIGHT_RANGE := 4.5
const CEILING := 2.6               ## the top of the POI walls
const PAPER := Color(0.9, 0.89, 0.85)
const CARDBOARD := Color(0.64, 0.51, 0.35)
const PINE := Color(0.76, 0.62, 0.44)


## Builds the layout's lights and story pieces into the world.
static func place(w: PoiWorld) -> void:
	var k := 0
	for e in w.layout.get("lights", []):
		_light(w, e, k)
		k += 1
	k = 0
	for e in w.layout.get("story", []):
		_story(w, e, k)
		k += 1


# --- lights ------------------------------------------------------------------------------

static func _light(w: PoiWorld, e: Dictionary, k: int) -> void:
	var at: Vector2 = e["at"]
	var h := float(e.get("h", 2.4))
	var kind := str(e.get("kind", "bulb"))
	var col := VoxelArt.to_color(int(e.get("color", 0xffd9a0)))
	var root := Node3D.new()
	root.name = "PoiLight_%d_%s" % [k, kind]
	root.position = Vector3(at.x, 0, at.y)
	root.rotation.y = float(e.get("yaw", 0.0))
	w.add_child(root)
	var fixture: Node3D
	var glow := h
	match kind:
		"lamp":
			fixture = PropKit.make("table_lamp", PropKit.default_size("table_lamp"), {"seed": k})
			fixture.position.y = h
			glow = h + 0.3
		"lantern":
			fixture = PropKit.make("lantern", PropKit.default_size("lantern"), {"seed": k})
			fixture.position.y = h
			glow = h + 0.18
		"tube", "emergency":
			fixture = _fixture_mesh(kind, col, maxf(CEILING - h, 0.05))
			fixture.position.y = h
			glow = h - 0.15
		_:
			var drop := maxf(CEILING - h, 0.2)
			fixture = PropKit.make("bare_bulb", Vector3(0.12, drop, 0.12), {"seed": k})
			fixture.position.y = h
			glow = h + 0.05
	root.add_child(fixture)
	var geos := fixture.find_children("*", "GeometryInstance3D", true, false)
	if fixture is GeometryInstance3D:
		geos.append(fixture)
	for g in geos:
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var o := OmniLight3D.new()
	o.name = "Glow"
	o.light_color = col
	o.omni_range = float(e.get("range", LIGHT_RANGE))
	o.omni_attenuation = 1.5
	o.light_specular = 0.2
	o.shadow_enabled = false
	o.position = Vector3(0, glow, 0)
	root.add_child(o)
	w.night_lights.append({"node": root, "light": o, "base": float(e.get("energy", 1.0)), "phase": float(k) * 2.71 + 0.4,
		"geos": geos, "poi": true, "flicker": e.get("flicker", false) == true})


## A fluorescent tube in its housing on two wires up to the ceiling (`drop`
## above it), or a boxy emergency light on the wall (its face toward +z).
static func _fixture_mesh(kind: String, col: Color, drop: float) -> MeshInstance3D:
	var mm := PropMesh.new()
	if kind == "tube":
		mm.set_mat(PropMaterials.L_PLAIN, Color(0.08, 0.08, 0.08))
		for sx in [-0.45, 0.45]:
			mm.box(Vector3(sx - 0.004, 0.04, -0.004), Vector3(sx + 0.004, drop, 0.004))
		mm.set_mat(PropMaterials.L_METAL, Color(0.78, 0.78, 0.76), 0.2)
		mm.box(Vector3(-0.62, 0.0, -0.08), Vector3(0.62, 0.06, 0.08))
		mm.set_mat(PropMaterials.L_GLOW, col.lerp(Color.WHITE, 0.4))
		mm.box(Vector3(-0.58, -0.035, -0.035), Vector3(0.58, 0.0, 0.035))
	else:
		mm.set_mat(PropMaterials.L_PLAIN, Color(0.86, 0.85, 0.8), 0.1)
		mm.box(Vector3(-0.17, -0.07, -0.02), Vector3(0.17, 0.07, 0.06))
		mm.set_mat(PropMaterials.L_GLOW, col)
		mm.box(Vector3(-0.13, -0.045, 0.06), Vector3(0.13, 0.045, 0.075))
	var mi := MeshInstance3D.new()
	mi.name = "Fixture"
	mi.mesh = _commit(mm)
	return mi


static func _commit(mm: PropMesh) -> ArrayMesh:
	var mesh := mm.commit()
	if mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, PropMaterials.kit())
	return mesh


## Each frame after HouseWorld's candle flicker: POI lights burn day and
## night at their own energy; a flickering one drops out now and then.
static func update_lights(w: PoiWorld, t: float) -> void:
	for l in w.night_lights:
		if not l.get("poi", false):
			continue
		var o: OmniLight3D = l["light"]
		var f := flicker(t, float(l["phase"])) if l.get("flicker", false) else 1.0
		o.light_energy = float(l["base"]) * f
		o.visible = f > 0.01 and not l.get("room_hidden", false)
		for g in l["geos"]:
			if is_instance_valid(g):
				(g as GeometryInstance3D).set_instance_shader_parameter("lit", clampf(f, 0.0, 1.0))


## A dying fluorescent tube: steady with a faint hum, then bad spells where
## it blinks out (deterministic in t).
static func flicker(t: float, phase: float) -> float:
	var slot := floorf(t * 14.0)
	var r := fposmod(sin(slot * 12.9898 + phase * 78.233) * 43758.5453, 1.0)
	var bad := sin(t * 0.9 + phase * 3.1) > 0.35
	if bad and r < 0.45:
		return 0.0
	if r < 0.05:
		return 0.2
	return 0.93 + 0.07 * sin(t * 37.0 + phase)


# --- story -------------------------------------------------------------------------------

static func _story(w: PoiWorld, e: Dictionary, k: int) -> void:
	var type := str(e.get("type", ""))
	var at: Vector2 = e.get("at", Vector2.ZERO)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([w.poi_id, k, type])
	var root := Node3D.new()
	root.name = "Story_%d_%s" % [k, type]
	root.position = Vector3(at.x, 0, at.y)
	root.rotation.y = float(e.get("yaw", 0.0))
	w.add_child(root)
	var mm := PropMesh.new()
	match type:
		"toppled":
			var piece := str(e.get("piece", "chair"))
			var s := PropKit.default_size(piece)
			var n := PropKit.make(piece, s, {"seed": k})
			n.basis = Basis(Vector3.BACK, PI * 0.5)        # over onto its side
			n.position = Vector3(s.y * 0.5 - 0.05, s.x * 0.5, 0)
			root.add_child(n)
		"spill":
			_spill(mm, float(e.get("r", 0.6)), rng)
		"papers":
			_papers(mm, float(e.get("r", 0.7)), int(e.get("n", 12)), rng)
		"glass":
			_glass(mm, float(e.get("w", 1.6)), float(e.get("d", 0.8)), rng)
		"planks":
			_planks(mm, int(e.get("n", 4)), float(e.get("len", 2.2)), rng)
		"pallet":
			_pallet(mm, str(e.get("load", "")), rng)
		"camp":
			_camp(mm, rng)
			var lantern := PropKit.make("lantern", PropKit.default_size("lantern"), {"seed": k})
			lantern.position = Vector3(0.55, 0, -0.75)
			root.add_child(lantern)
		"barricade":
			var length := float(e.get("len", 1.2))
			var b := PropKit.make("barricade", Vector3(length, 1.4, 0.2), {"seed": k, "damage": 0.45})
			b.basis = Basis(Vector3.RIGHT, -0.22)            # propped against the wall behind it
			b.position = Vector3(0, 0, 0.12)
			root.add_child(b)
			_planks(mm, 2, 1.1, rng, Vector3(0, 0, 0.55))
		"empty_rack":
			var r: Rect2 = e["rect"]
			var facing := str(e.get("facing", "S"))
			var h := float(e.get("h", 1.9))
			root.position = Vector3(r.get_center().x, 0, r.get_center().y)
			root.rotation.y = HouseWorld.FACING_YAW.get(facing, 0.0)
			var ns := facing == "N" or facing == "S"
			root.add_child(PropKit.make("gun_rack", Vector3(r.size.x if ns else r.size.y, h, r.size.y if ns else r.size.x),
				{"facing": "N", "seed": k, "style": "empty"}))
			w._block(r, h, root)
		"rubble":
			root.add_child(PropKit.make("rubble", Vector3(float(e.get("w", 1.0)), 0.2, float(e.get("d", 1.0))), {"seed": k}))
	if not mm.is_empty():
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = _commit(mm)
		root.add_child(mi)


## A box on its side, flaps open, its contents out across the floor.
static func _spill(mm: PropMesh, r: float, rng: RandomNumberGenerator) -> void:
	mm.set_mat(PropMaterials.L_PAPER, CARDBOARD.darkened(rng.randf_range(0.0, 0.15)), 0.35)
	mm.obox(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.4, 0.4)), Vector3(0, 0.17, 0)), Vector3(0.45, 0.34, 0.36), ["+z"])
	mm.thin = true
	mm.obox(Transform3D(Basis(Vector3.RIGHT, 1.2), Vector3(0, 0.03, 0.3)), Vector3(0.43, 0.2, 0.01))
	mm.thin = false
	var cols := [Color(0.7, 0.3, 0.22), Color(0.55, 0.6, 0.62), Color(0.75, 0.65, 0.35), Color(0.25, 0.35, 0.5), Color(0.82, 0.8, 0.74)]
	for i in rng.randi_range(6, 10):
		var a := rng.randf_range(-1.2, 1.2) + PI * 0.5
		var d := rng.randf_range(0.3, r)
		var p := Vector3(cos(a) * d, 0, sin(a) * d)
		mm.set_mat(PropMaterials.L_METAL if i % 2 == 0 else PropMaterials.L_PLAIN, cols[rng.randi() % cols.size()], 0.3)
		if i % 2 == 0:
			mm.tube(p + Vector3(-0.05, 0.04, 0), p + Vector3(0.05, 0.04, 0), 0.04, 0.04, 8)
		else:
			mm.obox(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p + Vector3(0, 0.03, 0)), Vector3(0.12, 0.06, 0.09))


static func _papers(mm: PropMesh, r: float, n: int, rng: RandomNumberGenerator) -> void:
	mm.thin = true
	for i in n:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * r
		var folder := i % 5 == 4
		mm.set_mat(PropMaterials.L_PAPER, Color(0.75, 0.62, 0.38) if folder else PAPER.darkened(rng.randf_range(0.0, 0.12)), 0.2)
		mm.obox(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(cos(a) * d, 0.004 + 0.002 * i, sin(a) * d)),
			Vector3(0.24 if folder else 0.21, 0.003, 0.31 if folder else 0.29))
	mm.thin = false


static func _glass(mm: PropMesh, w: float, d: float, rng: RandomNumberGenerator) -> void:
	mm.set_mat(PropMaterials.L_GLOSSY, Color(0.72, 0.82, 0.86), 0.0)
	for i in rng.randi_range(12, 18):
		var p := Vector3(rng.randf_range(-w, w) * 0.5, 0.006, rng.randf_range(-d, d) * 0.5)
		var s := rng.randf_range(0.04, 0.14)
		mm.obox(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p), Vector3(s, 0.008, s * rng.randf_range(0.4, 0.9)))


static func _planks(mm: PropMesh, n: int, length: float, rng: RandomNumberGenerator, at := Vector3.ZERO) -> void:
	for i in n:
		mm.set_mat(PropMaterials.L_WOOD, PINE.darkened(rng.randf_range(0.0, 0.2)), 0.25)
		var p := at + Vector3(rng.randf_range(-0.15, 0.15), 0.02 + 0.042 * (i % 3), rng.randf_range(-0.3, 0.3))
		mm.obox(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.35, 0.35)), p), Vector3(length * rng.randf_range(0.7, 1.0), 0.04, 0.14))


## A pallet (1.2 x 1.0), maybe with a load of sacks or boxes.
static func _pallet(mm: PropMesh, load: String, rng: RandomNumberGenerator) -> void:
	mm.set_mat(PropMaterials.L_ROUGH_WOOD, PINE.darkened(0.25), 0.4)
	for z in [-0.42, 0.0, 0.42]:
		mm.box(Vector3(-0.6, 0.0, z - 0.06), Vector3(0.6, 0.1, z + 0.06))
	for i in 7:
		var x := -0.54 + i * 0.18
		mm.box(Vector3(x - 0.06, 0.1, -0.5), Vector3(x + 0.06, 0.13, 0.5))
	match load:
		"bags":
			mm.set_mat(PropMaterials.L_FABRIC, Color(0.7, 0.68, 0.62), 0.3)
			for layer in 2:
				for j in 3:
					var c := Vector3(0, 0.2 + layer * 0.14, -0.33 + j * 0.33)
					mm.obox(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.08, 0.08)), c), Vector3(1.0, 0.13, 0.3))
		"boxes":
			for j in 4:
				mm.set_mat(PropMaterials.L_PAPER, CARDBOARD.darkened(rng.randf_range(0.0, 0.2)), 0.3)
				var c := Vector3(-0.28 + (j % 2) * 0.56, 0.13 + 0.2, -0.24 + (j / 2) * 0.48)
				mm.obox(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.1, 0.1)), c), Vector3(0.5, 0.4, 0.44))


## Someone slept here for a while: a sleeping bag, a rolled jacket, cans.
static func _camp(mm: PropMesh, rng: RandomNumberGenerator) -> void:
	mm.set_mat(PropMaterials.L_FABRIC, Color(0.25, 0.36, 0.3), 0.3)
	mm.blob(Vector3(0, 0.06, 0), Vector3(0.36, 0.07, 0.95), 2, 8)
	mm.set_mat(PropMaterials.L_FABRIC, Color(0.42, 0.3, 0.24), 0.3)
	mm.blob(Vector3(0.02, 0.1, -0.85), Vector3(0.24, 0.08, 0.13), 2, 8)
	for i in 4:
		mm.set_mat(PropMaterials.L_METAL, [Color(0.7, 0.3, 0.22), Color(0.55, 0.6, 0.62)][i % 2], 0.4)
		var p := Vector3(rng.randf_range(0.45, 0.8), 0, rng.randf_range(-0.4, 0.5))
		if i == 3:
			mm.tube(p + Vector3(-0.05, 0.04, 0), p + Vector3(0.05, 0.04, 0), 0.04, 0.04, 8)
		else:
			mm.cylinder(p, 0.04, 0.04, 0.11, 8)
	mm.set_mat(PropMaterials.L_GLOSSY, Color(0.55, 0.72, 0.85), 0.1)
	mm.cylinder(Vector3(0.7, 0, 0.7), 0.035, 0.035, 0.24, 8)
