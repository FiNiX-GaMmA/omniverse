# 🔑 Omniverse API Keys & Sync Configuration Guide

Welcome to **Omniverse**! Because Omniverse is a **100% decentralized, client-side, server-less app**, it connects directly to public APIs (such as TMDB, Trakt, and AniList) from your device. Your data, API limits, and credentials are kept entirely in your hands, offering absolute privacy.

This guide provides step-by-step instructions on how to easily obtain and set up these API keys.

---

## ⚡ Quick Setup: Zero-Config QR Sync
If you have **already configured your keys on one device** (e.g., your computer or tablet) and want to transfer them to another device (e.g., your phone or TV):
1. On your configured device, open **Settings** and tap **Show Sync QR** (or navigate to the **Cloud Sync** tab).
2. On your new device, during onboarding or in the settings menu, tap **Scan QR**.
3. Scan the QR code. All of your API keys, settings, watch history, and account links will be securely, instantly transferred without touching any third-party server!

---

## 🎬 1. TMDB Token (Required)
The Movie Database (TMDB) is used by Omniverse to load posters, backdrops, trailers, cast details, trending feeds, and search results for movies and standard TV shows.

### Steps to obtain your TMDB Token:
1. Go to [themoviedb.org](https://www.themoviedb.org/) and create a free account (or log in).
2. Click on your profile icon in the top right corner and select **Settings**.
3. In the left-hand menu, click on **API**.
4. Under the **Create** section, click on **Developer**.
5. Read and accept the terms of service, then fill in the basic details about your application (e.g., App Name: `Omniverse`, Description: `Personal native media tracker`).
6. Once submitted, TMDB will generate your API credentials.
7. Scroll down to find the **API Read Access Token** (this is the **very long** token starting with `ey...`).
8. Copy this long token and paste it into the **TMDB Read Access Token** field in the **Settings > API Keys** tab of Omniverse.

---

## ☁️ 2. Trakt.tv Client Keys (Highly Recommended)
Trakt.tv handles scrobbling (tracking your watch progress in real-time), syncing watchlists, and maintaining a secure, encrypted backup of your entire Omniverse config (including all other keys, preferences, and progress) in a private list on your profile.

### Steps to obtain your Trakt Developer Keys:
1. Register a free account at [Trakt.tv](https://trakt.tv).
2. Go to the Developer Dashboard at [trakt.tv/oauth/applications](https://trakt.tv/oauth/applications).
3. Click **Add a new application**.
4. Fill in the required fields:
   * **Name**: `Omniverse`
   * **Redirect URI**: `omniplay://trakt/oauth`
   * **Description**: `Omniverse Media Companion`
5. Leave the other fields at their default values and click **Save App**.
6. Once saved, Trakt will display your **Client ID** and **Client Secret**.
7. Copy and paste these into the **Trakt Developer Client Keys** section in your Omniverse settings.
8. Click **Connect Trakt** to authorize your account in the browser!

---

## 🌸 3. AniList Sync Token (For Anime Tracking)
AniList is utilized to search for anime metadata, fetch anime recommendations, and synchronize your progress when you watch anime episodes.

### Steps to connect:
1. Omniverse has **zero-configuration** support for AniList!
2. Open **Settings** in the app and go to the **Cloud Sync** tab.
3. Scroll to **AniList Sync Integration** and click **Connect AniList**.
4. Authorize your account in the browser page that opens, and it will automatically redirect back and link your account.
5. *Alternative (Manual Token Entry)*: If you prefer manual entry, authorize AniList directly via [this OAuth authorization page](https://anilist.co/api/v2/oauth/authorize?client_id=14187&response_type=token) and copy/paste the resulting token into the **AniList Access Token** field.

---

## 🏴‍☠️ 4. Pixeldrain API Key (Recommended for One Pace)
Pixeldrain is the hosting provider for **One Pace** fan-cut videos. Using an API key is highly recommended because it raises streaming/download rate limits and unlocks premium high-speed streaming.

### Steps to obtain your key:
1. Register/Log in to [Pixeldrain](https://pixeldrain.net/).
2. Go to your Account page, or navigate directly to [pixeldrain.net/api/user/key](https://pixeldrain.net/api/user/key).
3. Copy the alphanumeric API Key displayed.
4. Paste it into the **Pixeldrain API key** field in the Omniverse settings menu.

---

## 📺 5. TVDB API Key & subscriber PIN (Optional)
TheTVDB is used for advanced live TV listings, channel schedules, and extra TV series metadata.

### Steps to obtain your keys:
1. Create a developer account at [TheTVDB.com](https://thetvdb.com/).
2. Navigate to your dashboard and request an API key.
3. Enter the resulting API key and (if applicable) your subscriber PIN in the **TVDB API key** and **TVDB PIN** fields of Omniverse settings.
