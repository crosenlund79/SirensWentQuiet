# Experiment 008 — The First Week: contracts

**Approval:** the user's message "Experiment 008 — The First Week" (2026-11-26, autonomous overnight, Rapid Delivery).
**Branch:** `exp008/first-week`, from Experiment 007 (`8dff97b`). Like the Experiment 007 branch, the name is outside the Windows-build triggers.
**Delivery:** source only. No exe, no Windows CI and no merge to `main`. The Experiment 007 branch and its checkpoint stay unchanged.

**Goal:** make the existing systems come together. Don't add new survival meters, crafting trees, vehicles or enemy classes.

## Agents and ownership

| Agent | User's § | Owns |
|---|---|---|
| **H** (places) | 2, 3 | three hand-made layouts in `src/poi/poi_layouts.gd` (Hardware Store `hardware`, Pike's Guns `gun_shop`, Medical Clinic `clinic`); their `PoiDefs` entries (HAND_MADE, ARRIVAL); their loot data in `ExpeditionData` (those three locations only); per-POI lights and clutter in `PoiWorld` (`_place_pieces` and any new light or decal code); at most a handful of new PropKit pieces where no existing piece can stand in |
| **T** (travel) | 5 | POI → POI travel (the map at a POI offers the other known places; the home snapshot, ledger and car boot travel along; you can only unload at home); travel panel clarity (selection, progress, daylight warnings, walking vs. driving, cargo); arrival and departure transitions. Files: `src/travel/*`, `src/map/*`, `GameLaunch`, `run_save.gd` (site), and the exit and `leave()` / `finish()` part of `game_poi.gd` |
| **L** (looting) | 4, 10 (loot) | the interaction flow in `game_poi.gd` (prompts, search, take, panel), `poi_spot.gd`, `poi_loot_panel.gd`, and the spot markers in `poi_world.gd` (`_place_spots`, `_add_spot`, `apply_record`); `poi_state.gd` (depletion, no duplicates); a pack readout while away |
| **E** (encounters, home while away, pacing) | 6, 7, 8 | `PoiWorld.encounter_plan` and the encounter part of `game_poi.gd` (`_start_encounters`, `_spawn`, `_calm` / `_investigate` / `_hunt`, `_think`, `hear`); `src/travel/offscreen_home.gd` (with T's agreement on the call sites); early-game resource pacing (loot amounts, starting supplies), within the existing tables |
| **Lead** | 1, 9, 10, 11, 13 | loop verification and critical fixes first; scenarios A–D (`tests/firstweek/`); audio in the new POIs; F10; docs; merges |

**Shared hot file:** `game_poi.gd`. Each agent keeps to its own functions and adds new ones rather than rewriting others'.

## New optional layout keys (H fills them for the new POIs; E for the existing ones)

- `peek`: `[{"at": Vector2, "look": Vector2}]`. A spot outside a window where an enemy can stand looking in; `look` is the point inside it watches.
- `doorways`: `[Vector2]`. Points just outside an entrance, where an arriving enemy walks in.
- `lights`: `[{"at": Vector2, "h": float, "color": int, "energy": float, "flicker": bool}]`. Small light sources (an emergency light, a lamp left on, daylight through a skylight); H draws them in `PoiWorld`.
- `story`: `[{"type": String, "at": Vector2, ...}]`. Small details with no gameplay (an empty rack, a toppled stool, a blood-free scuffle of boxes); H decides the types.

Layouts without these keys keep working as before.

## POI → POI travel (T)

- **At a POI:** M (or an exit's "[E] Leave…") opens the region map. Travel goes to another known place with the normal time, fuel and pack rules. "Home" is always offered.
- **Carried along:**
  - the home snapshot;
  - the offscreen ledger;
  - the car and its boot (when driving);
  - what Eli carries.
- **Only at home** does anything go into household storage.
- **On leaving a POI**, the visit is finished once (`finish()`) before the next one begins, so stock, visit counts and the encounter seed stay per place.
- **Save at a POI:** the chain is stored as it is now (`site` + the carried home), and Continue resumes at the current POI.

## Never

- duplicate or lose inventory across home ↔ map ↔ POI ↔ save/load;
- spawn enemies from noise;
- require clearing a POI before leaving;
- hard-code a seven-day campaign.
