# Experiment 007 — status and how to resume

**Started:** 2026-11-25, 21:16 CET.
**Branch:** `exp007/house-has-ears`; base `10acb92`.

Agents per SPEC.md:

| Agent | Area | Worktree |
|---|---|---|
| T | travel and flow | `/home/user/swq7-t` |
| P | POIs | `/home/user/swq7-p` |
| N | noise and visibility | `/home/user/swq7-n` |
| O | overview and holes | `/home/user/swq7-o` |
| S | security | `/home/user/swq7-s` |

**The lead:** merges in priority order (T and P first, then a checkpoint `checkpoint/exp007-scavenging`), then N, O and S; adds the audio integration and report; writes REPORT.md.

## If the session is lost

1. For each worktree, check `git -C <wt> log --oneline <base>..HEAD`.
2. Cherry-pick its finished commits.
3. Finish or report the rest.
