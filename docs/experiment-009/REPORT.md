# Experiment 009 — The World Never Stands Still: report

- **Branch:** `exp009/poi-generator`, built on Experiment 008. The source-only checkpoint is `checkpoint/exp009-poi-generator`.
- **How it was built:** Rapid Delivery, overnight, with five agents in parallel: G (buildings), X (outside and exits), D (daily opportunities), P (dormant psychos) and R (loading). The lead wrote the contracts (`SPEC.md`), merged the work and wrote the scenarios A–H and the docs.
- **What wasn't done:** no exe, no Windows CI, no merge to `main`. Nothing was played by a human, and no sound was auditioned.
- **Launch:** open `project.godot` in Godot 4.7 and press F5. F10 opens the "POI generator" section.

## 1. The two-stage model

| Stage | When | What | Cost |
|---|---|---|---|
| **A: the day's opportunities** (`DailySites`) | At midnight, or on first use | One small setup per site: id, archetype, family, size, surroundings, categories, risk, seed, availability, plus the day's open/overrun lists | Pure data, no nodes; well under a millisecond |
| **B: the place** (`PoiGenerator`, through `PoiDefs.get_def` / `begin_def`) | Only when Eli travels there (or F10) | Footprint → rooms → doors and windows → furniture → containers and loot → main stash → spots for dormant psychos → lights and clutter → exterior (`PoiExterior`) → validation | About 5–17 ms for the building, 30–85 ms with the exterior; the voxel world is then built in stages behind the loading screen |

- **Nothing is generated** by opening the map, by dawn, or by a site being on today's list (scenario B checks this).
- **No geometry is saved.** A generated site is rebuilt from its seed and generator version, and only the existing compact differences are stored: what was searched and taken, the forced locks, the stash, and the visit's encounters.
- **Inactive POIs** are never kept loaded; only the active one exists.

## 2. Archetypes (19, plus the 6 hand-made places)

| Family | Archetypes (rooms; ✱ optional) |
|---|---|
| **Residential** | **small house** (living, kitchen, bedroom, bathroom, storage✱) · **family house** (living, dining✱, kitchen, hallway, two bedrooms, bathroom, storage✱) · **cottage**, plank walls · **apartment** (a shared hallway, then living, kitchen, bedroom, bathroom, storage) |
| **Commercial** | **supermarket** (sales floor with gondola rows, checkouts and fridges; stockroom; office; staff room✱) · **diner** (dining room, counter, kitchen, storage) · **pharmacy** (sales, dispensary, office) · **office** (corridor plan: lobby, offices, staff room, storage) |
| **Light industry** | **workshop** (work floor with benches, tool racks and machines; storage; office) · **vehicle repair garage** (a bay with a car; storage; office) · **warehouse** (a hall of pallet racks; office; storage) · **factory** (work floor with machines and pallets; lockers; office; storage) · **yard** (a site hut on open ground with pallets, crates and a wreck) |
| **Public** | **hospital** (corridor plan: lobby and waiting room, wards, exam room, dispensary, staff room) · **police station** (lobby and office, lockers, cells, armoury, evidence room✱; the military outpost is a darker variant) · **small clinic** (waiting room, exam rooms, dispensary) · **range** (shop front, firing lanes, armoury) · **fire station** (an engine bay, dorm, kitchen, lockers) |

**Where they apply:**
- **Hand-made, kept as templates:** Pine Woods, Corner Store, Public Library, Hardware Store, Pike's Guns and Medical Clinic.
- **Six new map sites:** Linden Apartments, Kessler Auto Repair, Carpentry Workshop, Northway Metalworks, Meridian Offices and Fire Station No. 2.
- **The old placeholder** remains only as a last fallback.

**Furniture** comes from a tagged, weighted catalog (`PoiFurniture`). Each piece belongs to room types and archetypes: sofas in living rooms and the odd staff lounge, hospital beds in wards, water dispensers in offices and clinics, pallet racks in warehouses, tool racks in workshops, gun racks in armouries, filing cabinets in offices and police stations.
- **Placement rules:** pieces fit against walls and face into the room. They never overlap, never block doors, and leave room in front of anything you use.
- **New interior pieces:** water dispenser, filing cabinet, tool rack, pallet, pallet rack, machine, locker, hospital bed, desk, safe.

**Navigation:** every layout passes `PoiGenerator.validate`. The entry, exits, every room, every container's front, the stash and every dormant spot must be reachable. A failing seed retries with seed + 1; about 1.0–1.1 attempts per seed are needed, and the fallback was never used in testing.

## 3. Daily availability

- **Day 1:** every known place is open.
- **From day 2:** about **4–6** known places are open each day (`DailySites.PER_DAY`, configurable). Pine Woods is always open and counts toward that number.
- **Streaks:** an open place stays open 1–3 days. A closed one stays overrun at least a day or two. Yesterday's closed places are picked first, so the list rotates.
- **Balance:** a food source is open on about 90 % of days, and a building-materials source other than the woods on about 85 %. Over 60 days and 3 seeds: food 58–60/60, materials 56–60/60.
- **Overrun places** stay on the map as greyed, crossed-out pins with "Overrun — too many hostiles to approach safely.", and travel there is refused. Home always works.
- **Word of a new place:** at midnight there is a 25 % chance an unknown place becomes known and open that day.
- **A running expedition** is never cut short: the POI Eli is at and his current destination stay open.
- **Saving:** the day's list is stored in the save (`state.region.daily`). Older saves get a list made on first use.

## 4. Identity and persistence

- **A stable seed per site:** a hash of the run's seed and the site id. A site's archetype never changes; only its availability does.
- **The first visit** records `{seed, generator version, size, surroundings}` in the site's record, so every revisit rebuilds the same building. Scenario G checks this through leave, save, a cleared cache and Continue: the same containers and walls, and what was taken stays taken.
- **Kept across visits and saves:**
  - searched containers and what is left in them;
  - pickups taken;
  - forced locks;
  - the stash;
  - the visit's enemies, dormant ones included;
  - the day's opportunities;
  - the car and its boot;
  - time.
- **Old saves:** a record from the placeholder era (or an older generator version) is started afresh on the site's next visit. Its containers are new; the visit count and the one-of-a-kind finds are kept.

## 5. Exteriors

`PoiExterior.decorate` builds surroundings for each family from 31 new outdoor pieces, in the snowy voxel style. Some of them can be searched.

| Family | Surroundings |
|---|---|
| Residential | picket fence, driveway, mailbox, bushes, a shed you can search, bins, pines, a left-behind car, porch light |
| Apartment | entrance steps, bike rack, wall lights, parking with a wreck, a dumpster, a small courtyard with benches |
| Commercial | parking bays, shop sign, trolleys, lamp posts, a delivery area with a loading door, pallets and a delivery van you can search |
| Industrial | mesh fence, shipping containers (some locked), scrap, barrels, pallets, a generator, a forklift, a wreck, a toolbox |
| Medical | an ambulance you can search, an emergency sign, direction signs, benches, medical waste bins |
| Police and fire | police cars (vans and an ambulance at the fire station), barriers, a sign, a fenced yard with a garage, a locked equipment container |
| Yard | perimeter fence, a site container, pallets, planks, scrap, barrels, a generator, a portable toilet |

## 6. Main stash

- **Every POI has exactly one** stash, usually locked (crowbar).
- **Examples:**
  - a safe or locked cupboard in a house;
  - the manager's office or stockroom in a shop;
  - the armoury or evidence room at the police station;
  - the dispensary or drug store in a clinic or hospital;
  - the storage cage in a warehouse.
- **The six hand-made places** mark their best locked container: the woodcutter's cabinet, the store's stockroom shelf, the library archive, the hardware stockroom, the gun locker and the drug cage.
- **Its loot:** its own roll of the place's locked table × 1.5, plus a chance at the place's rarest one-of-a-kind item. It is useful, not guaranteed.
- **No refill:** a looted stash stays looted forever (scenario D checks a month later).
- **F10 "Reveal stash"** shows where it is and its state.

## 7. Apartments and leaving

- **Apartments:** a short shared hallway with a street door at its lit end, one apartment, and the hallway's far end fading into darkness.
  - Walking into the dark asks "**Leave this location?**" (Leave / Stay). It asks once each time Eli enters, and Stay steps him back toward the light.
  - Leave opens the normal choice.
- **Everywhere else:** "**[E] Leave location**".
  - At the parked car's driver door, when Eli drove (the same car and boot, never a second car).
  - At a trail post at the scene's edge, when he walked.
  - Every way out opens **Go home / Travel on (map) / Stay**.
  - The six hand-made places work the same way.
  - Travel on keeps everything Eli carries and the boot, as in Experiment 008.

## 8. Dormant psychos

They are a real calm state of the existing AI, not an animation. Decisions run at 4 Hz.

| Behaviour | What it does |
|---|---|
| **bang** | Leans in and bangs its head against a wall or shelf in bursts, then pauses to listen |
| **circle** | Walks round a table, shelf or car on the navigation grid; sometimes reverses or pauses |
| **sway** | Rocks in place; turns its head now and then |
| **stare** | Motionless, facing a wall or object; twitches toward nothing |
| **tap** | Taps a cabinet, scratches at a door, or works a drawer, in bursts |
| **mumble** | Layered on any of the others (about 55 %) |

- **While absorbed:** it sees only about 3 m ahead. It ignores distant activity, notices Eli close by, and hears him run before it hears him walk. A loud noise makes it stop and listen; then it becomes suspicious, investigates, goes back, or attacks.
- **Sensitivity:** each psycho has its own, from 0.5 to 1.5, so some are much easier to wake than others.
- **Waking it:** a gunshot a few metres away wakes it at once (scenario F). Bumping into it or hurting it does too.
- **Once provoked** it is an ordinary enemy.
- **Bad spots:** a spot unfit for its behaviour falls back to stare or sway.
- **In the encounter mix:** generated places add dormant occupants (45 % of the occupants, at most 3) to the existing mix. Hidden enemies, wanderers, arrivals and empty buildings stay, and the quiet share is unchanged. At most one dormant sits beside a valuable container.
- **Save and Continue** bring them back where they were, with the same behaviour.

## 9. Audio still required

Logical names and inbox rules are ready for your ElevenLabs files. The suggested names map as they are:

| Suggested file | Plays |
|---|---|
| `Psycho - Incoherent Mumbling 01/02.mp3` | `psycho/mumble` |
| `Psycho - Nervous Humming.mp3` | `psycho/hum` |
| `Psycho - Rhythmic Head Banging.mp3` | `psycho/bang`, one thud per file |
| `Psycho - Disturbed Whispering.mp3` | `psycho/whisper` |
| `Psycho - Sudden Silence Reaction.mp3` | `psycho/startle` |
| `Psycho - Scratching.mp3` | `psycho/scratch`, one burst per file |
| `Psycho - Repetitive Tapping.mp3` | `psycho/tap`, one burst per file |

- **How they play:**
  - spatialized and attached to the enemy, quieter with distance, and through a wall at −6 dB with a low-pass;
  - one line at a time per psycho, with a pause of the line's length plus 7–18 s;
  - at most 2 voices at once, and none further than 20 m away;
  - they stop when the psycho is provoked.
- **Until your files exist:**
  - bang falls back to the door bash or wood impact;
  - tap falls back to a quiet wood impact;
  - mumble occasionally uses a quiet enemy vocal;
  - hum, whisper, scratch and startle stay silent.
- **Room tones:** store, clinic and library room tones (from Experiment 008) are still wanted.
- **The full list with prompts and durations:** `docs/experiment-007/AUDIO_REQUIREMENTS.md`, section G.

## 10. Loading

- **What it shows:** a loading screen in the travel cards' style, with the operation ("Entering Medical Clinic", "Returning home", "Loading saved game"), an amber bar, the stage line and a percentage.
- **Real progress:** it is weighted by stage, never moves backwards, and never runs ahead of finished work.
- **Stages:**
  - at a POI: preparing interior, placing furniture, populating containers (the generator, then the voxel world chunk by chunk), preparing inhabitants, final preparation;
  - at home and on Continue: reading the save, restoring the house, building the house chunk by chunk, the other storeys, final preparation.
- **Responsiveness:** work is time-sliced at about 12 ms per frame. Only the game scene's file loads on a thread; nothing touches the scene tree from it.
- **Hidden** when the operation finishes within about 0.25 s.
- **If a place can't be built:** Eli turns back home, the fuel for that leg is refunded, no time passes, and the save is untouched ("X couldn't be reached. You turned back home; nothing was used up.").

## 11. Performance

| Operation | Headless timing |
|---|---|
| Generating a building | 5–17 ms (apartment 5, hospital 14, office and factory 17) |
| Exterior | adds 20–70 ms |
| Arrival at a POI, staged | 370–870 ms over 23–54 frames; the worst frame 50–75 ms |
| Return home | 580–790 ms over 25–33 frames; one step of 240–300 ms (the house's base build) |

- **What was not measured:** real-GPU frame rates.
- **Cheap at runtime:** dormant AI ticks at 4–5 Hz, and the psycho voices are capped. Outdoor clutter has collision only on large pieces.

## Tests and checks

**Scenarios (`tests/poigen/test_e9_scenarios.gd`, through the real game scene):**

| | Checks | Result |
|---|---|---|
| **A** | Two consecutive days: 4–6 open; overrun places keep their archetype and seed and are refused | passes |
| **B** | Opening the map generates nothing | passes |
| **C** | A family house: kitchen, dining, living, hallway, storage, bedroom and bathroom; 38 props, 16 containers, a stash; validates | passes |
| **D** | A supermarket: shop shelving, no beds or sofas, exactly one stash, never refilled | passes |
| **E** | An apartment: the hallway's darkness asks once; Stay steps back | passes |
| **F** | A dormant psycho stays dormant with Eli across the place, and a gunshot beside it wakes it into the ordinary AI | passes |
| **G** | Take something, go home, save, clear the cache, Continue, go back: the same building, still taken | passes |
| **H** | The hospital's generation steps through named stages with rising progress, then lands in the cache for the arrival | passes |

- **Agents' tests:**
  - `test_poi_generator` (every archetype × 20 seeds);
  - `test_poi_exterior`;
  - `test_daily_sites`;
  - `test_dormant`;
  - `test_loading_screen`.
- **Full suite:** 609 passed, 0 failed.
- **Frames looked at:**
  - **Lead:** six generated places in the real game scene with the HUD (family house, supermarket, hospital, apartment, police station at night, workshop).
  - **G:** house, supermarket, workshop, hospital, apartment and yard.
  - **X:** every family by day and three at night, the dark hallway, the leave dialog.
  - **D:** the map with overrun and open places.
  - **R:** the loading screen mid-load, leaving and arriving.
  - **P:** a store with banging, tapping and swaying psychos.

## Known limitations

- **Generated buildings** have one storey. The yard's open ground isn't a room. Large rooms can feel sparse. A yard can end up with two wrecks (one from the building, one from the exterior).
- **Exterior:**
  - the street is always along the south edge;
  - lights by side doors are placed by a simple rule;
  - the bike rack reads as sticks from the game camera;
  - the ambulance can be some way from the door when space is tight.
- **Dormant psychos:**
  - they appear only in generated places (the hand-made ones have no dormant spots; F10 can place one anywhere);
  - once woken and then lost, a psycho becomes a wanderer, not dormant again;
  - most of their sounds are silent until the files arrive.
- **Daily list:** once many places are known, most are overrun on any given day (4–6 open by design).
- **Loading:**
  - New Game and F10 reload are not staged;
  - the home's base build is one 240–300 ms step;
  - on a failed Continue at a POI, the car's boot isn't brought home.
- **Doors** opened at a POI aren't saved (as before).
- **Old saves:** placeholder-era records restart their containers on the next visit.

## What needs human playtesting

1. Whether generated houses, shops, workshops, hospitals, police stations and apartments read as believable places from the game camera, and whether their furniture fits.
2. Whether the daily list creates real choices ("the clinic is open today"), or is frustrating.
3. Dormant psychos:
   - Is the tension there?
   - Can you sneak past?
   - Is waking them fair?
   - How do they look while banging, circling and swaying?
4. Whether the leave dialog and the apartment's darkness feel natural.
5. Whether the stash is worth the noise.
6. Loading screen pacing on a real machine.
7. The psycho audio once recorded.

## Trying generated POIs in Godot

- **The normal way:** open the region map (M), pick an open place that isn't one of the six hand-made ones (e.g. Linden Apartments, the Cul-de-sac, the Supermarket, the Hospital, the Police Station, Northway Metalworks), and Travel.
- **F10 → "POI generator":**
  - today's places, and "Next day (00:00)";
  - inspect a site's setup;
  - generate a test site by archetype with a new seed, and travel there instantly (ids `gen:<archetype>:<seed>`, never saved);
  - place a dormant psycho, or force a behaviour;
  - reveal the stash;
  - diagnostics (seed, rooms, furniture, containers, stash, ms);
  - return home.
- **Preview only:** `godot --path . res://src/poi/poi_preview.tscn -- --poi=hospital`.

## Verification

- **Full headless suite** on the final branch: **609 passed, 0 failed, 0 skipped**. That includes the scenarios A–H and the agents' new tests.
- **Headless boot:** the main menu and the game scene both start without script errors.
