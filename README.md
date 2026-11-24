# Sirens Went Quiet

*Working title.* Present day, after something nobody can explain. The grid is gone, the radio is silent and nobody has heard from another sane human since the sirens went quiet. You still have the house.

This repository holds **Experiment 004 — Make This House a Home**, built on Experiment 003 (Foundations of Survival) and Experiment 002 (The First Days). The house is your progression: scavenge, demolish, rebuild, reinforce, expand and keep it running. It is a survival game about one house on one lot, ringed by dense fog. **Experiment 001** (three ways to build a destructible house) is kept as history under *Visual Experiments*.

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
- **The region map (M, or the map on the dining table):** a voxel miniature of the region with drifting clouds and 25 places in five kinds: homes, food, medical, construction (including the Pine Woods, a wood source near home) and weapons.
  - Places you haven't found show as unknown.
  - Pick a place and a purpose to plan a trip; planning takes no game time.
- **The fog:** walk to the edge of the lot and press **E**. The expedition screen preselects your plan.
  - Approaches: general scavenging, targeted collection (much more of one thing), careful exploration (slower, safer, finds new places) and a high-risk raid.
  - Each trip costs travel time and has risk, loot and short decision events. Places run low when you strip them and slowly recover.
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
| B | Build mode (see below) |
| Mouse wheel | Zoom |
| Z / C | Turn the view 90° left / right around you (WASD follows the screen) |
| V | Roofs: hide them (and the floors above you) or let them fade automatically when you go inside |
| Esc | Close a panel or leave build mode, otherwise pause (Resume, Save, Settings, Main Menu) |
| H / F1 | Controls hint |
| F3 | FPS line |
| F10 | Developer (cheat) menu |

**Build mode** (press a class's key again to switch its variant):

| Key | Class | Variants |
|---|---|---|
| 1 | Walls | wood, stone; build straight over a wall of another material to replace it |
| 2 | Barricades | wood, iron, window boards (on a window) |
| 3 | Doors | wood, reinforced, metal |
| 4 | Doorway | |
| 5 | Storage | crate |
| 6 | Equipment | rain collector, workbench, fuse box (only when none exists) |
| 7 | Repair | |
| 8 | Reinforce | iron plating; on a door: wood → reinforced → metal |
| 9 | Demolish | anything: your own pieces refund in full; furniture, original walls, windows, doors and floor tiles give salvage |
| 0 | Floors & levels | stone foundation, wooden floor, stairs up, stairs down, upper floor, excavate (needs a shovel) |

**R** rotates, **RMB** cancels, click-drag for wall runs.

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
