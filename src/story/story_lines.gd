class_name StoryLines
extends RefCounted
## Exp 012 (S): the words of Chapter One, "Someone Is Watching", and where they
## are in the user's recordings. Data only (edit freely; times in seconds).
##
## CUES: one spoken line (or a few in one breath) = a span of one recording:
##   id: {"name": logical sound name (StoryAudio), "from", "to": the span in the
##        file (to < 0: to its end), "subs": [[t, text], ...] subtitles shown
##        from file time t}
## The spans were found by measuring the recordings (an RMS envelope, 20 ms
## windows, speech = within 30 dB of the loudest window; see
## StoryAudio.speech_spans and docs/experiment-012/STORY.md), widened by
## ~0.06 s before and ~0.1 s after, and the words checked against a local
## transcription. The encounter scripts (StoryDirector) put the script's
## pauses *between* cues, so the user's recordings are used as they are.
##
## Lines with no recording yet ("slots"): their name has no file, so they
## show as subtitles only, for `est` seconds. A file the user adds later
## under that logical name (custom/audio/<name>.ogg|.wav, or the inbox; see
## StoryAudio) plays automatically, whole. No voice is ever synthesised.

const CUES := {
	# --- "Wakey wakey sunshine" (7.55 s): the first encounter, behind the door
	"wakey": {"name": "story/architect_wakey", "from": 0.16, "to": 1.66, "subs": [[0.16, "Wakey, wakey, sunshine."]]},
	"there_you_are": {"name": "story/architect_wakey", "from": 2.06, "to": 4.32, "subs": [[2.06, "Well... there you are."]]},
	"beginning": {"name": "story/architect_wakey", "from": 5.32, "to": -1.0, "subs": [[5.32, "I was beginning to think you wouldn't wake up."]]},
	# --- "Comfortable" (8.52 s): the second encounter (first line also in the first)
	"watching": {"name": "story/architect_comfortable", "from": 0.04, "to": 2.46, "subs": [[0.04, "We've been watching you."]]},
	"some_time": {"name": "story/architect_comfortable", "from": 2.98, "to": 5.30, "subs": [[2.98, "For quite some time, actually."]]},
	"comfortable": {"name": "story/architect_comfortable", "from": 5.98, "to": -1.0, "subs": [[5.98, "You really have made yourself comfortable here."]]},
	# --- "Random on encounter" (5.49 s): two short lines
	"enough": {"name": "story/architect_random", "from": 0.14, "to": 3.22, "subs": [[0.14, "Well, I think that's enough for tonight."]]},
	"night_nighty": {"name": "story/architect_random", "from": 4.36, "to": -1.0, "subs": [[4.36, "Night nighty."]]},
	# --- "The final encounter before confrontation" (24.61 s): the fourth encounter
	"final_patient": {"name": "story/architect_final", "from": 0.10, "to": 3.44, "subs": [[0.10, "You know... I've been remarkably patient with you."]]},
	"final_walls": {"name": "story/architect_final", "from": 4.38, "to": 10.18, "subs": [[4.38, "I've watched you build your little walls."],
		[6.84, "Board up your windows."], [8.32, "Convince yourself that you're safe."]]},
	"final_still": {"name": "story/architect_final", "from": 10.62, "to": 13.34, "subs": [[10.62, "And still... you don't understand."]]},
	"final_asked": {"name": "story/architect_final", "from": 14.24, "to": 16.14, "subs": [[14.24, "I've asked them to leave you alone."]]},
	"final_courtesy": {"name": "story/architect_final", "from": 16.80, "to": 18.32, "subs": [[16.80, "That was a courtesy."]]},
	"final_run_out": {"name": "story/architect_final", "from": 19.10, "to": 20.62, "subs": [[19.10, "I'm afraid I've run out of those."]]},
	"final_sleep_well": {"name": "story/architect_final", "from": 21.36, "to": 22.66, "subs": [[21.36, "Sleep well, sunshine."]]},
	"final_while": {"name": "story/architect_final", "from": 23.26, "to": -1.0, "subs": [[23.26, "While you still can."]]},
	# --- the third encounter: no recordings yet (replaceable slots, subtitles only)
	"warn_progress": {"name": "story/architect_warning_01", "from": 0.0, "to": -1.0, "est": 1.8, "subs": [[0.0, "You're making progress."]]},
	"warn_walls": {"name": "story/architect_warning_02", "from": 0.0, "to": -1.0, "est": 2.0, "subs": [[0.0, "Those walls of yours..."]]},
	"warn_impressive": {"name": "story/architect_warning_03", "from": 0.0, "to": -1.0, "est": 1.9, "subs": [[0.0, "They're quite impressive."]]},
	"warn_watching": {"name": "story/architect_warning_04", "from": 0.0, "to": -1.0, "est": 2.0, "subs": [[0.0, "But I've been watching."]]},
	"warn_routine": {"name": "story/architect_warning_05", "from": 0.0, "to": -1.0, "est": 1.8, "subs": [[0.0, "You have a routine."]]},
	"warn_routines": {"name": "story/architect_warning_06", "from": 0.0, "to": -1.0, "est": 1.7, "subs": [[0.0, "And routines..."]]},
	"warn_inconvenient": {"name": "story/architect_warning_07", "from": 0.0, "to": -1.0, "est": 2.6, "subs": [[0.0, "They can become terribly inconvenient."]]},
}

## Eli's thoughts (subtitles in the thought style, never voiced).
const THOUGHTS := {
	"wake": ["Was that a dream?", "No... I was awake.", "Who the hell was that?", "What the fuck just happened?"],
	"observer_seen": ["That's him..."],
	"observer_voice": ["That's the voice."],
	"observer_still": ["Why is he just standing there?"],
	"burn": ["I'm not keeping those things.", "Not in my house."],
}

## The recordings behind the voice names (file-name keywords, matched in
## StoryAudio). Slots (no recording yet) are the warning_* names in CUES.
const VOICE_FILES := {
	"story/architect_wakey": ["wakey"],
	"story/architect_comfortable": ["comfortable"],
	"story/architect_random": ["random"],
	"story/architect_final": ["final"],
}


## Every logical voice name the chapter uses (recorded or a slot).
static func voice_names() -> Array:
	var out := []
	for id in CUES:
		var n: String = CUES[id]["name"]
		if not n in out:
			out.append(n)
	return out


## The full text of a cue (its subtitles joined).
static func text_of(id: String) -> String:
	var parts := []
	for s in CUES.get(id, {}).get("subs", []):
		parts.append(str(s[1]))
	return " ".join(parts)
