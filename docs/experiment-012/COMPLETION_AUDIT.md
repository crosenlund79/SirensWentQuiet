# Experiment 012 — Completion audit

This audit checks every requirement in the user's Experiment 012 message (recorded section by section in `ASSIGNMENT.md`) against the integrated branch `exp012/the-world-is-watching`. The audit and final integration are dated 2026-11-28.

**Statuses:**
- **COMPLETE:** implemented and functionally verified in the running game, by a test that boots the real game scene or by screenshots.
- **PARTIAL:** some of the requirement is still missing; the notes say what.
- **MISSING:** not implemented.
- **BLOCKED:** cannot be completed now, for the reason given.

**Where the evidence is:**
- Tests are in `tests/e12/` and are named in each row. The lead re-ran them on the integrated branch.
- Screenshots were taken from the game and looked at; the report lists them.
- "Lead" marks something the lead verified or fixed during integration.

**A note on the first pass:** it was interrupted by an API spending limit. All seven areas were then resumed, finished and integrated.

## Part I — Chapter One "Someone Is Watching"

| # | Requirement | Status | Evidence | Notes |
|---|---|---|---|---|
| 2.1 | Four escalating encounters | COMPLETE | `src/story/`; `test_story::test_every_encounter_runs_and_returns_control` | The Visitor, The Observer, The Warning, The Last Courtesy |
| 2.2 | Each has staging, progression state and a clean return to play | COMPLETE | Same test: no modal left, input and HUD back, stage cleared, no story audio, screen faded in | |
| 2.3 | Spread over a meaningful period, not four nights in a row | COMPLETE | `test_story::test_state_defaults_save_and_scheduling` | Encounter 1 is eligible from day 2–3; the later gaps are +3–6, +5–9 and +7–12 days |
| 2.4 | The first comes early; later ones after longer, randomised gaps | COMPLETE | Same test checks the ranges | |
| 2.5 | Only under suitable sleep and home conditions | COMPLETE | `story_director.gd` `takes_sleep`; `test_story::test_sleep_hook` | Encounters 1, 3 and 4 need Eli asleep in his bed at home at night. Encounter 2 needs him awake at home at dusk with no enemies near |
| 2.6 | Normal survival continues between encounters | COMPLETE | The director only takes nights when an encounter is due | |
| 2.7 | Progress persists across save and load | COMPLETE | `test_story` save round trip | **Lead:** an Experiment 011 save loads with a fresh chapter and re-saves |
| 3.1 | The Visitor: Eli wakes at night in his own bed | COMPLETE | `shot2_gas.png`; the in-game sleep hook | |
| 3.2 | The room is almost black | COMPLETE | Same screenshot | Lamps are put out and restored afterwards |
| 3.3 | Blankets over the windows | COMPLETE | Same screenshot | Temporary props |
| 3.4 | The door is closed and locked | COMPLETE | `shot4_door.png` | A temporary prop door; a player-built door is only hidden |
| 3.5 | Silence, then knocking | COMPLETE | `test_story` | The knock reuses the user's door-bash recording at −17 dB, because no knock recording exists (listed in the audio report) |
| 3.6 | The voice lines with pauses and heavy breathing | COMPLETE | `story_lines.gd`; `STORY.md` | From the user's recordings, with subtitles |
| 3.7 | Green gas, disorientation, blackout | COMPLETE | `shot2_gas.png` | |
| 3.8 | Waking shaken, with the four thought fragments; control returns | COMPLETE | `test_story` | |
| 3.9 | Construction and the save are never changed | COMPLETE | `test_story::test_previews_change_nothing` | |
| 3.10 | Postponed if the sleeping place can't be staged safely | PARTIAL | `takes_sleep` | It never runs during an invasion or with enemies near. The bed is fixed in the house plan, so there is no other "unsafe bed" check |
| 4.1 | The Observer: a motionless man outside who just watches | COMPLETE | `shot4_observer.png` | The Exp 011 rig in stillness and observe |
| 4.2 | Recognisably different from the psychos | COMPLETE | Same screenshot | No tics, a dark coat; not an enemy |
| 4.3 | Darkness, distance and subtle sound | COMPLETE | `test_story` | One distant howl or bark |
| 4.4 | Never vanishes in plain sight; walks away calmly when approached | COMPLETE | `test_story::test_watcher_walks_away` | **Lead:** he is drawn only when Eli can see him under the fog of war, and counts as seen only then |
| 4.5 | Dialogue only from matching recordings | COMPLETE | The "Comfortable" recording | |
| 4.6 | Eli's thoughts | COMPLETE | `test_story` | |
| 5.1 | The Warning: more background activity (barking, howling, breathing, metal) | COMPLETE | `test_story`; `StoryAudio` soundscape | |
| 5.2 | His seven composed lines | PARTIAL (needs recordings) | `story/architect_warning_01..07` slots and subtitles | **Blocked on the user:** none of the seven lines is recorded. They play as subtitles, and a recording placed in `custom/audio/story/` plays automatically. No voice is synthesised, as the assignment requires |
| 5.3 | No boss fight; it ends cleanly | COMPLETE | `shot2_warning.png` | It ends on the user's recorded "Well, I think that's enough for tonight." |
| 6.1 | The Last Courtesy: Eli bound in his bed, dark room, covered window, closed door | COMPLETE | `shot4_door.png`, `shot_bound.png` | |
| 6.2 | Dense, chaotic follower sound from many places | COMPLETE | `test_story` | Up to 9 at once, spatial |
| 6.3 | Violent impacts on the door; the door visibly shakes | COMPLETE | `test_story` counts at least 8 jolts | The motion only shows in the running game, not in a still |
| 6.4 | His speech | COMPLETE | `story_lines.gd` | The final recording, split into 8 timed cues |
| 6.5 | Complete silence at "I've asked them to leave you alone." | COMPLETE | `test_story` checks it | |
| 6.6 | Blackout; Eli isn't killed and the bedroom isn't damaged | COMPLETE | `test_story` | |
| 7.1 | Eli wakes tied, alone; a short scripted escape with no button mashing | COMPLETE | `shot_bound.png`; `test_story` | |
| 7.2 | Exactly four ropes as real inventory items | COMPLETE | `test_story::test_ropes` | A new "Rope" item with an icon |
| 7.3 | Keep or Burn choice | COMPLETE | `test_story` | A non-blocking card that comes back after loading until answered |
| 7.4 | Burn: the thoughts, the walk to the fireplace, the throw, the burning, exactly four removed | COMPLETE | `test_story` (7 held → 3 left); `shot4_burn.png` | |
| 7.5 | No fireplace or the fire is out: he keeps them | COMPLETE | `test_story` | |
| 7.6 | Unreachable fireplace: no impossible pathfinding | COMPLETE (by code) | `story_ropes.gd` | Refused when there is no nav path or he is on another floor; not tested on its own |
| 7.7 | Full inventory: nothing lost | COMPLETE | `test_story` | The extra ropes go in a pile by the bed |
| 7.8 | No duplicates or losses across save and load | COMPLETE | `test_story` | |
| 7.9 | An interrupted scene restores a safe state | COMPLETE | `test_story::test_leaving_mid_scene` | |
| 8.1 | He never appears before the story introduces him | COMPLETE | `test_architect`; `StoryState.architect_introduced` | The siege's watcher only appears after Encounter 1 |
| 8.2 | Never in the main menu, random spawns, POIs, hordes, notifications or enemy lists | COMPLETE | `test_architect` (director, roster, name scan) | |
| 8.3 | His recordings never in ordinary psycho pools | COMPLETE | `test_audio_leak` (6 tests, incl. an export-style listing) | |
| 8.4 | The main-menu leak found and fixed | COMPLETE | `docs/audio/AUDIO_REQUIREMENTS.md`; `menu_audio_log_export.txt` (32 s of an exported menu: 0 story plays) | **Root cause:** the inbox matched files word by word, so "heavy breathing" and "banging" went to `door/bash`, the bat recording to `build/hammer`, and "Wakey wakey … enemy" with the `voice/` folder to `enemy/moan`. The menu siege plays those pools. Now guarded at scan time and at play time |
| 8.5 | Story audio stops on menu return, on loading and when a scene ends | COMPLETE | `test_audio_leak::test_story_audio_stops_on_menu_and_load`; `test_story` | **Lead:** fixed the stop count where the two guards met |
| 8.6 | F10 and the showroom may show him | COMPLETE | F10 → Enemies "Internal (development only)"; Story tab | |
| 8.7 | The name never appears in player-facing text | COMPLETE | `test_architect::test_name_stays_internal` | **Lead:** removed the name from two code comments the scan caught |

## Part II — Coordinated sieges and hordes

| # | Requirement | Status | Evidence | Notes |
|---|---|---|---|---|
| 9.1 | Sieges are purposeful and noticeably different from hordes | COMPLETE | `src/siege/`; `test_siege`; `siege_markers.png` | |
| 9.2 | The Architect never attacks; he only directs or watches | COMPLETE | `test_siege` | The "SiegeWatcher" stands in the fog and isn't in the roster |
| 9.3 | Approach from several directions (encircle) | COMPLETE | `test_siege` | 3–4 groups on different sides gather, then push together |
| 9.4 | Pressure different entrances; exploit weak points (breach) | COMPLETE | Headless run "Breach at the wall" | Uses the walls' real weak points |
| 9.5 | Block the escape paths (contain) | COMPLETE | `siege_markers.png` | Posts outside the outer doors |
| 9.6 | Force Eli into an inner room and surround its exits (trap) | COMPLETE | `test_siege`; trap log | |
| 9.7 | A mix of runners and brutes (pressure) | COMPLETE | Headless logs | Runners attack in waves; not covered by a test |
| 9.8 | Physical, destructible barricades | COMPLETE | `test_siege` (save, reload, shot, destroyed); `enemy_barricade.png` | Built from the build system's wooden barricade, only in empty doorways, never touching the player's construction |
| 9.9 | No magical knowledge of where Eli is | PARTIAL | `siege_director.gd` perception | Tactics use the last-known position and the entrances actually seen. Members already engaging use the base chase, which reads Eli's real position |
| 9.10 | Counterplay exists; never an automatic loss | COMPLETE | All physical; dawn ends it | |
| 9.11 | Survivable with good defences | PARTIAL | Bot test | A standing bot in an undefended house died to sieges and to plain hordes of the same size. **Lead:** a siege now uses this invasion's budget, minimum 6. Needs human playtesting |
| 9.12 | Only eligible after Encounter 4, after a delay | COMPLETE | `StoryState.siege_eligible`; `test_siege` | 1–3 days after Encounter 4, then 4–7 days apart |
| 9.13 | F10 can start a siege at once | COMPLETE | F10 → Enemies "Coordinated siege now"; `test_siege` | |
| 10.1 | The whole group exists from the start | COMPLETE | `test_siege::test_e12_wave_exists_at_once_and_a_kill_spawns_nobody`; `horde_night.png` | Normal invasions and sieges |
| 10.2 | Different start points and distances (roads, woods, gardens) | COMPLETE | Same test | |
| 10.3 | Each moves on its own; arrivals vary | COMPLETE | Same test | Start delays per group |
| 10.4 | A kill never spawns another | COMPLETE | Same test | |
| 10.5 | Nothing appears in front of Eli | COMPLETE | Same test (camera frustum) | |
| 10.6 | Distant enemies stay cheap | COMPLETE | `InvasionDirector.throttle` | Not profiled |

## Part III — Enemies

| # | Requirement | Status | Evidence | Notes |
|---|---|---|---|---|
| 11.1 | A visible reaction on seeing Eli | COMPLETE | `test_enemies`; `scream.png` | |
| 11.2 | A shout or scream | COMPLETE | `EnemyReaction` | Uses the user's "Enemy - Vocal" recordings until a shout or scream is recorded (slots `psycho/shout` and `psycho/scream` are ready) |
| 11.3 | Runs at Eli aggressively | COMPLETE | `test_enemies` | A brief charge speed-up; the EnemyDefs speeds are unchanged |
| 11.4 | Shouts are real noise events heard by others | COMPLETE | `test_enemies::test_a_shout_draws_listeners_who_only_hunt_on_sight` | |
| 11.5 | Listeners go to an approximate origin and chase only on sight | COMPLETE | Same test | |
| 11.6 | Per-archetype reactions (runner, brute, psycho, bomber, Architect) | COMPLETE | `test_enemies` | The bomber keeps its own behaviour; the Architect isn't an enemy |
| 12.1 | First and last names from large pools | COMPLETE | `human_names.gd` | 160 male, 160 female, 180 surnames |
| 12.2 | Kept through save and load | COMPLETE | `test_enemies` | Derived from the saved appearance seed; corpses store the name too |
| 12.3 | No duplicate full names in one encounter | COMPLETE | `test_enemies` (14 different names) | |
| 12.4 | The Architect excluded | COMPLETE | | |
| 13.1 | "Name — Kind — Downed" toast | COMPLETE | `toast.png`; `test_enemies` | |
| 13.2 | Not modal and not covering the screen | COMPLETE | The existing toast stack | Merged during hordes. **Lead:** removed a duplicate bomber toast |
| 14.1 | Bodies stay and are searchable | COMPLETE | `corpses.png` | |
| 14.2 | Persist through leaving and returning to a POI, and save/load | COMPLETE | `test_enemies` (home save, POI record) | A full in-game travel round trip wasn't run; the same record is used |
| 14.3 | A fully looted body may be cleaned up | COMPLETE | | |
| 14.4 | No AI, animation or physics after settling | COMPLETE | `Corpse` | |
| 14.5 | Archetype loot from existing items; not every body | COMPLETE | `test_enemies` (200 rolls) | There is no "work gloves" item, so a vest stands in |
| 14.6 | Appearance influences loot | COMPLETE | `Corpse.BIAS` | |
| 25c | Full-inventory rules apply to bodies | COMPLETE | `test_enemies` | **Lead:** searching a body no longer falls back to a door sound |

## Part IV — Visibility

| # | Requirement | Status | Evidence | Notes |
|---|---|---|---|---|
| 15.1 | Undiscovered areas: dark, dense fog hides buildings | COMPLETE | `3_poi_half_explored.png`; `test_visibility` | |
| 15.2 | Discovered but not visible: darkened memory | COMPLETE | `2_enemy_wall_fow.png` | Darkened toward slate grey; only partly desaturated |
| 15.3 | Visible areas render normally | COMPLETE | Pixel comparison with the fog of war on and off | |
| 15.4 | A remembered house doesn't show its current occupants | COMPLETE | `test_visibility` | |
| 15.5 | Discovered areas are saved (home and per POI) | COMPLETE | `test_visibility` (round trip, POI memory) | |
| 16.1 | No enemies through walls | COMPLETE | `test_visibility`; screenshots 2 and 2b | |
| 16.2 | Objects in unexplored rooms are hidden | COMPLETE | `test_visibility` (POI items) | |
| 16.3 | Out of view means gone from view, with no last-seen ghost | COMPLETE | `test_visibility` | |
| 16.4 | Hearing is not seeing | COMPLETE | `test_visibility` (hidden enemies keep simulating) | |
| 16.5 | Corpses and the watchers obey it | COMPLETE | **Lead** wiring: `fow_remember` and `fow_dynamic` groups | |
| 17.1 | A vision cone that follows where Eli looks | COMPLETE | `test_visibility` | 120°, 24 m, plus a 1.75 m all-round ring |
| 17.2 | Enemies behind him are unseen | COMPLETE | Same test | |
| 17.3 | A subtle proximity cue for very close enemies | COMPLETE | `5_proximity_cue.png`; test | A visual edge pulse only; no sound, since no recording exists |
| 17.4 | Never through walls or between floors | COMPLETE | Test | |
| 17.5 | Cached and throttled | COMPLETE | 1.5–7 ms per cast, at most 10 per second | |
| 18.1 | Doors stay visible in cutaways, closed or open | COMPLETE | `4_door_cutaway.png`; test | Shown as a low stub |
| 18.2 | Cutaways reveal nothing | COMPLETE | Sight is computed on the voxel grid | |
| 19.1 | Gradual slowing into the fog boundary | COMPLETE | `test_visibility`; `test_expedition_fog_boundary` | |
| 19.2 | Moving back is immediate; Eli is never trapped | COMPLETE | Same tests | |

## Part V — POIs, travel and looting

| # | Requirement | Status | Evidence | Notes |
|---|---|---|---|---|
| 20.1 | Walking isn't tied to roads; shortcuts across open land | COMPLETE | `test_looting` (e12); `map_foot_route.png` | |
| 20.2 | The car is an off-road 4×4 that avoids buildings, water and impassable ground | COMPLETE | `test_looting` | |
| 20.3 | The route shown is the route and time used | COMPLETE | `test_looting`; travel tests | |
| 21 | A small, battered 4×4 on the map at about half size | COMPLETE | `map_car_4x4.png` | |
| 22.1 | Double walls round crowbar rooms in generated POIs | COMPLETE | `test_looting`; `secured_room.png` | A 0.2 m concrete lining plus the wall, for new sites only |
| 22.2 | No weak adjacent wall | COMPLETE | Test | No windows, a steel door, locked only without an open-plan gap |
| 23 | Kitchen chairs don't block movement | COMPLETE | `test_looting`; `kitchen_island.png` | A 0.68 m walkway |
| 24.1 | Larger, clearer search icons | COMPLETE | `interaction_highlight.png` | |
| 24.2 | A subtle cue for nearby usable things | COMPLETE | Marker rings at POIs (L); **lead** added `NearbyMarks` at home | |
| 24.3 | A stronger highlight and short prompt for the target | COMPLETE | `FocusRing` | |
| 24.4 | No highlights through walls; no flicker | COMPLETE | `test_looting` | |
| 25.1 | Searching never leaves a container stuck | COMPLETE | `test_looting` | **Root cause:** any health drop, such as starving, cancelled every search |
| 25.2 | Partial takes leave the rest; searchable until empty; kept in saves | COMPLETE | `test_looting` | |
| 26 | Fixed-size, scrolling loot and storage windows | COMPLETE | `test_looting` (0, 3 and 40 items); `loot_empty.png` / `loot_full.png` | |
| 27 | Compact item rows; descriptions on hover or focus; tooltips don't resize | COMPLETE | `item_tooltip.png`; tests | |
| 28 | A "Mostly searched" marker at 80 %, informational only, saved | COMPLETE | `test_looting` | |

## Part VI — Characters and lighting

| # | Requirement | Status | Evidence | Notes |
|---|---|---|---|---|
| 29.1 | No detached or floating limbs; root cause found | COMPLETE | `test_characters` (stress run, 0 broken frames) | **Root cause:** shoulder tics and the runner's hitch added to the arm offsets every frame without ever resetting. Now every bone is reset to rest each frame |
| 29.2 | Checked on psychos, runners, brutes and bombers | COMPLETE | Same test; `horde_night_ultra.png` | |
| 30.1 | No orange geometry through Eli's clothing; root cause found | COMPLETE | Voxel-overlap analysis; `clipping_before_after.png` | **Root cause:** the neck and collar meshes overlapped under a bowed head. The visible difference is subtle; the evidence is mostly the measurement |
| 30.2 | Other humanoids checked | PARTIAL | Same narrowing applied | Small collar overlaps remain at close range |
| 31.1 | One flashlight beam controlled by the equipment | COMPLETE | `test_characters` | **Cause:** the old gun light shone by itself every night |
| 31.2 | Checked on a new game, equip, unequip, switching, scene change and save/load | COMPLETE | Test and probe | |
| 31.3 | The beam follows the aim; night visibility stays separate | COMPLETE | `after_night_flashlight.png` | |

## Part VII — Graphics and performance

| # | Requirement | Status | Evidence | Notes |
|---|---|---|---|---|
| 32.1 | Low, Medium, High and Ultra presets | COMPLETE | Probe table in the report; Settings row | |
| 32.2 | Gameplay visibility is never hidden | COMPLETE | `horde_night_low.png` | |
| 32.3 | The choice persists | COMPLETE | Test | |
| 33.1 | A frame-rate display toggle | COMPLETE | Settings, F3, F10 → Debug | **Lead** wired the F10 toggle |
| 33.2 | Stutter from look building | COMPLETE | Measured: stalls of 1.3–15 s became 4–29 ms | Stand-in looks with an urgent swap |
| 33.3 | Other stutter | PARTIAL | | Some unattributed 50–180 ms frames on the overloaded build machine; shader warm-up not investigated |
| 34 | A modern UI font | COMPLETE | `menu_inter.png` | Inter (SIL OFL 1.1) |

## Part VIII — Audio

| # | Requirement | Status | Evidence | Notes |
|---|---|---|---|---|
| 35.1 | The user's recordings are used; nothing generated | COMPLETE | `story_audio.gd` | All 4 voice files and all 19 follower files |
| 35.2 | Natural, irregular use of the variants | COMPLETE | `StoryAudio` scheduler | |
| 36.1 | Encounter 1 almost silent | COMPLETE | | |
| 36.2 | Encounter 2 distant and barely audible | COMPLETE | | |
| 36.3 | Encounter 3 more activity | COMPLETE | | |
| 36.4 | Encounter 4 dense, with controlled silences | COMPLETE | | |
| 36.5 | Spatial sound, ducking, cleanup | COMPLETE | `test_story` | |
| 37.1 | Door jolts on each bat impact, at the recordings' real impact times | COMPLETE | `door_impacts.json`; `test_story` checks every stored impact against the recording | |
| 37.2 | Handle and hinge rattle; the door stays closed and undamaged; timing editable | COMPLETE | | |
| 38.1 | `docs/audio/AUDIO_REQUIREMENTS.md`: A missing recordings (prompt, length, loop, trigger, priority) | COMPLETE | The file | |
| 38.2 | B missing triggers | COMPLETE | The file | |
| 38.3 | C incorrect triggers | COMPLETE | The file | |
| 38.4 | D working sounds | COMPLETE | The file | |
| 38.5 | Obvious missing triggers connected | COMPLETE | `test_audio_leak::test_connected_triggers` | Enemy blows on wood, wooden breaches, indoor enemy steps |

## Part IX — F10

| # | Requirement | Status | Evidence | Notes |
|---|---|---|---|---|
| 39.1 | Tabs: Story, Player, World, Enemies, Building, POIs, Audio, Debug | COMPLETE | `test_dev_menu_tabs`; `f10_*.png` | |
| 39.2 | Every old control kept | COMPLETE | The test finds all 135 old buttons | |
| 39.3 | Compact, modern and scrollable; F10 opens and closes | COMPLETE | | Inter |
| 40.1 | Story tab: the chapter and its four encounters, with the state | COMPLETE | `test_story`; Story tab | |
| 40.2 | Preview (no progression) and Trigger (saved) per encounter | COMPLETE | `test_story::test_previews_change_nothing` | |
| 40.3 | Reset Chapter | COMPLETE | Story tab | |
| 40.4 | First-siege trigger | COMPLETE | "First siege eligible now" plus Enemies → "Coordinated siege now" | |
| 40.5 | Encounter 4 testable at once | COMPLETE | Trigger 4 works from a new game | |
| 41 | Enemies tab: spawns, invasion, horde, siege, AI debugging; the internal figure clearly labelled | COMPLETE | Enemies tab (E, G and A sections) | |
| 42 | Audio tab: voice previews, follower categories and variants, door test, intensity, silence, playing now | COMPLETE | Audio tab (A and S sections) | |
| 43 | Debug tab: FPS, frame time, render info, errors, existing tools | COMPLETE | Debug tab (A, V and C sections) | |

## Part X — Integration (§44) and smoke checks (§46)

| Check | Status | Evidence |
|---|---|---|
| The fog of war never reveals psychos; screams give only approximate threat | COMPLETE | `test_visibility`, `test_enemies` |
| Named enemies keep their names as corpses | COMPLETE | `test_enemies` |
| Corpse loot uses the fixed-size window | COMPLETE | `poi.png`, `search.png` |
| Sieges use whole-group spawning | COMPLETE | `test_siege` |
| He stays hidden before the story; his voice never reaches menus | COMPLETE | `test_architect`, `test_audio_leak` |
| The cinematic door never damages the house | COMPLETE | `test_story` |
| The ropes respect inventory capacity | COMPLETE | `test_story` |
| F10 replays scenes safely | COMPLETE | `test_story` previews |
| New models don't break in hordes | COMPLETE | `test_characters` stress run |
| The project launches | COMPLETE | Headless boot of the menu and the game |
| An existing save loads | COMPLETE | **Lead:** a save written by the `playtest/exp011` build loads with Continue and re-saves |
| Move, scavenge, fight, return home | COMPLETE | Full suite on the integrated branch: 672 passed, 1 failed (a test expectation, fixed), 1 skipped |
| All four encounters from F10, with control returning | COMPLETE | `test_story` |
| Story state survives saving | COMPLETE | `test_story` |
| A siege starts and can be survived | PARTIAL | It starts (`test_siege`); survivability needs a human |
| Several enemies attack at once | COMPLETE | `test_siege` |
| Corpse looting | COMPLETE | `test_enemies` |
| No duplicate flashlight | COMPLETE | `test_characters` |
| Characters intact | COMPLETE | `test_characters` |
| No story audio in menus | COMPLETE | `test_audio_leak`; exported-menu log |
| The Windows build starts | BLOCKED | There is no Windows machine here; the build itself is from GitHub Actions — BUILD |

## Unresolved items

1. **The Warning's seven lines** (§5.2) have no recordings and play as subtitles. Prompts and slots are listed in `docs/audio/AUDIO_REQUIREMENTS.md`.
2. **Siege survivability** (§9.11) is untested by a human, and the attackers' final chase uses Eli's real position (§9.9).
3. **Stutter** beyond look building (§33.3) isn't attributed.
4. **Small collar overlaps** remain on some psychos at close range (§30.2).
5. **The Windows build** can't be started on Windows here.
6. **Missing recordings:** a knock, a psycho shout or scream, a runner shriek and a brute roar. Each has a slot and an ElevenLabs prompt in the audio report.
