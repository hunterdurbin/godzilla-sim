extends CardEffect

## EBP03-023: Armor Mothra - Monster Rank 4 (Blue)
## <Enter> Evolve all of your Mothra battle cards with Evolution.
## When you successfully counter your opponent's monster card, if you have a card
## with <Base> in play, retreat your opponent's monster card back to zone 1.


func on_enter(ctx: EffectContext) -> void:
	# Evolve all Mothra cards with Evolution
	for i in range(8):
		var zone_card := ctx.owner.get_zone_top_card(i)
		if zone_card.is_empty():
			continue
		if zone_card.get("evolution_rank", -1) < 0:
			continue
		if CardEnums.CardTrait.MOTHRA not in zone_card.get("traits", []):
			continue
		await ctx.effect_handler.perform_evolution(ctx.owner.player_id, i)


func on_counter_success(ctx: EffectContext) -> void:
	if not _has_base_in_play(ctx):
		return
	# Retreat opponent's monster to zone 1
	if ctx.opponent.monster_zone > 1:
		var old_zone: int = ctx.opponent.monster_zone
		ctx.opponent.monster_zone = 1
		ctx.opponent.monster_changed.emit()


func _has_base_in_play(ctx: EffectContext) -> bool:
	for sz_card in ctx.owner.strategy_zones:
		if not sz_card.is_empty() and sz_card.get("is_base", false):
			return true
	return false
