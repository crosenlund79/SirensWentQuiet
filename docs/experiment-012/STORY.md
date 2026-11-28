# Experiment 012 — Chapter One "Someone Is Watching": implementation notes (S)

The requirements are ASSIGNMENT §2–8 and §35–37. The code is in `src/story/`.

## Modules

| File | Purpose |
|---|---|
| `story_state.gd` (`StoryState`) | The saved progression (`GameState.story`, top-level `"story"`; old saves start fresh), scheduling, `siege_eligible` / `note_siege` for the siege director |
| `story_director.gd` (`StoryDirector`) | The game's `story` helper: the sleep hook, the four encounters, the watcher, the ropes and the fireplace, the F10 API |
| `story_stage.gd` (`StoryStage`) | Temporary bedroom staging: blankets, the prop door and its jolts, dark lights, Eli lying or bound in his bed, the gas, the ropes flying into the fire |
| `story_audio.gd` (`StoryAudio`) | The user's recordings, voice cues, the follower soundscapes, the coordinated silence, the bat blows with door jolts, `stop_all()` |
| `story_overlay.gd` (`StoryOverlay`) | Darkness and vignette, the gas tint and disorientation, subtitles (his lines and Eli's thoughts), the keep or burn card |
| `story_figure.gd` (`StoryFigure`) | The watcher of Encounter 2 (the Exp 011 rig: stillness, the controlled turn, observing) |
| `story_lines.gd` (`StoryLines`) | The words: cue spans in the recordings, subtitles, Eli's thoughts |
| `story_dev.gd` (`StoryDev`) | The F10 Story and Audio sections |
| `door_impacts.json` | Bat impact times per recording (editable) |

## Timing and conditions

**Scheduling.** All values are randomised from the run seed.
- Encounter 1 becomes eligible at 20:00 on day 2 or 3.
- The later encounters follow at +3–6, +5–9 and +7–12 days.
- The first organised siege becomes eligible 1–3 days after Encounter 4.
- After each siege (`note_siege`), the next one waits 4–7 days.

**Conditions for 1, 3 and 4:**
- Eli sleeps in his bed at home.
- The encounter's time has come.
- The sleep reaches into 00:40–04:00. An invasion, a straggler or hunger can end the sleep earlier, and then the encounter waits for another night.

**Conditions for 2:**
- Eli is awake at home, outside build mode, with no enemies around.
- The time is between 19:00 and 23:45, and dusk has begun.

**While a night scene runs:**
- The game's modal is `"sleeping"`. The clock stands still, nothing saves, and no invasion or straggler can start.
- Input and the HUD are off. Esc skips to the end of the scene.
- Afterwards the stage, the lights, the camera distance, input, the HUD and the audio duck all come back.
- Leaving the scene (menu, load, quit) runs `_exit_tree`, which stops all story audio and restores the stage.

## The recordings and the lines

The spans come from an RMS envelope: 20 ms windows, with sound counted within 30 dB of the loudest window. The words were checked against a local transcription. The script's pauses fall between cues, so the recordings play unedited.

| Logical name | File | Spans used (s) → line |
|---|---|---|
| `story/architect_wakey` | voice/…Wakey wakey sunshine… .mp3 | 0.16–1.66 "Wakey, wakey, sunshine." · 2.06–4.32 "Well... there you are." · 5.32–end "I was beginning to think you wouldn't wake up." (this extra line is recorded in this file, so it is used in Encounter 1) |
| `story/architect_comfortable` | voice/…Comfortable… .mp3 | 0.04–2.46 "We've been watching you." (Encounter 1) · then the whole file as Encounter 2's three lines: + 2.98–5.30 "For quite some time, actually." · 5.98–end "You really have made yourself comfortable here." |
| `story/architect_random` | voice/…Random on encounter… .mp3 | 0.14–3.22 "Well, I think that's enough for tonight." (end of Encounter 3) · 4.36–end "Night nighty." (Encounter 1) |
| `story/architect_final` | voice/…The final encounter… .mp3 | Encounter 4 in eight cues: 0.10–3.44, 4.38–10.18 (three subtitles), 10.62–13.34, 14.24–16.14, 16.80–18.32, 19.10–20.62, 21.36–22.66, 23.32–end. The script's pauses are longer than the recording's, and the silence comes right after "I've asked them to leave you alone." |
| `story/architect_warning_01`…`_07` | none yet | Encounter 3's seven lines. They appear as subtitles only. A file `custom/audio/story/architect_warning_0N.ogg` or `.wav` plays automatically. |
| `story/follower_bark`, `_howl`, `_breath`, `_bin`, `_bat` | Architect followers – … 1–4 (breathing 1–3) | Bursts of 1–3 sounds (barks, bins), whole howls, or 3–6 s windows of breathing. The bat files always play whole. |

**Door impacts.** These are the main blows in each recording, in seconds. `door_impacts.json` also holds the bounce right after a blow, at strength 0.5.

| Bat file | Main blows (s) |
|---|---|
| 1 | 0.015, 2.22, 3.945, 5.96 |
| 2 | 0.02, 1.405, 2.935, 4.995, 6.495 |
| 3 | 0.02, 1.465, 3.56, 5.92 |
| 4 | 0.0, 1.98, 4.31 |

The `offset` value moves one file's blows, and `latency` moves all of them.

**Missing recordings** (for the audio requirements report):
- Encounter 3's seven lines (`story/architect_warning_01..07`).
- A soft knock on a door for Encounter 1. It currently uses the existing `door/bash` at −17 dB.

## Known limits

- Encounter 3's lines have no voice yet. They show as subtitles from outside the window.
- Each night scene plays in the original bedroom with the plan's bed.
- The prop door is a wooden door that stands in for any door built there while the scene runs. If the doorway has been walled up, the door still appears in the wall position.
- Burning the ropes needs Eli on the ground floor with a lit fire and a walkable path to it. Closed doors on the way are opened. Otherwise the card names the reason and he keeps the ropes.
