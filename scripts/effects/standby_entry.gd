class_name StandbyEntry
extends RefCounted

## One automatic ability waiting in standby (10.6.2) for CheckTiming to
## resolve it. Built only by TriggerDispatcher's _collect_* functions (and by
## tests); CheckTiming is the only reader.

## Owner of the ability (the player who plays it, 10.4.3.2 / 10.4.3.3).
var player_id: int
## Source card — drives the order-choice label and highlighting. It may have
## changed areas since; the ability still resolves (10.6.7).
var card: Dictionary
## The ability itself; awaited when the entry resolves.
var callback: Callable
## Optional gate re-checked just before the order prompt (10.6.3.2): returning
## false means the ability cannot be played and ceases to exist. Empty
## Callable = always applies. The only way an entry is dropped.
var still_applies: Callable
## Submission sequence number, stamped by CheckTiming.submit (-1 = not yet
## submitted). The order-choice prompt (10.4.3) lists a player's abilities in
## this order.
var seq: int = -1
## Non-empty on an ability that can be pending several times at once (a Rage
## increase of N triggers an increase watcher N times, Q381): the key names
## the (card, ability), so every pending copy of it shares the key, whichever
## increase triggered it. The order prompt lists a key once and resolves one
## copy per pick. Empty = this entry is its own ability.
var copy_key: String = ""


func _init(p_player_id: int, p_card: Dictionary, p_callback: Callable,
		p_still_applies: Callable = Callable()) -> void:
	player_id = p_player_id
	card = p_card
	callback = p_callback
	still_applies = p_still_applies


func applies() -> bool:
	## False when the still_applies gate reports the ability ceased (10.6.3).
	return not still_applies.is_valid() or bool(still_applies.call())
