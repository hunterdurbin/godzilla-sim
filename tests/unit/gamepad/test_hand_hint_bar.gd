extends GdUnitTestSuite

## HandHintBar.compute_hint_actions — the pure decision core behind the
## gamepad hand-hint cluster: which of play/rage/invade a hovered hand card
## earns, given the playable-index lists and the action-button enabled map.

const MONSTER := CardEnums.CardType.MONSTER
const BATTLE := CardEnums.CardType.BATTLE
const STRATEGY := CardEnums.CardType.STRATEGY


func _all_enabled() -> Dictionary:
	return {
		CardEnums.ActionType.PLAY_BATTLE: true,
		CardEnums.ActionType.PLAY_STRATEGY: true,
		CardEnums.ActionType.PLAY_MONSTER: true,
		CardEnums.ActionType.GAIN_RAGE: true,
		CardEnums.ActionType.INVADE: true,
	}


func test_monster_playable_and_rageable() -> void:
	var actions := HandHintBar.compute_hint_actions(MONSTER, 2,
			{"monster": [2], "rage": [1, 2], "invade": []}, _all_enabled())
	assert_array(actions).contains_exactly([
		CardEnums.ActionType.PLAY_MONSTER, CardEnums.ActionType.GAIN_RAGE])


func test_battle_card_only_in_invade_list() -> void:
	var actions := HandHintBar.compute_hint_actions(BATTLE, 0,
			{"battle": [], "rage": [], "invade": [0]}, _all_enabled())
	assert_array(actions).contains_exactly([CardEnums.ActionType.INVADE])


func test_strategy_card_playable() -> void:
	var actions := HandHintBar.compute_hint_actions(STRATEGY, 3,
			{"strategy": [1, 3], "rage": [], "invade": []}, _all_enabled())
	assert_array(actions).contains_exactly([CardEnums.ActionType.PLAY_STRATEGY])


func test_disabled_button_suppresses_action() -> void:
	var enabled := _all_enabled()
	enabled[CardEnums.ActionType.GAIN_RAGE] = false
	var actions := HandHintBar.compute_hint_actions(MONSTER, 0,
			{"monster": [0], "rage": [0], "invade": []}, enabled)
	assert_array(actions).contains_exactly([CardEnums.ActionType.PLAY_MONSTER])


func test_unknown_logical_index_yields_nothing() -> void:
	var actions := HandHintBar.compute_hint_actions(MONSTER, -1,
			{"monster": [0], "rage": [0], "invade": [0]}, _all_enabled())
	assert_array(actions).is_empty()


func test_list_membership_miss_yields_nothing() -> void:
	var actions := HandHintBar.compute_hint_actions(BATTLE, 4,
			{"battle": [0, 1], "rage": [], "invade": [2]}, _all_enabled())
	assert_array(actions).is_empty()


func test_missing_lists_and_enabled_default_closed() -> void:
	assert_array(HandHintBar.compute_hint_actions(MONSTER, 0, {}, {})).is_empty()


func test_untyped_card_can_still_rage_or_invade() -> void:
	# Defensive: card_type -1 earns no play row but list membership still counts.
	var actions := HandHintBar.compute_hint_actions(-1, 1,
			{"rage": [1], "invade": [1]}, _all_enabled())
	assert_array(actions).contains_exactly([
		CardEnums.ActionType.GAIN_RAGE, CardEnums.ActionType.INVADE])
