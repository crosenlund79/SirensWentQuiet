class_name SurvivalTuning
extends RefCounted
## Numbers for the survival loop (SPEC §6). Owner: S. Per game hour unless noted.

# --- time ---------------------------------------------------------------------
const MINUTES_PER_SECOND := 1.0        ## game minutes per real second (dev menu can scale)
const START_MINUTE := 7.0 * 60.0       ## Day 1, 07:00
const DAWN_MINUTE := 6.0 * 60.0
const DUSK_MINUTE := 20.0 * 60.0
const NIGHT_RAMP_DOWN := Vector2(5.0 * 60.0, 7.0 * 60.0)    ## night -> day
const NIGHT_RAMP_UP := Vector2(19.5 * 60.0, 21.0 * 60.0)    ## day -> night
const EXPEDITION_DEPART_FROM := 5.0 * 60.0
const EXPEDITION_DEPART_UNTIL := 18.0 * 60.0
const EXPEDITION_RETURN_BY := 20.0 * 60.0
const MAX_ADVANCE_MINUTES := 30.0 * 1440.0   ## one advance() call never skips more than 30 days
const MAX_SLEEP_MINUTES := 24.0 * 60.0
const MAX_EXPEDITION_MINUTES := 24.0 * 60.0  ## longer results are clamped

# --- stats --------------------------------------------------------------------
const HUNGER_PER_HOUR := 1.25
const HYDRATION_PER_HOUR := 1.9
const ENERGY_PER_HOUR := 4.5
const SLEEP_DECAY_SCALE := 0.6         ## hunger/hydration decay while asleep
const SLEEP_ENERGY_PER_HOUR := 12.5
const STARVING_DAMAGE := 4.0           ## health/h at hunger 0
const DEHYDRATED_DAMAGE := 6.0         ## health/h at hydration 0
const WARN_LEVEL := 15.0
const HURT_LEVEL := 30.0               ## "Badly hurt" warning at or below this health
const REGEN_AWAKE := 1.5
const REGEN_ASLEEP := 3.0
const REGEN_THRESHOLD := 50.0
const EXHAUSTED_SPEED := 0.75          ## energy <= WARN_LEVEL
const SPENT_SPEED := 0.6               ## energy <= 0
const NOT_TIRED_ENERGY := 95.0         ## by day, no sleep at or above this energy

const START_STATS := {"health": 100.0, "hunger": 75.0, "hydration": 70.0, "energy": 85.0}
## Exp 008 (E): 18 nails (was 12): three window boards' worth before the first trip (docs/experiment-008/PACING.md).
const START_ITEMS := {"handgun": 1, "canned_food": 3, "snacks": 2, "water": 4, "wood": 6, "nails": 18, "bandage": 1, "hammer": 1}

# --- invasions ----------------------------------------------------------------
const FIRST_INVASION_DAY := 3
const INVASION_HOUR := 22.0
const INVASION_INTERVAL_DAYS := 3
const INVASION_BASE_SIZE := 3
const INVASION_SIZE_STEP := 2
const INVASION_MAX_SIZE := 11
const INVASION_BASE_HP := 3            ## psycho HP in invasion 1; +1 every second invasion
const INVASION_SPEED_STEP := 0.05      ## psycho speed x(1 + step (k - 1))
const INVASION_DAMAGE_STEP := 0.1      ## enemy hit x(1 + step (k - 1))
const INVASION_SPAWN_GAP := Vector2(25.0, 40.0)   ## real seconds between invaders
const INVASION_WARNING_HOUR := 12.0
const STRAGGLER_CHANCE := 0.35
const STRAGGLER_FROM_DAY := 2
const STRAGGLER_WINDOW := Vector2(23.0 * 60.0, 27.0 * 60.0)   ## 23:00 .. 03:00, minutes from the start of the night's day
const ENEMY_DAMAGE := 12.0

# --- house --------------------------------------------------------------------
const RAIN_WATER_PER_COLLECTOR := 1    ## water per rain collector every dawn
