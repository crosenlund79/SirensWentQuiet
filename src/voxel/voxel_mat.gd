class_name VoxelMat
extends RefCounted
## Voxel material ids and their behaviour (Version A).
##
## A voxel stores one material id (byte). Colours are stored per voxel in the
## grid; the material decides how the voxel behaves: whether it is part of a
## destructible wall (collision + navigation), glass, shot through, how hard
## it is to carve and which impact effect it makes.

enum Impact { DUST, WOOD, PLASTER, GLASS, METAL, FABRIC, CONCRETE, CERAMIC, FLUFF, PLANT, PAPER }

const AIR := 0
# --- house structure -----------------------------------------------------------
const FOUNDATION := 1     ## concrete slab bottom, never carved
const SCREED := 2         ## subfloor
const FLOOR := 3          ## floor finish (planks / tiles / concrete, colour per voxel)
const RUG := 4            ## rug lying on the floor finish
const PLINTH := 5         ## exterior concrete base strip (structural)
const SIDING := 6         ## painted exterior boards (structural)
const STUD := 7           ## timber studs and plates (structural)
const INSULATION := 8     ## mineral wool between studs (structural)
const DRYWALL := 9        ## painted gypsum board (structural)
const WALL_TILE := 10     ## bathroom / kitchen wall tiles (structural)
const TRIM := 11          ## door jambs, corner boards, headers (structural)
const FRAME := 12         ## window frames, aluminium (structural)
const GLASS := 13         ## window panes
const SILL := 14          ## protruding sills (decor, no collision)
const BASEBOARD := 15     ## skirting boards (decor, no collision)
const THRESHOLD := 16     ## door thresholds in the floor
# --- furniture and props (low pieces; tall versions add TALL) -------------------
const WOOD := 32
const FABRIC := 33
const METAL := 34
const CERAMIC := 35
const PLASTIC := 36
const GLOW := 37          ## lamp shades / bulbs (emissive at night)
const FOAM := 38
const LEAF := 39
const SCREEN := 40
const PAPER := 41
const STONE := 42
const BARK := 43
const PAINTED := 44       ## painted metal (car body, appliances)
const RUBBER := 45
const TALL := 32          ## offset: tall furniture (>= Tuning.TALL_THRESHOLD) uses id + TALL

# Flag bits
const F_SOLID := 1        ## occupies space, gets meshed
const F_STRUCT := 2       ## destructible wall: collision, navigation
const F_GLASS := 4        ## transparent surface, no AO
const F_PASS := 8         ## bullets pass through (low furniture)
const F_HARD := 16        ## never carved
const F_EMISSIVE := 32    ## glows at night
const F_GLOSSY := 64      ## smoother / slightly metallic look

## Per-id tables, indexed by material id.
static var FLAGS := _make_flags()
static var OCCLUDES := _make_occludes()
static var STRUCT := _make_struct()
static var HARDNESS := _make_hardness()
static var IMPACT := _make_impact()


static func _make_flags() -> PackedByteArray:
	var f := PackedByteArray()
	f.resize(256)
	for id in [FOUNDATION, SCREED, FLOOR, RUG, THRESHOLD]:
		f[id] = F_SOLID
	f[FOUNDATION] |= F_HARD
	for id in [PLINTH, SIDING, STUD, INSULATION, DRYWALL, WALL_TILE, TRIM, FRAME]:
		f[id] = F_SOLID | F_STRUCT
	f[WALL_TILE] |= F_GLOSSY
	f[FRAME] |= F_GLOSSY
	f[GLASS] = F_SOLID | F_GLASS
	f[SILL] = F_SOLID
	f[BASEBOARD] = F_SOLID
	for id in range(WOOD, RUBBER + 1):
		f[id] = F_SOLID | F_PASS
		f[id + TALL] = F_SOLID
	for id in [METAL, CERAMIC, SCREEN, PAINTED]:
		f[id] |= F_GLOSSY
		f[id + TALL] |= F_GLOSSY
	f[GLOW] |= F_EMISSIVE
	f[GLOW + TALL] |= F_EMISSIVE
	return f


static func _make_occludes() -> PackedByteArray:
	var o := PackedByteArray()
	o.resize(256)
	for i in 256:
		o[i] = 1 if (FLAGS[i] & F_SOLID) != 0 and (FLAGS[i] & F_GLASS) == 0 else 0
	return o


static func _make_struct() -> PackedByteArray:
	var s := PackedByteArray()
	s.resize(256)
	for i in 256:
		s[i] = 1 if (FLAGS[i] & F_STRUCT) != 0 else 0
	return s


## 0 = carves easily, 1 = barely. Scales the carve radius for this material.
static func _make_hardness() -> PackedFloat32Array:
	var h := PackedFloat32Array()
	h.resize(256)
	h[SCREED] = 0.55
	h[FLOOR] = 0.35
	h[RUG] = 0.2
	h[PLINTH] = 0.25
	h[STUD] = 0.3
	h[TRIM] = 0.15
	h[FRAME] = 0.2
	h[THRESHOLD] = 0.4
	for id in [METAL, STONE, PAINTED]:
		h[id] = 0.35
		h[id + TALL] = 0.35
	return h


static func _make_impact() -> PackedByteArray:
	var m := PackedByteArray()
	m.resize(256)
	var table := {
		FOUNDATION: Impact.CONCRETE, SCREED: Impact.CONCRETE, FLOOR: Impact.WOOD, RUG: Impact.FABRIC,
		PLINTH: Impact.CONCRETE, SIDING: Impact.WOOD, STUD: Impact.WOOD, INSULATION: Impact.FLUFF,
		DRYWALL: Impact.PLASTER, WALL_TILE: Impact.CERAMIC, TRIM: Impact.WOOD, FRAME: Impact.METAL,
		GLASS: Impact.GLASS, SILL: Impact.WOOD, BASEBOARD: Impact.WOOD, THRESHOLD: Impact.WOOD,
		WOOD: Impact.WOOD, FABRIC: Impact.FABRIC, METAL: Impact.METAL, CERAMIC: Impact.CERAMIC,
		PLASTIC: Impact.DUST, GLOW: Impact.GLASS, FOAM: Impact.FLUFF, LEAF: Impact.PLANT,
		SCREEN: Impact.GLASS, PAPER: Impact.PAPER, STONE: Impact.CONCRETE, BARK: Impact.WOOD,
		PAINTED: Impact.METAL, RUBBER: Impact.DUST,
	}
	for id in table:
		m[id] = table[id]
		if id >= WOOD:
			m[id + TALL] = table[id]
	return m


static func is_struct(id: int) -> bool:
	return STRUCT[id] == 1


static func flags(id: int) -> int:
	return FLAGS[id]


## Low furniture id -> tall variant when the piece blocks bullets.
static func furniture(id: int, tall: bool) -> int:
	return id + TALL if tall and id >= WOOD and id < WOOD + TALL else id
