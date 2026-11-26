class_name MarkIcons
extends RefCounted
## Exp 012 (L, §24): the searchable-object markers' icons, drawn once in code
## (smooth, anti-aliased, a restrained modern style instead of the pixel
## bitmaps): a light disc with a dark rim under each glyph so it reads on
## snow, floors and dark rooms alike.
##   search  a ring with a dot: something to search
##   left    a ring with a filled centre: searched, something left
##   lock    a padlock: needs a crowbar
##   dark    a flashlight beam: too dark without one
##   empty   a small tick: searched, nothing left
##   take    a down arrow into a tray: a loose item to pick up

const SIZE := 64          ## texture px (drawn 2x and filtered down)
const SS := 2

static var _cache := {}


static func texture(kind: String) -> Texture2D:
	if _cache.has(kind):
		return _cache[kind]
	var n := SIZE * SS
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := float(n) * 0.5
	var r := float(n) * 0.5
	# the backing disc: dark rim, dark translucent face
	_disc(img, c, c, r * 0.98, Color(0.0, 0.01, 0.02, 0.55))
	_disc(img, c, c, r * 0.86, Color(0.07, 0.08, 0.09, 0.78))
	var w := Color(1, 1, 1, 1)          # glyphs are white: the marker tints them
	match kind:
		"search":
			_ring(img, c, c, r * 0.56, r * 0.1, w)
			_disc(img, c, c, r * 0.16, w)
		"left":
			_ring(img, c, c, r * 0.56, r * 0.1, w)
			_disc(img, c, c, r * 0.34, w)
		"lock":
			_ring_top(img, c, c - r * 0.12, r * 0.26, r * 0.09, w)
			_rect(img, c - r * 0.36, c - r * 0.12, r * 0.72, r * 0.56, w)
			_disc(img, c, c + r * 0.12, r * 0.08, Color(0.07, 0.08, 0.09, 1))
		"dark":
			_rect(img, c - r * 0.52, c - r * 0.12, r * 0.42, r * 0.24, w)
			_tri(img, Vector2(c - r * 0.1, c - r * 0.14), Vector2(c + r * 0.56, c - r * 0.42), Vector2(c + r * 0.56, c + r * 0.42), Vector2(c - r * 0.1, c + r * 0.14), w)
		"empty":
			_line(img, Vector2(c - r * 0.34, c + r * 0.02), Vector2(c - r * 0.08, c + r * 0.28), r * 0.1, w)
			_line(img, Vector2(c - r * 0.08, c + r * 0.28), Vector2(c + r * 0.38, c - r * 0.26), r * 0.1, w)
		"take":
			_rect(img, c - r * 0.07, c - r * 0.46, r * 0.14, r * 0.42, w)
			_tri(img, Vector2(c - r * 0.26, c - r * 0.08), Vector2(c + r * 0.26, c - r * 0.08), Vector2(c, c + r * 0.2), Vector2(c, c + r * 0.2), w)
			_rect(img, c - r * 0.42, c + r * 0.28, r * 0.84, r * 0.1, w)
		_:
			_disc(img, c, c, r * 0.2, w)
	img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	var t := ImageTexture.create_from_image(img)
	_cache[kind] = t
	return t


static func _blend(img: Image, x: int, y: int, col: Color, a: float) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height() or a <= 0.0:
		return
	var src := Color(col, col.a * clampf(a, 0.0, 1.0))
	var dst := img.get_pixel(x, y)
	var oa := src.a + dst.a * (1.0 - src.a)
	if oa <= 0.0:
		return
	var rgb := (Color(src.r, src.g, src.b) * src.a + Color(dst.r, dst.g, dst.b) * dst.a * (1.0 - src.a)) / oa
	img.set_pixel(x, y, Color(rgb.r, rgb.g, rgb.b, oa))


static func _disc(img: Image, cx: float, cy: float, rad: float, col: Color) -> void:
	for y in range(int(cy - rad - 1), int(cy + rad + 2)):
		for x in range(int(cx - rad - 1), int(cx + rad + 2)):
			var d := Vector2(x + 0.5 - cx, y + 0.5 - cy).length()
			_blend(img, x, y, col, clampf(rad - d + 0.5, 0.0, 1.0))


static func _ring(img: Image, cx: float, cy: float, rad: float, wid: float, col: Color) -> void:
	for y in range(int(cy - rad - wid - 1), int(cy + rad + wid + 2)):
		for x in range(int(cx - rad - wid - 1), int(cx + rad + wid + 2)):
			var d := absf(Vector2(x + 0.5 - cx, y + 0.5 - cy).length() - rad)
			_blend(img, x, y, col, clampf(wid * 0.5 - d + 0.5, 0.0, 1.0))


## The upper half of a ring (a padlock's shackle), down to its centre line.
static func _ring_top(img: Image, cx: float, cy: float, rad: float, wid: float, col: Color) -> void:
	for y in range(int(cy - rad - wid - 1), int(cy + 1)):
		for x in range(int(cx - rad - wid - 1), int(cx + rad + wid + 2)):
			var d := absf(Vector2(x + 0.5 - cx, y + 0.5 - cy).length() - rad)
			_blend(img, x, y, col, clampf(wid * 0.5 - d + 0.5, 0.0, 1.0))
	_rect(img, cx - rad - wid * 0.5, cy, wid, rad * 0.4, col)
	_rect(img, cx + rad - wid * 0.5, cy, wid, rad * 0.4, col)


static func _rect(img: Image, x0: float, y0: float, w: float, h: float, col: Color) -> void:
	for y in range(int(y0), int(ceil(y0 + h))):
		for x in range(int(x0), int(ceil(x0 + w))):
			var ax := clampf(minf(x + 1.0 - x0, x0 + w - x), 0.0, 1.0)
			var ay := clampf(minf(y + 1.0 - y0, y0 + h - y), 0.0, 1.0)
			_blend(img, x, y, col, ax * ay)


## A convex quad (or a triangle with d == c).
static func _tri(img: Image, a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
	var poly := PackedVector2Array([a, b, c, d])
	var lo := Vector2(minf(minf(a.x, b.x), minf(c.x, d.x)), minf(minf(a.y, b.y), minf(c.y, d.y)))
	var hi := Vector2(maxf(maxf(a.x, b.x), maxf(c.x, d.x)), maxf(maxf(a.y, b.y), maxf(c.y, d.y)))
	for y in range(int(lo.y), int(ceil(hi.y)) + 1):
		for x in range(int(lo.x), int(ceil(hi.x)) + 1):
			var hits := 0
			for sy in 2:
				for sx in 2:
					if Geometry2D.is_point_in_polygon(Vector2(x + 0.25 + sx * 0.5, y + 0.25 + sy * 0.5), poly):
						hits += 1
			_blend(img, x, y, col, hits / 4.0)


static func _line(img: Image, a: Vector2, b: Vector2, wid: float, col: Color) -> void:
	var lo := a.min(b) - Vector2(wid, wid)
	var hi := a.max(b) + Vector2(wid, wid)
	for y in range(int(lo.y), int(ceil(hi.y))):
		for x in range(int(lo.x), int(ceil(hi.x))):
			var p := Vector2(x + 0.5, y + 0.5)
			var q := Geometry2D.get_closest_point_to_segment(p, a, b)
			_blend(img, x, y, col, clampf(wid * 0.5 - p.distance_to(q) + 0.5, 0.0, 1.0))
