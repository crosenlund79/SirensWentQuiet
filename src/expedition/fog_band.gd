class_name FogBand
extends RefCounted
## Exp 012 (V): the edge of the world without an invisible wall (the user's
## §19). Between `inner` (the playable area) and `outer` (a safety wall just
## beyond) Eli slows gradually the deeper he walks into the fog: the part of
## his wanted velocity that points further out shrinks with the depth (to
## nothing at `outer`). The part that points back in, or along the edge, is
## untouched, so turning back is immediate and he is never trapped. Inside
## `inner` nothing changes. VoxelPlayer applies it to its wanted velocity
## (`move_band`); FogBoundary sets the home's, game_visibility.gd a POI's.

const HOME_DEPTH := 2.0                ## m of fog past the lot edge
const POI_INSET := 1.2                 ## a POI's band starts this far inside its walkable yard ...
const POI_WALL := 0.3                  ## ... and ends at its invisible bounds (PoiWorld: YARD.grow(-0.3))
const MIN_FACTOR := 0.0

var inner: Rect2
var outer: Rect2


func _init(i := Rect2(), o := Rect2()) -> void:
	inner = i
	outer = o


static func for_home() -> FogBand:
	return FogBand.new(FogBoundary.LOT, FogBoundary.LOT.grow(HOME_DEPTH))


static func for_poi() -> FogBand:
	return FogBand.new(HousePlan.YARD.grow(-POI_INSET), HousePlan.YARD.grow(-POI_WALL))


## How far (0..1) into the band along each side; 0 inside `inner`.
func depth_of(p: Vector2) -> float:
	return maxf(maxf(_d(p.x - inner.end.x, outer.end.x - inner.end.x), _d(inner.position.x - p.x, inner.position.x - outer.position.x)),
		maxf(_d(p.y - inner.end.y, outer.end.y - inner.end.y), _d(inner.position.y - p.y, inner.position.y - outer.position.y)))


static func _d(over: float, span: float) -> float:
	return clampf(over / maxf(span, 0.01), 0.0, 1.0) if over > 0.0 else 0.0


## The speed factor (1 .. 0) for moving further out at depth d (0..1): eases off.
static func factor(d: float) -> float:
	return maxf(pow(1.0 - clampf(d, 0.0, 1.0), 1.6), MIN_FACTOR)


## `want` (a world velocity, XZ used) with its outward parts slowed for a body at `pos`.
func limit(pos: Vector3, want: Vector3) -> Vector3:
	var p := Vector2(pos.x, pos.z)
	if inner.has_point(p):
		return want
	var v := want
	if p.x > inner.end.x and v.x > 0.0:
		v.x *= factor(_d(p.x - inner.end.x, outer.end.x - inner.end.x))
	elif p.x < inner.position.x and v.x < 0.0:
		v.x *= factor(_d(inner.position.x - p.x, inner.position.x - outer.position.x))
	if p.y > inner.end.y and v.z > 0.0:
		v.z *= factor(_d(p.y - inner.end.y, outer.end.y - inner.end.y))
	elif p.y < inner.position.y and v.z < 0.0:
		v.z *= factor(_d(inner.position.y - p.y, inner.position.y - outer.position.y))
	return v
