# Audio inbox

Drop your recordings here (sub-folders are fine). The game picks them up by their **descriptive file name**, with no code changes:

- `Footsteps - Snow.mp3` → the player's steps on snow
- `Door open 1.wav` … `Door open 4.wav` → door opening, a random one each time
- `Fireplace 1.wav` … `Fireplace 3.wav` → the crackling fire, cross-faded

**Rules:**

- **Names:** upper or lower case doesn't matter, nor do separators (`-`, `_`, spaces). Words may be longer than the keyword: "Footsteps - wood floor" matches the keywords "footstep" + "wood".
- **Variants:** a trailing number (`1`–`4`, `01`–`03`) makes a numbered set; the game picks a random variant each time, never the same one twice in a row.
- **Formats:** `.wav`, `.ogg` or `.mp3`. The game sets looping itself, so no import settings are needed.
- **Trimming and levels:** silence at the start and end is skipped at runtime and each file is levelled to its sound's target. Your files are never changed.
- **Footsteps:** recordings with several steps are cut into single steps automatically.
- **Precedence:** a file in `custom/audio/` next to the game still wins; this folder comes next and wins over the generated placeholder sounds. The first upload in `assets/audio/_inbox/` is read too; this folder wins over it.
- **Unknown or ambiguous files:** they are never played, only listed: in the log, in the F10 developer menu (section "Audio") and in `docs/experiment-005/AUDIO.md`.
- **New files:** open the project once in the Godot editor so they are imported, before a build.

**More:**

- `docs/experiment-005/AUDIO.md`: the full naming table and how each sound is used.
- `docs/experiment-005/AUDIO_REQUIREMENTS.md`: what to record next, with file names and prompts.
