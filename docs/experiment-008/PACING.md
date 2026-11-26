# Experiment 008 — First-week pacing (agent E)

**Question (the user's §8):** can Eli get the basics without an unrealistic number of trips? There's no hard-coded campaign, so this compares daily needs and early building costs with what a typical visit yields. Yields come from `PoiState` loot generated for 300 seeds per place: first visits at Normal difficulty and full stock.

## Needs

| Need | Per day | In items | Notes |
|---|---|---|---|
| Food | 26 hunger (16 h awake × 1.25, 8 h asleep × 0.75) | 0.9 canned food or 2.2 snacks | Starvation hurts at hunger 0 |
| Water | 39.5 hydration (16 × 1.9 + 8 × 1.14) | 1.3 bottles | The kitchen sink refills hydration without limit while it isn't wrecked (Exp 004 rule). Bottles matter on trips (a 3-hour trip costs about 6) or after the sink is wrecked. A rain collector gives 1 bottle per dawn. |
| Early building | — | window boards: 3 wood + 6 nails (the house has 8 windows: 24 + 48 for all); wooden wall: 4 + 6 per m; barricade: 2 + 4 per m; door: 4 + 6 + 1 scrap; rain collector: 2 + 2 + 3 scrap; workbench: 5 + 6 + 2 scrap | Nails are in nearly everything |
| Repairs | after an attack | 1 wood per 150 missing voxels + 1 nail per 60; a battered door 1–3 wood | Invasion 1: 3 psychos on day 3 at 22:00. Invasion 2: 5 on day 6. |

## What a visit yields

The figures show the open containers and pickups first, then the total including locked containers (crowbar). "Food" is the total hunger value found.

| Place (known at start?) | On foot (car), min | Danger | Quiet visit | Food | Canned / snacks / water | Wood | Nails | Scrap |
|---|---|---|---|---|---|---|---|---|
| Pine Woods (yes) | 10 (5) | 0.70 | 47 % | 24 | 0 / 2 / 1 | 15.5 / 22, plus about 33 from 11 chops (20 min each) | 0 / 2.3 | 0.7 / 1.4 |
| Corner Store (yes) | 10 (5) | 0.80 | 43 % | 104 / 150 | 2.4 / 2.6 / 2.0 (3.6 / 3.4 / 3.3) | — | — | — |
| Nearby Homes, placeholder (yes) | 10 (5) | 0.80 | 43 % | 64 / 88 | 1.2 / 2.3 / 1.7 | 2.1 / 5.3 | **4.4 / 11.3** (was 3.3 / 10.2) | 0 / 1.0 |
| Diner, placeholder (yes) | 10 (5) | 0.85 | 41 % | 104 / 143 | 2.4 / 2.7 / 2.5 | 0.7 | 1.0 | — |
| Supermarket, placeholder (yes) | 20 (10) | 1.00 | 35 % | 125 / 179 | 2.8 / 3.5 / 2.9 | — | — | — |
| Hardware Store (yes) | 15 (10) | 1.00 | 35 % | — | — | 8.9 / 14.4 | 9.4 / 19.9 | 1.4 / 4.2 |
| Public Library (yes) | 30 (20) | 1.05 | 33 % | 20 / 29 | 0 / 1.7 / 1.6 | — | — | — |
| Sawmill (no) | 30 (20) | 0.95 | 37 % | — | — | 10.3 / 17.4 | 11.9 / 18.6 | 1.4 / 3.4 |
| Scrapyard (no) | 25 (15) | 1.05 | 33 % | — | — | 0.6 | 9.6 / 13.5 | 6.9 / 11.7 (iron 1.4 / 3.8) |

Notes on the table:

- **Hardware Store:** these are the numbers before agent H's retune, and its crowbar is in the open 49 % of the time. The gun shop and clinic are also H's.
- **Public Library:** its value is the books.
- **Revisits** (everything taken, back after 2 or 4 days):
  - Pine Woods: wood 4.7 or 9.2, with 8 or 11 chops regrown. It is the renewable wood source.
  - Hardware Store: nails 3.3 or 6.7.
  - Corner Store: 1.6 or 3.1 food items.
  - Nearby Homes: one or two items.
- **Pack and car:** the pack holds 30 weight units. Food, water and wood weigh 1 each, snacks 0.5 and nails 0.05; a backpack raises the limit. A food trip's open loot weighs about 6, and a wood trip fills the pack. The car boot holds 60.

## Findings

- **Food isn't a constraint in week 1.**
  - The start (hunger 75, 3 cans, 2 snacks) is about 189 hunger points, or roughly 7 days.
  - One food place (the store, diner or supermarket) adds 4–7 days, so one or two food trips in the week are plenty.
- **Water isn't a constraint** while the sink works. A store gives 2–3 bottles for trips.
- **Wood is easy.** Pine Woods, 10 minutes away, fills a pack in one visit and regrows.
- **Nails are the early bottleneck.**
  - Each window board or wall metre costs 6, and repairs cost 1–5.
  - The known sources: the Hardware Store (about 9 in the open, 20 with a crowbar) and Nearby Homes (about 4, or 11).
  - Later, the sawmill and the scrapyard once discovered (about 30 % of trips spot a new place).
- **Scrap** (doors, the rain collector, the workbench) comes mainly from the Hardware Store and, later, the scrapyard.
- **The crowbar** opens a third to a half of each place's loot. The Hardware Store has it in the open about half the time, and Nearby Homes 14 %.

## Tuning (modest)

- **`SurvivalTuning.START_ITEMS` nails: 12 → 18.** That is three window boards before the first trip, and Day 1 is no longer gated on a nails run.
- **Residential profile nails chance: 0.5 → 0.65.** That raises Nearby Homes from about 3.3 to 4.4 open nails, and also covers the cul-de-sac, trailer park and farmhouse. Only the chance changed, so the loot rolls for everything else stay the same.

Not changed:

- food and water, which are already comfortable;
- the Hardware Store, gun shop and clinic (agent H);
- the encounter danger (see `PoiWorld.quiet_share`).

## A plausible Day 1–7

This is on foot at Normal difficulty. None of it is scripted.

| Day | What happens |
|---|---|
| 1 | Start: about 7 days of food, 6 wood, 18 nails. Morning at the Corner Store: about 2–3 cans, 2–3 snacks, 2 water. Afternoon at Pine Woods: about 15 wood from its boxes, plus 2–3 chops (6–9 planks). Evening: board three windows (9 wood, 18 nails). |
| 2 | The Hardware Store: about 9 nails, 9 wood, 1–2 scrap, and a crowbar half the time. Nearby Homes: about 4 nails, 2 wood and some food. Board two more windows or put up a barricade. |
| 3 | With a crowbar, the stockrooms: about 10 more nails and 3 scrap, enough for a rain collector. Or the library for a woodworking book. At 22:00 comes invasion 1: 3 psychos. Away from home, it costs 2–5 blows on the doors and walls instead. |
| 4 | Repairs (2–6 wood, 2–8 nails). Pine Woods again (regrown). Now and then a newly spotted place. |
| 5–6 | The supermarket or the diner for food: without a food trip, food runs short around day 6–7. A discovered sawmill or scrapyard for nails and scrap. On the night of day 6, invasion 2: 5 of them. |
| 7 | About 10–12 trips so far. The nearby known places are mostly picked over and revisits give a little; the woods keep giving wood. |

Rough trip counts:

- **Food:** about one trip per 4 days (26 a day against about 100 per food trip).
- **Nails:** about one trip per day of building (6–12 used against 4–9 found).
- **Wood:** one trip per several days.
