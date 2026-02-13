extends CardEffect
# Multi-purpose Fighting System-3 R3
# <Enter> If 2+ battle cards in your zones, opponent discards to 4.
# If a battle card was discarded this way, +1 rage.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func on_enter(ctx: EffectContext) -> void:
	var battle_count := 0
	for i in range(8):
		if not ctx.owner.is_zone_empty(i):
			battle_count += 1
	if battle_count < 2:
		return

	# Track opponent hand before discard
	var hand_before: Array[Dictionary] = []
	for card in ctx.opponent.hand:
		hand_before.append(card)

	await ctx.effect_handler.discard_hand_to(ctx.opponent.player_id, 4)

	# Check if any battle card was discarded
	var battle_discarded := false
	for card in hand_before:
		if card not in ctx.opponent.hand:
			if card.get("card_type") == CardEnums.CardType.BATTLE:
				battle_discarded = true
				break

	if battle_discarded:
		var old_rage := ctx.owner.rage
		ctx.owner.rage += 1
		ctx.owner.rage_changed.emit(ctx.owner.rage)
		await ctx.effect_handler.trigger_rage_changed(ctx.owner.player_id, old_rage, ctx.owner.rage)
