# Experiment 003 — Integration: one game (Phase B, I)

Owner: I. Code: `src/game/` (the game root and its helpers), `src/ui/`, `src/menu/`, `src/save/`, `src/audio/`; the sounds in `assets/audio/` and `tools/audio/`; the acceptance playtest `tools/survival_playtest.*`. Tests: `tests/game/`, `tests/ui/`, `tests/save/`, `tests/audio/`. Contract: SPEC-003 §7. This extends `docs/experiment-002/game.md` and `ui.md`, which still describe everything not changed here.

The five Phase A modules (equipment and weapons, construction, enemy AI, scavenging, the region map) are wired into the one game the main menu starts. Nothing is a parallel copy: the game calls each module's own API, and the developer menu uses the same calls.

## 1. Where the wiring lives

`survival_game.gd` still decides *when* things happen (its modal state, the clock, the flows). Experiment 003's *how* sits in three small helpers next to it, created in `_assemble()`:

| Helper | File | Owns |
|---|---|---|
| Combat | `src/game/game_combat.gd` | The `WeaponHandler` (K): firing, R / Q / 1 / 2, the "Out of ammo" / "Reloading" toast. The roster's signals (AI): wall strikes, blows on the player by archetype, the bomber's notice, fuse alert, ground marker and blast on the player with a camera shake. |
| Map | `src/game/game_map.gd` | `RegionMapScreen` (M), created once and prewarmed; the map on the dining table; the plan toast and autosave. |
| Dev | `src/game/game_dev.gd` | The Experiment 003 F10 tools (spawn each type, chosen waves, instant missions, reveal the map, difficulty, fill magazines). |

`survival_game.gd` went from 1,093 to about 1,066 lines: the new calls are offset by removing the foundation-era duck-typing branches (`has_method` fallbacks for `on_dawn`, `roll_straggler`, `can_sleep`, `force_invasion_now`, which GameState has had since Experiment 002).

## 2. New Game and the difficulty

- **Main menu:** New Game (after the overwrite question, if a save exists) opens `DifficultyDialog` (`src/ui/difficulty_dialog.gd`, a `UiModal`): Easy, Normal and Hard as buttons, each with `Difficulty.desc_of` as its one-line description below and the invasion schedule as the button caption ("Invasions from Day 2, every 2 days"). Focus starts on the last choice; Esc or Back returns to the menu.
- The choice goes through `GameLaunch.difficulty` to `GameState.new_run(seed, difficulty)`. Continue ignores it: the run's own difficulty comes from the save.
- **Shown in:** the HUD's clock card ("AFTERNOON · HARD"), the pause menu ("Hard difficulty · Day 3"), the inventory panel's header and the F10 inspect line.
- The roster's defaults follow the run: `sync_roster()` sets `roster.level` and `roster.invasion` after assembly, at the start and end of every invasion and when F10 changes the difficulty.

## 3. Weapons, the HUD and equipment

- **Firing** (LMB) goes through `combat.fire(aim) → WeaponHandler.try_fire`. The game no longer keeps its own interval or dry-click throttle (`_fire_cd`, `_dry_cd`, `DRY_FIRE_INTERVAL` are gone). `debug_fire_at` waits out the weapon's shot interval (`tick(cooldown())`) and then fires through the same path.
- **Keys** (outside build mode and panels): R `reload()`, Q `next()`, 1 `select_slot("primary")`, 2 `select_slot("secondary")`. A refusal is a toast ("No 9 mm rounds left.", "No other weapon equipped."), except "Full." and "Already reloading.". **In build mode** the game leaves these keys alone, so BuildMode's own 1–9, 0 and R (rotate) work as before.
- **`empty`** shows "Out of ammo" when there is no reserve, "Reloading" when the handler has started a reload.
- **HUD weapon card** (bottom right, replaces the ammo card): the weapon's name, `loaded / capacity`, "N spare rounds" or "N spare shells" (or "out of ammo", "empty · R reload", "reloading", "unlimited"), a thin reload bar while reloading, and "Q  Shotgun" for the other equipped weapon. It reads `WeaponHandler.current()` (`hud.set_weapons(handler)`) and redraws only when that changes.
- **Construction resources** in the HUD: one small line under the stat bars, "Wood 20 · Stone 4 · Iron 2". The build palette (C) shows planks, stone, iron, nails and scrap in build mode.
- **Inventory panel** (`I` / Tab): two tabs.
  - *Supplies:* food, water, medical | ammo (9 mm, shells) and materials (planks, nails, scrap, stone, iron with their caps).
  - *Equipment:* the six slots with what is in them and what it does ("Blows and blasts hurt 35 % less", "In hand · 9 mm · magazine 12"), Unequip per slot; on the right the gear groups (weapons, protective, utility, tools), each with Equip / Unequip through `GameState.equip` / `unequip` (the reason is shown when refused), the count column naming the slot, and the magazine of each weapon ("5 / 5 loaded · 5 spare").

## 4. Enemies, waves and the bomber

- **Invasions:** `start_invasion(kinds := [])` calls `director.begin_wave(state.difficulty, state.invasion_index(), seed, kinds)`; `_run_director` spawns `for k in director.tick_kinds(delta): roster.spawn_type(k, director.pick_spawn(...), director.spawn_opts(k))`. Stragglers are psychos scaled for the run (`spawn_type("psycho", at, {level, invasion})`).
- **Wall strikes:** `roster.wall_swing` arrives once per strike (a brute's swing is three) and the game calls `world.enemy_strike(pos, target)` with the default strength, as the AI doc requires.
- **Blows on the player:** `state.damage(state.enemy_damage() * e.damage_scale, e.kind)`; the vest applies inside `GameState.damage`. A brute's hit shakes the camera harder.
- **Bomber:**
  - when one appears (`enemy_spawned` with kind "bomber"): a warning toast;
  - `fuse_started`: a pulsing HUD alert under the banner ("BOMBER AT THE WALL · 3 S") for the fuse's length, and a pulsing orange ring on the ground at the fuse point, drawn through walls;
  - `detonated(at, radius, damage)`: the player takes `EnemyDefs.blast_damage_at(distance, damage, radius)` as cause "blast" (the vest applies), the camera shakes by distance, "Caught in the blast! (-N)" when hurt; the alert and marker go. `combat.last_blast` records it.
  - A bomber shot dead clears its alert and marker; "The bomber is down."
  - Enemies killed by a blast play `enemy/death`.

## 5. Scavenging

- **`apply_expedition_result(result)`** is the one apply path, used by the expedition screen's `finished` (only while the screen is open) and by F10's instant mission: `state.apply_expedition(result)`, then `ExpeditionData.apply_region(state, result)`. Both are once-only by the result id, so a repeated signal changes nothing (tested). `last_expedition.region_applied` records it.
- **The plan:** the expedition screen (X) preselects `state.region.planned` / `planned_purpose` when the player walks into the fog; the map writes them.

## 6. The region map

- Created once in `game_map.gd`; `RegionMapScreen.prewarm()` runs while the game assembles (about a second, once per session; later boots reuse the cache).
- **Opened** with M (`open_map` action) or from the map on the dining table: a folded paper map (a placeholder of a few boxes) with the prompt "[E] Study the region map". The table is a small interactable node from `src/game`, merged into the interaction finder with `world.interactables()`; the world module is untouched.
- **While it is open** the game's modal is "map" and **the world pauses** (like the inventory): the clock, the enemies and the player stop, so movement, firing and building are blocked, and WASD pans the map instead. Decision: pausing is the simplest consistent rule and makes the map a planning screen, not a way to lose time. The game's own 3D view stops rendering (`viewport.disable_3d`) while the map covers the screen, because the map draws its own world; it comes back on close.
- **Closing:** Esc or M close the map (the map handles them in `_input`, so Esc never reaches the pause menu); `closed` restores the game. Opening it from build mode leaves build mode.
- **Planning:** `destination_selected(id, purpose)` shows "Planned: Granite Quarry (Targeted collection: stone)" and autosaves ("plan").

## 7. Sleep

The wake-up toast uses `plan["text"]` from `GameState.plan_sleep` for every reason except the invasion's own line ("You wake to something at the door."). Waking for hunger or thirst ("You wake up parched. You need water.") is a warning, not "something at the door" (tested).

## 8. Save schema 2

- `SaveGame.SCHEMA = 2`, `MIN_SCHEMA = 1`. Same file layout. The state carries the difficulty, equipment, weapons and region (K, X); the world is HouseWorld save version 2 (C).
- **Experiment 002 saves (schema 1) load:** `info()` reports them valid (Continue is offered); `read()` decodes them, returns `migrated_from: 1` and marks the data schema 2 (`SaveGame.migrate`). The contents need no conversion: `GameState.from_dict` migrates a state without equipment and weapons (Normal, the handgun equipped with its magazine filled from the 9 mm rounds up to 12), and `HouseWorld.load_data` takes a version 1 world. The game then **re-saves at once** (autosave "migrated") with a toast, so the file on disk becomes schema 2.
- **Errors stay readable:** schema 0 or 3 ("an older / a newer version of the game"), a header that disagrees with its contents ("its versions disagree"), a missing or broken survival state, a refused house. None crash; the game returns to the menu with the notice.
- **Fixture:** `tests/save/fixtures/exp002_save_v1.dat` was written by the untouched Experiment 002 game (commit `4c87cd6`, extracted with `git archive` into a scratch folder): a new run (seed 2002) played headless to Day 1 12:30 by a small script that ate and drank, added 10 rounds (19 in all), 14 planks, 30 nails and 6 scrap, shot the south wall four times, built a crate and a barricade, stood in the living room and called `SurvivalGame.save_now()`. It holds 15 rounds, 20 planks, 42 nails, 156 missing voxels, a crate and a barricade.

## 9. F10 developer menu

Compact and scrollable as before; every action goes through the real systems. New or changed sections:

| Section | Buttons | Calls |
|---|---|---|
| Supplies | + Food & water, + Medical, + 10 ammo, **+ Shotgun & shells** (shotgun, 10 shells), **Fill magazines**, **+ Vest & gear** (vest, backpack, flashlight, crowbar), + Materials (now 20 planks, 20 stone, 10 iron, 40 nails, 10 scrap), All tools | `state.inventory.add` (gear auto-equips into free slots; owned gear is skipped with `Items.is_unique`); `dev_fill_magazines` → `state.set_magazine` |
| Materials | **+10 planks, +10 stone, +10 iron, +10 scrap** | `state.inventory.add` (caps apply) |
| Difficulty | **Easy, Normal, Hard** | `state.set_difficulty` + `sync_roster` |
| Threats | Next invasion, Repair house, Spawn 1 / 3 psychos (Experiment 002); **+ Psycho, + Runner, + Brute, + Bomber**; **a chosen wave** (click a type to set its count 0–4) and **Start this wave** | `roster.spawn_type(kind, fog point, {level, invasion})`; `state.force_invasion_now()` + `start_invasion(kinds)` → `director.begin_wave(..., kinds)` |
| Map and missions | a place and an approach (drop-downs), **Run mission now**, **Reveal all places** | `ExpeditionRun.simulate(state, id, default_gear, [], approach, "", true)` → `apply_expedition_result`; `state.region.discover_all()` |
| Time | unchanged | |

The dev menu finds the new methods on the game's `dev` helper (`_target(method)`), the Experiment 002 ones on the game root. The inspect panel adds "Enemies by type {…} · wave [...] budget … · difficulty … · map n/24 known · plan …".

## 10. Audio

Eight new template sounds, synthesised with `tools/audio/make_sounds.py` (numpy + ffmpeg/libvorbis, same normalisation and limits), checked with `tools/audio/analyze.py --check` (it passes; its sub-40 Hz rule caught the first version of the blast, which was fixed) and inspected as spectrograms. Not auditioned by ear.

| Name | What | Sfx |
|---|---|---|
| `weapon/shotgun_fire` | a heavier, lower blast, longer room tail, then the pump racked | cd 0.1 s, max 3 |
| `weapon/reload` | magazine released, dropped, a fresh one seated | cd 0.3 s, max 1 |
| `weapon/reload_done` | slide or pump snapping forward | cd 0.1 s, max 1 |
| `weapon/shell_load` | one shell into the tube | cd 0.08 s, max 2 |
| `weapon/switch` | cloth, sling, a handling click | cd 0.15 s, max 1 |
| `enemy/bomber_fuse` | one harsh two-tone beep (the bomber repeats it, faster and faster) | positional, SFX bus, cd 0.15 s, max 2 |
| `enemy/bomber_blast` | the detonation: boom, pressure wave, sizzle, rumble | positional, far, cd 0.3 s, max 2 |
| `structure/blast` | a wall blown apart: crack, timber and stone debris, dust | positional, far, cd 0.2 s, max 2 |

The modules pick them up by themselves (`Sfx.has`). Rows and measurements are in `docs/experiment-002/audio.md`.

## 11. Tests

```
godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd -- --filter=test_game_wiring
godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd -- --filter=test_save_game
godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd -- --filter=test_ui
```

- **`tests/game/test_game_wiring.gd`** (the real game scene): Hard from New Game (start rounds, first invasion day, roster, HUD, pause menu) and Continue keeping it; Easy's full magazine; weapons through the game's input (2, a found shotgun reloading shell by shell, a 6-pellet blast, 1, Q, R with and without a reserve, the HUD card and reload bar; in build mode 2 picks a class and R rotates); a brute's hit = `enemy_damage() × 1.8`; blasts on the player with fall-off and the vest; a real bomber spawned through F10 going for a defence, the HUD alert and ground marker during its fuse, the fall-off damage, the house damaged; the map (M, the world paused and the 3D view off, no shots, no movement, no clock; Esc closes without the pause menu; M closes; M from build mode); the table's prompt, planning, the toast and autosave, the expedition screen preselecting the plan; a result applied to the region once; F10 tools (each type, a chosen wave, reveal, an instant mission, difficulty, magazines, the real menu buttons); the thirst wake-up text; an Experiment 002 save continued and re-saved as schema 2.
- **`tests/game/test_survival_game.gd`** (Experiment 002, updated): the firing test reads the magazine and the handler's results (the unlimited cheat keeps the magazine full); the dev API test compares the wave with `Director.compose`.
- **`tests/save/test_save_game.gd`:** schema 2 with the Experiment 003 state; the Experiment 002 fixture (info, read, migration, RunSave, the house, re-save as schema 2, no second migration); damaged schema 1 files and version mismatches give readable errors.
- **`tests/ui/`:** the difficulty dialog (three levels, descriptions, schedule, focus, Esc, hand-over); the main menu's New Game flow; the HUD's weapon card, reserve wording, materials line, difficulty and alert; the equipment tab (slots, auto-equip, Unequip / Equip, the hammer by hand, stone and iron in Supplies); the dev menu's new buttons reaching the `dev` helper and the new packs.
- **`tests/audio/`:** the eight names resolve to decodable one-shots within the budget.

## 12. The acceptance playtest

`tools/survival_playtest.sh [out dir]` runs `tools/survival_playtest.gd` in two processes under Xvfb with software Vulkan at `--fixed-fps 30` (part 2 after a real application restart). The save goes to `<out>/playtest_save.dat`. Input is real: keys, mouse motion, wheel, drags and clicks on the actual buttons, pins and list entries; F10 actions are real clicks on the dev menu. The debug API reads state; any action through it is named in the step's line. Rendering and the HUD are off between screenshots. Steps follow ASSIGNMENT §13 one to one (1–19 in part 1, 20a–20f in part 2).

### Run 2 (the reported run: the code and playtest of commit `f2c09eb`, before the dev menu fix)

Part 1: **15 passed, 4 failed**. Part 2 (a separate process, Continue from the main menu): **6 passed, 0 failed**. The full step lines are in `docs/experiment-003/screenshots/i_playtest_run2.txt`; the screenshots (JPEG copies of the 1600 × 900 captures) are `docs/experiment-003/screenshots/i_*.jpg`.

| Step | Result | What happened |
|---|---|---|
| 1 New Game with a difficulty | PASS | New Game → the difficulty dialog → Hard; GameState Hard, first invasion Day 2, 9 rounds |
| 2 Wake in the house | PASS | Day 1 07:00 beside the bed; initial save |
| 3 Stats and equipment | PASS | I: Supplies, then the Equipment tab (handgun in the primary slot) |
| 4 Equip and switch weapons | PASS | F10 "+ Shotgun & shells" (auto-equipped); Unequip / Equip in the panel; 2, R (5 shells one by one), LMB (one blast, 6 pellets), 1, LMB (9 → 8), Q, Q |
| 5 Build with wood, stone, iron | PASS | F10 "+ Materials"; B; a 4-tile stone foundation, a 2 m stone wall, a 2 m wooden wall (drags), iron plating on a house wall section |
| 6 Open the map | PASS | F10 "Reveal all places" first (noted); E at the dining table; world paused, 3D view off |
| 7 Explore the map | PASS | wheel ×7 at the harbour (distance 198 → 75), drag pan, A held, H home |
| 8 Clouds move | PASS | 20 s apart: cloud time +20 s (16 world units), the frames differ by 19.8 / 255 on average |
| 9 Select a location | PASS | the quarry (its list entry; the pin click missed), 2 = targeted (stone), Plan expedition → "Planned: Granite Quarry (Targeted collection: stone)", autosave |
| 10 Into the fog | PASS | E at the fog; the screen preselected quarry / targeted / stone |
| 11 Targeted resources | PASS | +14 stone (+1 iron, +1 nails), 272 min; region: 1 visit, stock 0.93, plan used up |
| 12 Use them | PASS | a 2 m stone wall from the quarry's stone (14 → 2) |
| 13 Riskier destination | PASS | the Medical Clinic (High risk on Hard): +3 bandages, +8 rounds, food and water; 337 min |
| 14 Equipment-dependent decisions | **FAIL** | the clinic said "Needs a flashlight" before F10 "+ Vest & gear" and was available after (an equipment-dependent option), but the events drawn on this seed offered no option that needs gear, so no gear choice was made |
| 15 Sleep | PASS | F10 Night 20:00, ×10, ×1; walk to the bed, E, "Sleep until morning": 21:05 → Day 2 06:00, energy 21 → 99 |
| 16 Distinct AI behaviours | **FAIL** | psycho: walked at the player, shot down; brute: 3 wall swings = 9 strikes (3 a swing), 295 voxels bashed out; runner: did not come in through the open back door while watched (it stood at the closed front door, see below) |
| 17 Bomber at a wall | **FAIL** | no bomber spawned: the F10 panel had grown past the right screen edge, so the "+ Bomber" click landed off-screen (fixed afterwards, not re-run) |
| 18 Damage and repair | **FAIL** | follows from 17 (no blast to observe); the repair itself worked: B, 7, LMB repaired 5 damaged sections, 1,111 → 707 missing voxels |
| 19 Save and leave | PASS | M, the police station's pin, 3 (careful), Plan; Esc, Save (schema 2), Main Menu, Save and quit, Quit |
| 20a Continue | PASS | Continue (Day 2 · 07:19) after a real restart |
| 20b House | PASS | the voxel and colour hash, damage, objects, built sections, foundations and plating identical |
| 20c Inventory, equipment, difficulty | PASS | inventory, six equipped items, magazines, the weapon in hand and Hard identical |
| 20d Region map | PASS | 24 places, stock, visits, the plan (police, careful) identical; the map preselects the plan |
| 20e Clock, needs, position | PASS | |
| 20f Weapons after the restart | PASS | 2 → shotgun, 1 → handgun |

The bomber's full behaviour in the real game (F10 spawn → walks to a defence, not the player → HUD alert and ground marker during the fuse → blast with fall-off damage on the player → structural damage) is covered headless by `test_game_wiring::test_a_real_bomber_goes_for_the_house_warns_and_its_blast_hurts_the_player`, and its wall targeting by AI's `test_ai_bomber` tests; it was not captured in this run.

**Software renderer:** under lavapipe every frame with an animated overlay is a full redraw (about 1 s); run 1 spent about ten minutes in the intro overlay, so run 2 skips it with a key after its first second. Run 2's part 1 took about 45 minutes, part 2 a few minutes. No further automated playthrough was run after run 2 (user instruction).

## 13. Fixes outside my paths

- `docs/experiment-002/audio.md`: rows and measurements for the eight new sounds (the sound list lives there).
- No code outside my paths was changed.

## 14. Known issues and limitations

From playtest run 2 (not re-run after the fixes, by instruction):
- **Fixed after run 2:** the F10 panel grew past the right screen edge (4-column grids and wide drop-downs), hiding "+ Bomber" and other fourth-column buttons. It is now two columns, the drop-downs are stacked and the panel grows to the left. The fix passes the suite; it was not re-played.
- **Step 14:** whether an event offers a gear option is random; on this seed the clinic's events had none. The equipment dependency was shown only by the clinic's flashlight requirement.
- **Step 16, the runner:** with the back door open and the front door closed it did not come in through the back door while watched; the screenshot shows it at the closed front door. The playtest's watch also stopped too early (a straight-line distance through the wall; fixed in the script). Afterwards the runner was gone before the fight started (the fight found no threats); the cause was not investigated. AI's headless test of the runner's open-door detour passes.
- **Step 17–18:** no bomber blast was played or captured in the real renderer (see the F10 fix); the headless game test covers it.
- **Map pins:** in step 9 the click on the quarry's pin did not select it (the list entry did); in step 19 the police station's pin click worked.
- **Build mode HUD:** the dimmed status card shows its text shadow as a second, offset copy (Experiment 002 styling at 55 % opacity).
- **HUD weapon card:** "4 / 5  5 SPARE SHELLS" is dense; it reads, but a separator would help.
- **Intro overlay** under the software renderer: about 1 s per frame; the playtest skips it.

Limitations:
- The map table is a placeholder (a paper sheet of boxes), by the asset policy.
- The map pauses the world; planning costs no game time.
- The HUD alert covers one bomber at a time (the latest fuse); each bomber still gets its own ground marker.
- Sounds were measured, not auditioned.
- Software Vulkan only; no real-GPU timing. Not human-played.
