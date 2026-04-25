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


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	for card in owner.discard_pile:
		if CardUtils.is_monster(card) and CardUtils.rank_at_most(card, 2):
			return true
	if owner.has_monster_stack(5):
		for card in owner.discard_pile:
			if CardUtils.is_monster(card):
				return true
	return false


func on_enter(ctx: EffectContext) -> void:
	var has_low_rank_monster := false
	for card in ctx.owner.discard_pile:
		if CardUtils.is_monster(card) and CardUtils.rank_at_most(card, 2):
			has_low_rank_monster = true
			break

	var has_five_under := ctx.has_monster_stack(5)
	var has_any_monster := false
	if has_five_under:
		for card in ctx.owner.discard_pile:
			if CardUtils.is_monster(card):
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
		ctx.owner.player_id, options, tr("STR_EFF_CHOOSE_EFFECT"))
	var chosen_id: String = option_ids[chosen_idx] if chosen_idx >= 0 and chosen_idx < option_ids.size() else ""

	if chosen_id == "low_rank":
		await _return_low_rank_monster(ctx)
	elif chosen_id == "any_monster":
		await _return_any_monster(ctx)


func _return_low_rank_monster(ctx: EffectContext) -> void:
	var selected := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card): return CardUtils.is_monster(card) and CardUtils.rank_at_most(card, 2),
		tr("STR_EFF_EBP03_077_PROMPT_A")
	)
	if not selected.is_empty():
		ctx.owner.hand.append(selected)
		ctx.owner.hand_changed.emit()


func _return_any_monster(ctx: EffectContext) -> void:
	var selected := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card): return CardUtils.is_monster(card),
		tr("STR_EFF_EBP03_077_PROMPT_B")
	)
	if not selected.is_empty():
		ctx.owner.hand.append(selected)
		ctx.owner.hand_changed.emit()
