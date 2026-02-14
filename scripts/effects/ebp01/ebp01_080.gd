extends CardEffect

## EBP01-080: Godzilla and its son on Monster Island - Strategy Rank 6 (White)
## If your opponent has a strategy card in play, you can play this from your hand
## with its rank reduced by 2.
## While this card is in the strategy zone, your rank 5 or lower battle cards in
## zones 1-5 cannot be <Destroy> by your opponent's effects.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func get_play_rank_modifier_for_card(ctx: EffectContext, target_card: Dictionary) -> int:
	# Only modifies self
	if target_card.get("id") != ctx.card_data.get("id"):
		return 0
	# Check if opponent has any strategy card in play
	for sz_card in ctx.opponent.strategy_zones:
		if not sz_card.is_empty():
			return -2
	return 0


func protects_card_from_destruction(_ctx: EffectContext, card_data: Dictionary, zone_idx: int) -> bool:
	# Protect rank 5 or lower battle cards in zones 1-5 (indices 0-4)
	if zone_idx > 4:
		return false
	if card_data.get("card_type") != CardEnums.CardType.BATTLE:
		return false
	if card_data.get("rank", 0) > 5:
		return false
	return true


func is_base_strategy() -> bool:
	return false
