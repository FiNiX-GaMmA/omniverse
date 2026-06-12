package com.finix.omniverse

import android.util.Base64
import kotlinx.serialization.json.Json
import org.json.JSONObject

/// Server-less cross-device login payload (see native/SYNC_SPEC.md).
///
/// A single text string:  OMNIVERSE-SYNC1:<base64(utf8(json))>
/// The JSON keys are byte-stable so the iOS app interoperates. Standard RFC 4648
/// Base64 (NO_WRAP → no newlines, with `=` padding), NOT url-safe, NOT gzipped.
/// `watch_history` is intentionally omitted to keep the QR small/scannable.
object SyncCenter {

    const val PREFIX = "OMNIVERSE-SYNC1:"

    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    /// Build the QR string from the current credentials + settings.
    /// Empty credential fields are omitted to keep the payload small.
    fun buildSyncString(creds: ApiCredentials, settings: UserSettings): String {
        val obj = JSONObject().put("v", 1)
        putIfNotBlank(obj, "trakt_access_token", creds.traktAccessToken)
        putIfNotBlank(obj, "trakt_refresh_token", creds.traktRefreshToken)
        if (creds.traktTokenExpiresAt != 0L) obj.put("trakt_token_expires_at", creds.traktTokenExpiresAt)
        putIfNotBlank(obj, "trakt_username", creds.traktUsername)
        putIfNotBlank(obj, "trakt_client_id", creds.traktClientId)
        putIfNotBlank(obj, "trakt_client_secret", creds.traktClientSecret)
        putIfNotBlank(obj, "tmdb_token", creds.tmdbToken)
        putIfNotBlank(obj, "tvdb_api_key", creds.tvdbApiKey)
        putIfNotBlank(obj, "tvdb_pin", creds.tvdbPin)
        putIfNotBlank(obj, "pixeldrain_api_key", creds.pixeldrainApiKey)
        // NOTE: the long AniList JWT and the settings object are intentionally
        // omitted — they bloat the QR past a scannable density. After scanning,
        // the Trakt tokens above let the device pull the AniList token, settings,
        // watch history and watchlist from the cloud backup automatically.
        val b64 = Base64.encodeToString(obj.toString().toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
        return PREFIX + b64
    }

    /// Returns true if the scanned value is an OMNIVERSE-SYNC payload.
    fun isSyncString(s: String): Boolean = s.trim().startsWith(PREFIX)

    /// Decode an OMNIVERSE-SYNC payload to its JSON object, or null if malformed.
    fun parse(s: String): JSONObject? {
        val trimmed = s.trim()
        if (!trimmed.startsWith(PREFIX)) return null
        val b64 = trimmed.removePrefix(PREFIX).trim()

        // Try decoding with DEFAULT, NO_WRAP, and URL_SAFE.
        val decodedString = runCatching {
            String(Base64.decode(b64, Base64.DEFAULT), Charsets.UTF_8)
        }.recoverCatching {
            String(Base64.decode(b64, Base64.NO_WRAP), Charsets.UTF_8)
        }.recoverCatching {
            String(Base64.decode(b64, Base64.URL_SAFE), Charsets.UTF_8)
        }.getOrNull() ?: return null

        return runCatching { JSONObject(decodedString) }.getOrNull()
    }

    private fun putIfNotBlank(obj: JSONObject, key: String, value: String) {
        if (value.trim().isNotEmpty()) obj.put(key, value)
    }
}
