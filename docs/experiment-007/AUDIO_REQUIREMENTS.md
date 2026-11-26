# Audio requirements — Experiment 007 update

What to record next for the **current** game, including the new scavenging, security and observation-hole systems.

**How to deliver:** drop files into `assets/audio inbox/`; names are matched by keywords, case and separators don't matter, and numbered variants (`1`, `2`, …) become random pools. Leading and trailing silence is trimmed and levels are matched at runtime. Rules: `assets/audio inbox/README.md` and `docs/experiment-005/AUDIO.md`.

**What you've already uploaded:**
- the theme;
- Eli's two lines;
- footsteps on snow, wood and cement;
- fireplace;
- natural ambience;
- owls and wolves;
- house creaks;
- doors;
- handgun shot and reload;
- glass and wooden-wall destruction;
- building;
- hammer on metal;
- enemy footsteps on snow, heavy impacts and vocals.

All of these are mapped and in use.

**Audio and gameplay noise are separate:** enemies react to noise *events* (`NoiseEvent`), never to sound files. Replacing or missing a file never changes what enemies hear.

**Earlier list:** everything in `docs/experiment-005/AUDIO_REQUIREMENTS.md` (sections A–E) still applies. The rows below are the most important of those plus everything new in Experiment 007.

---

## A. Existing sounds worth replacing (placeholders play today)

| File name | Where it plays | Description (prompt) | Dur. (s) | Loop | Priority |
|---|---|---|---|---|---|
| `Weapon - Shotgun Shot 1–3` | Shotgun (player and turrets) | 12-gauge pump shotgun blast outdoors in snow, heavy low boom, short slapback, pump racked | 1.2 | OFF | **High** |
| `Weapon - Dry fire 1–2` | Firing an empty gun | Dry click of a trigger on an empty chamber, close, indoors | 0.2 | OFF | **High** |
| `Enemy - Attack 1–3` | An enemy swings | Hoarse, deranged man's snarl with a fast arm swipe, close | 0.7 | OFF | **High** |
| `Enemy - Hit 1–3` | A bullet hits an enemy | Short choked male grunt of pain, raw, no gore | 0.4 | OFF | **High** |
| `Enemy - Death 1–3` | An enemy dies | Long falling groan, then a body slumping onto snow | 1.8 | OFF | **High** |
| `Player - Hurt 1–3` | Eli is hit | Man in his thirties, short pained grunt, dull thud of a blow | 0.6 | OFF | **High** |
| `Impact - Wood 1–4` / `Impact - Plaster 1–4` | Bullets and blows on walls, doors, furniture | Bullet striking a wooden wall: splintery knock / drywall: dull dusty thud | 0.4 | OFF | **High** |
| `Weapon - Shotgun reload 1–3` | The shotgun's shell-by-shell reload | One shell pushed into a tube magazine, a short click and slide | 0.4 | OFF | Medium |
| `Enemy - Bomber fuse beep`, `Enemy - Bomber blast 1–2` | The bomber | Harsh two-tone beep / improvised bomb in snow, deep boom, long rumble | 0.15 / 2.5 | OFF | Medium |

## B. Missing gameplay effects (new or still silent)

| File name | Where it plays | Description (prompt) | Dur. (s) | Loop | Priority |
|---|---|---|---|---|---|
| `Search 1–4` | Searching a shelf, fridge or desk at a location | Hands rummaging through a shelf of cans and boxes, items shifting, quiet | 1.5 | OFF | **High** |
| `Pickup 1–3` | Taking an item at a location | A small item picked up and stuffed into a backpack, cloth rustle | 0.5 | OFF | **High** |
| `Chop 1–4` | Chopping a fallen tree in the Pine Woods | An axe biting into frozen pine wood, a crack, outdoors in snow | 0.8 | OFF | **High** |
| `Force - crowbar 1–2` | Forcing a locked door or cabinet | Crowbar prying a locked metal door, strained creak, a lock snapping | 2.0 | OFF | Medium |
| `Drill 1–2` | Drilling an observation hole | Cordless hand drill boring through a wooden wall, rising whine, wood dust, close | 3.0 | OFF | Medium |
| `Enemy - Footsteps Wood 1–4` | Enemies walking inside buildings (silent today) | Heavy uneven boots on an old wooden floor, a few slow steps | 3.0 | OFF | **High** |
| `Shovel - Dig 1–3` | Digging basements and trenches | Shovel cutting frozen earth and gravel, a scoop thrown aside | 1.5 | OFF | Medium |
| `Light switch 1–2` | Room and lamp switches | Old wall switch flicked, plastic click | 0.2 | OFF | Low |
| `Fireplace - Light`, `Fireplace - Extinguish` | Lighting or putting out the fire | Match strike, kindling catching / fire smothered, hiss | 2.0 | OFF | Low |
| `Car - Engine start` | The repaired car, setting off by car | Old car in freezing cold: cranks, coughs, catches and idles | 3.0 | OFF | Low |

## C. Environmental ambience

| File name | Where it plays | Description (prompt) | Dur. (s) | Loop | Priority |
|---|---|---|---|---|---|
| `Room tone - House interior 1–2` | Inside the house and indoor locations (silent today) | Quiet interior of a wooden house in winter: faint air, muffled wind against walls | 30–60 | bed | **High** |
| `Room tone - Basement 1–2` | Basements (silent today) | Cold concrete basement: low rumble, faint drip, muffled house above | 30–60 | bed | Medium |
| `Room tone - Abandoned store`, `Room tone - Clinic`, `Room tone - Library` | Inside the stores (Corner Store, Hardware Store, Pike's Guns, …), the clinics, the library | Empty shop with a dead fridge hum / a clinic's still air and a faint ballast buzz / a silent library with old-building ticking | 30–60 | bed | Low. **Wired since Experiment 008**; until they arrive every indoor place uses the house interior room tone, so record that first. |
| `Wind - Winter day loop`, `Night - Wind loop` | Outdoors, day and night | Steady winter wind over open snow / cold still night wind, very sparse | 45–60 | ON | Medium |
| `Tension - Invasion drone loop` | During invasions | Low ominous beating drone, slow pulse, no melody | 20–30 | ON | Medium |
| `Distant - Siren` | Out in the fog at random (the game's motif) | Very distant civil-defence siren rising, faltering, winding down, through fog | 6.0 | OFF | Medium |

## D. Eli's voice

| File name | Where it plays | Status |
|---|---|---|
| `Eli - Welcome to a new game` | After a new game's intro | **Covered** |
| `Eli - Continue saved game` | On Continue | **Covered** |

No further lines are needed by the current game (Eli speaks only these two, by design). New lines would need a decision on when he speaks.

## E. Electronic security (new)

| File name | Where it plays | Description (prompt) | Dur. (s) | Loop | Priority |
|---|---|---|---|---|---|
| `Alarm 1–2` | A motion sensor set to "audible" triggers (today a UI error beep plays) | Small battery house alarm: urgent electronic two-tone wail, harsh, indoors, 3 seconds | 3.0 | OFF | **High** |
| `Motion sensor beep 1–2` | A silent sensor triggers (today a UI click) | Soft electronic chirp of a motion detector, two short notes, close | 0.4 | OFF | Medium |
| `Turret reload 1–2` | A turret's auto-loader reloads (today the handgun reload) | Small electric servo whirr, then a magazine clicking home, mechanical | 1.2 | OFF | Medium |
| `Turret servo` (optional) | A turret turning toward a target | Short servo motor whine, a small metal mount rotating | 0.4 | OFF | Low |

(Turret shots use the mounted gun's own shot sound.)

## G. Dormant psychos (Experiment 009)

Some psychos inside a place are busy with something when Eli arrives: banging their head against a wall, circling a table, swaying, staring, tapping or scratching. These sounds tell the player someone is there before he sees them.

**How they play:**
- **Voices** (mumble, hum, whisper, the startle):
  - from the psycho himself, spatialised, quieter with distance and a little muffled through a wall;
  - one line at a time per psycho, then a pause of 7–18 s;
  - at most **two psycho voices at once** in the whole place;
  - nothing starts farther than 20 m from Eli.
- **Object sounds** (bang, scratch, tap):
  - from the wall or cabinet they're working at;
  - one bang per head-butt (every 1.1–1.5 s, in bursts of 4–9);
  - one tapping or scratching file per burst (bursts of 3–6 gestures, then a pause of 2–5 s).
- **The game logic doesn't depend on these files:** the gameplay noise of the banging is a separate event.

**Your suggested file names map as they are.** The word "Psycho" keeps them apart from your `Enemy - Vocal 1–4` and `Enemy - Heavy impact wood 1–4`, which still map to the enemy moans and the door bashing. Numbered variants (`01`, `02`, …) become random pools.

| File name | Logical name | Where it plays | Description (prompt) | Dur. (s) | Loop | Priority |
|---|---|---|---|---|---|---|
| `Psycho - Incoherent Mumbling 01–04` | `psycho/mumble` | A dormant psycho's voice, now and then | Deranged man mumbling to himself, incoherent half-words, low and close, dry indoor room, no music | 3–6 | OFF (variants, not a loop) | **High** |
| `Psycho - Nervous Humming 01–02` | `psycho/hum` | The same, sometimes | Man humming a broken, tuneless melody under his breath, nervous, stopping and starting | 3–6 | OFF | Medium |
| `Psycho - Disturbed Whispering 01–02` | `psycho/whisper` | The same, rarely | Harsh rapid whispering, a man arguing with himself, very close, unintelligible | 2–4 | OFF | Medium |
| `Psycho - Sudden Silence Reaction 01–02` | `psycho/startle` | When a psycho hears something and stops to listen | A mumble cut off mid-word, a sharp intake of breath, then silence | 1–1.5 | OFF | **High** |
| `Psycho - Rhythmic Head Banging 01–04` | `psycho/bang` | Each time a psycho knocks his head against a wall | **One** dull thud of a forehead against a plaster or wooden wall, a small grunt, no echo tail | 0.4–0.7 | OFF (one hit per file) | **High** |
| `Psycho - Scratching 01–02` | `psycho/scratch` | A burst of scratching at a door | Fingernails scratching slowly at a painted wooden door, uneven strokes | 2–3 | OFF | Medium |
| `Psycho - Repetitive Tapping 01–02` | `psycho/tap` | A burst of tapping on a cabinet (also a drawer worked open and shut) | Fingertips tapping a metal or wooden cabinet in an obsessive rhythm, 5–8 taps | 2–3 | OFF | Medium |

**Until they arrive:**
- bang: your `Enemy - Heavy impact wood`, quieter;
- tap: `Impact - Wood` (the template), very quiet;
- drawer: the door open and close sounds, quiet;
- mumble: rarely, one of your `Enemy - Vocal` files, quietly;
- hum, whisper, scratch and the startle: silent.

None of these are generated.

## F. Music

| File name | Where it plays | Description (prompt) | Dur. (s) | Loop | Priority | Status |
|---|---|---|---|---|---|---|
| `Theme/Sirens went quiet - Warmth in the freeze` | Main menu; softly after dawn | — | 299 | ON | — | **Covered** |
| `Stinger - Invasion` | The night's invasion begins | Short ominous orchestral swell into a deep hit, dark strings, a ghostly distant siren | 5–6 | OFF | **High** | Missing |
| `Stinger - Dawn` | Dawn after a night | Gentle relief: warm piano and soft strings, three hopeful notes, same key as the theme | 6–8 | OFF | Medium | Missing |
| `Music - Travel` (optional) | The map travel animation | Quiet, sparse piano-and-strings motif over soft wind, uneasy but hopeful, 20–30 s | 20–30 | OFF | Low | Optional |

## Suggested order

1. **G:** `Psycho - Rhythmic Head Banging`, `Psycho - Incoherent Mumbling`, `Psycho - Sudden Silence Reaction` (Experiment 009)
2. **E:** `Alarm`
3. **B:** `Search`, `Pickup`, `Chop`, `Enemy - Footsteps Wood`
4. **A:** `Weapon - Shotgun Shot`, `Weapon - Dry fire`, `Enemy - Attack`, `Enemy - Hit`, `Enemy - Death`, `Player - Hurt`, `Impact - Wood`, `Impact - Plaster`
5. **C:** `Room tone - House interior`
6. **F:** `Stinger - Invasion`
7. **The rest** by priority
