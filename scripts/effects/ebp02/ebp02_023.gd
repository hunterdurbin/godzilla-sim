extends CardEffect

## EBP02-023: Godzilla(1999) - Monster Rank 4 (Blue)
## <Enter> If you have 5 or more monster cards in your discard pile, 1 of your opponent's
## monster cards with 50,000 or less threat level retreats back by 1 zone.
## If you have 10 or more monster cards in your discard pile, this card gains +10,000 TL.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_threat", "weakens_opponent"]


func on_enter(ctx: EffectContext) -> void:
	var monster_count: int = ctx.effect_handler.count_monsters_in_discard(ctx.owner)
	if monster_count < 5:
		return

	var opp_tl: int = ctx.opponent.get_threat_level()
	if opp_tl <= 50000 and ctx.opponent.monster_zone > 1:
		await ctx.effect_handler.retreat_monster_to_zone(ctx.opponent.player_id, ctx.opponent.monster_zone - 1)


func get_threat_level_modifier(ctx: EffectContext) -> int:
	if ctx.effect_handler.count_monsters_in_discard(ctx.owner) >= 10:
		return 10000
	return 0
