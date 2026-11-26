class_name HumanoidSculpt
extends RefCounted
## Experiment 011: the voxel people (Eli's technique for everyone).
##
## A LOOK (a Dictionary, made by an archetype, see humanoid_looks.gd) is
##   key     unique cache key, e.g. "psycho/3/1"
##   body    HumanoidBody parameters (proportions)
##   outfit  clothing components (below)
##   face    {"skin", "iris", "eyes", "brows", "mouth", "circles", "pallor", "grime", "lines"}
##   hair    {"style", "col", "col2", "grey", "beard", "beard_col"}
## and becomes 15 part meshes (head, chest, pelvis, uarm/farm/hand/thigh/shin/foot
## _l/_r) at 1.5 cm voxels: implicit sculpture (EliSculpt's SDF helpers),
## painted voxel by voxel, shaded and meshed by EliSculpt's mesher. Parts are
## built in parallel on the WorkerThreadPool; only the voxels near the
## surface are evaluated (3-voxel blocks are culled by their centre's SDF),
## and only the visible ones are painted. Meshes are cached per look key in a
## bounded LRU (CACHE_MAX looks); enemies with the same look share them.
##
## OUTFIT (every field optional; colours are 0xRRGGBB ints):
##   top    {"type": tshirt|shirt|blouse|sport, "col", "col2", "sleeve" 0..1
##           (share of the arm covered), "rolled" bool, "tie" colour, "tucked" bool, "print" colour}
##   mid    {"type": sweater|hoodie|fleece|cardigan|coverall, "col", "col2", "sleeve", "rolled", "hood": "down"|"up"}
##   outer  {"type": coat|parka|work_jacket, "col", "col2", "sleeve", "open" bool, "fur" colour}
##   over   {"type": hivis|apron, "col", "col2"}
##   legs   {"type": jeans|trousers|cargo|sweatpants|skirt|leggings|coverall, "col", "col2" (tights / stripe), "belt" colour}
##   feet   [left, right]: {"type": sneakers|shoes|boots|slippers|sock, "col", "col2", "sole"}
##   hat    {"type": cap|beanie|headband|hood, "col", "col2", "back" bool}
##   acc    Array of: glasses, glasses_cracked, lanyard, watch_l, watch_r, glove_l, glove_r,
##          bandage_l, bandage_r, bandage_head, rag, name_tag
##   dirt   0..1 grime and mud; tears 0..1 holes and frayed hems
## Layers stack in the order top < mid < outer < over: each is a shell over
## the body (its thickness adds to the ones under it), with its own sleeve
## length, hem, front opening, collar and painted details.

const E := preload("res://src/character/eli_sculpt.gd")
const VS := 0.015
const PARTS := ["head", "chest", "pelvis", "uarm_l", "uarm_r", "farm_l", "farm_r", "hand_l", "hand_r",
	"thigh_l", "thigh_r", "shin_l", "shin_r", "foot_l", "foot_r"]
const CACHE_MAX := 24
const UNPAINTED := 0x1000000
const BLOCK := 4
const SLAB := 8                  ## rows per parallel job (a multiple of BLOCK)
const SUB_MARGIN := 0.034        ## half 2-voxel sub-block diagonal + slack
const BLOCK_MARGIN := 0.066      ## half 4-voxel block diagonal (0.052) + smooth-union slack

## Shell thickness each layer adds over the ones under it (m, at k = 1).
const INCR := {"tshirt": 0.006, "shirt": 0.007, "blouse": 0.007, "sport": 0.009, "sweater": 0.01,
	"hoodie": 0.012, "fleece": 0.011, "cardigan": 0.009, "coverall": 0.011, "coat": 0.013, "parka": 0.017,
	"work_jacket": 0.014, "hivis": 0.007, "apron": 0.006}
## Hem height (chest space, m at k = 1); "long" layers continue as a skirt on the pelvis.
const HEM := {"tshirt": -0.13, "shirt": -0.14, "blouse": -0.1, "sport": -0.1, "sweater": -0.11, "hoodie": -0.13,
	"fleece": -0.12, "cardigan": -0.16, "coverall": -1.0, "coat": -1.0, "parka": -1.0, "work_jacket": -0.1,
	"hivis": -0.07, "apron": -1.0}
const TY := ["tshirt", "shirt", "blouse", "sport", "sweater", "hoodie", "fleece", "cardigan", "coverall",
	"coat", "parka", "work_jacket", "hivis", "apron"]
enum { TSHIRT, SHIRT, BLOUSE, SPORT, SWEATER, HOODIE, FLEECE, CARDIGAN, COVERALL, COAT, PARKA, WORK_JACKET, HIVIS, APRON }
const SKIRT := {"coat": 0.41, "parka": 0.27, "apron": 0.36, "skirt": 0.37}
const LEG_T := {"jeans": 0.008, "trousers": 0.011, "cargo": 0.012, "sweatpants": 0.017, "skirt": 0.002,
	"leggings": 0.004, "coverall": 0.012}

static var _cache := {}             ## look key -> {part: ArrayMesh}
static var _lru: Array[String] = []
static var stats := {}              ## look key -> {"verts": int, "ms": float, "parts": {part: verts}}

# --- the look, unpacked (one sculptor per look; read-only while building) ---------------
var look: Dictionary
var k := 1.0
var T := 1.0
var HS := 1.15
var sex := 0.0
var weight := 0.3
var age := 0.4
var waist_y := 0.07
var neck_p := Vector3.ZERO
var shoulder := Vector3.ZERO
var hip := Vector3.ZERO
var thigh_len := 0.4
var shin_len := 0.4
var upper_arm := 0.28
var forearm := 0.25
var chest_c := Vector3.ZERO
var chest_r := Vector3.ONE
var abd_c := Vector3.ZERO
var abd_r := Vector3.ONE
var belly := 0.0
var bust := 0.0
var hump := 0.0
var sh_r := 0.056
var neck_r := 0.047
var neck_len := 1.0
var hips_c := Vector3.ZERO
var hips_r := Vector3.ONE
var arm_r0 := 0.05
var arm_r1 := 0.045
var farm_r0 := 0.044
var farm_r1 := 0.034
var wrist_r := 0.027
var thigh_r0 := 0.08
var thigh_r1 := 0.056
var knee_r := 0.047
var calf_r := 0.05
var ankle_r := 0.03
var hand_s := 1.0
var foot_s := 1.0
# head shape (q space = head space / HS)
var hw := 1.0
var hh := 1.0
var hd := 1.0
var jaw := 1.0
var chin := 0.5
var cheeks := 0.5
var nose := 1.0
var nose_w := 1.0
var brow := 1.0
var ears := 1.0
var eye_x := 0.04
var r_eye := 11
var r_brow := 13
var r_nose := 8
var r_mouth := 6
var c_iris := 3
# outfit
var layers: Array = []              ## torso layers, inner to outer, each with "t" (absolute)
# the same, as typed arrays for the hot loops (index = layer)
var l_ty := PackedInt32Array()
var l_t := PackedFloat32Array()
var l_hem := PackedFloat32Array()
var l_sleeve := PackedFloat32Array()
var l_open := PackedByteArray()
var l_rolled := PackedByteArray()
var l_top := PackedByteArray()
var legs: Dictionary = {}
var leg_t := 0.01
var feet: Array = [{}, {}]
var hat: Dictionary = {}
var acc: Dictionary = {}            ## accessory -> true
var dirt := 0.2
var tears := 0.1
var face: Dictionary = {}
var hair: Dictionary = {}
var skin := 0xc89a80
var skin_dk := 0xa47a62
var skin_red := 0xc9826c
var hair_style := "short"
var hair_col := 0x3a2a20
var hair_col2 := 0x5a4030
var beard := ""
var max_t := 0.0
var hood_up := false
var hat_low := 1.0                  ## hair above this (q space) is pressed under the hat
var claw := 0.5
var torn_l := false
var torn_r := false
var watch_any := false
var bandage_any := false


func _init(l: Dictionary) -> void:
	look = l
	var b := HumanoidBody.derive(l.get("body", {}))
	k = b["k"]; T = b["T"]; HS = b["HS"]; sex = b["sex"]; weight = b["weight"]; age = b["age"]
	waist_y = (b["waist"] as Vector3).y
	neck_p = b["neck"]; shoulder = b["shoulder"]; hip = b["hip"]
	thigh_len = b["thigh"]; shin_len = b["shin"]; upper_arm = b["upper_arm"]; forearm = b["forearm"]
	chest_c = b["chest_c"]; chest_r = b["chest_r"]; abd_c = b["abd_c"]; abd_r = b["abd_r"]
	belly = b["belly"]; bust = b["bust"]; hump = b["hump"]
	sh_r = b["sh_r"]; neck_r = b["neck_r"]; neck_len = b["neck_len"]; hips_c = b["hips_c"]; hips_r = b["hips_r"]
	arm_r0 = b["arm_r0"]; arm_r1 = b["arm_r1"]; farm_r0 = b["farm_r0"]; farm_r1 = b["farm_r1"]; wrist_r = b["wrist_r"]
	thigh_r0 = b["thigh_r0"]; thigh_r1 = b["thigh_r1"]; knee_r = b["knee_r"]; calf_r = b["calf_r"]; ankle_r = b["ankle_r"]
	hand_s = b["hand"]; foot_s = b["foot"]
	hw = b["head_w"]; hh = b["head_h"]; hd = b["head_d"]; jaw = b["jaw"]; chin = b["chin"]; cheeks = b["cheeks"]
	nose = b["nose"]; nose_w = b["nose_w"]; brow = b["brow"]; ears = b["ears"]
	eye_x = 0.04 * hw * float(b["eyes"])
	r_eye = roundi(0.1435 * hh * HS / VS)
	r_brow = r_eye + 2
	r_nose = roundi(0.1045 * hh * HS / VS)
	r_mouth = roundi(0.0783 * hh * HS / VS)
	c_iris = maxi(roundi(eye_x * HS / VS), 2)
	var o: Dictionary = l.get("outfit", {})
	var t := 0.0
	for slot in ["top", "mid", "outer", "over"]:
		if typeof(o.get(slot)) != TYPE_DICTIONARY:
			continue
		var g: Dictionary = (o[slot] as Dictionary).duplicate()
		var ty := str(g.get("type", "tshirt"))
		if not INCR.has(ty):
			continue
		g["type"] = ty
		g["slot"] = slot
		t += float(INCR[ty]) * k
		g["t"] = t
		var hem: float = float(HEM[ty]) * k
		if ty == "shirt" and bool(g.get("tucked", false)):
			hem = -0.06 * k
		g["hem"] = hem
		g["sleeve"] = float(g.get("sleeve", 0.0 if ty in ["hivis", "apron"] else 1.0))
		g["col"] = int(g.get("col", 0x808080))
		g["col2"] = int(g.get("col2", VoxelArt.scale(int(g["col"]), 0.75)))
		g["i"] = layers.size()
		layers.append(g)
		l_ty.append(TY.find(ty))
		l_t.append(t)
		l_hem.append(hem)
		l_sleeve.append(float(g["sleeve"]))
		var op_default := ty in ["coat", "cardigan", "hivis"]
		l_open.append(1 if bool(g.get("open", op_default)) else 0)
		l_rolled.append(1 if bool(g.get("rolled", false)) else 0)
		l_top.append(1 if slot == "top" else 0)
		if ty in ["hoodie", "parka"] and str(g.get("hood", "")) == "up":
			hood_up = true
	max_t = t
	legs = (o.get("legs", {"type": "trousers", "col": 0x3a3c40}) as Dictionary).duplicate()
	legs["type"] = str(legs.get("type", "trousers"))
	if not LEG_T.has(legs["type"]):
		legs["type"] = "trousers"
	for g in layers:
		if g["type"] == "coverall":
			legs = {"type": "coverall", "col": g["col"], "col2": g["col2"]}
	leg_t = float(LEG_T[legs["type"]]) * k
	legs["col"] = int(legs.get("col", 0x3a3c40))
	var fs: Variant = o.get("feet", [])
	for i in 2:
		var f: Dictionary = {"type": "shoes", "col": 0x2a2624}
		if fs is Array and (fs as Array).size() > i and typeof(fs[i]) == TYPE_DICTIONARY:
			f = (fs[i] as Dictionary).duplicate()
		elif typeof(fs) == TYPE_DICTIONARY:
			f = (fs as Dictionary).duplicate()
		f["type"] = str(f.get("type", "shoes"))
		f["col"] = int(f.get("col", 0x2a2624))
		feet[i] = f
	hat = (o.get("hat", {}) as Dictionary).duplicate() if typeof(o.get("hat")) == TYPE_DICTIONARY else {}
	if hood_up:
		hat = {"type": "hood"}
		for g in layers:
			if str(g.get("hood", "")) == "up":
				hat["col"] = g["col"]
				hat["col2"] = g["col2"]
				hat["fur"] = int(g.get("fur", -1))
	match str(hat.get("type", "")):
		"hood":
			hat_low = -1.0
		"beanie":
			hat_low = 0.15
		"cap":
			hat_low = 0.19
	for a in o.get("acc", []):
		acc[str(a)] = true
	torn_l = acc.has("torn_l")
	torn_r = acc.has("torn_r")
	watch_any = acc.has("watch_l") or acc.has("watch_r")
	bandage_any = acc.has("bandage_l") or acc.has("bandage_r")
	dirt = float(o.get("dirt", 0.2))
	tears = float(o.get("tears", 0.1))
	face = l.get("face", {})
	skin = int(face.get("skin", 0xc89a80))
	var pallor := float(face.get("pallor", 0.2))
	skin = VoxelArt.mix(skin, 0xa09c88, pallor * 0.3)
	skin_dk = VoxelArt.mix(VoxelArt.scale(skin, 0.8), 0x6a3a3a, 0.08)
	skin_red = VoxelArt.mix(skin, 0xb05a4a, 0.28)
	hair = l.get("hair", {})
	hair_style = str(hair.get("style", "short"))
	hair_col = int(hair.get("col", 0x3a2a20))
	hair_col2 = int(hair.get("col2", VoxelArt.scale(hair_col, 1.3)))
	beard = str(hair.get("beard", ""))
	claw = float((l.get("style", {}) as Dictionary).get("claw", 0.5))


# --- cache and building ------------------------------------------------------------------

## The 15 part meshes of `l` ({part: ArrayMesh}), built once and cached.
static func meshes(l: Dictionary, material: Material) -> Dictionary:
	var key := str(l.get("key", ""))
	if key != "" and _cache.has(key):
		_lru.erase(key)
		_lru.append(key)
		return _cache[key]
	var t0 := Time.get_ticks_usec()
	var s := HumanoidSculpt.new(l)
	# 1. grids, 2. shape per y slab, 3. paint per slab, 4. shade + mesh per part
	var grids := []
	var slabs := []
	for pi in PARTS.size():
		var g := s.new_grid(PARTS[pi])
		grids.append(g)
		var n: Vector3i = g["n"]
		var y := 1
		while y < n.y - 1:
			var y1 := mini(y + SLAB, n.y - 1)
			slabs.append({"g": pi, "y0": y, "y1": y1, "out": null})
			y = y1
	# one sculptor (with its own copy of the look) per slab: threads share no
	# Arrays or Dictionaries (their reference counts would serialize them)
	for sl in slabs:
		sl["s"] = HumanoidSculpt.new(l.duplicate(true))
		sl["grid"] = grids[int(sl["g"])].duplicate()
	_run(_shape_job.bind(slabs), slabs.size())
	for g in grids:
		g["shape"] = _join(g, slabs, grids.find(g), "out")
	for sl in slabs:
		sl["grid"] = grids[int(sl["g"])].duplicate()
	_run(_paint_job.bind(slabs), slabs.size())
	for gi in grids.size():
		grids[gi]["col"] = _join(grids[gi], slabs, gi, "out")
	_run(_mesh_job.bind(grids), grids.size())
	var out := {}
	var verts := 0
	var pv := {}
	for gi in grids.size():
		var g: Dictionary = grids[gi]
		out[PARTS[gi]] = E.arrays_to_mesh(g["arr"], material)
		verts += int(g["verts"])
		pv[PARTS[gi]] = g["verts"]
	if key != "":
		_cache[key] = out
		_lru.append(key)
		while _lru.size() > CACHE_MAX:
			_cache.erase(_lru.pop_front())
		stats[key] = {"verts": verts, "ms": float(Time.get_ticks_usec() - t0) / 1000.0, "parts": pv}
	return out


static func _run(c: Callable, n: int) -> void:
	var task := WorkerThreadPool.add_group_task(c, n, -1, true, "humanoid")
	WorkerThreadPool.wait_for_group_task_completion(task)


## The part's full cell array from its slabs (rows y0..y1 are contiguous).
static func _join(g: Dictionary, slabs: Array, gi: int, field: String) -> PackedInt32Array:
	var n: Vector3i = g["n"]
	var row := n.x * n.z
	var a := PackedInt32Array()
	a.resize(row)
	a.fill(-1)
	var y_end := 1
	for sl in slabs:
		if int(sl["g"]) != gi:
			continue
		a.append_array(sl[field])
		y_end = int(sl["y1"])
	var tail := PackedInt32Array()
	tail.resize((n.y - y_end) * row)
	tail.fill(-1)
	a.append_array(tail)
	return a


static func _mesh_job(i: int, grids: Array) -> void:
	var g: Dictionary = grids[i]
	E._shade(g)
	g["arr"] = E.grid_arrays(g)


static func _shape_job(i: int, slabs: Array) -> void:
	var sl: Dictionary = slabs[i]
	var sc: HumanoidSculpt = sl["s"]
	sl["out"] = sc.shape_rows(sl["grid"], int(sl["y0"]), int(sl["y1"]))


static func _paint_job(i: int, slabs: Array) -> void:
	var sl: Dictionary = slabs[i]
	var sc: HumanoidSculpt = sl["s"]
	sl["out"] = sc.paint_rows(sl["grid"], int(sl["y0"]), int(sl["y1"]))


static func is_cached(key: String) -> bool:
	return _cache.has(key)


static func clear_cache() -> void:
	_cache.clear()
	_lru.clear()


## Part space bounds [lo, hi] (generous: empty space is skipped cheaply).
func bounds(base: String) -> Array:
	var m := max_t + 0.03
	match base:
		"head":
			var top := 0.3 * hh * HS + 0.06
			return [Vector3(-0.15 * hw * HS - 0.04, -0.16 if hair_style in ["long"] else -0.09, -0.2 * HS),
				Vector3(0.15 * hw * HS + 0.04, top, 0.17 * HS + 0.04)]
		"chest":
			var wx := maxf(shoulder.x + arm_r0, chest_r.x) + m + 0.02
			var dz := maxf(chest_r.z, abd_r.z) + 0.06 * k * belly + m + 0.06
			return [Vector3(-wx, -0.17 * k, -dz - 0.03), Vector3(wx, neck_p.y + 0.1 * k, dz + 0.04)]
		"pelvis":
			var low := -0.12 * k
			for g in layers:
				if SKIRT.has(g["type"]):
					low = minf(low, -float(SKIRT[g["type"]]) * k - 0.03)
			if legs["type"] == "skirt":
				low = minf(low, -float(SKIRT["skirt"]) * k - 0.03)
			var wx := hips_r.x * 1.35 + m + 0.03
			return [Vector3(-wx, low, -hips_r.z * 1.5 - m - 0.03), Vector3(wx, 0.14 * k, hips_r.z * 1.5 + m + 0.03)]
		"uarm":
			var r := arm_r0 + m + 0.02
			return [Vector3(-r, -upper_arm - 0.03, -r), Vector3(r, 0.08 * k, r)]
		"farm":
			var r := farm_r0 + m + 0.02
			return [Vector3(-r, -forearm - 0.03, -r), Vector3(r, 0.06 * k, r)]
		"hand":
			return [Vector3(-0.06, -0.2, -0.1) * hand_s, Vector3(0.06, 0.035, 0.06) * hand_s]
		"thigh":
			var r := thigh_r0 + leg_t + 0.03
			return [Vector3(-r, -thigh_len - 0.04, -r), Vector3(r, 0.08 * k, r)]
		"shin":
			var r := knee_r + 0.05
			return [Vector3(-r, -shin_len - 0.02, -r - 0.01), Vector3(r, 0.07 * k, r)]
		"foot":
			return [Vector3(-0.08, -0.115, -0.25) * foot_s, Vector3(0.08, 0.07, 0.11) * foot_s]
	return [Vector3(-0.1, -0.1, -0.1), Vector3(0.1, 0.1, 0.1)]


## An empty grid for one part: {"part", "base", "side", "n", "i0"}.
func new_grid(part: String) -> Dictionary:
	var base := part
	var side := 0.0
	if part.ends_with("_l"):
		base = part.trim_suffix("_l")
		side = -1.0
	elif part.ends_with("_r"):
		base = part.trim_suffix("_r")
		side = 1.0
	var b := bounds(base)
	var lo: Vector3 = b[0]
	var hi: Vector3 = b[1]
	var i0 := Vector3i(floori(lo.x / VS) - 1, floori(lo.y / VS) - 1, floori(lo.z / VS) - 1)
	var i1 := Vector3i(ceili(hi.x / VS) + 1, ceili(hi.y / VS) + 1, ceili(hi.z / VS) + 1)
	# block aligned rows (slabs are multiples of BLOCK)
	return {"part": part, "base": base, "side": side, "n": i1 - i0 + Vector3i.ONE, "i0": i0, "verts": 0}


## Voxelizes one part on one thread (tests, tools): EliSculpt's grid format.
func build_grid(part: String) -> Dictionary:
	var g := new_grid(part)
	var n: Vector3i = g["n"]
	var slabs := []
	var y := 1
	while y < n.y - 1:
		var y1 := mini(y + SLAB, n.y - 1)
		slabs.append({"g": 0, "y0": y, "y1": y1, "out": shape_rows(g, y, y1)})
		y = y1
	g["shape"] = _join(g, slabs, 0, "out")
	for sl in slabs:
		sl["out"] = paint_rows(g, int(sl["y0"]), int(sl["y1"]))
	g["col"] = _join(g, slabs, 0, "out")
	return g


## Shape of rows y0 .. y1 - 1 (UNPAINTED = filled, -1 = empty). Blocks far
## from the surface are skipped (outside) or filled (inside) from their
## centre's distance.
func shape_rows(g: Dictionary, y0: int, y1: int) -> PackedInt32Array:
	var n: Vector3i = g["n"]
	var i0: Vector3i = g["i0"]
	var base: String = g["base"]
	var side: float = g["side"]
	var col := PackedInt32Array()
	col.resize((y1 - y0) * n.z * n.x)
	col.fill(-1)
	for by in range(y0, y1, BLOCK):
		for bz in range(1, n.z - 1, BLOCK):
			for bx in range(1, n.x - 1, BLOCK):
				var ex := mini(bx + BLOCK, n.x - 1)
				var ey := mini(by + BLOCK, y1)
				var ez := mini(bz + BLOCK, n.z - 1)
				var pc := (Vector3(i0) + Vector3(bx + ex - 1, by + ey - 1, bz + ez - 1) * 0.5) * VS
				var dc := eval(base, side, pc, i0.x + (bx + ex) / 2, i0.y + (by + ey) / 2, i0.z + (bz + ez) / 2, false)
				if dc > BLOCK_MARGIN:
					continue
				if dc < -BLOCK_MARGIN:
					_fill(col, n, y0, bx, ex, by, ey, bz, ez)
					continue
				# 2^3 sub-blocks
				for sy in range(by, ey, 2):
					for sz in range(bz, ez, 2):
						for sx in range(bx, ex, 2):
							var fx := mini(sx + 2, ex)
							var fy := mini(sy + 2, ey)
							var fz := mini(sz + 2, ez)
							var ps := (Vector3(i0) + Vector3(sx + fx - 1, sy + fy - 1, sz + fz - 1) * 0.5) * VS
							var ds := eval(base, side, ps, i0.x + sx, i0.y + sy, i0.z + sz, false)
							if ds > SUB_MARGIN:
								continue
							if ds < -SUB_MARGIN:
								_fill(col, n, y0, sx, fx, sy, fy, sz, fz)
								continue
							for y in range(sy, fy):
								for z in range(sz, fz):
									for x in range(sx, fx):
										var ix := i0.x + x
										var iy := i0.y + y
										var iz := i0.z + z
										if eval(base, side, Vector3(ix, iy, iz) * VS, ix, iy, iz, false) <= 0.0:
											col[((y - y0) * n.z + z) * n.x + x] = UNPAINTED
	return col


static func _fill(col: PackedInt32Array, n: Vector3i, y0: int, x0: int, x1: int, ya: int, yb: int, z0: int, z1: int) -> void:
	for y in range(ya, yb):
		for z in range(z0, z1):
			var r := ((y - y0) * n.z + z) * n.x
			for x in range(x0, x1):
				col[r + x] = UNPAINTED


## Colours of rows y0 .. y1 - 1: only the filled voxels with an open face
## are painted (the others keep UNPAINTED; nothing ever shows them).
func paint_rows(g: Dictionary, y0: int, y1: int) -> PackedInt32Array:
	var n: Vector3i = g["n"]
	var i0: Vector3i = g["i0"]
	var base: String = g["base"]
	var side: float = g["side"]
	var col: PackedInt32Array = g["shape"]
	var sx := n.x
	var sxz := n.x * n.z
	var out := col.slice(y0 * sxz, y1 * sxz)
	for y in range(y0, y1):
		for z in range(1, n.z - 1):
			for x in range(1, n.x - 1):
				var i := (y * n.z + z) * n.x + x
				if col[i] < 0:
					continue
				if col[i - 1] >= 0 and col[i + 1] >= 0 and col[i - sx] >= 0 and col[i + sx] >= 0 \
						and col[i - sxz] >= 0 and col[i + sxz] >= 0:
					continue
				var ix := i0.x + x
				var iy := i0.y + y
				var iz := i0.z + z
				out[i - y0 * sxz] = int(eval(base, side, Vector3(ix, iy, iz) * VS, ix, iy, iz, true))
	return out


## paint false: the signed distance of the part's outer surface at p (<= 0
## inside). paint true (p inside): the colour there (0xRRGGBB as a float).
func eval(base: String, side: float, p: Vector3, x: int, y: int, z: int, paint: bool) -> float:
	match base:
		"head": return _head(p, x, y, z, paint)
		"chest": return _chest(p, x, y, z, paint)
		"pelvis": return _pelvis(p, x, y, z, paint)
		"uarm": return _arm(p, side, false, x, y, z, paint)
		"farm": return _arm(p, side, true, x, y, z, paint)
		"hand": return _hand(p, side, x, y, z, paint)
		"thigh": return _thigh(p, side, x, y, z, paint)
		"shin": return _shin(p, side, x, y, z, paint)
		"foot": return _foot(p, side, x, y, z, paint)
	return 1.0


# --- helpers ------------------------------------------------------------------------------

static func _h(x: int, y: int, z: int, s: int) -> float:
	return VoxelArt.hash3(x, y, z, s)


static func _j(c: int, x: int, y: int, z: int, amt: float) -> int:
	return VoxelArt.jitter(c, x, y, z, amt)


static func _mix(a: int, b: int, t: float) -> int:
	return VoxelArt.mix(a, b, clampf(t, 0.0, 1.0))


static func _sc(c: int, f: float) -> int:
	return VoxelArt.scale(c, f)


## Worn fabric with grime: a base colour, soft blotches, grain, and dirt
## that gathers low on the body (`low` 0 .. 1 where mud splashes).
func _cloth(c: int, x: int, y: int, z: int, wear := 0.06, low := 0.0) -> int:
	var blot := (E._vn(x, y, z, 4, 11) - 0.5) * 2.0 * wear
	var cc := _sc(c, 1.0 + blot)
	if dirt > 0.0:
		var g := E._vn(x + 40, y, z, 5, 61)
		var amt := smoothstep(0.62 - 0.22 * dirt - 0.18 * low, 0.95, g) * (0.35 + 0.4 * dirt)
		if amt > 0.0:
			cc = _mix(cc, 0x3b3226 if low > 0.4 else 0x4a4236, amt)
	return _j(cc, x, y, z, 0.035)


## A ragged hole in a layer (it shows the layer below).
func _torn(x: int, y: int, z: int, salt: int) -> bool:
	if tears <= 0.0:
		return false
	return E._vn(x, y, z, 3, 71 + salt) > 1.0 - tears * 0.16 and _h(x, y, z, 73) > 0.25


# --- torso ---------------------------------------------------------------------------------

func _torso_skin(p: Vector3) -> float:
	var d := E._ell(p, chest_c, chest_r)
	d = E._smin(d, E._ell(p, abd_c, abd_r), 0.05 * k)
	for s: float in [-1.0, 1.0]:
		d = E._smin(d, E._cone(p, Vector3(0.03 * s * k, shoulder.y + 0.02 * T, shoulder.z), Vector3((shoulder.x - 0.022 * k) * s, shoulder.y - 0.025 * T, shoulder.z), sh_r * 0.95, sh_r * 0.86), 0.06 * k)
	d = E._smin(d, E._cone(p, Vector3(0.0, shoulder.y - 0.015 * T, 0.015 * k), Vector3(0.0, neck_p.y + 0.03 * k, neck_p.z + 0.008 * k), neck_r * 1.28, neck_r * 1.02), 0.05 * k)
	if belly > 0.02:
		d = E._smin(d, E._ell(p, Vector3(0.0, 0.075 * T, -0.03 * k - 0.025 * k * belly), Vector3(0.125 * k * (0.9 + 0.2 * belly), 0.12 * T, (0.06 + 0.05 * belly) * k)), 0.05 * k)
	if bust > 0.05:
		for s: float in [-1.0, 1.0]:
			d = E._smin(d, E._sph(p, Vector3(0.058 * s * k, 0.27 * T, -0.07 * k - 0.012 * k * weight), 0.05 * k * minf(bust, 1.3)), 0.045 * k)
	if hump > 0.05:
		d = E._smin(d, E._sph(p, Vector3(0.0, 0.36 * T, 0.05 * k), 0.085 * k * hump), 0.06 * k)
	return d


## Front opening half width of layer i at chest height y (0 = closed).
func _open_i(i: int, y: float) -> float:
	if l_open[i] == 0:
		return 0.0
	match l_ty[i]:
		COAT:
			return (0.018 + 0.07 * smoothstep(0.12 * T, 0.4 * T, y)) * k
		CARDIGAN:
			return (0.012 + 0.05 * smoothstep(0.1 * T, 0.42 * T, y)) * k
		WORK_JACKET, PARKA, SPORT:
			return (0.02 + 0.03 * smoothstep(0.2 * T, 0.4 * T, y)) * k
		HIVIS:
			return 0.012 * k
	return 0.0


func _opening(g: Dictionary, y: float) -> float:
	return _open_i(int(g["i"]), y)


## The neckline of layer i: it covers the neck base only below this (chest
## space). The cut is local to the neck (shoulders stay covered) and opens
## lower and wider at the front for crew, scoop and V necks.
func _neck_i(i: int, p: Vector3) -> float:
	var base := 0.0
	var v := 0.0
	match l_ty[i]:
		TSHIRT, SWEATER, SPORT:
			base = 0.03
			v = 0.03
		BLOUSE:
			base = 0.025
			v = 0.045
		HOODIE:
			base = 0.028
			v = 0.02
		SHIRT, COVERALL, WORK_JACKET, FLEECE, PARKA:
			base = 0.012
		COAT, CARDIGAN:
			base = 0.01
		HIVIS:
			base = 0.03
			v = 0.1
		APRON:
			return 0.33 * T
	var front := clampf((neck_p.z - p.z) / (0.06 * k), 0.0, 1.0)
	var r := Vector2(p.x, (p.z - neck_p.z) * (1.0 - 0.6 * front)).length()
	var near := 1.0 - smoothstep(neck_r * 1.15, neck_r * 1.15 + 0.035 * k, r)
	return lerpf(neck_p.y + 0.06 * k, neck_p.y - (base + v * front) * k, near)


func _neckline(g: Dictionary, p: Vector3) -> float:
	return _neck_i(int(g["i"]), p)


## Whether layer i covers torso point p (chest space), before its shell test.
func _cover_i(i: int, p: Vector3, x: int, z: int) -> bool:
	var hem := l_hem[i]
	if p.y < hem - 0.016:
		return false
	if p.y < hem + 0.016 and p.y < hem + _fray_i(x, z, i):
		return false
	if p.y > neck_p.y - 0.13 * k and p.y > _neck_i(i, p):
		return false
	var ty := l_ty[i]
	if ty == APRON:
		return p.z < 0.012 * k and absf(p.x) < (0.15 * k + 0.02 * k * weight)
	if l_open[i] != 0 and p.z < 0.0:
		var op := _open_i(i, p.y)
		if absf(p.x) < op:
			return false
	if ty == HIVIS and _arm_hole(p):
		return false
	return true


func _fray_i(x: int, z: int, i: int) -> float:
	return (_h(x, 0, z, 41 + int(l_t[i] * 997.0)) - 0.5) * 0.012 * (0.5 + tears * 2.0)


func _fray(x: int, z: int, g: Dictionary) -> float:
	return _fray_i(x, z, int(g["i"]))


func _arm_hole(p: Vector3) -> bool:
	return absf(p.x) > shoulder.x - 0.035 * k and p.y > shoulder.y - 0.12 * T


## Puffy quilting of a parka (extra thickness).
func _puff_i(i: int, h: float) -> float:
	if l_ty[i] != PARKA:
		return 0.0
	return 0.006 * k * (0.5 + 0.5 * cos(TAU * h / (0.075 * k)))


func _puff(g: Dictionary, h: float) -> float:
	return _puff_i(int(g["i"]), h)


func _chest(p: Vector3, x: int, y: int, z: int, paint: bool) -> float:
	var skin_d := _torso_skin(p)
	var d := skin_d
	var nl := l_ty.size()
	var gds := PackedFloat32Array()
	if paint:
		gds.resize(nl)
		gds.fill(1.0)
	for i in nl:
		if not _cover_i(i, p, x, z):
			continue
		var gd := skin_d - l_t[i] - _puff_i(i, p.y) - _raised_i(i, p)
		if not paint and d <= 0.0:
			d = minf(d, gd)                                    # filled anyway: holes can't matter
			continue
		if gd <= 0.004 and l_top[i] == 0 and _torn(x, y, z, int(l_t[i] * 1000.0)):
			continue
		if paint:
			gds[i] = gd
		d = minf(d, gd)
	# collars, hoods, ties, badges: separate shapes over the layers
	var xd := _extras_chest(p, skin_d)
	d = minf(d, xd[0])
	if not paint:
		return d
	if xd[0] <= 0.0:
		return float(int(xd[1]) if int(xd[1]) >= 0 else _paint_extra_chest(int(-int(xd[1])), p, x, y, z))
	for i in range(nl - 1, -1, -1):
		if gds[i] <= 0.0:
			return float(_paint_layer(layers[i], p, x, y, z, "chest"))
	return float(_skin_paint(x, y, z))


## Raised details on layer i's shell (pocket flaps, the kangaroo pocket,
## lapels, a storm flap): extra thickness at p.
func _raised_i(i: int, p: Vector3) -> float:
	var ax := absf(p.x)
	match l_ty[i]:
		HOODIE:
			if p.z < -0.02 * k and ax < 0.1 * k and p.y > 0.0 and p.y < 0.13 * T:
				return VS * 0.9
		COAT:
			if p.z < 0.0 and p.y > 0.15 * T:
				var op := _open_i(i, p.y)
				if ax > op and ax < op + 0.035 * k:
					return VS * 0.9                               # lapels
		WORK_JACKET, COVERALL:
			if p.z < -0.04 * k and ax > 0.035 * k and ax < 0.11 * k and p.y > 0.275 * T and p.y < 0.315 * T:
				return VS * 0.9                                   # pocket flaps
		PARKA:
			if p.z < 0.0 and ax < 0.02 * k:
				return VS * 0.8                                   # storm flap
	return 0.0


func _skin_paint(x: int, y: int, z: int) -> int:
	return _j(skin, x, y, z, 0.03)


## [distance, colour] of the extra shapes on the chest (colour < 0: -id for _paint_extra_chest).
func _extras_chest(p: Vector3, skin_d: float) -> Array:
	var best := 1.0
	var c := 0
	var ax := absf(p.x)
	var near_neck := p.y > neck_p.y - 0.1 * k and ax < neck_r * 2.2 + max_t + 0.03 and absf(p.z - neck_p.z) < 0.17 * k
	var front_mid := p.z < 0.0 and ax < 0.05 * k
	if not near_neck and not front_mid:
		return [best, c]
	for gi in layers.size():
		var g: Dictionary = layers[gi]
		var ty: String = g["type"]
		var t: float = g["t"]
		# standing collars
		if near_neck and ty in ["shirt", "coverall", "work_jacket", "fleece", "blouse"] or (ty == "parka" and not hood_up):
			var h0 := neck_p.y - 0.02 * k
			var h1 := neck_p.y + (0.04 if ty in ["fleece", "parka"] else 0.022) * k
			var r0 := neck_r * 1.1 + t * 0.6 + 0.006 * k
			var cd := E._cone(p, Vector3(0.0, h0, neck_p.z + 0.006 * k), Vector3(0.0, h1, neck_p.z + 0.012 * k), r0, r0 - 0.008 * k)
			cd = E._smax(cd, -E._cone(p, Vector3(0.0, h0 - 0.04 * k, neck_p.z + 0.006 * k), Vector3(0.0, h1 + 0.05 * k, neck_p.z + 0.012 * k), neck_r * 0.98, neck_r * 0.94), 0.004)
			if ty in ["shirt", "blouse", "coverall", "work_jacket"] and p.z < neck_p.z - 0.02 * k and ax < 0.015 * k + (p.y - h0) * 0.5:
				cd = 1.0                                          # open at the throat
			if cd < best:
				best = cd
				c = -(10 + gi)
		if near_neck and ty in ["hoodie", "parka"] and str(g.get("hood", "down")) != "up":
			# the hood, down: a fabric roll behind the neck
			var hd2 := E._ell(p, Vector3(0.0, neck_p.y - 0.035 * k, 0.07 * k + t), Vector3(0.1 * k, 0.055 * k, 0.045 * k))
			hd2 = E._smin(hd2, E._cone(p, Vector3(-0.075 * k, neck_p.y - 0.03 * k, 0.025 * k), Vector3(0.075 * k, neck_p.y - 0.03 * k, 0.025 * k), 0.024 * k, 0.024 * k), 0.025 * k)
			hd2 = maxf(hd2, -p.z - 0.01 * k)
			if hd2 < best:
				best = hd2
				c = -(30 + gi)
		if near_neck and ty in ["hoodie", "parka"] and hood_up:
			# the hood, up: fabric rising around the neck toward the head part
			var hu := E._cone(p, Vector3(0.0, neck_p.y - 0.04 * k, neck_p.z + 0.01 * k), Vector3(0.0, neck_p.y + 0.09 * k, neck_p.z + 0.02 * k), neck_r * 1.45 + t, neck_r * 1.55 + t)
			hu = E._smax(hu, -E._cone(p, Vector3(0.0, neck_p.y - 0.06 * k, neck_p.z), Vector3(0.0, neck_p.y + 0.12 * k, neck_p.z), neck_r * 1.1, neck_r * 1.2), 0.004)
			if p.z < neck_p.z - 0.02 * k and p.y > neck_p.y - 0.01 * k:
				hu = 1.0
			if hu < best:
				best = hu
				c = -(30 + gi)
		if ty == "shirt" and int(g.get("tie", -1)) >= 0:
			var tw := lerpf(0.011, 0.03, smoothstep(neck_p.y - 0.04 * k, 0.25 * T, p.y)) * k
			var tip := 0.08 * T + ax * 0.9
			if p.z < 0.0 and ax < tw and p.y < neck_p.y - 0.005 * k and p.y > tip:
				var td := skin_d - t - VS * 1.4
				if td < best:
					best = td
					c = -40
		if near_neck and ty == "apron":
			# the neck strap: a tilted loop from the bib's top corners around the neck
			var ry := neck_p.y - 0.045 * k - maxf(neck_p.z - p.z, 0.0) * 1.4
			var rr := neck_r * 1.3 + max_t + maxf(neck_p.z - p.z, 0.0) * 0.5
			var sd := absf(Vector2(p.x, p.z - neck_p.z).length() - rr) - 0.007 * k
			sd = maxf(sd, absf(p.y - ry) - 0.011 * k)
			if p.y < 0.33 * T:
				sd = 1.0
			if sd < best:
				best = sd
				c = int(g["col2"])
	if acc.has("lanyard") and (near_neck or front_mid):
		var ld := absf(Vector2(p.x * 1.1, p.z - neck_p.z - 0.01 * k).length() - (neck_r * 1.3 + max_t + 0.004)) - 0.005
		var ly := neck_p.y - 0.02 * k - maxf(-p.z, 0.0) * 1.9
		ld = maxf(ld, absf(p.y - ly) - 0.01)
		if ld < best:
			best = ld
			c = 0x1d3f8a
		var card := E._rbox(p, Vector3(0.0, 0.215 * T, -(chest_r.z + max_t + 0.012 * k + 0.02 * k * bust)), Vector3(0.026, 0.034, 0.006), 0.002)
		if card < best:
			best = card
			c = -50
	return [best, c]


func _paint_extra_chest(id: int, p: Vector3, x: int, y: int, z: int) -> int:
	if id >= 10 and id < 30:
		var g: Dictionary = layers[id - 10]
		var cc: int = g["col2"] if g["type"] in ["work_jacket", "coverall"] else g["col"]
		return _cloth(cc, x, y, z, 0.05)
	if id >= 30 and id < 40:
		var g: Dictionary = layers[id - 30]
		if g["type"] == "parka" and int(g.get("fur", -1)) >= 0 and p.y > neck_p.y - 0.01 * k:
			return _fur(int(g["fur"]), x, y, z)
		var c := _cloth(g["col"], x, y, z, 0.07)
		if posmod(y, 3) == 0:
			c = _sc(c, 0.88)                                       # fabric folds
		return c
	if id == 40:
		var tie: int = 0x7a2020
		for g in layers:
			if int(g.get("tie", -1)) >= 0:
				tie = g["tie"]
		var c := tie if posmod(y + x, 5) > 1 else _sc(tie, 0.72)   # diagonal stripes
		if p.y > neck_p.y - 0.035 * k:
			c = _sc(tie, 0.85)                                     # the knot
		return _j(c, x, y, z, 0.03)
	if id == 50:
		# ID badge: white card, a photo square, a coloured strip
		if p.y > 0.235 * T:
			return 0x2a5ab0
		if p.x < -0.002 and p.y < 0.228 * T and p.y > 0.2 * T:
			return 0x8a7a6a
		return 0xe4e2dc
	return 0xff00ff


func _fur(c: int, x: int, y: int, z: int) -> int:
	return _j(_mix(c, _sc(c, 0.7), _h(x, y, z, 91)), x, y, z, 0.08)


## Colour of torso layer g at p (`part`: chest, pelvis, arm).
func _paint_layer(g: Dictionary, p: Vector3, x: int, y: int, z: int, part: String) -> int:
	var ty: String = g["type"]
	var col: int = g["col"]
	var col2: int = g["col2"]
	var ax := absf(p.x)
	var front := p.z < -0.03 * k
	var low := 0.0
	if part == "pelvis":
		low = 0.35
	var c := _cloth(col, x, y, z, 0.06, low)
	if part == "arm":
		return _paint_sleeve(g, p, x, y, z, c)
	var hem: float = g["hem"]
	var at_hem := p.y < hem + 0.022 * k and part != "pelvis_skirt"
	match ty:
		"tshirt":
			if at_hem and p.y < hem + 0.012 * k:
				c = _sc(c, 0.85)
			if p.y > _neckline(g, p) - 0.016 * k:
				c = _sc(col, 0.8)                                   # rib collar
			var pr := int(g.get("print", -1))
			if pr >= 0 and front and part == "chest" and ax < 0.06 * k and absf(p.y - 0.27 * T) < 0.045 * k:
				if _h(x, y, 0, 15) > 0.25 and (posmod(y, 3) != 0 or ax < 0.03 * k):
					c = _mix(c, pr, 0.75)                           # a faded print
		"shirt", "blouse":
			if front and ax < VS * 0.6 and p.y > 0.0:
				c = _sc(col, 0.88)                                  # placket
				if posmod(y, 5) == 0:
					return 0xdcd8cc if col < 0x808080 else _sc(col, 0.7)
			if ty == "shirt" and front and p.x > 0.035 * k and p.x < 0.1 * k and p.y > 0.21 * T and p.y < 0.3 * T:
				if absf(p.y - 0.3 * T) < VS * 0.6 or absf(p.x - 0.035 * k) < VS * 0.6 or absf(p.x - 0.1 * k) < VS * 0.6:
					c = _sc(c, 0.86)                                # pocket
			var st := int(g.get("stripe", -1))
			if st >= 0 and posmod(x, 4) == 0:
				c = _mix(c, st, 0.5)
		"sweater", "cardigan":
			c = c if posmod(x, 2) == 0 else _sc(c, 0.88)           # knit columns
			if at_hem:
				c = _sc(col, 0.78) if posmod(x, 2) == 0 else _sc(col, 0.9)
			if p.y > _neckline(g, p) - 0.02 * k:
				c = _sc(col, 0.8)
			var band := int(g.get("band", -1))
			if band >= 0 and absf(p.y - 0.34 * T) < 0.022 * k:
				c = band if posmod(x + y, 3) != 0 else _sc(band, 0.7)
			if ty == "cardigan":
				var op := _opening(g, p.y)
				if p.z < 0.0 and absf(ax - op - VS) < VS * 0.6:
					if posmod(y, 6) == 0 and p.y < 0.3 * T:
						return 0x3a2e26                              # buttons
					c = _sc(col, 0.82)
		"hoodie":
			if at_hem:
				c = _sc(col, 0.82) if posmod(x, 2) == 0 else _sc(col, 0.9)
			if front and ax < 0.1 * k and p.y > 0.0 and p.y < 0.13 * T:
				if absf(ax - (0.1 * k - (p.y / (0.13 * T)) * 0.025 * k)) < VS * 0.8 and p.y < 0.11 * T:
					c = _sc(col, 0.7)                               # pocket openings
				elif absf(p.y - 0.13 * T) < VS * 0.6:
					c = _sc(col, 0.8)
			if front and absf(ax - 0.028 * k) < VS * 0.6 and p.y > 0.3 * T:
				return 0xd8d4c8                                     # drawstrings
			var pr := int(g.get("print", -1))
			if pr >= 0 and front and ax < 0.07 * k and absf(p.y - 0.28 * T) < 0.03 * k and posmod(y, 2) == 0:
				c = _mix(c, pr, 0.7)
		"fleece", "sport":
			if front and ax < VS * 0.6:
				return 0x2a2a2a if posmod(y, 2) == 0 else _sc(col, 0.6)   # zip
			c = _j(_mix(c, col2, 0.15 * float(_h(x / 2, y / 2, z / 2, 81) > 0.6)), x, y, z, 0.02)
			if ty == "sport" and absf(ax - 0.1 * k) < VS * 0.8:
				c = col2                                            # side panels
			if front and p.x < -0.05 * k and p.x > -0.08 * k and absf(p.y - 0.3 * T) < 0.012 * k:
				c = col2                                            # logo
		"coverall":
			if front and ax < VS * 0.6 and p.y > -0.05 * k:
				return 0x2c2c2c if posmod(y, 2) == 0 else _sc(col, 0.7)
			if front and p.x < -0.045 * k and p.x > -0.11 * k and absf(p.y - 0.33 * T) < 0.018 * k and part == "chest":
				if absf(p.y - 0.33 * T) < VS * 0.6 and p.x < -0.06 * k and p.x > -0.1 * k:
					return 0xb02a2a                                 # name stitched in red
				return 0xe0ded6                                     # name patch
			if front and ax > 0.035 * k and ax < 0.11 * k and p.y > 0.2 * T and p.y < 0.315 * T:
				if absf(p.y - 0.275 * T) < VS * 0.6 or absf(ax - 0.035 * k) < VS * 0.6 or absf(ax - 0.11 * k) < VS * 0.6:
					c = _sc(c, 0.8)
			if absf(p.y - 0.02 * k) < 0.014 * k and part == "chest":
				c = _sc(col, 0.85)                                  # waist band
			c = _grease(c, x, y, z)
		"coat":
			var op := _opening(g, p.y)
			if p.z < 0.0 and ax > op and ax < op + 0.035 * k and p.y > 0.15 * T:
				c = _sc(c, 0.92)                                    # lapels
				if absf(ax - op - 0.035 * k) < VS * 0.6:
					c = _sc(col, 0.75)
			if p.z < 0.0 and p.x < -op and absf(p.x + op + 0.05 * k) < VS * 0.7 and posmod(y, 7) == 0 and p.y < 0.2 * T:
				return 0x1c1a18                                     # buttons
			if p.z > 0.06 * k and ax < VS * 0.6:
				c = _sc(c, 0.85)                                    # back seam
		"parka":
			var h := fposmod(p.y, 0.075 * k)
			if h < VS or h > 0.075 * k - VS * 0.5:
				c = _sc(c, 0.78)                                    # quilting seams
			if p.z < 0.0 and ax < 0.02 * k:
				c = _sc(col, 0.85)
				if ax < VS * 0.6 and posmod(y, 6) == 0:
					return 0x3a3a3a                                  # snaps
		"work_jacket":
			if p.y > 0.36 * T:
				c = _mix(c, _sc(col, 1.12), 0.4)
			if front and ax < VS * 0.6 and p.y < 0.32 * T:
				return _mix(0x9a7d48, col2, 0.3) if posmod(y, 2) == 0 else _sc(col2, 0.7)
			if front and ax > 0.035 * k and ax < 0.11 * k and p.y > 0.27 * T and p.y < 0.32 * T:
				c = _sc(col2, 0.95)
			if at_hem:
				c = _cloth(col2, x, y, z, 0.05)
		"hivis":
			var refl := absf(p.y - 0.1 * T) < 0.016 * k or absf(p.y - 0.2 * T) < 0.016 * k
			if front and absf(ax - 0.08 * k) < 0.016 * k and p.y > 0.2 * T:
				refl = true
			if not front and p.y > 0.2 * T and absf(ax - absf(p.y - 0.2 * T) * 0.4 - 0.02 * k) < 0.014 * k:
				refl = true
			c = _cloth(col, x, y, z, 0.04)
			if refl:
				c = _j(_mix(0xc4c8cc, 0x8a8e90, E._vn(x, y, z, 3, 17) * dirt), x, y, z, 0.03)
			if dirt > 0.0:
				c = _mix(c, 0x6a6448, smoothstep(0.5, 0.9, E._vn(x, y, z, 4, 23)) * dirt * 0.8)
		"apron":
			c = _cloth(col, x, y, z, 0.06, low)
			if part == "chest" and p.x > 0.02 * k and p.x < 0.075 * k and absf(p.y - 0.29 * T) < 0.013 * k:
				if p.x > 0.025 * k and p.x < 0.07 * k and absf(p.y - 0.29 * T) < VS * 0.6:
					return 0x303030                                 # the name on the tag
				return 0xf0eee6                                     # name tag
			if part != "chest" and absf(p.y + 0.14 * k) < VS * 0.6 and ax < 0.13 * k:
				c = _sc(col, 0.8)                                   # pocket seam
			if absf(p.y - 0.02 * k) < 0.012 * k and part == "chest":
				c = int(g["col2"])
	return c


func _grease(c: int, x: int, y: int, z: int) -> int:
	var g := E._vn(x, y, z, 3, 93)
	if g > 0.62 - dirt * 0.15:
		return _mix(c, 0x1e1c1a, (g - 0.55) * 1.6)
	return c


func _paint_sleeve(g: Dictionary, p: Vector3, x: int, y: int, z: int, c: int) -> int:
	var ty: String = g["type"]
	var col: int = g["col"]
	if ty in ["sweater", "cardigan"]:
		c = c if posmod(y, 2) == 0 else _sc(c, 0.9)
	if ty == "parka":
		var h := fposmod(p.y, 0.07 * k)
		if h < VS:
			c = _sc(c, 0.78)
	if ty == "coverall":
		c = _grease(c, x, y, z)
	if ty == "sport" and absf(absf(atan2(p.x, p.z)) - 1.57) < 0.22:
		c = int(g["col2"])                                        # a stripe down the sleeve
	return c


# --- pelvis --------------------------------------------------------------------------------

func _hips_skin(p: Vector3) -> float:
	var d := E._ell(p, hips_c, hips_r)
	d = E._smin(d, E._rbox(p, Vector3(0.0, 0.03 * k, 0.004 * k), Vector3(hips_r.x * 0.92, 0.06 * k, hips_r.z * 0.94), 0.05 * k), 0.03 * k)
	if belly > 0.02:
		d = E._smin(d, E._ell(p, Vector3(0.0, 0.07 * k, -0.035 * k - 0.025 * k * belly), Vector3(0.12 * k, 0.07 * k, (0.06 + 0.04 * belly) * k)), 0.04 * k)
	return maxf(d, p.y - 0.09 * k)


## A flared skirt (a long coat's tails, an apron, a skirt) from the waist to `len` below.
func _skirt(p: Vector3, len: float, t: float, flare: float) -> float:
	var top := 0.02 * k
	var u := clampf((top - p.y) / len, 0.0, 1.0)
	var rx := hips_r.x * (1.0 + flare * u) + t
	var rz := hips_r.z * (1.0 + flare * 1.3 * u) + t + 0.01 * k * belly
	var q := Vector2(p.x / rx, (p.z - hips_c.z) / rz)
	var d := (q.length() - 1.0) * minf(rx, rz)
	return maxf(d, maxf(p.y - top - 0.06 * k, -len - p.y))


func _pelvis(p: Vector3, x: int, y: int, z: int, paint: bool) -> float:
	var skin_d := _hips_skin(p)
	var lt := leg_t
	var lower := skin_d - lt
	var ty: String = legs["type"]
	if ty == "skirt":
		lower = minf(lower, _skirt(p, float(SKIRT["skirt"]) * k, 0.006 * k, 0.32))
	var belt := 1.0
	var belt_c := int(legs.get("belt", -1))
	if belt_c >= 0 or ty in ["jeans", "trousers", "cargo"]:
		belt = maxf(skin_d - lt - 0.007 * k, absf(p.y - 0.035 * k) - 0.016 * k)
	var d := minf(minf(skin_d, lower), belt)
	var yc := p.y - waist_y
	var nl := layers.size()
	var gds := PackedFloat32Array()
	gds.resize(nl)
	var pc := Vector3(p.x, yc, p.z)
	var cov_i := l_ty.find(COVERALL)
	for i in nl:
		var g: Dictionary = layers[i]
		gds[i] = 1.0
		var gt: String = g["type"]
		var t: float = float(g["t"]) + lt + 0.005 * k
		var gd := 1.0
		if SKIRT.has(gt):
			var len: float = float(SKIRT[gt]) * k
			gd = _skirt(p, len + _fray(x, z, g) * 2.0, t + _puff(g, p.y), 0.22 if gt == "coat" else 0.14)
			if gt == "apron":
				if p.z > 0.0 or absf(p.x) > 0.15 * k + 0.02 * k * weight:
					gd = 1.0
			elif gt == "coat" and bool(g.get("open", true)) or gt == "parka" and bool(g.get("open", false)):
				var op := 0.018 * k + 0.05 * k * clampf(-p.y / len, 0.0, 1.0)
				if p.z < 0.0 and absf(p.x) < op:
					gd = maxf(gd, absf(p.x) - op)
			if gt == "coat" and p.z > 0.0 and absf(p.x) < 0.01 * k and p.y < -0.15 * k:
				gd = 1.0                                          # back vent
		elif gt == "coverall" or cov_i > i:
			gd = 1.0                                              # inside the coverall: the legs garment does it
		elif yc > float(g["hem"]) + _fray(x, z, g):
			gd = skin_d - t
			var op := _opening(g, yc)
			if op > 0.0 and p.z < 0.0 and absf(p.x) < op:
				gd = 1.0
		gds[i] = gd
		d = minf(d, gd)
	var rag := 1.0
	if acc.has("rag"):
		rag = E._rbox(p, Vector3(0.09 * k, -0.1 * k, hips_r.z + lt + 0.012 * k), Vector3(0.035 * k, 0.075 * k, 0.006 * k), 0.004)
		rag = maxf(rag, -(p.y + 0.17 * k + 0.02 * _h(x, 0, 0, 7)))
		d = minf(d, rag)
	if not paint:
		return d
	for i in range(nl - 1, -1, -1):
		if gds[i] <= 0.0:
			var g: Dictionary = layers[i]
			if SKIRT.has(g["type"]):
				# the opening's inner faces: the lining
				if g["type"] != "apron" and p.z < 0.0 and p.y < 0.0 and gds[i] < -VS * 1.5:
					return float(_sc(int(g["col"]), 0.5))
				return float(_paint_layer(g, Vector3(p.x, yc, p.z), x, y, z, "pelvis_skirt" if p.y < -0.05 * k else "pelvis"))
			return float(_paint_layer(g, pc, x, y, z, "pelvis"))
	if rag <= 0.0:
		return float(_j(_mix(0xb8402e, 0x7a6a5a, E._vn(x, y, z, 2, 5)), x, y, z, 0.06))
	if belt <= 0.0 and lower > -VS * 0.6:
		if p.z < -hips_r.z * 0.7 and absf(p.x) < 0.02 * k:
			return float(0xa8a294 if absf(p.x) > VS * 0.6 else 0x2a2a2a)
		return float(_j(belt_c if belt_c >= 0 else 0x2e2620, x, y, z, 0.05))
	return float(_paint_legs(p, x, y, z, "pelvis"))


## Trousers, jeans, skirts ... at p (`part`: pelvis, thigh, shin).
func _paint_legs(p: Vector3, x: int, y: int, z: int, part: String) -> int:
	var ty: String = legs["type"]
	var col: int = legs["col"]
	var low := 0.0 if part == "pelvis" else (0.2 if part == "thigh" else 0.7)
	var c := _cloth(col, x, y, z, 0.07, low)
	var ax := absf(p.x)
	match ty:
		"jeans":
			# faded front of the thighs and knees, orange stitching on the seams
			if p.z < -0.02 * k and part != "pelvis":
				c = _mix(c, 0x9aa6b8, 0.16 * (1.0 - absf(p.x) / (thigh_r0 + 0.01)))
			if part != "pelvis" and absf(p.z) < VS * 0.6 and p.x * 1.0 != 0.0:
				c = _mix(c, 0xb07a3a, 0.45) if posmod(y, 2) == 0 else c
			if part == "pelvis" and p.z > 0.05 * k and ax > 0.03 * k and ax < 0.12 * k and p.y < -0.0 and p.y > -0.1 * k:
				if absf(ax - 0.03 * k) < VS * 0.6 or absf(ax - 0.12 * k) < VS * 0.6 or absf(p.y + 0.1 * k) < VS * 0.7:
					c = _mix(c, 0xb07a3a, 0.4)
		"trousers":
			if part != "pelvis" and p.z < -0.02 * k and absf(p.x) < VS * 0.6:
				c = _sc(c, 1.12)                                    # front crease
		"cargo":
			if part == "thigh" and p.x * float(1) > 0.0 and absf(p.z) < 0.045 * k and p.y < -0.12 * k and p.y > -0.26 * k:
				if p.y > -0.14 * k or absf(absf(p.z) - 0.045 * k) < VS * 0.7:
					c = _sc(col, 0.8)
		"sweatpants":
			if part == "shin" and p.y < -shin_len + 0.13 * k:
				c = _sc(col, 0.85) if posmod(y, 2) == 0 else _sc(col, 0.95)   # cuffs
			if part == "pelvis" and p.z < -0.05 * k and absf(p.x - 0.012) < VS * 0.6 and p.y > 0.0 and p.y < 0.07 * k:
				return 0xe6e2d8                                     # drawstring
		"skirt":
			if part == "pelvis":
				if p.y < -float(SKIRT["skirt"]) * k + 0.02 * k:
					c = _sc(col, 0.8)
				if posmod(x, 5) == 0 and p.y < -0.05 * k:
					c = _sc(c, 0.88)                                # pleats
				return c
			var tights := int(legs.get("col2", -1))
			if tights < 0:
				return _skin_paint(x, y, z)
			return _j(_mix(skin, tights, 0.82), x, y, z, 0.03)
		"leggings":
			var st := int(legs.get("col2", -1))
			if st >= 0 and part != "pelvis" and absf(atan2(p.x, p.z)) > 1.4 and absf(atan2(p.x, p.z)) < 1.75:
				c = st
		"coverall":
			c = _grease(c, x, y, z)
	if part == "shin" and p.y < -shin_len + 0.06 * k and dirt > 0.1:
		c = _mix(c, 0x3a3024, dirt * 0.5 * _h(x, y, z, 19))       # mud at the hems
	return c


# --- arms ----------------------------------------------------------------------------------

func _arm(p: Vector3, side: float, lower: bool, x: int, y: int, z: int, paint: bool) -> float:
	var skin_d := 0.0
	var along := 0.0               ## 0 at the shoulder, 1 at the wrist
	var total := upper_arm + forearm
	if not lower:
		skin_d = E._sph(p, Vector3(0.004 * side * k, -0.014 * k, 0.004 * k), arm_r0 * 0.98)
		skin_d = E._smin(skin_d, E._cone(p, Vector3(0.0, -0.02 * k, 0.0), Vector3(0.0, -upper_arm + 0.005, 0.004 * k), arm_r0, arm_r1), 0.03 * k)
		along = clampf(-p.y / total, 0.0, 1.0)
	else:
		skin_d = E._sph(p, Vector3(0.0, 0.0, 0.004 * k), farm_r0)
		skin_d = E._smin(skin_d, E._cone(p, Vector3(0.0, 0.0, 0.0), Vector3(0.0, -forearm * 0.8, -0.002), farm_r0, farm_r1 * 1.1), 0.02 * k)
		skin_d = E._smin(skin_d, E._cone(p, Vector3(0.0, -forearm * 0.8, 0.0), Vector3(0.0, -forearm - 0.02 * k, 0.0), farm_r1, wrist_r), 0.015 * k)
		along = clampf((upper_arm - p.y) / total, 0.0, 1.03)
	var d := skin_d
	var nl := l_ty.size()
	var gds := PackedFloat32Array()
	gds.resize(nl)
	gds.fill(1.0)
	var torn_sleeve := torn_l if side < 0.0 else torn_r
	for i in nl:
		var sl := l_sleeve[i]
		if torn_sleeve and i == nl - 1:
			sl = minf(sl, 0.5)
		if sl <= 0.0 or along > sl + 0.02:
			continue
		if along > sl - 0.02 and along > sl + (_h(x, 0, z, 51) - 0.5) * 0.04 * tears:
			continue
		var t := l_t[i] * 0.8
		if l_rolled[i] != 0 and along > sl - 0.07:
			t += 0.01 * k                                         # the rolled cuff
		elif sl >= 0.99 and along > 0.94:
			t += 0.003 * k                                        # cuff
		var gd := skin_d - t - _puff_i(i, p.y)
		if not paint and d <= 0.0:
			d = minf(d, gd)
			continue
		if gd <= 0.004 and l_top[i] == 0 and _torn(x, y, z, 7 + i):
			continue
		gds[i] = gd
		d = minf(d, gd)
	var extra := 1.0
	var ex_c := 0
	var sfx := "_l" if side < 0.0 else "_r"
	if lower and (watch_any or bandage_any):
		if acc.has("watch" + sfx):
			extra = maxf(skin_d - 0.008 * k, absf(p.y + forearm - 0.035 * k) - 0.012 * k)
			ex_c = 0x2a2a2c if p.z > -wrist_r * 0.6 else 0xb8b8b0
		if acc.has("bandage" + sfx):
			var bd := maxf(skin_d - 0.006 * k, absf(p.y + forearm * 0.55) - 0.05 * k)
			if bd < extra:
				extra = bd
				ex_c = _j(_mix(0xe8e4d8, 0xb4a890, E._vn(x, y, z, 2, 9) * (0.4 + dirt)), x, y, z, 0.04)
				if posmod(y + roundi(p.x / VS), 4) == 0:
					ex_c = _sc(ex_c, 0.9)
	d = minf(d, extra)
	if not paint:
		return d
	if extra <= 0.0 and extra <= d + 0.0001:
		return float(ex_c)
	for i in range(nl - 1, -1, -1):
		if gds[i] <= 0.0:
			var g: Dictionary = layers[i]
			var c := _paint_layer(g, p, x, y, z, "arm")
			if bool(g.get("rolled", false)) and along > float(g["sleeve"]) - 0.07:
				c = _sc(c, 0.9 if posmod(y, 2) == 0 else 1.05)
			elif float(g["sleeve"]) >= 0.99 and along > 0.94:
				c = _sc(int(g["col"]), 0.82)
			return float(c)
	# bare skin: a few hairs and grime on the forearm
	var c := skin
	if lower and sex < 0.5 and _h(x, y, z, 33) > 0.85:
		c = _mix(skin, hair_col, 0.25)
	if dirt > 0.2 and E._vn(x, y, z, 3, 37) > 0.75:
		c = _mix(c, 0x5a4a3a, 0.3)
	return float(_j(c, x, y, z, 0.03))


## A tense, half-clawed hand (wrist at the origin, fingers along -Y, thumb
## forward -Z, palm toward the body), Eli's hand with longer, spread fingers.
func _hand(p: Vector3, side: float, x: int, y: int, z: int, paint: bool) -> float:
	var q := Vector3(p.x * side, p.y, p.z) / hand_s
	var palm := E._rbox(q, Vector3(0.002, -0.05, -0.004), Vector3(0.014, 0.042, 0.036), 0.012)
	var d := palm
	var lens := [0.155, 0.164, 0.156, 0.14]
	var curl := claw
	for i in 4:
		var fz := -0.031 + i * 0.0165 + (i - 1.5) * 0.004 * curl
		var tip: float = -float(lens[i])
		var mid := Vector3(-0.01 - 0.012 * curl, -0.12, fz)
		d = minf(d, E._cone(q, Vector3(0.0, -0.08, fz * 0.9), mid, 0.0088, 0.0082))
		d = minf(d, E._cone(q, mid, Vector3(-0.024 - 0.035 * curl, tip + 0.012 + 0.03 * curl, fz * 1.05), 0.0082, 0.007))
	d = E._smin(d, E._cone(q, Vector3(-0.004, -0.03, -0.036), Vector3(-0.02, -0.088, -0.064), 0.012, 0.0085), 0.008)
	d = E._smin(d, E._cone(q, Vector3(0.0, 0.03, 0.0), Vector3(0.0, -0.01, -0.002), 0.027, 0.03), 0.01)
	var sfx := "_l" if side < 0.0 else "_r"
	var glove := acc.has("glove" + sfx)
	if glove:
		d -= 0.003
	d *= hand_s
	if not paint:
		return d
	if glove:
		return float(_cloth(0x4a4440 if q.y > -0.02 else 0x5a5048, x, y, z, 0.06))
	var c := skin
	if absf(q.y + 0.088) < VS * 0.7 and q.x > 0.0:
		c = _mix(c, skin_red, 0.5)
	if q.y < -0.13:
		c = _mix(c, 0x4a3c30, 0.25 + 0.35 * dirt)                 # dirty fingertips
	return float(_j(c, x, y, z, 0.03))


# --- legs ----------------------------------------------------------------------------------

func _thigh(p: Vector3, side: float, x: int, y: int, z: int, paint: bool) -> float:
	var q := Vector3(p.x * side, p.y, p.z)
	var skin_d := E._sph(q, Vector3(0.004 * k, 0.0, 0.004 * k), thigh_r0)
	skin_d = E._smin(skin_d, E._cone(q, Vector3.ZERO, Vector3(0.0, -thigh_len, -0.004 * k), thigh_r0, thigh_r1), 0.03 * k)
	skin_d = E._smin(skin_d, E._ell(q, Vector3(0.006 * k, -thigh_len * 0.37, -0.012 * k), Vector3(thigh_r0 * 0.9, thigh_len * 0.37, thigh_r0 * 0.92)), 0.03 * k)
	var ty: String = legs["type"]
	var lt := leg_t if ty != "skirt" else 0.002 * k
	var pocket := ty == "cargo" and side > 0.0 and q.x > 0.02 * k and q.y < -0.12 * k and q.y > -0.27 * k and absf(q.z) < 0.048 * k
	var d := skin_d - lt - (VS * 0.9 if pocket else 0.0)
	if not paint:
		return d
	return float(_paint_legs(q, x, y, z, "thigh"))


func _shin(p: Vector3, side: float, x: int, y: int, z: int, paint: bool) -> float:
	var q := Vector3(p.x * side, p.y, p.z)
	var skin_d := E._sph(q, Vector3(0.0, -0.004 * k, -0.004 * k), knee_r)
	skin_d = E._smin(skin_d, E._cone(q, Vector3(0.0, -0.01 * k, 0.0), Vector3(0.0, -shin_len, 0.004 * k), knee_r, ankle_r), 0.02 * k)
	skin_d = E._smin(skin_d, E._ell(q, Vector3(0.0, -shin_len * 0.3, 0.014 * k), Vector3(calf_r, shin_len * 0.25, calf_r)), 0.03 * k)
	var ty: String = legs["type"]
	var f: Dictionary = feet[0 if side < 0.0 else 1]
	var ft: String = f["type"]
	var hem_y := -shin_len + 0.07 * k                       # trousers end over the shoe
	var lt := leg_t
	var trousers := 1.0
	if ty in ["skirt", "leggings"]:
		trousers = skin_d - (0.002 * k if ty == "skirt" else lt)
		hem_y = -shin_len - 0.1
	else:
		# trousers hang straight from the knee (a looser tube), sweatpants gather at the cuff
		var r0 := knee_r + lt + 0.006 * k
		var r1 := r0 - (0.012 * k if ty == "jeans" else 0.004 * k)
		if ty == "sweatpants":
			r1 = ankle_r + lt
		trousers = E._cone(q, Vector3(0.0, 0.0, 0.0), Vector3(0.0, hem_y, 0.006 * k), r0, r1)
		trousers = E._smin(trousers, skin_d - lt, 0.01)
		trousers = maxf(trousers, hem_y - q.y + _h(x, 0, z, 61) * 0.006 * tears * 4.0)
	var boot := 1.0
	if ft == "boots":
		boot = E._cone(q, Vector3(0.0, -shin_len + 0.13 * k, 0.004 * k), Vector3(0.0, -shin_len, 0.006 * k), ankle_r + 0.022 * k, ankle_r + 0.02 * k)
	var sock := skin_d - 0.002
	var d := minf(minf(trousers, boot), sock)
	if not paint:
		return d
	if trousers <= 0.0:
		return float(_paint_legs(q, x, y, z, "shin"))
	if boot <= 0.0:
		var c := _cloth(int(f["col"]), x, y, z, 0.06, 0.8)
		if q.z < -0.03 * k and absf(q.x) < 0.03 * k:
			c = 0xc9ab7b if posmod(y, 2) == 0 else _sc(int(f["col"]), 0.7)
		return float(c)
	# the sock between the hem and the shoe
	var sc: int = int(f.get("sock", 0xd0ccc0 if ft == "sneakers" else 0x2a2a2e))
	return float(_j(sc if posmod(y, 2) == 0 else _sc(sc, 0.92), x, y, z, 0.03))


func _foot(p: Vector3, side: float, x: int, y: int, z: int, paint: bool) -> float:
	var f: Dictionary = feet[0 if side < 0.0 else 1]
	var ft: String = f["type"]
	var q := Vector3(p.x * side, p.y, p.z) / foot_s
	var d := 1.0
	var sole := 1.0
	var col: int = f["col"]
	match ft:
		"boots":
			d = E._sph(q, Vector3(0.0, 0.0, 0.004), 0.05)
			d = E._smin(d, E._rbox(q, Vector3(0.0, -0.035, 0.03), Vector3(0.047, 0.042, 0.045), 0.02), 0.02)
			var top := lerpf(-0.01, -0.045, smoothstep(-0.02, -0.17, q.z))
			d = E._smin(d, E._rbox(q, Vector3(0.004, (top - 0.075) * 0.5, -0.09), Vector3(0.05, (top + 0.075) * 0.5, 0.095), 0.025), 0.03)
			sole = E._rbox(q, Vector3(0.002, -0.083, -0.055), Vector3(0.056, 0.012, 0.135), 0.008)
		"sneakers":
			d = E._sph(q, Vector3(0.0, -0.01, 0.006), 0.044)
			d = E._smin(d, E._rbox(q, Vector3(0.0, -0.042, 0.025), Vector3(0.044, 0.036, 0.045), 0.02), 0.02)
			var top := lerpf(-0.02, -0.05, smoothstep(-0.02, -0.17, q.z))
			d = E._smin(d, E._rbox(q, Vector3(0.003, (top - 0.07) * 0.5, -0.085), Vector3(0.047, (top + 0.07) * 0.5, 0.095), 0.028), 0.03)
			sole = E._rbox(q, Vector3(0.002, -0.08, -0.055), Vector3(0.054, 0.017, 0.14), 0.014)
		"shoes":
			d = E._sph(q, Vector3(0.0, -0.01, 0.004), 0.04)
			d = E._smin(d, E._rbox(q, Vector3(0.0, -0.045, 0.02), Vector3(0.04, 0.03, 0.045), 0.015), 0.02)
			var top := lerpf(-0.04, -0.062, smoothstep(-0.02, -0.18, q.z))
			d = E._smin(d, E._rbox(q, Vector3(0.002, (top - 0.08) * 0.5, -0.09), Vector3(0.042 - 0.012 * smoothstep(-0.1, -0.2, q.z), (top + 0.08) * 0.5, 0.1), 0.02), 0.025)
			sole = minf(E._rbox(q, Vector3(0.002, -0.086, -0.07), Vector3(0.046, 0.006, 0.13), 0.004),
				E._rbox(q, Vector3(0.0, -0.078, 0.035), Vector3(0.04, 0.014, 0.03), 0.004))
		"slippers":
			d = E._sph(q, Vector3(0.0, -0.02, 0.004), 0.04)
			d = E._smin(d, E._rbox(q, Vector3(0.0, -0.06, -0.05), Vector3(0.052, 0.03, 0.13), 0.026), 0.03)
			sole = E._rbox(q, Vector3(0.0, -0.085, -0.05), Vector3(0.054, 0.008, 0.14), 0.01)
		_:     # a sock: no shoe
			d = E._sph(q, Vector3(0.0, -0.01, 0.004), 0.036)
			d = E._smin(d, E._rbox(q, Vector3(0.0, -0.06, -0.045), Vector3(0.036, 0.026, 0.11), 0.022), 0.025)
			for i in 4:
				d = E._smin(d, E._sph(q, Vector3(-0.024 + i * 0.016, -0.07, -0.152 + absf(i - 1.2) * 0.008), 0.014), 0.008)
	if q.y < -0.082 and ft == "boots" and q.z > -0.06 and q.z < 0.0 and q.y < -0.088:
		sole = 1.0
	var dd := minf(d, sole) * foot_s
	if not paint:
		return dd
	var c2 := int(f.get("col2", _sc(col, 0.7)))
	if sole <= 0.0 and (d > 0.0 or q.y < -0.07):
		var sc := int(f.get("sole", 0xe0ddd4 if ft == "sneakers" else 0x29241f))
		var c := sc if posmod(z, 2) == 0 or q.y > -0.085 else _sc(sc, 0.8)
		if ft == "sneakers" and dirt > 0.0:
			c = _mix(c, 0x6a5a48, dirt * 0.6 * E._vn(x, y, z, 2, 3))
		return float(_j(c, x, y, z, 0.04))
	var c := _cloth(col, x, y, z, 0.06, 0.9)
	match ft:
		"boots":
			if q.z < -0.115:
				c = _cloth(_sc(col, 0.7), x, y, z, 0.05)
			elif q.y > lerpf(-0.01, -0.045, smoothstep(-0.02, -0.17, q.z)) - 0.016 and q.z < -0.01 and absf(q.x) < 0.024:
				c = 0xc9ab7b if posmod(z, 2) == 0 else _sc(col, 0.72)
		"sneakers":
			if q.z < -0.13:
				c = _cloth(c2, x, y, z, 0.04)
			if absf(q.x) > 0.035 and q.y < -0.035 and q.y > -0.06 and q.z > -0.12 and q.z < 0.0:
				c = c2                                             # side stripe
			if q.y > -0.035 and q.z < -0.02 and q.z > -0.12 and absf(q.x) < 0.022:
				c = 0xe8e6e0 if posmod(z, 2) == 0 else _sc(col, 0.8)   # laces
		"shoes":
			c = _j(_mix(col, 0xffffff, 0.08 * float(q.y > -0.03 and q.z < -0.12)), x, y, z, 0.02)
		"slippers":
			c = _j(_mix(col, _sc(col, 0.85), _h(x, y, z, 77)), x, y, z, 0.05)
		_:
			c = _j(int(f.get("sock", 0x8a8478)), x, y, z, 0.05)
			if q.y < -0.07:
				c = _mix(c, 0x3a3026, 0.6)                          # filthy sole
	return float(c)


# --- head ----------------------------------------------------------------------------------
# Head space: the neck pivot is the origin; the head is sculpted in q space
# (p / HS) like Eli's; face features are painted on explicit voxel rows /
# columns (r_eye, r_brow, r_nose, r_mouth, c_iris) derived from the proportions.

func _skull(q: Vector3) -> float:
	var c := Vector3(0.0, 0.19 * hh, 0.012 * hd)
	var r := Vector3(0.086 * hw, 0.106 * hh, 0.1 * hd)
	var d := E._ell(q, c, r)
	d = E._smin(d, E._rbox(q, Vector3(0.0, 0.1 * hh, -0.014), Vector3(0.064 * jaw * hw, 0.05 * hh, 0.064 * hd), 0.03), 0.035)
	d = E._smin(d, E._sph(q, Vector3(0.0, 0.062 * hh - 0.006 * (chin - 0.5), -0.06 - 0.012 * (chin - 0.5)), 0.031 * (0.85 + 0.3 * chin) * jaw), 0.02)
	for s: float in [-1.0, 1.0]:
		d = E._smin(d, E._sph(q, Vector3(0.048 * s * hw, 0.128 * hh, -0.058), 0.027 * (0.75 + 0.5 * cheeks)), 0.02)
		d = E._smin(d, E._ell(q, Vector3(0.087 * s * hw, 0.146 * hh, 0.01 * hd), Vector3(0.015, 0.03, 0.021) * ears), 0.008)
		if weight > 0.35:
			d = E._smin(d, E._sph(q, Vector3(0.05 * s * hw, 0.092 * hh, -0.045), 0.032 * (weight - 0.2)), 0.02)
		if age > 0.6:
			d = E._smin(d, E._sph(q, Vector3(0.05 * s * hw * jaw, 0.072 * hh, -0.044), 0.024 * (age - 0.45)), 0.015)
	if weight > 0.4:
		d = E._smin(d, E._sph(q, Vector3(0.0, 0.042 * hh, -0.035), 0.05 * (weight - 0.3)), 0.03)
	d = E._smin(d, E._cone(q, Vector3(-0.05 * hw, 0.176 * hh, -0.08), Vector3(0.05 * hw, 0.176 * hh, -0.08), 0.015 * brow, 0.015 * brow), 0.02)
	for s: float in [-1.0, 1.0]:
		d = E._smax(d, -E._sph(q, Vector3(eye_x * s, 0.15 * hh, -0.11), 0.016 + 0.004 * float(face.get("circles", 0.3))), 0.01)
	var tip := Vector3(0.0, 0.11 * hh - 0.012 * (nose - 1.0), -0.104 - 0.012 * (nose - 1.0))
	d = E._smin(d, E._cone(q, Vector3(0.0, 0.165 * hh, -0.09), tip + Vector3(0.0, 0.004, -0.005), 0.009 * nose_w, 0.012 * nose_w), 0.012)
	d = E._smin(d, E._sph(q, tip, 0.016 * nose_w), 0.01)
	var nr := neck_r * 1.02 / HS
	d = E._smin(d, E._cone(q, Vector3(0.0, -0.06 - 0.03 * (neck_len - 1.0), 0.014), Vector3(0.0, 0.1 * hh, 0.004), nr, nr * 0.94), 0.03)
	return d


func _hairline(q: Vector3) -> float:
	var a := absf(atan2(q.x, -(q.z - 0.01)))
	var front := float(hair.get("front", 0.214)) * hh
	if hair_style == "balding":
		front = 0.4
	var y := lerpf(front, 0.172 * hh, smoothstep(0.4, 1.4, a))
	if hair_style == "balding":
		y = lerpf(0.4, 0.2 * hh, smoothstep(0.9, 1.5, a))
	if a > 1.2 and a < 1.85:
		y = maxf(y, 0.172 * hh + 0.012 * sin((a - 1.2) / 0.65 * PI))
	y = lerpf(y, 0.1 * hh, smoothstep(1.7, 2.6, a))
	return y


func _hair_d(q: Vector3, x: int, y: int, z: int) -> float:
	if hair_style == "bald":
		return 1.0
	var hc := Vector3(0.0, 0.19 * hh, 0.012 * hd)
	var hr := Vector3(0.086 * hw, 0.106 * hh, 0.1 * hd)
	var top := smoothstep(0.13 * hh, 0.27 * hh, q.y)
	var thick := lerpf(0.006, 0.024, top)
	var noise := 0.01
	match hair_style:
		"buzz":
			thick = 0.0045
			noise = 0.0
		"messy":
			thick = lerpf(0.01, 0.034, top)
			noise = 0.03
		"curly":
			thick = lerpf(0.016, 0.04, top)
			noise = 0.022
		"combed", "bun", "ponytail", "long", "bob":
			thick = lerpf(0.007, 0.018, top)
			noise = 0.004
		"balding":
			thick = 0.008
	thick -= 0.006 * smoothstep(0.0, 0.08, q.z) * float(hair_style not in ["long", "bob", "curly"])
	var d := E._ell(q, hc + Vector3(0.0, 0.006, 0.004), hr + Vector3(thick, thick, thick))
	if noise > 0.0:
		d -= (E._vn(x, y, z, 4 if hair_style != "curly" else 2, 21) - 0.5) * noise * maxf(top, 0.4)
	match hair_style:
		"short", "messy":
			d = E._smin(d, E._ell(q, Vector3(-0.025, 0.238 * hh, -0.082), Vector3(0.065, 0.022, 0.032)), 0.02)
			d = E._smin(d, E._sph(q, Vector3(0.014, 0.302 * hh, 0.035), 0.013 + 0.01 * float(hair_style == "messy")), 0.012)
			if hair_style == "messy":
				d = E._smin(d, E._sph(q, Vector3(0.05, 0.27 * hh, 0.04), 0.02), 0.012)
				d = E._smin(d, E._sph(q, Vector3(-0.05, 0.24 * hh, -0.04), 0.018), 0.012)
		"combed":
			d = E._smin(d, E._ell(q, Vector3(0.015, 0.272 * hh, -0.03), Vector3(0.07, 0.022, 0.07)), 0.02)
			d = E._smin(d, E._ell(q, Vector3(0.03, 0.235 * hh, -0.085), Vector3(0.055, 0.018, 0.03)), 0.015)   # swept fringe
			if q.z < -0.07 and q.y < 0.25 * hh and q.y > 0.18 * hh and _h(x, 0, 0, 57) > 0.6:
				d -= 0.01                                            # strands falling on the forehead
			if q.y > 0.24 * hh and q.z < 0.04 and absf(q.x + 0.035) < 0.004:
				d = maxf(d, 0.002)                                   # the part
		"bun":
			d = E._smin(d, E._sph(q, Vector3(0.0, 0.25 * hh, 0.095), 0.042), 0.015)
		"ponytail":
			d = E._smin(d, E._cone(q, Vector3(0.0, 0.215 * hh, 0.1), Vector3(0.0, 0.03, 0.15), 0.026, 0.017), 0.015)
	var hl := _hairline(q)
	if q.z < -0.03:
		hl -= 0.016 * float(_h(x / 2, 0, 0, 51) > 0.55) + 0.008 * _h(x, 1, 0, 53)
	if hair_style in ["long", "bob"]:
		# a curtain hanging straight from the crown: an elliptic cylinder below the
		# head centre, cut away in front of the face
		var end := -0.06 if hair_style == "long" else 0.06 * hh
		var qc := q
		qc.y = maxf(q.y, hc.y)
		var cr := hr + Vector3(0.016, 0.0, 0.02)
		var cd := E._ell(qc, hc + Vector3(0.0, 0.0, 0.012), cr)
		cd = maxf(cd, end - q.y)
		cd -= (E._vn(x, y, z, 3, 25) - 0.5) * 0.008
		var face_cut := q.z < -0.03 and q.y < hl + 0.01 and absf(q.x) < 0.072 * hw
		if face_cut or (q.z < -0.065 and q.y < 0.17 * hh):
			cd = 1.0
		if q.y < end + 0.03:
			cd += _h(x, 0, z, 27) * 0.012                          # ragged ends
		return minf(E._smax(d, hl - q.y, 0.006), cd)
	if hair_style == "ponytail" and q.z > 0.06 and q.y < hl:
		return d
	return E._smax(d, hl - q.y, 0.006)


## Headwear distance (q space): cap, beanie, headband, hood (up).
func _hat_d(q: Vector3, x: int, y: int, z: int) -> float:
	var ty := str(hat.get("type", ""))
	var hc := Vector3(0.0, 0.19 * hh, 0.012 * hd)
	var hr := Vector3(0.086 * hw, 0.106 * hh, 0.1 * hd)
	match ty:
		"beanie":
			var d := E._ell(q, hc + Vector3(0.0, 0.012, 0.0), hr + Vector3(0.022, 0.022, 0.022))
			return maxf(d, 0.155 * hh - q.y + 0.01 * float(q.z > 0.0))
		"cap":
			var d := E._ell(q, hc + Vector3(0.0, 0.01, 0.0), hr + Vector3(0.014, 0.014, 0.014))
			d = maxf(d, 0.2 * hh - q.y)
			var fwd := -1.0 if not bool(hat.get("back", false)) else 1.0
			var brim := E._rbox(q, Vector3(0.0, 0.205 * hh - 0.006 * fwd * 0.0, (0.1 + 0.03) * fwd), Vector3(0.062, 0.005, 0.045), 0.004)
			return minf(d, brim)
		"headband":
			var d := E._ell(q, hc, hr + Vector3(0.008, 0.008, 0.008))
			return maxf(d, absf(q.y - 0.215 * hh) - 0.012)
		"hood":
			var d := E._ell(q, hc + Vector3(0.0, 0.012, 0.02), hr + Vector3(0.034, 0.03, 0.04))
			d = E._smin(d, E._cone(q, Vector3(0.0, -0.07, 0.045), Vector3(0.0, 0.1, 0.035), 0.085 * hw, 0.09 * hw), 0.04)
			# the face opening: an oval cut from the front, a rolled rim around it
			var o := Vector2(q.x / (0.078 * hw), (q.y - 0.13 * hh) / (0.135 * hh)).length()
			if o < 1.0:
				d = maxf(d, -(q.z - 0.012 + 0.03 * (1.0 - o)))
			d = maxf(d, -0.09 - q.y)
			return d
	return 1.0


func _beard_d(q: Vector3, ds: float, x: int, y: int, z: int) -> float:
	match beard:
		"full", "short":
			var t := 0.014 if beard == "full" else 0.006
			var d := ds - t - (E._vn(x, y, z, 2, 43) - 0.5) * 0.008
			var region := y <= r_mouth + 1 and y >= -1 and q.z < 0.03 and (absi(x) >= 3 or y <= r_mouth - 2 or not (q.z < -0.045))
			if q.y > 0.11 * hh or not region:
				return 1.0
			if absi(x) >= roundi(0.07 * hw * HS / VS) and q.y > 0.07 * hh and q.z > -0.02:
				return d                                           # sideburns
			return d
		"moustache":
			return maxf(ds - 0.008, maxf(absf(q.y - (r_mouth + 1.2) * VS / HS) - 0.008, absf(q.x) - 0.034))
	return 1.0


func _glasses_d(q: Vector3) -> float:
	if not (acc.has("glasses") or acc.has("glasses_cracked")):
		return 1.0
	var zf := -0.112
	var best := 1.0
	for s: float in [-1.0, 1.0]:
		var c := Vector3(eye_x * s * 1.08, 0.15 * hh, zf)
		var outer := E._rbox(q, c, Vector3(0.025, 0.017, 0.004), 0.004)
		var inner := E._rbox(q, c, Vector3(0.019, 0.011, 0.01), 0.002)
		best = minf(best, maxf(outer, -inner))
		var arm := E._rbox(q, Vector3(0.082 * s * hw, 0.155 * hh, zf + 0.06), Vector3(0.003, 0.003, 0.06), 0.0)
		best = minf(best, arm)
	best = minf(best, E._rbox(q, Vector3(0.0, 0.155 * hh, zf - 0.002), Vector3(0.012, 0.003, 0.003), 0.0))
	return best


func _head(p: Vector3, x: int, y: int, z: int, paint: bool) -> float:
	var q := p / HS
	var ds := _skull(q)
	var dh := _hair_d(q, x, y, z)
	var dt := _hat_d(q, x, y, z)
	if hat_low < 1.0 and q.y > hat_low and dh < 1.0:
		dh = maxf(dh, ds - 0.008)                                # hair stays under the hat or hood
	var db := _beard_d(q, ds, x, y, z)
	var dg := _glasses_d(q)
	var bandage := 1.0
	if acc.has("bandage_head"):
		bandage = maxf(ds - 0.01, absf(q.y - 0.21 * hh + q.x * 0.25) - 0.016)
	var d := minf(minf(minf(ds, dh), minf(dt, db)), minf(dg, bandage)) * HS
	if not paint:
		return d
	if dt <= 0.0:
		return float(_paint_hat(q, x, y, z))
	if dg <= 0.0 and ds > -0.003:
		return float(0x1c1c1e if not acc.has("glasses_cracked") or _h(x, y, z, 5) > 0.3 else 0x8a8a8a)
	if bandage <= 0.0:
		return float(_j(_mix(0xe6e2d6, 0xa89c84, E._vn(x, y, z, 2, 9) * (0.4 + dirt)), x, y, z, 0.04))
	if dh <= 0.0 and (ds > -0.004 or q.y > _hairline(q) + 0.012 or hair_style in ["long", "bob"] and ds > 0.0):
		return float(_paint_hair(q, x, y, z))
	if db <= 0.0 and ds > -0.002:
		return float(_beard_col(x, y, z, 1.0))
	return float(_face(q, x, y, z))


func _paint_hat(q: Vector3, x: int, y: int, z: int) -> int:
	var ty := str(hat.get("type", ""))
	var col := int(hat.get("col", 0x3a3a40))
	var col2 := int(hat.get("col2", _sc(col, 0.75)))
	match ty:
		"beanie":
			var c := col if posmod(x, 2) == 0 else _sc(col, 0.85)
			if q.y < 0.19 * hh:
				c = _sc(c, 0.9) if posmod(y, 2) == 0 else c         # folded rib
			return _j(c, x, y, z, 0.04)
		"cap":
			if q.y < 0.21 * hh and absf(q.z) > 0.09:
				return _cloth(col2, x, y, z, 0.04)                  # brim
			if q.y > 0.3 * hh:
				return col2                                         # button
			return _cloth(col, x, y, z, 0.05)
		"headband":
			return _j(col, x, y, z, 0.04)
		"hood":
			var fur := int(hat.get("fur", -1))
			var o := Vector2(q.x / (0.078 * hw), (q.y - 0.13 * hh) / (0.135 * hh)).length()
			if fur >= 0 and q.z < 0.0 and o < 1.45:
				return _fur(fur, x, y, z)
			var c := _cloth(col, x, y, z, 0.07)
			if q.z < 0.01 and o < 1.2:
				c = _sc(col, 0.72)                                  # hem around the face
			if absf(q.x) < 0.006 and q.z > -0.02 and q.y > 0.2 * hh:
				c = _sc(col, 0.82)                                  # centre seam
			return c
	return col


func _paint_hair(q: Vector3, x: int, y: int, z: int) -> int:
	var s := _h(x, 0, z / 3, 23) if q.y > 0.2 * hh else _h(0, y / 3, z, 23)
	if hair_style in ["long", "bob", "ponytail"] and q.y < 0.2 * hh:
		s = _h(x, y / 4, z, 23)
	var clump := E._vn(x, y, z, 3, 27)
	var c := _mix(hair_col, hair_col2, 0.4 * smoothstep(0.22, 0.3, q.y / hh) + 0.35 * smoothstep(0.55, 0.8, clump))
	if s < 0.2:
		c = _sc(c, 0.84)
	elif s > 0.85:
		c = _sc(c, 1.1)
	var grey := float(hair.get("grey", 0.0))
	if grey > 0.0:
		var gq := E._vn(x, y, z, 2, 29) * 0.7 + _h(x, y, z, 30) * 0.3
		if gq < grey * 0.9:
			c = _mix(c, 0x9c9890, 0.35 + 0.45 * grey)
	if hair_style == "ponytail" and absf(q.y - 0.19 * hh) < 0.01 and q.z > 0.1:
		return int(hair.get("tie", 0xa02a3a))
	if dirt > 0.3 and E._vn(x, y, z, 3, 31) > 0.8:
		c = _sc(c, 0.8)                                            # matted
	return _j(c, x, y, z, 0.025)


func _beard_col(x: int, y: int, z: int, amt: float) -> int:
	var bc := int(hair.get("beard_col", _mix(_sc(hair_col, 1.05), 0x8a6a52, 0.12)))
	var grey := float(hair.get("grey", 0.0))
	if grey > 0.0 and _h(x, y, z, 31) < grey * 1.1:
		bc = _mix(bc, 0xa8a49c, 0.6)
	return _j(_mix(skin, bc, amt + (_h(x, y, z, 37) - 0.5) * 0.18), x, y, z, 0.03)


func _face(q: Vector3, x: int, y: int, z: int) -> int:
	var c := skin
	var ax := absi(x)
	var front := q.z < -0.045
	if y < 2 and not (front and y >= 1):
		c = _mix(skin, skin_dk, 0.2)                              # neck
	# ruddy, cold: nose, cheeks, ears
	if front and ax >= c_iris and ax <= c_iris + 1 and (y == r_nose or y == r_nose + 1):
		c = _mix(c, skin_red, 0.45)
	if ax <= 1 and (y == r_nose or y == r_nose + 1) and q.z < -0.1:
		c = _mix(c, skin_red, 0.35)
	var ex := absf(q.x) > 0.075 * hw
	if ex and y >= r_nose and y <= r_brow and q.z > -0.03:
		c = _mix(c, skin_red, 0.25)
	# sallow skin, grime smudges
	var grime := float(face.get("grime", 0.3))
	if grime > 0.0:
		var g := E._vn(x, y, z, 3, 47)
		if g > 0.66 - grime * 0.2:
			c = _mix(c, 0x5a4a3c, (g - 0.6) * 1.2 * grime)
	if front:
		# circles and raw lids under the eyes
		var circ := float(face.get("circles", 0.4))
		if ax >= c_iris - 1 and ax <= c_iris + 1 and (y == r_eye - 1 or (y == r_eye - 2 and ax == c_iris)):
			c = _mix(c, 0x6a4652, 0.35 * circ + 0.08)
			if y == r_eye - 1:
				c = _mix(c, 0x8a4a48, 0.2)
		var f := _features(q, x, y, z, ax, c)
		if f >= 0:
			return f
		# age lines: forehead, nasolabial folds
		var lines := float(face.get("lines", age))
		if lines > 0.35:
			if (y == r_brow + 2 or y == r_brow + 4) and ax <= c_iris + 1 and posmod(x, 3) != 0:
				c = _mix(c, skin_dk, 0.3 * lines)
			if ax == c_iris and (y == r_mouth + 1 or y == r_mouth + 2):
				c = _mix(c, skin_dk, 0.4 * lines)
	# facial hair as a shade (stubble) where there's no beard volume
	if beard in ["stubble", "full", "short", "goatee"]:
		var jaw_reg := y <= r_mouth + 1 and y >= 1 and q.z < -0.005 and (ax >= 3 or y <= r_mouth - 2 or (y == r_mouth - 1 and ax >= 1) or not front)
		var lip := front and y == r_mouth + 1 and ax <= 1
		if beard == "goatee":
			jaw_reg = front and (y <= r_mouth - 1 and ax <= 2 or y == r_mouth + 1 and ax <= 2)
		if jaw_reg or lip:
			var amt := 0.42 if beard == "stubble" else 0.75
			if y <= 2 and q.z > -0.03:
				amt *= 0.6
			return _beard_col(x, y, z, amt)
	return _j(c, x, y, z, 0.02)


## Eyes, brows, nose, mouth: the expression. -1 where nothing is painted.
func _features(q: Vector3, x: int, y: int, z: int, ax: int, c: int) -> int:
	var eyes := str(face.get("eyes", "stare"))
	var brows := str(face.get("brows", "flat"))
	var mouth := str(face.get("mouth", "thin"))
	var iris := int(face.get("iris", 0x3a4a40))
	var white := VoxelArt.mix(0xe2dccd, 0xd8b0a0, float(face.get("bloodshot", 0.2)))
	var left := x < 0
	var ci := c_iris
	var shift := 0
	if eyes == "dart":
		shift = 1 if face.get("look_dir", 1) == 1 else -1
	elif eyes == "vacant" and left:
		shift = -1                                                 # one eye wanders outward
	var e_mode := eyes
	if eyes == "uneven":
		e_mode = "wide" if left else "squint"
	var ix := x - (ci if x > 0 else -ci)                         # column relative to the iris centre
	var near_eye := ax >= ci - 1 and ax <= ci + 1
	var lid := LASH_C
	match e_mode:
		"wide":
			if near_eye and y == r_eye:
				return iris if ix == shift else white
			if near_eye and y == r_eye + 1:
				return white if absi(ix) <= 1 else _mix(c, lid, 0.2)  # white above the iris
			if near_eye and y == r_eye + 2:
				return _mix(c, lid, 0.45)
		"stare":
			if near_eye and y == r_eye:
				return 0x181212 if ix == shift else white            # a pinprick pupil
			if near_eye and y == r_eye + 1:
				return _mix(c, lid, 0.25)
		"squint":
			if near_eye and y == r_eye:
				return iris if ix == shift else _mix(c, lid, 0.55)
			if near_eye and y == r_eye + 1:
				return _mix(c, lid, 0.5)
		_:
			# vacant, dart: Eli's eye, a pale or shifted iris
			if near_eye and y == r_eye:
				var ic := iris if eyes != "vacant" else _mix(iris, 0xa8b0b0, 0.5)
				return ic if ix == shift else white
			if near_eye and y == r_eye + 1:
				return _mix(c, lid, 0.42 if ix == 0 else 0.25)
	# brows
	var bc := _sc(hair_col, 0.8)
	if float(hair.get("grey", 0.0)) > 0.5:
		bc = _mix(bc, 0xa09a92, 0.5)
	var b_mode := brows
	if brows == "uneven":
		b_mode = "raised" if left else "knit"
	var brow_y := r_brow + (1 if e_mode == "wide" else 0)
	match b_mode:
		"raised":
			if (y == brow_y + 1 and ax >= 2 and ax <= ci) or (y == brow_y and ax == ci + 1) or (y == brow_y - 1 and ax == ci + 2):
				return _j(bc, x, y, z, 0.05)
		"knit":
			if (y == brow_y - 1 and ax >= 1 and ax <= 2) or (y == brow_y and ax >= 3 and ax <= ci + 2):
				return _j(bc, x, y, z, 0.05)
		"worried":
			if (y == brow_y + 1 and ax >= 1 and ax <= 2) or (y == brow_y and ax >= 3 and ax <= ci + 1) or (y == brow_y - 1 and ax == ci + 2):
				return _j(bc, x, y, z, 0.05)
		_:
			if (y == brow_y and ax >= 2 and ax <= ci + 1) or (y == brow_y - 1 and ax == ci + 2):
				return _j(bc, x, y, z, 0.05)
	if brow > 1.15 and y == brow_y + 1 and ax >= 2 and ax <= ci + 1 and _h(x, y, z, 3) > 0.4:
		return _j(bc, x, y, z, 0.05)                                # bushy
	# nostrils
	if y == r_nose - 1 and ax == 1 and q.z < -0.085:
		return _mix(skin_dk, 0x5a3028, 0.45)
	# mouth
	var dark := 0x2a1414
	var lip := VoxelArt.mix(skin_dk, 0x8a4a48, 0.35)
	var teeth := 0xcfc6ac
	match mouth:
		"slack":
			if (y == r_mouth or y == r_mouth - 1) and ax <= 1:
				return dark if y == r_mouth - 1 or ax == 1 else _mix(teeth, dark, 0.5)
			if y == r_mouth and ax == 2:
				return _mix(skin_dk, dark, 0.5)
			if y == r_mouth - 2 and ax <= 1:
				return lip
			if y == r_mouth + 1 and ax <= 1:
				return _mix(c, lip, 0.6)
		"grimace":
			if y == r_mouth and ax <= 2:
				return teeth if ax < 2 or posmod(x, 2) == 0 else _sc(teeth, 0.8)
			if (y == r_mouth + 1 or y == r_mouth - 1) and ax <= 2:
				return _mix(lip, dark, 0.45)
			if y == r_mouth and ax == 3:
				return _mix(skin_dk, dark, 0.6)
		"mutter":
			if y == r_mouth and ax <= 1:
				return dark if ax == 0 else _mix(skin_dk, dark, 0.6)
			if y == r_mouth - 1 and ax == 0:
				return _mix(lip, dark, 0.4)
		"grin":
			if y == r_mouth and ax <= 2:
				return teeth if ax <= 1 else dark
			if y == r_mouth + 1 and ax == 3:
				return _mix(skin_dk, dark, 0.55)
			if y == r_mouth - 1 and ax <= 2:
				return lip
		_:      # thin: pressed lips, the corners pulled down
			if y == r_mouth and ax <= 2:
				return _mix(skin_dk, 0x4a2520, 0.55)
			if y == r_mouth - 1 and ax == 3:
				return _mix(skin_dk, 0x4a2520, 0.35)
	return -1


const LASH_C := 0x2a1c15
