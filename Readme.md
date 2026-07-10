# DolphiniOS (bward-dev1 Fork)

A fork of [OatmealDome's DolphiniOS](https://github.com/OatmealDome/dolphin-ios) that adds several iOS-specific features, quality-of-life improvements, and new functionality while staying closely aligned with upstream.

---

## ✨ Features

### 🎯 Wii Motion Calibration

Built-in tools for accurate Wii pointer controls.

- **Calibrate Gyroscope** – Place your device flat on a surface to eliminate gyroscope drift.
- **Calibrate Gyroscope for TV** – Point your device at your TV to recenter the Wii pointer.

These tools also fix multiple issues in the upstream iOS motion input pipeline, resulting in significantly more accurate and reliable motion controls.

---

### 🎨 Controller Skins

Completely customize the on-screen touch controller using your own PNG artwork.

Place skins in:

```text
Skins/<Skin Name>/
```

Features include:

- Automatic fallback to the default artwork for any missing images.
- One-tap creation of a starter skin using the current controller artwork.
- Partial skins are fully supported, allowing you to replace only the images you want.

---

### 🌐 NetPlay

Play GameCube and Wii games online with friends directly from iOS.

Supported features include:

- Traversal Server host codes
- Direct IP connections
- UPnP
- Live lobby
- Player list
- Built-in chat

Every player must have their own copy of the game, as Dolphin's NetPlay synchronizes emulator state rather than streaming gameplay.

---

### 📱 Remote Controller (DSU)

Turn a second iPhone or iPad into a wireless Wii controller over your local Wi-Fi network.

The host device runs the game while the second device sends button presses and motion data using Dolphin's CemuHook-compatible DSU protocol.

The controller device:

- Does **not** need the game ROM.
- Does **not** emulate the game.
- Requires very little processing power.
- Only needs to be connected to the same local network as the host.

#### Host Setup

```text
Settings → Controllers → Remote Controller (DSU)
```

#### Controller Setup

```text
Play Together… → Remote Controller Mode…
```

---

### 🌈 Rainbow App Icon

Includes an alternate app icon featuring the classic DolphiniOS dolphin with a vertical rainbow gradient while preserving the original silhouette.

---

## 🚀 Getting an IPA

Every commit is automatically built using GitHub Actions on GitHub-hosted macOS runners.

No Mac, Apple Developer account, Xcode installation, or code-signing setup is required to obtain an installable build.

### Trigger a Build

Using GitHub CLI:

```sh
gh workflow run build.yml --ref <branch>
```

Or from the GitHub website:

1. Open the **Actions** tab.
2. Select the **Build** workflow.
3. Choose the latest successful run.
4. Download the workflow artifact.
5. Extract the downloaded ZIP.

The archive contains:

- `Non-Jailbroken.ipa`
- `TrollStore.tipa`
- Rootful jailbreak `.deb`
- Rootless jailbreak `.deb`

Install whichever package matches your device using:

- SideStore
- LiveContainer
- SideStore + LiveContainer Bundle
- TrollStore
- Sileo or Zebra (for jailbreak packages)

---

## 🛠️ Building Locally

### Requirements

- macOS Big Sur 11.3 or later
- Xcode 13 or newer
- Homebrew (or another package manager)

Install the required tools:

```sh
brew install cmake ninja bartycrouch
```

Before building, you'll need to configure your own bundle identifier and Apple Developer Team ID.

### Bundle Identifier

Edit:

```text
Project/Config/BundleIdentifier.xcconfig
```

Replace:

```text
use.your.own.organization.identifier
```

with a unique reverse-domain identifier.

### Development Team

Edit:

```text
Project/Config/DevelopmentTeam.xcconfig
```

Replace:

```text
your-team-id
```

with your Apple Developer Team ID.

Once configured, open:

```text
Source/iOS/App/DolphiniOS.xcodeproj
```

and build using Xcode.

---

## 📚 Upstream Documentation

This fork stays closely synchronized with the official Dolphin and DolphiniOS projects.

For additional documentation, including:

- System requirements
- Building on Windows, Linux, macOS, and Android
- Command-line options
- DolphinTool
- Emulator documentation
- Development information

see:

- **Dolphin:** https://github.com/dolphin-emu/dolphin
- **DolphiniOS:** https://github.com/OatmealDome/dolphin-ios
- **Official Documentation:** https://dolphin-emu.org/docs/

---

## ❤️ Credits

- **DolphiniOS** by OatmealDome
- **Dolphin Emulator Project** and its contributors
- Additional features and improvements by **bward-dev1**
