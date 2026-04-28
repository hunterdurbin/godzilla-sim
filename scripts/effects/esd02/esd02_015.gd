extends CardEffect

## ESD02-015: Burning Godzilla's Rampage - Strategy Rank 7
## Choose 1 of your opponent's zones. <Destroy> all of your opponent's battle cards
## in that zone and zones adjacent to it.
## (For example, if a card is in zone 7, the adjacent zones are 4, 6, and 8.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func on_enter(ctx: EffectContext) -> void:
	var all_zones: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
	await ctx.effect_handler.destroy_zone_and_adjacent(
		ctx.owner.player_id, ctx.opponent, all_zones,
		tr("STR_EFF_ESD02_015_PROMPT"))
