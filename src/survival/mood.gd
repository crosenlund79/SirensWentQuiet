class_name Mood
extends RefCounted
## Experiment 005 (C): Elias "Eli" Walker's mood, 0..100, as the tension
## between hardship and the comfort of home. Pure rules (no nodes); the game
## helper src/home/game_comfort.gd calls step() every UPDATE_MINUTES of game
## time and remember() on events. Every number is here.
##
## The mood drifts toward a target (exponentially, TAU_* game hours), so it is
## never a meter to babysit:
##   target = BASE
##          + home: (house comfort - HOME_PIVOT) x HOME_SCALE, capped
##          + warm by the lit fireplace (in its room or next door)
##          + lamplight / - sitting in the dark (indoors at night)
##          + well fed and watered / - hungry, thirsty, tired, hurt
##          - cold (outdoors or in an exposed room at night)
##          - rooms open to the outside
##          - long days in a bleak shelter (hours with a house comfort < BLEAK_COMFORT)
##          + memories: recent events that fade (attacks, a blast, getting
##            hurt, surviving the night, coming home safe, a good or bad sleep).
## A comfortable home makes bad memories fade faster and the mood rise faster.
##
## Effects (modest; mood never stands in for health or energy):
##   sleep restores energy x rest_scale(mood band, comfort of the room slept in):
##   a good mood and a comfortable bedroom rest better, a low mood and a
##   miserable room worse (GameState.rest_scale).
##
## Saved: GameState.mood and GameState.mood_state ({"mem": [{"id", "v"}], "bleak": hours}).

const START := 58.0                  ## Content, leaning positive
const BASE := 50.0
const UPDATE_MINUTES := 5.0
const BANDS := [20.0, 40.0, 62.0, 80.0]
const NAMES := ["Miserable", "Low", "Content", "Good", "Cheerful"]
## The F10 presets.
const PRESETS := {"low": 25.0, "normal": START, "high": 85.0}

# --- target terms -------------------------------------------------------------------------
const HOME_PIVOT := 14.0             ## house comfort that neither helps nor hurts
const HOME_SCALE := 0.6
const HOME_CAP := 14.0
const FIRE_NEAR := 5.0
const WELL_FED := 4.0                ## hunger and hydration at or above WELL_FED_AT
const WELL_FED_AT := 60.0
const HUNGRY := -7.0                 ## below NEED_LOW
const STARVING := -14.0              ## at 0
const THIRSTY := -7.0
const PARCHED := -14.0
const NEED_LOW := 25.0
const TIRED := -3.0                  ## energy below 40
const EXHAUSTED := -8.0              ## energy below 15
const HURT := -3.0                   ## health below 70
const BADLY_HURT := -8.0             ## health below 35
const COLD := -6.0
const LAMPLIGHT := 2.0               ## indoors at night in a lit room
const IN_THE_DARK := -3.0            ## indoors at night in a dark room
const OPEN_ROOM := -3.0              ## per exposed room in the house
const OPEN_ROOM_CAP := -6.0
const BLEAK_COMFORT := 6.0           ## house comfort below this counts as a bleak shelter
const BLEAK_PER_HOUR := 0.3          ## mood per bleak hour
const BLEAK_CAP := -8.0
const BLEAK_RECOVER := 2.0           ## bleak hours fade this many times faster than they gather

# --- memories -----------------------------------------------------------------------------
## id -> {"text", "v" (mood points when fresh), "half" (game hours to fade by half)}.
const MEMORIES := {
	"attack": {"text": "Under attack", "v": -10.0, "half": 8.0},
	"blast": {"text": "A blast shook the house", "v": -7.0, "half": 6.0},
	"hurt": {"text": "Got hurt", "v": -4.0, "half": 4.0},
	"survived": {"text": "Survived the night", "v": 5.0, "half": 8.0},
	"home_safe": {"text": "Back home safe", "v": 7.0, "half": 6.0},
	"home_hurt": {"text": "Made it back, barely", "v": 2.0, "half": 4.0},
	"slept_well": {"text": "Slept well", "v": 6.0, "half": 6.0},
	"slept_badly": {"text": "Slept badly", "v": -4.0, "half": 5.0},
}
const MEMORY_GONE := 0.4
const MEMORY_MAX := 8
const COMFORT_RECOVERY := 0.45       ## bad memories' half-life x (1 - this x home factor)
const HURT_DROP := 8.0               ## health lost between two updates that counts as "got hurt"

# --- drift --------------------------------------------------------------------------------
const TAU_DOWN := 4.0                ## game hours
const TAU_UP := 3.0
const COMFORT_RISE := 0.35           ## rising tau x (1 - this x home factor)

# --- effects ------------------------------------------------------------------------------
const REST_BY_MOOD := [0.85, 0.93, 1.0, 1.06, 1.12]
const REST_BY_ROOM := [0.85, 0.93, 1.0, 1.1, 1.2]     ## by ComfortCatalog level of the room slept in
const REST_MIN := 0.75
const REST_MAX := 1.35


static func band(mood: float) -> int:
	var i := 0
	while i < BANDS.size() and mood >= float(BANDS[i]):
		i += 1
	return i


static func name_of(mood: float) -> String:
	return NAMES[band(mood)]


## 0..1: how much the house helps (0 at a bleak shelter, 1 at a cosy home).
static func home_factor(house_comfort: float) -> float:
	return clampf((house_comfort - BLEAK_COMFORT) / 20.0, 0.0, 1.0)


## Sleep energy multiplier for the mood and the comfort level (0..4) of the room slept in.
static func rest_scale(mood: float, room_level: int) -> float:
	return clampf(float(REST_BY_MOOD[band(mood)]) * float(REST_BY_ROOM[clampi(room_level, 0, 4)]), REST_MIN, REST_MAX)


## The target and its causes ([[text, delta]], largest first). `inputs`:
## {"house": float, "fire_near": bool, "cold": bool, "exposed_rooms": int,
## "night_light": "lit" | "dark" | "", "media": "" | "tv_stand" | "radio" (Exp 006 (B))},
## the stats from `state`, the memories and bleak hours from state.mood_state.
static func target(state: Object, inputs: Dictionary) -> Dictionary:
	var causes := []
	var ms: Dictionary = state.mood_state
	var house := float(inputs.get("house", 0.0))
	var home := clampf((house - HOME_PIVOT) * HOME_SCALE, -HOME_CAP, HOME_CAP)
	if absf(home) >= 0.5:
		causes.append(["A comfortable home" if home > 0.0 else "An uncomfortable shelter", home])
	if bool(inputs.get("fire_near", false)):
		causes.append(["Warm by the fire", FIRE_NEAR])
	var hunger := float(state.hunger)
	var water := float(state.hydration)
	if hunger >= WELL_FED_AT and water >= WELL_FED_AT:
		causes.append(["Fed and watered", WELL_FED])
	if hunger <= 0.0:
		causes.append(["Starving", STARVING])
	elif hunger < NEED_LOW:
		causes.append(["Hungry", HUNGRY])
	if water <= 0.0:
		causes.append(["Parched", PARCHED])
	elif water < NEED_LOW:
		causes.append(["Thirsty", THIRSTY])
	var energy := float(state.energy)
	if energy < 15.0:
		causes.append(["Exhausted", EXHAUSTED])
	elif energy < 40.0:
		causes.append(["Tired", TIRED])
	var health := float(state.health)
	if health < 35.0:
		causes.append(["Badly hurt", BADLY_HURT])
	elif health < 70.0:
		causes.append(["Hurt", HURT])
	if bool(inputs.get("cold", false)):
		causes.append(["Cold", COLD])
	var media := HouseMedia.cause(str(inputs.get("media", "")))      # Exp 006 (B): a TV or radio in Eli's room
	if not media.is_empty():
		causes.append(media)
	match str(inputs.get("night_light", "")):
		"lit":
			causes.append(["A warm light against the night", LAMPLIGHT])
		"dark":
			causes.append(["Sitting in the dark", IN_THE_DARK])
	var open := int(inputs.get("exposed_rooms", 0))
	if open > 0:
		causes.append(["Rooms open to the outside" if open > 1 else "A room open to the outside", maxf(OPEN_ROOM * open, OPEN_ROOM_CAP)])
	var bleak := maxf(-float(ms.get("bleak", 0.0)) * BLEAK_PER_HOUR, BLEAK_CAP)
	if bleak <= -0.5:
		causes.append(["Long days in a bleak shelter", bleak])
	for m in ms.get("mem", []):
		var def: Dictionary = MEMORIES.get(str(m.get("id", "")), {})
		if not def.is_empty() and absf(float(m.get("v", 0.0))) >= 0.5:
			causes.append([def["text"], float(m["v"])])
	var t := BASE
	for c in causes:
		t += float(c[1])
	causes.sort_custom(func(a, b): return absf(a[1]) > absf(b[1]))
	return {"target": clampf(t, 0.0, 100.0), "causes": causes}


## Advances the mood by `minutes` of game time: memories fade, bleak hours
## gather or fade, and the mood drifts toward the target. Returns target().
static func step(state: Object, inputs: Dictionary, minutes: float) -> Dictionary:
	var hours := maxf(minutes, 0.0) / 60.0
	var hf := home_factor(float(inputs.get("house", 0.0)))
	var ms: Dictionary = state.mood_state
	if hours > 0.0:
		var keep := []
		for m in ms.get("mem", []):
			var def: Dictionary = MEMORIES.get(str(m.get("id", "")), {})
			if def.is_empty():
				continue
			var v := float(m.get("v", 0.0))
			var half := float(def["half"]) * ((1.0 - COMFORT_RECOVERY * hf) if v < 0.0 else 1.0)
			v *= pow(0.5, hours / maxf(half, 0.1))
			if absf(v) >= MEMORY_GONE:
				keep.append({"id": m["id"], "v": v})
		ms["mem"] = keep
		var bleak := float(ms.get("bleak", 0.0))
		if float(inputs.get("house", 0.0)) < BLEAK_COMFORT:
			bleak += hours
		else:
			bleak -= hours * BLEAK_RECOVER
		ms["bleak"] = clampf(bleak, 0.0, absf(BLEAK_CAP) / BLEAK_PER_HOUR)
	var t := target(state, inputs)
	if hours > 0.0:
		var goal := float(t["target"])
		var mood := float(state.mood)
		var tau := TAU_UP * (1.0 - COMFORT_RISE * hf) if goal > mood else TAU_DOWN
		state.mood = clampf(mood + (goal - mood) * (1.0 - exp(-hours / tau)), 0.0, 100.0)
	return t


## Adds (or refreshes) a memory: the same event twice doesn't stack, the
## stronger of the two stays.
static func remember(state: Object, id: String, scale := 1.0) -> void:
	var def: Dictionary = MEMORIES.get(id, {})
	if def.is_empty():
		return
	var ms: Dictionary = state.mood_state
	var mem: Array = ms.get("mem", [])
	var v := float(def["v"]) * scale
	for m in mem:
		if m.get("id", "") == id:
			if absf(v) > absf(float(m.get("v", 0.0))):
				m["v"] = v
			ms["mem"] = mem
			return
	mem.append({"id": id, "v": v})
	if mem.size() > MEMORY_MAX:
		mem.sort_custom(func(a, b): return absf(a["v"]) > absf(b["v"]))
		mem.resize(MEMORY_MAX)
	ms["mem"] = mem


## A mood value from untrusted data (older saves: START).
static func clean_value(v) -> float:
	if typeof(v) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(v)):
		return clampf(float(v), 0.0, 100.0)
	return START


## mood_state from untrusted data: known memories only, finite values.
static func clean(d) -> Dictionary:
	var out := {"mem": [], "bleak": 0.0}
	if typeof(d) != TYPE_DICTIONARY:
		return out
	var b = d.get("bleak", 0.0)
	if typeof(b) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(b)):
		out["bleak"] = clampf(float(b), 0.0, absf(BLEAK_CAP) / BLEAK_PER_HOUR)
	var mem = d.get("mem", [])
	if typeof(mem) == TYPE_ARRAY:
		for m in mem:
			if typeof(m) != TYPE_DICTIONARY or not MEMORIES.has(str(m.get("id", ""))):
				continue
			var v = m.get("v", 0.0)
			if typeof(v) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(v)):
				var cap := absf(float(MEMORIES[str(m["id"])]["v"])) * 2.0
				out["mem"].append({"id": str(m["id"]), "v": clampf(float(v), -cap, cap)})
			if out["mem"].size() >= MEMORY_MAX:
				break
	return out


## One line on what the mood does now (the Home panel).
static func effects_text(mood: float) -> String:
	var k := float(REST_BY_MOOD[band(mood)])
	if k > 1.0:
		return "Good spirits: sleep restores %d %% more energy." % roundi((k - 1.0) * 100.0)
	if k < 1.0:
		return "Low spirits: sleep restores %d %% less energy." % roundi((1.0 - k) * 100.0)
	return "Sleep restores energy normally."
