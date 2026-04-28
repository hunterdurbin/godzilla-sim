extends CardEffect
## EBP04-049: Ebirah (2004) - Battle Rank 5 (Blue)
## At the beginning of your counter phase, if you have a Rank 8 or higher
## battle card in play, reveal and discard 1 card from the top of your deck.
## If it is a non-blue card decrease your opponent's <Rage> by -2. If it's a
## blue card <Destroy> 1 of your rank 8 or higher battle cards.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_phase_start": {"phase": CardEnums.GamePhase.COUNTER, "own_turn": true},
}


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent", "mill_self"]


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	var has_rank8_plus: bool = not ctx.effect_handler.get_zones_in_rank_range(
		ctx.owner.player_id, 8, -1).is_empty()
	if not has_rank8_plus:
		return

	var top_card := await ctx.mill_one()
	if top_card.is_empty():
		return

	var is_blue: bool = CardUtils.has_color(top_card, CardEnums.CardColor.BLUE)

	if not is_blue:
		await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 2)
	else:
		var valid_zones: Array[int] = ctx.effect_handler.get_zones_in_rank_range(
			ctx.owner.player_id, 8, -1)
		if not valid_zones.is_empty():
			var chosen: int = await ctx.effect_handler.select_zone_target(
				ctx.owner.player_id, ctx.owner.player_id, valid_zones,
				tr("STR_EFF_DESTROY_OWN_RANK_HIGHER_FMT") % 8)
			if chosen >= 0:
				await ctx.effect_handler.destroy_zones(ctx.owner, [chosen])
