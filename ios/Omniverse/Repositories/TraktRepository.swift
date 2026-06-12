import Foundation

/// Native port of the Flutter `TraktRepository`. Talks to the Trakt API
/// (https://api.trakt.tv/) for OAuth, discovery rows, watchlist sync, playback
/// progress, scrobbling and remote-settings storage.
///
/// Faithful to ../../../lib/src/repositories/trakt_repository.dart — endpoints,
/// headers, request bodies and response parsing are preserved exactly.
final class TraktRepository: TraktRepositoryProtocol {

    private let base = URL(string: "https://api.trakt.tv/")!
    private static let redirectUri = "omniplay://trakt/oauth"
    /// Refresh the token if it would expire within this window (5 minutes, ms).
    private static let tokenRefreshSkewMs = 5 * 60 * 1000

    enum TraktError: Error, CustomStringConvertible {
        case state(String)
        case response(label: String, status: Int, body: String)
        var description: String {
            switch self {
            case .state(let m): return m
            case .response(let label, let status, let body):
                return "\(label) returned \(status): \(body)"
            }
        }
    }

    // MARK: - OAuth

    func buildOAuthAuthorizeUri(_ c: ApiCredentials, state: String) -> URL? {
        guard c.hasTraktApp else { return nil }
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "trakt.tv"
        comps.path = "/oauth/authorize"
        comps.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: c.traktClientId),
            URLQueryItem(name: "redirect_uri", value: Self.redirectUri),
            URLQueryItem(name: "state", value: state),
        ]
        return comps.url
    }

    func ensureFreshAccessToken(_ c: ApiCredentials) async throws -> ApiCredentials {
        if !c.hasTraktUser || c.traktTokenExpiresAt == 0 { return c }
        let refreshAt = Int(Date().timeIntervalSince1970 * 1000) + Self.tokenRefreshSkewMs
        if c.traktTokenExpiresAt > refreshAt { return c }
        if !c.canRefreshTrakt {
            throw TraktError.state("Reconnect Trakt to refresh your OAuth session.")
        }
        return try await refreshAccessToken(c)
    }

    func exchangeAuthorizationCode(_ c: ApiCredentials, code: String) async throws -> ApiCredentials {
        guard c.hasTraktApp, !c.traktClientSecret.trimmed.isEmpty else {
            throw TraktError.state("Save your Trakt client ID and client secret first.")
        }
        return try await exchangeToken(c, body: [
            "code": code,
            "client_id": c.traktClientId.trimmed,
            "client_secret": c.traktClientSecret.trimmed,
            "redirect_uri": Self.redirectUri,
            "grant_type": "authorization_code",
        ], failureLabel: "Trakt OAuth")
    }

    private func refreshAccessToken(_ c: ApiCredentials) async throws -> ApiCredentials {
        guard c.canRefreshTrakt else {
            throw TraktError.state("Reconnect Trakt to refresh your OAuth session.")
        }
        return try await exchangeToken(c, body: [
            "refresh_token": c.traktRefreshToken.trimmed,
            "client_id": c.traktClientId.trimmed,
            "client_secret": c.traktClientSecret.trimmed,
            "redirect_uri": Self.redirectUri,
            "grant_type": "refresh_token",
        ], failureLabel: "Trakt token refresh")
    }

    func startDeviceAuth(_ c: ApiCredentials) async throws -> TraktDeviceCode {
        guard c.hasTraktApp else {
            throw TraktError.state("Save a Trakt client ID first.")
        }
        // NOTE: client_id is NOT trimmed here, matching the Dart implementation.
        let r = try await postRaw("oauth/device/code",
                                  body: ["client_id": c.traktClientId],
                                  headers: ["Content-Type": "application/json"])
        if r.status >= 400 {
            throw TraktError.state("Trakt device auth returned \(r.status)")
        }
        let json = r.jsonObject()
        return TraktDeviceCode(
            deviceCode: json.str("device_code") ?? "",
            userCode: json.str("user_code") ?? "",
            verificationUrl: json.str("verification_url") ?? "",
            expiresIn: json.int("expires_in") ?? 0,
            interval: json.int("interval") ?? 0
        )
    }

    func completeDeviceAuth(_ c: ApiCredentials, _ code: TraktDeviceCode) async throws -> ApiCredentials {
        return try await exchangeToken(c, path: "oauth/device/token", body: [
            "code": code.deviceCode,
            "client_id": c.traktClientId.trimmed,
            "client_secret": c.traktClientSecret.trimmed,
        ], failureLabel: "Trakt token request")
    }

    // MARK: - User settings

    func fetchUserSettings(_ c: ApiCredentials) async throws -> ApiCredentials {
        if !c.hasTraktUser { return c }
        let r = try await get("users/settings", c, query: ["extended": "browsing"])
        try throwForResponse(r, "Trakt user settings")
        let json = r.jsonObject()
        let user = json.obj("user") ?? [:]
        let username = user.str("username") ?? ""
        var out = c
        out.traktUsername = username
        return out
    }

    // MARK: - Discovery

    func fetchDiscoveryCategories(_ c: ApiCredentials) async throws -> [MediaCategory] {
        if !c.hasTraktApp { return [] }
        async let movies = discoveryCategory(
            c,
            id: "trakt_trending_movies",
            title: "Trending Movies on Trakt",
            description: "Movies with the most Trakt watchers right now",
            path: "movies/trending",
            type: .movie,
            mediaKey: "movie"
        )
        async let series = discoveryCategory(
            c,
            id: "trakt_trending_series",
            title: "Trending Shows on Trakt",
            description: "Shows with the most Trakt watchers right now",
            path: "shows/trending",
            type: .series,
            mediaKey: "show"
        )
        return await [movies, series]
    }

    private func discoveryCategory(
        _ c: ApiCredentials,
        id: String,
        title: String,
        description: String,
        path: String,
        type: MediaType,
        mediaKey: String?
    ) async -> MediaCategory {
        do {
            let r = try await get(path, c, query: ["extended": "full", "limit": "18"],
                                  includeAuth: false)
            if r.status >= 400 {
                return MediaCategory(
                    id: id, title: title, type: type, items: [],
                    description: description,
                    error: "Trakt returned \(r.status). Check your API key."
                )
            }
            let data = r.jsonArray()
            var items: [MediaItem] = []
            for case let entry as [String: Any] in data {
                let mediaDict: [String: Any]?
                if let key = mediaKey {
                    mediaDict = entry.obj(key)
                } else {
                    mediaDict = entry
                }
                guard let mediaDict else { continue }
                if let m = fromTraktMedia(mediaDict, type: type) {
                    items.append(m)
                    if items.count >= 18 { break }
                }
            }
            return MediaCategory(
                id: id, title: title, type: type, items: items,
                description: description
            )
        } catch {
            return MediaCategory(
                id: id, title: title, type: type, items: [],
                description: description,
                error: "Could not load Trakt row: \(error)"
            )
        }
    }

    // MARK: - Watchlist

    func fetchWatchlist(_ c: ApiCredentials) async throws -> [MediaItem] {
        if !c.hasTraktUser { return [] }
        let r = try await get("sync/watchlist", c, query: ["extended": "full"])
        try throwForResponse(r, "Trakt watchlist")
        let data = r.jsonArray()
        var out: [MediaItem] = []
        for case let entry as [String: Any] in data {
            if let item = fromWatchlist(entry) { out.append(item) }
        }
        return out
    }

    func setWatchlistItem(_ c: ApiCredentials, _ item: MediaItem, add: Bool) async throws {
        guard let body = bulkBodyFor(item) else { return }
        let r = try await post(add ? "sync/watchlist" : "sync/watchlist/remove", c, body: body)
        if r.status != 200 && r.status != 201 {
            try throwForResponse(r, "Trakt watchlist sync")
        }
    }

    private func fromWatchlist(_ json: [String: Any]) -> MediaItem? {
        let movie = json.obj("movie")
        let show = json.obj("show")
        guard let value = movie ?? show else { return nil }
        return fromTraktMedia(value, type: movie == nil ? .series : .movie)
    }

    // MARK: - Playback progress

    func fetchPlaybackProgress(_ c: ApiCredentials) async -> [WatchProgress] {
        if !c.hasTraktUser { return [] }
        do {
            let r = try await get("sync/playback/movies,episodes", c, query: ["extended": "full"])
            if r.status >= 400 { return [] }
            guard let data = try? r.json() as? [Any] else { return [] }
            let now = Int(Date().timeIntervalSince1970 * 1000)
            var out: [WatchProgress] = []
            for case let entry as [String: Any] in data {
                if let wp = watchProgressFrom(entry, nowMs: now) { out.append(wp) }
            }
            return out
        } catch {
            return []
        }
    }

    private func watchProgressFrom(_ entry: [String: Any], nowMs: Int) -> WatchProgress? {
        let progressPct = entry.dbl("progress") ?? 0
        let pausedAtMs: Int
        if let pausedAt = entry.str("paused_at") {
            pausedAtMs = Self.parseIso8601Ms(pausedAt) ?? nowMs
        } else {
            pausedAtMs = nowMs
        }
        let episode = entry.obj("episode")
        let show = entry.obj("show")
        let movie = entry.obj("movie")
        let playbackId = entry.int("id")

        if let movie {
            let ids = movie.obj("ids") ?? [:]
            let title = movie.str("title") ?? ""
            let tmdb = ids.int("tmdb")
            let runtime = movie.int("runtime") ?? 0
            // Trakt stores progress as percent; fabricate a duration so the UI's
            // fraction math is consistent. Use runtime minutes when present,
            // otherwise 100 (so positionMs == progress %).
            let durationMs = runtime > 0 ? runtime * 60 * 1000 : 100
            let positionMs = Int((progressPct * Double(durationMs) / 100).rounded())
            let itemId = tmdb != nil
                ? "tmdb:movie:\(tmdb!)"
                : "trakt:movie:\(ids["trakt"].map { "\($0)" } ?? title)"
            return WatchProgress(
                id: playbackId,
                itemId: itemId,
                title: title,
                type: .movie,
                posterPath: nil,
                backdropPath: nil,
                seasonNumber: nil,
                episodeNumber: nil,
                episodeTitle: nil,
                positionMs: positionMs,
                durationMs: durationMs,
                lastWatchedAt: pausedAtMs
            )
        }
        if let episode, let show {
            let ids = show.obj("ids") ?? [:]
            let showTitle = show.str("title") ?? ""
            let season = episode.int("season") ?? 0
            let number = episode.int("number") ?? 0
            let epTitle = episode.str("title")
            let runtime = episode.int("runtime") ?? show.int("runtime") ?? 0
            let durationMs = runtime > 0 ? runtime * 60 * 1000 : 100
            let positionMs = Int((progressPct * Double(durationMs) / 100).rounded())
            let tmdb = ids.int("tmdb")
            let itemId = tmdb != nil
                ? "tmdb:series:\(tmdb!)"
                : "trakt:series:\(ids["trakt"].map { "\($0)" } ?? showTitle)"
            return WatchProgress(
                id: playbackId,
                itemId: itemId,
                title: showTitle,
                type: .series,
                posterPath: nil,
                backdropPath: nil,
                seasonNumber: season,
                episodeNumber: number,
                episodeTitle: epTitle,
                positionMs: positionMs,
                durationMs: durationMs,
                lastWatchedAt: pausedAtMs
            )
        }
        return nil
    }

    func deletePlaybackProgress(_ c: ApiCredentials, playbackId: Int) async throws {
        if !c.hasTraktUser { return }
        let url = base.appendingPathComponent("sync/playback/\(playbackId)")
        let r = try await Http.shared.request(url, method: "DELETE", headers: headers(c, includeAuth: true))
        if r.status != 204 && r.status != 200 {
            try throwForResponse(r, "Trakt playback delete")
        }
    }

    // MARK: - Scrobble

    func startScrobble(_ c: ApiCredentials, _ item: MediaItem, episode: MediaEpisode?, progress: Double) async throws {
        try await scrobble(c, item, episode: episode, action: "start", progress: progress)
    }

    func pauseScrobble(_ c: ApiCredentials, _ item: MediaItem, episode: MediaEpisode?, progress: Double) async throws {
        try await scrobble(c, item, episode: episode, action: "pause", progress: progress)
    }

    func stopScrobble(_ c: ApiCredentials, _ item: MediaItem, episode: MediaEpisode?, progress: Double) async throws {
        try await scrobble(c, item, episode: episode, action: "stop", progress: progress)
    }

    private func scrobble(_ c: ApiCredentials, _ item: MediaItem, episode: MediaEpisode?, action: String, progress: Double) async throws {
        guard let body = scrobbleBody(item, episode, progress) else { return }
        if action == "stop", let p = body["progress"] as? Double, p < 1 { return }
        let r = try await post("scrobble/\(action)", c, body: body)
        if r.status == 409 { return }
        if r.status != 200 && r.status != 201 {
            try throwForResponse(r, "Trakt scrobble")
        }
    }

    private func scrobbleBody(_ item: MediaItem, _ episode: MediaEpisode?, _ progress: Double) -> [String: Any]? {
        if item.type == .movie {
            let ids = idsFor(item, includeTvdb: false)
            if ids.isEmpty { return nil }
            return [
                "movie": ["ids": ids],
                "progress": cleanProgress(progress),
            ]
        } else if let episode {
            let showIds = idsFor(item, includeTvdb: false)
            if showIds.isEmpty { return nil }
            let originalSeason = episode.seasonNumber >= 1000
                ? Int(floor(Double(episode.seasonNumber) / 1000))
                : episode.seasonNumber
            return [
                "show": ["ids": showIds],
                "episode": [
                    "season": originalSeason,
                    "number": episode.episodeNumber,
                ],
                "progress": cleanProgress(progress),
            ]
        }
        return nil
    }

    // MARK: - Remote settings

    func fetchRemoteSettings(_ c: ApiCredentials) async -> String? {
        if !c.hasTraktUser { return nil }
        do {
            let r = try await get("users/me/lists", c)
            if r.status >= 400 { return nil }
            let data = r.jsonArray()
            for case let list as [String: Any] in data {
                let name = list.str("name")
                if name == "Omniverse Sync" || name == "Omniplay Sync" {
                    return list.str("description")
                }
            }
            return nil
        } catch {
            return nil
        }
    }

    func saveRemoteSettings(_ c: ApiCredentials, payload: String) async throws {
        if !c.hasTraktUser { return }

        // Check if the list already exists.
        let listResponse = try await get("users/me/lists", c)
        var existingListId: Int?
        if listResponse.status == 200 {
            let data = listResponse.jsonArray()
            for case let list as [String: Any] in data {
                let name = list.str("name")
                if name == "Omniverse Sync" || name == "Omniplay Sync" {
                    existingListId = list.obj("ids")?.int("trakt")
                    break
                }
            }
        }

        let body: [String: Any] = [
            "name": "Omniverse Sync",
            "description": payload,
            "privacy": "private",
        ]

        if let existingListId {
            // Update existing list.
            let url = base.appendingPathComponent("users/me/lists/\(existingListId)")
            let data = try JSONSerialization.data(withJSONObject: body)
            let r = try await Http.shared.request(url, method: "PUT",
                                                  headers: headers(c, includeAuth: true), body: data)
            try throwForResponse(r, "Trakt settings update")
        } else {
            // Create new list.
            let r = try await post("users/me/lists", c, body: body)
            try throwForResponse(r, "Trakt settings create")
        }
    }

    // MARK: - Trakt media parsing

    private func fromTraktMedia(_ value: [String: Any], type: MediaType) -> MediaItem? {
        let ids = value.obj("ids") ?? [:]
        let title = value.str("title") ?? value.str("name")
        guard let title, !title.isEmpty else { return nil }
        let year = value.int("year")
        let firstAired = value.str("first_aired")
        let releaseDate = firstAired ?? year.map { String($0) } ?? ""
        let idSuffix = ids["trakt"].map { "\($0)" } ?? (value.str("title") ?? title)
        return MediaItem(
            id: "trakt:\(type.rawValue):\(idSuffix)",
            type: type,
            title: title,
            overview: value.str("overview") ?? "",
            releaseDate: releaseDate,
            rating: value.dbl("rating") ?? 0,
            voteCount: value.int("votes") ?? 0,
            tmdbId: ids.int("tmdb"),
            tvdbId: ids.int("tvdb"),
            traktId: ids.int("trakt"),
            imdbId: ids.str("imdb"),
            source: "trakt"
        )
    }

    // MARK: - Bulk (watchlist) bodies

    private func bulkBodyFor(_ item: MediaItem) -> [String: Any]? {
        guard let entry = bulkEntryFor(item) else { return nil }
        switch item.type {
        case .movie: return ["movies": [entry]]
        case .series: return ["shows": [entry]]
        case .anime: return ["shows": [entry]]
        case .liveTv: return nil
        }
    }

    private func bulkEntryFor(_ item: MediaItem) -> [String: Any]? {
        let ids = idsFor(item, includeTvdb: item.type == .series || item.type == .anime)
        if !ids.isEmpty { return ["ids": ids] }
        guard let year = releaseYear(item.releaseDate) else { return nil }
        return ["title": item.title, "year": year]
    }

    private func idsFor(_ item: MediaItem, includeTvdb: Bool) -> [String: Any] {
        var ids: [String: Any] = [:]
        if let trakt = item.traktId { ids["trakt"] = trakt }
        if let imdb = item.imdbId, !imdb.trimmed.isEmpty { ids["imdb"] = imdb.trimmed }
        if let tmdb = item.tmdbId { ids["tmdb"] = tmdb }
        if includeTvdb, let tvdb = item.tvdbId { ids["tvdb"] = tvdb }
        return ids
    }

    private func releaseYear(_ value: String) -> Int? {
        guard let range = value.range(of: #"\d{4}"#, options: .regularExpression) else { return nil }
        return Int(value[range])
    }

    private func cleanProgress(_ progress: Double) -> Double {
        let clamped = min(max(progress, 0), 100)
        return (Double(String(format: "%.2f", clamped))) ?? clamped
    }

    // MARK: - Token exchange

    private func exchangeToken(_ c: ApiCredentials,
                               path: String = "oauth/token",
                               body: [String: Any],
                               failureLabel: String) async throws -> ApiCredentials {
        // Token endpoints use Content-Type only (no api-key / auth headers).
        let r = try await postRaw(path, body: body, headers: ["Content-Type": "application/json"])
        try throwForResponse(r, failureLabel)
        let json = r.jsonObject()
        return credentialsFromToken(c, json)
    }

    private func credentialsFromToken(_ c: ApiCredentials, _ json: [String: Any]) -> ApiCredentials {
        let createdAtSeconds = json.int("created_at") ?? Int(Date().timeIntervalSince1970)
        let expiresIn = json.int("expires_in") ?? 0
        let expiresAt = expiresIn <= 0 ? 0 : (createdAtSeconds + expiresIn) * 1000
        var out = c
        out.traktAccessToken = json.str("access_token") ?? ""
        out.traktRefreshToken = json.str("refresh_token") ?? ""
        out.traktTokenExpiresAt = expiresAt
        return out
    }

    // MARK: - HTTP plumbing

    private func get(_ path: String,
                     _ c: ApiCredentials,
                     query: [String: String] = [:],
                     includeAuth: Bool = true) async throws -> Http.Response {
        let url = resolve(path, query: query)
        return try await Http.shared.request(url, method: "GET", headers: headers(c, includeAuth: includeAuth))
    }

    private func post(_ path: String,
                      _ c: ApiCredentials,
                      body: [String: Any],
                      includeAuth: Bool = true) async throws -> Http.Response {
        let url = resolve(path, query: [:])
        let data = try JSONSerialization.data(withJSONObject: body)
        return try await Http.shared.request(url, method: "POST",
                                             headers: headers(c, includeAuth: includeAuth), body: data)
    }

    /// POST with an explicit header set (used by token / device endpoints, which
    /// send Content-Type only and no Trakt api-key / auth headers).
    private func postRaw(_ path: String,
                         body: [String: Any],
                         headers: [String: String]) async throws -> Http.Response {
        let url = resolve(path, query: [:])
        let data = try JSONSerialization.data(withJSONObject: body)
        return try await Http.shared.request(url, method: "POST", headers: headers, body: data)
    }

    private func resolve(_ path: String, query: [String: String]) -> URL {
        // Match Dart's Uri.resolve against the base, then attach query params.
        let resolved = URL(string: path, relativeTo: base)?.absoluteURL
            ?? base.appendingPathComponent(path)
        guard !query.isEmpty,
              var comps = URLComponents(url: resolved, resolvingAgainstBaseURL: false) else {
            return resolved
        }
        comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        return comps.url ?? resolved
    }

    private func headers(_ c: ApiCredentials, includeAuth: Bool) -> [String: String] {
        var h: [String: String] = [
            "Content-Type": "application/json",
            "trakt-api-version": "2",
        ]
        if c.hasTraktApp {
            h["trakt-api-key"] = c.traktClientId.trimmed
        }
        if includeAuth && c.hasTraktUser {
            h["Authorization"] = "Bearer \(c.traktAccessToken.trimmed)"
        }
        return h
    }

    private func throwForResponse(_ r: Http.Response, _ label: String) throws {
        if r.status < 400 { return }
        throw TraktError.response(label: label, status: r.status, body: r.bodyString)
    }

    // MARK: - Date parsing

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso8601NoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Parse an ISO-8601 timestamp (e.g. Trakt's `paused_at`) to epoch ms.
    private static func parseIso8601Ms(_ s: String) -> Int? {
        if let d = iso8601.date(from: s) { return Int(d.timeIntervalSince1970 * 1000) }
        if let d = iso8601NoFraction.date(from: s) { return Int(d.timeIntervalSince1970 * 1000) }
        return nil
    }
}
