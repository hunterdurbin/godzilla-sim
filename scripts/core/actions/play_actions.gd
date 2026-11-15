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
	## The Activate action; legality was decided when RulesEngine offered it.
	var player := state.get_current_player()
	var card: Dictionary = player.remove_hand_card_at(hand_index)
	enter_zone.play_strategy(player.player_id, card, EnterZone.Source.HAND, false)


func gain_rage(hand_index: int, state: GameState) -> void:
	var player := state.get_current_player()
	var card: Dictionary = player.remove_hand_card_at(hand_index)
	player.add_to_discard(card)
	events.card_discarded.emit(player.player_id, card)
	dispatcher.trigger_discard_from_hand(player.player_id, card)
	dispatcher.trigger_hand_card_discarded(player.player_id, card)
	rage_mover.increase(player.player_id, 1, RageMover.Cause.GAIN_RAGE_ACTION, card.get("id", ""))


func play_monster(hand_index: int, state: GameState) -> void:
	## The Play Monster action. It owns the once-per-turn flag, the +1 Rage,
	## Burst detection and the alternate cost; EnterZone.play_monster does
	## the play itself (hunterdurbin/godzilla-sim-issue-tracker#35 row 16).
	var player := state.get_current_player()
	var card: Dictionary = player.remove_hand_card_at(hand_index)
	var old_monster: Dictionary = player.current_monster

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
	if rank_mismatch:
		player.pre_burst_monster = old_monster
		player.burst_monster = card

	player.has_played_monster_this_turn = true
	enter_zone.play_monster(player.player_id, card, EnterZone.MonsterSource.HAND)
	# 8.5.1.1: the +1 comes once the played card is the invading monster, so
	# its own "whenever this card's <Rage> is increased" abilities see it.
	rage_mover.increase(player.player_id, 1, RageMover.Cause.MONSTER_PLAY, card.get("id", ""))


func play_monster_from_effect(_state: GameState, player_id: int, monster_card: Dictionary) -> void:
	## Play a monster card from the monster deck without rage increase. Does
	## NOT set `has_played_monster_this_turn` — effect-driven plays don't
	## consume the player's once-per-turn monster-play action.
	## Used by strategy effects like EBP03-074 (A Journey of 130 Million Years).
	## A Burst card it covers is still discarded at the end phase (12.5.2.1).
	enter_zone.play_monster(player_id, monster_card, EnterZone.MonsterSource.MONSTER_DECK)
