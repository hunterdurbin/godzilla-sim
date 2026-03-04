# iOS Sideloading Guide

This guide explains how to install the Unofficial Godzilla TCG Sim `.ipa` on your iOS device without an App Store listing.

> **Note:** All methods require a free Apple ID. Apps signed with a free Apple ID expire every **7 days** and must be re-signed.

> **Apple ID Warning:** We strongly recommend creating a **separate Apple ID** specifically for sideloading. Some of these tools require you to enter your Apple ID credentials into third-party software. While these tools are widely used and well-regarded in the sideloading community, they are not affiliated with Apple. Using a dedicated account protects your primary Apple ID in the unlikely event of an account flag or lock.

---

## Quick Install via SideStore Source

If you already have SideStore installed, you can add our source to get the app and future updates automatically:

1. Open this link on your iOS device: `sidestore://source?url=https://hunterdurbin.github.io/godzilla-sim/source.json`
2. Or manually add the source in SideStore: **Browse → Sources → +** and paste:
   ```
   https://hunterdurbin.github.io/godzilla-sim/source.json
   ```
3. Find "Unofficial Godzilla TCG Sim" in the source and tap **Get**

---

## Option 1: SideStore (Recommended)

**Best for:** Users who want to refresh apps on-device without a computer.

SideStore requires a computer (Mac, Windows, or Linux) for the initial install, but after that it runs entirely on your iPhone/iPad. It uses a local WireGuard VPN to re-sign apps without needing a computer again.

### Setup (one-time, requires a computer)

1. Visit [sidestore.io](https://sidestore.io/) and follow the [installation guide](https://docs.sidestore.io/docs/installation/prerequisites)
2. Install SideStore to your device using your computer
3. Install the WireGuard VPN profile (traffic stays local — nothing is sent externally)
4. Enable the WireGuard VPN on your device

### Install the .ipa

1. Download the `.ipa` file to your device (e.g., from Files, Safari, or AirDrop)
2. Open it with SideStore, or tap **+** in SideStore and select the `.ipa`
3. Sign in with your Apple ID when prompted
4. The app will install on your home screen

### Keeping it Active

- Open SideStore and tap **Refresh** before the 7-day window expires
- SideStore can send reminders — no computer needed
- Keep the WireGuard VPN profile active

---

## Option 2: AltStore

**Best for:** Users who have a Mac or PC they keep on the same WiFi as their device.

AltStore can automatically refresh app signatures in the background, but requires AltServer running on a computer.

### Setup

1. Download AltServer on your Mac or PC from [altstore.io](https://altstore.io/)
2. Run AltServer on your computer
3. Connect your iPhone/iPad via USB (first time only)
4. Install AltStore to your device through AltServer

### Install the .ipa

1. Transfer the `.ipa` to your device or open it from Files
2. Open the `.ipa` with AltStore
3. Sign in with your Apple ID when prompted
4. The app will install on your home screen

### Keeping it Active

- Keep AltServer running on your Mac/PC on the same WiFi network
- AltStore auto-refreshes apps in the background
- If auto-refresh fails, open AltStore and tap Refresh manually

---

## Option 3: Sideloadly

**Best for:** Quick one-time installs from a computer. No app to install on your device first.

Sideloadly is a desktop app that installs `.ipa` files directly to your device via USB.

### Setup

1. Download Sideloadly from [sideloadly.io](https://sideloadly.io/) (Mac or Windows)
2. Install and open it on your computer

### Install the .ipa

1. Connect your iPhone/iPad via USB
2. Drag the `.ipa` file into Sideloadly
3. Enter your Apple ID and password
4. Click Start — the app installs on your device
5. On your device, go to **Settings → General → VPN & Device Management** and trust your Apple ID profile

### Keeping it Active

- You must repeat the install process from your computer every 7 days
- There is no auto-refresh — connect and re-sideload when the app expires

---

## Troubleshooting

### "Untrusted Developer" error on first launch

Go to **Settings → General → VPN & Device Management**, find your Apple ID profile, and tap **Trust**.

### App crashes immediately after install

Make sure your device is running iOS 15 or later.

### App stops opening after 7 days

The free signing certificate has expired. Re-sign the app using whichever method you chose above.

### "Maximum number of apps" error

Free Apple IDs can only sideload **3 apps** at a time. Remove a sideloaded app to make room.

---

## Comparison

|                     | SideStore                             | AltStore                            | Sideloadly                              |
| ------------------- | ------------------------------------- | ----------------------------------- | --------------------------------------- |
| Computer needed     | First setup only                      | Always (same WiFi)                  | Every 7 days                            |
| Auto-refresh        | On-device (manual tap)                | Background (automatic)              | None                                    |
| Max sideloaded apps | 3                                     | 3                                   | 3                                       |
| Platform            | iOS                                   | Mac/PC + iOS                        | Mac/PC                                  |
| Website             | [sidestore.io](https://sidestore.io/) | [altstore.io](https://altstore.io/) | [sideloadly.io](https://sideloadly.io/) |
