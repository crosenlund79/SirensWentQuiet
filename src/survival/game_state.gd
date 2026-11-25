class_name GameState
extends RefCounted
## The whole survival state of one run (SPEC §7.1, SPEC-003 §2). Owner: K. Pure
## data: no nodes, no scene access. One clock (`total_minutes`); day and time
## derive from it. Every time skip goes through `advance`, which integrates the
## stats exactly once (piecewise linear, split at every threshold) and reports
## the events it crossed. Experiment 003 adds equipment slots with real effects,
## weapon magazines and difficulty semantics. Rules and numbers:
## docs/experiment-002/survival.md and docs/experiment-003/equipment.md.

signal changed
signal died(cause: String)
signal equipment_changed

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
## Experiment 003 (K):
var difficulty := Difficulty.DEFAULT            ## "easy" | "normal" | "hard" (set_difficulty reschedules)
var equipment := {}                             ## slot -> item id (Equipment.SLOTS); only owned items
var weapons := {}                               ## owned weapon id -> {"loaded": int} (magazine contents)
var active_weapon_slot := "primary"             ## the weapon in hand: "primary" | "secondary"
var region := RegionState.new_region()          ## the world outside the lot (SPEC-003 §3)
var run := {}
## Experiment 004 household state (fireplace, light and room switches), owned
## by the game's home helper (src/home/game_home.gd). Optional in saves.
var home := {}
var dead := false
var death_cause := ""
## Newly acquired gear goes into its slot when that slot is free (not saved).
var auto_equip := true
## Experiment 004 (E): the quick-access bar (Hotbar rules; saved as "hotbar")
## and the yard car, repaired once (saved as "car_repaired"). Both optional:
## older saves load with an empty bar (filled by the game) and a broken car.
var hotbar := Hotbar.new_bar()
var car_repaired := false
# Exp 005 (C): Eli's mood (Mood, src/survival/mood.gd). Saved; older saves get Mood.START.
var mood := Mood.START                          ## 0..100
var mood_state := {}                            ## Mood memories and bleak hours ({"mem", "bleak"})
var rest_scale := 1.0                           ## sleep energy x this (mood and bedroom comfort; set by the game, not saved)

var _quiet := false                             ## restoring: no equipment sync
var _gear_seen := {}                            ## equippable ids owned at the last sync


func _init() -> void:
	inventory = Inventory.new()
	run = _default_run(0)


## A fresh run: Day 1 07:00, the starting stats and items, the handgun equipped
## as the primary weapon holding the difficulty's `start_rounds` and no reserve.
static func new_run(run_seed := 0, level := Difficulty.DEFAULT) -> GameState:
	var s := GameState.new()
	s.difficulty = Difficulty.valid(level)
	s.total_minutes = T.START_MINUTE
	for k in T.START_STATS:
		s.set(k, T.START_STATS[k])
	s._quiet = true
	for id in T.START_ITEMS:
		s.inventory.add(id, T.START_ITEMS[id])
	s._quiet = false
	s._mark_gear_seen()
	s._sync_equipment(false)
	s.equip("handgun", "primary")
	s.set_magazine("handgun", int(Difficulty.get_value(s.difficulty, "start_rounds")))
	s.run = _default_run(run_seed if run_seed != 0 else int(Time.get_unix_time_from_system()) & 0x7fffffff, s.difficulty)
	return s


static func _default_run(run_seed: int, level := Difficulty.DEFAULT) -> Dictionary:
	return {
		"seed": run_seed,
		"invasions_done": 0,
		"invasion_active": false,
		"invasion_announced": false,   # invasion_due was reported; waiting for start_invasion()
		"invasion_forced": false,      # dev: due now, reported by the next advance
		"next_invasion_at": _invasion_slot_after(-1.0, level),
		"expeditions": 0,
		"applied_expeditions": [],
		"dawn_collected_day": 0,
		"log": [],
	}


func _on_inventory_changed() -> void:
	if not _quiet:
		_sync_equipment()
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
	var energy_rate := T.SLEEP_ENERGY_PER_HOUR * rest_scale if asleep else -T.ENERGY_PER_HOUR   # Exp 005 (C): rest_scale
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

## Any damage source (enemies, blasts, expeditions). Blocked by the
## invulnerable cheat and after death. Emits `died` once. An equipped vest
## takes 35 % off every cause except starvation and dehydration
## (`damage_factor`); the reduction applies before the 1000 bound.
func damage(amount: float, cause: String) -> void:
	if dead or not (amount > 0.0) or cheats.get("invulnerable", false):
		return
	health -= minf(amount * damage_factor(cause), 1000.0)
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


# --- equipment (SPEC-003 §2) -------------------------------------------------------

## Puts owned gear into a slot. `slot` "" picks one: the slot it fits, for a
## weapon the first free weapon slot (both taken: the weapon in hand is
## replaced). A weapon moved to the other weapon slot swaps places. Returns ""
## on success (also when it was already there) or a readable reason.
func equip(id, slot := "") -> String:
	if dead:
		return "You're dead."
	if not Items.has(id):
		return "Unknown item."
	id = str(id)
	var fits := Equipment.slots_for(id)
	if fits.is_empty():
		return "%s can't be equipped." % Items.name_of(id)
	if slot != "" and not slot in fits:
		return "%s doesn't go in the %s slot." % [Items.name_of(id), str(Equipment.SLOT_NAMES.get(slot, slot)).to_lower()]
	if inventory.count(id) <= 0:
		return "You don't have a %s." % Items.name_of(id).to_lower()
	var current := slot_of(id)
	if slot == "":
		if current != "":
			return ""
		slot = fits[0]
		for f in fits:
			if equipped(f) == "":
				slot = f
				break
		if equipped(slot) != "" and fits.size() > 1 and active_weapon_slot in fits:
			slot = active_weapon_slot
	if current == slot:
		return ""
	var prev := equipped(slot)
	if current != "":
		if prev != "":
			equipment[current] = prev
		else:
			equipment.erase(current)
	equipment[slot] = id
	_equipment_changed()
	return ""


## Empties a slot (the item stays in the inventory). False if it was empty.
func unequip(slot) -> bool:
	if not Equipment.is_slot(slot) or equipped(slot) == "":
		return false
	equipment.erase(slot)
	_equipment_changed()
	return true


## The item id in `slot`, or "" (empty, unknown slot, or no longer owned).
func equipped(slot) -> String:
	var id = equipment.get(slot, "") if Equipment.is_slot(slot) else ""
	return str(id) if typeof(id) == TYPE_STRING and id != "" and inventory.count(id) > 0 else ""


func has_equipped(id) -> bool:
	return slot_of(id) != ""


## The slot `id` is equipped in, or "".
func slot_of(id) -> String:
	for slot in Equipment.SLOTS:
		if equipped(slot) == str(id) and str(id) != "":
			return slot
	return ""


## Damage multiplier for `cause`: Equipment.VEST_FACTOR with the vest equipped,
## except for starvation and dehydration; 1 otherwise.
func damage_factor(cause: String) -> float:
	if has_equipped("vest") and not cause in Equipment.UNARMORED_CAUSES:
		return Equipment.VEST_FACTOR
	return 1.0


## Expedition carrying capacity (loot) multiplier: 1.5 with the backpack
## equipped, else 1. Household material caps don't change.
func carry_multiplier() -> float:
	return Equipment.BACKPACK_CARRY if has_equipped("backpack") else 1.0


## Why the player can't build ("" = they can): the household needs a hammer
## (owned; it needn't be equipped). The unlimited cheat builds without one.
func can_build() -> String:
	if cheats.get("unlimited", false) or inventory.count("hammer") > 0:
		return ""
	return "You need a hammer."


func _equipment_changed() -> void:
	_fix_active_slot()
	equipment_changed.emit()
	changed.emit()


## Keeps equipment, magazines and the weapon in hand consistent with the
## inventory: gear no longer owned leaves its slot, a weapon no longer owned
## takes its magazine with it, a newly owned weapon gets an empty magazine,
## and newly acquired gear goes into a free slot (auto_equip; not the hammer).
func _sync_equipment(notify := true) -> void:
	var eq_changed := false
	for slot in equipment.keys():
		var id = equipment[slot]
		if not Equipment.is_slot(slot) or typeof(id) != TYPE_STRING or inventory.count(id) <= 0 or not Equipment.fits(id, slot):
			equipment.erase(slot)
			eq_changed = true
	for id in weapons.keys():
		if not WeaponDefs.has(id) or inventory.count(id) <= 0:
			weapons.erase(id)
	for id in WeaponDefs.ids():
		if inventory.count(id) > 0 and not weapons.has(id):
			weapons[id] = {"loaded": 0}
	for id in Items.DEFS:
		if not Equipment.is_equippable(id):
			continue
		var owned := inventory.count(id) > 0
		if owned and not _gear_seen.has(id) and auto_equip and not id in Equipment.NO_AUTO_EQUIP and slot_of(id) == "":
			for slot in Equipment.slots_for(id):
				if equipped(slot) == "":
					equipment[slot] = id
					eq_changed = true
					break
		if owned:
			_gear_seen[id] = true
		else:
			_gear_seen.erase(id)
	if eq_changed:
		_fix_active_slot()
		if notify:
			equipment_changed.emit()


func _mark_gear_seen() -> void:
	_gear_seen.clear()
	for id in Items.DEFS:
		if Equipment.is_equippable(id) and inventory.count(id) > 0:
			_gear_seen[id] = true


func _fix_active_slot() -> void:
	if not active_weapon_slot in Equipment.WEAPON_SLOTS:
		active_weapon_slot = "primary"
	if equipped(active_weapon_slot) == "":
		for slot in Equipment.WEAPON_SLOTS:
			if equipped(slot) != "":
				active_weapon_slot = slot
				return


# --- weapons: magazines and reserve -------------------------------------------------

## The weapon in hand ("" = none): the active weapon slot, else the other one.
func active_weapon() -> String:
	_fix_active_slot()
	return equipped(active_weapon_slot)


## Makes `slot`'s weapon the one in hand. False if that slot is empty.
func set_active_weapon_slot(slot: String) -> bool:
	if not slot in Equipment.WEAPON_SLOTS or equipped(slot) == "":
		return false
	if slot != active_weapon_slot:
		active_weapon_slot = slot
		changed.emit()
	return true


## Rounds in `id`'s magazine (0 when not owned).
func magazine(id) -> int:
	if not WeaponDefs.has(id) or inventory.count(id) <= 0:
		return 0
	var w = weapons.get(str(id), {})
	var n := Inventory.to_count(w.get("loaded", 0)) if typeof(w) == TYPE_DICTIONARY else 0
	return clampi(n, 0, WeaponDefs.capacity(id))


## Sets the magazine directly (start, migration, dev). Clamped to the capacity;
## ignored for weapons not owned.
func set_magazine(id, n: int) -> void:
	if WeaponDefs.has(id) and inventory.count(id) > 0:
		_set_loaded(str(id), n)
		changed.emit()


func _set_loaded(id: String, n: int) -> void:
	weapons[id] = {"loaded": clampi(n, 0, WeaponDefs.capacity(id))}


## Rounds for `id` in the inventory (its ammo item).
func reserve(id) -> int:
	return inventory.count(WeaponDefs.ammo_of(id)) if WeaponDefs.has(id) else 0


## Moves up to `n` rounds (-1: as many as fit) from the reserve into `id`'s
## magazine. The unlimited cheat loads without taking from the reserve.
## Returns how many were loaded.
func load_rounds(id, n := -1) -> int:
	if dead or not WeaponDefs.has(id) or inventory.count(id) <= 0:
		return 0
	var room := WeaponDefs.capacity(id) - magazine(id)
	var want := room if n < 0 else mini(n, room)
	var unlimited: bool = cheats.get("unlimited", false)
	var k := want if unlimited else mini(want, reserve(id))
	if k <= 0:
		return 0
	_set_loaded(str(id), magazine(id) + k)
	if not unlimited:
		inventory.remove(WeaponDefs.ammo_of(id), k)
	else:
		changed.emit()
	return k


## Spends one round from `id`'s magazine for one trigger pull. False when it is
## empty. The unlimited cheat keeps the magazine full instead.
func spend_round(id) -> bool:
	if dead or not WeaponDefs.has(id) or inventory.count(id) <= 0:
		return false
	if cheats.get("unlimited", false):
		if magazine(id) < WeaponDefs.capacity(id):
			_set_loaded(str(id), WeaponDefs.capacity(id))
			changed.emit()
		return true
	var n := magazine(id)
	if n <= 0:
		return false
	_set_loaded(str(id), n - 1)
	changed.emit()
	return true


## Every round of `ammo_id` the player has: the reserve plus the magazines of
## the owned weapons that take it (what an expedition can bring).
func rounds_carried(ammo_id: String) -> int:
	var n := inventory.count(ammo_id)
	for w in WeaponDefs.using_ammo(ammo_id):
		n += magazine(w)
	return n


## Spends up to `n` rounds of `ammo_id`: the reserve first, then the magazines
## (the weapon in hand last). Returns how many were spent.
func _consume_rounds(ammo_id: String, n: int) -> int:
	var k := mini(n, inventory.count(ammo_id))
	if k > 0:
		inventory.remove(ammo_id, k)
	var left := n - k
	var order := WeaponDefs.using_ammo(ammo_id)
	order.sort_custom(func(a, b): return a != active_weapon() and b == active_weapon())
	for w in order:
		if left <= 0:
			break
		var take := mini(left, magazine(w))
		if take > 0:
			_set_loaded(w, magazine(w) - take)
			left -= take
			k += take
	return k


# --- inventory use and costs -------------------------------------------------------

func can_pay(cost: Dictionary) -> bool:
	return cheats.get("unlimited", false) or inventory.has_all(cost)


## Pays a cost atomically. The unlimited cheat pays nothing (and creates nothing).
func pay(cost: Dictionary) -> bool:
	if cheats.get("unlimited", false):
		return true
	return inventory.remove_all(cost)


## Experiment 002 API, kept for the old firing path: spends `n` 9 mm rounds,
## from the handgun's magazine first, then the reserve (all or nothing). The
## unlimited cheat spends nothing. The weapon runtime uses spend_round instead.
func use_ammo(n := 1) -> bool:
	if n < 0:
		return false
	if cheats.get("unlimited", false):
		return true
	var loaded := magazine("handgun")
	if loaded + inventory.count("ammo") < n:
		return false
	var from_mag := mini(loaded, n)
	if from_mag > 0:
		_set_loaded("handgun", loaded - from_mag)
	if n > from_mag:
		inventory.remove("ammo", n - from_mag)
	elif from_mag > 0:
		changed.emit()
	return true


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
	if _needs_hurt() > 0.0 and health <= T.HURT_LEVEL:
		return "You're too weak to sleep like this. Eat and drink first."
	if energy >= T.NOT_TIRED_ENERGY and not is_night():
		return "You're not tired."
	return ""


## How long a requested sleep can last: it ends exactly at the next invasion or
## straggler, and early when the body is in danger: when hunger or hydration
## runs out, or, with one already out, when health falls to the "Badly hurt"
## level (so nobody starves or dies of thirst in their sleep).
## {"minutes", "interrupted", "reason": ""|"invasion"|"straggler"|"needs",
## "text"}. Requests are clamped to 0..MAX_SLEEP_MINUTES.
func plan_sleep(requested_minutes: float) -> Dictionary:
	var want := clampf(requested_minutes, 0.0, T.MAX_SLEEP_MINUTES) if is_finite(requested_minutes) else 0.0
	if _invasion_pending():
		return {"minutes": 0.0, "interrupted": true, "reason": "invasion", "text": "Not with them out there."}
	var stop := total_minutes + want
	var reason := ""
	var text := ""
	var due: float = run.get("next_invasion_at", INF)
	if due > total_minutes and due <= stop:
		stop = due
		reason = "invasion"
		text = "You wake to noises in the fog. They're here."
	for d in [day() - 1, day()]:
		var s := roll_straggler(d)
		if s > total_minutes + SNAP_MIN and s < stop:
			stop = s
			reason = "straggler"
			text = "Something is moving outside."
	var wake := _needs_wake()
	if wake["at"] < stop:
		stop = wake["at"]
		reason = "needs"
		text = wake["text"]
	if reason == "":
		return {"minutes": want, "interrupted": false, "reason": "", "text": ""}
	# a straggler stop lands a hair past its minute so `total_minutes >= minute` holds
	var minutes := maxf(stop - total_minutes, 0.0) + (1e-6 if reason == "straggler" else 0.0)
	return {"minutes": minutes, "interrupted": true, "reason": reason, "text": text}


## Health lost per hour from empty needs right now (0 when fed and watered,
## or with the invulnerable cheat).
func _needs_hurt() -> float:
	if cheats.get("invulnerable", false):
		return 0.0
	return (T.STARVING_DAMAGE if hunger <= 0.0 else 0.0) + (T.DEHYDRATED_DAMAGE if hydration <= 0.0 else 0.0)


## When a sleep starting now must end for the body's sake: {"at", "text"}
## (at = INF if never within reach). Asleep, hunger and hydration fall at
## SLEEP_DECAY_SCALE of the awake rates; the damage rate is constant until the
## next need runs out, which is itself a wake-up.
func _needs_wake() -> Dictionary:
	var out := {"at": INF, "text": ""}
	if cheats.get("invulnerable", false):
		return out
	for need in [["hydration", T.HYDRATION_PER_HOUR, "You wake up parched. You need water."],
			["hunger", T.HUNGER_PER_HOUR, "Hunger wakes you. You need to eat."]]:
		var v: float = get(need[0])
		if v > 0.0:
			var at: float = total_minutes + v / (float(need[1]) * T.SLEEP_DECAY_SCALE) * 60.0
			if at < out["at"]:
				out = {"at": at, "text": need[2]}
	var hurt := _needs_hurt()
	if hurt > 0.0:
		var at := total_minutes + maxf(health - T.HURT_LEVEL, 0.0) / hurt * 60.0
		if at < out["at"]:
			out = {"at": at, "text": "You wake up weak. You need %s." % ("water" if hydration <= 0.0 else "food")}
	return out


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
	var first := first_invasion_day()
	return d >= first and (d - first) % invasion_interval_days() == 0


# --- invasions ---------------------------------------------------------------------

## Invasion slots are at 22:00 on the difficulty's first invasion day and then
## every `invasion_interval_days` (Normal: Day 3, 6, 9...; Easy: 4, 8, 12...;
## Hard: 2, 4, 6...). Returns the first slot after `t`.
static func _invasion_slot_after(t: float, level := Difficulty.DEFAULT) -> float:
	var first := (int(Difficulty.get_value(level, "first_invasion_day")) - 1) * DAY_MIN + T.INVASION_HOUR * 60.0
	var step := maxi(int(Difficulty.get_value(level, "invasion_interval_days")), 1) * DAY_MIN
	if t < first:
		return first
	return first + (floorf((t - first) / step) + 1.0) * step


func first_invasion_day() -> int:
	return int(Difficulty.get_value(difficulty, "first_invasion_day"))


func invasion_interval_days() -> int:
	return maxi(int(Difficulty.get_value(difficulty, "invasion_interval_days")), 1)


## A value from this run's Difficulty row (e.g. "loot", "scavenge_danger").
func difficulty_value(key: String) -> Variant:
	return Difficulty.get_value(difficulty, key)


## Changes the difficulty mid-run (dev menu). An invasion that is not yet due
## moves onto the new grid: the first slot from now on.
func set_difficulty(level: String) -> void:
	var lv := Difficulty.valid(level)
	if lv == difficulty:
		return
	difficulty = lv
	if not _invasion_pending():
		run["next_invasion_at"] = _invasion_slot_after(total_minutes, difficulty)
	_log("Difficulty: %s" % Difficulty.name_of(difficulty))
	changed.emit()


## Announced (due) or forced, or running.
## Running, announced, forced, or overdue (its time has passed but no advance
## has reported it yet, e.g. right after loading a save): no sleeping through it.
func _invasion_pending() -> bool:
	return run.get("invasion_active", false) or run.get("invasion_announced", false) or run.get("invasion_forced", false) \
		or float(run.get("next_invasion_at", INF)) <= total_minutes


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


## Experiment 002 wave size (the old director), scaled by the difficulty's
## enemy_count (Normal x1). The threat-budget director (AI) reads Difficulty.
func invasion_size() -> int:
	var base := mini(T.INVASION_BASE_SIZE + T.INVASION_SIZE_STEP * (invasion_index() - 1), T.INVASION_MAX_SIZE)
	return maxi(roundi(base * float(difficulty_value("enemy_count"))), 1)


## Psycho HP in this invasion, scaled by the difficulty's enemy_hp (Normal x1).
func invasion_enemy_hp() -> int:
	return maxi(roundi((T.INVASION_BASE_HP + (invasion_index() - 1) / 2) * float(difficulty_value("enemy_hp"))), 1)


## Multiply an archetype's base HP by this (AI's EnemyDefs).
func enemy_hp_scale() -> float:
	return float(difficulty_value("enemy_hp"))


func invasion_speed_scale() -> float:
	return 1.0 + T.INVASION_SPEED_STEP * (invasion_index() - 1)


## One psycho hit on the player: 12, +10 % per invasion, x the difficulty's
## enemy_damage (Easy 0.7, Normal 1, Hard 1.3). The vest applies later, in
## `damage`. Other archetypes multiply this by their own factor.
func enemy_damage() -> float:
	return T.ENEMY_DAMAGE * (1.0 + T.INVASION_DAMAGE_STEP * (invasion_index() - 1)) * float(difficulty_value("enemy_damage"))


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
	run["next_invasion_at"] = _invasion_slot_after(maxf(total_minutes, float(run.get("next_invasion_at", total_minutes))), difficulty)
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
## {"applied": bool, "events", "added", "left_behind", "consumed", "lost": {id: n},
##  "damage": float, "damage_taken": float}.
## Time passes first; then consumed and lost items are removed (clamped to what
## is owned; consumed rounds come from the reserve first, then the magazines),
## then gains are added up to the caps (the rest is `left_behind`), then
## damage (`damage` as reported by the trip, `damage_taken` the health actually
## lost after the vest). Unknown items and non-numeric or negative amounts are
## ignored.
func apply_expedition_report(result: Dictionary) -> Dictionary:
	var out := {"applied": false, "events": [], "added": {}, "left_behind": {}, "consumed": {}, "lost": {}, "damage": 0.0, "damage_taken": 0.0}
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
			# Unlimited resources: rounds spent on the trip cost nothing (lost tools still go).
			if key == "consumed" and cheats.get("unlimited", false):
				continue
			if key == "consumed" and Items.category(id) == "ammo":
				var spent := _consume_rounds(str(id), maxi(Inventory.to_count(items[id]), 0))
				if spent > 0:
					out[key][str(id)] = int(out[key].get(str(id), 0)) + spent
				continue
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
		var before := health
		damage(out["damage"], "expedition")
		out["damage_taken"] = before - health
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
		"dead": dead, "difficulty": difficulty,
	}


func to_dict() -> Dictionary:
	return {
		"total_minutes": total_minutes, "health": health, "hunger": hunger,
		"hydration": hydration, "energy": energy, "inventory": inventory.to_dict(),
		"cheats": cheats.duplicate(), "run": run.duplicate(true), "dead": dead, "death_cause": death_cause,
		"difficulty": difficulty, "equipment": equipment.duplicate(), "weapons": weapons.duplicate(true),
		"active_weapon": active_weapon_slot, "region": region.to_dict(),
		"hotbar": hotbar.duplicate(true), "car_repaired": car_repaired,
		"home": home.duplicate(true),
		"mood": mood, "mood_state": mood_state.duplicate(true),     # Exp 005 (C)
	}


## Restores a state from untrusted data. Returns null (no crash) when the clock,
## a stat, the inventory or the run record is missing or of the wrong type, or a
## number is NaN/infinite. Out-of-range values are clamped, unknown items
## dropped, and the run record is sanitised field by field. Equipment keeps only
## owned gear in a slot it fits (each item once); magazines only owned weapons,
## clamped to their capacity. An Experiment 002 dictionary (no "equipment" and
## no "weapons") gets the handgun equipped as primary with its magazine filled
## from the inventory's 9 mm rounds, up to 12; Normal difficulty.
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
	s._quiet = true
	s.total_minutes = clampf(nums["total_minutes"], T.START_MINUTE, MAX_TOTAL_MINUTES)
	for k in ["health", "hunger", "hydration", "energy"]:
		s.set(k, nums[k])
	s.inventory.from_dict(d["inventory"])
	var c = d.get("cheats", {})
	if typeof(c) != TYPE_DICTIONARY:
		c = {}
	s.cheats = {"invulnerable": _flag(c.get("invulnerable")), "unlimited": _flag(c.get("unlimited"))}
	# Experiment 003 fields; an Experiment 002 save has none of them (defaults).
	var lv = d.get("difficulty", Difficulty.DEFAULT)
	s.difficulty = Difficulty.valid(lv if typeof(lv) == TYPE_STRING else Difficulty.DEFAULT)
	s.run = _clean_run(d["run"], s.total_minutes, s.difficulty)
	s.dead = _flag(d.get("dead")) or (s.health <= 0.0 and not s.cheats["invulnerable"])
	s.death_cause = str(d.get("death_cause", "")).left(60) if s.dead else ""
	if not d.has("equipment") and not d.has("weapons"):
		s._migrate_from_v1()
	else:
		s.equipment = _clean_equipment(d.get("equipment"), s.inventory)
		s.weapons = _clean_weapons(d.get("weapons"), s.inventory)
	var aw = d.get("active_weapon", "primary")
	s.active_weapon_slot = aw if typeof(aw) == TYPE_STRING and aw in Equipment.WEAPON_SLOTS else "primary"
	s._quiet = false
	s._mark_gear_seen()        # what was owned when saved is not "newly acquired"
	s._sync_equipment(false)   # magazines for owned weapons
	s._fix_active_slot()
	s.region = RegionState.from_dict(d.get("region", {}))
	s.hotbar = Hotbar.clean(d.get("hotbar"))          # Experiment 004 (E), optional
	s.car_repaired = _flag(d.get("car_repaired"))
	var h = d.get("home", {})            # Experiment 004; older saves have none
	s.home = (h as Dictionary).duplicate(true) if typeof(h) == TYPE_DICTIONARY else {}
	s.mood = Mood.clean_value(d.get("mood"))           # Exp 005 (C); older saves: Mood.START
	s.mood_state = Mood.clean(d.get("mood_state"))
	return s


## Experiment 002 run: the handgun didn't exist as an item; the rounds were all
## in the inventory. Equip it and fill its magazine from them (up to 12).
func _migrate_from_v1() -> void:
	inventory.add("handgun", 1)
	equipment = {"primary": "handgun"}
	var n := mini(WeaponDefs.capacity("handgun"), inventory.count("ammo"))
	inventory.remove("ammo", n)
	weapons = {"handgun": {"loaded": n}}


static func _clean_equipment(v, inv: Inventory) -> Dictionary:
	var out := {}
	if typeof(v) != TYPE_DICTIONARY:
		return out
	for slot in Equipment.SLOTS:
		var id = v.get(slot)
		if typeof(id) == TYPE_STRING and Equipment.fits(id, slot) and inv.count(id) > 0 and not id in out.values():
			out[slot] = id
	return out


static func _clean_weapons(v, inv: Inventory) -> Dictionary:
	var out := {}
	for id in WeaponDefs.ids():
		if inv.count(id) <= 0:
			continue
		var w = v.get(id) if typeof(v) == TYPE_DICTIONARY else null
		var n := Inventory.to_count(w.get("loaded", 0)) if typeof(w) == TYPE_DICTIONARY else 0
		out[id] = {"loaded": clampi(n, 0, WeaponDefs.capacity(id))}
	return out


static func _clean_run(r: Dictionary, now: float, level := Difficulty.DEFAULT) -> Dictionary:
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
		due = _invasion_slot_after(now - STALE_INVASION_MIN, level)
	elif now - due > STALE_INVASION_MIN and not out["invasion_forced"]:
		due = _invasion_slot_after(now, level)
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
