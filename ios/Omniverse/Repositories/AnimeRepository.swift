import Foundation
import CryptoKit
import CommonCrypto

// Faithful Swift port of ../lib/src/repositories/anime_repository.dart.
//
// Routes anime through AniList (metadata) + AllManga / AllAnime (playback), the
// same path ani-cli uses. The AllAnime episode payload is AES-256-CTR encrypted
// ("tobeparsed") and source URLs are hex-encoded; both are decoded here with
// CryptoKit + CommonCrypto (no third-party crypto).

final class AnimeRepository: AnimeRepositoryProtocol {

    private let hianime: HianimeRepository

    init(hianime: HianimeRepository = HianimeRepository()) {
        self.hianime = hianime
    }

    private static let anilist = URL(string: "https://graphql.anilist.co")!
    private static let allanime = URL(string: "https://api.allanime.day/api")!

    private static let searchGql =
        "query($search:SearchInput $limit:Int $page:Int $translationType:VaildTranslationTypeEnumType $countryOrigin:VaildCountryOriginEnumType){shows(search:$search limit:$limit page:$page translationType:$translationType countryOrigin:$countryOrigin){edges{_id name availableEpisodes __typename}}}"
    private static let episodeGql =
        "query($showId:String! $translationType:VaildTranslationTypeEnumType! $episodeString:String!){episode(showId:$showId translationType:$translationType episodeString:$episodeString){episodeString sourceUrls}}"
    private static let episodeGqlHash =
        "d405d0edd690624b66baba3068e0edc3ac90f1597d898a1ec8db4e5c43c00fec"
    private static let providerPriority = [
        "S-mp4",
        "Luf-Mp4",
        "Yt-mp4",
        "Default",
        "Sl-Hls",
    ]

    private static let allanimeHeaders: [String: String] = [
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/121.0",
        "Referer": "https://allmanga.to",
        "Origin": "https://allmanga.to",
        "Accept": "*/*",
    ]

    private static let allmangaHeaders: [String: String] = [
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/121.0",
        "Referer": "https://allmanga.to",
        "Accept": "*/*",
    ]

    // MARK: - Supporting value types

    struct AnilistEpisodeMeta {
        let title: String
        let thumbnail: String?
    }

    private struct AnimeCategorySpec {
        let id: String
        let title: String
        let description: String
        let sort: [String]
        var format: String?
        var status: String?
        var season: String?
        var seasonYear: Int?
        var genre: String?
    }

    private struct CurrentSeason {
        let season: String
        let label: String
        let year: Int
    }

    private struct SeasonTitle {
        let title: String
        var romaji: String?
    }

    private struct AllAnimeSource {
        let sourceUrl: String
        var sourceName: String = ""
        var priority: Double = 0
        var path: String = ""
    }

    private struct ResolvedAnimeSource {
        let url: String
        let resolution: String
        let sourceName: String
        let referer: String
    }

    enum AnimeError: Error, CustomStringConvertible {
        case noSource(String)
        case status(String)
        var description: String {
            switch self {
            case .noSource(let t): return "No playable anime source found for \(t)."
            case .status(let m): return m
            }
        }
    }

    // MARK: - fetchAnimeCategories

    func fetchAnimeCategories() async throws -> [MediaCategory] {
        let season = currentAnilistSeason()
        // AniList rate-limits us to 30 requests per minute. Firing one query per
        // category (10 calls in parallel) trips the burst limiter and silently
        // returns `media: []` for most of them. Consolidate everything into one
        // GraphQL request with aliases — one round-trip, one rate-limit slot.
        let categories: [AnimeCategorySpec] = [
            AnimeCategorySpec(
                id: "anime_trending",
                title: "Trending Now",
                description: "What everyone is watching right now",
                sort: ["TRENDING_DESC"]
            ),
            AnimeCategorySpec(
                id: "anime_airing",
                title: "Currently Airing",
                description: "New episodes still landing each week",
                sort: ["POPULARITY_DESC"],
                status: "RELEASING"
            ),
            AnimeCategorySpec(
                id: "anime_this_season",
                title: "\(season.label) \(season.year)",
                description: "Highest-buzz shows this season",
                sort: ["POPULARITY_DESC"],
                season: season.season,
                seasonYear: season.year
            ),
            AnimeCategorySpec(
                id: "anime_top_rated",
                title: "All-Time Top Rated",
                description: "Highest scores on AniList",
                sort: ["SCORE_DESC"]
            ),
            AnimeCategorySpec(
                id: "anime_popular",
                title: "All-Time Popular",
                description: "Most-watched anime ever",
                sort: ["POPULARITY_DESC"]
            ),
            AnimeCategorySpec(
                id: "anime_recent",
                title: "Recently Added",
                description: "Newest additions to AniList",
                sort: ["ID_DESC"]
            ),
            AnimeCategorySpec(
                id: "anime_movies",
                title: "Anime Movies",
                description: "Movie-format anime",
                sort: ["SCORE_DESC"],
                format: "MOVIE"
            ),
            AnimeCategorySpec(
                id: "anime_action",
                title: "Action",
                description: "High-octane action picks",
                sort: ["POPULARITY_DESC"],
                genre: "Action"
            ),
            AnimeCategorySpec(
                id: "anime_romance",
                title: "Romance",
                description: "Love stories and slice-of-life",
                sort: ["POPULARITY_DESC"],
                genre: "Romance"
            ),
            AnimeCategorySpec(
                id: "anime_fantasy",
                title: "Fantasy",
                description: "Magic, isekai, and worlds elsewhere",
                sort: ["POPULARITY_DESC"],
                genre: "Fantasy"
            ),
        ]

        var aliasBlocks = ""
        for (i, c) in categories.enumerated() {
            var args: [String] = [
                "type: ANIME",
                "sort: \(gqlEnumList(c.sort))",
            ]
            if let format = c.format { args.append("format: \(format)") }
            if let status = c.status { args.append("status: \(status)") }
            if let s = c.season { args.append("season: \(s)") }
            if let sy = c.seasonYear { args.append("seasonYear: \(sy)") }
            if let genre = c.genre { args.append("genre: \"\(genre)\"") }
            args.append("isAdult: false")
            aliasBlocks += "  r\(i): Page(page: 1, perPage: 24) { media(\(args.joined(separator: ", "))) { ...animeFields } }\n"
        }

        let query = """
        fragment animeFields on Media {
          id
          title { romaji english native }
          description(asHtml: false)
          coverImage { extraLarge large }
          bannerImage
          genres
          averageScore
          episodes
          duration
          format
          seasonYear
          startDate { year month day }
          studios(isMain: true) { nodes { name } }
        }
        query {
        \(aliasBlocks)
        }
        """

        do {
            let body = try await postJson(Self.anilist, ["query": query])
            let data = body.obj("data") ?? [:]
            return categories.enumerated().map { (i, c) in
                let media = (data.obj("r\(i)"))?.arr("media")
                let items: [MediaItem]
                if let media {
                    items = media.compactMap { $0 as? [String: Any] }.map(mediaFromAnilist)
                } else {
                    items = []
                }
                return MediaCategory(
                    id: c.id,
                    title: c.title,
                    type: .anime,
                    items: items,
                    description: c.description,
                    error: items.isEmpty ? "No results from AniList" : nil
                )
            }
        } catch {
            return categories.map { c in
                MediaCategory(
                    id: c.id,
                    title: c.title,
                    type: .anime,
                    items: [],
                    description: c.description,
                    error: "Anime row could not load: \(error)"
                )
            }
        }
    }

    private func gqlEnumList(_ values: [String]) -> String {
        "[\(values.joined(separator: ", "))]"
    }

    // MARK: - recommendations

    /// AniList "you might also like" recommendations for an anime, used by the
    /// end-of-show recommendation rail when there are no more episodes/seasons.
    func recommendations(anilistId: Int) async -> [MediaItem] {
        let query = """
        query ($id: Int) {
          Media(id: $id, type: ANIME) {
            recommendations(sort: RATING_DESC, perPage: 24) {
              nodes {
                mediaRecommendation {
                  id
                  title { romaji english native }
                  description(asHtml: false)
                  coverImage { extraLarge large }
                  bannerImage
                  genres
                  averageScore
                  episodes
                  duration
                  format
                  seasonYear
                  startDate { year month day }
                  studios(isMain: true) { nodes { name } }
                }
              }
            }
          }
        }
        """
        do {
            let body = try await postJson(Self.anilist, ["query": query, "variables": ["id": anilistId]])
            let nodes = body.obj("data")?.obj("Media")?.obj("recommendations")?.arr("nodes") ?? []
            return nodes
                .compactMap { $0 as? [String: Any] }
                .compactMap { $0.obj("mediaRecommendation") }
                .map(mediaFromAnilist)
                .filter { $0.posterPath != nil || $0.backdropPath != nil }
        } catch {
            return []
        }
    }

    /// Maps the current calendar month to AniList's MediaSeason enum + year.
    private func currentAnilistSeason() -> CurrentSeason {
        let now = Date()
        let cal = Calendar.current
        let m = cal.component(.month, from: now)
        let year = cal.component(.year, from: now)
        let season: String
        switch m {
        case 1, 2, 3: season = "WINTER"
        case 4, 5, 6: season = "SPRING"
        case 7, 8, 9: season = "SUMMER"
        default: season = "FALL"
        }
        let label = String(season.prefix(1)) + season.dropFirst().lowercased()
        return CurrentSeason(season: season, label: label, year: year)
    }

    // MARK: - findByTitle

    /// Searches AniList by title and returns the best anime match as an
    /// AniList-sourced MediaItem, so a TMDB show flagged as anime can be
    /// re-routed through the AllManga playback path. Returns `nil` if no match
    /// is found or the request fails.
    func findByTitle(_ title: String) async -> MediaItem? {
        let query = title.trimmed
        if query.isEmpty { return nil }
        let gql = """
        query($search: String) {
          Page(page: 1, perPage: 5) {
            media(type: ANIME, search: $search, sort: [SEARCH_MATCH, POPULARITY_DESC], isAdult: false) {
              id
              title { romaji english native }
              description(asHtml: false)
              coverImage { extraLarge large }
              bannerImage
              genres
              averageScore
              episodes
              duration
              format
              seasonYear
              startDate { year month day }
              studios(isMain: true) { nodes { name } }
            }
          }
        }
        """
        do {
            let body = try await postJson(Self.anilist, [
                "query": gql,
                "variables": ["search": query],
            ])
            guard let media = (body.obj("data")?.obj("Page"))?.arr("media"),
                  !media.isEmpty,
                  let first = media.first(where: { $0 is [String: Any] }) as? [String: Any] else {
                return nil
            }
            return mediaFromAnilist(first)
        } catch {
            return nil
        }
    }

    // MARK: - fetchEpisodes

    func fetchEpisodes(_ item: MediaItem, seasonNumber: Int) async -> [MediaEpisode] {
        let season = item.seasons.first { $0.seasonNumber == seasonNumber }
        // Movie-format anime: just one entry.
        if season?.episodeCount == 1 {
            return [MediaEpisode(seasonNumber: 1, episodeNumber: 1, title: "Movie")]
        }

        // Resolve the right title for this season (sequels are separate AniList
        // entries with their own episode counts on AllAnime).
        let seasonTitle = await anilistSeasonTitle(item.title, seasonNumber: seasonNumber)
        let searchTitle = seasonTitle.title

        // Pull the actual available episode count from AllAnime — AniList's
        // `episodes` field is the planned total, which is wrong for airing shows
        // and split-season releases. Fall back to AniList's count if AllAnime
        // doesn't know the show yet.
        let liveCount = await allmangaEpisodeCount(searchTitle)
        let plannedCount = season?.episodeCount ?? item.episodes.count
        let count = liveCount ?? plannedCount
        if count <= 0 { return [] }

        // Look up real per-episode titles + thumbnails from AniList's
        // streamingEpisodes when present.
        let meta = await anilistEpisodeMeta(searchTitle)

        var episodes: [MediaEpisode] = []
        for ep in 1...count {
            episodes.append(MediaEpisode(
                seasonNumber: seasonNumber,
                episodeNumber: ep,
                title: meta[ep]?.title ?? "Episode \(ep)",
                stillPath: meta[ep]?.thumbnail
            ))
        }
        return episodes
    }

    private func allmangaEpisodeCount(_ title: String) async -> Int? {
        do {
            guard let edges = try await searchAllmanga(title, translationType: "sub"), !edges.isEmpty else {
                return nil
            }
            let lower = title.lowercased().trimmed
            let entry = edges.first { ($0.str("name")?.lowercased().trimmed ?? "") == lower } ?? edges.first!
            guard let available = entry.obj("availableEpisodes") else { return nil }
            let sub = available.int("sub") ?? 0
            let dub = available.int("dub") ?? 0
            let raw = available.int("raw") ?? 0
            let maxVal = [sub, dub, raw].reduce(0) { max($0, $1) }
            return maxVal == 0 ? nil : maxVal
        } catch {
            return nil
        }
    }

    func anilistEpisodeMeta(_ title: String) async -> [Int: AnilistEpisodeMeta] {
        let gql = """
        query($search: String) {
          Media(type: ANIME, search: $search, sort: SEARCH_MATCH) {
            streamingEpisodes { title thumbnail }
          }
        }
        """
        do {
            let body = try await postJson(Self.anilist, [
                "query": gql,
                "variables": ["search": title],
            ])
            guard let eps = (body.obj("data")?.obj("Media"))?.arr("streamingEpisodes") else {
                return [:]
            }
            var out: [Int: AnilistEpisodeMeta] = [:]
            // streamingEpisodes are normally returned in order. Common title shapes:
            // "Episode 1 - To You, In 2000 Years", "1 - Origins", just "Origins".
            let pattern = #"^(?:Episode\s+)?(\d+)\s*[-:.|]\s*(.+)$"#
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            for (i, entryAny) in eps.enumerated() {
                guard let entry = entryAny as? [String: Any] else { continue }
                let raw = (entry.str("title") ?? "").trimmed
                let thumb = entry.str("thumbnail")?.trimmed
                let thumbValue = (thumb == nil || thumb!.isEmpty) ? nil : thumb
                var number = i + 1
                var titleText = raw
                if let regex {
                    let ns = raw as NSString
                    if let m = regex.firstMatch(in: raw, options: [], range: NSRange(location: 0, length: ns.length)), m.numberOfRanges >= 3 {
                        let n = Int(ns.substring(with: m.range(at: 1)))
                        let t = ns.substring(with: m.range(at: 2)).trimmed
                        if let n, !t.isEmpty {
                            number = n
                            titleText = t
                        }
                    }
                }
                out[number] = AnilistEpisodeMeta(title: titleText, thumbnail: thumbValue)
            }
            return out
        } catch {
            return [:]
        }
    }

    // MARK: - resolveSource

    func resolveSource(item: MediaItem, episode: MediaEpisode, settings: UserSettings) async throws -> PlaybackSource {
        let dub = settings.preferDubbedAnime
        let translationType = dub ? "dub" : "sub"
        let isMovie = item.seasons.first?.episodeCount == 1 && episode.episodeNumber == 1

        // AllAnime — primary path. Same path ani-cli uses.
        var result = await resolveAllmanga(
            title: item.title,
            seasonNumber: episode.seasonNumber,
            episodeNumber: episode.episodeNumber,
            isMovie: isMovie,
            translationType: translationType
        )
        if result == nil && translationType == "dub" {
            result = await resolveAllmanga(
                title: item.title,
                seasonNumber: episode.seasonNumber,
                episodeNumber: episode.episodeNumber,
                isMovie: isMovie,
                translationType: "sub"
            )
        }
        guard let result else {
            throw AnimeError.noSource(item.title)
        }
        return PlaybackSource(
            id: "allmanga:\(item.id):\(episode.seasonNumber):\(episode.episodeNumber)",
            title: "\(result.sourceName) \(result.resolution)".trimmed,
            url: result.url,
            provider: "AllManga",
            kind: .direct,
            quality: result.resolution,
            headers: ["Referer": result.referer],
            subtitleUrl: settings.subtitleUrl.trimmed
        )
    }

    // MARK: - mediaFromAnilist

    private func mediaFromAnilist(_ json: [String: Any]) -> MediaItem {
        let id = json.int("id") ?? 0
        let titleJson = json.obj("title") ?? [:]
        let title = titleJson.str("english")
            ?? titleJson.str("romaji")
            ?? titleJson.str("native")
            ?? "Anime"
        let episodes = json.int("episodes")
            ?? ((json.str("format") == "MOVIE") ? 1 : 0)
        let year = json.int("seasonYear")
            ?? json.obj("startDate")?.int("year")
        let studios = (json.obj("studios")?.arr("nodes") ?? [])
            .compactMap { $0 as? [String: Any] }
            .compactMap { $0.str("name") }
            .filter { !$0.isEmpty }
            .prefix(3)
        let format = json.str("format")
        return MediaItem(
            id: "anilist:anime:\(id)",
            type: .anime,
            title: title,
            overview: cleanDescription(json.str("description") ?? ""),
            posterPath: json.obj("coverImage")?.str("extraLarge")
                ?? json.obj("coverImage")?.str("large"),
            backdropPath: json.str("bannerImage"),
            releaseDate: year.map(String.init) ?? "",
            rating: ((json.dbl("averageScore") ?? 0) / 10),
            genres: json.strArray("genres"),
            directors: Array(studios),
            runtimeMinutes: json.int("duration"),
            seasons: [
                MediaSeason(
                    seasonNumber: 1,
                    name: format == "MOVIE" ? "Movie" : "Season 1",
                    episodeCount: episodes
                ),
            ],
            source: "anilist"
        )
    }

    // MARK: - AllManga resolution

    private func resolveAllmanga(title: String, seasonNumber: Int, episodeNumber: Int, isMovie: Bool, translationType: String) async -> ResolvedAnimeSource? {
        let dubSub = translationType == "dub" ? "dub" : "sub"
        let seasonTitle = isMovie
            ? SeasonTitle(title: title)
            : await anilistSeasonTitle(title, seasonNumber: seasonNumber)
        let epStr = isMovie ? "1" : String(episodeNumber)

        // Ordered, de-duplicated candidate list (Swift Set is unordered, so we
        // build an ordered array honouring the Dart literal-set order while
        // dropping repeats and blanks).
        var seen = Set<String>()
        var candidates: [String] = []
        func addCandidate(_ value: String) {
            let v = value
            if v.trimmed.isEmpty { return }
            if seen.contains(v) { return }
            seen.insert(v)
            candidates.append(v)
        }
        addCandidate(seasonTitle.title)
        addCandidate(sanitizeTitle(seasonTitle.title))
        if let romaji = seasonTitle.romaji { addCandidate(romaji) }
        addCandidate(title)
        addCandidate(sanitizeTitle(title))

        var edges: [[String: Any]]?
        var matchedTitle = seasonTitle.title
        for candidate in candidates {
            edges = try? await searchAllmanga(candidate, translationType: dubSub)
            if let e = edges, !e.isEmpty {
                matchedTitle = candidate
                break
            }
        }
        guard let resolvedEdges = edges, !resolvedEdges.isEmpty else { return nil }

        let normalized = matchedTitle.lowercased()
        let anime = resolvedEdges.first { ($0.str("name")?.lowercased() ?? "") == normalized } ?? resolvedEdges.first!
        guard let showId = anime.str("_id") ?? (anime["_id"].map { "\($0)" }), !showId.isEmpty else { return nil }

        guard let sourceUrls = await episodeSourceUrls(showId: showId, translationType: dubSub, episodeString: epStr),
              !sourceUrls.isEmpty else {
            return nil
        }
        return await trySourceUrls(sourceUrls)
    }

    private func anilistSeasonTitle(_ baseTitle: String, seasonNumber: Int) async -> SeasonTitle {
        if seasonNumber <= 1 { return SeasonTitle(title: baseTitle) }
        let query = """
        query($search:String) {
          Media(search: $search, type: ANIME, sort: SEARCH_MATCH) {
            title { english romaji }
            relations {
              edges {
                relationType
                node {
                  type
                  format
                  title { english romaji }
                  startDate { year }
                  seasonYear
                }
              }
            }
          }
        }
        """
        do {
            let body = try await postJson(Self.anilist, [
                "query": query,
                "variables": ["search": baseTitle],
            ])
            guard let media = body.obj("data")?.obj("Media") else { return SeasonTitle(title: baseTitle) }
            let relations = media.obj("relations")?.arr("edges") ?? []
            var sequels = relations.compactMap { $0 as? [String: Any] }.filter { edge in
                let node = edge.obj("node") ?? [:]
                return (edge["relationType"] as? String) == "SEQUEL"
                    && (node["type"] as? String) == "ANIME"
                    && ((node["format"] as? String) == "TV" || (node["format"] as? String) == "TV_SHORT")
            }
            sequels.sort { a, b in
                let aNode = a.obj("node") ?? [:]
                let bNode = b.obj("node") ?? [:]
                let aYear = aNode.obj("startDate")?.int("year") ?? aNode.int("seasonYear") ?? 9999
                let bYear = bNode.obj("startDate")?.int("year") ?? bNode.int("seasonYear") ?? 9999
                return aYear < bYear
            }
            let targetIndex = seasonNumber - 2
            guard targetIndex >= 0, targetIndex < sequels.count else { return SeasonTitle(title: baseTitle) }
            let node = sequels[targetIndex].obj("node")
            let title = node?.obj("title")
            return SeasonTitle(
                title: title?.str("english") ?? title?.str("romaji") ?? baseTitle,
                romaji: title?.str("romaji")
            )
        } catch {
            return SeasonTitle(title: baseTitle)
        }
    }

    private func searchAllmanga(_ query: String, translationType: String) async throws -> [[String: Any]]? {
        let body = try await allanimeGql([
            "search": [
                "allowAdult": false,
                "allowUnknown": false,
                "query": query.lowercased(),
            ],
            "limit": 40,
            "page": 1,
            "translationType": translationType,
            "countryOrigin": "ALL",
        ], query: Self.searchGql)
        guard let edges = (body.obj("data")?.obj("shows"))?.arr("edges") else { return nil }
        return edges.compactMap { $0 as? [String: Any] }
    }

    private func episodeSourceUrls(showId: String, translationType: String, episodeString: String) async -> [AllAnimeSource]? {
        var candidates = [episodeString]
        if !episodeString.contains(".") { candidates.append("\(episodeString).0") }
        for candidate in candidates {
            let body = await allanimeEpisodeGql([
                "showId": showId,
                "translationType": translationType,
                "episodeString": candidate,
            ])
            if let sources = parseEpisodeSourceUrls(body), !sources.isEmpty {
                return sources
            }
        }
        return nil
    }

    private func allanimeGql(_ variables: [String: Any], query: String) async throws -> [String: Any] {
        try await postJson(Self.allanime, [
            "variables": variables,
            "query": query,
        ], headers: Self.allanimeHeaders)
    }

    private func allanimeEpisodeGql(_ variables: [String: Any]) async -> String {
        // GET path with persisted-query extensions first.
        if let varsData = try? JSONSerialization.data(withJSONObject: variables),
           let varsStr = String(data: varsData, encoding: .utf8) {
            let extensions = "{\"persistedQuery\":{\"version\":1,\"sha256Hash\":\"\(Self.episodeGqlHash)\"}}"
            var comps = URLComponents(url: Self.allanime, resolvingAgainstBaseURL: false)
            comps?.queryItems = [
                URLQueryItem(name: "variables", value: varsStr),
                URLQueryItem(name: "extensions", value: extensions),
            ]
            if let url = comps?.url {
                var headers = Self.allanimeHeaders
                headers["Origin"] = "https://youtu-chan.com"
                if let resp = try? await Http.shared.request(url, headers: headers, timeout: 12) {
                    let body = resp.bodyString
                    if let parsed = parseEpisodeSourceUrls(body), !parsed.isEmpty {
                        return body
                    }
                }
            }
        }
        // Fall back to the normal POST shape.
        if let body = try? await allanimeGql(variables, query: Self.episodeGql),
           let data = try? JSONSerialization.data(withJSONObject: body),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return ""
    }

    private func parseEpisodeSourceUrls(_ body: String) -> [AllAnimeSource]? {
        // First: the encrypted "tobeparsed" blob.
        if let encrypted = firstCapture(in: body, pattern: #""tobeparsed"\s*:\s*"([^"]+)""#) {
            let sources = decodeTobeparsed(encrypted)
            if !sources.isEmpty { return sources }
        }
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sourceUrls = (json.obj("data")?.obj("episode"))?.arr("sourceUrls") else {
            return nil
        }
        return sourceUrls.compactMap { $0 as? [String: Any] }.map { j in
            AllAnimeSource(
                sourceUrl: j.str("sourceUrl") ?? "",
                sourceName: j.str("sourceName") ?? "",
                priority: j.dbl("priority") ?? 0
            )
        }
    }

    // MARK: - tobeparsed decode (AES-256-CTR)

    private func decodeTobeparsed(_ blob: String) -> [AllAnimeSource] {
        guard let data = Data(base64Encoded: blob) else { return [] }
        let bytes = [UInt8](data)
        if bytes.count <= 29 { return [] }
        // key = SHA256(utf8("Xot36i3lK3:v1"))
        let key = Array(SHA256.hash(data: Data("Xot36i3lK3:v1".utf8)))
        // iv = bytes[1..<13] + [0,0,0,2]
        var iv = Array(bytes[1..<13])
        iv.append(contentsOf: [0, 0, 0, 2])
        let ciphertext = Array(bytes[13..<(bytes.count - 16)])
        guard let plainBytes = aesCTRDecrypt(ciphertext: ciphertext, key: key, iv: iv) else { return [] }
        let plain = String(decoding: plainBytes, as: UTF8.self) // lossy UTF-8

        var sources: [AllAnimeSource] = []
        // Split on regex [{}].
        let chunks = plain.components(separatedBy: CharacterSet(charactersIn: "{}"))
        for chunk in chunks {
            guard let url = firstCapture(in: chunk, pattern: #""sourceUrl"\s*:\s*"(--[^"]+)""#) else { continue }
            let name = firstCapture(in: chunk, pattern: #""sourceName"\s*:\s*"([^"]+)""#) ?? ""
            let priorityStr = firstCapture(in: chunk, pattern: #""priority"\s*:\s*([0-9.]+)"#) ?? ""
            sources.append(AllAnimeSource(
                sourceUrl: url,
                sourceName: name,
                priority: Double(priorityStr) ?? 0
            ))
        }
        return sources
    }

    private func aesCTRDecrypt(ciphertext: [UInt8], key: [UInt8], iv: [UInt8]) -> [UInt8]? {
        var cryptorRef: CCCryptorRef?
        let createStatus = key.withUnsafeBytes { keyPtr in
            iv.withUnsafeBytes { ivPtr in
                CCCryptorCreateWithMode(
                    CCOperation(kCCDecrypt),
                    CCMode(kCCModeCTR),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCPadding(ccNoPadding),
                    ivPtr.baseAddress,
                    keyPtr.baseAddress, key.count,
                    nil, 0, 0,
                    CCModeOptions(kCCModeOptionCTR_BE),
                    &cryptorRef
                )
            }
        }
        guard createStatus == kCCSuccess, let cryptor = cryptorRef else { return nil }
        defer { CCCryptorRelease(cryptor) }

        let outLen = CCCryptorGetOutputLength(cryptor, ciphertext.count, true)
        var output = [UInt8](repeating: 0, count: max(outLen, ciphertext.count))
        var moved = 0
        let updateStatus = ciphertext.withUnsafeBytes { dataPtr in
            CCCryptorUpdate(
                cryptor,
                dataPtr.baseAddress, ciphertext.count,
                &output, output.count,
                &moved
            )
        }
        guard updateStatus == kCCSuccess else { return nil }
        var total = moved
        var finalMoved = 0
        let tailCapacity = output.count - total
        let finalStatus = output[total...].withUnsafeMutableBytes { tailPtr in
            CCCryptorFinal(cryptor, tailPtr.baseAddress, tailCapacity, &finalMoved)
        }
        guard finalStatus == kCCSuccess else { return nil }
        total += finalMoved
        return Array(output[0..<total])
    }

    // MARK: - trySourceUrls

    private func trySourceUrls(_ sourceUrls: [AllAnimeSource]) async -> ResolvedAnimeSource? {
        var decoded = sourceUrls
            .filter { !$0.sourceUrl.isEmpty }
            .map { source -> AllAnimeSource in
                let path: String
                if source.sourceUrl.hasPrefix("--") {
                    path = decodeAllanimeUrl(source.sourceUrl).replacingOccurrences(of: "/clock", with: "/clock.json")
                } else {
                    path = source.sourceUrl
                }
                var copy = source
                copy.path = path
                return copy
            }
        decoded.sort { a, b in
            let aIndex = Self.providerPriority.firstIndex(of: a.sourceName) ?? -1
            let bIndex = Self.providerPriority.firstIndex(of: b.sourceName) ?? -1
            let aRank = aIndex == -1 ? 99 : aIndex
            let bRank = bIndex == -1 ? 99 : bIndex
            return aRank < bRank
        }

        for source in decoded {
            guard let fetchUrl = normalizeAllanimeUrl(source.path) else { continue }
            if fetchUrl.contains("fast4speed.rsvp") || source.sourceName == "Yt-mp4" {
                let finalUrl = await followRedirects(fetchUrl)
                if isDirectVideoUrl(finalUrl) && !isYoutubeUrl(finalUrl) {
                    return ResolvedAnimeSource(
                        url: finalUrl,
                        resolution: "?",
                        sourceName: source.sourceName,
                        referer: "https://allmanga.to"
                    )
                }
                continue
            }

            guard let url = URL(string: fetchUrl),
                  let response = try? await Http.shared.request(url, headers: Self.allmangaHeaders, timeout: 12),
                  response.status == 200, !response.data.isEmpty else {
                continue
            }
            guard let json = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any],
                  let links = json.arr("links") else {
                continue
            }
            let playable = links.compactMap { $0 as? [String: Any] }.filter { $0["link"] is String }
            if playable.isEmpty { continue }
            let mp4Links = playable.filter { link in
                let u = (link["link"] as! String).lowercased()
                return !u.contains(".m3u8") && !u.contains("master.")
            }
            var chosen = mp4Links.isEmpty ? playable : mp4Links
            chosen.sort { a, b in
                resolution(a["resolutionStr"]) > resolution(b["resolutionStr"])
            }
            guard let best = chosen.first, let bestUrl = best["link"] as? String else { continue }
            if !isDirectVideoUrl(bestUrl) { continue }
            return ResolvedAnimeSource(
                url: bestUrl,
                resolution: (best["resolutionStr"].map { "\($0)" }) ?? "?",
                sourceName: source.sourceName,
                referer: "https://allmanga.to"
            )
        }
        return nil
    }

    private func followRedirects(_ value: String, maxHops: Int = 10) async -> String {
        guard var uri = URL(string: value) else { return value }
        for _ in 0..<maxHops {
            guard let resp = try? await Http.shared.request(uri, method: "HEAD", headers: Self.allmangaHeaders, timeout: 10, followRedirects: false) else {
                return uri.absoluteString
            }
            // Http.shared collapses redirects unless followRedirects is honoured at the
            // session layer; we read the Location header from the response when present.
            // Since the shared Response only exposes status/data, we cannot read headers
            // here — so a 3xx with no body terminates the loop on the current URL.
            if resp.status >= 300 && resp.status < 400 {
                // No header access available; stop walking and return current URL.
                return uri.absoluteString
            }
            return uri.absoluteString
        }
        return uri.absoluteString
    }

    // MARK: - URL / text helpers

    private func postJson(_ uri: URL, _ body: [String: Any], headers: [String: String] = [:]) async throws -> [String: Any] {
        var h = headers
        h["Content-Type"] = "application/json"
        h["Accept"] = "application/json"
        let data = try JSONSerialization.data(withJSONObject: body)
        let resp = try await Http.shared.request(uri, method: "POST", headers: h, body: data, timeout: 14)
        if resp.status >= 400 {
            throw AnimeError.status("\(uri.host ?? "") returned \(resp.status)")
        }
        return resp.jsonObject()
    }

    private func normalizeAllanimeUrl(_ value: String) -> String? {
        if value.hasPrefix("//") { return "https:\(value)" }
        if value.hasPrefix("/") { return "https://allanime.day\(value)" }
        if value.hasPrefix("http") { return value }
        if !value.isEmpty { return "https://allanime.day/\(value)" }
        return nil
    }

    private func isDirectVideoUrl(_ value: String) -> Bool {
        let lower = value.lowercased()
        if lower.contains("googlevideo.com") { return true }
        return lower.range(of: #"\.(mp4|webm|m4v|mov|m3u8)(\?|$)"#, options: .regularExpression) != nil
    }

    private func isYoutubeUrl(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.contains("youtube.com/watch") || lower.contains("youtu.be/")
    }

    private func resolution(_ value: Any?) -> Int {
        let text = value.map { "\($0)" } ?? ""
        guard let r = text.range(of: #"\d+"#, options: .regularExpression) else { return 0 }
        return Int(text[r]) ?? 0
    }

    private func sanitizeTitle(_ value: String) -> String {
        var v = value
        v = v.replacingOccurrences(of: #"[''`´]"#, with: "", options: .regularExpression)
        v = v.replacingOccurrences(of: #"[:!.]"#, with: "", options: .regularExpression)
        v = v.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return v.trimmed
    }

    private func cleanDescription(_ value: String) -> String {
        var v = value
        v = v.replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
        v = v.replacingOccurrences(of: #"\(Source:[^)]*\)"#, with: "", options: [.regularExpression, .caseInsensitive])
        v = v.replacingOccurrences(of: #"\bNote:[^\n]*"#, with: "", options: [.regularExpression, .caseInsensitive])
        return v.trimmed
    }

    // MARK: - AllAnime hex URL decode

    private func decodeAllanimeUrl(_ encoded: String) -> String {
        var value = encoded.hasPrefix("--") ? String(encoded.dropFirst(2)) : encoded
        var buffer = ""
        let chars = Array(value)
        var index = 0
        while index < chars.count {
            let end = min(index + 2, chars.count)
            let pair = String(chars[index..<end])
            buffer += Self.allanimeHexMap[pair] ?? pair
            index += 2
        }
        value = buffer
        // replace "/" -> "/" and remove literal "\|"
        value = value.replacingOccurrences(of: #"/"#, with: "/")
        value = value.replacingOccurrences(of: #"\|"#, with: "")
        return value
    }

    // MARK: - updateAniListProgress

    func updateAniListProgress(accessToken: String, mediaId: Int, progress: Int, status: String) async throws {
        let mutation = """
              mutation ($mediaId: Int, $progress: Int, $status: MediaListStatus) {
                SaveMediaListEntry (mediaId: $mediaId, progress: $progress, status: $status) {
                  id
                  progress
                  status
                }
              }
        """
        let bodyDict: [String: Any] = [
            "query": mutation,
            "variables": [
                "mediaId": mediaId,
                "progress": progress,
                "status": status,
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: bodyDict)
        let resp = try await Http.shared.request(
            Self.anilist,
            method: "POST",
            headers: [
                "Authorization": "Bearer \(accessToken)",
                "Content-Type": "application/json",
                "Accept": "application/json",
            ],
            body: data
        )
        if resp.status >= 400 {
            throw AnimeError.status("AniList progress update returned \(resp.status): \(resp.bodyString)")
        }
    }

    // MARK: - AllAnime hex map (copied verbatim from anime_repository.dart)

    private static let allanimeHexMap: [String: String] = [
        "79": "A", "7a": "B", "7b": "C", "7c": "D", "7d": "E", "7e": "F", "7f": "G",
        "70": "H", "71": "I", "72": "J", "73": "K", "74": "L", "75": "M", "76": "N",
        "77": "O", "68": "P", "69": "Q", "6a": "R", "6b": "S", "6c": "T", "6d": "U",
        "6e": "V", "6f": "W", "60": "X", "61": "Y", "62": "Z", "59": "a", "5a": "b",
        "5b": "c", "5c": "d", "5d": "e", "5e": "f", "5f": "g", "50": "h", "51": "i",
        "52": "j", "53": "k", "54": "l", "55": "m", "56": "n", "57": "o", "48": "p",
        "49": "q", "4a": "r", "4b": "s", "4c": "t", "4d": "u", "4e": "v", "4f": "w",
        "40": "x", "41": "y", "42": "z", "08": "0", "09": "1", "0a": "2", "0b": "3",
        "0c": "4", "0d": "5", "0e": "6", "0f": "7", "00": "8", "01": "9", "15": "-",
        "16": ".", "67": "_", "46": "~", "02": ":", "17": "/", "07": "?", "1b": "#",
        "63": "[", "65": "]", "78": "@", "19": "!", "1c": "$", "1e": "&", "10": "(",
        "11": ")", "12": "*", "13": "+", "14": ",", "03": ";", "05": "=", "1d": "%",
    ]

    // MARK: - Regex helper

    private func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 2 else {
            return nil
        }
        return ns.substring(with: m.range(at: 1))
    }
}
