class_name RegionState
extends RefCounted
## What the run knows and has changed outside the lot (SPEC-003 §3). Owner: X.
## Saved inside GameState. Foundation version: discovery, depletion, flags.

## id -> true. Places the player knows about (shown with names on the map).
var discovered := {}
## id -> 0..1, how much of the place's loot is left (1 = untouched).
var stock := {}
## id -> {visits, last_day, flags...}: persistent mission consequences.
var notes := {}
## Layout identity of the region map (so a save notices a different map).
var layout := "region-v1"
## The destination chosen on the map (the expedition screen preselects it).
var planned := ""
var planned_purpose := ""

const START_KNOWN := ["homes", "convenience", "grocery", "hardware", "clinic", "diner"]


static func new_region() -> RegionState:
	var r := RegionState.new()
	for id in START_KNOWN:
		r.discovered[id] = true
	return r


func is_discovered(id: String) -> bool:
	return discovered.get(id, false)


func discover(id: String) -> void:
	if RegionLocations.has(id):
		discovered[id] = true


func stock_of(id: String) -> float:
	return clampf(float(stock.get(id, 1.0)), 0.0, 1.0)


func to_dict() -> Dictionary:
	return {"discovered": discovered.keys(), "stock": stock.duplicate(), "notes": notes.duplicate(true),
		"layout": layout, "planned": planned, "planned_purpose": planned_purpose}


static func from_dict(d) -> RegionState:
	var r := RegionState.new_region()
	if typeof(d) != TYPE_DICTIONARY:
		return r
	var disc = d.get("discovered", [])
	if typeof(disc) == TYPE_ARRAY:
		for id in disc:
			r.discover(str(id))
	var st = d.get("stock", {})
	if typeof(st) == TYPE_DICTIONARY:
		for id in st:
			if RegionLocations.has(str(id)):
				var v := float(st[id]) if typeof(st[id]) in [TYPE_INT, TYPE_FLOAT] else 1.0
				r.stock[str(id)] = clampf(v if is_finite(v) else 1.0, 0.0, 1.0)
	var n = d.get("notes", {})
	if typeof(n) == TYPE_DICTIONARY:
		r.notes = (n as Dictionary).duplicate(true)
	r.layout = str(d.get("layout", r.layout))
	r.planned = str(d.get("planned", ""))
	r.planned_purpose = str(d.get("planned_purpose", ""))
	return r
