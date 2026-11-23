class_name PropMaterials
extends RefCounted
## Shared materials for the hybrid props. One surface shader covers every
## piece (one material, so one draw call per piece); a second, translucent
## one draws build previews. Textures come from AssetResolver ("props/<name>"),
## so a creator can override them with custom/graphics/props/<name>.png.
## Forked from Experiment 001's modular kit materials (no runtime link to it).

# Material layers (stored per vertex in UV2.x, see props.gdshader).
const L_PLAIN := 0       ## matte paint, plastic
const L_WOOD := 1        ## furniture wood (props/wood_grain)
const L_FABRIC := 2      ## upholstery, bedding, rugs (props/fabric)
const L_METAL := 3       ## painted or bare metal
const L_GLOSSY := 4      ## ceramic, enamel, glossy plastic
const L_SCREEN := 5      ## dark glass, screens
const L_MIRROR := 6      ## mirror
const L_ROUGH_WOOD := 7  ## weathered planks (props/rough_wood)
const L_CONCRETE := 8    ## props/concrete
const L_ASPHALT := 9     ## props/asphalt
const L_BARK := 10
const L_SOIL := 11
const L_FOLIAGE := 12    ## dry leaves and twigs
const L_GLOW := 13       ## lantern diffuser, bulbs: emissive with `lit`
const L_FLAME := 14      ## candle flame: drawn only while `lit` > 0
const L_PAPER := 15      ## paper, cardboard
const L_RUST := 16       ## corroded metal
const L_TARP := 17       ## plastic sheet
const L_WAX := 18        ## candle wax (warms while lit)
const L_ROAD_PAINT := 19

## Shader parameter -> logical texture name (custom/graphics/props/<name>.png).
const TEXTURES := {
	"t_wood": "wood_grain",
	"t_rough": "rough_wood",
	"t_fabric": "fabric",
	"t_concrete": "concrete",
	"t_asphalt": "asphalt",
}

const SHADER_PATH := "res://src/props/props.gdshader"
const GHOST_SHADER_PATH := "res://src/props/prop_ghost.gdshader"

static var _kit: ShaderMaterial
static var _ghost: ShaderMaterial


## The one opaque material every prop uses.
static func kit() -> ShaderMaterial:
	if _kit == null:
		_kit = ShaderMaterial.new()
		_kit.shader = load(SHADER_PATH)
		for param in TEXTURES:
			_kit.set_shader_parameter(param, AssetResolver.get_texture("props/" + TEXTURES[param], true))
	return _kit


## Translucent preview material (instance parameter `tint`).
static func ghost() -> ShaderMaterial:
	if _ghost == null:
		_ghost = ShaderMaterial.new()
		_ghost.shader = load(GHOST_SHADER_PATH)
	return _ghost


## Materials that take the voxel cutaway uniforms (cut_origin, cut_dir,
## cut_radius, cut_floor): add these to HouseWorld's cut list.
static func cut_materials() -> Array[ShaderMaterial]:
	return [kit()]


## Drop the cached materials (tests that swap the override root call this).
static func reset() -> void:
	_kit = null
	_ghost = null
