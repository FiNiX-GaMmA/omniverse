package com.finix.omniverse

import org.jsoup.Jsoup
import java.net.URI
import kotlin.random.Random

// MARK: - Repository interfaces (mirror the Swift protocols in Repositories.swift)

interface TmdbRepository {
    suspend fun fetchLandingCategories(credentials: ApiCredentials, settings: UserSettings): List<MediaCategory>
    suspend fun fetchDetails(item: MediaItem, credentials: ApiCredentials, settings: UserSettings): MediaItem?
    suspend fun searchMulti(query: String, credentials: ApiCredentials, settings: UserSettings): List<MediaItem>
    suspend fun fetchSeasonEpisodes(item: MediaItem, seasonNumber: Int, credentials: ApiCredentials, settings: UserSettings): List<MediaEpisode>
    suspend fun fetchRecommendations(item: MediaItem, credentials: ApiCredentials, settings: UserSettings): List<MediaItem>
}

interface TvdbRepository {
    suspend fun validate(credentials: ApiCredentials): Boolean
    suspend fun enrichDetails(item: MediaItem, credentials: ApiCredentials): MediaItem
    suspend fun fetchSeasonEpisodes(item: MediaItem, seasonNumber: Int, credentials: ApiCredentials): List<MediaEpisode>
}

interface TraktRepository {
    suspend fun fetchUserSettings(c: ApiCredentials): ApiCredentials
    suspend fun fetchDiscoveryCategories(c: ApiCredentials): List<MediaCategory>
    suspend fun fetchWatchlist(c: ApiCredentials): List<MediaItem>
    suspend fun setWatchlistItem(c: ApiCredentials, item: MediaItem, add: Boolean)
    suspend fun fetchPlaybackProgress(c: ApiCredentials): List<WatchProgress>
    suspend fun deletePlaybackProgress(c: ApiCredentials, playbackId: Int)
    suspend fun startScrobble(c: ApiCredentials, item: MediaItem, episode: MediaEpisode?, progress: Double)
    suspend fun pauseScrobble(c: ApiCredentials, item: MediaItem, episode: MediaEpisode?, progress: Double)
    suspend fun stopScrobble(c: ApiCredentials, item: MediaItem, episode: MediaEpisode?, progress: Double)
    suspend fun fetchRemoteSettings(c: ApiCredentials): String?
    suspend fun saveRemoteSettings(c: ApiCredentials, payload: String)
    suspend fun ensureFreshAccessToken(c: ApiCredentials): ApiCredentials
    fun buildOAuthAuthorizeUri(c: ApiCredentials, state: String): String?
    suspend fun exchangeAuthorizationCode(c: ApiCredentials, code: String): ApiCredentials
    suspend fun startDeviceAuth(c: ApiCredentials): TraktDeviceCode
    suspend fun completeDeviceAuth(c: ApiCredentials, code: TraktDeviceCode): ApiCredentials
}

interface VidsrcRepository {
    fun sourcesFor(item: MediaItem, settings: UserSettings, episode: MediaEpisode?): List<PlaybackSource>
    suspend fun fetchLatestCategories(): List<MediaCategory>
}

// NOTE: `interface AnimeRepository` and `class HianimeRepository` /
// `class AnimeRepositoryImpl` are declared in AnimeRepositoryImpl.kt /
// HianimeRepository.kt (owned by the crypto agent). They are intentionally NOT
// redeclared here to avoid duplicate-declaration errors. The factory below
// references the crypto-provided `AnimeRepositoryImpl()`.

interface LiveTvRepository {
    suspend fun fetchSource(source: LiveTvSource): List<LiveTvEntry>
}

interface YarrlistRepository {
    suspend fun fetchLiveTvDirectory(): List<LiveTvEntry>
    suspend fun fetchMoviesTvDirectory(): List<LiveTvEntry>
}

// MARK: - Repositories holder + factory

class Repositories(
    val tmdb: TmdbRepository,
    val tvdb: TvdbRepository,
    val trakt: TraktRepository,
    val vidsrc: VidsrcRepository,
    val anime: AnimeRepository,
    val liveTv: LiveTvRepository,
    val yarrlist: YarrlistRepository,
) {
    companion object {
        fun live(): Repositories = Repositories(
            tmdb = TmdbRepositoryImpl(),
            tvdb = TvdbRepositoryImpl(),
            trakt = TraktRepositoryImpl(),
            vidsrc = VidsrcRepositoryImpl(),
            // Provided by the crypto agent (AnimeRepositoryImpl.kt).
            anime = AnimeRepositoryImpl(),
            liveTv = LiveTvRepositoryImpl(),
            yarrlist = YarrlistRepositoryImpl(),
        )
    }
}

// MARK: - VidsrcStream

data class VidsrcStream(
    val streamUrl: String,
    val headers: Map<String, String>,
    val serverName: String,
    val title: String,
)

class VidsrcExtractorException(message: String) : Exception("VidsrcExtractorException: $message")

// MARK: - VidsrcExtractor (concrete; ported from vidsrc_extractor.dart)

/// Resolves a VidSrc embed into a direct HLS (.m3u8) URL plus the Referer
/// header the stream host requires. (originally https://github.com/ThEditor/stremsrc).
///
/// Flow:
/// 1. GET the vidsrc embed page; parse the iframe origin (cloudnestra/...)
///    and the list of `.serversList .server[data-hash]` entries.
/// 2. For each server, GET `{base}/rcp/{dataHash}` and regex-extract the
///    `src: '/prorcp/...'` path.
/// 3. GET `{base}/prorcp/{id}` and regex-extract `file: '...'` — the stream.
class VidsrcExtractor {

    private data class Server(val name: String, val dataHash: String)
    private data class ParsedEmbed(val base: URI, val servers: List<Server>, val title: String)

    /// Candidate embed URLs in priority order. Subtitle url/language are appended
    /// (`sub_url` / `ds_lang`) when present so cloudnestra surfaces captions.
    fun embedUrlsFor(
        item: MediaItem,
        episode: MediaEpisode?,
        preferredDomain: String?,
        subtitleUrl: String = "",
        subtitleLanguage: String = "",
    ): List<String> {
        val id = idFor(item) ?: return emptyList()
        val extra = StringBuilder()
        val cleanSub = subtitleUrl.trim()
        if (cleanSub.isNotEmpty() && hasScheme(cleanSub)) {
            extra.append("&sub_url=").append(urlEncode(cleanSub))
        }
        val cleanLang = subtitleLanguage.trim()
        if (cleanLang.isNotEmpty()) {
            extra.append("&ds_lang=").append(urlEncode(cleanLang))
        }
        return orderedDomains(preferredDomain).map { domain ->
            val base = embedUri(domain, item, episode, id)
            if (extra.isEmpty()) base
            else {
                val sep = if (base.contains("?")) "" else "?"
                // extra always begins with '&'; if no query yet turn first '&' into nothing after '?'
                if (sep == "?") base + "?" + extra.toString().removePrefix("&")
                else base + extra.toString()
            }
        }
    }

    /// Walks rcp -> prorcp on an embed-page HTML body and returns the m3u8 stream.
    suspend fun resolveFromEmbedHtml(embedHtml: String, userAgent: String? = null): VidsrcStream {
        val parsed = parseServers(embedHtml)
        if (parsed.servers.isEmpty()) {
            throw VidsrcExtractorException("No servers listed on embed page")
        }
        val ua = userAgent ?: randomUserAgent()
        var lastError: Throwable? = null
        for (server in parsed.servers) {
            try {
                return resolveServer(server, parsed.base, ua, parsed.title)
            } catch (t: Throwable) {
                lastError = t
            }
        }
        throw VidsrcExtractorException(
            "No working server (${parsed.servers.size} tried). Last: $lastError"
        )
    }

    /// HTTP-only fallback: tries each domain, fetches the embed HTML, then resolves.
    suspend fun resolve(item: MediaItem, episode: MediaEpisode?, preferredDomain: String?): VidsrcStream {
        val id = idFor(item) ?: throw VidsrcExtractorException("No IMDb/TMDB id for this title")
        var lastError: Throwable? = null
        for (domain in orderedDomains(preferredDomain)) {
            try {
                val ua = randomUserAgent()
                val embedUri = embedUri(domain, item, episode, id)
                val embedResponse = Http.request(embedUri, headers = headers(ua, "https://$domain/"), timeoutMs = 18_000)
                if (embedResponse.status >= 400) {
                    throw VidsrcExtractorException("$domain returned HTTP ${embedResponse.status}")
                }
                return resolveFromEmbedHtml(embedResponse.body, ua)
            } catch (t: Throwable) {
                lastError = t
            }
        }
        throw VidsrcExtractorException(
            "Could not extract a playable stream from VidSrc. Last error: $lastError"
        )
    }

    /// Public variant used by a WebView resolver which already has base + dataHash.
    suspend fun resolveServer(base: String, dataHash: String, name: String, title: String, userAgent: String): VidsrcStream =
        resolveServer(Server(name, dataHash), URI(base), userAgent, title)

    private suspend fun resolveServer(server: Server, base: URI, ua: String, title: String): VidsrcStream {
        val baseStr = base.toString().trimEnd('/')
        val rcpUri = replacePath(base, "/rcp/${server.dataHash}")
        val rcpResp = Http.request(rcpUri, headers = headers(ua, "$baseStr/"), timeoutMs = 14_000)
        if (rcpResp.status >= 400) throw VidsrcExtractorException("rcp HTTP ${rcpResp.status}")
        val src = firstMatch(rcpResp.body, "src:\\s*'([^']*)'")
            ?: throw VidsrcExtractorException("rcp response missing src")
        if (!src.startsWith("/prorcp/")) {
            throw VidsrcExtractorException("Unexpected src prefix: $src")
        }
        val prorcpUri = replacePath(base, src)
        val prorcpResp = Http.request(prorcpUri, headers = headers(ua, "$baseStr/"), timeoutMs = 14_000)
        if (prorcpResp.status >= 400) throw VidsrcExtractorException("prorcp HTTP ${prorcpResp.status}")
        val streamUrl = firstMatch(prorcpResp.body, "file:\\s*'([^']*)'")
            ?: throw VidsrcExtractorException("prorcp response missing file")

        val scheme = base.scheme ?: "https"
        val host = base.host ?: ""
        var origin = "$scheme://$host"
        if (base.port != -1) origin += ":${base.port}"
        return VidsrcStream(
            streamUrl = streamUrl,
            headers = mapOf(
                "Referer" to "$baseStr/",
                "User-Agent" to ua,
                "Origin" to origin,
            ),
            serverName = server.name,
            title = title,
        )
    }

    // MARK: Embed URL

    private fun embedUri(domain: String, item: MediaItem, episode: MediaEpisode?, id: String): String {
        // stremsrc uses /embed/movie/{id} and /embed/tv/{id}/{season}-{episode}.
        return if (item.type == MediaType.MOVIE) {
            "https://$domain/embed/movie/$id"
        } else {
            val season = episode?.seasonNumber ?: 1
            val ep = episode?.episodeNumber ?: 1
            "https://$domain/embed/tv/$id/$season-$ep"
        }
    }

    // MARK: HTML parsing (jsoup)

    private fun parseServers(html: String): ParsedEmbed {
        val doc = Jsoup.parse(html)
        val title = doc.title().trim()

        val iframeSrc = doc.selectFirst("iframe[src]")?.attr("src")?.trim() ?: ""
        val normalized = if (iframeSrc.startsWith("//")) "https:$iframeSrc" else iframeSrc
        val resolved = normalized.takeIf { it.isNotEmpty() }?.let { runCatching { URI(it) }.getOrNull() }
        val fallback = URI("https://cloudnestra.com/")
        val base = resolved ?: fallback

        val scheme = base.scheme ?: "https"
        val host = base.host ?: "cloudnestra.com"
        val portPart = if (base.port != -1) ":${base.port}" else ""
        val base0 = runCatching { URI("$scheme://$host$portPart/") }.getOrDefault(fallback)

        val servers = doc.select("[data-hash]").mapNotNull { el ->
            val hash = el.attr("data-hash").trim()
            if (hash.isEmpty()) null
            else Server(name = el.text().trim(), dataHash = hash)
        }
        return ParsedEmbed(base0, servers, title)
    }

    private fun firstMatch(text: String, pattern: String): String? {
        val regex = Regex(pattern, RegexOption.IGNORE_CASE)
        return regex.find(text)?.groupValues?.getOrNull(1)
    }

    private fun replacePath(uri: URI, path: String): String {
        val scheme = uri.scheme ?: "https"
        val host = uri.host ?: ""
        val portPart = if (uri.port != -1) ":${uri.port}" else ""
        return "$scheme://$host$portPart$path"
    }

    // MARK: Headers / UA / id / domains

    private fun headers(ua: String, referer: String): Map<String, String> = mapOf(
        "User-Agent" to ua,
        "Accept" to "*/*",
        "Accept-Language" to "en-US,en;q=0.9",
        "Referer" to referer,
        "Sec-Fetch-Dest" to "iframe",
        "Sec-Fetch-Mode" to "no-cors",
        "Sec-Fetch-Site" to "same-origin",
    )

    private fun randomUserAgent(): String = userAgents[Random.nextInt(userAgents.size)]

    private fun idFor(item: MediaItem): String? {
        val imdb = item.imdbId?.trim()
        if (!imdb.isNullOrEmpty()) return imdb
        return item.tmdbId?.toString()
    }

    private fun orderedDomains(preferred: String?): List<String> {
        if (preferred == null) return sourceHosts
        val clean = preferred.trim()
        if (clean !in sourceHosts) return sourceHosts
        return listOf(clean) + sourceHosts.filter { it != clean }
    }

    private fun hasScheme(s: String): Boolean = runCatching { URI(s).scheme != null }.getOrDefault(false)

    private fun urlEncode(s: String): String = java.net.URLEncoder.encode(s, "UTF-8")

    companion object {
        private val sourceHosts = listOf(
            "vidsrc-embed.ru",
            "vidsrc-embed.su",
            "vidsrcme.su",
            "vsrc.su",
        )
        private val userAgents = listOf(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36",
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:129.0) Gecko/20100101 Firefox/129.0",
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15",
        )
    }
}
