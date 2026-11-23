#!/usr/bin/env bash
# Experiment 002 integrated playtest through real input events and the real
# renderer (Xvfb + software Vulkan), in two separate processes:
#   part 1: new game → ... → save and quit;  part 2: continue and verify.
# Game time is fixed at 30 fps (deterministic, independent of the slow
# renderer). The save goes to <out>/playtest_save.dat, never the player's save.
# Usage: tools/survival_playtest.sh [out dir] [--render-always]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(realpath -m "${1:-$ROOT/.godot/survival_playtest}")"; mkdir -p "$OUT"
shift || true
unset VK_DRIVER_FILES
export VK_ICD_FILENAMES="${VK_ICD_FILENAMES:-/opt/lavapipe/lvp_icd.json}"
export LP_NUM_THREADS="${LP_NUM_THREADS:-2}"
run_part() {
  timeout "${PLAYTEST_TIMEOUT:-1800}" xvfb-run -a -s "-screen 0 1600x900x24" \
    "${GODOT:-godot}" --path "$ROOT" --resolution 1600x900 --fixed-fps 30 -s res://tools/survival_playtest.gd \
    -- --part="$1" --out="$OUT" "${@:2}" 2>&1 | tee "$OUT/part$1.log"
}
run_part 1 "$@"
run_part 2 "$@"
FAILS=$(cat "$OUT/part1.log" "$OUT/part2.log" | grep -c '^FAIL' || true)
SKIPS=$(cat "$OUT/part1.log" "$OUT/part2.log" | grep -c '^SKIP' || true)
PASSES=$(cat "$OUT/part1.log" "$OUT/part2.log" | grep -c '^PASS' || true)
DONE=$(cat "$OUT/part1.log" "$OUT/part2.log" | grep -c '^PLAYTEST part' || true)
echo "SURVIVAL PLAYTEST: $PASSES passed, $FAILS failed, $SKIPS skipped, $DONE/2 parts completed (logs and screenshots in $OUT)"
[ "$FAILS" -eq 0 ] && [ "$DONE" -eq 2 ]
