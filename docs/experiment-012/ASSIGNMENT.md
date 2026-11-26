# Experiment 012 — The World Is Watching: assignment

**Approval:** the user's message of 2026-11-26, "Experiment 012 — The World Is Watching". It is autonomous and delivery-oriented, with minimal automated testing. A Windows x64 portable ZIP from GitHub Actions is required.

- **Baseline:** `playtest/exp011-faces-of-madness`, which is unchanged and stays the recovery point.
- **Branch:** `exp012/the-world-is-watching`, created from `exp011/faces-of-madness` (`1ed8ba2`).
- **Not allowed:** merging into `main`.

This file records the request. The § numbers follow the user's message.

**Priorities:**
1. preserve and improve the gameplay;
2. all four Architect encounters;
3. working coordinated sieges;
4. enemy behaviour and identity;
5. believable visibility and fog of war;
6. character, lighting and inventory bugs;
7. the F10 menu;
8. audio triggers and the missing-recordings report;
9. a playable Windows build.

**Rule:** don't call a placeholder complete. When a feature turns out costly, build the simplest working version and record the limitation.

## Part I — Chapter One: "Someone Is Watching"

The Architect is a high-functioning psycho: intelligent, patient, and with influence over the others. He is not supernatural, not obviously insane, and quiet, controlled and deliberate. Whether he is the leader or a lieutenant stays unresolved.

There are four escalating encounters (§2):
1. The Visitor;
2. The Observer;
3. The Warning;
4. The Last Courtesy.

Each needs:
- audiovisual staging;
- progression state;
- a clean return to normal play.

**Timing:**
- The chapter spans a meaningful period of survival, not four nights in a row.
- The first encounter comes early. Later ones come after progressively longer, randomised intervals, and need suitable sleeping and home conditions.
- Normal survival continues between them.
- Progress persists across save and load.

### §3 The Visitor

Eli wakes at night, still in bed.
- The room is almost dark.
- The windows are covered with blankets.
- The door is closed and locked.

**Sequence:**
1. A few seconds of silence, then knocking.
2. A calm male voice behind the door says "Wakey, wakey, sunshine."
3. A pause, then heavy breathing.
4. "Well... there you are."
5. A longer pause, then "We've been watching you."
6. Another silence, then "Night nighty."
7. Greenish gas seeps in. Eli becomes disoriented, the screen fades to black, and he is unconscious.

**Waking:** he wakes alone in a normal-looking room, shaken, with internal-dialogue fragments:
- "Was that a dream?"
- "No... I was awake."
- "Who the hell was that?"
- "What the fuck just happened?"

Control returns, and nothing is explained.

**Implementation:**
- Use Eli's actual sleeping place and house.
- Temporary blankets, the locks and the gas never permanently change the player's construction.
- If the sleep place can't stage the scene safely, postpone the natural trigger or use a controlled temporary adaptation.
- Never break the house geometry or the save.

### §4 The Observer

This encounter is mostly visual. A man stands outside the house or beyond the property edge.
- He is motionless: no twitching, no strange gestures, no aggression. He just watches.
- He is recognisably different from the psychos.
- Darkness, distance and subtle environmental audio set the scene.
- He never vanishes in plain sight. If approached, he walks away calmly into the trees or the dark.
- Limited dialogue only if matching recorded speech exists. No fabricated voice.

**Eli's thoughts:**
- "That's him..."
- "That's the voice."
- "Why is he just standing there?"

### §5 The Warning

He reveals that he has studied Eli's defences and routines. There is more background activity: distant human barking, howling, breathing and metallic banging, while he stays composed.

**Suggested lines:**
- "You're making progress."
- "Those walls of yours..."
- "They're quite impressive."
- (pause) "But I've been watching."
- "You have a routine."
- "And routines..."
- "They can become terribly inconvenient."

**Voice:**
- Use existing recordings where they exist.
- Unrecorded lines get replaceable voice-asset slots and subtitles.
- Never synthesise a generic Architect voice.

There is no boss fight. The player begins to suspect that some attacks are arranged.

### §6 The Last Courtesy (the climax)

**Setting:**
- Eli wakes in his own bed, bound with ropes.
- The room is dark, the windows covered, the door closed.
- Outside: many disturbed human sounds. Barking like dogs, howling, heavy breathing nearby, metal being struck.
- Then violent impacts on the bedroom door, which shakes visibly.

**His speech:**
1. "You know... I've been remarkably patient with you."
2. (pause) "I've watched you build your little walls. Board up your windows. Convince yourself that you're safe."
3. (pause) "And still... you don't understand."
4. (long pause) "I've asked them to leave you alone."
5. At that moment the background stops: complete silence.
6. "That was a courtesy."
7. (pause) "I'm afraid I've run out of those."
8. "Sleep well, sunshine."
9. "While you still can."

**Audio direction:**
- His voice stays controlled. He is losing patience but never theatrical.
- The followers are much louder and more chaotic than before.
- Their sudden silence implies they obey him; don't explain it.

**Ending:** Eli loses consciousness and the screen fades to black. Don't kill him, and don't destroy the bedroom.

### §7 The four ropes (aftermath)

Eli wakes tied to his bed, alone.
- A short scripted struggle frees him. No button-mashing.
- He gets exactly four rope pieces as real inventory resources. If they don't fit, they're kept safely nearby.

**The choice:**
- **Keep** the ropes for normal use.
- **Burn** them. Only possible with a usable, reachable fireplace. Eli thinks "I'm not keeping those things." / "Not in my house.", walks to the fireplace by himself, throws the four ropes in with a small believable animation, and watches them burn briefly. Exactly four are removed. Then control returns.

**Edge cases:**
- No fireplace: he keeps the ropes.
- Unreachable fireplace: no impossible pathfinding.
- Full inventory: nothing is lost.
- Save and load: no duplication and no loss.
- An interrupted cinematic restores a safe state.

The decision is persistent story state.

### §8 Secrecy (critical)

**Never before the story introduces him:** he doesn't appear or speak. Even after that, his appearances stay story-controlled.

**Never in:**
- the main menu;
- random spawns;
- POI encounters;
- invasion groups;
- enemy notifications;
- player-facing enemy lists.

**His recordings:**
- His voice and his followers' recordings are never selected as ordinary psycho ambience.
- The user heard Architect recordings in the main menu: **find and fix it** in audio discovery, categorisation and pooling.
- Returning to the menu, loading another save or leaving a cinematic stops story audio.

**Where he may be shown:** F10 and the showroom may expose him for development.

**His name:** the internal name "The Architect" never appears in ordinary interface text.

## Part II — Coordinated sieges

### §9 Real siege gameplay

**The difference:** normal hordes are chaotic; Architect-directed sieges are purposeful, and the difference is noticeable.

**His role:** the Architect never charges Eli himself. He directs, and may observe from a distance. The attackers are ordinary psychos, runners, brutes and bombers.

**Goals:**
- approach from several directions;
- pressure different entrances;
- exploit weak points;
- funnel Eli towards limited escape routes;
- block exits;
- force him into an isolated room;
- barricade or obstruct the accessible routes.

The feeling: they are trying to trap him in his own home.

**Tactics** (practical, not military AI):
- **Encircle:** several approach groups.
- **Breach:** concentrate on chosen entrances or weak structures.
- **Contain:** block the likely escape paths.
- **Trap:** when Eli retreats into an inner room, surround or obstruct its exits.
- **Pressure:** a mix of brutes and runners.

These rely on real navigation and on visible, reachable structures. Nothing knows Eli's exact location magically: they use his approximate last-known position and the observed entrances.

**Barricading:** visible attempts to block his movement.
- Attackers place, push or use a few existing obstructing objects at doorways.
- It uses the current construction and collision systems, without a large enemy-construction framework.
- Barricades are physical and destructible or counterable. No invisible barriers.

**Counterplay:**
- weapons, turrets and traps;
- defensive building;
- other exits;
- breaking barricades;
- outmanoeuvring;
- retreating to defensible rooms.

It is never an automatic loss.

**Story link and testing:** the first organised siege becomes eligible only after Encounter 4, after a suitable delay. There is an immediate F10 trigger.

### §10 Whole-group hordes

**The problem:** enemies currently appear one after another, so the fight goes shoot, wait, shoot.

**The rule:** the whole attacking group exists from the start of an invasion. They start at different places and distances (roads, woods, gardens, around the house) and move and decide independently. Their arrival times vary naturally.

**Constraints:**
- A kill never triggers the next enemy.
- This applies to normal invasions and to sieges.
- Distant processing stays light.
- Nothing appears visibly in front of Eli.

## Part III — Enemies

### §11 Psychos are not zombies

**On seeing Eli**, a psycho reacts visibly, shouts or screams, and runs at him aggressively.

**Shouts** are real noise events:
- Nearby psychos hear them and react to the approximate origin. They may investigate.
- They chase only once they see Eli themselves. Nobody knows his position automatically.

**Per archetype:**
- **Runner:** pursues almost at once.
- **Brute:** a heavy, determined approach.
- **Psycho:** variable hesitation, shouting, then pursuit.
- **Bomber:** keeps its existing behaviour.
- **Architect:** none of this.

Use the existing audio and report missing shouting recordings.

### §12 Names

**Who gets a name:** every ordinary humanoid psycho has a first and last name from large pools, for example Thomas Whitaker, Helen Crawford, Walter Briggs, Margaret Ellis.

**Rules:**
- The name is assigned when the enemy is generated and is kept through save and load.
- No duplicate full names within one encounter.
- No secret story identities, and the Architect is excluded.

### §13 Downed notification

A compact toast such as "Walter Briggs — Brute — Downed" gives the name, archetype and status.
- Use "Downed" rather than claiming a confirmed kill.
- No modal window, and it doesn't cover important parts of the screen.
- The Architect's identity is never exposed.

### §14 Persistent corpses

**Persistence:** a dead psycho's body stays and is searchable. Unlooted bodies persist through leaving and returning to a POI, saving and loading. A fully looted body may be cleaned up normally.

**Performance:** no AI, animation, navigation or active physics after the body settles; just a light visual and a loot container.

**Loot** (existing items only; not every body has loot):
- **Psycho:** a little food, water, personal belongings, basic tools.
- **Runner:** light supplies, bandages, small tools.
- **Brute:** heavy tools, work gloves, durable gear.
- **Bomber:** equipment remnants and small components.

Appearance may influence what they carry. The Architect's inventory is story-controlled.

## Part IV — Visibility and exploration

### §15 Fog of war with three states

**The states:**
- **Undiscovered:** never seen. Buildings are hidden by darker, denser fog.
- **Discovered, not visible:** remembered static structures are shown darkened.
- **Visible:** normal rendering, subject to light, weather and line of sight.

**Rules:**
- A remembered house stays recognisable, but its current occupants aren't shown.
- Saving keeps the discovered areas.

### §16 Real line of sight

You cannot see what you cannot see.
- Enemies behind walls are invisible.
- Objects in unexplored rooms don't show through closed walls or doors.
- An enemy leaving Eli's view disappears from direct view; its last position isn't shown.
- Static discovered geometry may stay as a darkened memory. Dynamic objects never reveal their current position outside valid perception.
- Hearing is not seeing: an enemy behind a wall can still be heard.

### §17 Directional vision

**The cone:**
- Eli has no 360° awareness. His vision follows where he looks, and enemies behind him are normally unseen.
- It is not impossibly narrow; it stays playable at the game's camera distance.

**Proximity sense:**
- A very close enemy behind him may be sensed, subtly, through a small visual or audio cue, without revealing it.
- Never an exact location through thick walls or between floors.

**Performance:** cache, and don't rebuild every frame without reason.

### §18 Doors in cutaways

Doors stay visible and recognisable when the cutaway hides the walls around them: closed looks closed, open looks open. Cutaways never reveal hidden enemies or unseen rooms, which matters especially in the bedroom encounters.

### §19 The fog boundary

At the edge of the world there is no invisible wall: Eli slows gradually as he walks into the fog.
- Moving back is immediately responsive, and he is never trapped.
- Movement elsewhere is unchanged.

## Part V — POIs, travel and looting

**§20 Regional map routing:**
- Walking is not restricted to roads. Shortcuts through gardens, fields, forest and open land are allowed; roads may be faster.
- The car is an old, battered off-road 4×4. It can go off-road where the terrain allows, but not through buildings, deep water or impassable terrain.
- The route shown agrees with the route and travel time actually used.

**§21 The map vehicle:** a small, battered vintage off-road 4×4 at about half the current oversized scale, in the voxel style. Add a restrained outline or ground ring if needed.

**§22 Secured rooms:**
- Rooms behind crowbar doors have double-layered walls, using the existing voxel construction and destruction. Stone or concrete is fine; nothing is indestructible.
- Breaching a wall is clearly costlier than using the tool, and no adjacent weak wall undermines this.
- It applies to the relevant generated POIs.

**§23 Kitchen chairs:** the chairs around the island block Eli. Fix the placement and collision sizes; the chairs stay solid but leave natural walking room.

**§24 Searchable-object icons:**
- They are larger and clearer, in the restrained modern style.
- Nearby interactables get a subtle indication; the current target gets a stronger highlight and a concise prompt.
- Nothing is highlighted through walls, and nothing flickers.

**§25 Full inventory:**
- Searching never leaves a container permanently unsearchable.
- Interrupted searches keep the remaining loot, and the container stays searchable until it is really empty.
- Saving keeps the contents correct. The same rules apply to corpses.

**§26 Loot windows:**
- Looting and scavenging windows have a fixed size and scroll internally.
- They never shrink for empty containers and never move as items are taken.
- The same sizing applies to related storage windows.

**§27 Item rows:**
- A row shows the icon, name, quantity and essential status.
- Descriptions appear only on hover, with a selection-based keyboard or controller equivalent.
- Tooltips never resize the menu.

**§28 Mostly depleted:**
- At about 80 % of a POI's searchable content searched, the map marks it as mostly depleted, from the real loot and search state.
- It is informational only and never blocks travel.
- It doesn't imply new loot unless replenishment really exists.
- Saving keeps it.

## Part VI — Characters and lighting

**§29 Body parts breaking apart:** intermittently, enemies show detached or floating parts. Investigate the real cause and fix it: animation transitions, the hierarchy, attachments, hit and death, ragdoll, impulses, voxel geometry, state cleanup. Check every enemy type and keep the Experiment 011 art.

**§30 Clipping:** orange geometry shows through Eli's dark clothing at the shoulders and torso. Find and fix the root cause (no painting over it), and check the other humanoids too.

**§31 Duplicate flashlight cones:**
- **Problem:** Eli seems to start with a cone already lit, and equipping the flashlight adds a second one.
- **Fix:** one flashlight gives one beam, controlled by the equipment.
- **Check:** a new game, equip, unequip, switching items, scene changes, save and load.
- **Beam:** it follows Eli's facing and aim.
- **Night visibility:** ambient night visibility stays separate.

## Part VII — Graphics and performance

**§32 Quality presets:**
- Low, Medium, High and Ultra, using practical Godot settings: shadows (resolution and distance), lighting, snow and weather density, effects, AA, view distance and render scale.
- Never hide gameplay-critical visibility, enemies or interactables.
- The choice persists, and any existing audit is used.

**§33 FPS and stutter:**
- An FPS display toggle.
- Investigate the laptop stalls, especially the Experiment 011 look cache (0.5–1 s first builds), with prewarming or spreading the work over frames.
- Changes are evidence-based; no engine rewrite.

**§34 Font:** replace Pixel Operator with a clean modern sans-serif. Keep readability, scaling and contrast, with restrained dark panels. No full layout redesign.

## Part VIII — Audio

**§35 The user's recordings:** use the real files in `assets/audio/_inbox/`. There are several variants each of:
- the voice lines;
- barking;
- howling;
- heavy breathing;
- banging on trash cans;
- bat impacts on the bedroom door.

Make natural, irregular soundscapes from them, never everything at once at full volume. Generate nothing.

**§36 Escalation per encounter:**

| Encounter | Sound |
|---|---|
| 1 | Almost silent: occasional breathing, knocking, the voice |
| 2 | Distant, barely audible: one isolated howl or bark |
| 3 | More: barking, howling, metal and breathing |
| 4 | Dense and chaotic from several places and many followers, heavy impacts and controlled silences, with the voice clearly in front |

- **Mix:** spatial where practical, with ducking so the dialogue stays clear.
- **Cleanup:** after each event.

**§37 Door impacts:** the bedroom door visibly jolts on every audible bat impact, timed from the recordings' real impact times.
- Short handle and hinge rattles, then back to rest. The door stays closed.
- The timing can be adjusted in development data.
- The door is never damaged, and the house is never rebuilt per impact.

**§38 Audio audit:** `docs/audio/AUDIO_REQUIREMENTS.md` covers four groups:
- A. Missing recordings: event, filename, a detailed ElevenLabs prompt, length, loop or one-shot, trigger, priority.
- B. Missing triggers: file, the event it belongs to, the issue, the connection needed.
- C. Incorrect triggers.
- D. Working sounds.

**Rules:**
- Connect the obvious missing triggers where the recording exists.
- Generate no audio.
- No generic substitute for missing Architect dialogue.
- Architect audio never reaches menus or random pools.

## Part IX — F10

**§39 Layout:**
- **Tabs:** a compact tabbed menu. Suggested: Story, Player, World, Enemies, Building, POIs, Audio, Debug, adjusted to fit the controls.
- **Style:** modern, compact and scrollable, with consistent control sizes, no giant buttons and no pixel font.
- **Keep:** F10 to open and close, and every existing function, obscure ones included.

**§40 Story tab:**
- **Shows:** "Someone Is Watching" with its four encounters and the story state (chapter, completed encounters, next eligible event).
- **Per encounter:** Preview (no progression change) and Trigger (a real event, saved progress).
- **Other controls:** Reset Chapter (only this chapter's state) and a first-siege trigger.
- **Encounter 4:** can be tested immediately.
- **Safe developer cinematics:** set up and recover safely. Previewing never duplicates ropes, destroys house objects or changes the save.

**§41 Enemies tab:**
- **Controls:** spawn a psycho, runner, brute or bomber; an invasion; a horde; a coordinated siege; AI debugging. The current functions stay.
- **The Architect:** only through an explicitly labelled internal function, never as a normal spawn.

**§42 Audio tab:**
- Preview voice recordings, play follower categories and choose variants.
- Test the door impacts.
- Adjust cinematic background intensity and test the coordinated silence.
- See what is playing.
- Not a full editor.

**§43 Debug tab:** FPS, frame time, render info, errors and status, and the existing tools.

## Part X — Integration and delivery

**§44 It all works together:**
- **Fog of war and sound:** fog of war never reveals psychos; screams give an approximate threat by sound only.
- **Corpses:** named enemies keep their names as corpses, and corpse loot uses the fixed-size loot window.
- **Sieges:** they use the whole-group spawning.
- **The Architect:** stays hidden before the story allows him, and his voice never reaches menus.
- **The house:** the cinematic door never damages the real house.
- **Ropes:** they respect inventory capacity.
- **F10:** replays cinematics safely.
- **New models:** they don't break in hordes.

**§45 Order** (reorderable):
- A: correctness (models, flashlight, story audio leaks).
- B: visibility, reactions, hordes, corpses.
- C: UI and POIs.
- D: the story.
- E: sieges.
- F: audio and F10.
- G: delivery.

There are no approval stops between phases; this is one combined Experiment 012.

**§46 Smoke checks:**
- launch;
- an existing save loads;
- move, scavenge, fight and return home;
- all four encounters from F10, each returning control;
- story state survives saving;
- a siege starts and can be survived;
- several enemies attack at once;
- corpse looting;
- no duplicate flashlight;
- characters intact;
- no Architect audio in menus;
- the Windows build starts.

No big repeated suite.

**§47 Delivery:**
- **Build:** a Windows x64 portable ZIP (a ready EXE with all resources, no installer) from GitHub Actions. It includes the story, sieges and F10.
- **Git:** push to `exp012/the-world-is-watching`, make a recoverable playtest checkpoint, and don't merge into `main`.
- **Link:** give the exact artifact URL.

**§48 Report:** `docs/experiment-012/REPORT.md` covers:
1. branch and SHA;
2. features;
3. the status of each observation (Completed / Partially completed / Not implemented);
4. the encounters and their triggers;
5. story saving;
6. the siege and its tactics;
7. visibility;
8. the AI and hordes;
9. corpses and loot;
10. model fixes;
11. graphics and performance;
12. the F10 tabs;
13. the audio integrated;
14. where the audio report is;
15. limitations;
16. the artifact URL.

Then STOP for human playtesting.
