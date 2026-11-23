#!/usr/bin/env bash
# Screenshot a scene through the real renderer (software Vulkan under Xvfb).
# Usage: tools/capture.sh <res://scene.tscn> <out.png> [seconds=4] [extra user args...]
# Example: tools/capture.sh res://src/modular/modular_demo.tscn /tmp/b_night.png 6 --night
# Engine flags (before the scene args) via CAPTURE_ENGINE_ARGS, e.g. CAPTURE_ENGINE_ARGS="--fixed-fps 30"
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCENE="$1"; OUT="$(realpath -m "$2")"; AT="${3:-4}"; shift 3 || shift $#
unset VK_DRIVER_FILES
export VK_ICD_FILENAMES="${VK_ICD_FILENAMES:-/opt/lavapipe/lvp_icd.json}"
export LP_NUM_THREADS="${LP_NUM_THREADS:-2}"
exec timeout "${CAPTURE_TIMEOUT:-300}" xvfb-run -a -s "-screen 0 1600x900x24" \
  "${GODOT:-godot}" --path "$ROOT" --resolution 1600x900 ${CAPTURE_ENGINE_ARGS:-} -s res://tools/capture.gd \
  -- --scene="$SCENE" --out="$OUT" --at="$AT" "$@"
