#!/usr/bin/env bash
# End-to-end playtest of one version through real input events and the real
# renderer (Xvfb + software Vulkan). Game time is fixed at 10 fps, so it is
# slow but deterministic. Usage: tools/playtest.sh <1|2|3> [screenshot dir]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(realpath -m "${2:-$ROOT/.godot/playtest}")"; mkdir -p "$OUT"
unset VK_DRIVER_FILES
export VK_ICD_FILENAMES="${VK_ICD_FILENAMES:-/opt/lavapipe/lvp_icd.json}"
export LP_NUM_THREADS="${LP_NUM_THREADS:-2}"
exec timeout "${PLAYTEST_TIMEOUT:-900}" xvfb-run -a -s "-screen 0 1600x900x24" \
  "${GODOT:-godot}" --path "$ROOT" --resolution 1600x900 --fixed-fps 10 -s res://tools/playtest.gd \
  -- --version="$1" --out="$OUT"
