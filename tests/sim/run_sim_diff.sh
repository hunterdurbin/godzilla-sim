#!/bin/bash
# Seed-matched bot-sim behavioral diff: the working tree vs a base ref.
#
# Usage: ./tests/sim/run_sim_diff.sh <godot> [base_ref] [games] [p1] [p2] [deck1] [deck2] [seed]
#   defaults: main 50 HARD HARD "ESD01 Starter" "ESD02 Starter" 424242
#   p1/p2 are BotConfig.Difficulty names (EASY NORMAL HARD KAIJU).
#
# Builds a detached worktree of base_ref (imported headless), copies THIS
# tree's bot_simulation_runner.gd into it (so both sides run the same harness
# and accept the same args), runs both sims in parallel, then reports:
#   - [SimResult] lines that differ (empty = no bot-visible behavior change)
#   - per side: games completed, P1 wins, SCRIPT ERROR count, and
#     `[Kaiju] … plan DIVERGED` count (the KAIJU replay-parity metric:
#     the planner's cached plan stopped matching the live game)
# Exit status: 0 = identical results and no script errors on this tree.
set -u

GODOT="${1:?usage: run_sim_diff.sh <godot> [base_ref] [games] [p1] [p2] [deck1] [deck2] [seed]}"
BASE_REF="${2:-main}"
GAMES="${3:-50}"
P1="${4:-HARD}"
P2="${5:-HARD}"
DECK1="${6:-ESD01 Starter}"
DECK2="${7:-ESD02 Starter}"
SEED="${8:-424242}"
TIMEOUT="${SIM_TIMEOUT:-3600}"

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/simdiff.XXXXXX")"
BASE_WT="$WORK/base"

cleanup() {
	pkill -9 -f "$BASE_WT" 2>/dev/null
	git -C "$REPO" worktree remove --force "$BASE_WT" 2>/dev/null
}
trap cleanup EXIT

git -C "$REPO" worktree add --detach "$BASE_WT" "$BASE_REF" >/dev/null 2>&1 \
	|| { echo "FAIL: cannot create worktree for $BASE_REF"; exit 1; }
cp "$REPO/tests/sim/bot_simulation_runner.gd" "$BASE_WT/tests/sim/bot_simulation_runner.gd"

# Import the base tree (class-name cache). Headless Godot may wedge at exit,
# so bound it instead of waiting.
"$GODOT" --headless --path "$BASE_WT" --import > "$WORK/import.log" 2>&1 &
IPID=$!
for _ in $(seq 1 180); do
	sleep 1
	kill -0 "$IPID" 2>/dev/null || break
done
kill -9 "$IPID" 2>/dev/null

run_sim() { # <dir> <out>
	"$GODOT" --headless --path "$1" res://tests/sim/BotSimulationRunner.tscn -- \
		--games="$GAMES" --seed="$SEED" --p1="$P1" --p2="$P2" \
		--deck1="$DECK1" --deck2="$DECK2" > "$2" 2>&1 &
	local pid=$! elapsed=0
	while kill -0 "$pid" 2>/dev/null; do
		sleep 5; elapsed=$((elapsed + 5))
		[ "$(grep -c '\[SimResult\]' "$2")" -ge "$GAMES" ] && { sleep 3; break; }
		[ "$elapsed" -ge "$TIMEOUT" ] && { echo "TIMEOUT: $2" >> "$2"; break; }
	done
	kill -9 "$pid" 2>/dev/null
}

echo "Sim diff: $BASE_REF vs working tree | $GAMES games, seed $SEED, $P1 ($DECK1) vs $P2 ($DECK2)"
run_sim "$BASE_WT" "$WORK/base.log" &
run_sim "$REPO" "$WORK/head.log" &
wait

summary() { # <label> <log>
	local res wins
	res=$(grep -c '\[SimResult\]' "$2")
	wins=$(grep '\[SimResult\]' "$2" | grep -c 'winner=0')
	printf '%-5s games=%s/%s p1_wins=%s script_errors=%s kaiju_diverged=%s%s\n' "$1" \
		"$res" "$GAMES" "$wins" "$(grep -c 'SCRIPT ERROR' "$2")" \
		"$(grep -c 'plan DIVERGED' "$2")" "$(grep -q '^TIMEOUT' "$2" && echo ' TIMEOUT')"
}
summary base "$WORK/base.log"
summary head "$WORK/head.log"

grep '\[SimResult\]' "$WORK/base.log" > "$WORK/base.res"
grep '\[SimResult\]' "$WORK/head.log" > "$WORK/head.res"
if diff "$WORK/base.res" "$WORK/head.res" > "$WORK/diff.txt"; then
	echo "RESULT: identical [SimResult] lines"
	STATUS=0
else
	echo "RESULT: $(grep -c '^>' "$WORK/diff.txt") differing games:"
	cat "$WORK/diff.txt"
	STATUS=1
fi
[ "$(grep -c 'SCRIPT ERROR' "$WORK/head.log")" -eq 0 ] || STATUS=1
[ "$(grep -c '\[SimResult\]' "$WORK/head.log")" -ge "$GAMES" ] || STATUS=1
echo "Logs: $WORK/{base,head}.log"
exit $STATUS
