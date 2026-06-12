package com.finix.omniverse

import android.content.Context
import android.net.Uri
import android.util.Base64
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.Json
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.ln
import kotlin.random.Random

private val appJson = Json { ignoreUnknownKeys = true; encodeDefaults = true }

/// Holds settings/credentials/categories/anime/liveTv/watchlist/watchHistory as
/// Compose state. Faithful port of OmniplayState (app_state.dart) plus the iOS
/// AppState. Runs its work on a Main-dispatched CoroutineScope.
class AppState(context: Context) {

    private val appContext = context.applicationContext
    val credentialsStore = CredentialsStore(appContext)
    val settingsStore = UserSettingsStore(appContext)
    var repos: Repositories = Repositories.live()

    private val scope = CoroutineScope(Dispatchers.Main)

    // MARK: - Compose-observable state

    var settings by mutableStateOf(UserSettings())
        private set
    var credentials by mutableStateOf(ApiCredentials())
        private set

    val categories = mutableStateListOf<MediaCategory>()
    val animeCategories = mutableStateListOf<MediaCategory>()
    val liveTv = mutableStateListOf<LiveTvEntry>()
    val liveTvSources = mutableStateListOf<LiveTvSource>()
    val watchHistory = mutableStateListOf<WatchProgress>()

    var watchlist by mutableStateOf<Set<String>>(emptySet())
        private set

    var initialized by mutableStateOf(false)
        private set
    var loading by mutableStateOf(false)
        private set
    var traktConnecting by mutableStateOf(false)
        private set
    var pendingTraktState by mutableStateOf<String?>(null)
        private set
    var message by mutableStateOf<String?>(null)

    var isScanningLiveTv by mutableStateOf(false)
        private set
    var liveTvScanProgress by mutableStateOf(0.0)
        private set
    var hasScannedLiveTv by mutableStateOf(false)
        private set

    val needsSetup: Boolean get() = !credentials.hasTmdb

    private var heroPicksCache: List<MediaItem> = emptyList()
    private var playbackPollJob: Job? = null

    // MARK: - Lifecycle

    fun initialize() {
        scope.launch {
            settings = settingsStore.loadSettings()
            credentials = credentialsStore.load()
            liveTvSources.clear(); liveTvSources.addAll(settingsStore.loadLiveTvSources())
            watchlist = settingsStore.loadWatchlist()
            val cachedCategories = settingsStore.loadCachedCategories()
            val cachedLiveTv = settingsStore.loadCachedLiveTv()
            if (cachedCategories.isNotEmpty()) { categories.clear(); categories.addAll(cachedCategories) }
            liveTv.clear(); liveTv.addAll(cachedLiveTv)
            hasScannedLiveTv = liveTv.isNotEmpty()
            watchHistory.clear(); watchHistory.addAll(settingsStore.loadWatchHistory())
            initialized = true

            // Silent refresh only if cache older than 6 hours.
            val last = settingsStore.lastRefreshedTime()
            val diff = System.currentTimeMillis() - last
            if (diff >= 6L * 3600 * 1000) {
                scope.launch { refreshAll(isManual = false) }
            } else {
                scope.launch { refreshTraktWatchlist() }
            }

            // Pull API keys + settings saved by other devices on the same Trakt
            // account so they propagate automatically on launch.
            scope.launch { pullRemoteSettingsSilently() }

            // Periodic full bidirectional sync every 20s while foreground.
            playbackPollJob?.cancel()
            playbackPollJob = scope.launch {
                while (isActive) {
                    delay(20_000)
                    if (credentials.hasTraktUser && initialized) syncNow()
                }
            }
        }
    }

    // MARK: - Refresh

    suspend fun refreshAll(isManual: Boolean = true) {
        if (isManual) { loading = true; message = null }
        refreshCategories()
        refreshAnime()
        refreshTraktWatchlist()
        settingsStore.setLastRefreshedTime(System.currentTimeMillis())
        clearHeroCache()
        if (isManual) loading = false
    }

    suspend fun refreshCategories() {
        val next = ArrayList<MediaCategory>()
        val notices = ArrayList<String>()
        try {
            val tmdb = repos.tmdb.fetchLandingCategories(credentials, settings)
            val loaded = nonEmptyCategories(tmdb)
            next.addAll(loaded)
            if (loaded.isEmpty()) categoryErrorMessage(tmdb, "TMDB")?.let { notices.add(it) }
        } catch (t: Throwable) { notices.add(safeRefreshMessage("TMDB", t)) }

        try {
            val trakt = repos.trakt.fetchDiscoveryCategories(credentials)
            val enriched = enrichMetadataCategories(trakt.filter { it.id.startsWith("trakt_") }, 12)
            next.addAll(nonEmptyCategories(enriched))
        } catch (t: Throwable) { notices.add(safeRefreshMessage("Trakt", t)) }

        val vid = repos.vidsrc.fetchLatestCategories()
        val enrichedVid = enrichMetadataCategories(vid, 10)
        if (next.isNotEmpty() || categories.isEmpty()) next.addAll(nonEmptyCategories(enrichedVid))

        if (next.isNotEmpty()) {
            categories.clear(); categories.addAll(next)
            settingsStore.saveCachedCategories(next)
        } else if (categories.isNotEmpty() && notices.isEmpty()) {
            notices.add("Showing cached rows.")
        }
        notices.firstOrNull()?.let { message = it }
    }

    suspend fun refreshAnime() {
        try {
            val cats = repos.anime.fetchAnimeCategories()
            animeCategories.clear(); animeCategories.addAll(cats)
        } catch (t: Throwable) { message = "Could not refresh anime rows: $t" }
    }

    suspend fun refreshTraktWatchlist() {
        if (!credentials.hasTraktUser) return
        try {
            refreshTraktCredentialsIfNeeded()
            val items = repos.trakt.fetchWatchlist(credentials)
            val next = watchlist.toMutableSet()
            for (item in items) next.addAll(watchlistKeys(item))
            watchlist = next
            settingsStore.saveWatchlist(next)
        } catch (t: Throwable) { message = "Could not sync Trakt watchlist: $t" }
        refreshTraktPlayback()
    }

    suspend fun refreshTraktPlayback() {
        if (!credentials.hasTraktUser) return
        try {
            refreshTraktCredentialsIfNeeded()
            syncWatchHistoryFromTrakt()
            val remote = repos.trakt.fetchPlaybackProgress(credentials)
            if (remote.isNotEmpty()) mergeProgress(remote, preferRemoteTime = false)
        } catch (_: Throwable) { /* keep local */ }
    }

    // MARK: - Watch history

    private fun mergeProgress(incoming: List<WatchProgress>, preferRemoteTime: Boolean) {
        val byKey = LinkedHashMap<String, WatchProgress>()
        for (e in watchHistory) byKey[e.progressKey] = e
        for (e in incoming) {
            val local = byKey[e.progressKey]
            if (local != null && local.lastWatchedAt >= e.lastWatchedAt) {
                continue
            }
            if (local != null) {
                byKey[e.progressKey] = e.copy(
                    posterPath = e.posterPath ?: local.posterPath,
                    backdropPath = e.backdropPath ?: local.backdropPath
                )
            } else {
                byKey[e.progressKey] = e
            }
        }
        val merged = byKey.values.sortedByDescending { it.lastWatchedAt }.take(30)
        watchHistory.clear(); watchHistory.addAll(merged)
        settingsStore.saveWatchHistory(merged)
    }

    suspend fun recordProgress(item: MediaItem, positionMs: Int, durationMs: Int, episode: MediaEpisode?) {
        if (durationMs <= 0) return
        val fraction = positionMs.toDouble() / durationMs
        if (positionMs < 5000 || fraction >= 0.95) {
            if (fraction >= 0.95) removeProgressEntry(item, episode)
            return
        }
        val entry = WatchProgress(
            id = null, itemId = item.id, title = item.title, type = item.type,
            posterPath = item.posterPath, backdropPath = item.backdropPath,
            seasonNumber = episode?.seasonNumber, episodeNumber = episode?.episodeNumber,
            episodeTitle = episode?.title, positionMs = positionMs, durationMs = durationMs,
            lastWatchedAt = System.currentTimeMillis(),
        )
        val next = ArrayList<WatchProgress>()
        next.add(entry)
        next.addAll(watchHistory.filter { it.progressKey != entry.progressKey })
        val capped = next.take(30)
        watchHistory.clear(); watchHistory.addAll(capped)
        settingsStore.saveWatchHistory(capped)
    }

    private fun removeProgressEntry(item: MediaItem, episode: MediaEpisode?) {
        val next = watchHistory.filter { it.progressKey != item.id }
        if (next.size == watchHistory.size) return
        watchHistory.clear(); watchHistory.addAll(next)
        settingsStore.saveWatchHistory(next)
    }

    suspend fun dismissProgress(entry: WatchProgress) {
        val next = watchHistory.filter { it.itemId != entry.itemId }
        watchHistory.clear(); watchHistory.addAll(next)
        settingsStore.saveWatchHistory(next)
        if (credentials.hasTraktUser) {
            runCatching { refreshTraktCredentialsIfNeeded() }
            if (entry.id != null) {
                runCatching { repos.trakt.deletePlaybackProgress(credentials, entry.id) }
            } else {
                val remote = repos.trakt.fetchPlaybackProgress(credentials)
                for (r in remote) if (r.itemId == entry.itemId && r.id != null) {
                    runCatching { repos.trakt.deletePlaybackProgress(credentials, r.id) }
                }
            }
            scope.launch { runCatching { syncSettingsToTrakt() } }
        }
    }

    val continueWatching: List<WatchProgress>
        get() = watchHistory.sortedByDescending { it.lastWatchedAt }

    suspend fun syncWatchHistoryFromTrakt() {
        if (!credentials.hasTraktUser) return
        val payload = repos.trakt.fetchRemoteSettings(credentials)?.trim()
        if (payload.isNullOrEmpty()) return
        val obj = decodeBase64Json(payload) ?: return
        val raw = obj.optArrayOrNull("watch_history") ?: return
        val restored = raw.objects().mapNotNull { watchProgressFromJson(it) }
        mergeProgress(restored, preferRemoteTime = true)
    }

    // MARK: - Trakt backup/restore (Base64(JSON), parity with app_state.dart)

    suspend fun syncSettingsToTrakt(silent: Boolean = false) {
        if (!credentials.hasTraktUser) throw IllegalStateException("Trakt not connected.")
        refreshTraktCredentialsIfNeeded()
        val payload = JSONObject()
            .put("version", 1)
            .put("tmdb_token", credentials.tmdbToken)
            .put("tvdb_api_key", credentials.tvdbApiKey)
            .put("tvdb_pin", credentials.tvdbPin)
            .put("pixeldrain_api_key", credentials.pixeldrainApiKey)
            .put("anilist_access_token", credentials.anilistAccessToken)
            .put("trakt_client_id", credentials.traktClientId)
            .put("trakt_client_secret", credentials.traktClientSecret)
            .put("settings", settingsToJson(settings))
            .put("watch_history", JSONArray().apply { watchHistory.forEach { put(watchProgressToJson(it)) } })
        val b64 = Base64.encodeToString(payload.toString().toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
        repos.trakt.saveRemoteSettings(credentials, b64)
        if (!silent) message = "All settings and API keys successfully synced to Trakt!"
    }

    /// Full bidirectional background sync: pull the cloud backup + Trakt
    /// watchlist/playback (merging newest-wins), then push the merged local state
    /// back. Keeps watchlist, watch time, last-watched episode and API keys in
    /// lockstep across devices. Silent (no toasts).
    suspend fun syncNow() {
        if (!credentials.hasTraktUser) return
        runCatching { refreshTraktCredentialsIfNeeded() }.getOrElse { return }
        pullRemoteSettingsSilently()
        refreshTraktWatchlist()
        runCatching { syncSettingsToTrakt(silent = true) }
    }

    suspend fun restoreSettingsFromTrakt() {
        if (!credentials.hasTraktUser) throw IllegalStateException("Trakt not connected.")
        refreshTraktCredentialsIfNeeded()
        val payload = repos.trakt.fetchRemoteSettings(credentials)?.trim()
        val obj = (if (payload.isNullOrEmpty()) null else decodeBase64Json(payload))
            ?: throw IllegalStateException("No backup settings found.")
        var c = credentials
        obj.optStringOrNull("tmdb_token")?.let { c = c.copy(tmdbToken = it) }
        obj.optStringOrNull("tvdb_api_key")?.let { c = c.copy(tvdbApiKey = it) }
        obj.optStringOrNull("tvdb_pin")?.let { c = c.copy(tvdbPin = it) }
        obj.optStringOrNull("pixeldrain_api_key")?.let { c = c.copy(pixeldrainApiKey = it) }
        obj.optStringOrNull("anilist_access_token")?.let { c = c.copy(anilistAccessToken = it) }
        saveCredentials(c)
        obj.optObjectOrNull("settings")?.let { saveSettings(settingsFromJson(it)) }
        obj.optArrayOrNull("watch_history")?.let {
            mergeProgress(it.objects().mapNotNull { o -> watchProgressFromJson(o) }, preferRemoteTime = true)
        }
        message = "All settings and API keys successfully restored from Trakt!"
    }

    /// Silently pull the latest API keys + settings from the Trakt-backed cloud
    /// backup ("Omniverse Sync" list) so they propagate across devices.
    /// Last-write-wins; does not re-upload (avoids loops).
    private suspend fun pullRemoteSettingsSilently() {
        if (!credentials.hasTraktUser) return
        runCatching { refreshTraktCredentialsIfNeeded() }.getOrElse { return }
        val payload = repos.trakt.fetchRemoteSettings(credentials)?.trim() ?: return
        if (payload.isEmpty()) return
        val obj = decodeBase64Json(payload) ?: return
        var c = credentials
        obj.optStringOrNull("tmdb_token")?.takeIf { it.isNotEmpty() }?.let { c = c.copy(tmdbToken = it) }
        obj.optStringOrNull("tvdb_api_key")?.takeIf { it.isNotEmpty() }?.let { c = c.copy(tvdbApiKey = it) }
        obj.optStringOrNull("tvdb_pin")?.let { c = c.copy(tvdbPin = it) }
        obj.optStringOrNull("pixeldrain_api_key")?.takeIf { it.isNotEmpty() }?.let { c = c.copy(pixeldrainApiKey = it) }
        obj.optStringOrNull("anilist_access_token")?.takeIf { it.isNotEmpty() }?.let { c = c.copy(anilistAccessToken = it) }
        obj.optStringOrNull("trakt_client_id")?.takeIf { it.isNotEmpty() }?.let { c = c.copy(traktClientId = it) }
        obj.optStringOrNull("trakt_client_secret")?.takeIf { it.isNotEmpty() }?.let { c = c.copy(traktClientSecret = it) }
        val changed = c != credentials
        credentials = c
        credentialsStore.save(c)
        obj.optObjectOrNull("settings")?.let { settings = settingsFromJson(it); settingsStore.saveSettings(settings) }
        if (changed) refreshAll(isManual = false)
    }

    // MARK: - Credentials / settings

    suspend fun saveCredentials(next: ApiCredentials) {
        var n = next
        val changed = n.traktClientId.trim() != credentials.traktClientId.trim() ||
            n.traktClientSecret.trim() != credentials.traktClientSecret.trim()
        if (changed) n = n.copy(traktAccessToken = "", traktRefreshToken = "", traktTokenExpiresAt = 0, traktUsername = "")
        credentials = n
        credentialsStore.save(n)
        if (credentials.hasTraktUser) scope.launch { runCatching { syncSettingsToTrakt() } }
        refreshAll()
    }

    suspend fun saveSettings(next: UserSettings) {
        settings = next
        settingsStore.saveSettings(next)
        if (credentials.hasTraktUser) scope.launch { runCatching { syncSettingsToTrakt() } }
        refreshAll()
    }

    // MARK: - Cross-device QR sync (server-less; see native/SYNC_SPEC.md)

    /// Apply a scanned QR value. If it's an OMNIVERSE-SYNC payload, decode it,
    /// merge present credential fields, apply settings, persist and refresh →
    /// returns true. If it's an http(s) URL (e.g. a Trakt activation link), open
    /// it externally → returns false. Returns false for anything unrecognised.
    suspend fun applySyncString(s: String): Boolean {
        val value = s.trim()
        if (!SyncCenter.isSyncString(value)) {
            if (value.startsWith("http://") || value.startsWith("https://")) {
                runCatching {
                    val intent = android.content.Intent(android.content.Intent.ACTION_VIEW, Uri.parse(value))
                        .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                    appContext.startActivity(intent)
                }
            } else {
                message = "That QR code isn't an Omniverse sync code."
            }
            return false
        }
        val obj = SyncCenter.parse(value)
        if (obj == null) { message = "Couldn't read that sync QR code."; return false }

        var c = credentials
        obj.optStringOrNull("trakt_access_token")?.let { c = c.copy(traktAccessToken = it) }
        obj.optStringOrNull("trakt_refresh_token")?.let { c = c.copy(traktRefreshToken = it) }
        if (obj.has("trakt_token_expires_at")) c = c.copy(traktTokenExpiresAt = obj.optLong("trakt_token_expires_at"))
        obj.optStringOrNull("trakt_username")?.let { c = c.copy(traktUsername = it) }
        obj.optStringOrNull("trakt_client_id")?.let { c = c.copy(traktClientId = it) }
        obj.optStringOrNull("trakt_client_secret")?.let { c = c.copy(traktClientSecret = it) }
        obj.optStringOrNull("tmdb_token")?.let { c = c.copy(tmdbToken = it) }
        obj.optStringOrNull("tvdb_api_key")?.let { c = c.copy(tvdbApiKey = it) }
        obj.optStringOrNull("tvdb_pin")?.let { c = c.copy(tvdbPin = it) }
        obj.optStringOrNull("pixeldrain_api_key")?.let { c = c.copy(pixeldrainApiKey = it) }
        obj.optStringOrNull("anilist_access_token")?.let { c = c.copy(anilistAccessToken = it) }

        credentials = c
        credentialsStore.save(c)
        obj.optObjectOrNull("settings")?.let {
            settings = settingsFromJson(it)
            settingsStore.saveSettings(settings)
        }
        message = "Synced from another device."
        refreshAll()
        return true
    }

    // MARK: - Search / details / playback

    suspend fun searchMedia(query: String): List<MediaItem> =
        repos.tmdb.searchMulti(query, credentials, settings)

    suspend fun detailsFor(item: MediaItem): MediaItem {
        if (item.type == MediaType.ANIME || item.isAnime) {
            repos.anime.findByTitle(item.title)?.let { hydrated ->
                return hydrated.copy(
                    tmdbId = item.tmdbId ?: hydrated.tmdbId,
                    tvdbId = item.tvdbId ?: hydrated.tvdbId,
                    imdbId = item.imdbId ?: hydrated.imdbId,
                    traktId = item.traktId ?: hydrated.traktId,
                )
            }
            if (item.type == MediaType.ANIME && item.seasons.isNotEmpty()) return item
        }
        val detailed = repos.tmdb.fetchDetails(item, credentials, settings) ?: item
        val enriched = repos.tvdb.enrichDetails(detailed, credentials)
        if (enriched.isAnime && enriched.type != MediaType.ANIME) {
            repos.anime.findByTitle(enriched.title)?.let { anilist ->
                return anilist.copy(
                    tmdbId = enriched.tmdbId, tvdbId = enriched.tvdbId,
                    imdbId = enriched.imdbId, traktId = enriched.traktId,
                )
            }
        }
        return enriched
    }

    suspend fun seasonEpisodesFor(item: MediaItem, seasonNumber: Int): List<MediaEpisode> {
        if (item.type == MediaType.ANIME) {
            var eps = repos.anime.fetchEpisodes(item, seasonNumber)
            if (item.tmdbId != null) {
                val tmdbEps = repos.tmdb.fetchSeasonEpisodes(item, seasonNumber, credentials, settings)
                if (tmdbEps.isNotEmpty()) {
                    val byNum = tmdbEps.associateBy { it.episodeNumber }
                    eps = eps.map { ep ->
                        val t = byNum[ep.episodeNumber]
                        if (t?.stillPath != null && (ep.stillPath ?: "").isEmpty()) ep.copy(stillPath = t.stillPath) else ep
                    }
                }
            }
            return eps
        }
        val eps = repos.tmdb.fetchSeasonEpisodes(item, seasonNumber, credentials, settings)
        if (eps.isNotEmpty() || !credentials.hasTvdb) return eps
        return repos.tvdb.fetchSeasonEpisodes(item, seasonNumber, credentials)
    }

    suspend fun playbackSourcesFor(item: MediaItem, episode: MediaEpisode? = null, overrides: PlaybackOverrides = PlaybackOverrides()): List<PlaybackSource> {
        val effective = settings.applying(overrides)
        if (item.type == MediaType.ANIME) {
            val target = episode ?: item.episodes.firstOrNull()
                ?: MediaEpisode(seasonNumber = 1, episodeNumber = 1, title = "Episode 1")
            return listOf(repos.anime.resolveSource(item, target, effective))
        }
        return repos.vidsrc.sourcesFor(item, effective, episode)
    }

    // MARK: - Recommendations

    /// "Because you watched ..." recommendations for the end-of-show screen when
    /// there are no more episodes/seasons to autoplay. Anime resolve through
    /// AniList, One Pace maps to One Piece (id 21), movies/TV use TMDB.
    suspend fun recommendationsFor(item: MediaItem?): List<MediaItem> {
        if (item == null) return emptyList()
        if (item.title == "One Pace") return repos.anime.recommendations(21)
        if ((item.type == MediaType.ANIME || item.isAnime) && item.anilistId != null) {
            val recs = repos.anime.recommendations(item.anilistId!!)
            if (recs.isNotEmpty()) return recs
        }
        if (item.tmdbId != null) return repos.tmdb.fetchRecommendations(item, credentials, settings)
        return emptyList()
    }

    // MARK: - Watchlist

    fun isInWatchlist(item: MediaItem): Boolean = watchlistKeys(item).any { it in watchlist }

    suspend fun toggleWatchlist(item: MediaItem) {
        val wasSaved = isInWatchlist(item)
        val keys = watchlistKeys(item)
        try {
            if (credentials.hasTraktUser && item.type != MediaType.LIVE_TV) {
                refreshTraktCredentialsIfNeeded()
                repos.trakt.setWatchlistItem(credentials, item, add = !wasSaved)
            }
            val next = watchlist.toMutableSet()
            if (wasSaved) keys.forEach { next.remove(it) } else next.addAll(keys)
            watchlist = next
            settingsStore.saveWatchlist(next)
            if (credentials.hasTraktUser && item.type != MediaType.LIVE_TV) {
                message = if (wasSaved) "Removed from Trakt watchlist." else "Added to Trakt watchlist."
            }
        } catch (t: Throwable) { message = "Could not sync Trakt watchlist: $t" }
    }

    private fun watchlistKeys(item: MediaItem): Set<String> {
        val typeNames = mutableSetOf(item.type.wire)
        if (item.type in listOf(MediaType.ANIME, MediaType.SERIES, MediaType.MOVIE)) {
            typeNames.addAll(listOf("anime", "series", "movie"))
        }
        val imdb = item.imdbId?.trim() ?: ""
        val keys = mutableSetOf(item.id)
        for (name in typeNames) {
            item.traktId?.let { keys.add("trakt:$name:$it") }
            item.tmdbId?.let { keys.add("tmdb:$name:$it") }
            item.tvdbId?.let { keys.add("tvdb:$name:$it") }
            if (imdb.isNotEmpty()) keys.add("imdb:$name:$imdb")
        }
        return keys
    }

    // MARK: - Scrobble

    suspend fun startTraktPlayback(item: MediaItem, progress: Double, episode: MediaEpisode?) =
        sendScrobble(item) { repos.trakt.startScrobble(it, item, episode, progress) }

    suspend fun pauseTraktPlayback(item: MediaItem, progress: Double, episode: MediaEpisode?) =
        sendScrobble(item) { repos.trakt.pauseScrobble(it, item, episode, progress) }

    suspend fun stopTraktPlayback(item: MediaItem, progress: Double, episode: MediaEpisode?) {
        sendScrobble(item) { repos.trakt.stopScrobble(it, item, episode, progress) }
        if (credentials.hasAnilist && episode != null) {
            val isAnime = item.type == MediaType.ANIME || item.isAnime || item.title == "One Pace"
            val anilistId = if (item.title == "One Pace") 21 else item.anilistId
            if (isAnime && anilistId != null) {
                runCatching {
                    repos.anime.updateAniListProgress(credentials.anilistAccessToken, anilistId, episode.episodeNumber, "CURRENT")
                }
            }
        }
    }

    private suspend fun sendScrobble(item: MediaItem, send: suspend (ApiCredentials) -> Unit) {
        if (!credentials.hasTraktUser || item.type == MediaType.LIVE_TV) return
        try { refreshTraktCredentialsIfNeeded(); send(credentials) }
        catch (t: Throwable) { message = "Could not update Trakt playback: $t" }
    }

    private suspend fun refreshTraktCredentialsIfNeeded() {
        val next = repos.trakt.ensureFreshAccessToken(credentials)
        if (next == credentials) return
        credentials = next
        credentialsStore.save(next)
    }

    // MARK: - Trakt connect

    fun startTraktBrowserAuth(): Uri? {
        val state = randomState()
        pendingTraktState = state
        traktConnecting = true
        message = "Opening Trakt sign in..."
        return repos.trakt.buildOAuthAuthorizeUri(credentials, state)?.let { Uri.parse(it) }
    }

    fun disconnectTrakt() {
        pendingTraktState = null; traktConnecting = false
        credentials = credentials.copy(traktAccessToken = "", traktRefreshToken = "", traktTokenExpiresAt = 0, traktUsername = "")
        credentialsStore.save(credentials)
        message = "Trakt disconnected."
    }

    suspend fun handleIncomingUri(uri: Uri) {
        // AniList token (fragment)
        if (uri.scheme == "omniplay" && uri.host == "anilist" && uri.path == "/oauth") {
            val frag = uri.fragment ?: uri.query ?: ""
            val params = frag.split("&").mapNotNull {
                val kv = it.split("=", limit = 2); if (kv.size == 2) kv[0] to kv[1] else null
            }.toMap()
            val token = params["access_token"]
            if (!token.isNullOrEmpty()) {
                credentials = credentials.copy(anilistAccessToken = token)
                saveCredentials(credentials)
                message = "AniList connected successfully!"
            }
            return
        }
        if (uri.scheme != "omniplay" || uri.host != "trakt" || uri.path != "/oauth") return
        val code = uri.getQueryParameter("code")
        if (!code.isNullOrEmpty()) {
            try {
                val next = repos.trakt.exchangeAuthorizationCode(credentials, code)
                saveTraktConnection(next)
            } catch (t: Throwable) { traktConnecting = false; message = "Trakt sign in failed: $t" }
        }
    }

    private suspend fun saveTraktConnection(next: ApiCredentials) {
        var withProfile = next
        runCatching { repos.trakt.fetchUserSettings(next) }.getOrNull()?.let { withProfile = it }
        credentials = withProfile
        credentialsStore.save(withProfile)
        pendingTraktState = null; traktConnecting = false
        // Auto-restore backup on first login.
        val payload = repos.trakt.fetchRemoteSettings(withProfile)?.trim()
        if (!payload.isNullOrEmpty()) {
            decodeBase64Json(payload)?.let { obj ->
                var c = withProfile
                obj.optStringOrNull("tmdb_token")?.let { c = c.copy(tmdbToken = it) }
                obj.optStringOrNull("tvdb_api_key")?.let { c = c.copy(tvdbApiKey = it) }
                obj.optStringOrNull("tvdb_pin")?.let { c = c.copy(tvdbPin = it) }
                obj.optStringOrNull("pixeldrain_api_key")?.let { c = c.copy(pixeldrainApiKey = it) }
                obj.optStringOrNull("anilist_access_token")?.let { c = c.copy(anilistAccessToken = it) }
                credentials = c; credentialsStore.save(c)
                obj.optObjectOrNull("settings")?.let { settings = settingsFromJson(it); settingsStore.saveSettings(settings) }
                obj.optArrayOrNull("watch_history")?.let {
                    mergeProgress(it.objects().mapNotNull { o -> watchProgressFromJson(o) }, preferRemoteTime = true)
                }
            }
        }
        message = if (withProfile.traktUsername.isEmpty()) "Trakt connected." else "Trakt connected as ${withProfile.traktUsername}."
        refreshTraktWatchlist()
    }

    // MARK: - Hero picks

    fun clearHeroCache() { heroPicksCache = emptyList() }

    val heroPicks: List<MediaItem>
        get() {
            if (heroPicksCache.isNotEmpty()) return heroPicksCache
            if (categories.isEmpty()) return emptyList()
            // Dedupe by CONTENT, not just the source-specific id — the same title
            // arrives from TMDB/Trakt/VidSrc with different ids, so keying on id let
            // duplicates through. Key on type + tmdbId/imdbId/title instead.
            val byKey = LinkedHashMap<String, MediaItem>()
            for (c in categories) if (c.type != MediaType.LIVE_TV && c.type != MediaType.ANIME) {
                for (item in c.items) if (!item.isAnime) {
                    val key = "${item.type.wire}:" + (item.tmdbId?.toString() ?: item.imdbId ?: item.title.lowercase())
                    if (byKey[key] == null) byKey[key] = item
                }
            }
            val withBackdrops = byKey.values.filter { it.heroBackdropUrl != null && it.overview.isNotEmpty() }
            val pool = (if (withBackdrops.isEmpty()) byKey.values.filter { it.posterUrl != null || it.backdropUrl != null } else withBackdrops)
                .sortedByDescending { heroScore(it) }
            val candidates = pool.take(25).shuffled()
            heroPicksCache = candidates.take(10)
            return heroPicksCache
        }

    private fun heroScore(item: MediaItem): Double {
        val voteWeight = ln((item.voteCount.coerceAtLeast(1)).toDouble() + 1)
        return item.rating * voteWeight + (if (item.heroBackdropUrl != null) 4 else 0)
    }

    // MARK: - Live TV sources

    suspend fun addLiveTvSource(name: String, url: String) {
        val uri = runCatching { Uri.parse(url.trim()) }.getOrNull()
        if (uri == null || uri.scheme.isNullOrEmpty() || uri.host.isNullOrEmpty()) {
            throw IllegalArgumentException("Enter a valid live TV URL.")
        }
        val title = name.trim().ifEmpty { uri.host!! }
        val source = LiveTvSource(id = System.nanoTime().toString(), name = title, url = uri.toString())
        liveTvSources.add(source)
        settingsStore.saveLiveTvSources(liveTvSources.toList())
    }

    suspend fun removeLiveTvSource(source: LiveTvSource) {
        val next = liveTvSources.filter { it.id != source.id }
        liveTvSources.clear(); liveTvSources.addAll(next)
        settingsStore.saveLiveTvSources(next)
    }

    suspend fun toggleLiveTvSource(source: LiveTvSource, enabled: Boolean) {
        val next = liveTvSources.map { if (it.id == source.id) it.copy(enabled = enabled) else it }
        liveTvSources.clear(); liveTvSources.addAll(next)
        settingsStore.saveLiveTvSources(next)
    }

    // MARK: - Live TV scan (iptv-org + M3U + Yarrlist + tv247 pipeline)

    fun cancelLiveTvScan() { isScanningLiveTv = false }

    fun startLiveTvScan() {
        scope.launch { runLiveTvScan() }
    }

    private suspend fun runLiveTvScan() = coroutineScope {
        isScanningLiveTv = true
        liveTvScanProgress = 0.0

        try {
            val parsedEntries = ArrayList<LiveTvEntry>()

            // 1) iptv-org channels.json + streams.json join.
            runCatching {
                val channelsResp = withTimeoutOrNull(15_000) { Http.request("https://iptv-org.github.io/api/channels.json") }
                val streamsResp = withTimeoutOrNull(15_000) { Http.request("https://iptv-org.github.io/api/streams.json") }
                if (channelsResp?.status == 200 && streamsResp?.status == 200) {
                    val channelsJson = JSONArray(channelsResp.body)
                    val streamsJson = JSONArray(streamsResp.body)
                    val channelMap = HashMap<String, JSONObject>()
                    for (o in channelsJson.objects()) o.optStringOrNull("id")?.let { channelMap[it] = o }

                    for (stream in streamsJson.objects()) {
                        val channelId = stream.optStringOrNull("channel") ?: continue
                        val url = stream.optStringOrNull("url") ?: continue
                        if (!url.lowercase().contains(".m3u8")) continue
                        val channelInfo = channelMap[channelId]
                        val languages = channelInfo?.optArrayOrNull("languages")?.stringList() ?: emptyList()
                        val hasTargetLanguage = languages.contains("eng") || languages.contains("hin") || languages.contains("ben")
                        if (!hasTargetLanguage) continue

                        val title = channelInfo?.optStringOrNull("name") ?: channelId
                        val logoUrl = "https://iptv-org.github.io/api/logos/$channelId.png"
                        val categoriesList = channelInfo?.optArrayOrNull("categories")?.stringList() ?: emptyList()
                        val titleLower = title.lowercase()
                        val isWestBengal = languages.contains("ben") || titleLower.contains("bengal") ||
                            titleLower.contains("kolkata") || titleLower.contains("bangla")

                        val finalCategories = ArrayList<String>()
                        if (isWestBengal) finalCategories.add("West Bengal / Bangla")
                        if (categoriesList.isNotEmpty()) finalCategories.addAll(categoriesList)
                        else if (!isWestBengal) finalCategories.add("General")
                        val genreString = finalCategories.map { it.trim() }.filter { it.isNotEmpty() }.joinToString(";")

                        val headers = HashMap<String, String>()
                        stream.optStringOrNull("http_referrer")?.takeIf { it.isNotEmpty() }?.let { headers["Referer"] = it }
                        val ua = stream.optStringOrNull("user_agent")
                        headers["User-Agent"] = if (!ua.isNullOrEmpty()) ua
                            else "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

                        parsedEntries.add(LiveTvEntry(
                            title = title, url = url, source = "iptv-org",
                            region = genreString.ifEmpty { "General" }, logoUrl = logoUrl, headers = headers,
                        ))
                    }
                }
            }

            // 2) Pre-rendered iptv-org M3U playlists, in parallel.
            runCatching {
                val m3uResults = IPTV_M3U_URLS.map { url ->
                    async {
                        runCatching {
                            val res = withTimeoutOrNull(10_000) {
                                repos.liveTv.fetchSource(LiveTvSource(id = "iptv-org-m3u-${url.hashCode()}", name = "IPTV Org M3U", url = url))
                            } ?: emptyList()
                            if (res.isNotEmpty()) {
                                val isEng = url.contains("languages/eng") || url.contains("countries/us") || url.contains("countries/gb")
                                val isIndia = url.contains("countries/in")
                                res.map { entry ->
                                    entry.copy(language = if (isEng) "eng" else if (isIndia) "hin;ben;eng" else entry.language)
                                }
                            } else emptyList()
                        }.getOrDefault(emptyList())
                    }
                }.awaitAll()

                for (res in m3uResults) {
                    if (res.isEmpty()) continue
                    val filtered = res.filter { entry ->
                        val tl = entry.title.lowercase()
                        val isBengali = tl.contains("bangla") || tl.contains("bengal") || tl.contains("kolkata") ||
                            tl.contains("jalsha") || tl.contains("aath") || tl.contains("ananda")
                        val isHindi = tl.contains("star plus") || tl.contains("sony sab") || tl.contains("zee tv") ||
                            tl.contains("colors") || tl.contains("dangal") || tl.contains("aaj tak") || tl.contains("news18 india")
                        val ll = entry.language.lowercase()
                        ll.contains("eng") || ll.contains("hin") || ll.contains("ben") || isBengali || isHindi ||
                            entry.source.lowercase().contains("india") || entry.source.lowercase().contains("us") ||
                            entry.source.lowercase().contains("uk") || entry.source.lowercase().contains("gb")
                    }
                    parsedEntries.addAll(filtered)
                }
            }

            // 3) Yarrlist live-TV playlists.
            runCatching {
                val yarrlistEntries = repos.yarrlist.fetchLiveTvDirectory()
                for (entry in yarrlistEntries) {
                    val u = entry.url
                    if (u.endsWith(".m3u") || u.endsWith(".m3u8") || u.contains("get.php") || u.contains("m3u")) {
                        runCatching {
                            val res = withTimeoutOrNull(10_000) {
                                repos.liveTv.fetchSource(LiveTvSource(id = "iptv-yarrlist-${u.hashCode()}", name = entry.title, url = u))
                            } ?: emptyList()
                            if (res.isNotEmpty()) parsedEntries.addAll(res)
                        }
                    }
                }
            }

            val dedupedPool = dedupeLiveTv(parsedEntries)
            if (dedupedPool.isEmpty() && parsedEntries.isEmpty()) {
                isScanningLiveTv = false
                hasScannedLiveTv = false
                message = "Scan complete. No channels found."
                return@coroutineScope
            }

            val tv247Channels = fetchTv247Channels()

            // 4) Probe channels in chunks with progress.
            val workingEntries = ArrayList<LiveTvEntry>()
            val total = dedupedPool.size
            val chunkSize = 25
            var i = 0
            while (i < total) {
                if (!isScanningLiveTv) break // user cancelled
                val chunk = dedupedPool.subList(i, minOf(i + chunkSize, total))
                val results = chunk.map { entry -> async { if (probeHead(entry)) entry else null } }.awaitAll()
                workingEntries.addAll(results.filterNotNull())
                liveTvScanProgress = (i + chunk.size).toDouble() / total
                i += chunkSize
            }

            if (workingEntries.isNotEmpty() || tv247Channels.isNotEmpty()) {
                val finalChannels = filterWorkingChannels(workingEntries)
                val combined = (finalChannels + tv247Channels).sortedWith(
                    compareBy({ it.region }, { it.title })
                )
                liveTv.clear(); liveTv.addAll(combined)
                settingsStore.saveCachedLiveTv(combined)
                hasScannedLiveTv = true
                message = "Scan complete! Found ${combined.size} active channels."
            } else {
                hasScannedLiveTv = false
                message = "Scan complete. None of the scanned channels responded."
            }
        } catch (t: Throwable) {
            hasScannedLiveTv = false
            message = "Scan failed: $t"
        } finally {
            isScanningLiveTv = false
        }
    }

    private suspend fun probeHead(entry: LiveTvEntry): Boolean = runCatching {
        val r = withTimeoutOrNull(1200) {
            Http.request(entry.url, method = "HEAD", headers = entry.headers, timeoutMs = 1200)
        } ?: return false
        r.status in 200..399
    }.getOrDefault(false)

    private fun dedupeLiveTv(entries: List<LiveTvEntry>): List<LiveTvEntry> {
        val seen = HashSet<String>()
        val result = ArrayList<LiveTvEntry>()
        for (entry in entries) {
            val key = entry.url.trim().lowercase()
            if (key.isEmpty() || !seen.add(key)) continue
            result.add(entry)
        }
        return result
    }

    private suspend fun filterWorkingChannels(entries: List<LiveTvEntry>): List<LiveTvEntry> = coroutineScope {
        val urlDeduped = dedupeLiveTv(entries)
        val grouped = LinkedHashMap<String, MutableList<LiveTvEntry>>()
        for (entry in urlDeduped) {
            val titleKey = entry.title.trim().lowercase()
            if (titleKey.isEmpty()) continue
            grouped.getOrPut(titleKey) { ArrayList() }.add(entry)
        }
        val result = ArrayList<LiveTvEntry>()
        val duplicateOptionLists = ArrayList<List<LiveTvEntry>>()
        for ((_, list) in grouped) {
            if (list.size == 1) result.add(list.first()) else duplicateOptionLists.add(list)
        }
        if (duplicateOptionLists.isNotEmpty()) {
            val resolved = duplicateOptionLists.map { options -> async { findFirstWorkingStream(options) } }.awaitAll()
            result.addAll(resolved)
        }
        result
    }

    private suspend fun findFirstWorkingStream(options: List<LiveTvEntry>): LiveTvEntry {
        for (entry in options) if (probeHead(entry)) return entry
        return options.first()
    }

    private suspend fun fetchTv247Channels(): List<LiveTvEntry> {
        val entries = ArrayList<LiveTvEntry>()
        runCatching {
            val response = withTimeoutOrNull(15_000) { Http.request("https://tv247.biz/tv-channels") }
            if (response?.status == 200) {
                val doc = org.jsoup.Jsoup.parse(response.body)
                for (anchor in doc.select("a")) {
                    val href = anchor.attr("href").trim()
                    val text = anchor.text().trim()
                    if (text.isEmpty() || href.isEmpty()) continue
                    val match = Regex("/tv/([^/]+)/?").find(href) ?: continue
                    val slug = match.groupValues[1]
                    val mainPageUrl = "https://tv247.biz/tv/$slug/"

                    var parent = anchor.parent()
                    var category = "US Channels"
                    while (parent != null) {
                        val h2 = parent.selectFirst("h2")
                        val h3 = parent.selectFirst("h3")
                        if (h2 != null) { category = h2.text().trim(); break }
                        else if (h3 != null) { category = h3.text().trim(); break }
                        parent = parent.parent()
                    }

                    val lowerCat = category.lowercase()
                    val isUsOrIndOrSports = lowerCat.contains("us") || lowerCat.contains("india") ||
                        lowerCat.contains("ind") || lowerCat.contains("sport")
                    if (isUsOrIndOrSports && !slug.contains("chat") && !slug.contains("tv-channels")) {
                        entries.add(LiveTvEntry(
                            title = text, url = mainPageUrl, source = "tv247.biz", region = category,
                            logoUrl = "https://raw.githubusercontent.com/m3u8playlist/tvlogo/master/logo/${slug.replace("-", "")}.png",
                        ))
                    }
                }
            }
        }

        val customEmbeds = listOf(
            "Star Sports Hindi" to "https://tv247.biz/tv/star-sports-hindi/",
            "Sony Ten 1" to "https://tv247.biz/tv/sony-ten-1/",
        )
        for ((name, url) in customEmbeds) {
            if (entries.none { it.url == url }) {
                entries.add(LiveTvEntry(
                    title = name, url = url, source = "tv247.biz", region = "Sports Channels",
                    logoUrl = "https://raw.githubusercontent.com/m3u8playlist/tvlogo/master/logo/${name.lowercase().replace(" ", "")}.png",
                ))
            }
        }
        return entries
    }

    // MARK: - Helpers

    private fun nonEmptyCategories(cats: List<MediaCategory>): List<MediaCategory> =
        cats.map { c -> c.copy(items = c.items.filter { it.posterPath != null || it.backdropPath != null }) }
            .filter { it.items.isNotEmpty() }

    private suspend fun enrichMetadataCategories(cats: List<MediaCategory>, maxItems: Int): List<MediaCategory> {
        if (!credentials.hasTmdb) return cats
        val out = ArrayList<MediaCategory>()
        for (c in cats) {
            val items = ArrayList<MediaItem>()
            c.items.forEachIndexed { i, item ->
                if (i < maxItems && canEnrich(item)) {
                    items.add(repos.tmdb.fetchDetails(item, credentials, settings) ?: item)
                } else items.add(item)
            }
            out.add(c.copy(items = items))
        }
        return out
    }

    private fun canEnrich(item: MediaItem): Boolean {
        if (item.tmdbId == null || item.type == MediaType.LIVE_TV) return false
        return item.posterPath == null || item.backdropPath == null || item.overview.isEmpty() || item.voteCount == 0
    }

    private fun categoryErrorMessage(cats: List<MediaCategory>, service: String): String? {
        for (c in cats) c.error?.takeIf { it.isNotEmpty() }?.let { return it }
        return if (cats.isEmpty()) "$service did not return rows. Showing cached rows." else null
    }

    private fun safeRefreshMessage(service: String, error: Throwable): String {
        val t = error.toString()
        return when {
            t.contains("401") || t.contains("403") -> "$service rejected the saved credentials. Check Settings."
            t.contains("429") -> "$service rate-limited this refresh. Showing cached rows."
            t.contains("timed out") || t.contains("unreachable") || t.contains("network") ->
                "$service is temporarily unreachable. Showing cached rows."
            else -> "$service refresh failed. Showing cached rows."
        }
    }

    private fun randomState(): String {
        val chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return (0 until 32).map { chars[Random.nextInt(chars.length)] }.joinToString("")
    }

    // MARK: - JSON conversion helpers for the Trakt backup payload

    private fun decodeBase64Json(payload: String): JSONObject? = runCatching {
        val bytes = Base64.decode(payload, Base64.DEFAULT)
        JSONObject(String(bytes, Charsets.UTF_8))
    }.getOrNull()

    private fun settingsToJson(s: UserSettings): JSONObject =
        JSONObject(appJson.encodeToString(UserSettings.serializer(), s))

    private fun settingsFromJson(json: JSONObject): UserSettings = runCatching {
        appJson.decodeFromString(UserSettings.serializer(), json.toString())
    }.getOrDefault(UserSettings())

    private fun watchProgressToJson(w: WatchProgress): JSONObject {
        val j = JSONObject()
        j.put("itemId", w.itemId)
        j.put("title", w.title)
        j.put("type", w.type.wire)
        j.put("positionMs", w.positionMs)
        j.put("durationMs", w.durationMs)
        j.put("lastWatchedAt", w.lastWatchedAt)
        w.id?.let { j.put("id", it) }
        w.posterPath?.let { j.put("posterPath", it) }
        w.backdropPath?.let { j.put("backdropPath", it) }
        w.seasonNumber?.let { j.put("seasonNumber", it) }
        w.episodeNumber?.let { j.put("episodeNumber", it) }
        w.episodeTitle?.let { j.put("episodeTitle", it) }
        return j
    }

    private fun watchProgressFromJson(j: JSONObject): WatchProgress? {
        val itemId = j.optStringOrNull("itemId") ?: return null
        return WatchProgress(
            id = j.optIntOrNull("id"),
            itemId = itemId,
            title = j.optStringOrNull("title") ?: "Untitled",
            type = MediaType.fromWire(j.optStringOrNull("type")),
            posterPath = j.optStringOrNull("posterPath"),
            backdropPath = j.optStringOrNull("backdropPath"),
            seasonNumber = j.optIntOrNull("seasonNumber"),
            episodeNumber = j.optIntOrNull("episodeNumber"),
            episodeTitle = j.optStringOrNull("episodeTitle"),
            positionMs = j.optIntOrNull("positionMs") ?: 0,
            durationMs = j.optIntOrNull("durationMs") ?: 0,
            lastWatchedAt = j.optLongOrNull("lastWatchedAt") ?: System.currentTimeMillis(),
        )
    }

    companion object {
        private val IPTV_M3U_URLS = listOf(
            // Free-TV/IPTV curated playlist (https://github.com/Free-TV/IPTV) — primary.
            "https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8",
            "https://iptv-org.github.io/iptv/languages/eng.m3u",
            "https://iptv-org.github.io/iptv/countries/in.m3u",
            "https://iptv-org.github.io/iptv/countries/us.m3u",
            "https://iptv-org.github.io/iptv/countries/gb.m3u",
            "https://iptv-org.github.io/iptv/categories/news.m3u",
            "https://iptv-org.github.io/iptv/categories/movies.m3u",
            "https://iptv-org.github.io/iptv/categories/sports.m3u",
            "https://iptv-org.github.io/iptv/categories/entertainment.m3u",
            "https://iptv-org.github.io/iptv/categories/music.m3u",
            "https://iptv-org.github.io/iptv/categories/kids.m3u",
            "https://iptv-org.github.io/iptv/categories/documentary.m3u",
            "https://iptv-org.github.io/iptv/categories/comedy.m3u",
            "https://iptv-org.github.io/iptv/categories/education.m3u",
            "https://iptv-org.github.io/iptv/categories/lifestyle.m3u",
            "https://iptv-org.github.io/iptv/categories/local.m3u",
            "https://iptv-org.github.io/iptv/categories/travel.m3u",
            "https://iptv-org.github.io/iptv/categories/weather.m3u",
            "https://iptv-org.github.io/iptv/categories/animation.m3u",
            "https://iptv-org.github.io/iptv/categories/drama.m3u",
            "https://iptv-org.github.io/iptv/categories/family.m3u",
            "https://iptv-org.github.io/iptv/categories/sci-fi.m3u",
        )
    }
}
