extends Node
## Owns the game's HUD, panels and overlays: U's CanvasLayers (HUD, pause,
## settings, inventory, sleep, death, developer menu, intro), E's expedition
## screen and the sleep fade. All of them process while the tree is paused.
## The game root connects their signals; this node only builds and closes them.

const ScreenFade := preload("res://src/game/screen_fade.gd")

var hud: GameHud
var pause_menu: PauseMenu
var settings: SettingsPanel
var inventory: InventoryPanel
var sleep_dialog: SleepDialog
var death_screen: DeathScreen
var dev_menu: DevMenu
var expedition: ExpeditionScreen
var intro: IntroOverlay
var fade: CanvasLayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## `with_intro`: a new run plays the intro overlay.
func build(state: GameState, game: Node, with_intro: bool) -> void:
	hud = _add(GameHud.new(), "Hud")
	hud.setup(state)
	expedition = _add(ExpeditionScreen.new(), "ExpeditionScreen")
	inventory = _add(InventoryPanel.new(), "InventoryPanel")
	sleep_dialog = _add(SleepDialog.new(), "SleepDialog")
	pause_menu = _add(PauseMenu.new(), "PauseMenu")
	settings = _add(SettingsPanel.new(), "SettingsPanel")
	death_screen = _add(DeathScreen.new(), "DeathScreen")
	dev_menu = _add(DevMenu.new(), "DevMenu")
	dev_menu.setup(state, game)
	fade = _add(ScreenFade.new(), "Fade")
	if with_intro:
		intro = _add(IntroOverlay.new(), "Intro")


func _add(n: Node, node_name: String) -> Node:
	n.name = node_name
	n.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(n)
	return n


static func is_open(panel: Node) -> bool:
	if panel == null:
		return false
	var v = panel.get("is_open")
	if typeof(v) == TYPE_BOOL:
		return v
	return panel.get("visible") == true


## Closes a panel without emitting anything the game listens to on purpose
## (the game updates its own state after calling this).
static func close(panel: Node) -> void:
	if panel == null:
		return
	if panel.has_method("close"):
		panel.close()
	elif "visible" in panel:
		panel.visible = false


func close_all() -> void:
	for p in [pause_menu, settings, inventory, sleep_dialog]:
		if is_open(p):
			close(p)
	if dev_menu != null and dev_menu.visible:
		dev_menu.toggle()
