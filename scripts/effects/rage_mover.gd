class_name RageMover
extends EffectModule

## The Rage module: the only engine code that changes a monster card's
## <Rage> during a match (hunterdurbin/godzilla-sim-issue-tracker#35 row 18).
## `scripts/tools/check_rage_writers.py` keeps `set_rage(` here, plus
## match setup (match_factory.gd) and the F4 board editor dev tool.
## Every change goes through one of its operations:
##   * `increase` — a Rage increase (GLOSSARY): the Gain Rage action
##     (8.4.1), playing a monster card (8.5.1.1) or an effect. Each one
##     emits GameEvents.rage_gained, writes the log line (row 21) and puts
##     the Rage abilities in standby — one entry per point for "increase"
##     watchers (Q381, TriggerDispatcher.trigger_rage_changed).
##   * `decrease` — an effect reducing Rage. It asks the prevention effects
##     with the controller of the reducing effect (row 20: EBP03-004 stops
##     only the opponent's effects), leaves one RAGE marker per point for
##     claiming abilities (EBP04-089) and puts the Rage abilities in standby.
##   * `reset` — the start phase (7.2): Rage back to 0 unless an on_rage_reset
##     effect intercepts it (EBP04-010); a drop leaves markers and triggers
##     like a decrease.
## The abilities enter standby; they resolve at the next check timing.

## What caused an increase; picks the log line (the Gain Rage action has its
## own; the others share rage_gained with the source card).
enum Cause {
	## The Gain Rage action (8.4.1); `source_card_id` = the discarded card.
	GAIN_RAGE_ACTION,
	## Playing a monster card (8.5.1.1); `source_card_id` = the played card.
	MONSTER_PLAY,
	## An effect; `source_card_id` = the card whose effect it is ("" = none).
	EFFECT,
}


func increase(player_id: int, amount: int, cause: Cause, source_card_id: String = "") -> int:
	## Raise the player's Rage by `amount` (a Rage increase of `amount`,
	## GLOSSARY). Emits GameEvents.rage_gained and the log line, then submits
	## the Rage abilities to standby (TriggerDispatcher.trigger_rage_changed:
	## one entry per point for increase watchers, Q381). Returns the amount
	## gained.
	if amount <= 0:
		return 0
	var player := game_state.players[player_id]
	var old_rage: int = player.rage
	player.set_rage(old_rage + amount)
	if events:
		events.rage_gained.emit(player_id, player.rage)
	if cause == Cause.GAIN_RAGE_ACTION:
		h.log_message.emit(GameLog.gained_rage(player_id, player.rage, source_card_id))
	else:
		h.log_message.emit(GameLog.rage_gained(player_id, amount, player.rage, source_card_id))
	dispatcher.trigger_rage_changed(player_id, old_rage, player.rage)
	return amount


func decrease(player_id: int, amount: int, reducer_id: int) -> int:
	## Reduce the player's Rage by up to `amount`. Returns the amount reduced
	## (0 when prevented or already 0). `reducer_id` is the controller of the
	## reducing effect, -1 for none (a rule). It is named by the caller, never
	## taken from the resolving ability: a passive or engine path runs outside
	## CheckTiming.run_effect, and a nested one would lend the innermost
	## ability's player (hunterdurbin/godzilla-sim-issue-tracker#48).
	## Prevention effects see it (EBP03-004 stops only the opponent's,
	## hunterdurbin/godzilla-sim-issue-tracker#35 row 20).
	## Leaves one RAGE marker per point and submits the Rage abilities.
	var player := game_state.players[player_id]
	if not player.has_rage() or amount <= 0:
		return 0
	if queries.is_rage_reduction_prevented(player_id, reducer_id):
		return 0
	var actual: int = mini(amount, player.rage)
	_lower(player_id, player.rage - actual)
	return actual


func reset(player_id: int) -> void:
	## Start phase Rage reset (7.2): 0, or the value an on_rage_reset effect
	## keeps (EBP04-010 keeps 2; its choice may prompt, so await this). The
	## kept value is a drop, never an increase — Q508: "No, it does not
	## increase. For example, if Rage is 5, it becomes 5 → 2. It does not go
	## 5 → 0 → 2." A drop leaves markers and triggers like a decrease.
	var new_rage: int = await dispatcher.apply_rage_reset(player_id)
	if new_rage < game_state.players[player_id].rage:
		_lower(player_id, new_rage)


func _lower(player_id: int, new_rage: int) -> void:
	## Set the lower Rage, leave one RAGE marker per point for claiming
	## abilities (EBP04-089; CheckTiming.resolve drops the unclaimed ones) and
	## put the Rage abilities in standby.
	var player := game_state.players[player_id]
	var old_rage: int = player.rage
	player.set_rage(new_rage)
	player.push_pending_rage_markers(old_rage - new_rage)
	dispatcher.trigger_rage_changed(player_id, old_rage, new_rage)
