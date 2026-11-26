class_name EliSculpt
extends RefCounted
## Experiment 010: the hand-sculpted voxel body parts of Elias "Eli" Walker.
##
## Every part is an implicit sculpture (capsules, ellipsoids, rounded boxes
## joined with smooth unions) voxelized at VS, then painted voxel by voxel
## (seams, stitches, pockets, laces, face) and meshed once with a face-culled
## mesher that bakes ambient occlusion into COLOR.a and a little cavity
## darkening / edge highlighting into the colours. Meshes are cached per
## variant and part; nothing is rebuilt per frame.
##
## Part spaces: the pivot of the part is the origin, limbs hang along -Y,
## the character faces -Z and his right side is +X. `side` is +1 for the
## right limb, -1 for the left one.

const VS := 0.015

## Variations: jacket, scarf, hair, beard (0 stubble, 1 short beard, 2 clean).
const VARIANTS := [
	{"name": "Canvas jacket", "jacket": 0x87694a, "jacket_dk": 0x67503a, "jacket_lt": 0x9f8462, "collar": 0x4b3526,
		"scarf": 0x8a3a31, "scarf_dk": 0x672c26, "hair": 0x4a3222, "hair_lt": 0x6c4a31, "beard": 1, "grey": 0.18,
		"knit": 0x5b636b, "legs": 0x4a4842, "lining": 0x6e3d33},
	{"name": "Forest overshirt", "jacket": 0x515a40, "jacket_dk": 0x3f4632, "jacket_lt": 0x687254, "collar": 0x3b3226,
		"scarf": 0x9c7d3c, "scarf_dk": 0x775e2c, "hair": 0x2c211b, "hair_lt": 0x463428, "beard": 1, "grey": 0.08,
		"knit": 0x6a5a4c, "legs": 0x3d3b38, "lining": 0x8a6a3a},
	{"name": "Grey morning", "jacket": 0x414852, "jacket_dk": 0x323840, "jacket_lt": 0x58606b, "collar": 0x2a2622,
		"scarf": 0xa4582e, "scarf_dk": 0x7e4223, "hair": 0x6a6259, "hair_lt": 0x8c857c, "beard": 2, "grey": 0.45,
		"knit": 0x7b766d, "legs": 0x4a4236, "lining": 0x5b6b7a},
]

## Fixed colours (all variants).
const SKIN := 0xd59d7f
const SKIN_DK := 0xb07a61
const SKIN_RED := 0xcf8a72
const LIP := 0xa5645a
const EYE_WHITE := 0xe9e3d8
const IRIS := 0x2f4150
const LASH := 0x2a1c15
const BELT := 0x3a291d
const BUCKLE := 0xb3ad9e
const LEATHER := 0x6e4a2d
const BOOT := 0x6f4a2b
const BOOT_DK := 0x4d331f
const SOLE := 0x29241f
const LACE := 0xc9ab7b
const PENCIL := 0xd9a128
const TAPE := 0xcf9f24
const GLOVE := 0x8e6e4a
const PATCH := 0x5a4431
const BRASS := 0x9a7d48
const METAL_DK := 0x2a2c30
const METAL := 0x3d4046

## [part] -> [lo, hi] bounds in part space.
const BOUNDS := {
	"head": [Vector3(-0.13, -0.06, -0.16), Vector3(0.13, 0.37, 0.15)],
	"chest": [Vector3(-0.27, -0.12, -0.2), Vector3(0.27, 0.57, 0.19)],
	"pelvis": [Vector3(-0.2, -0.2, -0.15), Vector3(0.2, 0.1, 0.16)],
	"uarm": [Vector3(-0.085, -0.3, -0.085), Vector3(0.085, 0.08, 0.085)],
	"farm": [Vector3(-0.07, -0.27, -0.07), Vector3(0.07, 0.06, 0.07)],
	"hand": [Vector3(-0.05, -0.19, -0.085), Vector3(0.05, 0.03, 0.05)],
	"fist": [Vector3(-0.06, -0.15, -0.085), Vector3(0.06, 0.03, 0.05)],
	"thigh": [Vector3(-0.11, -0.44, -0.11), Vector3(0.11, 0.08, 0.11)],
	"shin": [Vector3(-0.085, -0.43, -0.09), Vector3(0.085, 0.07, 0.09)],
	"foot": [Vector3(-0.075, -0.11, -0.22), Vector3(0.075, 0.06, 0.1)],
	"pistol": [Vector3(-0.03, -0.28, -0.04), Vector3(0.03, 0.0, 0.13)],
}

static var _cache := {}
static var build_ms := 0.0             ## total time spent building meshes (diagnostics)
static var vertex_counts := {}         ## "variant/part" -> vertices


static func variant_count() -> int:
	return VARIANTS.size()


static func variant_name(i: int) -> String:
	return str(VARIANTS[clampi(i, 0, VARIANTS.size() - 1)]["name"])


## The cached mesh of `part` ("head", "chest", "pelvis", "uarm_l", "farm_r",
## "hand_l", "fist_r", "thigh_l", "shin_r", "foot_l", "pistol", ...).
static func mesh(variant: int, part: String, material: Material) -> ArrayMesh:
	variant = clampi(variant, 0, VARIANTS.size() - 1)
	var key := "%d/%s" % [variant, part]
	if _cache.has(key):
		return _cache[key]
	var t0 := Time.get_ticks_usec()
	var base := part
	var side := 0.0
	if part.ends_with("_l"):
		base = part.trim_suffix("_l")
		side = -1.0
	elif part.ends_with("_r"):
		base = part.trim_suffix("_r")
		side = 1.0
	var v: Dictionary = VARIANTS[variant]
	var g := _voxelize(base, side, v)
	_shade(g)
	var m := _mesh_grid(g, material)
	_cache[key] = m
	vertex_counts[key] = g["verts"]
	build_ms += float(Time.get_ticks_usec() - t0) / 1000.0
	return m


# --- grid ------------------------------------------------------------------------------

static func _voxelize(part: String, side: float, v: Dictionary) -> Dictionary:
	var b: Array = BOUNDS[part]
	var lo: Vector3 = b[0]
	var hi: Vector3 = b[1]
	# cell centres sit on multiples of VS (x = 0 is a column centre: a centred nose)
	var i0 := Vector3i(floori(lo.x / VS) - 1, floori(lo.y / VS) - 1, floori(lo.z / VS) - 1)
	var i1 := Vector3i(ceili(hi.x / VS) + 1, ceili(hi.y / VS) + 1, ceili(hi.z / VS) + 1)
	var n := i1 - i0 + Vector3i.ONE
	var col := PackedInt32Array()
	col.resize(n.x * n.y * n.z)
	col.fill(-1)
	for y in range(1, n.y - 1):
		for z in range(1, n.z - 1):
			for x in range(1, n.x - 1):
				var ix := i0.x + x
				var iy := i0.y + y
				var iz := i0.z + z
				var p := Vector3(ix, iy, iz) * VS
				var c := -1
				match part:
					"head": c = _head(p, v, ix, iy, iz)
					"chest": c = _chest(p, v, ix, iy, iz)
					"pelvis": c = _pelvis(p, v, ix, iy, iz)
					"uarm": c = _uarm(p, side, v, ix, iy, iz)
					"farm": c = _farm(p, side, v, ix, iy, iz)
					"hand": c = _hand(p, side, false, ix, iy, iz)
					"fist": c = _hand(p, side, true, ix, iy, iz)
					"thigh": c = _thigh(p, side, v, ix, iy, iz)
					"shin": c = _shin(p, side, v, ix, iy, iz)
					"foot": c = _foot(p, side, ix, iy, iz)
					"pistol": c = _pistol(p, ix, iy, iz)
				col[(y * n.z + z) * n.x + x] = c
	return {"n": n, "i0": i0, "col": col, "verts": 0}


## Cavity darkening and edge highlights: the share of filled cells in a 5^3
## block around each voxel (3D prefix sums). Creases darken, ridges brighten,
## like a hand-painted voxel model.
static func _shade(g: Dictionary) -> void:
	var n: Vector3i = g["n"]
	var col: PackedInt32Array = g["col"]
	var px := n.x + 1
	var pz := n.z + 1
	var ps := PackedInt32Array()
	ps.resize((n.x + 1) * (n.y + 1) * (n.z + 1))
	for y in n.y:
		for z in n.z:
			for x in n.x:
				var f := 1 if col[(y * n.z + z) * n.x + x] >= 0 else 0
				var i := ((y + 1) * pz + (z + 1)) * px + (x + 1)
				ps[i] = f + ps[i - 1] + ps[i - px] + ps[i - px * pz] - ps[i - 1 - px] - ps[i - 1 - px * pz] \
						- ps[i - px - px * pz] + ps[i - 1 - px - px * pz]
	var out := col.duplicate()
	for y in range(1, n.y - 1):
		for z in range(1, n.z - 1):
			for x in range(1, n.x - 1):
				var i := (y * n.z + z) * n.x + x
				var c := col[i]
				if c < 0:
					continue
				var x0 := maxi(x - 2, 0)
				var y0 := maxi(y - 2, 0)
				var z0 := maxi(z - 2, 0)
				var x1 := mini(x + 3, n.x)
				var y1 := mini(y + 3, n.y)
				var z1 := mini(z + 3, n.z)
				var s := ps[(y1 * pz + z1) * px + x1] - ps[(y0 * pz + z1) * px + x1] - ps[(y1 * pz + z0) * px + x1] \
						- ps[(y1 * pz + z1) * px + x0] + ps[(y0 * pz + z0) * px + x1] + ps[(y0 * pz + z1) * px + x0] \
						+ ps[(y1 * pz + z0) * px + x0] - ps[(y0 * pz + z0) * px + x0]
				var vol := float((x1 - x0) * (y1 - y0) * (z1 - z0))
				var d := float(s) / vol
				var f := 1.0 + clampf((0.56 - d) * 0.3, -0.08, 0.035)
				out[i] = VoxelArt.scale(c, f)
	g["col"] = out


const _N := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const _U := [Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0)]
const _V := [Vector3i(0, 0, 1), Vector3i(0, 1, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 1, 0), Vector3i(1, 0, 0)]
const _AO := [0.62, 0.8, 0.92, 1.0]


## Face-culled mesh with per-vertex AO (COLOR.a, as VoxelMesher does).
static func _mesh_grid(g: Dictionary, material: Material) -> ArrayMesh:
	return arrays_to_mesh(grid_arrays(g), material)


## Exp 011: the mesh from grid_arrays() (main thread; null arrays = empty).
static func arrays_to_mesh(arr: Variant, material: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if arr == null:
		return mesh
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, material)
	return mesh


## Exp 011: the surface arrays of a voxel grid ({"n", "i0", "col"}; cells
## < 0 are empty), or null when it has no faces. Sets g["verts"]. Pure: safe
## on a worker thread (HumanoidSculpt builds its parts in parallel).
static func grid_arrays(g: Dictionary) -> Variant:
	var n: Vector3i = g["n"]
	var i0: Vector3i = g["i0"]
	var col: PackedInt32Array = g["col"]
	var sx := n.x
	var sxz := n.x * n.z
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var inds := PackedInt32Array()
	var dn := []
	var du := []
	var dv := []
	for d in 6:
		var a: Vector3i = _N[d]
		var u: Vector3i = _U[d]
		var w: Vector3i = _V[d]
		dn.append(a.x + a.z * sx + a.y * sxz)
		du.append(u.x + u.z * sx + u.y * sxz)
		dv.append(w.x + w.z * sx + w.y * sxz)
	var nv := 0
	for y in range(1, n.y - 1):
		for z in range(1, n.z - 1):
			for x in range(1, n.x - 1):
				var i := (y * n.z + z) * n.x + x
				var c := col[i]
				if c < 0:
					continue
				var colr := Color.hex((c << 8) | 0xff)
				var centre := Vector3(i0.x + x, i0.y + y, i0.z + z) * VS
				for d in 6:
					var ni: int = i + dn[d]
					if col[ni] >= 0:
						continue
					var u: int = du[d]
					var w: int = dv[d]
					var s_um := 1 if col[ni - u] >= 0 else 0
					var s_up := 1 if col[ni + u] >= 0 else 0
					var s_vm := 1 if col[ni - w] >= 0 else 0
					var s_vp := 1 if col[ni + w] >= 0 else 0
					var c_mm := 1 if col[ni - u - w] >= 0 else 0
					var c_pm := 1 if col[ni + u - w] >= 0 else 0
					var c_pp := 1 if col[ni + u + w] >= 0 else 0
					var c_mp := 1 if col[ni - u + w] >= 0 else 0
					var ao := [0 if (s_um and s_vm) else 3 - (s_um + s_vm + c_mm),
						0 if (s_up and s_vm) else 3 - (s_up + s_vm + c_pm),
						0 if (s_up and s_vp) else 3 - (s_up + s_vp + c_pp),
						0 if (s_um and s_vp) else 3 - (s_um + s_vp + c_mp)]
					var nn: Vector3i = _N[d]
					var uu: Vector3i = _U[d]
					var vv: Vector3i = _V[d]
					var nf := Vector3(nn) * 0.5 * VS
					var uf := Vector3(uu) * 0.5 * VS
					var vf := Vector3(vv) * 0.5 * VS
					var cs := [centre + nf - uf - vf, centre + nf + uf - vf, centre + nf + uf + vf, centre + nf - uf + vf]
					for k in 4:
						verts.append(cs[k])
						norms.append(Vector3(nn))
						var cc := colr
						cc.a = _AO[ao[k]]
						cols.append(cc)
					# split along the brighter diagonal (no AO streaks)
					if ao[0] + ao[2] >= ao[1] + ao[3]:
						inds.append_array([nv, nv + 2, nv + 1, nv, nv + 3, nv + 2])
					else:
						inds.append_array([nv, nv + 3, nv + 1, nv + 1, nv + 3, nv + 2])
					nv += 4
	g["verts"] = nv
	if nv == 0:
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = inds
	return arr


# --- implicit shapes -------------------------------------------------------------------

static func _sph(p: Vector3, c: Vector3, r: float) -> float:
	return (p - c).length() - r


static func _ell(p: Vector3, c: Vector3, r: Vector3) -> float:
	var q := (p - c) / r
	var k0 := q.length()
	var k1 := (q / r).length()
	return k0 * (k0 - 1.0) / k1 if k1 > 0.0001 else -minf(r.x, minf(r.y, r.z))


## Tapered capsule from a (radius ra) to b (radius rb).
static func _cone(p: Vector3, a: Vector3, b: Vector3, ra: float, rb: float) -> float:
	var pa := p - a
	var ba := b - a
	var h := clampf(pa.dot(ba) / ba.dot(ba), 0.0, 1.0)
	return (pa - ba * h).length() - lerpf(ra, rb, h)


static func _rbox(p: Vector3, c: Vector3, half: Vector3, r: float) -> float:
	var q := (p - c).abs() - half + Vector3(r, r, r)
	return Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length() + minf(maxf(q.x, maxf(q.y, q.z)), 0.0) - r


static func _smin(a: float, b: float, k: float) -> float:
	var h := clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)


static func _smax(a: float, b: float, k: float) -> float:
	return -_smin(-a, -b, k)


static func _h(x: int, y: int, z: int, s: int) -> float:
	return VoxelArt.hash3(x, y, z, s)


static func _j(c: int, x: int, y: int, z: int, amt: float) -> int:
	return VoxelArt.jitter(c, x, y, z, amt)


static func _mix(a: int, b: int, t: float) -> int:
	return VoxelArt.mix(a, b, clampf(t, 0.0, 1.0))


static func _sc(c: int, f: float) -> int:
	return VoxelArt.scale(c, f)


## Smooth value noise on a coarse lattice (cells of `cell` voxels), 0..1.
static func _vn(x: int, y: int, z: int, cell: int, s: int) -> float:
	var fx := float(x) / cell
	var fy := float(y) / cell
	var fz := float(z) / cell
	var ix := floori(fx)
	var iy := floori(fy)
	var iz := floori(fz)
	var tx := fx - ix
	var ty := fy - iy
	var tz := fz - iz
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	tz = tz * tz * (3.0 - 2.0 * tz)
	var a := lerpf(_h(ix, iy, iz, s), _h(ix + 1, iy, iz, s), tx)
	var b := lerpf(_h(ix, iy + 1, iz, s), _h(ix + 1, iy + 1, iz, s), tx)
	var c := lerpf(_h(ix, iy, iz + 1, s), _h(ix + 1, iy, iz + 1, s), tx)
	var d := lerpf(_h(ix, iy + 1, iz + 1, s), _h(ix + 1, iy + 1, iz + 1, s), tx)
	return lerpf(lerpf(a, b, ty), lerpf(c, d, ty), tz)


## Worn fabric: a base colour with soft blotches and per-voxel grain.
static func _cloth(c: int, x: int, y: int, z: int, wear := 0.06) -> int:
	var blot := (_vn(x, y, z, 4, 11) - 0.5) * 2.0 * wear
	return _j(_sc(c, 1.0 + blot), x, y, z, 0.035)


# --- head ------------------------------------------------------------------------------
# Origin: base of the neck. The head is sculpted in "q" space (p / HS, a
# slightly oversized head) and painted on explicit voxel rows/columns: the
# grid's column 0 is the face's centre line, row R_EYE the eyes.

const HS := 1.15
const HEAD_C := Vector3(0.0, 0.19, 0.012)
const HEAD_R := Vector3(0.086, 0.106, 0.1)
## Exp 012: how much thinner the neck is inside the collar (q space, m).
const NECK_TUCK := 0.017
## Exp 012: the opening the collar and scarf leave around the neck (chest
## space): nothing of the chest is solid inside it above NECK_HOLE_Y, so the
## head's neck turns freely in it. [y0, r0, y1, r1] along the collar's axis.
const NECK_HOLE := [0.38, 0.06, 0.56, 0.054]
const NECK_HOLE_Y := 0.405
## Face rows (voxel y index in head space) and columns (|x index|).
const R_BROW := 13
const R_EYE := 11
const R_NOSE := 8
const R_MOUTH := 6
const C_IRIS := 3


static func _skull(p: Vector3) -> float:
	var d := _ell(p, HEAD_C, HEAD_R)
	# a squarer jaw, the chin, cheekbones, ears
	d = _smin(d, _rbox(p, Vector3(0.0, 0.1, -0.014), Vector3(0.064, 0.05, 0.064), 0.03), 0.035)
	d = _smin(d, _sph(p, Vector3(0.0, 0.062, -0.06), 0.031), 0.02)
	for s in [-1.0, 1.0]:
		d = _smin(d, _sph(p, Vector3(0.048 * s, 0.128, -0.058), 0.027), 0.02)
		d = _smin(d, _ell(p, Vector3(0.087 * s, 0.146, 0.01), Vector3(0.015, 0.03, 0.021)), 0.008)
	# brow ridge, shallow eye sockets
	d = _smin(d, _cone(p, Vector3(-0.05, 0.176, -0.08), Vector3(0.05, 0.176, -0.08), 0.015, 0.015), 0.02)
	for s in [-1.0, 1.0]:
		d = _smax(d, -_sph(p, Vector3(0.04 * s, 0.15, -0.11), 0.016), 0.01)
	# nose: a straight bridge, a rounded tip with a little weight to it
	d = _smin(d, _cone(p, Vector3(0.0, 0.165, -0.09), Vector3(0.0, 0.114, -0.109), 0.009, 0.012), 0.012)
	d = _smin(d, _sph(p, Vector3(0.0, 0.11, -0.104), 0.016), 0.01)
	# neck. Exp 012: below the top of the scarf and collar (q.y ~0.04) it
	# narrows, so the part hidden in the collar stays clear of the scarf
	# roll and the collar when the head turns or bows (it used to fill the
	# opening and poke skin through them at every glance).
	var neck := _cone(p, Vector3(0.0, -0.05, 0.014), Vector3(0.0, 0.1, 0.004), 0.048, 0.045)
	neck += NECK_TUCK * (1.0 - smoothstep(0.012, 0.044, p.y))
	d = _smin(d, neck, 0.03)
	return d


static func _hairline(p: Vector3) -> float:
	# the height above which the scalp is hair, around the head (0 = front)
	var a := absf(atan2(p.x, -(p.z - 0.01)))
	var y := lerpf(0.214, 0.172, smoothstep(0.4, 1.4, a))          # forehead -> temples
	if a > 1.2 and a < 1.85:
		y = maxf(y, 0.172 + 0.012 * sin((a - 1.2) / 0.65 * PI))      # over the ears
	y = lerpf(y, 0.1, smoothstep(1.7, 2.6, a))                       # nape
	return y


static func _hair_d(p: Vector3, x: int, y: int, z: int) -> float:
	var top := smoothstep(0.13, 0.27, p.y)
	var thick := lerpf(0.006, 0.024, top) - 0.006 * smoothstep(0.0, 0.08, p.z)
	var d := _ell(p, HEAD_C + Vector3(0.0, 0.006, 0.004), HEAD_R + Vector3(thick, thick, thick))
	# soft clumps (not curls): a coarse noise on top only
	d -= (_vn(x, y, z, 4, 21) - 0.5) * 0.01 * top
	# a fringe swept to his left over the forehead, volume to the right of the part
	d = _smin(d, _ell(p, Vector3(-0.025, 0.238, -0.082), Vector3(0.065, 0.022, 0.032)), 0.02)
	d = _smin(d, _ell(p, Vector3(0.035, 0.27, -0.045), Vector3(0.045, 0.022, 0.05)), 0.02)
	# a couple of untidy tufts at the crown
	d = _smin(d, _sph(p, Vector3(0.014, 0.302, 0.035), 0.013), 0.012)
	d = _smin(d, _sph(p, Vector3(-0.03, 0.296, 0.06), 0.011), 0.01)
	# a side part on his right, and a ragged fringe (not a bowl cut)
	if p.y > 0.2:
		d = maxf(d, -(absf(p.x - 0.032) - 0.004) if p.z < 0.04 and p.y > 0.26 else d)
	var hl := _hairline(p)
	if p.z < -0.03:
		hl -= 0.016 * float(_h(x / 2, 0, 0, 51) > 0.55) + 0.008 * _h(x, 1, 0, 53)
	d = _smax(d, hl - p.y, 0.006)
	return d


static func _head(p: Vector3, v: Dictionary, x: int, y: int, z: int) -> int:
	var q := p / HS
	var dh := _hair_d(q, x, y, z)
	var ds := _skull(q)
	if ds > 0.0 and dh > 0.0:
		return -1
	if dh <= 0.0 and (ds > -0.004 or q.y > _hairline(q) + 0.012):
		var hair: int = v["hair"]
		var hair_lt: int = v["hair_lt"]
		# combed strands: streaks run front to back on top, downward on the sides
		var s := _h(x, 0, z / 3, 23) if q.y > 0.2 else _h(0, y / 3, z, 23)
		var clump := _vn(x, y, z, 3, 27)
		var c := _mix(hair, hair_lt, 0.4 * smoothstep(0.22, 0.3, q.y) + 0.35 * smoothstep(0.55, 0.8, clump))
		if s < 0.2:
			c = _sc(c, 0.86)
		elif s > 0.85:
			c = _sc(c, 1.08)
		# grey threads at the temples
		var temple := smoothstep(0.06, 0.085, absf(q.x)) * (1.0 - smoothstep(0.19, 0.23, q.y))
		if temple > 0.2 and _h(x, y, z, 29) < float(v["grey"]) * 1.2:
			c = _mix(c, 0x8f8a83, 0.25)
		return _j(c, x, y, z, 0.02)
	return _face(q, v, x, y, z)


static func _face(q: Vector3, v: Dictionary, x: int, y: int, z: int) -> int:
	var c := SKIN
	var ax := absi(x)
	var front := q.z < -0.045
	var hair: int = v["hair"]
	if y < 3 and not (front and y >= 1):
		c = _mix(SKIN, SKIN_DK, 0.2)                                  # neck
	# cold: redder nose tip, cheeks and ears
	if front and ax >= 3 and ax <= 4 and (y == R_NOSE or y == R_NOSE + 1):
		c = _mix(c, SKIN_RED, 0.5)
	if ax <= 1 and (y == R_NOSE or y == R_NOSE + 1) and q.z < -0.1:
		c = _mix(c, SKIN_RED, 0.4)
	if ax >= 6 and y >= 8 and y <= 13 and q.z > -0.03:
		c = _mix(c, SKIN_RED, 0.3)
	if front:
		# eyes: white | iris | white; a darker upper lid; a soft lower lid
		if y == R_EYE and ax >= C_IRIS - 1 and ax <= C_IRIS + 1:
			return IRIS if ax == C_IRIS else EYE_WHITE
		if y == R_EYE + 1 and ax >= C_IRIS - 1 and ax <= C_IRIS + 1:
			c = _mix(c, LASH, 0.42 if ax == C_IRIS else (0.3 if ax > C_IRIS else 0.12))
		if y == R_EYE - 1 and ax >= C_IRIS - 1 and ax <= C_IRIS + 1:
			c = _mix(c, SKIN_DK, 0.35)
		if ax == C_IRIS + 2 and (y == R_EYE or y == R_EYE - 1):
			c = _mix(c, SKIN_DK, 0.4)                                 # crow's feet
		# brows: thick, level, the outer ends dropping a row (kind, a little tired)
		if (y == R_BROW and ax >= 2 and ax <= C_IRIS + 1) or (y == R_BROW - 1 and ax == C_IRIS + 2):
			return _j(_sc(hair, 0.82), x, y, z, 0.05)
		# nostrils and the shadow under the nose
		if y == R_NOSE - 1 and ax == 1 and q.z < -0.085:
			return _mix(SKIN_DK, 0x6a3a2e, 0.45)
		# mouth: a closed line, corners turned up into faint smile creases
		if y == R_MOUTH and ax <= 1:
			return _mix(SKIN_DK, 0x4a2520, 0.55 if ax == 0 else 0.4)
		if y == R_MOUTH + 1 and ax == 2:
			return _mix(SKIN_DK, 0x4a2520, 0.3)                       # corners up: a quiet smile
		if y == R_MOUTH + 1 and ax == 3 and q.z < -0.06:
			c = _mix(c, SKIN_DK, 0.35)
		if y == R_MOUTH - 1 and ax == 0:
			return _mix(SKIN_DK, LIP, 0.3)                            # lower lip
	# beard: jaw, chin and upper lip, sideburns up to the hair
	var beard := int(v["beard"])
	var jaw := y <= R_MOUTH + 1 and y >= 2 and q.z < -0.005 and (ax >= 3 or y <= R_MOUTH - 2 or (y == R_MOUTH - 1 and ax >= 1) or not front)
	var lip := front and y == R_MOUTH + 1 and ax <= 1
	var burn := ax >= 5 and y >= R_MOUTH + 1 and y <= R_EYE and q.z > -0.03 and q.z < 0.0
	if jaw or lip or burn:
		# an even shade (not speckles): stubble, a short beard, or a faint shadow
		var amt: float = [0.48, 0.8, 0.16][beard]
		if y <= 3 and q.z > -0.03:
			amt *= 0.6                                                # thins out under the jaw
		var bc := _mix(_sc(hair, 1.05), 0x8a6a52, 0.15)
		if float(v["grey"]) > 0.3 and _h(x, y, z, 31) < 0.3:
			bc = _mix(bc, 0x9a948c, 0.6)
		return _j(_mix(c, bc, amt + (_h(x, y, z, 37) - 0.5) * 0.18), x, y, z, 0.03)
	return _j(c, x, y, z, 0.02)


# --- chest (jacket, collar, scarf) -----------------------------------------------------
# Origin: the waist (y 1.02 m). Shoulder joints at (+-0.185, 0.405, 0.01).

static func _body(p: Vector3) -> float:
	# ribcage, a narrower waist, sloping shoulders (neck -> shoulder capsules)
	var d := _ell(p, Vector3(0.0, 0.265, 0.0), Vector3(0.158, 0.19, 0.105))
	d = _smin(d, _ell(p, Vector3(0.0, 0.06, 0.005), Vector3(0.138, 0.15, 0.1)), 0.05)
	for s in [-1.0, 1.0]:
		d = _smin(d, _cone(p, Vector3(0.03 * s, 0.405, 0.012), Vector3(0.15 * s, 0.37, 0.012), 0.058, 0.054), 0.06)
	d = _smin(d, _cone(p, Vector3(0.0, 0.37, 0.015), Vector3(0.0, 0.48, 0.012), 0.06, 0.048), 0.05)
	return d


static func _hem(p: Vector3, x: int) -> float:
	# uneven hem: longer at the back, the left front corner hangs a little lower
	var h := -0.045 + (-0.022 * smoothstep(-0.02, 0.09, p.z))
	if p.x < 0.0 and p.z < 0.0:
		h -= 0.012 * smoothstep(0.03, 0.12, -p.x)
	h += (_h(x, 0, 0, 41) - 0.5) * 0.008
	return h


static func _chest(p: Vector3, v: Dictionary, x: int, y: int, z: int) -> int:
	var body := _body(p)
	var jacket := body - 0.016
	# chest pocket flaps stand out by a voxel
	var ax := absf(p.x)
	var flap := ax > 0.035 and ax < 0.115 and p.y > 0.275 and p.y < 0.315 and p.z < -0.05
	if flap:
		jacket -= VS * 0.9
	# the V of the collar opening shows the knit layer, set back
	var vee := p.z < -0.02 and p.y > 0.31 and ax < (p.y - 0.31) * 0.62 + 0.012
	if vee:
		jacket = maxf(jacket, body + 0.002)
	var hem := _hem(p, x)
	if p.y < hem:
		jacket = 1.0
	# corduroy collar standing around the neck
	var collar := _cone(p, Vector3(0.0, 0.41, 0.012), Vector3(0.0, 0.49, 0.022), 0.085, 0.072)
	collar = _smax(collar, -_cone(p, Vector3(0.0, 0.38, 0.012), Vector3(0.0, 0.56, 0.02), 0.06, 0.054), 0.004)
	collar = maxf(collar, -(p.z - (-0.06 + (p.y - 0.41) * 0.6)) if p.y > 0.41 else 1.0)   # open at the front
	# scarf: a knitted roll around the neck, one end down his left chest, a short one behind
	var ry := p.y - 0.468 + p.z * 0.16
	var ring := Vector2(Vector2(p.x, p.z - 0.01).length() - 0.074, ry).length() - 0.03
	var scarf := _smax(ring, absf(ry) - 0.026, 0.006)
	# the ends: a layer draped over the jacket
	var shell := maxf(-jacket - VS * 0.2, jacket - 0.022)
	var tx := -0.062 + (0.44 - p.y) * 0.1
	var tail := maxf(shell, maxf(absf(p.x - tx) - 0.03, absf(p.y - 0.325) - 0.125))
	if p.z > 0.0:
		tail = 1.0
	var back_tail := maxf(shell, maxf(absf(p.x - 0.05 - (0.44 - p.y) * 0.05) - 0.028, absf(p.y - 0.39) - 0.06))
	if p.z < 0.0:
		back_tail = 1.0
	var knit := body - 0.005
	if p.y < 0.3 or p.y > 0.5:
		knit = 1.0
	# Exp 012: the neck opening is empty above the collar's base (it used to
	# hold a clothed neck stump that the head's skin neck cut through).
	if p.y > NECK_HOLE_Y:
		var u := clampf((p.y - float(NECK_HOLE[0])) / (float(NECK_HOLE[2]) - float(NECK_HOLE[0])), 0.0, 1.0)
		var hole_r := lerpf(float(NECK_HOLE[1]), float(NECK_HOLE[3]), u)
		if Vector2(p.x, p.z - lerpf(0.012, 0.02, u)).length() < hole_r:
			jacket = 1.0
			knit = 1.0
	# a carpenter's pencil standing in the right chest pocket (graphite end up)
	if _rbox(p, Vector3(0.06, 0.328, -0.114), Vector3(0.008, 0.028, 0.012), 0.0) <= 0.0:
		return 0x3a3a3a if p.y > 0.342 else PENCIL
	# order: scarf > collar > jacket > knit
	if scarf <= 0.0 or tail <= 0.0 or back_tail <= 0.0:
		var sc: int = v["scarf"]
		var sd: int = v["scarf_dk"]
		var row := posmod(y, 2) == 0 if scarf <= 0.0 else posmod(x + (1 if p.z < 0 else 0), 2) == 0
		var c := sc if row else _mix(sc, sd, 0.6)
		if tail <= 0.0 and scarf > 0.0 and p.y < 0.24:
			if posmod(x, 2) == 1:
				return -1                                             # fringe
			c = _sc(c, 0.9)
		if back_tail <= 0.0 and scarf > 0.0 and p.y < 0.35 and posmod(x, 2) == 0:
			return -1
		return _j(c, x, y, z, 0.05)
	if collar <= 0.0:
		var cc: int = v["collar"]
		return _j(cc if posmod(x + z, 2) == 0 else _sc(cc, 0.8), x, y, z, 0.03)
	if jacket <= 0.0:
		return _jacket_paint(p, v, x, y, z, flap, hem)
	if knit <= 0.0:
		var k: int = v["knit"]
		return _j(k if posmod(x, 2) == 0 else _sc(k, 0.84), x, y, z, 0.03)
	return -1


static func _jacket_paint(p: Vector3, v: Dictionary, x: int, y: int, z: int, flap: bool, hem: float) -> int:
	var jc: int = v["jacket"]
	var jd: int = v["jacket_dk"]
	var jl: int = v["jacket_lt"]
	var ax := absf(p.x)
	var c := _cloth(jc, x, y, z, 0.07)
	# faded, worn panels: chest front and shoulder tops lighter
	if p.y > 0.36:
		c = _mix(c, jl, 0.25)
	# hem band and its stitch line
	if p.y < hem + 0.024:
		c = _cloth(jd, x, y, z, 0.05)
		if absf(p.y - (hem + 0.024)) < VS * 0.6 and posmod(x + z, 2) == 0:
			c = _sc(jd, 0.75)
	# front zipper (brass teeth on a dark tape), up to the collar V
	if p.z < -0.05 and ax < VS * 0.6 and p.y < 0.32:
		return _mix(BRASS, jd, 0.3) if posmod(y, 2) == 0 else _sc(jd, 0.7)
	if p.z < -0.05 and absf(ax - VS) < VS * 0.6 and p.y < 0.32:
		c = _sc(jd, 0.9)                                              # placket
	# chest pockets: flap with a dark edge and a button, the pocket below
	if p.z < -0.04 and ax > 0.035 and ax < 0.115:
		if flap:
			var bottom := p.y < 0.275 + VS
			c = _sc(jd, 0.82) if bottom else _cloth(jd, x, y, z, 0.04)
			if absf(ax - 0.075) < VS * 0.6 and absf(p.y - 0.285) < VS * 0.6:
				return BRASS
		elif p.y > 0.185 and p.y < 0.275:
			if absf(ax - 0.035) < VS * 0.6 or absf(ax - 0.115) < VS * 0.6 or absf(p.y - 0.19) < VS * 0.6:
				c = _sc(c, 0.82)                                      # pocket seams
	# hand-warmer pockets: slanted openings
	if p.z < -0.04 and ax > 0.05 and ax < 0.14 and p.y > 0.02 and p.y < 0.16:
		var slant := (ax - 0.05) * 1.3 + 0.03
		if absf(p.y - slant) < VS * 0.6:
			c = _sc(jd, 0.55)
		elif absf(p.y - slant - VS) < VS * 0.6:
			c = _sc(c, 1.1)
	# side seams, yoke seam across the back, shoulder seams
	if absf(ax - 0.165) < VS * 0.6 and p.y < 0.3 and absf(p.z) < 0.03:
		c = _sc(c, 0.82)
	if p.z > 0.06 and absf(p.y - 0.355) < VS * 0.6:
		c = _sc(c, 0.8)
	if p.y > 0.42 and absf(p.z - 0.012) < VS * 0.6 and ax > 0.08:
		c = _sc(c, 0.85)
	# a repair patch, low on the back, left
	if p.z > 0.06 and p.x < -0.03 and p.x > -0.11 and p.y > 0.06 and p.y < 0.13:
		var edge := p.x < -0.104 or p.x > -0.036 or p.y < 0.066 or p.y > 0.124
		c = _sc(PATCH, 0.8) if edge and posmod(x + y, 2) == 0 else _cloth(PATCH, x, y, z, 0.05)
	return c


# --- pelvis (belt, trousers seat, pouch, glove) ----------------------------------------
# Origin y 0.95 m; hip joints at (+-0.092, -0.035, 0).

static func _pelvis(p: Vector3, v: Dictionary, x: int, y: int, z: int) -> int:
	var hips := _ell(p, Vector3(0.0, -0.035, 0.006), Vector3(0.142, 0.1, 0.104))
	hips = _smin(hips, _rbox(p, Vector3(0.0, 0.03, 0.004), Vector3(0.13, 0.06, 0.098), 0.05), 0.03)
	hips = maxf(hips, p.y - 0.09)
	var belt := _rbox(p, Vector3(0.0, 0.012, 0.004), Vector3(0.143, 0.016, 0.11), 0.05)
	# tool pouch on his right hip, tape measure on the left, glove from the back pocket
	var pouch := _rbox(p, Vector3(0.15, -0.045, -0.01), Vector3(0.022, 0.06, 0.05), 0.012)
	var tool := _cone(p, Vector3(0.15, 0.02, -0.04), Vector3(0.15, 0.1, -0.05), 0.011, 0.011)
	var tape := _rbox(p, Vector3(-0.15, -0.01, 0.0), Vector3(0.018, 0.035, 0.035), 0.012)
	var glove := _rbox(p, Vector3(0.088, -0.075, 0.118), Vector3(0.022, 0.05, 0.01), 0.006)
	if glove <= 0.0 and p.y < -0.1 and posmod(x, 2) == 1:
		glove = 1.0                                                   # fingers
	if tool <= 0.0:
		return _j(0x8a6438 if p.y > 0.07 else 0x5a5d62, x, y, z, 0.04)   # hammer handle / head
	if pouch <= 0.0:
		var c := _cloth(LEATHER, x, y, z, 0.06)
		if p.y > -0.005:
			c = _sc(LEATHER, 0.8)                                     # flap
		if absf(p.y + 0.005) < VS * 0.6 and absf(p.z + 0.01) < VS * 0.6:
			return BUCKLE
		return c
	if tape <= 0.0:
		return _j(TAPE if absf(p.z) > 0.012 or p.y < 0.0 else 0x2a2a2a, x, y, z, 0.04)
	if glove <= 0.0:
		return _cloth(GLOVE, x, y, z, 0.06)
	if belt <= 0.0:
		if p.z < -0.08 and absf(p.x) < 0.022:
			return BUCKLE if absf(p.x) > VS * 0.6 or absf(p.y - 0.012) > VS * 0.6 else 0x2a2a2a
		# belt loops
		if posmod(int(round(atan2(p.x, -p.z) / 0.55)), 2) == 0 and absf(atan2(p.x, -p.z) - round(atan2(p.x, -p.z) / 0.55) * 0.55) < 0.06:
			return _cloth(v["legs"], x, y, z, 0.05)
		return _j(BELT, x, y, z, 0.06)
	if hips <= 0.0:
		var c := _cloth(v["legs"], x, y, z, 0.06)
		# fly seam, back pockets, a crease under the belt
		if p.z < -0.08 and absf(p.x + 0.012) < VS * 0.6 and p.y < 0.0:
			c = _sc(c, 0.78)
		if p.z > 0.06 and absf(p.x) > 0.03 and absf(p.x) < 0.12 and p.y < -0.01 and p.y > -0.1:
			if absf(absf(p.x) - 0.03) < VS * 0.6 or absf(absf(p.x) - 0.12) < VS * 0.6 or absf(p.y + 0.1) < VS * 0.7 or absf(p.y + 0.01) < VS * 0.6:
				c = _sc(c, 0.78)
		return c
	return -1


# --- arms -------------------------------------------------------------------------------

static func _uarm(p: Vector3, side: float, v: Dictionary, x: int, y: int, z: int) -> int:
	var d := _sph(p, Vector3(0.006 * side, -0.006, 0.004), 0.058)
	d = _smin(d, _cone(p, Vector3(0.0, -0.02, 0.0), Vector3(0.0, -0.275, 0.004), 0.054, 0.045), 0.03)
	if d > 0.0:
		return -1
	var c := _cloth(v["jacket"], x, y, z, 0.07)
	# set-in sleeve seam over the shoulder, folds at the inner elbow
	if absf(p.y + 0.035 - absf(p.x) * 0.3) < VS * 0.6 and p.y > -0.06:
		c = _sc(c, 0.8)
	if p.z < -0.03 and p.y < -0.2 and absf(p.y + 0.235 + p.x * side * 0.2) < VS * 0.6:
		c = _sc(c, 0.8)
	if p.y < -0.22 and p.z > 0.02 and side < 0.0:
		c = _cloth(PATCH, x, y, z, 0.05)                              # elbow patch (left)
	return c


static func _farm(p: Vector3, side: float, v: Dictionary, x: int, y: int, z: int) -> int:
	var d := _sph(p, Vector3(0.0, 0.0, 0.004), 0.045)
	d = _smin(d, _cone(p, Vector3(0.0, 0.0, 0.0), Vector3(0.0, -0.2, -0.002), 0.045, 0.042), 0.02)
	var rolled := side > 0.0
	var cuff_top := -0.15 if rolled else -0.19
	var cuff := _cone(p, Vector3(0.0, cuff_top, 0.0), Vector3(0.0, cuff_top - (0.03 if rolled else 0.04), 0.0), 0.05 if rolled else 0.047, 0.048 if rolled else 0.046)
	var under := _cone(p, Vector3(0.0, cuff_top - 0.02, 0.0), Vector3(0.0, -0.245, 0.0), 0.038, 0.034)
	var wrist := _cone(p, Vector3(0.0, -0.22, 0.0), Vector3(0.0, -0.27, 0.0), 0.029, 0.027)
	if p.y < cuff_top - 0.04 + (0.0 if rolled else 0.0):
		d = 1.0
	if d > 0.0 and cuff > 0.0 and under > 0.0 and wrist > 0.0:
		return -1
	if d <= 0.0 and cuff > 0.0:
		var c := _cloth(v["jacket"], x, y, z, 0.07)
		if p.y > -0.06 and p.z > 0.02 and side < 0.0:
			c = _cloth(PATCH, x, y, z, 0.05)
		if p.z < -0.02 and p.y > -0.05 and absf(p.y + 0.02 - p.x * side * 0.25) < VS * 0.6:
			c = _sc(c, 0.8)
		return c
	if cuff <= 0.0:
		if rolled:
			var l: int = v["lining"]
			return _j(l if posmod(y + int(round(atan2(p.x, p.z) * 2.0)), 2) == 0 else _sc(l, 0.88), x, y, z, 0.03)
		return _cloth(v["jacket_dk"], x, y, z, 0.05)
	if under <= 0.0:
		var k: int = v["knit"]
		return _j(k if posmod(x + z, 2) == 0 else _sc(k, 0.85), x, y, z, 0.03)
	return _j(SKIN, x, y, z, 0.03)


## A hand (wrist at the origin, fingers along -Y, thumb forward -Z, palm
## facing the body: -X for the right hand). `fist`: curled around a grip.
static func _hand(p: Vector3, side: float, fist: bool, x: int, y: int, z: int) -> int:
	var q := Vector3(p.x * side, p.y, p.z)        # mirrored: +qx is the back of the hand (outside)
	var palm := _rbox(q, Vector3(0.002, -0.05, -0.004), Vector3(0.014, 0.042, 0.036), 0.012)
	var d := palm
	var crease := false
	var finger := false
	if fist:
		# curled fingers wrap to the palm side; a knuckle ridge on top
		var f := _rbox(q, Vector3(-0.01, -0.1, -0.004), Vector3(0.022, 0.02, 0.036), 0.014)
		d = _smin(d, f, 0.012)
		d = _smin(d, _cone(q, Vector3(0.006, -0.088, -0.036), Vector3(0.006, -0.088, 0.03), 0.016, 0.014), 0.008)
		d = _smin(d, _cone(q, Vector3(-0.004, -0.03, -0.04), Vector3(-0.03, -0.072, -0.052), 0.013, 0.011), 0.01)   # thumb
		crease = q.y < -0.08 and absf(fposmod(q.z + 0.1, 0.018) - 0.009) < 0.0035 and q.x < 0.0
	else:
		# relaxed: four fingers on their own voxel columns (index longest at the front),
		# gently curled toward the palm; the thumb apart from them
		var lens := [0.158, 0.166, 0.158, 0.142]
		for k in 4:
			var fz := -0.03 + k * VS
			var tip: float = -float(lens[k])
			d = minf(d, _cone(q, Vector3(0.0, -0.08, fz), Vector3(-0.018, tip + 0.008, fz), 0.0085, 0.0075))
		d = _smin(d, _cone(q, Vector3(-0.004, -0.03, -0.036), Vector3(-0.016, -0.09, -0.06), 0.012, 0.0085), 0.008)   # thumb
		finger = q.y < -0.085 and q.z > -0.038
		crease = finger and posmod(z, 2) == 1
	d = _smin(d, _cone(q, Vector3(0.0, 0.03, 0.0), Vector3(0.0, -0.01, -0.002), 0.027, 0.03), 0.01)   # wrist
	if d > 0.0:
		return -1
	var c := SKIN
	if crease:
		c = _mix(SKIN, SKIN_DK, 0.45)
	# knuckles: redder, a ridge on the back of the hand
	if absf(q.y + 0.088) < VS * 0.7 and q.x > 0.0:
		c = _mix(c, SKIN_RED, 0.6)
	if q.y < -0.15 and not fist:
		c = _mix(c, 0xe0b5a0, 0.4)                                    # fingertips / nails
	return _j(c, x, y, z, 0.03)


# --- legs -------------------------------------------------------------------------------

static func _thigh(p: Vector3, side: float, v: Dictionary, x: int, y: int, z: int) -> int:
	var q := Vector3(p.x * side, p.y, p.z)        # +qx = outside of the leg
	var d := _sph(q, Vector3(0.004, 0.0, 0.004), 0.08)
	d = _smin(d, _cone(q, Vector3(0.0, 0.0, 0.0), Vector3(0.0, -0.405, -0.004), 0.08, 0.058), 0.03)
	d = _smin(d, _ell(q, Vector3(0.006, -0.15, -0.012), Vector3(0.072, 0.15, 0.074)), 0.03)
	# cargo pocket on the right thigh
	var cargo := side > 0.0 and q.x > 0.02 and q.y < -0.12 and q.y > -0.27 and absf(q.z + 0.005) < 0.048
	if cargo:
		d -= VS * 0.9
	if d > 0.0:
		return -1
	var legs: int = v["legs"]
	var c := _cloth(legs, x, y, z, 0.07)
	# outer seam, wrinkles at the hip and behind the knee
	if absf(q.z) < VS * 0.6 and q.x > 0.04:
		c = _sc(c, 0.8)
	if q.z > 0.04 and (absf(q.y + 0.36) < VS * 0.6 or absf(q.y + 0.31 - q.x * 0.3) < VS * 0.6):
		c = _sc(c, 0.78)
	if q.z < -0.03 and absf(q.y + 0.05 + q.x * 0.4) < VS * 0.6 and q.x < 0.03:
		c = _sc(c, 0.82)
	if cargo:
		var edge := q.y > -0.14 or q.y < -0.265 or absf(q.z + 0.005) > 0.042
		if q.y > -0.15:
			c = _sc(legs, 0.85)                                       # flap
		elif edge:
			c = _sc(legs, 0.75)
		if absf(q.y + 0.14) < VS * 0.6 and absf(q.z + 0.005) < VS * 0.6:
			return 0x2a2a2a
	# worn knee fronts
	if q.z < -0.03 and q.y < -0.3:
		c = _mix(c, 0x6c7680, 0.12)
	return c


static func _shin(p: Vector3, side: float, v: Dictionary, x: int, y: int, z: int) -> int:
	var q := Vector3(p.x * side, p.y, p.z)
	var d := _sph(q, Vector3(0.0, -0.004, -0.004), 0.05)
	d = _smin(d, _cone(q, Vector3(0.0, -0.01, 0.0), Vector3(0.0, -0.28, 0.004), 0.052, 0.053), 0.02)
	# trouser hem bunched over the boot
	d = _smin(d, _cone(q, Vector3(0.0, -0.27, 0.004), Vector3(0.0, -0.3, 0.008), 0.056, 0.059), 0.01)
	if q.y < -0.305:
		d = 1.0
	var boot := _cone(q, Vector3(0.0, -0.29, 0.004), Vector3(0.0, -0.42, 0.006), 0.05, 0.048)
	if d > 0.0 and boot > 0.0:
		return -1
	if d <= 0.0:
		var legs: int = v["legs"]
		var c := _cloth(legs, x, y, z, 0.07)
		if absf(q.z) < VS * 0.6 and q.x > 0.035:
			c = _sc(c, 0.8)
		# knee: double-knee patch on the left, wear on both
		if q.z < -0.02 and q.y > -0.1:
			c = _mix(c, 0x6c7680, 0.12)
			if side < 0.0 and q.y > -0.085 and q.y < 0.04 and absf(q.x) < 0.04:
				var edge := absf(absf(q.x) - 0.04) < VS * 0.6 or absf(q.y + 0.085) < VS * 0.6 or absf(q.y - 0.04) < VS * 0.6
				c = _sc(legs, 0.7) if edge and posmod(x + y, 2) == 0 else _cloth(_sc(legs, 1.15), x, y, z, 0.05)
		if q.y < -0.27:
			c = _sc(c, 0.85 if posmod(y, 2) == 0 else 0.95)          # bunched hem
		return c
	# boot shaft: padded collar, laces up the front with hooks
	var c := _cloth(BOOT, x, y, z, 0.06)
	if q.y > -0.315:
		c = _sc(BOOT_DK, 0.9)
	elif q.z < -0.03:
		if absf(q.x) < VS * 0.6:
			c = _sc(BOOT_DK, 1.1)                                     # tongue
		elif absf(q.x) < 0.03:
			c = LACE if posmod(y, 2) == 0 else _sc(BOOT_DK, 1.1)
		elif posmod(y, 2) == 0 and absf(q.x) < 0.045:
			c = 0x9e9a90                                              # hooks
	return c


static func _foot(p: Vector3, side: float, x: int, y: int, z: int) -> int:
	var q := Vector3(p.x * side, p.y, p.z)
	# heel + ankle, a forefoot that slopes down to a rounded toe cap
	var d := _sph(q, Vector3(0.0, 0.0, 0.004), 0.05)
	d = _smin(d, _rbox(q, Vector3(0.0, -0.035, 0.03), Vector3(0.047, 0.042, 0.045), 0.02), 0.02)
	var top := lerpf(-0.01, -0.045, smoothstep(-0.02, -0.17, q.z))
	var fore := _rbox(q, Vector3(0.004, (top - 0.075) * 0.5, -0.09), Vector3(0.05, (top + 0.075) * 0.5, 0.095), 0.025)
	d = _smin(d, fore, 0.03)
	var sole := _rbox(q, Vector3(0.002, -0.083, -0.055), Vector3(0.056, 0.012, 0.135), 0.008)
	if q.z > -0.06 and q.z < -0.0 and q.y < -0.088:
		sole = 1.0                                                     # arch gap between heel and tread
	if d > 0.0 and sole > 0.0:
		return -1
	if sole <= 0.0 and q.y < -0.074:
		if absf(q.y + 0.074) < VS * 0.6 + 0.001 and q.y > -0.078:
			return _mix(SOLE, LACE, 0.45) if posmod(x + z, 2) == 0 else _sc(SOLE, 1.3)  # welt stitching
		return _j(SOLE if posmod(z, 2) == 0 or q.y > -0.088 else _sc(SOLE, 0.75), x, y, z, 0.04)
	var c := _cloth(BOOT, x, y, z, 0.07)
	if q.z < -0.115:
		c = _cloth(BOOT_DK, x, y, z, 0.05)                            # toe cap
		if absf(q.z + 0.115) < VS * 0.6:
			c = _sc(BOOT_DK, 0.8)
	elif q.y > top - 0.016 and q.z < -0.01 and q.z > -0.11:
		# laces over the tongue
		if absf(q.x) < 0.024:
			c = LACE if posmod(z, 2) == 0 else _sc(BOOT_DK, 1.05)
	if q.z > 0.06 and q.y > -0.05:
		c = _sc(BOOT_DK, 0.95)                                        # heel counter
	return c


# --- the handgun (gun space: barrel along -Y, grip down +Z) -----------------------------

static func _pistol(p: Vector3, x: int, y: int, z: int) -> int:
	var slide := _rbox(p, Vector3(0.0, -0.168, -0.012), Vector3(0.012, 0.092, 0.012), 0.003)
	var frame := _rbox(p, Vector3(0.0, -0.15, 0.01), Vector3(0.011, 0.075, 0.01), 0.003)
	var grip_c := Vector3(0.0, -0.075 + (p.z - 0.02) * 0.25, 0.062)
	var grip := _rbox(p, grip_c, Vector3(0.013, 0.022, 0.045), 0.006)
	var guard := _rbox(p, Vector3(0.0, -0.125, 0.04), Vector3(0.006, 0.03, 0.018), 0.004)
	guard = _smax(guard, -_rbox(p, Vector3(0.0, -0.125, 0.038), Vector3(0.01, 0.019, 0.011), 0.002), 0.001)
	var sight := _rbox(p, Vector3(0.0, -0.25, -0.027), Vector3(0.003, 0.004, 0.005), 0.0)
	if slide > 0.0 and frame > 0.0 and grip > 0.0 and guard > 0.0 and sight > 0.0:
		return -1
	if grip <= 0.0 and slide > 0.0:
		return 0x1d1d1f if posmod(y + z, 2) == 0 else 0x2a2a2d
	if slide <= 0.0:
		if p.y > -0.11 and posmod(y, 2) == 0 and p.z < -0.012:
			return _sc(METAL, 0.75)                                    # serrations
		return METAL
	return METAL_DK
