# Sirens Went Quiet

*Working title.* Present day, after something nobody can explain. The grid is gone, the radio is silent and nobody has heard from another sane human since the sirens went quiet. You still have the house.

This repository holds **Experiment 012 — The World Is Watching** (Chapter One of the story, coordinated sieges, fog of war, named enemies and their bodies), built on Experiment 011 (Faces of Madness: handcrafted voxel people), Experiment 009 (The World Never Stands Still), Experiment 008 (The First Week), Experiment 007 (The House Has Ears / Beyond the Front Door), Experiment 006 (Defensive Living), Experiment 005 (A House Worth Living In), Experiment 004 (Make This House a Home), Experiment 003 (Foundations of Survival) and Experiment 002 (The First Days). The house is your progression: scavenge, demolish, rebuild, reinforce, furnish, expand up to five levels and keep it running. It is a survival game about one house on one lot, ringed by dense fog. **Experiment 001** (three ways to build a destructible house) is kept as history under *Visual Experiments*.

The loop: **wake → assess needs → plan on the map → scavenge → return home → build and prepare → survive the night → sleep → repeat.**

## Run it

1. Install **Godot 4.7** (developed with 4.7.2 stable, standard build, Forward+).
2. Open this folder in Godot (`project.godot`) and press **F5**, or run `godot --path .` from here. The first open imports the assets, which takes a minute.
3. The main menu has New Game, Continue, Settings, Visual Experiments and Quit.

**Windows build:** every push to the working branch (and to `playtest/...` branches) builds `SirensWentQuiet.exe` with GitHub Actions (workflow "Windows build"). Open the run on the repository's Actions tab and download the artifact at the bottom of the page (you need to be signed in to GitHub). Unzip it and run the `.exe`; no install is needed.

## Playing

**New Game** asks for a difficulty:

| Difficulty | Invasions | Start |
|---|---|---|
| Easy | from Day 4, every 4 days; no bombers until the 4th invasion | 12 rounds |
| Normal | from Day 3, every 3 days | 9 rounds |
| Hard | from Day 2, every 2 days; mixed waves and bombers early | 9 rounds |

You wake on Day 1 at 07:00 with a loaded handgun and no spare rounds, a little food and water, a hammer and a few planks.

- **Needs:** hunger, hydration and energy drain over time. Eat, drink and heal from the inventory (I). Starvation or dehydration costs health, and death ends the run.
- **Equipment (I, Equipment tab):** six slots — primary and secondary weapon, body, back, utility and tool.
  - A vest makes blows and blasts hurt 35 % less.
  - A backpack carries half as much again.
  - A flashlight and a crowbar open places and choices on expeditions.
- **Weapons:** handgun (9 mm, magazine) and shotgun (shells loaded one by one, a spread of pellets). The shotgun is found while scavenging.
- **The World Is Watching (Experiment 012):**
  - Someone is watching the house. Chapter One unfolds over the first weeks, at night, in Eli's own bedroom; after it, some nights the attackers come organised: they surround the house, block the doors and barricade Eli in. F10 → Story replays every scene; F10 → Enemies starts a siege.
  - Whole hordes arrive at once. Psychos scream when they see Eli and charge; the scream draws others. Every psycho has a name, and the bodies stay where they fall and can be searched.
  - You only see what Eli sees: fog of war, walls block sight, and his view follows where he looks. A faint pulse at the screen's edge warns of someone very close behind.
  - Walk or drive across open land on the map; locked rooms are double-walled; loot windows keep their size; places that are mostly searched are marked. Settings → Graphics has Low/Medium/High/Ultra and a frame-rate display (F3).
- **Faces of Madness (Experiments 010 and 011):** Eli and every enemy are handcrafted voxel people. The ordinary psychos are 30 different people (each keeps the same face when you come back or load), runners are starved and thin, brutes are about 2.4 m tall and duck through doors, and bombers are ordinary people wearing the glowing pack. Main menu → Visual Experiments → **D Character Showroom** (or F10 → Character) shows them all, side by side with Eli.
- **The world never stands still (Experiment 009):**
  - Every day 4–6 places are open; the others are **overrun** ("too many hostiles to approach safely") and may open again later. Pine Woods is always open.
  - Places other than the six hand-made ones are **generated when you first go there** (houses, apartments, supermarkets, diners, pharmacies, offices, workshops, garages, warehouses, factories, yards, hospitals, police stations, clinics, ranges, fire stations), with rooms, fitting furniture, surroundings and **one main stash**. They stay the same building on every revisit.
  - **Dormant psychos** may be absorbed in something strange (banging their heads, circling, swaying, staring, tapping, mumbling). Sneak past, or wake them.
  - Leave by the car or the trail post ("[E] Leave location": Go home / Travel on / Stay); apartments end in a dark hallway.
  - A loading screen shows real progress when a place is being prepared.
- **Scavenging (Experiments 007 and 008): you go there yourself.**
  1. **Choose a place:** open the region map (M, the map on the dining table, or **E** at the fog edge) and pick a known place. The panel shows:
     - what the place is good for (food and water, building materials, medical, weapons and ammo, books, tools), its danger, and whether you've been;
     - walking and driving side by side, with the time there, the arrival time and when you'd be home ("back before dark" or a warning);
     - fuel, if going by car;
     - your pack, and the car's boot.
  2. **Travel:** press **Travel** (C switches on foot / by car). Eli, or the car, moves along the roads on the map while time passes, with a progress card; Space skips the animation.
  3. **The place:** you arrive in a playable place, the same game in a different location.
     - **Pine Woods:** chop fallen trees for planks, search a shelter.
     - **Corner Store:** aisles, fridges, a locked stockroom.
     - **Public Library:** books and manuals in the stacks, a dark locked archive.
     - **Hardware Store:** nails, planks, scrap, iron and parts; a jammed stockroom and a delivery yard.
     - **Pike's Guns:** ammunition, and sometimes a gun; a locked steel back room.
     - **Medical Clinic:** bandages and first-aid kits; dark rooms down the corridor and a locked medical store.
     - **Every other place:** a placeholder layout for now.
  4. **Searching:** **E** at shelves, fridges, desks and crates. It takes a little time, can come up empty, and makes some noise.
     - Small markers show what you haven't searched, what's locked or dark, what's partly taken and what's empty. The prompt says what's left.
     - You take what you choose, within your pack limit, shown on the HUD (more with a backpack, plus the car's boot when you drive: "Stow what you found").
     - A crowbar opens locked rooms; a flashlight lights dark ones.
  5. **People:** often nobody. Someone may be hiding inside, watching through a window, walking in by a door, or arriving later. They stay calm until they hear or see you, and a hunter can lose you if you get out of sight. Fight, sneak or just leave.
  6. **Leaving:** **[E] Leave for home** at any exit, at any time, or **M** to **travel on** to another place (home → hardware store → clinic → home). You arrive home with exactly what you carried. Places stay looted and only slowly recover.
  - **While you're away,** attacks still come when they fall due. Your defences (doors, barricades, spikes, moats with raised drawbridges, walls, and turrets with ammo) decide the damage. Prowlers mostly look around and leave. On return a short report tells you what happened.
  - **Saving at a place** works unless someone is hunting you; Continue puts everyone back where they were.
- **Building (B):** wood, stone and iron.
  - Stone walls need a foundation (the house floor or a stone foundation).
  - Iron makes barricades, reinforced doors and plating.
  - A workbench turns 3 scrap into 1 iron.
  - Repair uses the damaged material. Stone takes much longer to break than wood, and plating doubles it.
  - You can never seal the last way out.
- **Nights:** invasions arrive at 22:00 as waves built from a threat budget that grows each time. A straggler can come on other nights.
  - The **psycho** bashes its way in.
  - The **runner** is fast and looks for an open way in.
  - The **brute** is slow and smashes walls, three strikes per swing.
  - The **suicide bomber** walks to a weak point in your defences and lights a fuse. A HUD alert and a ring on the ground warn you. The blast leaves a lasting breach, so shoot it first.
- **The house is your progression (Experiment 004):**
  - **Demolish anything** (B, 9): furniture, original walls, windows, doors and floor tiles give salvage; whatever you built refunds in full. You can clear the house out completely.
  - **Destruction:** furniture breaks apart under bullets, blows and blasts, then settles as rubble.
  - **Defences:** board up windows, reinforce doors (wood → reinforced → metal), build metal doors.
  - **Expand:** lay wooden floors, build stairs and an upper floor (40 planks, 40 nails, 4 iron), and dig a basement with a shovel (25 min and some energy per 1 m cell, +1 stone).
  - **Electricity:** every room has a wall switch, and some lamps their own switch. Everything electric hangs on the fuse box in the utility room. Switch the mains there, protect it, and rebuild it (B, 6) if it's destroyed; without it the house is dark.
  - **The fireplace** in the living room burns from the start and doesn't need power.
  - **The kitchen:** drink at the sink and eat from the fridge, which uses your stored food, while they're intact.
  - **The car** in the driveway needs a car battery, 2 fuel cans, 10 scrap, 4 iron and 6 nails. Once repaired it can come on expeditions: 1 fuel per trip, shorter travel, much more carried home.
- **The north:** dark nights, northern lights on most of them, snow and pines. Light matters.
- **Sleep:** use the bed. Sleep restores energy, still costs food and water, and is cut short when something arrives.
- **Saving:** the game autosaves after waking, at dawn, after an expedition, after an invasion and after planning on the map. You can also save from the pause menu (Esc). There is one save slot. Experiment 002 saves still load and are upgraded on the spot.

### Controls

| Input | Action |
|---|---|
| WASD / arrows | Move |
| Shift (hold) | Sprint (×1.6 speed; drains energy faster) |
| 1–8 | Quick-access bar: take that slot's item in hand (1 and 2 hold your weapons by default) |
| X | Empty your hands (press again to take the item back) |
| Mouse / LMB | Aim / use the item in hand: fire a weapon, eat, drink, bandage, toggle the flashlight; the hammer and shovel open build mode |
| R | Reload |
| Q | Next weapon on the bar |
| E | Use the bed, a door, a crate, a collector, the workbench, the map table or the fuse box; light or put out the fireplace (relighting costs a plank); a room's wall switch or a lamp; drink at the kitchen sink, eat from the fridge; inspect or repair the car; take the stairs; at the lot edge, head into the fog |
| I / Tab | Inventory and equipment (1–8 + **Bar** puts an item on the quick-access bar) |
| M | Region map (Esc or M closes it) |
| O | House overview (at home): 1–4 modes, PgUp/PgDn levels, Z/C turn, O/Esc leave |
| K | Skills and research |
| B | Build mode (see below) |
| Mouse wheel | Zoom |
| Z / C | Turn the view 90° left / right around you (WASD follows the screen) |
| V | Roofs: hide them (and the floors above you) or let them fade automatically when you go inside |
| Esc | Close a panel or leave build mode, otherwise pause (Resume, Save, Settings, Main Menu) |
| H / F1 | Controls hint |
| F3 | FPS line |
| F10 | Developer (cheat) menu |

**Build mode (B), Experiment 006 category menu:**
- **Categories (keys 1–8, or click the tabs):** 1 Walls · 2 Floors · 3 Doors · 4 Defence · 5 Furniture · 6 Utilities · 7 Decor · 8 Tools.
  - A key picks that category's last-used piece; press it again to step to the next one, or click a tile.
- **Direct tools:** **F** Repair · **X** Demolish · **G** Move · **Q** previous piece.
- **Tiles:** each tile shows its cost against what you have (carried + stored).
  - Locked pieces show a padlock and the skill they need.
  - Unaffordable pieces are dimmed, with the missing amounts in red.
- **Level:** **PgUp / PgDn** choose the level you build on.
- **What's in each category:**
  - **Walls:** wood and stone walls, stone foundation, timber footing, stone pillar.
  - **Floors:** wooden floor, stairs up and down, next storey, excavate.
  - **Doors:** wood, reinforced and metal doors, doorway, window boards.
  - **Defence:** barricades, wooden and metal spikes, dig trench, fill with water, backfill, 1- and 2-tile drawbridges.
  - **Furniture:** storage and furniture pieces.
  - **Utilities:** collector, workbench, fuse box, lamps, TV, radio.
  - **Decor:** rug, painting, plant.
  - **Tools:** repair, reinforce, demolish, move, remove window.

**R** rotates, **RMB** cancels, click-drag for wall runs.

**Levels (Experiment 005):** the house can grow to five levels.
- **The levels:**
  - −2 lower basement
  - −1 basement
  - 0 ground floor
  - +1 first upper floor
  - +2 second upper floor
- **Building them:**
  - Go up with stairs up plus "Next storey".
  - Go down by excavating, then stairs down.
- **Which level:** the card at the top right always shows your level. In build mode, **PgUp / PgDn** choose the level you build on without moving Eli.
- **Support:** higher levels rest on the outer walls below; pillars and inner walls can prop them.

**Furniture and storage:** press **E** at a cupboard, wardrobe, chest, shelf, tool cabinet, dresser, nightstand or the fridge to open its storage.
- Moving items: Put and Take move them between the storage and the household supplies.
- Stored items are kept aside: building and crafting use only what's out.
- Destroyed storage leaves a **pile of belongings** to search with E.

**Comfort and mood:**
- **Comfort:** each room has a comfort level from its furniture, light, daylight, the fireplace and its condition. Repeated pieces count less and less.
- **Mood:** Eli's mood drifts with comfort, needs, sleep and events. It changes how well he rests.
- **Where to see them:** the HUD shows the room and mood in two short lines. **I → Home** explains the factors and gives hints.

**Defences (Experiment 006):**
- **Spikes:** wooden or metal; they hurt enemies who push or swing against them.
- **Moats:** dig trenches outside with the shovel, then fill them with water. Filling is free next to a rain collector, or costs 1 bottle per 4 cells. Only brutes wade through water; dry trenches slow everyone.
- **Drawbridges:** 1 or 2 tiles across a trench. **E** raises and lowers them; when raised, enemies have to bash through.
- **You can't seal yourself in:** the game refuses changes that would cut off your last way out.

**Research (K):** read skill books found while scavenging (mostly at the new Public Library) to learn Woodworking → Reinforced construction → Metalworking → Advanced metal fabrication. These unlock drawbridges, reinforced doors and iron barricades, metal doors and metal spikes, and iron plating.

**Building from storage:** building, repairing and upgrading also take materials stored in your cupboards, chests and shelves. Eating, the quick bar and crafting still use only what you carry.

**The house has ears (Experiment 007):**
- **Noise:** hammering, drilling, smashing, gunfire, alarms and explosions make noise that nearby enemies hear. It's muffled in central rooms and basements, louder outdoors and through open doors and breaches. Noise never spawns enemies.
- **Stragglers** on ordinary nights may pass by, look in a window, test a door or lose interest. They turn hostile when provoked.
- **Room visibility:** you see the room you're in. Rooms behind closed doors hide their contents (enemies included) until you open the door.
- **O: the house overview.** Four modes (1 complete, 2 roofless, 3 cutaway, 4 blueprint), PgUp/PgDn for levels, Z/C to turn, O/Esc to leave.
- **Observation holes:** put the drill on the bar and use it on a wooden wall, door or barricade; it takes time and makes noise. At the hole, **E** looks through and **F** covers it.
- **Electronic security** (research Basic Electronics → Automated Defense Systems; electronic components from scavenging):
  - **Motion sensors** send a toast, a blinking marker and an optional alarm.
  - **Turret mounts:** install your own handgun or shotgun and fill its ammo box with real ammunition. Without the auto-loader upgrade (45 game minutes to install), you reload it by hand.
  - **Settings:** E at either one opens its panel.

**Audio inbox:** drop sounds into `assets/audio inbox/`; the existing upload in `assets/audio/_inbox/` is read too. Descriptive names map to game sounds automatically (see `assets/audio inbox/README.md` and `docs/experiment-005/AUDIO.md`).

**Replacing walls:** pick the other material and build over an existing wall (yours or the house's). It is one action: the old wall comes down with its usual refund (yours in full, the house's as salvage), the new one is paid, and only the difference changes hands. If you can't pay the difference, or the new wall can't stand there, nothing changes. Iron plating stays on. In a run, empty sections are built, other walls replaced, and doors, windows and walls already of that material are skipped. It works upstairs too.

### Developer menu (F10)

It doesn't pause the game. While any cheat is on, a **CHEATS ACTIVE** badge shows. Every button goes through the real systems.

- **Toggles:** invulnerability, unlimited resources.
- **Supplies:** food and water, medical, ammunition, the shotgun and shells, fill magazines, vest and gear, construction materials (+10 planks, stone, iron or scrap), all tools.
- **Needs and time:** set needs; advance an hour; skip to night or morning; time ×1 / ×4 / ×10.
- **Difficulty:** Easy, Normal or Hard.
- **Threats:**
  - next invasion;
  - spawn a psycho, runner, brute or bomber;
  - compose a wave and start it.
- **Map and missions:** run a mission now (any place and approach); reveal all places.
- **House:** repair everything.
- **Inspector:** game and save state.

Cheats are saved with the run. A new game always starts with them off.

### Saving: where and how

The save is `user://savegame.dat`, plus a `.bak` of the previous good save. On Linux that's `~/.local/share/godot/app_userdata/Sirens Went Quiet/`; on Windows, `%APPDATA%\Godot\app_userdata\Sirens Went Quiet\`.

- **What it holds (schema 2):**
  - the clock, stats, difficulty, inventory, equipment, magazines, cheats and invasion progression;
  - the region (known places, stock, visits, lasting consequences, the plan);
  - the player's position;
  - the house: voxel damage and construction, including materials, plating, foundations and blast scorch marks;
  - doors, barricades, crates, collectors and workbenches, with their HP and open state.
- **How it's written:** a temporary file first, which is checked before it replaces the save. If the main file is damaged, the backup is used. Schema 1 saves (Experiment 002) are migrated when loaded.
- **Limitations:**
  - You can't save while asleep, during an expedition or during an invasion, so a live fight is never stored.
  - Death deletes the save.

## Replace the art and the sound

Claude-made fallbacks live in `assets/**/template_*`. Put your own file with the same logical name (without `template_`) in the `custom/` folder, mirroring the subfolders, then restart the game:

- Graphics: `custom/graphics/<dir>/<name>.png`, e.g. `custom/graphics/props/wood_grain.png` or `custom/graphics/voxel/siding.png`.
- Audio: `custom/audio/<group>/<name>.ogg` (or `.wav`), e.g. `custom/audio/weapon/shotgun_fire.ogg`.

A missing or broken override falls back to the template with a warning; it never crashes. The same `custom/` folder next to an exported Windows/Linux game will work the same way, but this is untested because nothing has been exported. Files in `custom/` are yours and are never touched by the project. See `assets/README.md`.

The logical names are listed in `docs/experiment-002/audio.md`, `docs/experiment-002/props.md`, `docs/experiment-002/world.md` and `docs/experiment-001/voxel.md`.

## Docs

- `docs/experiment-012/REPORT.md`: the Experiment 012 report; `COMPLETION_AUDIT.md` (every requirement's status and evidence), `STORY.md` (the chapter's staging); `docs/audio/AUDIO_REQUIREMENTS.md` (missing recordings and triggers)
- `docs/experiment-011/REPORT.md`: the Experiment 011 report (voxel people for every enemy, the showroom); `HUMANOIDS.md` (how to add a humanoid)
- `docs/experiment-010/REPORT.md`: the Experiment 010 report (the handcrafted voxel Eli)
- `docs/experiment-009/REPORT.md`: the Experiment 009 report (two-stage POI generation, archetypes, daily availability, exteriors, stashes, apartments, dormant psychos, loading; scenarios A–H)
- `docs/experiment-008/REPORT.md`: the Experiment 008 report (the verified loop, three new places, looting, POI-to-POI travel, encounters, the first week; scenarios A–D); `PACING.md` (first-week resource pacing)
- `docs/experiment-007/REPORT.md`: the Experiment 007 report (playable scavenging, noise, visibility, overview, holes, security); `AUDIO_REQUIREMENTS.md` (what to record next)
- `docs/experiment-006/REPORT.md`: the Experiment 006 report (Defensive Living)
- `docs/experiment-005/REPORT.md`: the Experiment 005 report (A House Worth Living In); `AUDIO.md`, `AUDIO_REQUIREMENTS.md` (what to record next)
- `docs/experiment-004/REPORT.md`: the Experiment 004 report (Make This House a Home)
- `docs/experiment-003/REPORT.md`: the Experiment 003 report (what was built, tests, the playtest, limitations, screenshots)
- `docs/HANDOFF_EXP004.md`: the state of the code for the next milestone, and what to reuse
- `docs/experiment-003/`:
  - `ASSIGNMENT.md`, `SPEC.md`
  - module docs: `equipment.md`, `construction.md`, `ai.md`, `scavenging.md`, `map.md`
  - `game.md` (the integration)
- `docs/experiment-002/`:
  - `REPORT.md`, `SPEC.md`
  - module docs: `game.md`, `survival.md`, `world.md`, `VOXEL_RESOLUTION.md`, `props.md`, `expeditions.md`, `ui.md`, `audio.md`
- `docs/experiment-001/`: the visual technology experiment and `COMPARISON.md` (history)
- `docs/PROJECT_BRIEF.md`: confirmed decisions and the approved objective
- `docs/BACKLOG.md`: observations deferred during work (not approved tasks)
- `CLAUDE.md`, `docs/GODOT_CLAUDE_GUIDELINES.md`, `docs/DESIGN_WORKFLOW.md`: how work on this project is done

## Tests and checks

```bash
godot --headless --path . --import
godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd
```

Add `-- --filter=<text>` to run only the tests whose file or method name contains it.

Through the real renderer (Linux, Xvfb + software Vulkan, slow but deterministic):

- `tools/survival_playtest.sh [out dir]`: the integrated acceptance playtest. It runs in two processes (a new game through save and quit, then continue and verify), with real input events and screenshots. Under software rendering it takes about an hour.
- `tools/playtest.sh <1|2|3>`, `tools/compare.sh <1|2|3>`: Experiment 001 demo checks.
- `tools/capture.sh <res://scene.tscn> <out.png> [seconds] [args]`: one screenshot. Under software rendering, pass `CAPTURE_ENGINE_ARGS="--fixed-fps 30"`.
