# Experiment 008 — The First Week: report

- **Branch:** `exp008/first-week`, built on Experiment 007. The source-only checkpoint is `checkpoint/exp008-first-week`.
- **How it was built:** Rapid Delivery, overnight, with four agents in parallel: H (places), T (travel), L (looting) and E (encounters, the home while away, pacing). The lead verified the loop first, then did the integration, the audio, the scenarios and the docs.
- **What wasn't done:** no exe, no Windows CI, no merge to `main`. Nothing was played by a human.
- **Launch:** open `project.godot` in Godot 4.7 and press F5. F10 opens the developer menu.

## 1. The Experiment 007 loop, verified first

A new end-to-end test (`tests/firstweek/test_first_week.gd`) plays the user's 13 steps through the real game scene, using the player's own actions where practical: E on the nearest thing, the map's Travel button, the exits.

1. New game.
2. Equip a crowbar.
3. Pick the Corner Store on the map.
4. Travel, with the animation running for a moment.
5. Arrive at the store.
6. Search a shelf with E in real frames (game time passes) and take what's there; force the locked stockroom.
7. Check that enemies start unaware.
8. Leave through an exit with E.
9. Arrive home.
10. Find exactly what was carried, and nothing that appeared from nowhere.
11. Eat, and build a crate from planks and nails without cheats.
12. Sleep into the next day.
13. Save and Continue: the crate, the inventory, the visit and the searched shelf are all remembered.

**What it found:**

| Problem | Seriousness | Fixed by |
|---|---|---|
| At a POI, any living enemy blocked saving, even a calm one that hadn't noticed Eli. Continue at a POI restarted the encounter, so enemies Eli had killed came back. | Serious | E (see §4) |
| Audio at POIs decided "inside" by the home's floor plan, not the place's rooms. | Wrong behaviour | Lead (see §6) |
| A searched, empty container showed no prompt at all, so the player couldn't tell it had been searched. | Confusing | L (see §3) |
| 45 % of first library visits had no manual Eli could read yet (e.g. only "Metalworking", which needs "Reinforced Construction" first). | Pacing | Lead (see §5) |

## 2. Three new places

Each place has its own footprint, rooms, lights, hiding places, window and doorway spots for encounters, small signs of earlier occupants, and an arrival line. They reuse the existing pieces, plus three small new ones: a gun rack (also as an empty rack), an examination bed and a lumber rack.

| Place | Layout | Its story | Good for |
|---|---|---|---|
| **Hardware Store** | A wide 15 × 7 m brick store; a sales floor with lumber racks (one stripped bare) and aisles (tools, nails, paint, electrical, plumbing, power tools, how-to books, garden); a till; a key-cutting bench; a storage room with a loading door into a fenced delivery yard with pallets and crates. | A **jammed stockroom** (crowbar) holds the better stock. A smashed entrance, a window barricade someone gave up on. Lights: a flickering tube, a lantern on the till, a green emergency light. | Nails, planks, scrap, **iron (30 % in the stockroom)**, electronic components, a drill, a woodworking or construction manual |
| **Pike's Guns** | A small L-shaped shop with a back lot: a counter made of a display case and the till; a gun rack, a rifle rack and an **empty rack**; an ammunition shelf unit; a smashed display window; an office where someone slept (a sleeping bag, a lantern, cans). | A **locked steel back room** (crowbar): gun locker, ammo crate and shelf. Hiding places in the back room, the office and behind the counter. Lights: a desk lamp left on, a red emergency light in the back room, a flickering tube. | Ammunition and shells. A firearm turns up on the shop floor on about 11 % of visits and in the back room on about 23 %; a handgun now and then (15 % in the back room). |
| **Medical Clinic** | T-shaped, with a 10 m corridor. In front, a lit waiting room and reception; to the west, two exam rooms (picked over) and a staff room (fridge, kitchenette, lockers, someone's camp); to the east, no windows. | **Exam room 3** is dark (flashlight) and nobody searched it, so supplies tend to be there. The **medical store** is locked and dark (crowbar and flashlight). A fire exit at the far end; a flickering corridor tube and a green exit light. | Bandages and first-aid kits; food and water in the staff room. A flashlight no longer blocks the trip: it only lowers the risk and opens the dark rooms. |

## 3. Scavenging

- **Markers:** searchable things show a small pixel sign when Eli is within 4.5 m and can see them:
  - not searched yet: amber;
  - locked (crowbar) or dark (flashlight): an icon;
  - partly taken: "3 left";
  - searched and empty: a faint "searched".

  The one the prompt points at is brighter.
- **Prompts:** containers say what they hold now: "[E] Search the shelf", "[E] Take from the shelf · 2 cans of food, 1 bottle of water", "Shelf: searched · empty", "Picked clean. Someone got here first."
- **One choice at a time:** at a POI the prompt prefers what Eli faces and a usable thing over a note. It doesn't flicker between two spots, and a running search keeps its progress prompt.
- **Loot panel:** Take 1, Take all and Eat / Drink / Apply. Each row shows its weight. "Take all" becomes "Take 4" when only four fit. When Eli drove, the boot has a **"Stow what you found"** button.
- **HUD while away:** "Pack 18 / 30" (amber at 80 %, red when full), plus "· Boot 12 / 60" when driving.
- **Persistence:** looted stays looted across leaving, revisits and save / Continue; what's left in a container stays there.
- **One-of-a-kind items** (tools, weapons, gear, books) are never generated again while one exists anywhere: carried, stored at home, in a boot, or lying in any place.
- **Retreat:** pressing E at an exit during a search stops it and leaves, keeping what was taken.
- **Emptiness:**
  - the Corner Store's open containers are less often empty (about 56 % on a first visit, was 65 %), with a few nails, scrap and ammo in the back;
  - the library has small extras (water, snacks, a bandage), and three more of its bookshelves are "picked clean", so the manuals sit on fewer shelves.

## 4. Travel and encounters

### Direct POI → POI travel

- At a POI, **M** opens the map from where Eli is, and Travel goes straight on to another known place, or home. The exits say "[E] Leave for home · M: travel on".
- **Carried along on every leg:**
  - what Eli carries;
  - the car and its boot;
  - the home snapshot;
  - the record of what happened at home.
- **Only at home** is anything unloaded into the household.
- **Each leg:** ends the visit once (a refused departure no longer ends it), autosaves, and can spot a new place on the way.
- **Fuel:** leaving home by car burns 1 can (there and back, as before), and each further stop by car burns 1 more. Walking is free. The car stays with Eli, so he walks on if he walked out, and drives on if he drove.
- **Example:** Home → Hardware Store → Medical Clinic → Home works, and so does saving at the clinic and continuing.

### The travel panel

- **Good for** (food and water, building materials, medical, weapons and ammo, books, tools), danger, "Been there" and the stock.
- **Walking and driving** side by side.
- **Arrive at** and **Then home**, with the daylight line ("Back home by 13:50, before dark" or "You'd get home after dark").
- The pack, and the boot when driving.
- A progress card during the animation, and short title cards on departure and arrival. Space skips them.

### Encounters

- **Some places are quiet:** Pine Woods 47 %, the Corner Store 43 %, the Library 33 %, Pike's Guns 19 %.
- **Who may be there:**
  - someone **hidden** inside a room;
  - a **face at a window** that may see Eli through the glass and come in by the nearest door;
  - someone who **walks in through a doorway**, opening a closed door;
  - **arrivals** from the fog;
  - **wanderers**.
- **Noise:** it only brings the planned arrivals sooner (gunfire: within 5–10 s) and draws them toward it. It never adds anyone.
- **Losing Eli:** a hunter that loses him (no line of sight, over 10 m away, for 10 s) calms down, so retreating and hiding work.
- **Saving at a POI:** works unless an enemy is hunting Eli. Calm enemies, killed ones and pending arrivals are restored exactly on Continue.

### The house while Eli is away

- Only attacks that fall due happen; there is no automatic attack per trip.
- Strangers now mostly prowl and leave, as at home: 30 % attack, and turrets drive prowlers off with real rounds.
- Moats count toward the defence: water much more than a dry trench, and a lowered drawbridge weakens it.
- The report stays one short line.

## 5. The first week

`docs/experiment-008/PACING.md` compares daily needs with what a visit gives.

- **Food:** not a constraint in week 1. The start lasts about 7 days, and one food trip adds 4–7.
- **Water:** not a constraint while the sink works.
- **Wood:** easy. Pine Woods, 10 minutes away, fills a pack and regrows.
- **Nails:** the early bottleneck. Changes:
  - starting nails 12 → 18;
  - more nails in houses;
  - a few in the Corner Store's back room;
  - plenty at the Hardware Store.
- **Manuals:** a first visit that turns up manuals now always turns up one Eli can read now. That was 55 % of first library visits; it is now everything except the ~9 % that turn up no manual at all.

Each place now has a reason to go: food at the stores, materials at the Hardware Store and the woods, medicine at the clinic, ammunition at Pike's, manuals at the library. Nothing is scripted to a day.

## 6. Audio

- At a POI the indoor/outdoor mix now follows the place's own rooms. Pine Woods' shelter counts as exposed.
- New room-tone names: `Room tone - Abandoned store`, `Room tone - Clinic`, `Room tone - Library`. They are wired, and fall back to the house's room tone until recorded.
- Nothing was generated over the user's recordings. `docs/experiment-007/AUDIO_REQUIREMENTS.md` lists the new names.

## Tests and runtime checks

- **Full headless suite:** see Verification below.
- **New tests:**
  - `test_first_week`: the loop plus scenarios A–D;
  - `test_poi_places`: the three places;
  - `test_looting`;
  - `test_encounters`;
  - `test_offscreen_home`;
  - `test_travel_chain`;
  - `test_audio_poi`.

### Scenarios, through the real game scene

| | What it does | Result |
|---|---|---|
| **A, food** | The core loop above (Corner Store), plus: a save at the POI after taking things, then Continue → nothing doubled, the shelf stays searched, and home has the same | passes |
| **B, equipment** | Pike's Guns by car; ammunition (and any gun) from the shop and the back room; home: the inventory matches exactly, the crowbar is still equipped, 1 fuel can was used, a found shotgun is on the quick bar | passes |
| **C, research and building** | The library, with a manual Eli can read; home; read it; the pieces it unlocks are no longer locked; planks and nails still build | passes |
| **D, night defence** | The first invasion with a loaded turret by the front path: enemies come, the turret spends real rounds (32 → 25), the house takes damage; then a night's sleep into the morning and a save | passes |

### Automated vs. not

- **Automated:** the scenarios run headless at 60 fps, with the travel animation skipped after a moment.
- **Not automated:**
  - aiming and shooting by hand;
  - stealth by feel;
  - how the places look and read in motion;
  - whether the loot feels worth it;
  - audio by ear.

**Frames looked at:**
- **Lead:** the Corner Store's take panel; the three new places in the real game scene with the HUD (Hardware Store by day, Pike's Guns at night, the clinic).
- **Agents:**
  - H: every place from the entry and inside, at night;
  - L: markers, the panel, the boot and the HUD pack line;
  - T: the panel between two places, the departure and arrival cards, the clinic after arrival.

**New tool:** `tools/site_shot.tscn` takes screenshots of the real game scene at any POI (with `tools/capture.sh`).

## Known limitations

- **Places:**
  - A dark room is dark only at night (POIs have no roofs).
  - POI lights are always on.
  - Story clutter has no collision, except the empty rack.
  - The counter piece doubles as a glass display case.
  - The hardware yard isn't a room for room visibility.
- **Loot:**
  - One roll per site is shared by item category, so planks can land on any shelf that takes materials.
  - About 75 % of the library's containers are still empty on a first visit, because most of them are book-only shelves.
- **Travel:**
  - The "Then home" estimate uses the old expedition search time (a 4-hour stay at the clinic), so its daylight warnings are pessimistic.
  - No road hazards.
- **Encounters:** doors opened at a POI aren't saved. An invasion recorded during a long clock jump is timestamped at the end of the jump.
- **Carried over:** everything in `docs/experiment-007/REPORT.md`'s limitations that isn't listed as fixed here.

## What still needs a human playtest

1. Whether the new places read clearly from the game camera, and whether their stories come across.
2. Whether the markers and prompts feel helpful, or cluttered.
3. Encounter tension:
   - is a face at the window noticeable?
   - is retreating fair?
   - is gunfire's pull felt?
4. Whether a seven-day run has the intended rhythm (need → trip → return → build), and whether nails or anything else becomes a grind.
5. The travel panel and title cards at real speed.
6. Audio balance at the POIs.

## Verification

- (filled in at delivery)
