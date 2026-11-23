class_name GameLaunch
extends RefCounted
## Hand-off from the main menu to the game scene (no Autoloads).

const GAME_SCENE := "res://src/game/game.tscn"
const MENU_SCENE := "res://src/menu/main_menu.tscn"
const EXPERIMENTS_SCENE := "res://src/launcher/launcher.tscn"

static var mode := "new"      ## "new" | "continue"
static var notice := ""       ## one-shot message for the main menu (shown, then cleared)
