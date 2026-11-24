extends Node
## Experiment 004 (owner L): the house's storeys in the survival game. The
## game root creates this helper in _assemble() (`game.levels`) and asks it at
## a few insertion points (aiming, interactions, the view, saving).
##
##   storeys   the ground floor is the game's HouseWorld; the upper floor and
##             the basement are LevelWorlds, created when first built or dug
##             (old saves load as "ground only")
##   stairs    Levels stairs records with a StairsView and an interactable at
##             each end; walking onto them or E moves the player with a short
##             fade; the ground nav marks them SOLID (enemies go round)
##   player    `player_storey`; the player stands on its floor (floor_y); a hole
##             in the upper floor (or a window) drops you to the ground
##   build     BuildMode, the weapons and aiming target the player's storey;
##             LevelBuild adds the "Floors & levels" pieces (key 0)
##   view      storeys above the player are hidden (the upper floor stays
##             visible from outside the house, like the roof); in the basement
##             the ground floor, its yard and the enemies on it are hidden.
##             Hidden storeys keep simulating.
##   enemies   stay on their storey's nav; chasers whose target is on another
##             storey walk to the nearest stairs and follow (Levels.route);
##             bombers keep attacking the house. Blows and blasts never reach
##             through a floor (game_combat checks same_storey()).
##   save      world["levels"] (stairs, laid tiles, each LevelWorld's data);
##             the player's storey goes into RunSave.

signal storey_changed(storey: int)

const LevelBuild := preload("res://src/levels/level_build.gd")
const StairsView := preload("res://src/levels/stairs_view.gd")
const SAVE_VERSION := 1
const FADE_OUT := 0.12
const FADE_IN := 0.2
const COOLDOWN := 0.6

var game: Node                         ## SurvivalGame
var upper: LevelWorld
var basement: LevelWorld
var stairs: Array = []                 ## Levels stairs records
var laid := {}                         ## storey -> {Vector2i: true}: wooden floor tiles the player laid
var player_storey := Levels.GROUND
var build_ext: RefCounted              ## LevelBuild
var transitions := 0                   ## player storey changes (tests)
var enemy_moves := 0                   ## enemies that changed storey (tests)
var last_error := ""

var _views := {}                       ## stairs index key -> StairsView
var _ends := {}                        ## stairs key -> [StairsEnd, StairsEnd]
var _moving := false
var _cooldown := 0.0
var _blocked := ""                     ## stairs the player stands on that lead nowhere yet (one toast)
var _roof_base := INF
## Refinement 01: the roof toggle (V): the yard roof and the storeys above the
## player stay hidden, also while the player is outside the house.
var roofs_hidden := false


func setup(g: Node) -> void:
	game = g
	build_ext = LevelBuild.new(self)
	if game.build != null:
		game.build.ext = build_ext
	game.world.structure_changed.connect(_on_ground_changed)


# --- storeys -----------------------------------------------------------------------------

func world_of(storey: int) -> HouseWorld:
	match storey:
		Levels.UPPER:
			return upper
		Levels.BASEMENT:
			return basement
	return game.world


func active_world() -> HouseWorld:
	var w := world_of(player_storey)
	return w if w != null else game.world


func has_storey(storey: int) -> bool:
	return world_of(storey) != null


func _make_level(storey: int) -> LevelWorld:
	var lw := LevelWorld.new()
	lw.configure(storey, game.lighting)
	game.add_child(lw)
	lw.structure_changed.connect(_count_crates)
	lw.object_destroyed.connect(_on_level_object_destroyed)
	return lw


func ensure_basement() -> LevelWorld:
	if basement == null:
		basement = _make_level(Levels.BASEMENT)
		basement.build_new()
		basement.visible = player_storey == Levels.BASEMENT
		for st in stairs:
			_mark_stairs(st, true)
	return basement


## Builds the upper floor (no checks, no cost): deck, outer walls with
## windows, stairwells over the stairs up; the roof moves on top.
func build_upper() -> LevelWorld:
	if upper != null:
		return upper
	upper = _make_level(Levels.UPPER)
	upper.build_new()
	for st in stairs:
		if int(st["lo"]) == Levels.GROUND:
			for c in Levels.stairs_cells(st):
				Levels.remove_floor(upper, c)
	_raise_roof()
	_update_visibility()
	return upper


func _raise_roof() -> void:
	var yard: VoxelYard = game.world.yard
	if yard == null or yard.roof == null:
		return
	if _roof_base == INF:
		_roof_base = yard.roof.position.y
	yard.roof.position.y = _roof_base + (Levels.HEIGHT if upper != null else 0.0)


## Refinement 01: the roof toggle (V).
func set_roofs_hidden(on: bool) -> void:
	roofs_hidden = on
	var yard: VoxelYard = game.world.yard
	if yard != null:
		yard.hide_roof = on
	_update_visibility()


## Digs one basement cell; creates the basement on the first. False if it was dug.
func dig(c: Vector2i) -> bool:
	var b := ensure_basement()
	return b.dig(c)


# --- stairs --------------------------------------------------------------------------

static func _key(st: Dictionary) -> String:
	return "%d|%d|%d|%d" % Levels.stairs_to_array(st)


func stairs_at(p: Vector2, storey: int) -> Dictionary:
	for st in stairs:
		if Levels.joins(st, storey) and Levels.stairs_rect(st).has_point(p):
			return st
	return {}


## Adds stairs (no checks): views, nav marks and the floor changes (a hole in
## the ground floor for stairs down, a stairwell in the upper floor for up).
func add_stairs(st: Dictionary, edit_floors := true) -> void:
	stairs.append(st)
	if edit_floors:
		for c in Levels.stairs_cells(st):
			if int(st["lo"]) == Levels.GROUND:
				if upper != null:
					Levels.remove_floor(upper, c)
			else:
				Levels.remove_floor(game.world, c)
	_mark_stairs(st, true)
	var v := StairsView.make(st)
	add_child(v)
	_views[_key(st)] = v
	var ends := []
	for s in [int(st["lo"]), int(st["lo"]) + 1]:
		var e := StairsEnd.new()
		e.levels = self
		e.stairs = st
		e.storey = s
		var p := Levels.exit_point(st, s)
		e.position = Vector3(p.x, Levels.base_y(s), p.y)
		e.name = "StairsEnd_%d" % (s + 1)
		v.add_child(e)
		e.global_position = Vector3(p.x, Levels.base_y(s), p.y)
		ends.append(e)
	_ends[_key(st)] = ends
	_update_visibility()


## Takes stairs down (no refund here): the floors close again.
func remove_stairs(st: Dictionary) -> void:
	var k := _key(st)
	for i in stairs.size():
		if _key(stairs[i]) == k:
			stairs.remove_at(i)
			break
	_mark_stairs(st, false)
	for c in Levels.stairs_cells(st):
		if int(st["lo"]) == Levels.GROUND:
			if upper != null:
				Levels.lay_wood_floor(upper, c)
		else:
			Levels.lay_wood_floor(game.world, c)
	var v = _views.get(k)
	if v != null and is_instance_valid(v):
		v.queue_free()
	_views.erase(k)
	_ends.erase(k)


func _mark_stairs(st: Dictionary, on: bool) -> void:
	var r := Levels.stairs_rect(st)
	_mark_solid(game.world, r, on)
	if int(st["lo"]) == Levels.BASEMENT and basement != null:
		basement.set_static_solid(r, on)


static func _mark_solid(w: HouseWorld, r: Rect2, on: bool) -> void:
	if w is LevelWorld:
		(w as LevelWorld).set_static_solid(r, on)
		return
	# The ground floor: the furniture mask HouseWorld builds its nav from.
	var any := false
	for c in w.nav.cells_in_rect(r):
		var i := c.y * w.nav.size.x + c.x
		if w._static_solid[i] != (1 if on else 0):
			w._static_solid[i] = 1 if on else 0
			any = true
	if any:
		w._recompute_nav(r.grow(GridNav.CELL))


func _on_ground_changed() -> void:
	_count_crates()
	# keep the stairs' nav marks if the ground rebuilt its furniture mask
	for st in stairs:
		_mark_solid(game.world, Levels.stairs_rect(st), true)


# --- the player ----------------------------------------------------------------------

## Moves the player to `storey` at plan point p (instant). False if that storey
## doesn't exist.
func set_player_storey(storey: int, p: Vector2, yaw := NAN) -> bool:
	if world_of(storey) == null:
		return false
	player_storey = storey
	var y := Levels.base_y(storey)
	var pl: VoxelPlayer = game.player
	pl.floor_y = y
	pl.global_position = Vector3(p.x, y, p.y)
	pl.velocity = Vector3.ZERO
	if is_finite(yaw):
		pl.rig.rotation.y = yaw
	var fwd := -pl.rig.global_transform.basis.z
	pl.aim_point = pl.global_position + Vector3(fwd.x * 3.0, 1.1, fwd.z * 3.0)
	_retarget()
	if game.camera != null:
		game.camera.snap()
	_update_visibility()
	active_world().update_view(pl.global_position, game.camera, 5.0)
	transitions += 1
	storey_changed.emit(storey)
	return true


## The game placed the player on the ground floor (new run, wake-up, return).
func on_player_placed() -> void:
	if player_storey != Levels.GROUND or game.player.floor_y != 0.0:
		player_storey = Levels.GROUND
		game.player.floor_y = 0.0
		_retarget()
	_update_visibility()


## Takes stairs from the player's storey, with a short fade. `walked`: the
## player stepped onto them (a dead end is announced once, not every frame).
func use_stairs(st: Dictionary, walked := false) -> void:
	if _moving or not Levels.joins(st, player_storey):
		return
	var to := Levels.other_storey(st, player_storey)
	if world_of(to) == null:
		if not walked or _blocked != _key(st):
			game.toast("The stairs end at the ceiling. Build the upper floor (key 0 in build mode)." if to == Levels.UPPER
				else "There's no basement down there yet.", "warn")
		_blocked = _key(st)
		return
	await _move_player(to, Levels.exit_point(st, to), Levels.arrival_yaw(st, to))
	game.toast(Levels.name_of(to), "info")


func _move_player(storey: int, p: Vector2, yaw := NAN) -> void:
	_moving = true
	var fade: Node = game.ui.get("fade") if game.ui != null else null
	var slow: bool = fade != null and float(game.fade_time) >= 0.1 and is_inside_tree()
	if slow:
		await fade.fade_to(0.75, FADE_OUT)
	set_player_storey(storey, p, yaw)
	Sfx.play("player/footstep_2", null, -4.0)
	if slow:
		await fade.fade_to(0.0, FADE_IN)
	_moving = false
	_cooldown = COOLDOWN


func _retarget() -> void:
	var w := active_world()
	var b: Node = game.build
	if b != null:
		b.world = w
		b.plane_y = Levels.base_y(player_storey)
		b.set("_eval_key", "")
	if game.combat != null and game.combat.weapons != null:
		game.combat.weapons.world = w


func _physics_process(delta: float) -> void:
	if game == null or game.state == null or game.player == null:
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	_check_player()
	_update_enemies()


func _process(delta: float) -> void:
	if game == null or game.player == null or game.camera == null:
		return
	_update_visibility()
	for lw in [upper, basement]:
		if lw != null and lw.visible:
			lw.update_view(game.player.global_position, game.camera, delta)


func _check_player() -> void:
	if _moving or _cooldown > 0.0 or game.state.dead or str(game.call("debug_modal")) != "":
		return
	var p: Vector2 = game.player.plan_pos()
	var near := false
	for st in stairs:
		if not Levels.joins(st, player_storey):
			continue
		var r := Levels.stairs_rect(st)
		if r.grow(-0.15).has_point(p):
			use_stairs(st, true)
			return
		if r.grow(0.35).has_point(p):
			near = true
	_blocked = ""
	if player_storey == Levels.UPPER and upper != null and not near and not upper.has_floor_at(p):
		_move_player(Levels.GROUND, p)
		game.toast("You drop down to the ground floor.", "warn")


# --- enemies ---------------------------------------------------------------------------

func _update_enemies() -> void:
	if game.roster == null:
		return
	for e in game.roster.enemies:
		if not is_instance_valid(e) or not (e is AIEnemy) or not e.alive:
			continue
		var a: AIEnemy = e
		var p := a.plan_pos()
		if a.storey == Levels.UPPER and (upper == null or (not upper.has_floor_at(p) and not _near_stairs(p, Levels.UPPER))):
			move_enemy(a, Levels.GROUND, p)
			continue
		if a.storey != Levels.GROUND and (a.retreating or a.has_meta("retreat")):
			var back := Levels.route(stairs, a.storey, Levels.GROUND, p)
			move_enemy(a, Levels.GROUND, Levels.exit_point(back, Levels.GROUND) if not back.is_empty() else p)
			continue
		if a.storey == player_storey or a.retreating or str(a.def.get("behaviour", "chase")) != "chase":
			a.goal_override = Vector2.INF
			continue
		var st := Levels.route(stairs, a.storey, player_storey, p)
		if st.is_empty() or world_of(Levels.other_storey(st, a.storey)) == null:
			a.goal_override = Vector2.INF        # no way there: they come at the house instead
			continue
		var exit := Levels.exit_point(st, a.storey)
		a.goal_override = exit
		if p.distance_to(exit) < a.brain.attack_range + 0.45:
			var to := Levels.other_storey(st, a.storey)
			move_enemy(a, to, Levels.exit_point(st, to))


func _near_stairs(p: Vector2, storey: int) -> bool:
	for st in stairs:
		if Levels.joins(st, storey) and Levels.stairs_rect(st).grow(0.35).has_point(p):
			return true
	return false


## Puts an enemy on `storey` at plan point p with that storey's world and nav.
func move_enemy(e: AIEnemy, storey: int, p: Vector2) -> void:
	var w := world_of(storey)
	if w == null:
		return
	e.storey = storey
	e.floor_y = Levels.base_y(storey)
	e.global_position = Vector3(p.x, e.floor_y, p.y)
	e.velocity = Vector3.ZERO
	e.world = w
	e.nav = w.nav
	e.brain.nav = w.nav
	e.brain.planner = WeightedNav.for_nav(w.nav, float(e.def["bash_weight"]))
	e.brain.invalidate()
	e.goal_override = Vector2.INF
	e.visible = _storey_shown(storey)
	enemy_moves += 1


## True if heights a and b (body feet) are on the same storey: no blow or
## blast reaches through a floor.
static func same_storey(a: float, b: float) -> bool:
	return Levels.storey_at(a) == Levels.storey_at(b)


# --- visibility --------------------------------------------------------------------------

func _storey_shown(storey: int) -> bool:
	match storey:
		Levels.BASEMENT:
			return player_storey == Levels.BASEMENT
		Levels.GROUND:
			return player_storey >= Levels.GROUND
		Levels.UPPER:
			if player_storey == Levels.UPPER:
				return true
			return player_storey == Levels.GROUND and not roofs_hidden and not HousePlan.FOOTPRINT.grow(0.4).has_point(game.player.plan_pos())
	return true


func _update_visibility() -> void:
	if game == null or game.player == null:
		return
	var show_ground := _storey_shown(Levels.GROUND)
	if game.world.visible != show_ground:
		game.world.visible = show_ground
	var table = game.map.get("table") if game.get("map") != null else null
	if table is Node3D:
		(table as Node3D).visible = show_ground      # the map on the dining table
	if upper != null:
		upper.visible = _storey_shown(Levels.UPPER)
	if basement != null:
		basement.visible = _storey_shown(Levels.BASEMENT)
	for k in _views:
		var v: Node3D = _views[k]
		if is_instance_valid(v):
			var lo := int(v.stairs["lo"])
			v.visible = show_ground or (lo == Levels.BASEMENT and player_storey == Levels.BASEMENT)
			var pit := v.get_node_or_null("Pit") as Node3D
			if pit != null:
				pit.visible = player_storey != Levels.BASEMENT
	if game.roster != null:
		for e in game.roster.enemies:
			if is_instance_valid(e) and e is AIEnemy:
				(e as AIEnemy).visible = _storey_shown((e as AIEnemy).storey)


# --- interactions -----------------------------------------------------------------------

## What E can act on: `ground` (the game's list) on the ground floor, else the
## storey's own objects; plus the stairs' ends on the player's storey.
func interactables(ground: Array) -> Array:
	var out: Array = ground if player_storey == Levels.GROUND else active_world().interactables()
	for k in _ends:
		for e in _ends[k]:
			if is_instance_valid(e) and e.storey == player_storey:
				out.append(e)
	return out


func aim_ray(from: Vector3, dir: Vector3) -> Vector3:
	return active_world().aim_ray(from, dir)


func _count_crates() -> void:
	if game == null or game.state == null:
		return
	var n: int = game.world.count_objects("crate")
	for lw in [upper, basement]:
		if lw != null:
			n += lw.count_objects("crate")
	game.state.inventory.storage_crates = n


func _on_level_object_destroyed(kind: String, at: Vector3) -> void:
	if game.has_method("_on_object_destroyed"):
		game.call("_on_object_destroyed", kind, at)


# --- persistence ------------------------------------------------------------------------

## Adds "levels" to the world save (only when there is something to save, so
## a ground-only house saves exactly as before).
func world_save(world_data: Dictionary) -> Dictionary:
	if upper == null and basement == null and stairs.is_empty() and laid.is_empty():
		return world_data
	var st := []
	for s in stairs:
		st.append(Levels.stairs_to_array(s))
	var tiles := {}
	for s in laid:
		var cells := []
		for c in laid[s]:
			cells.append([c.x, c.y])
		tiles[str(s)] = cells
	var d := {"version": SAVE_VERSION, "stairs": st, "laid": tiles}
	if upper != null:
		d["upper"] = upper.save_data()
	if basement != null:
		d["basement"] = basement.save_data()
	world_data["levels"] = d
	return world_data


## Restores the storeys from a loaded world save and puts the player on the
## saved storey. Missing data = ground only. Damaged data: the storey is
## dropped with a warning (the ground floor still loads).
func restore(world_data: Dictionary, storey: int, pos: Variant) -> void:
	var d: Variant = world_data.get("levels")
	if typeof(d) == TYPE_DICTIONARY and int((d as Dictionary).get("version", 0)) == SAVE_VERSION:
		if typeof(d.get("upper")) == TYPE_DICTIONARY:
			var lw := _make_level(Levels.UPPER)
			if lw.load_data(d["upper"]):
				upper = lw
				_raise_roof()
			else:
				lw.queue_free()
				last_error = "upper floor"
		if typeof(d.get("basement")) == TYPE_DICTIONARY:
			var lw := _make_level(Levels.BASEMENT)
			if lw.load_data(d["basement"]):
				basement = lw
			else:
				lw.queue_free()
				last_error = "basement"
		var list: Variant = d.get("stairs", [])
		if list is Array:
			for v in list:
				var st: Variant = Levels.stairs_from_array(v)
				if st != null:
					add_stairs(st, false)
		var tiles: Variant = d.get("laid", {})
		if tiles is Dictionary:
			for k in tiles:
				var cells: Variant = Levels.cells_from_array(tiles[k])
				if cells != null:
					var s := int(str(k))
					laid[s] = {}
					for c in cells:
						laid[s][c] = true
		if last_error != "":
			game.toast("The %s could not be restored from the save." % last_error, "warn")
	_count_crates()
	if storey != Levels.GROUND and world_of(storey) != null and pos is Vector3:
		set_player_storey(storey, Vector2((pos as Vector3).x, (pos as Vector3).z), game.player.rig.rotation.y)
		transitions = 0
	_update_visibility()


# --- developer tools (F10 "Levels") -------------------------------------------------------

func dev_give_shovel() -> void:
	var n: int = game.state.inventory.add("shovel", 1)
	game.toast("Dev: a shovel." if n > 0 else "Dev: you already carry a shovel.", "info")


## The upper floor, now and free; with stairs up in the living room if there are none.
func dev_build_upper() -> void:
	if stairs.filter(func(s): return int(s["lo"]) == Levels.GROUND).is_empty():
		var st := Levels.make_stairs(Levels.GROUND, Vector2i(8, 7), 1)
		if build_ext.stairs_reason(st) == "":
			add_stairs(st)
	var had := upper != null
	build_upper()
	game.toast("Dev: the upper floor %s." % ("was already built" if had else "is built"), "info")


## A 3 x 3 m basement under the living room, now and free, with stairs down if there are none.
func dev_dig_basement() -> void:
	for j in range(6, 9):
		for i in range(6, 9):
			dig(Vector2i(i, j))
	if stairs.filter(func(s): return int(s["lo"]) == Levels.BASEMENT).is_empty():
		var st := Levels.make_stairs(Levels.BASEMENT, Vector2i(6, 8), 1)
		if build_ext.stairs_reason(st) == "":
			add_stairs(st)
	game.toast("Dev: a 3 x 3 m basement dug under the living room.", "info")


func dev_goto(storey: int) -> void:
	if world_of(storey) == null:
		game.toast("Dev: there is no %s yet." % Levels.name_of(storey).to_lower(), "warn")
		return
	var p: Vector2 = game.player.plan_pos()
	if storey == Levels.BASEMENT:
		var best := Vector2.INF
		for c in basement.dug:
			var cc := Levels.cell_center(c)
			if best == Vector2.INF or cc.distance_to(p) < best.distance_to(p):
				best = cc
		p = best
	elif storey == Levels.UPPER:
		p = p.clamp(Vector2(0.6, 0.6), Vector2(13.4, 8.4))
		if not upper.has_floor_at(p):
			p = Vector2(3.5, 6.5)
	set_player_storey(storey, p)
	game.toast("Dev: %s." % Levels.name_of(storey).to_lower(), "info")


func status_text() -> String:
	var parts := PackedStringArray()
	parts.append("on: %s" % Levels.name_of(player_storey).to_lower())
	parts.append("upper floor: %s" % ("yes" if upper != null else "no"))
	parts.append("basement: %s" % (("%d m²" % basement.dug.size()) if basement != null else "no"))
	parts.append("stairs: %d" % stairs.size())
	return " · ".join(parts)


## One end of a stairs piece: the E prompt on its storey.
class StairsEnd extends Node3D:
	var levels: Node
	var stairs: Dictionary
	var storey := 0

	func interact_prompt() -> String:
		var to := Levels.other_storey(stairs, storey)
		if to > storey:
			return "[E] Go up to the %s" % Levels.name_of(to).to_lower()
		return "[E] Go down to the %s" % Levels.name_of(to).to_lower()

	func interact(_game: Node) -> void:
		if levels != null:
			levels.use_stairs(stairs)
