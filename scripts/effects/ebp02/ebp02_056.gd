extends CardEffect

## EBP02-056: SpaceGodzilla - Monster Rank 4 (Green)
## If you have 3 or more "Crystals" in your zones, this card gains +20,000 threat level.
## <Your Turn> When this card advances during the end phase, it advances 1 additional
## zone for each "Crystals" in your zones.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_threat", "advances_monster"]



func get_threat_level_modifier(ctx: EffectContext) -> int:
	if ctx.owner.count_zone_tokens_by_id("EBP02-T03") >= 3:
		return 20000
	return 0


func get_extra_end_phase_advance(ctx: EffectContext) -> int:
	# <Your Turn> — only active during owner's turn
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return 0
	return ctx.owner.count_zone_tokens_by_id("EBP02-T03")
