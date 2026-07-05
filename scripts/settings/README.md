# scripts/settings/ — user preferences

One file: `game_settings.gd` — **autoload `GameSettings`**. Persists all user
preferences via ConfigFile at `user://settings.cfg`: player name, locale
(applies `TranslationServer.set_locale()` on boot), card-art locale,
auto-play toggles, visual/turn-indicator options, sound/music volume, bot
difficulty/deck weights, applied artwork fixes, and the online reconnect
session (`save_reconnect_session()` / `has_valid_reconnect_session()`,
90-minute window).

Also provides `pick_weighted_random_deck()` (bot deck sampling) and
`get_custom_base_path()` (per-OS custom-content dir: Android external
storage, iOS `~/Documents/custom`, else `user://custom`).

Call `GameSettings.save()` after mutating any persisted field — nothing
autosaves.
