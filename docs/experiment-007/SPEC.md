# Experiment 007 — The House Has Ears / Beyond the Front Door: contracts

**Approval:** the user's message "Combined Milestone — The House Has Ears / Beyond the Front Door" (2026-11-25, autonomous Rapid Delivery). Experiment 007 had not started before, so this is one combined milestone.
**Branch:** `exp007/house-has-ears`, from Experiment 006 (`f5c5d3d`). The branch name is outside the Windows-build triggers, so no CI build runs.
**Checkpoints:** source-only checkpoint branches are named `checkpoint/exp007-*`, also outside the CI triggers. No merge to `main`. The user playtests.

## Architecture in one paragraph

**The game scene works in two modes.**
- `GameLaunch.site` is `"home"` (as before) or a POI id.
- In POI mode, `SurvivalGame` builds a `PoiWorld` (a `HouseWorld` subclass, like `LevelWorld`) instead of the house. It keeps the shared gameplay: player, camera, HUD, `WeaponHandler`, roster / AI, quick bar, inventory, pause, dev menu, survival clock, audio. Home-only helpers (levels, home and electricity, storage, comfort, support, balance, defence, car, map table, fog boundary) are skipped or guarded with `game.is_home()`.

**Moving between home and a destination:**
1. The home is snapshotted with the existing full save (`RunSave`), in memory and on disk, when Eli leaves.
2. Travel plays as an accelerated animation on the regional map while game time advances.
3. The scene changes to the POI with the run's `GameState` carried in memory (`GameLaunch.carry`).
4. Leaving the POI plays the return travel and changes back home: the home is restored from the snapshot, the offscreen consequences are applied (invasions while away), and the run autosaves.
5. Expedition results are what Eli actually carries. There is no second loot roll.

## Agents and ownership

| Agent | User's § | Owns |
|---|---|---|
| **T** (travel and flow) | 2, 3, 9, 25, parts of 27 (priority 1) | new `src/travel/`; the site mode, scene transitions and carry in `survival_game.gd` and `game_launch.gd`; `run_save.gd` (site, travel checkpoint); the destination info and travel animation in `src/map/` (screen, overlay); the offscreen home resolution; removing the old dialogue expedition from normal play (`src/expedition/expedition_screen.gd` is no longer reachable from the fog or map; `ExpeditionData` / `RegionState` stay as data); car travel, fuel and cargo transfer home |
| **P** (POIs) | 4–8 (priority 1–2) | new `src/poi/`: definitions, `PoiWorld`, the three distinct layouts (Pine Woods, Convenience Store, Public Library), a reusable placeholder template for every other location, searchable containers, loose pickups, harvestable wood, loot from the existing `ExpeditionData` profiles, persistent per-POI state (searched containers, items taken, gradual replenishment) stored in `RegionState`, enemy encounter plans by danger, entries and exits, the car cargo box at the POI, carry limits while scavenging |
| **N** (noise, stragglers, visibility) | 10, 12, 13, 22 (priority 2–3) | new `src/noise/` (event-based noise with exposure modifiers via agent C's `src/home/rooms.gd`), straggler behaviours in `src/ai/` (wander, investigate, approach a window, test a door, lose interest, turn hostile), room-based visibility at home AND in POIs (new `src/visibility/`) |
| **O** (overview and holes) | 11, 14 (priority 3) | new `src/overview/` (structural overview: 4 modes, 5 levels, no furniture, enemies or player), new `src/holes/` (drill item, drilling, the look-through camera, covering a hole, enemies noticing) |
| **S** (security) | 15–19 (priority 4) | new `src/security/` (motion sensors, alarms, turret mounts with an installed inventory firearm, an ammo box per turret, an auto-reload upgrade, targeting with line of sight, config panel, save), the research extension (`Research`: Basic Electronics → Automated Defenses, an electronic-components item and books in the loot), the offscreen defence contribution API for T |

The lead handles the audio integration and production report (§20–23), the shared dev menu, merges, docs and checkpoints.

**Shared hot files:** `survival_game.gd` (T owns the structure; others add helpers through small "Exp 007 (X)" edits in `_assemble`), `dev_menu.gd` (one section function plus one call line each), `game_state.gd`, `house_world.gd`, `build_mode.gd`, `build_pieces.gd`, `src/ai/*`.

## 1. Site mode (T)

- **Launch state:**
  - `GameLaunch.site := "home"`, or a POI id;
  - `GameLaunch.carry := {}`: `{"state": GameState dict, "home": RunSave home snapshot, "travel": {...}, "poi": {...}}`.
- **Game API:**
  - `game.is_home() -> bool`
  - `game.site_id() -> String`
  - `game.poi` (POI helper, P), `game.travel` (T)
- **Signal `site_ready`:** emitted after assembly in either mode, so helpers can initialise per site.

## 2. POI world (P)

`PoiWorld extends HouseWorld`:
- **Built from** `PoiDefs.get_def(id)` + `RegionState` POI state;
- **Entry and exit:** `entry_point() -> Vector2`, `exit_points() -> Array[Vector2]`;
- **Looting:** searchable containers are `WorldObject`s (or POI objects) with stable ids; `game.poi` handles the search UI (reuse agent F's `StoragePanel` / `FurnitureStorage` with take-only), search time, noise, depletion, pickups and harvesting;
- **Encounters:** `encounter_plan(danger, seed) -> Array` of `{kind, at, when, mode}` (mode: wander / hidden / arrive), spawned through the existing roster.

## 3. Noise (N)

- **API:** `Noise.emit(game_or_world, pos: Vector3, level: float, source: String)`. Levels are about 1 low, 2 moderate, 3 high, 4 very high, 5 extreme; exposure is scaled by place (outdoor, exterior room, central, upper interior, basement), and openings and breaches raise it.
- **Enemy response:** nearby existing enemies investigate, approach cautiously, check an entrance, wander away or turn aggressive. Noise never spawns enemies.
- **Emitters (wired by N):**
  - gunfire (`WeaponHandler.fired`);
  - explosions;
  - build hammering (wood / metal);
  - smashing furniture.
- **Emitters (other agents call `Noise.emit` with a `has_method` / class fallback):**
  - drilling (O);
  - search actions (P);
  - alarms and turret fire (S).
- **Separation:** audio and noise are separate. Noise never depends on sound files.

## 4. Security (S)

- **Kinds:** `WorldObject` kinds `motion_sensor` and `turret_mount`, buildable, category "defense" or "utilities", gated by the new skills.
- **Offscreen defence for T:** `Security.offscreen_strength(world) -> Dictionary` with `{"turrets": n, "ammo": n, "sensors": n, "score": float}`, and `consume_offscreen(world, rounds)`.

## 5. Visibility (N) and overview (O)

- **Room visibility:** reuses `Rooms` (flood fill per world) at home and in POIs. Hidden rooms keep simulating; only their visuals hide.
- **The overview** reads the real house state, with no second simulation.

## 6. Audio (lead)

- **Inbox:** `assets/audio inbox/` and `assets/audio/_inbox/` (Experiment 005 `AudioInbox`). New logical names for security (alarm, sensor beep, turret), POIs (search, chop, pickup), travel and drilling fall back through `Sfx.play_first`.
- **Report:** `docs/experiment-007/AUDIO_REQUIREMENTS.md` extends the Experiment 005 inventory.
