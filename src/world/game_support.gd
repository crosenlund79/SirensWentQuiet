extends Node
## Refinement 01 (S): the house's structural support in the survival game.
## Created by SurvivalGame in _assemble() as `support` (like the other
## helpers). The model itself is HouseSupport (the ground HouseWorld's
## `support`); this helper
##   - links the upper storey to it when it is built or loaded,
##   - shows a collapse ("The roof over the kitchen gave way!") or a strain
##     warning as a toast, shakes the camera,
##   - hurts the player and the enemies standing under a collapsing zone (on
##     the storeys it falls on),
##   - answers the F10 "Structure" tools.

const PLAYER_DAMAGE := 30.0
const ENEMY_HITS := 4
const CAUSE := "crushed by the collapse"

var game: Node                         ## SurvivalGame
var model: HouseSupport
var last := {}                         ## the last collapse: info + {"player": damage taken, "enemies": hit} (tests)


func setup(g: Node) -> void:
	game = g
	model = game.world.support
	if model == null:
		return
	model.collapsed.connect(_on_collapsed)
	model.strained.connect(_on_strained)
	_link_upper()


func _process(_delta: float) -> void:
	_link_upper()


## Exp 005 (V): links every storey above ground (+1, +2) and the pillars.
func _link_upper() -> void:
	if model == null or game.get("levels") == null:
		return
	if model.levels == null:
		model.levels = game.levels
	for s in range(Levels.UPPER, Levels.HIGHEST + 1):
		var u = game.levels.world_of(s) if game.levels.has_method("world_of") else (game.levels.get("upper") if s == Levels.UPPER else null)
		if u != model.storeys.get(s) and (u == null or is_instance_valid(u)):
			model.set_storey(s, u)


func _on_collapsed(info: Dictionary) -> void:
	var r: Rect2 = info["rect"]
	var storeys: Array = info["storeys"]
	var hit := {"player": 0.0, "enemies": 0}
	var pl = game.player
	if pl != null and not game.state.dead:
		var ps: int = Levels.storey_at(pl.global_position.y)
		if r.grow(0.2).has_point(pl.plan_pos()) and ps in storeys:
			hit["player"] = game.combat._hurt(PLAYER_DAMAGE, CAUSE) if game.combat != null else 0.0
	if game.roster != null:
		for e in game.roster.enemies.duplicate():
			if not is_instance_valid(e) or not (e is AIEnemy) or not e.alive:
				continue
			var a: AIEnemy = e
			if r.grow(0.2).has_point(a.plan_pos()) and a.storey in storeys:
				a.take_damage(ENEMY_HITS, Vector3.DOWN, "collapse")
				hit["enemies"] += 1
	if game.camera != null:
		game.camera.nudge(2.0)
	var text: String = info["text"]
	if hit["player"] > 0.0:
		text += " (-%d)" % ceili(hit["player"])
	game.toast(text, "bad")
	last = info.duplicate()
	last.merge(hit)


func _on_strained(info: Dictionary) -> void:
	game.toast(info["text"], "warn")


# --- F10 "Structure" ---------------------------------------------------------------------

## The support state of every zone, as a toast (and the dev menu's status).
func dev_show_support() -> String:
	if model == null:
		return "No support model."
	var t := model.status_text()
	game.toast(t, "info")
	return t


## Knocks out the kitchen's north outer wall (6 m over one room): its roof
## (and the upper floor over it) should come down on the next frame.
func dev_collapse_test() -> String:
	var w: HouseWorld = game.world
	for k in range(8, 14):
		var s := Vector3i(0, 0, k)
		if HouseSupport.section_bears(w, s):
			w.cut_opening(s, true)
	return "Kitchen north wall knocked out."
