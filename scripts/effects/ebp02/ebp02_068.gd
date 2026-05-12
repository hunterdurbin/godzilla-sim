extends CardEffect

## EBP02-068: Mecha-King Ghidorah - Battle Rank 23 (Green)
## You can play this card from your hand with its rank reduced by 2 for each non-rank 23
## <《King Ghidorah》> card in your discard pile. (This card's rank returns to 23 after
## being played.)
## If this card is in the same column as your opponent's monster card, they cannot
## invade, and this card gains +3000 counter power.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["blocks_invade", "column_dependent_monster", "boosts_cp"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func get_play_rank_modifier_for_card(ctx: EffectContext, target_card: Dictionary) -> int:
	# Only modifies self
	if target_card.get("id") != ctx.card_data.get("id"):
		return 0
	# Count non-rank-23 King Ghidorah cards in discard
	var count: int = 0
	for card in ctx.owner.discard_pile:
		if card.get("rank", 0) != 23:
			if CardUtils.has_trait(card, CardEnums.CardTrait.KING_GHIDORAH):
				count += 1
	return -2 * count


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if _is_in_opponent_monster_column(ctx):
		return 3000
	return 0


func prevents_opponent_invasion(ctx: EffectContext) -> bool:
	return _is_in_opponent_monster_column(ctx)


func _is_in_opponent_monster_column(ctx: EffectContext) -> bool:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return false
	var opp_monster_idx: int = ctx.opponent.monster_zone - 1
	if opp_monster_idx < 0:
		return false
	var facing_zones := get_opponent_column_zones(zone_idx)
	return opp_monster_idx in facing_zones
