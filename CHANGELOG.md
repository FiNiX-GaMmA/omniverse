# 📜 Changelog & Release Notes

All notable changes to **Omniverse** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## 🚀 [v2.1.5] - 2026-07-28

> **Commit**: `d625c50` — `feat(auth): standardize Trakt API integration and sanitize OAuth credentials across platforms`

### 🔑 Authentication & Trakt API Standardization
- **Unified Trakt HTTP Headers**: Enforced standard Trakt headers (`trakt-api-version: 2`, `trakt-api-key`, and `User-Agent: Omniverse/2.1`) across Desktop, Android, and iOS for all endpoints including OAuth exchange, device authentication, token refresh, pull, and push.
- **Robust OAuth Code Extraction**: Implemented regular expression regex matching on Android and iOS to extract clean authorization tokens when raw deep-link callback strings containing `code=...` are received.
- **Whitespace & Token Sanitization**: Applied strict `.trim()` string sanitization to client IDs, client secrets, and access tokens across JS (`renderer.js`), Kotlin (`TraktRepositoryImpl.kt`), and Swift (`TraktRepository.swift`) to eliminate authentication failures caused by trailing/leading whitespace.

### 📱 iOS & Desktop Core Improvements
- **Media Models**: Added default `source` field (`"tmdb"`) to `MediaItem` struct in `Models.swift`.
- **Unit Test Fixes**: Corrected constructor syntax errors in `NavStateTests.swift` (`id = "1"` -> `id: "1"`).

### 🎨 Android UI & Layout Enhancements
- **Jetpack Compose**: Added `BoxWithConstraints` import to `HomeScreen.kt` to lay foundation for adaptive dynamic container layouts.

---

## 📦 Impacted Components & Files

| Component | Target File | Type | Changes Description |
| :--- | :--- | :---: | :--- |
| **Desktop** | [`desktop/renderer.js`](file:///c%3A/Users/the-geeky-couldron/Documents/GitHub/omniverse/desktop/renderer.js) | ⚡ Fix | Standardized Trakt API headers & added token string trimming |
| **Android** | [`android/app/src/main/java/com/finix/omniverse/TraktRepositoryImpl.kt`](file:///c%3A/Users/the-geeky-couldron/Documents/GitHub/omniverse/android/app/src/main/java/com/finix/omniverse/TraktRepositoryImpl.kt) | ⚡ Fix | OAuth regex code parsing, header uniformity & credential sanitization |
| **Android** | [`android/app/src/main/java/com/finix/omniverse/ui/HomeScreen.kt`](file:///c%3A/Users/the-geeky-couldron/Documents/GitHub/omniverse/android/app/src/main/java/com/finix/omniverse/ui/HomeScreen.kt) | ✨ Feature | Jetpack Compose dynamic constraints import |
| **iOS** | [`ios/Omniverse/Repositories/TraktRepository.swift`](file:///c%3A/Users/the-geeky-couldron/Documents/GitHub/omniverse/ios/Omniverse/Repositories/TraktRepository.swift) | ⚡ Fix | Robust OAuth code parsing & header consistency |
| **iOS** | [`ios/Omniverse/Models/Models.swift`](file:///c%3A/Users/the-geeky-couldron/Documents/GitHub/omniverse/ios/Omniverse/Models/Models.swift) | ✨ Feature | Added `source` property to `MediaItem` |
| **iOS** | [`ios/OmniverseTests/NavStateTests.swift`](file:///c%3A/Users/the-geeky-couldron/Documents/GitHub/omniverse/ios/OmniverseTests/NavStateTests.swift) | 🛠️ Test | Fixed test initializer parameter syntax |

---

## 🌟 Previous Releases

### 🚀 [v2.1.0] - Enterprise Release
- **Cross-Platform Parity**: Unified Trakt & AniList synchronization across Desktop, Android, and iOS.
- **Liquid-Glass Design**: Ultra-premium space black aesthetics with floating translucent pills and ProMotion 120Hz support.
- **OTA Updates**: Direct check against GitHub releases API with progress indicator and animated installer launcher.
