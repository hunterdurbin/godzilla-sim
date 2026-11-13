class_name StandbyEntry
extends RefCounted

## One automatic ability waiting in standby (10.6.2) for CheckTiming to
## resolve it. Built only by TriggerDispatcher's collect_* functions (and by
## tests); CheckTiming is the only reader.

## Owner of the ability (the player who plays it, 10.4.3.2 / 10.4.3.3).
var player_id: int
## Source card — drives the order-choice label, highlighting and the
## still-in-play filter.
var card: Dictionary
## The ability itself; awaited when the entry resolves.
var callback: Callable
## Optional gate re-checked just before the order prompt (10.6.3): returning
## false makes the ability cease to exist. Empty Callable = always applies.
var still_applies: Callable
## True for abilities whose card has already left the field (crush,
## <Revenge>, discard-from-hand, leave-play): bypasses the still-in-play
## filter of CheckTiming.submit_deferred.
var skip_active_check: bool


func _init(p_player_id: int, p_card: Dictionary, p_callback: Callable,
		p_still_applies: Callable = Callable(), p_skip_active_check: bool = false) -> void:
	player_id = p_player_id
	card = p_card
	callback = p_callback
	still_applies = p_still_applies
	skip_active_check = p_skip_active_check


static func off_field(p_player_id: int, p_card: Dictionary, p_callback: Callable,
		p_still_applies: Callable = Callable()) -> StandbyEntry:
	## Entry for an ability whose card has already left the field (crush,
	## <Revenge>, discard-from-hand, leave-play): skips the still-in-play filter.
	return StandbyEntry.new(p_player_id, p_card, p_callback, p_still_applies, true)


func applies() -> bool:
	## False when the still_applies gate reports the ability ceased (10.6.3).
	return not still_applies.is_valid() or bool(still_applies.call())
