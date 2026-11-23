extends Node2D
## Static illustrated scenery of Version C, built from HousePlan: ground and
## room floors (UV-repeated seamless tiles), the subfloor revealed under
## destroyed walls, furniture and yard props (sprites + collision), a few
## eerie details, light fixtures and the fenced yard boundary.

const Art := preload("res://src/illustrated/ill_art.gd")

const ROOM_FLOOR := {"wood_light": "floor_wood_light", "tile": "floor_tile", "kitchen_tile": "floor_kitchen_tile",
	"wood": "floor_wood", "concrete": "floor_concrete"}
## Flat props drawn as ground surfaces: type -> [texture, tile size m, outline]
const GROUND_PROPS := {"deck": ["floor_deck", 4.0, true], "path": ["ground_concrete", 4.0, true],
	"road": ["ground_asphalt", 4.0, false], "driveway": ["ground_concrete", 4.0, true], "step": ["ground_concrete", 4.0, true]}
## Art name per furniture id or type (default: the type itself).
const ART_BY_ID := {"rug_living": "rug_living", "rug_bed": "rug_bed", "bath_mat": "bath_mat"}
const ART_BY_TYPE := {"dryer": "washer", "trash_bin_tipped": "trash_bin", "streetlight_dead": "streetlight"}
## Canonical (front facing +Y) visual size in meters where it differs from the footprint.
const VISUAL_SIZE := {"dead_tree": Vector2(4.6, 4.6), "streetlight": Vector2(0.8, 4.4), "car": Vector2(2.3, 4.6)}
## Pieces drawn above characters (branches, lamp heads).
const OVERHEAD := ["dead_tree", "streetlight"]
## Counter-like pieces drawn as caps + tiled middle (art authored 1.0 m long).
const SLICED := ["counter"]
## Impact material of pieces tall enough to stop bullets.
const MATERIAL := {"floor_lamp": "metal", "fridge": "metal", "water_heater": "metal", "shelves": "metal",
	"car": "metal", "mailbox": "metal", "streetlight_dead": "metal", "trash_bin_tipped": "metal"}
## Tall pieces that also cast light shadows.
const OCCLUDES := ["bookshelf", "fridge", "wardrobe", "water_heater", "shelves", "car"]
## Purely decorative details (plan meters, radians, width in meters).
const DECOR := [
	{"art": "papers", "pos": Vector2(4.35, 6.2), "rot": 0.4, "size": 0.85},
	{"art": "papers", "pos": Vector2(9.1, 6.7), "rot": 2.3, "size": 0.6},
	{"art": "papers", "pos": Vector2(3.0, 9.9), "rot": -0.8, "size": 0.6},
	{"art": "mud_trail", "pos": Vector2(12.4, 6.75), "rot": PI + 0.12, "size": 2.6},
	{"art": "mud_trail", "pos": Vector2(15.3, 7.2), "rot": PI - 0.5, "size": 1.6},
	{"art": "shoe", "pos": Vector2(4.65, 12.1), "rot": 1.25, "size": 0.32},
	{"art": "toy", "pos": Vector2(1.2, 11.4), "rot": -0.6, "size": 0.5},
	{"art": "leaves", "pos": Vector2(-4.0, 1.9), "rot": 0.0, "size": 1.6},
	{"art": "leaves", "pos": Vector2(18.6, -2.6), "rot": 1.9, "size": 1.5},
	{"art": "leaves", "pos": Vector2(-4.4, 11.8), "rot": 3.4, "size": 1.4},
	{"art": "leaves", "pos": Vector2(6.8, 9.6), "rot": 0.7, "size": 0.9},
]
const FIXTURES := {"ceiling": ["ceiling_light", 0.46, true], "bare_bulb": ["bulb", 0.3, true], "table_lamp": ["table_lamp", 0.36, false]}

var ground: Node2D
var floor_decor: Node2D
var furniture: Node2D
var overhead: Node2D
var shadow_parent: Node
var bodies: Array[StaticBody2D] = []


func build(p_shadow_parent: Node) -> void:
	shadow_parent = p_shadow_parent
	ground = Art.layer(self, "Ground", Art.Z_GROUND)
	floor_decor = Art.layer(self, "FloorDecor", Art.Z_FLOOR_DECOR)
	furniture = Art.layer(self, "Furniture", Art.Z_FURNITURE)
	overhead = Art.layer(self, "Overhead", Art.Z_OVERHEAD)
	_build_ground()
	_build_floors()
	for f in HousePlan.FURNITURE + HousePlan.PROPS:
		if GROUND_PROPS.has(f["type"]):
			continue
		_build_piece(f)
	_build_decor()
	_build_fixtures()
	_build_boundary()


# --- surfaces ------------------------------------------------------------------------

func _surface(tex_name: String, r: Rect2, parent: Node2D, tile_m := 4.0, tint := Color.WHITE) -> Polygon2D:
	var p := Polygon2D.new()
	var wr := Art.rect(r)
	p.polygon = Art.rect_points(wr)
	p.color = tint
	var tex := Art.tex(tex_name)
	if tex != null:
		p.texture = tex
		p.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		var k := tex.get_size().x / (tile_m * Art.PX_PER_M)
		var uv := PackedVector2Array()
		for q in p.polygon:
			uv.append(q * k)
		p.uv = uv
	else:
		p.color = Color(0.35, 0.33, 0.3) * tint
	parent.add_child(p)
	return p


func _outline(r: Rect2, parent: Node2D, width := 2.0, color := Art.INK) -> void:
	var l := Line2D.new()
	var pts := Art.rect_points(Art.rect(r))
	pts.append(pts[0])
	l.points = pts
	l.width = width
	l.default_color = color
	l.joint_mode = Line2D.LINE_JOINT_ROUND
	parent.add_child(l)


func _build_ground() -> void:
	var big := HousePlan.YARD.grow(14.0)
	_surface("ground_grass", big, ground)
	for f in HousePlan.PROPS:
		if not GROUND_PROPS.has(f["type"]):
			continue
		var spec: Array = GROUND_PROPS[f["type"]]
		var r: Rect2 = f["rect"]
		if f["type"] == "road":
			r = Rect2(big.position.x, r.position.y, big.size.x, r.size.y)
		_surface(spec[0], r, ground, spec[1])
		if spec[2]:
			_outline(r, ground, 1.6)
		if f["type"] == "road":
			# kerb on the house side and a faded painted edge line
			var kerb := Rect2(r.position.x, r.position.y - 0.12, r.size.x, 0.12)
			_surface("ground_concrete", kerb, ground, 4.0, Color(1.05, 1.05, 1.0))
			_outline(kerb, ground, 1.4)
			var dash := Node2D.new()
			ground.add_child(dash)
			var x := r.position.x
			while x < r.end.x:
				var d := Polygon2D.new()
				d.polygon = Art.rect_points(Art.rect(Rect2(x, r.end.y - 0.3, 1.2, 0.08)))
				d.color = Color(0.78, 0.76, 0.66, 0.45)
				dash.add_child(d)
				x += 2.6


func _build_floors() -> void:
	for room in HousePlan.ROOMS:
		_surface(ROOM_FLOOR.get(room["floor"], "floor_wood"), room["rect"], ground)
	# doorways get the floor of the room they open into
	for o in HousePlan.OPENINGS:
		if o["kind"] != "door":
			continue
		var w := HousePlan.wall_by_id(o["wall"])
		var r := HousePlan.span_rect(w, o["from"], o["to"])
		var inside := HousePlan.room_at(r.get_center() + (Vector2(0, -0.3) if HousePlan.is_horizontal(w) else Vector2(-0.3, 0)))
		if inside.is_empty():
			inside = HousePlan.room_at(r.get_center() + (Vector2(0, 0.3) if HousePlan.is_horizontal(w) else Vector2(0.3, 0)))
		if not inside.is_empty():
			_surface(ROOM_FLOOR.get(inside["floor"], "floor_wood"), r, ground)
	# thin seam where the kitchen tiles meet the living-room boards
	var seam := Line2D.new()
	seam.points = PackedVector2Array([Art.w(Vector2(8.1, 4.0)), Art.w(Vector2(9.9, 4.0))])
	seam.width = 2.5
	seam.default_color = Color(0.55, 0.55, 0.52)
	ground.add_child(seam)
	var seam_ink := Line2D.new()
	seam_ink.points = seam.points
	seam_ink.width = 0.8
	seam_ink.default_color = Art.INK
	ground.add_child(seam_ink)
	# subfloor / sill plate under every wall (seen once a section is gone)
	for w in HousePlan.WALLS:
		var r := HousePlan.wall_rect(w)
		_surface("floor_subfloor", r, ground, 2.0)


# --- furniture & props -------------------------------------------------------------------

static func facing_rotation(facing: String) -> float:
	match facing:
		"N":
			return PI
		"E":
			return -PI * 0.5
		"W":
			return PI * 0.5
	return 0.0


static func canonical_size(f: Dictionary) -> Vector2:
	var s: Vector2 = (f["rect"] as Rect2).size
	return Vector2(s.y, s.x) if f["facing"] in ["E", "W"] else s


static func art_name(f: Dictionary) -> String:
	if ART_BY_ID.has(f["id"]):
		return ART_BY_ID[f["id"]]
	return ART_BY_TYPE.get(f["type"], f["type"])


func _build_piece(f: Dictionary) -> void:
	var type: String = f["type"]
	var art := art_name(f)
	var rect: Rect2 = f["rect"]
	var center := Art.w(rect.get_center())
	var rot := facing_rotation(f["facing"])
	var size: Vector2 = VISUAL_SIZE.get(art, canonical_size(f))
	var parent: Node2D = overhead if art in OVERHEAD else (floor_decor if not f["blocks"] else furniture)
	var tex := Art.tex(art)
	var node := _visual(tex, type, size)
	node.position = center
	node.rotation = rot
	parent.add_child(node)
	# soft day shadow: same silhouette, pushed down-right by its height
	if f["height"] > 0.05 and tex != null:
		var sh := _visual(tex, type, size)
		var h: float = minf(f["height"], 2.2)
		if art == "dead_tree":
			h = 3.0
		sh.position = center + Vector2(1.0, 1.35) * Art.m(0.03 + 0.07 * h)
		sh.rotation = rot
		shadow_parent.add_child(sh)
	if f["blocks"]:
		_body(f, rect)


func _visual(tex: Texture2D, type: String, size: Vector2) -> Node2D:
	if tex == null:
		return _placeholder(size)
	if type in SLICED:
		var sl := Sliced.new()
		sl.tex = tex
		sl.size_m = size
		return sl
	var s := Sprite2D.new()
	s.texture = tex
	s.scale = (size + Vector2.ONE * 2.0 * Art.ART_MARGIN_M) * Art.PX_PER_M / tex.get_size()
	return s


func _body(f: Dictionary, rect: Rect2) -> void:
	var tall: bool = f["height"] >= Tuning.TALL_THRESHOLD
	var b := StaticBody2D.new()
	b.name = "F_" + f["id"]
	b.collision_layer = 1 if tall else 16
	b.collision_mask = 0
	b.set_meta("material", MATERIAL.get(f["type"], "wood"))
	var wr := Art.rect(rect)
	b.position = wr.get_center()
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = wr.size
	cs.shape = rs
	b.add_child(cs)
	if f["type"] in OCCLUDES:
		var occ := LightOccluder2D.new()
		var poly := OccluderPolygon2D.new()
		poly.cull_mode = OccluderPolygon2D.CULL_COUNTER_CLOCKWISE
		poly.polygon = Art.rect_points(Rect2(-wr.size * 0.5, wr.size))
		occ.occluder = poly
		b.add_child(occ)
	add_child(b)
	bodies.append(b)


func _placeholder(size: Vector2) -> Node2D:
	var p := Polygon2D.new()
	var r := Rect2(-size * 0.5 * Art.PX_PER_M, size * Art.PX_PER_M)
	p.polygon = Art.rect_points(r)
	p.color = Color(0.4, 0.36, 0.32)
	return p


func _sprite(art: String, pos: Vector2, rot: float, width_m: float, parent: Node2D) -> Sprite2D:
	var tex := Art.tex(art)
	if tex == null:
		return null
	var s := Sprite2D.new()
	s.texture = tex
	var k := width_m * Art.PX_PER_M / tex.get_size().x
	s.scale = Vector2(k, k)
	s.position = Art.w(pos)
	s.rotation = rot
	parent.add_child(s)
	return s


func _build_decor() -> void:
	for d in DECOR:
		_sprite(d["art"], d["pos"], d["rot"], d["size"], floor_decor)


func _build_fixtures() -> void:
	for l in HousePlan.LIGHTS:
		if not FIXTURES.has(l["kind"]):
			continue
		var spec: Array = FIXTURES[l["kind"]]
		var s := _sprite(spec[0], l["pos"], 0.0, spec[1], overhead if spec[2] else furniture)
		if s != null and not spec[2]:
			s.z_index = 1


# --- yard boundary -------------------------------------------------------------------------

func _build_boundary() -> void:
	var y := HousePlan.YARD
	var t := 1.0
	for r in [Rect2(y.position.x - t, y.position.y - t, y.size.x + 2 * t, t), Rect2(y.position.x - t, y.end.y, y.size.x + 2 * t, t),
			Rect2(y.position.x - t, y.position.y, t, y.size.y), Rect2(y.end.x, y.position.y, t, y.size.y)]:
		var b := StaticBody2D.new()
		b.collision_layer = 1
		b.collision_mask = 0
		b.set_meta("material", "wood")
		var cs := CollisionShape2D.new()
		var rs := RectangleShape2D.new()
		var wr := Art.rect(r)
		rs.size = wr.size
		cs.shape = rs
		b.position = wr.get_center()
		b.add_child(cs)
		add_child(b)
	var road_top := 13.4
	for seg in [[Vector2(y.position.x, y.position.y + 0.06), Vector2(y.end.x, y.position.y + 0.06)],
			[Vector2(y.position.x + 0.06, y.position.y), Vector2(y.position.x + 0.06, road_top)],
			[Vector2(y.end.x - 0.06, y.position.y), Vector2(y.end.x - 0.06, road_top)]]:
		var f := Fence.new()
		f.a = Art.w(seg[0])
		f.b = Art.w(seg[1])
		f.tex = Art.tex("fence")
		f.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		f.z_index = Art.Z_WALLS
		f.z_as_relative = false
		add_child(f)


## A strip texture tiled along a segment (fence boards from above).
class Fence extends Node2D:
	const ArtC := preload("res://src/illustrated/ill_art.gd")
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	var tex: Texture2D

	func _draw() -> void:
		if tex == null:
			return
		var d := b - a
		var ln := d.length()
		draw_set_transform(a, d.angle(), Vector2.ONE)
		var ts := tex.get_size()
		var h := ts.y * (4.0 * ArtC.PX_PER_M / ts.x)
		draw_texture_rect_region(tex, Rect2(Vector2(0, -h * 0.5), Vector2(ln, h)), Rect2(Vector2.ZERO, Vector2(ln / (4.0 * ArtC.PX_PER_M) * ts.x, ts.y)))


## Caps + tiled middle, for counters of any length (art authored 1.0 m long).
class Sliced extends Node2D:
	const ArtC := preload("res://src/illustrated/ill_art.gd")
	const ART_LEN_M := 1.0
	const CAP_M := 0.18
	var tex: Texture2D
	var size_m := Vector2.ONE

	func _ready() -> void:
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED

	func _draw() -> void:
		var ts := tex.get_size()
		var mg := ArtC.ART_MARGIN_M
		var art_ppm := ts.x / (ART_LEN_M + 2.0 * mg)          # texture px per meter
		var W := (size_m.x + 2.0 * mg) * ArtC.PX_PER_M
		var H := (size_m.y + 2.0 * mg) * ArtC.PX_PER_M
		var cap := (CAP_M + mg)
		var x0 := -W * 0.5
		var cap_w := cap * ArtC.PX_PER_M
		var cap_src := cap * art_ppm
		draw_texture_rect_region(tex, Rect2(x0, -H * 0.5, cap_w, H), Rect2(0, 0, cap_src, ts.y))
		draw_texture_rect_region(tex, Rect2(-x0 - cap_w, -H * 0.5, cap_w, H), Rect2(ts.x - cap_src, 0, cap_src, ts.y))
		var mid_w := W - 2.0 * cap_w
		var src_mid := ts.x - 2.0 * cap_src
		var x := x0 + cap_w
		var left := mid_w
		while left > 0.5:
			var seg := minf(left, src_mid / art_ppm * ArtC.PX_PER_M)
			draw_texture_rect_region(tex, Rect2(x, -H * 0.5, seg, H), Rect2(cap_src, 0, seg / ArtC.PX_PER_M * art_ppm, ts.y))
			x += seg
			left -= seg
