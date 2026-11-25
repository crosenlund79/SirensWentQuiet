class_name RoomCache
extends RefCounted
## Experiment 007 (N): the rooms (HouseRooms.find) and windows of each storey
## world, found on demand and kept until that world's structure changes
## (structure_changed: walls built, broken or repaired, doors opened or
## closed, objects placed). Shared by room visibility and noise exposure; works
## for the home's storeys and for POI worlds alike. Never recomputed per frame:
## only when asked after a change.

var runs := 0                     ## HouseRooms.find calls (tests, diagnostics)
var last_ms := 0.0
var _maps := {}                   ## "world id:storey" -> HouseRooms.find()
var _wins := {}                   ## "world id:storey" -> HouseRooms.windows()
var _dirty := {}                  ## world id -> true
var _watched := {}                ## world id -> true


## The rooms of `world` (storey `storey`), fresh after any structure change.
func map_of(world: HouseWorld, storey: int) -> Dictionary:
	if world == null:
		return {}
	var key := _key(world, storey)
	_refresh(world)
	if not _maps.has(key):
		var t0 := Time.get_ticks_usec()
		_maps[key] = HouseRooms.find(world, storey)
		last_ms = (Time.get_ticks_usec() - t0) / 1000.0
		runs += 1
	return _maps[key]


func windows_of(world: HouseWorld, storey: int) -> Array:
	if world == null:
		return []
	var key := _key(world, storey)
	_refresh(world)
	if not _wins.has(key):
		_wins[key] = HouseRooms.windows(world, storey)
	return _wins[key]


## True if `world` changed since its rooms were last found.
func is_dirty(world: HouseWorld) -> bool:
	return world != null and (_dirty.has(world.get_instance_id()) or not _watched.has(world.get_instance_id()))


## Forgets one world's rooms (null: every world's).
func invalidate(world: HouseWorld = null) -> void:
	if world == null:
		_maps.clear()
		_wins.clear()
		_dirty.clear()
		return
	_dirty[world.get_instance_id()] = true


func _key(world: HouseWorld, storey: int) -> String:
	return "%d:%d" % [world.get_instance_id(), storey]


func _refresh(world: HouseWorld) -> void:
	var id := world.get_instance_id()
	if not _watched.has(id):
		_watched[id] = true
		world.structure_changed.connect(_on_changed.bind(id))
	if _dirty.has(id):
		_dirty.erase(id)
		var prefix := "%d:" % id
		for k in _maps.keys():
			if (k as String).begins_with(prefix):
				_maps.erase(k)
		for k in _wins.keys():
			if (k as String).begins_with(prefix):
				_wins.erase(k)


func _on_changed(id: int) -> void:
	_dirty[id] = true
