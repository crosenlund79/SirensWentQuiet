class_name VoxelArt
extends RefCounted
## Replaceable art for Version A, always loaded through AssetResolver.
##
## Swatches ("voxel/floor_wood", "voxel/siding", ...) are images where one
## pixel is the colour of one voxel face. Overrides may have any size.
## The palette ("voxel/palette") is a grid of 8x8 px swatches, 8 per row;
## slot n is sampled at the centre of swatch n (layout: docs/experiment-001/voxel.md).

enum Slot {
	SIDING_RAW, TRIM_EXT, FRAME, PLINTH, CAP, THRESHOLD, ROOF, FASCIA,
	PAINT_BEDROOM, PAINT_BATHROOM, PAINT_KITCHEN, PAINT_LIVING, PAINT_UTILITY, GYPSUM, TRIM_INT, BASEBOARD,
	STUD, SCREED, FOUNDATION, GLASS, TILE_BATH, TILE_KITCHEN, TILE_BISCUIT, SILL_EXT,
	SOFA, ARMCHAIR, DUVET, CABINET, WORKTOP, WOOD_DARK, WOOD_LIGHT, METAL_DARK,
}

## Fallback colours if an image is missing entirely (should not happen).
const FALLBACK := 0x808080

static var _images := {}


static func image(logical: String) -> Image:
	if _images.has(logical):
		return _images[logical]
	var img: Image = null
	var tex := AssetResolver.get_texture("voxel/" + logical)
	if tex != null:
		img = tex.get_image()
		if img != null:
			img = img.duplicate()
			if img.is_compressed():
				img.decompress()
			if img.has_mipmaps():
				img.clear_mipmaps()
			img.convert(Image.FORMAT_RGBA8)
	_images[logical] = img
	return img


static func clear_cache() -> void:
	_images.clear()


static func _px(img: Image, x: int, y: int) -> int:
	var c := img.get_pixel(posmod(x, img.get_width()), posmod(y, img.get_height()))
	return (int(c.r8) << 16) | (int(c.g8) << 8) | int(c.b8)


## Tiled sample: pixel (x mod w, y mod h).
static func sample(logical: String, x: int, y: int) -> int:
	var img := image(logical)
	return FALLBACK if img == null else _px(img, x, y)


## Stretched sample: u, v in [0, 1).
static func sample_uv(logical: String, u: float, v: float) -> int:
	var img := image(logical)
	if img == null:
		return FALLBACK
	return _px(img, clampi(int(u * img.get_width()), 0, img.get_width() - 1), clampi(int(v * img.get_height()), 0, img.get_height() - 1))


static func pal(slot: int) -> int:
	var img := image("palette")
	if img == null:
		return FALLBACK
	var cols := maxi(1, img.get_width() / 8)
	return _px(img, (slot % cols) * 8 + 4, (slot / cols) * 8 + 4)


# --- colour helpers (0xRRGGBB ints) ---------------------------------------------

static func scale(c: int, f: float) -> int:
	var r := clampi(int(((c >> 16) & 255) * f), 0, 255)
	var g := clampi(int(((c >> 8) & 255) * f), 0, 255)
	var b := clampi(int((c & 255) * f), 0, 255)
	return (r << 16) | (g << 8) | b


static func mix(a: int, b: int, t: float) -> int:
	var r := int(lerpf((a >> 16) & 255, (b >> 16) & 255, t))
	var g := int(lerpf((a >> 8) & 255, (b >> 8) & 255, t))
	var bl := int(lerpf(a & 255, b & 255, t))
	return (r << 16) | (g << 8) | bl


## Deterministic per-voxel hash in [0, 1).
static func hash3(x: int, y: int, z: int, seed := 0) -> float:
	var h := (x * 73856093) ^ (y * 19349663) ^ (z * 83492791) ^ (seed * 2654435761)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xffff) / 65536.0


## Colour with a small per-voxel brightness jitter.
static func jitter(c: int, x: int, y: int, z: int, amount := 0.05) -> int:
	return scale(c, 1.0 + (hash3(x, y, z) - 0.5) * 2.0 * amount)


static func to_color(c: int) -> Color:
	return Color.hex((c << 8) | 0xff)
