# 📜 Changelog & Release Notes

All notable changes to **Omniverse** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## 🚀 [v2.1.86] - 2026-07-29

> **Commit**: `fix(release): harden authentication recovery and update delivery`

### 🔐 Mobile OAuth Completion
- **Editable Recovery Credentials**: Android and iOS onboarding always displays and prefills the Trakt Client ID and Client Secret, allowing rejected developer credentials to be corrected without getting trapped behind the sign-in gate.
- **Authoritative Retry Values**: Reconnect attempts use the visible, normalized form values instead of silently falling back to a rejected stored Client ID.
- **Cold-Start Callback Safety**: Android and iOS wait for encrypted credentials to reload before exchanging Trakt's authorization code, preventing successful browser approval from bouncing back to onboarding after the OS restarts the app.
- **Idempotent Initialization**: Mobile state restoration can be requested by both the root UI and an OAuth callback without duplicating credential loads, timers, or refresh work.

### 🍎 Reliable macOS Sideload Updates
- **Uniform Team Identity**: The in-app updater signs every nested Mach-O binary, framework, helper, and application bundle inside-out with the same local Apple identity, preventing dyld from rejecting libraries such as `libffmpeg.dylib`.
- **Electron Runtime Entitlements**: JIT and unsigned-executable-memory permissions are reapplied and verified on the main app and helper executables, preventing V8 from aborting while reserving its code range.
- **Runtime Integrity Gate**: Update staging rejects mixed or missing Team Identifiers and missing Electron entitlements before replacing the installed application—conditions that `codesign --deep --strict` alone does not detect.
- **Installed-App Recovery Verified**: The affected macOS installation was repaired in place, passed strict signature verification, and remained running with its GPU, network, and renderer helpers.

### 🚀 Changelog-Driven Releases
- **One Version Source**: The newest versioned `CHANGELOG.md` heading now stamps Android, iOS, desktop packages, the Git tag, and the GitHub Release name.
- **Dynamic Release Pages**: A tested renderer extracts only the matching changelog section and generates the complete GitHub Release body and installation matrix.
- **Safe Release Updates**: Editing the current changelog section updates the existing release and assets under the same tag; adding a new version section creates the next release.
- **Fail-Closed Notes**: Missing, empty, or mismatched release sections stop publishing instead of showing stale notes from another version.

### 📖 Documentation & Verification
- Added the required post-update macOS command, `xattr -cr /Applications/Omniverse.app`, to the README and generated release instructions.
- Documented the changelog-driven versioning and release-page update workflow for contributors.
- Android unit tests and compilation pass, all Swift sources parse, the non-UI iOS authentication core type-checks, and all 20 desktop tests pass.

---

## 🚀 [v2.1.85] - 2026-07-29

> **Commit**: `fix(auth): make Trakt reauthentication resilient across every platform`

### 🔐 Reliable Trakt Reauthentication
- **Client ID Preflight**: Android, iOS, macOS, Windows, and Linux now verify the configured Trakt Client ID before opening OAuth, replacing Trakt's misleading `invalid_client / client_id is required` page with an actionable in-app explanation.
- **Clipboard-Safe Credentials**: Removes whitespace, line breaks, byte-order marks, and zero-width formatting characters that mobile and desktop clipboards can silently add to Client IDs, secrets, and OAuth tokens.
- **Automatic Session Repair**: Clears rejected, expired, or mismatched user tokens after Trakt returns `400`, `401`, or `403`, while preserving the developer Client ID and Client Secret for a clean reconnect.
- **Fresh Login Guarantees**: A manual Connect or Refresh Login now retires the stale OAuth session before starting its replacement, preventing watchlist and playback sync from looping on invalid authorization.

### 🌍 Native Platform Parity
- **Android Diagnostics**: The existing API verification panel now tests the Trakt Client ID alongside TMDB, TVDB, and Pixeldrain and highlights the exact invalid field.
- **iOS Recovery UX**: Onboarding and Settings preserve Trakt's actionable validation message instead of replacing it with a generic browser-opening error.
- **Desktop OAuth Core**: Adds a packaged, shared Trakt authentication helper for deterministic URL construction, credential normalization, and consistent rejection handling across every Electron desktop target.

### ✅ Authentication Regression Coverage
- Added Android, iOS, and desktop cases for invisible-character cleanup and non-empty, correctly encoded OAuth `client_id`, redirect URI, and state parameters.
- Android unit tests and compilation pass, all 18 desktop tests pass, and the complete Swift source parses with the non-UI iOS authentication core type-checking successfully.

---

## 🚀 [v2.1.83] - 2026-07-29

> **Commit**: `fix(android): preserve the release identity in secure CI builds`

### 🔏 Upgrade-Safe Android Signing
- **Original Identity Only**: Adds a secret-safe exporter that reads and validates the existing ignored keystore; it has no key-generation or rotation mode.
- **Certificate Continuity Pin**: Versions the public signing-certificate SHA-256 so local exports and CI reject a different keystore before an incompatible APK can ship.
- **Paste-Ready GitHub Secrets**: Produces the four required Actions values in a private `0600` file outside the repository without printing credentials to the terminal.
- **Fail-Closed CI**: Restores signing material under `umask 077`, verifies the alias and certificate, and removes the temporary keystore and properties even when a job fails.

### ✅ Release Guardrail Coverage
- **Five Exporter Tests**: Covers exact secret mapping, Base64 fidelity, overwrite refusal, `0600` permissions, malformed properties, certificate-pin validation, and JDK discovery.
- **Signed APK Proof**: Android unit tests, Lint, release assembly, APK signature verification, and certificate-to-pin matching pass with the preserved release identity.
- **Contributor Memory**: Records the direct-distribution signing contract in Graphify so future contributors know that rotating the key strands existing legacy users.

---

## 🚀 [v2.1.82] - 2026-07-29

> **Commit**: `docs(readme): map the codebase with Graphify intelligence`

### 🕸️ Graphify Codebase Intelligence
- **Complexity You Can See**: Adds a dense GitHub-safe topology map covering 2,281 nodes, 5,092 typed relationships, 185 communities, and 119 indexed files.
- **Platform Topology**: Visualizes Apple, Android, desktop, shared services, CI, and contributor knowledge as connected graph zones with real node volumes.
- **Technical Depth**: Surfaces relationship distribution, high-blast-radius domain hubs, extraction confidence, and a direct link to the interactive Graphify explorer.

### 🍎 Reliable Dual-Architecture DMGs
- **True Inside-Out Signing**: Sorts every Mach-O binary and bundle deepest-first so `chrome_crashpad_handler` is signed before its enclosing Electron framework on both Apple Silicon and Intel builds.
- **Installer Integrity Gate**: GitHub Actions now verifies strict application signatures, confirms the expected `arm64` and `x86_64` executables, and validates both DMG checksums before upload.
- **Single Release Publisher**: Disables electron-builder's implicit CI publishing for macOS; the dedicated release job remains the only artifact publisher.

### ✨ Cinematic Mobile Redesign
- **Desktop-Level Atmosphere**: Rebuilt Android and iOS phone/tablet shells with edge-to-edge heroes, floating glass navigation, adaptive rails, refined search, and touch-native details inspired by modern living-room platforms.
- **Native Interaction First**: Preserved SwiftUI and Compose behavior, safe areas, sheets, focus, gestures, typography, and playback conventions while unifying the crimson/cyan visual system.

### 🛡️ Live AdShield Dashboard
- **Telemetry That Actually Moves**: Replaced the broken counter path with a hydrated live snapshot for network filters, blocked popups, stopped navigation hijacks, totals, status, and last interception time.
- **Reliable Protection Pipeline**: AdShield reporting can no longer interrupt blocking when the renderer is absent, and every dashboard update is null-safe.

### 🔐 Security & Update Hardening
- **Zero Known npm Vulnerabilities**: Upgraded to Electron 43 and electron-builder 26, patched vulnerable transitive archive tooling, and verified a signed arm64 package.
- **M-Series Ready Packaging**: Re-signs nested Electron binaries inside-out, applies the required JIT entitlements, and verifies a native arm64 launch for Apple Silicon through M4.
- **Trusted Update Boundaries**: Desktop and Android reject non-HTTPS, off-repository, wrong-type, credential-bearing, query-bearing, and traversal-shaped update URLs.
- **Platform TLS Restored**: Removed Android's trust-all certificate and hostname bypass; iOS now limits ATS exceptions to media, web content, and local networking.
- **Secret-Safe Signing**: Removed Android signing files from source control, added a local template, and moved CI signing to masked repository secrets.
- **Sandboxed Desktop Guests**: Enabled Chromium sandboxing and clamp playback webview preferences before attachment.

### ✅ 49-Test Quality Matrix
- **Desktop**: 15 Node tests covering AdShield, updater rollback/signing, deterministic inside-out bundle ordering, URL trust, IPC protocols, Electron isolation, and tracked-secret detection.
- **Android**: 20 JUnit tests covering navigation, models, sync interoperability, update versions/URLs, filename traversal, streams, and progress edges.
- **iOS**: 14 XCTest cases covering credentials, sync payloads, legacy settings, malformed input, models, streams, and playback overrides.
- **Static Verification**: Android Lint passes with zero errors, Xcode Analyze passes, the full npm audit reports zero vulnerabilities, and both macOS DMGs pass signature and checksum verification.

### 📖 README Showcase
- Replaced oversized hidden galleries and the stretched mobile table with a compact real-app product tour.
- Added cross-preview SVG architecture and quality dashboards plus a corrected GitHub Mermaid experience flow.
- Documented the verified security baseline, release-signing secrets, platform matrix, and reproducible commands.

---

## 🚀 [v2.1.79] - 2026-07-29

> **Commit**: `feat(desktop): ship signed in-app macOS updates with fluid navigation`

### 🍎 Native macOS Update Installation
- **Fully In-App Updates**: macOS release images are now downloaded, mounted, validated, signed, installed, and relaunched entirely inside Omniverse—no external Terminal signing workflow is required.
- **Trusted Release Validation**: The updater accepts only official Omniverse GitHub release DMGs, confirms the bundle identifier and version, and refuses stale or unexpected app bundles.
- **Automatic Apple Identity Signing**: Omniverse discovers a local Apple Development identity first, preserves Electron hardened-runtime entitlements, removes quarantine metadata, and verifies the staged signature before installation.
- **Safe Rollback & Relaunch**: The detached installer keeps a backup, validates the final installed bundle, restores the previous version if copying or launching fails, and records diagnostics in `~/Library/Logs/OmniverseUpdater.log`.

### 📦 Deterministic macOS Packaging
- **Single Signing Authority**: The packaging hook now owns the macOS signing pass, preventing electron-builder and recursive `codesign` operations from racing over sealed Electron frameworks.
- **CI-Compatible Fallback**: Local builds use the available Apple identity, while certificate-free CI runners retain a safe ad-hoc signing fallback.
- **Verified Distribution Bundle**: The packaged arm64 app retains its JIT and unsigned-executable-memory entitlements and validates against its designated requirement.

### 🖱️ Fluid Desktop Navigation & Playback
- **Axis-Locked Scrolling**: Vertical wheel and trackpad gestures continue scrolling the page when hovering over Top 10 and other horizontal rails; native horizontal gestures and Shift+wheel remain available for rail navigation.
- **Stable Scroll Momentum**: Removed competing scripted smooth-scroll animations and contained overscroll at page and rail boundaries.
- **Atomic Player Launch**: Playback now opens through a guarded loading transition so initialization failures stay visible instead of appearing as an unexpected return to the home screen.

### ✅ Reliability Coverage
- Added updater tests for trusted URLs, semantic version ordering, signing identity selection, helper script syntax, rollback behavior, quarantine removal, and explicit relaunch.
- Added packaging-hook coverage for Apple Development and Developer ID Application identity detection.

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
