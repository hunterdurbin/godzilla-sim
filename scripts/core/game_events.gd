class_name GameEvents
extends RefCounted

## Gameplay notification bus: the logic layer emits, presentation / sync /
## sfx connect. One instance per session (created in TurnManager.setup,
## exposed as `turn_manager.events` and `GameSession.events`).
##
## These are pure notifications — no engine code awaits them and no game
## state changes in response. PlayerState's fine-grained change signals
## (hand_changed, zones_changed, ...) remain the state-diff layer.

# Bus signals: emitted by the logic layer via `events.<signal>.emit(...)`,
# never from this class — silence the per-class unused_signal analysis.
@warning_ignore_start("unused_signal")
signal battle_card_played(player_id: int, card: Dictionary, zone_index: int)
signal strategy_card_played(player_id: int, card: Dictionary, strategy_index: int)
signal monster_advanced(player_id: int, from_zone: int, to_zone: int)
signal rage_gained(player_id: int, new_rage: int)
signal card_discarded(player_id: int, card: Dictionary)
signal monster_played(player_id: int, old_monster: Dictionary, new_monster: Dictionary)
signal monster_countered(player_id: int, old_monster: Dictionary, new_monster: Dictionary)
signal battle_card_crushed(player_id: int, zone_index: int, card: Dictionary)
signal cards_drawn(player_id: int, count: int)
signal strategy_cleared(player_id: int, cards: Array)
signal counter_failed(player_id: int, total_cp: int, threat: int, rage_threat: int, effect_threat: int)
signal counter_succeeded(player_id: int, total_cp: int, threat: int, rage_threat: int, effect_threat: int)
signal counter_immunity_triggered(player_id: int, total_cp: int, threshold: int)
signal counter_prevented(player_id: int)
signal play_cancelled(player_id: int)
## Pending standby-effect stack snapshot (see StandbyResolver._publish_stack).
## Rows: { player_id, base_id, label, status: "resolving"|"pending", location }.
## Emitted with [] when the stack drains.
signal effect_stack_changed(stack: Array)
