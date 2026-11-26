extends "res://tests/test_case.gd"
## Exp 009 (R): the loading screen and the staged boot of the game scene
## (src/ui/loading_screen.gd, src/game/game_boot.gd, survival_game.gd
## _boot_staged). The tests opt in with GameLaunch.staged = true (the real
## travel flow and Continue set it through LoadingScreen.change_scene).

const SCENE := "res://src/game/game.tscn"
const SAVE := "user://test_loading_screen.dat"
const TravelFlow := preload("res://src/travel/travel_flow.gd")

var _closed := []                      ## [{"history", "shown", "title"}] of the screens that closed


func _boot(mode: String, staged := false) -> Node:
	SaveGame.path_override = SAVE
	GameLaunch.mode = mode
	GameLaunch.seed = 9009
	GameLaunch.staged = staged
	var g: Node = (load(SCENE) as PackedScene).instantiate()
	g.stay_in_scene = true
	g.skip_intro = true
	g.fade_time = 0.02
	g.death_delay = 0.05
	g.aim_with_mouse = false
	var fired := []
	g.site_ready.connect(func() -> void: fired.append(Engine.get_process_frames()))
	g.set_meta("fired", fired)
	add(g)
	tree.current_scene = g
	if staged:
		var ls: LoadingScreen = g.loading
		check(ls != null, "the staged boot opens a loading screen")
		if ls != null:
			ls.closed.connect(func() -> void: _closed.append({"history": ls.history.duplicate(true), "shown": ls.was_shown, "title": ls.title}))
		check(not GameLaunch.staged, "the flag is used up")
		await _wait_until(func() -> bool: return not fired.is_empty(), 900)
		check(not fired.is_empty(), "site_ready fires after the staged boot")
		await frames(2)
	else:
		await frames(3)
	return g


func _wait_until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await frames(1)
	return cond.call()


func cleanup() -> void:
	tree.paused = false
	if SaveGame.path_override == SAVE:
		SaveGame.delete_save()
	SaveGame.path_override = ""
	GameLaunch.mode = "new"
	GameLaunch.seed = 0
	GameLaunch.notice = ""
	GameLaunch.site = "home"
	GameLaunch.carry = {}
	GameLaunch.staged = false
	GameBoot.debug_invalid_site = ""
	TravelFlow.skip_animation = false
	LoadingScreen.close_current()
	await super.cleanup()


## The carry a departure from home for `id` hands to the next scene.
func _carry_to(g: Node, id: String, car := false, minutes := 30) -> Dictionary:
	var s: GameState = g.debug_state()
	return {"state": s.to_dict(), "home": g.compose_home_save(),
		"travel": {"to": id, "car": car, "minutes": minutes, "depart_at": s.total_minutes, "leg": "out", "stops": []}}


func _monotonic(history: Array) -> bool:
	for i in range(1, history.size()):
		if float(history[i]["progress"]) < float(history[i - 1]["progress"]) - 0.000001:
			return false
	return true


func _texts(history: Array) -> Array:
	var out := []
	for h in history:
		if out.is_empty() or out.back() != h["text"]:
			out.append(h["text"])
	return out


## The first frame a stage text was drawn on.
func _frame_of(history: Array, text: String) -> int:
	for h in history:
		if h["text"] == text:
			return int(h["frame"])
	return -1


# --- the screen ----------------------------------------------------------------------------

func test_progress_is_stage_weighted_and_never_goes_back() -> void:
	var host: Node = add(Node.new())
	var ls := LoadingScreen.open(host, "Entering somewhere")
	check(LoadingScreen.current() == ls, "one screen at a time")
	check(LoadingScreen.open(host, "Returning home") == ls and ls.title == "Returning home", "open() reuses the open one")
	ls.plan([["a", 1.0, "First…"], ["b", 3.0, "Second…"]])
	ls.begin("a")
	check_eq(ls.progress, 0.0, "nothing done yet")
	ls.set_fraction(0.5)
	check(is_equal_approx(ls.progress, 0.125), "half of a quarter (%f)" % ls.progress)
	ls.begin("b")
	check(is_equal_approx(ls.progress, 0.25), "a done (%f)" % ls.progress)
	check_eq(ls.stage_text, "Second…", "the stage line")
	ls.set_fraction(0.5)
	check(is_equal_approx(ls.progress, 0.625), "half of b (%f)" % ls.progress)
	ls.set_fraction(0.2)
	check(is_equal_approx(ls.progress, 0.625), "never back (%f)" % ls.progress)
	ls.plan([["c", 1.0, "Third…"]])
	ls.begin("c")
	ls.set_fraction(0.5)
	check(is_equal_approx(ls.progress, 0.8125), "a new plan shares what's left (%f)" % ls.progress)
	ls.finish()
	check_eq(ls.progress, 1.0, "full at the end")
	# a scene change: the scene's loading is a small first share, the game's boot the rest
	var sc := LoadingScreen.open(host, "Entering somewhere")
	sc.begin_scene_load()
	sc.set_fraction(1.0)
	check(sc.progress > 0.0 and sc.progress <= 0.1, "the scene loaded (%f)" % sc.progress)
	sc.plan([["site", 1.0, "Preparing interior…"]])
	sc.begin("site")
	sc.set_fraction(0.5)
	check(sc.progress > 0.5 and sc.progress < 0.6, "the boot shares the rest (%f)" % sc.progress)
	sc.finish()
	check(LoadingScreen.current() == null, "closed")
	await frames(2)


func test_an_instant_operation_shows_nothing() -> void:
	var host: Node = add(Node.new())
	var ls := LoadingScreen.open(host, "Returning home")
	ls.plan([["a", 1.0, "Quick…"], ["b", 1.0, "Quicker…"]])
	ls.begin("a")
	ls.set_fraction(1.0)
	ls.begin("b")
	ls.finish()
	check(not ls.was_shown and not ls.visible, "under %d ms nothing is shown" % LoadingScreen.SHOW_AFTER_MS)
	await frames(2)
	# a slow one shows at its next stage after the threshold
	var slow := LoadingScreen.open(host, "Entering somewhere")
	slow.plan([["a", 1.0, "Slow…"], ["b", 1.0, "Then…"]])
	slow.begin("a")
	check(not slow.visible, "not at once")
	while slow.elapsed_ms() < LoadingScreen.SHOW_AFTER_MS + 30:
		await frames(1)
	check(not slow.visible, "not between updates")
	slow.begin("b")
	check(slow.was_shown and slow.visible, "shown at the stage after the threshold")
	slow.finish()
	await frames(2)


# --- the staged boot -------------------------------------------------------------------------

## A PoiWorld built step by step is the PoiWorld build_new makes.
func test_poi_build_job_matches_build_new() -> void:
	var lighting: VoxelLighting = add(VoxelLighting.new())
	var a := PoiWorld.new()
	a.configure("clinic", lighting, true)
	add(a)
	a.build_new()
	var b := PoiWorld.new()
	b.configure("clinic", lighting, true)
	add(b)
	var job := b.begin_build()
	var stages := []
	while not job.step():
		if stages.is_empty() or stages.back() != job.stage:
			stages.append(job.stage)
	check_eq(stages, ["interior", "furniture", "containers"], "the build's stages")
	check(job.steps > 100, "many small steps (%d)" % job.steps)
	check_eq(b.chunks.face_count, a.chunks.face_count, "the same voxel faces")
	check_eq(b.objects.size(), a.objects.size(), "the same doors")
	check_eq(b.spots.size(), a.spots.size(), "the same spots")
	check_eq(b.props.size(), a.props.size(), "the same pieces")
	check_eq(b.get_child_count(), a.get_child_count(), "the same nodes")
	check(not b.chunks.needs_build(), "every chunk built")


func test_staged_arrival_at_a_poi_reaches_site_ready() -> void:
	var g: Node = await _boot("new")
	var s: GameState = g.debug_state()
	s.total_minutes = 9.0 * 60.0
	var carry := _carry_to(g, "clinic", false, 40)
	g.queue_free()
	await frames(2)
	GameLaunch.site = "clinic"
	GameLaunch.carry = carry
	var p: Node = await _boot("carry", true)
	check(not p.is_home() and p.world is PoiWorld, "at the clinic")
	check(not p.world.chunks.needs_build() and p.world.chunks.face_count > 0, "its chunks are built")
	check(p.world.process_mode == Node.PROCESS_MODE_INHERIT, "the place runs again")
	check(p.poi != null, "the POI helper is there")
	check(p.debug_modal() == "" and p.player.input_enabled, "playable afterwards")
	check(p.autosave_log.has("arrived"), "travel's arrival ran after the boot (%s)" % [p.autosave_log])
	check(absf(p.debug_state().total_minutes - (9.0 * 60.0 + 40.0)) < 0.5, "the road's time passed once (%f)" % p.debug_state().total_minutes)
	check_eq(_closed.size(), 1, "the screen closed")
	if _closed.is_empty():
		return
	var h: Array = _closed[0]["history"]
	check(_monotonic(h), "progress only grows")
	check_eq(float(h.back()["progress"]), 1.0, "and ends full")
	check(_closed[0]["shown"], "a real arrival shows the screen")
	check_eq(_closed[0]["title"], "Entering %s" % RegionLocations.name_of("clinic"), "the destination")
	var texts := _texts(h)
	for t in ["Preparing interior…", "Placing furniture…", "Populating containers…", "Preparing inhabitants…", "Final preparation…"]:
		check(texts.has(t), "stage '%s' (%s)" % [t, texts])
	check(_frame_of(h, "Placing furniture…") > _frame_of(h, "Preparing interior…"), "the screen redraws between stages")
	check(p.boot_frames >= 8, "the boot spans several frames (%d)" % p.boot_frames)
	print("    staged arrival at the clinic: %.0f ms, %d frames, %d updates" % [p.boot_ms, p.boot_frames, h.size()])


func test_staged_return_home_reaches_site_ready() -> void:
	var g: Node = await _boot("new")
	var s: GameState = g.debug_state()
	s.total_minutes = 9.0 * 60.0
	var carry := _carry_to(g, "convenience")
	g.queue_free()
	await frames(2)
	GameLaunch.site = "convenience"
	GameLaunch.carry = carry
	var p: Node = await _boot("carry")
	var why: String = await p.travel.leave_for_home(true)
	check_eq(why, "", "leaves for home")
	p.queue_free()
	await frames(2)
	var h0: Node = await _boot("carry", true)
	check(h0.is_home(), "home again")
	check(GameBoot.unbuilt(h0).is_empty() and h0.world.chunks.face_count > 0, "every chunk of the house built")
	check(not HouseWorld.defer_chunks, "deferral is over")
	check(h0.autosave_log.has("returned"), "travel's return ran (%s)" % [h0.autosave_log])
	if _closed.is_empty():
		check(false, "the screen closed")
		return
	var h: Array = _closed.back()["history"]
	check(_monotonic(h), "progress only grows")
	check_eq(_closed.back()["title"], "Returning home", "the operation")
	var texts := _texts(h)
	check(texts.has("Restoring the house…") and texts.has("Building the house…") and texts.has("Final preparation…"), "home's stages (%s)" % [texts])
	print("    staged return home: %.0f ms, %d frames" % [h0.boot_ms, h0.boot_frames])


func test_staged_continue_loads_the_save() -> void:
	var g: Node = await _boot("new")
	check_eq(g.debug_save(), "", "saved")
	var day: int = g.debug_state().day()
	g.queue_free()
	await frames(2)
	var c: Node = await _boot("continue", true)
	check(c.is_home() and c.debug_state().day() == day, "the saved run")
	check(GameBoot.unbuilt(c).is_empty(), "built")
	if _closed.is_empty():
		check(false, "the screen closed")
		return
	check_eq(_closed.back()["title"], "Loading saved game", "the operation")
	check(_texts(_closed.back()["history"]).has("Reading the save…"), "reads the save first")
	print("    staged Continue (home): %.0f ms, %d frames" % [c.boot_ms, c.boot_frames])


# --- failure -------------------------------------------------------------------------------

## A place that can't be made (an invalid layout) on a real departure by car:
## back home, the fuel back, no time passed, the inventory as it was, the save
## untouched (the departure's checkpoint).
func test_a_failed_arrival_turns_back_home_and_uses_nothing() -> void:
	var g: Node = await _boot("new")
	var s: GameState = g.debug_state()
	s.total_minutes = 9.0 * 60.0
	s.car_repaired = true
	s.inventory.add("fuel", 2)
	s.region.discover("convenience")
	var inv: Dictionary = s.inventory.to_dict()
	var minutes := s.total_minutes
	TravelFlow.skip_animation = true
	var why: String = await g.travel.depart("convenience", true)
	check_eq(why, "", "sets out by car")
	check(g.debug_state().inventory.count("fuel") < 2, "the leg's fuel was taken")
	var saved := FileAccess.get_file_as_bytes(SAVE)
	check(not saved.is_empty(), "the departure's checkpoint")
	g.queue_free()
	await frames(2)
	GameBoot.debug_invalid_site = "convenience"
	var h0: Node = await _boot("carry", true)
	check(h0.is_home(), "turned back home")
	var t: GameState = h0.debug_state()
	check_eq(t.inventory.to_dict(), inv, "the inventory as before (fuel included)")
	check(absf(t.total_minutes - minutes) < 0.5, "no time passed but a few frames (%f)" % t.total_minutes)
	check(not OffscreenHome.is_away(t), "the away ledger is closed")
	check(FileAccess.get_file_as_bytes(SAVE) == saved, "no save written")
	check(h0.autosave_log.has("held:returned") and not h0.autosave_log.has("returned"), "the return's autosave held (%s)" % [h0.autosave_log])
	check(h0.last_toast.contains("couldn't be reached"), "a toast says why (%s)" % h0.last_toast)
	check(h0.debug_modal() == "" and GameBoot.unbuilt(h0).is_empty(), "playable at home")
	check(not h0.get_children().any(func(n: Node) -> bool: return n is PoiWorld), "no half-made place left")
	if not _closed.is_empty():
		check(_closed.back()["title"] == "Returning home" and _monotonic(_closed.back()["history"]), "the screen says so and never goes back")


## An unknown place (staged and not): back home the same way.
func test_an_unknown_place_turns_back_home() -> void:
	for staged in [false, true]:
		var g: Node = await _boot("new")
		var carry := _carry_to(g, "nowhere_at_all")
		var minutes: float = g.debug_state().total_minutes
		g.queue_free()
		await frames(2)
		GameLaunch.site = "nowhere_at_all"
		GameLaunch.carry = carry
		var h0: Node = await _boot("carry", staged)
		check(h0.is_home() and h0.left_to == "", "home, not the menu (staged %s)" % staged)
		check(absf(h0.debug_state().total_minutes - minutes) < 0.5, "no time passed")
		check(not FileAccess.file_exists(SAVE) or not h0.autosave_log.has("returned"), "nothing saved")
		check(h0.last_toast.contains("couldn't be reached"), "a toast (%s)" % h0.last_toast)
		h0.queue_free()
		await frames(2)
