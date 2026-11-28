# Humanoids (Experiment 011): voxel people

Every humanoid is built like Eli (Exp 010): implicit sculpture at 1.5 cm
voxels, painted voxel by voxel, shaded and meshed by `EliSculpt`'s mesher,
one mesh per bone on Eli's skeleton, procedural animation. Eli himself is
unchanged (`EliSculpt` / `EliRig`); people use the shared foundation below.

| File | Role |
|---|---|
| `src/character/humanoid_body.gd` | `HumanoidBody`: proportions → skeleton + girths |
| `src/character/humanoid_sculpt.gd` | `HumanoidSculpt`: a look → 15 part meshes (clothing layers, heads, faces, hair), parallel build, LRU cache, background builds |
| `src/character/humanoid_rig.gd` | `HumanoidRig extends VoxelRig`: skeleton, shared gait/IK, style, attack/hit/tic overlays, `collapse()` |
| `src/character/humanoid_archetype.gd` | `HumanoidArchetype`: base of an archetype (seed → look → rig) |
| `src/character/humanoid_looks.gd` | `HumanoidLooks`: the factory `make_rig(kind, seed)`, `pick_seed`, `warm` |
| `src/character/archetypes/psycho.gd` | the ordinary psychos: 10 people × 3 variations |
| `src/character/archetypes/architect.gd` | the Architect (internal name): 2 looks |
| `src/character/architect_rig.gd` | `ArchitectRig`: stillness, controlled turn, observe |
| `src/character/architect_identity.gd` | `ArchitectIdentity`: his internal id and flags |
| `src/character/architect_figure.gd` | `ArchitectFigure`: the F10 preview figure near Eli |
| `src/character/eli_showroom.gd` | the character showroom (all humanoids, comparison mode) |
| `src/character/archetypes/brute.gd`, `brute_rig.gd` | the brutes: 4 people × 2 variations, ~2.4 m; their club and their movement |

## A look

A look is a Dictionary: `body`, `outfit`, `face`, `hair`, `style` (+ `key`,
`name`, filled in by the archetype). The same look always gives the same
meshes; they are built once and shared by every enemy wearing it.

**Proportions** (`body`, see `HumanoidBody.DEFAULTS`): `height`, `sex` 0..1,
`weight`, `muscle`, `age`, multipliers `shoulders hips legs arms neck hands
feet`, head `head head_w head_h head_d`, face `jaw chin cheeks nose nose_w
brow ears eyes`. `derive()` turns them into joint offsets / bone lengths
(the rig) and girths (the sculpt): a heavy body gets a belly, a double chin
and thicker limbs; a woman narrower shoulders, wider hips, a bust, a smaller
jaw; age a hump, jowls, a forward head, bigger ears and nose. Real geometry,
never a uniform scale. Beyond the ordinary range: `bulk` (girth of neck,
deltoids, limbs and chest depth; 1 = ordinary) and `traps` (0..1, a
trapezius slope from neck to shoulders), both used by the brute.

**Clothing** (`outfit`, documented at the top of `humanoid_sculpt.gd`):
layers `top < mid < outer < over` (tshirt, shirt, blouse, sport, sweater,
hoodie, fleece, cardigan, coverall, coat, parka, work_jacket, hivis, apron),
`legs` (jeans, trousers, cargo, sweatpants, skirt, leggings), `feet` per side
(sneakers, shoes, boots, slippers, sock), `hat` (cap, beanie, headband, hood),
`acc` (glasses, glasses_cracked, lanyard, watch_l/r, glove_l/r, bandage_l/r,
bandage_head, rag, torn_l/r), `dirt`, `tears`. Each layer is a shell over the
body with its own sleeve length, hem, neckline, front opening and painted
details; "long" layers continue as a skirt on the pelvis.

**Face / hair**: `skin`, `iris`, `eyes` (wide, stare, squint, uneven, vacant,
dart), `brows` (raised, knit, worried, uneven, flat), `mouth` (slack,
grimace, mutter, grin, thin), `circles`, `pallor`, `grime`, `lines`,
`bloodshot`; hair `style` (buzz, short, messy, curly, combed, balding, bald,
bob, long, bun, ponytail), `col`, `col2`, `grey`, `beard` (stubble, short,
full, moustache, goatee). New components: add a branch in the sculpt (shape
in the part's `_…()` function, colour in its paint function).

**Animation style** (`style`, see `HumanoidRig.STYLE`): posture (`hunch`,
`head_up`, `tilt`, `crouch`), gait (`stride`, `cadence`, `bob`, `sway`,
`limp`, `limp_side`, `irregular`, `walk_top`), arms (`swing`, `spread`,
`arm_l` / `arm_r`: swing, hang, tight, raised, fidget, reach, limp),
`twitch`, `tempo`, `attack` (overhead, swipe, lunge, flail), `claw` (hand
curl, sculpted). The gait is shared (feet planted at the real ground speed,
walk → run, turning shuffles); the style shapes it per person.

## Adding an archetype (phase 2: runner, bomber, brute, the Architect)

1. Create `src/character/archetypes/<kind>.gd` (`<kind>` = the EnemyDefs kind)
   `extends HumanoidArchetype`; implement `variety()` and `make_look(i)`
   returning `body`, `outfit`, `face`, `hair`, `style` (copy a person from
   `psycho.gd` as a start). No registration: `HumanoidLooks` finds the file,
   and every enemy of that kind gets the new rig (`AIEnemy.configure` →
   `HumanoidLooks.make_rig(kind, appearance)`).
2. Own animation: subclass `HumanoidRig` (override `_style_pose(delta)`,
   `_attack_pose(p)`, `_hit_pose(k)`, `collapse(...)`, or `_arms`) and return
   it from `new_rig(look)`.
3. Extras (club, bomb pack, light): build them in `new_rig` (child of
   `rig.hand_r` / `rig.torso`) and adapt `EnemyLooks.apply`, which today
   returns `{}` for a `HumanoidRig` (no scale, tint or hunch on people);
   `bomber_behaviour.gd` reads `extras["pack_mat"]` / `["light"]`.
4. Materials: `HumanoidRig.material_for(look)` (the enemy material with
   x-ray); a tint needs its own material there.
5. Showroom: `eli_showroom.tscn` (Visual Experiments, F10 > Character
   showroom) picks the kind up by itself (see "The showroom" below).
6. Test: add the kind to `tests/character/test_humanoids.gd`.

## Runner and bomber (phase 2)

* `archetypes/runner.gd`: six starved people (one look each). New, additive
  parameters (0 / absent = every other look unchanged, verified byte for
  byte): body `gaunt` 0..1 (`HumanoidBody._waste`: wasted limbs, shallow
  ribcage, sunken belly, bony shoulders, thin neck; in the sculpt hollow
  cheeks and temples, sunken eyes, cheekbones, collarbones, painted ribs on
  bare skin, slack trouser legs) and a layer's or `legs`' `"loose"` (m: the
  garment hangs from the shoulders, straight over the belly, in vertical
  folds, sleeves and legs widening to the cuffs). `RunnerRig`: restless
  knee-bounce and snapping glances, the head leading turns, a loping run
  with flung, flapping arms, a deeper lunge, a jolting hit, a strings-cut
  collapse.
* `archetypes/bomber.gd`: four ordinary people. Outfit acc `"straps"`
  sculpts a back pack's shoulder and chest straps over the outermost layer.
  `BomberRig` builds the Exp 003 pack (`EnemyLooks._pack`) on its torso in
  `_ready` (so the showroom shows it too) and `extras()` returns it for
  `bomber_behaviour.gd`. Stiff hurried walk, head bowed in muttered bursts,
  a hand on a strap and a fist on the chest; when the pack's light runs hot
  (the fuse) it hunches over and shakes.

## Seeds, persistence, performance

* `appearance` (AIEnemy) is the seed; look = `seed % variety()`. The roster
  picks one with `HumanoidLooks.pick_seed` (prefers looks already built);
  POI encounters store it as `"app"` in the visit's `"enc"` record, so a
  saved enemy comes back as the same person.
* A look builds in ~0.4–0.9 s on 4 threads (parts split into row slabs; only
  voxels near the surface are evaluated, only visible ones painted); 60–100k
  vertices, 15 draw calls (+ the x-ray pass) per person. `HumanoidSculpt`
  keeps at most `CACHE_MAX` (32) looks. `HumanoidLooks.warm(kind, host)`
  builds looks on a worker thread while `host` (the roster) lives and
  cancels them when it leaves the tree.

## The Architect (internal name only)

"The Architect" is a development name: it never appears in player-facing
text, and he is not an `EnemyDefs` kind, so no roster, invasion director,
POI encounter, straggler or menu siege can choose him (asking the roster for
the kind gives an ordinary psycho). Only the showroom and F10 > Character
make his figure. `ArchitectIdentity` holds his id (`"architect"`) and flags
(`hidden`, `spawnable = false`, `silent`, `hostile = false`) and the states
his rig supports. He is silent: no sounds are wired (the recordings in the
audio inbox stay untouched). `tests/character/test_architect.gd` guards
this: no source file outside his own files, the showroom, the sculpt and
the dev menu may contain the word.

* **Look** (`archetypes/architect.gd`): 1.9 m, lean, upright; a dark,
  well-kept overcoat buttoned below the chest over a pressed shirt and black
  tie (look 1: a black jumper), dark trousers, polished black shoes, black
  leather gloves, neat dark hair with a side part, a pale composed face,
  pale grey-blue eyes, flat brows, a closed level mouth. No dirt, no tears.
* **Animation** (`ArchitectRig`): no tics, no glances, very little sway,
  slow breathing; a measured upright walk with a short arm swing; a
  controlled turn (`face_yaw`): the head leads, the chest follows a little,
  then the body eases round; `observe`: hands clasped behind the back, the
  head tilted slightly, watching (also while walking). Attack, hit and
  collapse are the shared overlays.
* **F10 > Character**: "Show Architect (internal)" places `ArchitectFigure`
  3 m in front of Eli, side-on; he turns to face Eli and observes, and
  follows a few measured steps (at most 3 m) if Eli walks away. Not an
  enemy, no collision, not saved. "Remove Architect" takes him away.

Sculpt components added for him (defaults leave every other look unchanged):
outfit `glove_col` (gloves as smooth leather of that colour); any layer
`hem` (an explicit hem height); coat `shut` (an open front buttoned shut
below that chest height); hair `neat` (no strands on the forehead for
`combed`); face `mouth: "set"` (closed and level); `eyes: "calm"` uses the
default eye.

## The showroom

Visual Experiments > Character Showroom, or F10 > Character showroom (over
the game). Panel: **Character** (Eli, Psycho, Runner, Brute, Bomber,
Architect; kinds without an archetype file show the old figure), **Previous
/ Next look** (Eli's variations, an archetype's looks), **Compare beside
Eli** (the character beside Eli at the same scale with a metre ruler, a
50 cm floor grid and both measured heights; "Original": Eli beside the old
figure), **Animation** (idle, walk, jog / hunt, run, turn, attack, hit,
collapse; enemies also the dormant poses bang, tap, sway, stare, listen;
the Architect: still and observe; Eli: handgun, two-handed, flashlight,
hammer), **View** (3/4, front, side, back, face, turnaround, game camera),
**Light** (day, night with a lamp, a flashlight held by the viewer). Drag
or A/D turns, wheel or W/S zooms, Esc goes back / closes.

Capture args (`tools/capture.sh res://src/character/eli_showroom.tscn out.png 8 …`):
`--char=eli|psycho|runner|brute|bomber|architect`,
`--compare=psycho|runner|brute|bomber|architect` (`--compare` alone: the
original figure), `--view=three|front|side|back|face|sheet|gameplay`,
`--anim=idle|walk|jog|run|turn|attack|hit|die|observe` (Eli also
`handgun|shotgun|flashlight|tool`), `--dormant=bang|tap|sway|stare|listen`,
`--pose=x`, `--light=day|night|flashlight` (`--night`), `--variant=N`,
`--seed=N`, `--people=<kind> --count=N --cols=N`, `--yaw=deg --dist=m
--ty=m`, `--moving`, `--hide-ui`. Example: `--compare=brute --view=three
--hide-ui`.
## The brute (phase 2)

* **Size and voxels.** A brute is 2.39–2.56 m (1.31–1.40 × Eli) and about
  twice his breadth. At 1.5 cm voxels that is ~200k vertices, so his look is
  sculpted at 1 / `VOXEL_SCALE` (1.33: `height` divided, `head` compensated
  for its k^0.45 curve) and `BruteRig` scales itself back up: 2 cm voxels,
  115–150k vertices. The look carries `voxel_scale`; `collapse()` keeps the
  scale in the rig's basis. Proportions still come from the body parameters.
* **Doors** leave 2.1 m. He is always stooped (`hunch` ~0.4) and ducks lower
  (`duck` 0..1: deeper lean, bent knees, crown ≤ ~2.0 m) when a lintel is
  just behind, over or ahead of him: `_door_probe` samples the parent
  enemy's `world.grid` every 0.1 s (solid at 2.0–2.35 m with air at 1.3 m),
  so it works at home and in POIs. `duck_hold` forces it (captures, tests).
* **Club**: `extras()` → `BruteRig.attach_club()`: a 1.5 cm voxel model (a
  nailed 2×4 with a rag grip, or a taped steel pipe; look field `club`) in
  the right hand, in `parts` (flash, fade, night). It swings in line with
  the arm during attacks and drops beside him when he goes down (reparented
  next to the rig; back in the hand if the showroom replays the collapse).
* **Material**: his own copy of the people's material with a deeper x-ray
  self-occlusion depth (1.15 m instead of 0.55 m).
* `tools/people_stage.tscn` (capture stage: `--who=eli,brute:0,...`) puts
  figures of any size side by side; `tools/site_shot.tscn` takes
  `--kind=brute --enemy-at=x,y`.

## Experiment 012 additions

* **Rest pose every frame.** `HumanoidRig._rest_pose()` puts every bone back
  at its skeleton offset (unit scale) before a frame's pose, in `animate()`
  and in every `collapse()`. Styles and overlays may nudge a bone's
  position additively (a shrug), never cumulatively. Breathing scales the
  chest's mesh (`breathe_chest`), not the bone. The legs are solved again
  after the overlays, and a non-finite pose resets (`_guard`).
* **RigIntegrity** (`src/character/rig_integrity.gd`) measures a rig (bone
  offset from rest, scale, NaN) and `stress()` drives rigs through every
  state; `HumanoidStress` does it to live enemies in the game (F10 > Debug
  > Stress humanoids). `tests/e12/test_characters.gd` runs it.
* **No build on the spot in a running game.** While a game or the menu
  siege runs (a roster `Warmer` is alive) and no loading screen is up, a rig
  whose look isn't built wears a built stand-in of its archetype
  (`HumanoidLooks.stand_in`), asks for its own look on a high-priority
  worker, and changes into it in place (`adopt_pending`: new skeleton,
  props moved over, `_after_bones()` hook for archetype extras). Showroom
  and preview figures set `ready_look_only`. A queued background build is
  never waited for. Behind a loading screen each archetype's first look is
  built at once, so a stand-in always exists.
* **Necks.** The head's neck narrows below the collar (Eli: `NECK_TUCK`;
  people: below the pivot), and Eli's chest leaves the collar's opening
  empty (`NECK_HOLE`), so a turning or bowing head doesn't cut skin through
  the collar and scarf.
