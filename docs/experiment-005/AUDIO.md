# Audio — Experiment 005: the audio inbox and layered sound

Owner: A. This document covers the user's §11. What to record next is in `AUDIO_REQUIREMENTS.md`.

**Code:**

- `src/audio/audio_inbox.gd` (`AudioInbox`): the scan and the mapping table.
- `src/audio/audio_analysis.gd` (`AudioAnalysis`): trimming, step slicing and levels.
- `src/audio/audio_mix.gd` (`AudioMix`): the Outdoor and Voice buses and the voice duck.
- `src/audio/ambience.gd` + `src/audio/ambience_bed.gd`: the layers.
- `src/audio/voice.gd` (`Voice`): Eli.
- `src/audio/game_audio.gd`: the game's audio helper.
- `src/game/footsteps.gd`: gait and surface.
- `src/audio/sfx.gd`: playback and precedence.

**Tests:** `tests/audio/test_audio_inbox.gd`, `test_audio_layers.gd`, `test_audio_game.gd` (a smoke test in the real game scene).

**Honesty note:** the mix levels below were set by measurement (active RMS, envelopes), not by ear. Listen in game and adjust the targets in `AudioInbox.RULES` or the per-file trims in `AudioInbox.FILE_GAIN`.

## 1. The inbox

### Where files go

- **The drop folder:** `assets/audio inbox/` (with a space). It has a short `README.md`.
- **The first upload:** `assets/audio/_inbox/` (the user's 64 files from 2026-11-25) is read as well. Nothing was moved, renamed, converted or rewritten. Only Godot's `.import` files were added next to them, so they load in exported builds.
- **Scanning:** both folders are scanned recursively once per session, when sound first plays.
- **In an exported game:** the folder lists `X.wav.import` / `.remap` instead of `X.wav`; the scanner strips those suffixes.
- **A file that isn't imported yet** (dropped while the editor is closed) is loaded straight from disk (`load_from_file`). Open the editor once before a build so it gets imported.

### Precedence, per logical name

1. **`custom/audio/<logical>.ogg|.wav`** (next to the game; the creator system of `docs/experiment-002/audio.md`). It wins for the whole name, including all variants of a group, as soon as any of its files exists.
2. **The inbox.** For one name, the first folder that has files for it provides the whole pool: `assets/audio inbox/` before `assets/audio/_inbox/`. Files that lose are reported as "shadowed".
3. **The generated template** `assets/audio/<dir>/template_<name>.ogg`.

`Sfx.source_of(name)` tells which one plays; the F10 sound list shows it too.

### Naming and mapping

- **Words:** a file's name, without extension and trailing variant number, is split into lower-case words at anything that isn't a letter or digit.
- **Rules:** each rule in `AudioInbox.RULES` lists:
  - the keywords that must all appear (alternatives allowed);
  - keywords that must not appear.

  A keyword matches a word that **starts** with it ("footstep" matches "Footsteps", "wood" matches "wooden"), so "Footsteps - Wood.mp3" and "Footsteps - wood floor.wav" both match.
- **Best rule:** the rule with more keywords wins.
  - Two different names tied: the file is **ambiguous**.
  - No rule matches the name alone: the folder names are added (a song in `Theme/` is the menu theme).
- **Variants:** a trailing number after a space, `_`, `-` or `.` (`1`–`4`, `01`–`03`) makes a variant. All files of one name form a **random pool**, never the same clip twice in a row.
- **Unknown, ambiguous or shadowed files** are never played. They are reported:
  - one warning line each at startup (`AudioInbox: '<path>' not used (<reason>)`);
  - the F10 Audio list;
  - `AudioInbox.report()`.
- **Aliases:** a name without its own files borrows another pool:
  - `player/footstep` → `player/step_wood` (the stairs and the old footstep group);
  - `music/dawn` → `music/menu` (the theme).

### Playback

**Per file at first use:** the file is decoded in script with `AudioStreamPlayback.mix_audio` (any imported format: WAV in its default QOA compression, MP3, Ogg) and measured. No import setting was changed.

**Trimming:**

- **Starts:** the clip starts where the sound starts. The exports carry up to 1.25 s of near-silence or a decaying tail before the sound: handgun shot 01 starts at 1.25 s, door close 1 at 0.71 s.
- **Ends:** it stops (with a 30 ms fade) where the sound ends, so a voice is free again early.

**Levels:** each clip is levelled towards its rule's target active RMS (`db`), clamped to ±12 dB.

- Door open 4 measures −41 dB; the other door-open takes about −30 dB.
- The snow steps measure −40 dB.
- `FILE_GAIN` adds per-file trims in dB.

**Footsteps:** recordings are sliced into single steps (`kind: "step"`):

- onsets with hysteresis between two thresholds above the noise floor;
- each step runs to the end of its sound, at most 0.55 s;
- scuffs more than 9 dB below the median step are dropped.

The current files give 5 wooden, 6 snow, 4 cement and 32 enemy-snow steps.

**Loops** are set in code on a copy of the stream: `AudioStreamWAV.loop_mode`, `AudioStreamMP3.loop`, `AudioStreamOggVorbis.loop`. Any new file loops without import settings.

**Beds** (forest, fireplace, room tones) don't loop a file: the recordings aren't seamless. A bed cross-fades over 3 s into another file of its pool, or the same one again, before the end.

**Cost:** about 0.35 s once per session while the game loads (`AudioInbox.prepare_all()`, everything but the music). The theme (MP3) loads on the main menu in about 40 ms.

## 2. The mapping table (short)

The full table is `AudioInbox.RULES`. `+` joins required keywords; `|` separates alternatives.

| Keywords in the file name | Logical name | Plays |
|---|---|---|
| footstep\|step + snow (not enemy) | `player/step_snow` | player steps outside (sliced) |
| footstep\|step + wood (not enemy) | `player/step_wood` | steps on wooden floors, the stairs (sliced) |
| footstep\|step + cement\|concrete\|stone\|tile | `player/step_cement` | basement, utility room, bathroom, kitchen (sliced) |
| enemy + footstep + snow / wood | `enemy/step_snow` / `enemy/step_wood` | the nearest 3 enemies' steps (sliced) |
| handgun\|pistol + shot\|fire | `weapon/handgun_fire` | handgun shot |
| shotgun + shot\|fire\|blast | `weapon/shotgun_fire` | shotgun shot |
| reload (not done) | `weapon/reload` | reload start (handgun and shotgun share it) |
| reload + done\|finish\|ready | `weapon/reload_done` | the slide or pump forward |
| shell / dry\|empty / weapon + switch\|holster\|draw | `weapon/shell_load` / `weapon/dry_fire` / `weapon/switch` | |
| door + open / door + close\|shut\|slam | `door/open` / `door/close` | |
| bash\|heavy\|pound\|bang\|kick | `door/bash` | an enemy's blow on a wooden door |
| glass | `impact/glass` | a window hit or broken |
| impact + wood\|plaster\|metal\|flesh\|ground\|snow | `impact/*` | bullet and blow impacts |
| destruction\|break\|smash + wall\|wood\|timber | `structure/break` | a wall section breaking |
| building\|constructing\|hammer\|nail (not metal) | `build/hammer` | building, repairing |
| metal + hammer\|upgrade\|reinforce | `build/upgrade` | upgrades, metal doors |
| place\|plank\|board / demolish\|crowbar / invalid | `build/place` / `build/demolish` / `build/invalid` | |
| crumble\|debris\|rubble / blast\|explosion | `structure/crumble` / `structure/blast` | |
| enemy + vocal\|moan\|groan\|growl | `enemy/moan` | enemy voices |
| enemy + attack / hit\|pain\|grunt / death | `enemy/attack` / `enemy/hit` / `enemy/death` | |
| bomber + fuse\|beep / bomber + blast | `enemy/bomber_fuse` / `enemy/bomber_blast` | |
| hurt\|pain, eat, drink, bandage, sleep, death (not enemy) | `player/*` | |
| fireplace + light\|ignite / fireplace + extinguish\|out | `home/fireplace_light` / `home/fireplace_out` | lighting or putting out the fire |
| light\|lamp + switch | `home/light_switch` | room and lamp switches |
| car + start\|engine | `car/start` | the repaired car's engine |
| shovel\|dig | `build/dig` | basement digging (hook pending, see §8) |
| ui + click\|hover\|open\|close\|error | `ui/*` | interface |
| stinger + invasion / stinger + dawn | `stinger/*` | |
| theme\|menu (or a file in `Theme/`) | `music/menu` | the main menu, and softly at dawn |
| music + dawn\|morning | `music/dawn` | a dedicated dawn piece (else the theme) |
| wind (not night) / night + wind\|bed\|loop / tension\|drone | `ambient/wind_day` / `ambient/night` / `ambient/tension` | the existing loops |
| distant (+ scrape / shriek / siren) | `ambient/distant` (`_1` / `_2` / `_3`) | noises out in the fog |
| natural\|nature\|forest\|outdoor\|woods | `ambient/forest` | outdoor bed |
| fireplace\|hearth | `ambient/fireplace` | positional fire bed |
| room\|interior\|indoor + tone\|ambience / basement\|cellar + tone\|ambience | `ambient/room_tone` / `ambient/basement_tone` | indoor beds |
| owl\|hoot / wolf\|wolves | `ambient/owl` / `ambient/wolf` | night details |
| creak\|settling, or wood + house | `ambient/house_creak` | indoor details |
| eli + new / eli + continue\|saved | `voice/eli_new_game` / `voice/eli_continue` | Eli |

## 3. What each uploaded file does

All 64 files map; none is unknown or ambiguous.

| Files | Logical name | Used for |
|---|---|---|
| `Theme/Sirens went quiet - Warmth in the freeze.mp3` | `music/menu` (and `music/dawn`) | Main menu (−8 dB); softly at dawn (−16 dB) |
| `voice/Eli - Welcome to a new game.mp3` | `voice/eli_new_game` | After a new game's intro |
| `voice/Eli - Continue saved game.mp3` | `voice/eli_continue` | 1.2 s after Continue |
| `Fireplace 1–3.wav` | `ambient/fireplace` | Positional bed at the hearth while it burns |
| `Natural ambiance 1–3.wav` | `ambient/forest` | Outdoor bed, levelled from about −42 dB to −31 dB |
| `Nighttime - Owl howling 1–4.wav` | `ambient/owl` | Night detail out in the fog |
| `Nighttime - Wolf howl 1–4.wav` | `ambient/wolf` | Night detail out in the fog |
| `Wooden house periodic ambiance 1–4.wav` | `ambient/house_creak` | Indoor detail near the player |
| `Footsteps - Snow.wav` | `player/step_snow` | 6 sliced steps, levelled from about −40 dB |
| `Footsteps - wood floor.wav` | `player/step_wood` | 5 sliced steps; also the stairs |
| `Footsteps - Cement floor.wav` | `player/step_cement` | 4 sliced steps (2 scuffs dropped) |
| `Enemy - Footsteps Snow 1–4.wav` | `enemy/step_snow` | 32 sliced steps for nearby enemies outside |
| `Enemy - Heavy impact wood 1–4.wav` | `door/bash` | An enemy's blow on a wooden door |
| `Enemy - Vocal 1–4.wav` | `enemy/moan` | Enemy voices (were 2 generated variants) |
| `Building or constructing 1–4.wav` | `build/hammer` | Building, repairing, boarding |
| `Hammer on metal 1–3.wav` | `build/upgrade` | Upgrades, metal reinforcement |
| `Destruction - Glass Shatter 1–4.wav` | `impact/glass` | Window hits |
| `Destruction - Wooden Wall 1–2.wav` | `structure/break` | A wall section or furniture breaking |
| `Door open 1–4.wav` / `Door close 1–4.wav` | `door/open` / `door/close` | Doors |
| `Weapon - HAndgun Reload 1–4.wav` | `weapon/reload` | Reload start (also the shotgun's, until it has its own) |
| `Weapon - Handgun Shot 01–03.wav` | `weapon/handgun_fire` | The handgun; 0.7–1.25 s of leading silence skipped |

## 4. Layered ambience

Extends `Ambience` (`src/audio/ambience.gd`). The game helper tells it where the player is about four times a second.

| Layer | Content | Bus | Behaviour |
|---|---|---|---|
| 1. Outdoor | **Forest bed** (inbox), the generated **wind** (day) and **night** loops, owls, wolves, the distant noises | **Outdoor** → Ambient | The generated wind and night sit 6 dB under a recorded forest; the forest bed drops to 0.55 at night |
| 2. Indoor | **Room tone** (inside) or **basement tone**; both await recordings | Ambient | Inside, the Outdoor bus is turned down and low-passed |
| 3. Fireplace | **Fire bed** at the hearth, positional (unit size 2.5 m) | Ambient | Only while lit, gliding in and out; at 0.3 from another storey |
| 4. Details | **Owls** (night ≥ 0.55, every 35–90 s), **wolves** (night ≥ 0.7, every 70–160 s), beyond the lot edge like the distant noises; **house creaks** indoors (every 30–80 s, 2–4 m from the player) | Outdoor / Ambient | Silent during invasions |
| 5. Threat | The existing tension drone, the stingers, enemy sounds | Ambient / Music / SFX | During an invasion, the outdoor beds dip 3 dB and the animals fall silent |
| 6. Music | The theme on the main menu; softly for 95 s from 6 s after dawn (`music/dawn`) | Music | Never during an invasion; stops when one starts |
| 7. Voice | Eli (§6) | Voice | Ducks Ambient and Music by 6 dB while he speaks |

**Places** (`Ambience.PLACES`; the mix glides between them in about 1.5 s):

| Place | When | Outdoor bus | Low-pass | Room tone | Basement tone |
|---|---|---|---|---|---|
| outside | Outside the house footprint on the ground floor | 0 dB | off | 0 | 0 |
| inside | In the footprint, or a room (agent C's `comfort.room_at`, when present) | −9 dB | 1500 Hz | 1 | 0 |
| exposed | A room C reports as `exposed` (open to the outside) | −4 dB | 5000 Hz | 0.5 | 0 |
| basement | Any storey below 0 | −18 dB | 520 Hz | 0.25 | 1 |

**The extra buses** are created at runtime by `AudioMix.ensure_buses()` (called by `Sfx.attach`), so `default_bus_layout.tres` is unchanged:

- **Outdoor** → Ambient, with a low-pass that is bypassed outside. The Ambient slider still scales it. It's reset when the game scene ends.
- **Voice** → Master. There is no slider; Master scales it.
- **"VoiceDuck" amplifiers** on Ambient and Music. The ducking never touches the settings sliders' bus volumes.

No physical sound propagation: places are rules, not acoustics.

## 5. Footsteps

**Gait:** a step plays each time the player rig's `walk_phase` passes a heel strike (π/2 + kπ). Refinement 01 ties the phase to distance travelled, so steps match the animation, speed up when sprinting and stop with the movement. Below 0.6 m/s nothing plays.

**Surface** (`Footsteps.surface(storey, plan_pos)`):

| Where | Surface |
|---|---|
| Ground floor outside the footprint | snow |
| Basements | cement |
| Upper floors | wood |
| Ground-floor rooms | from `HousePlan.ROOMS[].floor`: wood / wood_light → wood; concrete, tile, kitchen_tile → cement |

Tiled rooms use the hard-floor recording until there's a tile one.

**Playback:**

- each step is a random slice (§1) with ±6 % pitch, flat (the listener is at the player), at −4 dB, +2 dB when sprinting;
- with no inbox file for a surface, the generated wooden footsteps play;
- `tick()` (the Experiment 002 timer) is kept for callers without a rig, but the game no longer uses it.

**Enemies:** the nearest 3 enemies within 16 m on the player's storey step on their own gait, positional, on snow outside (`enemy/step_snow`). Indoors they use `enemy/step_wood`, which is silent until there is a recording.

## 6. Eli's voice

- `Voice.say(name)` plays a line on the **Voice** bus.
- **Never overlapping:** a second line while one plays is refused.
- **Ducking:** Ambient and Music duck by −6 dB, in over 0.35 s and back over 1.2 s.
- **New game:** "Welcome to a new game" plays 1.2 s after the intro overlay finishes (or after the start when the intro is skipped).
- **Continue:** "Continue saved game" plays 1.2 s after the game opens.
- **No other commentary.** A missing file means silence.
- The line stops when the game scene ends.

## 7. Developer menu (F10 → Audio)

- **A sound list:** every logical name with its source (inbox, template, custom, no file). "Play sound" plays it:
  - positional sounds at the player;
  - voice through `Voice`;
  - music tracks toggled through `Sfx.music`.
- **Stop voice / music.**
- **Layer toggles:** Outdoor, Indoor, Fireplace, Details, Threat.
- **"Owl / wolf / creak":** plays one of each now.
- **Status:** the place, the outdoor level and low-pass, the layers, the bed levels, the last surface and step counts, the music and the last voice line.
- **The inbox:** each mapped name with its first file and pool size, then the unused files in orange with the reason.

## 8. API additions (all additive)

| Member | Purpose |
|---|---|
| `Sfx.clip(name)` | `{"stream", "from", "to", "db", "source"}`: what plays for a name |
| `Sfx.available(name)`, `Sfx.source_of(name)` | Lookups |
| `Sfx.all_names()` | Every name, with or without a file (`names()` still lists template names only) |
| `Sfx.play_first(names, at, db)` | Plays the first name that has a file (a new recording, then the old sound) |
| `AudioInbox.report()`, `report_text()`, `files_of()`, `names()`, `clips_of()`, `prepare_all()`, `match_path()` | The inbox |
| `Ambience.set_place()`, `set_listener()`, `set_fireplace()`, `set_layer()`, `layer_status()`, `play_detail()` | Layers |
| `Voice.say()`, `speaking()`, `stop()`; `AudioMix.duck()`, `set_outdoor()` | Voice and mix |

**New logical names** (no generated template; silent until a file maps to them):

- `player/step_snow|wood|cement`
- `enemy/step_snow|wood`
- `ambient/forest|fireplace|room_tone|basement_tone|owl|wolf|house_creak`
- `voice/eli_new_game|eli_continue`
- `music/dawn`
- `home/fireplace_light|fireplace_out|light_switch`
- `car/start`
- `build/dig`

**Small edits in shared files:**

- `survival_game.gd`: creates the helper; the old timer-based footsteps are removed.
- `dev_menu.gd`: one section and one refresh line.
- `game_home.gd`: the two light switches use `play_first(["home/light_switch", "ui/click"])`.
- `game_car.gd`: the car start uses `play_first(["car/start", "ui/open"])`.

**Hook pending (for the lead, to avoid a conflict with agent V):** `src/levels/level_build.gd`, where a basement cell is dug. Today it plays `impact/ground` and `build/demolish`; it could play `Sfx.play_first(["build/dig", "build/demolish"], at)` instead.

**Tests:** `tests/audio/test_audio_ambience.gd` and `test_audio_sfx.gd` were adapted:

- the wind, night and distant noises are on the Outdoor bus;
- the music loop check accepts an MP3.

## 9. Limits

- **Nothing was auditioned by ear.** The levels and the step slicing come from measurements; listen and adjust `RULES[].db` or `FILE_GAIN`.
- **Step slicing** is an energy-onset detector. Snow crunches are soft and noisy, so one of the six snow slices is a weak −49 dB step. The enemy recordings have quick steps; some slices may hold a step and a half.
- **The fixed-length exports** sometimes start with the tail of another take (Handgun Shot 02/03). The trimming skips it by level, which also skips a deliberately soft lead-in more than 30 dB below the peak.
- **The shotgun** shares the handgun reload recording (`weapon/reload` is one name in the weapon code) until a shotgun file exists and the weapon code asks for a per-weapon name.
- **The bed recordings** are not seamless loops, so beds cross-fade between files; a one-file loop (`ambient/wind_day` from the inbox) loops its file as it is.
- **Room tones** are silent until recorded.
- **Places:** "inside" is the footprint (or C's rooms when present); a broken wall only counts with C's `exposed` flag. There is no occlusion between rooms.
- **Loading:** about 0.35 s once per session while the game loads, and about 40 ms for the theme on the menu.
- **No Voice slider** in Settings; Master scales the voice.
- **New files** in an exported build appear only after the project has been opened in the editor or imported by the build.
