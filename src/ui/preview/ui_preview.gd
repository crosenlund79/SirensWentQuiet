extends Node
## Screenshot harness for UI review (not used by the game). Owner: U.
##   tools/capture.sh res://src/ui/preview/ui_preview.tscn /abs/out.png 2 --ui=pause --hour=22
## Args (after --):
##   --base=game|menu      what sits underneath (default game: res://src/game/game.tscn)
##   --ui=none|pause|settings|inventory|dev|sleep|death|intro|confirm|build
##   --day=N --hour=H      set the clock (game base)
##   --low                 low needs (warnings), --cheats (both cheats on)
##   --toasts, --banner=TEXT, --edge (stand at the lot edge for a prompt)

const GAME := "res://src/game/game.tscn"
const MENU := "res://src/menu/main_menu.tscn"

var args := {}
var base: Node
var state: GameState
var hud: GameHud


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.trim_prefix("--").split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var use_menu: bool = args.get("base", "game") == "menu"
	base = (load(MENU if use_menu else GAME) as PackedScene).instantiate()
	add_child(base)
	await get_tree().process_frame
	await get_tree().process_frame
	if not use_menu:
		_setup_game()
	if args.has("sequence") and state != null and hud != null:
		run_sequence(args["sequence"])
		return
	_open(args.get("ui", "none"))


func _setup_game() -> void:
	state = base.get("state") as GameState
	hud = base.get("hud") as GameHud
	if state == null:
		return
	if args.has("hour") or args.has("day"):
		var d := int(args.get("day", "1"))
		var h := float(args.get("hour", "9"))
		state.total_minutes = (d - 1) * 1440.0 + h * 60.0
	if args.has("low"):
		state.hunger = 12.0
		state.hydration = 9.0
		state.energy = 13.0
		state.health = 46.0
		state.inventory.remove("ammo", 6)
	if args.has("cheats"):
		state.cheats["invulnerable"] = true
		state.cheats["unlimited"] = true
	if args.has("edge"):
		var p := base.get("player") as Node3D
		if p != null:
			p.global_position = Vector3(-4.05, 0.0, 4.0)
	if hud != null:
		if args.has("toasts"):
			hud.toast("Found 3 planks and a tin of beans", "good")
			hud.toast("Out of ammo", "warn")
			hud.toast("Out of ammo", "warn")
			hud.toast("The back door is giving way", "bad")
		if args.has("banner"):
			hud.set_banner(args["banner"])


func _open(ui: String) -> void:
	match ui:
		"pause":
			get_tree().paused = true
			var p := PauseMenu.new()
			add_child(p)
			p.open("Not while enemies are near" if args.has("blocked") else "")
		"settings":
			if base.has_method("settings_panel"):
				base.settings_panel().open()
			else:
				get_tree().paused = true
				var s := SettingsPanel.new()
				add_child(s)
				s.open()
		"inventory":
			get_tree().paused = true
			var inv := InventoryPanel.new()
			add_child(inv)
			inv.open(state)
		"dev":
			var dev := DevMenu.new()
			add_child(dev)
			dev.setup(state, base)
			dev.toggle()
		"sleep":
			get_tree().paused = true
			var sd := SleepDialog.new()
			add_child(sd)
			sd.open(state)
		"death":
			get_tree().paused = true
			var ds := DeathScreen.new()
			add_child(ds)
			ds.open(state.days_survived() if state != null else 3, "psycho")
		"intro":
			var io := IntroOverlay.new()
			add_child(io)
			io.play()
		"confirm":
			var cd := ConfirmDialog.new()
			add_child(cd)
			cd.ask("This will overwrite your current survival run.", "Start a new run", "Cancel", "New game")
		"build":
			if hud != null:
				hud.set_mode("build")


# --- sequence mode: several screenshots from one game load ----------------------
## --sequence=/abs/dir shoots hud_day, inventory, dev, hud_night, pause, sleep,
## build and death into that folder, then quits. Run it through capture.sh
## with a large <secs> and CAPTURE_TIMEOUT so capture.gd never fires first.

func run_sequence(dir: String) -> void:
	var tree := get_tree()
	_set_clock(1, 10.0)
	var p := base.get("player") as Node3D
	if p != null:
		p.global_position = Vector3(-4.05, 0.0, 4.0)
	hud.toast("Found 3 planks and a tin of beans", "good")
	hud.toast("Out of ammo", "warn")
	hud.toast("Out of ammo", "warn")
	await _frames(8)
	await _shot(dir, "hud_day")
	# inventory over the day scene
	tree.paused = true
	var inv := InventoryPanel.new()
	add_child(inv)
	state.hunger = 58.0
	inv.open(state)
	await _frames(8)
	inv.use_item("canned_food")
	await _frames(14)
	await _shot(dir, "inventory")
	inv.close()
	tree.paused = false
	# developer menu (does not pause) with both cheats on
	var dev := DevMenu.new()
	add_child(dev)
	dev.setup(state, base)
	dev.toggle()
	dev.set_cheat("invulnerable", true)
	dev.add_pack("materials")
	await _frames(10)
	await _shot(dir, "dev_menu")
	dev.toggle()
	state.cheats["invulnerable"] = false
	# night, invasion day, low needs
	_set_clock(3, 22.4)
	state.hunger = 12.0
	state.hydration = 9.0
	state.energy = 13.0
	state.health = 46.0
	state.inventory.remove("ammo", state.inventory.count("ammo") - 2)
	hud.set_banner("They're here")
	hud.toast("Something is at the back door", "bad")
	if p != null:
		p.global_position = Vector3(7.0, 0.0, 4.5)
	await _frames(12)
	await _shot(dir, "hud_night")
	# pause (saving blocked during the invasion)
	tree.paused = true
	var pm := PauseMenu.new()
	add_child(pm)
	pm.open("Not while enemies are near")
	await _frames(8)
	await _shot(dir, "pause")
	pm._confirm_page()
	await _frames(4)
	await _shot(dir, "pause_confirm")
	pm.close()
	hud.set_banner("")
	# sleep
	_set_clock(2, 23.0)
	state.energy = 22.0
	var sd := SleepDialog.new()
	add_child(sd)
	sd.open(state)
	await _frames(8)
	await _shot(dir, "sleep")
	sd.close()
	tree.paused = false
	# build mode HUD
	hud.set_mode("build")
	hud.toast("That would seal the last way out.", "warn")
	await _frames(10)
	await _shot(dir, "hud_build")
	hud.set_mode("play")
	# death
	tree.paused = true
	var ds := DeathScreen.new()
	add_child(ds)
	ds.open(4, "psycho")
	await _frames(60)
	await _shot(dir, "death")
	tree.quit(0)


func _set_clock(day: int, hour: float) -> void:
	state.total_minutes = (day - 1) * 1440.0 + hour * 60.0


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(dir: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(dir.path_join(name + ".png"))
		print("ui_preview: shot ", name)
