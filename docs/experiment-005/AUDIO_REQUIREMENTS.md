# Audio requirements — what to record next

A production list for the **current** playable game, not a wish list.

**Scope:** it covers:

- every `Sfx` name in `src/audio/sfx.gd` (`DEFS`);
- every `Sfx.play` call in the code;
- the ambience layers;
- the music.

**How to deliver:**

- Drop each file into `assets/audio inbox/` under the recommended name. Spelling is tolerant (`docs/experiment-005/AUDIO.md` §1).
- `1–3` means record numbered variants (`Impact - Wood 1.wav`, `Impact - Wood 2.wav`, …); the game picks one at random.
- Formats: WAV (16-bit, 44.1 or 48 kHz), Ogg or MP3.
- Mono is fine for one-shots that play in the world.
- Fixed-length exports are fine: leading and trailing silence is skipped and levels are matched at runtime.
- Loops marked **ON** should be seamless. Beds are cross-faded, so they needn't be.

**Columns:**

- **Status:** **Covered** (your upload already provides it), **Replace** (a generated placeholder plays today), **Missing** (nothing plays today, or a UI click stands in).
- **Prompt:** a one-line description to paste into ElevenLabs (sound effects) or Suno (music).

## What your upload already covers

These 22 sounds now play from your 64 files, so there's no need to record them again:

- **Footsteps:** snow, wood and cement steps; enemy steps on snow.
- **Combat and doors:**
  - the handgun shot and reload;
  - door open and close;
  - an enemy's blows on doors;
  - enemy voices.
- **Building and destruction:**
  - building and hammering;
  - metal upgrades;
  - glass breaking;
  - a wooden wall breaking.
- **Ambience:** the winter forest bed, the fireplace, owls, wolves, house creaks.
- **Eli:** both of his lines.
- **Music:** the theme.

More variants of any of these are welcome: a fourth `Door close`, more `Footsteps - Snow` takes. With only one recording per surface, the steps repeat noticeably, so 2–3 takes each would help.

## A. Existing sounds worth replacing immediately

These are generated placeholders, heard often or at key moments.

| Recommended filename | Where it plays | Description / prompt | Dur. (s) | Loop | Priority | Status |
|---|---|---|---|---|---|---|
| `Weapon - Dry fire 1–2` | Firing with an empty gun (you start with nine bullets) | Dry click of a handgun trigger and hammer on an empty chamber, close, indoors | 0.2 | OFF | **High** | Replace |
| `Enemy - Attack 1–3` | An enemy swings at the player or a wall | Hoarse, deranged man's snarl with a fast arm swipe whoosh, close | 0.7 | OFF | **High** | Replace |
| `Enemy - Hit 1–3` | A bullet hits an enemy | Short choked male grunt of pain, raw, no gore, close | 0.4 | OFF | **High** | Replace |
| `Enemy - Death 1–3` | An enemy dies | Long falling male groan fading to a rattle, then a body slumping onto snow | 1.8 | OFF | **High** | Replace |
| `Player - Hurt 1–3` | The player is hit | Man in his thirties, short pained grunt as he takes a blow, dull thud of a body hit | 0.6 | OFF | **High** | Replace |
| `Impact - Wood 1–4` | Bullets and blows on wooden walls, doors and furniture | Bullet striking a wooden wall: sharp splintery knock, small debris | 0.4 | OFF | **High** | Replace |
| `Impact - Plaster 1–4` | Bullets and blows on interior walls | Bullet hitting drywall: dull thud with a dusty crumble | 0.5 | OFF | **High** | Replace |
| `Weapon - Shotgun Shot 1–3` | The shotgun | 12-gauge pump shotgun blast outdoors in snow, heavy low boom, short slapback, then the pump racked | 1.2 | OFF | **High** | Replace |
| `Impact - Snow 1–3` | Shots into the ground | Bullet thumping into packed snow and frozen dirt, muffled puff | 0.3 | OFF | Medium | Replace |
| `Impact - Metal 1–3` | Hits on iron walls and metal doors | Bullet ricochet off a steel plate: ringing clank | 0.5 | OFF | Medium | Replace |
| `Impact - Flesh 1–3` | A blow or bullet hitting a body | Dull muffled body impact, a punch into a heavy coat, not gory | 0.3 | OFF | Medium | Replace |
| `Weapon - Reload done 1–2` | The end of a reload | Handgun slide released and snapping forward, crisp metal | 0.3 | OFF | Medium | Replace |
| `Weapon - Shotgun Shell 1–3` | Each shell pushed into the shotgun | One shotgun shell pushed into a tube magazine, a short click and slide | 0.3 | OFF | Medium | Replace |
| `Building - Place board 1–3` | Placing a wall, barricade or furniture | Heavy wooden plank set down on a wooden floor, solid thunk | 0.4 | OFF | Medium | Replace |
| `Building - Demolish 1–3` | Demolishing a piece | Crowbar prying boards loose, wood cracking, boards clattering down | 1.2 | OFF | Medium | Replace |
| `Structure - Crumble 1–3` | Debris after damage | Plaster and small debris trickling down after a wall is hit | 1.0 | OFF | Medium | Replace |
| `Structure - Blast 1–2` | A wall blown apart | Wooden house wall blown apart by an explosion: crack, timber chunks, dust settling | 2.0 | OFF | Medium | Replace |
| `Enemy - Bomber fuse beep` | The bomber's fuse, repeated faster and faster | One harsh two-tone electronic beep, short and dry | 0.15 | OFF | Medium | Replace |
| `Enemy - Bomber blast 1–2` | The bomber detonates | Improvised bomb exploding outdoors in snow: deep boom, pressure wave, long rumble | 2.5 | OFF | Medium | Replace |
| `Player - Eat 1–2` | Eating (inventory, fridge, quick bar) | Man eating canned food: three crunchy chews and a swallow | 1.5 | OFF | Medium | Replace |
| `Player - Drink 1–2` | Drinking (inventory, sink, quick bar) | Man drinking from a plastic bottle: four gulps and a quiet sigh | 1.5 | OFF | Medium | Replace |
| `Player - Bandage` | Using a bandage or medkit | Cloth bandage torn, then wrapped twice around an arm | 1.5 | OFF | Low | Replace |
| `Player - Sleep` | Going to sleep | Tired man's long exhale as he lies down on a bed, soft creak of the mattress | 2.0 | OFF | Low | Replace |
| `Player - Death` | The player dies | Man's final pained breath, collapse onto a wooden floor | 2.0 | OFF | Low | Replace |
| `Weapon - Switch 1–2` | Changing weapons | Holstering a handgun and drawing another weapon: cloth rustle and a light click | 0.5 | OFF | Low | Replace |
| `Building - Invalid` | A build that can't be placed | Muffled low wooden double knock, a soft "no" | 0.3 | OFF | Low | Replace |
| `UI - Click`, `UI - Hover`, `UI - Open`, `UI - Close`, `UI - Error` | Menus and panels | Soft warm interface tick; tiny airy tick; soft rising swish; soft falling swish; two dull low tones | 0.1–0.4 | OFF | Low | Replace |

**Note:** the handgun reload recording also plays when the shotgun starts reloading. One name is shared in the weapon code, so a separate shotgun reload needs a small code change first.

## B. Missing sounds needed by current gameplay

These events are silent or use a stand-in today. Each is wired: it plays as soon as the file exists.

| Recommended filename | Where it plays | Description / prompt | Dur. (s) | Loop | Priority | Status |
|---|---|---|---|---|---|---|
| `Enemy - Footsteps Wood 1–4` | Enemies walking inside the house (the snow steps play outside) | Heavy, uneven boots of one person walking on an old wooden floor, a few slow steps | 3.0 | OFF | **High** | Missing (silent indoors) |
| `Fireplace - Light` | Lighting the fireplace with [E] | Kindling catching in a fireplace: a match strike, a whoosh, crackle starting | 2.0 | OFF | Medium | Missing (UI click) |
| `Fireplace - Extinguish` | Putting the fire out | Fire smothered in a fireplace: hiss, embers collapsing, last crackles | 2.0 | OFF | Medium | Missing (UI click) |
| `Light switch 1–2` | Room and lamp switches | Old household wall light switch flicked, plastic click with a little room | 0.2 | OFF | Medium | Missing (UI click) |
| `Car - Engine start` | The repaired car runs | Old car engine in freezing cold: cranks, coughs twice, then catches and idles | 3.0 | OFF | Low | Missing (UI sound) |
| `Shovel - Dig 1–3` | Digging out the basement, per cell | Shovel cutting into frozen earth and gravel, a scoop thrown aside | 1.5 | OFF | Low | Missing; the one-line hook in `level_build.gd` is pending (`AUDIO.md` §8) |

## C. Additional environmental ambience

| Recommended filename | Where it plays | Description / prompt | Dur. (s) | Loop | Priority | Status |
|---|---|---|---|---|---|---|
| `Room tone - House interior 1–2` | Indoor layer, inside the house | Quiet interior of a small wooden house in winter: faint air, distant fridge hum, muffled wind against walls | 30–60 | bed | **High** | Missing (layer silent) |
| `Room tone - Basement 1–2` | Indoor layer, in the basement | Cold concrete basement: low rumble, faint drip, muffled house above | 30–60 | bed | Medium | Missing (layer silent) |
| `Wind - Winter day loop` | Outdoor layer by day (under the forest bed) | Steady winter wind across an open snowy lot, soft gusts, no birds | 45–60 | **ON** | Medium | Replace |
| `Night - Wind loop` | Outdoor layer at night | Cold still night wind, very sparse, an occasional distant creak, no insects | 45–60 | **ON** | Medium | Replace |
| `Tension - Invasion drone loop` | During invasions | Low ominous beating drone with a slow pulse, dark and tense, no melody | 20–30 | **ON** | Medium | Replace |
| `Distant - Siren` | Out in the fog, at random (the game's motif) | A very distant civil-defence siren rising, faltering and winding down to silence, heard through fog | 6.0 | OFF | Medium | Replace |
| `Distant - Shriek` | Out in the fog, mostly at night | Far-off human shriek, two voices slightly apart, echoing over snow | 3.0 | OFF | Medium | Replace |
| `Distant - Metal scrape` | Out in the fog, mostly by day | Distant metal scraping, something dragged across concrete, through fog | 4.0 | OFF | Low | Replace |
| `Natural ambiance`, `Fireplace`, `Wooden house periodic ambiance`, `Nighttime - Owl howling`, `Nighttime - Wolf howl` | — | — | — | — | — | **Covered** (more variants welcome) |

## D. Character voice lines

| Recommended filename | Where it plays | Description | Dur. (s) | Loop | Priority | Status |
|---|---|---|---|---|---|---|
| `Eli - Welcome to a new game` | After a new game's intro | — | 13.4 | OFF | — | **Covered** |
| `Eli - Continue saved game` | On Continue | — | 9.1 | OFF | — | **Covered** |

Nothing else is needed for the current game: Eli deliberately says only these two lines. Further lines would need a decision on when he speaks, plus a small hook each; they aren't listed as requirements.

## E. Music

| Recommended filename | Where it plays | Description / prompt | Dur. (s) | Loop | Priority | Status |
|---|---|---|---|---|---|---|
| `Theme/Sirens went quiet - Warmth in the freeze` | Main menu; softly for 95 s after dawn | — | 299 | ON (set in code) | — | **Covered** |
| `Stinger - Invasion` | The night's invasion begins | Short ominous orchestral swell into a deep hit, dark strings and a ghostly distant siren, 5 seconds | 5–6 | OFF | **High** | Replace |
| `Stinger - Dawn` | Dawn after the night | Gentle relief: warm piano and soft strings, three hopeful notes, quiet, 6 seconds, same key as the theme | 6–8 | OFF | Medium | Replace |
| `Music - Dawn` (optional) | Dawn, instead of the theme's first 95 s | Quiet, sparse piano-and-strings variation of the main theme, slow, warm, no drums, fades out at the end | 60–90 | OFF | Low | Optional |

## Suggested order

1. A (High):
   - `Weapon - Dry fire`;
   - `Enemy - Attack`, `Enemy - Hit`, `Enemy - Death`;
   - `Player - Hurt`;
   - `Impact - Wood`, `Impact - Plaster`;
   - `Weapon - Shotgun Shot`.
2. B (High): `Enemy - Footsteps Wood`.
3. C (High): `Room tone - House interior`.
4. E (High): `Stinger - Invasion`.
5. More takes of `Footsteps - Snow`, `Footsteps - wood floor` and `Footsteps - Cement floor`: one recording per surface repeats.
6. The rest by priority.
