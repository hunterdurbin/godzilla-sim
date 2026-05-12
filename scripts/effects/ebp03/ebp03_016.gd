extends CardEffect

## EBP03-016: Godzilla(2003) - Monster Rank 3 (Blue)
## Whenever you discard a battle card from your hand, reduce your opponent’s <Rage> by
## 1. If your opponent’s <Rage> is 0, increase this card’s <Rage> by 1 instead.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_hand_card_discarded": {"card_type": "battle"},
}


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent", "boosts_threat"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func on_hand_card_discarded(ctx: EffectContext, _discarded_card: Dictionary) -> void:
	if ctx.opponent_has_rage():
		await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 1)
	else:
		await ctx.effect_handler.gain_rage(ctx.owner.player_id, 1, ctx.card_data.get("id", ""))
