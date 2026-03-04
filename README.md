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

**Engine:** Godot 4.6
**Language:** GDScript
**Renderer:** GL Compatibility

### Running from Source

1. Install [Godot 4.6](https://godotengine.org/download/)
2. Clone this repository
3. Open the project in Godot
4. Press F5 to run
