# Unofficial Godzilla Sim — Project Documentation

Fan-made Godzilla TCG simulator. **Engine:** Godot 4.6 · **Language:**
GDScript · **Renderer:** GL Compatibility · **Physics:** Jolt (3D).

Every subsystem directory has a `README.md` — those are the authoritative
per-area docs. This file is the map plus the rules that span subsystems.

## Layout

```
scripts/                 # LOGIC LAYER (see scripts/README.md — incl. the 12-autoload registry)
├── core/                #   pure match engine: GameState, RulesEngine, TurnManager,
│                        #   MatchFactory, GameEvents bus, actions/ resolvers,
│                        #   input/ PlayerInput port (Signal/Scripted variants)
├── effects/             #   ~370 per-card effect scripts + EffectHandler facade,
│                        #   EffectRegistry, trigger_map.gd codegen — PATH-FROZEN
├── cards/               #   card_database.gd (autoload CardData) + sets/card_set_*.gd
│                        #   (one data file per set), enums, deck validation, decklists
├── bot/                 #   BotPlayer + scoring/zone/invasion/selection helpers, combos
├── input/               #   controller support: GamepadInput autoload, GlyphDB,
│                        #   ControllerGlyph (@tool WYSIWYG glyph) — see input/README.md
├── session/             #   GameSession, MultiplayerSync (ALL 47 @rpc), EffectUIRouter
├── server/              #   dedicated headless server (rooms, HeadlessBoard)
├── net/ replay/ audio/ services/ localization/ settings/ util/ tools/
scenes/                  # PRESENTATION LAYER (see scenes/README.md)
├── board/               #   GameBoard + PlayerBoard + hud/ + overlays/ + modules/
├── cards/ deck/ slots/  #   Card.tscn, CardManager, Deck, Slot
├── menus/               #   LoadingScreen (main scene), MainMenu, Options, Extras
├── lobby/ deck_builder/ replay/ server/
tests/                   # unit/ (gdUnit4) + harness/ (multiplayer) + sim/ (bot self-play)
assets/ translations/ docs/ comprehensive_rules/ deploy/ flatpak/
```

## Architecture rules

- `scripts/core/` and `scripts/effects/` are `RefCounted`, UI-free; cards are
  plain Dictionaries (per-copy instance ids — compare via
  `CardUtils.base_id`). Presentation depends on logic, never the reverse.
- **PlayerInput** is the single decision port: engine `await`s
  `input.choose_option(...)`; `SignalPlayerInput` serves UI/RPC/bot,
  `ScriptedPlayerInput` serves tests.
- **EffectHandler is a facade** over the modules listed in
  `scripts/effects/README.md`; **GameEvents** carries gameplay notifications;
  **RulesEngine** stays pure/synchronous (queries injected).
- All RPCs live in `scripts/session/multiplayer_sync.gd`; the duck-typed
  `_board` contract has THREE implementations (game_board, harness stub,
  headless_board) — **RPC-surface changes must hit all three**
  (`scripts/session/README.md`).
- Board UI splits into `scenes/board/modules/` (BoardModule pattern);
  extraction rules and hard-won binding gotchas:
  `scenes/board/modules/README.md`.
- Every TurnManager owner must call `teardown()` or the cyclic engine graph
  leaks.
- **Card scripts express intent; the engine enforces rules.** Per-card effect
  scripts call EffectHandler primitives and never mutate zones/monster
  position or fire triggers by hand; missing primitive → add it to the engine
  (`scripts/effects/README.md` § Per-card scripts).

## Testing & verification

- Unit (gdUnit4): `./tests/run_unit_tests.sh <godot> [path]` (digest output;
  `--per-suite` when a SCRIPT ERROR aborts the run); suites in
  `tests/unit/`, fixtures in `tests/fixtures/` (hand-built dicts for core;
  `real_cards.gd` `Real.instance(id)` for effect tests — never raw CardData
  templates). Smoke suite fails if `trigger_map.gd` is stale.
- Multiplayer harness: `./tests/harness/run_harness.sh 3 <godot>` — greps
  DESYNC / SCRIPT ERROR. Run after touching session/server/board RPC surface.
- Bot sim diff vs a base ref: `./tests/sim/run_sim_diff.sh <godot> [base_ref] [games] [p1] [p2] [deck1] [deck2]`
  — seed-matched `[SimResult]` diff + KAIJU `plan DIVERGED` counts
  (`tests/sim/README.md`).
- Mechanical rules (a pattern grep can catch) get a check in `scripts/tools/`
  wired into `githooks/pre-commit` + `tests.yml`, not prose — see
  `scripts/tools/README.md` for the existing ones.
- Headful verification of board UI: the `verify` skill
  (`.claude/skills/verify/`) — unit+harness do NOT exercise the real
  GameBoard `_ready`.
- After moving files outside the editor: `./tests/import.sh <godot>`
  (wedge-safe headless import; a stale class-name cache breaks headless runs —
  the unit and sim-diff runners import on their own when it is stale).
- Before merging a PR: `/code-review` — judgement rules live in
  `CODING_STANDARDS.md`; mechanical ones are checks in `scripts/tools/`.
  PR body closes its ticket: `Closes hunterdurbin/godzilla-sim-issue-tracker#N`,
  or `Tracker: none` (`docs/agents/issue-tracker.md` § Closing tickets).
  Merge after CI passes (main requires it; auto-merge is disabled):
  `gh pr checks <n> --watch && gh pr merge <n> --squash --delete-branch`.

## Codegen & data invariants

- `scripts/effects/trigger_map.gd` is GENERATED by
  `scripts/effects/generate_trigger_map.sh` (pre-commit hook regenerates).
  NEVER run it while a headless game/harness is running. New CardEffect
  virtual → add to its `METHODS`.
- Card data lives in `scripts/cards/sets/card_set_*.gd`; the
  `effect_script` strings inside must match `scripts/effects/` paths
  byte-for-byte. "Add a card" checklist: `scripts/cards/README.md`.
- `translations/cards.csv` is generated by
  `translations/generate_card_csv.py` (parses the set files).

## Conventions

- PascalCase scenes (`FooBar.tscn`) + snake_case scripts (`foo_bar.gd`),
  co-located and same-named; snake_case asset dirs sliced by domain.
- Type hints everywhere; prefer signals for decoupling; follow the GDScript
  style guide.
- Godot editor formatting: tabs (see project settings).

## Game rules quick reference

`comprehensive_rules/` holds the official PDF; engine comments cite rule
numbers (e.g. 10.4.3 standby ordering) — look them up in the greppable
`comprehensive_rules/rules.txt` (`grep -A4 '^10\.4\.3\.'`). Official Q&A rulings
override the rules text: `comprehensive_rules/qa.txt` (`grep -A2 '^Q480 '`, or
grep a card id). Quote a ruling verbatim, with its Q number, wherever a design
or comment depends on it. 2 players, 8 zones + 2 strategy
zones; win by invading past zone 8 or when the opponent can't rank up while
countered. Turn: Start → Main → Counter → End. Threat = base + rage × 5000.
Deck: 50 main (≤10 invade-2), 4 monsters rank 1–4.

## History

The 2026-07 structural overhaul (domain re-slice, god-file splits, this doc
set) is recorded in `docs/restructure/` — read its `STATE.md` before
resuming any unfinished phase.

## Agent skills

### Issue tracker

GitHub Issues in the separate repo `hunterdurbin/godzilla-sim-issue-tracker`
(always pass `--repo`). See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-role vocabulary (needs-triage, needs-info, ready-for-agent,
ready-for-human, wontfix). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.

---

**Last Updated:** 2026-07-05
