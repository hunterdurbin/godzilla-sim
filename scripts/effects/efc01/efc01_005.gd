extends CardEffect

## EFC01-005: Godzilla Appears in Godzilla Festival - Strategy Rank 6 (Red)
## 《Your Turn》 When your monster card enters, reveal the top 5 cards of your deck. Add
## all <Fest> cards to your hand and discard the rest. At the beginning of
## your counter phase, discard your hand.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_phase_start": {"phase": CardEnums.GamePhase.COUNTER, "own_turn": true},
}


func get_bot_tags() -> Array[String]:
	return ["draws_cards"]


func on_monster_played(ctx: EffectContext, _old_monster: Dictionary, _new_monster: Dictionary) -> void:
	# Only during your turn
	if ctx.is_opponent_turn():
		return

	# Reveal top 5 cards (taken off the deck, shown to both players)
	var revealed: Array[Dictionary] = await ctx.effect_handler.reveal_deck_top(
		ctx.owner.player_id, 5, "STR_EFF_REVEALED_CARDS")
	if revealed.is_empty():
		return

	# Separate Fest cards from the rest
	var fest_cards: Array[Dictionary] = []
	var rest: Array[Dictionary] = []
	for card in revealed:
		if CardUtils.has_trait(card, CardEnums.CardTrait.FEST):
			fest_cards.append(card)
		else:
			rest.append(card)

	ctx.effect_handler.add_cards_to_hand(ctx.owner.player_id, fest_cards)
	ctx.effect_handler.discard_cards(ctx.owner.player_id, rest)


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	# Discard entire hand
	await ctx.effect_handler.discard_hand_to(ctx.owner.player_id, 0)
