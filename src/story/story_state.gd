class_name StoryState
extends RefCounted
## Exp 012 (S): the saved progression of the story (docs/experiment-012/SPEC.md,
## "Story state"). Static, no Autoload. It lives in `GameState.story`, saved as
## the top-level key "story"; a save without it (older versions) starts fresh.
##
## Chapter One, "Someone Is Watching": four encounters (1 The Visitor, 2 The
## Observer, 3 The Warning, 4 The Last Courtesy), then the first organised
## siege becomes eligible after a short delay.
##
##   StoryState.ch1(state)       # {"done", "next", "next_at", "rope", "siege_at", "sieges", ...}
##   StoryState.siege_eligible(state)   # agent G's siege director asks this
##   StoryState.note_siege(state)       # ... and records a siege here
##
## The intervals are randomised from the run's seed (stable per run): the
## first encounter falls on a night of days 2-4, the later ones after
## progressively longer gaps (GAPS, in days after the previous one). An
## encounter only becomes *eligible* at next_at; it happens when its
## conditions hold (StoryDirector: asleep in bed at night, or awake at home
## at dusk), so the real gaps are often longer. Normal survival goes on in
## between. Previews (F10) never call the writers here.

const KEY := "ch1"
const FINISHED := 5                         ## "next" once all four are done
const NAMES := {1: "The Visitor", 2: "The Observer", 3: "The Warning", 4: "The Last Courtesy"}
const TITLE := "Someone Is Watching"
const FIRST_DAY := Vector2i(2, 3)           ## E1 eligible from 20:00 of one of these days (a night of days 2-4)
const GAPS := {2: Vector2i(3, 6), 3: Vector2i(5, 9), 4: Vector2i(7, 12)}   ## days after the previous encounter
const EVENING := {1: 20.0, 2: 16.5, 3: 20.0, 4: 20.0}   ## hour of the eligible day it opens
const SIEGE_DELAY := Vector2(1.0, 3.0)      ## days after Encounter 4 until the first siege
const SIEGE_REPEAT := Vector2(4.0, 7.0)     ## days until the next organised siege after one happened
const ROPE_VALUES := ["", "kept", "burned"]
const DAY := 1440.0


## The chapter's record, created on first use (a fresh one for old saves).
## The dictionary is live: writers change it in place.
static func ch1(state: GameState) -> Dictionary:
	if typeof(state.story) != TYPE_DICTIONARY:
		state.story = {}
	var c: Variant = state.story.get(KEY)
	if typeof(c) != TYPE_DICTIONARY:
		c = fresh(int(state.run.get("seed", 0)))
		state.story[KEY] = c
	return c


## A new chapter for a run with this seed.
static func fresh(seed: int) -> Dictionary:
	var day := _rng(seed, 1).randi_range(FIRST_DAY.x, FIRST_DAY.y)
	return {"done": [], "next": 1, "next_at": (day - 1) * DAY + EVENING[1] * 60.0, "rope": "",
		"siege_at": -1.0, "sieges": 0, "ropes": 0, "pile": "", "at": {}}


## True once the man behind the door has been met (Encounter 1 is done).
static func architect_introduced(state: GameState) -> bool:
	return 1 in ch1(state)["done"]


static func is_done(state: GameState, n: int) -> bool:
	return n in ch1(state)["done"]


## The encounter that comes next (1..4), or FINISHED.
static func next_encounter(state: GameState) -> int:
	return int(ch1(state)["next"])


## True when encounter `n` is the next one and its time has come (its
## conditions are the director's).
static func eligible(state: GameState, n: int) -> bool:
	var c := ch1(state)
	return int(c["next"]) == n and state.total_minutes >= float(c["next_at"])


## Agent G: the first organised siege may start (Encounter 4 is done and its
## delay has passed). Repeats after note_siege's delay.
static func siege_eligible(state: GameState) -> bool:
	var c := ch1(state)
	return 4 in c["done"] and float(c["siege_at"]) >= 0.0 and state.total_minutes >= float(c["siege_at"])


## Agent G: a siege happened now; the next one waits SIEGE_REPEAT days.
static func note_siege(state: GameState) -> void:
	var c := ch1(state)
	c["sieges"] = int(c["sieges"]) + 1
	var r := _rng(int(state.run.get("seed", 0)), 100 + int(c["sieges"]))
	c["siege_at"] = state.total_minutes + r.randf_range(SIEGE_REPEAT.x, SIEGE_REPEAT.y) * DAY


## Records encounter `n` as done at `now` and schedules the next one. Earlier
## ones count as done too (a developer trigger can jump ahead).
static func complete(state: GameState, n: int, now := -1.0) -> void:
	var c := ch1(state)
	if now < 0.0:
		now = state.total_minutes
	for k in range(1, n + 1):
		if not k in c["done"]:
			(c["done"] as Array).append(k)
	(c["done"] as Array).sort()
	(c["at"] as Dictionary)[str(n)] = now
	c["next"] = maxi(int(c["next"]), n + 1)
	var seed := int(state.run.get("seed", 0))
	if n < 4:
		var nx := n + 1
		var gap: Vector2i = GAPS[nx]
		var days := _rng(seed, 10 + nx).randi_range(gap.x, gap.y)
		c["next_at"] = (floorf(now / DAY) + days) * DAY + float(EVENING[nx]) * 60.0
	else:
		c["next_at"] = MAX_TIME
		c["siege_at"] = now + _rng(seed, 99).randf_range(SIEGE_DELAY.x, SIEGE_DELAY.y) * DAY


## F10: makes the first organised siege eligible now (Encounter 4 counts as done).
static func make_siege_eligible_now(state: GameState) -> void:
	var c := ch1(state)
	if not 4 in c["done"]:
		complete(state, 4)
	c["siege_at"] = state.total_minutes


## F10 "Reset Chapter": only this chapter's record (a fresh one on next use).
static func reset(state: GameState) -> void:
	if typeof(state.story) != TYPE_DICTIONARY:
		state.story = {}
	state.story.erase(KEY)


## F10: the next encounter becomes eligible now.
static func make_eligible_now(state: GameState) -> void:
	ch1(state)["next_at"] = state.total_minutes


const MAX_TIME := 3650.0 * 1440.0           ## "never" (finite, JSON-safe)


## Restores the story record from untrusted save data (anything wrong -> fresh parts).
static func clean(v: Variant) -> Dictionary:
	var out := {}
	if typeof(v) != TYPE_DICTIONARY:
		return out
	var c: Variant = (v as Dictionary).get(KEY)
	if typeof(c) != TYPE_DICTIONARY:
		return out
	var d := c as Dictionary
	var done: Array = []
	if typeof(d.get("done")) == TYPE_ARRAY:
		for x in d["done"]:
			if typeof(x) in [TYPE_INT, TYPE_FLOAT] and int(x) >= 1 and int(x) <= 4 and not int(x) in done:
				done.append(int(x))
	done.sort()
	var next := int(d.get("next", 1)) if typeof(d.get("next")) in [TYPE_INT, TYPE_FLOAT] else 1
	var lowest := 1
	while lowest in done:
		lowest += 1
	next = clampi(maxi(next, lowest), 1, FINISHED)
	var rope := str(d.get("rope", ""))
	var at := {}
	if typeof(d.get("at")) == TYPE_DICTIONARY:
		for k in d["at"]:
			if str(k) in ["1", "2", "3", "4"]:
				at[str(k)] = _num(d["at"][k], 0.0)
	out[KEY] = {"done": done, "next": next, "next_at": clampf(_num(d.get("next_at"), 0.0), 0.0, MAX_TIME),
		"rope": rope if rope in ROPE_VALUES else "", "siege_at": clampf(_num(d.get("siege_at"), -1.0), -1.0, MAX_TIME),
		"sieges": maxi(int(_num(d.get("sieges"), 0.0)), 0), "ropes": clampi(int(_num(d.get("ropes"), 0.0)), 0, 4),
		"pile": str(d.get("pile", "")).left(32), "at": at}
	return out


## A short status for F10.
static func status_text(state: GameState) -> String:
	var c := ch1(state)
	var lines := ["%s — Chapter One" % TITLE]
	var done: Array = c["done"]
	lines.append("Done: %s" % (", ".join(done.map(func(n): return "%d %s" % [n, NAMES[n]])) if not done.is_empty() else "none"))
	var nx := int(c["next"])
	if nx < FINISHED:
		var t := float(c["next_at"])
		var wait := t - state.total_minutes
		lines.append("Next: %d %s, eligible %s (%s)" % [nx, NAMES[nx], _when(t), "now" if wait <= 0.0 else "in %.1f h" % (wait / 60.0)])
		lines.append("Needs: " + ("Eli awake at home at dusk or night" if nx == 2 else "Eli asleep in his bed at night"))
	else:
		lines.append("Chapter complete")
	if 4 in done:
		lines.append("Ropes: %s · siege %s · sieges %d" % [c["rope"] if c["rope"] != "" else ("undecided" if int(c["ropes"]) > 0 else "-"),
			("eligible" if siege_eligible(state) else "from " + _when(float(c["siege_at"]))) if float(c["siege_at"]) >= 0.0 else "-", int(c["sieges"])])
	return "\n".join(lines)


static func _when(t: float) -> String:
	if t >= MAX_TIME:
		return "never"
	var m := int(fposmod(t, DAY))
	return "Day %d %02d:%02d" % [int(floorf(t / DAY)) + 1, m / 60, m % 60]


static func _num(v: Variant, fallback: float) -> float:
	if typeof(v) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(v)):
		return float(v)
	return fallback


static func _rng(seed: int, salt: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = (seed & 0x7fffffff) * 7919 + salt * 104729 + 17
	return r
