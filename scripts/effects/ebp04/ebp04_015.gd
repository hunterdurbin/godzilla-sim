extends CardEffect
## EBP04-015: Godzilla(2003) - Monster Rank 4 (Blue)
## Whenever you discard a battle card from your hand, if your opponent’s <Rage> is 0,
## <Destroy> 1 of your opponent’s rank 6 or lower battle cards.
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


func on_hand_card_discarded(ctx: EffectContext, _discarded_card: Dictionary) -> void:
	if ctx.opponent_has_rage():
		return
	await ctx.effect_handler.destroy_zone_target(
		ctx.owner.player_id, ctx.opponent,
		func(card: Dictionary) -> bool: return ctx.field_rank(card, ctx.opponent.player_id) <= 6,
		tr("STR_EFF_DESTROY_OPP_RANK_LOWER_FMT") % 6)
