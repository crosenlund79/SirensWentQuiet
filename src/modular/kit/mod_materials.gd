class_name ModMaterials
extends RefCounted
## Shared materials for Version B. One kit shader covers every static piece;
## its textures come from AssetResolver ("modular/<name>"), so a creator can
## override them with custom/graphics/modular/<name>.png.

# Material layers (stored per vertex in UV2.x, see kit.gdshader).
const L_SIDING := 0
const L_PAINT := 1
const L_TRIM := 2
const L_CAP := 3
const L_TIMBER := 4
const L_INSULATION := 5
const L_GYPSUM := 6
const L_METAL := 7
const L_FLOOR_WOOD := 8
const L_FLOOR_WOOD_LIGHT := 9
const L_FLOOR_TILE := 10
const L_FLOOR_KITCHEN := 11
const L_CONCRETE := 12
const L_ROOF := 13
const L_GRASS := 14
const L_ASPHALT := 15
const L_FABRIC := 16
const L_WOOD := 17
const L_PLAIN := 18
const L_GLOSSY := 19
const L_EMISSIVE := 20
const L_SCREEN := 21
const L_SOIL := 22
const L_CONCRETE_PLAIN := 23
const L_BARK := 24
const L_ROAD_PAINT := 25
const L_MIRROR := 26

## Logical texture names (custom/graphics/modular/<name>.png overrides).
const TEXTURES := {
	"t_siding": "siding",
	"t_plaster": "plaster",
	"t_wood": "floor_wood",
	"t_wood_light": "floor_wood_light",
	"t_tile": "floor_tile",
	"t_kitchen": "floor_kitchen_tile",
	"t_concrete": "concrete",
	"t_roof": "roof",
	"t_grass": "grass",
	"t_asphalt": "asphalt",
	"t_fabric": "fabric",
	"t_grain": "wood_grain",
}
const MARKS_TEXTURE := "marks"

## Floor finish per HousePlan room "floor" value.
const FLOOR_LAYERS := {
	"wood_light": L_FLOOR_WOOD_LIGHT,
	"tile": L_FLOOR_TILE,
	"kitchen_tile": L_FLOOR_KITCHEN,
	"wood": L_FLOOR_WOOD,
	"concrete": L_CONCRETE,
}

## Room paint (sRGB) applied per wall side through instance uniforms.
const ROOM_PAINT := {
	"bedroom": Color(0.80, 0.85, 0.78),     # pale sage
	"bathroom": Color(0.80, 0.88, 0.90),    # washed aqua
	"kitchen": Color(0.97, 0.93, 0.84),     # warm cream
	"living": Color(0.93, 0.87, 0.80),      # warm greige
	"utility": Color(0.78, 0.79, 0.80),     # grey primer
	"": Color(0.9, 0.9, 0.88),
}

const SIDING_TINT := Color(1, 1, 1)
const FRAME_COLOR := Color(0.13, 0.135, 0.15)     # charcoal window frames, posts
const TRIM_COLOR := Color(0.93, 0.92, 0.89)
const TIMBER_COLOR := Color(0.86, 0.72, 0.5)
const SHEATHING_COLOR := Color(0.62, 0.5, 0.34)
const INSULATION_COLOR := Color(0.95, 0.8, 0.52)
const GYPSUM_COLOR := Color(0.92, 0.9, 0.86)

static var _kit: ShaderMaterial
static var _glass: ShaderMaterial
static var _marks: ShaderMaterial
static var _figure: ShaderMaterial
static var _fx_add: StandardMaterial3D
static var _fx_dust: StandardMaterial3D
static var _fx_solid: ShaderMaterial


static func kit() -> ShaderMaterial:
	if _kit == null:
		_kit = ShaderMaterial.new()
		_kit.shader = load("res://src/modular/kit/kit.gdshader")
		for param in TEXTURES:
			_kit.set_shader_parameter(param, AssetResolver.get_texture("modular/" + TEXTURES[param], true))
		_kit.set_shader_parameter("trim_color", TRIM_COLOR)
	return _kit


static func glass() -> ShaderMaterial:
	if _glass == null:
		_glass = ShaderMaterial.new()
		_glass.shader = load("res://src/modular/kit/glass.gdshader")
		_glass.set_shader_parameter("t_marks", AssetResolver.get_texture("modular/" + MARKS_TEXTURE, true))
		_glass.render_priority = 1
	return _glass


## Bullet holes, cracks and gashes: atlas quads on a MultiMesh (INSTANCE_CUSTOM.x = cell).
static func marks() -> ShaderMaterial:
	if _marks == null:
		_marks = ShaderMaterial.new()
		_marks.shader = load("res://src/modular/kit/marks.gdshader")
		_marks.set_shader_parameter("t_marks", AssetResolver.get_texture("modular/" + MARKS_TEXTURE, true))
	return _marks


static func figure() -> ShaderMaterial:
	if _figure == null:
		_figure = ShaderMaterial.new()
		_figure.shader = load("res://src/modular/actors/figure.gdshader")
	return _figure


## Additive glow (muzzle flash, tracers, sparks).
static func fx_add() -> StandardMaterial3D:
	if _fx_add == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.no_depth_test = false
		m.disable_receive_shadows = true
		_fx_add = m
	return _fx_add


## Soft dust puffs (alpha-blended, lit, billboards).
static func fx_dust() -> StandardMaterial3D:
	if _fx_dust == null:
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.vertex_color_use_as_albedo = true
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.albedo_texture = _soft_disc()
		m.roughness = 1.0
		m.disable_receive_shadows = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_fx_dust = m
	return _fx_dust


## Solid debris chips (opaque, per-instance colour and layer-free).
static func fx_solid() -> ShaderMaterial:
	if _fx_solid == null:
		_fx_solid = ShaderMaterial.new()
		_fx_solid.shader = load("res://src/modular/fx/chip.gdshader")
	return _fx_solid


static func _soft_disc() -> Texture2D:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(x - size * 0.5 + 0.5, y - size * 0.5 + 0.5).length() / (size * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


## Paint colour of the room at a plan point (exterior -> "").
static func paint_at(p: Vector2) -> Color:
	var r := HousePlan.room_at(p)
	return ROOM_PAINT.get(r.get("id", ""), ROOM_PAINT[""])
