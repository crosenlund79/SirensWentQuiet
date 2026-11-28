# Audio requirements — Experiment 012 audit

This audit covers the game as it stands in Experiment 012, including the "Someone Is Watching" story chapter, the sieges, first-sight shouts and corpses. It is based on the real files in `assets/audio/`, the inbox rules (`AudioInbox.RULES` in `src/audio/audio_inbox.gd`), the logical sounds (`Sfx.DEFS` in `src/audio/sfx.gd`) and every place in `src/` that plays a sound.

**Sections:**
- **A. Missing recordings:** what to record, with names, prompts, lengths and triggers.
- **B. Missing triggers:** recordings you already have that an event should use.
- **C. Incorrect triggers:** sounds that played, or would play, in the wrong place.
- **D. Working sounds:** what is wired and plays today.

No audio was generated for this audit, and nothing in the inbox was moved or renamed.

## How to deliver recordings

**Where:** drop files into `assets/audio inbox/` or `assets/audio/_inbox/`. Subfolders are fine.

**Names:** `<Category> - <description> <n>.wav` (`.ogg` and `.mp3` also work).
- Numbered variants (`1`, `2`, `3` …) become one random pool.
- Matching uses keywords, ignoring case and separators. The names below are tested against the rules.

**Story recordings are kept apart (new in Experiment 012):** a file counts as story-only when any of these is true:
- "Architect" appears anywhere in its name or folder;
- its name starts with "Story";
- it sits in a folder called `story/`.

Story-only files never join an ordinary pool (enemy vocals, door bashing, the menu siege, ambience). Only the story module plays them, under its own `story/*` names. Keep your naming as before, for example `The Architect - …` and `Architect followers - …`.

**Processing:** silence at the start and end is trimmed, and levels are normalised at runtime.

**Check what was picked up:** F10 → Audio. The tab shows the counts, the unknown files, the story-only files and what is playing now.

**Audio is separate from enemy hearing:** enemies react to noise *events* (`NoiseEvent`), not to sound files. Adding or replacing a recording never changes the AI.

**Status today:**
- 87 files in the inbox. 64 are mapped to 22 pools, which 25 sounds use (counting aliases), and 23 are story-only (the four voice lines and nineteen follower sounds).
- 37 sounds play generated placeholders (`assets/audio/**/template_*.ogg`).
- 29 sound slots are silent until a recording arrives. The code falls back to an older sound where one fits.

---

## A. Missing recordings

**Priority:**
- **High:** heard constantly, or needed for the story to read as intended.
- **Medium:** noticeable.
- **Low:** polish.

**Loop column:** "one-shot" plays once; "loop" or "bed" plays continuously. Lengths are targets; trimming handles the rest.

**ElevenLabs tips:**
- Generate 3–4 variants of each sound and number them.
- Keep reverb dry unless the prompt asks for a space; the game adds distance and walls.
- Avoid music in effect prompts.

### A1. Story: "Someone Is Watching" (ASSIGNMENT §3–§7, agent S)

**Voice lines first.** You have four recordings of his voice. Judging by their names and lengths, this is what they probably cover:

| Recording | Length | Probably covers |
|---|---|---|
| `The Architect - Wakey wakey sunshine - for first encounter (scripted) with this enemy` | 7.6 s | §3 "Wakey, wakey, sunshine." At 7.6 s it may also hold "Well... there you are." |
| `The Architect - Comfortable - for second encounter (scripted)` | 8.5 s | §4, The Observer's limited dialogue (no script line given) |
| `The Architect - Random on encounter (scripted)` | 5.5 s | A short line usable in any encounter |
| `The Architect - The final encounter before confrontation` | 24.6 s | §6, The Last Courtesy. 24.6 s fits most of the nine lines, but the long pauses would make it longer, so some may be missing. |

The lines below need their own files when the recordings above don't contain them. Use **the same ElevenLabs voice** as the four existing files.

**Voice prompt (all lines):** "Calm, controlled, educated male voice, late forties, quiet and deliberate, a faint smile in the voice that feels wrong, speaking close behind a closed wooden bedroom door at night, no shouting, no theatrical villainy, slow pacing with natural breaths."

The game shows subtitles for every line, so a missing file never stops a scene. It never substitutes a generic voice.

| Priority | Event (§) | Suggested file name | Line / prompt | Length | Loop | Trigger | Probably covered by |
|---|---|---|---|---|---|---|---|
| High | Visitor (§3), step 4 | `The Architect - Visitor - Well there you are.mp3` | "Well... there you are." | 2.5 s | one-shot | After the breathing, behind the locked door | possibly "Wakey wakey sunshine" |
| High | Visitor (§3), step 5 | `The Architect - Visitor - We've been watching you.mp3` | "We've been watching you." (after a long pause) | 2.5 s | one-shot | After a longer silence | not covered |
| High | Visitor (§3), step 6 | `The Architect - Visitor - Night nighty.mp3` | "Night nighty." Soft, almost tender. | 1.5 s | one-shot | Just before the gas | not covered |
| High | Warning (§5) | `The Architect - Warning - You're making progress.mp3` | "You're making progress." | 2 s | one-shot | The Warning, line 1 | not covered |
| High | Warning (§5) | `The Architect - Warning - Those walls of yours.mp3` | "Those walls of yours..." | 2 s | one-shot | Line 2 | not covered |
| High | Warning (§5) | `The Architect - Warning - They're quite impressive.mp3` | "They're quite impressive." | 2 s | one-shot | Line 3 | not covered |
| High | Warning (§5) | `The Architect - Warning - But I've been watching.mp3` | (pause) "But I've been watching." | 2.5 s | one-shot | Line 4 | not covered |
| High | Warning (§5) | `The Architect - Warning - You have a routine.mp3` | "You have a routine." | 2 s | one-shot | Line 5 | not covered |
| High | Warning (§5) | `The Architect - Warning - And routines.mp3` | "And routines..." | 1.5 s | one-shot | Line 6 | not covered |
| High | Warning (§5) | `The Architect - Warning - Terribly inconvenient.mp3` | "They can become terribly inconvenient." | 3 s | one-shot | Line 7 | not covered |
| Medium | Last Courtesy (§6), lines 1–9 | `The Architect - Last courtesy - <line> .mp3` (one per line) | §6 lines 1–9 verbatim: "You know... I've been remarkably patient with you." … "While you still can." Losing patience, never raising his voice. | 2–8 s each | one-shot | One per line, so the follower silence lands exactly before "That was a courtesy." | **probably covered** by "The final encounter before confrontation"; record per line only if timing the silence inside the long file doesn't work |
| High | Visitor (§3), step 1 | `Architect - Knock on bedroom door 1–3.wav` | "Three slow, unhurried knuckle knocks on a closed wooden interior door, heard from inside a small dark bedroom, close, dry, quiet house at night" | 2.5 s | one-shot | After a few seconds of silence | — |
| High | Visitor (§3), step 7 | `Architect - Gas seeping under door 1–2.wav` | "Soft continuous hiss of gas escaping from a canister, leaking under a door gap into a small room, faint pressurised whisper, slowly building" | 10 s | loop | While the green gas seeps in | — |
| Medium | Visitor and Last Courtesy (§3, §6) | `Architect - Blackout 1–2.wav` | "Muffled heartbeat slowing down, high faint ringing in the ears, the room sound fading away to nothing, disorientation" | 5 s | one-shot | During the fade to black | — |
| High | Ropes (§7) | `Architect - Rope struggle 1–3.wav` | "A man straining against rough ropes tied to a wooden bed frame, rope creaking and rubbing, bed frame knocking, laboured breaths, the knot finally slipping loose" | 4 s | one-shot | The scripted struggle | — |
| Medium | Ropes (§7) | `Architect - Ropes thrown into fire 1–2.wav` | "A bundle of rope tossed onto a burning wood fire, a soft thump, the fire flaring up with a whoosh, crackling more intensely for a moment" | 3 s | one-shot | Burning the ropes | — |
| Medium | Door impacts (§37) | `Architect - Door handle rattle 1–4.wav` | "A metal door handle and loose hinges rattling briefly after a heavy blow against a closed wooden door, short, close" | 0.6 s | one-shot | After each bat impact (the door jolt) | — |
| Medium | Last Courtesy (§6) | `Architect followers - shuffling in the hallway 1–3.wav` | "Several people shuffling and pacing restlessly in a narrow wooden hallway outside a closed door, creaking floorboards, uneven steps, a few twitchy breaths, no words" | 8 s | bed | The dense background before the silence | — |
| Low | Observer (§4) | `Architect - Distant footsteps in snow 1–2.wav` | "One person walking away calmly through deep snow at night, measured unhurried steps, receding into a quiet forest" | 6 s | one-shot | He walks away into the trees | — |

**Eli's thoughts (§3, §4, §7):** today they are subtitles. A recording replaces the text with his voice. Put the files in `assets/audio/_inbox/story/` so they are story-only.

**Voice prompt:** "Man in his late thirties, tired and shaken, quiet internal monologue, close microphone, breathy, not acted out."

| Priority | Line | File name (in `_inbox/story/`) | Length |
|---|---|---|---|
| Medium | "Was that a dream?" | `Eli - Thought - Was that a dream.mp3` | 1.5 s |
| Medium | "No... I was awake." | `Eli - Thought - No I was awake.mp3` | 2 s |
| Medium | "Who the hell was that?" | `Eli - Thought - Who the hell was that.mp3` | 1.5 s |
| Medium | "What the fuck just happened?" | `Eli - Thought - What just happened.mp3` | 1.5 s |
| Low | "That's him..." | `Eli - Thought - That's him.mp3` | 1.5 s |
| Low | "That's the voice." | `Eli - Thought - That's the voice.mp3` | 1.5 s |
| Low | "Why is he just standing there?" | `Eli - Thought - Why is he standing there.mp3` | 2 s |
| Low | "I'm not keeping those things." | `Eli - Thought - Not keeping those.mp3` | 1.5 s |
| Low | "Not in my house." | `Eli - Thought - Not in my house.mp3` | 1 s |

**The followers are covered:**
- barking: 4 files;
- howling: 4 files;
- heavy breathing: 3 files;
- banging on a tin trash can: 4 files;
- baseball bat on the door: 4 files.

These are 7–10 s takes. More variants would make §36 encounter 4 ("dense and chaotic from several places") less repetitive. Medium priority: 2–4 more of each, and 2–3 s single barks and single bat impacts.

### A2. Enemies (§11 shouts and the existing gaps)

| Priority | Event | Suggested file name | ElevenLabs prompt | Length | Loop | Trigger | Logical name |
|---|---|---|---|---|---|---|---|
| **High** | A psycho sees Eli and shouts before charging (§11) | `Psycho - Shout 1–4.wav` | "A deranged man suddenly shouting a wordless, furious alarm cry when he spots someone, raw throat, outdoors in snow, not a monster growl, human" | 1.2 s | one-shot | `EnemyReaction`'s first sight (psycho, brute, runner). **Wired now**; today the existing enemy vocals play instead | `psycho/shout` |
| **High** | A runner or psycho screams on sight (§11) | `Psycho - Scream 1–3.wav` | "A thin, high, unhinged human scream of excitement and rage, short, breaking voice, outdoors at night" | 1.0 s | one-shot | Second choice after the shout. **Wired now** | `psycho/scream` |
| Medium | A brute's heavier roar | `Psycho - Shout brute 1–2.wav` | "A huge heavy man bellowing a low, wordless roar, chest voice, slow and menacing" | 1.5 s | one-shot | The brute's first sight (the same pool as the shout today) | `psycho/shout` |
| **High** | An enemy swings at Eli | `Enemy - Attack 1–3.wav` | "Hoarse deranged man's snarl with a fast arm swipe, close" | 0.7 s | one-shot | Melee swing (`game_combat`) | `enemy/attack` (template today) |
| **High** | A bullet hits an enemy | `Enemy - Hit 1–3.wav` | "Short choked male grunt of pain, raw, no gore" | 0.4 s | one-shot | Hits (`weapon_handler`, turrets) | `enemy/hit` (template) |
| **High** | An enemy dies | `Enemy - Death 1–3.wav` | "Long falling groan, then a body slumping onto snow" | 1.8 s | one-shot | Death; the body then becomes a corpse | `enemy/death` (template) |
| **High** | Enemies walking inside buildings | `Enemy - Footsteps Wood 1–4.wav` | "Heavy uneven boots on an old wooden floor, a few slow dragging steps" | 3 s | one-shot (sliced) | Enemy gait indoors. Until it exists, **Eli's wood-floor steps stand in** (new) | `enemy/step_wood` |
| Medium | The bomber's fuse and blast | `Enemy - Bomber fuse beep.wav`, `Enemy - Bomber blast 1–2.wav` | "Harsh two-tone electronic beep, small speaker" / "Improvised bomb exploding in snow, deep boom, debris, long rumble" | 0.15 s / 2.5 s | one-shot | Bomber | `enemy/bomber_fuse`, `enemy/bomber_blast` |
| Medium | Dormant psychos (Exp 009): mumbling, humming, whispering, startle | `Psycho - Incoherent mumbling 1–4`, `Psycho - Humming 1–3`, `Psycho - Whisper 1–3`, `Psycho - Startle gasp 1–2` | "A disturbed man alone in an abandoned building, muttering incoherently to himself, close, intimate, unsettling" (vary per file: humming a broken tune, whispering, a sharp startled gasp) | 3–6 s | one-shot | DormantMind behaviours at POIs (silent today) | `psycho/mumble`, `psycho/hum`, `psycho/whisper`, `psycho/startle` |
| Low | Dormant psychos: banging, scratching, tapping | `Psycho - Bang on wall 1–3`, `Psycho - Scratch 1–3`, `Psycho - Tap 1–3` | "Fist banging on a wooden wall in a slow obsessive rhythm" / "fingernails scratching wood" / "fingers drumming on a table" | 2–4 s | one-shot | DormantMind (door and impact sounds stand in) | `psycho/bang`, `psycho/scratch`, `psycho/tap` |

### A3. Corpses, looting and POIs

| Priority | Event | File name | Prompt | Length | Loop | Trigger | Logical name |
|---|---|---|---|---|---|---|---|
| **High** | Searching a container or a corpse | `Search 1–4.wav` | "Hands rummaging through a shelf of cans and boxes, items shifting, cloth pockets patted, quiet" | 1.5 s | one-shot | POI containers, corpses (§14) | `poi/search` |
| **High** | Taking an item | `Pickup 1–3.wav` | "A small item picked up and stuffed into a backpack, cloth rustle" | 0.5 s | one-shot | Loot panel take | `poi/pickup` |
| Medium | Chopping a fallen tree | `Chop 1–4.wav` | "An axe biting into frozen pine wood, a crack, outdoors in snow" | 0.8 s | one-shot | Pine Woods | `poi/chop` (building sound today) |
| Medium | Forcing a lock | `Force - crowbar 1–2.wav` | "Crowbar prying a locked metal door, strained creak, a lock snapping" | 2 s | one-shot | Locked doors and cabinets | `poi/force` (door bash today) |

### A4. Weapons, the flashlight and the player

| Priority | Event | File name | Prompt | Length | Loop | Trigger | Logical name |
|---|---|---|---|---|---|---|---|
| **High** | Shotgun shot | `Weapon - Shotgun Shot 1–3.wav` | "12-gauge pump shotgun blast outdoors in snow, heavy low boom, short slapback, pump racked" | 1.2 s | one-shot | Player and turrets | `weapon/shotgun_fire` (template) |
| **High** | Dry fire | `Weapon - Dry fire 1–2.wav` | "Dry click of a trigger on an empty chamber, close" | 0.2 s | one-shot | Empty gun | `weapon/dry_fire` |
| Medium | Shotgun reload, shell | `Weapon - Shotgun reload 1–3.wav`, `Weapon - Shotgun Shell 1–3.wav` | "One shell pushed into a tube magazine, short click and slide" | 0.4 s | one-shot | Shotgun reload | `weapon/shotgun_reload`, `weapon/shell_load` |
| Medium | Weapon switch, reload done | `Weapon - Switch 1–2.wav`, `Weapon - Reload done 1–2.wav` | "Pistol drawn from a holster, cloth and metal" / "slide released, chambering a round" | 0.4 s | one-shot | Hotbar switch, end of reload | `weapon/switch`, `weapon/reload_done` |
| Medium | Flashlight on/off (§30, agent C) | `Flashlight - Click on 1–2.wav` | "Small rubber flashlight button clicked, close, dry" | 0.2 s | one-shot | Toggling the light. **Needs a slot:** no rule or logical name exists yet | — |
| **High** | Eli is hurt | `Player - Hurt 1–3.wav` | "Man in his thirties, short pained grunt, dull thud of a blow" | 0.6 s | one-shot | Damage | `player/hurt` (template) |
| Medium | Eat, drink, bandage, sleep, death | `Player - Eat 1–2`, `Player - Drink 1–2`, `Player - Bandage`, `Player - Sleep`, `Player - Death` | "Chewing dry food" / "gulping water from a bottle" / "tearing and wrapping a bandage" / "tired exhale lying down" / "final pained breath, body falling" | 1–2 s | one-shot | Survival actions | `player/*` (templates) |

### A5. Building, the house and destruction

| Priority | Event | File name | Prompt | Length | Loop | Trigger | Logical name |
|---|---|---|---|---|---|---|---|
| **High** | Bullets and blows on walls (non-wood) | `Impact - Plaster 1–4.wav`, `Impact - Metal 1–3.wav` | "Bullet into drywall, dull dusty thud" / "Bullet or club striking steel plate, sharp clang" | 0.4 s | one-shot | Shots, metal strikes | `impact/plaster`, `impact/metal` |
| Medium | Bullets into wood, flesh, snow | `Impact - Wood 1–4`, `Impact - Flesh 1–3`, `Impact - Snow 1–3` | "Bullet striking a wooden wall: splintery knock" / "muffled body hit" / "bullet into packed snow" | 0.3 s | one-shot | Shots | `impact/wood`, `impact/flesh`, `impact/ground` |
| Medium | Placing, demolishing, invalid | `Building - Place board 1–3`, `Building - Demolish 1–3`, `Building - Invalid` | "Wooden plank set down on a frame" / "crowbar tearing boards off nails" / "soft dull thunk, a denied action" | 0.5–1.5 s | one-shot | Build mode | `build/place`, `build/demolish`, `build/invalid` |
| Medium | Crumbling and blasts | `Structure - Crumble 1–3`, `Structure - Blast 1–2` | "Plaster and debris crumbling to the floor" / "an explosion blowing a wall apart" | 1–2.5 s | one-shot | Masonry breaches, bombs | `structure/crumble`, `structure/blast` |
| Medium | Digging, drilling | `Shovel - Dig 1–3`, `Drill 1–2` | "Shovel cutting frozen earth" / "cordless drill boring through a wooden wall" | 1.5–3 s | one-shot | Basements, trenches, observation holes | `build/dig`, `build/drill` |
| Low | Light switch, fireplace light/out | `Light switch 1–2`, `Fireplace - Light`, `Fireplace - Extinguish` | "Old wall switch flicked" / "match strike, kindling catching" / "fire smothered, hiss" | 0.2–2 s | one-shot | Home | `home/light_switch`, `home/fireplace_*` |
| Low | TV static, radio (Exp 006) | `TV - Static loop`, `Radio - Static and faint voices loop` | "Old CRT television showing only static, soft hiss" / "Car radio scanning dead frequencies, hiss, faint broken voices" | 20 s | loop | TV/radio on. Static is **synthesised in code today**; **needs a slot** to use a recording | — |

### A6. Travel, the map and the car

| Priority | Event | File name | Prompt | Length | Loop | Trigger | Logical name |
|---|---|---|---|---|---|---|---|
| Medium | Setting off by car, the repaired car | `Car - Engine start 1–2.wav` | "Old car in freezing cold: cranks, coughs, catches and idles" | 3 s | one-shot | Travel by car, car repair | `car/start` (a UI sound today) |
| Medium | Setting off on foot | `Travel - Depart on foot 1–2.wav` | "Boots crunching away through deep snow, a backpack strap tightened, a gate creaking" | 2 s | one-shot | Travel on foot. **Slot added in Exp 012** | `travel/depart` |
| Low | Driving on the map | `Car - Driving loop.wav` | "Interior of an old car driving slowly on a snowy road, engine hum, tyres on snow" | 20 s | loop | During the map travel animation. **Needs a slot** | — |

### A7. Ambience and weather

| Priority | Event | File name | Prompt | Length | Loop | Trigger | Logical name |
|---|---|---|---|---|---|---|---|
| **High** | Inside the house and indoor places | `Room tone - House interior 1–2.wav` | "Quiet interior of a wooden house in winter: faint air, muffled wind against walls" | 30–60 s | bed | Indoors (silent today) | `ambient/room_tone` |
| Medium | Basements | `Room tone - Basement 1–2.wav` | "Cold concrete basement: low rumble, faint drip, muffled house above" | 30–60 s | bed | Levels −1, −2 | `ambient/basement_tone` |
| Medium | Wind by day and night | `Wind - Winter day loop`, `Night - Wind loop` | "Steady winter wind over open snow" / "cold still night wind, very sparse" | 45–60 s | loop | Outdoors | `ambient/wind_day`, `ambient/night` (templates) |
| Medium | Invasions and sieges | `Tension - Invasion drone loop` | "Low ominous beating drone, slow pulse, no melody" | 20–30 s | loop | Invasion and siege | `ambient/tension` (template) |
| Medium | Out in the fog | `Distant - Siren`, `Distant - Metal scrape`, `Distant - Shriek` | "Very distant civil-defence siren rising, faltering, winding down, through fog" (and so on) | 6 s | one-shot | Random fog details | `ambient/distant_*` (templates) |
| Low | Store, clinic and library room tones | `Room tone - Abandoned store`, `Room tone - Clinic`, `Room tone - Library` | "Empty shop with a dead fridge hum" / "a clinic's still air, faint ballast buzz" / "a silent library, old-building ticking" | 30–60 s | bed | POI interiors | `ambient/room_store`, `ambient/room_clinic`, `ambient/room_library` |

### A8. Security, UI and stingers

| Priority | Event | File name | Prompt | Length | Loop | Trigger | Logical name |
|---|---|---|---|---|---|---|---|
| Medium | Alarm, sensor, turret reload | `Alarm 1–2`, `Motion sensor beep 1–2`, `Turret reload 1–2` | "Shrill battery house alarm" / "small sensor chirp" / "mechanical magazine swap, motor whirr" | 0.3–3 s | one-shot | Security system | `security/*` (UI sounds stand in) |
| Low | Interface | `UI - Click`, `UI - Hover`, `UI - Open`, `UI - Close`, `UI - Error` | "Soft dry wooden click" (and so on) | 0.1–0.3 s | one-shot | Menus | `ui/*` (templates) |
| Low | Stingers | `Stinger - Invasion`, `Stinger - Dawn` | "Short ominous low brass swell" / "a soft hopeful tone at sunrise" | 3–5 s | one-shot | An invasion starts / dawn | `stinger/*` (templates) |

---

## B. Missing triggers (recordings that exist; events that should use them)

| Existing file(s) | Expected event | Issue | Connection | Status |
|---|---|---|---|---|
| `Enemy - Heavy impact wood 1–4` (`door/bash`) | An enemy's blow on a **wooden wall** or **furniture** | Only door and barricade blows used them. Wall and furniture blows played the small bullet-impact template. | `HouseWorld.strike_sound()`: wood → `door/bash` in `_bite` and `HouseFurniture.strike` | **Connected (Exp 012)** |
| `Destruction - Wooden Wall 1–2` (`structure/break`) | A **wooden** wall giving way (a passage opens) | The breach always played the crumble template. | `HouseWorld._breach_sound()`: a breach through wood → `structure/break` | **Connected (Exp 012)** |
| `Footsteps - wood floor` (`player/step_wood`) | **Enemies walking indoors** | Silent indoors: `enemy/step_wood` had no file. | `AudioInbox.ALIASES["enemy/step_wood"] = "player/step_wood"` until an enemy recording exists | **Connected (Exp 012)** |
| `Enemy - Vocal 1–4` (`enemy/moan`) | First-sight shouts (§11) | No shout recording exists. | E's `EnemyReaction` falls back to `enemy/moan` after `psycho/shout` and `psycho/scream` (slots added) | Connected as a fallback (agent E) |
| `Architect followers - …` (19 files) | The chapter's soundscapes (§35–§37) | Held back from every ordinary pool. | The story module maps `AudioInbox.reserved_files()` to `story/follower_bark`, `…_howl`, `…_breath`, `…_bin`, `…_bat` (agent S) | Agent S |
| `The Architect - …` (4 files) | The encounters' voice lines | Held back as above. | Story module → `story/architect_*` (agent S) | Agent S |
| `Hammer on metal 1–3` (`build/upgrade`) | An enemy's club or bat striking **iron plating or a metal door** | Plays the `impact/metal` template today. The recording fits a melee strike on metal well, but it is also the player's upgrade sound, so this is your call. | One line: `STRIKE_SOUND[VoxelMat.Impact.METAL] = "build/upgrade"` in `house_world.gd` | Not connected (awaiting your choice) |
| `Fireplace 1–3` (`ambient/fireplace`) | The ropes burning (§7) | The bed plays whenever the fire is lit, so it already carries the scene. A flare-up needs `Architect - Ropes thrown into fire`. | — | Works as the base layer |

## C. Incorrect triggers

| What | Where | Problem | Status |
|---|---|---|---|
| **His voice and his followers in the main menu (§8)** | `AudioInbox` matching, before Exp 011 (`5f7a4bb`) | The inbox matched file names word by word. As a result: <br>• "…human **heavy** breathing" and "…**bang**ing on tin trash can" joined `door/bash`; <br>• "…bat **hammer**s door" joined `build/hammer`; <br>• "…Wakey wakey sunshine… with this **enemy**" in the folder `voice/` matched `enemy/moan` (the word "enemy" in the name plus the folder word "voice"). <br>The main-menu siege plays `enemy/moan` and `door/bash` all the time, so the menu played "Wakey wakey sunshine", the breathing and the bin banging. | **Fixed.** <br>• Exp 011 added the reserved word. <br>• Exp 012 holds the files back by path, refuses `story/*` names, refuses a story file at play time and stops story audio on menu return and load. <br>• Proof: `tests/e12/test_audio_leak.gd`; an export-pack run of the menu with a stream log. |
| Corpse search sound | `game_corpses.gd` (agent E): `play_first(["poi/search", "door/open"])` | With no search recording, searching a body plays **a door opening**. | Open. Suggest `["poi/search", "poi/pickup", "ui/click"]` or nothing. |
| Travel by car | `travel_flow.gd`: `play_first(["travel/car_start", "car/start"])` | `travel/car_start` is not a sound the game knows, so a recording could never fill it. Harmless: `car/start` follows. | Open (cosmetic): drop the dead name. |
| Travel on foot | `travel_flow.gd`: `["travel/depart", "ui/open"]` | `travel/depart` had no slot, so it always played a UI sound. | **Fixed:** slot and rule added (`Travel - Depart on foot`). |
| First-sight shouts | `enemy_reaction.gd` (agent E): `["psycho/shout", "psycho/scream", "enemy/moan"]` | The two shout names had no slot, so a recording could never be used. | **Fixed:** slots and rules added (`Psycho - Shout`, `Psycho - Scream`). |
| Enemy blows on wooden walls | `HouseWorld._bite` | Played the bullet-impact template instead of the heavy-impact recordings. | **Fixed** (see B). |
| Eli says "Continue saved game" after an F10 reload | `game_audio.gd` voice on `continue` | A developer reload counts as Continue. | Minor, developer-only; left as is. |

## D. Working sounds (wired and playing today)

**From your recordings (inbox):**

| Logical name | Files | Plays when |
|---|---|---|
| `music/menu` (+ `music/dawn` alias) | `Theme/Sirens went quiet - Warmth in the freeze` | Main menu; softly at dawn |
| `voice/eli_new_game`, `voice/eli_continue` | `Eli - Welcome to a new game`, `Eli - Continue saved game` | After a new game's intro; on Continue |
| `player/step_snow`, `player/step_wood`, `player/step_cement` | `Footsteps - Snow`, `- wood floor`, `- Cement floor` (sliced into steps) | Eli's gait by surface. Wood also on stairs, and now for enemies indoors. |
| `enemy/step_snow` | `Enemy - Footsteps Snow 1–4` | Enemies walking outdoors near Eli |
| `enemy/moan` | `Enemy - Vocal 1–4` | Enemies' periodic vocals; dormant psychos; first-sight shout fallback |
| `door/bash` | `Enemy - Heavy impact wood 1–4` | Enemies bashing doors and barricades; now also wooden walls and furniture |
| `door/open`, `door/close` | `Door open 1–4`, `Door close 1–4` | Doors, drawbridges, POI doors, dormant psychos' drawers |
| `build/hammer` | `Building or constructing 1–4` | Building, repairs, barricades (player and siege), chopping fallback |
| `build/upgrade` | `Hammer on metal 1–3` | Upgrades, metal pieces, turret mounting |
| `structure/break` | `Destruction - Wooden Wall 1–2` | Objects and furniture destroyed; collapses; now wooden breaches |
| `impact/glass` | `Destruction - Glass Shatter 1–4` | Windows shot or smashed |
| `weapon/handgun_fire` | `Weapon - Handgun Shot 01–03` | Handgun (player, turrets); shotgun fallback |
| `weapon/reload` | `Weapon - HAndgun Reload 1–4` | Reloads; shotgun and turret reload fallback |
| `ambient/forest` | `Natural ambiance 1–3` | Outdoor bed |
| `ambient/fireplace` | `Fireplace 1–3` | A lit fireplace, positional |
| `ambient/owl`, `ambient/wolf`, `ambient/house_creak` | `Nighttime - Owl howling 1–4`, `- Wolf howl 1–4`, `Wooden house periodic ambiance 1–4` | Night details and house creaks |

**Generated templates (they work and are replaceable; see A):**
- player hurt, eat, drink, bandage, sleep and death;
- shotgun, dry fire, reload done, shell and switch;
- impacts (wood, plaster, metal, flesh, ground);
- build place, demolish and invalid;
- structure crumble and blast;
- enemy attack, hit and death; the bomber's fuse and blast;
- wind, night, tension and distant details;
- UI;
- the stingers.

**Story-only (held back, played only by the story module):**
- all four voice files;
- all nineteen follower files: barking, howling, breathing, bin banging and bat impacts.

They never play in the main menu or in random pools (`tests/e12/test_audio_leak.gd`).

## Experiment 013: weapon recordings needed

The guns work without these: each falls back to an existing sound (noted below). Drop the files into `assets/audio/_inbox/` with these names and they are picked up on the next start.

| Event | Suggested filename | ElevenLabs prompt | Length | Type | Trigger | Fallback now | Priority |
|---|---|---|---|---|---|---|---|
| Rifle shot | `Weapon - Rifle Shot 01.wav` (02, 03) | "A single .308 bolt-action hunting rifle shot outdoors in a cold, quiet forest: a sharp, heavy crack with a long rolling echo off distant trees, no music, no voices." | 1.5–2.5 s | one-shot | each rifle shot | the shotgun shot | High |
| Shotgun pump | `Weapon - Shotgun Pump 01.wav` (02) | "A pump-action 12-gauge shotgun being racked once, close up: a firm metallic slide back and forward, crisp clack-clack, a spent shell clattering away, dry studio sound." | 0.5–0.8 s | one-shot | the pump after each shotgun shot | the shell-load click | High |
| Rifle bolt | `Weapon - Rifle Bolt 01.wav` (02) | "The bolt of a hunting rifle worked by hand, close up: lift, pull back, push forward, lock down; precise metallic clicks with a brass case ejecting, dry studio sound." | 0.6–0.9 s | one-shot | the bolt after each rifle shot | the reload-done click | High |
| Rifle reload | `Weapon - Rifle Reload 01.wav` | "Opening a bolt-action rifle to load it: the bolt pulled back and held open, a soft metallic rattle, close up, dry." | 0.5–0.8 s | one-shot | starting a rifle reload | the generic reload | Medium |
| Rifle round loaded | `Weapon - Rifle Round Load 01.wav` (02, 03) | "A single rifle cartridge pressed into a rifle's magazine with the thumb: a short brass click and slide, close up, dry studio sound." | 0.3–0.5 s | one-shot | each round going in | the shell-load click | Medium |
| Spent case landing | `Foley - Brass Casing Drop 01.wav` (02–04) | "A single empty brass cartridge case bouncing twice on a wooden floor, tiny metallic tinkles, close up, quiet." | 0.4–0.8 s | one-shot | (not yet connected: a case settling) | none | Low |
