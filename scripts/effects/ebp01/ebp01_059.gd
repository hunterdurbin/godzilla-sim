extends CardEffect

## EBP01-059: Fire Rodan - Battle Rank 7 (Blue)
## When this card is discarded from your hand by your opponent's effect, and their
## monster card is in zones 4-8, you may play this card.
## If this card is in zone 8, this card gains +3000 counter power.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: Uses trigger_discard_from_hand + play_from_discard


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if find_zone_of_card(ctx) == 7:
		return 3000
	return 0


func on_discard_from_hand(ctx: EffectContext) -> void:
	# Check if opponent's monster is in zones 4-8
	if ctx.opponent.monster_zone < 4:
		return

	# Play self from discard
	await ctx.effect_handler.play_from_discard(ctx.owner.player_id, ctx.card_data)
