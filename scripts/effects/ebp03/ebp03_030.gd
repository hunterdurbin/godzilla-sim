extends CardEffect
# SHIRASAGI : AC-3 (Battle R2)
# Your <《Mechagodzilla》> battle cards in your zone 8 gain +3000 counter power.
# <Enter> You may move 1 other battle card in your zones to an unoccupied zone.
#
# Tested: Yes
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["boosts_cp", "zone_dependent"]


func get_field_cp_modifiers(ctx: EffectContext) -> Dictionary:
	var mods := {}
	var zone8_card := ctx.owner.get_zone_top_card(7) # zone 8 = index 7
	if not zone8_card.is_empty() and CardUtils.is_battle(zone8_card):
		if CardUtils.has_trait(zone8_card, CardEnums.CardTrait.MECHAGODZILLA):
			# Don't double-count if this card IS in zone 8
			var my_zone := find_zone_of_card(ctx)
			if my_zone != 7:
				mods[7] = 3000
	return mods


func on_enter(ctx: EffectContext) -> void:
	var my_id: String = ctx.card_data.get("id", "")
	var occupied: Array[int] = ctx.owner.get_zone_top_indices_matching(func(c: Dictionary) -> bool:
		return c.get("id", "") != my_id)
	if occupied.is_empty():
		return

	var source := await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, occupied,
		tr("STR_EFF_MOVE_BATTLE_OR_SKIP"), true)
	if source < 0:
		return

	var empty := ctx.owner.get_empty_zone_indices()
	if empty.is_empty():
		return

	var dest := await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, empty,
		tr("STR_EFF_MOVE_DEST_ZONE"))
	if dest < 0:
		return

	var stack: Array = ctx.owner.zones[source]
	ctx.owner.zones[source] = []
	ctx.owner.zones[dest] = stack
	ctx.owner.zones_changed.emit()
