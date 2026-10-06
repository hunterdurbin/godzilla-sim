extends CardEffect

## ESD03-008: Humanity's Crime and Punishment - Strategy Rank 7 (Red)
## If your monster card is rank III or higher, each player chooses 1 battle
## card in their zones, then <Destroy> all other battle cards. (You declare
## which of your battle cards remains first.)
## If your monster card has 3 or more <Rage>, your opponent discards cards
## until they have 2 cards remaining in their hand.
##
## Tested: Yes
## Known issues: None
## Edge cases: A player with 0 or 1 battle cards isn't prompted (nothing to
##   choose); a lone kept card is still announced.
## Rules: None
## Interactions: None
## Implementation notes: Owner picks first, then the opponent (routed to the
##   opponent's input — UI/RPC/bot). Each pick is made public via
##   ctx.announce_zone_choice (log + zone highlight + reveal to the other
##   player) before the next pick. Both picks happen before any destruction.


func get_bot_tags() -> Array[String]:
	return ["destroys_zone", "disrupts_hand"]


func bot_can_fulfill_on_enter(owner: PlayerState, opponent: PlayerState) -> bool:
	return (owner.get_monster_rank() >= 3 and opponent.get_battle_card_zone_indices().size() >= 2) \
		or (owner.rage >= 3 and opponent.hand.size() > 2)


func on_enter(ctx: EffectContext) -> void:
	if ctx.owner.get_monster_rank() >= 3:
		var own_kept: int = await _choose_kept_zone(ctx, ctx.owner)
		var opp_kept: int = await _choose_kept_zone(ctx, ctx.opponent)
		await ctx.effect_handler.destroy_zones(ctx.owner, _zones_except(ctx.owner, own_kept))
		await ctx.effect_handler.destroy_zones(ctx.opponent, _zones_except(ctx.opponent, opp_kept))

	if ctx.owner.rage >= 3:
		await ctx.effect_handler.discard_hand_to(ctx.opponent.player_id, 2)


func _choose_kept_zone(ctx: EffectContext, player: PlayerState) -> int:
	## The zone `player` keeps (-1 when they have no battle cards).
	## The choice is announced to the other player before the next pick.
	var occupied := player.get_battle_card_zone_indices()
	if occupied.is_empty():
		return -1
	var kept: int = occupied[0]
	if occupied.size() > 1:
		var chosen: int = await ctx.effect_handler.select_zone_target(
			player.player_id, player.player_id, occupied, tr("STR_EFF_ESD03_008_KEEP_PROMPT"))
		# Defensive: an invalid answer still keeps exactly one card.
		if chosen in occupied:
			kept = chosen
	await ctx.announce_zone_choice(player, kept,
		tr("STR_EFF_ESD03_008_KEPT_FMT") % [GameLog.player_name(player.player_id), kept + 1])
	return kept


func _zones_except(player: PlayerState, kept: int) -> Array[int]:
	var out: Array[int] = []
	for zi in player.get_battle_card_zone_indices():
		if zi != kept:
			out.append(zi)
	return out
