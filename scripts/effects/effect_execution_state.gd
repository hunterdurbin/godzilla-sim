class_name EffectExecutionState
extends RefCounted

## Cross-cutting mutable state for effect execution, shared by reference
## between the EffectHandler facade, the StandbyResolver, and (in later
## phases) the trigger dispatcher and destruction engine.
##
## Tracks which card's effect is currently executing (drives decision
## highlighting and the caused_by_opponent filter gates) and the standby
## deferral queue (rule 10.4.3): while a resolution pass or an active effect
## is underway, newly triggered effects queue here instead of running inline.

## Player whose effect is currently executing (-1 = none).
var active_player_id: int = -1
## Card whose effect is currently executing ({} = none).
var active_card: Dictionary = {}

## True while a standby resolution pass is running.
var in_standby_resolution: bool = false
## Entries deferred during standby resolution / active effect execution.
var pending_standby_entries: Array = []

## Max destroyable rank for the in-flight zone-target prompt (bot filtering).
var pending_destroy_max_rank: int = -1


func set_active(player_id: int, card: Dictionary) -> void:
	active_player_id = player_id
	active_card = card


func clear_active() -> void:
	active_player_id = -1
	active_card = {}


func has_active_effect() -> bool:
	return not active_card.is_empty()


## True when new trigger entries must defer to the pending queue instead of
## resolving inline (10.4.3): either a standby pass is running, or an effect
## callback is actively executing.
func should_defer() -> bool:
	return in_standby_resolution or has_active_effect()
