# Experiment 003 — Foundations of Survival: report

**Status:** integrated and published as a playtest checkpoint (2026-11-24).
- **Baseline:** Experiment 002 at `4c87cd6`.
- **Working branch:** `claude/practical-heisenberg-mjc1xx`.
- **Checkpoint branch:** `playtest/exp003-integrated`. It points at `3f80fa3`.

Not human-played. No real-GPU timing (software Vulkan only). Sounds measured, not listened to. Not merged to `main`; no export.

## What was built

| System | Module (owner) | Doc |
|---|---|---|
| Equipment: six slots with real effects (vest -35 % damage, backpack ×1.5 carry, flashlight and crowbar gates). Weapons: handgun and shotgun with magazines, reloading (shell by shell), fire rate, pellets, range, switching. Scrap → iron crafting | `src/survival/equipment.gd`, `crafting.gd`, `src/combat/` (K) | `equipment.md` |
| Construction materials: stone wall, stone foundation, iron barricade, reinforced door, workbench, iron plating, repair by material. Blast damage (`explode`), ranked weak points, world save v2 with v1 loading | `src/world/`, `src/build/` (C) | `construction.md` |
| Reusable enemy AI: psycho, runner (seeks openings), brute (3 strikes a swing), suicide bomber (goes for weak defences, telegraphed fuse, persistent breach). Threat-budget invasion director. Progress-based stuck rule | `src/ai/`, `src/game/enemy_roster.gd`, `invasion_director.gd`, `src/common/pursuit_brain.gd` (AI) | `ai.md` |
| Scavenging: 24 data-driven places in 5 categories, 4 approaches, depletion and recovery, lasting consequences, discovery | `src/expedition/` (X), `src/region/` (lead + X) | `scavenging.md` |
| Region map: a voxel miniature with terrain, river, bay, city and drifting clouds; pins, info panel, planning. Shares `RegionLocations` with the expeditions | `src/map/` (M) | `map.md` |
| Difficulty (Easy / Normal / Hard) | `src/survival/difficulty.gd` (lead + K) | `SPEC.md` §4 |
| Integration: difficulty at New Game, weapon keys and HUD card, equipment tab, bomber alert/marker/blast on the player, map (M and the dining table), one expedition apply path, save schema 2 with schema 1 migration, F10 tools, 8 new sounds | `src/game/`, `src/ui/`, `src/menu/`, `src/save/`, `src/audio/` (I) | `game.md` |

Reused from Experiment 002 without rewrites: the voxel house world and build mode, GameState and survival rules, the fog boundary and expedition screen, the roster and director, the HUD, menus and dev menu, `Sfx` and the asset resolver, `SaveGame` (safe writes, checksum, backup).

## Tests

- **Full headless suite:** 385 passed, 0 failed, run on the merged working branch (`godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd`). It was 367 at the end of Phase A and 23 test groups at the start of Experiment 002.
- **New focused tests:** `tests/game/test_game_wiring.gd` (11), the equipment, weapons, construction materials, blast, AI archetypes, director, scavenging, region and map tests in the module folders, and save migration with a real Experiment 002 save (`tests/save/fixtures/exp002_save_v1.dat`).

## Integrated playtest (ASSIGNMENT §13)

One reported run in two processes under Xvfb with software Vulkan, with real input and a real application restart:
- **Part 1:** 15 passed, 4 failed.
- **Part 2:** 6 of 6 passed.

Step-by-step results are in `game.md` §12 and `screenshots/i_playtest_run2.txt`.
- **Passed:**
  - difficulty, equipment and weapon switching;
  - building with wood, stone and iron;
  - the map (zoom, pan, clouds, selection, planning);
  - a targeted quarry trip whose stone built a wall;
  - a clinic trip, sleep, psycho and brute fights, repair, save and quit;
  - after the restart, the house, inventory, equipment, magazines, difficulty, region map and position were all identical.
- **Failed:**
  - **14:** the events drawn offered no gear-dependent choice, though the clinic's flashlight requirement worked.
  - **16:** the runner was not seen entering through the open back door.
  - **17–18:** no bomber spawned, because the F10 panel overflowed the screen. Fixed afterwards and not re-run, by the user's instruction to stop long automated playthroughs. The bomber flow in the real game scene is covered by a headless test.

## Screenshots (`screenshots/`)

- **City map:**
  - `a_m01_region_overview.jpg`, `i_06_map_overview.jpg`
  - `i_06b_map_clouds_20s_later.jpg` (the clouds moved)
  - `i_06c_map_zoom_bay_docks.jpg`
  - `i_07_map_quarry_info_targeted.jpg`
- **Enemies:**
  - `a_01_lineup.jpg` (the four archetypes)
  - `a_07_bomber_fuse.jpg` and `a_08_bomber_hole.jpg` (the bomber's fuse at a wall, then the breach; AI's preview scene on the real house)
  - `a_09_wave_hard_4.jpg`
  - `i_12a_psycho.jpg`, `i_12b_runner_through_the_open_door.jpg` (the runner at the closed front door), `i_12c_brute_bashing.jpg`
- **Construction:**
  - `a_c_materials.jpg`
  - `i_05_construction_stone_ghost.jpg`, `i_05b_built_wood_stone_iron.jpg`, `i_09_stone_wall_from_the_quarry.jpg`
  - `a_c_blast_after.jpg`
  - `i_14a_repair_mode.jpg`, `i_14b_repaired.jpg`
- **UI and flow:**
  - `i_01b_new_game_difficulty.jpg`, `i_03b_inventory_equipment.jpg`
  - `i_04c_hud_weapons.jpg`, `i_04b_shotgun_fired.jpg`
  - `i_08*` (expedition), `i_17_continued.jpg`, `i_18_map_after_restart.jpg`

`a_*` are module captures from Phase A preview scenes; `i_*` are from the integrated game.

## Known bugs and limitations

- **Not re-run since the fix:** the in-game bomber, live on screen.
- **Runner:** it was not seen using an open door in the integrated run, though the headless test passes.
- **Event options:** gear-dependent choices depend on the random event draw.
- **Map:**
  - Pin clicks were unreliable in automation; list entries work.
  - The map pauses the world, so planning takes no game time.
- **HUD:**
  - The weapon card text is dense.
  - In build mode the dimmed status card shows a doubled text shadow.
- **Construction:** no collapse simulation. Blasts cost 40–140 ms in GDScript.
- **Balance:** a first pass from simulations.
- **Assets:** the shotgun, workbench and map table are placeholders, by the asset policy.
- **Software renderer:** under it, an animated overlay costs about 1 s per frame, which slows the automated playtest. This doesn't represent a gaming PC.
- **Per-module limits:** see each module doc and `docs/BACKLOG.md`.

## Deferred

- **Playtest:**
  - a re-run of steps 16–18 with a captured bomber blast;
  - a deterministic step 14.
- **Experiment 004 (approved by the user and to be done in a fresh session):** see `docs/HANDOFF_EXP004.md`.
