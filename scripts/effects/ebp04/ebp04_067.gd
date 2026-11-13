extends CardEffect
## EBP04-067: Godzilla Earth - Battle Rank 7 (Green)
## This card can only be played in zone 8.
## <Enter> Play 1 “Godzilla Earth” token in your zone 3.
## If either this card or that token leave their zone or move, <Destroy> both of them.
##
## Tested: Yes
## Known issues: None
## Edge cases: Token zone blocked by the owner's monster → this card is
##   destroyed (the second clause). Both cards leaving in the same batch →
##   each link trigger finds nothing left and ceases to exist (10.6.3).
## Rules: The link is an area-changing trigger (10.6.4): it enters standby
##   (10.6.2) and resolves at the check timing AFTER the effect that moved or
##   removed the card (10.4.3) — e.g. Constructed Future finishes its
##   play-back first. It still resolves although the triggering card left
##   (10.6.7).
## Interactions: Shares the link logic with EBP04-T01 via the static helpers
##   below.
## Implementation notes: The pair is linked by per-copy ids stamped on both
##   card dicts ("link_partner"), so a second Godzilla Earth's token is never
##   taken for "that token". Pairs without the stamp (hand-built test states,
##   older saves) fall back to matching by base id.

const LINK_KEY := "link_partner"
const MAIN_ID := "EBP04-067"
const TOKEN_ID := "EBP04-T01"


func get_bot_tags() -> Array[String]:
	return ["plays_other_cards"]


func get_required_play_zones(_ctx: EffectContext) -> Array[int]:
	return [7] # Zone 8 only (index 7)


func on_enter(ctx: EffectContext) -> void:
	# Continuous link: if the token can't be placed in zone 3, destroy self
	# per the second clause. The engine refuses the play when the owner's
	# monster occupies zone 3 (5.11.1.1).
	ctx.card_data.erase(LINK_KEY)
	var placed: bool = await ctx.effect_handler.create_token_in_zone(ctx.owner, TOKEN_ID, 2)
	if placed:
		var token := ctx.owner.get_zone_top_card(2)
		token[LINK_KEY] = str(ctx.card_data.get("id", ""))
		ctx.card_data[LINK_KEY] = str(token.get("id", ""))
		return
	var my_zone: int = find_zone_of_card(ctx)
	if my_zone >= 0:
		await ctx.effect_handler.destroy_zones(ctx.owner, [my_zone])


func on_leave_play(ctx: EffectContext, _zone_idx: int) -> void:
	await destroy_linked_pair(ctx, TOKEN_ID)


func on_zone_changed(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	await destroy_linked_pair(ctx, TOKEN_ID)


func area_change_still_applies(ctx: EffectContext) -> bool:
	return not linked_pair_zones(ctx, TOKEN_ID).is_empty()


static func destroy_linked_pair(ctx: EffectContext, partner_base_id: String) -> void:
	## "<Destroy> both of them": whichever of the pair is still on the field,
	## in one batch.
	var zones := linked_pair_zones(ctx, partner_base_id)
	if not zones.is_empty():
		await ctx.effect_handler.destroy_zones(ctx.owner, zones)


static func linked_pair_zones(ctx: EffectContext, partner_base_id: String) -> Array[int]:
	## Zones (0-indexed) on the owner's board whose top card is this card or
	## its linked partner.
	var self_id: String = str(ctx.card_data.get("id", ""))
	var partner_id: String = str(ctx.card_data.get(LINK_KEY, ""))
	var out: Array[int] = []
	for i in range(8):
		var top := ctx.owner.get_zone_top_card(i)
		if top.is_empty():
			continue
		var top_id: String = str(top.get("id", ""))
		if top_id == self_id:
			out.append(i)
		elif partner_id != "":
			if top_id == partner_id:
				out.append(i)
		elif CardUtils.base_id(top) == partner_base_id:
			out.append(i)  # Unstamped pair: fall back to the base id.
	return out
