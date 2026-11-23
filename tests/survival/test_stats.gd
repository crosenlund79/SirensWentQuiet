extends "res://tests/test_case.gd"
## GameState stats: decay math, sleep multipliers, thresholds, consequences,
## regeneration, speed, warnings, item use.

const T := preload("res://src/survival/survival_tuning.gd")


func _near(a: float, b: float, msg: String) -> void:
	check(absf(a - b) < 1e-6, "%s (expected %f, got %f)" % [msg, b, a])


func test_awake_decay() -> void:
	var s := GameState.new_run(1)
	s.advance(4 * 60.0)
	_near(s.hunger, 75.0 - 4 * T.HUNGER_PER_HOUR, "hunger")
	_near(s.hydration, 70.0 - 4 * T.HYDRATION_PER_HOUR, "hydration")
	_near(s.energy, 85.0 - 4 * T.ENERGY_PER_HOUR, "energy")
	_near(s.health, 100.0, "health stays full")


func test_asleep_decay_and_energy() -> void:
	var s := GameState.new_run(1)
	s.energy = 20.0
	s.advance(4 * 60.0, true)
	_near(s.hunger, 75.0 - 4 * T.HUNGER_PER_HOUR * T.SLEEP_DECAY_SCALE, "hunger x0.6 asleep")
	_near(s.hydration, 70.0 - 4 * T.HYDRATION_PER_HOUR * T.SLEEP_DECAY_SCALE, "hydration x0.6 asleep")
	_near(s.energy, 20.0 + 4 * T.SLEEP_ENERGY_PER_HOUR, "energy +12.5/h asleep")
	s.advance(10 * 60.0, true)
	_near(s.energy, 100.0, "energy capped at 100")


func test_regeneration_awake_asleep_and_threshold_split() -> void:
	var s := GameState.new_run(1)
	s.health = 50.0
	s.hunger = 90.0
	s.hydration = 90.0
	s.advance(120.0)
	_near(s.health, 53.0, "+1.5/h awake")
	s.advance(120.0, true)
	_near(s.health, 59.0, "+3/h asleep")
	# regeneration stops exactly when hunger reaches 50 (after 1 h here)
	s = GameState.new_run(1)
	s.health = 50.0
	s.hunger = 50.0 + T.HUNGER_PER_HOUR
	s.hydration = 100.0
	s.advance(180.0)
	_near(s.health, 50.0 + T.REGEN_AWAKE, "regen only for the hour above 50")
	_near(s.hunger, 50.0 - 2 * T.HUNGER_PER_HOUR, "hunger kept decaying")


func test_starvation_and_dehydration_damage() -> void:
	var s := GameState.new_run(1)
	s.hunger = T.HUNGER_PER_HOUR    # reaches 0 after exactly 1 h
	s.hydration = 100.0
	s.advance(180.0)
	_near(s.health, 100.0 - 2 * T.STARVING_DAMAGE, "-4/h for the 2 h at hunger 0")
	s = GameState.new_run(1)
	s.hunger = 100.0
	s.hydration = 0.0
	s.advance(60.0)
	_near(s.health, 100.0 - T.DEHYDRATED_DAMAGE, "-6/h at hydration 0")
	s = GameState.new_run(1)
	s.hunger = 0.0
	s.hydration = 0.0
	s.advance(60.0)
	_near(s.health, 100.0 - T.STARVING_DAMAGE - T.DEHYDRATED_DAMAGE, "both stack")


func test_death_and_died_signal_once() -> void:
	var s := GameState.new_run(1)
	var deaths := []
	s.died.connect(func(c): deaths.append(c))
	s.damage(60.0, "psycho")
	check(not s.dead, "alive at 40")
	s.damage(40.0, "psycho")
	check(s.dead, "dead at 0")
	s.damage(10.0, "psycho")
	s.damage(10.0, "other")
	check_eq(deaths, ["psycho"], "died once with the first cause")
	check_eq(s.death_cause, "psycho", "cause kept")
	s = GameState.new_run(1)
	s.hydration = 0.0
	s.hunger = 100.0
	s.health = 3.0
	s.died.connect(func(c): deaths.append(c))
	s.advance(600.0)
	check_eq(deaths.back(), "dehydration", "dehydration death")
	check_eq(deaths.size(), 2, "one more death")


func test_damage_and_heal_ignore_bad_amounts() -> void:
	var s := GameState.new_run(1)
	s.health = 50.0
	for v in [NAN, -5.0, 0.0, -INF]:
		s.damage(v, "x")
		s.heal(v)
	_near(s.health, 50.0, "unchanged")
	s.heal(INF)
	_near(s.health, 100.0, "heal clamps")
	s.damage(INF, "x")
	check(s.dead and s.health == 0.0, "infinite damage kills cleanly")


func test_stat_assignments_are_clamped() -> void:
	var s := GameState.new_run(1)
	s.health = 250.0
	s.hunger = -40.0
	s.energy = NAN
	check_eq(s.health, 100.0, "health clamped")
	check_eq(s.hunger, 0.0, "hunger clamped")
	check_eq(s.energy, 85.0, "NaN ignored")


func test_move_speed_scale() -> void:
	var s := GameState.new_run(1)
	s.energy = 50.0
	check_eq(s.move_speed_scale(), 1.0, "rested")
	s.energy = T.WARN_LEVEL
	check_eq(s.move_speed_scale(), T.EXHAUSTED_SPEED, "exhausted at 15")
	s.energy = 0.0
	check_eq(s.move_speed_scale(), T.SPENT_SPEED, "spent at 0")


func test_warnings() -> void:
	var s := GameState.new_run(1)
	check_eq(s.warnings(), [], "none at the start")
	s.hunger = 10.0
	s.hydration = 12.0
	s.energy = 5.0
	s.health = 25.0
	check_eq(s.warnings(), ["Badly hurt", "Thirsty", "Hungry", "Exhausted"], "low stats")
	s.hunger = 0.0
	s.hydration = 0.0
	check_eq(s.warnings(), ["Dehydrated", "Starving", "Badly hurt", "Exhausted"], "empty stats")


func test_use_item() -> void:
	var s := GameState.new_run(1)
	s.hunger = 40.0
	s.hydration = 40.0
	var text := s.use_item("canned_food")
	check_eq(text, "Canned food: food +30, water +4", "feedback")
	check_eq(s.inventory.count("canned_food"), 2, "one can used")
	check_eq(s.hunger, 70.0, "hunger +30")
	check_eq(s.hydration, 44.0, "hydration +4")
	check_eq(s.use_item("water"), "Bottled water: water +30", "drink")
	check_eq(s.use_item("ammo"), "", "ammo can't be used")
	check_eq(s.use_item("nonsense"), "", "unknown")
	check_eq(s.use_item(42), "", "wrong type")
	check_eq(s.use_item("medkit"), "", "none owned")
	check_eq(s.can_use("medkit"), "You have none left.", "reason")
	check_eq(s.can_use("bandage"), "You're not hurt.", "full health")
	check_eq(s.use_item("bandage"), "", "bandage not wasted")
	check_eq(s.inventory.count("bandage"), 1, "bandage kept")
	s.health = 50.0
	check_eq(s.use_item("bandage"), "Bandage: health +20", "bandage used")
	check_eq(s.health, 70.0, "healed")
	s.hunger = 100.0
	check_eq(s.can_use("snacks"), "You couldn't eat another bite.", "full")
	check_eq(Items.verb("water"), "Drink", "verb")
	check_eq(Items.verb("hammer"), "", "no verb for tools")


func test_days_survived_and_summary() -> void:
	var s := GameState.new_run(1)
	s.cheats["invulnerable"] = true
	check_eq(s.days_survived(), 0, "none yet")
	s.advance(1440.0 * 2 + 100.0)
	check_eq(s.days_survived(), 2, "two days")
	var sm := s.summary()
	check_eq(sm["day"], 3, "summary day")
	check_eq(sm["clock"], "08:40", "summary clock")
	check_eq(sm["days_survived"], 2, "summary days survived")
	check_eq(sm["health"], 100, "summary health")
