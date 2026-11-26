# Experiment 009 — The World Never Stands Still: contracts

**Approval:** the user's message "Experiment 009 — The World Never Stands Still" (2026-11-26, autonomous overnight, Rapid Delivery).
**Branch:** `exp009/poi-generator`, from Experiment 008 (`d29773f`). The name is outside the Windows-build triggers.
**Delivery:** source-only checkpoints `checkpoint/exp009-*`. No exe, no Windows CI and no merge to `main`.

**The rule:** generate setups cheaply; generate a place only when Eli commits to going there. Reuse the Experiment 007/008 POI pipeline: a layout dictionary (`PoiLayouts` format) → `PoiWorld` → `PoiState` → `game_poi.gd`.

## Agents and ownership

| Agent | User's § | Owns |
|---|---|---|
| **G** (buildings) | 2B, 3, 5, 6, 7, 11 | new `src/poigen/` core: `poi_archetypes.gd` (the catalog and the site → archetype table), `poi_generator.gd` (footprint, rooms, doors, windows, interior furniture, containers, main stash, dormant spots, navigation validation, staged API), `furniture_catalog.gd` (tagged, weighted pieces); `PoiDefs.get_def` and `PoiLayouts.build` routing generated sites; the stash roll in `poi_state.gd`; new interior PropKit pieces in a new `src/props/prop_gen_interior.gd`; stash flags on the six hand-made layouts |
| **X** (outside and exits) | 8, 9, 10 | new `src/poigen/poi_exterior.gd` (surroundings per archetype, the car spot, arrival/departure point, outdoor containers), the apartment's dark hallway exit and its "Leave this location?" confirmation, "[E] Leave location" at the car or the arrival point (home or travel on), new exterior PropKit pieces in `src/props/prop_gen_exterior.gd`; the exit/cargo parts of `game_poi.gd` and the exit markers in `poi_world.gd` |
| **D** (daily opportunities) | 2A, 4, 16, 17 | new `src/poigen/daily_sites.gd` (the daily selection, overrun, refresh, save); new map sites in `RegionLocations` + `ExpeditionData` (see below); the map and travel panel (overrun shown and refused); the day-transition hook; F10 "POI generator" section and dev test sites; `region_state.gd` |
| **P** (dormant psychos) | 12, 13, 14 | dormant behaviours in `src/ai/` (a new `dormant_mind.gd` plus the hooks in `ai_enemy.gd` / `enemy_roster.gd` / `straggler_mind.gd`); the encounter part of `game_poi.gd` and `PoiWorld.encounter_plan` (mode `"dormant"`); psycho sound logical names, inbox rules and spatial playback with pauses |
| **R** (loading) | 15 | new `src/ui/loading_screen.gd`; staged, responsive boot of the game scene for travel arrivals and Continue (`survival_game.gd` `_ready` / `_launch` path), the staged `PoiWorld.build_new`, the progress from `PoiGenerator`'s staged API; failure handling (back to a valid state, no resources consumed) |
| **Lead** | 1, 19, 21 | SPEC, integration, scenarios A–H (`tests/poigen/`), the audio report, docs, checkpoints |

**Shared hot files:** `game_poi.gd`, `poi_world.gd`, `prop_kit.gd`, `survival_game.gd`, `dev_menu.gd`. Each agent keeps to its own functions, adds new ones rather than rewriting others', and adds one registration line where a list must grow.

## Sites and archetypes

**Stable site ids:** the `RegionLocations` ids. D adds six map sites:

| Site | Archetype | District / category |
|---|---|---|
| `apartments` | apartment | suburbs / residential |
| `auto_garage` | garage | industrial / construction |
| `workshop` | workshop | industrial / construction |
| `factory` | factory | industrial / construction |
| `office_block` | office | centre / knowledge |
| `fire_station` | fire_station | centre / medical |

**Site → archetype** (`PoiArchetypes.for_site(id)`, G):
- **Hand-made, kept as templates:** `forest`, `convenience`, `library`, `hardware`, `gun_shop`, `clinic`.
- **Residential:** `homes` house_small · `cul_de_sac` house_family · `farmhouse` cottage · `trailer_park` cottage · `apartments` apartment.
- **Commercial:** `grocery` supermarket · `diner`/`restaurant`/`fast_food` diner · `drugstore` pharmacy · `office_block` office.
- **Light industry:** `workshop` workshop · `auto_garage` garage · `warehouse` warehouse · `sawmill` warehouse · `factory` factory.
- **Outdoor industrial:** `scrapyard`, `quarry`, `construction_site`, `logging` → yard (a fenced or open site with a site hut).
- **Public:** `hospital` hospital · `police` police · `military` police (variant outpost) · `vet_clinic` clinic_small · `shooting_range` range · `fire_station` fire_station.

A site's archetype never changes. Only its availability does.

## Stage A: the setup (D, cheap, no nodes)

`DailySites.setup(state, id) -> Dictionary`:
`{id, archetype, family, size: "s"|"m"|"l", surroundings, categories: [..], risk: float, seed: int, hand_made: bool, available: bool, overrun_until: int}`.

- **Seed:** `seed = hash([run seed, id])`, stable for the run.
- **Today's selection** lives in `state.region.daily = {"day": d, "available": [ids], "overrun": [ids], "streak": {id: days}}`.
- **Size:** about 4–6 available a day (`DailySites.PER_DAY`, configurable).
- **Balance:** food and building materials usually have a source.
- **The active site:** the site of a running expedition is never removed.
- **Refresh:** at the day transition (00:00).

## Stage B: the place (G, on demand)

- `PoiGenerator.generate(setup) -> Dictionary`: a layout in the `PoiLayouts` format, plus new keys:
  - `bounds: Rect2` (the building);
  - `archetype`;
  - `stash: String` (the main stash container id);
  - `dormant: [{"at": Vector2, "behaviour": "bang"|"circle"|"sway"|"stare"|"tap", "target": Vector2, "radius": float}]` (valid spots; P chooses who is there);
  - `exit_kind: "car"|"edge"|"dark"`;
  - `dark_exit: Rect2` (apartments);
  - `diag: {seed, rooms, furniture, containers, stash_at, ms}`.
- **Staged:** `PoiGenerator.begin(setup) -> Object` (a context), `ctx.step() -> bool` (true = done), `ctx.stage: String`, `ctx.progress: float 0..1` and `ctx.layout`, with weighted stages: layout, rooms, doors, furniture, containers and loot, inhabitants, exterior. `generate()` steps it to the end. Pure data: no nodes, deterministic for a seed.
- **Exteriors:** `PoiExterior.decorate(L: Dictionary, setup: Dictionary, rng: RandomNumberGenerator)` (X) adds surroundings, `car`, `entry`, `exits`, `edges` and outdoor `wander` around `L["bounds"]` and its front doors (`L["doorways"]`). G calls it in the exterior stage.
- **Identity:** `PoiDefs.get_def(id, state)` builds a generated site from its setup.
  - The layout is cached by (id, seed, `PoiGenerator.VERSION`).
  - `PoiState` records the seed and version at the first visit, so revisits rebuild the same building. Containers keep stable ids.
  - Nothing of the geometry is saved: only the seed plus the existing compact differences (searched, taken, forced, the stash, the visit's encounters).
- **Navigation:** every generated layout passes `PoiGenerator.validate(L)`. Entry, exits, every room, every container front, the stash and every dormant spot must be reachable from the entry on a coarse grid. A failed seed retries with seed + 1, up to 8 times, then a simple fallback.

## Main stash (G)

- **Every POI has exactly one** container with `"stash": true`, `table: "stash"` and usually `needs: "crowbar"`. `L["stash"]` holds its id.
- **The stash roll:** `PoiState.generate` rolls the location's locked table × 1.5 into the stash alone, plus one roll of the profile's best unique item at its normal chance. It is useful, not guaranteed.
- **Looted stays looted** (no refill): `replenish` skips the stash.

## Dormant psychos (P)

- **Encounter mode `"dormant"`:** an enemy busy with a behaviour at a `dormant` spot. It is calm, has a lower sight range, stops to listen to noise, becomes suspicious, investigates and turns hostile per the existing alert rules. Some are more sensitive than others (`sensitivity` 0.5–1.5).
- **Behaviours:** bang, circle, sway, stare, tap, and mumble (layered on any of them).
- **Audio:** logical names `psycho/mumble`, `psycho/hum`, `psycho/bang`, `psycho/whisper`, `psycho/startle`, `psycho/scratch`, `psycho/tap`, mapped from the user's suggested filenames. One voice at a time per enemy, with pauses, a small global cap, and the existing fallbacks.

## Leaving (X)

- **By car:** the parked car stands outside the building; "[E] Leave location" at it opens a small choice: Go home, Travel on (map), Stay.
- **On foot:** an arrival/departure marker at the scene edge does the same.
- **Apartments:** the hallway fades into darkness. Walking into `dark_exit` asks "Leave this location?" (Leave / Stay), shown once per entry into the zone.
- **Rules:** existing travel rules and inventory carry-over apply. There is never a duplicate car, and no leaving through walls.

## Loading (R)

- **Where:** a loading screen with the destination, a bar, the stage text and real, stage-weighted progress, shown for generation, POI arrival, the home's return and Continue.
- **Short transitions:** under about 0.25 s it shows nothing.
- **Threading:** only threaded resource loading where useful; never scene-tree work off the main thread.
- **Tests:** the existing tests boot the game synchronously and must keep passing. The staged boot is used by the real flows (`GameLaunch.staged := true` from travel and the main menu); tests may opt in.
- **Failure:** a toast, back home or to the map, nothing consumed, and the save is untouched.

## F10 (D, with G's and P's calls)

The "POI generator" section:
- today's list; next day;
- inspect a setup;
- generate a test site by archetype (`house_small`, `apartment`, `supermarket`, `workshop`, `clinic_small`, `hospital`, `police`, …) with a new seed;
- spawn a dormant psycho; force a behaviour;
- reveal the stash; diagnostics; return home.

**Test sites** use ids `gen:<archetype>:<seed>`. They are never saved into the region, and they are cleared on leaving.

## Never

- generate detailed places at dawn;
- keep inactive POI scenes;
- regenerate a visited building differently;
- refill a stash;
- eject Eli at midnight;
- consume travel resources on a generation failure.
