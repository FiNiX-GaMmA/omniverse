package com.finix.omniverse

import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.net.URLEncoder
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

/// Native port of the Flutter `TraktRepository`. Talks to the Trakt API
/// (https://api.trakt.tv/) for OAuth, discovery rows, watchlist sync, playback
/// progress, scrobbling and remote-settings storage. Faithful to
/// trakt_repository.dart — endpoints, headers, bodies and parsing preserved.
class TraktRepositoryImpl : TraktRepository {

    private val base = "https://api.trakt.tv/"

    class TraktException(message: String) : Exception(message)

    // MARK: - OAuth

    override fun buildOAuthAuthorizeUri(c: ApiCredentials, state: String): String? {
        if (!c.hasTraktApp) return null
        val params = listOf(
            "response_type" to "code",
            "client_id" to c.traktClientId,
            "redirect_uri" to REDIRECT_URI,
            "state" to state,
        )
        val qs = params.joinToString("&") { "${it.first}=${enc(it.second)}" }
        return "https://trakt.tv/oauth/authorize?$qs"
    }

    override suspend fun ensureFreshAccessToken(c: ApiCredentials): ApiCredentials {
        if (!c.hasTraktUser || c.traktTokenExpiresAt == 0L) return c
        val refreshAt = System.currentTimeMillis() + TOKEN_REFRESH_SKEW_MS
        if (c.traktTokenExpiresAt > refreshAt) return c
        if (!c.canRefreshTrakt) throw TraktException("Reconnect Trakt to refresh your OAuth session.")
        return refreshAccessToken(c)
    }

    override suspend fun exchangeAuthorizationCode(c: ApiCredentials, code: String): ApiCredentials {
        if (!c.hasTraktApp || c.traktClientSecret.trim().isEmpty()) {
            throw TraktException("Save your Trakt client ID and client secret first.")
        }
        val body = JSONObject()
            .put("code", code)
            .put("client_id", c.traktClientId.trim())
            .put("client_secret", c.traktClientSecret.trim())
            .put("redirect_uri", REDIRECT_URI)
            .put("grant_type", "authorization_code")
        return exchangeToken(c, body = body, failureLabel = "Trakt OAuth")
    }

    private suspend fun refreshAccessToken(c: ApiCredentials): ApiCredentials {
        if (!c.canRefreshTrakt) throw TraktException("Reconnect Trakt to refresh your OAuth session.")
        val body = JSONObject()
            .put("refresh_token", c.traktRefreshToken.trim())
            .put("client_id", c.traktClientId.trim())
            .put("client_secret", c.traktClientSecret.trim())
            .put("redirect_uri", REDIRECT_URI)
            .put("grant_type", "refresh_token")
        return exchangeToken(c, body = body, failureLabel = "Trakt token refresh")
    }

    override suspend fun startDeviceAuth(c: ApiCredentials): TraktDeviceCode {
        if (!c.hasTraktApp) throw TraktException("Save a Trakt client ID first.")
        // NOTE: client_id is NOT trimmed here, matching the Dart implementation.
        val r = postRaw("oauth/device/code", JSONObject().put("client_id", c.traktClientId),
            mapOf("Content-Type" to "application/json"))
        if (r.status >= 400) throw TraktException("Trakt device auth returned ${r.status}")
        val json = r.jsonObject()
        return TraktDeviceCode(
            deviceCode = json.optStringOrNull("device_code") ?: "",
            userCode = json.optStringOrNull("user_code") ?: "",
            verificationUrl = json.optStringOrNull("verification_url") ?: "",
            expiresIn = json.optIntOrNull("expires_in") ?: 0,
            interval = json.optIntOrNull("interval") ?: 0,
        )
    }

    override suspend fun completeDeviceAuth(c: ApiCredentials, code: TraktDeviceCode): ApiCredentials {
        val body = JSONObject()
            .put("code", code.deviceCode)
            .put("client_id", c.traktClientId.trim())
            .put("client_secret", c.traktClientSecret.trim())
        return exchangeToken(c, path = "oauth/device/token", body = body, failureLabel = "Trakt token request")
    }

    // MARK: - User settings

    override suspend fun fetchUserSettings(c: ApiCredentials): ApiCredentials {
        if (!c.hasTraktUser) return c
        val r = get("users/settings", c, query = mapOf("extended" to "browsing"))
        throwForResponse(r, "Trakt user settings")
        val user = r.jsonObject().optObjectOrNull("user") ?: JSONObject()
        return c.copy(traktUsername = user.optStringOrNull("username") ?: "")
    }

    // MARK: - Discovery

    override suspend fun fetchDiscoveryCategories(c: ApiCredentials): List<MediaCategory> = coroutineScope {
        if (!c.hasTraktApp) return@coroutineScope emptyList()
        val movies = async {
            discoveryCategory(c, "trakt_trending_movies", "Trending Movies on Trakt",
                "Movies with the most Trakt watchers right now", "movies/trending", MediaType.MOVIE, "movie")
        }
        val series = async {
            discoveryCategory(c, "trakt_trending_series", "Trending Shows on Trakt",
                "Shows with the most Trakt watchers right now", "shows/trending", MediaType.SERIES, "show")
        }
        listOf(movies.await(), series.await())
    }

    private suspend fun discoveryCategory(
        c: ApiCredentials, id: String, title: String, description: String,
        path: String, type: MediaType, mediaKey: String?,
    ): MediaCategory {
        return try {
            val r = get(path, c, includeAuth = false, query = mapOf("extended" to "full", "limit" to "18"))
            if (r.status >= 400) {
                return MediaCategory(id, title, type, emptyList(), description, "Trakt returned ${r.status}. Check your API key.")
            }
            val data = r.jsonArray()
            val items = ArrayList<MediaItem>()
            for (entry in data.objects()) {
                val mediaDict = if (mediaKey != null) entry.optObjectOrNull(mediaKey) else entry
                if (mediaDict == null) continue
                fromTraktMedia(mediaDict, type)?.let {
                    items.add(it)
                    if (items.size >= 18) return@discoveryCategory MediaCategory(id, title, type, items, description)
                }
            }
            MediaCategory(id, title, type, items, description)
        } catch (t: Throwable) {
            MediaCategory(id, title, type, emptyList(), description, "Could not load Trakt row: $t")
        }
    }

    // MARK: - Watchlist

    override suspend fun fetchWatchlist(c: ApiCredentials): List<MediaItem> {
        if (!c.hasTraktUser) return emptyList()
        val r = get("sync/watchlist", c, query = mapOf("extended" to "full"))
        throwForResponse(r, "Trakt watchlist")
        return r.jsonArray().objects().mapNotNull { fromWatchlist(it) }
    }

    override suspend fun setWatchlistItem(c: ApiCredentials, item: MediaItem, add: Boolean) {
        val body = bulkBodyFor(item) ?: return
        val r = post(if (add) "sync/watchlist" else "sync/watchlist/remove", c, body)
        if (r.status != 200 && r.status != 201) throwForResponse(r, "Trakt watchlist sync")
    }

    private fun fromWatchlist(json: JSONObject): MediaItem? {
        val movie = json.optObjectOrNull("movie")
        val show = json.optObjectOrNull("show")
        val value = movie ?: show ?: return null
        return fromTraktMedia(value, type = if (movie == null) MediaType.SERIES else MediaType.MOVIE)
    }

    // MARK: - Playback progress

    override suspend fun fetchPlaybackProgress(c: ApiCredentials): List<WatchProgress> {
        if (!c.hasTraktUser) return emptyList()
        return try {
            val r = get("sync/playback/movies,episodes", c, query = mapOf("extended" to "full"))
            if (r.status >= 400) return emptyList()
            val data = r.jsonArray()
            val now = System.currentTimeMillis()
            data.objects().mapNotNull { watchProgressFrom(it, now) }
        } catch (_: Throwable) {
            emptyList()
        }
    }

    private fun watchProgressFrom(entry: JSONObject, nowMs: Long): WatchProgress? {
        val progressPct = entry.optDoubleOrNull("progress") ?: 0.0
        val pausedAtMs = entry.optStringOrNull("paused_at")?.let { parseIso8601Ms(it) } ?: nowMs
        val episode = entry.optObjectOrNull("episode")
        val show = entry.optObjectOrNull("show")
        val movie = entry.optObjectOrNull("movie")
        val playbackId = entry.optIntOrNull("id")

        if (movie != null) {
            val ids = movie.optObjectOrNull("ids") ?: JSONObject()
            val title = movie.optStringOrNull("title") ?: ""
            val tmdb = ids.optIntOrNull("tmdb")
            val runtime = movie.optIntOrNull("runtime") ?: 0
            val durationMs = if (runtime > 0) runtime * 60 * 1000 else 100
            val positionMs = Math.round(progressPct * durationMs / 100).toInt()
            val itemId = if (tmdb != null) "tmdb:movie:$tmdb"
                else "trakt:movie:${ids.optIntOrNull("trakt")?.toString() ?: title}"
            return WatchProgress(
                id = playbackId, itemId = itemId, title = title, type = MediaType.MOVIE,
                positionMs = positionMs, durationMs = durationMs, lastWatchedAt = pausedAtMs,
            )
        }
        if (episode != null && show != null) {
            val ids = show.optObjectOrNull("ids") ?: JSONObject()
            val showTitle = show.optStringOrNull("title") ?: ""
            val season = episode.optIntOrNull("season") ?: 0
            val number = episode.optIntOrNull("number") ?: 0
            val epTitle = episode.optStringOrNull("title")
            val runtime = episode.optIntOrNull("runtime") ?: show.optIntOrNull("runtime") ?: 0
            val durationMs = if (runtime > 0) runtime * 60 * 1000 else 100
            val positionMs = Math.round(progressPct * durationMs / 100).toInt()
            val tmdb = ids.optIntOrNull("tmdb")
            val itemId = if (tmdb != null) "tmdb:series:$tmdb"
                else "trakt:series:${ids.optIntOrNull("trakt")?.toString() ?: showTitle}"
            return WatchProgress(
                id = playbackId, itemId = itemId, title = showTitle, type = MediaType.SERIES,
                seasonNumber = season, episodeNumber = number, episodeTitle = epTitle,
                positionMs = positionMs, durationMs = durationMs, lastWatchedAt = pausedAtMs,
            )
        }
        return null
    }

    override suspend fun deletePlaybackProgress(c: ApiCredentials, playbackId: Int) {
        if (!c.hasTraktUser) return
        val r = Http.request(base + "sync/playback/$playbackId", method = "DELETE",
            headers = headers(c, includeAuth = true))
        if (r.status != 204 && r.status != 200) throwForResponse(r, "Trakt playback delete")
    }

    // MARK: - Scrobble

    override suspend fun startScrobble(c: ApiCredentials, item: MediaItem, episode: MediaEpisode?, progress: Double) =
        scrobble(c, item, episode, "start", progress)
    override suspend fun pauseScrobble(c: ApiCredentials, item: MediaItem, episode: MediaEpisode?, progress: Double) =
        scrobble(c, item, episode, "pause", progress)
    override suspend fun stopScrobble(c: ApiCredentials, item: MediaItem, episode: MediaEpisode?, progress: Double) =
        scrobble(c, item, episode, "stop", progress)

    private suspend fun scrobble(c: ApiCredentials, item: MediaItem, episode: MediaEpisode?, action: String, progress: Double) {
        val body = scrobbleBody(item, episode, progress) ?: return
        if (action == "stop" && body.optDoubleOrNull("progress")?.let { it < 1 } == true) return
        val r = post("scrobble/$action", c, body)
        if (r.status == 409) return
        if (r.status != 200 && r.status != 201) throwForResponse(r, "Trakt scrobble")
    }

    private fun scrobbleBody(item: MediaItem, episode: MediaEpisode?, progress: Double): JSONObject? {
        if (item.type == MediaType.MOVIE) {
            val ids = idsFor(item, includeTvdb = false)
            if (ids.length() == 0) return null
            return JSONObject().put("movie", JSONObject().put("ids", ids)).put("progress", cleanProgress(progress))
        } else if (episode != null) {
            val showIds = idsFor(item, includeTvdb = false)
            if (showIds.length() == 0) return null
            val originalSeason = if (episode.seasonNumber >= 1000) episode.seasonNumber / 1000 else episode.seasonNumber
            return JSONObject()
                .put("show", JSONObject().put("ids", showIds))
                .put("episode", JSONObject().put("season", originalSeason).put("number", episode.episodeNumber))
                .put("progress", cleanProgress(progress))
        }
        return null
    }

    // MARK: - Remote settings

    override suspend fun fetchRemoteSettings(c: ApiCredentials): String? {
        if (!c.hasTraktUser) return null
        return try {
            val r = get("users/me/lists", c)
            if (r.status >= 400) return null
            for (list in r.jsonArray().objects()) {
                if (list.optStringOrNull("name") == "Omniverse Sync") return list.optStringOrNull("description")
            }
            null
        } catch (_: Throwable) {
            null
        }
    }

    override suspend fun saveRemoteSettings(c: ApiCredentials, payload: String) {
        if (!c.hasTraktUser) return

        val listResponse = get("users/me/lists", c)
        var existingListId: Int? = null
        if (listResponse.status == 200) {
            for (list in listResponse.jsonArray().objects()) {
                if (list.optStringOrNull("name") == "Omniverse Sync") {
                    existingListId = list.optObjectOrNull("ids")?.optIntOrNull("trakt")
                    break
                }
            }
        }

        val body = JSONObject()
            .put("name", "Omniverse Sync")
            .put("description", payload)
            .put("privacy", "private")

        if (existingListId != null) {
            val r = Http.request(base + "users/me/lists/$existingListId", method = "PUT",
                headers = headers(c, includeAuth = true),
                body = body.toString().toRequestBody(JSON_MEDIA))
            throwForResponse(r, "Trakt settings update")
        } else {
            val r = post("users/me/lists", c, body)
            throwForResponse(r, "Trakt settings create")
        }
    }

    // MARK: - Trakt media parsing

    private fun fromTraktMedia(value: JSONObject, type: MediaType): MediaItem? {
        val ids = value.optObjectOrNull("ids") ?: JSONObject()
        val title = value.optStringOrNull("title") ?: value.optStringOrNull("name")
        if (title.isNullOrEmpty()) return null
        val year = value.optIntOrNull("year")
        val firstAired = value.optStringOrNull("first_aired")
        val releaseDate = firstAired ?: year?.toString() ?: ""
        val idSuffix = ids.optIntOrNull("trakt")?.toString() ?: value.optStringOrNull("title") ?: title
        return MediaItem(
            id = "trakt:${type.wire}:$idSuffix",
            type = type,
            title = title,
            overview = value.optStringOrNull("overview") ?: "",
            releaseDate = releaseDate,
            rating = value.optDoubleOrNull("rating") ?: 0.0,
            voteCount = value.optIntOrNull("votes") ?: 0,
            traktId = ids.optIntOrNull("trakt"),
            tvdbId = ids.optIntOrNull("tvdb"),
            tmdbId = ids.optIntOrNull("tmdb"),
            imdbId = ids.optStringOrNull("imdb"),
            source = "trakt",
        )
    }

    // MARK: - Bulk (watchlist) bodies

    private fun bulkBodyFor(item: MediaItem): JSONObject? {
        val entry = bulkEntryFor(item) ?: return null
        return when (item.type) {
            MediaType.MOVIE -> JSONObject().put("movies", JSONArray().put(entry))
            MediaType.SERIES -> JSONObject().put("shows", JSONArray().put(entry))
            MediaType.ANIME -> JSONObject().put("shows", JSONArray().put(entry))
            MediaType.LIVE_TV -> null
        }
    }

    private fun bulkEntryFor(item: MediaItem): JSONObject? {
        val ids = idsFor(item, includeTvdb = item.type == MediaType.SERIES || item.type == MediaType.ANIME)
        if (ids.length() != 0) return JSONObject().put("ids", ids)
        val year = releaseYear(item.releaseDate) ?: return null
        return JSONObject().put("title", item.title).put("year", year)
    }

    private fun idsFor(item: MediaItem, includeTvdb: Boolean): JSONObject {
        val ids = JSONObject()
        item.traktId?.let { ids.put("trakt", it) }
        item.imdbId?.trim()?.takeIf { it.isNotEmpty() }?.let { ids.put("imdb", it) }
        item.tmdbId?.let { ids.put("tmdb", it) }
        if (includeTvdb) item.tvdbId?.let { ids.put("tvdb", it) }
        return ids
    }

    private fun releaseYear(value: String): Int? =
        Regex("\\d{4}").find(value)?.value?.toIntOrNull()

    private fun cleanProgress(progress: Double): Double {
        val clamped = progress.coerceIn(0.0, 100.0)
        return String.format(Locale.US, "%.2f", clamped).toDoubleOrNull() ?: clamped
    }

    // MARK: - Token exchange

    private suspend fun exchangeToken(c: ApiCredentials, path: String = "oauth/token", body: JSONObject, failureLabel: String): ApiCredentials {
        // Token endpoints use Content-Type only (no api-key / auth headers).
        val r = postRaw(path, body, mapOf("Content-Type" to "application/json"))
        throwForResponse(r, failureLabel)
        return credentialsFromToken(c, r.jsonObject())
    }

    private fun credentialsFromToken(c: ApiCredentials, json: JSONObject): ApiCredentials {
        val createdAtSeconds = json.optIntOrNull("created_at") ?: (System.currentTimeMillis() / 1000).toInt()
        val expiresIn = json.optIntOrNull("expires_in") ?: 0
        val expiresAt = if (expiresIn <= 0) 0L else (createdAtSeconds.toLong() + expiresIn) * 1000
        return c.copy(
            traktAccessToken = json.optStringOrNull("access_token") ?: "",
            traktRefreshToken = json.optStringOrNull("refresh_token") ?: "",
            traktTokenExpiresAt = expiresAt,
        )
    }

    // MARK: - HTTP plumbing

    private suspend fun get(path: String, c: ApiCredentials, query: Map<String, String> = emptyMap(), includeAuth: Boolean = true): Http.Response {
        return Http.request(resolve(path, query), method = "GET", headers = headers(c, includeAuth))
    }

    private suspend fun post(path: String, c: ApiCredentials, body: JSONObject, includeAuth: Boolean = true): Http.Response {
        return Http.request(resolve(path, emptyMap()), method = "POST", headers = headers(c, includeAuth),
            body = body.toString().toRequestBody(JSON_MEDIA))
    }

    private suspend fun postRaw(path: String, body: JSONObject, headers: Map<String, String>): Http.Response {
        return Http.request(resolve(path, emptyMap()), method = "POST", headers = headers,
            body = body.toString().toRequestBody(JSON_MEDIA))
    }

    private fun resolve(path: String, query: Map<String, String>): String {
        val full = if (path.startsWith("http")) path else base + path.removePrefix("/")
        if (query.isEmpty()) return full
        val qs = query.entries.joinToString("&") { "${it.key}=${enc(it.value)}" }
        return "$full?$qs"
    }

    private fun headers(c: ApiCredentials, includeAuth: Boolean): Map<String, String> {
        val h = HashMap<String, String>()
        h["Content-Type"] = "application/json"
        h["trakt-api-version"] = "2"
        if (c.hasTraktApp) h["trakt-api-key"] = c.traktClientId.trim()
        if (includeAuth && c.hasTraktUser) h["Authorization"] = "Bearer ${c.traktAccessToken.trim()}"
        return h
    }

    private fun throwForResponse(r: Http.Response, label: String) {
        if (r.status < 400) return
        throw TraktException("$label returned ${r.status}: ${r.body}")
    }

    private fun enc(value: String): String = URLEncoder.encode(value, "UTF-8")

    // MARK: - Date parsing

    private fun parseIso8601Ms(s: String): Long? {
        val formats = listOf("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", "yyyy-MM-dd'T'HH:mm:ss'Z'")
        for (fmt in formats) {
            try {
                val sdf = SimpleDateFormat(fmt, Locale.US)
                sdf.timeZone = TimeZone.getTimeZone("UTC")
                return sdf.parse(s)?.time
            } catch (_: Throwable) { /* try next */ }
        }
        return null
    }

    companion object {
        private const val REDIRECT_URI = "omniplay://trakt/oauth"
        private const val TOKEN_REFRESH_SKEW_MS = 5L * 60 * 1000
        private val JSON_MEDIA = "application/json; charset=utf-8".toMediaType()
    }
}
