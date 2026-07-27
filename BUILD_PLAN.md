# Omniverse — Native Rewrite Build Plan

Two **fully native** apps reimplementing the Flutter `omniplay` app (20,366 LOC) with feature parity:

- **iOS** — SwiftUI, vivid glassmorphism, Apple-TV-inspired. `native/ios/`
- **Android** — Kotlin + Jetpack Compose + Compose-for-TV (phones, tablets, Android TV), sleek/minimal. `native/android/`

App name **Omniverse**, bundle id **com.finix.omniverse** on both.
Source of truth = the Dart files in `../lib/src/` (read them for exact logic).

## Hard requirements
- Max/ProMotion refresh rate (iOS: `CADisableMinimumFrameDurationOnPhone` + `maximumFramesPerSecond`; Android: `WindowManager` preferred display mode / `Surface.setFrameRate`).
- Keep screen on while playing (iOS: `isIdleTimerDisabled`; Android: `FLAG_KEEP_SCREEN_ON`).
- Dynamic screen size + orientation on every device.
- Android: one universal signed APK, keystore `native/keystore/omniverse-release.jks` (alias `omniverse`, pass `Omniverse@2026`, CN=Finix C=IN, 10000-day validity).
- iOS install target device: `00008142-0008181C0E11401C`.

## Subsystems (parity targets) — see Dart source for exact constants
- TMDB (dual auth: Bearer if token starts `ey`, else `api_key`), TVDB v4 (login+pin→token), Trakt (web OAuth `omniplay://trakt/oauth`, device-code, refresh; scrobble; Base64(JSON) settings backup in a private list named "Omniplay Sync").
- VidSrc: embed list + `embed/movie|tv`; extractor chain embed→`/rcp/{hash}`→`/prorcp/`→`file:'...'` m3u8; WebView Turnstile resolution (vidsrc_resolve).


- Live TV: iptv-org json+m3u, yarrlist scrape, tv247.biz, HEAD-probe scanning.
- Player: AVPlayer/ExoPlayer, scrobble thresholds (start on play, pause on pause, stop at complete/100%), 10s progress record, 12s stall recovery, AniSkip auto-skip, .ass/vtt captions, audio/sub sheets, drag-to-dismiss.

## Status
- [x] Full codebase read & specced
- [x] Toolchain (Xcode 26.5, JBR21, xcodegen, gradle 9.4, adb, devicectl)
- [x] Android release keystore generated
- [~] iOS foundation: design system, models, storage, networking, device tuning
- [ ] iOS repositories, AppState, screens, build+install
- [ ] Android app
