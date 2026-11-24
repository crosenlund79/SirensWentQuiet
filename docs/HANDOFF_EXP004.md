# Handoff: Experiment 003 → Experiment 004

**Written:** 2026-11-24, at the end of the session that built Experiments 001–003.

- **The game state:** Experiment 003 ("Foundations of Survival") is integrated and published for playtesting.
- **Next milestone:** Experiment 004 ("A House to Live In") was approved by the user's directive of 2026-11-24 and is to be done in a **fresh session**. Nothing of Experiment 004 is implemented here.

The suggestions in §6 are Claude proposals, not approvals; the user's directive defines the scope.

## 1. Where things are

| What | Where |
|---|---|
| **Playtest checkpoint** (frozen, never commit to it) | branch `playtest/exp003-integrated` at `3f80fa3` |
| Development branch (continue here or on a new working branch) | `claude/practical-heisenberg-mjc1xx` |
| Experiment 002 baseline | `4c87cd6` |
| Experiment 003 report | `docs/experiment-003/REPORT.md` (plus the module docs in that folder) |
| Rules | `CLAUDE.md`, `docs/GODOT_CLAUDE_GUIDELINES.md`, `docs/PROJECT_BRIEF.md`, `docs/DESIGN_WORKFLOW.md` |
| Deferred observations | `docs/BACKLOG.md` |

**Branches on GitHub:** `main`, the working branch and `playtest/exp003-integrated`. That is three, the guideline's limit. The directive of 2026-11-24 explicitly allows more `playtest/...` checkpoint branches. Never force-push or rewrite them. Nothing is merged to `main`.

## 2. Launch the checkpoint

1. **Get the project:** on GitHub, switch to the branch `playtest/exp003-integrated`, then Code → Download ZIP (or check the branch out with GitHub Desktop).
2. **Install Godot:** 4.7 (developed with 4.7.2 stable, standard build, Forward+).
3. **Open the project:** open `project.godot` in Godot. The first open imports the assets, which takes about a minute. Press **F5**.
   - Alternatively, from the project folder: `godot --path .`
4. **Start a game:** main menu → New Game → pick Easy, Normal or Hard.
   - Controls are in the README and on H / F1 in game.
   - F10 is the developer menu.

No executable was built; exports aren't approved.

## 3. What is implemented (and where)

| System | Files | Notes |
|---|---|---|
| Game root and flows | `src/game/survival_game.gd` (about 1,070 lines: modal state, clock, flows, debug API); helpers `game_combat.gd`, `game_map.gd`, `game_dev.gd`, `game_input.gd`, `interaction_finder.gd`, `run_save.gd`, `enemy_roster.gd`, `invasion_director.gd` | `docs/experiment-003/game.md`, `docs/experiment-002/game.md` |
| Survival state | `src/survival/game_state.gd` (clock, needs, inventory, equipment, magazines, difficulty, region, cheats; `to_dict`/`from_dict`), `survival_tuning.gd`, `difficulty.gd`, `equipment.gd`, `crafting.gd`, `items.gd` | `survival.md`, `equipment.md` |
| Weapons | `src/combat/weapon_defs.gd`, `weapon_handler.gd` (signals `fired`, `empty`, `reload_*`, `switched`) | `equipment.md` |
| House world | `src/world/house_world.gd` (about 2,000 lines), `world_object.gd` (doors, barricades, crates, collectors, workbench), `bed_interactable.gd` | `docs/experiment-002/world.md`, `construction.md` |
| Voxels | `src/voxel/` (grid, mesher, chunks, carver, fx, lighting, house builder `voxel_house.gd`, yard and roof `voxel_yard.gd`) | `docs/experiment-001/voxel.md` |
| Building | `src/build/build_mode.gd`, `build_pieces.gd`, `build_palette.gd`, `workbench.gd` | `construction.md` |
| Enemy AI | `src/ai/` (`ai_enemy.gd` extends `VoxelEnemy`; behaviours; `enemy_defs.gd`; `weighted_nav.gd`), `src/common/pursuit_brain.gd`, `grid_nav.gd` | `ai.md` |
| Scavenging | `src/expedition/` (`expedition_data.gd`, `expedition_run.gd`, `expedition_screen.gd`, `fog_boundary.gd`), `src/region/region_locations.gd` (the 24 places), `region_state.gd` | `scavenging.md` |
| Region map | `src/map/` (`RegionMapScreen`) | `map.md` |
| UI | `src/ui/` (HUD, inventory/equipment, pause, settings, dev menu, dialogs), `src/menu/main_menu.gd` | `docs/experiment-002/ui.md`, `game.md` |
| Audio | `src/audio/sfx.gd` (static `Sfx`), `ambience.gd`; templates in `assets/audio/`; `tools/audio/` | `docs/experiment-002/audio.md` |
| Save | `src/save/save_game.gd` (schema 2, schema 1 migration, temp → verify → `.bak`), `src/game/run_save.gd` | `survival.md`, `game.md` §8 |
| Asset overrides | `src/common/asset_resolver.gd` (`custom/` over `template_`) | `assets/README.md` |

**No Autoloads.** The static classes are `GameLaunch`, `GameSettings`, `AssetResolver` and `Sfx`.

**Physics layers:**

| Layer | Use |
|---|---|
| 1 | Environment |
| 2 | Walls |
| 3 | Player |
| 4 | Enemies |
| 5 | Low obstacles |
| 6 | Lot boundary |

## 4. Architecture facts that matter for a three-floor house

These are the load-bearing assumptions to plan around:

1. **One floor plan, as constants.**
   - `src/common/house_plan.gd` (`HousePlan`) is a static class of `const` data: `FOOTPRINT`, `ROOMS`, `WALLS`, `OPENINGS`, `FURNITURE`, `PROPS`, `LIGHTS`, `PLAYER_START`, `SPAWN_POINTS`, `YARD`.
   - It is read directly by about 15 source files: voxel house, yard, lighting, furniture, props, house world, grid nav, fog boundary, invasion director, enemy spawner, bomber, AI preview, and the Experiment 001 demos.
   - It is also read by 14 test files, including `tests/test_versions_smoke.gd` and `tests/common/test_house_plan.gd`.
   - A second house needs the plan to become selectable, or the new house to be built beside it. The Experiment 001 demos and the old house must keep working; the directive asks to preserve the previous house.
2. **One voxel grid.**
   - `HouseWorld` owns one `VoxelGrid` for the whole lot: 0.1 m storage, 0.2 m damage quantum, `design` vs current `grid`.
   - It also owns a sections registry, objects, scorch marks and one `GridNav`.
   - Its save is a diff against the pristine house, tagged with `LAYOUT := "swq-house-1"`. A new house must use a new layout id, and old saves need a rule: keep the old house, or refuse with a message.
3. **Everything stands at y = 0.**
   - The player: `src/voxel/voxel_player.gd:80`.
   - Enemies: `voxel_enemy.gd:110`, `ai_enemy.gd:204`.
   - `RunSave` stores the player as `[x, z]` and loads it at y = 0 (`run_save.gd:58`).
   - Floors need a per-body floor height and a saved floor index, as an optional field or a new schema.
4. **Navigation is one 2D layer.** `GridNav` uses 0.25 m cells; `PursuitBrain` and `WeightedNav` run on it. The directive allows ground-floor-only enemies and construction for the first checkpoint. Enemies on other floors would need one nav per floor plus a stair rule.
5. **Aiming and shooting.**
   - `world.aim_ray(camera ray)` picks the aim point against the voxel grid (`survival_game.gd:329`).
   - `HouseWorld.shoot` ray-marches the grid.
   - Both assume the single grid.
6. **The view.**
   - `HouseWorld.update_view(player_pos, camera, delta)` cuts a cylinder between the camera and the player in the voxel shader (`cut_materials`), and hides tall props in it.
   - `VoxelYard.update_roof` dissolves the flat roof while the player is inside.
   - These are the existing hooks for room visibility and the overview. The roof is a single mesh (`yard.roof`).
7. **Interactables.**
   - `world.interactables()` returns the bed and objects with a prompt.
   - The game merges its own: the map table in `game_map.gd`, and the fog boundary.
   - `interaction_finder.gd` picks the nearest. Stairs fit here as one more interactable.
8. **Night threats already distinguish ordinary nights from horde nights.**
   - `InvasionDirector.straggler_at()` gives a lone straggler from Day 2 (35 %, 23:00–03:00) on non-invasion nights.
   - `begin_wave()` builds the invasion from the threat budget.
   - The directive asks not to redesign it.
9. **Hooks for noise events:**
   - gunfire: `WeaponHandler.fired`;
   - explosions: `HouseWorld.explode` and the roster's `detonated`;
   - building, repair and demolish: the actions in `BuildMode`;
   - crafting: `Workbench`.
   - The roster spawns and holds the live enemies (`enemy_roster.gd`), so pointing nearby stragglers at a sound fits there.
10. **Developer menu.** `src/ui/dev_menu.gd` builds the buttons. Methods resolve on `game.dev` (`game_dev.gd`) or the game root. It already has time, needs, supplies, ammunition, each enemy type, waves and repair all. It lacks floor teleport and noise events.

## 5. Known limitations at the checkpoint

From `docs/experiment-003/REPORT.md`:
- **Not played by a human:**
  - no real-GPU timing;
  - sounds were measured, not auditioned;
  - balance is a first pass.
- **The bomber:** its blast was never captured in the running game. Its flow is tested headless, and AI's preview captures show the fuse and the breach.
- **The runner:** it was not seen using an open door in the integrated run.
- **Map:**
  - Pin clicks were unreliable in automation.
  - The map pauses the world.
  - The map table is a placeholder.
- **HUD:** the weapon card is dense; the build-mode status card shows a doubled shadow.
- **Menu music:** it doesn't start on the very first launch. This dates from Experiment 002: `Sfx.music` is called while the root is still adding the main scene. It plays after returning from a game.
- **Construction:**
  - no collapse simulation;
  - blasts cost 40–140 ms in GDScript;
  - a 12 m wall run costs about 90 ms.
- **Automated playtest speed:** the full playtest (`tools/survival_playtest.sh`) takes about an hour under software Vulkan in this container. The user asked not to repeat long automated playthroughs. Prefer the headless suite plus a short smoke check.

## 6. Suggestions for Experiment 004 (proposals only)

- **Reuse, don't rewrite:**
  - GameState, survival rules, WeaponHandler and the roster/director;
  - expeditions, the map and the save pipeline;
  - BuildMode, HouseWorld's destruction and repair, the dev menu, `Sfx` and the HUD.
- **Smallest path to a first house checkpoint** (consistent with the directive's "a simple stair interaction is acceptable"):
  - Make the floor plan selectable (the classic plan stays the default for the demos and old saves).
  - Give the new house its own layout id.
  - Keep the ground floor as the full `HouseWorld`, with destruction, building and enemies.
  - Add the basement and upstairs as separate, lighter floor nodes at their real heights, with walls, floor, furniture and their interactables (beds, workbench, storage). Use stair interactables with a fade to move between floors.
  - Store the player's floor in the save.
  - Hide the floors above the player.
  - Enemies stay on the ground floor at first; document what they do while the player is elsewhere.
- **Visibility:**
  - room-level rules: show the current room and rooms reachable through open doorways or breaches; hide the contents of closed-off rooms;
  - update on events: room change, door toggled, structure changed (`HouseWorld.structure_changed`);
  - per-floor show and hide; never pause hidden simulation.
- **Noise:**
  - one small module mapping action → base level, with modifiers for room, floor and enclosure (from the room plan and whether its exterior walls are breached);
  - emit from the hooks in §4.9;
  - let the roster steer existing nearby stragglers to the sound; no spawning.
- **Overview:**
  - a modal view: the camera pulled out, furniture, enemies and the player hidden by visibility layers;
  - roof on or off, the cutaway and a 2D blueprint drawn from the grid's columns with damage colours, per floor;
  - rendered only while open.
- **Testing:** one main workflow, headless tests for new pure logic, the existing suite, a short smoke launch. Publish `playtest/...` branches at each playable stage.

## 7. Working conventions in this repo

- **Tests:** `godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd [-- --filter=text]`.
  - The runner fails a test on any GDScript runtime error and on scripts that don't compile.
  - `--filter` matches a test file's base name or method, not its folder.
- **Rendering checks (Xvfb + lavapipe):** `tools/capture.sh` with `CAPTURE_ENGINE_ARGS="--fixed-fps 30"`.
  - Under lavapipe any HUD or canvas change forces a full 3D redraw (about 1 s per frame).
  - The playtest hides the HUD between screenshots for that reason.
- **Files in `custom/` belong to the user:** never modify them. Don't integrate SirenVoxelLibrary assets unless the user says so. That directive was revoked for this project's sessions.
- **No model identifiers** in commits, code or docs.
- **Each commit message ends with the session's attribution lines,** as given by the harness.
