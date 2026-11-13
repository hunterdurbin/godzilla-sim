extends CardEffect
## EBP04-T01: Godzilla Earth - Battle Rank 7 (Green)
## (Tokens cannot be added to the deck. They are banished when removed from
## zones.)
##
## Tested: Yes
## Known issues: None
## Edge cases: None
## Rules: The "<Destroy> both" link printed on EBP04-067 applies when the
##   token leaves its zone or moves — same standby timing (10.6.4, 10.4.3).
## Interactions: EBP04-067 — link logic lives there.
## Implementation notes: None

const _Earth = preload("res://scripts/effects/ebp04/ebp04_067.gd")


func on_leave_play(ctx: EffectContext, _zone_idx: int) -> void:
	await _Earth.destroy_linked_pair(ctx, _Earth.MAIN_ID)


func on_zone_changed(ctx: EffectContext, _from_zone: int, _to_zone: int) -> void:
	await _Earth.destroy_linked_pair(ctx, _Earth.MAIN_ID)


func area_change_still_applies(ctx: EffectContext) -> bool:
	return not _Earth.linked_pair_zones(ctx, _Earth.MAIN_ID).is_empty()
