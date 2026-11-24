# Experiment 004 — "Make This House a Home" (user assignment, 2026-11-24)

**Execution mode:** Rapid Delivery. The user is the primary playtester; Claude implements the whole milestone without intermediate approval gates, makes minor decisions independently, and performs only basic verification.

This is a condensed record of the user's message. Numbers match the user's sections.

1. **Destruction and performance.** Intact objects are cheap static geometry and collision. Damage activates detailed voxel destruction where needed. Destroyed remains become simplified static rubble. No permanently accumulating active physics objects. Substantial destruction must not degrade performance over time.
2. **Main menu background.** A live simulation: a randomly selected or generated house attacked and demolished by a horde of psychos, with no player. It restarts with another house once the current one is sufficiently destroyed. Lightweight; reuse gameplay systems.
3. **Northern atmosphere** (inspired by Red Thaw; not nuclear winter):
   - less ambient light and much darker nights;
   - northern lights on most nights;
   - mostly pine trees and snow;
   - the world map adapted to snow;
   - a fireplace, lit at the start;
   - a cold exterior against a warm interior.
4. **Furniture and demolition.**
   - Furniture can be damaged, destroyed and deliberately demolished for resources, and so can the original house structures; the house can be cleared out completely.
   - Refunds: original structures and furniture return a portion; player-built pieces return the full cost.
5. **Electrical system.**
   - Toggleable lights and room switches.
   - A physical fuse box: the main supply toggle; damageable and destructible (which kills all electric light); rebuildable for meaningful resources; strategically important.
   - The fireplace is independent. A simple dependency system, no engineering simulation.
6. **Equipment bar.**
   - Quick access to weapons, tools, food, drinking water, bandages and other usable equipment.
   - Easy selection and use.
   - Arms hang naturally when nothing is equipped.
7. **Scavenging and vehicle.**
   - The forest is a destination on the map, for wood.
   - A nonfunctional car can be repaired and then becomes expedition equipment: more carrying capacity, and larger and heavier items brought home.
   - No driving.
8. **Doors, windows and defences.**
   - The player no longer obstructs a door when opening or closing it.
   - Existing doors can be reinforced, windows can be boarded up, and metal doors can be built.
   - All of these take part in damage and destruction.
9. **House expansion and excavation.**
   - Replaceable floors, stairs and an upper floor.
   - Basement excavation with a shovel, with the levels accessible.
   - Basic enemy navigation and destruction must keep working around the expanded house. No structural engineering simulation.
10. **Household survival interactions.**
    - The kitchen sink gives water while it works; drink from it.
    - The fridge lets you eat, consuming available food.
    - Shift sprints.
11. **Persistence and assets.**
    - Save the house changes, damage, equipment, car repair and infrastructure state, the simplest practical way.
    - Reuse assets; make temporary assets where missing; keep the replaceable asset and audio conventions.
12. **Basic verification only:** it builds, launches, a new game starts, the major systems are reachable, there are no obvious fatal errors, and save/load works.
13. **Delivery.**
    - A ready-to-run Windows build as a downloadable GitHub Actions artifact.
    - Commit and push on the project's branch conventions.
    - A concise final report: summary, download link, known limitations, anything not implemented, anything not verified, and the actual time against the estimate.

**Estimate given at the start (20:31 CET, 2026-11-24):**
- **Implementation:** about 10–12 hours.
- **Windows build:** best guess about 08:00 CET on 2026-11-25; range 03:00–14:00.
