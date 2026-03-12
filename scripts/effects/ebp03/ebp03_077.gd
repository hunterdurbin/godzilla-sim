extends CardEffect
# Rebirth of Mothra 3 (Strategy R4)
# Choose one:
# - Return 1 R2 or lower monster card from discard to hand.
# - If 5+ cards under your monster, return 1 monster card from discard to hand.
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["draws_cards"]


func on_enter(ctx: EffectContext) -> void:
	var has_low_rank_monster := false
	for card in ctx.owner.discard_pile:
		if card.get("card_type") == CardEnums.CardType.MONSTER and card.get("rank", 0) <= 2:
			has_low_rank_monster = true
			break

	var has_five_under := ctx.owner.monster_stack.size() >= 5
	var has_any_monster := false
	if has_five_under:
		for card in ctx.owner.discard_pile:
			if card.get("card_type") == CardEnums.CardType.MONSTER:
				has_any_monster = true
				break

	if not has_low_rank_monster and not (has_five_under and has_any_monster):
		return

	# Build options
	var options: Array[String] = []
	var option_ids: Array[String] = []
	if has_low_rank_monster:
		options.append("Return R2 or lower monster")
		option_ids.append("low_rank")
	if has_five_under and has_any_monster:
		options.append("Return any monster (5+ under)")
		option_ids.append("any_monster")

	if options.size() == 1:
		# Only one valid option
		if option_ids[0] == "low_rank":
			await _return_low_rank_monster(ctx)
		else:
			await _return_any_monster(ctx)
		return

	var chosen_idx := await ctx.effect_handler.select_choice(
		ctx.owner.player_id, options, "Choose an effect:")
	var chosen_id: String = option_ids[chosen_idx] if chosen_idx >= 0 and chosen_idx < option_ids.size() else ""

	if chosen_id == "low_rank":
		await _return_low_rank_monster(ctx)
	elif chosen_id == "any_monster":
		await _return_any_monster(ctx)


func _return_low_rank_monster(ctx: EffectContext) -> void:
	var selected := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card): return card.get("card_type") == CardEnums.CardType.MONSTER and card.get("rank", 0) <= 2,
		"Return a rank 2 or lower monster from discard to hand:"
	)
	if not selected.is_empty():
		ctx.owner.hand.append(selected)
		ctx.owner.hand_changed.emit()


func _return_any_monster(ctx: EffectContext) -> void:
	var selected := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card): return card.get("card_type") == CardEnums.CardType.MONSTER,
		"Return a monster from discard to hand:"
	)
	if not selected.is_empty():
		ctx.owner.hand.append(selected)
		ctx.owner.hand_changed.emit()
