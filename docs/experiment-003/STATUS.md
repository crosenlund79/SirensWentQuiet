# Experiment 003 — status and how to resume

**Updated:** 2026-11-24, Phase B start.
**Baseline:** Experiment 002 delivered at `4c87cd6`. The Experiment 003 foundation is at `0820700` (`SPEC.md`, region locations, difficulty, item and state fields, explode/weak_points foundation versions, inputs).

## Phase A: done (all five modules merged, 367 tests passing at `4c24b42`)

K (equipment and weapons), C (construction), AI (enemies and director), X (scavenging) and M (city map) are merged on the working branch. Their docs are in this folder (`equipment.md`, `construction.md`, `ai.md`, `scavenging.md`, `map.md`), each with an Integration section.

## Phase B (in progress): integration agent I

Worktree: `/home/user/swq3-i`, local and not pushed until merged. It wires everything into the game, UI and save (v2, with v1 migration), adds the new sounds and F10 tools, and runs the 20-step acceptance playtest (`ASSIGNMENT.md` §13).

## How to resume if this session is lost

1. `git worktree list`, then `git -C /home/user/swq3-i log --oneline 4c24b42..HEAD` and `git -C /home/user/swq3-i status`.
2. If the worktree is gone, restart Phase B from the branch head with the brief in `SPEC.md` §1 and §7 and the modules' Integration sections.
3. Merge, run the full suite and the playtest (`tools/survival_playtest.sh`), then write `REPORT.md`.
