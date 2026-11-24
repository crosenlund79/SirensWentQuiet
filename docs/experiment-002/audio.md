# Audio — Experiment 002

Owner: A. Code: `src/audio/` (`Sfx`, `Ambience`) and `AssetResolver.get_audio` in `src/common/asset_resolver.gd`. Template sounds: `assets/audio/`. Generator and analysis: `tools/audio/`. Tests: `tests/audio/` and the audio part of `tests/common/test_asset_resolver.gd`.

**Honesty note:** every sound here was synthesised by a script and checked by **measurement only** (levels, peaks, loop seams, durations, spectra and spectrogram images). **Nothing was auditioned by ear.** Treat the templates as reasonable placeholders that a person should listen to, and replace any that don't work (see "Replacing sounds").

## 1. Using it (for other modules)

```gdscript
Sfx.attach(self)                            # scene root, once per scene (the game already does)
Sfx.play("impact/wood", hit_pos)            # Vector3 world position = positional
Sfx.play("impact/wood", Vector2(x, y))      # plan coordinates also work (height 1 m)
Sfx.play("player/eat")                      # no position = flat (non-positional)
Sfx.play("player/footstep", player_pos)     # a group name picks a random variant
Sfx.ui("ui/click")                          # UI bus; works in menus and while paused
Sfx.music("music/menu") ; Sfx.music("")     # 2 s cross-fade; "" fades out

var amb := Ambience.new() ; add_child(amb)  # loops start on entering the tree
amb.set_night_amount(state.night_amount())  # every frame is fine (it smooths)
amb.set_tension(1.0 if invasion else 0.0)   # low drone during invasions
```

- **Groups:** `player/footstep` (4 variants), `enemy/moan` (2) and `ambient/distant` (3) play a random variant, never the same one twice in a row. The numbered names (`player/footstep_3`) play that exact file.
- **Repeats are tamed:** every name has a cooldown and a cap on simultaneous instances (table in §3), so calling `play` every frame can't machine-gun. Within its cap a name restarts its oldest instance (impacts, gunfire) or skips (footsteps, moans).
- **Unknown names** warn once and play nothing. Loops (`ambient/*` beds, `music/menu`) are refused by `play` with a warning: use `Ambience` or `Sfx.music`.
- **No root attached** (or the root was freed): `play` warns once and uses the SceneTree root instead; it never crashes.
- **Where the players live:** flat and positional players are pooled under the attached scene root (16 flat, 32 positional) and disappear with the scene. UI (6) and music (up to 3) players live under the SceneTree root, so a click on "New Game" and a music cross-fade survive the scene change. All pools run while the tree is paused, so eating from the paused inventory is heard.
- **Listener:** the game camera is 11–32 m from the player, so the scene host adds an `AudioListener3D` that sits where the current camera looks (the camera ray meets the plane y = 1 m), with the camera's orientation for panning. It never takes over when another listener is current. Set `Sfx.auto_listener = false` before `attach` to disable.
- **Positional settings:** inverse-distance attenuation, unit size 9 m, max distance 40 m, a gentle air filter (7 kHz, −10 dB). Distant noises (`far`) use unit size 14 m, max distance 60 m and a stronger filter (2.2 kHz, −20 dB), so they sound like they come through fog.

### API additions (beyond SPEC §7.6; all additive)

| Member | Purpose |
|---|---|
| `Sfx.key_of(name) -> String` | The metadata key: the name itself or its group; `""` if unknown |
| `Sfx.has(name)`, `Sfx.is_loop(name)` | Lookups |
| `Sfx.variants(name) -> PackedStringArray` | A group's files, or the name itself |
| `Sfx.active_count(name) -> int` | Instances playing now (tests, debugging) |
| `Sfx.current_music() -> String` | The track asked for last (`""` when stopped) |
| `Sfx.stats` | `{"played", "skipped", "stolen"}` counters |
| `Sfx.auto_listener` | See "Listener" |
| `Sfx.reset()` | Tests: detach, stop the music at once, clear cooldowns, warnings and counters |
| `Sfx.GROUPS`, `Sfx.DEFS` | The metadata tables |
| `Ambience.play_distant(index := -1) -> Vector3` | Play one distant noise now (dev menu, tests) |
| `Ambience.distant_point(angle)`, `distant_interval_range()`, `next_distant_in()`, `gains()`, `player(id)` | Introspection |
| `Ambience.distant_enabled` | False stops new distant noises |
| `AssetResolver.get_audio(logical) -> AudioStream` | SPEC §7.6 |
| `AssetResolver.audio_override_formats()`, `audio_override_path(logical, ext)`, `audio_fallback_path(logical)` | Paths and formats |

## 2. Buses

`default_bus_layout.tres` (lead): Master ← SFX, UI (sends to SFX), Ambient, Music. Settings sliders should set bus volumes with `AudioServer.set_bus_volume_db(idx, linear_to_db(v))`. Because UI sends to SFX, the SFX slider also scales UI sounds.

Stingers play on **Music** (a player who mutes music hears no musical stingers; the HUD carries the same warnings). Distant noises and the ambience loops play on **Ambient**.

## 3. Sound list

Every logical name, what it is, its bus, loop or one-shot, and its metadata (pitch spread ±, cooldown, simultaneous cap). The template file is `assets/audio/<group>/template_<name>.ogg`; for example `impact/wood` → `assets/audio/impact/template_wood.ogg`. The override goes to `custom/audio/<group>/<name>.ogg`.

| Logical name | Description | Bus | Type | Pitch ± | Cooldown | Cap | Positional |
|---|---|---|---|---|---|---|---|
| `player/footstep_1..4` | Soft heel-and-toe steps on a wooden floor, four variants | SFX | one-shot | 7 % | 0.12 s | 2 (skip) | yes |
| `player/hurt` | Dull body hit with a short breathy grunt | SFX | one-shot | 6 % | 0.35 s | 1 | no |
| `player/eat` | Three crunchy chews and a swallow | SFX | one-shot | 3 % | 0.5 s | 1 | no |
| `player/drink` | Four gulps from a bottle, small bubbles, a quiet "ahh" | SFX | one-shot | 3 % | 0.5 s | 1 | no |
| `player/bandage` | Cloth tear, then two soft wraps | SFX | one-shot | 3 % | 0.5 s | 1 | no |
| `player/sleep` | Long exhale over a soft, warm low chord | SFX | one-shot | — | 1 s | 1 | no |
| `player/death` | Collapse and thud, a low dissonant swell, faint ringing | SFX | one-shot | — | 2 s | 1 | no |
| `weapon/handgun_fire` | Sharp crack, punchy body and low thump, slide clack, short room tail and slap echo | SFX | one-shot | 3 % | 0.05 s | 4 | yes |
| `weapon/dry_fire` | Trigger and hammer click on an empty chamber | SFX | one-shot | 4 % | 0.12 s | 1 | yes |
| `weapon/shotgun_fire` | Experiment 003. A heavier, lower 12-gauge blast with a longer room tail, then the pump racked back and forward | SFX | one-shot | 3 % | 0.1 s | 3 | yes |
| `weapon/reload` | Experiment 003. Magazine released, dropped in the hand, a fresh one seated (also starts a shell reload) | SFX | one-shot | 3 % | 0.3 s | 1 | yes |
| `weapon/reload_done` | Experiment 003. Slide or pump snapping forward: ready | SFX | one-shot | 3 % | 0.1 s | 1 | yes |
| `weapon/shell_load` | Experiment 003. One shell pushed into the tube | SFX | one-shot | 5 % | 0.08 s | 2 | yes |
| `weapon/switch` | Experiment 003. Cloth and sling, then a light handling click | SFX | one-shot | 4 % | 0.15 s | 1 | yes |
| `impact/wood` | Splintery knock | SFX | one-shot | 10 % | 0.03 s | 4 | yes |
| `impact/plaster` | Dull thud with a dusty crumble | SFX | one-shot | 10 % | 0.03 s | 4 | yes |
| `impact/glass` | Crack and a tinkle of shards | SFX | one-shot | 8 % | 0.05 s | 3 | yes |
| `impact/metal` | Ringing clank | SFX | one-shot | 8 % | 0.04 s | 3 | yes |
| `impact/flesh` | Dull, muffled thud (not gory) | SFX | one-shot | 10 % | 0.03 s | 3 | yes |
| `impact/ground` | Soft thump with a scatter of dirt | SFX | one-shot | 10 % | 0.03 s | 4 | yes |
| `build/place` | Board set down: wooden thunk | SFX | one-shot | 6 % | 0.08 s | 2 | yes |
| `build/hammer` | Two hammer blows on a nail into wood | SFX | one-shot | 5 % | 0.25 s | 2 | yes |
| `build/demolish` | Crowbar creak, a crack, boards clattering down | SFX | one-shot | 4 % | 0.2 s | 2 | yes |
| `build/invalid` | Subtle, muffled low double buzz | SFX | one-shot | — | 0.25 s | 1 | no |
| `build/upgrade` | Metal sheet wobble and two rivet clinks | SFX | one-shot | 4 % | 0.2 s | 2 | yes |
| `door/open` | Latch click and a hinge creak | SFX | one-shot | 5 % | 0.15 s | 2 | yes |
| `door/close` | Short creak, wooden thud, latch | SFX | one-shot | 5 % | 0.15 s | 2 | yes |
| `door/bash` | Heavy blow on a door, rattling frame | SFX | one-shot | 8 % | 0.12 s | 3 | yes |
| `structure/break` | A wall section breaking: crack, splinters, debris, low rumble | SFX | one-shot | 6 % | 0.1 s | 3 | yes |
| `structure/crumble` | Plaster and debris trickling down | SFX | one-shot | 8 % | 0.08 s | 3 | yes |
| `structure/blast` | Experiment 003. A wall blown apart: crack, timber and masonry chunks, dust settling (HouseWorld.explode) | SFX | one-shot | 5 % | 0.2 s | 2 | yes (far) |
| `enemy/moan_1` | Low, unstable, breathy groan falling into vocal fry | SFX | one-shot | 8 % | 1.2 s (group) | 3 (skip) | yes |
| `enemy/moan_2` | Breathy rising groan ending in a throat rattle | SFX | one-shot | 8 % | 1.2 s (group) | 3 (skip) | yes |
| `enemy/attack` | Swipe whoosh with a guttural snarl | SFX | one-shot | 8 % | 0.2 s | 3 | yes |
| `enemy/hit` | Short choked grunt | SFX | one-shot | 8 % | 0.1 s | 3 | yes |
| `enemy/death` | Long falling groan and rattle, then a body slump | SFX | one-shot | 6 % | 0.1 s | 3 | yes |
| `enemy/bomber_fuse` | Experiment 003. One harsh two-tone electronic beep; the bomber repeats it faster and faster (0.7 s to 0.25 s apart) | SFX | one-shot | — | 0.15 s | 2 (skip) | yes |
| `enemy/bomber_blast` | Experiment 003. The detonation: a deep boom and pressure wave, sizzling air, a long rumble | SFX | one-shot | 4 % | 0.3 s | 2 | yes (far) |
| `ambient/wind_day` | Day wind: filtered noise with gusts, a faint whistle, leaves in the gusts (48 s) | Ambient | **loop** | — | — | — | no (Ambience) |
| `ambient/night` | Night bed: low wind, house creaks, a far dog, one hesitant cricket (52 s) | Ambient | **loop** | — | — | — | no (Ambience) |
| `ambient/tension` | *Added.* Low beating drone with a slow pulse for invasions (24 s) | Ambient | **loop** | — | — | — | no (Ambience) |
| `ambient/distant_1` | Far metal scrape, dragged, through fog | Ambient | one-shot | 5 % | 8 s (group) | 1 | yes, far |
| `ambient/distant_2` | Far shriek, two voices slightly apart | Ambient | one-shot | 5 % | 8 s (group) | 1 | yes, far |
| `ambient/distant_3` | A very distant siren that rises, falters, and winds down to silence (the motif) | Ambient | one-shot | 5 % | 8 s (group) | 1 | yes, far |
| `ui/click` | Soft, warm tick | UI | one-shot | 2 % | 0.03 s | 2 | no |
| `ui/hover` | Tiny airy tick, very quiet | UI | one-shot | 3 % | 0.04 s | 1 | no |
| `ui/open` | Soft rising two-tone with a swish | UI | one-shot | — | 0.08 s | 1 | no |
| `ui/close` | The same, falling | UI | one-shot | — | 0.08 s | 1 | no |
| `ui/error` | Two dull low tones | UI | one-shot | — | 0.25 s | 1 | no |
| `stinger/invasion` | Ominous swell: low cluster, reversed noise, a ghost of the siren, a deep hit | Music | one-shot | — | 5 s | 1 | no |
| `stinger/dawn` | Gentle relief: warm D major pad, three soft piano notes, a distant bird | Music | one-shot | — | 5 s | 1 | no |
| `music/menu` | Sparse D minor drone with slow, sad piano-like notes (72 s) | Music | **loop** | — | — | — | no (`Sfx.music`) |

Ambience timing: distant noises every 25–70 s by day and 14–40 s at full night (interpolated by the night amount), 2–6 m beyond the lot edge in a random direction, weighted by day towards the scrape and the siren and at night towards the shriek, rarely the same twice in a row. Day wind and night bed cross-fade with equal power over about 1.5 s; the tension drone fades in and out on the same time constant and stops when silent.

## 4. Replacing sounds (creators)

1. Find the logical name in §3, for example `impact/wood`.
2. Save your file as `custom/audio/impact/wood.ogg` in the project folder, or next to an exported Windows/Linux game in `<game folder>/custom/audio/impact/wood.ogg`. The folder structure mirrors the logical name.
3. Restart the game. Overrides are read once per session (no hot reload).

- **Variants:** replace them one by one (`custom/audio/player/footstep_1.ogg` … `_4`). A group always plays its numbered files.
- **Loops:** an override of a looping template (`ambient/wind_day`, `ambient/night`, `ambient/tension`, `music/menu`) is looped automatically. Make your file seamless (the end must flow into the start); a WAV's own loop points are kept if it has them.
- **If there is no override file,** the template plays, with no warning. **If it can't be decoded** (corrupt, empty, wrong content for its extension), the game prints a warning naming the file and plays the template; it never crashes.
- `custom/` belongs to you: the game and its tools never write there.

### Supported formats

| Format | Extension | Notes |
|---|---|---|
| Ogg Vorbis | `.ogg` | Preferred. Checked first. Any sample rate and channel count Godot accepts. |
| WAV (uncompressed PCM) | `.wav` | Godot 4.7 loads WAV at runtime (`AudioStreamWAV.load_from_file`, verified at runtime through `ClassDB`), so it's accepted. If both `.ogg` and `.wav` exist, the `.ogg` wins. Tested with 8-bit and 16-bit PCM. |
| MP3, FLAC, Opus, others | — | Ignored (not part of the override contract in `assets/README.md`). |

### Loudness guidelines

Match the templates so the mix stays balanced (the in-game volume per name is set in `Sfx.DEFS`, on top of the file's level):

- **Peaks:** below −1 dBFS (sample peak); leave headroom for inter-sample peaks after encoding.
- **Active RMS** (RMS over the part of the sound within 20 dB of its loudest 50 ms):

| Category | Target active RMS | Notes |
|---|---|---|
| Gunshot | about −14 dBFS | Heavily limited crack, the loudest one-shot |
| Impacts, doors, building, enemy sounds | −16 to −22 dBFS | Heavy events (door bash, structure break) at the loud end |
| Player sounds | −19 to −24 dBFS | Hurt and death louder; eat, drink, bandage, sleep softer |
| Footsteps | about −27 dBFS | They repeat constantly: keep them soft and dull (little above 3 kHz) |
| UI | −24 dBFS (click) to −31 dBFS (hover) | Short and soft |
| Stingers | −17 (invasion) to −21 dBFS (dawn) | |
| Distant noises | about −20 dBFS in the file | 3D distance and the fog filter make them quieter in game |
| Ambience beds | −28 to −33 dBFS, about −28 to −33 LUFS | Background; they play continuously |
| Music | about −24 dBFS, about −23 LUFS | |

- Use **mono** for anything positional (stereo files are folded to mono by 3D playback anyway); stereo is fine for beds, stingers and music.
- Keep energy below 40 Hz low and avoid DC offset; trim silence at the start of one-shots (a late start feels like lag).

## 5. Template sounds: how they were made

`tools/audio/make_sounds.py` (Python 3 + numpy, no scipy; ffmpeg with libvorbis) synthesises every sound from scratch; no recordings or sample libraries are used. `tools/audio/dsp.py` holds the toolkit: exact biquad responses applied in the frequency domain, resonator banks (modal synthesis for wood, metal, glass and doors), granular debris, stick-slip friction for creaks, a source-filter voice (jittery glottal source + breath + vocal fry through moving formants) for the vocal sounds, stiff-string additive synthesis for the piano-like notes, synthetic room responses, and a look-ahead limiter.

- **Normalisation:** each sound is high-passed at 22 Hz, scaled to its category's active RMS target, and limited to −1.5 dBFS (at most 6 dB of limiting; 9 dB for the gunshots and the bomber's blast). After encoding, the file is decoded again and re-encoded quieter if the decoded peak exceeds −1 dBFS.
- **Seamless loops:** the loops are built from exactly periodic parts (noise generated in the frequency domain over the loop length, periodic gust and swell envelopes, tones with a whole number of cycles, events and reverb tails wrapped around the end), so before encoding the end flows into the start to within −70 dBFS or better. Lossy coding then adds its own small error, which is smooth inside the file but not across the wrap-around: the end and the start come from unrelated blocks, so the seam gets a step about the size of Vorbis's local coding noise (−50 to −70 dBFS here; higher quality settings barely change it). To keep that step small, each loop is rotated to start at a quiet, slow point, choosing among 16 candidates by measuring the decoded seam.
- **Encoding:** Ogg Vorbis, quality 4–5 for one-shots, 3 for music and distant noises, 2 for the noise beds. 44.1 kHz; mono one-shots, stereo beds, stingers and music. Every `.import` file sets `loop` (true for the four loops).

Regenerate and re-check:

```
python3 tools/audio/make_sounds.py            # all, or list logical names
godot --headless --path . --import
python3 tools/audio/analyze.py [--png DIR] [--check]
```

## 6. Analysis

`tools/audio/analyze.py` decodes each file with ffmpeg (what a player would hear) and measures it: sample peak; true peak (4× band-limited oversampling); active RMS; a BS.1770-style gated loudness (K-weighting, 400 ms blocks; a short sound counts as one block, so its figure isn't comparable to a long one's); spectral centroid; the share of energy below 40 Hz and above 8 kHz; and for loops the seam: the second-difference step across the wrap-around in dBFS, the same step relative to the largest normal steps within half a second of the seam ("local" ≤ 1 means it is indistinguishable from the signal's own movement), and the level change between the last and the first half second. `--check` fails if any peak exceeds −1 dBFS, any sample clips, DC offset exceeds 0.002, more than 25 % of the energy is below 40 Hz, a loop changes length, or a loop seam steps by more than 4× the local movement while being less than 30 dB below the loop's own active RMS. Spectrogram images (`--png`) were inspected for every sound.

| Logical name | Dur (s) | Ch | Size (KB) | Peak (dBFS) | True peak (dBTP) | Active RMS (dBFS) | Loudness (LUFS) | Centroid (Hz) | <40 Hz % | >8 kHz % | Loop seam |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| `weapon/handgun_fire` | 0.69 | 1 | 7.9 | -1.2 | -0.9 | -14.4 | -19.7 | 520 | 0.2 | 0.9 | — |
| `weapon/dry_fire` | 0.05 | 1 | 4.7 | -2.0 | -1.9 | -24.3 | -21.9 | 4816 | 0.0 | 12.4 | — |
| `weapon/shotgun_fire` | 1.32 | 1 | 12.1 | -1.4 | -1.1 | -12.6 | -20.1 | 365 | 1.9 | 0.6 | — |
| `weapon/reload` | 0.99 | 1 | 10.9 | -2.2 | -2.2 | -23.9 | -27.7 | 1434 | 0.1 | 0.5 | — |
| `weapon/reload_done` | 0.08 | 1 | 5.0 | -2.0 | -2.0 | -22.8 | -21.0 | 3721 | 0.0 | 5.3 | — |
| `weapon/shell_load` | 0.09 | 1 | 5.0 | -3.5 | -3.5 | -24.0 | -21.7 | 3555 | 0.0 | 4.4 | — |
| `weapon/switch` | 0.30 | 1 | 8.6 | -4.7 | -4.7 | -26.2 | -25.2 | 2018 | 0.0 | 0.3 | — |
| `impact/wood` | 0.27 | 1 | 5.7 | -1.4 | -1.4 | -19.1 | -20.5 | 841 | 0.7 | 0.9 | — |
| `impact/plaster` | 0.77 | 1 | 12.2 | -1.4 | -1.4 | -21.9 | -23.5 | 1776 | 0.3 | 3.4 | — |
| `impact/glass` | 0.83 | 1 | 12.0 | -3.5 | -3.5 | -19.1 | -18.5 | 6010 | 0.0 | 18.6 | — |
| `impact/metal` | 1.30 | 1 | 9.0 | -1.1 | -1.0 | -20.2 | -22.3 | 1140 | 0.1 | 0.3 | — |
| `impact/flesh` | 0.38 | 1 | 6.1 | -5.3 | -5.3 | -18.0 | -23.1 | 167 | 1.6 | 0.0 | — |
| `impact/ground` | 0.32 | 1 | 6.7 | -5.1 | -5.1 | -20.0 | -23.6 | 186 | 1.0 | 0.0 | — |
| `player/footstep_1` | 0.17 | 1 | 4.9 | -10.0 | -10.0 | -27.1 | -26.9 | 596 | 0.0 | 0.0 | — |
| `player/footstep_2` | 0.17 | 1 | 4.9 | -7.9 | -7.9 | -27.2 | -26.0 | 599 | 0.0 | 0.0 | — |
| `player/footstep_3` | 0.17 | 1 | 5.0 | -9.0 | -9.0 | -27.5 | -26.4 | 473 | 0.0 | 0.0 | — |
| `player/footstep_4` | 0.18 | 1 | 5.1 | -7.3 | -7.3 | -27.2 | -26.2 | 706 | 0.0 | 0.0 | — |
| `player/hurt` | 0.34 | 1 | 5.4 | -9.2 | -9.2 | -19.0 | -20.5 | 226 | 0.1 | 0.0 | — |
| `player/eat` | 1.18 | 1 | 11.9 | -7.9 | -7.7 | -23.0 | -31.2 | 885 | 1.1 | 1.1 | — |
| `player/drink` | 1.65 | 1 | 15.0 | -6.5 | -6.5 | -23.1 | -26.8 | 354 | 4.2 | 0.0 | — |
| `player/bandage` | 1.32 | 1 | 13.9 | -5.5 | -5.2 | -23.2 | -22.5 | 4416 | 0.0 | 9.9 | — |
| `player/sleep` | 3.30 | 1 | 14.9 | -9.5 | -9.5 | -24.0 | -24.4 | 494 | 0.0 | 0.0 | — |
| `player/death` | 4.37 | 1 | 24.9 | -1.5 | -1.5 | -18.3 | -21.6 | 145 | 0.5 | 0.0 | — |
| `build/place` | 0.19 | 1 | 5.1 | -1.7 | -1.6 | -19.1 | -20.2 | 424 | 3.2 | 0.2 | — |
| `build/hammer` | 0.54 | 1 | 7.4 | -2.1 | -2.0 | -21.6 | -24.4 | 1239 | 0.0 | 2.0 | — |
| `build/demolish` | 1.47 | 1 | 17.9 | -1.5 | -1.5 | -18.4 | -19.6 | 956 | 0.0 | 0.4 | — |
| `build/invalid` | 0.26 | 1 | 4.2 | -15.1 | -15.1 | -24.9 | -27.2 | 154 | 0.0 | 0.0 | — |
| `build/upgrade` | 0.75 | 1 | 6.4 | -3.2 | -3.2 | -19.0 | -25.3 | 311 | 0.1 | 0.5 | — |
| `door/open` | 0.90 | 1 | 14.8 | -8.0 | -8.0 | -22.1 | -21.0 | 1182 | 0.0 | 0.0 | — |
| `door/close` | 0.53 | 1 | 8.2 | -3.1 | -3.1 | -21.1 | -22.9 | 792 | 0.6 | 0.2 | — |
| `door/bash` | 0.43 | 1 | 7.0 | -2.7 | -2.7 | -16.0 | -19.3 | 522 | 1.0 | 0.1 | — |
| `structure/break` | 2.20 | 1 | 25.6 | -1.6 | -1.5 | -16.7 | -19.3 | 599 | 5.7 | 0.6 | — |
| `structure/crumble` | 1.78 | 1 | 23.0 | -2.5 | -2.3 | -21.0 | -22.6 | 2041 | 1.6 | 5.8 | — |
| `structure/blast` | 2.72 | 1 | 32.0 | -1.3 | -1.2 | -17.6 | -17.1 | 2083 | 0.0 | 2.4 | — |
| `enemy/moan_1` | 2.71 | 1 | 15.5 | -5.7 | -5.7 | -20.0 | -21.1 | 220 | 0.1 | 0.0 | — |
| `enemy/moan_2` | 2.40 | 1 | 17.7 | -5.6 | -5.6 | -20.0 | -21.2 | 222 | 0.1 | 0.0 | — |
| `enemy/attack` | 0.43 | 1 | 6.4 | -6.9 | -6.9 | -17.0 | -18.3 | 310 | 0.0 | 0.0 | — |
| `enemy/hit` | 0.33 | 1 | 5.5 | -8.3 | -8.3 | -17.8 | -19.4 | 211 | 0.3 | 0.0 | — |
| `enemy/death` | 2.44 | 1 | 16.2 | -1.3 | -1.3 | -18.1 | -20.4 | 205 | 0.5 | 0.0 | — |
| `enemy/bomber_fuse` | 0.13 | 1 | 4.5 | -13.5 | -13.5 | -19.8 | -18.5 | 2334 | 0.0 | 0.1 | — |
| `enemy/bomber_blast` | 3.80 | 1 | 30.3 | -1.4 | -1.4 | -13.1 | -16.2 | 229 | 0.2 | 0.1 | — |
| `ambient/wind_day` | 48.00 | 2 | 532.1 | -11.7 | -11.7 | -30.1 | -28.0 | 1176 | 2.0 | 4.9 | step -69 dBFS (6.7x local), level 0.3 dB |
| `ambient/night` | 52.00 | 2 | 458.9 | -14.6 | -14.6 | -33.1 | -32.2 | 124 | 2.8 | 0.0 | step -78 dBFS (0.5x local), level 1.3 dB |
| `ambient/tension` | 24.00 | 2 | 103.3 | -16.0 | -16.0 | -28.1 | -28.7 | 73 | 0.3 | 0.0 | step -69 dBFS (1.9x local), level 0.4 dB |
| `ambient/distant_1` | 4.90 | 1 | 35.5 | -5.1 | -5.1 | -20.0 | -19.9 | 982 | 0.0 | 0.0 | — |
| `ambient/distant_2` | 3.44 | 1 | 14.5 | -7.6 | -7.6 | -20.0 | -20.5 | 949 | 0.0 | 0.0 | — |
| `ambient/distant_3` | 11.12 | 1 | 34.3 | -5.4 | -5.4 | -20.0 | -20.4 | 497 | 0.0 | 0.0 | — |
| `ui/click` | 0.08 | 1 | 4.3 | -2.9 | -2.8 | -24.0 | -21.3 | 1063 | 0.1 | 0.0 | — |
| `ui/hover` | 0.05 | 1 | 4.3 | -15.2 | -15.2 | -31.4 | -28.8 | 2495 | 0.0 | 0.0 | — |
| `ui/open` | 0.37 | 1 | 6.5 | -15.6 | -15.6 | -27.0 | -28.3 | 725 | 0.0 | 0.1 | — |
| `ui/close` | 0.35 | 1 | 6.2 | -15.2 | -15.2 | -27.0 | -28.4 | 731 | 0.0 | 0.2 | — |
| `ui/error` | 0.30 | 1 | 4.9 | -13.6 | -13.6 | -25.0 | -25.8 | 241 | 0.0 | 0.0 | — |
| `stinger/invasion` | 8.76 | 2 | 73.0 | -1.3 | -1.3 | -17.4 | -17.1 | 158 | 0.2 | 0.1 | — |
| `stinger/dawn` | 7.40 | 2 | 51.1 | -8.8 | -8.8 | -21.0 | -18.7 | 241 | 0.0 | 0.0 | — |
| `music/menu` | 72.01 | 2 | 684.3 | -11.1 | -11.1 | -24.0 | -23.0 | 128 | 0.1 | 0.0 | step -67 dBFS (1.0x local), level 0.6 dB |

Total: 55 files, 2473 KB (2.41 MB) (Experiment 003 added eight sounds).

**Results:** `--check` passes. No file clips; every decoded peak is at or below −1 dBFS; no DC offset; the sub-40 Hz share is small everywhere; all loops keep their exact length through encoding, and every seam step is more than 30 dB below its loop's level. This is a technical check, not a listening test.

## 7. Manual listening checklist (not done yet)

Headless tests can't judge sound (`tests/README.md`), so these need a person with speakers or headphones:

- [ ] **Gunshot:** sharp and punchy, not harsh or "spitty"; the tail suggests a room. Nine shots in a row don't fatigue.
- [ ] **Footsteps:** soft and dull, not clicky; the four variants are similar enough that none sticks out.
- [ ] **Impacts:** wood, plaster, glass, metal, flesh and ground are told apart without seeing the hit.
- [ ] **Enemies:** the moans are unsettling, not cartoonish and not comic; two psychos moaning at once don't sound like a choir.
- [ ] **Loops:** no click or bump at the loop point of `ambient/wind_day` (48 s), `ambient/night` (52 s), `ambient/tension` (24 s) and `music/menu` (72 s); the night's dog and creaks don't become annoying on repetition.
- [ ] **Distant noises:** come from the direction of the fog and sound far away; the siren reads as a siren that dies.
- [ ] **Music:** the piano-like notes don't sound cheap; the drone isn't boomy on small speakers.
- [ ] **UI:** clicks and hovers are subtle at default volume.
- [ ] **Mix:** gunshot > impacts > footsteps; ambience sits under everything; the settings sliders affect the right sounds.

## 8. Limitations and known issues

- **Not auditioned.** All judgements about character ("splintery", "unsettling", "sad") describe the design intent and the spectra, not a listening test. The enemy voices and the piano-like music are the riskiest; a person should listen before the sounds are judged.
- **Synthetic character.** Physical modelling this simple can sound "clean" or toy-like next to recordings; the designs avoid pure tones where possible (noise excitation, jitter, detuning, rooms), but it remains a template set.
- **Headless tests use Godot's dummy audio driver:** they prove streams decode, players start on the right buses and positions, caps and cooldowns work and loops are flagged, but not what comes out of a speaker.
- **The listener assumption:** the auto-listener follows the current camera's look point at 1 m height. A scene with a different camera style should turn it off and place its own `AudioListener3D`.
- **Sounds tied to the scene:** gameplay one-shots stop when their scene is freed (by design). UI and music persist.
- **Loop seams after Vorbis:** a residual step at the loop point the size of the codec's own noise (see §5) is unavoidable with a lossy format; it was measured in files decoded by ffmpeg, not in Godot's own playback (Godot loops an Ogg stream by seeking back to the start, which should produce the same samples). Whether it is audible was not tested by ear.
- **Override checks** are only "exists, right signature, decodes, has a length, can start playback". Loudness, length and channel count of user files are not checked (that would need approval, per `assets/README.md`). WAV overrides without their own loop points are looped over the whole file.
- **Exported-game verification of overrides is pending:** no export was approved, so overrides were tested with an injected override root, not next to a real exported executable.
