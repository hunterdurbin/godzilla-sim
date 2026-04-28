extends CardEffect

## EFC01-002: Gigan(Gojika Festival) - Battle Rank 5 (White)
## <Enter> If this card is in a zone adjacent to your monster card, send the top card
## of your deck to your discard pile. If it is a battle card, you may return up to 1
## monster card from your discard pile to your hand.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["mill_self", "draws_cards"]


func on_enter(ctx: EffectContext) -> void:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return
	var monster_zone_idx: int = ctx.owner.monster_zone - 1
	if monster_zone_idx < 0:
		return
	var adjacent := get_adjacent_zones(monster_zone_idx)
	if zone_idx not in adjacent:
		return

	var card := await ctx.mill_one()
	if card.is_empty():
		return

	if not CardUtils.is_battle(card):
		return

	var selected := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			return CardUtils.is_monster(card),
		tr("STR_EFF_EFC01_002_PROMPT"))

	if not selected.is_empty():
		await ctx.effect_handler.return_discard_to_hand(ctx.owner.player_id, selected)
