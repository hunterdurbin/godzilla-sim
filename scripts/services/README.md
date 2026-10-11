# scripts/services/ — app/platform services

Autoloaded singletons for everything that isn't gameplay: content delivery,
telemetry, updates, input mode.

| File | Role |
|---|---|
| `artwork_downloader.gd` | **Autoload `ArtworkDownloader`** — downloads per-locale card art from `https://api.godzillatcg.com` (single `GET /media/by-number/<n>?locale=` or batch-zip `POST /media/by-number/batch`) into `user://CardContent/Artwork/<locale>/<set>/`; cache counting/clearing; `apply_fix_pool()` invalidates stale art via `CardArtworkFixPool` (`scripts/cards/pools/`); signals `progress_updated`, `download_complete` |
| `stats_uploader.gd` | **Autoload `StatsUploader`** — POSTs the full game-result payload (players, decks, final board) to `https://api.godzillatcg.com/game-results` after online matches, one retry; respects mode/visibility from NetworkManager |
| `update_checker.gd` | **Autoload `UpdateChecker`** — GitHub Releases check on startup; `find_offers()` builds `pending_update` = `{current, same_channel, stable_switch}` (see Channels below), each offer carrying `url`/`size`/`sha256` (from the asset `digest`); `skip_key()` for "Skip This Version"; signal `update_available(update)`; boots `UpdateInstaller.cleanup_leftovers()` |
| `update_installer.gd` | **`UpdateInstaller`** (not an autoload; the main-menu update dialog creates it) — in-app updater for desktop zip builds. See below |
| `touch_helper.gd` | **Autoload `TouchHelper`** — `is_touch_device()` (runtime touch-vs-mouse tracking, forced on mobile, `--mobile` CLI override); bridges Android back button to `ui_cancel` |

These talk to `GameSettings` for preferences (locales, applied fixes,
opt-outs) and never to the game engine directly.

## Channels

Tags look like `v<major>.<minor>.<patch>-unstable.N`, `-release`, or
`-release-hotfix.N`.

- **Release builds** are offered the newest newer release or hotfix. They
  never see unstable builds.
- **Unstable builds** are offered the newest newer unstable build, in any
  series (`0.1.12-unstable.13` → `0.1.13-unstable.1`).
- **Stable switch.** Unstable builds are also offered the newest stable
  release whose `major.minor.patch` is at least their own: the series they
  were heading toward, or a later one (never an older one, which would be a
  downgrade). The dialog shows "Switch to Stable" alongside "Update Now".
- **Data on a switch.** Desktop zip builds of both channels share one
  `user://` dir (same `config/name`, no custom user dir), so a switch keeps
  decks, settings and saves. Flatpak and Android channels have separate app
  ids and sandboxes, so the dialog warns that data won't carry over
  (`channel_switch_keeps_data()`). An export/import tool for those platforms
  is a planned follow-up.
- **Skipping.** "Skip This Version" stores the tags of every offer shown.
  The dialog comes back as soon as either offer changes.
- **No prompts:** iOS (SideStore delivers its updates) and Web.

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
4. **Swap.** On "Restart Now", move the target (the exe, or the `.app` bundle
   on macOS) into `.update_staging/replaced/`, then move the payload to its
   final path. Roll back every move if one fails. Then relaunch (`open -n` on
   macOS, `create_process` elsewhere) and quit.
   - **Final path, same channel:** the running file's own path, so a renamed
     exe keeps its name.
   - **Final path, channel switch:** the payload's own name
     (`godzilla_tcg_sim.exe` / `.app`) in the same dir. A stale copy already
     at that name is moved aside first.
5. **Cleanup.** On the next boot, `cleanup_leftovers()` deletes the staging dir
   (including whatever was replaced), plus any legacy `<target>.old`.

The swap waits until the restart click on purpose. Godot reads the PCK lazily
by path, so once the running exe or bundle has been replaced, any resource that
isn't cached yet would load from the wrong file.

Flatpak users still update through the browser. Flathub distribution (which
handles updates itself) is a planned follow-up.
