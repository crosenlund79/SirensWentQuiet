class_name VoxelSupport
extends RefCounted
## Refinement 01 (S): what a structural change left without support, on a
## VoxelGrid (pure data, no nodes).
##
## A voxel is supported if a 6-connected chain of solid voxels joins it to
## the ground: any voxel in the rows up to `ground_row` (the floor slab,
## foundations, paving, sole plates and the first wall row, which stands on
## the floor or the yard) or undug basement EARTH. Everything else hangs in
## the air and should fall.
##
## Run once per change, over the change's box: every solid voxel in the box
## above the ground starts a depth-first search that tries "down" first, so a
## standing wall finds the floor in a few steps, and stops as soon as it
## reaches the ground or a voxel already known to be grounded. Only a piece
## that really floats is explored completely. Pieces larger than `cap`
## voxels count as grounded (a bound on the cost; the house is one connected
## body through its walls and floor slab, so real fragments are small).
## Unlike VoxelCarver.remove_floating (a crumb cleanup with a 400-voxel cap
## and no notion of the ground) this drops whole wall bands, lintels, sills
## and window assemblies that lost what held them.
##
## Furniture voxels (materials from VoxelMat.WOOD up: a damaged piece's
## voxels, HouseFurniture) count as air here: they keep their own
## break-off lifecycle (some pieces' voxel models have parts above thin
## legs), and they don't hold up walls.

const CAP := 25000


## Cell indices of the unsupported solid voxels reachable from the solid
## voxels in [lo, hi) (clamped to the grid). F_HARD voxels (the foundation,
## earth) are never returned.
static func unsupported(g: VoxelGrid, lo: Vector3i, hi: Vector3i, ground_row := VoxelHouse.BASE_ROW, cap := CAP) -> PackedInt32Array:
	var out := PackedInt32Array()
	lo = lo.clamp(Vector3i(1, ground_row + 1, 1), Vector3i(g.sx - 1, g.sy - 1, g.sz - 1))
	hi = hi.clamp(Vector3i(1, ground_row + 1, 1), Vector3i(g.sx - 1, g.sy - 1, g.sz - 1))
	if hi.x <= lo.x or hi.y <= lo.y or hi.z <= lo.z:
		return out
	var sxz := g.sx * g.sz
	var n_total := g.mat.size()
	var ground_hi := (ground_row + 1) * sxz          # indices below this are ground rows
	var mat := g.mat
	var flags := VoxelMat.FLAGS
	var furniture := VoxelMat.WOOD
	# pushed in this order, popped in reverse: down first, then sideways, up last
	var deltas := PackedInt32Array([sxz, g.sx, -g.sx, 1, -1, -sxz])
	var known := {}                                  # index -> true (grounded) / false (falls)
	for y in range(lo.y, hi.y):
		for z in range(lo.z, hi.z):
			var base := (y * g.sz + z) * g.sx
			for x in range(lo.x, hi.x):
				var s := base + x
				if mat[s] == 0 or mat[s] >= furniture or known.has(s):
					continue
				var seen := {s: true}
				var stack := PackedInt32Array([s])
				var grounded := false
				while not stack.is_empty():
					var i := stack[stack.size() - 1]
					stack.resize(stack.size() - 1)
					for d in deltas:
						var j := i + d
						if j < 0 or j >= n_total or mat[j] == 0 or mat[j] >= furniture or seen.has(j):
							continue
						if j < ground_hi or mat[j] == VoxelMat.EARTH or known.get(j, false):
							grounded = true
							break
						if known.has(j):
							continue                     # part of a piece already found to fall
						seen[j] = true
						stack.append(j)
					if grounded or seen.size() > cap:
						grounded = true
						break
				for i in seen:
					known[i] = grounded
				if not grounded:
					for i in seen:
						if (flags[mat[i]] & VoxelMat.F_HARD) == 0:
							out.append(i)
	return out
