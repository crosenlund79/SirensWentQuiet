class_name StoryDev
extends RefCounted
## Exp 012 (S): the story's F10 tools (ASSIGNMENT §40, §42), built into the
## developer menu by DevMenu._build_e12_s_section (tab: Story) and
## _build_e12_s_audio_section (tab: Audio). They act on the game's `story`
## helper (StoryDirector).

static func _story(menu: DevMenu) -> StoryDirector:
	var g: Variant = menu.game
	if g == null or not is_instance_valid(g):
		return null
	return g.get("story") as StoryDirector


static func build_story(menu: DevMenu, box: VBoxContainer) -> void:
	var st := _story(menu)
	if st == null:
		return
	box.add_child(UiTheme.make_section("Story: Someone Is Watching"))
	var status := UiTheme.make_caption(st.status_text(), DevMenu.WIDTH - 52)
	status.name = "StoryStatus"
	box.add_child(status)
	var refresh := func() -> void:
		if is_instance_valid(status) and is_instance_valid(st):
			status.text = st.status_text()
	var run := func(c: Callable) -> void:
		var r: Variant = await c.call()
		menu._say(str(r))
		refresh.call()
	var items := []
	for n in [1, 2, 3, 4]:
		var nm: String = StoryState.NAMES[n]
		items.append(["Preview %d %s" % [n, nm], func(): run.call(func(): return await st.preview_encounter(n))])
		items.append(["Trigger %d %s" % [n, nm], func(): run.call(func(): return await st.trigger(n))])
	box.add_child(menu._grid(2, items))
	box.add_child(menu._grid(2, [
		["Preview rope burning", func(): run.call(func(): return await st.burn_ropes(true))],
		["Skip the scene", func():
			st.skip()
			menu._say("Skipped")],
		["Next one eligible now", func():
			StoryState.make_eligible_now(st.state)
			menu._say("The next encounter is eligible now")
			refresh.call()],
		["First siege eligible now", func():
			StoryState.make_siege_eligible_now(st.state)
			menu._say("The first organised siege is eligible (Encounter 4 counts as done)")
			refresh.call()],
		["The watcher leaves", func(): menu._say(st.dismiss_observer())],
		["Reset Chapter", func():
			StoryState.reset(st.state)
			StoryState.ch1(st.state)
			st.overlay.hide_choice()
			menu._say("Chapter One reset")
			refresh.call()],
		["Refresh status", refresh],
	]))


static func build_audio(menu: DevMenu, box: VBoxContainer) -> void:
	var st := _story(menu)
	if st == null:
		return
	var au := st.audio
	box.add_child(UiTheme.make_section("Story audio"))
	var playing := UiTheme.make_caption(au.playing_text(), DevMenu.WIDTH - 52)
	playing.name = "StoryAudioPlaying"
	box.add_child(playing)
	var timer := Timer.new()
	timer.wait_time = 0.5
	timer.autostart = true
	timer.process_mode = Node.PROCESS_MODE_ALWAYS
	timer.timeout.connect(func():
		if is_instance_valid(playing) and is_instance_valid(au):
			playing.text = "Playing: " + au.playing_text())
	playing.add_child(timer)
	var voices := []
	for n in StoryLines.VOICE_FILES:
		var label := "Voice: " + str(n).trim_prefix("story/architect_")
		voices.append([label, func():
			au.stop()
			var len := au.play_voice_file(n)
			menu._say("%s (%.1f s)" % [label, len] if len > 0.0 else "No recording for " + label, len <= 0.0)])
	box.add_child(menu._grid(2, voices))
	var variant := OptionButton.new()
	variant.name = "StoryVariant"
	variant.focus_mode = Control.FOCUS_NONE
	for v in ["Variant: random", "Variant 1", "Variant 2", "Variant 3", "Variant 4"]:
		variant.add_item(v)
	variant.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(variant)
	var cats := []
	for n in StoryAudio.FOLLOWERS:
		cats.append([StoryAudio.LABELS[n], func():
			var v := variant.selected - 1
			var len := au.play_follower(n, null, 0.0, v, true) if n != "story/follower_bat" else au.play_bat(v, null)
			menu._say("%s (%d files)" % [StoryAudio.LABELS[n], StoryAudio.variants(n)] if len > 0.0 else "No recording", len <= 0.0)])
	box.add_child(menu._grid(2, cats))
	var slider := UiTheme.make_slider(0.0, 1.5, 0.05)
	slider.value = au.intensity
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(x: float): au.intensity = x)
	box.add_child(UiTheme.make_caption("Cinematic background intensity", DevMenu.WIDTH - 52))
	box.add_child(slider)
	box.add_child(menu._grid(2, [
		["Test door impacts", func(): menu._say(test_door(st, variant.selected - 1))],
		["Test the silence", func(): menu._say(test_silence(st))],
		["Scape: Visitor (1)", func(): au.set_level(1); menu._say("Soundscape 1")],
		["Scape: Warning (3)", func(): au.set_level(3); menu._say("Soundscape 3")],
		["Scape: Last (4)", func(): au.set_level(4); menu._say("Soundscape 4")],
		["Stop story audio", func():
			StoryAudio.stop_all(menu.get_tree())
			menu._say("Story audio stopped")],
	]))


## A bat recording with the stage door in the bedroom doorway jolting on it
## (the door is a prop: taken away when the recording ends).
static func test_door(st: StoryDirector, variant: int) -> String:
	if st.running != 0:
		return "A story scene is running."
	st.stage.build({"door": true})
	var len := st.audio.play_bat(variant)
	var hold := st.get_tree().create_timer(len + 0.6)
	hold.timeout.connect(func():
		if is_instance_valid(st) and st.running == 0:
			st.stage.restore())
	var ons: Array = st.audio.last_bat.get("onsets", [])
	return "Bat %d: %d impacts at %s s" % [int(st.audio.last_bat.get("variant", 0)) + 1, ons.size(),
		", ".join(ons.map(func(o): return "%.2f" % float(o[0])))]


## The followers at full chaos, then complete silence after 5 s.
static func test_silence(st: StoryDirector) -> String:
	st.audio.unsilence()
	st.audio.set_level(4)
	var t := st.get_tree().create_timer(5.0)
	t.timeout.connect(func():
		if is_instance_valid(st):
			st.audio.silence())
	return "Followers at level 4; silence in 5 s"
