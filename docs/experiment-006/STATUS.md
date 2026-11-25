# Experiment 006 — status and how to resume

**Started:** 2026-11-25, 19:55 CET.
**Branch:** `exp006/defensive-living`; base `f591dea` (Experiment 005 plus the Pixel Operator font).

Four agents work in their own worktrees, as SPEC.md sets out:

| Agent | Area | Worktree |
|---|---|---|
| D | defences | `/home/user/swq6-d` |
| R | research, library, shotgun, gun store | `/home/user/swq6-r` |
| U | build menu, UI and font | `/home/user/swq6-u` |
| B | aurora, enemies, windows, TV/radio, foundations, storage supply | `/home/user/swq6-b` |

The lead cherry-picks each agent's commits, runs the suite, pushes and writes `REPORT.md`.

## If the session is lost

1. For each worktree, check `git -C <wt> log --oneline f591dea..HEAD`.
2. Cherry-pick its finished commits.
3. Finish or report the rest from SPEC.md.
