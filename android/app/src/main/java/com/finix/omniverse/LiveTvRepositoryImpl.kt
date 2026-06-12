package com.finix.omniverse

import java.net.URI

/// Fetches and parses live-TV sources (direct streams or M3U playlists).
/// Ported from live_tv_source_repository.dart (LiveTvSourceRepository).
class LiveTvRepositoryImpl : LiveTvRepository {

    override suspend fun fetchSource(source: LiveTvSource): List<LiveTvEntry> {
        if (!source.enabled) return emptyList()
        if (source.isDirectStream) {
            return listOf(LiveTvEntry(title = source.name, url = source.url, source = source.name))
        }

        val uri = runCatching { URI(source.url) }.getOrNull()
            ?: return listOf(LiveTvEntry(title = source.name, url = source.url, source = source.name))

        val response = Http.request(source.url)
        if (response.status >= 400) throw LiveTvException("${source.name} returned ${response.status}")

        val body = response.body
        if (leftTrimmed(body).startsWith("#EXTM3U")) {
            val parsed = parseM3u(body, uri, source.name)
            if (parsed.isNotEmpty()) return parsed
        }
        return listOf(LiveTvEntry(title = source.name, url = source.url, source = source.name))
    }

    companion object {

        private val DEFAULT_UA =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

        // MARK: M3U parsing

        fun parseM3u(content: String, baseUrl: URI, sourceLabel: String): List<LiveTvEntry> {
            val entries = ArrayList<LiveTvEntry>()
            var pendingTitle: String? = null
            var pendingLogo: String? = null
            var pendingGroup = ""
            var pendingHeaders = HashMap<String, String>()

            val lines = content.split("\n").map { it.replace("\r", "") }

            for (rawLine in lines) {
                val line = rawLine.trim()
                if (line.isEmpty() || line == "#EXTM3U") continue

                if (line.startsWith("#EXTINF")) {
                    pendingTitle = titleFromExtInf(line)
                    pendingLogo = attribute(line, "tvg-logo")
                    pendingGroup = attribute(line, "group-title") ?: ""
                    pendingHeaders = HashMap()
                    val userAgent = attribute(line, "http-user-agent")
                    pendingHeaders["User-Agent"] = if (!userAgent.isNullOrEmpty()) userAgent else DEFAULT_UA
                    val referrer = attribute(line, "http-referrer")
                    if (!referrer.isNullOrEmpty()) pendingHeaders["Referer"] = referrer
                    continue
                }

                if (line.startsWith("#EXTVLCOPT:")) {
                    val option = line.removePrefix("#EXTVLCOPT:")
                    val eq = option.indexOf('=')
                    if (eq < 0) continue
                    val name = option.substring(0, eq).trim().lowercase()
                    val value = option.substring(eq + 1).trim()
                    if (name == "http-user-agent" && value.isNotEmpty()) pendingHeaders["User-Agent"] = value
                    else if (name == "http-referrer" && value.isNotEmpty()) pendingHeaders["Referer"] = value
                    continue
                }

                if (line.startsWith("#")) continue

                val url = resolve(baseUrl, line)
                val resolvedHost = runCatching { URI(url).host }.getOrNull()
                val title = if (!pendingTitle.isNullOrEmpty()) pendingTitle!! else (resolvedHost ?: "Live channel")
                entries.add(LiveTvEntry(
                    title = title, url = url, source = sourceLabel,
                    region = pendingGroup, logoUrl = pendingLogo, headers = HashMap(pendingHeaders),
                ))
                pendingTitle = null
                pendingLogo = null
                pendingGroup = ""
                pendingHeaders = HashMap()
            }
            return entries
        }

        private fun titleFromExtInf(line: String): String {
            val comma = line.lastIndexOf(',')
            if (comma < 0 || comma == line.length - 1) {
                return attribute(line, "tvg-name") ?: "Live channel"
            }
            return line.substring(comma + 1).trim()
        }

        private fun attribute(line: String, name: String): String? {
            val regex = Regex("${Regex.escape(name)}=\"([^\"]*)\"")
            return regex.find(line)?.groupValues?.getOrNull(1)?.trim()
        }

        /// Mirror Dart Uri.resolve: absolute URLs pass through, relative ones resolve against base.
        fun resolve(base: URI, line: String): String {
            val direct = runCatching { URI(line) }.getOrNull()
            if (direct?.scheme != null) return direct.toString()
            return runCatching { base.resolve(line).toString() }.getOrDefault(line)
        }
    }

    private fun leftTrimmed(s: String): String {
        val idx = s.indexOfFirst { !it.isWhitespace() }
        return if (idx < 0) "" else s.substring(idx)
    }
}

private class LiveTvException(message: String) : Exception(message)
