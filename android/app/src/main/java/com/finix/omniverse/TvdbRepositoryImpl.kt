package com.finix.omniverse

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject

/// TheTVDB v4 client. Ported from tvdb_repository.dart.
class TvdbRepositoryImpl : TvdbRepository {

    private val base = "https://api4.thetvdb.com/v4/"

    // Token cache (valid ~28 days).
    private var token: String? = null
    private var tokenExpiresAtMs: Long = 0
    private val tokenMutex = Mutex()

    override suspend fun validate(credentials: ApiCredentials): Boolean {
        if (!credentials.hasTvdb) return false
        return try { ensureToken(credentials); true } catch (_: Throwable) { false }
    }

    override suspend fun enrichDetails(item: MediaItem, credentials: ApiCredentials): MediaItem {
        if (!credentials.hasTvdb || item.type == MediaType.LIVE_TV) return item
        return try {
            val token = ensureToken(credentials)
            val tvdbId = item.tvdbId ?: findTvdbId(item, token) ?: return item
            val path = if (item.type == MediaType.MOVIE) "movies/$tvdbId/extended" else "series/$tvdbId/extended"
            val response = Http.request(base + path, headers = authHeaders(token), timeoutMs = 12_000)
            if (response.status >= 400) return item.copy(tvdbId = tvdbId)
            val data = response.jsonObject().optObjectOrNull("data") ?: return item.copy(tvdbId = tvdbId)
            mergeExtended(item, data, tvdbId)
        } catch (_: Throwable) {
            item
        }
    }

    override suspend fun fetchSeasonEpisodes(item: MediaItem, seasonNumber: Int, credentials: ApiCredentials): List<MediaEpisode> {
        if (!credentials.hasTvdb || item.type != MediaType.SERIES) return emptyList()
        return try {
            val token = ensureToken(credentials)
            val tvdbId = item.tvdbId ?: findTvdbId(item, token) ?: return emptyList()
            val response = Http.request(base + "series/$tvdbId/episodes/default/eng", headers = authHeaders(token), timeoutMs = 12_000)
            if (response.status >= 400) return emptyList()
            val data = response.jsonObject().optObjectOrNull("data") ?: return emptyList()
            val episodes = data.optArrayOrNull("episodes") ?: return emptyList()
            episodes.objects()
                .filter { it.optIntOrNull("seasonNumber") == seasonNumber }
                .map { episode ->
                    MediaEpisode(
                        seasonNumber = episode.optIntOrNull("seasonNumber") ?: seasonNumber,
                        episodeNumber = episode.optIntOrNull("number") ?: 0,
                        title = episode.optStringOrNull("name") ?: "Episode",
                        overview = episode.optStringOrNull("overview") ?: "",
                        airDate = episode.optStringOrNull("aired") ?: episode.optStringOrNull("firstAired") ?: "",
                        runtimeMinutes = episode.optIntOrNull("runtime"),
                        stillPath = episode.optStringOrNull("image"),
                    )
                }
                .filter { it.episodeNumber > 0 }
        } catch (_: Throwable) {
            emptyList()
        }
    }

    // MARK: Token

    private suspend fun ensureToken(credentials: ApiCredentials): String = tokenMutex.withLock {
        token?.let { if (System.currentTimeMillis() < tokenExpiresAtMs) return it }
        val payload = JSONObject()
        payload.put("apikey", credentials.tvdbApiKey.trim())
        if (credentials.tvdbPin.trim().isNotEmpty()) payload.put("pin", credentials.tvdbPin.trim())
        val response = Http.postJson(base + "login", payload, timeoutMs = 12_000)
        if (response.status >= 400) throw TvdbException("TVDB returned ${response.status}")
        val t = response.jsonObject().optObjectOrNull("data")?.optStringOrNull("token")
        if (t.isNullOrEmpty()) throw TvdbException("TVDB login response did not include token.")
        token = t
        tokenExpiresAtMs = System.currentTimeMillis() + 28L * 24 * 60 * 60 * 1000
        t
    }

    // MARK: Remote id lookup

    private suspend fun findTvdbId(item: MediaItem, token: String): Int? {
        val remoteIds = ArrayList<String>()
        item.imdbId?.trim()?.takeIf { it.isNotEmpty() }?.let { remoteIds.add(it) }
        item.tmdbId?.let { remoteIds.add(it.toString()) }

        for (remoteId in remoteIds) {
            val response = try { Http.request(base + "search/remoteid/$remoteId", headers = authHeaders(token), timeoutMs = 12_000) }
                catch (_: Throwable) { continue }
            if (response.status >= 400) continue
            val data = response.jsonObject().optArrayOrNull("data") ?: continue
            for (result in data.objects()) {
                val type = (result.optStringOrNull("type") ?: "").lowercase()
                val typeMatches = (item.type == MediaType.MOVIE && type.contains("movie")) ||
                    ((item.type == MediaType.SERIES || item.type == MediaType.ANIME) && type.contains("series"))
                if (!typeMatches && type.isNotEmpty()) continue
                (result.optIntOrNull("tvdb_id") ?: result.optIntOrNull("id"))?.let { return it }
            }
        }
        return null
    }

    // MARK: Merge

    private fun mergeExtended(item: MediaItem, data: JSONObject, tvdbId: Int): MediaItem {
        val genres = (data.optArrayOrNull("genres")?.objects() ?: emptyList())
            .mapNotNull { it.optStringOrNull("name") }.filter { it.isNotEmpty() }
        val artworks = data.optArrayOrNull("artworks")?.objects() ?: emptyList()
        val poster = item.posterPath ?: data.optStringOrNull("image")
        val backdrop = item.backdropPath ?: bestArtwork(artworks)

        return item.copy(
            overview = if (item.overview.isEmpty()) (data.optStringOrNull("overview") ?: "") else item.overview,
            posterPath = poster,
            backdropPath = backdrop,
            genres = if (item.genres.isEmpty()) genres else item.genres,
            runtimeMinutes = item.runtimeMinutes ?: data.optIntOrNull("averageRuntime") ?: data.optIntOrNull("runtime"),
            tvdbId = tvdbId,
        )
    }

    private fun bestArtwork(artworks: List<JSONObject>): String? {
        for (artwork in artworks) {
            val image = artwork.optStringOrNull("image")
            if (!image.isNullOrEmpty()) return image
        }
        return null
    }

    private fun authHeaders(token: String): Map<String, String> =
        mapOf("Authorization" to "Bearer $token", "Accept" to "application/json")
}

private class TvdbException(message: String) : Exception(message)
