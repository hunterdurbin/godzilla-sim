# Unofficial Godzilla Sim

A fan-made Godzilla Trading Card Game simulator built with Godot 4.6.

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

## Development

**Engine:** Godot 4.6
**Language:** GDScript
**Renderer:** GL Compatibility

### Running from Source

1. Install [Godot 4.6](https://godotengine.org/download/)
2. Clone this repository
3. Open the project in Godot
4. Press F5 to run
