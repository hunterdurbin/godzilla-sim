extends CardEffect
## EBP04-052: Mothra Imago (1992) - Battle Rank 7 (Blue)
## When this card is discarded from your hand by your opponent's effect and
## their monster card is in zones 4-8 you may play this card.
## Any time you discard cards from your hand by your opponent's effects, and
## this is in area 8, increase your <Rage> by 2.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["plays_from_discard", "boosts_threat"]


func on_discard_from_hand(ctx: EffectContext) -> void:
	# Only when discarded by opponent's effect
	if ctx.is_own_turn():
		return

	if ctx.opponent.is_awakening(4):
		await ctx.effect_handler.play_from_discard(ctx.owner.player_id, ctx.card_data)


func on_hand_card_discarded(ctx: EffectContext, discarded_card: Dictionary) -> void:
	# Rage +2 when ANY hand card discarded by opponent + this is in area 8
	if ctx.is_own_turn():
		return

	var my_zone: int = find_zone_of_card(ctx)
	if my_zone != 7:  # Must be zone 8 (index 7)
		return

	await ctx.effect_handler.gain_rage(ctx.owner.player_id, 2, ctx.card_data.get("id", ""))
