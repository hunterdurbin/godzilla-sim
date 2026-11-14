class_name LeaveZone
extends EffectModule

## The one "card leaves a zone" operation (GLOSSARY: Leave), the mirror of
## EnterZone. A battle card in one of the eight zones goes to an area that is
## not a zone: the discard pile, the hand, or the top or bottom of the deck.
## Every engine path that takes a battle card out of a zone runs `leave(...)`:
## Destroy (after its replacement and protection checks), a replacement that
## sends the card to the deck bottom instead, effects that return a card to
## the deck, and the 11.4 illegal-card cleanup. Being put under the card in
## another zone keeps the card in play, so it is a Move
## (`EnterZone.move_under`), not a Leave. `leave` owns:
##   1. emptying the zone (the only `PlayerState.clear_zone(` caller besides
##      EnterZone's moves — scripts/tools/check_clear_zone_owner.py);
##   2. routing the top card to the destination; a token disappears instead
##      (9.1.4.1–9.1.4.2: a battle token may exist only in zones);
##   3. sending the cards under it to the discard pile, tokens banished (they
##      are not destroyed, 5.12.1.1);
##   4. submitting the top card's on_leave_play to standby — an
##      area-changing trigger, whatever the destination (10.6.4).
## Destroy-specific parts (replacement effects, on_destroy, <Revenge>, the
## destroyed watchers) stay in DestructionEngine. Strategy-zone exits are not
## battle-zone leaves and stay where they are.

## Where the leaving card goes.
enum Destination { DISCARD, HAND, DECK_TOP, DECK_BOTTOM }


func leave(player_id: int, zone_idx: int, destination: Destination) -> Dictionary:
	## The top card of `player_id`'s zone `zone_idx` leaves it for
	## `destination`, taking the cards under it out too (to the discard pile).
	## Never prompts; fires on_leave_play, which only enters standby
	## (CheckTiming.submit).
	## Returns the card that left, or {} (nothing happens) for an empty zone.
	var player := game_state.players[player_id]
	var top_card := player.get_zone_top_card(zone_idx)
	if top_card.is_empty():
		return {}
	var stack: Array = player.clear_zone(zone_idx)
	if destination == Destination.DISCARD:
		CardMover.banish_or_discard(player, stack)
	else:
		_send_top_card(player, top_card, destination)
		CardMover.banish_or_discard(player, stack.slice(1))
	dispatcher.trigger_leave_play(player_id, top_card, zone_idx)
	return top_card


func _send_top_card(player: PlayerState, card: Dictionary, destination: Destination) -> void:
	## Put the leaving top card into its non-discard destination; a token
	## disappears instead (9.1.4.2).
	if PlayerState.is_token(card):
		return
	match destination:
		Destination.HAND:
			player.add_to_hand(card)
		Destination.DECK_TOP:
			player.put_on_deck_top(card)
		Destination.DECK_BOTTOM:
			player.put_on_deck_bottom(card)
