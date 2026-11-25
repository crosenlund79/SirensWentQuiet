class_name DefenseObjects
extends RefCounted
## Exp 006 (D): the looks and the drawbridge mechanics of the defence
## WorldObject kinds (WorldObject.DEFS: "spikes_wood", "spikes_metal",
## "drawbridge_1", "drawbridge_2"). WorldObject calls make() for the visual
## and apply_bridge() whenever a drawbridge is raised or lowered.
##
## Built with PropMesh and the props' kit material, in the canonical prop
## frame: the front (the attackers' side) faces -Z.
##   spikes      a 1 m cheval-de-frise on a wall line: crossed, sharpened
##               stakes (wood) or steel bars on a rail (metal), pointing out
##               both ways; broken stakes drop away with damage
##   drawbridge  a plank deck spanning 1 or 2 trench cells (size.z), hinged
##               at its back (house side) end between two posts, with chains
##               to the far end; raised it stands upright at the hinge
## A drawbridge's `open` is "lowered". Raised, its collision is the upright
## deck at the hinge (bodies only, like a barricade); lowered, it has none
## (bodies walk on the deck at ground level).

const RAISED := 1.5          ## rad the deck turns up when raised (about 86 degrees)
const RAISE_TIME := 1.1
const LOWER_TIME := 0.7
const POST := 0.12
const PLANK_W := [Color(0.5, 0.39, 0.27), Color(0.45, 0.35, 0.25), Color(0.56, 0.44, 0.3), Color(0.42, 0.33, 0.24)]
const STEEL := Color(0.36, 0.37, 0.38)


static func handles(kind: String) -> bool:
	return DefenseGrid.is_bridge(kind) or DefenseGrid.is_spikes(kind)


## The visual of a defence object (size = WorldObject size: w, h, d).
static func make(kind: String, size: Vector3, seed: int, damage: float) -> Node3D:
	var root := Node3D.new()
	root.name = kind.capitalize().replace(" ", "")
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s#%d" % [kind, seed])
	if DefenseGrid.is_spikes(kind):
		var mm := PropMesh.new()
		if kind == "spikes_metal":
			_metal_spikes(mm, size, rng, damage)
		else:
			_wood_spikes(mm, size, rng, damage)
		root.add_child(_mesh(mm, "Mesh"))
		return root
	var span := size.z
	var post_h := 1.45 if span < 1.5 else 2.3
	# fixed part: the sill on the land behind the hinge, two posts, a cross bar
	var fm := PropMesh.new()
	fm.set_mat(PropMaterials.L_ROUGH_WOOD, PLANK_W[2].darkened(0.15), 0.35)
	fm.box(Vector3(-0.62, -0.04, span * 0.5 - 0.02), Vector3(0.62, 0.07, span * 0.5 + 0.24))
	fm.grain_v = true
	for sx in [-1.0, 1.0]:
		var x: float = sx * 0.6
		fm.box(Vector3(x - POST * 0.5, -0.04, span * 0.5 + 0.06), Vector3(x + POST * 0.5, post_h, span * 0.5 + 0.06 + POST))
	fm.grain_v = false
	fm.box(Vector3(-0.66, post_h - 0.1, span * 0.5 + 0.05), Vector3(0.66, post_h, span * 0.5 + 0.07 + POST))
	fm.set_mat(PropMaterials.L_METAL, STEEL, 0.4)
	for sx in [-1.0, 1.0]:
		fm.cylinder(Vector3(sx * 0.6, post_h - 0.26, span * 0.5 + 0.0), 0.05, 0.05, 0.06, 8)    # pulley
	root.add_child(_mesh(fm, "Frame"))
	# the deck, hinged at the back end
	var deck := Node3D.new()
	deck.name = "Deck"
	deck.position = Vector3(0, 0.02, span * 0.5)
	var dm := PropMesh.new()
	var n := maxi(int(round(span / 0.2)), 5)
	var pitch := span / n
	for i in n:
		var broken := damage > 0.3 and rng.randf() < (damage - 0.25) * 0.6
		var z0 := -pitch * (i + 1) + 0.012
		var z1 := -pitch * i - 0.012
		var col: Color = (PLANK_W[rng.randi() % PLANK_W.size()] as Color).darkened(rng.randf_range(0.0, 0.12))
		dm.set_mat(PropMaterials.L_ROUGH_WOOD, col, rng.randf_range(0.15, 0.4) + damage * 0.3)
		if broken:
			var cut := rng.randf_range(-0.2, 0.25)
			dm.box(Vector3(-0.5, 0.0, z0), Vector3(cut, 0.055, z1))
		else:
			dm.box(Vector3(-0.5, 0.0, z0), Vector3(0.5, 0.055, z1))
	dm.set_mat(PropMaterials.L_ROUGH_WOOD, PLANK_W[3].darkened(0.2), 0.35)
	for sx in [-1.0, 1.0]:
		dm.box(Vector3(sx * 0.38 - 0.05, -0.1, -span + 0.02), Vector3(sx * 0.38 + 0.05, 0.0, -0.02))
	dm.set_mat(PropMaterials.L_METAL, STEEL, 0.5)
	for z in [-0.12, -span * 0.5, -span + 0.12]:
		dm.box(Vector3(-0.51, 0.055, z - 0.03), Vector3(0.51, 0.065, z + 0.03))
	for sx in [-1.0, 1.0]:
		dm.cylinder(Vector3(sx * 0.45, 0.055, -span + 0.08), 0.035, 0.035, 0.05, 6)     # chain eyes
	deck.add_child(_mesh(dm, "Mesh"))
	root.add_child(deck)
	# chains from the pulleys to the far end (posed with the deck)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.014
	cm.bottom_radius = 0.014
	cm.height = 1.0
	cm.radial_segments = 5
	cm.rings = 1
	var chain_mat := StandardMaterial3D.new()
	chain_mat.albedo_color = Color(0.2, 0.2, 0.21)
	chain_mat.metallic = 0.6
	chain_mat.roughness = 0.5
	for sx in [-1.0, 1.0]:
		var c := MeshInstance3D.new()
		c.name = "ChainL" if sx < 0 else "ChainR"
		c.mesh = cm
		c.material_override = chain_mat
		c.set_meta("from", Vector3(sx * 0.6, post_h - 0.26, span * 0.5))
		c.set_meta("tip", Vector3(sx * 0.45, 0.09, -span + 0.08))
		root.add_child(c)
	root.set_meta("span", span)
	return root


static func _mesh(mm: PropMesh, nm: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var m := mm.commit()
	if m.get_surface_count() > 0:
		m.surface_set_material(0, PropMaterials.kit())
	mi.mesh = m
	return mi


static func _wood_spikes(mm: PropMesh, size: Vector3, rng: RandomNumberGenerator, damage: float) -> void:
	var w := size.x
	var h := size.y
	var d := size.z
	mm.set_mat(PropMaterials.L_BARK, Color(0.36, 0.28, 0.2), 0.35)
	mm.tube(Vector3(-w * 0.5 + 0.02, h * 0.36, 0), Vector3(w * 0.5 - 0.02, h * 0.36, 0), 0.06, 0.06, 7)
	var n := 5
	for i in n:
		var x := -w * 0.5 + (i + 0.5) * w / n + rng.randf_range(-0.03, 0.03)
		for back in [false, true]:
			var s := 1.0 if back else -1.0
			var gone := rng.randf() < damage * 0.8
			var foot := Vector3(x + rng.randf_range(-0.02, 0.02), 0.0, -s * d * 0.42)
			var tip := Vector3(x + rng.randf_range(-0.04, 0.04), h * rng.randf_range(0.82, 1.0), s * d * 0.55)
			if gone:
				tip = foot.lerp(tip, rng.randf_range(0.35, 0.5))
			var mid := foot.lerp(tip, 0.78)
			mm.set_mat(PropMaterials.L_ROUGH_WOOD, PLANK_W[rng.randi() % PLANK_W.size()], 0.3 + damage * 0.3)
			mm.tube(foot, mid, 0.034, 0.026, 6)
			mm.set_mat(PropMaterials.L_WOOD, Color(0.78, 0.66, 0.48), 0.1)        # the freshly cut point
			mm.tube(mid, tip, 0.026, 0.003 if not gone else 0.022, 6)


static func _metal_spikes(mm: PropMesh, size: Vector3, rng: RandomNumberGenerator, damage: float) -> void:
	var w := size.x
	var h := size.y
	var d := size.z
	mm.set_mat(PropMaterials.L_METAL, STEEL.darkened(0.15), 0.45)
	mm.box(Vector3(-w * 0.5 + 0.02, h * 0.3, -0.035), Vector3(w * 0.5 - 0.02, h * 0.3 + 0.07, 0.035))
	for sx in [-1.0, 1.0]:      # two crossed feet at the ends
		var x: float = sx * (w * 0.5 - 0.06)
		mm.tube(Vector3(x, 0.0, -d * 0.45), Vector3(x, h * 0.34, 0), 0.025, 0.025, 6)
		mm.tube(Vector3(x, 0.0, d * 0.45), Vector3(x, h * 0.34, 0), 0.025, 0.025, 6)
	var n := 7
	for i in n:
		var x := -w * 0.5 + (i + 0.5) * w / n
		var s := 1.0 if i % 2 == 0 else -1.0
		var gone := rng.randf() < damage * 0.7
		var foot := Vector3(x, h * 0.3, -s * d * 0.18)
		var tip := Vector3(x + rng.randf_range(-0.02, 0.02), h * rng.randf_range(0.9, 1.05), s * d * 0.5)
		if gone:
			tip = foot.lerp(tip, 0.4)
		mm.set_mat(PropMaterials.L_RUST if rng.randf() < 0.4 else PropMaterials.L_METAL, STEEL.lerp(Color(0.45, 0.3, 0.22), rng.randf_range(0.0, 0.4)), 0.35 + damage * 0.3)
		mm.tube(foot, tip, 0.02, 0.002 if not gone else 0.016, 5)
		mm.tube(Vector3(x, h * 0.3, s * d * 0.16), Vector3(x + 0.01, h * 0.62, -s * d * 0.42), 0.017, 0.002, 5)


# --- drawbridges ---------------------------------------------------------------------------

## Raises or lowers a drawbridge's deck and switches its collision (the
## WorldObject's own box: the upright deck at the hinge while raised).
static func apply_bridge(o: WorldObject, shape: CollisionShape3D, instant: bool) -> void:
	var span := float(DefenseGrid.span_of(o.kind))
	if shape != null:
		var box := shape.shape as BoxShape3D
		if box != null and not o.open:
			box.size = Vector3(1.0, span, 0.18)
			shape.position = Vector3(0, span * 0.5, span * 0.5 - 0.09)
		shape.set_deferred("disabled", o.open)
	var goal := 0.0 if o.open else RAISED
	var cur := float(o.get_meta("deck_angle", goal))
	if instant or not o.is_inside_tree() or is_equal_approx(cur, goal):
		o.set_meta("deck_angle", goal)
		pose_bridge(o)
		return
	if o.has_meta("deck_tween"):
		var old = o.get_meta("deck_tween")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	var tw := o.create_tween()
	o.set_meta("deck_tween", tw)
	tw.tween_method(func(a: float) -> void:
		if is_instance_valid(o):
			o.set_meta("deck_angle", a)
			pose_bridge(o), cur, goal, LOWER_TIME if o.open else RAISE_TIME) \
		.set_trans(Tween.TRANS_QUAD if o.open else Tween.TRANS_SINE).set_ease(Tween.EASE_IN if o.open else Tween.EASE_IN_OUT)


## Puts the deck (and the chains) at the object's current angle.
static func pose_bridge(o: WorldObject) -> void:
	var v := o.visual
	if v == null or not is_instance_valid(v):
		return
	var a := float(o.get_meta("deck_angle", 0.0 if o.open else RAISED))
	var deck := v.get_node_or_null("Deck") as Node3D
	if deck == null:
		return
	deck.rotation.x = a
	var hinge := deck.position
	for nm in ["ChainL", "ChainR"]:
		var c := v.get_node_or_null(nm) as MeshInstance3D
		if c == null:
			continue
		var from: Vector3 = c.get_meta("from")
		var tip: Vector3 = c.get_meta("tip")
		var t := hinge + Vector3(tip.x, tip.y * cos(a) - tip.z * sin(a), tip.y * sin(a) + tip.z * cos(a))
		var dv := t - from
		var l := dv.length()
		if l < 0.05:
			c.visible = false
			continue
		c.visible = true
		var b := Basis(Quaternion(Vector3.UP, dv / l)) * Basis.from_scale(Vector3(1, l, 1))
		c.transform = Transform3D(b, (from + t) * 0.5)


## The E prompt of a drawbridge.
static func bridge_prompt(o: WorldObject) -> String:
	if not o.open:
		return "[E] Lower the drawbridge"
	if o.hp < ceili(o.max_hp * DefenseGrid.RAISE_MIN_HP):
		return "[E] Drawbridge (too damaged to raise: repair it)"
	return "[E] Raise the drawbridge"
