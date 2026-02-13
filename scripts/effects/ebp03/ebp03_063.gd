extends CardEffect

## EBP03-063: King Ghidorah(1998) - Battle Rank 6 (Green)
## <Your Turn> <Awakening4> When your monster card is played, you may play this card
## from your discard pile.
##
## Tested: No
## Known issues: None
## Edge cases: None
## Rules: None
## Interactions: None
## Implementation notes: None


func can_play_from_discard_on_monster_played(ctx: EffectContext) -> bool:
	# Only on your turn
	if ctx.game_state.current_player_id != ctx.owner.player_id:
		return false
	# Awakening4: monster in zone 4+
	if ctx.owner.monster_zone < 4:
		return false
	return true
