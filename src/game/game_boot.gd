class_name GameBoot
extends RefCounted
## Exp 009 (R): the pieces of the game scene's staged boot (survival_game.gd
## `_boot_staged`; the loading screen is src/ui/loading_screen.gd).
##
## Jobs share one shape: `step() -> bool` (true = done), `progress` (0..1)
## and `stage` (a key of TEXTS). They run to the end at once in a normal boot
## (the existing tests) or a step at a time behind the loading screen.
##
## - SiteJob: a POI's place. The layout first: through the generator's staged
##   API (`PoiDefs.begin_def(id, state)` when it exists, else
##   `PoiGenerator.begin(DailySites.setup(state, id))` for a site that isn't
##   hand-made), otherwise `PoiDefs.get_def` as one step. Then the checks (an
##   unknown place, no definition, an invalid layout: `error`), then the
##   world (PoiSite.prepare_world) and its build (PoiWorld.begin_build) step
##   by step. The world doesn't process until it is built.
## - ChunkJob: the voxel chunks a house or a storey left unbuilt while
##   HouseWorld.defer_chunks was on, one chunk per step.
##
## Stage weights (PLANS) are rough shares of a headless boot: meshing the
## voxel chunks dominates every arrival.

const TEXTS := {
	"read": "Reading the save…",
	"layout": "Laying out the place…", "rooms": "Dividing the rooms…", "doors": "Fitting doors and windows…",
	"interior": "Preparing interior…", "furniture": "Placing furniture…", "containers": "Populating containers…",
	"loot": "Populating containers…", "inhabitants": "Preparing inhabitants…", "exterior": "Preparing the surroundings…",
	"house": "Restoring the house…", "chunks": "Building the house…", "storeys": "Restoring the storeys…",
	"assemble": "Preparing the house…", "final": "Final preparation…",
}

## [[stage, weight, text], ...] after the save is read (LoadingScreen.plan).
const PLANS := {
	"site": [["site", 0.78, "Preparing interior…"], ["inhabitants", 0.17, "Preparing inhabitants…"], ["final", 0.05, "Final preparation…"]],
	"home": [["house", 0.22, "Restoring the house…"], ["chunks", 0.48, "Building the house…"], ["assemble", 0.16, "Preparing the house…"],
		["storeys", 0.09, "Restoring the storeys…"], ["final", 0.05, "Final preparation…"]],
	"new": [["house", 0.2, "Building the house…"], ["chunks", 0.5, "Building the house…"], ["assemble", 0.25, "Preparing the house…"],
		["final", 0.05, "Final preparation…"]],
}

## What a boot of each kind is expected to take (ms) before one was timed
## here: about a headless boot's time (LoadingScreen.expect).
const EXPECTED_MS := {"site": 450, "site_save": 450, "home": 550, "carry_home": 550, "new": 900}

## Tests: a place whose layout counts as invalid (the failure path).
static var debug_invalid_site := ""

static var _took := {}                  ## kind -> the last staged boot's time (ms)

static var _scripts := {}


static func plan_for(kind: String) -> Array:
	if kind in ["site", "site_save"]:
		return PLANS["site"]
	return PLANS["new"] if kind == "new" else PLANS["home"]


## How long a staged boot of `kind` should take (the last one, else EXPECTED_MS).
static func expected_ms(kind: String) -> float:
	return float(_took.get(kind, EXPECTED_MS.get(kind, 0)))


static func took(kind: String, ms: float) -> void:
	_took[kind] = ms


## The global class `cls` (e.g. "PoiGenerator"), or null while it doesn't exist.
static func global_script(cls: String) -> Script:
	if not _scripts.has(cls):
		var found: Script = null
		for c in ProjectSettings.get_global_class_list():
			if str(c["class"]) == cls:
				found = load(str(c["path"]))
				break
		_scripts[cls] = found
	return _scripts[cls]


static func _has_static(s: Script, method: String) -> bool:
	if s == null:
		return false
	for m in s.get_script_method_list():
		if str(m["name"]) == method:
			return true
	return false


static func _arg_count(s: Script, method: String) -> int:
	for m in s.get_script_method_list():
		if str(m["name"]) == method:
			return (m["args"] as Array).size()
	return 0


## PoiDefs.get_def(id) or, once it takes the run, get_def(id, state).
static func def_of(id: String, state: GameState) -> Dictionary:
	var s: Script = PoiDefs
	var d: Variant = s.call("get_def", id, state) if _arg_count(s, "get_def") >= 2 else PoiDefs.get_def(id)
	return d if typeof(d) == TYPE_DICTIONARY else {}


## The generator's staged context for `id`, or null (a hand-made place, or
## no generator yet): see the header.
static func begin_generation(id: String, state: GameState) -> Object:
	var defs: Script = PoiDefs
	if _has_static(defs, "begin_def"):
		var c: Variant = defs.call("begin_def", id, state)
		return c if c is Object and (c as Object).has_method("step") else null
	var gen := global_script("PoiGenerator")
	var daily := global_script("DailySites")
	if not _has_static(gen, "begin") or not _has_static(daily, "setup"):
		return null
	var setup: Variant = daily.call("setup", state, id)
	if typeof(setup) != TYPE_DICTIONARY or (setup as Dictionary).is_empty() or bool((setup as Dictionary).get("hand_made", true)):
		return null
	var ctx: Variant = gen.call("begin", setup)
	return ctx if ctx is Object and (ctx as Object).has_method("step") else null


## Why the place `id` can't be built from `def` ("" = it can).
static func layout_error(id: String, def: Dictionary) -> String:
	var name := RegionLocations.name_of(id) if RegionLocations.has(id) else id
	if def.is_empty():
		return "%s has no description." % name
	var L: Variant = def.get("layout")
	if typeof(L) != TYPE_DICTIONARY or (L as Dictionary).is_empty() or id == debug_invalid_site:
		return "%s has no valid layout." % name
	var l: Dictionary = L
	if typeof(l.get("floors", [])) != TYPE_ARRAY or typeof(l.get("walls", [])) != TYPE_ARRAY:
		return "%s has a damaged layout." % name
	if (l.get("floors", []) as Array).is_empty() and (l.get("walls", []) as Array).is_empty() and not l.get("outdoor", false):
		return "%s has no building." % name
	var e: Variant = l.get("entry", Vector2(7, 11))
	if not (e is Vector2) or not (e as Vector2).is_finite():
		return "%s has no way in." % name
	return ""


## Every VoxelWorld under `root` left unbuilt (HouseWorld.defer_chunks).
static func unbuilt(root: Node) -> Array:
	var out := []
	_collect(root, out)
	return out


static func _collect(n: Node, out: Array) -> void:
	if n is VoxelWorld and (n as VoxelWorld).needs_build():
		out.append(n)
	for c in n.get_children():
		_collect(c, out)


## A POI's place, step by step (see the header).
class SiteJob extends RefCounted:
	const GEN_SHARE := 0.3              ## of the job when the generator runs (else 0.03 for the definition)

	var stage := "layout"
	var progress := 0.0
	var error := ""
	var world: PoiWorld
	var gen: Object                     ## the generator's context (generated sites)
	var build: Object                   ## PoiWorld.BuildJob
	var steps := 0
	var game: Node
	var id := ""
	var _phase := 0
	var _share := 0.03

	func _init(g: Node, site_id: String) -> void:
		game = g
		id = site_id

	func step() -> bool:
		steps += 1
		match _phase:
			0:
				if not PoiDefs.has(id):
					error = "the place %s could not be built." % (RegionLocations.name_of(id) if RegionLocations.has(id) else id)
					return _end()
				gen = GameBoot.begin_generation(id, game.state)
				if gen != null:
					_share = GEN_SHARE
				_phase = 1 if gen != null else 2
				return false
			1:
				if gen.step():
					_phase = 2
				var s := str(gen.get("stage"))
				stage = s if s != "" else "layout"
				progress = _share * clampf(float(gen.get("progress")), 0.0, 1.0)
				return false
			2:
				var err := GameBoot.layout_error(id, GameBoot.def_of(id, game.state))
				if err != "":
					error = "the place could not be prepared: " + err
					return _end()
				world = PoiSite.prepare_world(id, game)
				if world == null:
					error = "the place %s could not be built." % RegionLocations.name_of(id)
					return _end()
				world.process_mode = Node.PROCESS_MODE_DISABLED     # nothing runs on a half-built place
				build = world.begin_build()
				stage = "interior"
				progress = _share
				_phase = 3
				return false
			3:
				var done: bool = build.step()
				stage = str(build.get("stage"))
				progress = _share + (1.0 - _share) * float(build.get("progress"))
				if done:
					world.process_mode = Node.PROCESS_MODE_INHERIT
					return _end()
				return false
		return true

	func _end() -> bool:
		_phase = 4
		progress = 1.0
		return true


## The unbuilt chunks of `worlds` (VoxelWorld), one per step.
class ChunkJob extends RefCounted:
	var stage := "chunks"
	var progress := 0.0
	var steps := 0
	var _list := []
	var _i := 0

	func _init(worlds: Array) -> void:
		for vw in worlds:
			if vw is VoxelWorld:
				for c in (vw as VoxelWorld).chunk_coords():
					_list.append([vw, c])

	func step() -> bool:
		if _i >= _list.size():
			progress = 1.0
			return true
		var e: Array = _list[_i]
		if is_instance_valid(e[0]):
			(e[0] as VoxelWorld).build_chunk(e[1])
		_i += 1
		steps += 1
		progress = float(_i) / float(_list.size())
		return _i >= _list.size()
