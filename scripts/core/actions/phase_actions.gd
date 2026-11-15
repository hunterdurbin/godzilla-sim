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
			var card := await destruction.discard_strategy_from_zone(player.player_id, i, true)
			if not card.is_empty():
				cleared.append(card)
		if not cleared.is_empty():
			events.strategy_cleared.emit(player.player_id, cleared)


func execute_start_phase_reset(state: GameState) -> void:
	var player := state.get_current_player()

	# Rage back to 0 unless an effect intercepts (EBP04-010); decrease
	# watchers (EBP04-089) see the drop.
	await rage_mover.reset(player.player_id)

	# Reset per-turn flags
	player.has_invaded_this_turn = false
	player.has_played_monster_this_turn = false
	player.invasion_zones_crossed = 0

	# Clear destroyed-this-turn tracking for both players
	for p in state.players:
		p.cards_destroyed_this_turn.clear()


func execute_end_phase_burst_discard(state: GameState) -> void:
	## Burst (12.5.2): at the beginning of the end phase the Burst card goes
	## from the invading monster to the discard pile — 12.5.2.1: "Even if
	## this card is not the topmost card at the beginning of the end phase
	## for any reason, the card is still sent to the discard pile." Only when
	## it is still on top does the monster card under it become the invading
	## monster again; neither case is a play, so nothing enters (12.5.3,
	## Q107: "No, it does not.")
	## (hunterdurbin/godzilla-sim-issue-tracker#35 row 15).
	var player := state.get_current_player()
	if player.burst_monster.is_empty():
		return
	var burst_card: Dictionary = player.burst_monster
	var pre_burst: Dictionary = player.pre_burst_monster
	player.burst_monster = {}
	player.pre_burst_monster = {}
	if player.current_monster == burst_card:
		player.remove_from_monster_stack(pre_burst)
		player.set_current_monster(pre_burst)
	elif not player.remove_from_monster_stack(burst_card):
		return  # an effect already moved it out of the invading monster
	player.add_to_discard(burst_card)
	await dispatcher.trigger_burst_discard(player.player_id, burst_card)


func execute_end_phase_advance(state: GameState) -> void:
	## Advance monster (7.5.2) and check crush rule.
	## Extra advance from effects (e.g. EBP02-056 SpaceGodzilla R4) adds additional zones.
	## The abilities the movement triggers enter standby and resolve at the
	## 7.5.3 check timing, after the whole advance.
	var player := state.get_current_player()

	# Check if monster is blocked from advancing (e.g. Biollante Rose Form)
	if queries.is_monster_advance_blocked(player.player_id):
		return

	var extra: int = queries.get_extra_end_phase_advance(player.player_id)
	var total_advance: int = 1 + extra
	var from_invasion := false  # the 7.5.2 advance is not an invasion
	monster_mover.advance(player.player_id, total_advance, from_invasion)


func execute_end_phase_draw(state: GameState) -> void:
	## Draw up to 5 cards (7.5.4).
	var player := state.get_current_player()
	# Skip silently if hand is already at the cap — no draw would happen anyway,
	# so the "draw blocked" log line would just be noise.
	if player.hand.size() >= 5:
		return
	if queries.is_opponent_end_phase_draw_blocked(player.player_id):
		effect_handler.log_message.emit(GameLog.end_phase_draw_blocked())
		return
	var drawn := player.draw_up_to(5)
	if drawn.size() > 0:
		events.cards_drawn.emit(player.player_id, drawn.size())
