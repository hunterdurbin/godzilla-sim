extends Node

const SETTINGS_PATH := "user://settings.cfg"

var _custom_base_path: String = ""


## Returns the absolute path to the custom assets directory.
## On Android, uses the external data directory (browseable by file managers).
## On iOS, uses the Documents directory (visible in the Files app).
## On other platforms, uses the standard user:// directory.
func get_custom_base_path() -> String:
	if _custom_base_path.is_empty():
		if OS.get_name() == "Android":
			_custom_base_path = OS.get_data_dir().path_join("custom")
		elif OS.get_name() == "iOS":
			var home := OS.get_environment("HOME")
			_custom_base_path = home.path_join("Documents/custom")
		else:
			_custom_base_path = ProjectSettings.globalize_path("user://custom")
	return _custom_base_path

var player_name: String = ""
var locale: String = ""  # empty = never chosen; LoadingScreen prompts on first launch
var card_art_locale: String = "en"  # decoupled from UI locale; user downloads per-locale artwork
var auto_draw: bool = true
var auto_phase_advance: bool = true
var auto_discard_strategies: bool = true
var auto_reset_rage: bool = true
var auto_counter_check: bool = true
var auto_advance: bool = true
var confirm_main_phase_pass: bool = false
var hand_sort_type_order: int = 0  # 0-5 index into type permutations
var hand_sort_rank_ascending: bool = true
var stacked_view: bool = true  # Remembered stacked toggle for overlays
var default_game_mode: String = "rumble_west"
var deck_list_format: String = ""  # DeckListView format filter; "" = Any (grey ineligible decks)

# Visual settings
var custom_playmat_enabled: bool = false
var custom_playmat_opponent: bool = false
var color_overlay_mode: int = 3  # 0=none, 1=self only, 2=opponent only, 3=both
var custom_card_art_enabled: bool = false
var custom_card_back_mode: int = 0  # 0=disabled, 1=myself only, 2=both players
var custom_rage_marker_enabled: bool = false

# Audio settings
var sound_volume: int = 1  # 0=OFF, 1=25%, 2=50%, 3=75%, 4=100%
var music_volume: int = 0  # 0=OFF, 1=25%, 2=50%, 3=75%, 4=100%

# Advanced settings
var use_mobile_layout: bool = false

# Bot settings
var bot_difficulty: int = BotConfig.Difficulty.NORMAL  # 0=Easy, 1=Normal, 2=Hard
var bot_seed_text: String = ""             # raw text; if valid int, used as seed; "" = auto
var bot_speed_value: int = 0               # 0=Auto, 1-10 = 0.1s..1.0s delay
var bot_playstyle_value: int = 0           # 0=Auto, 1=Invasion, 2=Counter, 3=Balanced
var bot_random_deck_enabled: bool = false
var bot_random_deck_on_rematch: bool = true  # When random deck is enabled, re-pick from the pool on each rematch
var bot_random_deck_format: String = ""    # GameModeValidator mode id, "" = Any
var bot_deck_weights: Dictionary = {}      # {deck_name: int weight, 0=disabled, >=1=weight}
var bot_folder_weights: Dictionary = {}    # {folder_path: int weight, 0/missing=disabled}

# Update settings
var skipped_version: String = ""

# Cache invalidation — keys from CardArtworkFixPool.ENTRIES that have already
# been applied on this install. New keys trigger a one-shot re-download on
# the next launch.
var applied_artwork_fixes: Array[String] = []

# Reconnect session data
var reconnect_room_code: String = ""
var reconnect_timestamp_sec: int = 0  # Unix time (persists across restarts)
var reconnect_is_host: bool = false
var reconnect_game_mode: String = ""
var reconnect_is_public: bool = false
const RECONNECT_TIMEOUT_SEC: int = 90 * 60  # 90 minutes


func _ready() -> void:
	use_mobile_layout = OS.get_name() in ["Android", "iOS"] or OS.has_feature("mobile")
	_load()
	# Apply persisted locale immediately if chosen; otherwise LoadingScreen
	# prompts the user, then calls set_locale().
	if not locale.is_empty():
		TranslationServer.set_locale(locale)
	if player_name.is_empty():
		player_name = "Player%06d" % (randi() % 1000000)
		_save()


func has_chosen_locale() -> bool:
	return not locale.is_empty()


func set_locale(new_locale: String) -> void:
	locale = new_locale
	TranslationServer.set_locale(new_locale)
	_save()


func save() -> void:
	_save()


func save_reconnect_session(room_code: String, is_host: bool, p_game_mode: String, p_is_public: bool) -> void:
	reconnect_room_code = room_code
	reconnect_timestamp_sec = int(Time.get_unix_time_from_system())
	reconnect_is_host = is_host
	reconnect_game_mode = p_game_mode
	reconnect_is_public = p_is_public
	_save()


func clear_reconnect_session() -> void:
	reconnect_room_code = ""
	reconnect_timestamp_sec = 0
	reconnect_is_host = false
	reconnect_game_mode = ""
	reconnect_is_public = false
	_save()


func has_valid_reconnect_session() -> bool:
	if reconnect_room_code.is_empty():
		return false
	var elapsed := int(Time.get_unix_time_from_system()) - reconnect_timestamp_sec
	return elapsed >= 0 and elapsed < RECONNECT_TIMEOUT_SEC


func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("gameplay", "player_name", player_name)
	config.set_value("gameplay", "locale", locale)
	config.set_value("gameplay", "card_art_locale", card_art_locale)
	config.set_value("gameplay", "auto_draw", auto_draw)
	config.set_value("gameplay", "auto_phase_advance", auto_phase_advance)
	config.set_value("gameplay", "auto_discard_strategies", auto_discard_strategies)
	config.set_value("gameplay", "auto_reset_rage", auto_reset_rage)
	config.set_value("gameplay", "auto_counter_check", auto_counter_check)
	config.set_value("gameplay", "auto_advance", auto_advance)
	config.set_value("gameplay", "confirm_main_phase_pass", confirm_main_phase_pass)
	config.set_value("gameplay", "hand_sort_type_order", hand_sort_type_order)
	config.set_value("gameplay", "hand_sort_rank_ascending", hand_sort_rank_ascending)
	config.set_value("gameplay", "stacked_view", stacked_view)
	config.set_value("gameplay", "default_game_mode", default_game_mode)
	config.set_value("gameplay", "deck_list_format", deck_list_format)
	config.set_value("visual", "custom_playmat_enabled", custom_playmat_enabled)
	config.set_value("visual", "custom_playmat_opponent", custom_playmat_opponent)
	config.set_value("visual", "color_overlay_mode", color_overlay_mode)
	config.set_value("visual", "custom_card_art_enabled", custom_card_art_enabled)
	config.set_value("visual", "custom_card_back_mode", custom_card_back_mode)
	config.set_value("visual", "custom_rage_marker_enabled", custom_rage_marker_enabled)
	config.set_value("audio", "sound_volume", sound_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("bot", "difficulty", bot_difficulty)
	config.set_value("bot", "seed_text", bot_seed_text)
	config.set_value("bot", "speed_value", bot_speed_value)
	config.set_value("bot", "playstyle_value", bot_playstyle_value)
	config.set_value("bot", "random_deck_enabled", bot_random_deck_enabled)
	config.set_value("bot", "random_deck_on_rematch", bot_random_deck_on_rematch)
	config.set_value("bot", "random_deck_format", bot_random_deck_format)
	config.set_value("bot", "deck_weights", bot_deck_weights)
	config.set_value("bot", "folder_weights", bot_folder_weights)
	config.set_value("advanced", "use_mobile_layout", use_mobile_layout)
	config.set_value("updates", "skipped_version", skipped_version)
	config.set_value("cache", "applied_artwork_fixes", applied_artwork_fixes)
	config.set_value("reconnect", "room_code", reconnect_room_code)
	config.set_value("reconnect", "timestamp_sec", reconnect_timestamp_sec)
	config.set_value("reconnect", "is_host", reconnect_is_host)
	config.set_value("reconnect", "game_mode", reconnect_game_mode)
	config.set_value("reconnect", "is_public", reconnect_is_public)
	config.save(SETTINGS_PATH)


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	player_name = config.get_value("gameplay", "player_name", "")
	locale = config.get_value("gameplay", "locale", "")
	card_art_locale = config.get_value("gameplay", "card_art_locale", "")
	# Migrate / repair: empty card_art_locale means a stale write or pre-locale
	# install. Fall back to the UI locale when set, else "en". Without this,
	# ArtworkDownloader.start_download() would treat the empty path as
	# uncached and re-fetch all 382 cards.
	if card_art_locale.is_empty():
		card_art_locale = locale if not locale.is_empty() else "en"
	auto_draw = config.get_value("gameplay", "auto_draw", true)
	auto_phase_advance = config.get_value("gameplay", "auto_phase_advance", true)
	auto_discard_strategies = config.get_value("gameplay", "auto_discard_strategies", true)
	auto_reset_rage = config.get_value("gameplay", "auto_reset_rage", true)
	auto_counter_check = config.get_value("gameplay", "auto_counter_check", true)
	auto_advance = config.get_value("gameplay", "auto_advance", true)
	confirm_main_phase_pass = config.get_value("gameplay", "confirm_main_phase_pass", false)
	hand_sort_type_order = config.get_value("gameplay", "hand_sort_type_order", 0)
	hand_sort_rank_ascending = config.get_value("gameplay", "hand_sort_rank_ascending", true)
	stacked_view = config.get_value("gameplay", "stacked_view", true)
	default_game_mode = config.get_value("gameplay", "default_game_mode", "rumble_west")
	deck_list_format = config.get_value("gameplay", "deck_list_format", "")
	custom_playmat_enabled = config.get_value("visual", "custom_playmat_enabled", false)
	custom_playmat_opponent = config.get_value("visual", "custom_playmat_opponent", false)
	color_overlay_mode = config.get_value("visual", "color_overlay_mode", 3)
	custom_card_art_enabled = config.get_value("visual", "custom_card_art_enabled", false)
	custom_card_back_mode = config.get_value("visual", "custom_card_back_mode", 0)
	custom_rage_marker_enabled = config.get_value("visual", "custom_rage_marker_enabled", false)
	# Migrate old bool sound_enabled to new int sound_volume
	var _old_sound: Variant = config.get_value("audio", "sound_enabled", "") if config.has_section_key("audio", "sound_enabled") else ""
	if _old_sound is bool:
		sound_volume = 4 if _old_sound else 0
	else:
		sound_volume = config.get_value("audio", "sound_volume", 2)
	var _old_music: Variant = config.get_value("audio", "music_enabled", "") if config.has_section_key("audio", "music_enabled") else ""
	if _old_music is bool:
		music_volume = 4 if _old_music else 0
	else:
		music_volume = config.get_value("audio", "music_volume", 2)
	bot_difficulty = config.get_value("bot", "difficulty", BotConfig.Difficulty.NORMAL)
	bot_seed_text = config.get_value("bot", "seed_text", "")
	bot_speed_value = config.get_value("bot", "speed_value", 0)
	bot_playstyle_value = config.get_value("bot", "playstyle_value", 0)
	bot_random_deck_enabled = config.get_value("bot", "random_deck_enabled", false)
	bot_random_deck_on_rematch = config.get_value("bot", "random_deck_on_rematch", true)
	bot_random_deck_format = config.get_value("bot", "random_deck_format", "")
	bot_deck_weights = config.get_value("bot", "deck_weights", {})
	bot_folder_weights = config.get_value("bot", "folder_weights", {})
	var _mobile_default := OS.get_name() in ["Android", "iOS"] or OS.has_feature("mobile")
	use_mobile_layout = config.get_value("advanced", "use_mobile_layout", _mobile_default)
	skipped_version = config.get_value("updates", "skipped_version", "")
	# ConfigFile returns a generic Array; defensively rebuild as Array[String].
	var raw_fixes: Array = config.get_value("cache", "applied_artwork_fixes", [])
	applied_artwork_fixes.clear()
	for k in raw_fixes:
		if k is String:
			applied_artwork_fixes.append(k)
	reconnect_room_code = config.get_value("reconnect", "room_code", "")
	reconnect_timestamp_sec = config.get_value("reconnect", "timestamp_sec", 0)
	reconnect_is_host = config.get_value("reconnect", "is_host", false)
	reconnect_game_mode = config.get_value("reconnect", "game_mode", "")
	reconnect_is_public = config.get_value("reconnect", "is_public", false)


func pick_weighted_random_deck() -> String:
	## Two-stage sampler: each pool entry is either a single deck OR a whole
	## folder (uniform pick inside it). Folder-enabled decks are NOT also
	## listed individually — the folder takes over. Honors bot_random_deck_format
	## by skipping decks not legal in that mode (folders contribute weight only
	## when at least one of their decks is legal). Returns "" when no pool is
	## configured / nothing eligible; caller should leave the previous deck
	## selection in place.
	var entries := DecklistManager.get_all_deck_entries()
	var format_id := bot_random_deck_format
	var eligibility_cache: Dictionary = {}
	var is_eligible := func(deck_name: String) -> bool:
		if format_id.is_empty():
			return true
		if eligibility_cache.has(deck_name):
			return bool(eligibility_cache[deck_name])
		var ok := DecklistManager.is_decklist_valid_for_mode(deck_name, format_id)
		eligibility_cache[deck_name] = ok
		return ok

	var enabled_folders: Dictionary = {}
	for fp in bot_folder_weights:
		var fw := int(bot_folder_weights[fp])
		if fw > 0:
			enabled_folders[fp] = fw

	# Pre-expand each enabled folder to the set of *eligible* decks inside it.
	# Folders with zero eligible decks are skipped entirely (don't contribute
	# weight, can't be picked).
	var folder_eligible_decks: Dictionary = {}
	for fp in enabled_folders:
		var legal: Array[String] = []
		for entry in entries:
			if entry["folder"] == fp and is_eligible.call(entry["name"]):
				legal.append(entry["name"])
		if not legal.is_empty():
			folder_eligible_decks[fp] = legal

	var pool: Array = []
	var total := 0
	for fp in enabled_folders:
		if not folder_eligible_decks.has(fp):
			continue
		pool.append({"kind": "folder", "name": fp, "weight": enabled_folders[fp]})
		total += int(enabled_folders[fp])

	for entry in entries:
		if enabled_folders.has(entry["folder"]):
			continue
		var deck_name: String = entry["name"]
		var has_entry: bool = bot_deck_weights.has(deck_name)
		var w: int = 1
		if has_entry:
			w = int(bot_deck_weights[deck_name])
		if w <= 0:
			continue
		if not is_eligible.call(deck_name):
			continue
		pool.append({"kind": "deck", "name": deck_name, "weight": w})
		total += w

	if total <= 0 or pool.is_empty():
		return ""

	var r := randi() % total
	var acc := 0
	for e in pool:
		acc += int(e["weight"])
		if r < acc:
			if e["kind"] == "folder":
				var folder_decks: Array[String] = folder_eligible_decks[e["name"]]
				return folder_decks[randi() % folder_decks.size()]
			return e["name"]
	return ""
