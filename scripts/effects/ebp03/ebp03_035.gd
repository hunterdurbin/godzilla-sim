extends CardEffect
# Satsuma (Battle R5)
# <Enter> If this card is in the same column as your opponent’s monster card, you may
# discard 1 strategy card from your hand. If you do, advance your monster card to zone
# 6.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["advances_self", "column_dependent_monster"]


func get_bot_max_advance_zone(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 6


func get_bot_advance_reliability(owner: PlayerState, _opponent: PlayerState) -> int:
	# Requires same column as opponent monster AND a strategy card in hand to discard.
	var has_strategy: bool = false
	for card in owner.hand:
		if CardUtils.is_strategy(card):
			has_strategy = true
			break
	if not has_strategy:
		return 0
	# Check if any zone aligns with opponent monster column and isn't blocked
	# by the bot's own monster occupying the only zone in that column
	var opp_monster_idx: int = _opponent.monster_zone - 1
	var own_monster_idx: int = owner.monster_zone - 1
	var can_align: bool = false
	for z in range(8):
		if z == own_monster_idx:
			continue
		if opp_monster_idx in get_opponent_column_zones(z):
			can_align = true
			break
	if not can_align:
		return 0
	return 90


func on_enter(ctx: EffectContext) -> void:
	var zone_idx := find_zone_of_card(ctx)
	if zone_idx < 0:
		return

	var opp_monster_idx: int = ctx.opponent.monster_zone - 1
	if opp_monster_idx not in get_opponent_column_zones(zone_idx):
		return

	if ctx.owner.monster_zone >= 6:
		return

	var selected := await ctx.effect_handler.select_hand_card(
		ctx.owner.player_id,
		func(card): return CardUtils.is_strategy(card),
		tr("STR_EFF_EBP03_035_PROMPT"),
		true
	)
	if selected.is_empty():
		return

	await ctx.effect_handler.advance_monster_to_zone(ctx.owner.player_id, 6)
