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
never a uniform scale.

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
5. Showroom: `eli_showroom.tscn` (Visual Experiments, F10) with
   `--people=<kind> --seed=N --count=N --cols=N --anim=idle|walk|jog|run|attack|hit|die
   --pose=x --dormant=bang|tap|sway|stare` (and the "People" buttons).
6. Test: add the kind to `tests/character/test_humanoids.gd`.

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
