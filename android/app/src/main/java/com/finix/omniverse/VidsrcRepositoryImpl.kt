package com.finix.omniverse

import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import org.json.JSONObject
import java.net.URLEncoder

/// Builds VidSrc embed PlaybackSources and fetches the JSON "latest" listings.
/// Ported from vidsrc_repository.dart.
class VidsrcRepositoryImpl : VidsrcRepository {

    override fun sourcesFor(item: MediaItem, settings: UserSettings, episode: MediaEpisode?): List<PlaybackSource> {
        if (item.type == MediaType.LIVE_TV || item.type == MediaType.ANIME) return emptyList()
        if (idFor(item) == null) return emptyList()

        return orderedDomains(settings.vidsrcDomain).map { domain ->
            PlaybackSource(
                id = "vidsrc:$domain:${item.id}:${episode?.seasonNumber ?: 0}:${episode?.episodeNumber ?: 0}",
                title = domainLabel(domain),
                url = embedUri(domain, item, episode, settings),
                provider = "VidSrc",
                kind = PlaybackSourceKind.EMBED,
                quality = "Embed",
            )
        }
    }

    override suspend fun fetchLatestCategories(): List<MediaCategory> = coroutineScope {
        val movies = async { fetchLatestMovies(1) }
        val tv = async { fetchLatestTvShows(1) }
        val episodes = async { fetchLatestEpisodes(1) }
        listOf(movies.await(), tv.await(), episodes.await())
    }

    suspend fun fetchLatestMovies(page: Int = 1): MediaCategory {
        return try {
            val items = fetchLatest("movies/latest/page-$page.json").mapNotNull { movieFromLatest(it) }.take(18)
            MediaCategory("vidsrc_latest_movies", "Latest Movies on Vidsrc", MediaType.MOVIE, items,
                "Recently added movie embeds from Vidsrc")
        } catch (t: Throwable) {
            MediaCategory("vidsrc_latest_movies", "Latest Movies on Vidsrc", MediaType.MOVIE, emptyList(),
                "Recently added movie embeds from Vidsrc", "Vidsrc movies could not load: $t")
        }
    }

    suspend fun fetchLatestTvShows(page: Int = 1): MediaCategory {
        return try {
            val items = fetchLatest("tvshows/latest/page-$page.json").mapNotNull { seriesFromLatest(it) }.take(18)
            MediaCategory("vidsrc_latest_tv", "Latest TV Shows on Vidsrc", MediaType.SERIES, items,
                "Recently added TV show embeds from Vidsrc")
        } catch (t: Throwable) {
            MediaCategory("vidsrc_latest_tv", "Latest TV Shows on Vidsrc", MediaType.SERIES, emptyList(),
                "Recently added TV show embeds from Vidsrc", "Vidsrc TV shows could not load: $t")
        }
    }

    suspend fun fetchLatestEpisodes(page: Int = 1): MediaCategory {
        return try {
            val items = fetchLatest("episodes/latest/page-$page.json").mapNotNull { episodeFromLatest(it) }.take(18)
            MediaCategory("vidsrc_latest_episodes", "Latest Episodes on Vidsrc", MediaType.SERIES, items,
                "Episode-specific Vidsrc entries, newest first")
        } catch (t: Throwable) {
            MediaCategory("vidsrc_latest_episodes", "Latest Episodes on Vidsrc", MediaType.SERIES, emptyList(),
                "Episode-specific Vidsrc entries, newest first", "Vidsrc episodes could not load: $t")
        }
    }

    // MARK: Embed URL

    private fun embedUri(domain: String, item: MediaItem, episode: MediaEpisode?, settings: UserSettings): String {
        val query = ArrayList<Pair<String, String>>()
        val imdb = item.imdbId?.trim()
        if (!imdb.isNullOrEmpty()) query.add("imdb" to imdb)
        else item.tmdbId?.let { query.add("tmdb" to it.toString()) }
        if (episode != null) {
            query.add("season" to episode.seasonNumber.toString())
            query.add("episode" to episode.episodeNumber.toString())
            query.add("autonext" to "1")
        }
        val subtitleUrl = settings.subtitleUrl.trim()
        if (subtitleUrl.isNotEmpty() && hasScheme(subtitleUrl)) query.add("sub_url" to subtitleUrl)
        val subtitleLanguage = settings.subtitleLanguage.trim()
        if (subtitleLanguage.isNotEmpty()) query.add("ds_lang" to subtitleLanguage)
        query.add("autoplay" to "1")

        val path = if (item.type == MediaType.MOVIE) "/embed/movie" else "/embed/tv"
        val qs = query.joinToString("&") { "${it.first}=${enc(it.second)}" }
        return "https://$domain$path?$qs"
    }

    private fun idFor(item: MediaItem): String? {
        val imdb = item.imdbId?.trim()
        if (!imdb.isNullOrEmpty()) return imdb
        return item.tmdbId?.toString()
    }

    private fun orderedDomains(preferred: String): List<String> {
        val clean = preferred.trim()
        if (clean !in EMBED_DOMAINS) return EMBED_DOMAINS
        return listOf(clean) + EMBED_DOMAINS.filter { it != clean }
    }

    // MARK: Latest JSON

    private suspend fun fetchLatest(path: String): List<JSONObject> {
        val url = "https://$LISTING_DOMAIN/$path"
        val response = Http.request(url, headers = mapOf("User-Agent" to "Omniplay"), timeoutMs = 18_000)
        if (response.status >= 400) throw VidsrcExtractorException("${Http.hostOf(url)} returned ${response.status}")
        val decoded = response.jsonObject()
        return decoded.optArrayOrNull("result")?.objects() ?: emptyList()
    }

    private fun movieFromLatest(json: JSONObject): MediaItem? {
        val imdbId = string(json.opt("imdb_id"))
        val tmdbId = intVal(json.opt("tmdb_id"))
        if (imdbId == null && tmdbId == null) return null
        val title = string(json.opt("title")) ?: "Movie"
        return MediaItem(
            id = "vidsrc:movie:${imdbId ?: tmdbId.toString()}",
            type = MediaType.MOVIE, title = title, overview = latestOverview(json),
            tmdbId = tmdbId, imdbId = imdbId, source = "vidsrc",
        )
    }

    private fun seriesFromLatest(json: JSONObject): MediaItem? {
        val imdbId = string(json.opt("imdb_id"))
        val tmdbId = intVal(json.opt("tmdb_id"))
        if (imdbId == null && tmdbId == null) return null
        val title = string(json.opt("title")) ?: string(json.opt("show_title")) ?: "TV Show"
        return MediaItem(
            id = "vidsrc:series:${imdbId ?: tmdbId.toString()}",
            type = MediaType.SERIES, title = title, overview = latestOverview(json),
            tmdbId = tmdbId, imdbId = imdbId, source = "vidsrc",
        )
    }

    private fun episodeFromLatest(json: JSONObject): MediaItem? {
        val imdbId = string(json.opt("imdb_id"))
        val tmdbId = intVal(json.opt("tmdb_id"))
        if (imdbId == null && tmdbId == null) return null
        val title = string(json.opt("show_title")) ?: string(json.opt("title")) ?: "TV Show"
        val season = intVal(json.opt("season")) ?: 1
        val episode = intVal(json.opt("episode")) ?: 1
        return MediaItem(
            id = "vidsrc:episode:${imdbId ?: tmdbId.toString()}:$season:$episode",
            type = MediaType.SERIES, title = title, overview = latestOverview(json),
            seasons = listOf(MediaSeason(season, "Season $season", episode)),
            episodes = listOf(MediaEpisode(season, episode, "Episode $episode")),
            tmdbId = tmdbId, imdbId = imdbId, source = "vidsrc",
        )
    }

    private fun latestOverview(json: JSONObject): String {
        val parts = ArrayList<String>()
        string(json.opt("quality"))?.let { parts.add(it) }
        string(json.opt("time_added"))?.let { parts.add("Added $it") }
        return if (parts.isEmpty()) "Vidsrc embed entry." else parts.joinToString(" • ")
    }

    private fun domainLabel(domain: String): String {
        val index = EMBED_DOMAINS.indexOf(domain)
        return if (index < 0) domain else "Server ${index + 1}"
    }

    private fun string(value: Any?): String? {
        if (value == null) return null
        val text = value.toString().trim()
        if (text.isEmpty() || text == "null") return null
        return text
    }

    private fun intVal(value: Any?): Int? = when (value) {
        is Int -> value
        is Long -> value.toInt()
        is Double -> value.toInt()
        is Number -> value.toInt()
        is String -> value.toIntOrNull()
        else -> null
    }

    private fun hasScheme(s: String): Boolean = runCatching { java.net.URI(s).scheme != null }.getOrDefault(false)

    private fun enc(value: String): String = URLEncoder.encode(value, "UTF-8")

    companion object {
        val EMBED_DOMAINS = listOf("vidsrc-embed.ru", "vidsrc-embed.su", "vidsrcme.su", "vsrc.su")
        private const val LISTING_DOMAIN = "vidsrc-embed.ru"
    }
}
