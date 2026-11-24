# Experiment 003 — Foundations of Survival: shared spec and contracts

The user's assignment (recorded in `ASSIGNMENT.md`) is the authority. This file turns it into module boundaries, contracts and numbers. It **extends** Experiment 002 (`docs/experiment-002/SPEC.md` still holds where this file doesn't change it). Rules: `docs/GODOT_CLAUDE_GUIDELINES.md`. Baseline: Experiment 002 delivered at `4c87cd6`.

**Goal:** a systems-first vertical slice, with one or two working examples of each mechanic, all connected and persistent. The loop is **scavenge → obtain resources → equip and build → defend → survive → explore further.** The policy is no new detailed art: reuse existing meshes and procedural visuals, and use simple placeholders for new things. The voxel city map is the exception: it needs an attractive overall landscape, built from simple masses.

## 1. Phases and file ownership

**Phase A (parallel; each agent works in its own worktree and edits only its own paths):**

| Agent | Paths (exclusive) | Delivers |
|---|---|---|
| **K** (kit) | `src/survival/**`, `src/combat/**`, `tests/survival/**`, `tests/combat/**`, `docs/experiment-003/equipment.md` | Equipment slots with real effects, weapons (handgun + shotgun: magazines, reload, fire rate, damage, pellets, ammo types), resources (stone, iron, scrap → iron), difficulty semantics, survival consolidation |
| **C** (construction) | `src/voxel/**`, `src/world/**`, `src/build/**`, `src/props/**`, `tests/voxel/**`, `tests/world/**`, `tests/build/**`, `tests/props/**`, `docs/experiment-003/construction.md` | Stone and iron tiers (walls, a floor or foundation piece, doors, barricades), a workbench (scrap → iron), two or more material strengths, `explode()` and `weak_points()` done properly, sections ready for load-bearing, persistence |
| **AI** (enemies) | `src/ai/**`, `src/common/pursuit_brain.gd`, `src/game/invasion_director.gd`, `src/game/enemy_roster.gd`, `tests/ai/**`, `tests/common/test_pursuit_brain.gd`, `tests/game/test_game_helpers.gd`, `docs/experiment-003/ai.md` | A reusable AI with shared behaviours; the psycho, runner, brute and suicide bomber; difficulty and a threat-budget invasion director |
| **X** (scavenging) | `src/expedition/**`, `src/region/region_state.gd`, `tests/expedition/**`, `tests/region/**`, `docs/experiment-003/scavenging.md` | A data-driven destination framework for all 24 locations; mission approaches; loot profiles; equipment-dependent options; depletion and consequences |
| **M** (map) | `src/map/**`, `tests/map/**`, `docs/experiment-003/map.md` | The interactive voxel city map: terrain, districts, roads, river, bay, forests, buildings, drifting clouds, pan and zoom, selection |
| **Lead** | `project.godot`, `src/region/region_locations.gd`, `src/common/**` (except the brain), `tests/run_tests.gd`, `tests/test_case.gd`, `tests/test_versions_smoke.gd`, this SPEC, `README.md`, `docs/PROJECT_BRIEF.md`, `docs/BACKLOG.md` | Contracts and merging |

**Phase B (after the merge; one agent, I):** `src/game/**` (except AI's two files), `src/ui/**`, `src/menu/**`, `src/save/**`, `tests/game/**`, `tests/ui/**`, `tests/save/**`, and `tools/survival_playtest.*`. Its job is to wire every module into the game: the difficulty choice in New Game, weapon switching and reload, the HUD, an equipment panel, map access, the F10 additions, save schema v2 with migration from v1, and the 20-step acceptance playtest.

**Phase A rule:** don't edit `src/game` (except AI's files) or `src/ui`. Instead, give each module:
- a **standalone preview scene or debug harness** that demonstrates it with the real world where relevant;
- an **"Integration" section** in your doc listing the exact calls the game and UI must make.

Phase B wires those up. Need a change in someone else's path? Put it in your report.

## 2. Equipment, weapons and resources (K)

- **Items** (`Items.DEFS`; the foundation added `stone`, `iron`, `shells`, `handgun`, `shotgun`, `vest`, an item `slot` field and new categories).
  - Categories: weapon, ammo, protective, tool, utility, medical, food, water, material.
  - K may move flashlight and backpack to `utility`.
- **Equipment slots** (`GameState.equipment`, slot → item id): `primary` and `secondary` (weapons), `body` (vest), `back` (backpack), `utility` (flashlight), `tool` (crowbar or hammer).
  - Effects must be real:
    - **vest:** incoming damage −35 %, applied in `GameState.damage` for psychos and blasts;
    - **backpack:** carrying capacity (expedition loot capacity, and material caps when equipped is a K decision; document it);
    - **flashlight:** expedition options and risk;
    - **crowbar:** alternative scavenging options;
    - **hammer:** needed to build.
  - API: `equip(id) -> String` (reason or ""), `unequip(slot)`, `equipped(slot)`, `has_equipped(id)`.
- **Weapons:**
  - definitions in `src/combat/weapon_defs.gd` (`WeaponDefs`):

    | Weapon | Ammo | Magazine | Fire interval | Damage | Pellets | Spread | Range | Reload |
    |---|---|---|---|---|---|---|---|---|
    | handgun | `ammo` (9 mm) | 12 | 0.2 s | 1 | 1 | small | 40 m | 1.4 s |
    | shotgun | `shells` | 5 | 0.9 s | 1 per pellet | 6 | 9° | effective about 14 m | 0.5 s per shell, interruptible |

  - the runtime is `WeaponHandler` (src/combat; a Node): `setup(state, world, player)`, `try_fire(aim_point) -> Dictionary`, `reload()`, `switch_to(id)`, `next()`, `current() -> {id, loaded, reserve, reloading}`, with signals `fired`, `empty`, `reloaded`, `switched`.
  - Firing resolves through `HouseWorld.shoot()`, once per pellet. The magazine state lives in `GameState.weapons` (saved). The unlimited cheat keeps the magazine full.
  - Start: the handgun is owned and equipped as primary, holding the difficulty's `start_rounds` (9 on Normal) and no reserve. Nine bullets still means nine.
  - A visual placeholder for the shotgun is fine (e.g. a longer box on the rig's gun; don't edit `voxel_rig.gd`; attach to the rig's `gun` node at runtime).
- **Resources:** `wood` (planks), `stone`, `iron` and `nails` are usable construction resources. `scrap` is a **raw** material that a workbench turns into iron (3 scrap → 1 iron, one example of processing, no crafting tree). Caps: stone 40 (+20 per crate), iron 20 (+10 per crate).
- **Difficulty** (`src/survival/difficulty.gd`, foundation table). K owns its semantics in the survival core: the start, `GameState.enemy_damage()`, and invasion interval and first day via the schedule. AI and X read it.
- **Survival consolidation** (assignment §4): keep the rates forgiving.
  - Expeditions consume time and needs.
  - Sleep never skips an attack.
  - Food, water and medicine matter.
  - Review for inconsistencies only; no new subsystems.

## 3. Region, locations and scavenging (lead + X)

- **One list:** `src/region/region_locations.gd` (`RegionLocations`, lead) has 24 places with `name`, `category`, `district`, `pos` (region cells, 1 cell = 25 m, region 160 × 120), `size` and `desc`, plus `HOME`, `travel_minutes(id)` and `distance_km(id)`.
  - The map and the expeditions both use this list; never duplicate it.
  - The four Experiment 002 ids are kept (`homes`, `grocery`, `hardware`, `clinic`).
- **X's destination data,** keyed by location id: a **loot profile** (shared profile tables, not per-location code), risk, search duration, relevant equipment, events, and depletion behaviour.
  - Family houses differ by small per-house variations of one residential profile.
  - **Mission approaches:** general scavenging, targeted collection (pick a resource), careful exploration (slower, safer, can discover new locations), high-risk raid (faster, more loot, more danger). The approach and the equipment change the options and outcomes.
  - **Dangerous places** (military outpost, police, hospital, gun shop) are rewarding without guaranteed success. The outpost should demand preparation (e.g. a vest, a shotgun or enough rounds, a flashlight).
  - Travel time comes from `RegionLocations.travel_minutes`, plus the search duration by approach.
  - The departure window rule stays.
  - Loot is scaled by `Difficulty` `loot` and danger by `scavenge_danger`.
  - New items appear in loot: stone, iron, shells, shotgun (rare), vest (rare), and scrap.
- **`RegionState`** (`src/region/region_state.gd`, X owns it after the foundation): discovered locations, `stock` (depletion 0..1 per location), `notes` (consequences), `layout`, and `planned` / `planned_purpose` (the map's selection).
  - Saved inside `GameState.to_dict()["region"]`.
  - Expeditions update it; the map reads it.
- **Result schema:** Experiment 002's, extended additively with `"location"`, `"approach"`, `"stock_after"`, `"discovered"`.

## 4. Construction (C)

- **Resources in costs:** wood, stone, iron and nails.
- **At least two structural material strengths,** e.g. a wood wall (existing) and a stone wall (masonry voxels with high `HARDNESS`), plus iron reinforcement as an upgrade (sheathing now costs iron).
- **One or two examples per class:**
  - walls (wood, stone);
  - floor or foundation (e.g. a stone foundation or floor tile on the lot);
  - doors and openings (wood door, reinforced door, doorway);
  - barricades (wood, iron);
  - storage (crate);
  - functional equipment (rain collector, workbench: scrap → iron);
  - upgrades and repairs (iron sheathing; repair by material).
- **Keep:** grid snapping, previews, wall-run dragging, collision validation, costs, voxel damage, nav updates, persistence, and construction-grid resolution separate from damage resolution.
- **Sections:** store per-section material and strength (`section_info` / `sections`). Add a documented `support` hook (e.g. `section_load_hint(s)`) for a future load-bearing model. No collapse simulation.
- **`HouseWorld.explode(center, radius, power) -> Dictionary`** (foundation version exists): it carves a local sphere, damages objects in range, updates nav and collision, and persists. C makes it robust and gives it a strong, readable effect (flash, debris, dust); the shake is the game's job.
- **`HouseWorld.weak_points(from: Vector2) -> Array`** (foundation version exists) returns doors, barricades and wall sections, scored for a wall-seeking attacker. C refines it, e.g. by preferring a weak wall next to where the player is, and avoiding sheathed or stone sections.

## 5. Enemies, difficulty and invasions (AI)

- **A reusable AI** in `src/ai/`: one body and one shared behaviour core, with archetypes as **data plus small behaviour hooks**, not copies.
  - **Shared behaviours:** target selection (the player, a breach, a defence), navigation (the shared GridNav + PursuitBrain, improved: e.g. a progress-based stuck rule, see the BACKLOG), obstacle recognition, attacking doors, barricades and walls through `world.enemy_strike`, reacting to new breaches (nav revision changes → re-plan), attacking the player, receiving damage, death, and joining a wave.
  - The Experiment 001 voxel demo keeps using `VoxelEnemy` unchanged.
- **Archetypes** (`EnemyDefs`): placeholder visuals by scaling and tinting the voxel rig, plus attached simple meshes (e.g. the bomber's glowing pack).

  | Type | Speed | HP | Behaviour |
  |---|---|---|---|
  | psycho | 1.4 m/s | 3 | Baseline. |
  | runner | about 2.6 m/s | 1–2 | Prefers existing openings (low bash weight willingness; detours to open doors and holes). |
  | brute | about 1.0 m/s | 8 | Heavy wall and barricade damage (e.g. ×3 per swing), knockback-resistant. |
  | **bomber** | about 1.6 m/s | 2 | See below. |

  **The bomber** ignores the player as a target:
  1. It picks `world.weak_points(from)` (a door, barricade or weak wall), paths to it, and stops at it.
  2. It starts a telegraphed fuse of about 2.5 s: a flashing light, a beeping sound (an Sfx name of AI's choice, documented, played via `Sfx`), and an on-screen warning via a signal.
  3. Then `world.explode(...)` runs, and nearby characters, the player included, take damage via a `detonated(at, radius)` signal the game handles.
  4. Killed before detonating, it drops harmlessly (or with a small blast; document the choice).
  5. The player must have a fair chance to see it coming: it is distinct visually and audibly.
- **Difficulty and director:** a reusable `InvasionDirector` builds each wave from a **threat budget** (`Difficulty.threat_budget` + step × (invasion − 1)) and archetype costs (psycho 1, runner 1.5, brute 3, bomber 4), with rules:
  - bombers only from `bomber_from_invasion`, and never early on Easy;
  - specials from `special_from_invasion`;
  - the first waves are small.
  - Enemy hp and damage scale by difficulty.
  - The interval and first day come from `Difficulty`.
  - Keep the Experiment 002 roster and director API working for the game, or document the exact replacement calls.
- **Dev spawning:** every type can be spawned individually through a function the dev menu will call (e.g. `roster.spawn_type(kind, at)`).

## 6. The voxel city map (M)

- **What it is:** a miniature 3D region (`src/map/`), not a playable world. It is coarse voxel terrain (e.g. 160 × 120 columns, matching `RegionLocations.SIZE`) with:
  - rolling hills, the north-west mountains, a river from the mountains to the eastern bay, the coast and harbour, forests in the north;
  - roads connecting every location and HOME;
  - districts (residential, centre, industrial, docks), with simple voxel masses for buildings (taller in the centre), fields in the farmland, and remote facilities.
- **Geography** follows the positions and districts in `RegionLocations` (e.g. the quarry in the foothills, the harbour on the bay).
- **Look:** an atmospheric miniature (soft light, a muted palette, water with a shimmer, fog at the edges). **Drifting clouds** move slowly, with gaps and shadows or tonal variation, and never hide the map's usability.
- **Interaction:**
  - **Screen:** `RegionMapScreen` (CanvasLayer + SubViewport, or its own 3D scene; M decides): `open(state)`, `close()`, signals `closed` and `destination_selected(id, purpose)`.
  - **Navigation:** pan (drag or WASD), zoom (wheel), "find my house".
  - **Location info:** hover or select a location to see its name, category, travel time (`travel_minutes`), risk, potential resources and relevant equipment.
  - **Planning:** choose a mission purpose (approach), then "Plan expedition". This sets `state.region.planned` / `planned_purpose`; leaving still happens by walking into the fog.
  - **Undiscovered** places show as unknown silhouettes or are hidden.
  - **Gameplay text** (risk, resources, equipment, approaches) comes from X's data via a small documented API that X provides (e.g. `ExpeditionData.location_summary(id, state)`). Until X's is merged, M uses a local fallback built from `RegionLocations` only.
- **Persistence:** `RegionState` holds discovery and stock; the map keeps nothing of its own except the camera, which isn't saved. A `layout` id guards against a changed map.

## 7. Save and developer tools (Phase B, I)

- **Save:**
  - `SaveGame.SCHEMA` 2 holds everything in GameState: difficulty, equipment, weapons, region, plus the world (C's persistence version).
  - **v1 saves** (Experiment 002) load with defaults: Normal difficulty; the handgun equipped with its magazine filled from inventory `ammo`, up to 12; the default region. They are re-saved as v2.
  - Invalid data gets a readable error, never a crash.
- **F10 additions:**
  - wood, stone and iron; weapons and ammunition (the shotgun, shells, 9 mm); equipment (the vest, backpack and flashlight);
  - the difficulty setting;
  - spawning each enemy type; triggering an invasion (directly, or with a chosen composition);
  - a mission result (instant expedition to a chosen location);
  - revealing all map locations;
  - time; repairing the house.
  - All through the real systems.

## 8. Numbers, inputs, physics

- **Inputs** (lead added): `reload` (R), `weapon_next` (Q), `weapon_1` (1), `weapon_2` (2), `open_map` (M). In build mode, the number keys and R keep their build meaning, and the game doesn't switch or reload there.
- **Physics layers:** unchanged from Experiment 002.
- **Bomber blast** (a suggestion; AI and C may tune): radius about 1.6 m for voxels, objects within about 2.4 m. Characters take up to about 60 damage at the centre and 0 at about 4 m, scaled by difficulty `enemy_damage` and reduced by the vest.

## 9. Testing, captures and honesty

- **Tests:**
  - focused tests per module;
  - the FULL suite passes, including the Experiment 001 smoke tests and Experiment 002's game tests (they must keep passing or be updated by their Phase B owner; Phase A agents report breakages rather than editing other owners' tests);
  - a GDScript runtime error fails a test;
  - name test files so `--filter=<area>` finds them (the filter matches the file's base name and the method).
- **Captures** use the real renderer: `CAPTURE_ENGINE_ARGS="--fixed-fps 30" LP_NUM_THREADS=1 tools/capture.sh <scene> <png> <secs> [args]` (Xvfb + lavapipe). Under lavapipe, any HUD change forces a full 3D redraw (about 1 s/frame), so preview scenes for captures should keep 2D overlays static or hidden while waiting.
- **Honesty:** no claims of human play, real-GPU speed or listening.

## 10. Out of scope (Experiment 003)

- Structural collapse simulation; multi-floor construction.
- A crafting tree beyond the one scrap → iron example; weapon customisation.
- Detailed models of any kind (SirenVoxelLibrary handles those; don't integrate its assets).
- A second playable outdoor world; endless procedural generation.
- Exports and installers.
