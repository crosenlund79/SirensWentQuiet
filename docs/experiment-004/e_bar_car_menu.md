# Experiment 004: quick-access bar, the car, the pine woods, the menu siege

Agent E's part of "Make This House a Home": the user's sections 6 (equipment bar), 7 (scavenging and the car) and 2 (the main menu background).

## 1. The quick-access bar

**Files:**
- `src/survival/hotbar.gd` (`Hotbar`): the pure rules;
- `src/game/game_hotbar.gd`: input, the item in hand and its use;
- `src/ui/hotbar_bar.gd` (`HotbarBar`): the bar on the HUD;
- `src/combat/weapon_handler.gd`: the `holstered` state;
- `src/voxel/voxel_rig.gd`: relaxed arms, `carry`, `set_held`.

**Keys** (outside build mode and panels):

| Key | Effect |
|---|---|
| 1-8 | Select a slot and take its item in hand. 1 and 2 hold the equipped weapons by default. An empty slot means empty hands. |
| Q | The next weapon on the bar. |
| X | Empty hands (holster). Press again to take the selected item back. |
| LMB | Use the item in hand (below). |
| R | Reload the weapon in hand. With no weapon in hand, a short hint. |

**Using the item in hand:**
- **Weapon:** fires through `WeaponHandler`, as before.
- **Food, water, bandage, medkit:** one unit per click through `GameState.use_item`, with a toast and the eat, drink or bandage sound. The hand lifts once.
- **Hammer:** opens build mode.
- **Flashlight:** LMB toggles a shadowed cone light from the hand toward the aim point. The arm is held out while it is on.
- **Shovel:** opens build mode and selects the excavate tool when build mode has one (`excavate`, `dig` or `shovel`). Otherwise it says how to dig.
- **Crowbar:** explains its expedition use.
- **Vest, backpack:** LMB equips or takes it off.

**Empty hands:**
- The handler is holstered: `current_id()` is "", and firing returns `no_weapon`.
- The gun is hidden, `rig.aiming` is off and the arms hang with a slow sway.
- Tools and consumables show as a small model in the right hand.

**Filling the bar:**
- Automatic and stable: the equipped weapons go to slots 1 and 2. Then newly owned items from `Items.BAR_AUTO` take the first free slot, in this order: flashlight, hammer, water, canned food, snacks, bandage, medkit, crowbar, shovel.
- An item the bar placed once is not put back by itself (the `known` list).
- A consumable that runs out keeps its slot, shown dimmed with 0.

**Arranging:** in the inventory, press 1-8 to choose a slot, then press **Bar** on any weapon, tool, gear or consumable row. The item swaps places with whatever was in that slot.

**Display:**
- Eight slots at the bottom centre, each showing the key, a glyph, a short name and a count. Weapons show the rounds in the magazine.
- The selected slot has an accent frame. With nothing in hand, the bar shows "Hands empty".
- The bar is hidden in build mode, while panels are open and after death.
- The weapon card stays at the bottom right and shows "Unarmed" when holstered.

**Save:** `GameState.hotbar` is an optional field, `{"slots", "selected", "holstered", "known"}`. Older saves load with an empty bar, which the game fills.

## 2. The car

**Files:** `src/game/game_car.gd`; the car rules in `src/expedition/expedition_data.gd` (`CAR_*`) and `expedition_run.gd`.

**Inspecting:** walk up to the yard car. The prompt follows the car's outline, so it works from any side.
- "[E] Inspect the car" lists the parts with have/need counts.

**Repair needs:** a car battery, 2 fuel cans, 10 scrap, 4 iron and 6 nails.

**Repairing:** once everything is in the house, "[E] Repair the car (2 h)":
- spends the parts;
- passes two hours of game time behind a fade (needs keep falling; it is refused with enemies around);
- sets `GameState.car_repaired` (saved, optional);
- flashes the headlights twice and autosaves.

Afterwards the prompt is "[E] Check the car", which shows the fuel left and blinks the lights.

**New items:**

| Item | Category | Cap | Found at |
|---|---|---|---|
| `car_battery` | material | 2 | Scrapyard 35 %, Hardware 20 %, Farm 20 %, Police 15 % |
| `fuel` | material | 10, +4 per crate | Farm 45 % (1-2), Construction site 40 % (1-2), Scrapyard 30 % (1-2), Hardware 30 %, Police 30 %; also a locked car's boot and the residential car haul |

**On expeditions** (gear id `"car"`, a checkbox on the Plan step; it comes along by default when repaired and fuelled):
- **Fuel:** 1 can per trip (reported as consumed).
- **Travel:** 60 % of the time each way, so about 40 % shorter.
- **Load:** stackable loot ×2 on top of the backpack; wood, stone, iron and scrap ×1.5 more (×3 in total).
- **Heavy loads:** only by car, by kind of place:
  - houses: wood, scrap, fuel;
  - food places: cases of water, canned food;
  - medical places: a medkit, water;
  - construction places: stone, iron, wood;
  - weapons places: ammunition, iron.
- Household storage caps still apply; the rest is reported as left behind.
- No driving.

## 3. The pine woods (the 25th place)

`RegionLocations["forest"]`: "Pine Woods", construction category, hills district, map cell (47, 70), 5 × 6 cells. It is known from the start (`RegionState.START_KNOWN`). The map forces dense pine cover around it (`region_terrain.gd`, two small additions).

**Numbers** (`ExpeditionData.LOCATIONS["forest"]`, `construction_wood` profile):
- **Travel:** about 10 min each way; 6 min by car.
- **Search:** 150 min.
- **Risk:** danger 0.7 ("Low").
- **Loot:**
  - planks 8–17 (always), plus 3–6 at 60 %;
  - scrap 1–2 at 50 %;
  - no nails or tools.
- **Locked table** (crowbar), a woodcutter's shed: planks 5–9 (90 %), nails 2–6 (60 %), scrap 1–2 (40 %).
- **Events:** deadfall 3 (new), hunter's cabin 2 (new), dogs 1, tracks 1, fog bank 1; a second event 40 %.
- **Stock:** −8 % a visit, +10 % a day, never below 50 %.

## 4. The main menu siege

**Files:** `src/menu/menu_siege.gd` (`MenuSiege`), started by `src/menu/main_menu.gd`.

**A round:**
- **Build:** a new `VoxelLighting` and `HouseWorld` (`build_new`), the game's enemy roster, the roof faded out.
- **Variation** through the world's own API:
  - 0–3 wall runs in the yard (wood, or stone 30 %), each with a door 70 % of the time (iron 30 %);
  - boarded windows (45 % each, iron 25 %);
  - 0–3 iron-plated sections;
  - 0–2 pre-damage blasts and 0–16 shots;
  - a random time of day (five steps from overcast day to full night);
  - a random camera side and direction.
- **Sound:** the SFX bus is muted while a round is prepared and unmuted as it fades in. It is restored on exit.

**The horde:**
- 3 at once, then one every 2.5–6 s, at most 7 alive.
- Weights: psycho 6, runner 2, brute 1.4, bomber 0.7.
- Each enemy chases its own hidden stand-in target. A target starts in a random room. When the enemy reaches it, or every 14–26 s, it hops to another room or outside the far wall. So the horde keeps breaking walls, doors and barricades.
- Wall strikes go to `HouseWorld.enemy_strike` at strength 2.5. Bombers use their own weak-point logic.

**Camera:** a slow orbit (0.03 rad/s) at 19–24 m and 12–16 m high, looking at the house centre.

**Restart:** when 35 % of the wall sections are under 55 % integrity, or after 4 minutes, the view fades out (1.1 s) and a new round is built.
- Headless, the house reached 17 % broken after 90 s.

**Cost:**
- One build per round: about 1.7 s for the first round of a session (pristine house cache), 0.5–0.8 s after (headless).
- At most 7 enemies; the simulation took about 1.6 ms a frame headless.

**The menu on top:**
- The painted fog street shows until the first round is built. A dark gradient on the left keeps the menu readable.
- `live_background = false`, or the user argument `--static-menu`, keeps the painted background.

**Menu music:** it now starts deferred (`_start_music.call_deferred()`), so it plays on the very first launch (see `docs/BACKLOG.md`).
