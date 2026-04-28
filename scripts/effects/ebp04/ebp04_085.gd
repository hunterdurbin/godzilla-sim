extends CardEffect
## EBP04-085: The Golden Demise - Strategy Rank 1 (Green)
## When this is moved from your strategy zones to your discard pile, if you have
## 2 or more green battle cards in your zones you may return this from your
## discard pile to your hand.
## <Opponent's Turn> [Higher Dimensional Monster Ghidorah] in your zones 1-5
## cannot be <Destroy> by your opponent's effects.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


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


func protects_card_from_destruction(ctx: EffectContext, card_data: Dictionary, zone_idx: int) -> bool:
	# Opponent's Turn: protect Higher Dimensional Monster Ghidorah in zones 1-5
	if ctx.is_own_turn():
		return false
	if zone_idx >= 5:
		return false
	return CardUtils.has_trait(card_data, CardEnums.CardTrait.HIGHER_DIMENSIONAL)
