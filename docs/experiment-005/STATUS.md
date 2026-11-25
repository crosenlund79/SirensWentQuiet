# Experiment 005 — status and how to resume

**Started:** 2026-11-25, 01:45 CET.
**Branch:** `exp005/house-worth-living-in`; base `4320b5e`.

Four agents work in their own worktrees, as SPEC.md sets out:

| Agent | Area | Worktree |
|---|---|---|
| V | levels | `/home/user/swq5-v` |
| F | furniture and storage | `/home/user/swq5-f` |
| C | comfort, mood and rooms | `/home/user/swq5-c` |
| A | audio | `/home/user/swq5-a` |

The lead cherry-picks each agent's commits when it reports, runs the suite, pushes, and writes `REPORT.md` with the audio requirements (`AUDIO_REQUIREMENTS.md` by A).

## If the session is lost

1. List the worktrees: `git worktree list`.
2. For each worktree, check `git -C <wt> log --oneline 4320b5e..HEAD` and `git -C <wt> status`.
3. Cherry-pick finished commits onto the branch. Then finish the unfinished areas from SPEC.md, or report them as not done.
