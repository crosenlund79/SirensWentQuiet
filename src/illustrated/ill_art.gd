extends RefCounted
## Version C shared constants and art helpers (no state besides small caches).
##
## World scale: 64 world px per plan meter. Template art is authored at
## 128 px per meter (2x) and always loaded through AssetResolver, so a creator
## can override any piece with custom/graphics/illustrated/<name>.png.

const PX_PER_M := 64.0          ## world px per meter
const ART_PX_PER_M := 128.0     ## template art density (2x world)
const ART_MARGIN_M := 0.0625    ## transparent margin baked around sprites (8 art px)
const INK := Color(0.075, 0.063, 0.059)

## Shared z layers (absolute z_index).
const Z_GROUND := -30
const Z_FLOOR_DECOR := -27
const Z_DECALS := -26
const Z_SHADOWS := -24
const Z_FURNITURE := -20
const Z_WALLS := -16
const Z_CORPSES := -12
const Z_ACTORS := -10
const Z_FX := 0
const Z_OVERHEAD := 10

## Every logical art name Version C loads ("illustrated/<name>"), grouped as in
## docs/experiment-001/illustrated.md. Tests check that each one resolves.
const MANIFEST := {
	"floors": ["floor_wood", "floor_wood_light", "floor_tile", "floor_kitchen_tile", "floor_concrete", "floor_subfloor",
		"floor_deck", "ground_grass", "ground_concrete", "ground_asphalt"],
	"walls": ["wall_ext", "wall_ext_cracked", "wall_ext_broken", "wall_int", "wall_int_cracked", "wall_int_broken",
		"window", "window_cracked", "window_shattered", "window_broken", "wall_post", "door_leaf", "fence"],
	"furniture": ["sofa", "armchair", "coffee_table", "tv_stand", "floor_lamp", "bookshelf", "dining_table", "chair", "plant",
		"rug_living", "rug_bed", "bath_mat", "counter", "sink_counter", "stove", "fridge", "island", "stool", "bed",
		"nightstand", "wardrobe", "dresser", "bathtub", "toilet", "vanity", "water_heater", "workbench", "washer",
		"shelves", "boxes"],
	"props": ["car", "dead_tree", "trash_bin", "mailbox", "streetlight"],
	"details": ["papers", "shoe", "toy", "mud_trail", "leaves", "ceiling_light", "bulb", "table_lamp"],
	"debris": ["debris_planks", "debris_plaster", "debris_glass"],
	"characters": ["player", "psycho_a", "psycho_b", "psycho_a_dead", "psycho_b_dead"],
	"lights": ["light_soft", "light_cone"],
}

static var _unshaded: CanvasItemMaterial
static var _additive: CanvasItemMaterial
static var _fx_cache := {}


static func w(p: Vector2) -> Vector2:
	return p * PX_PER_M


static func plan(p: Vector2) -> Vector2:
	return p / PX_PER_M


static func m(v: float) -> float:
	return v * PX_PER_M


static func rect(r: Rect2) -> Rect2:
	return Rect2(r.position * PX_PER_M, r.size * PX_PER_M)


## Texture for logical name "illustrated/<name>" (user override or template).
static func tex(name: String) -> Texture2D:
	return AssetResolver.get_texture("illustrated/" + name, true)


static func unshaded() -> CanvasItemMaterial:
	if _unshaded == null:
		_unshaded = CanvasItemMaterial.new()
		_unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return _unshaded


static func additive() -> CanvasItemMaterial:
	if _additive == null:
		_additive = CanvasItemMaterial.new()
		_additive.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive


static func layer(parent: Node, node_name: String, z: int) -> Node2D:
	var n := Node2D.new()
	n.name = node_name
	n.z_index = z
	n.z_as_relative = false
	parent.add_child(n)
	return n


static func rect_points(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


## Tiny procedural particle textures (effects are procedural, not replaceable art).
static func fx_texture(kind: String) -> Texture2D:
	if _fx_cache.has(kind):
		return _fx_cache[kind]
	var img: Image
	match kind:
		"dot":
			img = Image.create(24, 24, false, Image.FORMAT_RGBA8)
			for y in 24:
				for x in 24:
					var d := Vector2(x - 11.5, y - 11.5).length() / 11.5
					img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 1.6))
		"splinter":
			img = Image.create(12, 4, false, Image.FORMAT_RGBA8)
			for y in 4:
				for x in 12:
					var edge := y == 0 or y == 3 or x == 0 or x == 11
					var taper := float(x) / 11.0
					if (y == 0 or y == 3) and taper > 0.7:
						continue
					img.set_pixel(x, y, Color(0.12, 0.09, 0.07, 1) if edge else Color(1, 1, 1, 1))
		"shard":
			img = Image.create(8, 8, false, Image.FORMAT_RGBA8)
			for y in 8:
				for x in 8:
					var d := absf(x - 3.5) + absf(y - 3.5) * 1.6
					if d < 4.2:
						img.set_pixel(x, y, Color(1, 1, 1, 0.95 if d < 3.0 else 0.5))
		"spark":
			img = Image.create(16, 4, false, Image.FORMAT_RGBA8)
			for y in 4:
				for x in 16:
					var a := (1.0 - absf(y - 1.5) / 2.0) * (float(x) / 15.0)
					img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
		_:
			img = Image.create(4, 4, false, Image.FORMAT_RGBA8)
			img.fill(Color.WHITE)
	var t := ImageTexture.create_from_image(img)
	_fx_cache[kind] = t
	return t
