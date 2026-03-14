extends CardEffect

## EBP01-040: Godzilla(1999) - Monster Rank 4 (Blue)
## <Enter> <Destroy> 1 of your opponent's rank 7 or lower battle cards.
## <When Invading> If you have 5 or more monster cards in your discard pile,
## increase this card's <Rage> by 1.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func get_bot_destroy_max_rank(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 7


func bot_can_fulfill_on_when_invading(owner: PlayerState, _opponent: PlayerState) -> bool:
	var monster_count := 0
	for card in owner.discard_pile:
		if card.get("card_type") == CardEnums.CardType.MONSTER:
			monster_count += 1
			if monster_count >= 5:
				return true
	return false


func on_enter(ctx: EffectContext) -> void:
	await ctx.effect_handler.destroy_zone_target(
		ctx.owner.player_id, ctx.opponent,
		func(card: Dictionary) -> bool: return ctx.field_rank(card, ctx.opponent.player_id) <= 7,
		"Choose an opponent's rank 7 or lower battle card to destroy:")


func on_when_invading(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	if ctx.effect_handler.count_monsters_in_discard(ctx.owner) >= 5:
		ctx.owner.rage += 1
		ctx.owner.rage_changed.emit(ctx.owner.rage)
