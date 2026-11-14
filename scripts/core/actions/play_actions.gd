class_name PlayActions
extends ActionResolver

## Main-phase card plays: battle cards, strategies, rage gain, monster plays
## (normal / burst / alternate-cost), and effect-driven monster plays.


func play_battle_card(hand_index: int, zone_index: int, state: GameState) -> void:
	var player := state.get_current_player()

	var card: Dictionary = player.remove_hand_card_at(hand_index)

	# Apply optional play costs (e.g., ESC01-001 discard a Godzilla card for rank reduction)
	var proceed: bool = await mover.apply_play_cost(player.player_id, card, zone_index)
	if not proceed:
		# Cost declined — restore card to hand
		player.insert_into_hand(mini(hand_index, player.hand.size()), card)
		events.play_cancelled.emit(player.player_id)
		return

	# Rule legality was decided when RulesEngine offered the action; the
	# enter-zone operation does the rest: stack-on-play or Overload (11.5),
	# placement, the log line, and the leave-play / <Enter> / "when played"
	# entries.
	enter_zone.enter(player.player_id, card, zone_index, EnterZone.Source.HAND, false)


func play_strategy_card(hand_index: int, state: GameState) -> void:
	var player := state.get_current_player()
	var card: Dictionary = player.remove_hand_card_at(hand_index)
	var sz_index: int = player.get_first_empty_strategy_zone_index()
	player.place_strategy(sz_index, card, state.turn_number)
	events.strategy_card_played.emit(player.player_id, card, sz_index)
	if effect_handler:
		effect_handler.log_message.emit(
			GameLog.played_strategy(player.player_id, card.get("id", ""), card.get("is_base", false)))
		dispatcher.trigger_enter(player.player_id, card)


func gain_rage(hand_index: int, state: GameState) -> void:
	var player := state.get_current_player()
	var card: Dictionary = player.remove_hand_card_at(hand_index)
	var old_rage: int = player.rage
	player.add_to_discard(card)
	player.set_rage(player.rage + 1)
	events.card_discarded.emit(player.player_id, card)
	events.rage_gained.emit(player.player_id, player.rage)
	if effect_handler:
		effect_handler.log_message.emit(
			GameLog.gained_rage(player.player_id, player.rage, card.get("id", "")))
		dispatcher.trigger_discard_from_hand(player.player_id, card)
		dispatcher.trigger_hand_card_discarded(player.player_id, card)
		dispatcher.trigger_rage_changed(player.player_id, old_rage, player.rage)


func play_monster(hand_index: int, state: GameState) -> void:
	var player := state.get_current_player()
	var card: Dictionary = player.remove_hand_card_at(hand_index)
	var old_monster: Dictionary = player.current_monster
	var old_rage: int = player.rage

	# Alternate play cost (e.g. EBP04-012): execute cost before committing, allow cancel
	var rank_mismatch: bool = card.get("rank", 0) != old_monster.get("rank", 0)
	if rank_mismatch and effect_handler and registry.has_trigger(card, "apply_play_cost"):
		var cost_ok: bool = await mover.apply_play_cost(player.player_id, card, -1)
		if not cost_ok:
			# Cost declined — restore card to hand
			player.insert_into_hand(hand_index, card)
			events.play_cancelled.emit(player.player_id)
			return
		rank_mismatch = false  # Not a burst play — cost was paid

	# Detect Burst play: card rank doesn't match current monster rank
	var is_burst_play: bool = rank_mismatch
	if is_burst_play:
		player.pre_burst_monster = old_monster
		player.burst_monster = card

	# Push old monster onto the stack (both normal and burst)
	if not old_monster.is_empty():
		player.push_under_monster(old_monster)

	player.has_played_monster_this_turn = true

	player.set_current_monster(card)
	player.set_rage(player.rage + 1)
	events.monster_played.emit(player.player_id, old_monster, card)
	events.rage_gained.emit(player.player_id, player.rage)
	if effect_handler:
		if is_burst_play:
			var burst_effect := registry.get_effect(card)
			var burst_rank: int = burst_effect.get_burst_rank() if burst_effect else -1
			effect_handler.log_message.emit(
				GameLog.burst_played(player.player_id, card.get("id", ""), burst_rank, player.rage))
		else:
			effect_handler.log_message.emit(
				GameLog.played_monster(player.player_id, card.get("id", ""), player.rage))
		# Snapshot discard before on_enter so cards milled during enter don't
		# retroactively qualify for can_play_from_discard_on_monster_played
		# (e.g. EBP02-048 milling EBP03-063 into discard).
		var discard_snapshot: Array = player.discard_pile.duplicate()
		dispatcher.trigger_enter(player.player_id, card)
		dispatcher.trigger_monster_played(player.player_id, old_monster, card, discard_snapshot)
		dispatcher.trigger_rage_changed(player.player_id, old_rage, player.rage)


func play_monster_from_effect(state: GameState, player_id: int, monster_card: Dictionary) -> void:
	## Play a monster card from the monster deck without rage increase. Does
	## NOT set `has_played_monster_this_turn` — effect-driven plays don't
	## consume the player's once-per-turn monster-play action.
	## Used by strategy effects like EBP03-074 (A Journey of 130 Million Years).
	var player := state.players[player_id]
	var old_monster: Dictionary = player.current_monster

	# Push old monster onto the stack
	if not old_monster.is_empty():
		player.push_under_monster(old_monster)

	# If a burst monster is active, the new monster buries it in the stack.
	# Clear burst state so the burst card isn't discarded at end of turn.
	if not player.burst_monster.is_empty():
		player.burst_monster = {}
		player.pre_burst_monster = {}

	player.remove_from_monster_deck(monster_card)
	player.set_current_monster(monster_card)
	events.monster_played.emit(player_id, old_monster, monster_card)
	if effect_handler:
		var discard_snapshot: Array = player.discard_pile.duplicate()
		dispatcher.trigger_enter(player_id, monster_card, true)
		dispatcher.trigger_monster_played(player_id, old_monster, monster_card, discard_snapshot)
