package com.finix.omniverse

import org.jsoup.Jsoup
import java.net.URI

/// Scrapes the Yarrlist directory pages for live-TV / movie links.
/// Ported from yarrlist_repository.dart. HTML <a> anchors parsed with jsoup.
class YarrlistRepositoryImpl : YarrlistRepository {

    override suspend fun fetchLiveTvDirectory(): List<LiveTvEntry> {
        val response = Http.request(LIVE_TV_URL)
        if (response.status >= 400) throw YarrlistException("Yarrlist returned ${response.status}")
        return parseDirectory(response.body, LIVE_TV_URL, "Yarrlist Live TV")
    }

    override suspend fun fetchMoviesTvDirectory(): List<LiveTvEntry> {
        val response = Http.request(MOVIES_URL)
        if (response.status >= 400) throw YarrlistException("Yarrlist returned ${response.status}")
        return parseDirectory(response.body, MOVIES_URL, "Yarrlist Movies/TV")
    }

    companion object {
        private const val MOVIES_URL = "https://yarrlist.net/movies-and-tv-shows"
        private const val LIVE_TV_URL = "https://yarrlist.net/live-tv-list"

        fun parseDirectory(html: String, baseUrl: String, sourceLabel: String): List<LiveTvEntry> {
            val seen = HashSet<String>()
            val entries = ArrayList<LiveTvEntry>()
            val baseUri = runCatching { URI(baseUrl) }.getOrNull()
            val doc = Jsoup.parse(html)

            for (anchor in doc.select("a")) {
                val href = anchor.attr("href").trim()
                if (href.isEmpty()) continue
                val text = anchor.text().replace(Regex("\\s+"), " ").trim()
                if (text.isEmpty()) continue
                val absolute = resolve(baseUri, href)
                val host = runCatching { URI(absolute).host }.getOrNull() ?: ""
                if (isNavigation(text, host)) continue
                if (!seen.add(absolute)) continue
                entries.add(LiveTvEntry(title = cleanTitle(text), url = absolute, source = sourceLabel))
            }
            return entries
        }

        private fun resolve(base: URI?, href: String): String {
            val direct = runCatching { URI(href) }.getOrNull()
            if (direct?.scheme != null) return direct.toString()
            if (base == null) return href
            return runCatching { base.resolve(href).toString() }.getOrDefault(href)
        }

        private fun isNavigation(text: String, host: String): Boolean {
            val lower = text.lowercase()
            val nav = setOf(
                "backups", "yarrlist", "movies/tv shows", "movies tv shows", "anime",
                "manga", "live sports", "live tv", "torrents", "games", "music",
                "ebooks", "comics", "asian drama", "adult", "adblock", "adblockers",
                "vpn", "reddit",
            )
            return nav.contains(lower) || host == "github.com" || host == "yarrlist.net" || host == "ahoylist.net"
        }

        private fun cleanTitle(text: String): String =
            text.replace(Regex("\\s*†.*$"), "").trim()
    }
}

private class YarrlistException(message: String) : Exception(message)
