extends CardEffect
# Megalon and Gigan: Villain Tag Team (Strategy R5)
# If there are 3 or more battle cards in your opponent’s zones, 
# <Destroy> 1 battle card from the rightmost and 1 from the leftmost position from among them (from your perspective).
#
# Tested: No
# Known issues: None
# Edge cases: None
# Rules: None
# Interactions: None
# Implementation notes: None


func get_bot_tags() -> Array[String]:
	return ["destroys_zone"]


func bot_can_fulfill_on_enter(_owner: PlayerState, opponent: PlayerState) -> bool:
	var count: int = 0
	for i in range(8):
		if opponent.zone_has_battle_card(i):
			count += 1
			if count >= 3:
				return true
	return false


func on_enter(ctx: EffectContext) -> void:
	# Column layout from left to right (your perspective looking at opponent's board):
	# Col 1: zones 5/6, Col 2: zones 4/7, Col 3: zones 3/8, Col 4: zone 2, Col 5: zone 1
	const COLUMNS: Array = [[4, 5], [3, 6], [2, 7], [1], [0]]

	# Find columns that have battle cards, preserving left-to-right order
	var occupied_columns: Array = [] # Array of {col_idx, zones: Array[int]}
	var total_battle_cards: int = 0
	for col in COLUMNS:
		var col_zones: Array[int] = []
		for zone_idx in col:
			if ctx.opponent.zone_has_battle_card(zone_idx):
				col_zones.append(zone_idx)
		if not col_zones.is_empty():
			occupied_columns.append(col_zones)
			total_battle_cards += col_zones.size()

	if total_battle_cards < 3:
		return

	var leftmost_zones: Array[int] = occupied_columns[0]
	var rightmost_zones: Array[int] = occupied_columns[occupied_columns.size() - 1]

	# Collect targets: choose 1 from leftmost, 1 from rightmost, then destroy together
	var zones_to_destroy: Array[int] = []

	var right_chosen := await ctx.effect_handler.select_zone_target(
		ctx.owner.player_id, ctx.opponent.player_id, rightmost_zones,
		"Choose a battle card to destroy from the rightmost column:")
	if right_chosen >= 0:
		zones_to_destroy.append(right_chosen)

	if rightmost_zones != leftmost_zones:
		var left_chosen := await ctx.effect_handler.select_zone_target(
			ctx.owner.player_id, ctx.opponent.player_id, leftmost_zones,
			"Choose a battle card to destroy from the leftmost column:")
		if left_chosen >= 0:
			zones_to_destroy.append(left_chosen)

	if not zones_to_destroy.is_empty():
		await ctx.effect_handler.destroy_zones(ctx.opponent, zones_to_destroy)
