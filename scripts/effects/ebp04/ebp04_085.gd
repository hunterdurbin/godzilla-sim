extends CardEffect
## EBP04-085: The Golden Demise - Strategy Rank 1 (Green)
## When this card is sent from the strategy zone to your discard pile, if you have 2 or
## more green battle cards in your zones, you may return this card from your discard
## pile to your hand.
## <Opponent’s Turn> “Void Ghidorah” in your zones 1–5 cannot be <Destroy> by your
## opponent’s effects.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"protects_card_from_destruction": {"own_turn": false, "caused_by_opponent": true},
}


func get_bot_tags() -> Array[String]:
	return ["protects_cards"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func on_strategy_discarded(ctx: EffectContext, strategy_card: Dictionary) -> void:
	if strategy_card.get("id", "") != ctx.card_data.get("id", ""):
		return

	var green_count: int = ctx.owner.count_zones_matching(
		func(c: Dictionary) -> bool:
			return CardUtils.is_battle(c) and CardUtils.has_color(c, CardEnums.CardColor.GREEN))

	if green_count < 2:
		return

	await ctx.effect_handler.return_discard_to_hand(ctx.owner.player_id, strategy_card)


func protects_card_from_destruction(_ctx: EffectContext, card_data: Dictionary, zone_idx: int) -> bool:
	# Turn / cause-by-opponent gating handled by TRIGGER_FILTERS.
	# Protect Higher Dimensional Monster Ghidorah in zones 1-5.
	if zone_idx >= 5:
		return false
	return CardUtils.has_trait(card_data, CardEnums.CardTrait.HIGHER_DIMENSIONAL)
