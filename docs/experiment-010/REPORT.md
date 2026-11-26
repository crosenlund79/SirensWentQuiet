# Experiment 010 — The Human Element: report

This is a rapid visual experiment: a handcrafted voxel Elias "Eli" Walker in the real game, with the original character kept as a fallback.

- **Branch:** `exp010/the-human-element`.
- **Windows build:** the `playtest/exp010-human-element` branch is built by GitHub Actions; the portable ZIP is the "Windows build" artifact.
- **Reference image:** the attached reference image wasn't available to this session, so the written art direction was followed.

## What was made

**Eli** is a 41-year-old carpenter, about 1.81 m tall (the original is about 1.8 m).
- **Build:** the head is about 15 % oversized, with sloping shoulders, a narrow waist and slim, articulated limbs.
- **Voxel size:** 1.5 cm (the original uses 5 cm).

| Part | Details |
|---|---|
| **Face** | Whites, irises and heavy brows; crow's feet; a straight nose with a cold-reddened tip; a quiet smile inside a short beard; ears |
| **Hair** | Short and untidy dark brown, with a side part, a ragged fringe and grey at the temples |
| **Jacket** | Worn canvas work jacket with a corduroy collar, zipper, flap pockets, seams, an uneven hem, a back patch, a left elbow patch, and the right sleeve rolled up over a flannel lining and knit cuff |
| **Scarf and pocket** | A brick-red knitted scarf with one fringed end; a carpenter's pencil in the chest pocket |
| **Trousers** | Charcoal work trousers with a cargo pocket, a double knee and worn knees |
| **Belt** | Buckle, a leather tool pouch with a hammer, a tape measure, and a glove in the back pocket |
| **Boots** | Leather work boots with toe caps, laces, a welt and lugged soles |
| **Hands** | Open and fist versions, with a thumb and knuckles |

- **Variations:** Canvas jacket (default); Forest overshirt (olive, mustard scarf, dark hair); Grey morning (charcoal, rust scarf, grey hair, clean-shaven).
- **Animations:**
  - idle, with breathing, a weight shift and glances;
  - walk, jog and sprint, with leg IK and the feet planted at the real ground speed, strafing and backwards included;
  - handgun, held two-handed and aimed;
  - shotgun, with the butt in the shoulder and a hand on the pump;
  - the flashlight, tool, and eat/drink poses, plus recoil and stagger.
- **Technical:** 16 body meshes, about 70k vertices in total. They are built once per look (about 1.1 s at startup) and cached. Nothing is rebuilt per frame.

## Using it

- **Toggle:** Settings → Character ("Experimental Eli" and "Look"), or F10 → Character (Experimental Eli / Original character / Next Eli look). Both switch live, with no new game needed.
  - The choice is stored in the settings, not in the save game.
  - Eli is the default.
- **Showroom:**
  - **Where:** Main menu → Visual Experiments → "D Character Showroom", or F10 → Character → Character showroom.
  - **Animations:** Idle, Walk, Jog, Run, Handgun, Two-handed, Flashlight, Hammer, and a walk across the stage.
  - **Views:** 3/4, Front, Side, Back, Face, Turnaround, and **Gameplay distance** (the game camera).
  - **Options:** the variations, day or night with a lamp, and "Beside the original character".
  - **Controls:** drag or A/D to turn; wheel or W/S to zoom.

## Screenshots (`shots/`)

| File | What it shows |
|---|---|
| `final_sheet.png` | Front, 3/4, side and back |
| `final_face2.png` | Face |
| `final_cmp.png` | Beside the original |
| `gun1.png` | With the handgun |
| `sg1.png` | With the shotgun |
| `home_day_crop.png` | Gameplay distance at home by day |
| `hardware_crop.png` | Outside the Hardware Store |
| `hw_night_crop.png` | The Hardware Store at night |

## Known visual problems

- Curved surfaces show voxel steps as fine vertical streaks on the jacket and trousers, most visible under lamps at night.
- Hands are simple; the fist looks a little like a mitten.
- In profile the nose is a bit blocky and the hair a bit bulky.
- From the top-down game camera the face can't be read. Eli is recognisable by his hair, tan jacket, red scarf and dark trousers.
- The in-game screenshots show him from behind, because the screenshot tool ignores the facing at home. No running shot was taken in the game; the gait was checked in the showroom.
- Each look takes about 1.1 s to prepare, at startup and the first time a variation is chosen.

## Verification

- **Tests:**
  - `test_eli_character` (4);
  - `test_voxel`, `test_survival_game`, `test_hotbar` and `test_weapon`;
  - the dev menu, settings and main menu UI tests;
  - `test_versions_smoke`.
- **Headless boot:** the main menu, the game and the showroom start without script errors.
- **Not run:** the full suite, by request (minimal testing).
- **Windows build:** GitHub Actions run 9 succeeded. Artifact `SirensWentQuiet-windows-68e92c7…` (77.5 MB ZIP, kept until 2026-12-26): https://github.com/crosenlund79/SirensWentQuiet/actions/runs/45837772717. It wasn't started on Windows by Claude (there's no Windows machine here).
