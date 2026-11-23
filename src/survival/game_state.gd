class_name GameState
extends RefCounted
## The whole survival state of one run (SPEC §7.1). Owner: S. Pure data: no
## nodes, no scene access. One clock (`total_minutes`); day and time derive
## from it. Every time skip goes through `advance`, which applies stat decay
## exactly once and reports the events it crossed.

signal changed
signal died(cause: String)

const T := preload("res://src/survival/survival_tuning.gd")
const DAY_MIN := 1440.0
const STEP_MIN := 10.0          ## integration step for decay / thresholds

var total_minutes := T.START_MINUTE
var health := 100.0
var hunger := 75.0
var hydration := 70.0
var energy := 85.0
var inventory := Inventory.new()
var cheats := {"invulnerable": false, "unlimited": false}
var run := {}
var dead := false
var death_cause := ""


static func new_run(seed := 0) -> GameState:
	var s := GameState.new()
	s.total_minutes = T.START_MINUTE
	for k in T.START_STATS:
		s.set(k, T.START_STATS[k])
	for id in T.START_ITEMS:
		s.inventory.add(id, T.START_ITEMS[id])
	s.run = {
		"seed": seed if seed != 0 else int(Time.get_unix_time_from_system()) & 0x7fffffff,
		"invasions_done": 0,
		"invasion_active": false,
		"next_invasion_at": (T.FIRST_INVASION_DAY - 1) * DAY_MIN + T.INVASION_HOUR * 60.0,
		"expeditions": 0,
		"applied_expeditions": [],
		"log": [],
	}
	s.inventory.changed.connect(s._on_inventory_changed)
	return s


func _on_inventory_changed() -> void:
	changed.emit()


# --- clock ---------------------------------------------------------------------

func day() -> int:
	return int(floor(total_minutes / DAY_MIN)) + 1


func minute_of_day() -> float:
	return fposmod(total_minutes, DAY_MIN)


func clock_text() -> String:
	var m := int(minute_of_day())
	return "%02d:%02d" % [m / 60, m % 60]


func night_amount() -> float:
	var m := minute_of_day()
	if m < T.NIGHT_RAMP_DOWN.x or m >= T.NIGHT_RAMP_UP.y:
		return 1.0
	if m < T.NIGHT_RAMP_DOWN.y:
		return 1.0 - smoothstep(T.NIGHT_RAMP_DOWN.x, T.NIGHT_RAMP_DOWN.y, m)
	if m >= T.NIGHT_RAMP_UP.x:
		return smoothstep(T.NIGHT_RAMP_UP.x, T.NIGHT_RAMP_UP.y, m)
	return 0.0


func is_night() -> bool:
	return night_amount() > 0.5


## Minutes from now until the next 06:00.
func until_morning_minutes() -> float:
	var m := minute_of_day()
	var d := T.DAWN_MINUTE - m
	if d <= 0.0:
		d += DAY_MIN
	return d


## Advances the clock, applying stat decay once for the span. Returns the
## events crossed, in order: {"type": "new_day"|"dawn"|"dusk"|"invasion_due", "at": minute}.
func advance(minutes: float, asleep := false) -> Array:
	var events := []
	if minutes <= 0.0 or dead:
		return events
	var start := total_minutes
	var end := start + minutes
	# boundary events
	var first_day := int(floor(start / DAY_MIN))
	var last_day := int(floor(end / DAY_MIN))
	for d in range(first_day, last_day + 1):
		var base := d * DAY_MIN
		for e in [["new_day", base], ["dawn", base + T.DAWN_MINUTE], ["dusk", base + T.DUSK_MINUTE]]:
			if e[1] > start and e[1] <= end:
				events.append({"type": e[0], "at": e[1]})
	var due: float = run.get("next_invasion_at", INF)
	if not run.get("invasion_active", false) and due > start and due <= end:
		events.append({"type": "invasion_due", "at": due})
	events.sort_custom(func(a, b): return a["at"] < b["at"])
	# decay
	var left := minutes
	while left > 0.0 and not dead:
		var step := minf(left, STEP_MIN)
		_decay(step / 60.0, asleep)
		left -= step
	total_minutes = end
	changed.emit()
	return events


func _decay(hours: float, asleep: bool) -> void:
	var k := T.SLEEP_DECAY_SCALE if asleep else 1.0
	hunger = clampf(hunger - T.HUNGER_PER_HOUR * k * hours, 0.0, 100.0)
	hydration = clampf(hydration - T.HYDRATION_PER_HOUR * k * hours, 0.0, 100.0)
	if asleep:
		energy = clampf(energy + T.SLEEP_ENERGY_PER_HOUR * hours, 0.0, 100.0)
	else:
		energy = clampf(energy - T.ENERGY_PER_HOUR * hours, 0.0, 100.0)
	var dmg := 0.0
	if hunger <= 0.0:
		dmg += T.STARVING_DAMAGE * hours
	if hydration <= 0.0:
		dmg += T.DEHYDRATED_DAMAGE * hours
	if dmg > 0.0:
		damage(dmg, "dehydration" if hydration <= 0.0 else "starvation")
	elif hunger > T.REGEN_THRESHOLD and hydration > T.REGEN_THRESHOLD:
		heal((T.REGEN_ASLEEP if asleep else T.REGEN_AWAKE) * hours)


# --- health ----------------------------------------------------------------------

func damage(amount: float, cause: String) -> void:
	if dead or amount <= 0.0 or cheats.get("invulnerable", false):
		return
	health = clampf(health - amount, 0.0, 100.0)
	if health <= 0.0:
		dead = true
		death_cause = cause
		changed.emit()
		died.emit(cause)
		return
	changed.emit()


func heal(amount: float) -> void:
	if dead or amount <= 0.0:
		return
	health = clampf(health + amount, 0.0, 100.0)
	changed.emit()


func move_speed_scale() -> float:
	if energy <= 0.0:
		return T.SPENT_SPEED
	if energy <= T.WARN_LEVEL:
		return T.EXHAUSTED_SPEED
	return 1.0


func days_survived() -> int:
	return maxi(int(floor((total_minutes - T.START_MINUTE) / DAY_MIN)), 0)


# --- inventory use and costs -------------------------------------------------------

func can_pay(cost: Dictionary) -> bool:
	return cheats.get("unlimited", false) or inventory.has_all(cost)


func pay(cost: Dictionary) -> bool:
	if cheats.get("unlimited", false):
		return true
	return inventory.remove_all(cost)


func use_ammo(n := 1) -> bool:
	if cheats.get("unlimited", false):
		return true
	return inventory.remove("ammo", n)


## Eats / drinks / heals with one unit. Returns feedback text, "" if not usable.
func use_item(id: String) -> String:
	if dead or not Items.is_consumable(id) or inventory.count(id) <= 0:
		return ""
	var d: Dictionary = Items.DEFS[id]
	inventory.remove(id, 1)
	var parts := []
	if d.has("hunger"):
		hunger = clampf(hunger + d["hunger"], 0.0, 100.0)
		parts.append("food +%d" % d["hunger"])
	if d.has("hydration"):
		hydration = clampf(hydration + d["hydration"], 0.0, 100.0)
		parts.append("water +%d" % d["hydration"])
	if d.has("health"):
		heal(d["health"])
		parts.append("health +%d" % d["health"])
	changed.emit()
	return "%s: %s" % [d["name"], ", ".join(parts)]


# --- sleep and invasions -----------------------------------------------------------

func plan_sleep(requested_minutes: float) -> Dictionary:
	if run.get("invasion_active", false):
		return {"minutes": 0.0, "interrupted": true, "reason": "invasion"}
	var due: float = run.get("next_invasion_at", INF)
	if due > total_minutes and due <= total_minutes + requested_minutes:
		return {"minutes": due - total_minutes, "interrupted": true, "reason": "invasion"}
	return {"minutes": requested_minutes, "interrupted": false, "reason": ""}


func invasion_index() -> int:
	return int(run.get("invasions_done", 0)) + 1


func invasion_due_soon() -> bool:
	var due: float = run.get("next_invasion_at", INF)
	return not run.get("invasion_active", false) and due - total_minutes <= (T.INVASION_HOUR - T.INVASION_WARNING_HOUR) * 60.0 and due >= total_minutes


func invasion_size() -> int:
	return mini(T.INVASION_BASE_SIZE + T.INVASION_SIZE_STEP * (invasion_index() - 1), T.INVASION_MAX_SIZE)


func invasion_enemy_hp() -> int:
	return Tuning.ENEMY_HP + (invasion_index() - 1) / 2


func invasion_speed_scale() -> float:
	return 1.0 + 0.05 * (invasion_index() - 1)


func enemy_damage() -> float:
	return T.ENEMY_DAMAGE * (1.0 + 0.1 * (invasion_index() - 1))


func start_invasion() -> void:
	run["invasion_active"] = true
	changed.emit()


func end_invasion(survived: bool) -> void:
	if not run.get("invasion_active", false):
		return
	run["invasion_active"] = false
	if survived:
		run["invasions_done"] = int(run.get("invasions_done", 0)) + 1
	run["next_invasion_at"] = float(run.get("next_invasion_at", total_minutes)) + T.INVASION_INTERVAL_DAYS * DAY_MIN
	while run["next_invasion_at"] <= total_minutes:
		run["next_invasion_at"] += T.INVASION_INTERVAL_DAYS * DAY_MIN
	changed.emit()


# --- expeditions -------------------------------------------------------------------

## Applies an expedition result exactly once (guarded by result["id"]).
func apply_expedition(result: Dictionary) -> Array:
	var rid := str(result.get("id", ""))
	var applied: Array = run.get("applied_expeditions", [])
	if rid == "" or rid in applied:
		return []
	applied.append(rid)
	if applied.size() > 32:
		applied.pop_front()
	run["applied_expeditions"] = applied
	run["expeditions"] = int(run.get("expeditions", 0)) + 1
	var events := advance(maxf(float(result.get("minutes", 0)), 0.0))
	for id in result.get("consumed", {}):
		inventory.remove(id, mini(int(result["consumed"][id]), inventory.count(id)))
	for id in result.get("lost", {}):
		inventory.remove(id, mini(int(result["lost"][id]), inventory.count(id)))
	for id in result.get("gained", {}):
		inventory.add(id, maxi(int(result["gained"][id]), 0))
	damage(float(result.get("damage", 0.0)), "expedition")
	_log("%s: %s" % [result.get("name", "Expedition"), result.get("summary", "")])
	return events


func _log(text: String) -> void:
	var l: Array = run.get("log", [])
	l.append("Day %d %s  %s" % [day(), clock_text(), text])
	if l.size() > 40:
		l.pop_front()
	run["log"] = l


# --- persistence ---------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"total_minutes": total_minutes, "health": health, "hunger": hunger,
		"hydration": hydration, "energy": energy, "inventory": inventory.to_dict(),
		"cheats": cheats.duplicate(), "run": run.duplicate(true), "dead": dead, "death_cause": death_cause,
	}


static func from_dict(d: Dictionary) -> GameState:
	for k in ["total_minutes", "health", "hunger", "hydration", "energy", "inventory", "run"]:
		if not d.has(k):
			return null
	var s := GameState.new()
	s.total_minutes = maxf(float(d["total_minutes"]), 0.0)
	for k in ["health", "hunger", "hydration", "energy"]:
		s.set(k, clampf(float(d[k]), 0.0, 100.0))
	s.inventory.from_dict(d["inventory"])
	var c: Dictionary = d.get("cheats", {})
	s.cheats = {"invulnerable": bool(c.get("invulnerable", false)), "unlimited": bool(c.get("unlimited", false))}
	s.run = (d["run"] as Dictionary).duplicate(true)
	s.dead = bool(d.get("dead", false))
	s.death_cause = str(d.get("death_cause", ""))
	s.inventory.changed.connect(s._on_inventory_changed)
	return s
