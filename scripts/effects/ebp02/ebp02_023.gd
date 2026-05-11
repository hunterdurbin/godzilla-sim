extends CardEffect

## EBP02-023: Godzilla(1999) - Monster Rank 4 (Blue)
## <Enter> If you have 5 or more monster cards in your discard pile, 1 of your
## opponent's monster cards with 50,000 or less threat level retreats back by 1 zone.
## If you have 10 or more monster cards in your discard pile, this card gains +10,000
## threat level.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_threat", "weakens_opponent"]


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	var monster_count: int = 0
	for card in owner.discard_pile:
		if CardUtils.is_monster(card):
			monster_count += 1
			if monster_count >= 5:
				return true
	return false


func bot_can_fulfill_threat_level(owner: PlayerState, _opponent: PlayerState) -> bool:
	var monster_count: int = 0
	for card in owner.discard_pile:
		if CardUtils.is_monster(card):
			monster_count += 1
			if monster_count >= 10:
				return true
	return false


func on_enter(ctx: EffectContext) -> void:
	var monster_count: int = CardUtils.count_monsters_in_discard(ctx.owner.discard_pile)
	if monster_count < 5:
		return

	var opp_tl: int = ctx.effect_handler.get_effective_threat_level(ctx.opponent.player_id)
	if opp_tl <= 50000 and ctx.opponent.monster_zone > 1:
		await ctx.effect_handler.retreat_monster_to_zone(ctx.opponent.player_id, ctx.opponent.monster_zone - 1)


func get_threat_level_modifier(ctx: EffectContext) -> int:
	if CardUtils.count_monsters_in_discard(ctx.owner.discard_pile) >= 10:
		return 10000
	return 0
