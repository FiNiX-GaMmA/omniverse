import Foundation

// MARK: - MediaItem.fromTmdb

extension MediaItem {
    /// Builds a MediaItem from a TMDB list/search result row.
    /// id = "tmdb:{type}:{id}". Mirrors `MediaItem.fromTmdb` in models.dart.
    static func fromTmdb(_ json: [String: Any], _ type: MediaType, genreNames: [Int: String] = [:]) -> MediaItem? {
        guard let id = json.int("id") else { return nil }
        let title = (json.str("title") ?? json.str("name")) ?? "Untitled"
        let date = (json.str("release_date") ?? json.str("first_air_date")) ?? ""
        let genreIds = (json.arr("genre_ids") ?? []).compactMap { value -> Int? in
            if let n = value as? Int { return n }
            if let n = value as? Double { return Int(n) }
            return nil
        }
        let genres = genreIds.compactMap { genreNames[$0] }
        let originCountry = (json.arr("origin_country") ?? []).compactMap { $0 as? String }
        return MediaItem(
            id: "tmdb:\(type.rawValue):\(id)",
            type: type,
            title: title,
            overview: json.str("overview") ?? "",
            posterPath: json.str("poster_path"),
            backdropPath: json.str("backdrop_path"),
            releaseDate: date,
            rating: json.dbl("vote_average") ?? 0,
            voteCount: json.int("vote_count") ?? 0,
            genres: genres,
            originCountry: originCountry,
            tmdbId: id
        )
    }
}

// MARK: - TmdbRepository

final class TmdbRepository: TmdbRepositoryProtocol {

    private let base = URL(string: "https://api.themoviedb.org/3/")!

    private struct CachedResponse {
        let response: Http.Response
        let expiresAt: Date
    }

    // Cache + concurrency gate. Actor-isolated state guards the cache and the
    // in-flight semaphore the same way the Dart Queue<Completer> did.
    private actor State {
        var cache: [String: CachedResponse] = [:]
        private var inflight = 0
        private var waiters: [CheckedContinuation<Void, Never>] = []

        static let maxInflight = 4
        static let cacheTtl: TimeInterval = 5 * 60

        func cached(_ key: String) -> Http.Response? {
            if let c = cache[key], Date() < c.expiresAt { return c.response }
            return nil
        }

        func store(_ key: String, _ response: Http.Response) {
            cache[key] = CachedResponse(response: response, expiresAt: Date().addingTimeInterval(Self.cacheTtl))
            evictExpired()
        }

        private func evictExpired() {
            guard cache.count > 80 else { return }
            let now = Date()
            cache = cache.filter { now <= $0.value.expiresAt }
        }

        func acquireSlot() async {
            if inflight < Self.maxInflight {
                inflight += 1
                return
            }
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                waiters.append(cont)
            }
        }

        func releaseSlot() {
            if inflight > 0 { inflight -= 1 }
            guard !waiters.isEmpty else { return }
            inflight += 1
            let cont = waiters.removeFirst()
            cont.resume()
        }
    }

    private let state = State()

    // MARK: Landing categories

    func fetchLandingCategories(credentials: ApiCredentials, settings: UserSettings) async throws -> [MediaCategory] {
        if !credentials.hasTmdb { return demoCategories }

        let (movieGenres, tvGenres) = await fetchGenres(credentials, settings)

        var categories: [MediaCategory] = []
        categories.append(await category(
            id: "trending_movies", title: "Trending Movies",
            description: "What people are watching this week",
            path: "trending/movie/week", type: .movie,
            credentials: credentials, settings: settings, genreNames: movieGenres))
        categories.append(await category(
            id: "now_playing", title: "Now Playing",
            description: "Current theatrical and recent movie releases",
            path: "movie/now_playing", type: .movie,
            credentials: credentials, settings: settings, genreNames: movieGenres))
        categories.append(await category(
            id: "action_movies", title: "Action Movies",
            description: "High-energy movies from TMDB Discover",
            path: "discover/movie", type: .movie,
            credentials: credentials, settings: settings, genreNames: movieGenres,
            query: ["with_genres": "28", "sort_by": "popularity.desc"]))
        categories.append(await category(
            id: "trending_series", title: "Trending TV Shows",
            description: "Series gaining momentum this week",
            path: "trending/tv/week", type: .series,
            credentials: credentials, settings: settings, genreNames: tvGenres))
        categories.append(await category(
            id: "airing_today", title: "Airing Today",
            description: "Episodes scheduled today",
            path: "tv/airing_today", type: .series,
            credentials: credentials, settings: settings, genreNames: tvGenres))
        categories.append(await category(
            id: "top_rated_series", title: "Top Rated TV",
            description: "Well-loved shows with strong audience scores",
            path: "tv/top_rated", type: .series,
            credentials: credentials, settings: settings, genreNames: tvGenres))
        return categories
    }

    // MARK: Details

    func fetchDetails(_ item: MediaItem, credentials: ApiCredentials, settings: UserSettings) async -> MediaItem? {
        guard credentials.hasTmdb, let tmdbId = item.tmdbId else { return item }
        let url = uri("\(item.type.tmdbPath)/\(tmdbId)", credentials, settings, [
            "append_to_response": "external_ids,credits,images",
            "include_image_language": imageLanguages(settings),
        ])
        guard let response = try? await get(url, credentials) else { return item }
        if response.status >= 400 { return item }
        let json = response.jsonObject()

        let images = json.obj("images")
        let posterPath = bestImagePath(
            images?["posters"],
            fallback: json.str("poster_path") ?? item.posterPath,
            targetRatio: 2.0 / 3.0)
        let backdropPath = bestImagePath(
            images?["backdrops"],
            fallback: json.str("backdrop_path") ?? item.backdropPath,
            targetRatio: 16.0 / 9.0)

        let seasons = seasonsFrom(json)
        let firstSeason = seasons.first { $0.seasonNumber > 0 }
        var episodes: [MediaEpisode] = []
        if item.type == .series, let firstSeason {
            var fallback = item
            if fallback.tmdbId == nil { fallback.tmdbId = json.int("id") }
            episodes = await fetchSeasonEpisodes(fallback, seasonNumber: firstSeason.seasonNumber,
                                                 credentials: credentials, settings: settings)
        }

        let externalIds = json.obj("external_ids")

        // origin_country (TV) + production_countries[].iso_3166_1 (movie).
        var origin: [String] = (json.arr("origin_country") ?? []).compactMap { $0 as? String }
        origin += (json.arr("production_countries") ?? [])
            .compactMap { $0 as? [String: Any] }
            .compactMap { $0.str("iso_3166_1") }
            .filter { !$0.isEmpty }

        let genres = (json.arr("genres") ?? [])
            .compactMap { $0 as? [String: Any] }
            .compactMap { $0.str("name") }
            .filter { !$0.isEmpty }

        return MediaItem(
            id: item.id,
            type: item.type,
            title: (json.str("title") ?? json.str("name")) ?? item.title,
            overview: json.str("overview") ?? item.overview,
            posterPath: posterPath,
            backdropPath: backdropPath,
            releaseDate: (json.str("release_date") ?? json.str("first_air_date")) ?? item.releaseDate,
            rating: json.dbl("vote_average") ?? item.rating,
            voteCount: json.int("vote_count") ?? item.voteCount,
            genres: genres,
            originCountry: origin,
            cast: castFrom(json),
            directors: directorsFrom(json),
            runtimeMinutes: runtimeFrom(json, item.type),
            seasons: seasons,
            episodes: episodes,
            tmdbId: item.tmdbId,
            tvdbId: externalIds?.int("tvdb_id") ?? item.tvdbId,
            traktId: item.traktId,
            imdbId: externalIds?.str("imdb_id") ?? json.str("imdb_id") ?? item.imdbId,
            source: item.source
        )
    }

    // MARK: Search

    func searchMulti(_ query: String, credentials: ApiCredentials, settings: UserSettings) async -> [MediaItem] {
        let trimmed = query.trimmed
        if trimmed.isEmpty || !credentials.hasTmdb { return [] }

        let url1 = uri("search/multi", credentials, settings, ["query": trimmed, "page": "1"])
        let url2 = uri("search/multi", credentials, settings, ["query": trimmed, "page": "2"])

        async let p1 = try? get(url1, credentials)
        async let p2 = try? get(url2, credentials)
        let pages = [await p1, await p2].compactMap { $0 }

        var results: [MediaItem] = []
        var seen = Set<String>()
        for response in pages {
            if response.status >= 400 { continue }
            let body = response.jsonObject()
            for raw in (body.arr("results") ?? []) {
                guard let dict = raw as? [String: Any] else { continue }
                let mediaType = dict.str("media_type")
                let type: MediaType
                if mediaType == "movie" { type = .movie }
                else if mediaType == "tv" { type = .series }
                else { continue }
                guard let mediaItem = MediaItem.fromTmdb(dict, type, genreNames: [:]) else { continue }
                if mediaItem.posterPath == nil && mediaItem.backdropPath == nil { continue }
                if !seen.insert(mediaItem.id).inserted { continue }
                results.append(mediaItem)
            }
        }
        return Array(results.prefix(40))
    }

    // MARK: Season episodes

    func fetchSeasonEpisodes(_ item: MediaItem, seasonNumber: Int, credentials: ApiCredentials, settings: UserSettings) async -> [MediaEpisode] {
        guard credentials.hasTmdb, item.type == .series, let tmdbId = item.tmdbId else { return [] }
        guard let response = try? await get(uri("tv/\(tmdbId)/season/\(seasonNumber)", credentials, settings), credentials) else { return [] }
        if response.status >= 400 { return [] }
        let json = response.jsonObject()
        return (json.arr("episodes") ?? [])
            .compactMap { $0 as? [String: Any] }
            .map { episode in
                MediaEpisode(
                    seasonNumber: episode.int("season_number") ?? seasonNumber,
                    episodeNumber: episode.int("episode_number") ?? 0,
                    title: episode.str("name") ?? "Episode",
                    overview: episode.str("overview") ?? "",
                    airDate: episode.str("air_date") ?? "",
                    runtimeMinutes: episode.int("runtime"),
                    stillPath: episode.str("still_path")
                )
            }
    }

    /// TMDB "more like this" recommendations for the given movie/series. Powers
    /// the end-of-show recommendation rail when there are no more episodes.
    func fetchRecommendations(_ item: MediaItem, credentials: ApiCredentials, settings: UserSettings) async -> [MediaItem] {
        guard credentials.hasTmdb, let tmdbId = item.tmdbId else { return [] }
        let type: MediaType = item.type == .movie ? .movie : .series
        let path = "\(type.tmdbPath)/\(tmdbId)/recommendations"
        guard let response = try? await get(uri(path, credentials, settings), credentials) else { return [] }
        if response.status >= 400 { return [] }
        let body = response.jsonObject()
        return (body.arr("results") ?? [])
            .compactMap { $0 as? [String: Any] }
            .filter { ($0.str("media_type")) != "person" }
            .compactMap { MediaItem.fromTmdb($0, type) }
            .filter { $0.posterPath != nil || $0.backdropPath != nil }
            .prefix(18)
            .map { $0 }
    }

    // MARK: Genres

    private func fetchGenres(_ credentials: ApiCredentials, _ settings: UserSettings) async -> ([Int: String], [Int: String]) {
        func fetch(_ path: String) async -> [Int: String] {
            guard let response = try? await get(uri(path, credentials, settings), credentials) else { return [:] }
            if response.status >= 400 { return [:] }
            let body = response.jsonObject()
            var map: [Int: String] = [:]
            for genre in (body.arr("genres") ?? []) {
                guard let g = genre as? [String: Any], let gid = g.int("id"), let name = g.str("name") else { continue }
                map[gid] = name
            }
            return map
        }
        let movie = await fetch("genre/movie/list")
        let tv = await fetch("genre/tv/list")
        return (movie, tv)
    }

    // MARK: Category builder

    private func category(id: String, title: String, description: String, path: String, type: MediaType,
                          credentials: ApiCredentials, settings: UserSettings, genreNames: [Int: String],
                          query: [String: String] = [:]) async -> MediaCategory {
        do {
            let response = try await get(uri(path, credentials, settings, query), credentials)
            if response.status >= 400 {
                return MediaCategory(id: id, title: title, type: type, items: [], description: description,
                                     error: statusMessage(response.status))
            }
            let body = response.jsonObject()
            let items = (body.arr("results") ?? [])
                .compactMap { $0 as? [String: Any] }
                .filter { ($0.str("media_type")) != "person" }
                .compactMap { MediaItem.fromTmdb($0, type, genreNames: genreNames) }
                .filter { $0.posterPath != nil || $0.backdropPath != nil }
                .prefix(18)
            return MediaCategory(id: id, title: title, type: type, items: Array(items), description: description)
        } catch {
            return MediaCategory(id: id, title: title, type: type, items: [], description: description,
                                 error: friendlyError(error))
        }
    }

    // MARK: URL + headers

    private func uri(_ path: String, _ credentials: ApiCredentials, _ settings: UserSettings, _ query: [String: String] = [:]) -> URL {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "language", value: settings.language),
            URLQueryItem(name: "region", value: settings.region),
            URLQueryItem(name: "include_adult", value: settings.includeAdult ? "true" : "false"),
        ]
        for (k, v) in query { items.append(URLQueryItem(name: k, value: v)) }
        if !usesBearer(credentials.tmdbToken) {
            items.append(URLQueryItem(name: "api_key", value: credentials.tmdbToken.trimmed))
        }
        comps.queryItems = items
        return comps.url!
    }

    private func headers(_ credentials: ApiCredentials) -> [String: String] {
        var h = ["Accept": "application/json", "User-Agent": "Omniplay/1.0"]
        if usesBearer(credentials.tmdbToken) {
            h["Authorization"] = "Bearer \(credentials.tmdbToken.trimmed)"
        }
        return h
    }

    private func usesBearer(_ value: String) -> Bool { value.trimmed.hasPrefix("ey") }

    // MARK: Networking with cache + retry + concurrency gate

    private func get(_ url: URL, _ credentials: ApiCredentials) async throws -> Http.Response {
        let key = cacheKey(url, credentials)
        if let cached = await state.cached(key) { return cached }

        var lastError: Error?
        for attempt in 0..<3 {
            do {
                await state.acquireSlot()
                let response: Http.Response
                do {
                    response = try await Http.shared.request(url, headers: headers(credentials), timeout: 16)
                } catch {
                    await state.releaseSlot()
                    throw error
                }
                await state.releaseSlot()

                if shouldRetryStatus(response.status) && attempt < 2 {
                    try? await Task.sleep(nanoseconds: retryDelayNanos(attempt))
                    continue
                }
                if response.status >= 200 && response.status < 300 {
                    await state.store(key, response)
                }
                return response
            } catch {
                lastError = error
                if attempt == 2 || !isTransient(error) { break }
                try? await Task.sleep(nanoseconds: retryDelayNanos(attempt))
            }
        }
        throw TmdbNetworkException(friendlyError(lastError))
    }

    private func cacheKey(_ url: URL, _ credentials: ApiCredentials) -> String {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let filtered = comps?.queryItems?.filter { $0.name != "api_key" }
        comps?.queryItems = filtered
        let sanitized = comps?.url?.absoluteString ?? url.absoluteString
        return "\(credentials.tmdbToken.hashValue)|\(sanitized)"
    }

    private func shouldRetryStatus(_ status: Int) -> Bool {
        status == 408 || status == 429 || status >= 500
    }

    private func isTransient(_ error: Error?) -> Bool {
        guard let error else { return false }
        if let httpError = error as? Http.HttpError {
            switch httpError {
            case .status(let s, _): return shouldRetryStatus(s)
            case .transport: return true
            }
        }
        let text = "\(error)"
        return text.contains("timed out") || text.contains("SocketException")
            || text.contains("Connection reset") || text.contains("Failed host lookup")
            || text.contains("Network is unreachable") || text.contains("network connection was lost")
            || text.contains("offline")
    }

    private func retryDelayNanos(_ attempt: Int) -> UInt64 {
        (attempt == 0 ? 350 : 900) * 1_000_000
    }

    private func friendlyError(_ error: Error?) -> String {
        if let net = error as? TmdbNetworkException { return net.message }
        let text = "\(error.map { "\($0)" } ?? "")"
        if text.contains("401") || text.contains("403") {
            return "TMDB rejected the saved API key. Check Settings."
        }
        if text.contains("429") {
            return "TMDB rate-limited this refresh. Showing cached rows."
        }
        if isTransient(error) {
            return "TMDB is temporarily unreachable. Showing cached rows."
        }
        return "TMDB refresh failed. Showing cached rows."
    }

    private func statusMessage(_ status: Int) -> String {
        if status == 401 || status == 403 {
            return "TMDB rejected the saved API key. Check Settings."
        }
        if status == 429 {
            return "TMDB rate-limited this refresh. Showing cached rows."
        }
        return "TMDB returned \(status). Showing cached rows."
    }

    // MARK: Image selection

    private func imageLanguages(_ settings: UserSettings) -> String {
        let primary = settings.language.split(separator: "-").first.map(String.init)?.trimmed ?? ""
        var languages: [String] = []
        if !primary.isEmpty { languages.append(primary) }
        languages.append("en")
        languages.append("null")
        // dedupe preserving order
        var seen = Set<String>()
        return languages.filter { seen.insert($0).inserted }.joined(separator: ",")
    }

    private func bestImagePath(_ rawImages: Any?, fallback: String?, targetRatio: Double) -> String? {
        let images = (rawImages as? [Any] ?? [])
            .compactMap { $0 as? [String: Any] }
            .filter { $0["file_path"] is String }
        if images.isEmpty { return fallback }
        let sorted = images.sorted { imageScore($0, targetRatio) > imageScore($1, targetRatio) }
        return sorted.first?.str("file_path") ?? fallback
    }

    private func imageScore(_ image: [String: Any], _ targetRatio: Double) -> Double {
        let width = image.dbl("width") ?? 0
        let height = image.dbl("height") ?? 1
        let ratio = height == 0 ? 0 : width / height
        let ratioPenalty = abs(ratio - targetRatio) * 2.2
        let votes = image.dbl("vote_count") ?? 0
        let average = image.dbl("vote_average") ?? 0
        let language = image.str("iso_639_1")
        let languageBoost = (language == nil || language == "en") ? 2.0 : 0.0
        let resolutionBoost: Double = width >= 1920 ? 2.2 : (width >= 1280 ? 1.4 : 0.0)
        let clampedVotes = min(max(votes, 0), 20)
        return average + languageBoost + resolutionBoost + clampedVotes / 6 - ratioPenalty
    }

    // MARK: Credits / runtime / seasons

    private func castFrom(_ json: [String: Any]) -> [String] {
        let credits = json.obj("credits") ?? [:]
        return (credits.arr("cast") ?? [])
            .compactMap { $0 as? [String: Any] }
            .compactMap { $0.str("name") }
            .filter { !$0.isEmpty }
            .prefix(8)
            .map { $0 }
    }

    private func directorsFrom(_ json: [String: Any]) -> [String] {
        let createdBy = (json.arr("created_by") ?? [])
            .compactMap { $0 as? [String: Any] }
            .compactMap { $0.str("name") }
            .filter { !$0.isEmpty }
        let credits = json.obj("credits") ?? [:]
        let crew = (credits.arr("crew") ?? [])
            .compactMap { $0 as? [String: Any] }
            .filter { ($0.str("job")) == "Director" }
            .compactMap { $0.str("name") }
            .filter { !$0.isEmpty }
        var result: [String] = []
        var seen = Set<String>()
        for name in createdBy + crew where seen.insert(name).inserted {
            result.append(name)
        }
        return Array(result.prefix(6))
    }

    private func runtimeFrom(_ json: [String: Any], _ type: MediaType) -> Int? {
        if type == .movie { return json.int("runtime") }
        let runtimes = (json.arr("episode_run_time") ?? []).compactMap { value -> Int? in
            if let n = value as? Int { return n }
            if let n = value as? Double { return Int(n) }
            return nil
        }
        return runtimes.first
    }

    private func seasonsFrom(_ json: [String: Any]) -> [MediaSeason] {
        return (json.arr("seasons") ?? [])
            .compactMap { $0 as? [String: Any] }
            .map { season in
                MediaSeason(
                    seasonNumber: season.int("season_number") ?? 0,
                    name: season.str("name") ?? "Season",
                    episodeCount: season.int("episode_count") ?? 0
                )
            }
            .filter { $0.episodeCount > 0 }
    }
}

// MARK: - TmdbNetworkException

struct TmdbNetworkException: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

// MARK: - Demo categories (shown until TMDB credentials are saved)

private let demoPoster =
    "https://images.unsplash.com/photo-1489599849927-2ee91cede3ba?auto=format&fit=crop&w=600&q=80"

let demoCategories: [MediaCategory] = {
    let movieTitles = [
        "Midnight Signal", "The Glass Harbor", "Orbit Nine", "Northline",
        "Last Train Home", "Neon Season", "Drift Atlas", "The Quiet Frame",
    ]
    let seriesTitles = [
        "Signal Room", "Long Weekend", "The Ninth Map", "Harbor Watch",
        "After Meridian", "Low Orbit", "Public Square", "The Archive",
    ]
    let movies = (0..<8).map { index in
        MediaItem(
            id: "demo:movie:\(index)",
            type: .movie,
            title: movieTitles[index],
            overview: "Sample title shown until TMDB credentials are saved in Settings.",
            posterPath: demoPoster,
            rating: 7.2 + Double(index % 3) / 10,
            genres: ["Drama", "Adventure"]
        )
    }
    let series = (0..<8).map { index in
        MediaItem(
            id: "demo:series:\(index)",
            type: .series,
            title: seriesTitles[index],
            overview: "Sample show shown until TMDB credentials are saved in Settings.",
            posterPath: demoPoster,
            rating: 8.0 - Double(index % 4) / 10,
            genres: ["Mystery", "Sci-Fi"]
        )
    }
    return [
        MediaCategory(id: "demo_movies", title: "Movies", type: .movie, items: movies,
                      description: "Add your TMDB key to replace these samples with live data"),
        MediaCategory(id: "demo_series", title: "TV Shows", type: .series, items: series,
                      description: "Trending and airing rows appear after TMDB setup"),
    ]
}()
