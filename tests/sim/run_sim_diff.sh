#!/bin/bash
# Seed-matched bot-sim behavioral diff: the working tree vs a base ref.
#
# Usage: ./tests/sim/run_sim_diff.sh <godot> [base_ref] [games] [p1] [p2] [deck1] [deck2] [seed]
#                                    [--pair "deckA|deckB"]...
#   defaults: main 50 HARD HARD "ESD01 Starter" "ESD02 Starter" 424242
#   p1/p2 are BotConfig.Difficulty names (EASY NORMAL HARD KAIJU).
#   A deck is a decklist name or @<path> to a .deck file (e.g. a committed
#   @tests/sim/decks/cov_*.deck; relative paths resolve against this repo).
#   --pair (repeatable, anywhere in the args) runs several deck pairs against
#   ONE imported base worktree; when given, deck1/deck2 are ignored.
#
# Builds a detached worktree of base_ref (imported headless once), copies
# THIS tree's bot_simulation_runner.gd into it (so both sides run the same
# harness and accept the same args), then per pair runs both sims in
# parallel and reports:
#   - [SimResult] lines that differ (empty = no bot-visible behavior change)
#   - SPLIT: per game whose [SimTurn] trace differs, the last shared turn
#     line and the first differing one, base vs head (first_divergence.py),
#     so every divergence traces to the turn and monsters it started from
#   - per side: games completed, P1 wins, SCRIPT ERROR count, and
#     `[Kaiju] … plan DIVERGED` count (the KAIJU replay-parity metric:
#     the planner's cached plan stopped matching the live game)
# and finally, per changed card script (scripts/effects/<set>/*.gd differing
# from base_ref, incl. untracked): how many times its abilities started
# resolving, base -> head, per pair and in total ([SimEffects] line). A card
# whose head total is 0 is UNEXERCISED: the [SimResult] diff says nothing
# about it — pick decks that run it (decks_with_cards.sh). Passive-only
# cards (modifiers, replacement queries) never "resolve" and always show 0.
# Head runs straight from the working tree, so the tree is fingerprinted
# (HEAD + tracked diff + untracked files) at the start and re-checked after
# every pair: an edit mid-run means the verdict covers mixed code.
# Exit status (also printed as the final "STATUS: <n> (...)" line):
#   0 = identical results and no script errors on this tree;
#   1 = results differ / script errors / missing games (any pair);
#   2 = otherwise clean, but some changed card was UNEXERCISED;
#   3 = the working tree changed during the run — the verdict is void, rerun
#       without editing (overrides 0-2);
#   4 = bad arguments (games / seed not integers, p1/p2 not a difficulty,
#       a --pair without "|"): nothing ran. A deck name passed as a
#       positional arg (e.g. `--pair "A" "B"`) lands here instead of
#       running unmatched seeds.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"

POS=()
PAIRS=()
while [ "$#" -gt 0 ]; do
	case "$1" in
		--pair) PAIRS+=("${2:?--pair needs \"deckA|deckB\"}"); shift 2 ;;
		--pair=*) PAIRS+=("${1#--pair=}"); shift ;;
		*) POS+=("$1"); shift ;;
	esac
done
set -- "${POS[@]+"${POS[@]}"}"

GODOT="${1:?usage: run_sim_diff.sh <godot> [base_ref] [games] [p1] [p2] [deck1] [deck2] [seed] [--pair \"A|B\"]...}"
BASE_REF="${2:-main}"
GAMES="${3:-50}"
P1="${4:-HARD}"
P2="${5:-HARD}"
DECK1="${6:-ESD01 Starter}"
DECK2="${7:-ESD02 Starter}"
SEED="${8:-424242}"
TIMEOUT="${SIM_TIMEOUT:-3600}"

# Reject misplaced args up front: a deck name that slips into a positional
# slot would otherwise become the seed or game count, run unmatched games
# and report a bogus behaviour diff.
bad_args() {
	echo "run_sim_diff.sh: $1" >&2
	echo "usage: run_sim_diff.sh <godot> [base_ref] [games] [p1] [p2] [deck1] [deck2] [seed] [--pair \"A|B\"]..." >&2
	echo "STATUS: 4 (bad arguments)"
	exit 4
}
[ "${#POS[@]}" -le 8 ] || bad_args "too many positional args (${#POS[@]}): quote deck names; a pair is --pair \"A|B\""
[[ "$GAMES" =~ ^[0-9]+$ ]] || bad_args "games must be an integer, got '$GAMES'"
[[ "$SEED" =~ ^-?[0-9]+$ ]] || bad_args "seed must be an integer, got '$SEED'"
for side in "$P1" "$P2"; do
	case "$side" in
		EASY|NORMAL|HARD|KAIJU) ;;
		*) bad_args "p1/p2 must be EASY, NORMAL, HARD or KAIJU, got '$side'" ;;
	esac
done
for pair in "${PAIRS[@]+"${PAIRS[@]}"}"; do
	[[ "$pair" == *"|"* ]] || bad_args "--pair needs \"deckA|deckB\", got '$pair'"
done
[ "${#PAIRS[@]}" -gt 0 ] || PAIRS=("$DECK1|$DECK2")

# @relative -> @/abs/path in THIS repo, so the base worktree (which may not
# have the deck file) reads the same deck.
resolve_deck() {
	case "$1" in
		@/*|@res://*) printf '%s' "$1" ;;
		@*) printf '@%s/%s' "$REPO" "${1#@}" ;;
		*) printf '%s' "$1" ;;
	esac
}

# Fingerprint of everything head runs: HEAD, the tracked diff, and the
# untracked files' contents (.godot and other ignored paths excluded).
tree_fingerprint() {
	{
		git -C "$REPO" rev-parse HEAD
		git -C "$REPO" diff HEAD --binary
		git -C "$REPO" ls-files --others --exclude-standard -z \
			| (cd "$REPO" && xargs -0 shasum 2>/dev/null)
	} | shasum | cut -d' ' -f1
}

# Head runs on this tree's class-name cache: refresh it if a script was
# added, moved or renamed outside the editor (the base worktree imports below).
if ! python3 "$REPO/scripts/tools/check_class_cache.py" --quiet; then
	echo "run_sim_diff.sh: importing to refresh the class-name cache"
	"$REPO/tests/import.sh" "$GODOT" > /dev/null || { echo "FAIL: tests/import.sh failed"; exit 1; }
fi
TREE_FP="$(tree_fingerprint)"
TREE_CHANGED=0

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

# Import the base tree once (class-name cache). Headless Godot may wedge at
# exit, so bound it instead of waiting.
"$GODOT" --headless --path "$BASE_WT" --import > "$WORK/import.log" 2>&1 &
IPID=$!
for _ in $(seq 1 180); do
	sleep 1
	kill -0 "$IPID" 2>/dev/null || break
done
kill -9 "$IPID" 2>/dev/null

run_sim() { # <dir> <out> <deck1> <deck2>
	"$GODOT" --headless --path "$1" res://tests/sim/BotSimulationRunner.tscn -- \
		--games="$GAMES" --seed="$SEED" --p1="$P1" --p2="$P2" \
		--deck1="$3" --deck2="$4" > "$2" 2>&1 &
	local pid=$! elapsed=0
	while kill -0 "$pid" 2>/dev/null; do
		sleep 5; elapsed=$((elapsed + 5))
		grep -q '^\[SimEffects\]' "$2" && { sleep 1; break; }
		[ "$(grep -c '\[SimResult\]' "$2")" -ge "$GAMES" ] && { sleep 3; break; }
		[ "$elapsed" -ge "$TIMEOUT" ] && { echo "TIMEOUT: $2" >> "$2"; break; }
	done
	kill -9 "$pid" 2>/dev/null
}

summary() { # <label> <log>
	local res wins
	res=$(grep -c '\[SimResult\]' "$2")
	wins=$(grep '\[SimResult\]' "$2" | grep -c 'winner=0')
	printf '  %-5s games=%s/%s p1_wins=%s script_errors=%s kaiju_diverged=%s%s\n' "$1" \
		"$res" "$GAMES" "$wins" "$(grep -c 'SCRIPT ERROR' "$2")" \
		"$(grep -c 'plan DIVERGED' "$2")" "$(grep -q '^TIMEOUT' "$2" && echo ' TIMEOUT')"
}

STATUS=0
LOGS=()
i=0
for pair in "${PAIRS[@]}"; do
	i=$((i + 1))
	d1="${pair%%|*}"; d2="${pair#*|}"
	echo "[$i] Sim diff: $BASE_REF vs working tree | $GAMES games, seed $SEED, $P1 ($d1) vs $P2 ($d2)"
	run_sim "$BASE_WT" "$WORK/base$i.log" "$(resolve_deck "$d1")" "$(resolve_deck "$d2")" &
	run_sim "$REPO" "$WORK/head$i.log" "$(resolve_deck "$d1")" "$(resolve_deck "$d2")" &
	wait
	summary base "$WORK/base$i.log"
	summary head "$WORK/head$i.log"
	grep '\[SimResult\]' "$WORK/base$i.log" > "$WORK/base$i.res"
	grep '\[SimResult\]' "$WORK/head$i.log" > "$WORK/head$i.res"
	if diff "$WORK/base$i.res" "$WORK/head$i.res" > "$WORK/diff$i.txt"; then
		echo "  RESULT: identical [SimResult] lines"
	else
		echo "  RESULT: $(grep -c '^>' "$WORK/diff$i.txt") differing games:"
		sed 's/^/    /' "$WORK/diff$i.txt"
		STATUS=1
	fi
	# Turn traces catch games that split mid-game, even ones that reconverge
	# on the same [SimResult]; the first differing [SimTurn] is where to look.
	if ! python3 "$REPO/tests/sim/first_divergence.py" "$WORK/base$i.log" "$WORK/head$i.log" \
			> "$WORK/split$i.txt"; then
		echo "  SPLIT: $(grep -c '^game=' "$WORK/split$i.txt") games' turn traces differ (last shared, then first differing [SimTurn]):"
		sed 's/^/    /' "$WORK/split$i.txt"
		STATUS=1
	fi
	[ "$(grep -c 'SCRIPT ERROR' "$WORK/head$i.log")" -eq 0 ] || STATUS=1
	[ "$(grep -c '\[SimResult\]' "$WORK/head$i.log")" -ge "$GAMES" ] || STATUS=1
	LOGS+=("$WORK/base$i.log" "$WORK/head$i.log")
	if [ "$TREE_CHANGED" -eq 0 ] && [ "$(tree_fingerprint)" != "$TREE_FP" ]; then
		echo "  WARNING: the working tree changed during this pair — head ran mixed code"
		TREE_CHANGED=1
	fi
done

# Changed card scripts -> card ids (via the effect_script paths in the set
# files) -> resolution counts per side, per pair.
CHANGED=$( { git -C "$REPO" diff --name-only "$BASE_REF" -- 'scripts/effects/*/*.gd';
	git -C "$REPO" ls-files --others --exclude-standard -- 'scripts/effects/*/*.gd'; } | sort -u)
if [ -n "$CHANGED" ]; then
	UNEXERCISED=$(python3 - "$REPO" "${#PAIRS[@]}" "${LOGS[@]}" -- $CHANGED <<'PY'
import glob, os, re, sys
args = sys.argv[1:]
repo, npairs = args[0], int(args[1])
logs = args[2:2 + 2 * npairs]
changed = args[2 + 2 * npairs + 1:]
ids_for = {}
for set_file in sorted(glob.glob(os.path.join(repo, "scripts/cards/sets/card_set_*.gd"))):
    last_id = None
    for line in open(set_file, encoding="utf-8"):
        m = re.search(r'"id":\s*"([^"]+)"', line)
        if m:
            last_id = m.group(1)
        m = re.search(r'"effect_script":\s*"res://([^"]+)"', line)
        if m and last_id:
            ids_for.setdefault(m.group(1), []).append(last_id)
def counts(log):
    for line in open(log, encoding="utf-8", errors="replace"):
        if line.startswith("[SimEffects]"):
            parts = line.split()[1:]
            if parts == ["unavailable"]:
                return None
            return {k: int(v) for k, v in (p.split("=") for p in parts)}
    return None
pairs = [(counts(logs[2 * i]), counts(logs[2 * i + 1])) for i in range(npairs)]
def fmt(c, cid):
    return "?" if c is None else str(c.get(cid, 0))
unexercised = []
head_cols = "  ".join("[%d] base->head" % (i + 1) for i in range(npairs))
print("Changed card scripts (abilities resolved): %s%s" % (head_cols, "  total" if npairs > 1 else ""), file=sys.stderr)
for path in changed:
    for cid in ids_for.get(path, [os.path.basename(path)]):
        cols, head_total, base_total = [], 0, 0
        for b, h in pairs:
            cols.append("%5s -> %-5s" % (fmt(b, cid), fmt(h, cid)))
            head_total += h.get(cid, 0) if h is not None else 0
            base_total += b.get(cid, 0) if b is not None else 0
        def tot(side_total, idx):
            return "?" if all(p[idx] is None for p in pairs) else str(side_total)
        total = ("  %5s -> %-5s" % (tot(base_total, 0), tot(head_total, 1))) if npairs > 1 else ""
        flag = "  UNEXERCISED" if head_total == 0 else ""
        print("  %-12s %s%s%s" % (cid, "  ".join(cols), total, flag), file=sys.stderr)
        if flag:
            unexercised.append(cid)
print(" ".join(unexercised))
PY
)
	if [ -n "$UNEXERCISED" ]; then
		echo "UNEXERCISED on this tree: $UNEXERCISED (identical results are no evidence for these)"
		[ "$STATUS" -eq 0 ] && STATUS=2
	fi
fi
echo "Logs: $WORK/{base,head}<n>.log"
[ "$TREE_CHANGED" -eq 1 ] && STATUS=3
# Last line carries the verdict, so it survives `| grep` / `| tail` filters.
case "$STATUS" in
	0) echo "STATUS: 0 (identical)" ;;
	2) echo "STATUS: 2 (unexercised)" ;;
	3) echo "STATUS: 3 (working tree changed during the run: verdict void, rerun without editing)" ;;
	*) echo "STATUS: $STATUS (differs, script errors or missing games)" ;;
esac
exit $STATUS
