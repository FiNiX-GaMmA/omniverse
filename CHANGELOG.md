# 📜 Changelog & Release Notes

All notable changes to **Omniverse** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## 🚀 [v2.1.78] - 2026-07-28

> **Commit**: `fix(desktop): prevent play button redirect loop by isolating player webviews and locking main frame navigation`

### 🎥 Player Webview Isolation & Frame Navigation Security
- **Electron Webview Recovery**: Replaced hardcoded `useElectronWebview = false` in [`desktop/renderer.js`](file:///c%3A/Users/the-geeky-couldron/Documents/GitHub/omniverse/desktop/renderer.js#L2655) with dynamic Electron environment detection. Movie, TV show, and anime stream embeds now run inside an isolated `<webview partition="persist:player">` container rather than a raw `<iframe>`.
- **Top-Level Hijack Defusal**: Isolated `window.top` inside the `<webview>` context so cross-origin stream providers and ad scripts cannot execute top-level navigation hijacks (`top.location = ...`).
- **Iframe Sandbox Fallback**: Enforced `sandbox="allow-scripts allow-same-origin allow-forms allow-presentation allow-media-type"` on `<iframe>` web fallbacks, explicitly omitting `allow-top-navigation`.
- **Main Window Shell Lock**: Updated `mainWindow.webContents.on("will-navigate")` in [`desktop/main.js`](file:///c%3A/Users/the-geeky-couldron/Documents/GitHub/omniverse/desktop/main.js#L187) to prevent all top-level window navigation attempts away from the initialized SPA shell, eliminating the issue where clicking PLAY reloaded `index.html` and returned the user to the homepage.

---

## 🚀 [v2.1.77] - 2026-07-28

> **Commit**: `feat(sync): restore Desktop Continue Watching shelf, simplify Trakt last-seen sync, and update release logs`

### 📺 Desktop Continue Watching Shelf
- **Restored Home Shelf**: Added `#continue-watching-section` and `#grid-continue-watching` markup back into [`desktop/index.html`](file:///c%3A/Users/the-geeky-couldron/Documents/GitHub/omniverse/desktop/index.html#L175-L188) above Trending Movies.
- **Responsive Card Rail**: Applied `shrink-0 w-44` styling to Continue Watching cards in [`desktop/renderer.js`](file:///c%3A/Users/the-geeky-couldron/Documents/GitHub/omniverse/desktop/renderer.js#L4968) for smooth horizontal scrolling.

### 🔄 Simplified Continue Watching & Multi-Device Trakt Sync
- **Vidsrc Timestamp Delegation**: Removed strict millisecond timestamp / position fraction checks in `recordProgress()` across Android (`AppState.kt`), iOS (`AppState.swift`), and Desktop (`renderer.js`). Media items and episodes are now recorded as "last seen" immediately when played (since Vidsrc embeds manage exact playback timestamps internally).
- **Cross-Device Sync**: Automatically triggers background Trakt list sync (`syncSettingsToTrakt` / `pushToTrakt`) and QR pairing state updates so Continue Watching items stay synchronized across all devices connected to the same Trakt Client ID or account.

### 🛡️ Trakt 403 Error Muting & Disconnect Purge
- **Eliminated 10s Error Toast Loop**: Muted background exception toasts on 401, 403, 409, and 429 Trakt scrobble responses across Android, iOS, and Desktop.
- **Scrobble Auto-Pause**: Player tickers on Android and iOS now automatically pause active scrobble requests when a remote scrobble call returns non-200.
- **Complete Credential Reset**: Updated `disconnectTrakt()` across Desktop, Android, and iOS to clear `traktClientId` and `traktClientSecret` in state and persistent storage, restoring clean onboarding input fields.

---

## 🚀 [v2.1.76] - 2026-07-28

> **Baseline Release**: `v2.1.76 Release`

- **Authentication Standardization**: Standardized Trakt HTTP headers (`trakt-api-version: 2`, `trakt-api-key`, `User-Agent`) across Desktop, Android, and iOS.
- **OAuth Extraction**: Added regex extraction for raw `code=...` deep-link authorization callbacks and string whitespace sanitization.

---

## 📦 Impacted Components & Files

| Component | Target File | Type | Changes Description |
| :--- | :--- | :---: | :--- |
| **Desktop Main** | [`desktop/main.js`](file:///c%3A/Users/the-geeky-couldron/Documents/GitHub/omniverse/desktop/main.js) | 🐛 Fix | Locked `will-navigate` on top-level window to prevent embed redirects |
| **Desktop Renderer** | [`desktop/renderer.js`](file:///c%3A/Users/the-geeky-couldron/Documents/GitHub/omniverse/desktop/renderer.js) | 🐛 Fix | Restored Electron `<webview>` isolation & set iframe sandboxing |

---

## 🌟 Previous Releases

### 🚀 [v2.1.0] - Enterprise Release
- **Cross-Platform Parity**: Unified Trakt & AniList synchronization across Desktop, Android, and iOS.
- **Liquid-Glass Design**: Ultra-premium space black aesthetics with floating translucent pills and ProMotion 120Hz support.
- **OTA Updates**: Direct check against GitHub releases API with progress indicator and animated installer launcher.
