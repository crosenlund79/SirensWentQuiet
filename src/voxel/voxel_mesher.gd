class_name VoxelMesher
extends RefCounted
## Face-culled voxel mesher with baked per-vertex ambient occlusion.
##
## Builds triangle arrays for a box region of a VoxelGrid. Every exposed voxel
## face becomes one quad with its own colour (so per-voxel colour patterns,
## paint and cut faces survive). COLOR.a carries the AO term (the shader feeds
## it to AO, so it only darkens ambient light, plus a little direct light).
## UV carries flags: x = emissive, y = glossy + 2 * (painted / finished face).
##
## Directions: 0 +X, 1 -X, 2 +Y, 3 -Y, 4 +Z, 5 -Z (bit d of pmask paints face d).

const AO_CURVE := [0.38, 0.6, 0.8, 1.0]
const NORMALS := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
## Tangents u, v per direction with u x v = normal.
const TAN_U := [Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0)]
const TAN_V := [Vector3i(0, 0, 1), Vector3i(0, 1, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 1, 0), Vector3i(1, 0, 0)]
const NORMAL_I := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]


static func _delta(g: VoxelGrid, v: Vector3i) -> int:
	return v.x + v.z * g.sx + v.y * g.sx * g.sz


## Corner offsets (in cells, from the voxel min corner) for the 4 quad corners
## (-u-v, +u-v, +u+v, -u+v) of each direction.
static func _corners() -> Array:
	var out := []
	for d in 6:
		var n := Vector3(NORMAL_I[d])
		var u := Vector3(TAN_U[d])
		var v := Vector3(TAN_V[d])
		var c := Vector3(0.5, 0.5, 0.5) + n * 0.5
		out.append([c - (u + v) * 0.5, c + (u - v) * 0.5, c + (u + v) * 0.5, c + (v - u) * 0.5])
	return out


static var _CORNERS := _corners()


## Mesh arrays (Mesh.ARRAY_MAX sized) for cells in [lo, hi), or [] if empty.
## glass = false: opaque voxels; true: glass voxels only (no AO).
## `offset` is subtracted from vertex positions (model pivots).
static func build_arrays(g: VoxelGrid, lo: Vector3i, hi: Vector3i, glass := false, offset := Vector3.ZERO) -> Array:
	lo = lo.clamp(Vector3i.ONE, Vector3i(g.sx - 1, g.sy - 1, g.sz - 1))
	hi = hi.clamp(Vector3i.ONE, Vector3i(g.sx - 1, g.sy - 1, g.sz - 1))
	var mat := g.mat
	var col := g.col
	var pcol := g.pcol
	var pmask := g.pmask
	var occl := VoxelMat.OCCLUDES
	var flags := VoxelMat.FLAGS
	var st := VoxelMat.STRUCT
	var sx := g.sx
	var sxz := g.sx * g.sz
	var vs := g.vs
	var cap_row := g.cap_row
	var cap_col := Color.hex((g.cap_color << 8) | 0xff)
	var ao_curve := PackedFloat32Array(AO_CURVE)
	var dn := PackedInt32Array()
	var du := PackedInt32Array()
	var dv := PackedInt32Array()
	var corners := []
	for d in 6:
		dn.append(_delta(g, NORMAL_I[d]))
		du.append(_delta(g, TAN_U[d]))
		dv.append(_delta(g, TAN_V[d]))
		var cs := PackedVector3Array()
		for k in 4:
			cs.append(_CORNERS[d][k] * vs)
		corners.append(cs)
	var normals := PackedVector3Array(NORMALS)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var inds := PackedInt32Array()
	var org := g.origin - offset
	var glass_flag := VoxelMat.F_GLASS
	var nverts := 0
	for y in range(lo.y, hi.y):
		for z in range(lo.z, hi.z):
			var row := (y * g.sz + z) * sx
			for x in range(lo.x, hi.x):
				var i := row + x
				var m := mat[i]
				if m == 0:
					continue
				var fl := flags[m]
				var is_glass := (fl & glass_flag) != 0
				if is_glass != glass:
					continue
				var base := org + Vector3(x, y, z) * vs
				var pm := pmask[i]
				var uv := Vector2(1.0 if (fl & VoxelMat.F_EMISSIVE) != 0 else 0.0, 1.0 if (fl & VoxelMat.F_GLOSSY) != 0 else 0.0)
				for d in 6:
					var ni := i + dn[d]
					var nm := mat[ni]
					if is_glass:
						if nm != 0:
							continue
					elif occl[nm] == 1:
						continue
					var c: Color
					var fuv := uv
					if d == 2 and y == cap_row and st[m] == 1:
						c = cap_col
						fuv.y += 2.0
					elif (pm >> d) & 1:
						c = Color.hex((pcol[i] << 8) | 0xff)
						fuv.y += 2.0
					else:
						c = Color.hex((col[i] << 8) | 0xff)
					var cs: PackedVector3Array = corners[d]
					var nrm := normals[d]
					if is_glass:
						for k in 4:
							verts.append(base + cs[k])
							norms.append(nrm)
							cols.append(c)
							uvs.append(fuv)
						inds.append(nverts)
						inds.append(nverts + 2)
						inds.append(nverts + 1)
						inds.append(nverts)
						inds.append(nverts + 3)
						inds.append(nverts + 2)
						nverts += 4
						continue
					var a := ni
					var u := du[d]
					var v := dv[d]
					var s_um := occl[mat[a - u]]
					var s_up := occl[mat[a + u]]
					var s_vm := occl[mat[a - v]]
					var s_vp := occl[mat[a + v]]
					var c_mm := occl[mat[a - u - v]]
					var c_pm := occl[mat[a + u - v]]
					var c_pp := occl[mat[a + u + v]]
					var c_mp := occl[mat[a - u + v]]
					var ao0 := 0 if (s_um and s_vm) else 3 - (s_um + s_vm + c_mm)
					var ao1 := 0 if (s_up and s_vm) else 3 - (s_up + s_vm + c_pm)
					var ao2 := 0 if (s_up and s_vp) else 3 - (s_up + s_vp + c_pp)
					var ao3 := 0 if (s_um and s_vp) else 3 - (s_um + s_vp + c_mp)
					verts.append(base + cs[0])
					verts.append(base + cs[1])
					verts.append(base + cs[2])
					verts.append(base + cs[3])
					norms.append(nrm)
					norms.append(nrm)
					norms.append(nrm)
					norms.append(nrm)
					cols.append(Color(c.r, c.g, c.b, ao_curve[ao0]))
					cols.append(Color(c.r, c.g, c.b, ao_curve[ao1]))
					cols.append(Color(c.r, c.g, c.b, ao_curve[ao2]))
					cols.append(Color(c.r, c.g, c.b, ao_curve[ao3]))
					uvs.append(fuv)
					uvs.append(fuv)
					uvs.append(fuv)
					uvs.append(fuv)
					# Split along the diagonal that keeps AO gradients smooth.
					inds.append(nverts)
					if ao0 + ao2 >= ao1 + ao3:
						inds.append(nverts + 2)
						inds.append(nverts + 1)
						inds.append(nverts)
						inds.append(nverts + 3)
						inds.append(nverts + 2)
					else:
						inds.append(nverts + 3)
						inds.append(nverts + 1)
						inds.append(nverts + 1)
						inds.append(nverts + 3)
						inds.append(nverts + 2)
					nverts += 4
	if nverts == 0:
		return []
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = inds
	return arrays


## Triangle soup (for ConcavePolygonShape3D.set_faces) of the boundary of the
## structural voxels in [lo, hi) restricted to rows [row_lo, row_hi].
static func collision_faces(g: VoxelGrid, lo: Vector3i, hi: Vector3i, row_lo: int, row_hi: int) -> PackedVector3Array:
	lo = lo.clamp(Vector3i.ONE, Vector3i(g.sx - 1, g.sy - 1, g.sz - 1))
	hi = hi.clamp(Vector3i.ONE, Vector3i(g.sx - 1, g.sy - 1, g.sz - 1))
	var out := PackedVector3Array()
	var mat := g.mat
	var st := VoxelMat.STRUCT
	var sx := g.sx
	var vs := g.vs
	var dn := PackedInt32Array()
	var corners := []
	for d in 6:
		dn.append(_delta(g, NORMAL_I[d]))
		var cs := PackedVector3Array()
		for k in 4:
			cs.append(_CORNERS[d][k] * vs)
		corners.append(cs)
	for y in range(maxi(lo.y, row_lo), mini(hi.y, row_hi + 1)):
		for z in range(lo.z, hi.z):
			var row := (y * g.sz + z) * sx
			for x in range(lo.x, hi.x):
				var i := row + x
				if st[mat[i]] == 0:
					continue
				var base := g.origin + Vector3(x, y, z) * vs
				for d in 6:
					if st[mat[i + dn[d]]] == 1:
						continue
					var cs: PackedVector3Array = corners[d]
					var p0 := base + cs[0]
					var p2 := base + cs[2]
					out.append(p0)
					out.append(p2)
					out.append(base + cs[1])
					out.append(p0)
					out.append(base + cs[3])
					out.append(p2)
	return out


## Convenience: a whole small grid as an ArrayMesh (characters, props, models).
static func build_mesh(g: VoxelGrid, material: Material, offset := Vector3.ZERO, glass_material: Material = null) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var lo := Vector3i.ONE
	var hi := Vector3i(g.sx - 1, g.sy - 1, g.sz - 1)
	var a := build_arrays(g, lo, hi, false, offset)
	if not a.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	if glass_material != null:
		var b := build_arrays(g, lo, hi, true, offset)
		if not b.is_empty():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b)
			mesh.surface_set_material(mesh.get_surface_count() - 1, glass_material)
	return mesh
