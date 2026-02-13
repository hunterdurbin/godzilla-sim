extends CardEffect
# SHIRASAGI : AC-3 (Battle R2)
# Your Mechagodzilla battle cards in zone 8 get +3000 CP.
# <Enter> Move 1 other battle card in your zones to an unoccupied zone.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_field_cp_modifiers(ctx: EffectContext) -> Dictionary:
	var mods := {}
	var zone8_card := ctx.owner.get_zone_top_card(7)  # zone 8 = index 7
	if not zone8_card.is_empty() and zone8_card.get("card_type") == CardEnums.CardType.BATTLE:
		if CardEnums.CardTrait.MECHAGODZILLA in zone8_card.get("traits", []):
			# Don't double-count if this card IS in zone 8
			var my_zone := find_zone_of_card(ctx)
			if my_zone != 7:
				mods[7] = 3000
	return mods


func on_enter(ctx: EffectContext) -> void:
	var my_id: String = ctx.card_data.get("id", "")
	var occupied: Array[int] = []
	for i in range(8):
		var top := ctx.owner.get_zone_top_card(i)
		if not top.is_empty() and top.get("id", "") != my_id:
			occupied.append(i)
	if occupied.is_empty():
		return

	var source := await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, occupied,
		"Choose a battle card to move (or skip):", true)
	if source < 0:
		return

	var empty := ctx.owner.get_empty_zone_indices()
	if empty.is_empty():
		return

	var dest := await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.owner.player_id, empty,
		"Choose destination zone:")
	if dest < 0:
		return

	var stack: Array = ctx.owner.zones[source]
	ctx.owner.zones[source] = []
	ctx.owner.zones[dest] = stack
	ctx.owner.zones_changed.emit()
