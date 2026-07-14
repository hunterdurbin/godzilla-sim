# scripts/services/ — app/platform services

Autoloaded singletons for everything that isn't gameplay: content delivery,
telemetry, updates, input mode.

| File | Role |
|---|---|
| `artwork_downloader.gd` | **Autoload `ArtworkDownloader`** — downloads per-locale card art from `https://api.godzillatcg.com` (single `GET /media/by-number/<n>?locale=` or batch-zip `POST /media/by-number/batch`) into `user://CardContent/Artwork/<locale>/<set>/`; cache counting/clearing; `apply_fix_pool()` invalidates stale art via `CardArtworkFixPool` (`scripts/cards/pools/`); signals `progress_updated`, `download_complete` |
| `stats_uploader.gd` | **Autoload `StatsUploader`** — POSTs the full game-result payload (players, decks, final board) to `https://api.godzillatcg.com/game-results` after online matches, one retry; respects mode/visibility from NetworkManager |
| `update_checker.gd` | **Autoload `UpdateChecker`** — GitHub Releases check on startup (same release channel), OS-specific asset pick; signal `update_available` |
| `touch_helper.gd` | **Autoload `TouchHelper`** — `is_touch_device()` (runtime touch-vs-mouse tracking, forced on mobile, `--mobile` CLI override); bridges Android back button to `ui_cancel` |

These talk to `GameSettings` for preferences (locales, applied fixes,
opt-outs) and never to the game engine directly.
