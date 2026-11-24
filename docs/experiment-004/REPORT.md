# Experiment 004 — Make This House a Home: report

**Delivered:** 2026-11-24, on `claude/practical-heisenberg-mjc1xx`, as the playtest checkpoint `playtest/exp004-house-home`. The Windows build is a GitHub Actions artifact (workflow "Windows build").

**Mode:** Rapid Delivery. Four agents worked in parallel (D, L, H, E) and the lead integrated and verified the basics. Not played by a human; the user playtests.

## What was built (by the user's sections)

| § | What | Where |
|---|---|---|
| 1 | Destruction lifecycle. Intact furniture is a mesh plus a box. On first damage it becomes voxels in the house grid, which break off piece by piece. Destroyed pieces become low static rubble with no collision. Settled debris stops updating, and debris stays capped at 700 chips with no physics bodies. Stress test: 30 blasts and 300 shots; blasts dropped from 130 to 77–91 ms average, shots from 6 to 3 ms, and nodes and debris stayed flat. | `src/world/house_furniture.gd`, `house_world.gd`, `voxel_fx.gd` |
| 2 | Live main-menu siege: the real house, lighting and AI with no player. Each round varies the yard walls, boards, plating, pre-damage, time of day and camera side. Up to 7 enemies of all four types. A new round starts at 35 % of walls broken or after 4 minutes. A round builds in about 0.5–0.8 s and the simulation costs about 1.6 ms a frame (headless). It uses the northern look. | `src/menu/menu_siege.gd`, `main_menu.gd` |
| 3 | Northern atmosphere:<br>- far-north palette; darker days, much darker nights;<br>- northern lights on about 70 % of nights, as curtains at the top of the frame plus green-tinted night light and fog;<br>- snow on the ground, roof and props, falling snow;<br>- pines on the lot and in the fog;<br>- a cold fog bank and a snowy region map with ice;<br>- a brick fireplace, lit at the start, independent of power. | `src/home/`, `src/voxel/voxel_lighting.gd`, `voxel_yard.gd`, `src/props/`, `src/map/` |
| 4 | Destructible and demolishable furniture: 28 types, each with HP and salvage. Original walls, windows, doors, the fuse box and floor tiles give salvage. The player's own pieces refund in full. The last-exit rule is kept. | `house_furniture.gd`, `build_mode.gd`, `build_pieces.gd` |
| 5 | Electricity: fixtures in every room, wall switches, the lamps' own switches and a fuse box in the utility room. A light shines only if its own switch, its room switch, the fuse box and the mains are all on. The fuse box (20 HP) can be shot, struck or blasted. It is rebuilt on build key 6 (6 iron, 8 scrap, 4 nails; only one). | `src/home/home_electrical.gd`, `game_home.gd`, `world_object.gd` |
| 6 | Quick-access bar: 8 slots on keys 1–8, X empties the hands, LMB uses the item. It holds weapons, tools (the flashlight is a cone light), food, water, bandages and medkits. With nothing in hand the arms hang. The layout is saved. | `src/survival/hotbar.gd`, `src/ui/hotbar_bar.gd`, `src/game/game_hotbar.gd`, `voxel_rig.gd`, `weapon_handler.gd` |
| 7 | Pine Woods: the 25th place, a wood source, known from the start, on the map.<br>The car: repair needs a battery, 2 fuel, 10 scrap, 4 iron and 6 nails, plus 2 h. Repaired, it is expedition gear: 1 fuel per trip, travel ×0.6, loot ×2 and materials ×1.5. The new items `car_battery` and `fuel` are found while scavenging. | `src/region/`, `src/expedition/`, `src/game/game_car.gd` |
| 8 | Doors: closing steps the player clear instead of refusing. Window boards (key 2), metal doors (key 3, 70 HP), and reinforcing a door with key 8 (wood → reinforced → metal). All take part in shots, blows, blasts, bomber targeting and repair. Bullets now damage objects. | `world_object.gd`, `house_world.gd`, `build_mode.gd` |
| 9 | Levels on build key 0 (Floors & levels): wooden floor tiles, stairs up and down, the upper floor (40 planks, 40 nails, 4 iron), and basement excavation with a shovel (25 min, 6 energy and +1 stone per 1 m cell). Each storey is its own `LevelWorld`, so building, damage and repair work on it. The player moves between storeys by the stairs with a fade. Storeys above are hidden. Chasing enemies follow the player by the stairs; bombers stay on the ground; nothing hits through a floor. | `src/levels/` |
| 10 | Sink: drink (+30 water, 1 min). Fridge: eat from the stored food. Both only while the furniture is intact. Shift sprints (×1.6, extra energy drain). | `src/home/household.gd`, `voxel_player.gd` |
| 11 | Persistence:<br>- **Optional fields, same schemas:**<br>&nbsp;&nbsp;- world: `furniture`, `exp4`, `levels` (storeys, stairs, laid floor tiles, dug cells), fuse box `mains_on`, `boards`, metal doors;<br>&nbsp;&nbsp;- game: `player.storey`;<br>&nbsp;&nbsp;- state: `hotbar`, `car_repaired`, `home` (fire, lights, rooms).<br>- **Older saves:** they load with intact furniture, a pristine fuse box and the ground floor only. | |
| 13 | Windows build: `export_presets.cfg` and `.github/workflows/windows-build.yml`. Every push to `claude/**` or `playtest/**` exports `SirensWentQuiet.exe` (embedded pack) with an empty `custom/` folder and a README, as an artifact kept 30 days. | |

**F10 additions:**
- **House:** destroy furniture, damage doors, toggle or destroy the fuse box, 10 debris blasts, repair everything.
- **Levels:** give a shovel, build the upper floor, dig a 3×3 basement, go to a storey.
- **Home:** fireplace, all lights on or off, northern lights tonight, time 23:00, snow on or off.
- **Car and quick bar:** car parts, repair the car, bar test kit.

## Verification (basic, as asked)

- **Headless test suite:** 413 passed, 0 failed, on the merged branch. Each agent added a few focused tests and one game-scene smoke test.
- **Export:** the Windows export succeeds locally (122 MB `.exe`) and in GitHub Actions.
- **Exported pack:** run headless with the Linux engine, it boots the main menu (with the live siege) and a new game with no script errors.
- **Rendered checks:** frames from the game at 23:00 (the dark snowy lot, northern lights, the warm interior, the fireplace, the bar) and from the main-menu siege were looked at.
- **Save and load:** covered by the suite, including continuing on the upper floor, the furniture states with older saves, and the bar and car fields.
- **Not done:** no long automated playthrough, as instructed. The Windows `.exe` itself was not started (no Windows machine here). Sounds not listened to. No real-GPU timing.

## Known limitations

- **Levels:**
  - Stairs are a fade-teleport (no ramp collision).
  - Blasts and enemy blows don't damage the upper floor or the basement.
  - No structural support: the upper floor stands even if the ground walls go.
  - Ground-floor holes don't open into the basement.
  - The basement has no ceiling or lights (it is lit like the cutaway).
  - Excavating needs build mode, which also needs the hammer.
  - The electric fixtures are on the ground floor only.
- **Furniture:**
  - A damaged piece switches from the mesh look to the 0.1 m voxel look.
  - Enemies may smash through furniture rather than walk around it (by design, untested).
  - Window boards always cover 0.85–2.15 m.
- **Fireplace:** its navigation block and the stairs' use a private house-world array, and build mode can place a wall over the fireplace.
- **Car and expeditions:** the expedition list checks departure time on foot, so a place reachable in time only by car can show as unavailable.
- **Bar:** selecting a weapon that is on the bar but not equipped equips it.
- **Sink:** the optional "fill a bottle" isn't done.
- **Fuse box:** hard to read as wall-mounted from the fixed camera.
- **Balance and look:**
  - Balance (salvage, costs, car, forest, sprint drain) is a first pass.
  - The aurora strength and snow were judged from a few software-rendered frames.
- **Earlier experiments' limitations still apply:** see `docs/BACKLOG.md`.

## Time

- **Estimate at the start (20:31 CET):** 10–12 hours; the Windows build around 08:00 CET (range 03:00–14:00).
- **Actual:** the final delivery report gives the actual time. A usage-limit stop paused all agents for about 40 minutes.
