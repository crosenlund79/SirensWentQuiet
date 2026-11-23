class_name ModHouse
extends Node3D
## Assembles the house from HousePlan using the modular kit and keeps
## collision, navigation and the cutaway view in step with it.
##
## Grid rules (see docs/experiment-001/modular.md):
##  * walls sit on whole-meter grid lines and are split into 1 m modules
##    along HousePlan.wall_spans (solid, window or door module per meter);
##  * every wall end and T-junction gets a square post module the size of
##    the thickest wall there; modules touching a post are shortened by half
##    the post size, so pieces never overlap;
##  * floors are 1 m tiles per room; roof panels are 1 m strips.
## A destroyed module turns the nav cells of its real footprint OPEN.

signal module_changed(module: ModWall, old_state: int)

const M := preload("res://src/modular/kit/mod_materials.gd")
const CUT_HEIGHT := 1.0
const FULL_HEIGHT := HousePlan.WALL_HEIGHT + 0.06
const NO_CUT := 100.0
const TALL := Tuning.TALL_THRESHOLD

## Which way each door leaf stands open: [swing toward side A (+1) or B (-1),
## hinge at the module's far end]. Purely decorative; leaves never block.
const DOOR_LEAVES := {
	"front_door": [-1.0, true],
	"back_door": [1.0, true],
	"bedroom_door": [-1.0, false],
	"bathroom_door": [-1.0, true],
	"utility_door": [-1.0, true],
}

var nav: GridNav
var walls: Array[ModWall] = []
var posts: Array[ModPost] = []
var roof: ModRoof
var floor_tiles := 0
var furniture_pieces := 0
var lamp_meshes: Array[GeometryInstance3D] = []
var cut_enabled := true
var roof_mode := "auto"            ## "auto", "hidden", "shown"
var instant := false               ## apply view changes at once (screenshots)

var _cut_level := {}               ## node -> 0..1
var _yard_edge: StaticBody3D
var _tall_props: Array[Dictionary] = []   ## {mi, pos, fade}


func build(grid: GridNav) -> void:
	nav = grid
	_build_ground()
	floor_tiles = ModFloorKit.build(self)
	_build_walls()
	for f in HousePlan.FURNITURE:
		_build_item(f, true)
	for p in HousePlan.PROPS:
		_build_item(p, false)
	roof = ModRoof.new()
	roof.name = "Roof"
	add_child(roof)
	_build_dressing()


func yard_edge_rid() -> RID:
	return _yard_edge.get_rid()


func module_count() -> int:
	return walls.size() + posts.size() + floor_tiles + int(round(roof.x1 - roof.x0)) * 2 + furniture_pieces


func damaged_counts() -> Vector3i:
	var v := Vector3i.ZERO
	for w in walls:
		match w.state:
			ModWall.State.DAMAGED:
				v.x += 1
			ModWall.State.HEAVY:
				v.y += 1
			ModWall.State.DESTROYED:
				v.z += 1
	return v


# --- walls -------------------------------------------------------------------------------------

## Grid nodes with a post: wall ends and T-junctions -> post size.
func _junctions() -> Dictionary:
	var nodes := {}
	for w in HousePlan.WALLS:
		for p in [w["a"], w["b"]]:
			nodes[p] = maxf(nodes.get(p, 0.0), HousePlan.thickness(w))
			for o in HousePlan.WALLS:
				if o == w:
					continue
				if _on_segment(p, o["a"], o["b"]):
					nodes[p] = maxf(nodes[p], HousePlan.thickness(o))
	return nodes


func _on_segment(p: Vector2, a: Vector2, b: Vector2) -> bool:
	var r := Rect2(a, Vector2.ZERO).expand(b)
	return r.grow(0.001).has_point(p) and absf((b - a).cross(p - a)) < 1e-4


func _build_walls() -> void:
	var nodes := _junctions()
	for w in HousePlan.WALLS:
		for span in HousePlan.wall_spans(w):
			var k: float = span["from"]
			var e: float = span["to"]
			var idx := 0
			while k < e - 0.001:
				var to := minf(k + 1.0, e)
				_add_module(w, span, k, to, nodes, idx)
				k = to
				idx += 1
	for p in nodes:
		var post := ModPost.new()
		post.size = nodes[p]
		post.plan_pos = p
		post.name = "Post_%d_%d" % [int(p.x), int(p.y)]
		post.position = Vector3(p.x, 0, p.y)
		add_child(post)
		posts.append(post)


func _add_module(w: Dictionary, span: Dictionary, from: float, to: float, nodes: Dictionary, idx: int) -> void:
	var horiz := HousePlan.is_horizontal(w)
	var line: float = w["a"].y if horiz else w["a"].x
	var p_from := Vector2(from, line) if horiz else Vector2(line, from)
	var p_to := Vector2(to, line) if horiz else Vector2(line, to)
	var trim0: float = nodes.get(p_from, 0.0) * 0.5
	var trim1: float = nodes.get(p_to, 0.0) * 0.5
	var t := HousePlan.thickness(w)
	var m := ModWall.new()
	match span["kind"]:
		"window":
			m.kind = ModWall.Kind.WINDOW
			m.sill = HousePlan.window_sill(span["opening"])
		"door":
			m.kind = ModWall.Kind.DOOR
		_:
			m.kind = ModWall.Kind.SOLID
	m.length = (to - trim1) - (from + trim0)
	m.thickness = t
	m.exterior = w["exterior"]
	m.wall_id = w["id"]
	m.world_x0 = from + trim0
	m.seed = hash("%s_%d_%d" % [w["id"], int(from * 10), idx])
	# side A is +z (south) for horizontal walls and -x (west) for vertical ones
	var a_dir := Vector2(0, 1) if horiz else Vector2(-1, 0)
	var mid := (p_from + p_to) * 0.5
	var room_a := HousePlan.room_at(mid + a_dir * 0.5)
	var room_b := HousePlan.room_at(mid - a_dir * 0.5)
	if m.exterior:
		m.outside = 0 if room_a.is_empty() else 1
	m.tint_a = M.ROOM_PAINT.get(room_a.get("id", ""), M.ROOM_PAINT[""])
	m.tint_b = M.ROOM_PAINT.get(room_b.get("id", ""), M.ROOM_PAINT[""])
	if m.kind == ModWall.Kind.DOOR:
		var o: Dictionary = span["opening"]
		var cfg: Array = DOOR_LEAVES.get(o["id"], [1.0, false])
		m.door_swing = cfg[0]
		m.door_hinge_end = cfg[1]
		m.door_style = "front" if o["id"] == "front_door" else ("back" if m.exterior else "interior")
	if horiz:
		m.transform = Transform3D(Basis.IDENTITY, Vector3(from + trim0, 0, line))
		m.plan_rect = Rect2(from + trim0, line - t * 0.5, m.length, t)
	else:
		m.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(line, 0, from + trim0))
		m.plan_rect = Rect2(line - t * 0.5, from + trim0, t, m.length)
	m.name = "Wall_%s_%02d" % [w["id"], int(from)]
	add_child(m)
	m.state_changed.connect(_on_module_changed)
	walls.append(m)


func _on_module_changed(m: ModWall, old_state: int) -> void:
	if m.state == ModWall.State.DESTROYED:
		# real geometry changed: the module's footprint is now open floor
		for c in nav.cells_in_rect(m.plan_rect):
			if nav.get_raw(c) == GridNav.WALL:
				nav.set_raw(c, GridNav.OPEN)
		nav.refresh_region(m.plan_rect)
	module_changed.emit(m, old_state)


## Module (or post) whose footprint is at/near a plan point.
func wall_near(p: Vector2, max_d := 0.6) -> ModWall:
	var best: ModWall = null
	var best_d := max_d
	for w in walls:
		if not w.is_destructible() or w.state == ModWall.State.DESTROYED:
			continue
		var r := w.plan_rect
		var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
		var d := q.distance_to(p)
		if d < best_d:
			best_d = d
			best = w
	return best


# --- view: cutaway and roof ----------------------------------------------------------------------

## Sims-style cutaway: whole 1 m modules between the camera and the player
## slide down to CUT_HEIGHT; the roof fades while the player is inside or
## hidden behind it.
func update_view(player: Vector2, delta: float) -> void:
	var fp := HousePlan.FOOTPRINT
	var near_house := fp.grow(1.2).has_point(player) or Rect2(fp.position.x - 0.8, fp.position.y - 3.2, fp.size.x + 1.6, 3.4).has_point(player)
	var fade_goal := 1.0 if near_house else 0.0
	if roof_mode == "hidden":
		fade_goal = 1.0
	elif roof_mode == "shown":
		fade_goal = 0.0
	var f := move_toward(roof.fade, fade_goal, delta / 0.35)
	if instant:
		f = fade_goal
	if f != roof.fade or roof.fade == 0.0 and fade_goal == 0.0 and not roof.visible:
		roof.set_fade(f)
	# tall props (trees, streetlight) between camera and player dissolve
	for d in _tall_props:
		var pos: Vector2 = d["pos"]
		var dy := pos.y - player.y
		var want := dy > -0.5 and dy < 6.0 and absf(pos.x - player.x) < 1.8 + maxf(dy, 0.0) * 0.3
		var goal := 1.0 if want else 0.0
		var fv: float = goal if instant else move_toward(d["fade"], goal, delta / 0.3)
		if fv != d["fade"]:
			d["fade"] = fv
			(d["mi"] as GeometryInstance3D).set_instance_shader_parameter("fade", fv)
	for w in walls:
		_update_cut(w, w.plan_rect.get_center(), absf(w.plan_rect.size.x) < absf(w.plan_rect.size.y), player, delta)
	for p in posts:
		_update_cut(p, p.plan_pos, false, player, delta)


func _update_cut(node: Node3D, c: Vector2, vertical: bool, player: Vector2, delta: float) -> void:
	var dx := c.x - player.x
	var dy := c.y - player.y
	var want := false
	if cut_enabled:
		var lateral := (1.2 if vertical else 2.6) - maxf(dy, 0.0) * 0.12
		want = dy > -0.3 and dy < 3.8 and absf(dx) < lateral
	var lvl: float = _cut_level.get(node, 0.0)
	var goal := 1.0 if want else 0.0
	if is_equal_approx(lvl, goal):
		return
	lvl = goal if instant else move_toward(lvl, goal, delta / 0.28)
	_cut_level[node] = lvl
	var e := lvl * lvl * (3.0 - 2.0 * lvl)
	var h := NO_CUT if lvl <= 0.0 else lerpf(FULL_HEIGHT, CUT_HEIGHT, e)
	node.call("set_cut", h)


## True if a ray hit at `point` on `collider` lies in a part the cutaway hides.
func is_hidden(collider: Object, point: Vector3) -> bool:
	if collider is ModWall:
		return point.y > (collider as ModWall).cut + 0.02
	if collider is ModPost:
		return point.y > (collider as ModPost).cut + 0.02
	return false


## Where a camera ray meets the visible top of a cut-down module, or null.
func cut_top_hit(collider: Object, from: Vector3, dir: Vector3) -> Variant:
	if not (collider is ModWall or collider is ModPost) or absf(dir.y) < 0.01:
		return null
	var node := collider as Node3D
	var h: float = node.get("cut")
	var p := from + dir * ((h - from.y) / dir.y)
	var local := node.to_local(p)
	if collider is ModWall:
		var m := collider as ModWall
		if m.state == ModWall.State.DESTROYED:
			return null
		if local.x >= 0.0 and local.x <= m.length and absf(local.z) <= m.thickness * 0.5 + 0.01:
			return p
	elif absf(local.x) <= (collider as ModPost).size * 0.5 and absf(local.z) <= (collider as ModPost).size * 0.5:
		return p
	return null


## Force every module to a cut level now (scenarios / screenshots).
func set_all_cut(level: float) -> void:
	for n in walls + posts:
		_cut_level[n] = level
		n.call("set_cut", NO_CUT if level <= 0.0 else lerpf(FULL_HEIGHT, CUT_HEIGHT, level))


# --- furniture and props -------------------------------------------------------------------------

func _build_item(f: Dictionary, indoor: bool) -> void:
	var rect: Rect2 = f["rect"]
	var center := rect.get_center()
	var h: float = f["height"]
	var mi := MeshInstance3D.new()
	mi.name = "Item_%s" % f["id"]
	mi.mesh = ModFurnitureKit.build(f)
	mi.material_override = M.kit()
	var y := ModFloorKit.TILE_TOP - 0.005 if indoor and f["type"] != "rug" else 0.0
	mi.transform = Transform3D(ModFurnitureKit.facing_basis(f.get("facing", "S")), Vector3(center.x, y, center.y))
	# floor_lamp: its shade surrounds its own shadowed bulb and would print a black disc
	if f["type"] in ["rug", "road", "path", "driveway", "deck", "step", "floor_lamp"]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	furniture_pieces += 1
	if f["type"] in ["floor_lamp", "stove"]:
		lamp_meshes.append(mi)
	if not indoor and h >= 2.5:
		_tall_props.append({"mi": mi, "pos": center, "fade": 0.0})
	if not f["blocks"]:
		return
	var body := StaticBody3D.new()
	body.name = "Body_%s" % f["id"]
	body.collision_layer = 1 if h >= TALL else 16
	body.collision_mask = 0
	body.set_meta("material", ModFurnitureKit.material_of(f["type"]))
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(rect.size.x, h, rect.size.y)
	cs.shape = box
	cs.position = Vector3(center.x, h * 0.5, center.y)
	body.add_child(cs)
	add_child(body)


# --- ground and dressing ---------------------------------------------------------------------------

func _build_ground() -> void:
	var mm := ModMesh.new()
	mm.set_mat(M.L_GRASS)
	var g := Rect2(-45, -40, 104, 95)
	mm.quad(Vector3(g.position.x, 0, g.position.y), Vector3(g.end.x, 0, g.position.y), Vector3(g.end.x, 0, g.end.y), Vector3(g.position.x, 0, g.end.y), Vector3.UP)
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = mm.commit()
	mi.material_override = M.kit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("material", "ground")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(g.size.x, 1.0, g.size.y)
	cs.shape = box
	cs.position = Vector3(g.get_center().x, -0.5, g.get_center().y)
	body.add_child(cs)
	add_child(body)
	# the yard edge keeps bodies in (blocks movement, not bullets)
	var yard := HousePlan.YARD
	var edge := StaticBody3D.new()
	_yard_edge = edge
	edge.name = "YardEdge"
	edge.collision_layer = 16
	edge.collision_mask = 0
	for r in [Rect2(yard.position.x - 1, yard.position.y - 1, yard.size.x + 2, 1), Rect2(yard.position.x - 1, yard.end.y, yard.size.x + 2, 1),
			Rect2(yard.position.x - 1, yard.position.y, 1, yard.size.y), Rect2(yard.end.x, yard.position.y, 1, yard.size.y)]:
		var s := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(r.size.x, 2.0, r.size.y)
		s.shape = b
		s.position = Vector3(r.get_center().x, 1.0, r.get_center().y)
		edge.add_child(s)
	add_child(edge)


## Purely decorative: dry grass tufts, a picket of dead hedges along the lot
## line, leaves. Nothing here collides or touches navigation.
func _build_dressing() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var tuft := ModMesh.new()
	for k in 7:
		var a := TAU * k / 7.0 + rng.randf_range(-0.3, 0.3)
		var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.05, 0.14)
		var base := Vector3(cos(a), 0, sin(a)) * 0.03
		var hgt := rng.randf_range(0.14, 0.3)
		tuft.set_mat(M.L_PLAIN, Color(0.62, 0.56, 0.36).darkened(rng.randf_range(0.0, 0.3)))
		var side := Vector3(-sin(a), 0, cos(a)) * 0.018
		tuft.tri(base - side, base + side, base + lean + Vector3(0, hgt, 0), Vector3.ZERO)
	var tuft_mesh := tuft.commit()
	var blocked: Array[Rect2] = [HousePlan.FOOTPRINT.grow(0.5)]
	for p in HousePlan.PROPS:
		if p["type"] in ["road", "path", "driveway", "deck", "step", "car"]:
			blocked.append((p["rect"] as Rect2).grow(0.2))
	blocked.append(Rect2(-50, 13.3, 120, 7.6))
	var xforms: Array[Transform3D] = []
	var tries := 0
	while xforms.size() < 1300 and tries < 9000:
		tries += 1
		var p := Vector2(rng.randf_range(-18, 32), rng.randf_range(-14, 26))
		var ok := true
		for r in blocked:
			if r.has_point(p):
				ok = false
				break
		if not ok:
			continue
		# clumps: denser near fences and trees
		if rng.randf() < 0.45 and absf(sin(p.x * 0.7) * cos(p.y * 0.9)) < 0.5:
			continue
		var s := rng.randf_range(0.7, 1.6)
		xforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.7, 1.3), s)), Vector3(p.x, 0, p.y)))
	var mmesh := MultiMesh.new()
	mmesh.transform_format = MultiMesh.TRANSFORM_3D
	mmesh.mesh = tuft_mesh
	mmesh.instance_count = xforms.size()
	for i in xforms.size():
		mmesh.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "GrassTufts"
	mmi.multimesh = mmesh
	mmi.material_override = M.kit()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
