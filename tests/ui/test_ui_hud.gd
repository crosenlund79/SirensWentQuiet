extends "res://tests/test_case.gd"
## HUD reflects GameState: clock and glyph, stat bars, warnings, ammo,
## cheats badge, prompt, toasts, banner, build mode, F3.

const U := preload("res://tests/ui/ui_test_util.gd")


func test_hud_reflects_state() -> void:
	var state := GameState.new_run(4)
	var hud: GameHud = add(GameHud.new())
	hud.setup(state)
	await frames(2)
	var t := hud.debug_texts()
	check_eq(t["clock"], "Day 1 · 07:00", "clock")
	check(not t["night_glyph"], "sun by day")
	check_eq(t["ammo"], "9", "nine bullets")
	check(not t["cheats_visible"], "no cheats badge")
	check(not t["fps_visible"], "FPS line off by default")
	check(t["warnings"].is_empty(), "no warnings at the start")
	# night
	state.advance(15 * 60.0)   # 22:00
	await frames(2)
	t = hud.debug_texts()
	check_eq(t["clock"], "Day 1 · 22:00", "clock advanced")
	check(t["night_glyph"], "moon at night")
	check_eq(t["period"], "Night · Normal", "period and difficulty")
	# warnings derived from the stats
	state.hunger = 10.0
	state.hydration = 0.0
	state.energy = 12.0
	state.health = 14.0
	await frames(2)
	t = hud.debug_texts()
	for w in ["Hungry", "Dehydrated", "Exhausted", "Badly hurt"]:
		check(w in t["warnings"], "warns '%s' (%s)" % [w, t["warnings"]])
	check(t["flash"] > 0.1, "a big health drop flashes the screen")
	# cheats badge
	state.cheats["invulnerable"] = true
	await frames(1)
	t = hud.debug_texts()
	check(t["cheats_visible"], "CHEATS ACTIVE badge")
	check(t["cheats"].contains("Invulnerable"), "lists the cheat")
	state.cheats["unlimited"] = true
	await frames(1)
	check(hud.debug_texts()["cheats"].contains("Unlimited resources"), "lists both")
	state.cheats["invulnerable"] = false
	state.cheats["unlimited"] = false
	await frames(1)
	check(not hud.debug_texts()["cheats_visible"], "badge hides when cheats are off")
	# the weapon in hand
	check_eq(t["weapon"], "Handgun", "weapon name")
	check_eq(t["ammo_cap"], "/ 12", "magazine capacity")
	check_eq(t["ammo_note"], "0 9 mm spare", "reserve")
	check_eq(t["materials"], "Wood 6 · Stone 0 · Iron 0", "construction resources")
	state.inventory.add("stone", 4)
	await frames(1)
	check_eq(hud.debug_texts()["materials"], "Wood 6 · Stone 4 · Iron 0", "stone shows")
	state.set_magazine("handgun", 0)
	await frames(1)
	t = hud.debug_texts()
	check_eq(t["ammo"], "0", "ammo count")
	check_eq(t["ammo_note"], "out of ammo", "out of ammo")


func test_invasion_warning_on_invasion_day() -> void:
	var state := GameState.new_run(4)
	state.total_minutes = 2 * 1440.0 + 12.5 * 60.0   # Day 3, 12:30
	var hud: GameHud = add(GameHud.new())
	hud.setup(state)
	await frames(2)
	check("Something is coming tonight." in hud.debug_texts()["warnings"], "invasion day warning")


func test_prompt_toasts_banner_modes() -> void:
	var state := GameState.new_run(4)
	var hud: GameHud = add(GameHud.new())
	hud.setup(state)
	await frames(1)
	hud.set_prompt("[E] Sleep")
	var chip := hud.find_child("Prompt", true, false)
	check(U.all_label_text(chip).contains("E") and U.all_label_text(chip).contains("Sleep"), "key chip + text")
	check(hud.debug_texts()["prompt_visible"], "prompt visible")
	hud.toast("Out of ammo", "warn")
	hud.toast("Out of ammo", "warn")
	hud.toast("Found 2 planks", "good")
	var toasts: Array = hud.debug_texts()["toasts"]
	check_eq(toasts.size(), 2, "repeat coalesces")
	check(toasts[0].contains("×2"), "repeat counted (%s)" % [toasts])
	for i in 6:
		hud.toast("Toast %d" % i, "info")
	check(hud.debug_texts()["toasts"].size() <= GameHud.TOAST_MAX, "stack is capped")
	await seconds(GameHud.TOAST_LIFE + 1.5)
	check(hud.debug_texts()["toasts"].is_empty(), "toasts fade away")
	hud.set_banner("They're here")
	check_eq(hud.debug_texts()["banner"], "THEY'RE HERE", "banner")
	hud.set_banner("")
	check_eq(hud.debug_texts()["banner"], "", "banner hides")
	hud.set_mode("build")
	await frames(1)
	check(not hud.debug_texts()["prompt_visible"], "build mode keeps the bottom centre clear")
	check(not (hud.find_child("Ammo", true, false) as Control).visible, "ammo hidden in build mode")
	hud.set_mode("play")
	await frames(1)
	check(hud.debug_texts()["prompt_visible"], "prompt back in play mode")
	U.key(tree, KEY_F3)
	await frames(1)
	check(hud.debug_texts()["fps_visible"], "F3 shows the FPS line")
	hud.flash_damage()
	check(hud.debug_texts()["flash"] > 0.5, "flash_damage")


func test_hud_weapon_card_reads_the_weapon_handler_and_alerts() -> void:
	var state := GameState.new_run(4, "hard")
	state.inventory.add("shotgun", 1)
	state.inventory.add("shells", 7)
	var hud: GameHud = add(GameHud.new())
	hud.setup(state)
	var w: WeaponHandler = add(WeaponHandler.new())
	w.auto_tick = false
	w.setup(state, null, null)
	hud.set_weapons(w)
	await frames(2)
	var t := hud.debug_texts()
	check_eq(t["period"], "Morning · Hard", "the difficulty in the clock card")
	check_eq(t["weapon"], "Handgun", "the handgun in hand")
	check(t["weapon_other"].contains("Shotgun"), "the other weapon (%s)" % t["weapon_other"])
	check_eq(w.switch_to("shotgun"), "", "switch")
	await frames(1)
	t = hud.debug_texts()
	check_eq(t["weapon"], "Shotgun", "the HUD follows the handler")
	check_eq(t["ammo"], "0", "an empty shotgun")
	check_eq(t["ammo_note"], "empty · R reload", "says how to fill it")
	w.tick(0.5)
	check_eq(w.reload(), "", "reload starts")
	w.tick(0.2)
	await frames(1)
	t = hud.debug_texts()
	check(t["reloading"], "reload bar shown")
	check_eq(t["ammo_note"], "reloading", "reloading")
	w.tick(2.6)
	await frames(1)
	t = hud.debug_texts()
	check_eq(t["ammo"], "5", "shells loaded")
	check_eq(t["ammo_note"], "2 shells spare", "reserve")
	check(not t["reloading"], "bar hidden")
	hud.alert("Bomber at the wall · 3 s", 0.3)
	check_eq(hud.debug_texts()["alert"], "BOMBER AT THE WALL · 3 S", "alert shown")
	await seconds(0.5)
	check_eq(hud.debug_texts()["alert"], "", "alert hides after its time")
	hud.alert("x", 5.0)
	hud.alert("")
	check_eq(hud.debug_texts()["alert"], "", "alert('') hides at once")
