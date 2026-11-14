#!/bin/bash
# Run every mechanical check in scripts/tools/ — the one list that
# githooks/pre-commit and .github/workflows/tests.yml both call, so a new
# check is wired in one place (add a row to CHECKS below).
#
# Usage: scripts/tools/run_checks.sh [--staged] [<godot>]
#   --staged  only the checks whose path filter matches a staged file
#             (pre-commit); default: every check.
#   <godot>   Godot binary for check_gdscript_warnings.py (or set GODOT_BIN;
#             `godot` on PATH is the fallback). Skipped when none is found.
# Runs every selected check, then exits 1 if any failed, naming them.
set -u
cd "$(dirname "$0")/../.." || exit 2

STAGED=0
GD_BIN="${GODOT_BIN:-}"
for arg in "$@"; do
	case "$arg" in
		--staged) STAGED=1 ;;
		-h|--help) sed -n '2,11p' "$0"; exit 0 ;;
		*) GD_BIN="$arg" ;;
	esac
done
[ -n "$GD_BIN" ] || GD_BIN="$(command -v godot || true)"

# <staged-path regex>|<check script> [args]. The regex is the set of files
# that can change the check's verdict; a full run ignores it.
CHECKS=(
	'\.gd$|engine_private_calls_allowlist\.txt$|check_engine_private_calls.py'
	'\.gd$|effect_handler_card_api_allowlist\.txt$|check_effect_handler_card_api.py'
	'^scripts/effects/.*\.gd$|card_monster_zone_checks_allowlist\.txt$|check_card_monster_zone_checks.py'
	'^scripts/(core|effects)/.*\.gd$|engine_player_state_writes_allowlist\.txt$|check_card_mutations.py'
	'^scripts/effects/[^/]+\.gd$|check_effect_resolution_notes.py'
	'^scripts/effects/.*\.gd$|check_card_unawaited_coroutines.py'
	'\.gd$|check_typed_array_dynamic_calls.py'
	'\.gd$|check_player_input_contract.py'
	'^scripts/.*\.gd$|check_standby_entry_builders.py'
	'^(scripts|scenes)/.*\.gd$|check_monster_zone_writers.py'
	'^(scripts|scenes)/.*\.gd$|check_clear_zone_owner.py'
	'^(scripts|scenes)/.*\.gd$|check_rage_writers.py'
	'^scripts/(core|effects)/.*\.gd$|check_docstring_signals.py'
	'^(scripts|scenes|tests|githooks)/|check_tracker_refs.py'
	'^(scripts|scenes)/.*\.gd$|rank_up_rule_allowlist\.txt$|check_rank_up_rule_owner.py'
	'^(scripts|scenes)/.*\.gd$|check_log_message_tokens.py'
	'\.gd$|\.gd\.uid$|check_gd_uid_pairs.py'
	'\.gd$|gdscript_warnings_allowlist\.txt$|check_gdscript_warnings.py'
)

FILES=""
[ "$STAGED" -eq 1 ] && FILES="$(git diff --cached --name-only)"

FAILED=()
for row in "${CHECKS[@]}"; do
	check="${row##*|}"
	regex="${row%|*}"
	# A check script edited or added counts as touching its own check, and
	# their shared library (gd_ratchet.py) as touching every check.
	if [ "$STAGED" -eq 1 ] && ! printf '%s\n' "$FILES" \
			| grep -qE "$regex|^scripts/tools/${check//./\\.}$|^scripts/tools/gd_ratchet\.py$"; then
		continue
	fi
	args=()
	if [ "$check" = "check_gdscript_warnings.py" ]; then
		if [ -z "$GD_BIN" ]; then
			echo "run_checks: no Godot binary (pass one or set GODOT_BIN), skipping $check (CI runs it)"
			continue
		fi
		args=("$GD_BIN")
	fi
	python3 "scripts/tools/$check" "${args[@]+"${args[@]}"}" || FAILED+=("$check")
done

if [ "${#FAILED[@]}" -gt 0 ]; then
	echo "run_checks: FAILED: ${FAILED[*]}"
	exit 1
fi
