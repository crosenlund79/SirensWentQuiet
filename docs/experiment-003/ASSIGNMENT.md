# Experiment 003 — Foundations of Survival (queued assignment, verbatim summary)

**Status:** approved by the user on 2026-11-24 as a **queued** objective. It starts automatically only after Experiment 002 has been genuinely delivered: integrated, playtested, documented, committed and pushed. The two milestones must not overlap. If the session ends first, this assignment remains pending.

This file preserves the user's assignment so it isn't lost between sessions. The user's message is the authority; this is a faithful condensed record of it.

## Execution order (Phase 0)
- Finish all Experiment 002 work first: let any active agents finish, integrate, fix regressions, complete the acceptance checks and the integrated playtest, finish the docs and the delivery report, and commit and push.
- Don't redirect Experiment 002 agents, don't restart running agents, and don't launch duplicates.
- Then give the Experiment 002 completion report (final SHA, known limitations), verify the repository, and proceed autonomously with Experiment 003. No further approval is needed for that transition.

## 1. Objective
Shift the emphasis from making 3D models and artwork (these will come from the separate **SirenVoxelLibrary**) to the fundamental gameplay systems of a complete survival game, each with one or two representative implementations. The result should be a functional vertical slice, not a content library. Extend Experiment 002; don't rebuild it.

Priorities:
- equipment and inventory;
- weapons and ammunition;
- construction and resources;
- day/night, sleeping and survival;
- a flexible enemy AI foundation;
- several enemy types, including suicide bombers;
- difficulty settings and escalating invasions;
- a larger simulated scavenging system;
- an interactive voxel city map;
- persistent world state and save/load.

## 2. Equipment and inventory
- **Categories:** weapons and ammunition, tools, protective equipment, utility equipment, medical supplies, food and water, construction resources.
- **Slots:** practical slots for weapons, tools and protective or utility gear.
- **Real effects,** for example:
  - a backpack increases carrying capacity;
  - a flashlight improves certain expedition choices;
  - a protective vest reduces incoming damage;
  - a crowbar unlocks alternative scavenging options.
- Build the underlying definitions and interactions, with only a few working examples. Don't create dozens of placeholder items.
- **Weapons:** keep the handgun and add one more type (e.g. a shotgun). Provide the foundation for weapon switching, ammunition types, magazine capacities, reloading, fire rate, damage and inventory ammunition. Use simple temporary visuals, with no customization or detailed firearm modelling.

## 3. Construction and resources
Keep the voxel structural technology and the building system.

**Resources:**
- **Wood:** basic building, barricades, repairs.
- **Stone:** masonry, foundations, stronger defences.
- **Iron:** reinforcement, stronger components.
- Keep planks, nails and scrap where appropriate, with a coherent distinction between raw materials and usable construction resources. No crafting tree yet.

**Building:** one or two working examples from each class:
- walls;
- floors or foundations;
- doors and openings;
- barricades;
- storage;
- functional equipment;
- structural upgrades and repairs.

Demonstrate at least two structural material strengths. Keep:
- grid snapping, clear previews, drag-placed wall runs;
- collision validation, material costs;
- structural voxel damage, navigation updates, persistence.

Prepare the structural-section system for future load-bearing calculations, but no collapse simulation yet. Construction-grid resolution stays independent of voxel-damage resolution.

## 4. Survival, time and sleeping
- Consolidate hunger, hydration, health, energy, sleep and the clock so they behave consistently.
- Expeditions consume time and affect needs.
- Sleep advances time without skipping scheduled attacks, and danger interrupts it.
- Food, water and medicine have meaningful uses.
- Rates stay forgiving.

## 5. Enemy AI foundation (major priority)
A reusable AI with shared behaviours and specialised roles. Don't duplicate the whole AI per type, and reuse and improve Experiment 002's navigation and pursuit.

Shared behaviours:
- target selection, navigation, obstacle recognition;
- attacking doors, barricades and walls; reacting to new breaches;
- attacking the player, taking damage, death;
- taking part in coordinated waves.

Archetypes:
- **A. Ordinary psycho:** the baseline.
- **B. Runner:** fast, aggressive and fragile; prefers existing entrances and openings.
- **C. Brute:** slow, tough and destructive; a serious threat to wooden barricades and walls.
- **D. Suicide bomber:**
  - It deliberately targets the house's defences and structural walls, not the player, seeking vulnerable or strategically useful points of entry.
  - Near its target it starts a visibly and audibly telegraphed detonation.
  - The explosion damages a local structural area and nearby barricades and doors, and injures nearby characters. It can create a new opening, updates navigation and leaves persistent damage.
  - The player gets a reasonable chance to spot and stop it.
  - Its behaviour is fictional and abstract (no real-world explosive detail), and its wall-targeting is demonstrably different from the other types.

## 6. Difficulty and invasion director
- **Levels:** Easy, Normal, Hard.
- **Difficulty affects:** enemy counts, health and damage; invasion frequency and composition; resource availability; scavenging danger.
- **The director** is reusable and works from: the day, the difficulty, invasion progression, enemy types, and a configurable threat budget.
- **Bombers** appear mainly on harder difficulties and in later invasions, never in the opening days on Easy.
- Every enemy type can be spawned individually from F10.
- The first waves stay small.

## 7. Simulated scavenging, expanded
The house and lot are playable; everything outside is a simulated expedition.

**Framework:** a reusable destination framework, in which the mission purpose affects risk, duration and rewards.
- **Approaches:** general scavenging, targeted resource collection, careful exploration, high-risk raid.
- **Equipment** influences the options and outcomes.

**Destinations:**
- **Construction:** forest/logging area (wood); sawmill/lumberyard (processed wood, tools); quarry (stone); construction site (wood, stone, iron); scrapyard (iron, scrap); industrial warehouse (mixed).
- **Weapons and ammunition** (generally high-risk): gun shop; shooting range (ammo, protective gear); police station (weapons, ammo, protective gear); military outpost (rare equipment; especially dangerous; needs preparation).
- **Medical:** drugstore/pharmacy; clinic; veterinary clinic; hospital.
- **Food and water:** restaurant; diner; fast-food restaurant; supermarket; convenience store.
- **Family houses:** small amounts of many types; occasionally ammo; rarely a weapon. Vary the residential properties rather than giving them one generic table.

**Each destination has:** travel time, risk, relevant equipment, potential loot, search duration, simple decision events, and persistent availability or depletion. Dangerous places are rewarding without guaranteeing success. Loot profiles and mission purposes are data-driven, with no custom code per location.

## 8. Voxel city map
An interactive strategic map of the region: a miniature 3D representation for understanding the region and choosing expeditions. It is not a second playable world.

- **Terrain:** coarse voxel terrain with rolling hills, mountains, rivers, a bay or coastline, forests, roads, residential, commercial and industrial districts, and remote facilities. The geography is logical:
  - roads connect locations;
  - quarries sit near the mountains;
  - the harbour relates to the bay;
  - the police station, hospital, shops and housing are placed sensibly;
  - the player's house has a recognisable place relative to the city.
- **Look:** an atmospheric miniature landscape, not a debug view. Simple voxel masses for buildings; what matters is readable geography, districts and destinations.
- **Clouds:** slowly drifting clouds that let the terrain show through gaps, with shadows or tonal variation where practical, without hurting usability. A lightweight shader or layered approach is fine.
- **Interaction:** open the map, pan and zoom, find the house, select destinations, see travel time, risk and potential resources, choose a mission purpose, and inspect equipment requirements. The map is inspectable at home.
- **Departure** still happens by walking into the fog at the property boundary. The map and the expeditions use the SAME location definitions (no two lists).
- **Persistence:** the region seed or layout identity, discovered locations, destination resource states and persistent mission consequences. Prefer one attractive deterministic region (partly authored, with procedural detail) over endless generation.

## 9. Progression foundations
Scavenge → obtain resources → equip and build → defend → survive → explore further.
- Wood strengthens basic defences, stone enables tougher walls, and iron improves reinforcement.
- Ammunition improves readiness, medicine aids recovery, and equipment makes harder missions achievable.
- Keep crafting and upgrades extensible, with no huge tech tree.

## 10. Save game and developer tools
**Save:** extend persistence to cover stats, inventory, equipment, weapons and ammo, difficulty, house structure and damage, the day and time, invasion progression, map state and discoveries, and scavenging consequences. Handle older save versions sensibly.

**F10 developer menu:** keep it, and add:
- wood, stone and iron;
- weapons and ammunition; equipment;
- difficulty;
- individual enemy types; invasion triggering;
- mission results; revealing map locations;
- time advancement; repairing the house.

These tools must test the real systems, not parallel logic.

## 11. Visual and asset policy
- No detailed models of furniture, weapons, trees, vehicles or decorative objects (there is a separate library for those). Reuse existing models and procedural visuals, with simple placeholders for new equipment and enemies.
- Focus on consistency, function and readability.
- The city map needs an attractive overall landscape, but its features stay simple.
- Don't integrate SirenVoxelLibrary assets unless separately instructed.

## 12. Implementation strategy
1. After Experiment 002, start with a short technical assessment of the existing systems and extension points.
2. Coordinate work across sensible module boundaries. Possible specialists: equipment, resources and construction; enemy AI, difficulty and director; scavenging locations and missions; the voxel regional map; integration, persistence, UI and testing.
3. Use agents where useful and avoid simultaneous edits to shared files.
4. No huge new framework, and no needless rewrites of working Experiment 002 systems. Connected, demonstrable mechanics come before decorative polish.

## 13. Vertical-slice acceptance
1. Start a game with a selected difficulty.
2. Wake in the existing house.
3. Inspect survival stats and equipment.
4. Equip and switch weapons.
5. Build with wood, stone and iron.
6. Open the voxel city map.
7. Explore its hills, rivers, bay, roads and districts.
8. Watch clouds move over the landscape.
9. Select a scavenging location.
10. Enter the fog and begin a simulated expedition.
11. Collect targeted construction resources.
12. Return home and use them.
13. Visit a riskier destination for ammunition or medical supplies.
14. Experience equipment-dependent mission decisions.
15. Sleep and advance the clock.
16. Fight enemies with distinct AI behaviours.
17. Watch a suicide bomber deliberately attack a wall.
18. Experience persistent damage and repair it.
19. Save and leave the game.
20. Reload with the house, inventory, difficulty and regional map state intact.

Run focused tests and an integrated playthrough. Verify the real game camera and UI. Capture representative screenshots, especially of the **voxel city map**, enemy behaviours and construction.

## 14. Final delivery
- Commit and push to the authorized working branch. Don't merge into `main`. No executable or installer without separate approval.
- Report: the Experiment 002 baseline commit, the Experiment 003 branch and SHA, implemented and reused systems, tests, integrated playtest results, screenshots, known bugs and limitations, and deferred work.

**Final instruction:** finish Experiment 002 first, completely. Then proceed with this approved Experiment 003 vertical slice if the session can continue. "The house is the playable world. The voxel city map represents the larger world. Expeditions connect them. Construction, equipment and defence make survival meaningful."
