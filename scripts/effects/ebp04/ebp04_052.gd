extends CardEffect
## EBP04-052: Mothra(imago)(1992) - Battle Rank 7 (Blue)
## When this card is discarded from your hand by your opponent’s effect, if your
## opponent’s monster card is in zones 4–8, you may play this card.
## Whenever your opponent’s effect causes you to discard cards from your hand, if this
## card is in zone 8, increase your monster card’s <Rage> by 2.
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


const TRIGGER_FILTERS = {
	"on_discard_from_hand": {"caused_by_opponent": true},
	"on_hand_card_discarded": {"own_turn": false},
}


func get_bot_tags() -> Array[String]:
	return ["plays_from_discard", "boosts_threat"]


func on_discard_from_hand(ctx: EffectContext) -> void:
	# Opponent's monster must be in zones 4-8
	if ctx.opponent.monster_zone < 4:
		return
	await ctx.effect_handler.play_from_discard_or_skip(
		ctx.owner.player_id, ctx.card_data,
		tr("STR_EFF_PLACE_DISCARD_FMT") % ctx.card_data.get("name", "card"))


func on_hand_card_discarded(ctx: EffectContext, _discarded_card: Dictionary) -> void:
	# Rage +2 when ANY hand card discarded by opponent + this is in area 8
	var my_zone: int = find_zone_of_card(ctx)
	if my_zone != 7: # Must be zone 8 (index 7)
		return

	await ctx.effect_handler.gain_rage(ctx.owner.player_id, 2, ctx.card_data.get("id", ""))
