extends Node
## Experiment 007 (N): room-based visibility in the running game,
## `game.visibility` (the user's §10). Works at home (every storey) and in
## POIs (any HouseWorld; see HouseRooms.floor_rects for a POI's floor).
##
## Rules: RoomVisibility (Eli's room full; through open doorways near, through
## open doors partial; closed-off rooms hidden). Hidden rooms keep simulating:
## only visuals hide:
##   - furniture meshes and their rubble (HouseFurniture pieces), placed
##     objects inside rooms (furniture, crates, lamps with their light, TVs,
##     loot piles, POI containers) - never doors, boards, barricades or other
##     wall pieces, which bound the rooms;
##   - candles and lanterns with their glow (HouseWorld.night_lights);
##   - the map on the dining table;
##   - enemies standing inside a hidden room (their rig; checked every POLL
##     seconds per enemy, a table lookup);
##   - the floor of a hidden (or partly seen) room gets a dark overlay, one
##     mesh for the storey.
## Outdoors there is no room logic: enemies, trees and the yard show as before.
##
## When it updates (never per frame room-wide):
##   - Eli changes room (looked up every POLL s in the current rooms);
##   - a door opens or closes, a wall is broken, built or repaired, an opening
##     is cut, objects are placed or destroyed (structure_changed, debounced);
##   - furniture changes (furniture_changed / furniture_layout_changed);
##   - the storey changes (levels.storey_changed / view_changed /
##     levels_changed) or build mode opens or closes (everything shows in build
##     mode, so you can plan anywhere).
## It leaves the cutaway (HouseWorld.update_view: it hides geometry, this
## hides whole nodes), the roof toggle, PgUp / PgDn and the camera alone.
##
## F10 "Noise & visibility": reveal all (enabled = false), room boundaries
## (each room tinted, with a label), visibility diagnostics (a HUD line).

const POLL := 0.15                     ## s between Eli's room look-ups and the enemies' check
const DEBOUNCE := 0.25                 ## s after a structure change before re-applying
const OVERLAY_LIFT := 0.02             ## m above the storey's floor
const ROOM_HUES := [0.0, 0.12, 0.3, 0.45, 0.58, 0.7, 0.8, 0.9]

var game: Node
var cache := RoomCache.new()
var enabled := true                    ## false: reveal all (F10)
var show_bounds := false               ## F10: tint every room, label it
var diagnostics := false               ## F10: the HUD line
var states := {}                       ## room index -> RoomVisibility state, on the active storey
var here := -1                         ## Eli's room on the active storey (-1: outdoors or another storey)
var storey := 0                        ## the active storey (the viewed one)
var stats := {"updates": 0, "ms": 0.0, "reason": "", "hidden_nodes": 0, "hidden_enemies": 0}

var _world: HouseWorld
var _map := {}
var _hidden := {}                      ## instance id -> Node3D we hid
var _lights: Array = []                ## night-light entries we dimmed
var _rigs := {}                        ## enemy instance id -> its rig (hidden by us)
var _overlay: MeshInstance3D
var _labels: Node3D
var _diag: Label
var _dirty := true
var _reason := "start"
var _since := 999.0
var _poll := 0.0
var _key := ""
var _watched := {}


func setup(g: Node) -> void:
	game = g
	_overlay = MeshInstance3D.new()
	_overlay.name = "RoomShade"
	_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_overlay.material_override = m
	add_child(_overlay)
	_labels = Node3D.new()
	_labels.name = "RoomLabels"
	add_child(_labels)
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	_diag = Label.new()
	_diag.position = Vector2(12, 150)
	_diag.add_theme_font_size_override("font_size", 14)
	_diag.add_theme_color_override("font_outline_color", Color.BLACK)
	_diag.add_theme_constant_override("outline_size", 4)
	_diag.visible = false
	layer.add_child(_diag)
	_watch()
	var lv = game.get("levels")
	if lv != null:
		for sig in ["storey_changed", "view_changed", "levels_changed"]:
			if lv.has_signal(sig):
				lv.connect(sig, _on_levels.bind(sig))
	if game.has_signal("site_ready"):
		game.connect("site_ready", _on_site)


## Re-applies at once (F10, tests).
func refresh(reason := "manual") -> void:
	_reason = reason
	_apply()


func set_enabled(on: bool) -> void:
	enabled = on
	refresh("reveal all" if not on else "rooms on")


func set_show_bounds(on: bool) -> void:
	show_bounds = on
	refresh("boundaries")


func set_diagnostics(on: bool) -> void:
	diagnostics = on
	_diag.visible = on
	_update_diag()


## The state of the room at plan point p on the active storey ("" outside rooms).
func state_at(p: Vector2) -> String:
	if _map.is_empty() or _world == null:
		return ""
	var i := HouseRooms.room_index_at(_map, _world.nav, p, 1)
	return RoomVisibility.name_of(states[i]) if states.has(i) else ""


## True if we hid this node (furniture, an object, an enemy's rig).
func is_hidden(n: Node) -> bool:
	if n == null:
		return false
	if n is AIEnemy:
		return _rigs.has(n.get_instance_id())
	return _hidden.has(n.get_instance_id())


# --- triggers --------------------------------------------------------------------------

func _watch() -> void:
	for w in _worlds():
		var id := (w as HouseWorld).get_instance_id()
		if _watched.has(id):
			continue
		_watched[id] = true
		w.structure_changed.connect(_mark.bind("structure"))
		w.object_destroyed.connect(func(_k, _at): _mark("destroyed"))
		for sig in ["furniture_changed", "furniture_layout_changed"]:
			if w.has_signal(sig):
				w.connect(sig, _on_furniture)


func _worlds() -> Array:
	var out := []
	var lv = game.get("levels")
	if lv != null and lv.has_method("storeys"):
		for s in lv.call("storeys"):
			var w = lv.call("world_of", s)
			if w is HouseWorld:
				out.append(w)
	elif game.get("world") is HouseWorld:
		out.append(game.world)
	return out


func _on_site(_a = null) -> void:
	_now("site")


func _on_furniture(_a = null) -> void:
	_mark("furniture")


func _on_levels(_a = null, _sig := "") -> void:
	_watch()
	_now("storey")


func _mark(reason: String) -> void:
	if not _dirty:
		_since = 0.0
	_dirty = true
	_reason = reason


func _now(reason: String) -> void:
	_dirty = true
	_reason = reason
	_since = DEBOUNCE


func _process(delta: float) -> void:
	if game == null or game.get("player") == null:
		return
	_since += delta
	_poll += delta
	if _poll >= POLL:
		_poll = 0.0
		var k := _view_key()
		if k != _key:
			_key = k
			_now("room change")
		elif not _dirty:
			_update_enemies()
		if diagnostics:
			_update_diag()
	if _dirty and _since >= DEBOUNCE:
		_apply()


## storey | Eli's room in the current rooms | build mode | on.
func _view_key() -> String:
	var a := _active()
	var w: HouseWorld = a[0]
	var room := -1
	if w != null and w == _world and not _map.is_empty() and _player_storey() == int(a[1]):
		room = HouseRooms.room_index_at(_map, w.nav, _player_plan(), 1)
	return "%d|%d|%s|%s|%d" % [int(a[1]), room, _building(), enabled, w.get_instance_id() if w != null else 0]


func _active() -> Array:
	var lv = game.get("levels")
	if lv != null and lv.has_method("world_of"):
		var s := int(lv.get("view_storey"))
		return [lv.call("world_of", s), s]
	return [game.get("world"), 0]


func _player_storey() -> int:
	var lv = game.get("levels")
	return int(lv.get("player_storey")) if lv != null else 0


func _player_plan() -> Vector2:
	var pl: Node3D = game.get("player")
	return Vector2(pl.global_position.x, pl.global_position.z)


func _building() -> bool:
	var b = game.get("build")
	return b != null and bool(b.get("active"))


# --- applying ----------------------------------------------------------------------------

func _apply() -> void:
	var t0 := Time.get_ticks_usec()
	_dirty = false
	_since = 0.0
	_restore()
	var a := _active()
	_world = a[0]
	storey = int(a[1])
	states = {}
	here = -1
	_map = {}
	if _world != null and is_instance_valid(_world):
		_map = cache.map_of(_world, storey)
	if _map.is_empty() or _map["rooms"].is_empty() or (not enabled and not show_bounds) or _building():
		_build_overlay()
		_finish(t0)
		return
	if _player_storey() == storey:
		here = HouseRooms.room_index_at(_map, _world.nav, _player_plan(), 1)
	if enabled:
		states = RoomVisibility.compute(_map, RoomVisibility.links(_world, _map), here)
		_hide_contents()
		_update_enemies()
	_build_overlay()
	_finish(t0)


func _finish(t0: int) -> void:
	_key = _view_key()
	stats["updates"] += 1
	stats["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	stats["reason"] = _reason
	stats["hidden_nodes"] = _hidden.size()
	if diagnostics:
		_update_diag()


func _room_hidden(p: Vector2, reach := 1) -> bool:
	var i := HouseRooms.room_index_at(_map, _world.nav, p, reach)
	return i >= 0 and states.get(i, RoomVisibility.FULL) == RoomVisibility.HIDDEN


func _hide_contents() -> void:
	var fur = _world.get("furniture")
	if fur != null and fur.get("pieces") is Dictionary:
		for id in fur.pieces:
			var p: Dictionary = fur.pieces[id]
			var f = p.get("f")
			if not (f is Dictionary and f.get("rect") is Rect2):
				continue
			if _room_hidden((f["rect"] as Rect2).get_center(), 2):
				_hide(p.get("node"))
				_hide(p.get("rubble"))
	for o in _world.objects:
		if WorldObject.is_segment_kind(o.kind) or DefenseGrid.is_bridge(o.kind):
			continue
		if _room_hidden(o.pos, 1):
			_hide(o)
	for l in _world.night_lights:
		var n = l.get("node")
		if n is Node3D and _room_hidden(Vector2((n as Node3D).position.x, (n as Node3D).position.z), 2):
			l["room_hidden"] = true
			for gi in l.get("geos", []):
				if is_instance_valid(gi):
					(gi as GeometryInstance3D).visible = false
			_lights.append(l)
	if storey == 0 and _world == game.get("world"):
		var mp = game.get("map")
		var table = mp.get("table") if mp != null else null
		if table is Node3D and _room_hidden(Vector2((table as Node3D).global_position.x, (table as Node3D).global_position.z), 2):
			for c in (table as Node3D).get_children():
				_hide(c)


func _hide(n) -> void:
	if not (n is Node3D) or not is_instance_valid(n) or not (n as Node3D).visible:
		return
	(n as Node3D).visible = false
	_hidden[(n as Node3D).get_instance_id()] = n


func _restore() -> void:
	for id in _hidden:
		var n = _hidden[id]
		if is_instance_valid(n):
			(n as Node3D).visible = true
	_hidden.clear()
	for l in _lights:
		l.erase("room_hidden")
		for gi in l.get("geos", []):
			if is_instance_valid(gi):
				(gi as GeometryInstance3D).visible = true
	_lights.clear()


## Enemies inside hidden rooms of the active storey lose their rig (they keep
## moving and acting); everyone else shows. A per-enemy table lookup.
func _update_enemies() -> void:
	var r = game.get("roster")
	if r == null:
		return
	var n := 0
	var seen := {}
	for e in r.enemies:
		if not is_instance_valid(e) or not (e is AIEnemy):
			continue
		var a := e as AIEnemy
		var hide := false
		if not states.is_empty() and a.storey == storey and _world != null:
			var i := HouseRooms.room_index_at(_map, _world.nav, a.plan_pos(), 0)
			hide = i >= 0 and states.get(i, RoomVisibility.FULL) == RoomVisibility.HIDDEN
		var id := a.get_instance_id()
		seen[id] = true
		if a.rig == null:
			continue
		if hide:
			n += 1
			if not _rigs.has(id):
				_rigs[id] = a.rig
				a.rig.visible = false
		elif _rigs.has(id):
			_rigs.erase(id)
			a.rig.visible = true
	for id in _rigs.keys():
		if not seen.has(id):
			_rigs.erase(id)
	stats["hidden_enemies"] = n


# --- overlay and diagnostics --------------------------------------------------------------

func _build_overlay() -> void:
	for c in _labels.get_children():
		c.queue_free()
	if _map.is_empty() or _world == null or (states.is_empty() and not show_bounds):
		_overlay.mesh = null
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads := 0
	for r in _map["rooms"]:
		var i := int(r["index"])
		var c := Color(0, 0, 0, 0)
		if show_bounds:
			c = Color.from_hsv(ROOM_HUES[i % ROOM_HUES.size()], 0.75, 0.9, 0.32)
			if states.get(i, RoomVisibility.FULL) == RoomVisibility.HIDDEN:
				c = c.darkened(0.6)
			var lab := Label3D.new()
			lab.text = "R%d %s" % [i, RoomVisibility.name_of(states[i]) if states.has(i) else ""]
			lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lab.no_depth_test = true
			lab.font_size = 40
			lab.pixel_size = 0.006
			lab.outline_size = 8
			var ctr: Vector2 = r["centre"]
			lab.position = Vector3(ctr.x, Levels.base_y(storey) + 1.4, ctr.y)
			_labels.add_child(lab)
		elif states.has(i):
			c = Color(0, 0, 0, RoomVisibility.DIM[states[i]])
		if c.a <= 0.01:
			continue
		quads += _add_cells(st, r["points"], c)
	if quads == 0:
		_overlay.mesh = null
		return
	_overlay.mesh = st.commit()
	_overlay.position = Vector3(0, Levels.base_y(storey) + OVERLAY_LIFT, 0)


## Quads over a room's 0.25 m cells, merged along x. Returns the quad count.
static func _add_cells(st: SurfaceTool, pts: PackedVector2Array, c: Color) -> int:
	var rows := {}
	for p in pts:
		var k := roundi(p.y / HouseRooms.CELL)
		if not rows.has(k):
			rows[k] = []
		rows[k].append(p.x)
	var h := HouseRooms.CELL * 0.5
	var n := 0
	for k in rows:
		var xs: Array = rows[k]
		xs.sort()
		var y := float(k) * HouseRooms.CELL
		var x0: float = xs[0]
		var prev: float = xs[0]
		for j in range(1, xs.size() + 1):
			var x: float = xs[j] if j < xs.size() else INF
			if x - prev > HouseRooms.CELL * 1.5:
				_quad(st, Vector2(x0 - h, y - h), Vector2(prev + h, y + h), c)
				n += 1
				x0 = x
			prev = x
	return n


static func _quad(st: SurfaceTool, a: Vector2, b: Vector2, c: Color) -> void:
	for v in [Vector3(a.x, 0, a.y), Vector3(b.x, 0, a.y), Vector3(b.x, 0, b.y), Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), Vector3(a.x, 0, b.y)]:
		st.set_color(c)
		st.add_vertex(v)


func info() -> String:
	var cn := RoomVisibility.counts(states)
	var rooms: int = _map["rooms"].size() if not _map.is_empty() else 0
	var where := "outdoors" if here < 0 else "room %d" % here
	return "Visibility %s · %s · %s of %d rooms · %d full, %d near, %d partial, %d hidden · hidden: %d props, %d enemies · %s (%.1f ms) · %d updates, rooms found %d×" % [
		"on" if enabled else "OFF (reveal all)", Levels.name_of(storey), where, rooms, cn["full"], cn["near"], cn["partial"], cn["hidden"],
		int(stats["hidden_nodes"]), int(stats["hidden_enemies"]), str(stats["reason"]), float(stats["ms"]), int(stats["updates"]), cache.runs]


func _update_diag() -> void:
	if _diag != null and _diag.visible:
		_diag.text = info()


# --- F10 ----------------------------------------------------------------------------------

func dev_toggle_bounds() -> String:
	set_show_bounds(not show_bounds)
	return "Room boundaries %s." % ("shown" if show_bounds else "hidden")


func dev_toggle_diagnostics() -> String:
	set_diagnostics(not diagnostics)
	return "Visibility diagnostics %s. %s" % ["on" if diagnostics else "off", info()]


func dev_toggle_reveal() -> String:
	set_enabled(not enabled)
	return "Reveal all: %s." % ("off (room visibility on)" if enabled else "on (every room shows)")
