# Experiment 005 — A House Worth Living In: report

- **Branch:** `exp005/house-worth-living-in`. It builds on Refinement 01 and the user's audio upload.
- **How it was built:** autonomous overnight work in Rapid Delivery mode. Four agents worked in parallel (V levels, F furniture, C comfort and mood, A audio) and the lead integrated their work.
- **What wasn't done:** no executable and no Windows CI build. Nothing was played by a human, and no sound was listened to by ear.
- **Launch:** open `project.godot` in Godot 4.7 and press F5.
- **Testing quickly:** F10 has sections for Levels, Furniture, Comfort & mood and Audio.

## 1. Five levels (V)

- **Levels:**
  - −2 lower basement
  - −1 basement
  - 0 ground floor
  - +1 first upper floor
  - +2 second upper floor

  One set of rules applies to all of them. Each level is a `LevelWorld` (a `HouseWorld`), so building, damage, repair, demolition, furniture and saving work the same everywhere. Nothing goes below −2 or above +2, and nothing is given automatically.
- **Building on key 0 ("Floors & levels"):**

  | Piece | Cost | Rule |
  |---|---|---|
  | Stairs up / down | 8 planks + 10 nails | Up from level 0 or higher; down over 3 dug cells in a line |
  | Next storey | 40 planks + 40 nails + 4 iron | Builds the level above: deck, outer walls, windows. Needs stairs up and outer walls that carry it. |
  | Excavate | shovel; 25 min, 6 energy | +1 stone per 1 m cell. −1 under the house, −2 under dug −1 cells. |
  | Stone pillar | 4 stone | |
  | Wooden floor | 2 planks + 2 nails | Only where it's held up |

- **Which level am I on:**
  - an indicator card at the top right ("Level +1 · First upper floor");
  - in build mode it reads "Building on …", and **PgUp / PgDn** change the level being built on without moving Eli;
  - the levels above are hidden, the camera lifts to the chosen level, and underground build mode shows a floor plan.
- **The roof** sits on the topmost level. It fades indoors, the V key toggles it, and it is always hidden in build mode, so it never gets in the way of building.
- **Support:**
  - Each level's outer walls carry the levels above it. A failing zone brings down the decks, walls and objects above it.
  - Inner walls up to 2 m inside, and pillars up to 2.5 m inside, prop an outer wall.
  - On +1 and +2, floor tiles are held up through a support grid.
  - Support is recomputed when something changes, never every frame.
- **Enemies** follow the player level by level using the stairs (tested down to −2). They wait 0.6 s after changing level and drop through holes.
- **Saving:** level data version 2; Experiment 004 saves map onto it.

## 2. Functional furniture (F)

- **Storage:** press E at a storage piece, and the game pauses on a panel:
  - Put 1 / all, Take 1 / all, Take everything;
  - Eat, Drink or Apply directly from a container.
- **Capacities** (in items):

  | Piece | Capacity |
  |---|---|
  | Chest | 80 (anything) |
  | Shelves | 60 |
  | Tool cabinet | 60 |
  | Cupboard | 30 |
  | Bookshelf | 30 |
  | Fridge | 24 (food and water) |
  | Wardrobe | 24 |
  | Dresser | 20 |
  | Nightstand | 8 |

  The house's own counters, island, boxes and vanity are containers too. A new game starts with a little food in the fridge and a few nails on the shelves.
- **Inventory rule:** stored items are kept aside. Building, crafting, the bar and expeditions use the household supplies; the panel says so. Transfers are atomic and can't duplicate or lose items (tested).
- **Destroyed or demolished storage** drops a "Pile of belongings" (E to search). Piles merge with nearby piles and are saved.
- **Key 5 ("Furniture & storage")** places 19 types:
  - storage: cupboard, chest, tool cabinet, wardrobe, shelves, bookshelf, dresser, nightstand;
  - furniture: bed, sofa, armchair, chair, table, coffee table, rug;
  - light and decoration: floor lamp, table lamp, painting, plant.

  Costs are in planks, nails and scrap. R rotates. Placement is validated (overlaps, walls, doorways, stairs, floor, people, the last exit).
- **Move** (key 5 again) picks up any piece, the house's own included, and sets it down elsewhere, on any level. It is free, and contents, HP and the lamp switch travel with it. Fixtures (sink, bath, toilet, stove, washer and so on) stay put.
- **Demolish:** your own furniture refunds in full; the house's gives salvage.
- **Placed lamps** shine only with power (fuse box and mains). Built beds can be slept in.

## 3. Comfort, rooms and mood (C)

- **Rooms:** found by flood fill on every level. Walls, windows, doors and boards bound them; a room open to the outside is "exposed".
- **Labels** come from contents: Bedroom, Kitchen, Living room (the default house has an open "Kitchen & living room"), Bathroom, Workshop, Storage room, Hallway, Room.
- **Comfort per room** draws on:
  - furniture by category, each repeat worth half the one before, with caps (twenty chairs are worth about two);
  - furnished / bare;
  - finished floor or bare earth;
  - lamp light;
  - daylight through intact windows;
  - boarded, broken or missing windows;
  - darkness;
  - the fireplace (+6 in its room, +2.5 next door);
  - exposure, damaged walls, wrecked furniture.

  It is recomputed on events only.
- **Comfort words:** Miserable · Uncomfortable · Content · Comfortable · At home.
- **The starting house** is about 25, "Comfortable"; a fresh basement is "Miserable". A lit, furnished basement with a floor reaches "Content".
- **Mood** (Eli, 0..100, starts at 58 "Content") drifts every 5 game minutes toward a target:
  - house comfort;
  - the fire;
  - being fed and watered;
  - hunger, thirst, exhaustion, injury;
  - cold, exposed rooms, darkness;
  - fading memories of events (attacks, blasts, a safe return, a good or bad sleep).
- **Mood bands:** Miserable · Low · Content · Good · Cheerful.
- **Mood's effect:** sleep restores energy × 0.75–1.35, from mood and the comfort of the room you sleep in. That is its only effect; it never replaces health or energy.
- **UI:** two short HUD lines ("Bedroom · Comfortable", "Mood: Good"). The **I → Home** tab shows factors, hints, mood causes and the house by level.

## 4. Audio (A)

- **The inbox:** `assets/audio inbox/` is the drop folder (see its README). The existing upload in `assets/audio/_inbox/` is read too; nothing was moved.
  - Descriptive filenames map to game sounds; numbered variants form random pools.
  - Precedence: `custom/` → inbox → generated templates.
  - Unknown or ambiguous files are reported (log, F10), never assigned at random.
  - All 64 uploaded files are mapped: details in `AUDIO.md`.
  - Runtime analysis trims silence, levels clips, sets loops and slices footsteps.
- **Layered ambience:**
  - outdoor bed (forest, wind);
  - indoor mix (outdoor sounds turned down and muffled, room tone);
  - basement mix (more muffled);
  - fireplace (positional, only while lit);
  - details: owls and wolves at night, house creaks indoors;
  - threat dip during invasions;
  - music: the theme on the menu, and softly for 95 s after dawn.
- **Footsteps:** snow / wood / cement single steps sliced from the recordings, timed to the walking animation, stopping when Eli stops. Enemies step on snow outdoors.
- **Eli's voice:** "Welcome to a new game" after the new-game intro, "Continue saved game" on Continue. Never overlapping, and the ambience and music duck under it.
- **What to record next:** `AUDIO_REQUIREMENTS.md`, groups A–E with filenames, places, prompts, durations, loop flags, priorities and status.

## Verification

- **Tests:** the full suite on the merged branch: see the final commit message.
- **Each agent's new tests:**
  - `test_five_levels`: the in-game flow on all five levels, building upstairs through the real camera, save and continue.
  - `test_storage` and `test_storage_lamps`.
  - `test_comfort`: in-game rooms, HUD, the Home tab, save.
  - `test_audio_inbox`, `test_audio_layers` and `test_audio_game`.
- **Boot check:** the main menu and a new game boot headless without script errors.

## Known issues and limits

- **Levels:**
  - Upper levels are whole decks over the house footprint, made by "Next storey". Single tiles only fill held holes; nothing is built outside the footprint.
  - Dev repair doesn't restore a collapsed roof or fallen decks.
  - Pillars can't be repaired with the Repair tool.
  - Walls on upper levels don't check what stands under them.
  - No fall damage.
- **Furniture:**
  - Capacity counts items: a nail weighs as much as a plank.
  - Crates still raise caps rather than store things.
  - A moved house piece becomes a mesh object, keeping its HP fraction but losing its voxel damage.
  - Placed furniture doesn't fall through a hole cut under it.
  - F10 "Repair everything" can restore a moved house piece at its old spot as well.
- **Comfort:**
  - Rooms need a floor.
  - The player can't build windows, so only original and upper-level windows count.
  - The fireplace is fixed on the ground floor.
  - The calibration is a first pass.
- **Audio:**
  - Not listened to. Onset slicing may give a weak or double step.
  - Room-tone and basement-tone layers are silent until recorded.
  - The shotgun shares the handgun reload.
  - There's no Voice volume slider (Master scales it).
- **Carried over:** the general limits from Experiments 002–004 and Refinement 01 (`docs/BACKLOG.md`) still apply.
