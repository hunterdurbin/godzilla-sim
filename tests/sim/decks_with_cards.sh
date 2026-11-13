#!/bin/bash
# Rank the user's decklists by how many copies of the given cards they run —
# pick deck1/deck2 for run_sim_diff.sh so the sim actually plays the cards a
# change touched (the default starters rarely do).
#
# Usage: ./tests/sim/decks_with_cards.sh <card_id> [card_id ...]
#   e.g. ./tests/sim/decks_with_cards.sh EBP03-080 ESD01-012 EBP02-077
# Output: copies  distinct/N  deck name   (best first; decks with 0 hits omitted)
#   The deck name is what run_sim_diff.sh / --deck1= expects.
# Decklist dir: $SIM_DECKLIST_DIR, else the Godot user-data decklists dir
# (macOS / Linux). Card ids match per-copy-free base ids (EBP03-080).
set -u

[ "$#" -ge 1 ] || { sed -n '2,12p' "$0"; exit 2; }

APP="Unofficial Godzilla Sim"
if [ -n "${SIM_DECKLIST_DIR:-}" ]; then
	DIR="$SIM_DECKLIST_DIR"
elif [ -d "$HOME/Library/Application Support/Godot/app_userdata/$APP/decklists" ]; then
	DIR="$HOME/Library/Application Support/Godot/app_userdata/$APP/decklists"
else
	DIR="${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/$APP/decklists"
fi
[ -d "$DIR" ] || { echo "No decklist dir: $DIR (set SIM_DECKLIST_DIR)"; exit 1; }

IDS="$*"
find "$DIR" -name '*.deck' -print0 | while IFS= read -r -d '' f; do
	awk -v ids="$IDS" -v name="$(basename "$f" .deck)" '
		BEGIN { n = split(ids, want, " "); for (i = 1; i <= n; i++) w[want[i]] = 1 }
		$2 in w { copies += $1; if (!seen[$2]++) distinct++ }
		END { if (copies > 0) printf "%3d  %d/%d  %s\n", copies, distinct, n, name }
	' "$f"
done | sort -k2,2nr -k1,1nr
