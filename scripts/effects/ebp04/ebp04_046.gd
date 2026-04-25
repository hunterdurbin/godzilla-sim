extends CardEffect
## EBP04-046: Rodan (2004) - Battle Rank 4 (Blue)
## When this card is discarded from your hand by your opponent's effect you
## may play this card.
## <Awakening 6> This gains +3000 counter power.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["plays_from_discard", "boosts_cp"]


func on_discard_from_hand(ctx: EffectContext) -> void:
	# Only when discarded by opponent's effect (not own turn)
	if ctx.is_own_turn():
		return
	await ctx.effect_handler.play_from_discard(ctx.owner.player_id, ctx.card_data)


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if ctx.is_awakening(6):
		return 3000
	return 0
