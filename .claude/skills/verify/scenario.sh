#!/bin/bash
# Headful scenario run of the real GameBoard: a solo game, then a scenario
# script's run(v) stages state (BoardEditor), fires engine entry points and
# takes screenshots. See SKILL.md § Scenarios and scenario_driver.gd for what
# `v` offers; scenarios/ holds committed examples to copy.
#
# Usage: .claude/skills/verify/scenario.sh [godot_binary] <scenario.gd> [shots_dir]
#   godot_binary  default: $GODOT_BIN, then `godot`
#   scenario.gd   any path (compiled at runtime; scratchpad throwaways are fine)
#   shots_dir     default: a new temp dir (printed)
#
# Exit status: 0 = PASS (scenario finished, no SCRIPT/Parse error);
#              1 = FAIL (error, scenario failed to load, crash, or timeout).
# Wedge guard: killed once "[Scenario] DONE" prints or after
# $SCENARIO_TIMEOUT seconds (default 180).
set -u

GODOT="${1:-${GODOT_BIN:-godot}}"
SCENARIO="${2:?usage: scenario.sh <godot> <scenario.gd> [shots_dir]}"
SHOTS="${3:-$(mktemp -d "${TMPDIR:-/tmp}/scenario_shots.XXXXXX")}"
TIMEOUT="${SCENARIO_TIMEOUT:-180}"
case "$SCENARIO" in /*) ;; *) SCENARIO="$PWD/$SCENARIO" ;; esac
cd "$(dirname "$0")/../../.."

if ! command -v "$GODOT" > /dev/null 2>&1 && [ ! -x "$GODOT" ]; then
	echo "scenario.sh: Godot binary not found: $GODOT (pass it as \$1 or set GODOT_BIN)"
	exit 1
fi
[ -f "$SCENARIO" ] || { echo "scenario.sh: no such scenario: $SCENARIO"; exit 1; }
mkdir -p "$SHOTS"
LOG="$(mktemp "${TMPDIR:-/tmp}/scenario_log.XXXXXX")"

"$GODOT" --path . res://.claude/skills/verify/scenario_driver.tscn \
	-- --scenario="$SCENARIO" --shots="$SHOTS" > "$LOG" 2>&1 &
PID=$!

STATUS=""
ELAPSED=0
while :; do
	sleep 1
	ELAPSED=$((ELAPSED + 1))
	if grep -qE "^\[Scenario\] (DONE|FAIL)" "$LOG"; then
		sleep 1; STATUS=0; break
	fi
	if grep -q "Debugger Break" "$LOG"; then
		STATUS=1; break
	fi
	if ! kill -0 "$PID" 2>/dev/null; then
		echo "Godot exited before the scenario finished"
		STATUS=1; break
	fi
	if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
		echo "TIMEOUT after ${TIMEOUT}s"
		STATUS=1; break
	fi
done
kill -9 "$PID" 2>/dev/null
wait "$PID" 2>/dev/null

grep "^\[Scenario\]" "$LOG"
grep -E "SCRIPT ERROR|Parse Error" -A1 "$LOG" | grep -v "^--$"
if grep -qE "SCRIPT ERROR|Parse Error|^\[Scenario\] FAIL" "$LOG"; then
	STATUS=1
fi
if [ "$STATUS" = 0 ]; then
	echo "SCENARIO PASS (${ELAPSED}s)"
else
	echo "SCENARIO FAIL"
fi
echo "Screenshots: $SHOTS"
echo "Full log: $LOG"
exit "$STATUS"
