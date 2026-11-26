class_name HumanoidBody
extends RefCounted
## Experiment 011: proportions of a humanoid (Eli-style voxel people).
##
## A body is a small dictionary of high-level parameters (all optional, see
## DEFAULTS): height in metres; sex 0 (male) .. 1 (female); weight 0 (thin)
## .. 1 (heavy); muscle 0 .. 1; age 0 (young) .. 1 (old); and multipliers
## for shoulders, hips, legs, arms, neck, hands, feet, the head (size,
## width, height, depth) and the face (jaw, chin, cheeks, nose, nose_w,
## brow, ears, eyes = eye spacing). belly, bust and hump are derived from
## weight / sex / age unless given. gaunt 0 .. 1 (Exp 011, the runner):
## starved below weight 0: wasted limbs, a shallow ribcage, a sunken belly,
## bony shoulders and a thin neck (and in the sculpt hollow cheeks, sunken
## eyes, ribs); 0 leaves every other look exactly as it was.
## weight / sex / age unless given. Beyond the ordinary range (Exp 011,
## the brute): "bulk" multiplies the girth of neck, deltoids, limbs and
## the chest's depth (1 = ordinary), "traps" (0 .. 1) adds a slope of
## trapezius from the neck to the shoulders.
##
## derive() turns them into the skeleton the rig uses (joint offsets, bone
## lengths) and the girths the sculpt uses (radii of ribcage, belly, hips,
## limbs ...). Everything is real geometry: a heavy body has a belly and
## thicker limbs, a woman narrower shoulders and wider hips, an old man a
## hump and thinner arms. Nothing is a uniform scale of another mesh.
## Joint layout and spaces match EliRig: the character faces -Z, his right
## is +X, the soles at y 0, limbs hang along -Y.

const DEFAULTS := {
	"height": 1.78, "sex": 0.0, "weight": 0.3, "muscle": 0.4, "age": 0.4,
	"shoulders": 1.0, "hips": 1.0, "legs": 1.0, "arms": 1.0, "neck": 1.0, "hands": 1.0, "feet": 1.0,
	"head": 1.0, "head_w": 1.0, "head_h": 1.0, "head_d": 1.0,
	"jaw": 1.0, "chin": 0.5, "cheeks": 0.5, "nose": 1.0, "nose_w": 1.0, "brow": 1.0, "ears": 1.0, "eyes": 1.0,
	"belly": -1.0, "bust": -1.0, "hump": -1.0,
	"gaunt": 0.0,
	"bulk": 1.0, "traps": 0.0,
}


static func param(body: Dictionary, k: String) -> float:
	return float(body.get(k, DEFAULTS[k]))


## The derived skeleton and girths (see the file header).
static func derive(body: Dictionary) -> Dictionary:
	var h := param(body, "height")
	var S := clampf(param(body, "sex"), 0.0, 1.0)
	var W := clampf(param(body, "weight"), 0.0, 1.0)
	var M := clampf(param(body, "muscle"), 0.0, 1.0)
	var A := clampf(param(body, "age"), 0.0, 1.0)
	var k := h / 1.81
	var B := maxf(param(body, "bulk"), 0.1)
	var o := {"k": k, "sex": S, "weight": W, "muscle": M, "age": A, "traps": clampf(param(body, "traps"), 0.0, 1.5)}
	# head: smaller people have relatively larger heads
	var hh := param(body, "head_h")
	var HS := 1.15 * param(body, "head") * pow(k, 0.45) * (1.0 - 0.03 * S)
	o["HS"] = HS
	o["head_w"] = param(body, "head_w") * (1.0 - 0.04 * S + 0.05 * W)
	o["head_h"] = hh
	o["head_d"] = param(body, "head_d")
	for f in ["chin", "cheeks", "brow", "eyes"]:
		o[f] = param(body, f)
	o["jaw"] = param(body, "jaw") * (1.0 - 0.12 * S + 0.06 * W)
	o["brow"] = float(o["brow"]) * (1.0 - 0.45 * S)
	o["nose"] = param(body, "nose") * (1.0 + 0.12 * A - 0.08 * S)
	o["nose_w"] = param(body, "nose_w") * (1.0 + 0.15 * A + 0.15 * W - 0.1 * S)
	o["ears"] = param(body, "ears") * (1.0 + 0.22 * A - 0.12 * S)
	# heights: soles 0 .. pelvis .. waist .. neck base .. crown
	var neck_world := h - 0.3 * hh * HS
	var pelvis_y := 0.93 * k * param(body, "legs") * (1.0 + 0.01 * S - 0.015 * A)
	var waist_y := 0.07 * k
	var neck_c := neck_world - pelvis_y - waist_y
	var T := neck_c / 0.45                     # torso vertical scale (Eli = 1)
	o["T"] = T
	o["pelvis_y"] = pelvis_y
	o["waist"] = Vector3(0.0, waist_y, 0.0)
	var nk := 0.012 * k + 0.035 * k * clampf(A - 0.5, 0.0, 1.0)      # old: the head juts forward
	o["neck"] = Vector3(0.0, neck_c, 0.004 * k - nk)
	var hip_drop := 0.035 * k
	var feet := param(body, "feet") * (1.0 - 0.1 * S)
	var ankle_y := 0.095 * k * sqrt(feet)
	var leg := pelvis_y - hip_drop - ankle_y
	o["thigh"] = leg * 0.506
	o["shin"] = leg * 0.494
	o["ankle_y"] = ankle_y
	var hips := param(body, "hips")
	o["hip"] = Vector3(0.088 * k * hips * (1.0 + 0.12 * S + 0.12 * W), -hip_drop, 0.0)
	o["stance_x"] = float((o["hip"] as Vector3).x) + 0.017 * k
	# torso girths
	var cw := k * param(body, "shoulders") * (1.0 + 0.12 * M + 0.16 * W - 0.13 * S)
	o["chest_c"] = Vector3(0.0, 0.265 * T, 0.0)
	o["chest_r"] = Vector3(0.158 * cw, 0.19 * T, 0.105 * k * (1.0 + 0.2 * W + 0.08 * M) * sqrt(B))
	o["abd_c"] = Vector3(0.0, 0.06 * T, 0.005 * k)
	o["abd_r"] = Vector3(0.138 * k * (1.0 + 0.4 * W - 0.1 * S + 0.04 * A), 0.15 * T, 0.1 * k * (1.0 + 0.42 * W))
	var belly := param(body, "belly")
	if belly < 0.0:
		belly = clampf((W - 0.25) * 1.4, 0.0, 1.0) * (1.0 + 0.4 * A) * (1.0 - 0.4 * S)
	o["belly"] = belly
	var bust := param(body, "bust")
	if bust < 0.0:
		bust = S * (0.75 + 0.45 * W)
	o["bust"] = bust
	var hump := param(body, "hump")
	if hump < 0.0:
		hump = clampf((A - 0.6) * 2.5, 0.0, 1.0)
	o["hump"] = hump
	o["shoulder"] = Vector3(0.162 * cw * (1.0 + 0.03 * M), 0.385 * T - 0.012 * k * hump, 0.01 * k + 0.02 * k * hump)
	o["sh_r"] = 0.056 * k * (1.0 + 0.22 * M + 0.22 * W - 0.14 * S) * B
	o["neck_len"] = param(body, "neck")
	o["neck_r"] = 0.047 * k * (1.0 + 0.25 * W + 0.2 * M - 0.16 * S) * B
	o["hips_c"] = Vector3(0.0, -0.035 * k, 0.006 * k)
	o["hips_r"] = Vector3(0.142 * k * hips * (1.0 + 0.2 * S + 0.3 * W), 0.1 * k, 0.104 * k * (1.0 + 0.14 * S + 0.3 * W))
	# limbs
	var a := (1.0 + 0.42 * W + 0.25 * M - 0.15 * S - 0.1 * A) * B
	var arms := param(body, "arms")
	o["upper_arm"] = 0.28 * k * arms
	o["forearm"] = 0.25 * k * arms
	o["arm_r0"] = 0.054 * k * a
	o["arm_r1"] = 0.045 * k * a
	o["farm_r0"] = 0.044 * k * a
	o["farm_r1"] = 0.034 * k * (0.75 + 0.25 * a)
	o["wrist_r"] = 0.027 * k * (0.85 + 0.15 * a)
	var l := (1.0 + 0.4 * W + 0.15 * M + 0.1 * S - 0.12 * A) * pow(B, 0.75)
	o["thigh_r0"] = 0.08 * k * l
	o["thigh_r1"] = 0.056 * k * l
	o["knee_r"] = 0.047 * k * (0.8 + 0.2 * l)
	o["calf_r"] = 0.05 * k * l
	o["ankle_r"] = 0.03 * k * (0.9 + 0.1 * l)
	o["hand"] = k * param(body, "hands") * (1.0 - 0.12 * S + 0.08 * M)
	o["foot"] = k * feet
	var G := clampf(param(body, "gaunt"), 0.0, 1.0)
	o["gaunt"] = G
	if G > 0.0:
		_waste(o, G)
	return o


## Starvation (gaunt G > 0): girths shrink, the joints stay (knobbly knees,
## bony wrists and shoulders); the skeleton (bone lengths) is unchanged.
static func _waste(o: Dictionary, G: float) -> void:
	for kk in ["arm_r0", "arm_r1", "farm_r0", "thigh_r0", "thigh_r1", "calf_r"]:
		o[kk] = float(o[kk]) * (1.0 - 0.4 * G)
	o["farm_r1"] = float(o["farm_r1"]) * (1.0 - 0.3 * G)
	o["wrist_r"] = float(o["wrist_r"]) * (1.0 - 0.12 * G)
	o["knee_r"] = float(o["knee_r"]) * (1.0 - 0.14 * G)
	o["ankle_r"] = float(o["ankle_r"]) * (1.0 - 0.12 * G)
	o["sh_r"] = float(o["sh_r"]) * (1.0 - 0.3 * G)
	o["neck_r"] = float(o["neck_r"]) * (1.0 - 0.3 * G)
	var c: Vector3 = o["chest_r"]
	o["chest_r"] = Vector3(c.x * (1.0 - 0.15 * G), c.y, c.z * (1.0 - 0.2 * G))
	var a: Vector3 = o["abd_r"]
	o["abd_r"] = Vector3(a.x * (1.0 - 0.26 * G), a.y, a.z * (1.0 - 0.36 * G))
	o["abd_c"] = (o["abd_c"] as Vector3) + Vector3(0.0, 0.0, 0.016 * float(o["k"]) * G)    # the belly sinks in
	var h: Vector3 = o["hips_r"]
	o["hips_r"] = Vector3(h.x * (1.0 - 0.18 * G), h.y, h.z * (1.0 - 0.22 * G))
	o["belly"] = 0.0
