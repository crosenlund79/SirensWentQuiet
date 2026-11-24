# Experiment 003 — Scavenging: destinations, approaches, consequences (owner X)

The lot is the only place you can walk; everything outside is a **simulated** expedition. Experiment 002 had four hand-tuned destinations. Experiment 003 turns them into a **data-driven framework** over the 24 places of the regional map (`RegionLocations`, the one list), with four mission approaches, equipment-dependent options and outcomes, and persistent consequences (stock, discoveries, guarded or cleared places). Contracts: `SPEC.md` §3; the user's assignment §7.

| File | What |
|---|---|
| `src/expedition/expedition_data.gd` | `ExpeditionData`: profiles, per-place data, approaches, events, rules, risk, the map API (`location_summary`, `approaches`), formatting. Static and pure, except `apply_region`. |
| `src/expedition/expedition_run.gd` | `ExpeditionRun`: one deterministic expedition from departure to the result. |
| `src/expedition/expedition_screen.gd` | `ExpeditionScreen`: list (grouped, discovered places) → plan (approach, target, gear) → confirm → events → report. |
| `src/region/region_state.gd` | `RegionState`: discoveries, stock with slow recovery, notes and flags, the map's plan, once-only application of results, save round trip. |
| `src/expedition/fog_preview.*` | Capture and preview scene (real world, fog, the screen at any step). |
| `tests/expedition/`, `tests/region/` | Rules (Experiment 002, kept), framework, screen, region state. |

Unchanged from Experiment 002: the fog and the boundary (`FogBoundary`), the screen's look and flow, the result schema (extended additively), the departure window, determinism and "the screen never mutates the GameState". See `docs/experiment-002/expeditions.md` for those parts.

## 1. The framework

No per-place code. `ExpeditionData.destination(id)` merges three layers into one Dictionary (cached):

1. **`RegionLocations`** (lead): name, category, district, position, description and `travel_minutes(id)` (one way).
2. **A loot profile** (`PROFILES`, shared per kind of place): the main loot table, a "locked" table (opened on arrival by a brought crowbar), default danger, search time, event pool, chance of a second event, depletion.
3. **The place** (`LOCATIONS[id]`): its profile plus small variations: `mods` ({item: factor}: stackables scale their amounts, unique items their chance, 0 removes the entry), `extra` loot entries, `danger`, `search`, `place` (the word in event text), `requires`, `prep` (preparation), its own `events`, `locked`, `deplete`/`regen`/`floor`, `max_damage`, `risk_floor`.

Loot entries are `[item, min, max, chance]`, all `Items.DEFS` ids. **Unique items** (`Items.is_unique`: weapons, the vest, tools, utility gear) are found at most once, never when already owned, and multipliers scale their chance (at most ×1.5, capped at 95 %).

### Loot profiles

| Profile | Main table | Locked table (crowbar) |
|---|---|---|
| residential | canned food 1–2 (85 %), snacks 1–3 (70 %), water 1–3 (85 %), planks 2–5 (55 %), nails 4–10 (50 %), bandage (35 %), 9 mm 2–4 (15 %), crowbar 12 %, flashlight 20 %, backpack 15 % | garages: planks, nails, scrap, canned food |
| food | canned food 2–4 (95 %), snacks 2–4 (85 %), water 2–4 (100 %), bandage (20 %), backpack 8 % | stockroom: water, canned food, snacks |
| medical | bandages 2–4 (100 %), first-aid kits 1–2 (60 %), 9 mm 3–6 (30 %), water 1–2 (40 %) | drug cage: first-aid kit, bandages, 9 mm |
| construction_wood | planks 6–12 (100 %), nails 6–12 (80 %), scrap 1–4 (50 %), hammer 40 %, crowbar 35 %, flashlight 20 % | stockroom: planks, nails, scrap |
| construction_stone | stone 4–8 (100 %), scrap 1–3 (45 %), iron 1–2 (30 %), nails 2–6 (35 %), planks 1–3 (30 %), flashlight 12 %, crowbar 12 % | site container: stone, iron, nails |
| construction_iron | scrap 3–7 (100 %), iron 1–3 (70 %), nails 4–10 (50 %), planks 1–3 (30 %), crowbar 20 % | locked shed: iron, scrap, nails |
| weapons | 9 mm 2–5 (65 %), shells 1–3 (40 %), bandage (30 %), flashlight 20 %, vest 8 %, shotgun 6 % | locked cabinet: 9 mm, shells, shotgun 15 %, vest 15 % |
| military | 9 mm 3–8 (70 %), shells 2–4 (50 %), vest 30 %, shotgun 18 %, first-aid kit (50 %), bandages, flashlight 30 %, rations, water, iron | sealed container: 9 mm, shells, vest 35 %, shotgun 25 %, first-aid kits |

### Destinations

Generated from the data (`Risk`: the risk shown for a general search, bare-handed with no rounds → with a handgun and 12 rounds, crowbar, flashlight, backpack and vest equipped; Normal difficulty, untouched stock).

| Place (id) | Profile | Travel | Search g / c / r | Danger | Risk: bare -> kit | Needs | Preparation | Events (weight; 2nd event) | Deplete / regen per day / floor |
|---|---|---|---|---|---|---|---|---|---|
| Nearby Homes (`homes`) | residential | 10 min | 130 / 195 / 70 min | 0.80 | Low -> Low | - | - | boarded_house 3, collapsed_floor 2, locked_car 2, dogs 2, lone_psycho 1, tracks 1, fog_bank 1; 40 % | 0.15 / 0.030 / 0.15 |
| Birch Court (`cul_de_sac`) | residential | 10 min | 150 / 225 / 85 min | 0.85 | Low -> Low | - | - | locked_car 3, boarded_house 2, collapsed_floor 2, dogs 1, lone_psycho 1, tracks 1, fog_bank 1; 45 % | 0.20 / 0.030 / 0.15 |
| Riverside Trailer Park (`trailer_park`) | residential | 20 min | 140 / 210 / 75 min | 0.95 | Moderate -> Low | - | - | dogs 3, lone_psycho 2, locked_car 2, collapsed_floor 1, tracks 1, fog_bank 1; 50 % | 0.20 / 0.030 / 0.15 |
| Halvorsen Farm (`farmhouse`) | residential | 15 min | 160 / 240 / 90 min | 0.85 | Low -> Low | - | - | collapsed_floor 3, dogs 2, tracks 2, boarded_house 1, fog_bank 2; 45 % | 0.25 / 0.025 / 0.15 |
| Corner Store (`convenience`) | food | 10 min | 90 / 135 / 50 min | 0.80 | Low -> Low | - | - | storage_door 2, lone_psycho 2, locked_car 1, tracks 1, fog_bank 1; 35 % | 0.35 / 0.020 / 0.10 |
| Supermarket (`grocery`) | food | 20 min | 170 / 255 / 95 min | 1.00 | Moderate -> Low | - | - | storage_door 3, lone_psycho 2, dogs 1, locked_car 1, tracks 1, fog_bank 1; 60 % | 0.25 / 0.020 / 0.10 |
| Route 9 Diner (`diner`) | food | 10 min | 120 / 180 / 65 min | 0.85 | Low -> Low | - | - | storage_door 3, locked_car 2, collapsed_floor 1, lone_psycho 1, fog_bank 1; 45 % | 0.25 / 0.020 / 0.10 |
| Harbour Restaurant (`restaurant`) | food | 35 min | 150 / 225 / 85 min | 1.05 | Moderate -> Low | - | - | storage_door 3, dogs 2, lone_psycho 2, fog_bank 2, tracks 1; 60 % | 0.25 / 0.020 / 0.10 |
| Burger Barn (`fast_food`) | food | 20 min | 110 / 165 / 60 min | 0.95 | Moderate -> Low | - | - | storage_door 3, lone_psycho 2, dogs 1, locked_car 1, fog_bank 1; 50 % | 0.25 / 0.020 / 0.10 |
| Main Street Pharmacy (`drugstore`) | medical | 25 min | 120 / 180 / 65 min | 1.05 | Moderate -> Low | - | - | dark_pharmacy 3, storage_door 2, lone_psycho 2, tracks 1, fog_bank 1; 60 % | 0.30 / 0.015 / 0.10 |
| Medical Clinic (`clinic`) | medical | 25 min | 250 / 375 / 140 min | 1.30 | High -> Low | flashlight | - | dark_pharmacy 4, waiting_room 3, dogs 1, tracks 1, fog_bank 1; 100 % | 0.30 / 0.015 / 0.10 |
| Valley Vet (`vet_clinic`) | medical | 10 min | 150 / 225 / 85 min | 0.90 | Moderate -> Low | - | - | dark_pharmacy 3, dogs 3, tracks 1, fog_bank 1; 55 % | 0.30 / 0.015 / 0.10 |
| St. Brigid's Hospital (`hospital`) | medical | 30 min | 300 / 450 / 165 min | 1.60 | Severe -> Moderate | - | flashlight x0.85, 3+ rounds x0.85 | ward 4, waiting_room 3, dark_pharmacy 2, patrol 2, fog_bank 1; 100 % | 0.30 / 0.015 / 0.10 |
| Hardware Store (`hardware`) | construction_wood | 15 min | 210 / 315 / 115 min | 1.00 | Moderate -> Low | - | - | timber_rack 3, storage_door 2, collapsed_floor 1, lone_psycho 1, locked_car 1, tracks 1, fog_bank 1; 55 % | 0.22 / 0.030 / 0.15 |
| Logging Area (`logging`) | construction_wood | 35 min | 180 / 270 / 100 min | 0.90 | Moderate -> Low | - | - | heavy_load 3, timber_rack 2, dogs 2, fog_bank 2, tracks 1; 55 % | 0.10 / 0.080 / 0.50 |
| Pine Creek Sawmill (`sawmill`) | construction_wood | 30 min | 180 / 270 / 100 min | 0.95 | Moderate -> Low | - | - | timber_rack 3, heavy_load 2, storage_door 1, lone_psycho 1, fog_bank 1; 55 % | 0.22 / 0.030 / 0.15 |
| Granite Quarry (`quarry`) | construction_stone | 30 min | 200 / 300 / 110 min | 1.00 | Moderate -> Low | - | - | heavy_load 3, lone_psycho 1, dogs 1, tracks 1, fog_bank 2; 50 % | 0.08 / 0.100 / 0.60 |
| Construction Site (`construction_site`) | construction_stone | 20 min | 190 / 285 / 105 min | 1.10 | Moderate -> Low | - | - | scaffold 4, heavy_load 2, lone_psycho 2, dogs 1, fog_bank 1; 65 % | 0.20 / 0.030 / 0.20 |
| Scrapyard (`scrapyard`) | construction_iron | 25 min | 180 / 270 / 100 min | 1.05 | Moderate -> Low | - | - | heavy_load 3, dogs 2, lone_psycho 1, locked_car 2, fog_bank 1; 60 % | 0.15 / 0.050 / 0.30 |
| Riverside Warehouse (`warehouse`) | construction_iron | 30 min | 200 / 300 / 110 min | 1.10 | Moderate -> Low | - | - | storage_door 3, heavy_load 2, lone_psycho 2, collapsed_floor 1, fog_bank 1; 60 % | 0.22 / 0.020 / 0.15 |
| Pike's Guns (`gun_shop`) | weapons | 25 min | 140 / 210 / 75 min | 1.45 | Severe -> Moderate | - | 3+ rounds x0.85 | armoury 3, lone_psycho 2, patrol 2, storage_door 1, fog_bank 1; 75 % | 0.40 / 0.010 / 0.05 |
| Shooting Range (`shooting_range`) | weapons | 10 min | 170 / 255 / 95 min | 1.20 | High -> Low | - | - | armoury 3, lone_psycho 2, dogs 1, patrol 1, fog_bank 1; 60 % | 0.35 / 0.010 / 0.05 |
| Police Station (`police`) | weapons | 25 min | 220 / 330 / 120 min | 1.60 | Severe -> Moderate | - | vest x0.85, 3+ rounds x0.85 | armoury 4, patrol 3, waiting_room 1, lone_psycho 1, fog_bank 1; 100 % | 0.35 / 0.010 / 0.05 |
| Military Outpost (`military`) | military | 20 min | 260 / 390 / 145 min | 2.60 | Severe -> High | flashlight | vest x0.75, 4+ rounds x0.7 | outpost_gate 5, patrol 3, armoury 3, fog_bank 1; 100 % | 0.30 / 0.020 / 0.15 |

Variations on the profiles (the family houses are four takes on one residential profile):

- **Nearby Homes** (`homes`): the residential profile as it is; slow depletion (a whole street of houses).
- **Birch Court** (`cul_de_sac`): tools and medicine: bandages 1–2 (50 %), first-aid kit (25 %), hammer and crowbar (20 % each), flashlight (15 %); nails ×1.3, canned food ×0.8.
- **Riverside Trailer Park** (`trailer_park`): shells 1–3 sometimes (25 %), scrap 1–3 (40 %); less food and wood; dogs and psychos.
- **Halvorsen Farm** (`farmhouse`): preserves (canned food 1–3, 70 %), firewood (planks 3–6, 70 %), shells 1–2 (15 %), rarely a shotgun (7 %); a cellar is the likeliest event.
- **Food**: the corner store is small and close (less of everything, depletes fast), the restaurant has more water and tins, the fast-food place snacks and drinks, the diner some planks and nails.
- **Medical**: the pharmacy has bandages but no rounds, the vet's less of everything, the hospital ×1.6 first-aid kits and ×1.5 bandages.
- **Construction**: the hardware store keeps Experiment 002's numbers (planks, nails, scrap, tools); the logging area is almost only wood and recovers fast; the sawmill wood and nails; the quarry ×1.4 stone, recovers fast and never drops below 60 %; the construction site stone plus planks 3–6 and iron 1–3; the scrapyard ×1.4 scrap; the warehouse a mix (planks, stone, food and water extras).
- **Weapons**: the gun shop more rounds and shells and a better shotgun chance; the shooting range more 9 mm and a better vest chance; the police station ×2.5 vest and ×1.5 shotgun chance plus first-aid kits.

## 2. Mission approaches

`ExpeditionData.APPROACHES` (data; `approaches()` lists them for the map and the screen):

| Approach | Search time | Loot | Danger | Stock used | Discovery | Other |
|---|---|---|---|---|---|---|
| General scavenging (`general`) | ×1 | ×1 | ×1 | ×1 | 10 % | – |
| Targeted collection (`targeted`) | ×1 | target ×1.8 (chance at least 90 %), everything else ×0.4 | ×1 | ×0.9 | – | a target: one of `targets(id)` (the place's stackable items, most plentiful first) |
| Careful exploration (`careful`) | ×1.5 | ×0.9 | ×0.65 | ×0.8 | 55 %, then 15 % for a second | adds the *lookout* event (map what you see: one more place); a second event 15 % less likely |
| High-risk raid (`raid`) | ×0.55 | ×1.4 | ×1.6 | ×1.3 | – | needs a loaded weapon (3 rounds, or 2 shells); adds the *alarm* event; a second event 25 % more likely; leaves the place **guarded** for 2 days |

The approach and the gear change the options (raids need rounds; the plan step shows each approach's time and risk with the gear chosen, or why it's unavailable), the events (approach-only events: `only: [...]`) and the outcomes (time, loot, danger, depletion, discovery, marks).

**Purpose strings** (the map's `planned_purpose`): an approach id, or `targeted:<item>` (`ExpeditionData.parse_purpose`, `purpose_of`).

## 3. Equipment and rounds

The trip brings what is **equipped** (K's slots, `state.has_equipped`). Owned but unequipped gear stays home ("Not equipped: equip it at home to bring it"; required gear says "Equip yours first").

- **Vest and backpack** are worn: always along when equipped.
  - Vest: K's `GameState.damage` takes 35 % off the expedition injury when the result is applied; the resolver doesn't reduce it a second time. It lowers the shown risk where fights happen and is a preparation item (below). The report shows the health actually lost ("the vest took N off").
  - Backpack: stackable loot × `state.carry_multiplier()` (1.5).
- **Crowbar and flashlight** can be left at home for a trip (then they can't be lost).
  - Crowbar: opens the place's locked table on arrival and unlocks forced-entry options. It can be lost at the timber rack.
  - Flashlight: halves the injury chance in dark events and unlocks light options. The clinic and the outpost require it. It can be lost in the waiting room.
- **Rounds**: `rounds_owned(state, ammo)` = `state.rounds_carried(ammo)` (reserve + magazines) when the weapon that fires them is equipped (`ammo` → handgun, `shells` → shotgun), else 0. The plan step has a slider for each (default up to 12 rounds and 6 shells).
  - Event options cost **shots**: 9 mm rounds first, then shells, one shell counting as two rounds ("4 rounds (or 2 shells)").
  - In a fight event, an injury while you still have rounds makes you fire once to get clear (injury halved).
  - `consumed` lists `ammo` and `shells`. `apply_expedition` takes them from the reserve, then the magazines (K).
- **Preparation** (`prep`, per place): the trip's danger × factor when the gear is brought.
  - Military outpost: vest ×0.75, 4+ rounds ×0.7.
  - Police: vest ×0.85, 3+ rounds ×0.85.
  - Hospital: flashlight ×0.85, 3+ rounds ×0.85.
  - Gun shop: 3+ rounds ×0.85.
- `relevant_equipment(id)` lists the gear that matters at a place (required, preparation, then what its events and tables use); `gear_effect(gear, id)` gives the line.

## 4. Risk and danger

- **Trip danger** (`trip_danger`; it scales every injury chance on the trip) = place danger × approach × preparation × flags (guarded ×1.3, cleared ×0.8), at least the place's `risk_floor`, × difficulty `scavenge_danger` × 1.25 when exhausted (energy ≤ 15).
- **Shown risk** (`danger_for`) folds in the per-event gear effects where the place's preparation rule doesn't already count them:
  - rounds in fights: ×0.78 with 3+, ×0.9 with 1–2;
  - the vest in fights: ×0.85;
  - the flashlight in dark places: ×0.9.
- Tiers: < 0.9 Low, < 1.15 Moderate, < 1.45 High, else Severe.
- The military outpost never shows Low (`risk_floor` 1.0).
- A trip can cost at most 40 health; 50 at the weapons places and the hospital; 60 at the outpost.
- **Dangerous places** reward without guarantees:
  - they have bigger injury ranges;
  - `hurt_loot` options cut the loot when a fight goes badly;
  - rare finds are rare: a shotgun in under half the prepared outpost trips (tested).

## 5. Time and the departure window

- Nominal time = `RegionLocations.travel_minutes(id)` × 2 + the search time for the approach (rounded to 5 min).
- The Experiment 002 window stays: depart 05:00–18:00, nominal return by 20:00. It's checked per approach, so a careful trip can be too late while a raid still fits.
- The actual trip adds travel jitter (±15 min) and the options' minutes. It's clamped to at least `max(60, 2 × travel + 10)` and at most nominal + 150.

## 6. Persistence: stock, notes, discovery (RegionState)

- **Stock** (0..1 per place): loot × stock.
  - Each visit lowers it by `deplete` × the approach's factor × the trip's loot multiplier (0.5–1.25), down to the place's `floor`.
  - It **recovers slowly**: `regen` per day since the last visit (1 % a day at the weapons places up to 10 % at the quarry; the logging area 8 %), up to 1. Recovery is lazy: `RegionState.stock_on(id, day)` (or `ExpeditionData.stock_now(state, id)`) gives today's level; `stock_of(id)` is the level the last visit left.
  - The report says when a place is picked over (< 50 %) or picked clean (< 25 %).
- **Notes** (`notes[id]` = `{visits, last_day, flags: {flag: until_day}}`): the consequences.
  - `guarded` (a raid; danger ×1.3 for 2 days);
  - `cleared` (you fought your way through: *Fight your way through*, *Open fire*, *Fight your way in*; danger ×0.8 for 3 days);
  - each clears the other.
  - `notes_text(state, id)` gives lines such as "Visited 2 times, last on day 3.", "Picked over (55 % left).", "Guarded since your raid (until day 5)."
- **Discovery**: six places are known at the start (`RegionState.START_KNOWN`).
  - Careful exploration (55 % + 15 %), the lookout event and, rarely, general scavenging (10 %) find new ones. Nearer places are likelier (weight 1 / (1 + d/20)²).
  - Found places go into the result's `discovered`; the map shows them once the region applies the result.
  - The list only shows discovered places. `discover_all()` is for the dev menu.
- **Once-only application**: `RegionState.apply_result(result)` (also `ExpeditionData.apply_region(state, result)`), guarded by the result id (the last 64 ids are kept and saved). It records:
  - the visit and the return day;
  - `stock_after`, the `marks` and the `discovered` places;
  - it uses up a map plan for that place.
  - It tolerates Experiment 002 results (no region fields: just a visit) and garbage.
- **Saved** in `GameState.to_dict()["region"]`: `discovered` (sorted ids), `stock`, `notes`, `layout`, `planned`, `planned_purpose`, `applied`. `from_dict` drops unknown ids, wrong types and non-finite numbers, clamps values and never fails.

## 7. Difficulty

- Loot × `Difficulty.loot` (Easy 1.25, Hard 0.8): amounts of stackables, chances of unique items, event bonuses.
- Danger × `scavenge_danger` (Easy 0.8, Hard 1.25).
- Both are read from `state.difficulty`.

## 8. Events

The Experiment 002 events stay (rounds now through `shots`). New:

| Event | Where | Options |
|---|---|---|
| `heavy_load` *Too much to carry* | logging, sawmill, quarry, scrapyard, warehouse, construction site | *Load up anyway* (+30 min, loot ×1.25, strain 25 %) / *Pack it properly* (backpack; +15 min, loot ×1.3) / *Take what's easy* (−15 min, loot ×0.85) |
| `scaffold` *The scaffolding* | construction site | *Climb up for the rebar* (iron, stone; fall 35 %) / *Lever the pallet down* (crowbar; stone, iron; 8 %) / *Stay on the ground* |
| `outpost_gate` *The gate* | outpost | *Fight your way in* (4 rounds; loot ×1.2; hurt 40 %, 10–25, loot ×0.6 if hurt; clears the place) / *Slip in along the fence* (flashlight; +40 min; hurt 35 %, 10–22) / *Turn back* (−60 min, loot ×0.3) |
| `armoury` *The armoury* | weapons places, outpost | *Pry the door open* (crowbar; the locked table; the bang brings them 30 %) / *Search the lockers* (rounds, shells, bandage) / *Leave it* |
| `ward` *The stairwell* | hospital | *Climb with the flashlight* (first-aid kits, bandages; 25 %) / *Climb in the dark* (same; 55 %, 10–22) / *Search the ground floor* (loot ×0.85) |
| `patrol` *A pack of them* | weapons places, hospital, outpost | *Open fire* (3 rounds; clears the place) / *Hide and let them pass* (+30 min; 30 %, 10–24) / *Run for the exit* (−45 min, loot ×0.5) |
| `alarm` *Too loud* (raids only) | every place | *Grab and go* / *Hold your ground* (2 rounds) / *Keep searching* (loot ×1.2; 45 %) |
| `lookout` *A view* (careful only) | every place | *Climb up and map what you see* (+25 min; one more place) / *Keep your head down* |

Option fields added: `shots` (rounds fired; a shell counts as two), `hurt_loot`, `mark` ([flag, days]), `discover` (n places). Every event keeps an option that needs no gear.

## 9. The result

SPEC-002 §7.7 plus Experiment 002's additive fields, plus:

```
{"location": id (= destination), "approach": "general"|"targeted"|"careful"|"raid", "target": item id or "",
 "stock_before": 0..1, "stock_after": 0..1, "discovered": [ids], "marks": {flag: until_day}, "day": return day}
```

- `id` = `exp-<seed>-<n>-<place>-<approach>-<depart>`.
- `consumed` may hold `ammo` and `shells`.
- `damage` is the trip's injury; GameState applies the vest.
- The resolver never touches the GameState. The same state, gear, approach, target and choices give the same result.
- Four RNG streams: events, outcome, loot, discovery. The events met don't depend on the gear.

## 10. The screen

`ExpeditionScreen` keeps the Experiment 002 flow, look (UiTheme), keyboard and signals:

1. **List**, "Into the fog":
   - discovered places only, grouped by category under section headers, in a scroll list that follows the selection; each entry shows time and risk, "unavailable", or "planned".
   - Details: category and district, description, time (travel each way, return clock), risk with your gear and bare-handed, what might be found, what is known (visits, stock, flags), needs, gear effects, and each approach's time and risk or why it's unavailable.
   - The footer counts the known places.
2. **Plan** (step `gear`, "Plan the trip"):
   - the four approaches with their time and risk for the chosen gear (or the reason);
   - the approach text, and target buttons for targeted collection;
   - sliders for 9 mm rounds and shells (with a shotgun);
   - the gear rows: equipped, worn, required or not equipped, each with its effect.
   - On the right: risk, time, what to expect (loot focus, stock, difficulty), what you bring and recommendations.
   - *Continue* is disabled with the reason when the approach's needs aren't met.
3. **Confirm**, **events** (keys 1–3, hints like "4 rounds (or 2 shells)"), **outcome** (rounds and shells used).
4. **Report**: approach, found, used, lost, health actually lost, left behind, new places (now on the map), the place's stock, and what happened.

The map's plan (`state.region.planned` / `planned_purpose`) is **preselected** when that place is discovered: the place, the approach and the target (`preselected_plan`).

Public helpers (tests, preview, the game): Experiment 002's (`select_destination`, `to_gear`, `set_ammo`, `set_tool`, `to_confirm`, `depart`, `choose_option`, `continue_on`, `return_home`, `cancel`, `back`, `brought_gear`, `step`, `is_open`, `instant`), plus `select_approach`, `set_target`, `set_shells`, `plan_state`, `listed_ids`, `approach`, `target`, `approach_buttons`, `target_buttons`, `shells_slider`, `preselected_plan`.

## 11. API for the map (M)

```gdscript
ExpeditionData.location_summary(id: String, state: GameState) -> Dictionary   # {} for an unknown id; state may be null
ExpeditionData.approaches() -> Array   # [{id, name, short, desc, search, loot, danger, discovers: bool, needs_shots: int}]
ExpeditionData.parse_purpose(purpose) -> {"approach", "target"}  ;  ExpeditionData.purpose_of(approach, target := "") -> String
state.region.plan(id, purpose)  ;  state.region.clear_plan()  ;  state.region.is_discovered(id)  ;  state.region.discovered
```

`location_summary(id, state)` returns:

| Key | Value |
|---|---|
| `id`, `name`, `category`, `category_name`, `district`, `desc` | from RegionLocations |
| `risk_name`, `risk_value` | general approach, with the gear the player would bring now |
| `risk_bare_name`, `risk_bare_value` | the same bare-handed |
| `travel_minutes` | one way (`RegionLocations.travel_minutes`) |
| `search_minutes`, `minutes` | general search, and the round trip |
| `resources` | item ids, most plentiful first; `rewards` is a sentence |
| `targets` | what targeted collection can go for |
| `equipment` | `[{id, name, effect, have, equipped, required}]`, most important first (ids: flashlight, handgun, shotgun, vest, crowbar, backpack) |
| `requires` | item ids |
| `approaches` | `[{id, name, short, desc, available, reason, minutes, search_minutes, risk_name, risk_value}]`, in the order general, targeted, careful, raid |
| `stock`, `stock_text` | today's stock (0..1) and "Untouched", "Plenty left", "Picked over", "Mostly stripped" or "Picked clean" |
| `discovered` | bool |
| `notes` | lines (visits, stock, guarded or cleared) |
| `available`, `reason` | can you set out now (general approach) |

For undiscovered places the map should show only a silhouette or "?": the summary includes everything, so hide it there. A call costs about 0.8 ms under headless Godot here (24 places ≈ 20 ms): call it when the selection or hover changes, not every frame.

## 12. Integration (Phase B)

1. **Opening** (unchanged): on `boundary.exit_requested(at)`, pause the tree and call `ui.expedition.open(state)`.
2. **Finishing**: on `finished(result)`:
   - `state.apply_expedition(result)`;
   - then **`ExpeditionData.apply_region(state, result)`** (new; once-only by the result id, so a repeated signal is harmless);
   - move the player to `boundary.return_point(at)`, unpause, autosave.
3. **Cancelled** (unchanged): unpause.
4. **The map** (M) sets `state.region.plan(id, purpose)`; the screen preselects it on the next `open`. A plan is used up when an expedition to that place is applied.
5. **Save** (v2): `GameState.to_dict()["region"]` already holds everything (`RegionState.to_dict`/`from_dict`); v1 saves load the default region.
6. **F10**:
   - **instant expedition**: `ExpeditionRun.simulate(state, id, ExpeditionData.default_gear(state, id), [], approach, target, true)`. The last argument skips the window and requirement checks; the resolver is the real one. Then do what `finished` does (`apply_expedition` + `apply_region`), or emit `ui.expedition.finished` as `debug_finish_expedition` does.
   - **reveal the map**: `state.region.discover_all()`.
   - optional: `state.region.set_stock(id, v, state.day())`, `set_flag(id, "guarded", day)`.
7. **The playtest** (`tools/survival_playtest.gd`) keeps working:
   - the list preselects the first available place, so the primary button ("Plan the trip") is clickable at once;
   - the plan step is still called `gear`, with a primary *Continue* button;
   - the number keys still answer events.
   - Step 5's screenshots now show the plan step.

## 13. Requests and notes for other owners

- **K**: nothing blocking. `apply_expedition_report` already spends `consumed` rounds from the magazines and applies the vest.
  - Optional: call `region.apply_result(result)` inside `apply_expedition_report`'s once-guard. That would make step 2 above automatic, and calling both stays harmless.
- **Phase B**: step 2 (`apply_region`) is the one new call; without it the stock, discoveries and plans never change.
- **Lead**: no change needed in `region_locations.gd`.
- **Not in my paths**: `docs/experiment-002/expeditions.md` describes the four Experiment 002 destinations; this document supersedes it for destinations, gear and rules.

## 14. Preview and captures

`src/expedition/fog_preview.tscn` user args, besides Experiment 002's:

- `--screen=list|gear|confirm|event|outcome|report`;
- `--approach=id`, `--target=item`, `--plan=id[:purpose]`;
- `--discover=all|id,...`, `--stock=id:v,...`;
- `--event=id[,id]` (forces the events), `--difficulty=level`.

`--give=` adds items, which auto-equip.

```
CAPTURE_ENGINE_ARGS="--fixed-fps 30" LP_NUM_THREADS=1 tools/capture.sh res://src/expedition/fog_preview.tscn /abs/01_list_grouped.png 0.5 --pos=6.5,7.8 --clock=09:10 --screen=list --dest=quarry --give=flashlight:1,crowbar:1,backpack:1 --discover=quarry,cul_de_sac,scrapyard,police,logging,vet_clinic,farmhouse,construction_site,gun_shop --stock=grocery:0.45
CAPTURE_ENGINE_ARGS="--fixed-fps 30" LP_NUM_THREADS=1 tools/capture.sh res://src/expedition/fog_preview.tscn /abs/02_plan_targeted.png 0.5 --pos=6.5,7.8 --clock=08:20 --screen=gear --dest=quarry --approach=targeted --target=stone --give=flashlight:1,crowbar:1,backpack:1,vest:1 --discover=quarry --stock=quarry:0.7
CAPTURE_ENGINE_ARGS="--fixed-fps 30" LP_NUM_THREADS=1 tools/capture.sh res://src/expedition/fog_preview.tscn /abs/03_outpost_event.png 0.5 --pos=6.5,7.8 --clock=07:40 --screen=event --dest=military --event=outpost_gate --give=ammo:6,shotgun:1,shells:4,flashlight:1,vest:1,backpack:1 --discover=military
CAPTURE_ENGINE_ARGS="--fixed-fps 30" LP_NUM_THREADS=1 tools/capture.sh res://src/expedition/fog_preview.tscn /abs/04_report_discovery.png 0.5 --pos=6.5,7.8 --clock=09:10 --seed=2042 --screen=report --dest=homes --approach=careful --picks=0,0 --give=flashlight:1,crowbar:1,backpack:1
```

These four were captured and checked visually under software Vulkan.

## 15. Tests

`godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd -- --filter=expedition` (and `--filter=region`).

- **`test_expedition_framework`**:
  - every place configured from the one list, and the profile variations the assignment asks for;
  - **the resolver fuzzed over all 24 places × 4 approaches**: schema and new fields, positive int counts, valid ids, caps, unique items only when missing, consumed within brought and carried, stock only goes down, new discoveries only, valid marks, return day, determinism, unique ids, no state mutation;
  - results apply cleanly, the region once only;
  - stock depletion, the floor, recovery per day, loot scaling with stock;
  - discovery: careful usually, general rarely, targeted never, nearby first, nothing when all are known;
  - equipment: the backpack, crowbar and flashlight; the vest without a double count, with the health lost measured through `apply_expedition_report`; equipped vs owned; rounds from magazines and reserve; shells;
  - outpost preparation: the flashlight is required; unprepared is Severe, usually hurt, sometimes badly; preparation halves the health lost; a shotgun is possible but not guaranteed;
  - the other dangerous places;
  - approaches: time, danger, loot, targeted focus, approach-only events, guarded and cleared;
  - difficulty scaling;
  - `location_summary` for every id (with and without a state) and `approaches()`;
  - the developer path.
- **`test_expedition_rules`**: Experiment 002's rules on the new data.
- **`test_expedition_screen`**:
  - Experiment 002's flow;
  - grouped, discovered-only list;
  - the map's plan preselected (and ignored when undiscovered);
  - the plan step: raid gating, targets, shells;
  - the report naming new places without applying them.
- **`test_region_state`**: discovery, recovery, flags, plan, once-only application, round trip (including JSON and through GameState), garbage input.

## 16. Measured averages

300 seeds per row, from a throwaway script (not committed), 07:00 departure, option picks varied per seed, untouched stock, Normal difficulty, items gained per trip.

- **Bare**: the handgun with no rounds, plus a flashlight.
- **Kit**: crowbar, flashlight, backpack, vest and shotgun equipped; 21 rounds and 6 shells (12 rounds and 6 shells brought).
- **Lost** = health actually lost (after the vest).

| Place, approach | Time | Bare: hurt, lost | Kit: hurt, lost | Kit: main finds |
|---|---|---|---|---|
| Nearby Homes, general | 2 h 50 | 17 %, 1.8 | 11 %, 0.5 | 17 nails, 8.7 planks, 3.6 cans, 3.5 water, 2.8 snacks |
| Nearby Homes, careful | 3 h 50 | 9 %, 0.8 | 6 %, 0.3 | 15 nails, 7.6 planks, 3.1 cans; **0.83 new places** |
| Nearby Homes, raid | 1 h 45 | – (needs rounds) | 26 %, 1.3 | 23 nails, 11.8 planks, 4.8 cans |
| Supermarket, general | 3 h 30 | 21 %, 2.5 | 26 %, 1.2 | 8.4 water, 6.8 cans, 4.9 snacks |
| Supermarket, targeted water | 3 h 40 | – | 26 %, 1.2 | 14.3 water, 3 cans, 2.2 snacks |
| Granite Quarry, general | 4 h 40 | 24 %, 2.1 | 16 %, 0.7 | 21.5 stone, 7.2 nails, 2 iron |
| Granite Quarry, targeted stone | 4 h 40 | – | 16 %, 0.7 | 35.4 stone |
| Construction Site, general | 4 h 10 | 30 %, 3.1 | 16 %, 0.8 | 15.6 stone, 6.8 planks, 6.7 nails, 4.6 iron |
| Scrapyard, general | 4 h | 28 %, 2.6 | 20 %, 0.9 | 16.8 scrap, 11.2 nails, 5.9 iron |
| Logging Area, general | 4 h 30 | 25 %, 2.4 | 18 %, 0.9 | 30 planks |
| Hardware Store, general | 4 h 10 | 26 %, 2.8 | 23 %, 1.3 | 32.5 nails, 23.5 planks, 7.6 scrap |
| Medical Clinic, general | 5 h 10 | 28 %, 3.7 | 26 %, 1.5 | 6.8 bandages, 2.8 first-aid kits, 4.2 rounds |
| St. Brigid's Hospital, general | 6 h 10 | 33 %, 5.6 | 29 %, 1.8 | 11.2 bandages, 5.5 first-aid kits |
| Pike's Guns, general | 3 h 20 | 36 %, 4.7 | 34 %, 1.8 | 9.8 rounds, 3.8 shells (bare: 3 rounds, 1.1 shells) |
| Police Station, general | 4 h 40 | 44 %, 6.5 | 35 %, 2.0 | 9.2 rounds, 3.1 shells |
| Military Outpost, general | 5 h 15 | **80 %, 15.4** (max 43) | 51 %, 3.9 (max 40) | 12.4 rounds, 5.1 shells, 1.9 first-aid kits |
| Military Outpost, careful | 7 h 20 | 49 %, 8.4 | 35 %, 2.5 | 11.2 rounds, 4.5 shells; 0.98 new places |
| Military Outpost, raid | 3 h 05 | – | 73 %, 6.6 | 16.2 rounds, 6.5 shells |

Unprepared, the outpost still yielded a vest in about one trip in ten, and a shotgun about as often.

For scale: a day costs about one can of food and one and a half bottles of water. A wall costs 4 planks and 6 nails in Experiment 002 (stone and iron costs are C's).

## 17. Limitations

- The economy is a first pass, judged from measured averages, not from play.
- Discovery picks nearby places by straight distance, not by roads; the map's roads are M's.
- Stock is one number per place: taking only water doesn't leave the food untouched.
- Recovery is lazy (computed from the day of the last visit), so places don't change while nobody looks; the map must use `stock_now`/`location_summary`, not `stock_of`, to show today's level.
- A trip still resolves its loot at the end: a round found on the trip can't be fired in a later event of the same trip.
- The plan step and list were only checked at 1600 × 900 (the project's base size, stretch "expand").
- English only.
