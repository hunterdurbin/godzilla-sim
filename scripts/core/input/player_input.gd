class_name PlayerInput
extends RefCounted

## The engine's player-decision port. One method per decision the engine can
## ask a player to make. Engine code always `await`s these calls; GDScript
## resolves `await` on a non-coroutine return immediately, so synchronous
## implementations (this base class, ScriptedPlayerInput) and signal-awaiting
## ones (SignalPlayerInput) share the same call shape.
##
## The base implementations are the headless fallbacks that used to live
## behind the `X_requested.get_connections().is_empty()` checks in
## EffectHandler/ActionHandler: auto-pick the first valid option, auto-confirm.
##
## Decision methods take only the data needed to decide — state mutation
## (discarding the chosen cards, moving the monster, ...) stays with the
## caller.


## Drop any pending decision state at match teardown. Base is stateless.
func teardown() -> void:
	pass


## Choose one of `options` (parallel `prompt` text). Returns the 0-based index.
func choose_option(_player_id: int, options: Array[String], _prompt: String) -> int:
	return 0 if not options.is_empty() else -1


## Pick a card from `matching` (subset of `all_cards`, both display copies).
## Returns the chosen card dict, or {} to skip / when nothing matches.
func search_cards(_player_id: int, matching: Array[Dictionary], _all_cards: Array[Dictionary], _prompt: String, _allow_skip: bool) -> Dictionary:
	return matching[0] if not matching.is_empty() else {}


## Pick between min_count and max_count cards from `matching`. Returns the
## chosen cards, or [] to skip.
func select_cards(_player_id: int, matching: Array[Dictionary], _all_cards: Array[Dictionary], _prompt: String, min_count: int, _max_count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in range(mini(min_count, matching.size())):
		result.append(matching[i])
	return result


## Choose `count` hand indices to discard. `hand_size` is the current hand
## size (indices must be < hand_size). Default: discard from the back of hand.
func choose_hand_discards(_player_id: int, count: int, hand_size: int) -> Array[int]:
	var indices: Array[int] = []
	for i in range(mini(count, hand_size)):
		indices.append(hand_size - 1 - i)
	return indices


## Choose one of `valid_indices` in the player's hand. Returns the hand index,
## or -1 to skip.
func select_hand_card(_player_id: int, valid_indices: Array[int], _prompt: String, _allow_skip: bool) -> int:
	return valid_indices[0] if not valid_indices.is_empty() else -1


## Choose one of `valid_zones` (0-7) on target_player_id's board. Returns the
## zone index, or -1 to skip.
func select_zone(_player_id: int, _target_player_id: int, valid_zones: Array[int], _prompt: String, _allow_skip: bool) -> int:
	return valid_zones[0] if not valid_zones.is_empty() else -1


## Choose multiple zones (0-7) on target_player_id's board. In exact mode
## (up_to = false) the caller passes count already clamped to the number of
## valid zones and expects exactly that many; in up-to mode (up_to = true) any
## 0..count zones are acceptable and [] declines the effect entirely.
func select_zones(_player_id: int, _target_player_id: int, valid_zones: Array[int], count: int, _up_to: bool, _prompt: String) -> Array[int]:
	var result: Array[int] = []
	for i in range(mini(count, valid_zones.size())):
		result.append(valid_zones[i])
	return result


## Choose one of `valid_indices` strategy zones on target_player_id's board.
func select_strategy(_player_id: int, _target_player_id: int, valid_indices: Array[int], _prompt: String) -> int:
	return valid_indices[0] if not valid_indices.is_empty() else -1


## Reorder `cards` and optionally discard some.
## Returns {"keep": Array[Dictionary] (first = top of deck), "discard": Array[Dictionary]}.
func arrange_deck(_player_id: int, cards: Array[Dictionary], _prompt: String) -> Dictionary:
	return {"keep": cards, "discard": [] as Array[Dictionary]}


## Show `cards` to the player; returns once dismissed.
func acknowledge_reveal(_player_id: int, _cards: Array[Dictionary], _title: String) -> void:
	pass


## Choose a rank-up monster from `monsters` (the full monster deck).
## `valid_indices` are the playable entries. Returns the deck index.
func choose_rankup(_player_id: int, _monsters: Array[Dictionary], valid_indices: Array[int], _prompt: String) -> int:
	return valid_indices[0] if not valid_indices.is_empty() else -1


## Pause at a phase step until the player confirms. `setting` is the
## presentation-layer auto-skip settings key (the engine never interprets it).
func confirm_step(_player_id: int, _prompt: String, _setting: String) -> void:
	pass
