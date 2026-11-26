extends "res://tests/test_case.gd"
## Experiment 012 (A), ASSIGNMENT §39–43: the tabbed developer menu. Every
## tab builds, every button of the single-page menu is still there (by its
## text, in some tab), the tabs switch, the last tab is remembered, the
## Debug and Audio pages show live text, unrouted sections land in "More".

## Every button text of the Exp 011 single-page menu (static texts).
const OLD_BUTTONS := ["+ 10 ammo", "+ All books", "+ Food & water", "+ Materials", "+ Medical", "+ Shotgun & shells",
	"+ Vest & gear", "+1 hour", "+10 iron", "+10 planks", "+10 scrap", "+10 stone", "+3 fuel", "10 debris blasts",
	"All lights off", "All lights on", "All tools", "Aurora: old / subtle", "Bar test kit", "Brute at the moat",
	"Build all 5 levels", "Build upper floor", "Calm runner", "Calm straggler", "Car parts", "Character showroom",
	"Collapse test", "Components, iron, scrap", "Damage all doors", "Defence info", "Destroy furniture", "Destroy fuse box",
	"Details layer", "Diagnostics", "Dig 3×3 basement", "Dormant psycho", "Experimental Eli", "Fill a chest",
	"Fill magazines", "Fill the moat", "Fireplace layer", "Force behaviour", "Forget all", "Foundation kit",
	"Furniture kit", "Generate test site", "Give a drill", "Give shovel", "Go to this place", "Go: basement (-1)",
	"Go: ground floor (0)", "Go: level +2", "Go: level -2", "Go: upper floor (+1)", "Hole in the nearest wall",
	"Home panel", "Indoor layer", "Inspect setup", "Last noises", "Learn all", "List holes", "Moat ring + bridge",
	"Mood high", "Mood low", "Mood normal", "Morning 06:00", "Next Eli look", "Next day (00:00)", "Next invasion",
	"Night 20:00", "Noise: extreme", "Noise: high", "Noise: low", "Northern lights tonight", "Open the overview",
	"Original character", "Outdoor layer", "Owl / wolf / creak", "POI state", "Place a radio", "Play sound",
	"Psycho at the moat", "Raise / lower bridges", "Recompute", "Remove Architect", "Remove window here",
	"Repair all levels", "Repair car", "Repair car now", "Repair everything", "Repair house", "Restore power",
	"Restore this POI's loot", "Return home", "Return home (POI gen)", "Reveal all", "Reveal all places",
	"Reveal containers", "Reveal stash", "Room boundaries", "Run mission now", "Security info", "Sensor here",
	"Shovel, water, wood", "Show Architect (internal)", "Show comfort", "Show containers", "Show skills", "Show supply",
	"Show support", "Skip travel anim", "Snow on/off", "Spawn 1 psycho", "Spawn 3 psychos", "Spawn a straggler here",
	"Start this wave", "Stop voice / music", "Storage items", "Supply ammo", "TV / radio on/off", "Threat layer",
	"Time 23:00", "Today's places", "Toggle fireplace", "Toggle fuse box", "Trigger nearest sensor",
	"Turret here (handgun)", "Unlock security research", "Visibility diagnostics", "Invulnerable", "Unlimited resources",
	"×1", "×4", "×10", "+ Psycho", "+ Runner", "+ Brute", "+ Bomber", "Spawn psycho", "Spawn bomber"]


class FakeHelper extends RefCounted:
	func dev_learn_all() -> String: return "learned"
	func dev_state_text() -> String: return "poi"
	func dev_travel_to(_id: String) -> void: pass


class FakeResearch extends Node:
	func dev_learn_all() -> String: return "learned"


class FakeGame extends Node:
	var research: Node
	var poi := FakeHelper.new()
	var travel := FakeHelper.new()
	func dev_info() -> String: return "fake"
	func _init() -> void:
		research = FakeResearch.new()
		add_child(research)


func _menu() -> DevMenu:
	var game: FakeGame = add(FakeGame.new())
	var m: DevMenu = add(DevMenu.new())
	m.setup(GameState.new_run(3), game)
	return m


func test_every_tab_builds_and_every_old_button_is_reachable() -> void:
	DevMenu.last_tab = "Player"
	var m := _menu()
	m.set_open(true)
	await frames(2)
	for t in DevMenu.TABS:
		check(m.tab_names().has(t), "tab %s" % t)
		m.select_tab(t)
		await frames(1)
		check_eq(m.current_tab(), t, "tab %s shows" % t)
		var page: Control = m.find_child("Page_" + t, true, false)
		check(page != null and page.visible, "page %s visible" % t)
		var box := m._tab(t)
		check(box.get_child_count() > 0, "tab %s has content" % t)
	for text in OLD_BUTTONS:
		check(m.button(text) != null, "button '%s' still reachable" % text)
	# where the main groups went
	var where := {"Invulnerable": "Player", "Spawn 3 psychos": "Enemies", "Show Architect (internal)": "Enemies",
		"Night 20:00": "World", "Build all 5 levels": "Building", "Run mission now": "POIs", "Play sound": "Audio"}
	for text in where:
		var page: Node = m.find_child("Page_" + where[text], true, false)
		check(page != null and DevMenu._find_button(page, text) != null, "'%s' in %s" % [text, where[text]])
	m.set_open(false)


func test_last_tab_is_remembered_and_live_pages_fill() -> void:
	DevMenu.last_tab = "Player"
	var m := _menu()
	m.set_open(true)
	await frames(1)
	check_eq(m.current_tab(), "Player", "opens on Player by default")
	(m.find_child("Tab_Debug", true, false) as Button).pressed.emit()
	for i in 4:
		await frames(1)
		m._process(0.6)
	check_eq(m.current_tab(), "Debug", "the tab button switches")
	var perf: RichTextLabel = m.find_child("Performance", true, false)
	check(perf != null and perf.text.contains("FPS") and perf.text.contains("draw calls"), "Debug: FPS and render info (%s)" % (perf.text if perf != null else "none"))
	check(m.frame_stats()["avg"] > 0.0, "frame times measured")
	var errs: RichTextLabel = m.find_child("Errors", true, false)
	check(errs != null and errs.text.contains("Status"), "Debug: errors and status")
	var insp: RichTextLabel = m.find_child("Inspect", true, false)
	check(insp != null and insp.text.contains("Day"), "Debug: inspect")
	check(m.button("FPS overlay") != null and m.button("Save now") != null, "Debug tools")
	m.button("FPS overlay").pressed.emit()
	check(m.last_status != "", "the FPS overlay hook answers (%s)" % m.last_status)
	m.select_tab("Audio")
	m._process(0.6)
	var now: RichTextLabel = m.find_child("AudioNow", true, false)
	check(now != null and now.text.contains("Players") and now.text.contains("Buses") and now.text.contains("story-only"), "Audio: playing now, buses, inbox")
	m.set_open(false)
	m.queue_free()
	await frames(1)
	# a new menu (a new scene) opens on the remembered tab
	var m2 := _menu()
	m2.set_open(true)
	await frames(1)
	check_eq(m2.current_tab(), "Audio", "the last tab is remembered this session")
	m2.set_open(false)
	DevMenu.last_tab = "Player"


func test_unrouted_sections_land_in_more() -> void:
	var m := _menu()
	m.set_open(true)
	await frames(1)
	check(not m.tab_names().has(DevMenu.MORE_TAB), "no More tab without unrouted sections")
	m.set_open(false)
	var m2: DevMenu = add(UnroutedMenu.new())
	m2.setup(GameState.new_run(3), add(FakeGame.new()))
	m2.set_open(true)
	await frames(1)
	check(m2.tab_names().has(DevMenu.MORE_TAB), "an unrouted section gets the More tab")
	check(m2.button("Unrouted tool") != null, "and its button works there")
	var routed := m2._tab("Story")
	check(DevMenu._find_button(routed, "Routed story tool") != null, "a routed section is in its tab")


class UnroutedMenu extends DevMenu:
	func _build() -> void:
		super._build()
		var box := _unrouted
		box.add_child(_grid(1, [["Unrouted tool", func(): pass]]))
		_tab("Story").add_child(_grid(1, [["Routed story tool", func(): pass]]))
