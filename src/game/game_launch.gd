class_name GameLaunch
extends RefCounted
## Hand-off from the main menu to the game scene (no Autoloads).

const GAME_SCENE := "res://src/game/game.tscn"
const MENU_SCENE := "res://src/menu/main_menu.tscn"
const EXPERIMENTS_SCENE := "res://src/launcher/launcher.tscn"

static var mode := "new"      ## "new" | "continue" | "carry" (Exp 007, T: a scene change home <-> POI)
static var notice := ""       ## one-shot message for the main menu (shown, then cleared)
static var seed := 0          ## run seed for a new game; 0 = random (tests and tools fix it)
static var difficulty := "normal"   ## chosen in the main menu for a new game (Difficulty.LEVELS)
## Exp 007 (T): where the game scene is ("home" or a POI id, RegionLocations)
## and what a scene change between home and a POI carries in memory:
## {"state": GameState.to_dict(), "home": RunSave home snapshot (the save
## dictionary written when Eli left), "travel": {"to", "from", "car",
## "minutes", "depart_at"}, "poi": the POI helper's state, "cargo": {item: n}}.
## mode "carry" launches the scene from it (src/travel/travel_flow.gd).
## Exp 008 (T): a leg from one POI to the next ("travel" leg "on", with
## "from" and "stops": the places before this one) also carries "cargo" (the
## car's boot, which stays the boot) and "pack" ({item: n} taken on the
## earlier stops and still carried, which keeps counting toward the pack
## limit); "home" is the same snapshot all along the chain.
static var site := "home"
static var carry := {}
