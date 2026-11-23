class_name GameState
extends RefCounted
## The whole survival state of one run (SPEC §7.1). Owner: S. Pure data: no
## nodes, no scene access. One clock (`total_minutes`); day and time derive
## from it. Every time skip goes through `advance`, which integrates the stats
## exactly once (piecewise linear, split at every threshold) and reports the
## events it crossed. Rules and numbers: docs/experiment-002/survival.md.

signal changed
signal died(cause: String)

const T := preload("res://src/survival/survival_tuning.gd")
const DAY_MIN := 1440.0
const SNAP_MIN := 0.001           ## an advance ending this close before a boundary lands on it
const STALE_INVASION_MIN := 8.0 * 60.0   ## a restored invasion overdue by more is rescheduled, not re-fired
const MAX_TOTAL_MINUTES := 3650.0 * DAY_MIN
const LOG_SIZE := 40
const APPLIED_IDS_KEPT := 64
const EVENT_RANK := {"new_day": 0, "dawn": 1, "dusk": 2, "invasion_due": 3}

var total_minutes := T.START_MINUTE:
	set(v):
		if is_finite(v):
			total_minutes = clampf(v, 0.0, MAX_TOTAL_MINUTES)
var health := 100.0:
	set(v):
		if is_finite(v):
			health = clampf(v, 0.0, 100.0)
var hunger := 75.0:
	set(v):
		if is_finite(v):
			hunger = clampf(v, 0.0, 100.0)
var hydration := 70.0:
	set(v):
		if is_finite(v):
			hydration = clampf(v, 0.0, 100.0)
var energy := 85.0:
	set(v):
		if is_finite(v):
			energy = clampf(v, 0.0, 100.0)
var inventory: Inventory:
	set(v):
		if inventory != null and inventory.changed.is_connected(_on_inventory_changed):
			inventory.changed.disconnect(_on_inventory_changed)
		inventory = v if v != null else Inventory.new()
		inventory.changed.connect(_on_inventory_changed)
var cheats := {"invulnerable": false, "unlimited": false}
var run := {}
var dead := false
var death_cause := ""


func _init() -> void:
	inventory = Inventory.new()
	run = _default_run(0)


static func new_run(run_seed := 0) -> GameState:
	var s := GameState.new()
	s.total_minutes = T.START_MINUTE
	for k in T.START_STATS:
		s.set(k, T.START_STATS[k])
	for id in T.START_ITEMS:
		s.inventory.add(id, T.START_ITEMS[id])
	s.run = _default_run(run_seed if run_seed != 0 else int(Time.get_unix_time_from_system()) & 0x7fffffff)
	return s


static func _default_run(run_seed: int) -> Dictionary:
	return {
		"seed": run_seed,
		"invasions_done": 0,
		"invasion_active": false,
		"invasion_announced": false,   # invasion_due was reported; waiting for start_invasion()
		"invasion_forced": false,      # dev: due now, reported by the next advance
		"next_invasion_at": _invasion_slot_after(-1.0),
		"expeditions": 0,
		"applied_expeditions": [],
		"dawn_collected_day": 0,
		"log": [],
	}


func _on_inventory_changed() -> void:
	changed.emit()


# --- clock ---------------------------------------------------------------------

func day() -> int:
	return int(floorf(total_minutes / DAY_MIN)) + 1


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
	var d := T.DAWN_MINUTE - minute_of_day()
	if d <= 0.0:
		d += DAY_MIN
	return d


## Advances the clock by `minutes` and integrates the stats once for the span.
## Returns the events crossed, in time order (ties: new_day, dawn, dusk,
## invasion_due): [{"type", "at": total_minutes}]. Zero, negative and
## non-finite input does nothing. One call skips at most MAX_ADVANCE_MINUTES.
## If the player dies during the span, the clock stops at the moment of death
## and only the events before it are reported. Once dead, nothing changes.
func advance(minutes: float, asleep := false) -> Array:
	if dead or not is_finite(minutes) or minutes <= 0.0:
		return []
	var start := total_minutes
	var end := _snap_end(start + minf(minutes, T.MAX_ADVANCE_MINUTES))
	_live((end - start) / 60.0, asleep, start)
	if not dead:
		total_minutes = end
	var events := _events_between(start, total_minutes)
	changed.emit()
	return events


## Moves `end` onto a boundary or the invasion time if it falls just short of it,
## so that `advance(plan_sleep(x).minutes)` and `advance(until_morning_minutes())`
## always cross the boundary they aim for despite float rounding.
func _snap_end(end: float) -> float:
	var base := floorf(end / DAY_MIN) * DAY_MIN
	for c in [base + T.DAWN_MINUTE, base + T.DUSK_MINUTE, base + DAY_MIN, float(run.get("next_invasion_at", INF))]:
		if c > end and c - end <= SNAP_MIN:
			return c
	return end


func _events_between(start: float, stop: float) -> Array:
	var events := []
	for d in range(int(floorf(start / DAY_MIN)), int(floorf(stop / DAY_MIN)) + 1):
		var base: float = d * DAY_MIN
		for e in [["new_day", base], ["dawn", base + T.DAWN_MINUTE], ["dusk", base + T.DUSK_MINUTE]]:
			if e[1] > start and e[1] <= stop:
				events.append({"type": e[0], "at": e[1]})
	if not dead and not run.get("invasion_active", false) and not run.get("invasion_announced", false):
		var forced: bool = run.get("invasion_forced", false)
		var due: float = run.get("next_invasion_at", INF)
		if forced or due <= stop:
			run["invasion_announced"] = true
			events.append({"type": "invasion_due", "at": start if forced else maxf(due, start)})
	events.sort_custom(func(a, b): return a["at"] < b["at"] or (a["at"] == b["at"] and EVENT_RANK[a["type"]] < EVENT_RANK[b["type"]]))
	return events


## Integrates the stats over `hours`, piecewise linear and split exactly where a
## threshold is crossed (hunger/hydration reach 50 or 0, health reaches 0).
## Keeps `total_minutes` in step so that `died` listeners see the time of death.
func _live(hours: float, asleep: bool, start: float) -> void:
	var k := T.SLEEP_DECAY_SCALE if asleep else 1.0
	var hunger_rate := T.HUNGER_PER_HOUR * k
	var water_rate := T.HYDRATION_PER_HOUR * k
	var energy_rate := T.SLEEP_ENERGY_PER_HOUR if asleep else -T.ENERGY_PER_HOUR
	var regen := T.REGEN_ASLEEP if asleep else T.REGEN_AWAKE
	var done := 0.0
	for _i in 16:   # at most five thresholds can split the span
		if dead or done >= hours:
			break
		var hurt := 0.0
		if hunger <= 0.0:
			hurt += T.STARVING_DAMAGE
		if hydration <= 0.0:
			hurt += T.DEHYDRATED_DAMAGE
		var healing := regen if hurt == 0.0 and hunger > T.REGEN_THRESHOLD and hydration > T.REGEN_THRESHOLD else 0.0
		if cheats.get("invulnerable", false):
			hurt = 0.0
		var dt := hours - done
		dt = minf(dt, _hours_to_threshold(hunger, hunger_rate))
		dt = minf(dt, _hours_to_threshold(hydration, water_rate))
		if hurt > 0.0:
			dt = minf(dt, health / hurt)
		hunger = _snap_stat(hunger - hunger_rate * dt)
		hydration = _snap_stat(hydration - water_rate * dt)
		energy += energy_rate * dt
		health += healing * dt - hurt * dt
		done = hours if dt >= hours - done else done + dt
		total_minutes = start + done * 60.0
		if hurt > 0.0 and health <= 1e-6:
			health = 0.0
			_die("dehydration" if hydration <= 0.0 else "starvation")


static func _hours_to_threshold(v: float, rate: float) -> float:
	if v > T.REGEN_THRESHOLD:
		return (v - T.REGEN_THRESHOLD) / rate
	if v > 0.0:
		return v / rate
	return INF


static func _snap_stat(v: float) -> float:
	if absf(v - T.REGEN_THRESHOLD) < 1e-6:
		return T.REGEN_THRESHOLD
	return 0.0 if v < 1e-6 else v


# --- health ----------------------------------------------------------------------

## Any damage source (enemies, starvation, expeditions). Blocked by the
## invulnerable cheat and after death. Emits `died` once.
func damage(amount: float, cause: String) -> void:
	if dead or not (amount > 0.0) or cheats.get("invulnerable", false):
		return
	health -= minf(amount, 1000.0)
	if health <= 1e-6:
		health = 0.0
		_die(cause)
	changed.emit()


func _die(cause: String) -> void:
	if dead:
		return
	dead = true
	death_cause = cause
	_log("Died (%s)" % cause)
	died.emit(cause)


func heal(amount: float) -> void:
	if dead or not (amount > 0.0):
		return
	health += minf(amount, 1000.0)
	changed.emit()


func move_speed_scale() -> float:
	if energy <= 0.0:
		return T.SPENT_SPEED
	if energy <= T.WARN_LEVEL:
		return T.EXHAUSTED_SPEED
	return 1.0


## Whole days since the run started (Day 1 07:00); stops at the time of death.
func days_survived() -> int:
	return maxi(int(floorf((total_minutes - T.START_MINUTE) / DAY_MIN)), 0)


## HUD warnings, most urgent first: "Dehydrated", "Starving", "Badly hurt",
## "Thirsty", "Hungry", "Exhausted".
func warnings() -> Array:
	var out := []
	if dead:
		return out
	if hydration <= 0.0:
		out.append("Dehydrated")
	if hunger <= 0.0:
		out.append("Starving")
	if health <= T.HURT_LEVEL:
		out.append("Badly hurt")
	if hydration > 0.0 and hydration <= T.WARN_LEVEL:
		out.append("Thirsty")
	if hunger > 0.0 and hunger <= T.WARN_LEVEL:
		out.append("Hungry")
	if energy <= T.WARN_LEVEL:
		out.append("Exhausted")
	return out


# --- inventory use and costs -------------------------------------------------------

func can_pay(cost: Dictionary) -> bool:
	return cheats.get("unlimited", false) or inventory.has_all(cost)


## Pays a cost atomically. The unlimited cheat pays nothing (and creates nothing).
func pay(cost: Dictionary) -> bool:
	if cheats.get("unlimited", false):
		return true
	return inventory.remove_all(cost)


func use_ammo(n := 1) -> bool:
	if n < 0:
		return false
	if cheats.get("unlimited", false):
		return true
	return inventory.remove("ammo", n)


## Why `id` can't be used right now ("" = it can).
func can_use(id) -> String:
	if dead:
		return "You're dead."
	if not Items.is_consumable(id):
		return "That can't be used."
	if inventory.count(id) <= 0:
		return "You have none left."
	var d: Dictionary = Items.DEFS[str(id)]
	var helps := (d.has("hunger") and hunger < 100.0) or (d.has("hydration") and hydration < 100.0) or (d.has("health") and health < 100.0)
	if not helps:
		return "You're not hurt." if d.has("health") else ("You're not thirsty." if not d.has("hunger") else "You couldn't eat another bite.")
	return ""


## Eats / drinks / heals with one unit. Returns feedback text ("Canned food:
## food +30, water +4"), or "" if not usable (see `can_use` for the reason).
func use_item(id) -> String:
	if can_use(id) != "":
		return ""
	var d: Dictionary = Items.DEFS[str(id)]
	inventory.remove(id, 1)
	var parts := []
	if d.has("hunger"):
		hunger += d["hunger"]
		parts.append("food +%d" % d["hunger"])
	if d.has("hydration"):
		hydration += d["hydration"]
		parts.append("water +%d" % d["hydration"])
	if d.has("health"):
		health += d["health"]
		parts.append("health +%d" % d["health"])
	changed.emit()
	return "%s: %s" % [d["name"], ", ".join(parts)]


## Rain collectors: +RAIN_WATER_PER_COLLECTOR water each, once per day. Pass the
## dawn event's "at" so every dawn of a multi-day skip counts (default: today).
## Returns what was added ({"water": n}, or {} if nothing / already collected).
func on_dawn(collectors: int, at := -1.0) -> Dictionary:
	var n := clampi(collectors, 0, 100) * T.RAIN_WATER_PER_COLLECTOR
	var d := day() if not (at >= 0.0 and at <= total_minutes) else int(floorf(at / DAY_MIN)) + 1
	if dead or n <= 0 or int(run.get("dawn_collected_day", 0)) >= d:
		return {}
	run["dawn_collected_day"] = d
	var added := inventory.add("water", n)
	if added > 0:
		_log("Rain collectors: +%d water" % added)
	return {"water": added} if added > 0 else {}


# --- sleep -------------------------------------------------------------------------

## Why the player can't sleep now ("" = they can).
func can_sleep() -> String:
	if dead:
		return "You're dead."
	if _invasion_pending():
		return "Not with them out there."
	if energy >= T.NOT_TIRED_ENERGY and not is_night():
		return "You're not tired."
	return ""


## How long a requested sleep can last: it ends exactly at the next invasion or
## straggler. {"minutes", "interrupted", "reason": ""|"invasion"|"straggler",
## "text"}. Requests are clamped to 0..MAX_SLEEP_MINUTES.
func plan_sleep(requested_minutes: float) -> Dictionary:
	var want := clampf(requested_minutes, 0.0, T.MAX_SLEEP_MINUTES) if is_finite(requested_minutes) else 0.0
	if _invasion_pending():
		return {"minutes": 0.0, "interrupted": true, "reason": "invasion", "text": "Not with them out there."}
	var stop := total_minutes + want
	var reason := ""
	var due: float = run.get("next_invasion_at", INF)
	if due > total_minutes and due <= stop:
		stop = due
		reason = "invasion"
	for d in [day() - 1, day()]:
		var s := roll_straggler(d)
		if s > total_minutes + SNAP_MIN and s < stop:
			stop = s
			reason = "straggler"
	if reason == "":
		return {"minutes": want, "interrupted": false, "reason": "", "text": ""}
	# a straggler stop lands a hair past its minute so `total_minutes >= minute` holds
	var minutes := stop - total_minutes + (1e-6 if reason == "straggler" else 0.0)
	var text := "Something is moving outside." if reason == "straggler" else "You wake to noises in the fog. They're here."
	return {"minutes": minutes, "interrupted": true, "reason": reason, "text": text}


## Total minute of the straggler on the night that starts on `day` (23:00 ..
## 03:00 next day), or -1. Deterministic from run.seed and the day: 35 % from
## Day 2, never on an invasion night.
func roll_straggler(for_day: int) -> float:
	if for_day < T.STRAGGLER_FROM_DAY or _is_invasion_night(for_day):
		return -1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = (int(run.get("seed", 0)) & 0x7fffffff) * 1000003 + for_day * 7919 + 101
	if rng.randf() >= T.STRAGGLER_CHANCE:
		return -1.0
	var span := int(T.STRAGGLER_WINDOW.y - T.STRAGGLER_WINDOW.x)
	return (for_day - 1) * DAY_MIN + T.STRAGGLER_WINDOW.x + rng.randi_range(0, span - 1)


func _is_invasion_night(d: int) -> bool:
	var due: float = run.get("next_invasion_at", INF)
	if is_finite(due) and int(floorf(due / DAY_MIN)) + 1 == d:
		return true
	return d >= T.FIRST_INVASION_DAY and (d - T.FIRST_INVASION_DAY) % T.INVASION_INTERVAL_DAYS == 0


# --- invasions ---------------------------------------------------------------------

## Invasion slots are Day 3, 6, 9... at 22:00. Returns the first slot after `t`.
static func _invasion_slot_after(t: float) -> float:
	var first := (T.FIRST_INVASION_DAY - 1) * DAY_MIN + T.INVASION_HOUR * 60.0
	var step := T.INVASION_INTERVAL_DAYS * DAY_MIN
	if t < first:
		return first
	return first + (floorf((t - first) / step) + 1.0) * step


## Announced (due) or forced, or running.
func _invasion_pending() -> bool:
	return run.get("invasion_active", false) or run.get("invasion_announced", false) or run.get("invasion_forced", false)


## 1-based index of the current (or next) invasion.
func invasion_index() -> int:
	return int(run.get("invasions_done", 0)) + 1


## HUD warning window: from 12:00 on an invasion day until it is due.
func invasion_due_soon() -> bool:
	if run.get("invasion_active", false) or run.get("invasion_announced", false):
		return false
	if run.get("invasion_forced", false):
		return true
	var due: float = run.get("next_invasion_at", INF)
	return due >= total_minutes and due - total_minutes <= (T.INVASION_HOUR - T.INVASION_WARNING_HOUR) * 60.0


func invasion_size() -> int:
	return mini(T.INVASION_BASE_SIZE + T.INVASION_SIZE_STEP * (invasion_index() - 1), T.INVASION_MAX_SIZE)


func invasion_enemy_hp() -> int:
	return T.INVASION_BASE_HP + (invasion_index() - 1) / 2


func invasion_speed_scale() -> float:
	return 1.0 + T.INVASION_SPEED_STEP * (invasion_index() - 1)


func enemy_damage() -> float:
	return T.ENEMY_DAMAGE * (1.0 + T.INVASION_DAMAGE_STEP * (invasion_index() - 1))


func start_invasion() -> void:
	if run.get("invasion_active", false):
		return
	run["invasion_active"] = true
	run["invasion_announced"] = true
	run["invasion_forced"] = false
	_log("Invasion %d begins (%d of them)" % [invasion_index(), invasion_size()])
	changed.emit()


## Ends the running (or announced but never started) invasion. Every ended
## invasion counts towards the size progression; `survived` only goes into the
## log. Schedules the next one on the first slot after now and after the slot
## that was due (so a forced invasion replaces the upcoming one).
func end_invasion(survived: bool) -> void:
	if not (run.get("invasion_active", false) or run.get("invasion_announced", false)):
		return
	_log("Invasion %d %s" % [invasion_index(), "survived" if survived else "ended"])
	run["invasion_active"] = false
	run["invasion_announced"] = false
	run["invasion_forced"] = false
	run["invasions_done"] = invasion_index()
	run["next_invasion_at"] = _invasion_slot_after(maxf(total_minutes, float(run.get("next_invasion_at", total_minutes))))
	changed.emit()


## Dev cheat: the next invasion is due now; the next advance() reports it.
## Returns false if one is already running or announced.
func force_invasion_now() -> bool:
	if run.get("invasion_active", false) or run.get("invasion_announced", false):
		return false
	run["invasion_forced"] = true
	changed.emit()
	return true


## "Day 3, 22:00 (in 15 h 00 min)", "Due now" or "In progress".
func next_invasion_text() -> String:
	if run.get("invasion_active", false):
		return "In progress (invasion %d)" % invasion_index()
	if run.get("invasion_announced", false) or run.get("invasion_forced", false):
		return "Due now (invasion %d)" % invasion_index()
	var due: float = run.get("next_invasion_at", INF)
	if not is_finite(due):
		return "None scheduled"
	var m := int(fposmod(due, DAY_MIN))
	var left := maxi(int(ceilf(due - total_minutes)), 0)
	var span := "%d h %02d min" % [left / 60, left % 60] if left >= 60 else "%d min" % left
	return "Day %d, %02d:%02d (in %s)" % [int(floorf(due / DAY_MIN)) + 1, m / 60, m % 60, span]


# --- expeditions -------------------------------------------------------------------

## Applies an expedition result exactly once (guarded by result["id"]) and
## returns the clock events crossed during the trip. See apply_expedition_report.
func apply_expedition(result: Dictionary) -> Array:
	return apply_expedition_report(result)["events"]


## Like apply_expedition, with what actually happened:
## {"applied": bool, "events", "added", "left_behind", "consumed", "lost": {id: n}, "damage": float}.
## Time passes first; then consumed and lost items are removed (clamped to what
## is owned), then gains are added up to the caps (the rest is `left_behind`),
## then damage. Unknown items and non-numeric or negative amounts are ignored.
func apply_expedition_report(result: Dictionary) -> Dictionary:
	var out := {"applied": false, "events": [], "added": {}, "left_behind": {}, "consumed": {}, "lost": {}, "damage": 0.0}
	var rid := str(result.get("id", "")) if result.get("id") != null else ""
	var applied: Array = run.get("applied_expeditions", [])
	if dead or rid == "" or rid in applied:
		return out
	applied.append(rid)
	while applied.size() > APPLIED_IDS_KEPT:
		applied.pop_front()
	run["applied_expeditions"] = applied
	run["expeditions"] = int(run.get("expeditions", 0)) + 1
	out["applied"] = true
	var minutes := clampi(Inventory.to_count(result.get("minutes", 0)), 0, int(T.MAX_EXPEDITION_MINUTES))
	out["events"] = advance(float(minutes))
	if dead:
		return out
	for key in ["consumed", "lost"]:
		var items = result.get(key, {})
		if typeof(items) != TYPE_DICTIONARY:
			continue
		for id in items:
			var n := mini(Inventory.to_count(items[id]), inventory.count(id))
			if n > 0 and inventory.remove(id, n):
				out[key][str(id)] = int(out[key].get(str(id), 0)) + n
	var gained = result.get("gained", {})
	if typeof(gained) == TYPE_DICTIONARY:
		for id in gained:
			var n := Inventory.to_count(gained[id])
			if n <= 0 or not Items.has(id):
				continue
			var k := inventory.add(id, n)
			if k > 0:
				out["added"][str(id)] = int(out["added"].get(str(id), 0)) + k
			if n > k:
				out["left_behind"][str(id)] = int(out["left_behind"].get(str(id), 0)) + n - k
	var dmg := _finite_or_nan(result.get("damage", 0.0))
	if is_finite(dmg) and dmg > 0.0:
		out["damage"] = minf(dmg, 100.0)
		damage(out["damage"], "expedition")
	var name_text := str(result.get("name", "Expedition")).left(60)
	_log("%s: %s" % [name_text, str(result.get("summary", "")).left(140)])
	changed.emit()
	return out


func _log(text: String) -> void:
	var l: Array = run.get("log", [])
	l.append("Day %d %s  %s" % [day(), clock_text(), text])
	while l.size() > LOG_SIZE:
		l.pop_front()
	run["log"] = l


# --- persistence ---------------------------------------------------------------------

## Small slot description for the save file and the main menu.
func summary() -> Dictionary:
	return {
		"day": day(), "clock": clock_text(), "health": int(ceilf(health)),
		"days_survived": days_survived(), "invasions_done": int(run.get("invasions_done", 0)),
		"dead": dead,
	}


func to_dict() -> Dictionary:
	return {
		"total_minutes": total_minutes, "health": health, "hunger": hunger,
		"hydration": hydration, "energy": energy, "inventory": inventory.to_dict(),
		"cheats": cheats.duplicate(), "run": run.duplicate(true), "dead": dead, "death_cause": death_cause,
	}


## Restores a state from untrusted data. Returns null (no crash) when the clock,
## a stat, the inventory or the run record is missing or of the wrong type, or a
## number is NaN/infinite. Out-of-range values are clamped, unknown items
## dropped, and the run record is sanitised field by field.
static func from_dict(d) -> GameState:
	if typeof(d) != TYPE_DICTIONARY:
		return null
	var nums := {}
	for k in ["total_minutes", "health", "hunger", "hydration", "energy"]:
		var v := _finite_or_nan(d.get(k))
		if is_nan(v):
			return null
		nums[k] = v
	if typeof(d.get("inventory")) != TYPE_DICTIONARY or typeof(d.get("run")) != TYPE_DICTIONARY:
		return null
	var s := GameState.new()
	s.total_minutes = clampf(nums["total_minutes"], T.START_MINUTE, MAX_TOTAL_MINUTES)
	for k in ["health", "hunger", "hydration", "energy"]:
		s.set(k, nums[k])
	s.inventory.from_dict(d["inventory"])
	var c = d.get("cheats", {})
	if typeof(c) != TYPE_DICTIONARY:
		c = {}
	s.cheats = {"invulnerable": _flag(c.get("invulnerable")), "unlimited": _flag(c.get("unlimited"))}
	s.run = _clean_run(d["run"], s.total_minutes)
	s.dead = _flag(d.get("dead")) or (s.health <= 0.0 and not s.cheats["invulnerable"])
	s.death_cause = str(d.get("death_cause", "")).left(60) if s.dead else ""
	return s


static func _clean_run(r: Dictionary, now: float) -> Dictionary:
	var out := r.duplicate(true)   # unknown keys from other modules survive
	var seed_f := _finite_or_nan(r.get("seed"))
	out["seed"] = (int(r["seed"]) if typeof(r.get("seed")) == TYPE_INT else (0 if is_nan(seed_f) else int(clampf(seed_f, -2e9, 2e9)))) & 0x7fffffff
	out["invasions_done"] = clampi(Inventory.to_count(r.get("invasions_done", 0)), 0, 1000)
	# live encounters are never saved: a restored run has no invasion running,
	# and one that was due (announced or not) is reported again by the next advance
	out["invasion_active"] = false
	out["invasion_announced"] = false
	out["invasion_forced"] = _flag(r.get("invasion_forced"))
	var due := _finite_or_nan(r.get("next_invasion_at"))
	if is_nan(due) or due < 0.0 or due > now + 400.0 * DAY_MIN:
		due = _invasion_slot_after(now - STALE_INVASION_MIN)
	elif now - due > STALE_INVASION_MIN and not out["invasion_forced"]:
		due = _invasion_slot_after(now)
	out["next_invasion_at"] = due
	out["expeditions"] = maxi(Inventory.to_count(r.get("expeditions", 0)), 0)
	out["dawn_collected_day"] = maxi(Inventory.to_count(r.get("dawn_collected_day", 0)), 0)
	var ids := []
	var a = r.get("applied_expeditions", [])
	if typeof(a) == TYPE_ARRAY:
		for x in a:
			if typeof(x) == TYPE_STRING and x != "":
				ids.append(x)
	out["applied_expeditions"] = ids.slice(maxi(ids.size() - APPLIED_IDS_KEPT, 0))
	var lines := []
	var l = r.get("log", [])
	if typeof(l) == TYPE_ARRAY:
		for x in l:
			if typeof(x) == TYPE_STRING:
				lines.append(x.left(200))
	out["log"] = lines.slice(maxi(lines.size() - LOG_SIZE, 0))
	return out


## A finite float from an int or float; NaN for anything else.
static func _finite_or_nan(v) -> float:
	if typeof(v) == TYPE_INT:
		return float(v)
	if typeof(v) == TYPE_FLOAT and is_finite(v):
		return v
	return NAN


static func _flag(v) -> bool:
	match typeof(v):
		TYPE_BOOL:
			return v
		TYPE_INT:
			return v != 0
	return false
