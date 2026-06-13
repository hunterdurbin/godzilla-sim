extends CardEffect

## EBP03-017: Godzilla(2003) - Monster Rank 4 (Blue)
## Whenever you discard a battle card from your hand, reduce your opponent’s <Rage> by
## 1. If your opponent’s <Rage> is 0, increase this card’s <Rage> by 1 instead.
## <Enter> You may discard 1 battle card from your hand. If you do, <Destroy> 1 of your
## opponent’s rank 6 or lower battle cards.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_hand_card_discarded": {"card_type": "battle"},
}


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func get_bot_destroy_max_rank(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 6


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	for card in owner.hand:
		if CardUtils.is_battle(card):
			return true
	return false


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS, CardEnums.EffectCategory.ACTIVATED]


func on_hand_card_discarded(ctx: EffectContext, _discarded_card: Dictionary) -> void:
	if ctx.opponent_has_rage():
		await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 1)
	else:
		await ctx.effect_handler.gain_rage(ctx.owner.player_id, 1, ctx.card_data.get("id", ""))


func on_enter(ctx: EffectContext) -> void:
	# Discard 1 battle card from hand (optional)
	var selected: Dictionary = await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool: return CardUtils.is_battle(card),
		tr("STR_EFF_EBP03_017_PROMPT"),
		true)

	if selected.is_empty():
		return

	# Destroy 1 opponent R6 or lower battle card
	await ctx.effect_handler.destroy_zone_target(
		ctx.owner.player_id, ctx.opponent,
		func(card: Dictionary) -> bool: return ctx.field_rank(card, ctx.opponent.player_id) <= 6,
		tr("STR_EFF_DESTROY_OPP_RANK_LOWER_FMT") % 6)
