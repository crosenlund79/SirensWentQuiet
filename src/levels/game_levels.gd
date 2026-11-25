extends Node
## Experiment 004 (owner L), generalised in Experiment 005 (V): the house's
## storeys in the survival game. The game root creates this helper in
## _assemble() (`game.levels`) and asks it at a few insertion points (aiming,
## interactions, the view, saving).
##
##   storeys   -2..+2 (Levels.LOWEST..HIGHEST). The ground floor is the game's
##             HouseWorld; every other storey is a LevelWorld in `worlds`,
##             created when first built (above ground: the "Next storey"
##             piece, a deck with outer walls) or dug (below ground: the
##             shovel). One set of rules for all of them; old saves load as
##             before (their "upper" / "basement" become +1 / -1).
##   stairs    Levels stairs records joining two adjacent storeys, with a
##             StairsView and an interactable at each end; walking onto them
##             or E moves the player with a short fade; both storeys' nav mark
##             them SOLID (enemies go round)
##   player    `player_storey`; the player stands on its floor (floor_y); a
##             hole in a floor drops you to the storey below
##   view      `view_storey`: the storey build mode edits and the camera
##             shows. It is the player's storey, except in build mode, where
##             PageUp / PageDown select another (the body stays put; the
##             camera lifts to that level). Storeys above the view are hidden
##             (the upper ones stay visible from the yard, outside build mode
##             and without the V toggle); underground only the viewed storey
##             shows. Hidden storeys keep simulating but don't render.
##   build     BuildMode targets the viewed storey; LevelBuild adds the
##             "Floors & levels" pieces (key 0)
##   roof      the yard's roof sits on the topmost storey (moves up with +1 /
##             +2); it fades while you're inside, and stays hidden in build
##             mode and with V
##   enemies   stay on their storey's nav; chasers whose target is on another
##             storey walk to the nearest stairs toward it and follow
##             (Levels.route, one storey at a time); bombers keep attacking
##             the house. Blows and blasts never reach through a floor
##             (game_combat checks same_storey()).
##   save      world["levels"] (version 2: stairs, laid tiles, pillars, each
##             LevelWorld's data by storey); the player's storey goes into
##             RunSave. Version 1 ("upper", "basement") still loads.
##   indicator a small HUD card ("Level +1 · First upper floor"), prominent in
##             build mode (LevelIndicator)

signal storey_changed(storey: int)
signal levels_changed                  ## Exp 005 (V): a storey was created or removed
signal view_changed(storey: int)       ## Exp 005 (V): build mode looks at another storey

const LevelBuild := preload("res://src/levels/level_build.gd")
const StairsView := preload("res://src/levels/stairs_view.gd")
const Indicator := preload("res://src/levels/level_indicator.gd")
const SAVE_VERSION := 2
const FADE_OUT := 0.12
const FADE_IN := 0.2
const COOLDOWN := 0.6

var game: Node                         ## SurvivalGame
var worlds := {}                       ## storey (not 0) -> LevelWorld
var stairs: Array = []                 ## Levels stairs records
var laid := {}                         ## storey -> {Vector2i: true}: wooden floor tiles the player laid
var pillars := {}                      ## storey -> {Vector2i: true}: masonry pillars (Exp 005)
var player_storey := Levels.GROUND
var view_storey := Levels.GROUND       ## Exp 005: the storey build mode edits and the view shows
var build_ext: RefCounted              ## LevelBuild
var indicator: CanvasLayer             ## LevelIndicator
var transitions := 0                   ## player storey changes (tests)
var enemy_moves := 0                   ## enemies that changed storey (tests)
var last_error := ""

## Compatibility with Experiment 004 callers and tests: the +1 and -1 storeys.
var upper: LevelWorld:
	get:
		return worlds.get(Levels.UPPER)
var basement: LevelWorld:
	get:
		return worlds.get(Levels.BASEMENT)

var _views := {}                       ## stairs key -> StairsView
var _ends := {}                        ## stairs key -> [StairsEnd, StairsEnd]
var _moving := false
var _cooldown := 0.0
var _blocked := ""                     ## stairs the player stands on that lead nowhere yet (one toast)
var _enemy_cd := {}                    ## enemy instance id -> seconds before it takes stairs again
var _roof_base := INF
var _lid: MeshInstance3D               ## shadow-only lid over the house while looking at an underground storey
## Refinement 01: the roof toggle (V): the yard roof and the storeys above the
## player stay hidden, also while the player is outside the house.
var roofs_hidden := false


func setup(g: Node) -> void:
	game = g
	build_ext = LevelBuild.new(self)
	if game.build != null:
		game.build.ext = build_ext
		game.build.changed.connect(_on_build_changed)
	game.world.structure_changed.connect(_on_ground_changed)
	if game.world.support != null:
		game.world.support.levels = self      # pillars prop the outer walls
	indicator = Indicator.new()
	indicator.name = "LevelIndicator"
	indicator.levels = self
	add_child(indicator)
	# The storeys above an underground view are hidden, and hidden meshes cast
	# no shadow: an invisible lid keeps the sun out of the basements.
	_lid = MeshInstance3D.new()
	_lid.name = "UndergroundLid"
	var box := BoxMesh.new()
	box.size = Vector3(60.0, 0.4, 60.0)
	_lid.mesh = box
	_lid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_lid.position = Vector3(7.0, -0.3, 4.5)
	_lid.visible = false
	add_child(_lid)


# --- storeys -----------------------------------------------------------------------------

func world_of(storey: int) -> HouseWorld:
	if storey == Levels.GROUND:
		return game.world
	return worlds.get(storey)


func active_world() -> HouseWorld:
	var w := world_of(player_storey)
	return w if w != null else game.world


func has_storey(storey: int) -> bool:
	return world_of(storey) != null


## True if storey `storey` has a walkable floor in 1 m cell c (for room
## finding: the ground floor's holes, upper decks' holes and stairwells,
## dug cells underground). False for a storey that doesn't exist.
func floor_at(storey: int, c: Vector2i) -> bool:
	var w := world_of(storey)
	if w == null or not Levels.in_house(c):
		return false
	if w is LevelWorld:
		var lw := w as LevelWorld
		if storey < Levels.GROUND and not lw.is_dug(c):
			return false
		return lw.has_floor_at(Levels.cell_center(c))
	return Levels.floor_coverage(w, c) >= 0.5


## The cells with a floor on `storey` ({Vector2i: true}); stairs cells excluded.
func floor_cells(storey: int) -> Dictionary:
	var out := {}
	var f := HousePlan.FOOTPRINT
	for j in range(int(f.position.y), int(f.end.y)):
		for i in range(int(f.position.x), int(f.end.x)):
			var c := Vector2i(i, j)
			if floor_at(storey, c) and stairs_at(Levels.cell_center(c), storey).is_empty():
				out[c] = true
	return out


## The storeys that exist, sorted (0 always).
func storeys() -> Array[int]:
	var out: Array[int] = [Levels.GROUND]
	for s in worlds:
		out.append(int(s))
	out.sort()
	return out


func top_storey() -> int:
	return storeys().max()


func bottom_storey() -> int:
	return storeys().min()


func _make_level(storey: int) -> LevelWorld:
	var lw := LevelWorld.new()
	lw.configure(storey, game.lighting)
	game.add_child(lw)
	lw.structure_changed.connect(_count_crates)
	lw.object_destroyed.connect(_on_level_object_destroyed)
	return lw


## Creates an underground storey (-1 or -2: solid earth) if it doesn't exist.
func ensure_underground(storey: int) -> LevelWorld:
	if storey >= Levels.GROUND or storey < Levels.LOWEST:
		return null
	if not worlds.has(storey):
		var lw := _make_level(storey)
		lw.build_new()
		worlds[storey] = lw
		_storey_added(storey)
	return worlds[storey]


func ensure_basement() -> LevelWorld:
	return ensure_underground(Levels.BASEMENT)


## Builds a storey above ground (no checks, no cost): deck, outer walls with
## windows, stairwells over the stairs coming up; the roof moves on top.
func build_storey(storey: int) -> LevelWorld:
	if storey <= Levels.GROUND or storey > Levels.HIGHEST:
		return null
	if worlds.has(storey):
		return worlds[storey]
	var lw := _make_level(storey)
	lw.build_new()
	worlds[storey] = lw
	for st in stairs:
		if int(st["lo"]) == storey - 1:
			for c in Levels.stairs_cells(st):
				Levels.remove_floor(lw, c)
	_storey_added(storey)
	return lw


func build_upper() -> LevelWorld:
	return build_storey(Levels.UPPER)


func _storey_added(storey: int) -> void:
	for st in stairs:
		if Levels.joins(st, storey):
			_mark_stairs(st, true)
	_place_roof()
	_link_support()
	_retarget()
	_update_visibility()
	levels_changed.emit()


func _link_support() -> void:
	var m: HouseSupport = game.world.support
	if m == null:
		return
	m.levels = self
	for s in range(Levels.UPPER, Levels.HIGHEST + 1):
		m.set_storey(s, worlds.get(s))


## The yard's roof sits on the topmost storey above ground.
func _place_roof() -> void:
	var yard: VoxelYard = game.world.yard
	if yard == null or yard.roof == null:
		return
	if _roof_base == INF:
		_roof_base = yard.roof.position.y
	yard.roof.position.y = _roof_base + Levels.HEIGHT * float(maxi(top_storey(), 0))


func _raise_roof() -> void:
	_place_roof()


func roof_storey() -> int:
	return maxi(top_storey(), Levels.GROUND)


## Refinement 01: the roof toggle (V).
func set_roofs_hidden(on: bool) -> void:
	roofs_hidden = on
	_apply_roof_hide()
	_update_visibility()


## The roof hides with V and always in build mode (it never gets in the way of building).
func _apply_roof_hide() -> void:
	var yard: VoxelYard = game.world.yard
	if yard != null:
		yard.hide_roof = roofs_hidden or _building()


func _building() -> bool:
	return game != null and game.build != null and game.build.active


## Digs one cell of an underground storey (-1 by default); creates the storey
## on the first. False if it was dug.
func dig(c: Vector2i, storey := Levels.BASEMENT) -> bool:
	var b := ensure_underground(storey)
	return b != null and b.dig(c)


# --- the viewed / edited storey (Exp 005) -------------------------------------------------

## The storeys PageUp / PageDown can show in build mode: the existing ones
## and the next one to build above and to dig below.
func view_choices() -> Array[int]:
	var out := storeys()
	if out.max() < Levels.HIGHEST:
		out.append(out.max() + 1)
	if out.min() > Levels.LOWEST:
		out.push_front(out.min() - 1)
	return out


## Shows and edits `storey` in build mode (the body stays where it is).
func set_view_storey(storey: int) -> void:
	storey = clampi(storey, Levels.LOWEST, Levels.HIGHEST)
	if storey == view_storey:
		return
	view_storey = storey
	_retarget()
	_update_visibility()
	view_changed.emit(storey)


## PageUp (+1) / PageDown (-1) in build mode. Returns the message shown.
func step_view(dir: int) -> String:
	var ch := view_choices()
	var target := view_storey
	for s in (ch if dir > 0 else _reversed(ch)):
		if (dir > 0 and s > view_storey) or (dir < 0 and s < view_storey):
			target = s
			break
	var text := ""
	if target == view_storey:
		text = "Nothing above %s." % Levels.label(view_storey) if dir > 0 else "Nothing below %s." % Levels.label(view_storey)
		if dir > 0 and view_storey < Levels.HIGHEST:
			text = "Build %s first." % Levels.label(view_storey)
		elif dir < 0 and view_storey > Levels.LOWEST:
			text = "Dig %s first." % Levels.label(view_storey)
	else:
		set_view_storey(target)
		text = "Building on %s" % Levels.label(target)
		if world_of(target) == null:
			text += " (not there yet: %s)" % ("Next storey, key 0, builds it" if target > 0 else "Excavate, key 0, digs it")
		text += "."
	if game.has_method("toast"):
		game.toast(text, "info")
	return text


static func _reversed(a: Array[int]) -> Array[int]:
	var out := a.duplicate()
	out.reverse()
	return out


func _on_build_changed() -> void:
	if not _building() and view_storey != player_storey:
		set_view_storey(player_storey)
	_apply_roof_hide()
	_update_visibility()


func _unhandled_input(event: InputEvent) -> void:
	if not _building() or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = (event as InputEventKey).keycode
	if k == KEY_PAGEUP or k == KEY_PAGEDOWN:
		step_view(1 if k == KEY_PAGEUP else -1)
		get_viewport().set_input_as_handled()


# --- stairs --------------------------------------------------------------------------

static func _key(st: Dictionary) -> String:
	return "%d|%d|%d|%d" % Levels.stairs_to_array(st)


func stairs_at(p: Vector2, storey: int) -> Dictionary:
	for st in stairs:
		if Levels.joins(st, storey) and Levels.stairs_rect(st).has_point(p):
			return st
	return {}


## Adds stairs (no checks): views, nav marks and the floor change (a hole in
## the upper of the two storeys' floor over both cells: a stairwell for
## stairs up, the opening for stairs down).
func add_stairs(st: Dictionary, edit_floors := true) -> void:
	stairs.append(st)
	if edit_floors:
		var top := world_of(int(st["lo"]) + 1)
		if top != null:
			for c in Levels.stairs_cells(st):
				Levels.remove_floor(top, c)
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
		e.name = "StairsEnd_%d" % (s + 3)
		v.add_child(e)
		e.global_position = Vector3(p.x, Levels.base_y(s), p.y)
		ends.append(e)
	_ends[_key(st)] = ends
	_update_visibility()


## Takes stairs down (no refund here): the floor closes again.
func remove_stairs(st: Dictionary) -> void:
	var k := _key(st)
	for i in stairs.size():
		if _key(stairs[i]) == k:
			stairs.remove_at(i)
			break
	_mark_stairs(st, false)
	var top := world_of(int(st["lo"]) + 1)
	if top != null:
		for c in Levels.stairs_cells(st):
			Levels.lay_wood_floor(top, c)
	var v = _views.get(k)
	if v != null and is_instance_valid(v):
		v.queue_free()
	_views.erase(k)
	_ends.erase(k)


func _mark_stairs(st: Dictionary, on: bool) -> void:
	var r := Levels.stairs_rect(st)
	for s in [int(st["lo"]), int(st["lo"]) + 1]:
		var w := world_of(s)
		if w != null:
			_mark_solid(w, r, on)


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
		if Levels.joins(st, Levels.GROUND):
			_mark_solid(game.world, Levels.stairs_rect(st), true)


# --- pillars (Exp 005) ---------------------------------------------------------------------

## Builds a masonry pillar in cell c of `storey` (no checks, no cost).
func add_pillar(storey: int, c: Vector2i) -> bool:
	var w := world_of(storey)
	if w == null:
		return false
	if not pillars.has(storey):
		pillars[storey] = {}
	pillars[storey][c] = true
	Levels.stamp_pillar(w, c)
	return true


func remove_pillar(storey: int, c: Vector2i) -> void:
	var w := world_of(storey)
	if pillars.has(storey):
		pillars[storey].erase(c)
	if w != null:
		Levels.clear_pillar(w, c)


func pillar_at(storey: int, p: Vector2) -> Variant:
	var c := Levels.cell_of(p)
	if pillars.get(storey, {}).has(c) and Levels.pillar_rect(c).grow(0.3).has_point(p):
		return c
	return null


## Standing pillars (at least half their masonry) of the storey whose world is w.
func pillars_on(w: HouseWorld) -> Array:
	var out := []
	for s in pillars:
		if world_of(s) != w:
			continue
		for c in pillars[s]:
			if Levels.pillar_stands(w, c):
				out.append(c)
	return out


# --- the player ----------------------------------------------------------------------

## Moves the player to `storey` at plan point p (instant). False if that storey
## doesn't exist.
func set_player_storey(storey: int, p: Vector2, yaw := NAN) -> bool:
	if world_of(storey) == null:
		return false
	player_storey = storey
	view_storey = storey
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
	view_changed.emit(storey)
	return true


## The game placed the player on the ground floor (new run, wake-up, return).
func on_player_placed() -> void:
	if player_storey != Levels.GROUND or game.player.floor_y != 0.0 or view_storey != Levels.GROUND:
		player_storey = Levels.GROUND
		view_storey = Levels.GROUND
		game.player.floor_y = 0.0
		_retarget()
		storey_changed.emit(player_storey)
	_update_visibility()


## Takes stairs from the player's storey, with a short fade. `walked`: the
## player stepped onto them (a dead end is announced once, not every frame).
func use_stairs(st: Dictionary, walked := false) -> void:
	if _moving or not Levels.joins(st, player_storey):
		return
	var to := Levels.other_storey(st, player_storey)
	if world_of(to) == null:
		if not walked or _blocked != _key(st):
			game.toast("The stairs end at the ceiling. Build the next storey (key 0 in build mode)." if to > player_storey
				else "There's nothing dug out down there yet.", "warn")
		_blocked = _key(st)
		return
	await _move_player(to, Levels.exit_point(st, to), Levels.arrival_yaw(st, to))
	game.toast(Levels.label(to), "info")


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


## Points build mode at the viewed storey and the weapons at the player's.
func _retarget() -> void:
	var b: Node = game.build
	if b != null:
		var w := world_of(view_storey)
		if w == null:                          # a storey not built yet: the nearest one toward the ground
			w = world_of(view_storey - signi(view_storey))
		b.world = w if w != null else game.world
		b.plane_y = Levels.base_y(view_storey)
		b.set("_eval_key", "")
	if game.combat != null and game.combat.weapons != null:
		game.combat.weapons.world = active_world()
	if game.camera != null and "lift" in game.camera:
		game.camera.lift = Levels.base_y(view_storey) - Levels.base_y(player_storey)


func _physics_process(delta: float) -> void:
	if game == null or game.state == null or game.player == null:
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	for k in _enemy_cd.keys():
		_enemy_cd[k] -= delta
		if _enemy_cd[k] <= 0.0:
			_enemy_cd.erase(k)
	_check_player()
	_update_enemies()


func _process(delta: float) -> void:
	if game == null or game.player == null or game.camera == null:
		return
	_apply_roof_hide()
	_update_visibility()
	var pp: Vector3 = game.player.global_position
	var at := Vector3(pp.x, Levels.base_y(view_storey), pp.z) if view_storey != player_storey else pp
	for s in worlds:
		var lw: LevelWorld = worlds[s]
		if lw != null and lw.visible:
			lw.update_view(at, game.camera, delta)


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
	if near or player_storey == Levels.GROUND:
		return
	var below := fall_target(player_storey, p)
	if below != player_storey:
		_move_player(below, p)
		game.toast("You drop down to the %s." % Levels.name_of(below).to_lower(), "warn")


## Where a body on `storey` at plan point p ends up: `storey` if it has a floor
## there; else the storey below (above ground always, down to the ground
## floor; below ground only into dug space of the storey below).
func fall_target(storey: int, p: Vector2) -> int:
	var w := world_of(storey)
	if storey == Levels.GROUND or (w is LevelWorld and (w as LevelWorld).has_floor_at(p)):
		return storey
	if storey > Levels.GROUND:
		return storey - 1
	var lw := world_of(storey - 1) as LevelWorld
	if lw != null and lw.is_dug(Levels.cell_of(p)):
		return storey - 1
	return storey


# --- enemies ---------------------------------------------------------------------------

func _update_enemies() -> void:
	if game.roster == null:
		return
	for e in game.roster.enemies:
		if not is_instance_valid(e) or not (e is AIEnemy) or not e.alive:
			continue
		var a: AIEnemy = e
		var p := a.plan_pos()
		if a.storey != Levels.GROUND:
			if world_of(a.storey) == null:
				move_enemy(a, Levels.GROUND, p)
				continue
			if not _near_stairs(p, a.storey):
				var to := fall_target(a.storey, p)
				if to != a.storey:
					move_enemy(a, to, p)
					continue
		if a.storey != Levels.GROUND and (a.retreating or a.has_meta("retreat")):
			var back := Levels.route(stairs, a.storey, Levels.GROUND, p)
			var to_s := a.storey + signi(Levels.GROUND - a.storey)
			move_enemy(a, to_s, Levels.exit_point(back, to_s) if not back.is_empty() else p)
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
		if p.distance_to(exit) < a.brain.attack_range + 0.45 and not _enemy_cd.has(a.get_instance_id()):
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
	e.visible = storey_shown(storey)
	enemy_moves += 1
	_enemy_cd[e.get_instance_id()] = COOLDOWN       # a short walk off the stairs before the next ones


## True if heights a and b (body feet) are on the same storey: no blow or
## blast reaches through a floor.
static func same_storey(a: float, b: float) -> bool:
	return Levels.storey_at(a) == Levels.storey_at(b)


# --- visibility --------------------------------------------------------------------------

## True if `storey` is drawn: the viewed storey and, above ground, the ones
## under it; the ones over it only from the yard (not in build mode, not with
## V). Underground only the viewed storey shows.
func storey_shown(storey: int) -> bool:
	var v := view_storey
	if storey == v:
		return true
	if storey < Levels.GROUND or v < Levels.GROUND:
		return false
	if storey < v:
		return true
	if roofs_hidden or _building() or game == null or game.player == null:
		return false
	return not HousePlan.FOOTPRINT.grow(0.4).has_point(game.player.plan_pos())


func _storey_shown(storey: int) -> bool:
	return storey_shown(storey)


func _update_visibility() -> void:
	if game == null or game.player == null:
		return
	var show_ground := storey_shown(Levels.GROUND)
	if game.world.visible != show_ground:
		game.world.visible = show_ground
	var table = game.map.get("table") if game.get("map") != null else null
	if table is Node3D:
		(table as Node3D).visible = show_ground      # the map on the dining table
	for s in worlds:
		var lw: LevelWorld = worlds[s]
		if lw != null:
			lw.visible = storey_shown(s)
	for k in _views:
		var v: Node3D = _views[k]
		if is_instance_valid(v):
			var lo := int(v.stairs["lo"])
			var lo_shown := storey_shown(lo)
			v.visible = lo_shown or storey_shown(lo + 1)
			var pit := v.get_node_or_null("Pit") as Node3D
			if pit != null:
				pit.visible = not lo_shown        # stairs down seen from above: a dark pit
	if _lid != null:
		_lid.visible = view_storey < Levels.GROUND
	# the player's body only where its storey shows (build mode looking at a level below)
	var body_shown := storey_shown(player_storey)
	if game.player.visible != body_shown:
		game.player.visible = body_shown
	if game.roster != null:
		for e in game.roster.enemies:
			if is_instance_valid(e) and e is AIEnemy:
				(e as AIEnemy).visible = storey_shown((e as AIEnemy).storey)


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
	for s in worlds:
		if worlds[s] != null:
			n += worlds[s].count_objects("crate")
	game.state.inventory.storage_crates = n


func _on_level_object_destroyed(kind: String, at: Vector3) -> void:
	if game.has_method("_on_object_destroyed"):
		game.call("_on_object_destroyed", kind, at)


# --- persistence ------------------------------------------------------------------------

## Adds "levels" to the world save (only when there is something to save, so
## a ground-only house saves exactly as before).
func world_save(world_data: Dictionary) -> Dictionary:
	if worlds.is_empty() and stairs.is_empty() and laid.is_empty() and pillars.is_empty():
		return world_data
	var st := []
	for s in stairs:
		st.append(Levels.stairs_to_array(s))
	var d := {"version": SAVE_VERSION, "stairs": st, "laid": _cells_save(laid), "pillars": _cells_save(pillars),
		"roof_storey": roof_storey(), "storeys": {}}
	for s in worlds:
		if worlds[s] != null:
			d["storeys"][str(s)] = worlds[s].save_data()
	world_data["levels"] = d
	return world_data


static func _cells_save(by_storey: Dictionary) -> Dictionary:
	var out := {}
	for s in by_storey:
		var cells := []
		for c in by_storey[s]:
			cells.append([c.x, c.y])
		if not cells.is_empty():
			out[str(s)] = cells
	return out


static func _cells_load(v: Variant) -> Dictionary:
	var out := {}
	if not (v is Dictionary):
		return out
	for k in v:
		var s := int(str(k))
		var cells: Variant = Levels.cells_from_array(v[k])
		if cells == null or not Levels.valid(s):
			continue
		out[s] = {}
		for c in cells:
			out[s][c] = true
	return out


## Restores the storeys from a loaded world save and puts the player on the
## saved storey. Missing data = ground only. Damaged data: the storey is
## dropped with a warning (the ground floor still loads). Version 1 saves
## ("upper", "basement") load as +1 / -1.
func restore(world_data: Dictionary, storey: int, pos: Variant) -> void:
	var d: Variant = world_data.get("levels")
	if typeof(d) == TYPE_DICTIONARY and int((d as Dictionary).get("version", 0)) in [1, SAVE_VERSION]:
		var data := {}
		if int(d["version"]) == 1:
			for k in [["upper", Levels.UPPER], ["basement", Levels.BASEMENT]]:
				if typeof(d.get(k[0])) == TYPE_DICTIONARY:
					data[k[1]] = d[k[0]]
		elif typeof(d.get("storeys")) == TYPE_DICTIONARY:
			for k in d["storeys"]:
				var s := int(str(k))
				if Levels.valid(s) and s != Levels.GROUND and typeof(d["storeys"][k]) == TYPE_DICTIONARY:
					data[s] = d["storeys"][k]
		var keys := data.keys()
		keys.sort()
		for s in keys:
			var lw := _make_level(s)
			if lw.load_data(data[s]):
				worlds[s] = lw
			else:
				lw.queue_free()
				last_error = Levels.name_of(s).to_lower()
		_place_roof()
		_link_support()
		var list: Variant = d.get("stairs", [])
		if list is Array:
			for v in list:
				var st: Variant = Levels.stairs_from_array(v)
				if st != null:
					add_stairs(st, false)
		laid = _cells_load(d.get("laid", {}))
		pillars = _cells_load(d.get("pillars", {}))
		if last_error != "":
			game.toast("The %s could not be restored from the save." % last_error, "warn")
		if not worlds.is_empty():
			levels_changed.emit()
	_count_crates()
	if storey != Levels.GROUND and world_of(storey) != null and pos is Vector3:
		set_player_storey(storey, Vector2((pos as Vector3).x, (pos as Vector3).z), game.player.rig.rotation.y)
		transitions = 0
	_update_visibility()


# --- developer tools (F10 "Levels") -------------------------------------------------------

func dev_give_shovel() -> void:
	var n: int = game.state.inventory.add("shovel", 1)
	game.toast("Dev: a shovel." if n > 0 else "Dev: you already carry a shovel.", "info")


## Stairs from `lo` at cell c (rot), if there are none from `lo` yet and they fit.
func _dev_stairs(lo: int, c: Vector2i, rot: int) -> void:
	if not stairs.filter(func(s): return int(s["lo"]) == lo).is_empty():
		return
	var st := Levels.make_stairs(lo, c, rot)
	var why: String = build_ext.stairs_reason(st)
	if why == "":
		add_stairs(st)
	else:
		push_warning("dev stairs from %d at %s: %s" % [lo, str(c), why])


## The first upper floor, now and free; with stairs up in the living room if there are none.
func dev_build_upper() -> void:
	_dev_stairs(Levels.GROUND, Vector2i(8, 7), 1)
	var had := upper != null
	build_storey(Levels.UPPER)
	game.toast("Dev: the upper floor %s." % ("was already built" if had else "is built"), "info")


## A 3 x 3 m basement under the living room, now and free, with stairs down if there are none.
func dev_dig_basement() -> void:
	for j in range(6, 9):
		for i in range(6, 9):
			dig(Vector2i(i, j))
	_dev_stairs(Levels.BASEMENT, Vector2i(6, 8), 1)
	game.toast("Dev: a 3 x 3 m basement dug under the living room.", "info")


## Exp 005: every storey for inspection, now and free: +1 and +2 with stairs
## up, a 3 x 3 m basement (-1) and lower basement (-2) with stairs down.
func dev_build_all() -> void:
	_dev_stairs(Levels.GROUND, Vector2i(8, 7), 1)
	build_storey(Levels.UPPER)
	_dev_stairs(Levels.UPPER, Vector2i(2, 6), 1)
	build_storey(Levels.UPPER2)
	for j in range(6, 9):
		for i in range(6, 9):
			dig(Vector2i(i, j), Levels.BASEMENT)
	_dev_stairs(Levels.BASEMENT, Vector2i(6, 8), 1)
	for j in range(6, 9):
		for i in range(5, 8):
			dig(Vector2i(i, j), Levels.LOWER_BASEMENT)
	_dev_stairs(Levels.LOWER_BASEMENT, Vector2i(7, 6), 3)
	game.toast("Dev: all five levels: %s." % status_text(), "info")


## Exp 005: every storey's structure and objects back to their design (what
## the player built and laid included; collapsed decks stay gone).
func dev_repair_levels() -> void:
	game.world.repair_all()
	for s in worlds:
		if worlds[s] != null:
			worlds[s].repair_all()
	game.toast("Dev: every level repaired.", "info")


func dev_goto(storey: int) -> void:
	if world_of(storey) == null:
		game.toast("Dev: there is no %s yet." % Levels.name_of(storey).to_lower(), "warn")
		return
	var p: Vector2 = game.player.plan_pos()
	if storey < Levels.GROUND:
		var lw: LevelWorld = worlds[storey]
		var best := Vector2.INF
		for c in lw.dug:
			var cc := Levels.cell_center(c)
			if _near_stairs(cc, storey) or not lw.has_floor_at(cc):
				continue
			if best == Vector2.INF or cc.distance_to(p) < best.distance_to(p):
				best = cc
		if best == Vector2.INF:
			game.toast("Dev: no free floor on the %s." % Levels.name_of(storey).to_lower(), "warn")
			return
		p = best
	elif storey > Levels.GROUND:
		var lw: LevelWorld = worlds[storey]
		p = p.clamp(Vector2(0.6, 0.6), Vector2(13.4, 8.4))
		if not lw.has_floor_at(p) or _near_stairs(p, storey):
			p = Vector2.INF
			for j in 9:
				for i in 14:
					var cc := Levels.cell_center(Vector2i(i, j))
					if p == Vector2.INF and lw.has_floor_at(cc) and not _near_stairs(cc, storey) and not Levels.wall_on(lw, Vector2i(i, j)):
						p = cc
			if p == Vector2.INF:
				game.toast("Dev: no free floor on the %s." % Levels.name_of(storey).to_lower(), "warn")
				return
	set_player_storey(storey, p)
	game.toast("Dev: %s." % Levels.label(storey), "info")


func status_text() -> String:
	var parts := PackedStringArray()
	parts.append("on %s" % Levels.label(player_storey))
	for s in storeys():
		if s == Levels.GROUND:
			continue
		var lw: LevelWorld = worlds[s]
		parts.append(("%s: %d m² dug" % [Levels.number(s), lw.dug.size()]) if s < 0 else ("%s: built" % Levels.number(s)))
	parts.append("stairs: %d" % stairs.size())
	var n := 0
	for s in pillars:
		n += (pillars[s] as Dictionary).size()
	if n > 0:
		parts.append("pillars: %d" % n)
	parts.append("roof on %s" % Levels.number(roof_storey()))
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
