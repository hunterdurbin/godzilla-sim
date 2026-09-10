extends CardEffect

## EPR-020: Godzilla(2003) - Monster Rank 3 (Blue)
## Whenever you discard a battle card from your hand, reduce your opponent's
## <Rage> by 1.
## <Your Turn> When your opponent's <Rage> becomes 0, increase this card's
## <Rage> by 2. (Does not activate if their <Rage> was already 0.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: The "already 0" clause is covered by the "decrease"
## direction filter (old > new) plus the new == 0 check in the body.


const TRIGGER_FILTERS = {
	"on_hand_card_discarded": {"card_type": "battle"},
	"on_opponent_rage_changed": {"direction": "decrease", "own_turn": true},
}


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent", "boosts_threat"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func on_hand_card_discarded(ctx: EffectContext, _discarded_card: Dictionary) -> void:
	await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 1)


func on_opponent_rage_changed(ctx: EffectContext, _old_rage: int, new_rage: int) -> void:
	if new_rage != 0:
		return
	await ctx.effect_handler.gain_rage(ctx.owner.player_id, 2, ctx.card_data.get("id", ""))
