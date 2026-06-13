extends CardEffect

## EBP03-027: Ghidorah(2001) - Monster Rank 3 (Green)
## <Your Turn> If there are 3 or more cards under this card, reduce the rank of all
## battle cards in your opponent's zones by 2.
## <When Invading> If there are 5 or more cards under this card, your opponent discards
## cards until they have 4 cards remaining in their hand.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent", "disrupts_hand"]


func bot_can_fulfill_on_when_invading(owner: PlayerState, opponent: PlayerState) -> bool:
	return owner.has_monster_stack(5) and opponent.hand.size() > 4


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func get_opponent_field_rank_modifier(ctx: EffectContext) -> int:
	if ctx.is_opponent_turn():
		return 0
	if not ctx.has_monster_stack(3):
		return 0
	return -2


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	if not ctx.has_monster_stack(5):
		return
	if ctx.opponent.hand.size() <= 4:
		return
	await ctx.effect_handler.discard_hand_to(ctx.opponent.player_id, 4)
