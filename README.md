# macSteam

<p align="center">
  <strong>Native Steam unlock client for Apple Silicon (ARM64) macOS with full CrossOver Steam, Game Fixes (Online-Fix), and CloudRedirect integration.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13.0%2B-000000?style=flat&logo=apple&logoColor=white" alt="macOS 13+" />
  <img src="https://img.shields.io/badge/Architecture-Apple%20Silicon%20(ARM64)-blue?style=flat" alt="Apple Silicon Only" />
  <img src="https://img.shields.io/badge/Version-0.7.1-brightgreen?style=flat" alt="Version 0.7.1" />
  <img src="https://img.shields.io/badge/Languages-FR%20%7C%20EN-orange?style=flat" alt="FR | EN" />
  <img src="https://img.shields.io/badge/License-AGPLv2-lightgrey?style=flat" alt="AGPLv2" />
</p>

> [!IMPORTANT]
> **Apple Silicon only (M1 / M2 / M3 / M4).** Intel Macs (`x86_64`) are **not** supported.

---

## Table of Contents

- [Overview](#overview)
- [Key Features](#key-features)
  - [Discovery & Library Management](#discovery--library-management)
  - [CrossOver Steam (Windows Games on macOS)](#crossover-steam-windows-games-on-macos)
  - [Game Fixes & Online-Fix](#game-fixes--online-fix)
  - [CloudRedirect (Cloud Saves)](#cloudredirect-cloud-saves)
  - [Steam Plugin (CEF Store Injection)](#steam-plugin-cef-store-injection)
  - [Install, Repair & Settings](#install-repair--settings)
- [How It Works](#how-it-works)
- [Quick Start](#quick-start)
- [Building from Source](#building-from-source)
- [Quick Troubleshooting](#quick-troubleshooting)
- [Credits & License](#credits--license)

---

## Overview

**macSteam** is a complete macOS (Apple Silicon) ecosystem made of two components:

1. **`macsteam.dylib`**: a native ARM64 library injected into Steam for macOS that handles game ownership unlocking, license/manifest injection, and achievement schema fetching.
2. **`macSteam Config.app`**: a native macOS companion app (Swift / AppKit, bilingual **French / English**) that centralizes game search, `.lua` and `.manifest` management, game fixes (Online-Fix / bypasses), automated **CrossOver Steam** setup, and cloud save synchronization via **CloudRedirect**.

---

## Key Features

### Discovery & Library Management

| Module | Description |
| :--- | :--- |
| **Home** | Dashboard showing macSteam status, library overview, and quick actions. |
| **Search & Add** | Direct search across the Steam catalog & LuaTools API with game details, reviews, and one-click `.lua` / `.manifest` installation. |
| **ZIP / Lua Import** | Drag-and-drop `.zip` archives or `.lua` files with automatic manifest mirroring to both macOS Steam and CrossOver Steam bottles. |
| **My Games** | Manage unlocked games, inspect metadata, and remove entries cleanly. |
| **Builds** | Browse and manage game builds and depots. |
| **Downloads** | Built-in download queue to monitor manifest and game fix downloads. |

### CrossOver Steam (Windows Games on macOS)

macSteam provides a turnkey bridge to play **Windows** games through **CrossOver** with zero manual configuration:

- **One-Click BetterSteamTools Setup**: automatically downloads and deploys `OpenSteamTool.dll`, `dwmapi.dll`, `xinput1_4.dll`, and `opensteamtool.toml` into your CrossOver bottle.
- **Smart Bottle Priority**: detects CrossOver bottles containing Steam and always prioritizes the main `Steam` bottle over single-game bottles.
- **Automatic Wine DLL Overrides**: configures `dwmapi` and `xinput1_4` for `steam.exe` plus default Online-Fix overrides (`OnlineFix64`, `SteamOverlay64`, `steam_api64`, `dnet`, `winmm`) in `user.reg`, with **live registry injection** via `wine reg add` whenever `wineserver` is already running.
- **Automatic Sync & Cache Refresh**: syncs `.lua` and `.manifest` files between macOS Steam and CrossOver Steam, and automatically clears stale `appcache/packageinfo.vdf` and `appcache/appinfo.vdf` on sync/restart so newly added games appear right away.
- **Anti-Conflict Protection**: launching either macOS Steam or CrossOver Steam from macSteam automatically closes the other client to prevent session collisions (*"No Connection"* / `0 B` stuck downloads).

### Game Fixes & Online-Fix

- **Multi-Library Detection**: automatically locates installed games across both **native macOS Steam** and **CrossOver Steam** libraries.
- **Safe Apply & Rollback**: extracts and applies fix archives (Online-Fix, bypasses) while automatically backing up modified files for **one-click revert**.
- **Automatic Wine Configuration**: registers both default and per-executable DLL overrides in your CrossOver bottle (on disk and live in `wineserver`).

### CloudRedirect (Cloud Saves)

Native **CloudRedirect** integration inside `macSteam Config.app` to sync Steam Cloud saves for unlocked games across macOS, CrossOver, and Windows:

- **Multi-Provider Support**: works with **Google Drive**, **Dropbox**, **OneDrive**, **WebDAV**, and local folders.
- **Native OAuth Sign-In**: seamless macOS OAuth flow with an owner-only (`0600`) macOS credential mirror that stays intact even when Wine DPAPI re-encrypts tokens inside CrossOver.
- **Save Browser & Controls**: inspect remote saves per game, trigger manual backups/restores, and monitor live sync logs.

### Steam Plugin (CEF Store Injection)

- **In-Store Controls**: injects macSteam buttons directly into Steam's Store UI using the Chrome DevTools Protocol (CDP).
- **Battery Friendly**: fully event-driven (`NSWorkspace` lifecycle observers + persistent CDP WebSocket) with **0 CPU wakeups/sec** when idle.

### Install, Repair & Settings

- **One-Click Deployment**: installs and injects `macsteam.dylib` into `Steam.app`.
- **Built-in Repair Tool**: verifies installation health and repairs Steam or macSteam in one click after major Steam client updates.
- **Automatic Updates**: integrated **Sparkle** auto-updater.
- **Bilingual UI**: instant switching between **English** and **French**.

---

## How It Works

1. **`macSteam Config.app`** deploys `macsteam.dylib` into `Steam.app` (and `OpenSteamTool.dll` into your CrossOver bottle when using CrossOver Steam).
2. On macOS Steam launch, `macsteam.dylib` is loaded and injects the licenses defined in your `.lua` files.
3. Missing manifests are fetched automatically from OpenSteamTool / LuaTools-compatible endpoints.
4. Configuration and user data are stored in:
   ```text
   ~/Library/Application Support/macsteam/
   ```

---

## Quick Start

1. Download the latest release from the [Releases page](https://github.com/ZoraxxHD/macSteam/releases).
2. Unzip the archive and move **`macSteam Config.app`** into `/Applications`.
3. Open **`macSteam Config.app`**, go to the **Install** tab, and click **Install**.
4. Approve the macOS TCC permission prompt allowing `macSteam Config` to modify the Steam app bundle.
5. *(Optional — Windows Games)* Open the **CrossOver Steam** tab and click **Install** to automatically configure your CrossOver Steam bottle.

---

## Building from Source

### Requirements

- **Apple Silicon (ARM64)** Mac running **macOS 13.0+**
- **Xcode Command Line Tools** / **Swift 6.0+**

### 1. Build the dylib (`macsteam.dylib`)

```bash
make rebuild
```

### 2. Build and package `macSteam Config.app`

```bash
cd macsteam-app
bash make_app.sh
```

The ad-hoc signed app bundle is generated at `macsteam-app/macSteam Config.app`. To install it into `/Applications`:

```bash
rm -rf "/Applications/macSteam Config.app"
cp -R "macSteam Config.app" "/Applications/macSteam Config.app"
```

> [!NOTE]
> The repository also includes an experimental launcher in `launcher/` that does not modify the `Steam.app` bundle (provided as an experiment only).

---

## Quick Troubleshooting

- **A newly added game does not appear in CrossOver Steam**: check that the **CrossOver Steam** tab shows **Configured ✓**, then click **Restart CrossOver Steam** (which syncs `.lua` files and clears `appcache/packageinfo.vdf` & `appinfo.vdf`). Also make sure the *"Ready to Play"* filter is turned off in Steam's Library.
- **A CrossOver game is capped below Retina resolution**: in CrossOver, select your **Steam** bottle, enable **High Resolution Mode**, and restart CrossOver Steam.
- **Downloads stuck at `0 B` or *"No Connection"***: make sure only one Steam client (macOS **or** CrossOver) is running at a time — launching Steam from `macSteam Config.app` handles this automatically.

---

## Credits & License

- Original macSteam project by [Selectively11](https://github.com/Selectively11/macsteam).
- CrossOver integration powered by [BetterSteamTools / OpenSteamTool](https://github.com/madoiscool/BetterSteamTools).
- Cloud save synchronization based on [CloudRedirect](https://github.com/Selectively11/CloudRedirect).
- Achievement schema fetcher inspired by [SLSSteam](https://github.com/AceSLS/SLSsteam).

Licensed under **AGPLv2** — see [`LICENSE`](LICENSE) for full terms.
