extends CardEffect
## EBP04-079: Godzilla Final Wars - Strategy Rank 7 (Red)
## Reveal the top 7 cards of your deck, play all  《Final Wars》 battle cards from among
## them, then send the rest to your discard pile.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["plays_other_cards", "searches_deck"]


func on_enter(ctx: EffectContext) -> void:
	var revealed := await ctx.effect_handler.reveal_deck_top(ctx.owner.player_id, 7)
	if revealed.is_empty():
		return

	var final_wars_cards: Array[Dictionary] = []
	var other_cards: Array[Dictionary] = []
	for card in revealed:
		if CardUtils.is_battle(card) and CardUtils.has_trait(card, CardEnums.CardTrait.FINAL_WARS):
			final_wars_cards.append(card)
		else:
			other_cards.append(card)

	# Play all Final Wars battle cards into different zones (rule 5.11.1.3).
	# The player picks which card to play next and the zone for it; cards may
	# overload occupied zones, but no zone is reused within this effect. If zones
	# run out before cards do, the leftover cards stay unplayed.
	var unplayed: Array[Dictionary] = await ctx.effect_handler.play_battle_cards_in_zones(
		ctx.owner, final_wars_cards, tr("STR_EFF_EBP04_079_PICK"))

	# Discard everything that wasn't played — the non-matching cards plus any Final
	# Wars cards that couldn't be placed — together, after the battle cards are played.
	ctx.effect_handler.discard_cards(ctx.owner.player_id, other_cards + unplayed)
