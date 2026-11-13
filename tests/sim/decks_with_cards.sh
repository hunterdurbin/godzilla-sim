#!/bin/bash
# Rank decklists by how many copies of the given cards they run — pick
# deck1/deck2 (or --pair) for run_sim_diff.sh so the sim actually plays the
# cards a change touched (the default starters rarely do).
#
# Usage: ./tests/sim/decks_with_cards.sh <card_id> [card_id ...]
#   e.g. ./tests/sim/decks_with_cards.sh EBP03-080 ESD01-012 EBP02-077
# Output: copies  distinct/N  deck   (best first; decks with 0 hits omitted)
#   then "NOT IN ANY DECK: <ids>" for cards no deck runs.
#   The deck column is what run_sim_diff.sh / --deck1= expects: a decklist
#   name, or @tests/sim/decks/<file>.deck for the committed coverage decks.
# Scans the user's decklists ($SIM_DECKLIST_DIR, else the Godot user-data
# decklists dir on macOS / Linux) and tests/sim/decks/. Card ids are base ids
# (EBP03-080). A card in no deck: add a coverage deck to tests/sim/decks/
# (see tests/sim/README.md) rather than a throwaway in the user's decklists.
set -u

[ "$#" -ge 1 ] || { sed -n '2,16p' "$0"; exit 2; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
APP="Unofficial Godzilla Sim"
if [ -n "${SIM_DECKLIST_DIR:-}" ]; then
	DIR="$SIM_DECKLIST_DIR"
elif [ -d "$HOME/Library/Application Support/Godot/app_userdata/$APP/decklists" ]; then
	DIR="$HOME/Library/Application Support/Godot/app_userdata/$APP/decklists"
else
	DIR="${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/$APP/decklists"
fi
[ -d "$DIR" ] || { echo "No user decklist dir: $DIR (set SIM_DECKLIST_DIR); scanning tests/sim/decks only" >&2; DIR=""; }

IDS="$*"
RANKED=$(
	{
		[ -n "$DIR" ] && find "$DIR" -name '*.deck' -print0 | while IFS= read -r -d '' f; do
			printf '%s\t%s\n' "$(basename "$f" .deck)" "$f"
		done
		for f in "$REPO"/tests/sim/decks/*.deck; do
			[ -e "$f" ] && printf '@%s\t%s\n' "${f#"$REPO"/}" "$f"
		done
	} | while IFS=$'\t' read -r name f; do
		awk -v ids="$IDS" -v name="$name" '
			BEGIN { n = split(ids, want, " "); for (i = 1; i <= n; i++) w[want[i]] = 1 }
			$2 in w { copies += $1; if (!seen[$2]++) distinct++; hit[$2] = 1 }
			END {
				if (copies > 0) {
					printf "%3d  %d/%d  %s\t", copies, distinct, n, name
					for (id in hit) printf "%s ", id
					printf "\n"
				}
			}
		' "$f"
	done | sort -k2,2nr -k1,1nr
)
[ -n "$RANKED" ] && printf '%s\n' "$RANKED" | cut -f1

MISSING=""
for id in $IDS; do
	printf '%s\n' "$RANKED" | cut -f2 | grep -qw -- "$id" || MISSING="$MISSING $id"
done
[ -z "$MISSING" ] || echo "NOT IN ANY DECK:$MISSING"
