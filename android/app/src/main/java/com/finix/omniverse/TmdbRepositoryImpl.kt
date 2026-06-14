package com.finix.omniverse

import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.sync.withPermit
import org.json.JSONObject
import java.net.URLEncoder
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

class TmdbNetworkException(message: String) : Exception(message)

// MARK: - MediaItem.fromTmdb (mirrors models.dart MediaItem.fromTmdb)

internal fun mediaItemFromTmdb(json: JSONObject, type: MediaType, genreNames: Map<Int, String> = emptyMap()): MediaItem? {
    val id = json.optIntOrNull("id") ?: return null
    val title = json.optStringOrNull("title") ?: json.optStringOrNull("name") ?: "Untitled"
    val date = json.optStringOrNull("release_date") ?: json.optStringOrNull("first_air_date") ?: ""
    val genreIds = json.optArrayOrNull("genre_ids")?.intList() ?: emptyList()
    val genres = genreIds.mapNotNull { genreNames[it] }
    val originCountry = json.optArrayOrNull("origin_country")?.stringList() ?: emptyList()
    return MediaItem(
        id = "tmdb:${type.wire}:$id",
        type = type,
        title = title,
        overview = json.optStringOrNull("overview") ?: "",
        posterPath = json.optStringOrNull("poster_path"),
        backdropPath = json.optStringOrNull("backdrop_path"),
        releaseDate = date,
        rating = json.optDoubleOrNull("vote_average") ?: 0.0,
        voteCount = json.optIntOrNull("vote_count") ?: 0,
        genres = genres,
        originCountry = originCountry,
        tmdbId = id,
    )
}

class TmdbRepositoryImpl : TmdbRepository {

    private val base = "https://api.themoviedb.org/3/"

    private data class CachedResponse(val response: Http.Response, val expiresAtMs: Long)

    private val cache = HashMap<String, CachedResponse>()
    private val cacheMutex = Mutex()
    private val gate = Semaphore(MAX_INFLIGHT)

    // MARK: Landing categories

    override suspend fun fetchLandingCategories(credentials: ApiCredentials, settings: UserSettings): List<MediaCategory> {
        if (!credentials.hasTmdb) return demoCategories

        val (movieGenres, tvGenres) = fetchGenres(credentials, settings)
        val categories = ArrayList<MediaCategory>()
        categories.add(category("trending_movies", "Trending Movies",
            "What people are watching this week", "trending/movie/week", MediaType.MOVIE,
            credentials, settings, movieGenres))
        categories.add(category("now_playing", "Now Playing",
            "Current theatrical and recent movie releases", "movie/now_playing", MediaType.MOVIE,
            credentials, settings, movieGenres))
        categories.add(category("action_movies", "Action Movies",
            "High-energy movies from TMDB Discover", "discover/movie", MediaType.MOVIE,
            credentials, settings, movieGenres, mapOf("with_genres" to "28", "sort_by" to "popularity.desc")))
        categories.add(category("trending_series", "Trending TV Shows",
            "Series gaining momentum this week", "trending/tv/week", MediaType.SERIES,
            credentials, settings, tvGenres))
        categories.add(category("airing_today", "Airing Today",
            "Episodes scheduled today", "tv/airing_today", MediaType.SERIES,
            credentials, settings, tvGenres))
        categories.add(category("top_rated_series", "Top Rated TV",
            "Well-loved shows with strong audience scores", "tv/top_rated", MediaType.SERIES,
            credentials, settings, tvGenres))
        return categories
    }

    // MARK: Details

    override suspend fun fetchDetails(item: MediaItem, credentials: ApiCredentials, settings: UserSettings): MediaItem? {
        val tmdbId = item.tmdbId
        if (!credentials.hasTmdb || tmdbId == null) return item
        val url = uri("${item.type.tmdbPath}/$tmdbId", credentials, settings, mapOf(
            "append_to_response" to "external_ids,credits,images",
            "include_image_language" to imageLanguages(settings),
        ))
        val response = try { get(url, credentials) } catch (_: Throwable) { return item }
        if (response.status >= 400) return item
        val json = response.jsonObject()

        val images = json.optObjectOrNull("images")
        val posterPath = bestImagePath(images?.optArrayOrNull("posters"),
            json.optStringOrNull("poster_path") ?: item.posterPath, 2.0 / 3.0)
        val backdropPath = bestImagePath(images?.optArrayOrNull("backdrops"),
            json.optStringOrNull("backdrop_path") ?: item.backdropPath, 16.0 / 9.0)

        val seasons = seasonsFrom(json)
        val firstSeason = seasons.firstOrNull { it.seasonNumber > 0 }
        var episodes: List<MediaEpisode> = emptyList()
        if (item.type == MediaType.SERIES && firstSeason != null) {
            val fallback = if (item.tmdbId == null) item.copy(tmdbId = json.optIntOrNull("id")) else item
            episodes = fetchSeasonEpisodes(fallback, firstSeason.seasonNumber, credentials, settings)
        }

        val externalIds = json.optObjectOrNull("external_ids")

        val origin = ArrayList<String>()
        json.optArrayOrNull("origin_country")?.stringList()?.let { origin.addAll(it) }
        json.optArrayOrNull("production_countries")?.objects()
            ?.mapNotNull { it.optStringOrNull("iso_3166_1") }
            ?.filter { it.isNotEmpty() }
            ?.let { origin.addAll(it) }

        val genres = json.optArrayOrNull("genres")?.objects()
            ?.mapNotNull { it.optStringOrNull("name") }
            ?.filter { it.isNotEmpty() } ?: emptyList()

        return MediaItem(
            id = item.id,
            type = item.type,
            title = json.optStringOrNull("title") ?: json.optStringOrNull("name") ?: item.title,
            overview = json.optStringOrNull("overview") ?: item.overview,
            posterPath = posterPath,
            backdropPath = backdropPath,
            releaseDate = json.optStringOrNull("release_date") ?: json.optStringOrNull("first_air_date") ?: item.releaseDate,
            rating = json.optDoubleOrNull("vote_average") ?: item.rating,
            voteCount = json.optIntOrNull("vote_count") ?: item.voteCount,
            genres = genres,
            originCountry = origin,
            cast = castFrom(json),
            directors = directorsFrom(json),
            runtimeMinutes = runtimeFrom(json, item.type),
            seasons = seasons,
            episodes = episodes,
            tmdbId = item.tmdbId,
            tvdbId = externalIds?.optIntOrNull("tvdb_id") ?: item.tvdbId,
            traktId = item.traktId,
            imdbId = externalIds?.optStringOrNull("imdb_id") ?: json.optStringOrNull("imdb_id") ?: item.imdbId,
            source = item.source,
        )
    }

    // MARK: Search

    override suspend fun searchMulti(query: String, credentials: ApiCredentials, settings: UserSettings): List<MediaItem> = coroutineScope {
        val trimmed = query.trim()
        if (trimmed.isEmpty() || !credentials.hasTmdb) return@coroutineScope emptyList()

        val url1 = uri("search/multi", credentials, settings, mapOf("query" to trimmed, "page" to "1"))
        val url2 = uri("search/multi", credentials, settings, mapOf("query" to trimmed, "page" to "2"))
        val p1 = async { runCatching { get(url1, credentials) }.getOrNull() }
        val p2 = async { runCatching { get(url2, credentials) }.getOrNull() }
        val pages = listOfNotNull(p1.await(), p2.await())

        val results = ArrayList<MediaItem>()
        val seen = HashSet<String>()
        for (response in pages) {
            if (response.status >= 400) continue
            val body = response.jsonObject()
            for (dict in (body.optArrayOrNull("results")?.objects() ?: emptyList())) {
                val mediaType = dict.optStringOrNull("media_type")
                val type = when (mediaType) {
                    "movie" -> MediaType.MOVIE
                    "tv" -> MediaType.SERIES
                    else -> continue
                }
                val mediaItem = mediaItemFromTmdb(dict, type) ?: continue
                if (mediaItem.posterPath == null && mediaItem.backdropPath == null) continue
                if (!seen.add(mediaItem.id)) continue
                results.add(mediaItem)
            }
        }
        results.take(40)
    }

    // MARK: Season episodes

    override suspend fun fetchSeasonEpisodes(item: MediaItem, seasonNumber: Int, credentials: ApiCredentials, settings: UserSettings): List<MediaEpisode> {
        val tmdbId = item.tmdbId
        if (!credentials.hasTmdb || item.type != MediaType.SERIES || tmdbId == null) return emptyList()
        val response = try { get(uri("tv/$tmdbId/season/$seasonNumber", credentials, settings), credentials) }
            catch (_: Throwable) { return emptyList() }
        if (response.status >= 400) return emptyList()
        val json = response.jsonObject()
        return (json.optArrayOrNull("episodes")?.objects() ?: emptyList()).map { episode ->
            MediaEpisode(
                seasonNumber = episode.optIntOrNull("season_number") ?: seasonNumber,
                episodeNumber = episode.optIntOrNull("episode_number") ?: 0,
                title = episode.optStringOrNull("name") ?: "Episode",
                overview = episode.optStringOrNull("overview") ?: "",
                airDate = episode.optStringOrNull("air_date") ?: "",
                runtimeMinutes = episode.optIntOrNull("runtime"),
                stillPath = episode.optStringOrNull("still_path"),
            )
        }
    }

    /// TMDB "more like this" recommendations for a movie/series, powering the
    /// end-of-show recommendation rail when there are no more episodes.
    override suspend fun fetchRecommendations(item: MediaItem, credentials: ApiCredentials, settings: UserSettings): List<MediaItem> {
        val tmdbId = item.tmdbId
        if (!credentials.hasTmdb || tmdbId == null) return emptyList()
        val type = if (item.type == MediaType.MOVIE) MediaType.MOVIE else MediaType.SERIES
        val response = try { get(uri("${type.tmdbPath}/$tmdbId/recommendations", credentials, settings), credentials) }
            catch (_: Throwable) { return emptyList() }
        if (response.status >= 400) return emptyList()
        return (response.jsonObject().optArrayOrNull("results")?.objects() ?: emptyList())
            .filter { it.optStringOrNull("media_type") != "person" }
            .mapNotNull { mediaItemFromTmdb(it, type) }
            .filter { it.posterPath != null || it.backdropPath != null }
            .take(18)
    }

    // MARK: Genres

    private suspend fun fetchGenres(credentials: ApiCredentials, settings: UserSettings): Pair<Map<Int, String>, Map<Int, String>> = coroutineScope {
        suspend fun fetch(path: String): Map<Int, String> {
            val response = try { get(uri(path, credentials, settings), credentials) } catch (_: Throwable) { return emptyMap() }
            if (response.status >= 400) return emptyMap()
            val map = HashMap<Int, String>()
            for (g in (response.jsonObject().optArrayOrNull("genres")?.objects() ?: emptyList())) {
                val gid = g.optIntOrNull("id") ?: continue
                val name = g.optStringOrNull("name") ?: continue
                map[gid] = name
            }
            return map
        }
        val movie = async { fetch("genre/movie/list") }
        val tv = async { fetch("genre/tv/list") }
        Pair(movie.await(), tv.await())
    }

    // MARK: Category builder

    private suspend fun category(
        id: String, title: String, description: String, path: String, type: MediaType,
        credentials: ApiCredentials, settings: UserSettings, genreNames: Map<Int, String>,
        query: Map<String, String> = emptyMap(),
    ): MediaCategory {
        return try {
            val response = get(uri(path, credentials, settings, query), credentials)
            if (response.status >= 400) {
                return MediaCategory(id, title, type, emptyList(), description, statusMessage(response.status))
            }
            val items = (response.jsonObject().optArrayOrNull("results")?.objects() ?: emptyList())
                .filter { it.optStringOrNull("media_type") != "person" }
                .mapNotNull { mediaItemFromTmdb(it, type, genreNames) }
                .filter { it.posterPath != null || it.backdropPath != null }
                .take(18)
            MediaCategory(id, title, type, items, description)
        } catch (t: Throwable) {
            MediaCategory(id, title, type, emptyList(), description, friendlyError(t))
        }
    }

    override suspend fun validate(credentials: ApiCredentials, settings: UserSettings): Boolean {
        if (!credentials.hasTmdb) return false
        return try {
            val response = get(uri("genre/movie/list", credentials, settings), credentials)
            response.status in 200..299
        } catch (_: Throwable) {
            false
        }
    }

    override suspend fun fetchStudioMovies(studio: String, credentials: ApiCredentials, settings: UserSettings): List<MediaItem> {
        if (!credentials.hasTmdb) return emptyList()
        val companyId = when (studio.lowercase()) {
            "disney" -> "2" // Walt Disney Pictures
            "netflix" -> "178464" // Netflix Movies
            "hbo" -> "174" // Warner Bros. (HBO Max Movie parent)
            "prime" -> "20580" // Amazon Studios
            "apple" -> "194303" // Apple Studios
            "paramount" -> "4" // Paramount Pictures
            "hulu" -> "164090" // Hulu Originals
            "peacock" -> "161044" // Universal/Peacock Movies
            "marvel" -> "420" // Marvel Studios
            "warner" -> "174" // Warner Bros. Pictures
            "universal" -> "33" // Universal Pictures
            "sony" -> "5" // Columbia Pictures
            "crunchyroll" -> "11444" // Crunchyroll Movies
            else -> null
        } ?: return emptyList()
        return try {
            val url = uri("discover/movie", credentials, settings, mapOf("with_companies" to companyId))
            val response = get(url, credentials)
            if (response.status >= 400) return emptyList()
            val (movieGenres, _) = fetchGenres(credentials, settings)
            (response.jsonObject().optArrayOrNull("results")?.objects() ?: emptyList())
                .mapNotNull { mediaItemFromTmdb(it, MediaType.MOVIE, movieGenres) }
                .filter { it.posterPath != null || it.backdropPath != null }
                .take(18)
        } catch (_: Throwable) {
            emptyList()
        }
    }

    override suspend fun fetchStudioTVShows(studio: String, credentials: ApiCredentials, settings: UserSettings): List<MediaItem> {
        if (!credentials.hasTmdb) return emptyList()
        val networkId = when (studio.lowercase()) {
            "disney" -> "2739" // Disney+ TV
            "netflix" -> "213" // Netflix TV
            "hbo" -> "3186" // HBO Max TV
            "prime" -> "1024" // Amazon Prime TV
            "apple" -> "2552" // Apple TV+
            "paramount" -> "359" // Paramount+ TV
            "hulu" -> "453" // Hulu TV
            "peacock" -> "3353" // Peacock TV
            "marvel" -> "420" // Marvel TV series are tagged under Marvel Company
            "warner" -> "3186" // Max TV
            "universal" -> "33" // NBC TV
            "sony" -> "5" // Sony/Columbia TV
            "crunchyroll" -> "1112" // Crunchyroll TV
            else -> null
        } ?: return emptyList()
        return try {
            val isCompanyQuery = studio.lowercase() in listOf("marvel", "universal", "sony")
            val queryKey = if (isCompanyQuery) "with_companies" else "with_networks"
            val url = uri("discover/tv", credentials, settings, mapOf(queryKey to networkId))
            val response = get(url, credentials)
            if (response.status >= 400) return emptyList()
            val (_, tvGenres) = fetchGenres(credentials, settings)
            (response.jsonObject().optArrayOrNull("results")?.objects() ?: emptyList())
                .mapNotNull { mediaItemFromTmdb(it, MediaType.SERIES, tvGenres) }
                .filter { it.posterPath != null || it.backdropPath != null }
                .take(18)
        } catch (_: Throwable) {
            emptyList()
        }
    }

    // MARK: URL + headers

    private fun uri(path: String, credentials: ApiCredentials, settings: UserSettings, query: Map<String, String> = emptyMap()): String {
        val params = LinkedHashMap<String, String>()
        params["language"] = settings.language
        params["region"] = settings.region
        params["include_adult"] = if (settings.includeAdult) "true" else "false"
        params.putAll(query)
        if (!usesBearer(credentials.tmdbToken)) params["api_key"] = credentials.tmdbToken.trim()
        val qs = params.entries.joinToString("&") { "${it.key}=${enc(it.value)}" }
        return "$base$path?$qs"
    }

    private fun headers(credentials: ApiCredentials): Map<String, String> {
        val h = HashMap<String, String>()
        h["Accept"] = "application/json"
        h["User-Agent"] = "Omniplay/1.0"
        if (usesBearer(credentials.tmdbToken)) h["Authorization"] = "Bearer ${credentials.tmdbToken.trim()}"
        return h
    }

    private fun usesBearer(value: String): Boolean = value.trim().startsWith("ey")

    // MARK: Networking with cache + retry + concurrency gate

    private suspend fun get(url: String, credentials: ApiCredentials): Http.Response {
        val key = cacheKey(url, credentials)
        cacheMutex.withLock {
            cache[key]?.let { if (System.currentTimeMillis() < it.expiresAtMs) return it.response }
        }

        var lastError: Throwable? = null
        for (attempt in 0 until 3) {
            try {
                val response = gate.withPermit {
                    Http.request(url, headers = headers(credentials), timeoutMs = 16_000)
                }
                if (shouldRetryStatus(response.status) && attempt < 2) {
                    delay(retryDelayMs(attempt))
                    continue
                }
                if (response.status in 200..299) {
                    cacheMutex.withLock {
                        cache[key] = CachedResponse(response, System.currentTimeMillis() + CACHE_TTL_MS)
                        if (cache.size > 80) {
                            val now = System.currentTimeMillis()
                            val expired = cache.filterValues { now > it.expiresAtMs }.keys
                            expired.forEach { cache.remove(it) }
                        }
                    }
                }
                return response
            } catch (t: Throwable) {
                lastError = t
                if (attempt == 2 || !isTransient(t)) break
                delay(retryDelayMs(attempt))
            }
        }
        throw TmdbNetworkException(friendlyError(lastError))
    }

    private fun cacheKey(url: String, credentials: ApiCredentials): String {
        // Strip api_key from the cache key (parity with iOS).
        val sanitized = url.split("&").filterNot { it.startsWith("api_key=") }.joinToString("&")
        return "${credentials.tmdbToken.hashCode()}|$sanitized"
    }

    private fun shouldRetryStatus(status: Int): Boolean = status == 408 || status == 429 || status >= 500

    private fun isTransient(error: Throwable?): Boolean {
        if (error == null) return false
        if (error is Http.HttpError.Status) return shouldRetryStatus(error.status)
        if (error is Http.HttpError.Transport) return true
        val text = error.toString()
        return text.contains("timed out") || text.contains("SocketException") ||
            text.contains("Connection reset") || text.contains("Failed host lookup") ||
            text.contains("Network is unreachable") || text.contains("network connection was lost") ||
            text.contains("offline") || text.contains("Unable to resolve host")
    }

    private fun retryDelayMs(attempt: Int): Long = if (attempt == 0) 350 else 900

    private fun friendlyError(error: Throwable?): String {
        if (error is TmdbNetworkException) return error.message ?: "TMDB refresh failed."
        val text = error?.toString() ?: ""
        if (text.contains("401") || text.contains("403")) return "TMDB rejected the saved API key. Check Settings."
        if (text.contains("429")) return "TMDB rate-limited this refresh. Showing cached rows."
        if (isTransient(error)) return "TMDB is temporarily unreachable. Showing cached rows."
        return "TMDB refresh failed. Showing cached rows."
    }

    private fun statusMessage(status: Int): String = when {
        status == 401 || status == 403 -> "TMDB rejected the saved API key. Check Settings."
        status == 429 -> "TMDB rate-limited this refresh. Showing cached rows."
        else -> "TMDB returned $status. Showing cached rows."
    }

    // MARK: Image selection

    private fun imageLanguages(settings: UserSettings): String {
        val primary = settings.language.split("-").firstOrNull()?.trim() ?: ""
        val languages = ArrayList<String>()
        if (primary.isNotEmpty()) languages.add(primary)
        languages.add("en")
        languages.add("null")
        val seen = LinkedHashSet<String>()
        return languages.filter { seen.add(it) }.joinToString(",")
    }

    private fun bestImagePath(rawImages: org.json.JSONArray?, fallback: String?, targetRatio: Double): String? {
        val images = (rawImages?.objects() ?: emptyList()).filter { it.optStringOrNull("file_path") != null }
        if (images.isEmpty()) return fallback
        val sorted = images.sortedByDescending { imageScore(it, targetRatio) }
        return sorted.firstOrNull()?.optStringOrNull("file_path") ?: fallback
    }

    private fun imageScore(image: JSONObject, targetRatio: Double): Double {
        val width = image.optDoubleOrNull("width") ?: 0.0
        val height = image.optDoubleOrNull("height") ?: 1.0
        val ratio = if (height == 0.0) 0.0 else width / height
        val ratioPenalty = abs(ratio - targetRatio) * 2.2
        val votes = image.optDoubleOrNull("vote_count") ?: 0.0
        val average = image.optDoubleOrNull("vote_average") ?: 0.0
        val language = image.optStringOrNull("iso_639_1")
        val languageBoost = if (language == null || language == "en") 2.0 else 0.0
        val resolutionBoost = if (width >= 1920) 2.2 else if (width >= 1280) 1.4 else 0.0
        val clampedVotes = min(max(votes, 0.0), 20.0)
        return average + languageBoost + resolutionBoost + clampedVotes / 6 - ratioPenalty
    }

    // MARK: Credits / runtime / seasons

    private fun castFrom(json: JSONObject): List<String> {
        val credits = json.optObjectOrNull("credits") ?: JSONObject()
        return (credits.optArrayOrNull("cast")?.objects() ?: emptyList())
            .mapNotNull { it.optStringOrNull("name") }
            .filter { it.isNotEmpty() }
            .take(8)
    }

    private fun directorsFrom(json: JSONObject): List<String> {
        val createdBy = (json.optArrayOrNull("created_by")?.objects() ?: emptyList())
            .mapNotNull { it.optStringOrNull("name") }.filter { it.isNotEmpty() }
        val credits = json.optObjectOrNull("credits") ?: JSONObject()
        val crew = (credits.optArrayOrNull("crew")?.objects() ?: emptyList())
            .filter { it.optStringOrNull("job") == "Director" }
            .mapNotNull { it.optStringOrNull("name") }.filter { it.isNotEmpty() }
        val result = LinkedHashSet<String>()
        result.addAll(createdBy)
        result.addAll(crew)
        return result.take(6)
    }

    private fun runtimeFrom(json: JSONObject, type: MediaType): Int? {
        if (type == MediaType.MOVIE) return json.optIntOrNull("runtime")
        return json.optArrayOrNull("episode_run_time")?.intList()?.firstOrNull()
    }

    private fun seasonsFrom(json: JSONObject): List<MediaSeason> {
        return (json.optArrayOrNull("seasons")?.objects() ?: emptyList()).map { season ->
            MediaSeason(
                seasonNumber = season.optIntOrNull("season_number") ?: 0,
                name = season.optStringOrNull("name") ?: "Season",
                episodeCount = season.optIntOrNull("episode_count") ?: 0,
            )
        }.filter { it.episodeCount > 0 }
    }

    private fun enc(value: String): String = URLEncoder.encode(value, "UTF-8")

    companion object {
        private const val MAX_INFLIGHT = 4
        private const val CACHE_TTL_MS = 5L * 60 * 1000
    }
}

// MARK: - Demo categories (shown until TMDB credentials are saved)

private const val DEMO_POSTER =
    "https://images.unsplash.com/photo-1489599849927-2ee91cede3ba?auto=format&fit=crop&w=600&q=80"

val demoCategories: List<MediaCategory> = run {
    val movieTitles = listOf(
        "Midnight Signal", "The Glass Harbor", "Orbit Nine", "Northline",
        "Last Train Home", "Neon Season", "Drift Atlas", "The Quiet Frame",
    )
    val seriesTitles = listOf(
        "Signal Room", "Long Weekend", "The Ninth Map", "Harbor Watch",
        "After Meridian", "Low Orbit", "Public Square", "The Archive",
    )
    val movies = (0 until 8).map { index ->
        MediaItem(
            id = "demo:movie:$index",
            type = MediaType.MOVIE,
            title = movieTitles[index],
            overview = "Sample title shown until TMDB credentials are saved in Settings.",
            posterPath = DEMO_POSTER,
            rating = 7.2 + (index % 3) / 10.0,
            genres = listOf("Drama", "Adventure"),
        )
    }
    val series = (0 until 8).map { index ->
        MediaItem(
            id = "demo:series:$index",
            type = MediaType.SERIES,
            title = seriesTitles[index],
            overview = "Sample show shown until TMDB credentials are saved in Settings.",
            posterPath = DEMO_POSTER,
            rating = 8.0 - (index % 4) / 10.0,
            genres = listOf("Mystery", "Sci-Fi"),
        )
    }
    listOf(
        MediaCategory("demo_movies", "Movies", MediaType.MOVIE, movies,
            "Add your TMDB key to replace these samples with live data"),
        MediaCategory("demo_series", "TV Shows", MediaType.SERIES, series,
            "Trending and airing rows appear after TMDB setup"),
    )
}
