class_name SessionConfig
extends RefCounted

## Per-match configuration injected into TurnManager.setup() so the logic
## layer never reads the NetworkManager/GameSettings/DecklistManager
## singletons directly. Local host/solo sessions build it from those
## singletons via from_singletons(); a dedicated server builds it from room
## seat data instead.

## Active format string (e.g. "" or a named mode); drives per-format card
## printing in TurnManager.setup().
var game_mode: String = ""

## Per-player deck payloads. Entry i is {} to use the card-data fallback
## deck, otherwise {"monster_deck": Array, "main_deck": Array}.
var decks: Array = [{}, {}]

## Initial player names (overridden per-seat by callers that know better).
var player_names: Array = ["Player 1", "Player 2"]

## The local player's display name (GameSettings.player_name on a normal
## host; unused on a dedicated server where both names come from seats).
var local_player_name: String = ""

## Stats metadata broadcast to clients for disconnect reporting.
var deck_names: Array = ["", ""]
var decklists: Array = [null, null]


## Capture the current singleton state (deck selection, mode, names) into a
## config. Behavior-identical to what TurnManager.setup() used to read.
static func from_singletons() -> SessionConfig:
	var cfg := SessionConfig.new()
	# Public/online MP syncs the chosen format into NetworkManager.game_mode;
	# solo-bot games leave it empty and use the player's saved default format.
	if NetworkManager.mode == NetworkManager.Mode.SOLO_BOT:
		cfg.game_mode = GameSettings.default_game_mode
	else:
		cfg.game_mode = NetworkManager.game_mode
	cfg.local_player_name = GameSettings.player_name
	for i in range(2):
		if DecklistManager.has_player_deck(i):
			cfg.decks[i] = {
				"monster_deck": DecklistManager.get_player_monster_deck(i).duplicate(true),
				"main_deck": DecklistManager.build_main_deck_for_player(i),
			}
		cfg.deck_names[i] = DecklistManager.get_player_deck_name(i)
		var deck_data = DecklistManager._player_decks[i]
		if deck_data != null:
			cfg.decklists[i] = {
				"main_entries": deck_data["main_entries"],
				"monster_deck": deck_data["monster_deck"],
			}
	return cfg
