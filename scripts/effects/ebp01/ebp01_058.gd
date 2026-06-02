extends CardEffect

## EBP01-058: Biollante Plant Beast Form - Battle Rank 7 (Blue)
## If you have a <《Biollante》> card with <Evolution> in your discard pile, you can play
## this from your hand with its rank reduced by 2. (After being played, this card is
## rank 7.)
## <Enter> Return all cards in your discard pile to your deck then shuffle.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["heals_deck", "plays_from_discard"]


func get_play_rank_modifier_for_card(ctx: EffectContext, target_card: Dictionary) -> int:
	# Only modifies self
	if target_card.get("id") != ctx.card_data.get("id"):
		return 0
	# Check for a Biollante card with Evolution in discard
	for card in ctx.owner.discard_pile:
		if CardUtils.has_trait(card, CardEnums.CardTrait.BIOLLANTE) and card.has("evolution_rank"):
			return -2
	return 0


func on_enter(ctx: EffectContext) -> void:
	ctx.effect_handler.shuffle_discard_into_deck(ctx.owner.player_id)
