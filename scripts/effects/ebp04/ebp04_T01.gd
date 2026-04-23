extends CardEffect
## EBP04-T01: Godzilla Earth - Battle Rank 7 (Green)
## (Tokens cannot be added to the deck. They are banished when removed from
## zones.)
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func on_destroy(ctx: EffectContext, _zone_idx: int) -> void:
	var card: Dictionary = ctx.owner.get_zone_top_card(7)
	if card.get("id") == "EBP04-067":
		await ctx.effect_handler.destroy_zones(ctx.owner, [7])


func on_zone_changed(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	var card: Dictionary = ctx.owner.get_zone_top_card(7)
	if card.get("id") == "EBP04-067":
		await ctx.effect_handler.destroy_zones(ctx.owner, [7])
