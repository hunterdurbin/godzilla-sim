# Unofficial Godzilla Sim

A fan-made Godzilla Trading Card Game simulator built with Godot 4.6.

> **Disclaimer:** This project is for education and learning purposes. This project is not to be used for official tournament play or similar use. All Rights Reserved. This is a fan-made simulator. Godzilla and the Godzilla Card Game are trademarks or registered trademarks of Toho Co., Ltd.

## Running the Game

[Download the latest release](https://github.com/hunterdurbin/godzilla-sim/releases/latest) for your platform and run it. Since the game is not code-signed, your operating system may show a security warning on first launch.

### Windows

Windows SmartScreen may display a warning:

> **Windows protected your PC** — Microsoft Defender SmartScreen prevented an unrecognized app from starting.

To run the game:

1. Click **More info**
2. Click **Run anyway**

This warning is normal for indie software that isn't code-signed. It will appear less frequently as more users run the app.

### macOS

macOS Gatekeeper may display a warning:

> **"Unofficial Godzilla Sim" can't be opened because Apple cannot check it for malicious software.**

To run the game:

1. Open **System Settings** → **Privacy & Security**
2. Scroll down — you'll see a message about the blocked app
3. Click **Open Anyway**
4. Enter your password when prompted

Alternatively, you can right-click (or Control-click) the app and select **Open** from the context menu, then click **Open** in the dialog.

### Linux

The downloaded binary may not have execute permission. To fix this, open a terminal and run:

```bash
chmod +x ./UnofficialGodzillaSim.x86_64
./UnofficialGodzillaSim.x86_64
```

Alternatively, a Flatpak is available. Download the `.flatpak` file from the [latest release](https://github.com/hunterdurbin/godzilla-sim/releases/latest) and install it:

```bash
flatpak install ./UnofficialGodzillaSim.flatpak
```

### Android

Android requires sideloading since the app is not available on the Google Play Store.

#### Enable sideloading

1. Open **Settings** → **Apps** (or **Settings** → **Security** on older devices)
2. Enable **Install unknown apps** (or **Unknown sources**) for your browser or file manager
   - On Android 8+, this is per-app: find the app you'll use to open the APK (e.g., Chrome, Files) and toggle **Allow from this source**

#### Install the APK

1. Download the `.apk` file from the [latest release](https://github.com/hunterdurbin/godzilla-sim/releases/latest) on your device
2. Open the downloaded `.apk` file (check your notifications or the Downloads folder)
3. Tap **Install** when prompted
4. If Google Play Protect shows a warning ("Blocked by Play Protect" or "Unknown developer"), tap **More details** → **Install anyway**
5. Once installed, open the app from your app drawer

### iOS

iOS requires sideloading since the app is not available on the App Store. See the [iOS Sideloading Guide](docs/ios-sideloading.md) for detailed instructions on installing the `.ipa` using SideStore, AltStore, or Sideloadly.

## Development

**Engine:** Godot 4.6 · **Language:** GDScript · **Renderer:** GL Compatibility

### Running from Source

1. Install [Godot 4.6](https://godotengine.org/download/)
2. Clone this repository
3. Open the project in Godot
4. Press F5 to run

### Project layout

Every subsystem directory contains a `README.md` documenting it — start at
[scripts/README.md](scripts/README.md) (logic layer) and
[scenes/README.md](scenes/README.md) (presentation layer).

| Dir | What lives there |
|---|---|
| `scripts/` | Logic layer: pure match engine (`core/`), per-card effects (`effects/`), card database (`cards/`), bot AI (`bot/`), session/multiplayer glue (`session/`), dedicated server (`server/`), transport (`net/`), replays/saves (`replay/`), audio, app services, settings |
| `scenes/` | Presentation: game board (`board/`), cards/deck/slots, app screens (`menus/`), multiplayer lobbies (`lobby/`), deck builder, replay viewer |
| `tests/` | All test tiers: gdUnit4 unit suites, multiplayer harness, bot-sim — see [tests/README.md](tests/README.md) |
| `assets/` | Art/audio/fonts in snake_case domain buckets |
| `translations/` | en/ja localization CSVs + generator |
| `data-free zones` | `docs/` (cross-cutting docs + architecture graphs), `comprehensive_rules/` (official rules PDF), `deploy/`, `flatpak/` (packaging) |

### Testing

```bash
# Unit tests (gdUnit4, also run by CI):
./tests/run_unit_tests.sh <godot-binary>

# Multiplayer integration harness (server + 2 headless clients, desync grep):
./tests/harness/run_harness.sh 3 <godot-binary>

# Bot self-play simulation:
<godot-binary> --headless --path . res://tests/sim/BotSimulationRunner.tscn
```
