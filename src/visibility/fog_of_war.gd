class_name FogOfWar
extends Node3D
## Exp 012 (V): the fog of war, at home and in POIs (the user's §15-17).
## `game.visibility.fow` (created by game_visibility.gd).
##
## Three states per 0.5 m cell (FowGrid): undiscovered (a dense dark fog),
## discovered but not visible (remembered: darkened, drained of colour) and
## visible (as rendered). Drawn by one full-screen pass (fog_of_war.gdshader:
## the depth buffer gives each pixel's plan XZ, two tiny textures give the
## state), so the night, lamps and shadows stay as they are inside the view.
##
## What Eli sees: a cone along where he faces (his rig's yaw, which follows
## the aim), `cone_deg` wide (default 120) out to REACH m, plus a 360-degree
## ring of RING m around him; line of sight is cast on the voxel world at eye
## height (FowGrid.build_occlusion: walls, closed doors, boards; glass and
## open doorways let it through). While Eli looks through an observation hole
## (set_peek) the hole's view cone is cast as well.
##
## Dynamic things are drawn only while they are in the visible set; their
## logic, sounds and collisions are untouched:
##   - roster enemies: their rig (game_visibility.gd combines this with the
##     Exp 007 room visibility; `sees(enemy)`). No last-seen ghost.
##   - nodes in the group "fow_dynamic" (agent E's corpses, anything that
##     moves or appears): shown only while visible
##   - nodes in the group "fow_remember": hidden until first seen, then kept
##     (meta "fow_seen")
##   - POI loose items and container spots (their markers): hidden while their
##     cell is undiscovered, remembered once seen
## Enemies on another storey are never seen, except outdoors from an upper
## floor (through the windows); the house's interior never through a floor.
##
## Proximity sense: the nearest unseen enemy within PROX_RANGE on Eli's
## storey with no wall between them pulses a soft dark edge on that side of
## the screen (proximity_cue.gd), quantised to eight directions: a presence,
## never a position.
##
## Updates: at most HZ a second and only when Eli moved MOVE_EPS m or turned
## TURN_EPS rad, the storey or the peek changed, or the structure changed
## (occlusion rebuilt after OCC_DEBOUNCE s). `stats` has the costs.
##
## Memory: home: state.home["seen"]; a POI: its visit record's "seen"
## (FowGrid.save_seen, ~200-600 bytes). At home the lot and the house start
## discovered (Eli knows his own house and yard); the fog band beyond the lot
## is discovered by looking into it. A POI starts undiscovered.
##
## API for others (L, E, G, S): is_point_visible(world_pos) -> bool (true when
## the fog of war is off), is_discovered(world_pos) -> bool, sees(enemy),
## plan_visible(p), active().

const SHADER := preload("res://src/visibility/fog_of_war.gdshader")
const Cue := preload("res://src/visibility/proximity_cue.gd")
const HZ := 10.0
const REACH := 24.0                    ## m: the cone's range (the camera shows ~18 m at most)
const RING := 1.75                     ## m: all-round awareness
const CONE_DEG := 120.0
const MOVE_EPS := 0.2
const TURN_EPS := 0.05                 ## rad (~3 degrees)
const OCC_DEBOUNCE := 0.3
const PROX_RANGE := 3.2                ## m: the proximity sense
const SAVE_EVERY := 1.0                ## s between writes of the memory into the run
const HOME_KNOWN := Rect2(-4.8, -3.8, 23.6, 16.6)   ## FogBoundary.LOT grown by 0.3 m: known from the start
## Looks (day -> night), linear colours (the pass is unshaded, then tonemapped).
const MEMORY_DAY := Color(0.022, 0.026, 0.036)
const MEMORY_NIGHT := Color(0.003, 0.004, 0.008)
const FOG_DAY := Color(0.05, 0.055, 0.065)
const FOG_NIGHT := Color(0.006, 0.008, 0.014)

var game: Node
var grid := FowGrid.new()
var enabled := true
var cone_deg := CONE_DEG
var show_debug := false
var peek := {}                         ## {} or {"o": Vector2, "d": Vector2, "half": rad, "range": m}
var key := ""                          ## the memory's layout key
var stats := {"updates": 0, "ms": 0.0, "avg_ms": 0.0, "max_ms": 0.0, "occ_ms": 0.0, "occ_runs": 0, "skipped": 0,
	"rays": 0, "steps": 0, "new_cells": 0, "hidden_nodes": 0}
var cue: CanvasLayer                   ## proximity_cue.gd
var sensed: Node = null                ## the enemy the proximity sense felt last (tests)

var _world: HouseWorld
var _watched := {}
var _occ_dirty := true
var _occ_since := 99.0
var _tick := 99.0
var _last_eye := Vector2.INF
var _last_yaw := INF
var _last_cone := -1.0
var _force := true
var _blend := 1.0
var _quad: MeshInstance3D
var _mat: ShaderMaterial
var _img_disc: Image
var _img_vis: Image
var _tex_disc: ImageTexture
var _tex_vis: ImageTexture
var _tex_prev: ImageTexture
var _debug: MeshInstance3D
var _hidden := {}                      ## instance id -> Node3D we hid
var _seen_dirty := false
var _save_t := 0.0
var _loaded := false
var _was_on := true
var _look := Vector4(-1, -1, -1, -1)


func setup(g: Node) -> void:
	game = g
	name = "FogOfWar"
	_img_disc = Image.create_from_data(grid.w, grid.h, false, Image.FORMAT_L8, grid.disc)
	_img_vis = Image.create_from_data(grid.w, grid.h, false, Image.FORMAT_L8, grid.vis)
	_tex_disc = ImageTexture.create_from_image(_img_disc)
	_tex_vis = ImageTexture.create_from_image(_img_vis)
	_tex_prev = ImageTexture.create_from_image(_img_vis)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.render_priority = 120
	_mat.set_shader_parameter("area", Vector4(FowGrid.AREA.position.x, FowGrid.AREA.position.y, FowGrid.AREA.size.x, FowGrid.AREA.size.y))
	_mat.set_shader_parameter("noise_tex", FogBoundary.noise_texture())
	_bind_textures()
	_quad = MeshInstance3D.new()
	_quad.name = "FogOfWarPass"
	var qm := QuadMesh.new()
	qm.size = Vector2(2, 2)
	_quad.mesh = qm
	_quad.material_override = _mat
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quad.extra_cull_margin = 16384.0
	add_child(_quad)
	cue = Cue.new()
	cue.name = "ProximitySense"
	add_child(cue)
	_load_seen()
	var lv = game.get("levels")
	if lv != null and lv.has_signal("storey_changed"):
		lv.connect("storey_changed", func(_s): _force = true)


func _bind_textures() -> void:
	_mat.set_shader_parameter("disc_tex", _tex_disc)
	_mat.set_shader_parameter("vis_tex", _tex_vis)
	_mat.set_shader_parameter("prev_tex", _tex_prev)


## True while the fog of war is on (and in the tree).
func active() -> bool:
	return enabled and is_inside_tree()


# --- queries ---------------------------------------------------------------------------------

## Exp 012 (V) API: can Eli see this point now? (true when the fog of war is off)
func is_point_visible(p: Vector3) -> bool:
	if not active():
		return true
	var pp := Vector2(p.x, p.z)
	return _storey_ok(_storey_of_y(p.y), pp) and grid.is_visible(pp)


## Exp 012 (V) API: has Eli ever seen this spot? (true when the fog of war is off)
func is_discovered(p: Vector3) -> bool:
	return not active() or grid.is_discovered(Vector2(p.x, p.z))


## Plan point on Eli's storey visible now.
func plan_visible(p: Vector2) -> bool:
	return not active() or grid.is_visible(p)


## Is this enemy (AIEnemy, or any node with plan_pos() / storey) in sight?
func sees(e: Node) -> bool:
	if not active():
		return true
	var p: Vector2
	if e.has_method("plan_pos"):
		p = e.call("plan_pos")
	elif e is Node3D:
		p = Vector2((e as Node3D).global_position.x, (e as Node3D).global_position.z)
	var st = e.get("storey")
	return _storey_ok(int(st) if st != null else _storey_of_y((e as Node3D).global_position.y if e is Node3D else 0.0), p) and grid.is_visible(p)


func _player_storey() -> int:
	var lv = game.get("levels") if game != null else null
	return int(lv.get("player_storey")) if lv != null else 0


func _storey_of_y(y: float) -> int:
	return int(floor((y + 0.6) / Levels.HEIGHT))


## Another storey is never seen through a floor; outdoors on the ground,
## from an upper floor (the windows), is.
func _storey_ok(st: int, p: Vector2) -> bool:
	var ps := _player_storey()
	if st == ps:
		return true
	if game == null or game.get("levels") == null:
		return st == ps
	if HousePlan.FOOTPRINT.grow(0.3).has_point(p):
		return false
	return st == 0 and ps > 0


# --- updating --------------------------------------------------------------------------------

func _current_world() -> HouseWorld:
	var lv = game.get("levels")
	if lv != null and lv.has_method("world_of"):
		var w = lv.call("world_of", int(lv.get("player_storey")))
		if w is HouseWorld:
			return w
	return game.get("world") as HouseWorld


func _watch(w: HouseWorld) -> void:
	if w == null or _watched.has(w.get_instance_id()):
		return
	_watched[w.get_instance_id()] = true
	w.structure_changed.connect(func():
		if w == _world:
			_occ_dirty = true
			_occ_since = 0.0)


func _process(delta: float) -> void:
	if game == null or game.get("player") == null or not is_instance_valid(game.player):
		return
	if not enabled:
		if _was_on:
			_switch_off()
		return
	if not _was_on:
		_was_on = true
		_quad.visible = true
		_force = true
	if not _loaded:
		_load_seen()
	_occ_since += delta
	_tick += delta
	if _blend < 1.0:
		_blend = minf(_blend + delta * HZ, 1.0)
		_mat.set_shader_parameter("blend", _blend)
	_update_look()
	if _tick >= 1.0 / HZ:
		_tick = 0.0
		_maybe_update()
		_update_nodes()
		_update_cue()
	_save_t += delta
	if _seen_dirty and _save_t >= SAVE_EVERY:
		_store_seen()


## Re-casts now (tests, F10, after a teleport).
func refresh() -> void:
	_force = true
	_occ_dirty = true
	_occ_since = 99.0
	_maybe_update()
	_update_nodes()
	_update_cue()


func _maybe_update() -> void:
	var w := _current_world()
	if w != _world:
		_world = w
		_occ_dirty = true
		_occ_since = 99.0
	_watch(w)
	if _occ_dirty and _occ_since >= OCC_DEBOUNCE:
		var t0 := Time.get_ticks_usec()
		grid.build_occlusion(_world)
		stats["occ_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
		stats["occ_runs"] += 1
		_occ_dirty = false
		_force = true
	var pl: Node3D = game.player
	var eye := Vector2(pl.global_position.x, pl.global_position.z)
	var yaw := _yaw()
	if not _force and eye.distance_to(_last_eye) < MOVE_EPS and absf(angle_difference(yaw, _last_yaw)) < TURN_EPS and cone_deg == _last_cone:
		stats["skipped"] += 1
		return
	_force = false
	_last_eye = eye
	_last_yaw = yaw
	_last_cone = cone_deg
	_cast(eye, yaw)


func _yaw() -> float:
	var pl = game.player
	var rig = pl.get("rig")
	if rig is Node3D:
		return (rig as Node3D).rotation.y
	return (pl as Node3D).rotation.y


func _cast(eye: Vector2, yaw: float) -> void:
	var t0 := Time.get_ticks_usec()
	grid.begin()
	grid.cast(eye, Vector2(-sin(yaw), -cos(yaw)), deg_to_rad(cone_deg * 0.5), REACH, RING)
	if not peek.is_empty():
		grid.cast(peek["o"], peek["d"], float(peek["half"]), float(peek["range"]), 0.0)
	var fresh := grid.commit()
	var tmp := _tex_prev                   # the current visible layer becomes the previous one
	_tex_prev = _tex_vis
	_tex_vis = tmp
	_img_vis.set_data(grid.w, grid.h, false, Image.FORMAT_L8, grid.vis)
	_tex_vis.update(_img_vis)
	if fresh > 0 or stats["updates"] == 0:
		_img_disc.set_data(grid.w, grid.h, false, Image.FORMAT_L8, grid.disc)
		_tex_disc.update(_img_disc)
		_seen_dirty = _seen_dirty or fresh > 0
	_bind_textures()
	_blend = 0.0
	_mat.set_shader_parameter("blend", 0.0)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	stats["updates"] += 1
	stats["ms"] = ms
	stats["max_ms"] = maxf(float(stats["max_ms"]), ms)
	stats["avg_ms"] = lerpf(float(stats["avg_ms"]), ms, 0.1) if stats["updates"] > 1 else ms
	stats["rays"] = grid.rays
	stats["steps"] = grid.steps
	stats["new_cells"] = fresh
	if show_debug:
		_build_debug()


## Night colours; build mode keeps the memory light (planning anywhere).
func _update_look() -> void:
	var lt = game.get("lighting")
	var n := float(lt.get("night_amount")) if lt != null else 0.0
	var b = game.get("build")
	var building := b != null and bool(b.get("active"))
	var look := Vector4(snappedf(n, 0.02), 1.0 if building else 0.0, 0, 0)
	if look == _look:
		return
	_look = look
	_mat.set_shader_parameter("memory_color", _rgb(MEMORY_DAY.lerp(MEMORY_NIGHT, n)))
	_mat.set_shader_parameter("memory_alpha", lerpf(0.6, 0.66, n) * (0.3 if building else 1.0))
	_mat.set_shader_parameter("fog_color", _rgb(FOG_DAY.lerp(FOG_NIGHT, n)))
	_mat.set_shader_parameter("fog_alpha", lerpf(0.93, 0.96, n))


static func _rgb(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


# --- dynamic and remembered nodes ---------------------------------------------------------------

func _update_nodes() -> void:
	var tree := get_tree()
	for n in tree.get_nodes_in_group("fow_dynamic"):
		if n is Node3D:
			_show(n, sees(n))
	for n in tree.get_nodes_in_group("fow_remember"):
		if n is Node3D:
			if sees(n):
				n.set_meta("fow_seen", true)
			_show(n, n.has_meta("fow_seen"))
	var w = game.get("world")
	if w is PoiWorld:
		for k in ["pickup", "container"]:
			for s in (w as PoiWorld).spots_of(k):
				if s is PoiSpot:
					_show(s, grid.is_discovered((s as PoiSpot).interact_point()))
	for id in _hidden.keys():
		if not is_instance_valid(_hidden[id]):
			_hidden.erase(id)
	stats["hidden_nodes"] = _hidden.size()


func _show(n: Node3D, on: bool) -> void:
	var id := n.get_instance_id()
	if not on:
		if n.visible:
			n.visible = false
			_hidden[id] = n
	elif _hidden.has(id):
		_hidden.erase(id)
		n.visible = true


func _restore_nodes() -> void:
	for id in _hidden:
		var n = _hidden[id]
		if is_instance_valid(n):
			(n as Node3D).visible = true
	_hidden.clear()


func _switch_off() -> void:
	_was_on = false
	_quad.visible = false
	_restore_nodes()
	cue.strength = 0.0
	if _debug != null:
		_debug.mesh = null


# --- the proximity sense ------------------------------------------------------------------------

func _update_cue() -> void:
	var r = game.get("roster")
	var pl: Node3D = game.player
	var eye := Vector2(pl.global_position.x, pl.global_position.z)
	var ps := _player_storey()
	var best: Node = null
	var bd := PROX_RANGE
	if r != null:
		for e in r.get("enemies"):
			if not is_instance_valid(e) or not (e is AIEnemy) or not (e as AIEnemy).alive:
				continue
			var a := e as AIEnemy
			if a.storey != ps:
				continue
			var p := a.plan_pos()
			var d := p.distance_to(eye)
			if d >= bd or sees(a) or not grid.segment_clear(eye, p):
				continue
			best = a
			bd = d
	sensed = best
	if best == null:
		cue.strength = 0.0
		return
	cue.strength = clampf(1.0 - (bd - RING) / (PROX_RANGE - RING), 0.3, 1.0) * 0.9
	cue.side = _screen_side((best as AIEnemy).plan_pos() - eye)


## Plan direction -> screen direction (x right, y down), snapped to 45 degrees.
func _screen_side(d: Vector2) -> Vector2:
	var cam: Camera3D = game.get("camera")
	var right := Vector2(1, 0)
	var fwd := Vector2(0, -1)
	if cam != null and is_instance_valid(cam) and cam.is_inside_tree():
		var b := cam.global_transform.basis
		right = Vector2(b.x.x, b.x.z).normalized()
		fwd = Vector2(-b.z.x, -b.z.z).normalized()
	var s := Vector2(d.dot(right), -d.dot(fwd))
	var a := snappedf(s.angle(), PI / 4.0)
	return Vector2(cos(a), sin(a))


# --- peeking (observation holes) -----------------------------------------------------------------

func set_peek(origin: Vector3, dir: Vector3, half_deg: float, reach: float) -> void:
	var d := Vector2(dir.x, dir.z)
	peek = {"o": Vector2(origin.x, origin.z), "d": d.normalized() if d.length() > 0.001 else Vector2(0, -1),
		"half": deg_to_rad(half_deg), "range": reach}
	_force = true
	_maybe_update()
	_update_nodes()


func clear_peek() -> void:
	if peek.is_empty():
		return
	peek = {}
	_force = true


# --- memory --------------------------------------------------------------------------------------

func _layout_key() -> String:
	var w = game.get("world")
	if w is PoiWorld:
		var rec: Dictionary = (w as PoiWorld).record
		var gen = rec.get("gen", {})
		return "%s|%s" % [(w as PoiWorld).layout_id(), str(int(gen.get("seed", 0))) if gen is Dictionary else "0"]
	return "home"


func _is_home() -> bool:
	return not (game.get("world") is PoiWorld)


func _load_seen() -> void:
	var st = game.get("state")
	if st == null:
		return
	if _is_home():
		key = "home"
		var h: Dictionary = st.home if st.home is Dictionary else {}
		if not grid.load_seen(h.get("seen"), key):
			grid.clear_discovered()
		grid.discover_rect(HOME_KNOWN)
		_loaded = true
	else:
		var rec: Dictionary = (game.world as PoiWorld).record
		if rec.is_empty():
			return                             # the helper hasn't set the visit's record yet
		key = _layout_key()
		if not grid.load_seen(rec.get("seen"), key):
			grid.clear_discovered()
		_loaded = true
	_img_disc.set_data(grid.w, grid.h, false, Image.FORMAT_L8, grid.disc)
	_tex_disc.update(_img_disc)
	_force = true


func _store_seen() -> void:
	_save_t = 0.0
	if not _loaded:
		return
	_seen_dirty = false
	var st = game.get("state")
	if st == null:
		return
	if _is_home():
		st.home["seen"] = grid.save_seen("home")
	else:
		var rec: Dictionary = (game.world as PoiWorld).record
		if not rec.is_empty():
			rec["seen"] = grid.save_seen(key)


func _exit_tree() -> void:
	if _seen_dirty:
		_store_seen()


# --- debug overlay and F10 -----------------------------------------------------------------------

func _build_debug() -> void:
	if _debug == null:
		_debug = MeshInstance3D.new()
		_debug.name = "FowDebug"
		_debug.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.vertex_color_use_as_albedo = true
		m.no_depth_test = true
		m.render_priority = 121
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_debug.material_override = m
		add_child(_debug)
	if not show_debug:
		_debug.mesh = null
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := Levels.base_y(_player_storey()) + 0.06
	var hc := FowGrid.CELL * 0.45
	for j in grid.h:
		for i in grid.w:
			var k := j * grid.w + i
			var c: Color
			if grid.vis[k] != 0:
				c = Color(0.2, 1.0, 0.35, 0.28)
			elif grid.disc[k] != 0:
				continue
			else:
				c = Color(1.0, 0.2, 0.2, 0.18)
			var x := FowGrid.AREA.position.x + (i + 0.5) * FowGrid.CELL
			var z := FowGrid.AREA.position.y + (j + 0.5) * FowGrid.CELL
			_dquad(st, Vector3(x - hc, y, z - hc), Vector3(x + hc, y, z + hc), c)
	if grid.occ_size != Vector2i.ZERO:
		var ho := FowGrid.OCC_CELL * 0.4
		for j in grid.occ_size.y:
			for i in grid.occ_size.x:
				if grid.occ[j * grid.occ_size.x + i] != 0:
					var x := grid.occ_origin.x + i * FowGrid.OCC_CELL
					var z := grid.occ_origin.y + j * FowGrid.OCC_CELL
					_dquad(st, Vector3(x - ho, y + 0.01, z - ho), Vector3(x + ho, y + 0.01, z + ho), Color(1, 0.85, 0.2, 0.6))
	var e := _last_eye
	var half := deg_to_rad(cone_deg * 0.5)
	for s in [-1.0, 1.0]:
		var a: float = Vector2(-sin(_last_yaw), -cos(_last_yaw)).angle() + float(s) * half
		var d := Vector2(cos(a), sin(a))
		var n := Vector2(-d.y, d.x) * 0.04
		var p0 := e
		var p1 := e + d * 8.0
		for v in [Vector3(p0.x - n.x, y + 0.02, p0.y - n.y), Vector3(p1.x - n.x, y + 0.02, p1.y - n.y), Vector3(p1.x + n.x, y + 0.02, p1.y + n.y),
				Vector3(p0.x - n.x, y + 0.02, p0.y - n.y), Vector3(p1.x + n.x, y + 0.02, p1.y + n.y), Vector3(p0.x + n.x, y + 0.02, p0.y + n.y)]:
			st.set_color(Color(1, 1, 1, 0.8))
			st.add_vertex(v)
	_debug.mesh = st.commit()


static func _dquad(st: SurfaceTool, a: Vector3, b: Vector3, c: Color) -> void:
	for v in [Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z)]:
		st.set_color(c)
		st.add_vertex(v)


func info() -> String:
	return "Fog of war %s · cone %d° · %d updates (%.2f ms, avg %.2f, max %.2f; %d rays, %d steps) · occlusion %.1f ms ×%d · skipped %d · discovered %d/%d cells · hidden nodes %d%s" % [
		"on" if enabled else "OFF", int(cone_deg), int(stats["updates"]), float(stats["ms"]), float(stats["avg_ms"]), float(stats["max_ms"]),
		int(stats["rays"]), int(stats["steps"]), float(stats["occ_ms"]), int(stats["occ_runs"]), int(stats["skipped"]),
		grid.discovered_count(), grid.w * grid.h, int(stats["hidden_nodes"]), " · peeking" if not peek.is_empty() else ""]


func dev_toggle() -> String:
	enabled = not enabled
	if enabled:
		refresh()
	return "Fog of war %s." % ("on" if enabled else "off (everything shows)")


func dev_reveal_all() -> String:
	grid.reveal_all()
	_img_disc.set_data(grid.w, grid.h, false, Image.FORMAT_L8, grid.disc)
	_tex_disc.update(_img_disc)
	_seen_dirty = true
	refresh()
	return "Every cell is discovered (the memory is saved)."


func dev_reset() -> String:
	grid.clear_discovered()
	if _is_home():
		grid.discover_rect(HOME_KNOWN)
	_img_disc.set_data(grid.w, grid.h, false, Image.FORMAT_L8, grid.disc)
	_tex_disc.update(_img_disc)
	_seen_dirty = true
	refresh()
	return "Discovered areas reset%s." % (" (the lot stays known)" if _is_home() else "")


func dev_toggle_debug() -> String:
	show_debug = not show_debug
	_build_debug()
	return "Vision debug overlay %s (green: visible, red: undiscovered, yellow: sight blockers)." % ("on" if show_debug else "off")


func dev_set_cone(deg: float) -> String:
	cone_deg = clampf(deg, 40.0, 360.0)
	_force = true
	return "Vision cone %d°." % int(cone_deg)
