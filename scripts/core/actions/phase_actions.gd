class_name PhaseActions
extends ActionResolver

## Automated phase steps: start-phase draw / strategy discard / rage reset,
## end-phase burst discard / advance / hand refill.


func execute_start_phase_draw(state: GameState) -> void:
	var player := state.get_current_player()
	var opponent := state.get_opponent_of_current()
	var draw_count: int = opponent.get_monster_rank()
	player.draw_cards(draw_count)
	events.cards_drawn.emit(player.player_id, draw_count)


func execute_start_phase_discard(state: GameState) -> void:
	var player := state.get_current_player()

	# Clear strategy cards placed before this turn
	# Collect indices to discard first, then process (replacement effects handled by helper)
	var indices_to_discard: Array[int] = []
	for i in range(player.strategy_zones.size()):
		if not player.strategy_zones[i].is_empty():
			if player.strategy_zone_turn_placed[i] < state.turn_number:
				# Base strategies are exempt from start phase discard (12.9.2 / 7.2.3)
				if queries.is_base_strategy(player.strategy_zones[i]):
					continue
				# Cards with custom anti-discard rule text (e.g. EBP04-089) are also exempt
				if queries.prevents_self_start_phase_discard(player.player_id, player.strategy_zones[i]):
					continue
				indices_to_discard.append(i)

	if not indices_to_discard.is_empty():
		var cleared: Array = []
		for i in indices_to_discard:
			# Start phase discard (7.2.3) is a rule action, not <Destroy> — bypass protection.
			var card := await destruction.discard_strategy_from_zone(player.player_id, i, null, true)
			if not card.is_empty():
				cleared.append(card)
		if not cleared.is_empty():
			events.strategy_cleared.emit(player.player_id, cleared)


func execute_start_phase_reset(state: GameState) -> void:
	var player := state.get_current_player()

	# Reset rage to 0, allowing effects to intercept (e.g. EBP04-010)
	var old_rage: int = player.rage
	var new_rage: int = await dispatcher.apply_rage_reset(player.player_id)
	player.set_rage(new_rage)
	# Fire rage_changed trigger so cards that watch for rage decrease (EBP04-089)
	# pick up the start phase reset. Populate the claim bucket on decrease so
	# they can pop markers as a true resource; the check timing clears leftovers.
	if new_rage != old_rage:
		var delta: int = old_rage - new_rage
		if delta > 0:
			player.push_pending_rage_markers(delta)
		dispatcher.trigger_rage_changed(player.player_id, old_rage, new_rage)

	# Reset per-turn flags
	player.has_invaded_this_turn = false
	player.has_played_monster_this_turn = false
	player.invasion_zones_crossed = 0

	# Clear destroyed-this-turn tracking for both players
	for p in state.players:
		p.cards_destroyed_this_turn.clear()


func execute_end_phase_burst_discard(state: GameState) -> void:
	## Discard Burst monster at beginning of end phase and restore previous monster.
	var player := state.get_current_player()
	if not player.burst_monster.is_empty():
		var burst_card: Dictionary = player.burst_monster
		player.add_to_discard(burst_card)
		# Pop the pre-burst monster off the stack (it was pushed when burst was played)
		player.pop_under_monster()
		player.set_current_monster(player.pre_burst_monster)
		player.burst_monster = {}
		player.pre_burst_monster = {}
		await dispatcher.trigger_burst_discard(player.player_id, burst_card)


func execute_end_phase_advance(state: GameState) -> void:
	## Advance monster (7.5.2) and check crush rule.
	## Extra advance from effects (e.g. EBP02-056 SpaceGodzilla R4) adds additional zones.
	## Movement fully resolves before triggered abilities activate; cards crushed during
	## movement are filtered out of the standby queue.
	var player := state.get_current_player()

	# Check if monster is blocked from advancing (e.g. Biollante Rose Form)
	if queries.is_monster_advance_blocked(player.player_id):
		return

	var extra: int = queries.get_extra_end_phase_advance(player.player_id)
	var total_advance: int = 1 + extra
	var deferred_entries: Array = []
	var from_invasion := false  # the 7.5.2 advance is not an invasion
	monster_mover.advance(player.player_id, total_advance, from_invasion, deferred_entries)

	# Submit the collected abilities once all movement completes; they
	# resolve at the 7.5.3 check timing.
	check_timing.submit(deferred_entries)


func execute_end_phase_draw(state: GameState) -> void:
	## Draw up to 5 cards (7.5.4).
	var player := state.get_current_player()
	# Skip silently if hand is already at the cap — no draw would happen anyway,
	# so the "draw blocked" log line would just be noise.
	if player.hand.size() >= 5:
		return
	if queries.is_opponent_end_phase_draw_blocked(player.player_id):
		effect_handler.log_message.emit(tr("STR_AH_END_PHASE_DRAW_BLOCKED"))
		return
	var drawn := player.draw_up_to(5)
	if drawn.size() > 0:
		events.cards_drawn.emit(player.player_id, drawn.size())
