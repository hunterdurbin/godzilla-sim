class_name BoardSfx
extends Node

## Sound concern for the game board. Subscribes itself to TurnManager /
## ActionHandler / EffectHandler signals and plays the matching SFX —
## game_board.gd handlers keep only their visual/log/broadcast concerns.
##
## Owns the _pending_sound_events buffer: on the multiplayer host every
## played sound is also queued so MultiplayerSync can piggyback it on the
## next state broadcast (the client plays envelope sounds directly).
##
## Binds on GameSession.session_started, which fires on initial host start
## AND on every rematch (start_host_session), so rebinding is automatic.
## All connects are idempotent — double-bind cannot double-play.

var _board: Node
var _session: GameSession

# Sound events buffered for the client (drained by MultiplayerSync at
# broadcast time, via the board's forwarding property during extraction).
var _pending_sound_events: PackedStringArray = []


func _ready() -> void:
	_board = get_parent()
	var session_node := _board.get_node_or_null("GameSession")
	if session_node == null:
		push_error("[BoardSfx] No GameSession sibling — sounds will not bind.")
		return
	_session = session_node
	_session.session_started.connect(_bind)


## Play a sound locally; on the multiplayer host also buffer it for the
## next state broadcast to the client.
func play(sound_name: String) -> void:
	SfxManager.play(sound_name)
	if _board.is_multiplayer_game and NetworkManager.is_host():
		_pending_sound_events.append(sound_name)


func _bind() -> void:
	var tm: TurnManager = _session.turn_manager
	if tm == null:
		return # Client peer: sounds arrive via the state broadcast envelope
	var ah: ActionHandler = tm.action_handler
	var eh: EffectHandler = ah.effect_handler
	_connect_once(tm.turn_started, _on_turn_started)
	_connect_once(ah.cards_drawn, _on_cards_drawn)
	_connect_once(ah.card_discarded, _on_card_discarded)
	_connect_once(ah.rage_gained, _on_rage_gained)
	_connect_once(ah.strategy_card_played, _on_strategy_card_played)
	_connect_once(ah.battle_card_played, _on_battle_card_played)
	_connect_once(ah.monster_advanced, _on_monster_advanced)
	_connect_once(ah.battle_card_crushed, _on_battle_card_crushed)
	_connect_once(ah.counter_succeeded, _on_counter_succeeded)
	_connect_once(ah.counter_failed, _on_counter_failed)
	_connect_once(eh.card_evolved, _on_card_evolved)
	_connect_once(eh.card_destroyed, _on_card_destroyed)
	for player in tm.game_state.players:
		_connect_once(player.discard_reshuffled, _on_discard_reshuffled)


func _connect_once(sig: Signal, callback: Callable) -> void:
	if not sig.is_connected(callback):
		sig.connect(callback)


func _on_turn_started(_player_id: int) -> void:
	play("turn_start")


func _on_cards_drawn(_player_id: int, _count: int) -> void:
	play("card_draw")


func _on_card_discarded(_player_id: int, _card: Dictionary) -> void:
	play("card_discard")


func _on_rage_gained(_player_id: int, _new_rage: int) -> void:
	play("gain_rage")


func _on_strategy_card_played(_player_id: int, _card: Dictionary, _strategy_index: int) -> void:
	play("card_play")


func _on_battle_card_played(_player_id: int, _card: Dictionary, _zone_index: int) -> void:
	play("card_play")


func _on_monster_advanced(_player_id: int, _from_zone: int, _to_zone: int) -> void:
	play("monster_advance")


func _on_battle_card_crushed(_player_id: int, _zone_index: int, _card: Dictionary) -> void:
	play("card_destroy")


func _on_counter_succeeded(_player_id: int, _total_cp: int, _threat: int, _rage_threat: int, _effect_threat: int) -> void:
	play("counter_success")


func _on_counter_failed(_player_id: int, _total_cp: int, _threat: int, _rage_threat: int, _effect_threat: int) -> void:
	play("counter_fail")


func _on_card_evolved(_player_id: int, _card: Dictionary, _zone_index: int) -> void:
	play("card_evolve")


func _on_card_destroyed(_player_id: int, _zone_index: int) -> void:
	play("card_destroy")


func _on_discard_reshuffled(_moved_cards: Array) -> void:
	play("deck_shuffle")
