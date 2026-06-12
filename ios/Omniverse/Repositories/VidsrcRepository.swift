import Foundation

// MARK: - VidsrcRepository

/// Builds VidSrc embed PlaybackSources and fetches the JSON "latest" listings.
/// Ported from vidsrc_repository.dart.
final class VidsrcRepository: VidsrcRepositoryProtocol {

    static let embedDomains = [
        "vidsrc-embed.ru",
        "vidsrc-embed.su",
        "vidsrcme.su",
        "vsrc.su",
    ]

    private static let listingDomain = "vidsrc-embed.ru"

    func sourcesFor(_ item: MediaItem, settings: UserSettings, episode: MediaEpisode?) -> [PlaybackSource] {
        if item.type == .liveTv || item.type == .anime { return [] }
        guard idFor(item) != nil else { return [] }

        return orderedDomains(settings.vidsrcDomain).map { domain in
            PlaybackSource(
                id: "vidsrc:\(domain):\(item.id):\(episode?.seasonNumber ?? 0):\(episode?.episodeNumber ?? 0)",
                title: domainLabel(domain),
                url: embedUri(domain: domain, item: item, episode: episode, settings: settings).absoluteString,
                provider: "VidSrc",
                kind: .embed,
                quality: "Embed"
            )
        }
    }

    func fetchLatestCategories() async -> [MediaCategory] {
        async let movies = fetchLatestMovies(page: 1)
        async let tv = fetchLatestTvShows(page: 1)
        async let episodes = fetchLatestEpisodes(page: 1)
        return [await movies, await tv, await episodes]
    }

    func fetchLatestMovies(page: Int = 1) async -> MediaCategory {
        do {
            let entries = try await fetchLatest("movies/latest/page-\(page).json")
            let items = entries.compactMap(movieFromLatest).prefix(18)
            return MediaCategory(id: "vidsrc_latest_movies", title: "Latest Movies on Vidsrc",
                                 type: .movie, items: Array(items),
                                 description: "Recently added movie embeds from Vidsrc")
        } catch {
            return MediaCategory(id: "vidsrc_latest_movies", title: "Latest Movies on Vidsrc",
                                 type: .movie, items: [],
                                 description: "Recently added movie embeds from Vidsrc",
                                 error: "Vidsrc movies could not load: \(error)")
        }
    }

    func fetchLatestTvShows(page: Int = 1) async -> MediaCategory {
        do {
            let entries = try await fetchLatest("tvshows/latest/page-\(page).json")
            let items = entries.compactMap(seriesFromLatest).prefix(18)
            return MediaCategory(id: "vidsrc_latest_tv", title: "Latest TV Shows on Vidsrc",
                                 type: .series, items: Array(items),
                                 description: "Recently added TV show embeds from Vidsrc")
        } catch {
            return MediaCategory(id: "vidsrc_latest_tv", title: "Latest TV Shows on Vidsrc",
                                 type: .series, items: [],
                                 description: "Recently added TV show embeds from Vidsrc",
                                 error: "Vidsrc TV shows could not load: \(error)")
        }
    }

    func fetchLatestEpisodes(page: Int = 1) async -> MediaCategory {
        do {
            let entries = try await fetchLatest("episodes/latest/page-\(page).json")
            let items = entries.compactMap(episodeFromLatest).prefix(18)
            return MediaCategory(id: "vidsrc_latest_episodes", title: "Latest Episodes on Vidsrc",
                                 type: .series, items: Array(items),
                                 description: "Episode-specific Vidsrc entries, newest first")
        } catch {
            return MediaCategory(id: "vidsrc_latest_episodes", title: "Latest Episodes on Vidsrc",
                                 type: .series, items: [],
                                 description: "Episode-specific Vidsrc entries, newest first",
                                 error: "Vidsrc episodes could not load: \(error)")
        }
    }

    // MARK: Embed URL

    private func embedUri(domain: String, item: MediaItem, episode: MediaEpisode?, settings: UserSettings) -> URL {
        var query: [URLQueryItem] = []
        if let imdb = item.imdbId?.trimmed, !imdb.isEmpty {
            query.append(URLQueryItem(name: "imdb", value: imdb))
        } else if let tmdbId = item.tmdbId {
            query.append(URLQueryItem(name: "tmdb", value: String(tmdbId)))
        }
        if let episode {
            query.append(URLQueryItem(name: "season", value: String(episode.seasonNumber)))
            query.append(URLQueryItem(name: "episode", value: String(episode.episodeNumber)))
            query.append(URLQueryItem(name: "autonext", value: "1"))
        }
        let subtitleUrl = settings.subtitleUrl.trimmed
        if !subtitleUrl.isEmpty, let u = URL(string: subtitleUrl), u.scheme != nil {
            query.append(URLQueryItem(name: "sub_url", value: subtitleUrl))
        }
        let subtitleLanguage = settings.subtitleLanguage.trimmed
        if !subtitleLanguage.isEmpty {
            query.append(URLQueryItem(name: "ds_lang", value: subtitleLanguage))
        }
        query.append(URLQueryItem(name: "autoplay", value: "1"))

        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = domain
        comps.path = item.type == .movie ? "/embed/movie" : "/embed/tv"
        comps.queryItems = query
        return comps.url!
    }

    private func idFor(_ item: MediaItem) -> String? {
        if let imdb = item.imdbId?.trimmed, !imdb.isEmpty { return imdb }
        if let tmdbId = item.tmdbId { return String(tmdbId) }
        return nil
    }

    private func orderedDomains(_ preferred: String) -> [String] {
        let clean = preferred.trimmed
        if !Self.embedDomains.contains(clean) { return Self.embedDomains }
        return [clean] + Self.embedDomains.filter { $0 != clean }
    }

    // MARK: Latest JSON

    private func fetchLatest(_ path: String) async throws -> [[String: Any]] {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = Self.listingDomain
        comps.path = "/" + path
        let url = comps.url!
        let response = try await Http.shared.request(url, headers: ["User-Agent": "Omniplay"], timeout: 18)
        if response.status >= 400 {
            throw VidsrcError.message("\(url.host ?? "") returned \(response.status)")
        }
        let decoded = response.jsonObject()
        guard let result = decoded.arr("result") else { return [] }
        return result.compactMap { $0 as? [String: Any] }
    }

    private func movieFromLatest(_ json: [String: Any]) -> MediaItem? {
        let imdbId = string(json["imdb_id"])
        let tmdbId = int(json["tmdb_id"])
        if imdbId == nil && tmdbId == nil { return nil }
        let title = string(json["title"]) ?? "Movie"
        return MediaItem(
            id: "vidsrc:movie:\(imdbId ?? String(tmdbId!))",
            type: .movie,
            title: title,
            overview: latestOverview(json),
            tmdbId: tmdbId,
            imdbId: imdbId,
            source: "vidsrc"
        )
    }

    private func seriesFromLatest(_ json: [String: Any]) -> MediaItem? {
        let imdbId = string(json["imdb_id"])
        let tmdbId = int(json["tmdb_id"])
        if imdbId == nil && tmdbId == nil { return nil }
        let title = string(json["title"]) ?? string(json["show_title"]) ?? "TV Show"
        return MediaItem(
            id: "vidsrc:series:\(imdbId ?? String(tmdbId!))",
            type: .series,
            title: title,
            overview: latestOverview(json),
            tmdbId: tmdbId,
            imdbId: imdbId,
            source: "vidsrc"
        )
    }

    private func episodeFromLatest(_ json: [String: Any]) -> MediaItem? {
        let imdbId = string(json["imdb_id"])
        let tmdbId = int(json["tmdb_id"])
        if imdbId == nil && tmdbId == nil { return nil }
        let title = string(json["show_title"]) ?? string(json["title"]) ?? "TV Show"
        let season = int(json["season"]) ?? 1
        let episode = int(json["episode"]) ?? 1
        return MediaItem(
            id: "vidsrc:episode:\(imdbId ?? String(tmdbId!)):\(season):\(episode)",
            type: .series,
            title: title,
            overview: latestOverview(json),
            seasons: [MediaSeason(seasonNumber: season, name: "Season \(season)", episodeCount: episode)],
            episodes: [MediaEpisode(seasonNumber: season, episodeNumber: episode, title: "Episode \(episode)")],
            tmdbId: tmdbId,
            imdbId: imdbId,
            source: "vidsrc"
        )
    }

    private func latestOverview(_ json: [String: Any]) -> String {
        var parts: [String] = []
        if let quality = string(json["quality"]) { parts.append(quality) }
        if let timeAdded = string(json["time_added"]) { parts.append("Added \(timeAdded)") }
        return parts.isEmpty ? "Vidsrc embed entry." : parts.joined(separator: " • ")
    }

    private func domainLabel(_ domain: String) -> String {
        guard let index = Self.embedDomains.firstIndex(of: domain) else { return domain }
        return "Server \(index + 1)"
    }

    private func string(_ value: Any?) -> String? {
        guard let value else { return nil }
        let text = "\(value)".trimmed
        if text.isEmpty || text == "null" { return nil }
        return text
    }

    private func int(_ value: Any?) -> Int? {
        if let n = value as? Int { return n }
        if let n = value as? Double { return Int(n) }
        if let s = value as? String { return Int(s) }
        return nil
    }
}

// MARK: - VidsrcStream

struct VidsrcStream {
    let streamUrl: String
    let headers: [String: String]
    let serverName: String
    let title: String
}

struct VidsrcExtractorException: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { "VidsrcExtractorException: \(message)" }
}

private enum VidsrcError: Error, CustomStringConvertible {
    case message(String)
    var description: String {
        switch self { case .message(let m): return m }
    }
}

// MARK: - VidsrcExtractor

/// Resolves a VidSrc embed into a direct HLS (.m3u8) URL plus the Referer
/// header the stream host requires. Ported from vidsrc_extractor.dart
/// (originally https://github.com/ThEditor/stremsrc).
///
/// Flow:
/// 1. GET the vidsrc embed page; parse the iframe origin (cloudnestra/...)
///    and the list of `.serversList .server[data-hash]` entries.
/// 2. For each server, GET `{base}/rcp/{dataHash}` and regex-extract the
///    `src: '/prorcp/...'` path.
/// 3. GET `{base}/prorcp/{id}` and regex-extract `file: '...'` — the stream.
///
/// HTML is parsed with regex/string scanning (no SwiftSoup dependency).
final class VidsrcExtractor {

    private static let sourceHosts = [
        "vidsrc-embed.ru",
        "vidsrc-embed.su",
        "vidsrcme.su",
        "vsrc.su",
    ]

    private static let userAgents = [
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:129.0) Gecko/20100101 Firefox/129.0",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15",
    ]

    private struct Server {
        let name: String
        let dataHash: String
    }

    private struct ParsedEmbed {
        let base: URL
        let servers: [Server]
        let title: String
    }

    /// Candidate embed URLs in priority order. Subtitle url/language are
    /// appended (`sub_url` / `ds_lang`) when present so cloudnestra surfaces captions.
    func embedUrlsFor(item: MediaItem, episode: MediaEpisode?, preferredDomain: String?,
                      subtitleUrl: String = "", subtitleLanguage: String = "") -> [URL] {
        guard let id = idFor(item) else { return [] }
        var extraQuery: [URLQueryItem] = []
        let cleanSub = subtitleUrl.trimmed
        if !cleanSub.isEmpty, let u = URL(string: cleanSub), u.scheme != nil {
            extraQuery.append(URLQueryItem(name: "sub_url", value: cleanSub))
        }
        let cleanLang = subtitleLanguage.trimmed
        if !cleanLang.isEmpty {
            extraQuery.append(URLQueryItem(name: "ds_lang", value: cleanLang))
        }
        return orderedDomains(preferredDomain).map { domain in
            let base = embedUri(domain: domain, item: item, episode: episode, id: id)
            if extraQuery.isEmpty { return base }
            var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
            comps.queryItems = extraQuery
            return comps.url ?? base
        }
    }

    /// Walks rcp -> prorcp on an embed-page HTML body and returns the m3u8 stream.
    func resolveFromEmbedHtml(embedHtml: String, userAgent: String? = nil) async throws -> VidsrcStream {
        let parsed = parseServers(embedHtml)
        if parsed.servers.isEmpty {
            throw VidsrcExtractorException("No servers listed on embed page")
        }
        let ua = userAgent ?? randomUserAgent()
        var lastError: Error?
        for server in parsed.servers {
            do {
                return try await resolveServer(server: server, base: parsed.base, ua: ua, title: parsed.title)
            } catch {
                lastError = error
            }
        }
        throw VidsrcExtractorException(
            "No working server (\(parsed.servers.count) tried). Last: \(String(describing: lastError))")
    }

    /// HTTP-only fallback: tries each domain, fetches the embed HTML, then resolves.
    func resolve(item: MediaItem, episode: MediaEpisode?, preferredDomain: String?) async throws -> VidsrcStream {
        guard let id = idFor(item) else {
            throw VidsrcExtractorException("No IMDb/TMDB id for this title")
        }
        let domains = orderedDomains(preferredDomain)
        var lastError: Error?
        for domain in domains {
            do {
                let ua = randomUserAgent()
                let embedUri = embedUri(domain: domain, item: item, episode: episode, id: id)
                let embedResponse = try await Http.shared.request(
                    embedUri, headers: headers(ua, referer: "https://\(domain)/"), timeout: 18)
                if embedResponse.status >= 400 {
                    throw VidsrcExtractorException("\(domain) returned HTTP \(embedResponse.status)")
                }
                return try await resolveFromEmbedHtml(embedHtml: embedResponse.bodyString, userAgent: ua)
            } catch {
                lastError = error
            }
        }
        throw VidsrcExtractorException(
            "Could not extract a playable stream from VidSrc. Last error: \(String(describing: lastError))")
    }

    /// Public variant used by the WebView resolver which already has base + dataHash.
    func resolveServer(base: URL, dataHash: String, name: String, title: String, userAgent: String) async throws -> VidsrcStream {
        try await resolveServer(server: Server(name: name, dataHash: dataHash), base: base, ua: userAgent, title: title)
    }

    private func resolveServer(server: Server, base: URL, ua: String, title: String) async throws -> VidsrcStream {
        let baseStr = base.absoluteString
        let rcpUri = replacePath(base, "/rcp/\(server.dataHash)")
        let rcpResp = try await Http.shared.request(rcpUri, headers: headers(ua, referer: "\(baseStr)/"), timeout: 14)
        if rcpResp.status >= 400 {
            throw VidsrcExtractorException("rcp HTTP \(rcpResp.status)")
        }
        guard let src = firstMatch(in: rcpResp.bodyString, pattern: "src:\\s*'([^']*)'") else {
            throw VidsrcExtractorException("rcp response missing src")
        }
        if !src.hasPrefix("/prorcp/") {
            throw VidsrcExtractorException("Unexpected src prefix: \(src)")
        }

        let prorcpUri = replacePath(base, src)
        let prorcpResp = try await Http.shared.request(prorcpUri, headers: headers(ua, referer: "\(baseStr)/"), timeout: 14)
        if prorcpResp.status >= 400 {
            throw VidsrcExtractorException("prorcp HTTP \(prorcpResp.status)")
        }
        guard let streamUrl = firstMatch(in: prorcpResp.bodyString, pattern: "file:\\s*'([^']*)'") else {
            throw VidsrcExtractorException("prorcp response missing file")
        }

        var origin = "\(base.scheme ?? "https")://\(base.host ?? "")"
        if let port = base.port { origin += ":\(port)" }
        return VidsrcStream(
            streamUrl: streamUrl,
            headers: [
                "Referer": "\(baseStr)/",
                "User-Agent": ua,
                "Origin": origin,
            ],
            serverName: server.name,
            title: title
        )
    }

    // MARK: Embed URL

    private func embedUri(domain: String, item: MediaItem, episode: MediaEpisode?, id: String) -> URL {
        // stremsrc uses /embed/movie/{id} and /embed/tv/{id}/{season}-{episode}.
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = domain
        if item.type == .movie {
            comps.path = "/embed/movie/\(id)"
        } else {
            let season = episode?.seasonNumber ?? 1
            let ep = episode?.episodeNumber ?? 1
            comps.path = "/embed/tv/\(id)/\(season)-\(ep)"
        }
        return comps.url!
    }

    // MARK: HTML parsing (regex / string scanning, no external lib)

    private func parseServers(_ html: String) -> ParsedEmbed {
        let title = firstMatch(in: html, pattern: "<title[^>]*>([\\s\\S]*?)</title>")?.trimmed ?? ""

        let iframeSrc = firstIframeSrc(html) ?? ""
        let normalized = iframeSrc.hasPrefix("//") ? "https:\(iframeSrc)" : iframeSrc
        let resolved = normalized.isEmpty ? nil : URL(string: normalized)
        let fallback = URL(string: "https://cloudnestra.com/")!
        let base = resolved ?? fallback

        // base0 = scheme + host (+ port) only.
        var comps = URLComponents()
        comps.scheme = base.scheme ?? "https"
        comps.host = base.host ?? "cloudnestra.com"
        if let port = base.port { comps.port = port }
        comps.path = "/"
        let base0 = comps.url ?? fallback

        let servers = parseServerList(html)
        return ParsedEmbed(base: base0, servers: servers, title: title)
    }

    /// Extract the first <iframe ... src="..."> value (handles single/double quotes).
    private func firstIframeSrc(_ html: String) -> String? {
        guard let iframeTag = firstMatch(in: html, pattern: "<iframe\\b([^>]*)>", group: 1) else { return nil }
        if let v = firstMatch(in: iframeTag, pattern: "src\\s*=\\s*\"([^\"]*)\"") { return v }
        if let v = firstMatch(in: iframeTag, pattern: "src\\s*=\\s*'([^']*)'") { return v }
        return nil
    }

    /// Find `.serversList .server` elements carrying `data-hash`. We scan all
    /// tags bearing a `data-hash` attribute (the embed markup tags these as the
    /// server buttons) and read the element's text as the server name.
    private func parseServerList(_ html: String) -> [Server] {
        var servers: [Server] = []
        // Match an opening tag with data-hash, then capture text up to the next tag.
        let pattern = "<[^>]*\\bdata-hash\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>([\\s\\S]*?)<"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return servers
        }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        for m in matches where m.numberOfRanges >= 3 {
            let hash = ns.substring(with: m.range(at: 1)).trimmed
            guard !hash.isEmpty else { continue }
            let rawText = ns.substring(with: m.range(at: 2))
            let name = stripTags(rawText).trimmed
            servers.append(Server(name: name, dataHash: hash))
        }
        return servers
    }

    private func stripTags(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func firstMatch(in text: String, pattern: String, group: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > group, m.range(at: group).location != NSNotFound else { return nil }
        return ns.substring(with: m.range(at: group))
    }

    private func replacePath(_ url: URL, _ path: String) -> URL {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        comps.path = path
        comps.query = nil
        return comps.url ?? url
    }

    // MARK: Headers / UA / id / domains

    private func headers(_ ua: String, referer: String) -> [String: String] {
        [
            "User-Agent": ua,
            "Accept": "*/*",
            "Accept-Language": "en-US,en;q=0.9",
            "Referer": referer,
            "Sec-Fetch-Dest": "iframe",
            "Sec-Fetch-Mode": "no-cors",
            "Sec-Fetch-Site": "same-origin",
        ]
    }

    private func randomUserAgent() -> String {
        let index = Int(DispatchTime.now().uptimeNanoseconds / 1000) % Self.userAgents.count
        return Self.userAgents[index]
    }

    private func idFor(_ item: MediaItem) -> String? {
        if let imdb = item.imdbId?.trimmed, !imdb.isEmpty { return imdb }
        if let tmdbId = item.tmdbId { return String(tmdbId) }
        return nil
    }

    private func orderedDomains(_ preferred: String?) -> [String] {
        guard let preferred else { return Self.sourceHosts }
        let clean = preferred.trimmed
        if !Self.sourceHosts.contains(clean) { return Self.sourceHosts }
        return [clean] + Self.sourceHosts.filter { $0 != clean }
    }
}
