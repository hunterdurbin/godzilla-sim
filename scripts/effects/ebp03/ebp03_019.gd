extends CardEffect

## EBP03-019: Mothra(larva)(1996) - Monster Rank 2 (Blue)
## When you successfully counter your opponent's monster card, if you have a card
## with <Base> in play, increase this card's Rage by 2.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_threat"]


func on_counter_success(ctx: EffectContext) -> void:
	if not _has_base_in_play(ctx):
		return
	var old_rage: int = ctx.owner.rage
	ctx.owner.rage += 2
	ctx.owner.rage_changed.emit(ctx.owner.rage)
	await ctx.effect_handler.trigger_rage_changed(ctx.owner.player_id, old_rage, ctx.owner.rage)


func _has_base_in_play(ctx: EffectContext) -> bool:
	for sz_card in ctx.owner.strategy_zones:
		if not sz_card.is_empty() and sz_card.get("is_base", false):
			return true
	return false
