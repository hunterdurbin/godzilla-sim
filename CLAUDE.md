# Example TCG Game - Project Documentation

## Project Overview

This is a Trading Card Game (TCG) built with Godot Engine 4.6.

**Engine:** Godot 4.6
**Renderer:** GL Compatibility
**Physics:** Jolt Physics (3D)
**Language:** GDScript

## Project Structure

```
example-tcg-game/
├── scripts/core/            # Pure game logic (RefCounted, no Node/UI)
│   ├── game_state.gd        # Match-level state container (2 PlayerStates)
│   ├── player_state.gd      # Per-player state + zone/deck helpers
│   ├── rules_engine.gd      # Pure validation (valid actions, validate_action)
│   ├── turn_manager.gd      # Phase state machine (FlowState enum)
│   ├── match_factory.gd     # Builds + wires a match (setup / setup_from_save)
│   ├── game_events.gd       # Gameplay notification bus (UI/sync/sfx subscribe)
│   ├── actions/             # ActionHandler (dispatcher) + resolvers:
│   │                        #   play_actions, invasion_resolver,
│   │                        #   counter_resolver, rule_actions, phase_actions
│   └── input/               # PlayerInput decision port:
│                            #   player_input (defaults), signal_player_input
│                            #   (live UI/RPC/bot), scripted_player_input (tests)
├── scripts/effects/         # Effect system
│   ├── effect_handler.gd    # FACADE — the stable effect-script API; delegates to:
│   ├── effect_registry.gd   #   effect/filter loading + caching (test injection)
│   ├── trigger_filters.gd   #   pure static TRIGGER_FILTERS evaluation
│   ├── effect_execution_state.gd  # active-effect + standby queue (shared)
│   ├── standby_resolver.gd  #   rule 10.4.3 resolution ordering
│   ├── trigger_dispatcher.gd#   trigger_* / collect_* dispatch over active cards
│   ├── destruction_engine.gd#   destroy flows + protection/replacement
│   ├── card_mover.gd        #   hand/deck/discard traffic, tokens, evolution
│   ├── monster_mover.gd     #   effect-driven monster movement
│   ├── effect_queries.gd    #   read-only modifier/blocking aggregation
│   └── {ebp01..04,esd01..} # ~270 per-card effect scripts (call the facade)
├── scripts/session/         # GameSession, MultiplayerSync, EffectUIRouter
├── scripts/server/          # Dedicated server (ServerMain, HeadlessBoard)
├── scenes/board/            # Presentation (GameBoard, PlayerBoard, modules)
├── tests/                   # gdUnit4 suites (tests/unit) + fixtures
│   └── run_unit_tests.sh    # Headless test runner (also used in CI)
└── project.godot            # Main project configuration
```

### Logic-layer architecture

- Everything in `scripts/core/` and the effect system is `RefCounted` and
  UI-free; cards are plain Dictionaries.
- **PlayerInput** is the single player-decision port: engine code `await`s
  `input.choose_option(...)`-style calls. `SignalPlayerInput` re-exposes the
  request signals (`choice_requested`, `zone_target_requested`, ...) and
  `resolve_*()` callbacks for UI/RPC/bot; `ScriptedPlayerInput` feeds queued
  answers synchronously in tests. Resolving during the request emit is safe.
- **EffectHandler is a facade**: effect scripts and `EffectContext` call it
  exactly as before; the implementation lives in the modules listed above
  (each holds the facade hub `h` via `EffectModule`).
- **GameEvents** (`turn_manager.events` / `GameSession.events`) carries the
  gameplay notifications previously declared on ActionHandler.
- **RulesEngine** depends only on `EffectQueries` (`rules_engine.queries`),
  stays pure/synchronous — it gates server-side action validation.
- **MatchFactory** owns construction/wiring; TurnManager's `setup`/
  `setup_from_save` delegate to it. TurnManager exposes `flow_state`
  (IDLE / AWAITING_ACTION / PROCESSING_ACTION / ADVANCING_PHASES / GAME_OVER).

## Development Guidelines

### Godot Conventions

- **Scene Organization:** Group related scenes in appropriate folders (e.g., `scenes/cards/`, `scenes/ui/`, `scenes/boards/`)
- **Script Location:** Keep scripts alongside their scenes or in a `scripts/` folder
- **Resource Files:** Store assets in organized folders (`assets/sprites/`, `assets/sounds/`, `assets/fonts/`)
- **Naming:** Use PascalCase for scene files (e.g., `CardBase.tscn`) and snake_case for scripts (e.g., `card_base.gd`)

### Code Style

- Follow Godot's official GDScript style guide
- Use type hints for better code clarity: `var health: int = 100`
- Prefer signals over direct function calls for decoupling
- Document complex functions with comments

### Testing

- Unit tests (gdUnit4): `./tests/run_unit_tests.sh [godot_binary]` — runs
  headless; suites live in `tests/unit/`, fixtures in `tests/fixtures/`
  (hand-built card dicts; no CardData dependency for core tests).
- Per-card effect tests: `tests/unit/effects/cards/` — smoke/consistency
  suite over all effect scripts (incl. trigger_map.gd currency check),
  parameterized cluster suites, and per-set bespoke suites; cluster/bespoke
  membership ledger in `classification.md` there. Real card dicts come from
  `tests/fixtures/real_cards.gd` (`Real.instance(id)` — never use raw
  CardData templates). New/changed card effects need their tests updated;
  the smoke suite fails if trigger_map.gd is stale.
- Bot stress: `godot --headless --path . res://tests/sim/BotSimulationRunner.tscn`
  (set `base_seed` + per-game `[SimResult]` lines enable seed-matched
  behavioral diffs between branches).
- Multiplayer integration: `./tests/harness/run_harness.sh 3 <godot>`
  (greps for DESYNC / SCRIPT ERROR across server + client logs).
- Test scenes in isolation before integrating; create debug scenes for rapid iteration
- Use `@tool` annotation for editor-time scripts when appropriate

## TCG Game Design

### Core Concepts

**Card System:**
- [Document card types, attributes, mechanics]

**Game Board:**
- [Document board zones: deck, hand, play area, discard]

**Turn Structure:**
- [Document phases: draw, main, combat, end]

**Win Conditions:**
- [Document how players win/lose]

### Technical Architecture

**Key Systems to Implement:**
- Card data management (resources/database)
- Deck building system
- Hand management
- Play area/board state
- Combat resolution
- AI opponent (if applicable)
- Networking/multiplayer (if applicable)

## Assets & Resources

**Required Assets:**
- Card artwork and templates
- UI elements (buttons, frames, backgrounds)
- Sound effects and music
- Fonts
- VFX for card plays and effects

## Performance Considerations

- Use object pooling for frequently instantiated cards
- Optimize texture atlases for card artwork
- Consider LOD for 3D elements if used
- Profile regularly with Godot's built-in profiler

## Known Issues & TODOs

- [ ] Initial project setup
- [ ] Design core card mechanics
- [ ] Create card base scene
- [ ] Implement deck system
- [ ] Build game board UI
- [ ] Add turn management system

## External Resources

- [Godot Documentation](https://docs.godotengine.org/)
- [GDScript Style Guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html)

---

**Last Updated:** 2026-06-12
