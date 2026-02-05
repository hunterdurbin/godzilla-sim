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
├── .godot/          # Godot engine files (auto-generated)
├── project.godot    # Main project configuration
└── icon.svg         # Project icon
```

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

- Test scenes in isolation before integrating
- Create debug scenes for rapid iteration
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

**Last Updated:** 2026-02-05
