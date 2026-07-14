# Phase 3 — scripts/ + data/ domain re-slice

**Goal:** dissolve the 42-file catch-all at `scripts/` root and the top-level
`data/` dir into domain dirs. Mechanical `git mv` only — no file content
changes beyond path literals, **no splits** (those are Phases 6–8).

## Moves (git mv, with `.uid` twins)

New dirs: `scripts/{bot,net,replay,audio,services,localization,settings,cards,cards/pools}`.

| Destination | Files (from `scripts/` root unless noted) |
|---|---|
| `scripts/bot/` | bot_player.gd, bot_config.gd, bot_combo.gd, bot_combo_shin.gd |
| `scripts/net/` | network_manager.gd, game_server_peer.gd, relay_multiplayer_peer.gd, rpc_logger.gd, chat_filter.gd |
| `scripts/replay/` | replay_data.gd, replay_recorder.gd, game_serializer.gd, game_log.gd, game_log_export.gd |
| `scripts/audio/` | sfx_manager.gd, music_manager.gd |
| `scripts/services/` | artwork_downloader.gd, stats_uploader.gd, update_checker.gd, touch_helper.gd |
| `scripts/localization/` | loc.gd |
| `scripts/settings/` | game_settings.gd (from `data/`) |
| `scripts/cards/` | card_data.gd, card_enums.gd, deck_validator.gd, decklist_manager.gd, decklog_importer.gd, game_mode_validator.gd (from `data/`) |
| `scripts/cards/pools/` | bulkzilla_card_pool.gd, card_artwork_fix_pool.gd (from `data/`) |

Adjust to reality: `ls scripts/*.gd data/*.gd` first — the table above is from
the planning audit; any file it misses goes to the most fitting domain dir
(record the decision in STATE.md). `data/` must be EMPTY (then deleted) and
`scripts/` root must contain no loose `.gd` when done. `scripts/util/` and
`scripts/tools/` stay as-is.

## project.godot — update ALL autoload paths

All 11 keep their NAMES; only paths change. Expected result (verify each):

```
CardData="*res://scripts/cards/card_data.gd"
DecklistManager="*res://scripts/cards/decklist_manager.gd"
GameSettings="*res://scripts/settings/game_settings.gd"
ArtworkDownloader="*res://scripts/services/artwork_downloader.gd"
NetworkManager="*res://scripts/net/network_manager.gd"
StatsUploader="*res://scripts/services/stats_uploader.gd"
UpdateChecker="*res://scripts/services/update_checker.gd"
RpcLogger="*res://scripts/net/rpc_logger.gd"
TouchHelper="*res://scripts/services/touch_helper.gd"
SfxManager="*res://scripts/audio/sfx_manager.gd"
MusicManager="*res://scripts/audio/music_manager.gd"
```

## Path-literal audit

For EVERY moved filename, grep the old `res://` literal:

```bash
for f in bot_player bot_config bot_combo bot_combo_shin network_manager \
         game_server_peer relay_multiplayer_peer rpc_logger chat_filter \
         replay_data replay_recorder game_serializer game_log game_log_export \
         sfx_manager music_manager artwork_downloader stats_uploader \
         update_checker touch_helper loc; do
  grep -rn "res://scripts/$f.gd" . --include='*.gd' --include='*.tscn' \
    --exclude-dir=build --exclude-dir=.godot --exclude-dir=.git
done
grep -rn 'res://data/' . --include='*.gd' --include='*.tscn' --include='*.cfg' \
  --include='*.sh' --include='*.yml' --exclude-dir=build --exclude-dir=.godot --exclude-dir=.git
```

Known hotspots from planning: one preload of bot_combo from bot_player;
`scripts/server/game_room.gd` has ~4 `res://scripts/` refs (check whether
they point at server/effects paths that did NOT move); exactly one
`res://data/` hit existed at audit time — find and fix it. Also sweep
`.github/`, `build_ios.sh`, `deploy/`, `flatpak/`, `.claude/`.

**Not affected (verify, don't fix):** `res://scripts/effects/…` (368 strings
in card_data.gd + trigger_map.gd) — effects didn't move; card_data.gd moving
does not change those strings.

## Docs to write this phase

`scripts/README.md` (domain map + the 11-autoload registry table + layering
rules), plus per-dir READMEs: core, cards, bot, session, server, net, replay,
audio, services, localization, util, tools, effects (see the content specs in
the approved plan / phase-9 file), and `translations/README.md`,
`comprehensive_rules/README.md`.

## Gate (full)

Run the sim FIRST as a cheap boot smoke — a wrong autoload path crashes at
boot. Then unit tests, sim diff, harness, zero-hit greps
(`res://data/` + every moved `res://scripts/<name>.gd` literal).

## Commit

`restructure(phase-3): re-slice scripts/ and dissolve data/ into domain dirs`
