# Experiment 012 — The World Is Watching: report

**Branch and checkpoint:**
- Branch: `exp012/the-world-is-watching`, from Experiment 011 (`1ed8ba2`).
- Playtest checkpoint: `playtest/exp012-the-world-is-watching`.
- Not merged into `main`.

**Where the status lives:**
- Every requirement's status, with its evidence, is in `COMPLETION_AUDIT.md`.
- The requirement list is `ASSIGNMENT.md`; the contracts are `SPEC.md`; the story staging is described in `STORY.md`.
- The audio needs are in `docs/audio/AUDIO_REQUIREMENTS.md`.

**How it was built:** seven agents worked in parallel:
- story;
- sieges and hordes;
- enemies;
- visibility;
- characters and rendering;
- looting, POIs and travel;
- audio and F10.

The first pass was cut off by an API spending limit. Every agent was then resumed, finished, and checked in the real game. The lead integrated and fixed the places where the areas met.

## 1. Branch and commit

The checkpoint `playtest/exp012-the-world-is-watching` and the build are at `10fc741`. The branch `exp012/the-world-is-watching` adds only this report's build link on top.

## 2. What is new

- **Chapter One, "Someone Is Watching":** four playable encounters (The Visitor, The Observer, The Warning, The Last Courtesy), the four-ropes aftermath with Keep or Burn, and saved story progress.
- **Hordes:** the whole group exists from the start.
- **Coordinated sieges** after Encounter 4: encircle, breach, contain, trap and pressure, with destructible enemy barricades.
- **Psychos:**
  - they see, scream and charge;
  - their shouts alert others to an approximate spot;
  - they have human names, a "Name — Kind — Downed" toast, and bodies that stay and can be searched, with fitting loot, at home and away.
- **Visibility:**
  - fog of war with three states and remembered areas;
  - real line of sight and a 120° vision cone;
  - a close-range cue;
  - doors kept visible in cutaways;
  - a soft fog boundary.
- **Looting and travel:**
  - walking and the 4×4 can leave the road, and the time shown is the time used;
  - a small battered 4×4 on the map;
  - double-walled locked rooms;
  - a clear kitchen walkway;
  - larger icons, a target ring and a faint nearby cue;
  - searching with a full pack;
  - fixed-size scrolling windows with compact rows and hover descriptions;
  - "Mostly searched" places on the map.
- **Characters and graphics:**
  - no limbs drifting apart;
  - less neck clipping;
  - one flashlight beam;
  - Low, Medium, High and Ultra presets;
  - a frame-rate display;
  - no more long look-building freezes;
  - the Inter UI font.
- **Audio:**
  - the main-menu leak of the Architect recordings is fixed and guarded;
  - all 23 of the user's recordings are used in escalating soundscapes;
  - door jolts are timed to the recorded bat impacts;
  - the audio requirements report.
- **F10:** eight tabs (Story, Player, World, Enemies, Building, POIs, Audio, Debug) with every old control kept.

## 3. Status of the requests

`COMPLETION_AUDIT.md` lists every requirement as COMPLETE, PARTIAL, MISSING or BLOCKED.

**Summary:** no requirement is MISSING. These are PARTIAL:
- §3.10: the bed's "unsafe" check;
- §5.2: the Warning's lines have no recordings and play as subtitles;
- §9.9: the final chase uses Eli's real position;
- §9.11: siege survivability, which needs a human playtest;
- §30.2: small collar overlaps on some psychos;
- §33.3: stutter outside look building.

BLOCKED: starting the Windows build on Windows, since there is no Windows machine here.

## 4. Encounters and triggers

| # | Encounter | Natural trigger | F10 (Story tab) |
|---|---|---|---|
| 1 | The Visitor | Eligible from 20:00 on day 2 or 3. Eli asleep in his bed at home; the night window is 00:40–04:00 | Preview / Trigger |
| 2 | The Observer | 3–6 days later. Eli awake at home, 19:00–23:45, no enemies near. Rescheduled if nobody saw him | Preview / Trigger |
| 3 | The Warning | 5–9 days later, asleep in bed | Preview / Trigger |
| 4 | The Last Courtesy | 7–12 days later, asleep in bed; ends with the ropes | Preview / Trigger |

**Rules for every encounter:**
- None ever starts during an invasion or with enemies near.
- Esc skips a scene to its end.
- Preview changes nothing; Trigger saves progress.
- "Next one eligible now", "First siege eligible now" and "Reset Chapter" are on the same tab.

## 5. Story saving

- **Format:** stored as `"story"` (`ch1`: done, next, next_at, rope, siege_at, sieges, pile).
- **Old saves:** start the chapter fresh. An Experiment 011 save was loaded with Continue and re-saved.
- **Scenes:** night scenes run in the game's sleeping mode, so there are no saves mid-scene and the clock stands still. Changes are written only when a scene ends.

## 6. Sieges

**Timing:**
- The first is eligible 1–3 days after Encounter 4, then every 4–7 days. One replaces the invasion at its normal slot.
- F10 → Enemies → "Coordinated siege now".

**Tactics:**
- **Encircle:** 3–4 groups on different sides.
- **Breach:** the weakest entrance seen.
- **Contain:** posts outside the doors.
- **Trap:** when Eli is in an inner room they go to its doorways, and one builds a wooden barricade.
- **Pressure:** runners attack in waves.

**Barricades:** they are the build system's wooden barricade. Bullets, blows, blasts and demolition destroy them. They are saved with the house and never touch the player's construction.

**The Architect:** he may stand watching in the fog, but only after Encounter 1, and never attacks.

**Size:** this invasion's budget, at least 6.

## 7. Visibility

- **The pass:** a full-screen fog-of-war pass driven by a coarse sight grid cast against the voxel world. It runs at most 10 times a second, and only when Eli moves or turns.
- **What is hidden:** enemies, bodies, the watchers and loose items are shown only when seen. Hearing still works.
- **Memory:** saved at home and per POI.
- **Cost:** a cast takes 1.5–7 ms.

## 8. Enemies and hordes

- **Seeing Eli:** first sight causes a jerk, a scream and a charge that varies by archetype. The scream is a noise event; listeners investigate an approximate spot and chase only once they see him.
- **Hordes:** invasions put the whole wave in at once, in groups from roads, woods and gardens, out of Eli's view. A kill never spawns anyone.
- **Names:** 160 male and 160 female first names, 180 surnames. Unique within an encounter, and kept through saves by the appearance seed.

## 9. Bodies and loot

- **What a body is:** it settles into a static body (no AI, animation or physics).
- **Searching:** through the same windows as containers ("In the pockets").
- **Loot:** follows the archetype and the clothing (a mechanic carries tools, a guard a flashlight and rounds). Existing items only; 20–35 % of bodies are empty.
- **Persistence:** saved at home and in the POI record. A searched-empty body is dropped from the save.

## 10. Character fixes

- **Limbs drifting:** shoulder tics and the runner's shoulder hitch added to the arm offsets every frame and never reset, so arms drifted, worst on runners at 2.2 m after 30 s. Every bone is now reset to rest each frame; the stress test finds 0 broken frames.
- **Eli's neck:** the neck and collar meshes overlapped under the game's bowed head. The neck is now tucked inside an open collar.
- **Flashlight:** the old gun light shone by itself every night. It is off in the game, and the hand-held flashlight is the only beam.

## 11. Graphics and performance

- **Presets:** each one sets the render scale, anti-aliasing, shadow distance, lamp shadows, SSAO and glow, snow density and view distance. Gameplay visibility is never reduced.
- **Frame rate:** shown via Settings, F3 or F10 → Debug.
- **Look building:**
  - **Before:** a spawn waiting for its look could stall 1.3–15 s.
  - **After:** a spawn takes 4–29 ms, wearing a ready stand-in look of its archetype until its own is built.
- **Font:** Inter (SIL OFL 1.1).

## 12. F10 tabs

| Tab | Contents |
|---|---|
| Story | The chapter, Preview and Trigger ×4, rope burning, skip, eligibility, reset |
| Player | Cheats, supplies, needs, car and quick bar, character, research |
| World | Time, difficulty, home, comfort, noise |
| Enemies | Threats and waves, reactions and bodies, hordes and sieges, the internal figure |
| Building | Levels, house, structure, furniture, balance, defences, security, overview |
| POIs | Missions, POI, travel, the generator, looting and routes |
| Audio | Layers, inbox, playing now, voice previews, follower categories and variants, door test, intensity, silence |
| Debug | FPS and frame time, render info, errors, fog of war and vision, quality presets, the stress test, flashlight, look cache |

## 13. Audio integrated

**The user's recordings:**
- The 4 voice files ("Wakey wakey sunshine", "Comfortable", "Random on encounter", "The final encounter before confrontation"). Cue spans and subtitles are in `story_lines.gd`.
- The 19 follower files: bark ×4, howl ×4, breathing ×3, bins ×4, bat on the door ×4. Impact times are in `door_impacts.json`.

**Newly connected:** the user's "Enemy - Heavy impact wood" and "Destruction - Wooden Wall" recordings now play when enemies strike or breach wood.

## 14. Audio requirements report

`docs/audio/AUDIO_REQUIREMENTS.md` has four sections:
- **A:** missing recordings, with ElevenLabs prompts, lengths, loop or one-shot, triggers and priorities;
- **B:** missing triggers;
- **C:** incorrect triggers;
- **D:** working sounds.

## 15. Known limitations

**Missing recordings:**
- The Warning's seven lines have no recordings, so they are subtitles only.
- There is no recording for the knock, psycho shouts and screams, a runner shriek or a brute roar. The existing vocals and door bash stand in.

**Sieges:**
- Survivability is untested by a human. The siege bot died to sieges and to hordes of the same size.
- Attackers already engaging use the chase's real view of Eli.

**Looks:**
- A newly spawned person can change look about 1–2 s after appearing (a stand-in look). This usually happens before it is in view.

**Visibility:**
- Remembered areas are darkened toward grey rather than fully desaturated.
- The Low preset drops lamp shadows, so light leaks through walls.

**Story staging:**
- During story scenes the "Level 0" chip stays on screen.
- The door's motion shows only in the running game.

**Before playtesting:**
- Invasions are noticeably harder now that whole groups arrive at once.
- Many trips are about 5 minutes shorter thanks to shortcuts.

## 16. Windows build

GitHub Actions run 11 succeeded for `playtest/exp012-the-world-is-watching` (`10fc741`). Artifact `SirensWentQuiet-windows-10fc741…` (an 85 MB portable win-x64 ZIP with the EXE and all resources, kept until 2026-12-28): https://github.com/crosenlund79/SirensWentQuiet/actions/runs/46098273712/artifacts/15244386250 (run page: https://github.com/crosenlund79/SirensWentQuiet/actions/runs/46098273712). It wasn't started on Windows by Claude: there is no Windows machine here.

## Screenshots (`shots/`)

| File | What it shows |
|---|---|
| `f10_story.jpg` | The integrated game: the F10 Story tab, Inter, fog of war, the target ring |
| `visitor_gas.jpg` | The Visitor: dark bedroom, blankets, green gas, "Night nighty." |
| `observer.jpg` | The Observer at the lot edge at dusk |
| `last_courtesy.jpg` | The Last Courtesy: bound in bed, "I've asked them to leave you alone." |
| `ropes_bound.jpg` | The morning after: the four ropes |
| `horde_night.jpg` | A whole horde arriving from several sides |
| `siege_markers.jpg` | A siege with its tactic markers (staged at the rally spots) |
| `enemy_barricade.jpg` | An enemy barricade in the bedroom doorway (placed by the capture tool) |
| `corpses.jpg` | Bodies at night with "[E] Search Russell Henderson" |
| `downed_toast.jpg` | "Wayne Thatcher - Brute - Downed" |
| `fow_enemy_wall.jpg` | Fog of war: the enemy behind the wall hidden, the one in view shown |
| `fow_poi.jpg` | A half-explored hospital |
| `map_route.jpg` | A cross-country route on the map |
| `loot_window.jpg` | The fixed-size loot window |
| `flashlight.jpg` | One flashlight beam at night |
| `settings_graphics.jpg` | The Graphics presets and the frame-rate option |

## Verification

**Full suite** on the integrated branch: 672 passed, 1 failed, 1 skipped.
- The failure was a test expectation exposed by the new Rope item (spending from an empty stock). The game is unchanged and the test was fixed.
- The skip is a stand-in-look case that no longer happens because every bomber look is already built.

**New tests** in `tests/e12/`: story, siege, enemies, visibility, characters, looting, audio leak, dev-menu tabs.

**Lead's checks:**
- An Experiment 011 save loads and re-saves.
- The integrated game shows the routed F10 Story tab, the Inter font, the fog of war and the target ring (`shots/f10_story.jpg`).
