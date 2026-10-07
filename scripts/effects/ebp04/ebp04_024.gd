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
##   cards' (effective) ranks — see
##   EffectHandler.destroy_zones_within_rank_budget.


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
	await ctx.effect_handler.destroy_zones_within_rank_budget(
		ctx.owner.player_id, ctx.opponent, MAX_RANK_BUDGET)


func _green_battle_discard_count(ctx: EffectContext) -> int:
	return CardUtils.count(ctx.owner.discard_pile,
		func(c: Dictionary) -> bool:
			return CardUtils.is_battle(c) and CardUtils.has_color(c, CardEnums.CardColor.GREEN))
