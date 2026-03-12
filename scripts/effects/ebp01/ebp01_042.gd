extends CardEffect

## EBP01-042: Godzilla(2000) - Monster Rank 3 (Blue)
## <Enter> If you have 5 or more monster cards in your discard pile, you may discard
## 1 card from your hand to reduce your opponent's <Rage> by 1.
## If you have 5 or more monster cards in your discard pile, this card gains
## +10,000 threat level.
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
	if ctx.effect_handler.count_monsters_in_discard(ctx.owner) < 5:
		return
	if ctx.opponent.rage <= 0:
		return

	var discarded := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(_card: Dictionary) -> bool: return true,
		"Discard a card to reduce opponent's Rage by 1:",
		true # allow_skip
	)
	if not discarded.is_empty() and ctx.opponent.rage > 0:
		ctx.opponent.rage -= 1
		ctx.opponent.rage_changed.emit(ctx.opponent.rage)


func get_threat_level_modifier(ctx: EffectContext) -> int:
	if ctx.effect_handler.count_monsters_in_discard(ctx.owner) >= 5:
		return 10000
	return 0
