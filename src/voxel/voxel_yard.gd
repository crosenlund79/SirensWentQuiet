class_name VoxelYard
extends Node3D
## The outside of Version A: a voxel-resolution ground image (one texel per
## 0.1 m), voxel props from HousePlan.PROPS with collision boxes, grass tufts,
## and a flat voxel roof that dissolves while the player is inside the house
## (it keeps casting shadows, so light still enters only through windows and holes).

const VS := 0.1
const GROUND_Y := -0.03
const IMG_ORIGIN := Vector2(-15.0, -13.0)
const IMG_SIZE := Vector2(44.0, 36.0)
const ROOF_ORIGIN := Vector3(-0.65, 2.5, -0.65)

static var _ground_tex: ImageTexture

var demo: Node
## false: no voxel props (the survival world places PropKit meshes and their
## collision itself); ground, grass tufts and the roof stay.
var voxel_props := true
var roof: MeshInstance3D
var roof_mat: ShaderMaterial
var prop_mat: ShaderMaterial
var _roof_fade := 1.0
var _rng := RandomNumberGenerator.new()
## Experiment 003: plan rects where no grass grows (stone foundations). Set
## before the yard enters the tree, or call set_tuft_avoid() later.
var tuft_avoid: Array = []
var last_tuft_ms := 0.0
var _tufts: MeshInstance3D
var _tuft_state := -1


func _ready() -> void:
	_rng.seed = 4242
	_build_ground()
	prop_mat = demo._surface_material(Vector3.ZERO, VS, true)
	if voxel_props:
		for p in HousePlan.PROPS:
			_build_prop(p)
	_build_tufts()
	_build_roof()


# --- ground ------------------------------------------------------------------------

func _build_ground() -> void:
	if _ground_tex == null:
		_ground_tex = ImageTexture.create_from_image(_ground_image())
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 100)
	mi.mesh = pm
	mi.position = Vector3(7, GROUND_Y, 4.5)
	var m := ShaderMaterial.new()
	m.shader = load("res://src/voxel/shaders/voxel_ground.gdshader")
	m.set_shader_parameter("ground_tex", _ground_tex)
	m.set_shader_parameter("lawn_tex", AssetResolver.get_texture("voxel/ground", true))
	m.set_shader_parameter("img_origin", IMG_ORIGIN)
	m.set_shader_parameter("img_size", IMG_SIZE)
	mi.material_override = m
	mi.name = "Ground"
	add_child(mi)


func _rect(id: String) -> Rect2:
	for p in HousePlan.PROPS:
		if p["id"] == id:
			return p["rect"]
	return Rect2()


func _ground_image() -> Image:
	var w := int(IMG_SIZE.x / VS)
	var h := int(IMG_SIZE.y / VS)
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	var road := _rect("road")
	var drive := _rect("driveway")
	var path := _rect("front_path")
	var walk := Rect2(-30, 12.5, 80, 1.0)
	var house := HousePlan.FOOTPRINT.grow(0.15)
	var gravel := house.grow(0.35)
	var noise := FastNoiseLite.new()
	noise.seed = 77
	noise.frequency = 0.08
	var trees := []
	for p in HousePlan.PROPS:
		if p["type"] == "dead_tree":
			trees.append((p["rect"] as Rect2).get_center())
	for j in h:
		for i in w:
			var p := IMG_ORIGIN + Vector2(i + 0.5, j + 0.5) * VS
			var c := VoxelArt.sample("ground", i, j)
			var leaf_bias := 0.0
			for t in trees:
				leaf_bias = maxf(leaf_bias, 1.0 - p.distance_to(t) / 4.5)
			if road.has_point(Vector2(5, p.y)):
				c = VoxelArt.sample("asphalt", i, j)
				var ly := p.y - road.position.y
				if ly < 0.1 or ly > road.size.y - 0.1:
					c = 0x8e8a83
				elif absf(ly - road.size.y * 0.5) < 0.06 and fposmod(p.x, 4.0) < 2.0:
					c = VoxelArt.mix(c, 0xb8a868, 0.55)
				# skid marks swerving toward the car
				var sk := absf(ly - 0.45 - sin(p.x * 0.35) * 0.2)
				if p.x > 6.0 and p.x < 17.0 and (absf(sk) < 0.05 or absf(sk - 0.25) < 0.05) and VoxelArt.hash3(i, j, 1) > 0.25:
					c = VoxelArt.scale(c, 0.78)
			elif walk.has_point(p):
				c = VoxelArt.sample("paving", i, j)
			elif drive.has_point(p) or path.has_point(p):
				c = VoxelArt.sample("paving", i, j)
				if drive.has_point(p) and Vector2(p.x - 17.0, (p.y - 11.0) * 0.6).length() < 0.6:
					c = VoxelArt.scale(c, 0.55)   # oil stain
			elif gravel.has_point(p) and not house.has_point(p):
				c = VoxelArt.sample("roof", i, j)
			else:
				var n := noise.get_noise_2d(p.x, p.y)
				if n > 0.55 - leaf_bias * 0.6:
					var lc := [0x6e4a2a, 0x8a5a2a, 0x5a3d26, 0x9a7a3a]
					if VoxelArt.hash3(i, j, 3) > 0.55 - leaf_bias * 0.3:
						c = lc[int(VoxelArt.hash3(i, j, 9) * 4.0) % 4]
				# damp, darker soil close to the house
				var dx := maxf(maxf(gravel.position.x - p.x, p.x - gravel.end.x), 0.0)
				var dz := maxf(maxf(gravel.position.y - p.y, p.y - gravel.end.y), 0.0)
				var d := Vector2(dx, dz).length()
				if d < 0.8:
					c = VoxelArt.scale(c, 0.8 + 0.2 * d / 0.8)
			img.set_pixel(i, j, VoxelArt.to_color(c))
	return img


# --- props -------------------------------------------------------------------------

func _build_prop(p: Dictionary) -> void:
	var r: Rect2 = p["rect"]
	var t: String = p["type"]
	var h: float = p["height"]
	var model: Array = []
	match t:
		"car": model = _car(r, h)
		"dead_tree": model = _tree(r, h)
		"trash_bin_tipped": model = _bin(r)
		"mailbox": model = _mailbox(r, h)
		"streetlight_dead": model = _streetlight(r, h)
		"deck": model = _deck(r)
		"step": model = _step(r)
	if not model.is_empty():
		var mi := MeshInstance3D.new()
		mi.mesh = VoxelMesher.build_mesh(model[0], prop_mat)
		mi.position = model[1]
		mi.name = "Prop_" + p["id"]
		add_child(mi)
	if p["blocks"]:
		var tall := h >= Tuning.TALL_THRESHOLD
		var body: StaticBody3D = demo._box_body(r, h, 1 if tall else 1 << 4)
		var impact := VoxelMat.Impact.METAL
		if t == "dead_tree":
			impact = VoxelMat.Impact.WOOD
		elif t == "trash_bin_tipped":
			impact = VoxelMat.Impact.DUST
		body.set_meta("impact", impact)
		add_child(body)


## A model grid of `size_m` metres whose cell (1,1,1) min corner sits at the
## returned world position (lattice aligned to whole 0.1 m steps).
func _grid(size_m: Vector3, vs := VS) -> VoxelGrid:
	var n := Vector3i((size_m / vs).ceil()) + Vector3i(2, 2, 2)
	return VoxelGrid.new(n, vs, -Vector3.ONE * vs)


func _fill(g: VoxelGrid, f: Callable) -> void:
	for y in range(1, g.sy - 1):
		for z in range(1, g.sz - 1):
			for x in range(1, g.sx - 1):
				var p := g.center(Vector3i(x, y, z))
				var res: int = f.call(p, x, y, z)
				if res >= 0:
					g.set_voxel(x, y, z, res >> 24, res & 0xffffff, res & 0xffffff, 0)


static func _e(m: int, c: int) -> int:
	return (m << 24) | c


func _car(r: Rect2, h: float) -> Array:
	# An abandoned family sedan, nose to the north: rounded body, hood and boot,
	# glasshouse with pillars, a flat front tyre, one side window smashed.
	var g := _grid(Vector3(r.size.x, h + 0.1, r.size.y))
	var W := r.size.x
	var L := r.size.y
	var paint := 0x6a3a35
	var glass := 0x1c2428
	var trim := 0x2a2b2d
	var axles := [0.82, L - 0.86]
	_fill(g, func(p: Vector3, x: int, y: int, z: int) -> int:
		var cx := absf(p.x - W * 0.5)
		var half := W * 0.5 - 0.04
		# wheels
		for axle in axles:
			var flat: bool = axle < 1.0 and p.x < W * 0.5
			var wy := 0.31 if not flat else 0.24
			var dz: float = p.z - axle
			var dy := (p.y - wy) * (1.0 if not flat else 1.35)
			if cx > half - 0.24 and cx <= half and Vector2(dz, dy).length() < 0.32:
				if Vector2(dz, p.y - wy).length() < 0.14 and cx > half - 0.08:
					return _e(VoxelMat.METAL, 0x8e9193)
				return _e(VoxelMat.RUBBER, 0x161718)
		if p.y < 0.2:
			return -1
		# plan outline with rounded corners
		var rz := minf(p.z, L - p.z)
		var corner := 0.32
		if rz < corner and cx > half - corner and Vector2(corner - rz, cx - (half - corner)).length() > corner:
			return -1
		if cx > half or p.z < 0.04 or p.z > L - 0.04:
			return -1
		# wheel arches
		for axle in axles:
			if Vector2(p.z - axle, p.y - 0.31).length() < 0.42 and cx > half - 0.3:
				return -1
		# lower body: hood (front), boot (rear), sills
		var top := 0.8
		if p.z < 1.3:
			top = 0.72 + 0.1 * (p.z / 1.3)
		elif p.z > L - 0.9:
			top = 0.86 - 0.08 * ((p.z - (L - 0.9)) / 0.9)
		if p.y < top:
			if p.y < 0.4 and (p.z < 0.14 or p.z > L - 0.14):
				return _e(VoxelMat.PLASTIC, trim)          # bumpers
			if p.z < 0.12 and p.y > 0.5 and p.y < 0.64 and cx > half - 0.42 and cx < half - 0.06:
				return _e(VoxelMat.GLOW, 0xc9c6b4)         # headlights (dead)
			if p.z > L - 0.12 and p.y > 0.52 and p.y < 0.68 and cx > half - 0.4 and cx < half - 0.06:
				return _e(VoxelMat.PAINTED, 0x7a1d18)      # tail lights
			if p.y < 0.3:
				return _e(VoxelMat.PLASTIC, trim)
			var dirt := VoxelArt.hash3(x / 2, y, z / 2, 5) * clampf((0.62 - p.y) * 2.5, 0.0, 1.0)
			var c := VoxelArt.mix(VoxelArt.jitter(paint, x, y, z, 0.035), 0x55473a, dirt * 0.6)
			if absf(p.z - 2.45) < 0.03 and cx > half - 0.06 and p.y > 0.4:
				c = VoxelArt.scale(c, 0.7)                  # door seam
			return _e(VoxelMat.PAINTED, c)
		# glasshouse
		var z0 := 1.3
		var z1 := L - 0.9
		var k := clampf((p.y - top) / (h - 0.02 - top), 0.0, 1.0)
		var zf := lerpf(z0, 1.95, k)
		var zb := lerpf(z1, 3.25, k)
		var inset := 0.12 + 0.12 * k
		if p.y >= h - 0.02 or p.z < zf or p.z > zb or cx > half - inset:
			return -1
		if p.y > h - 0.12:
			return _e(VoxelMat.PAINTED, VoxelArt.jitter(paint, x, y, z, 0.03))  # roof
		var pillar := p.z < zf + 0.09 or p.z > zb - 0.1 or absf(p.z - 2.5) < 0.05
		if pillar:
			return _e(VoxelMat.PAINTED, VoxelArt.scale(paint, 0.8))
		if p.x > W * 0.5 and p.z > 2.55 and VoxelArt.hash3(x, y, z, 2) > 0.4:
			return -1                                       # smashed rear side window
		return _e(VoxelMat.SCREEN, glass)
	)
	return [g, Vector3(r.position.x, GROUND_Y, r.position.y)]


func _tree(r: Rect2, h: float) -> Array:
	var size := Vector3(4.2, h + 0.4, 4.2)
	var g := _grid(size)
	var base := Vector3(size.x * 0.5, 0.0, size.z * 0.5)
	var bark := 0x3b342e
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(r.position)
	var segs := []   # [a, b, radius]
	var trunk_top := base + Vector3(rng.randf_range(-0.2, 0.2), h * 0.55, rng.randf_range(-0.2, 0.2))
	segs.append([base, trunk_top, 0.2])
	var tips := [trunk_top]
	for level in 3:
		var next := []
		for tip in tips:
			for b in (3 if level == 0 else 2):
				var ang := rng.randf() * TAU
				var out := Vector3(cos(ang), 0, sin(ang)) * rng.randf_range(0.5, 1.0) * (1.0 - level * 0.2)
				var up := rng.randf_range(0.5, 1.1) * (h * 0.18)
				var e: Vector3 = tip + out + Vector3(0, up, 0)
				e.x = clampf(e.x, 0.15, size.x - 0.15)
				e.z = clampf(e.z, 0.15, size.z - 0.15)
				e.y = minf(e.y, size.y - 0.15)
				segs.append([tip, e, 0.11 - level * 0.035])
				next.append(e)
		tips = next
	for s in segs:
		var a: Vector3 = s[0]
		var b: Vector3 = s[1]
		var rad: float = s[2]
		var steps := int(a.distance_to(b) / (VS * 0.5)) + 1
		for k in steps + 1:
			var p := a.lerp(b, float(k) / steps)
			var rr := maxf(rad * (1.0 - 0.3 * float(k) / steps), 0.05)
			var c0 := g.cell_of(p - Vector3.ONE * rr)
			var c1 := g.cell_of(p + Vector3.ONE * rr)
			for y in range(c0.y, c1.y + 1):
				for z in range(c0.z, c1.z + 1):
					for x in range(c0.x, c1.x + 1):
						if g.center(Vector3i(x, y, z)).distance_to(p) <= rr + 0.02:
							g.set_voxel(x, y, z, VoxelMat.BARK, VoxelArt.jitter(bark, x, y, z, 0.12), 0, 0)
	var c := r.get_center()
	return [g, Vector3(c.x - base.x, GROUND_Y, c.y - base.z)]


func _bin(r: Rect2) -> Array:
	var size := Vector3(r.size.x + 1.0, 0.7, r.size.y + 0.6)
	var g := _grid(size)
	_fill(g, func(p: Vector3, x: int, y: int, z: int) -> int:
		# wheelie bin lying on its side, opening toward +x, spilled bags
		var q := Vector3(p.x - 0.05, p.y, p.z - 0.3)
		if q.x > 0.0 and q.x < r.size.x and q.z > 0.0 and q.z < r.size.y and q.y < 0.58:
			var inner := q.x > 0.08 and q.z > 0.08 and q.z < r.size.y - 0.08 and q.y > 0.08 and q.y < 0.5
			if inner:
				return -1
			return _e(VoxelMat.PLASTIC, VoxelArt.jitter(0x3f4a3f, x, y, z, 0.04))
		for bag in [Vector3(r.size.x + 0.35, 0.18, 0.55), Vector3(r.size.x + 0.65, 0.15, 0.25)]:
			if Vector3((p.x - bag.x) / 0.3, (p.y - bag.y) / 0.2, (p.z - bag.z) / 0.25).length() < 1.0:
				return _e(VoxelMat.PLASTIC, VoxelArt.jitter(0x1c1d20, x, y, z, 0.1))
		return -1)
	return [g, Vector3(r.position.x - 0.05, GROUND_Y, r.position.y - 0.3)]


func _mailbox(r: Rect2, h: float) -> Array:
	var g := _grid(Vector3(0.5, h + 0.1, 0.6))
	_fill(g, func(p: Vector3, x: int, y: int, z: int) -> int:
		if absf(p.x - 0.25) < 0.05 and absf(p.z - 0.3) < 0.05 and p.y < h - 0.25:
			return _e(VoxelMat.WOOD, VoxelArt.jitter(0x5a4634, x, y, z, 0.06))
		if absf(p.x - 0.25) < 0.12 and absf(p.z - 0.3) < 0.24 and p.y >= h - 0.3 and p.y < h:
			return _e(VoxelMat.PAINTED, 0x24282b)
		if p.x > 0.35 and p.x < 0.42 and absf(p.z - 0.18) < 0.04 and p.y >= h - 0.25 and p.y < h + 0.05:
			return _e(VoxelMat.PAINTED, 0x8a2a22)
		return -1)
	return [g, Vector3(r.position.x - 0.1, GROUND_Y, r.position.y - 0.15)]


func _streetlight(r: Rect2, h: float) -> Array:
	var g := _grid(Vector3(0.6, h + 0.2, 1.8))
	var px := 0.3
	var pz := 1.4
	_fill(g, func(p: Vector3, x: int, y: int, z: int) -> int:
		if absf(p.x - px) < 0.07 and absf(p.z - pz) < 0.07 and p.y < h:
			return _e(VoxelMat.METAL, VoxelArt.jitter(0x4b4e50, x, y, z, 0.05))
		if absf(p.x - px) < 0.05 and p.y > h - 0.15 and p.y < h and p.z > 0.25 and p.z < pz:
			return _e(VoxelMat.METAL, 0x4b4e50)
		if absf(p.x - px) < 0.15 and p.y > h - 0.25 and p.y < h - 0.05 and p.z > 0.1 and p.z < 0.6:
			return _e(VoxelMat.SCREEN if p.y < h - 0.15 else VoxelMat.METAL, 0x2a2f33 if p.y < h - 0.15 else 0x3a3d40)
		return -1)
	return [g, Vector3(r.get_center().x - px, GROUND_Y, r.get_center().y - pz)]


func _deck(r: Rect2) -> Array:
	var g := _grid(Vector3(r.size.x, 0.1, r.size.y))
	var wood := 0x6f5a44
	_fill(g, func(p: Vector3, x: int, y: int, z: int) -> int:
		var board := int(p.z / VS)
		var c := VoxelArt.scale(wood, 1.0 + (VoxelArt.hash3(board, 0, int(p.x / 1.3), 4) - 0.5) * 0.18)
		if board % 2 == 1:
			c = VoxelArt.scale(c, 0.9)
		return _e(VoxelMat.WOOD, VoxelArt.jitter(c, x, y, z, 0.04)))
	return [g, Vector3(r.position.x, GROUND_Y - 0.06, r.position.y)]


func _step(r: Rect2) -> Array:
	var g := _grid(Vector3(r.size.x, 0.1, r.size.y))
	_fill(g, func(p: Vector3, x: int, y: int, z: int) -> int:
		return _e(VoxelMat.STONE, VoxelArt.jitter(0x85817a, x, y, z, 0.05)))
	return [g, Vector3(r.position.x, GROUND_Y - 0.05, r.position.y)]


## Sparse dry grass tufts and a few weeds over the lawn (decor, no collision).
## Rebuilds the grass tufts without the ones inside `rects` (plan metres),
## from the same random sequence, so every other tuft stays where it was.
func set_tuft_avoid(rects: Array) -> void:
	tuft_avoid = rects.duplicate()
	if _tufts == null or _tuft_state < 0:
		return
	var after := _rng.state
	_tufts.free()
	_tufts = null
	_rng.state = _tuft_state
	_build_tufts()
	_rng.state = after


func _build_tufts() -> void:
	var t0 := Time.get_ticks_usec()
	_tuft_state = _rng.state
	var area := Rect2(-9.0, -8.0, 32.0, 21.4)
	var g := _grid(Vector3(area.size.x, 0.4, area.size.y))
	var avoid := [HousePlan.FOOTPRINT.grow(0.6), _rect("driveway").grow(0.2), _rect("front_path").grow(0.2), _rect("porch_deck").grow(0.2), Rect2(-30, 12.3, 80, 4.0)]
	for p in HousePlan.PROPS:
		if p["blocks"]:
			avoid.append((p["rect"] as Rect2).grow(0.3))
	var extra: Array = tuft_avoid
	var cols := [0x7d7748, 0x6b6a40, 0x8c8152, 0x59613c, 0x947a46]
	for k in 2600:
		var pos := Vector2(_rng.randf_range(area.position.x, area.end.x), _rng.randf_range(area.position.y, area.end.y))
		var skip := false
		for a in avoid:
			if (a as Rect2).has_point(pos):
				skip = true
				break
		if skip:
			continue
		var c := g.cell_of(Vector3(pos.x - area.position.x, 0.05, pos.y - area.position.y))
		var ht := 1 + int(_rng.randf() * _rng.randf() * 3.5)
		var col: int = cols[_rng.randi() % cols.size()]
		for a in extra:
			if (a as Rect2).grow(0.08).has_point(pos):
				skip = true
				break
		if skip:
			if ht >= 2 and _rng.randf() < 0.5:     # the same draws as a drawn tuft
				_rng.randi()
			continue
		for y in ht:
			g.set_voxel(c.x, 1 + y, c.z, VoxelMat.LEAF, VoxelArt.scale(col, 1.0 + y * 0.08), 0, 0)
		if ht >= 2 and _rng.randf() < 0.5:
			var side: Vector3i = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)][_rng.randi() % 4]
			g.set_voxel(c.x + side.x, 1, c.z + side.z, VoxelMat.LEAF, VoxelArt.scale(col, 0.92), 0, 0)
	var mi := MeshInstance3D.new()
	mi.mesh = VoxelMesher.build_mesh(g, prop_mat)
	mi.position = Vector3(area.position.x, GROUND_Y, area.position.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "GrassTufts"
	add_child(mi)
	_tufts = mi
	last_tuft_ms = (Time.get_ticks_usec() - t0) / 1000.0


# --- roof --------------------------------------------------------------------------

func _build_roof() -> void:
	var size := Vector3i(153, 10, 103)
	var g := VoxelGrid.new(size, VS, ROOF_ORIGIN)
	var fascia := VoxelArt.pal(VoxelArt.Slot.FASCIA)
	var coping := VoxelArt.pal(VoxelArt.Slot.TRIM_EXT)
	var xr := g.centre_range(0, -0.55, 14.55)
	var zr := g.centre_range(2, -0.55, 9.55)
	for z in range(zr.x, zr.y):
		for x in range(xr.x, xr.y):
			var edge := x == xr.x or x == xr.y - 1 or z == zr.x or z == zr.y - 1
			g.set_voxel(x, 1, z, VoxelMat.WOOD, VoxelArt.jitter(fascia, x, 1, z, 0.04), 0, 0)
			var top := VoxelArt.sample("roof", x, z)
			# rain streaks and a dark puddle
			var pc := Vector2(x - 40, (z - 60) * 1.4).length()
			if pc < 9.0:
				top = VoxelArt.mix(top, 0x26282a, 0.6)
			g.set_voxel(x, 2, z, VoxelMat.STONE, top, 0, 0)
			if edge:
				g.set_voxel(x, 3, z, VoxelMat.METAL, VoxelArt.jitter(coping, x, 3, z, 0.03), 0, 0)
	# A few rooftop details: vent stacks, an AC unit, a skylight frame.
	_roof_box(g, Vector3(11.2, 2.8, 6.6), Vector3(1.0, 0.6, 0.8), VoxelMat.PAINTED, 0x8e9294)
	_roof_box(g, Vector3(11.3, 3.4, 6.7), Vector3(0.8, 0.1, 0.6), VoxelMat.METAL, 0x3a3d40)
	for v in [Vector3(6.4, 2.8, 1.6), Vector3(12.6, 2.8, 1.1), Vector3(3.1, 2.8, 2.3)]:
		_roof_box(g, v, Vector3(0.2, 0.5, 0.2), VoxelMat.METAL, 0x4a4d50)
	_roof_box(g, Vector3(4.0, 2.8, 5.0), Vector3(2.0, 0.1, 1.2), VoxelMat.METAL, 0x2c2e31)
	_roof_box(g, Vector3(4.1, 2.8, 5.1), Vector3(1.8, 0.1, 1.0), VoxelMat.SCREEN, 0x34464e)
	roof_mat = demo._surface_material(ROOF_ORIGIN, VS)
	roof = MeshInstance3D.new()
	roof.name = "Roof"
	roof.mesh = VoxelMesher.build_mesh(g, roof_mat)
	add_child(roof)


func _roof_box(g: VoxelGrid, pos: Vector3, size: Vector3, m: int, c: int) -> void:
	var xr := g.centre_range(0, pos.x, pos.x + size.x)
	var yr := g.centre_range(1, pos.y, pos.y + size.y)
	var zr := g.centre_range(2, pos.z, pos.z + size.z)
	for y in range(yr.x, yr.y):
		for z in range(zr.x, zr.y):
			for x in range(xr.x, xr.y):
				g.set_voxel(x, y, z, m, VoxelArt.jitter(c, x, y, z, 0.04), 0, 0)


## Roof dissolves voxel by voxel while the player is inside the footprint.
func update_roof(player_pos: Vector3, delta: float, instant := false) -> void:
	if roof == null:
		return
	var inside := HousePlan.FOOTPRINT.grow(0.4).has_point(Vector2(player_pos.x, player_pos.z))
	var goal := 0.0 if inside else 1.0
	_roof_fade = goal if instant else move_toward(_roof_fade, goal, minf(delta, 0.05) / 0.35)
	roof_mat.set_shader_parameter("fade", _roof_fade)
	roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _roof_fade > 0.0 else GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY


func roof_visible() -> bool:
	return _roof_fade > 0.0
