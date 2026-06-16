#!/bin/bash
# Run the gdUnit4 unit test suite headless.
# Usage: ./tests/run_unit_tests.sh [godot_binary]
set -e

GODOT="${1:-${GODOT_BIN:-godot}}"
cd "$(dirname "$0")/.."

"$GODOT" --headless --path . -s -d addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/unit -c
