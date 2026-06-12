# Omniverse Cross-Device Login & Sync — v1 (server-less QR)

The OLD approach (upload JSON to Pixeldrain, show file-id QR, paste base64 to restore)
is REMOVED. It failed with Pixeldrain 401 and the "scanner" only accepted pasted base64.

## New approach — direct QR transfer (no server, 2 steps)

Device A → Settings/Cloud Sync → **"Show Sync QR"** renders a QR that contains the FULL
credential+settings bundle. Device B → **"Scan Sync QR"** opens the CAMERA, decodes the QR,
restores everything, and is instantly signed in to every service (TMDB, TVDB, Trakt,
AniList, Pixeldrain) + all preferences. Because the Trakt access/refresh tokens are inside
the payload, ongoing Trakt-based sync (watch history, settings backup) resumes automatically
on device B with no re-login. No Pixeldrain, no Trakt OAuth round-trip on the 2nd device.

## QR payload format (MUST be byte-identical across iOS & Android so they interoperate)

A single text string:

    OMNIVERSE-SYNC1:<base64(utf8(json))>

where `json` is (omit empty fields to keep it small; keys are stable):

```json
{
  "v": 1,
  "trakt_access_token": "...",
  "trakt_refresh_token": "...",
  "trakt_token_expires_at": 1730000000000,
  "trakt_username": "...",
  "trakt_client_id": "...",
  "trakt_client_secret": "...",
  "tmdb_token": "...",
  "tvdb_api_key": "...",
  "tvdb_pin": "...",
  "pixeldrain_api_key": "...",
  "anilist_access_token": "...",
  "settings": { /* UserSettings as JSON, same keys as the model */ }
}
```

- Base64 = standard (RFC 4648, `+/`, with `=` padding). NOT url-safe. NOT gzipped (keep it
  trivially cross-platform; this payload is ~0.8–1.6 KB → fits a QR at error-correction M).
- Do NOT include `watch_history` in the QR (keeps it small + scannable). History re-syncs via
  Trakt after login if Trakt is connected.
- QR error correction level: **M**. Render large (min 280pt/dp) on a white card with quiet zone.

## Restore logic (both platforms)
On a successful scan/decode:
1. Verify prefix `OMNIVERSE-SYNC1:`; strip it. (If the scanned value is an http/https URL,
   open it externally instead — supports Trakt activation links.)
2. base64-decode → JSON.
3. Apply every present field onto ApiCredentials; apply `settings` onto UserSettings.
4. Persist (Keychain / EncryptedSharedPreferences + settings store), then refresh.
5. This satisfies the onboarding gate (hasTraktUser becomes true when tokens are present).

## Camera scanner (NOT base64 paste)
- iOS: `AVCaptureSession` + `AVCaptureMetadataOutput` (`.qr`), in a `UIViewControllerRepresentable`.
  Request camera permission (Info.plist `NSCameraUsageDescription`). Provide a small "Paste code"
  fallback link for devices without a camera, but the camera is the default.
- Android: `com.journeyapps:zxing-android-embedded` (`ScanContract`/`ScanOptions`) launched from a
  Composable via `rememberLauncherForActivityResult`. Requests CAMERA permission. Decodes QR_CODE.

## Onboarding
Make **"Scan Sync QR"** (camera) the prominent primary action on the onboarding screen, alongside
"Connect Trakt" and manual key entry. Scanning a valid sync QR logs in immediately.
