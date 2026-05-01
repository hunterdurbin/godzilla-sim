extends Node

## Drop-in audio wiring. Subscribes to session ActionHandler /
## EffectHandler / TurnManager signals and plays the matching SfxManager
## sound. No designer code needed.
##
## Sound names match the events SfxManager already understands:
##   "turn_start", "card_draw", "card_discard", "card_play",
##   "monster_advance", "card_destroy", "deck_shuffle", "gain_rage",
##   "card_evolve", "counter_success", "counter_fail", "action_required",
##   "game_win", "game_lose"

@export var auto_bind: bool = true
@export var sound_for_local_player_id: int = 0  # used for win/lose differentiation


func _ready() -> void:
	if auto_bind:
		_try_bind()


func _try_bind() -> void:
	var session := BoardModule.find_session(self)
	if session == null:
		return
	if session.is_running():
		_bind(session)
	else:
		session.session_started.connect(func(): _bind(session), CONNECT_ONE_SHOT)


func _bind(session: GameSession) -> void:
	var tm := session.turn_manager
	if tm == null:
		return
	tm.turn_started.connect(_on_turn_started)
	tm.game_ended.connect(_on_game_ended)

	var ah := session.action_handler
	if ah:
		ah.cards_drawn.connect(_on_cards_drawn)
		ah.card_discarded.connect(_on_card_discarded)
		ah.rage_gained.connect(_on_rage_gained)
		ah.strategy_card_played.connect(_on_strategy_card_played)
		ah.battle_card_played.connect(_on_battle_card_played)
		ah.monster_advanced.connect(_on_monster_advanced)
		ah.battle_card_crushed.connect(_on_battle_card_crushed)
		ah.counter_succeeded.connect(_on_counter_succeeded)
		ah.counter_failed.connect(_on_counter_failed)

	var eh := session.effect_handler
	if eh:
		eh.card_evolved.connect(_on_card_evolved)
		eh.card_destroyed.connect(_on_card_destroyed)

	# Per-player discard reshuffle.
	for pid in range(2):
		var p := session.get_player(pid)
		if p:
			p.discard_reshuffled.connect(_on_discard_reshuffled)


func _on_turn_started(_player_id: int) -> void:
	SfxManager.play("turn_start")


func _on_cards_drawn(_player_id: int, _count: int) -> void:
	SfxManager.play("card_draw")


func _on_card_discarded(_player_id: int, _card: Dictionary) -> void:
	SfxManager.play("card_discard")


func _on_strategy_card_played(_player_id: int, _card: Dictionary, _strategy_index: int) -> void:
	SfxManager.play("card_play")


func _on_battle_card_played(_player_id: int, _card: Dictionary, _zone_index: int) -> void:
	SfxManager.play("card_play")


func _on_monster_advanced(_player_id: int, _from_zone: int, _to_zone: int) -> void:
	SfxManager.play("monster_advance")


func _on_battle_card_crushed(_player_id: int, _zone_index: int, _card: Dictionary) -> void:
	SfxManager.play("card_destroy")


func _on_counter_succeeded(_player_id: int, _total_cp: int, _threat: int) -> void:
	SfxManager.play("counter_success")


func _on_counter_failed(_player_id: int, _total_cp: int, _threat: int) -> void:
	SfxManager.play("counter_fail")


func _on_rage_gained(_player_id: int, _new_rage: int) -> void:
	SfxManager.play("gain_rage")


func _on_card_evolved(_player_id: int, _card: Dictionary, _zone_index: int) -> void:
	SfxManager.play("card_evolve")


func _on_card_destroyed(_player_id: int, _zone_index: int) -> void:
	SfxManager.play("card_destroy")


func _on_discard_reshuffled() -> void:
	SfxManager.play("deck_shuffle")


func _on_game_ended(winner_id: int, _reason_key: String) -> void:
	SfxManager.play("game_win" if winner_id == sound_for_local_player_id else "game_lose")
