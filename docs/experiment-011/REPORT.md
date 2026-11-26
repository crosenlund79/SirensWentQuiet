# Experiment 011 — Faces of Madness: report

Every humanoid now uses the handcrafted voxel style of the Experiment 010 Eli. The details of how humanoids are built and added are in `HUMANOIDS.md`.

- **Branch:** `exp011/faces-of-madness` (from Experiment 010).
- **Windows build:** `playtest/exp011-faces-of-madness`, built by GitHub Actions. The portable ZIP is the "Windows build" artifact (link below).
- **Not changed:** the AI, speeds, health, damage, collision radii and the save format. Eli himself is unchanged.

## The models

| Archetype | Looks | Height | What makes it |
|---|---|---|---|
| **Ordinary psychos** | 10 people × 3 variations | 1.56–1.9 m | Men and women, young to old, slim to heavy. Their clothing suggests former lives: a mechanic, an office clerk, a shop assistant, a labourer, a pensioner in slippers, a hooded youth, a neighbour, a retired man, a jogger and a security guard. Faces are disturbed but human, with no gore. |
| **Runner** | 6 people | 1.74–1.90 m | Starved thin: wasted limbs, knobbly joints, hollow cheeks and sunken eyes, visible collarbones and ribs. Clothes hang loose. They include a patient in pyjamas, a man in a torn vest and a girl in a track jacket. |
| **Brute** | 4 people × 2 variations | 2.39–2.56 m | 1.31–1.40 × Eli's height and about 2 × his width. He has huge shoulders and trapezius, a gut, a thick short neck and a small head. Clothing: a bouncer, a butcher (a stained apron, no gore), a lumberjack and a mover. He carries a nailed plank or a taped pipe. |
| **Bomber** | 4 ordinary people | ≈ 1.7–1.85 m | A delivery driver, a woman in a fleece, an older man and a young man in a tracksuit. Each wears straps and the existing abstract glowing pack. |
| **The Architect** (internal name) | 2 | 1.92 m | Calm and orderly: a dark, buttoned long overcoat over a pressed shirt and black tie (or a black jumper), black gloves, polished shoes, neat hair and a composed face. |

**Proportions** come from real geometry, never a uniform scale.
- The body parameters are height, sex, weight, muscle and age, plus multipliers for the limbs, head and face.
- Phase 2 added three:
  - `gaunt` (the runner);
  - `bulk` and `traps` (the brute).

## Animation

All humanoids share one gait: the feet are planted at the real ground speed, it moves from walk to run, and turns shuffle on the spot. Each archetype has its own style.

| | Idle | Walk / run | Turn | Attack | Hit | Collapse |
|---|---|---|---|---|---|---|
| **Psycho** | Breathing, weight shifts, tics (head jerks, shoulder hitches) | Per person: limps, shuffles, stoops | Shuffling | Overhead, swipe, lunge or flail | Recoil | The knees buckle, then he falls with limbs splayed |
| **Runner** | Restless bouncing, snapping head | A loping, over-long sprint, head thrust forward, arms flung out | Snapping | A face-first lunge with clawed hands | A spasm | Drops like a marionette |
| **Brute** | Heavy breathing, shoulders rising | A lumbering, rolling walk; the run is a ponderous charge | Slow; the torso lags behind | A wound-up overhead slam or a sweep with the club | Barely rocks him | On his knees, then face down; the club drops |
| **Bomber** | Head bowed, muttering | Stiff and hurried, a hand on a strap and a fist on the chest | — | (the blast) | Clutches the pack | Shared; when the fuse is lit he hunches and shakes |
| **Architect** | Almost perfectly still | Measured and upright | Controlled: the head leads, then the body | — | — | — |

- **Dormant behaviours** (bang, tap, sway, stare) look right on the new bodies.
- **The Architect** also has an **observe** pose: hands clasped behind his back, head slightly tilted, watching.

## Psycho variation

- An enemy's appearance seed picks its look.
- The roster prefers looks that are already built, so variety grows during play without hitches.
- POI encounters save the seed (`"app"`), so a revisited or reloaded enemy is the same person.

## The Architect: preparation and secrecy

- **Identity:** `ArchitectIdentity` holds the internal id `architect` and the flags hidden, not spawnable, silent and not hostile. It also lists his animation states: still, walk, turn, observe.
- **Not in the game:** there is no AI, encounter, siege or voice. He isn't in `EnemyDefs`, the invasion director, POI encounters, stragglers or the menu siege. Asking the roster for him gives an ordinary psycho.
- **Where he can be seen:** only in F10 → Character and the showroom.
  - **"Show Architect (internal)"** places a silent preview figure near Eli. It turns to him in a controlled way, observes, and follows a few measured steps.
  - The figure is not an enemy and isn't saved. **"Remove Architect"** takes it away.
- **Test:** `test_architect` checks his flags and that the director and roster never choose him. It also scans `src/` for the word and fails if it appears outside the developer files.
- **Your recordings:** your uploaded recordings ("The Architect – …" voice lines and "Architect followers – …") are untouched and not wired.
  - The audio inbox now holds back any file with "Architect" in its name. Before this, a few of them would have been picked up as ordinary psycho sounds (enemy vocals, door bashing).

## Showroom

- **Where:** Main menu → Visual Experiments → "D Character Showroom", or F10 → Character → Character showroom.
- **Character:** Eli, Psycho, Runner, Brute, Bomber, Architect. "Previous / Next look" browses the variations.
- **Compare beside Eli:** Psycho, Runner, Brute, Bomber, Architect or the original figure, at the same scale, with a metre ruler, a floor grid and measured heights.
- **Animation:**
  - Idle, Walk, Hunt, Run, Turn, Attack, Hit, Collapse;
  - the dormant poses Bang, Tap, Sway, Stare and Listen;
  - for the Architect: Still, Walk, Turn, Observe.
- **View:** 3/4, Front, Side, Back, Face, Turnaround, Game cam; "Walk across the stage".
- **Light:** Day, Night + lamp, Flashlight.
- **Controls:** drag or A/D to turn; wheel or W/S to zoom; Esc to go back. Command-line arguments for screenshots are listed in `HUMANOIDS.md`.

## Integration

- **In the game:** invasions, stragglers, POI encounters (dormant ones too), F10 spawns and the main-menu siege all use the new people.
- **Unchanged:** the AI, speeds, health, damage and collision. The only change on the AI side is a collapse hook in `AIEnemy._corpse`.
- **Props:** an archetype attaches its own props through `HumanoidArchetype.extras()`, called by `EnemyLooks.apply`. The brute's club and the bomber's pack and pulsing light work as before.
- **Doors:** the brute stoops, and he ducks when a lintel is just ahead of or over him, so he goes through ordinary 2.1 m doorways. His collision radius is unchanged.

## Performance

**Build time and size per look:**

| Archetype | Vertices | Build time |
|---|---|---|
| Psychos | 62k–101k | 0.4–0.9 s |
| Runners | 51k–74k | 0.45–0.75 s |
| Bombers | 69k–86k | 0.5–0.7 s |
| Brutes | 116k–130k | 0.65–1.2 s |

- **Brute voxels:** the brute is sculpted with 2 cm voxels; the others use 1.5 cm.
- **Draw calls:** 15 per person, plus props and the x-ray pass.
- **Cache:** the meshes are built once per look on worker threads and shared by every enemy wearing that look. The cache holds 48 looks; all enemy looks together are 48.
- **Background builds:** at the start of a game, 16 psycho looks and 3 each of runner, bomber and brute build in the background (fewer in the menu siege). Unfinished builds are cancelled on quit.
- **Memory:** about 3 MB of GPU memory per look. This is an estimate, not measured.

## Limitations

- A look that isn't built yet is built on the spot, which freezes the game for about 0.5–1 s. This can happen with the first rare looks at a POI arrival.
- Coat and parka skirts clip a little with swinging thighs.
- On wider bodies the bomber's strap hand can float slightly off the strap. A bomber in a dormant pose would look odd, but bombers are never dormant in the game.
- In the face close-up you can see down the runner's hanging shirt collar.
- The brute's 2 cm voxels make his face slightly coarser than the others'.
- The Architect's F10 figure uses the enemy material, so behind walls he shows as the red x-ray silhouette.
- Faces can't be read from the game camera. People are recognised by their silhouette, clothing colours and how they move.
- The gait and leg IK code is duplicated between `EliRig` and `HumanoidRig`, so Eli himself is unchanged.

## Screenshots (`shots/`)

| File | What it shows |
|---|---|
| `eli_runner.png` | Eli beside a runner (3/4, ruler) |
| `eli_brute.png` | Eli beside a brute (lumberjack, club) |
| `eli_architect.png` | Eli beside the Architect |
| `people_group.png` | A mixed group of ordinary psychos |
| `night_encounter.png` | A night encounter at gameplay distance: psychos, runners, a brute and a bomber outside the Hardware Store |
| `architect_observing.png` | The Architect observing |
| `showroom_compare_ui.png` | The showroom in comparison mode |
| `runner_sprint.png` | Runners mid-sprint |
| `brute_lineup.png` | The four brutes beside Eli |
| `brute_doorway.png` | A brute ducking through a doorway in the house |
| `bomber_lineup_night.png` | The bombers at night with their packs lit |
| `hardware_night.png`, `face_hooded_youth.png`, `attack_windup.png`, `people_variations_b.png` | Phase 1 working shots |

## Verification

- **Full suite:** 627 passed and 2 failed on the integrated branch. Both failures were in `test_audio_game` and had one cause: Eli and the new people walked silently.
  - **Cause:** the new rigs kept their own gait phase, so the footstep sounds never triggered. This had been true for Eli since Experiment 010.
  - **Fixed:** Eli's and the people's rigs now drive the shared walk phase.
  - **After the fix:** the audio, character, humanoid and AI tests all pass. The full suite was not run again.
- **New tests:**
  - `tests/character/test_humanoids.gd` (9): every look builds within budget; the runner is thinner than a psycho; the brute is ≥ 1.3 × Eli's height and ≥ 1.6 × his width, carries his club and ducks in doorways; the bomber has its pack and light; the animations run.
  - `tests/character/test_architect.gd` (6): his flags, secrecy and F10.
- **Screenshots:** taken headlessly with the showroom and `tools/site_shot`, and looked at.
- **Not checked:** the Windows build wasn't started on Windows by Claude (there is no Windows machine here).
- **Windows build:** GitHub Actions run 10 succeeded for `playtest/exp011-faces-of-madness` (`37671ff`). Artifact `SirensWentQuiet-windows-37671ff…` (an 84 MB ZIP, kept until 2026-12-26): https://github.com/crosenlund79/SirensWentQuiet/actions/runs/45869308625
