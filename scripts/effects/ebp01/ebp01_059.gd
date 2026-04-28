extends CardEffect

## EBP01-059: Fire Rodan - Battle Rank 7 (Blue)
## When this card is discarded from your hand by your opponent's effect, and their
## monster card is in zones 4-8, you may play this card.
## If this card is in zone 8, this card gains +3000 counter power.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: Uses caused_by_opponent filter + play_from_discard_or_skip


const TRIGGER_FILTERS = {
	"on_discard_from_hand": {"caused_by_opponent": true},
}


func get_bot_tags() -> Array[String]:
	return ["plays_from_discard", "boosts_cp", "zone_dependent"]


func get_bot_preferred_zones() -> Array[int]:
	return [7]  # zone 8 (0-indexed) — +3000 CP in zone 8


func get_counter_power_modifier(ctx: EffectContext) -> int:
	if find_zone_of_card(ctx) == 7:
		return 3000
	return 0


func on_discard_from_hand(ctx: EffectContext) -> void:
	# Opponent's monster must be in zones 4-8
	if ctx.opponent.monster_zone < 4:
		return
	await ctx.effect_handler.play_from_discard_or_skip(
		ctx.owner.player_id, ctx.card_data,
		tr("STR_EFF_PLACE_DISCARD_FMT") % ctx.card_data.get("name", "card"))
