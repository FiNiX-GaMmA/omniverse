package com.finix.omniverse

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json

private val json = Json {
    ignoreUnknownKeys = true
    encodeDefaults = true
}

// MARK: - EncryptedSharedPreferences-backed credentials store
// Mirrors the iOS CredentialsStore (Keychain). Same key names as the Dart app.

class CredentialsStore(context: Context) {

    private object K {
        const val tmdbToken = "tmdb_token"
        const val tvdbKey = "tvdb_api_key"
        const val tvdbPin = "tvdb_pin"
        const val traktClientId = "trakt_client_id"
        const val traktClientSecret = "trakt_client_secret"
        const val traktAccessToken = "trakt_access_token"
        const val traktRefreshToken = "trakt_refresh_token"
        const val traktTokenExpiresAt = "trakt_token_expires_at"
        const val traktUsername = "trakt_username"
        const val pixeldrainApiKey = "pixeldrain_api_key"
        const val anilistAccessToken = "anilist_access_token"
    }

    private val prefs: SharedPreferences = run {
        val masterKey = MasterKey.Builder(context.applicationContext)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        try {
            EncryptedSharedPreferences.create(
                context.applicationContext,
                "omniverse_credentials",
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
            )
        } catch (_: Throwable) {
            // Fallback to plain prefs if the keystore is unavailable (e.g. corrupted
            // master key on some OEM devices). Better than crashing on launch.
            context.applicationContext.getSharedPreferences("omniverse_credentials_plain", Context.MODE_PRIVATE)
        }
    }

    fun load(): ApiCredentials = ApiCredentials(
        tmdbToken = prefs.getString(K.tmdbToken, "") ?: "",
        tvdbApiKey = prefs.getString(K.tvdbKey, "") ?: "",
        tvdbPin = prefs.getString(K.tvdbPin, "") ?: "",
        traktClientId = prefs.getString(K.traktClientId, "") ?: "",
        traktClientSecret = prefs.getString(K.traktClientSecret, "") ?: "",
        traktAccessToken = prefs.getString(K.traktAccessToken, "") ?: "",
        traktRefreshToken = prefs.getString(K.traktRefreshToken, "") ?: "",
        traktTokenExpiresAt = (prefs.getString(K.traktTokenExpiresAt, "") ?: "").toLongOrNull() ?: 0L,
        traktUsername = prefs.getString(K.traktUsername, "") ?: "",
        pixeldrainApiKey = prefs.getString(K.pixeldrainApiKey, "") ?: "",
        anilistAccessToken = prefs.getString(K.anilistAccessToken, "") ?: "",
    )

    fun save(c: ApiCredentials) {
        prefs.edit().apply {
            putString(K.tmdbToken, c.tmdbToken.trim())
            putString(K.tvdbKey, c.tvdbApiKey.trim())
            putString(K.tvdbPin, c.tvdbPin.trim())
            putString(K.traktClientId, c.traktClientId.trim())
            putString(K.traktClientSecret, c.traktClientSecret.trim())
            putString(K.traktAccessToken, c.traktAccessToken.trim())
            putString(K.traktRefreshToken, c.traktRefreshToken.trim())
            putString(K.traktTokenExpiresAt, c.traktTokenExpiresAt.toString())
            putString(K.traktUsername, c.traktUsername.trim())
            putString(K.pixeldrainApiKey, c.pixeldrainApiKey.trim())
            putString(K.anilistAccessToken, c.anilistAccessToken.trim())
        }.apply()
    }
}

// MARK: - SharedPreferences-backed settings / cache store
// Mirrors the iOS UserSettingsStore (UserDefaults). kotlinx.serialization JSON.

class UserSettingsStore(context: Context) {

    private object K {
        const val settings = "settings"
        const val liveTvSources = "live_tv_sources"
        const val cachedCategories = "cached_categories"
        const val cachedLiveTv = "cached_live_tv"
        const val watchlist = "watchlist"
        const val watchHistory = "watch_history_v1"
        const val lastRefreshedTime = "last_refreshed_time"
    }

    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences("omniverse_settings", Context.MODE_PRIVATE)

    fun loadSettings(): UserSettings = decode(K.settings, UserSettings.serializer()) ?: UserSettings()
    fun saveSettings(s: UserSettings) = encode(K.settings, UserSettings.serializer(), s)

    fun loadLiveTvSources(): List<LiveTvSource> =
        decode(K.liveTvSources, ListSerializer(LiveTvSource.serializer())) ?: emptyList()
    fun saveLiveTvSources(v: List<LiveTvSource>) =
        encode(K.liveTvSources, ListSerializer(LiveTvSource.serializer()), v)

    fun loadCachedCategories(): List<MediaCategory> =
        decode(K.cachedCategories, ListSerializer(MediaCategory.serializer())) ?: emptyList()
    fun saveCachedCategories(v: List<MediaCategory>) =
        encode(K.cachedCategories, ListSerializer(MediaCategory.serializer()), v)

    fun loadCachedLiveTv(): List<LiveTvEntry> =
        decode(K.cachedLiveTv, ListSerializer(LiveTvEntry.serializer())) ?: emptyList()
    fun saveCachedLiveTv(v: List<LiveTvEntry>) =
        encode(K.cachedLiveTv, ListSerializer(LiveTvEntry.serializer()), v)

    fun loadWatchlist(): Set<String> =
        (decode(K.watchlist, ListSerializer(String.serializer())) ?: emptyList()).toSet()
    fun saveWatchlist(v: Set<String>) =
        encode(K.watchlist, ListSerializer(String.serializer()), v.sorted())

    fun loadWatchHistory(): List<WatchProgress> =
        decode(K.watchHistory, ListSerializer(WatchProgress.serializer())) ?: emptyList()
    fun saveWatchHistory(v: List<WatchProgress>) =
        encode(K.watchHistory, ListSerializer(WatchProgress.serializer()), v)

    fun lastRefreshedTime(): Long = prefs.getLong(K.lastRefreshedTime, 0L)
    fun setLastRefreshedTime(ms: Long) = prefs.edit().putLong(K.lastRefreshedTime, ms).apply()

    private fun <T> decode(key: String, serializer: kotlinx.serialization.KSerializer<T>): T? {
        val raw = prefs.getString(key, null) ?: return null
        return try { json.decodeFromString(serializer, raw) } catch (_: Throwable) { null }
    }

    private fun <T> encode(key: String, serializer: kotlinx.serialization.KSerializer<T>, value: T) {
        try {
            prefs.edit().putString(key, json.encodeToString(serializer, value)).apply()
        } catch (_: Throwable) { /* ignore serialization failures */ }
    }
}
