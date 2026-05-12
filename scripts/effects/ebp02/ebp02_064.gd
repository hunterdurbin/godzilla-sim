extends CardEffect

## EBP02-064: Gigan(1972) - Battle Rank 6 (Green)
## If there is a card with <《King Ghidorah》> or <《Megalon》> in your zones, this card
## gains +3000 counter power.
## <Revenge> Return up to 1 <《King Ghidorah》> monster card from your discard pile to
## your hand. (Activates when destroyed by a card effect or monster movement.)
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_cp", "draws_cards"]


func get_counter_power_modifier(ctx: EffectContext) -> int:
	var has: bool = ctx.owner.has_zone_matching(
		func(c: Dictionary) -> bool:
			return CardUtils.has_any_trait(c, [CardEnums.CardTrait.KING_GHIDORAH, CardEnums.CardTrait.MEGALON]))
	if has:
		return 3000
	return 0


func on_revenge(ctx: EffectContext) -> void:
	var selected := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			if not CardUtils.is_monster(card):
				return false
			return CardUtils.has_trait(card, CardEnums.CardTrait.KING_GHIDORAH),
		tr("STR_EFF_EBP02_058_PROMPT"))

	if not selected.is_empty():
		await ctx.effect_handler.return_discard_to_hand(ctx.owner.player_id, selected)
