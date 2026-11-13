#!/bin/bash
# Headful smoke run of the real GameBoard: solo hotseat game, End Main for N
# turns (effect overlays auto-closed), screenshots at start and end.
# Use for engine/logic changes that need a "the real board still runs" check;
# write a custom driver (SKILL.md recipe) to verify specific UI behaviour.
#
# Usage: .claude/skills/verify/smoke.sh [godot_binary] [turns] [shots_dir]
#   godot_binary  default: $GODOT_BIN, then `godot`
#   turns         default: 4
#   shots_dir     default: a new temp dir (printed)
#
# Exit status: 0 = PASS (all turns advanced, no SCRIPT/Parse error);
#              1 = FAIL (error, stalled turn, crash, or timeout).
# Wedge guard: killed once "[Smoke] DONE" prints or after $SMOKE_TIMEOUT
# seconds (default 180) — pure shell polling, macOS has no `timeout`.
set -u

GODOT="${1:-${GODOT_BIN:-godot}}"
TURNS="${2:-4}"
SHOTS="${3:-$(mktemp -d "${TMPDIR:-/tmp}/smoke_shots.XXXXXX")}"
TIMEOUT="${SMOKE_TIMEOUT:-180}"
cd "$(dirname "$0")/../../.."

if ! command -v "$GODOT" > /dev/null 2>&1 && [ ! -x "$GODOT" ]; then
	echo "smoke.sh: Godot binary not found: $GODOT (pass it as \$1 or set GODOT_BIN)"
	exit 1
fi
mkdir -p "$SHOTS"
LOG="$(mktemp "${TMPDIR:-/tmp}/smoke_log.XXXXXX")"

"$GODOT" --path . res://.claude/skills/verify/smoke_driver.tscn \
	-- --turns="$TURNS" --shots="$SHOTS" > "$LOG" 2>&1 &
PID=$!

STATUS=""
ELAPSED=0
while :; do
	sleep 1
	ELAPSED=$((ELAPSED + 1))
	if grep -q "^\[Smoke\] DONE" "$LOG"; then
		sleep 1; STATUS=0; break
	fi
	if grep -q "Debugger Break" "$LOG"; then
		STATUS=1; break
	fi
	if ! kill -0 "$PID" 2>/dev/null; then
		echo "Godot exited before the smoke run finished"
		STATUS=1; break
	fi
	if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
		echo "TIMEOUT after ${TIMEOUT}s"
		STATUS=1; break
	fi
done
kill -9 "$PID" 2>/dev/null
wait "$PID" 2>/dev/null

grep "^\[Smoke\]" "$LOG"
grep -E "SCRIPT ERROR|Parse Error" -A1 "$LOG" | grep -v "^--$"
if grep -qE "SCRIPT ERROR|Parse Error|^\[Smoke\] STALL" "$LOG"; then
	STATUS=1
fi
if [ "$STATUS" = 0 ]; then
	echo "SMOKE PASS (${ELAPSED}s)"
else
	echo "SMOKE FAIL"
fi
echo "Screenshots: $SHOTS"
echo "Full log: $LOG"
exit "$STATUS"
