class_name LoadingScreen
extends CanvasLayer
## Exp 009 (R): the loading screen of the staged boot (the user's §15).
##
## Dark and plain, as the travel cards: the operation ("Entering Medical
## Clinic", "Returning home", "Loading saved game"), an amber rule, a
## progress bar, and the current stage under it ("Placing furniture…") with
## the percentage. Progress is real and stage-weighted: plan() gives each
## stage its share, begin() starts the next one (the earlier ones count as
## done), set_fraction() reports how far the current one is. Progress never
## goes back and never runs ahead of finished work.
##
## Short operations show nothing: the screen stays invisible until an update
## (a stage or a chunk of work) comes SHOW_AFTER_MS after it opened, or the
## operation is expected to take longer than that (expect(): the last time
## the same kind of boot took).
##
## One at a time (`current()`). A scene change (change_scene(): travel, the
## main menu's Continue) adds it to the tree's root so it survives the change,
## loads the game scene on a thread, sets GameLaunch.staged and swaps the
## scene; the new game picks it up (open() returns the open one) and finishes
## it. The game opens its own (as its child) when it boots staged without one.
##
##   var ls := LoadingScreen.open(self, "Entering Medical Clinic")
##   ls.plan([["site", 0.8, "Preparing interior…"], ["final", 0.2, "Final preparation…"]])
##   await ls.drive(job, "site", TEXTS)   # job.step() -> bool, job.progress, job.stage
##   ls.begin("final")
##   ls.finish()
##
## Never touches the scene tree off the main thread: only the PackedScene
## comes from a loader thread (ResourceLoader.load_threaded_request).

signal closed

const LAYER := 95                    ## above every game panel (dev menu 80, dialogs 85, intro 90)
const SHOW_AFTER_MS := 250
const SLICE_MS := 12.0               ## work per frame in drive() before the screen redraws
const BAR_SIZE := Vector2(460, 10)
const BACK := Color(0.0, 0.006, 0.012, 1.0)     ## the travel cards' scrim

static var _current: LoadingScreen
static var show_at_once := false     ## tools (screenshots): no SHOW_AFTER_MS wait

var title := ""
var stage := ""                      ## the current stage's key
var stage_text := ""
var progress := 0.0                  ## 0..1, never decreasing
var was_shown := false               ## the screen became visible at some point
var frames := 0                      ## frames drawn while it was open (tests, timings)
var history: Array = []              ## [{"ms", "stage", "text", "progress", "frame"}] on every change (tests)
var opened_ms := 0
var expect_ms := 0                   ## how long the operation is expected to take (0 = unknown)

var _plan := {}                      ## stage -> share of the span (0..1)
var _texts := {}
var _base := 0.0
var _span := 1.0
var _done := 0.0                     ## shares of the finished stages
var _cur := 0.0                      ## share of the current stage
var _closing := false
var _scene_path := ""

var _root: Control
var _title: Label
var _fill: ColorRect
var _stage: Label
var _pct: Label


func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "LoadingScreen"
	visible = false
	opened_ms = Time.get_ticks_msec()
	_build()


## The open loading screen, or a new one added to `parent` (the tree's root
## for a scene change; the game itself otherwise).
static func open(parent: Node, text: String) -> LoadingScreen:
	var ls := current()
	if ls == null:
		ls = LoadingScreen.new()
		_current = ls
		if parent != null:
			parent.add_child(ls)
	ls.set_title(text)
	return ls


static func current() -> LoadingScreen:
	if _current != null and is_instance_valid(_current) and not _current._closing:
		return _current
	return null


## Closes the open screen, if any (a failed boot on its way to the menu).
static func close_current() -> void:
	var ls := current()
	if ls != null:
		ls.close()


## A scene change behind the loading screen: opens it on the root, loads
## `path` on a thread and changes to it; the next game boots staged.
static func change_scene(tree: SceneTree, path: String, text: String) -> LoadingScreen:
	var ls := open(tree.root, text)
	GameLaunch.staged = true
	ls.begin_scene_load()
	ls._scene_path = path
	if ResourceLoader.load_threaded_request(path, "PackedScene") != OK:
		ls._scene_path = ""
		tree.change_scene_to_file.call_deferred(path)
	return ls


## The operation is expected to take `ms`: at SHOW_AFTER_MS or more the
## screen shows at its next update instead of after the wait (a house restore
## starts with one long step; showing nothing through it would look frozen).
func expect(ms: float) -> void:
	expect_ms = int(ms)


## The scene's own loading: the first 8 % of the bar (the game's plan shares
## the rest once it boots).
func begin_scene_load() -> void:
	plan([["scene", 0.08, "Loading…"], ["game", 0.92, "Loading…"]])
	begin("scene")


func set_title(text: String) -> void:
	title = text
	if _title != null:
		_title.text = text


## The stages to come, [[key, weight, text], ...]: they share what is left
## of the bar (an earlier plan's progress stays).
func plan(stages: Array) -> void:
	_base = progress
	_span = 1.0 - progress
	_plan = {}
	_texts = {}
	_done = 0.0
	_cur = 0.0
	stage = ""
	var total := 0.0
	for s in stages:
		total += float(s[1])
	for s in stages:
		_plan[str(s[0])] = float(s[1]) / total if total > 0.0 else 0.0
		_texts[str(s[0])] = str(s[2]) if s.size() > 2 else ""
	_log()


## Starts stage `key` (the current one is done). `text` overrides the plan's.
func begin(key: String, text := "") -> void:
	if stage != "" and stage != key:
		_done += _cur
	stage = key
	_cur = float(_plan.get(key, 0.0))
	stage_text = text if text != "" else str(_texts.get(key, stage_text))
	_update(0.0)


## How far the current stage is (0..1).
func set_fraction(f: float) -> void:
	_update(f)


## A new line under the bar within the current stage (a job's own stages).
func set_text(text: String) -> void:
	if text == "" or text == stage_text:
		return
	stage_text = text
	_update(-1.0)


## Steps `job` (job.step() -> bool, true = done; job.progress 0..1; job.stage
## a key of `texts`) as stage `key`, SLICE_MS of work per frame, so the
## screen redraws between chunks. Returns when the job is done.
func drive(job: Object, key: String, texts := {}) -> void:
	begin(key)
	await _frame()
	var t0 := Time.get_ticks_usec()
	while not job.step():
		var sub := str(job.get("stage"))
		if texts.has(sub):
			set_text(str(texts[sub]))
		set_fraction(float(job.get("progress")))
		if (Time.get_ticks_usec() - t0) / 1000.0 >= SLICE_MS:
			await _frame()
			t0 = Time.get_ticks_usec()
	set_fraction(1.0)


## The operation is done: the bar is full and the screen goes (a short fade
## when it was shown).
func finish() -> void:
	if _closing:
		return
	_done = 1.0
	_cur = 0.0
	_update(0.0)
	close()


func close() -> void:
	if _closing:
		return
	_closing = true
	if _current == self:
		_current = null
	closed.emit()
	if visible and is_inside_tree():
		var tw := create_tween()
		tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.tween_property(_root, "modulate:a", 0.0, 0.18)
		tw.tween_callback(queue_free)
	else:
		queue_free()


func is_closing() -> bool:
	return _closing


func elapsed_ms() -> int:
	return Time.get_ticks_msec() - opened_ms


func _frame() -> void:
	if is_inside_tree():
		await get_tree().process_frame


func _process(_delta: float) -> void:
	frames += 1
	if _scene_path == "":
		return
	var p := []
	var st := ResourceLoader.load_threaded_get_status(_scene_path, p)
	if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		set_fraction(float(p[0]) if not p.is_empty() else 0.0)
		return
	var path := _scene_path
	_scene_path = ""
	var ps: PackedScene = ResourceLoader.load_threaded_get(path) if st == ResourceLoader.THREAD_LOAD_LOADED else null
	set_fraction(1.0)
	if ps != null:
		get_tree().change_scene_to_packed(ps)
	else:
		get_tree().change_scene_to_file(path)


func _update(f: float) -> void:
	if f >= 0.0:
		var p := _base + _span * (_done + _cur * clampf(f, 0.0, 1.0))
		progress = maxf(progress, minf(p, 1.0))
	_log()
	if _fill != null:
		_fill.size.x = BAR_SIZE.x * progress
		_stage.text = stage_text
		_pct.text = "%d %%" % int(floor(progress * 100.0))
	if not was_shown and not _closing and (show_at_once or elapsed_ms() >= SHOW_AFTER_MS or expect_ms >= SHOW_AFTER_MS):
		was_shown = true
		visible = true


func _log() -> void:
	var last: Dictionary = history.back() if not history.is_empty() else {}
	if not last.is_empty() and is_equal_approx(float(last["progress"]), progress) and last["text"] == stage_text and last["stage"] == stage:
		return
	history.append({"ms": elapsed_ms(), "stage": stage, "text": stage_text, "progress": progress, "frame": frames})


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.theme = UiTheme.theme()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP      # nothing behind it takes clicks
	add_child(_root)
	var back := ColorRect.new()
	back.name = "Back"
	back.color = BACK
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(back)
	var box := VBoxContainer.new()
	box.name = "Card"
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)
	_title = UiTheme.make_title(title, UiTheme.FONT_BIG)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	var rule := ColorRect.new()
	rule.color = UiTheme.ACCENT
	rule.custom_minimum_size = Vector2(56, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)
	box.add_child(UiTheme.make_spacer(14))
	var track := ColorRect.new()
	track.name = "Bar"
	track.color = UiTheme.LINE
	track.custom_minimum_size = BAR_SIZE
	track.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(track)
	_fill = ColorRect.new()
	_fill.name = "Fill"
	_fill.color = UiTheme.ACCENT
	_fill.position = Vector2.ZERO
	_fill.size = Vector2(0.0, BAR_SIZE.y)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(_fill)
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(BAR_SIZE.x, 0)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	_stage = UiTheme.make_label("", UiTheme.FONT_BODY, UiTheme.TEXT_DIM)
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_stage)
	_pct = UiTheme.make_label("0 %", UiTheme.FONT_BODY, UiTheme.TEXT_FAINT)
	_pct.add_theme_font_override("font", UiTheme.font("mono"))
	row.add_child(_pct)
