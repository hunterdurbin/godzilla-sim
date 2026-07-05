# scripts/ — the logic layer

Everything under `scripts/` is engine/services code: `RefCounted` game logic,
autoloaded singletons, and network/server plumbing. **No scene files live
here**, and nothing in `core/` or `effects/` may reference `scenes/` — the
presentation layer (`scenes/`) depends on this layer, never the reverse.

## Domain map

| Dir | Responsibility | README |
|---|---|---|
| `core/` | Pure match engine: state, rules, turn flow, action resolution, player-input port | [core/README.md](core/README.md) |
| `effects/` | Per-card effect scripts + facade + registry + codegen (**path-frozen** — see its README) | [effects/README.md](effects/README.md) |
| `cards/` | Card database, enums, deck validation/management, format pools | [cards/README.md](cards/README.md) |
| `bot/` | Bot AI: decision pipeline, scoring, combos, difficulty config | [bot/README.md](bot/README.md) |
| `session/` | GameSession glue: multiplayer sync (all `@rpc`s), effect-UI routing | [session/README.md](session/README.md) |
| `server/` | Dedicated headless server (rooms, connections, headless board) | [server/README.md](server/README.md) |
| `net/` | Transport: LAN/relay/dedicated peers, RPC byte logging, chat filter | [net/README.md](net/README.md) |
| `replay/` | Replays, saves, structured game log + export | [replay/README.md](replay/README.md) |
| `audio/` | SFX + music managers | [audio/README.md](audio/README.md) |
| `services/` | App services: artwork download, stats upload, update check, touch input | [services/README.md](services/README.md) |
| `localization/` | `Loc.t()` translation helper (data lives in `translations/`) | [localization/README.md](localization/README.md) |
| `settings/` | Persisted user preferences (`user://settings.cfg`) | [settings/README.md](settings/README.md) |
| `util/` | Small dependency-free helpers | [util/README.md](util/README.md) |
| `tools/` | Dev/CI check scripts (not shipped features) | [tools/README.md](tools/README.md) |

## Autoload registry (project.godot `[autoload]`)

| Name | Path | Responsibility |
|---|---|---|
| `CardData` | `scripts/cards/card_database.gd` | Card template database (`CARD_TEMPLATES`, deck builders) |
| `DecklistManager` | `scripts/cards/decklist_manager.gd` | `.deck` files under `user://decklists/`, per-player deck selection |
| `GameSettings` | `scripts/settings/game_settings.gd` | User prefs, locale, reconnect session |
| `NetworkManager` | `scripts/net/network_manager.gd` | Connection lifecycle (LAN/relay/dedicated), scene handoff |
| `ArtworkDownloader` | `scripts/services/artwork_downloader.gd` | Card art cache (`user://CardContent/Artwork`) |
| `StatsUploader` | `scripts/services/stats_uploader.gd` | Game-result POST to api.godzillatcg.com |
| `UpdateChecker` | `scripts/services/update_checker.gd` | GitHub release check |
| `TouchHelper` | `scripts/services/touch_helper.gd` | Touch-vs-mouse detection, Android back button |
| `GamepadInput` | `scripts/input/gamepad_input.gd` | Physical→logical controller action translation, rebinding, glyph lookup (see input/README.md) |
| `GamepadHelper` | `scripts/services/gamepad_helper.gd` | Gamepad-vs-pointer device tracking, focus-context stack |
| `SfxManager` | `scripts/audio/sfx_manager.gd` | Sound effects |
| `MusicManager` | `scripts/audio/music_manager.gd` | Background music |

Keep autoloads at these 12 — new globals need a strong reason. Autoload
scripts live in their domain dir; this table is the index. Demotion outcomes
(2026-07): `RpcLogger` became a static class (`class_name`, no Node
features needed); `TouchHelper` stays an autoload deliberately — it needs
tree membership for `_input` tracking and the Android back-button
notification. `GamepadInput`/`GamepadHelper` need tree membership for the
same reason (`_unhandled_input`/`_input` + `_process` injection).

## Layering rules

1. `core/` and `effects/` are UI-free `RefCounted` code; cards are plain
   `Dictionary`s. They may use `CardData`/`CardEnums` but never scenes.
2. Player decisions flow through the **PlayerInput port**
   (`core/input/`) — engine code `await`s `input.choose_option(...)`;
   UI/RPC/bot implement `SignalPlayerInput`, tests use `ScriptedPlayerInput`.
3. All gameplay notifications ride the **GameEvents bus**
   (`core/game_events.gd`); UI/sync/sfx subscribe — engine never calls them.
4. All 47 `@rpc`s live in `session/multiplayer_sync.gd` — the single network
   surface. RPC-facing board methods are duck-typed across three boards
   (see [session/README.md](session/README.md)).
