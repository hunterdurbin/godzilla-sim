extends CardEffect

## EBP03-028: Thousand-Year Dragon King Ghidorah - Monster Rank 4 (Green)
## <Your Turn> If there are 5 or more cards under this card, reduce the rank of all
## battle cards in your opponent’s zones by 3.
## <Opponent’s Turn> At the beginning of the counter phase, you may place 3 monster
## cards from your discard pile under this card. If you do, <Destroy> all rank 5 or
## lower battle cards in your opponent’s zones 1–5.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_phase_start": {"phase": CardEnums.GamePhase.COUNTER, "own_turn": false},
}


func get_bot_tags() -> Array[String]:
	return ["weakens_opponent", "destroys_zone"]


func get_bot_destroy_max_rank(_owner: PlayerState, _opponent: PlayerState) -> int:
	return 5


func bot_can_fulfill_on_phase_start(owner: PlayerState, _opponent: PlayerState, _effect_handler = null) -> bool:
	var monster_count := 0
	for card in owner.discard_pile:
		if CardUtils.is_monster(card):
			monster_count += 1
			if monster_count >= 3:
				return true
	return false


func get_effect_categories() -> Array[CardEnums.EffectCategory]:
	return [CardEnums.EffectCategory.CONTINUOUS, CardEnums.EffectCategory.ACTIVATED]


func get_opponent_field_rank_modifier(ctx: EffectContext) -> int:
	if ctx.is_opponent_turn():
		return 0
	if not ctx.has_monster_stack(5):
		return 0
	return -3


func on_phase_start(ctx: EffectContext, _phase: CardEnums.GamePhase) -> void:
	# Place exactly 3 monster cards from discard under this card (or skip entirely)
	var monsters: Array[Dictionary] = []
	for card in ctx.owner.discard_pile:
		if CardUtils.is_monster(card):
			monsters.append(card)

	if monsters.size() < 3:
		return

	var selected: Array[Dictionary] = await ctx.effect_handler.select_cards_from_pool(
		ctx.owner.player_id, monsters, ctx.owner.discard_pile.duplicate(),
		tr("STR_EFF_EBP03_028_SELECT"), 3)

	if selected.is_empty():
		return

	# Remove selected cards from discard pile
	for card in selected:
		var card_id: String = card.get("id", "")
		for i in range(ctx.owner.discard_pile.size()):
			if ctx.owner.discard_pile[i].get("id") == card_id:
				ctx.owner.discard_pile.remove_at(i)
				break

	# Place under monster
	for card in selected:
		ctx.owner.monster_stack.append(card)

	ctx.owner.discard_changed.emit()
	ctx.owner.monster_changed.emit()

	# Destroy all R5 or lower battle cards in opponent's zones 1-5 (indices 0-4)
	var zones_to_destroy: Array[int] = []
	for i in range(5):
		var zone_card := ctx.opponent.get_zone_top_card(i)
		if not zone_card.is_empty() and ctx.field_rank(zone_card, ctx.opponent.player_id) <= 5:
			zones_to_destroy.append(i)

	if not zones_to_destroy.is_empty():
		await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)
