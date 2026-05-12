extends CardEffect

## EBP03-015: Godzilla(2002) - Monster Rank 2 (Blue)
## Whenever you discard a battle card from your hand, reduce your opponent’s <Rage> by
## 1.
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
	return ["weakens_opponent"]


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS]


func on_hand_card_discarded(ctx: EffectContext, _discarded_card: Dictionary) -> void:
	await ctx.effect_handler.reduce_rage(ctx.opponent.player_id, 1)
