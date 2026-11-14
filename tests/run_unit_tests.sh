#!/bin/bash
# Run the gdUnit4 unit suite headless (also used by CI — keep the name/path).
#
# Usage: ./tests/run_unit_tests.sh [godot_binary] [test_path] [--verbose] [--per-suite]
#   godot_binary  default: $GODOT_BIN, then `godot`
#   test_path     suite file or directory (default: tests/unit)
#   --verbose     print the full gdUnit log instead of the digest
#   --per-suite   run every test_*.gd under test_path in its own Godot
#                 process and aggregate. A SCRIPT ERROR (e.g. an out-of-bounds
#                 index) aborts the whole gdUnit run under `-d`, hiding every
#                 later failure; per-suite confines an abort to its suite, so
#                 one pass lists every failing suite. Slower (one startup per
#                 suite) — use it when a run aborts or many tests are expected
#                 to fail. $GDUNIT_JOBS suites run in parallel (default 1).
#
# Default output is a digest: each failure report, SCRIPT/Parse errors, the
# summary (ANSI stripped) and — on failure — a "Failed test cases: N" line
# (gdUnit's own "failures" counts assertions, not tests). The full log path
# is printed at the end. --per-suite prints the digest of each suite that
# failed or aborted, then one "Per-suite summary" line.
# Stale class-name cache (a script added / moved / renamed outside the
# editor; scripts/tools/check_class_cache.py) → tests/import.sh runs first.
# Exit status: gdUnit's own exit code; 1 on parse error / crash / timeout;
# --per-suite: 0 only when every suite passed.
#
# Wedge guard: headless Godot can hang at exit after gdUnit finishes, and a
# parse error drops `-d` into an interactive `debug>` prompt. The run is
# killed once gdUnit prints "Exit code: N", hits the debugger, or exceeds
# $GDUNIT_TIMEOUT seconds (default 900).
set -u

POSITIONAL=()
VERBOSE=0
PER_SUITE=0
for arg in "$@"; do
	case "$arg" in
		--verbose) VERBOSE=1 ;;
		--per-suite) PER_SUITE=1 ;;
		*) POSITIONAL+=("$arg") ;;
	esac
done
GODOT="${POSITIONAL[0]:-${GODOT_BIN:-godot}}"
TARGET="${POSITIONAL[1]:-tests/unit}"
TIMEOUT="${GDUNIT_TIMEOUT:-900}"
JOBS="${GDUNIT_JOBS:-1}"
cd "$(dirname "$0")/.."

# A script added, moved or renamed outside the editor leaves the class-name
# cache stale, and every suite touching that class fails to parse
# ("Identifier X not declared"). Import first when the cache is behind.
if command -v python3 > /dev/null 2>&1 && ! python3 scripts/tools/check_class_cache.py --quiet; then
	echo "run_unit_tests.sh: importing to refresh the class-name cache"
	./tests/import.sh "$GODOT" > /dev/null || { echo "run_unit_tests.sh: tests/import.sh failed"; exit 1; }
fi

# run_one <target> <plain_log>: run gdUnit on one target, write the
# ANSI-stripped log to <plain_log>, return gdUnit's exit code (1 on abort).
run_one() {
	local target="$1" plain="$2" raw pid status="" elapsed=0
	raw="$(mktemp "${TMPDIR:-/tmp}/gdunit_raw.XXXXXX")"
	"$GODOT" --headless --path . -s -d addons/gdUnit4/bin/GdUnitCmdTool.gd \
		--ignoreHeadlessMode -a "$target" -c > "$raw" 2>&1 &
	pid=$!
	while :; do
		sleep 1
		elapsed=$((elapsed + 1))
		sed $'s/\x1b\\[[0-9;]*m//g' "$raw" > "$plain"
		if grep -q "^Exit code: " "$plain"; then
			sleep 1; sed $'s/\x1b\\[[0-9;]*m//g' "$raw" > "$plain"
			status=$(grep -m1 "^Exit code: " "$plain" | sed 's/[^0-9]//g')
			break
		fi
		if grep -q "Debugger Break\|^debug>" "$plain"; then
			status=1; break
		fi
		if ! kill -0 "$pid" 2>/dev/null; then
			status=1; break
		fi
		if [ "$elapsed" -ge "$TIMEOUT" ]; then
			echo "TIMEOUT after ${TIMEOUT}s" >> "$plain"
			status=1; break
		fi
	done
	kill -9 "$pid" 2>/dev/null
	wait "$pid" 2>/dev/null
	rm -f "$raw"
	return "${status:-1}"
}

# digest <plain_log>: failure blocks, SCRIPT/Parse errors and the summary.
digest() {
	# Failure blocks run from a FAILED line until the next test/summary line.
	awk '
		/ FAILED / { infail = 1; print; next }
		infail && (/ STARTED/ || / PASSED / || /^Statistics:/ || /^Overall Summary:/) { infail = 0 }
		infail { print; next }
		/SCRIPT ERROR|Parse Error|Debugger Break|^TIMEOUT/ { print; getline; print; next }
		/^Overall Summary:|^Executed test (suites|cases)|^Exit code:/ { print }
	' "$1"
}

if [ "$PER_SUITE" = 1 ]; then
	if [ -f "$TARGET" ]; then
		SUITES=("$TARGET")
	else
		SUITES=()
		while IFS= read -r f; do SUITES+=("$f"); done < <(find "$TARGET" -name 'test_*.gd' | sort)
	fi
	OUTDIR="$(mktemp -d "${TMPDIR:-/tmp}/gdunit_suites.XXXXXX")"
	export -f run_one
	export GODOT TIMEOUT
	# Each suite: <OUTDIR>/<n>.log (plain log) + <n>.status (exit code).
	for i in "${!SUITES[@]}"; do printf '%s\t%s\n' "$i" "${SUITES[$i]}"; done \
		| xargs -P "$JOBS" -L 1 bash -c \
			'run_one "$1" "'"$OUTDIR"'/$0.log"; echo $? > "'"$OUTDIR"'/$0.status"'
	PASSED=0; FAILED=0; ABORTED=0; FAILED_TESTS=0; BAD=()
	for i in "${!SUITES[@]}"; do
		log="$OUTDIR/$i.log"
		st=$(cat "$OUTDIR/$i.status" 2>/dev/null || echo 1)
		n=$(grep -c ' FAILED ' "$log" 2>/dev/null); n=${n:-0}
		FAILED_TESTS=$((FAILED_TESTS + n))
		if [ "$st" = 0 ]; then
			PASSED=$((PASSED + 1)); continue
		fi
		if grep -q "^Overall Summary:" "$log"; then
			FAILED=$((FAILED + 1)); BAD+=("FAILED  ${SUITES[$i]}")
		else
			ABORTED=$((ABORTED + 1)); BAD+=("ABORTED ${SUITES[$i]}")
		fi
		echo "=== ${SUITES[$i]} (exit $st) — log: $log"
		if [ "$VERBOSE" = 1 ]; then cat "$log"; else digest "$log"; fi
	done
	echo
	for b in ${BAD[@]+"${BAD[@]}"}; do echo "$b"; done
	echo "Per-suite summary: ${#SUITES[@]} suites | $PASSED passed | $FAILED failed | $ABORTED aborted | $FAILED_TESTS failed test cases"
	echo "Logs: $OUTDIR"
	[ $((FAILED + ABORTED)) -eq 0 ]
	exit $?
fi

PLAIN="$(mktemp "${TMPDIR:-/tmp}/gdunit_log.XXXXXX")"
run_one "$TARGET" "$PLAIN"
STATUS=$?

if [ "$VERBOSE" = 1 ]; then
	cat "$PLAIN"
else
	digest "$PLAIN"
	# gdUnit's "N failures" counts failed ASSERTIONS; this counts failed tests.
	FAILED_TESTS=$(grep -c ' FAILED ' "$PLAIN")
	[ "$FAILED_TESTS" -gt 0 ] && echo "Failed test cases: $FAILED_TESTS (Overall Summary 'failures' counts assertions)"
	# GDScript warnings not in the ratchet allowlist (scripts this run compiled;
	# the full check is scripts/tools/check_gdscript_warnings.py).
	if command -v python3 > /dev/null 2>&1; then
		python3 scripts/tools/check_gdscript_warnings.py --log "$PLAIN" --new-only
	fi
fi
echo "Full log: $PLAIN"
exit "$STATUS"
