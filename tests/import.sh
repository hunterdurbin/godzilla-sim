#!/bin/bash
# Headless project import (regenerates .uid files and the class-name cache).
# Run after adding, moving or renaming scripts/scenes outside the editor.
#
# Usage: ./tests/import.sh [godot_binary]
#   godot_binary  default: $GODOT_BIN, then `godot`
#
# Prints a digest (SCRIPT/Parse errors and ERROR lines) and the full log path.
# Exit status: 0 = import finished; 1 = missing binary, crash, timeout, or a
# SCRIPT/Parse error in the log. The import doesn't compile every script, so
# a syntax error can pass here — the unit run (run_unit_tests.sh) catches it.
#
# Wedge guard: headless Godot can hang at exit after the import is done, so
# the run is killed once the import's final step ("[ DONE ]
# loading_editor_layout") prints, or after $IMPORT_TIMEOUT seconds
# (default 300). Pure shell polling — macOS has no `timeout`.
#
# Expected noise on a fresh checkout: NotoSans/default_theme "non-existent
# resource" ERROR lines (the startup theme loads before its font is
# imported). They are printed but don't fail the run.
set -u

GODOT="${1:-${GODOT_BIN:-godot}}"
TIMEOUT="${IMPORT_TIMEOUT:-300}"
cd "$(dirname "$0")/.."

if ! command -v "$GODOT" > /dev/null 2>&1 && [ ! -x "$GODOT" ]; then
	echo "import.sh: Godot binary not found: $GODOT (pass it as \$1 or set GODOT_BIN)"
	exit 1
fi

LOG="$(mktemp "${TMPDIR:-/tmp}/godot_import_raw.XXXXXX")"
PLAIN="$(mktemp "${TMPDIR:-/tmp}/godot_import_log.XXXXXX")"

"$GODOT" --headless --path . --import > "$LOG" 2>&1 &
PID=$!

strip() { sed $'s/\x1b\\[[0-9;]*m//g' "$LOG" > "$PLAIN"; }

STATUS=""
ELAPSED=0
while :; do
	sleep 1
	ELAPSED=$((ELAPSED + 1))
	if ! kill -0 "$PID" 2>/dev/null; then
		wait "$PID"; STATUS=$?
		break
	fi
	strip
	if grep -q "\[ DONE \] loading_editor_layout" "$PLAIN"; then
		sleep 2  # let the exit happen on its own if it will
		STATUS=0; break
	fi
	if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
		echo "TIMEOUT after ${TIMEOUT}s"
		STATUS=1; break
	fi
done
kill -9 "$PID" 2>/dev/null
wait "$PID" 2>/dev/null
strip

grep -E "SCRIPT ERROR|Parse Error|^ERROR" -A1 "$PLAIN"
if grep -qE "SCRIPT ERROR|Parse Error" "$PLAIN"; then
	STATUS=1
fi
if [ "$STATUS" = 0 ]; then
	echo "IMPORT OK (${ELAPSED}s)"
else
	echo "IMPORT FAILED (status $STATUS)"
fi
echo "Full log: $PLAIN"
rm -f "$LOG"
exit "$STATUS"
