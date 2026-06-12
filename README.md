# <p align="center"><img src="assets/branding/omniplay_icon_1024.png" alt="Omniverse Logo" width="120" height="120"/><br>Omniverse</p>

<p align="center">
  <strong>The ultimate, ultra-premium media companion app for your iOS, iPadOS, Android, and Android TV devices. Completely native, blazing fast, and privately yours.</strong>
</p>

<p align="center">
  <a href="https://kotlinlang.org"><img src="https://img.shields.io/badge/Language-Kotlin%20%7C%20Swift-7F52FF?style=for-the-badge&logo=kotlin&logoColor=white" alt="Kotlin & Swift" /></a>
  <a href="#platforms"><img src="https://img.shields.io/badge/UI-Jetpack%20Compose%20%7C%20SwiftUI-E3008C?style=for-the-badge" alt="UI" /></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-4fc921?style=for-the-badge" alt="License" /></a>
</p>

---

## 🌟 What is Omniverse?

**Omniverse** is an elegant, high-fidelity native media player and discovery center redesigned from the ground up to run directly on your hardware. Unlike clunky, slow web-wrapped apps, Omniverse is **100% pure native code** (Kotlin for Android/Android TV and Swift for iOS/iPadOS). It opens instantly, glides at a silky-smooth **120Hz**, and integrates deeply with your system’s video pipeline.

No trackers, no central servers, and completely open source. Your watch history, accounts, and playlists are encrypted and synchronized peer-to-peer or backed up privately to your personal account.

---

## ✨ Premium Features You’ll Love

### ☁️ 1. Zero-Config 1-Second Sync (No Server, Fully Private)
*   **Instant Setup**: Signed in on your iPad and want to move to your Android phone? Just go to Settings, tap **Show Sync QR**, and scan it on your phone.
*   **Total Cloud Sync**: Your Trakt account, API keys, lists, and watch history are instantly copied and signed in.
*   **No Central Server**: Because everything is handled in a secure, peer-to-peer-like Base64 package encoded directly in the QR code, your keys are never stored on any third-party servers.

### ⏱️ 2. Netflix-Style Next Episode Countdown
*   **Smooth Transitions**: In the video player, when there are less than 10 seconds remaining, a premium card slides in.
*   **Interactive Ring**: Watch a gorgeous circular countdown ring drain in real-time. 
*   **Auto-Play**: Tap the card or click it with your Android TV D-pad to start the next episode immediately, or wait for the countdown to hit zero and let it autoplay!

### 🍿 3. Clean "Continue Watching" Shelf
*   **No Clutter**: Unlike other apps that list separate entries for every single episode you watched, Omniverse groups progress by show.
*   **One Card Per Show**: You'll see exactly one card for *"Attack on Titan"* or *"Inception"*, showing your latest watched episode badge. Tap it, and it resumes exactly from where you paused!

### 🔄 4. Silky 120Hz Fluid Rendering & Landscape-Lock
*   **Silky Smooth**: Supports Apple ProMotion and Android high-refresh displays to render animations, transitions, and sliders at a beautiful, stutter-free **120 frames per second**.
*   **Landscape Lock**: Tired of the video rotating back and forth when you lie down? The video player locks strictly into Landscape mode no matter how you hold your device, and restores your standard settings automatically when you exit.

### 🏴‍☠️ 5. Dedicated "One Pace" & Anime Support
*   **One Pace Integration**: Automatically scrapes and resolves One Pace arcs, mapping them to standard episode indexes seamlessly.
*   **Auto-Skip Intros & Outros**: Features deep **AniSkip integration** to automatically skip intro scenes, recaps, and endings.
*   **Pro Subtitles & Dual Audio**: Supports complex `.ass` subtitle files and dual-audio (Japanese subbed/English dubbed) stream switching natively.

### 📺 6. Real Android TV Leanback Support
*   **TV Parity**: A gorgeous, dedicated layout designed for your TV screen. Focus halos, scale-up highlights, and full native support for your Android TV remote/D-pad.

---

## 🚀 Easy One-Click Real Device Installers

We have crafted smart, fully-automated deployment scripts that build and install the application directly onto your connected device with **zero manual configuration**!

### 📱 A. Install to iPad / iPhone (macOS)
If you have an iPad or iPhone connected to your Mac (via USB or on the same Wi-Fi network with Developer Mode turned on):

1.  Open your terminal in the project directory and run:
    ```bash
    ./install_ipad.sh
    ```
2.  The script will automatically detect your iPad Pro, compile the Swift project, sign it, and install it.
3.  **To Trust the App (First-Time Only)**:
    *   Open **Settings** on your iPad.
    *   Go to **General > VPN & Device Management**.
    *   Tap your Apple ID email under "Developer App" and tap **Trust**.
4.  The terminal script will detect when you're ready and instantly launch Omniverse on your iPad!

### 🤖 B. Install to Android Device (Phone / Tablet / TV)
If you have an Android device connected via USB with USB Debugging enabled:

1.  Open your terminal in the project directory and run:
    ```bash
    ./install_android.sh
    ```
2.  The script will auto-detect your device model (e.g. *Samsung Galaxy*), boot Android Studio's bundled JDK, compile, and install the package.
3.  The app will instantly launch on your Android screen in the foreground!

---

## 🏗️ Repository Architecture

If you're a developer or just curious about how things are structured under the hood, here is the directory layout:

```
omniplay/
├── android/            # Native Kotlin + Jetpack Compose Android & Android TV App
│   ├── app/            # Main Android application module
│   └── build.gradle.kts# Gradle dependencies and targets
├── ios/                # Native Swift + SwiftUI iOS & iPadOS App
│   ├── Omniverse/      # Swift layout views, networking, and assets
│   ├── Omniverse.xcodeproj # Generated Xcode project bundle
│   └── project.yml     # XcodeGen configuration sheet
├── keystore/           # Secure release keystores for signed Android binaries
├── SYNC_SPEC.md        # Cryptographic sync protocol specification
├── build.sh            # Unified multi-platform build compiler
├── install_ipad.sh     # One-click iPad/iOS device installer
└── install_android.sh  # One-click Android device installer
```

---

## ☁️ Setting Up Sync Services

To get the most out of Omniverse, we highly recommend linking a free **Trakt.tv** account:

1.  Create a free account at [Trakt.tv](https://trakt.tv).
2.  When you first launch Omniverse, tap **Connect Trakt.tv**.
3.  Follow the simple on-screen activation prompt (or scan the QR code to log in on your phone).
4.  Once linked, your watch progress, watchlists, settings, and custom API integrations will sync automatically across all of your devices!

---

## 🤝 Community & Contributing

We welcome contributions of all kinds!
*   **Feedback & Feature Requests**: Open an issue to suggest additions.
*   **Android Tweaks**: convention follows [Official Kotlin Coding Conventions](https://kotlinlang.org/docs/coding-conventions.html).
*   **iOS Tweaks**: Keep SwiftUI views lightweight and leverage our central `@Observable` `AppState` engine.

---

## 📄 License

Omniverse is open-source software distributed under the [MIT License](LICENSE). Made with ❤️ for a premium, private streaming experience.

---

## ⚖️ Legal Disclaimer

**Omniverse does NOT host, store, stream, or distribute any media files, movies, TV shows, anime, or video files.**

The application functions strictly as a client-side **media player, catalog organizer, and search index browser** that connects to public metadata directories (such as TMDB, TVDB, and Trakt.tv) and plays user-provided local streams or user-resolved public feeds. 

Omniverse does not promote, encourage, or facilitate copyright infringement or digital piracy. It is an open-source tool designed solely for personal media management, cataloging, and playing legally acquired content. Any third-party stream links or sources accessed through the player are hosted elsewhere, and Omniverse has no control over, nor assumes any responsibility or liability for, their content, legality, or availability.
