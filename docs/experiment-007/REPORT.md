# Experiment 007 — The House Has Ears / Beyond the Front Door: report

- **Branch:** `exp007/house-has-ears`. It builds on Experiment 006, as one combined milestone.
- **Checkpoint:** source-only `checkpoint/exp007-scavenging`.
- **How it was built:** Rapid Delivery, with five agents (T travel and flow, P POIs, N noise, stragglers and visibility, O overview and holes, S security). The lead did the integration, the audio and the docs.
- **What wasn't done:** no exe, no Windows CI build, no merge to `main`. Nothing was played by a human, and no sound was listened to.
- **Launch:** open `project.godot` in Godot 4.7 and press F5.

## 1. Playable scavenging (priority 1)

- **The old dialogue expedition is gone from play.** The fog edge (E), M and the dining-table map all open the region map.
- **Destination panel:**
  - travel time on foot and by car;
  - km and the road route;
  - expected finds and danger;
  - travel mode, with fuel needed (1 can per round trip);
  - the carrying limit (pack 30 × backpack, car boot 60);
  - "back before dark" or a warning;
  - Travel, or the reason it's refused (e.g. "Not with them at the door").
- **Visible travel:**
  - Autosave "departed", then the home is snapshotted (the full house save, every storey).
  - A tiny voxel Eli (4–8 s) or a car (3–5 s) moves along the roads with a running clock; Space skips.
  - The road minutes pass. The scene changes to the POI with the run's state carried in memory.
- **POIs:** the same 3D voxel gameplay and controls. The game scene runs in "site mode" with a `PoiWorld` (a `HouseWorld` subclass). Shared: player, camera, HUD, weapons, AI, quick bar, inventory, survival, noise, visibility and audio. Home-only systems are switched off. B says "You can only build at home", and M shows the map with "You are here".

| Location | What's there |
|---|---|
| **Pine Woods** | A snowy clearing with pines. 4 fallen trees: "[E] Chop wood" takes 20 game min, makes noise 3 and gives 2–4 planks, regrowing over days. A plank shelter with a workbench, a locked tool cabinet (crowbar) and a chest; a crate, a hunter's stash, a cooler, loose pickups, two trail exits. |
| **Corner Store** | Entrance, 6 aisle shelves (2 already picked clean), 3 fridges, checkout, snack rack, back hall, office, a locked stockroom (crowbar, the better loot), windows, front and rear exits. |
| **Public Library** | Reading room, lobby with reception and book returns, office, the stacks (8 bookshelves), and a locked, dark archive (crowbar to enter, flashlight to search). Real walls and doors between rooms, for room visibility and sound. Research books follow the existing skill rules. |
| **Every other place** | A clearly labelled placeholder: an 8 × 6 m two-room building whose containers are filled from that place's loot profile by category (house, shop, clinic, depot, gun shop, office). |

- **Looting:**
  - "[E] Search …" takes 2 s of real time and 6–10 game min; it can be empty and makes noise. A take-only panel opens (Take, Take all, Eat), with "Pack: 18 / 30".
  - Items are generated once per site from the existing loot profiles (difficulty, stock, one-of-a-kind items, books), seeded per run and place, and shared across the containers.
  - Taken is gone, and containers keep stable ids. Revisits refill only slowly (chance by days × regen, at most 70 %).
  - Driving gives a car boot (60) at the entry.
- **Encounters:**
  - By danger: nobody (5–40 %) or 1–5 enemies. One may be hidden in a room, others wander or arrive after 1–3 minutes (sooner on noise).
  - Runners appear from danger 1.0 and brutes from 1.3; no bombers.
  - Enemies are calm until they hear, see or are hurt by Eli.
  - Every exit works at any time, and no clearing is required.
- **Leaving:** "[E] Leave for home", then return travel. Home is restored from the snapshot; Eli walks up the front path; the car boot is unloaded (overflow goes to a pile by the car); autosave "returned". **The results are only what Eli carried.**
- **While away (offscreen home):**
  - Invasions, stragglers and dawns that fall due are recorded.
  - On return each attack is resolved against a defence score: closed doors, boards and barricades by HP and material, spikes, raised drawbridges (more with water), outer-wall integrity × material, open doors counting against it, plus the turrets' offscreen score. Blows land on the weakest points.
  - Turret ammo is spent; rain collectors fill.
  - A report line: "While you were away: Day 2, 22:00: they came, 3 of them; they broke a door; the walls took 3 blows."
- **Saving:**
  - At a POI the save stores the site, Eli's position and the carried home. Continue rebuilds the POI.
  - No saving during the travel animation; checkpoints are "departed", "arrived" and "returned".
  - Saving needs no live enemies (the existing rule), so wandering enemies at a POI can block it.
  - Older saves load at home.

## 2. The house has ears

- **Noise (`NoiseEvent`; separate from audio):**
  - Levels:

    | Level | Events |
    |---|---|
    | 1 | hammering wood, digging, searching |
    | 2 | masonry, drilling, forcing a lock, demolishing |
    | 3 | hammering metal, smashing furniture, alarm |
    | 4 | gunfire (shotgun 4.4) |
    | 5 | explosion |

  - Outdoor hearing radius by level: 6, 11, 17, 26, 38 m.
  - Exposure: outdoors 1.0, a room on an outer wall 0.75, a central room or upper interior 0.5, basement 0.25. Open outer doors, breaches and broken windows add up to +0.45.
  - Enemies build up alert: they investigate at 0.35 (toward the nearest entrance if the sound came from inside) and turn hostile at 3. No enemies spawn from noise; hordes are separate.
- **Stragglers:** on ordinary nights they do 2–4 calm activities (pass by, look in a window, test a door, examine damage), then leave; 30 % turn on the house instead.
  - Provoked by noise, by Eli within 2 m, by a clear line of sight for 0.9 s within 7.5 m, or by any damage.
  - POI enemies use the same calm modes (wander, hidden, arrive).
- **Room visibility** (home and POIs):
  - Eli's room is full; rooms through doorways are near; rooms through open doors are dimmed; other rooms are hidden. Furniture, objects, lamps, candles and enemies there are hidden, and the floor is darkened.
  - Updates on room change, door or structure change, storey or view change, and build mode. Hidden enemies keep simulating.
  - Build mode shows everything.
- **Structural overview (O, home only):**
  - Modes: 1 complete, 2 roofless, 3 cutaway (front half cut to 1 m), 4 blueprint (top-down plan with damage colours, windows, doors, stairs, holes, collapsed roof zones, a legend).
  - PgUp/PgDn across the levels that exist; Z/C rotate.
  - No Eli, enemies, furniture or clutter; it reads the real house state, with nothing simulated twice. The world pauses while it is open.
- **Observation holes:**
  - Drill item (hardware loot, F10). LMB with the drill on wooden walls, doors, barricades or boards takes 2–4 game min and makes noise 2. Stone, metal and glass are refused.
  - A small tunnel is carved at eye height (saved in the voxel diff, filled by Repair). Doors and barricades get a peephole.
  - **E** looks through: a narrow 32° keyhole view with slight aim, showing enemies in the cone. **F** covers it (1 plank or 2 nails).
  - Enemies near an open hole may notice it, and may poke it.

## 3. Electronic security

- **Research:** a separate electronics line.
  - Basic Electronics (book) → motion sensor.
  - Automated Defense Systems (book; needs Basic) → turret mount and auto-loader.
  - New item: electronic components (hardware, police, military, scrapyard, warehouse).
- **Motion sensor** (2 components, 2 scrap; Fortifications):
  - A post-mounted 110° cone up to 7 m, checked 4×/s, against hostile enemies only; never Eli, never through walls.
  - Needs mains power.
  - On trigger: a toast naming it ("Sensor at the front door: movement"), a blinking marker, an optional alarm (sound plus noise 3.5), or a soft beep when silent. It wakes a linked turret.
  - **E** opens its panel: enabled, alarm/silent, hostile-only, linked turret, turn.
- **Turret mount** (4 components, 4 iron, 3 scrap):
  - **E** opens its panel: install a handgun or shotgun from Eli's inventory (8 game min). The gun leaves the inventory, slots and bar, and comes back with its magazine when removed.
  - Its own 60-round ammo box takes only the installed gun's ammo, filled from what Eli carries and then from house storage. No infinite ammo.
  - 120° arc around its facing; range from the gun (handgun ≤ 20 m, shotgun 14 m). Line of sight is checked; it never fires through walls, roofs or closed doors and holds fire when Eli is in the line. It fires 1.5× slower than Eli, and each shot is a noise event.
  - **Basic mount:** fires the magazine, then needs Eli to reload it from the box (E).
  - **Auto-loader upgrade:** 3 components, 2 iron, 2 scrap; 45 game minutes. It reloads from the box with the gun's reload time × 1.5; the shotgun loads shell by shell.
  - Destroyed or demolished turrets drop the gun, magazine and box into a "Pile of belongings".
  - Status light: green ready, amber ammo or reloading, red off, dark no power.

## 4. Audio

- **Integrated:** all 64 of your uploaded files are mapped and in use: footsteps on snow, wood and cement timed to the walk; fireplace; forest; owls and wolves; house creaks; doors; handgun; destruction; building; enemy steps, impacts and vocals; Eli's two lines; the theme.
- **Layers:** outdoor, indoor and basement mixes; the fireplace; details; threat; music; voice. They work at home and at POIs.
- **New inbox rules** for drill, search, chop, force, pickup, alarm, sensor beep and turret reload, so recordings with those names replace today's fallback sounds.
- **Production report:** `docs/experiment-007/AUDIO_REQUIREMENTS.md`, with priorities and prompts. It covers existing sounds to replace, missing effects, ambience, Eli's voice, electronic security and music.

## F10 additions

| Section | Tools |
|---|---|
| Travel | go instantly to Pine Woods, Corner Store, Public Library or any place; return home; +3 fuel; repair car; skip the travel animation |
| POI | restore loot; spawn a straggler; reveal containers; POI state |
| Noise & visibility | sample noises; last noises; calm stragglers; room boundaries; diagnostics; reveal all |
| Overview & holes | open the overview; give a drill; hole at the nearest wall; list holes |
| Security | components; unlock research; sensor here; turret here; supply ammo; trigger sensor; restore power; info |

## Verification

- **Tests:** the full headless suite on the merged branch: **519 passed, 0 failed**. The main menu and the game scene boot headless without script errors. New tests: travel (including a real-scene store trip that brings an item home), POIs (12), noise, stragglers, visibility, holes, security.
- **Frames looked at:** by the agents, the travel panel, walking and driving, the store on arrival, each POI, the overview cutaway and blueprint, room visibility from the bedroom, turrets in the yard.

## Known limitations

- **Scavenging:**
  - Only Pine Woods, Corner Store and Public Library have their own layouts; every other place uses the labelled placeholder.
  - No hazards on the road, and no travel from one POI straight to another.
  - POIs have no roofs, and their containers can't be destroyed.
  - Saving at a POI is blocked while enemies are alive.
  - Offscreen damage lands on the ground floor only.
  - The old expedition screen code remains for dev tools and tests (F10 "Run mission now"). The Experiment 002/003 automated playtest tool still expects it.
- **Visibility and noise:**
  - The starting house has doorways rather than doors inside, so from the living room every room shows until doors are hung.
  - Ceiling lights still light hidden rooms; sight doesn't see through windows or shorten at night.
- **Holes:** the cutaway hides holes in front walls. Drilling can't be cancelled and has no progress bar. Holes at POIs aren't saved.
- **Security:**
  - Sensors are post-mounted only; turrets ignore other storeys; glass breaks on the first shot.
  - The auto-loader isn't refunded on demolish.
- **Audio:** room tones and many effects are still placeholders (see the report). The travel sounds fall back to UI sounds.
- **Balance:** a first pass throughout. Nothing was played by a human, and no sound was auditioned.
