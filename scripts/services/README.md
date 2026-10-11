# scripts/services/ — app/platform services

Autoloaded singletons for everything that isn't gameplay: content delivery,
telemetry, updates, input mode.

| File | Role |
|---|---|
| `artwork_downloader.gd` | **Autoload `ArtworkDownloader`** — downloads per-locale card art from `https://api.godzillatcg.com` (single `GET /media/by-number/<n>?locale=` or batch-zip `POST /media/by-number/batch`) into `user://CardContent/Artwork/<locale>/<set>/`; cache counting/clearing; `apply_fix_pool()` invalidates stale art via `CardArtworkFixPool` (`scripts/cards/pools/`); signals `progress_updated`, `download_complete` |
| `stats_uploader.gd` | **Autoload `StatsUploader`** — POSTs the full game-result payload (players, decks, final board) to `https://api.godzillatcg.com/game-results` after online matches, one retry; respects mode/visibility from NetworkManager |
| `update_checker.gd` | **Autoload `UpdateChecker`** — GitHub Releases check on startup (same release channel), OS-specific asset pick (`url`/`size`/`sha256` from the asset `digest`) into `pending_update`; signal `update_available`; boots `UpdateInstaller.cleanup_leftovers()` |
| `update_installer.gd` | **`UpdateInstaller`** (not an autoload; the main-menu update dialog creates it) — in-app updater for desktop zip builds. See below |
| `touch_helper.gd` | **Autoload `TouchHelper`** — `is_touch_device()` (runtime touch-vs-mouse tracking, forced on mobile, `--mobile` CLI override); bridges Android back button to `ui_cancel` |

These talk to `GameSettings` for preferences (locales, applied fixes,
opt-outs) and never to the game engine directly.

## In-app updates (`UpdateInstaller`)

"Update Now" installs in place when `UpdateInstaller.can_self_update()` is
true. That means an exported Windows/macOS/Linux zip build, outside Flatpak,
whose install dir is writable. Every other case (Flatpak, mobile, editor,
read-only dir, or any install failure) falls back to opening the download in
the browser.

1. **Download.** Fetch the platform zip to `<install dir>/.update_staging/pkg.zip`.
   Staging lives next to the install, so the final rename stays on one filesystem.
2. **Verify.** Check the size, and the sha256 when GitHub supplies a `digest`.
3. **Extract.** Unpack with `ZIPReader`, rejecting unsafe paths, then restore
   exec bits (ZIPReader drops Unix modes).
4. **Swap.** On "Restart Now", rename the target (the exe, or the `.app` bundle
   on macOS) to `<target>.old` and move the payload into its place. Roll back if
   the move fails. Then relaunch: `open -n` on macOS, `create_process` elsewhere.
   Finally quit.
5. **Cleanup.** On the next boot, `cleanup_leftovers()` deletes `<target>.old` and
   the staging dir.

The swap waits until the restart click on purpose. Godot reads the PCK lazily
by path, so once the running exe or bundle has been replaced, any resource that
isn't cached yet would load from the wrong file.

Flatpak users still update through the browser. Flathub distribution (which
handles updates itself) is a planned follow-up.
