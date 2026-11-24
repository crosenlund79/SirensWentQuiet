# Experiment 003 — status and how to resume

**Updated:** 2026-11-24, about 16:00 UTC.
**Baseline:** Experiment 002 delivered at `4c87cd6`. The Experiment 003 foundation is at `0820700` (`SPEC.md`, region locations, difficulty, item and state fields, explode/weak_points foundation versions, inputs).

## Phase A (in progress): five module agents, each in a local detached git worktree

Work in progress lives **only in these local worktrees** until the lead merges it. It is not pushed.

| Agent | Worktree | Scope (SPEC §1) |
|---|---|---|
| K | `/home/user/swq3-k` | equipment, weapons (handgun + shotgun), resources, difficulty semantics |
| C | `/home/user/swq3-c` | stone and iron construction, workbench, explode/weak_points, sections |
| AI | `/home/user/swq3-ai` | enemy AI core, psycho, runner, brute, bomber, threat-budget director |
| X | `/home/user/swq3-x` | data-driven scavenging over the 24 locations, approaches, depletion |
| M | `/home/user/swq3-m` | the interactive voxel city map with clouds |

**History:** the agents were stopped twice by account usage limits (around 12:50 and 13:00 UTC). They were resumed at 15:58 UTC, after the limit reset.

## How to resume if this session is lost

1. **Check the worktrees:** `git worktree list`, then for each one: `git -C <wt> log --oneline 0820700..HEAD` and `git -C <wt> status`.
2. **If a worktree is gone** (the container was reclaimed), restart that agent from `0820700` with its brief, which is §1 of `SPEC.md` for its scope.
3. **Merge:** verify each agent touched only its own paths, then `git cherry-pick 0820700..<tip>` and run the full suite.
4. **Phase B:** one integration agent wires everything into the game and UI, adds save v2 (with v1 migration) and runs the 20-step acceptance playtest (`ASSIGNMENT.md` §13).
