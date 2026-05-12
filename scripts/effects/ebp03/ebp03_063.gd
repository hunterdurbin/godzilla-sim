extends CardEffect

## EBP03-063: King Ghidorah(1998) - Battle Rank 6 (Green)
## <Your Turn> <Awakening4> When your monster card is played, you may play this card
## from your discard pile. (Active if your monster card is in zone 4 or beyond.)
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["plays_from_discard"]


func is_discard_play_optional() -> bool:
	return true


func can_play_from_discard_on_monster_played(ctx: EffectContext) -> bool:
	# Only on your turn
	if ctx.is_opponent_turn():
		return false
	# Awakening4: monster in zone 4+
	if not ctx.is_awakening(4):
		return false
	return true
