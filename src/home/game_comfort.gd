extends Node
## Experiment 005 (C): comfort, rooms and mood in the running game. Created by
## SurvivalGame in _assemble() as `comfort` (the game_*.gd pattern).
##
## - Rooms (HouseRooms) per storey, recomputed when a storey's structure
##   changes (debounced: at most once per ROOMS_DEBOUNCE real seconds).
## - Comfort (HomeComfort) per room, recomputed when the rooms, the furniture,
##   the power, a light switch, the fireplace or the daylight bucket changes
##   (a cheap signature is polled every POLL seconds). Never per frame.
## - Mood (Mood): a step every Mood.UPDATE_MINUTES of game time, and memories
##   on events (invasions, a blast, sleep, coming home from an expedition).
## - GameState.rest_scale: the sleep bonus of the mood and of the room you
##   are in (so the bedroom you sleep in counts).
## - UI: a short line on the HUD ("Living room · Comfortable", "Mood:
##   Content"), and report() for the Home tab of the inventory (I).
## - F10 "Comfort & mood": dev_show, dev_mood, dev_recompute.
##
## API (SPEC §3): room_at(storey, plan_pos) -> {"label", "comfort",
## "level_name", "factors": [[text, delta]], ...}; house_comfort() -> float.
## Furniture comes from HouseWorld.furniture_items() where it exists (agent F),
## else from HousePlan.FURNITURE and the furniture states.

const ROOMS_DEBOUNCE := 1.0            ## real seconds between room recomputes (of the storeys that changed)
const POLL := 0.5                      ## real seconds between signature checks
const BLAST_REACH := 6.0               ## m around the house: a blast there shakes it
const LAMP_TYPES := ["floor_lamp", "table_lamp"]
const OBJECT_ITEMS := {"crate": "crate", "workbench": "workbench"}
const SLEEP_MEMORY_MINUTES := 120.0    ## a sleep this long counts as a night's rest

var game: Node                         ## SurvivalGame
var state: GameState
var maps := {}                         ## storey -> HouseRooms.find()
var windows := {}                      ## storey -> HouseRooms.windows()
var rooms := {}                        ## storey -> [room report]
var house := 0.0
var mood_info := {"target": Mood.START, "causes": []}
var stats := {"rooms_ms": 0.0, "comfort_ms": 0.0, "rooms_runs": 0, "comfort_runs": 0, "mood_steps": 0}
var last_text := ""                    ## the last dev / toast text (tests)

var _rooms_dirty := true
var _dirty_storeys := {}               ## storey -> true: its structure changed (all when empty and _rooms_dirty)
var _comfort_dirty := true
var _poll_t := 0.0
var _rooms_t := 999.0
var _sig := ""
var _watched := {}                     ## world instance id -> true
var _mood_at := -1.0
var _last_health := -1.0
var _hud_key := ""


func setup(g: Node) -> void:
	game = g
	state = g.state
	_watch_worlds()
	var lv = game.get("levels")
	if lv != null:
		if lv.has_signal("storey_changed"):
			lv.connect("storey_changed", func(_s): _update_hud(true))
		if lv.has_signal("levels_changed"):
			lv.connect("levels_changed", _on_levels_changed)
	if game.has_signal("sleep_finished"):
		game.connect("sleep_finished", _on_slept)
	if game.has_signal("invasion_started"):
		game.connect("invasion_started", _on_invasion_started)
	if game.has_signal("invasion_ended"):
		game.connect("invasion_ended", _on_invasion_ended)
	if game.has_signal("autosaved"):
		game.connect("autosaved", _on_autosaved)
	var roster = game.get("roster")
	if roster != null and roster.has_signal("detonated"):
		roster.connect("detonated", _on_detonated)
	var ui = game.get("ui")
	if ui != null and ui.get("inventory") != null and "home_source" in ui.inventory:
		ui.inventory.home_source = self
	_mood_at = state.total_minutes
	_last_health = state.health
	recompute()
	mood_info = Mood.step(state, _mood_inputs(), 0.0)
	_apply_rest()
	_update_hud(true)


# --- API -----------------------------------------------------------------------------

## The room at plan point p on `storey`: {"label", "comfort", "level", "level_name"
## (the comfort word), "factors", "hints", "exposed", "lit", "storey",
## "storey_name", "area", "centre", "id"}, or {} outside every room.
func room_at(storey: int, p: Vector2) -> Dictionary:
	var map: Dictionary = maps.get(storey, {})
	var w := world_of(storey)
	if map.is_empty() or w == null:
		return {}
	var i := HouseRooms.room_index_at(map, w.nav, p, 1)
	var list: Array = rooms.get(storey, [])
	return list[i] if i >= 0 and i < list.size() else {}


func house_comfort() -> float:
	return house


## The room the player is in ({} outdoors).
func player_room() -> Dictionary:
	var pl = game.get("player")
	if pl == null:
		return {}
	return room_at(player_storey(), pl.plan_pos())


func player_storey() -> int:
	var lv = game.get("levels")
	return int(lv.player_storey) if lv != null else 0


func storeys() -> Array:
	var lv = game.get("levels")
	if lv == null:
		return [0]
	if lv.has_method("storeys"):
		return lv.call("storeys")
	var out := []
	for s in [-1, 0, 1]:
		var w = lv.world_of(s)
		if w != null and (s == 0 or w != game.world):
			out.append(s)
	return out


func world_of(storey: int) -> HouseWorld:
	var lv = game.get("levels")
	if lv == null:
		return game.world if storey == 0 else null
	return lv.world_of(storey)


## Forces rooms and comfort now (F10, tests).
func recompute() -> void:
	_dirty_storeys.clear()
	_recompute_rooms()
	_recompute_comfort()


# --- the loop --------------------------------------------------------------------------

func _process(delta: float) -> void:
	if game == null or state == null:
		return
	_poll_t += delta
	_rooms_t += delta
	if _poll_t >= POLL:
		_poll_t = 0.0
		var sig := _signature()
		if sig != _sig:
			if _sig != "" and sig.get_slice("|", 0) != _sig.get_slice("|", 0):
				_rooms_dirty = true            # a storey appeared or went
				_watch_worlds()
			_sig = sig
			_comfort_dirty = true
		_update_hud(false)
	if _rooms_dirty and _rooms_t >= ROOMS_DEBOUNCE:
		_recompute_rooms()
	if _comfort_dirty and not _rooms_dirty:
		_recompute_comfort()
	if state.total_minutes - _mood_at >= Mood.UPDATE_MINUTES:
		_mood_tick()


func _signature() -> String:
	var parts := [str(storeys()), _light_bucket(), _fire_lit(), _mains()]
	var h = game.get("home")
	if h != null:
		parts.append(str(h.get("_states")))
		var fallen = h.get("_fallen")
		parts.append(str(fallen.size()) if fallen is Dictionary else "")
	for s in storeys():
		var w := world_of(s)
		if w == null:
			continue
		for o in w.objects:
			if o.has_method("is_lit"):
				parts.append("1" if o.call("is_lit") else "0")
	var b = game.get("balance")          # Exp 006 (B): TVs and radios switched on or off
	if b != null and b.has_method("media_signature"):
		parts.append(str(b.call("media_signature")))
	return "|".join(parts)


func _watch_worlds() -> void:
	for s in storeys():
		var w := world_of(s)
		if w == null or _watched.has(w.get_instance_id()):
			continue
		_watched[w.get_instance_id()] = true
		w.structure_changed.connect(_on_structure.bind(w))
		w.object_destroyed.connect(func(_k, _at): _on_structure(w))
		if w.has_signal("furniture_changed"):
			w.connect("furniture_changed", _on_furniture)
		if w.has_signal("power_changed"):
			w.connect("power_changed", _on_furniture)
		if w.has_signal("furniture_layout_changed"):          # agent F
			w.connect("furniture_layout_changed", _on_furniture)
	_rooms_dirty = true
	_dirty_storeys.clear()


func _on_structure(w: HouseWorld) -> void:
	if not _rooms_dirty or not _dirty_storeys.is_empty():
		var s := int(w.get("storey")) if w is LevelWorld else 0
		_dirty_storeys[s] = true
	_rooms_dirty = true


func _on_furniture(_a = null, _b = null) -> void:
	_comfort_dirty = true


func _on_levels_changed(_a = null) -> void:
	_watch_worlds()


# --- rooms and comfort -------------------------------------------------------------------

func _recompute_rooms() -> void:
	var t0 := Time.get_ticks_usec()
	var keep := {}
	var only := _dirty_storeys.duplicate()     # empty: every storey
	for s in storeys():
		var w := world_of(s)
		if w == null:
			continue
		keep[s] = true
		if only.is_empty() or only.has(s) or not maps.has(s):
			maps[s] = HouseRooms.find(w, s)
			windows[s] = HouseRooms.windows(w, s)
	_dirty_storeys.clear()
	for s in maps.keys():
		if not keep.has(s):
			maps.erase(s)
			windows.erase(s)
			rooms.erase(s)
	_rooms_dirty = false
	_rooms_t = 0.0
	_comfort_dirty = true
	stats["rooms_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	stats["rooms_runs"] += 1


func _recompute_comfort() -> void:
	var t0 := Time.get_ticks_usec()
	var light := _light_bucket()
	var fire := _fire_info()
	var media := _media_rooms()          # Exp 006 (B): playing TVs and radios, capped house-wide
	var all := []
	for s in maps:
		var w := world_of(s)
		var map: Dictionary = maps[s]
		if w == null:
			continue
		var nav: GridNav = w.nav
		var infos := []
		for r in map["rooms"]:
			var dw := 0
			for sec in r["sections"]:
				if w.section_integrity(sec) < ComfortCatalog.WALL_DAMAGED:
					dw += 1
			infos.append({"area": r["area"], "bbox": r["bbox"], "storey": s, "items": [], "wrecked": 0, "lamps": 0,
				"fire": "", "fireplace": false, "windows": {"intact": 0, "broken": 0, "boarded": 0}, "light": light,
				"floor": _floor_fraction(s, r["points"]), "exposed": r["exposed"], "damaged_walls": dw})
		if infos.is_empty():
			rooms[s] = []
			continue
		for it in _items_of(w):
			var i := HouseRooms.room_index_at(map, nav, it["pos"], 3)
			if i >= 0:
				infos[i]["items"].append(it)
		for p in _wrecked_of(w):
			var i := HouseRooms.room_index_at(map, nav, p, 3)
			if i >= 0:
				infos[i]["wrecked"] += 1
		for p in _lit_lamps(w, s):
			var i := HouseRooms.room_index_at(map, nav, p, 3)
			if i >= 0:
				infos[i]["lamps"] += 1
		for i in infos.size():          # Exp 006 (B)
			infos[i]["media"] = str(media["bonus"].get("%d:%d" % [s, i], ""))
		for win in windows.get(s, []):
			var i := HouseRooms.room_index_at(map, nav, win["inside"], 2)
			if i >= 0:
				infos[i]["windows"][win["state"]] += 1
		if not fire.is_empty() and int(fire["storey"]) == s:
			var i := HouseRooms.room_index_at(map, nav, fire["pos"], 3)
			if i >= 0:
				infos[i]["fireplace"] = true
				if fire["lit"]:
					infos[i]["fire"] = "here"
					for n in map["rooms"][i]["neighbours"]:
						var far: float = (map["rooms"][n]["centre"] as Vector2).distance_to(fire["pos"])
						if infos[n]["fire"] == "" and far <= ComfortCatalog.FIRE_NEAR_REACH:
							infos[n]["fire"] = "near"
		var out := []
		for i in infos.size():
			var r: Dictionary = map["rooms"][i]
			var e := HomeComfort.evaluate(infos[i])
			e["storey"] = s
			e["storey_name"] = Levels.name_of(s)
			e["area"] = r["area"]
			e["centre"] = r["centre"]
			e["id"] = "%d:%d" % [s, i]
			e["fire"] = infos[i]["fire"]
			e["media_here"] = str(media["here"].get(e["id"], ""))      # Exp 006 (B): for the mood
			out.append(e)
			all.append(e)
		rooms[s] = out
	house = HomeComfort.house_value(all)
	_comfort_dirty = false
	stats["comfort_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	stats["comfort_runs"] += 1
	_apply_rest()
	_update_hud(true)


## Exp 006 (B): the playing TVs and radios by room: {"here": {"s:i": best
## kind there}, "bonus": {"s:i": kind whose comfort counts}} (HouseMedia caps
## the bonus at ROOMS_MAX rooms). Sources come from the game's balance helper.
func _media_rooms() -> Dictionary:
	var here := {}
	var bonus := {}
	var b = game.get("balance")
	if b == null or not b.has_method("playing_sources"):
		return {"here": here, "bonus": bonus}
	var keys := []
	var lists := []
	for src in b.call("playing_sources"):
		var s := int(src["storey"])
		var map: Dictionary = maps.get(s, {})
		var w := world_of(s)
		if map.is_empty() or w == null:
			continue
		var i := HouseRooms.room_index_at(map, w.nav, src["pos"], 3)
		if i < 0:
			continue
		var key := "%d:%d" % [s, i]
		var at := keys.find(key)
		if at < 0:
			keys.append(key)
			lists.append([])
			at = keys.size() - 1
		lists[at].append(src["kind"])
	var won := HouseMedia.room_bonuses(lists)
	for k in keys.size():
		here[keys[k]] = HouseMedia.best(lists[k])
		if won[k] != "":
			bonus[keys[k]] = won[k]
	return {"here": here, "bonus": bonus}


## Furniture of a world as [{"type", "state", "pos", "id"}].
func _items_of(w: HouseWorld) -> Array:
	var out := []
	if w.has_method("furniture_items"):
		for it in w.call("furniture_items"):
			var r = it.get("rect")
			var p: Vector2 = (r as Rect2).get_center() if r is Rect2 else Vector2(it.get("pos", Vector2.INF))
			out.append({"type": str(it.get("type", "")), "state": str(it.get("state", "intact")), "pos": p, "id": str(it.get("id", "")),
				"lit": it.get("lit"), "node": it.get("node")})
	elif not w is LevelWorld:
		var fur = w.get("furniture")
		for f in HousePlan.FURNITURE:
			var rect: Rect2 = f["rect"]
			var st := "intact"
			if f["type"] == "rug":
				if not _rug_present(w, rect):
					continue
			elif fur != null:
				st = fur.state_of(f["id"])
				if not st in ["intact", "damaged"]:
					continue
			out.append({"type": f["type"], "state": st, "pos": rect.get_center(), "id": f["id"]})
	for o in w.objects:
		if OBJECT_ITEMS.has(o.kind):
			out.append({"type": OBJECT_ITEMS[o.kind], "state": "damaged" if o.hp < o.max_hp else "intact", "pos": o.pos, "id": ""})
	return out


func _rug_present(w: HouseWorld, rect: Rect2) -> bool:
	var c := w.grid.cell_of(Vector3(rect.get_center().x, 0.0, rect.get_center().y))
	return w.grid.get_mat(c.x, VoxelHouse.FLOOR_ROW, c.z) == VoxelMat.RUG


## Positions of destroyed furniture (rubble) on a world.
func _wrecked_of(w: HouseWorld) -> Array:
	var out := []
	var fur = w.get("furniture")
	if fur == null or not "pieces" in fur or not fur.has_method("state_of"):
		return out
	for id in fur.pieces:
		var p = fur.pieces[id]
		if fur.state_of(id) == "destroyed" and p is Dictionary and p.get("f") is Dictionary and p["f"].get("rect") is Rect2:
			out.append((p["f"]["rect"] as Rect2).get_center())
	return out


## Positions of the lights that shine on a storey: the electric fixtures
## (ground floor), lamps among the furniture (agent F's is_lit(), else intact
## with the mains on) and lamp objects with is_lit().
func _lit_lamps(w: HouseWorld, storey: int) -> Array:
	var out := []
	var h = game.get("home")
	var skip := {}
	if storey == 0 and h != null and h.get("_states") is Dictionary:
		var st: Dictionary = h.get("_states")
		var fallen = h.get("_fallen")
		for l in HousePlan.LIGHTS:
			if st.get(l["id"], false) and not (fallen is Dictionary and fallen.has(l["id"])):
				out.append(l["pos"])
		for id in HomeElectrical.NEEDS_FURNITURE.values():
			skip[id] = true            # those lamps are fixtures already
	var mains := _mains()
	var objs := []                     # lamp objects (agent F): counted once, not again as furniture
	for o in w.objects:
		if o.has_method("is_lit"):
			objs.append(o.pos)
			if o.call("is_lit"):
				out.append(o.pos)
	for it in _items_of(w):
		if not it["type"] in LAMP_TYPES or skip.has(it["id"]) or objs.any(func(q): return q.distance_to(it["pos"]) < 0.3):
			continue
		var lit = it.get("lit")
		if lit == null:
			var n = it.get("node")
			if n is Object and is_instance_valid(n) and n.has_method("is_lit"):
				lit = n.call("is_lit")
			else:
				lit = mains and it["state"] == "intact"
		if lit:
			out.append(it["pos"])
	return out


func _floor_fraction(storey: int, pts: PackedVector2Array) -> float:
	if storey > 0 or pts.is_empty():
		return 1.0                     # the upper deck is a wooden floor
	var lv = game.get("levels")
	var laid_all = lv.get("laid") if lv != null else null
	var laid: Dictionary = laid_all.get(storey, {}) if laid_all is Dictionary else {}
	var good := 0
	for p in pts:
		if (storey == 0 and HousePlan.FOOTPRINT.has_point(p)) or laid.has(Levels.cell_of(p)):
			good += 1
	return float(good) / float(pts.size())


func _fire_info() -> Dictionary:
	var h = game.get("home")
	var fp = h.get("fireplace") if h != null else null
	if fp == null or not is_instance_valid(fp):
		return {}
	var r := Fireplace.RECT
	return {"storey": 0, "pos": Vector2(r.get_center().x, r.end.y + 0.45), "lit": bool(fp.lit)}


func _fire_lit() -> bool:
	var f := _fire_info()
	return not f.is_empty() and f["lit"]


func _mains() -> bool:
	var h = game.get("home")
	return bool(h.call("mains_on")) if h != null and h.has_method("mains_on") else true


func _light_bucket() -> String:
	var n := state.night_amount()
	return "day" if n < 0.3 else ("dusk" if n < 0.7 else "night")


# --- mood ------------------------------------------------------------------------------

func _mood_inputs() -> Dictionary:
	var here := player_room()
	var exposed := 0
	for s in rooms:
		for r in rooms[s]:
			if r["exposed"] and r["label"] != "Hallway":
				exposed += 1
	var night := state.night_amount() > 0.5
	var night_light := ""
	if night and not here.is_empty():
		night_light = "lit" if here.get("lit", false) else "dark"
	return {"house": house, "fire_near": not here.is_empty() and here.get("fire", "") != "",
		"cold": night and (here.is_empty() or here["exposed"]), "exposed_rooms": exposed, "night_light": night_light,
		"media": str(here.get("media_here", ""))}      # Exp 006 (B): a TV or radio playing in Eli's room


func _mood_tick() -> void:
	var now := state.total_minutes
	var dt := maxf(now - _mood_at, 0.0) if _mood_at >= 0.0 else 0.0
	_mood_at = now
	if _last_health >= 0.0 and state.health < _last_health - Mood.HURT_DROP and state.hunger > 0.0 and state.hydration > 0.0:
		Mood.remember(state, "hurt")
	_last_health = state.health
	if _comfort_dirty and not _rooms_dirty:
		_recompute_comfort()
	mood_info = Mood.step(state, _mood_inputs(), dt)
	stats["mood_steps"] += 1
	_apply_rest()
	_update_hud(false)


func _apply_rest() -> void:
	var r := player_room()
	state.rest_scale = Mood.rest_scale(state.mood, int(r.get("level", 2)) if not r.is_empty() else 2)


func _on_slept(plan: Dictionary) -> void:
	_mood_tick()
	if state.dead or float(plan.get("minutes", 0.0)) < SLEEP_MEMORY_MINUTES:
		return
	var r := player_room()
	var lvl := int(r.get("level", 2)) if not r.is_empty() else 1
	var quiet: bool = plan.get("interrupted", false)       # the game's own wake-up line stays the last word
	if lvl >= 3 and not quiet:
		Mood.remember(state, "slept_well")
		_tell("You slept well. It feels like home." if lvl >= 4 else "You slept well in a comfortable room.", "good")
	elif lvl <= 1:
		Mood.remember(state, "slept_badly")
		if not quiet:
			_tell("A poor night's sleep. The room is %s." % str(r.get("level_name", "uncomfortable")).to_lower(), "warn")
	mood_info = Mood.target(state, _mood_inputs())


func _on_invasion_started() -> void:
	_mood_tick()
	Mood.remember(state, "attack")


func _on_invasion_ended(reason: String) -> void:
	_mood_tick()
	if not state.dead and reason in ["cleared", "dawn"]:
		Mood.remember(state, "survived")


func _on_autosaved(reason: String) -> void:
	if reason == "expedition":
		_mood_tick()
		Mood.remember(state, "home_safe" if state.health >= 50.0 else "home_hurt")
		mood_info = Mood.target(state, _mood_inputs())


func _on_detonated(at: Vector3, _radius: float, _damage: float) -> void:
	if HousePlan.FOOTPRINT.grow(BLAST_REACH).has_point(Vector2(at.x, at.z)):
		Mood.remember(state, "blast")
		mood_info = Mood.target(state, _mood_inputs())


# --- UI ---------------------------------------------------------------------------------

func _update_hud(force: bool) -> void:
	var hud = game.get("hud")
	if hud == null or not hud.has_method("set_home_line"):
		return
	var r := player_room()
	var room_text := "Outdoors"
	var lvl := -1
	if not r.is_empty():
		room_text = "%s · %s" % [r["label"], r["level_name"]]
		lvl = int(r["level"])
	var mood_text := "Mood: %s" % Mood.name_of(state.mood)
	var key := room_text + mood_text
	if not force and key == _hud_key:
		return
	_hud_key = key
	hud.call("set_home_line", room_text, lvl, mood_text, Mood.band(state.mood))


## Everything the Home tab shows.
func report() -> Dictionary:
	if _rooms_dirty:
		_recompute_rooms()
	if _comfort_dirty:
		_recompute_comfort()
	var here := player_room()
	var by_storey := []
	var list := storeys()
	list.sort()
	list.reverse()                     # top storey first
	for s in list:
		var rs: Array = rooms.get(s, []).duplicate()
		rs.sort_custom(func(a, b): return a["area"] > b["area"])
		by_storey.append({"storey": s, "name": Levels.name_of(s), "rooms": rs})
	var rest := Mood.rest_scale(state.mood, int(here.get("level", 2)) if not here.is_empty() else 2)
	return {"here": here, "house": house, "house_name": ComfortCatalog.level_name(house), "storeys": by_storey,
		"mood": state.mood, "mood_name": Mood.name_of(state.mood), "target": float(mood_info.get("target", state.mood)),
		"causes": mood_info.get("causes", []), "effects": Mood.effects_text(state.mood), "rest": rest}


func _tell(text: String, kind: String) -> void:
	last_text = text
	if game.has_method("toast"):
		game.call("toast", text, kind)


# --- F10 ---------------------------------------------------------------------------------

func dev_show() -> String:
	recompute()
	var parts := ["House %.1f (%s)" % [house, ComfortCatalog.level_name(house)]]
	var list := storeys()
	list.sort()
	for s in list:
		for r in rooms.get(s, []):
			parts.append("%s: %s %.1f%s" % [Levels.name_of(s), r["label"], r["comfort"], " (exposed)" if r["exposed"] else ""])
	parts.append("Mood %.0f %s, heading to %.0f" % [state.mood, Mood.name_of(state.mood), float(mood_info.get("target", 0.0))])
	var text := " · ".join(parts)
	_tell("House %.1f (%s), mood %s. Details: F10 status, or I › Home." % [house, ComfortCatalog.level_name(house), Mood.name_of(state.mood)], "info")
	last_text = text
	return text


func dev_mood(which: String) -> String:
	state.mood = float(Mood.PRESETS.get(which, Mood.START))
	if which == "normal":
		state.mood_state = Mood.clean({})
	mood_info = Mood.target(state, _mood_inputs())
	_apply_rest()
	_update_hud(true)
	last_text = "Mood set to %s (%.0f). It drifts toward %.0f." % [Mood.name_of(state.mood), state.mood, float(mood_info["target"])]
	return last_text


func dev_recompute() -> String:
	recompute()
	var n := 0
	for s in rooms:
		n += rooms[s].size()
	last_text = "Recomputed %d rooms on %d storeys (rooms %.1f ms, comfort %.1f ms)." % [n, rooms.size(), stats["rooms_ms"], stats["comfort_ms"]]
	return last_text


## Opens the inventory on its Home tab (F10).
func dev_open_panel() -> String:
	if game.has_method("debug_open"):
		game.call("debug_open", "inventory")
	var inv = game.get("ui").get("inventory") if game.get("ui") != null else null
	if inv != null and inv.has_method("show_tab"):
		inv.call("show_tab", "home")
		return "Home panel open (I, then Home)."
	return "No inventory panel."


func info() -> String:
	var r := player_room()
	return "Comfort: house %.1f %s · here %s · mood %.0f %s (target %.0f) · rest x%.2f" % [house, ComfortCatalog.level_name(house),
		("%s %.1f" % [r["label"], r["comfort"]]) if not r.is_empty() else "outdoors", state.mood, Mood.name_of(state.mood),
		float(mood_info.get("target", 0.0)), state.rest_scale]
