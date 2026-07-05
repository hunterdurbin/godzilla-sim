# Project Restructure — Execution Plan

A full structural overhaul of this project to the organizational standards of
Slay the Spire 2's Godot source (layered logic/presentation split, shared
domain vocabulary across every tree, subsystem READMEs living inside the
directories they document), executed in 10 phases over multiple days/sessions.

**If you are an agent (or human) picking this work up: read [STATE.md](STATE.md)
first.** It is the single source of truth for where the work stands.

## What this restructure does

1. **Cleanup** — delete orphaned prototype scenes and stale test reports.
2. **Consolidation** — all test/dev harnesses move under `tests/` (they are
   currently spread across `scenes/server/tests/`, `scenes/simulation/`,
   `scenes/board/tests/`, `scripts/tools/`).
3. **Domain re-slice** — the 42-file catch-all at `scripts/` root and the
   stray top-level `data/` dir dissolve into domain dirs (`bot/`, `net/`,
   `replay/`, `audio/`, `services/`, `cards/`, …); `scenes/ui/` splits into
   `menus/`, `lobby/`, `deck_builder/`, `replay/`; assets normalize to
   snake_case domain buckets.
4. **God-file splits** — `data/card_data.gd` (4,769 lines),
   `scripts/bot_player.gd` (2,157), `scenes/board/game_board.gd` (3,274)
   decompose behind stable public surfaces.
5. **Documentation** — ~30 `.md` files: a README inside every subsystem
   directory, plus rewrites of the root `README.md` and `CLAUDE.md`.

The full rationale, target tree, and rules live in
[conventions.md](conventions.md).

## Phase index

| Phase | File | Summary |
|---|---|---|
| 0 | [phase-0-baselines.md](phase-0-baselines.md) | These plan docs + baseline captures |
| 1 | [phase-1-cleanup.md](phase-1-cleanup.md) | Delete orphans + stale reports/ |
| 2 | [phase-2-test-harnesses.md](phase-2-test-harnesses.md) | Consolidate harnesses under tests/ |
| 3 | [phase-3-scripts-reslice.md](phase-3-scripts-reslice.md) | scripts/ + data/ domain re-slice |
| 4 | [phase-4-scenes-reslice.md](phase-4-scenes-reslice.md) | scenes/ re-slice |
| 5 | [phase-5-assets.md](phase-5-assets.md) | assets/ normalization + icons merge |
| 6 | [phase-6-split-card-data.md](phase-6-split-card-data.md) | Split card_data.gd into per-set files |
| 7 | [phase-7-split-bot-player.md](phase-7-split-bot-player.md) | Split bot_player.gd into helpers |
| 8 | [phase-8-split-game-board.md](phase-8-split-game-board.md) | Split game_board.gd into modules |
| 9 | [phase-9-docs-sweep.md](phase-9-docs-sweep.md) | Documentation sweep + closeout |

Phases run **in order**. Each phase is independently verifiable and ends in
exactly one commit (Phases 7 and 8 use gated sub-commits).

## Handoff protocol

1. **On resume**: read `STATE.md` → open the current phase file → verify the
   working tree matches STATE (`git status` clean, last commit SHA matches).
2. **During work**: check off steps in the phase file as you complete them
   (edit the file's checkboxes); record any deviation from the plan in
   STATE.md **immediately**, not at phase end.
3. **At each gate**: paste gate results (test count, sim diff verdict, harness
   verdict, grep zero-hit confirmation) into STATE.md **before** committing.
4. **Commit convention**: `restructure(phase-N): <summary>` — so
   `git log --oneline --grep 'restructure('` reconstructs progress.
5. **Never commit** the local seed-pinning edit to
   `BotSimulationRunner.tscn` (see conventions.md → Verification gate).
