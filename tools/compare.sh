#!/usr/bin/env bash
# Renders the same scripted situation (same hole, window, chips, enemies and
# player position) in one version, day and night, from its game camera.
# Usage: tools/compare.sh <1|2|3> [out dir]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(realpath -m "${2:-$ROOT/.godot/compare}")"; mkdir -p "$OUT"
unset VK_DRIVER_FILES
export VK_ICD_FILENAMES="${VK_ICD_FILENAMES:-/opt/lavapipe/lvp_icd.json}"
export LP_NUM_THREADS="${LP_NUM_THREADS:-2}"
exec timeout "${COMPARE_TIMEOUT:-1200}" xvfb-run -a -s "-screen 0 1600x900x24" \
  "${GODOT:-godot}" --path "$ROOT" --resolution 1600x900 --fixed-fps 30 -s res://tools/compare.gd \
  -- --version="$1" --out="$OUT"
