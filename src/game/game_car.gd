extends Node
## The yard car (Experiment 004, E). It starts broken; an interactable at the
## car ("[E] Inspect the car") lists what the repair needs, and once
## everything is in the house "[E] Repair the car (2 h)" spends the parts and
## two hours of game time (a fade, like sleep) and sets GameState.car_repaired
## (saved). The headlights blink once when it starts. Afterwards the car is
## expedition equipment (ExpeditionData: CAR_*): picked on the expedition
## screen, it carries far more (heavy loads too), cuts the travel time and
## burns one fuel can per trip. No driving. F10: dev_give_parts, dev_repair.
## Docs: docs/experiment-004/car.md.

const REPAIR_COST := {"car_battery": 1, "fuel": 2, "scrap": 10, "iron": 4, "nails": 6}
const REPAIR_ORDER := ["car_battery", "fuel", "scrap", "iron", "nails"]
const REPAIR_MINUTES := 120.0
const CAR_RECT := Rect2(16.0, 8.5, 2.0, 4.4)   ## fallback; HousePlan.PROPS "car" wins
const REACH := 0.35                            ## the prompt point sits this far outside the body

var game: Node                         ## SurvivalGame
var spot: CarSpot
var rect := CAR_RECT
var repairs := 0                       ## repairs done here (tests)
var _lamps: Array = []                 ## [OmniLight3D, MeshInstance3D] pairs
var _busy := false


func setup(g: Node) -> void:
	game = g
	for p in HousePlan.PROPS:
		if str(p.get("id", "")) == "car":
			rect = p["rect"]
	spot = CarSpot.new()
	spot.name = "CarSpot"
	spot.car = self
	game.add_child(spot)
	spot.global_position = Vector3(rect.get_center().x, 0.0, rect.get_center().y)
	_build_lamps()


func interactables() -> Array:
	return [spot] if spot != null and is_instance_valid(spot) else []


## What the repair still needs: {item: missing amount} ({} = ready).
static func missing(s: GameState) -> Dictionary:
	var out := {}
	if s.cheats.get("unlimited", false):
		return out
	for id in REPAIR_COST:
		var short := int(REPAIR_COST[id]) - s.inventory.count(id)
		if short > 0:
			out[id] = short
	return out


## "Car battery 0/1 · Fuel cans 1/2 · ...": have / need per part.
static func needs_text(s: GameState) -> String:
	var parts := []
	for id in REPAIR_ORDER:
		parts.append("%s %d/%d" % [Items.name_of(id), mini(s.inventory.count(id), int(REPAIR_COST[id])), int(REPAIR_COST[id])])
	return " · ".join(parts)


func prompt() -> String:
	var s: GameState = game.state
	if s.dead or _busy:
		return ""
	if s.car_repaired:
		return "[E] Check the car"
	if missing(s).is_empty():
		return "[E] Repair the car (2 h)"
	return "[E] Inspect the car"


func interact() -> void:
	var s: GameState = game.state
	if _busy or s.dead:
		return
	if s.car_repaired:
		game.toast("The car runs. Take it on an expedition: carries far more, faster there and back, 1 fuel can a trip (%d left)." % s.inventory.count("fuel"), "good")
		blink()
		return
	var m := missing(s)
	if not m.is_empty():
		game.toast("The car won't start. It needs: %s." % needs_text(s), "warn")
		return
	repair()


## Spends the parts and two hours, then the car runs. Returns "" or the reason.
func repair() -> String:
	var s: GameState = game.state
	if s.car_repaired:
		return "The car already runs."
	if not missing(s).is_empty():
		return "Missing parts."
	if game._threats():
		game.toast("Not with them out there.", "warn")
		return "threats"
	if not s.pay(REPAIR_COST):
		return "Missing parts."
	_busy = true
	var fade = game.ui.fade if game.ui != null else null
	if fade != null and game.is_inside_tree() and game.fade_time > 0.0:
		await fade.fade_to(1.0, game.fade_time)
		fade.set_text("Working on the car…")
	game._advance_clock(REPAIR_MINUTES)
	s.car_repaired = true
	repairs += 1
	s.changed.emit()
	if fade != null and game.is_inside_tree() and game.fade_time > 0.0:
		fade.set_text("Day %d · %s" % [s.day(), s.clock_text()])
		await fade.fade_to(0.0, game.fade_time)
		fade.set_text("")
	_busy = false
	if s.dead:
		return "dead"
	game.toast("The engine coughs, then catches. The car runs: pick it on the expedition screen.", "good")
	Sfx.play("ui/open")
	blink()
	game._autosave("car")
	return ""


# --- the headlights --------------------------------------------------------------------

func _build_lamps() -> void:
	# The car faces north (HousePlan facing "N"): its front is the rect's low-y edge.
	var front := rect.position.y + 0.12
	for x in [rect.position.x + 0.42, rect.end.x - 0.42]:
		var mi := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.09
		sph.height = 0.12
		mi.mesh = sph
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.95, 0.78)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		game.add_child(mi)
		mi.global_position = Vector3(x, 0.72, front)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.93, 0.75)
		l.omni_range = 5.0
		l.light_energy = 0.0
		l.visible = false
		game.add_child(l)
		l.global_position = Vector3(x, 0.8, front - 0.5)
		_lamps.append([l, mi])


## The headlights flash twice (the repaired car, or a check on it).
func blink() -> void:
	if _lamps.is_empty() or not is_inside_tree():
		return
	var tw := create_tween()
	for k in 2:
		tw.tween_callback(_set_lamps.bind(true))
		tw.tween_interval(0.28)
		tw.tween_callback(_set_lamps.bind(false))
		tw.tween_interval(0.22)


func _set_lamps(on: bool) -> void:
	for p in _lamps:
		(p[0] as OmniLight3D).visible = on
		(p[0] as OmniLight3D).light_energy = 2.6 if on else 0.0
		(p[1] as MeshInstance3D).visible = on


func lamps_lit() -> bool:
	return not _lamps.is_empty() and (_lamps[0][1] as MeshInstance3D).visible


# --- developer tools (F10) -------------------------------------------------------------

## Adds whatever the repair still needs (and two spare fuel cans).
func dev_give_parts() -> void:
	var s: GameState = game.state
	for id in REPAIR_COST:
		s.inventory.add(id, maxi(int(REPAIR_COST[id]) - s.inventory.count(id), 0))
	s.inventory.add("fuel", 2)
	game.toast("Dev: car parts and fuel added.", "info")


## Repairs the car at once (no parts, no time).
func dev_repair() -> void:
	game.state.car_repaired = true
	game.state.changed.emit()
	game.toast("Dev: the car runs.", "info")
	blink()


func info() -> String:
	var s: GameState = game.state
	return "Car %s · %s" % ["repaired" if s.car_repaired else "broken", needs_text(s)]


## The car's interactable. It follows the player around the car's outline so
## [E] works from any side (InteractionFinder measures to this node).
class CarSpot extends Node3D:
	var car: Node

	func _process(_delta: float) -> void:
		if car == null or car.game == null or car.game.player == null:
			return
		var r: Rect2 = car.rect.grow(REACH)
		var p: Vector2 = car.game.player.plan_pos()
		var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
		global_position = Vector3(q.x, 0.0, q.y)

	func interact_prompt() -> String:
		return car.prompt() if car != null else ""

	func interact(_g: Node) -> void:
		if car != null:
			car.interact()
