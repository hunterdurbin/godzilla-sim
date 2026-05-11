extends CardEffect
## EBP04-024: Godzilla Ultima - Monster Rank 4 (Green)
## <Enter> If you have 10 or more green battle cards in your discard pile, you
## may <Destroy> any number of your opponent's battle cards whose total ranks
## add up to 7 or less.
## This card gains +1000 threat level for each green battle card in your
## discard pile.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: The 7-rank limit applies to the SUM of destroyed
##   cards' (effective) ranks — not the remaining board state. Eligible
##   zones are gated each iteration so the player can't pick one that would
##   overflow the budget.


const MAX_RANK_BUDGET: int = 7


func get_bot_tags() -> Array[String]:
	return ["destroys_zone", "boosts_threat"]


func get_threat_level_modifier(ctx: EffectContext) -> int:
	return _green_battle_discard_count(ctx) * 1000


func bot_can_fulfill_on_enter(_owner: PlayerState, opponent: PlayerState) -> bool:
	return not opponent.get_battle_card_zone_indices().is_empty()


func on_enter(ctx: EffectContext) -> void:
	if _green_battle_discard_count(ctx) < 10:
		return

	var spent_rank: int = 0
	while true:
		var remaining: int = MAX_RANK_BUDGET - spent_rank
		var eligible: Array[int] = []
		for i in range(8):
			var zone_card := ctx.opponent.get_zone_top_card(i)
			if zone_card.is_empty():
				continue
			var r: int = ctx.field_rank(zone_card, ctx.opponent.player_id)
			if r > remaining:
				continue
			if not ctx.effect_handler.can_destroy_card(ctx.opponent, zone_card):
				continue
			eligible.append(i)

		if eligible.is_empty():
			break

		var chosen: int = await ctx.effect_handler.select_zone_target(
			ctx.owner.player_id, ctx.opponent.player_id, eligible,
			tr("STR_EFF_EBP04_024_DESTROY_FMT") % remaining, true)
		if chosen < 0:
			break

		# Capture rank before destruction — destroy_zones mutates the zone.
		var destroyed_card := ctx.opponent.get_zone_top_card(chosen)
		var destroyed_rank: int = ctx.field_rank(destroyed_card, ctx.opponent.player_id)
		await ctx.effect_handler.destroy_zones(ctx.opponent, [chosen])
		spent_rank += destroyed_rank


func _green_battle_discard_count(ctx: EffectContext) -> int:
	return CardUtils.count(ctx.owner.discard_pile,
		func(c: Dictionary) -> bool:
			return CardUtils.is_battle(c) and CardUtils.has_color(c, CardEnums.CardColor.GREEN))
