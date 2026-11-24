class_name RegionState
extends RefCounted
## What the run knows and has changed outside the lot (SPEC-003 §3). Owner: X.
## Saved inside GameState.to_dict()["region"]. Expeditions change it (once per
## result, `apply_result`); the map reads it and sets the plan.
##
## Stock: `stock[id]` is the level (0..1) set at the last visit, on day
## `notes[id].last_day`. It recovers slowly afterwards (ExpeditionData
## `regen` per day, up to 1); `stock_on(id, day)` gives today's level. Places
## never visited are at 1.
##
## Notes: id -> {"visits": int, "last_day": int, "flags": {flag: until_day}}.
## Flags (ExpeditionData.FLAGS: "guarded", "cleared") are lasting consequences
## that change a place's danger until (and including) their day.

const START_KNOWN := ["homes", "convenience", "grocery", "hardware", "clinic", "diner"]
const APPLIED_KEPT := 64
const MAX_DAY := 100000
const PURPOSE_MAX := 40

## id -> true. Places the player knows about (shown with names on the map).
var discovered := {}
## id -> 0..1, how much of the place's loot was left after the last visit.
var stock := {}
## id -> {visits, last_day, flags}: persistent mission consequences.
var notes := {}
## Layout identity of the region map (so a save notices a different map).
var layout := "region-v1"
## The destination chosen on the map (the expedition screen preselects it).
## planned_purpose: an approach id, "targeted:<item>" for targeted collection.
var planned := ""
var planned_purpose := ""
## Result ids whose region consequences were applied (the once-only guard).
var applied := []


static func new_region() -> RegionState:
	var r := RegionState.new()
	for id in START_KNOWN:
		r.discovered[id] = true
	return r


# --- discovery -------------------------------------------------------------------------

func is_discovered(id: String) -> bool:
	var v = discovered.get(id, false)
	return typeof(v) == TYPE_BOOL and v


## Returns true if the place was new.
func discover(id: String) -> bool:
	if not RegionLocations.has(id) or is_discovered(id):
		return false
	discovered[id] = true
	return true


## Developer tool: every place becomes known.
func discover_all() -> void:
	for id in RegionLocations.ids():
		discovered[id] = true


func undiscovered() -> Array:
	var out := []
	for id in RegionLocations.ids():
		if not is_discovered(id):
			out.append(id)
	return out


# --- stock ----------------------------------------------------------------------------

## The stored level (as left by the last visit, without recovery).
func stock_of(id: String) -> float:
	return clampf(float(stock.get(id, 1.0)), 0.0, 1.0)


## Today's level: the stored level plus the place's recovery since the last visit.
func stock_on(id: String, day: int) -> float:
	if not stock.has(id):
		return 1.0
	var since := maxi(day - last_day(id), 0)
	return clampf(stock_of(id) + ExpeditionData.regen_per_day(id) * float(since), 0.0, 1.0)


func set_stock(id: String, value: float, day: int) -> void:
	if not RegionLocations.has(id) or not is_finite(value):
		return
	stock[id] = clampf(value, 0.0, 1.0)
	_note(id)["last_day"] = clampi(day, 0, MAX_DAY)


# --- notes and flags ------------------------------------------------------------------

func _note(id: String) -> Dictionary:
	if not notes.has(id):
		notes[id] = {"visits": 0, "last_day": 0, "flags": {}}
	return notes[id]


func visits(id: String) -> int:
	return int(notes.get(id, {}).get("visits", 0))


func last_day(id: String) -> int:
	return int(notes.get(id, {}).get("last_day", 0))


## The last day a flag holds (0 = not set).
func flag_until(id: String, flag: String) -> int:
	return int(notes.get(id, {}).get("flags", {}).get(flag, 0))


func has_flag(id: String, flag: String, day: int) -> bool:
	return flag_until(id, flag) >= day and flag_until(id, flag) > 0


## Sets a flag until `until_day` and clears the flags it replaces
## (ExpeditionData.FLAGS[flag].clears).
func set_flag(id: String, flag: String, until_day: int) -> void:
	if not RegionLocations.has(id) or flag == "":
		return
	var flags: Dictionary = _note(id)["flags"]
	for other in ExpeditionData.FLAGS.get(flag, {}).get("clears", []):
		flags.erase(other)
	flags[flag] = clampi(until_day, 0, MAX_DAY)


# --- the map's plan ---------------------------------------------------------------------

## The map: plan an expedition (purpose: an approach id or "targeted:<item>").
## An unknown id clears the plan.
func plan(id: String, purpose := "general") -> void:
	if not RegionLocations.has(id):
		clear_plan()
		return
	planned = id
	planned_purpose = purpose.left(PURPOSE_MAX)


func clear_plan() -> void:
	planned = ""
	planned_purpose = ""


# --- expedition results ---------------------------------------------------------------------

## Applies an expedition result's region consequences once (guarded by
## result["id"]): the place becomes known and visited, its stock is set to
## `stock_after` on the return `day`, `marks` ({flag: until_day}) are set,
## `discovered` ids become known, and a plan for this place is used up.
## Returns true when applied. Untrusted input is tolerated (ignored fields).
func apply_result(result) -> bool:
	if typeof(result) != TYPE_DICTIONARY:
		return false
	var rid := str(result.get("id", "")) if result.get("id") != null else ""
	if rid == "" or rid in applied:
		return false
	applied.append(rid)
	while applied.size() > APPLIED_KEPT:
		applied.pop_front()
	var loc := str(result.get("location", result.get("destination", "")))
	var day := _num(result.get("day"), -1.0)
	if day < 0.0:
		var back := _num(result.get("return_at"), -1.0)
		day = floorf(back / 1440.0) + 1.0 if back >= 0.0 else float(last_day(loc))
	var d := clampi(int(day), 0, MAX_DAY)
	if RegionLocations.has(loc):
		discover(loc)
		var before := stock_on(loc, d)
		var n := _note(loc)
		n["visits"] = int(n.get("visits", 0)) + 1
		n["last_day"] = d
		var s := _num(result.get("stock_after"), NAN)
		if is_finite(s):
			stock[loc] = clampf(s, 0.0, 1.0)
		elif stock.has(loc):
			stock[loc] = before     # no new level: keep today's (recovered) level
		var marks = result.get("marks", {})
		if typeof(marks) == TYPE_DICTIONARY:
			for f in marks:
				var until := _num(marks[f], -1.0)
				if until >= 0.0:
					set_flag(loc, str(f), int(until))
	var disc = result.get("discovered", [])
	if typeof(disc) == TYPE_ARRAY:
		for id in disc:
			discover(str(id))
	if planned != "" and planned == loc:
		clear_plan()
	return true


static func _num(v, fallback: float) -> float:
	if typeof(v) == TYPE_INT:
		return float(v)
	if typeof(v) == TYPE_FLOAT and is_finite(v):
		return v
	return fallback


# --- persistence ------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var disc := discovered.keys()
	disc.sort()
	return {"discovered": disc, "stock": stock.duplicate(), "notes": notes.duplicate(true),
		"layout": layout, "planned": planned, "planned_purpose": planned_purpose,
		"applied": applied.duplicate()}


## Restores from untrusted data: unknown ids, non-numbers and wrong types are
## dropped; numbers are clamped. Never fails (garbage gives a new region).
static func from_dict(d) -> RegionState:
	var r := RegionState.new_region()
	if typeof(d) != TYPE_DICTIONARY:
		return r
	var disc = d.get("discovered", [])
	if typeof(disc) == TYPE_ARRAY:
		for id in disc:
			if typeof(id) == TYPE_STRING or typeof(id) == TYPE_STRING_NAME:
				r.discover(str(id))
	elif typeof(disc) == TYPE_DICTIONARY:
		for id in disc:
			if typeof(disc[id]) == TYPE_BOOL and disc[id]:
				r.discover(str(id))
	var st = d.get("stock", {})
	if typeof(st) == TYPE_DICTIONARY:
		for id in st:
			if RegionLocations.has(str(id)):
				var v := _num(st[id], 1.0)
				r.stock[str(id)] = clampf(v, 0.0, 1.0)
	var n = d.get("notes", {})
	if typeof(n) == TYPE_DICTIONARY:
		for id in n:
			var e = n[id]
			if not RegionLocations.has(str(id)) or typeof(e) != TYPE_DICTIONARY:
				continue
			var note := {"visits": clampi(int(_num(e.get("visits"), 0.0)), 0, MAX_DAY),
				"last_day": clampi(int(_num(e.get("last_day"), 0.0)), 0, MAX_DAY), "flags": {}}
			var fl = e.get("flags", {})
			if typeof(fl) == TYPE_DICTIONARY:
				for f in fl:
					var until := _num(fl[f], -1.0)
					if (typeof(f) == TYPE_STRING or typeof(f) == TYPE_STRING_NAME) and until >= 0.0:
						note["flags"][str(f).left(32)] = clampi(int(until), 0, MAX_DAY)
			r.notes[str(id)] = note
	var lay = d.get("layout", r.layout)
	r.layout = str(lay).left(64) if typeof(lay) == TYPE_STRING else r.layout
	var p = d.get("planned", "")
	r.planned = str(p) if typeof(p) == TYPE_STRING and RegionLocations.has(str(p)) else ""
	var pp = d.get("planned_purpose", "")
	r.planned_purpose = str(pp).left(PURPOSE_MAX) if typeof(pp) == TYPE_STRING and r.planned != "" else ""
	var a = d.get("applied", [])
	if typeof(a) == TYPE_ARRAY:
		for x in a:
			if typeof(x) == TYPE_STRING and x != "":
				r.applied.append(x)
		r.applied = r.applied.slice(maxi(r.applied.size() - APPLIED_KEPT, 0))
	return r
