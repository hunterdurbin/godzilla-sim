extends CardEffect

## ESD05-005: Constructed Future - Strategy Rank 6 (Green)
## In order from lowest rank, <Destroy> 3 battle cards in your zones. If you
## <Destroy> 3, play 1 of the highest rank battle cards from your discard pile.
##
## Tested: Yes
## Known issues: None
## Edge cases: Fewer than 3 battle cards → all of them are destroyed and
##   nothing is played. A card that survives its destruction (replacement /
##   can't-be-destroyed) doesn't count toward the 3. Ties at a rank boundary
##   → the owner picks which tied card goes.
## Rules: None
## Interactions: Cards destroyed by this effect are already in the discard
##   pile when the highest-rank card is chosen, so they're eligible.
## Implementation notes: All 3 targets are chosen up front, then destroyed
##   as one batch (revenge triggers defer per 10.4.3). Rank = effective field
##   rank on the board, printed rank in the discard pile.

const DESTROY_COUNT := 3


func get_bot_tags() -> Array[String]:
	return ["plays_from_discard"]


func bot_can_fulfill_on_enter(owner: PlayerState, _opponent: PlayerState) -> bool:
	return owner.get_battle_card_zone_indices().size() >= DESTROY_COUNT


func on_enter(ctx: EffectContext) -> void:
	var targets: Array[int] = await _choose_targets(ctx)
	if targets.is_empty():
		return
	var destroyed: Array[Dictionary] = await ctx.effect_handler.destroy_zones(ctx.owner, targets)
	if destroyed.size() < DESTROY_COUNT:
		return

	var top_rank: int = -1
	for card in ctx.owner.discard_pile:
		if CardUtils.is_battle(card):
			top_rank = maxi(top_rank, int(card.get("rank", 0)))
	if top_rank < 0:
		return
	var found := await ctx.effect_handler.search_discard(
		ctx.owner.player_id,
		func(card: Dictionary) -> bool:
			return CardUtils.is_battle(card) and int(card.get("rank", 0)) == top_rank,
		tr("STR_EFF_ESD05_005_PLAY_PROMPT"),
		false)
	if found.is_empty():
		return
	await ctx.effect_handler.play_from_discard(ctx.owner.player_id, found)


func _choose_targets(ctx: EffectContext) -> Array[int]:
	## Up to DESTROY_COUNT of the owner's battle-card zones, lowest field rank
	## first. When a rank tier doesn't fit entirely, the owner picks from it.
	var remaining: Array[int] = ctx.owner.get_battle_card_zone_indices()
	var chosen: Array[int] = []
	while chosen.size() < DESTROY_COUNT and not remaining.is_empty():
		var low: int = _rank_at(ctx, remaining[0])
		for zi in remaining:
			low = mini(low, _rank_at(ctx, zi))
		var tier: Array[int] = []
		for zi in remaining:
			if _rank_at(ctx, zi) == low:
				tier.append(zi)
		var pick: int = tier[0]
		if tier.size() > DESTROY_COUNT - chosen.size():
			var answer: int = await ctx.effect_handler.select_zone_target(
				ctx.owner.player_id, ctx.owner.player_id, tier, tr("STR_EFF_ESD05_005_DESTROY_PROMPT"))
			if answer in tier:
				pick = answer
			chosen.append(pick)
			remaining.erase(pick)
		else:
			chosen.append_array(tier)
			for zi in tier:
				remaining.erase(zi)
	return chosen


func _rank_at(ctx: EffectContext, zone_idx: int) -> int:
	return ctx.field_rank(ctx.owner.get_zone_top_card(zone_idx), ctx.owner.player_id)
