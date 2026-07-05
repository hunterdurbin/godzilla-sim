extends CardEffect
## EBP04-046: Rodan(2004) - Battle Rank 4 (Blue)
## When this card is discarded from your hand by your opponent’s effect, you may play
## this card.
## <Awakening 6> This card gains +3000 counter power. (Active if your monster card is in
## zone 6 or beyond.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


## CP modifier is placement-independent — safe to preview while in hand.
const HAND_CP_PREVIEW := true


const TRIGGER_FILTERS = {
	"on_discard_from_hand": {"caused_by_opponent": true},
}


func get_bot_tags() -> Array[String]:
	return ["plays_from_discard", "boosts_cp"]


func on_discard_from_hand(ctx: EffectContext) -> void:
	await ctx.effect_handler.play_from_discard_or_skip(
		ctx.owner.player_id, ctx.card_data,
		tr("STR_EFF_PLACE_DISCARD_FMT") % ctx.card_data.get("name", "card"))


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if ctx.is_awakening(6):
		return 3000
	return 0
