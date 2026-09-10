extends CardEffect

## EPR-019: Gravity Beam - Strategy Rank 7 (White)
## If you have a battle card with both <《Fest》> and <《King Ghidorah》> in your
## zones, you can play this card from your hand with its rank reduced by 3.
## Your opponent discards cards until they have 3 cards remaining in their hand.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["disrupts_hand"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS, CardEnums.EffectCategory.ACTIVATED]


func get_play_rank_modifier_for_card(ctx: EffectContext, target_card: Dictionary) -> int:
	# Only modifies self
	if target_card.get("id") != ctx.card_data.get("id"):
		return 0
	if _has_fest_ghidorah(ctx.owner):
		return -3
	return 0


func on_enter(ctx: EffectContext) -> void:
	await ctx.effect_handler.discard_hand_to(ctx.opponent.player_id, 3)


static func _has_fest_ghidorah(owner: PlayerState) -> bool:
	return owner.count_zones_matching(
		func(card: Dictionary) -> bool:
			return CardUtils.is_battle(card) \
				and CardUtils.has_trait(card, CardEnums.CardTrait.FEST) \
				and CardUtils.has_trait(card, CardEnums.CardTrait.KING_GHIDORAH)) > 0
