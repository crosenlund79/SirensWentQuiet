class_name SiegeStory
extends RefCounted
## Exp 012 (G): the siege's view of the story state (SPEC "Story state (S)").
## Agent S owns `StoryState` (src/story/story_state.gd). This file only asks
## it, loaded by path so the siege module compiles and runs without it:
##   eligible(state)    StoryState.siege_eligible(state)
##   introduced(state)  StoryState.architect_introduced(state) (the watcher may
##                      observe a siege)
##   note(state)        StoryState.note_siege(state)
## Without StoryState (or a story in the state) it reads the documented keys
## defensively: state.story["ch1"] = {"done": [1..4], "siege_at": minutes,
## "sieges": n}; nothing there means no siege and no watcher. No shim class:
## the lead can drop this fallback once S's file is in.

const STORY_STATE := "res://src/story/story_state.gd"

static var _ss: Variant = null
static var _looked := false


static func story_state() -> Variant:
	if not _looked:
		_looked = true
		if ResourceLoader.exists(STORY_STATE):
			_ss = load(STORY_STATE)
	return _ss


## Is an organised siege due at this invasion slot?
static func eligible(state: Object) -> bool:
	var ss: Variant = story_state()
	if ss != null and ss.has_method("siege_eligible") and _has_story(state):
		return bool(ss.siege_eligible(state))
	var c := ch1(state)
	if c.is_empty():
		return false
	var at := float(c.get("siege_at", -1.0))
	return (c.get("done", []) as Array).has(4) and at >= 0.0 and float(state.get("total_minutes")) >= at


## Has Eli met him (Encounter 1 done)? Then he may watch a siege from afar.
static func introduced(state: Object) -> bool:
	var ss: Variant = story_state()
	if ss != null and ss.has_method("architect_introduced") and _has_story(state):
		return bool(ss.architect_introduced(state))
	return (ch1(state).get("done", []) as Array).has(1)


## Records that a siege happened (StoryState.note_siege; the fallback counts
## it in the documented keys and clears siege_at so the next one waits for S).
static func note(state: Object) -> void:
	var ss: Variant = story_state()
	if ss != null and ss.has_method("note_siege") and _has_story(state):
		ss.note_siege(state)
		return
	var c := ch1(state)
	if c.is_empty():
		return
	c["sieges"] = int(c.get("sieges", 0)) + 1
	c["siege_at"] = -1.0


## Sieges so far (0 without a story).
static func sieges(state: Object) -> int:
	return int(ch1(state).get("sieges", 0))


## The chapter dictionary (shared, writable), or {} with no story.
static func ch1(state: Object) -> Dictionary:
	if state == null:
		return {}
	var st: Variant = state.get("story") if "story" in state else (state.get_meta("story") if state.has_meta("story") else null)
	if not (st is Dictionary):
		return {}
	var c: Variant = (st as Dictionary).get("ch1", st)
	return c if c is Dictionary else {}


static func _has_story(state: Object) -> bool:
	return state != null and "story" in state
