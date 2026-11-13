#!/bin/bash
# Run the gdUnit4 unit suite headless (also used by CI — keep the name/path).
#
# Usage: ./tests/run_unit_tests.sh [godot_binary] [test_path] [--verbose]
#   godot_binary  default: $GODOT_BIN, then `godot`
#   test_path     suite file or directory (default: tests/unit)
#   --verbose     print the full gdUnit log instead of the digest
#
# Default output is a digest: each failure report, SCRIPT/Parse errors, the
# summary (ANSI stripped) and — on failure — a "Failed test cases: N" line
# (gdUnit's own "failures" counts assertions, not tests). The full log path
# is printed at the end.
# Exit status: gdUnit's own exit code; 1 on parse error / crash / timeout.
#
# Wedge guard: headless Godot can hang at exit after gdUnit finishes, and a
# parse error drops `-d` into an interactive `debug>` prompt. The run is
# killed once gdUnit prints "Exit code: N", hits the debugger, or exceeds
# $GDUNIT_TIMEOUT seconds (default 900).
set -u

GODOT="${1:-${GODOT_BIN:-godot}}"
TARGET="${2:-tests/unit}"
VERBOSE=0
[ "${3:-}" = "--verbose" ] && VERBOSE=1
TIMEOUT="${GDUNIT_TIMEOUT:-900}"
cd "$(dirname "$0")/.."

LOG="$(mktemp "${TMPDIR:-/tmp}/gdunit_raw.XXXXXX")"
PLAIN="$(mktemp "${TMPDIR:-/tmp}/gdunit_log.XXXXXX")"

"$GODOT" --headless --path . -s -d addons/gdUnit4/bin/GdUnitCmdTool.gd \
	--ignoreHeadlessMode -a "$TARGET" -c > "$LOG" 2>&1 &
PID=$!

strip() { sed $'s/\x1b\\[[0-9;]*m//g' "$LOG" > "$PLAIN"; }

STATUS=""
ELAPSED=0
while :; do
	sleep 1
	ELAPSED=$((ELAPSED + 1))
	strip
	if grep -q "^Exit code: " "$PLAIN"; then
		sleep 1; strip
		STATUS=$(grep -m1 "^Exit code: " "$PLAIN" | sed 's/[^0-9]//g')
		break
	fi
	if grep -q "Debugger Break\|^debug>" "$PLAIN"; then
		STATUS=1; break
	fi
	if ! kill -0 "$PID" 2>/dev/null; then
		STATUS=1; break
	fi
	if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
		echo "TIMEOUT after ${TIMEOUT}s"
		STATUS=1; break
	fi
done
kill -9 "$PID" 2>/dev/null
wait "$PID" 2>/dev/null

if [ "$VERBOSE" = 1 ]; then
	cat "$PLAIN"
else
	# Failure blocks run from a FAILED line until the next test/summary line.
	awk '
		/ FAILED / { infail = 1; print; next }
		infail && (/ STARTED/ || / PASSED / || /^Statistics:/ || /^Overall Summary:/) { infail = 0 }
		infail { print; next }
		/SCRIPT ERROR|Parse Error|Debugger Break/ { print; getline; print; next }
		/^Overall Summary:|^Executed test (suites|cases)|^Exit code:/ { print }
	' "$PLAIN"
	# gdUnit's "N failures" counts failed ASSERTIONS; this counts failed tests.
	FAILED_TESTS=$(grep -c ' FAILED ' "$PLAIN")
	[ "$FAILED_TESTS" -gt 0 ] && echo "Failed test cases: $FAILED_TESTS (Overall Summary 'failures' counts assertions)"
fi
echo "Full log: $PLAIN"
rm -f "$LOG"
exit "${STATUS:-1}"
