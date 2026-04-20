extends CardEffect
# Biollante Plant Beast Form
# Play cost: may place Rank III monster from monster deck under Rank II Biollante.
# <Enter> Place [Tentacles] tokens in every adjacent area (max 3).


func get_bot_tags() -> Array[String]:
	return ["plays_other_cards"]


func on_enter(ctx: EffectContext) -> void:
	var monster_idx: int = ctx.owner.monster_zone - 1
	var adjacent := CardEffect.get_effect_play_adjacent_zones(ctx.owner, monster_idx)
	if adjacent.is_empty():
		return

	for zone_idx in adjacent:
		await ctx.effect_handler.create_token_in_zone(ctx.owner, "EBP02-T02", zone_idx)
