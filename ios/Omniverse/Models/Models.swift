import Foundation

// MARK: - MediaType

enum MediaType: String, Codable, CaseIterable {
    case movie, series, anime, liveTv

    var label: String {
        switch self {
        case .movie: return "Movie"
        case .series: return "TV Show"
        case .anime: return "Anime"
        case .liveTv: return "Live TV"
        }
    }

    /// TMDB path segment: movies use `movie`, everything else uses `tv`.
    var tmdbPath: String { self == .movie ? "movie" : "tv" }
}

// MARK: - Image URL resolution (ported from models.dart `_imageUrl`)

func imageUrl(_ path: String?, size: String) -> String? {
    guard let path, !path.isEmpty else { return nil }
    if path.hasPrefix("http") { return path }
    if path.hasPrefix("//") { return "https:\(path)" }
    if path.hasPrefix("/_next/") || path.hasPrefix("_next/") {
        let clean = path.hasPrefix("/") ? path : "/\(path)"
        return "https://onepace.net\(clean)"
    }
    if path.hasPrefix("banners/") || path.hasPrefix("/banners/") {
        let clean = path.hasPrefix("/") ? path : "/\(path)"
        return "https://artworks.thetvdb.com\(clean)"
    }
    return "https://image.tmdb.org/t/p/\(size)\(path)"
}

// MARK: - ApiCredentials

struct ApiCredentials: Codable, Equatable {
    var tmdbToken = ""
    var tvdbApiKey = ""
    var tvdbPin = ""
    var traktClientId = ""
    var traktClientSecret = ""
    var traktAccessToken = ""
    var traktRefreshToken = ""
    var traktTokenExpiresAt = 0          // epoch milliseconds
    var traktUsername = ""
    var pixeldrainApiKey = ""
    var anilistAccessToken = ""

    var hasTmdb: Bool { !tmdbToken.trimmed.isEmpty }
    var hasTvdb: Bool { !tvdbApiKey.trimmed.isEmpty }
    var hasTraktApp: Bool { !traktClientId.trimmed.isEmpty }
    var hasTraktUser: Bool { !traktAccessToken.trimmed.isEmpty }
    var hasPixeldrain: Bool { !pixeldrainApiKey.trimmed.isEmpty }
    var hasAnilist: Bool { !anilistAccessToken.trimmed.isEmpty }
    var canRefreshTrakt: Bool { !traktRefreshToken.trimmed.isEmpty && !traktClientSecret.trimmed.isEmpty }
}

// MARK: - UserSettings

struct UserSettings: Codable, Equatable {
    var language = "en-US"
    var region = "US"
    var includeAdult = false
    var tvMode = false
    var vidsrcDomain = "vidsrc-embed.ru"
    var subtitleUrl = ""
    var subtitleLanguage = "en"
    var preferDubbedAnime = false
    var liveTvCountry = "IN"
    var showMoviesTv = true
    var showAnime = true
    var showLiveTv = true
    var stremioManifests: [String] = []
    var preferredSource = "vidsrc"
    var disableVidsrc = false
    var stremioServerUrl = "http://localhost:11470"
    var enableStremioService = true

    /// Apply per-playback overrides (subtitle url/lang, dub preference).
    func applying(_ o: PlaybackOverrides) -> UserSettings {
        var s = self
        if let v = o.subtitleLanguage { s.subtitleLanguage = v }
        if let v = o.subtitleUrl { s.subtitleUrl = v }
        if let v = o.preferDubbedAnime { s.preferDubbedAnime = v }
        return s
    }
}

struct PlaybackOverrides {
    var subtitleLanguage: String?
    var subtitleUrl: String?
    var preferDubbedAnime: Bool?
}

// MARK: - MediaSeason / MediaEpisode

struct MediaSeason: Codable, Equatable, Hashable {
    var seasonNumber: Int
    var name: String = "Season"
    var episodeCount: Int = 0
}

struct MediaEpisode: Codable, Equatable, Hashable, Identifiable {
    var seasonNumber: Int
    var episodeNumber: Int
    var title: String = "Episode"
    var overview: String = ""
    var airDate: String = ""
    var runtimeMinutes: Int?
    var stillPath: String?

    var id: String { "s\(seasonNumber)e\(episodeNumber)" }
    var stillUrl: String? { imageUrl(stillPath, size: "w300") }
}

// MARK: - MediaItem

struct MediaItem: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var type: MediaType
    var title: String
    var overview: String = ""
    var posterPath: String?
    var backdropPath: String?
    var releaseDate: String = ""
    var rating: Double = 0
    var voteCount: Int = 0
    var genres: [String] = []
    var originCountry: [String] = []
    var cast: [String] = []
    var directors: [String] = []
    var runtimeMinutes: Int?
    var seasons: [MediaSeason] = []
    var episodes: [MediaEpisode] = []
    var tmdbId: Int?
    var tvdbId: Int?
    var traktId: Int?
    var imdbId: String?
    var source: String = "tmdb"

    var posterUrl: String? { imageUrl(posterPath, size: "w342") }
    var backdropUrl: String? { imageUrl(backdropPath, size: "w1280") }
    var heroBackdropUrl: String? { imageUrl(backdropPath, size: "original") }

    /// AniList id when sourced from AniList / One Pace ("anilist:anime:{id}").
    var anilistId: Int? {
        guard id.hasPrefix("anilist:") || id.hasPrefix("onepace:") else { return nil }
        let parts = id.split(separator: ":")
        guard parts.count >= 3 else { return nil }
        return Int(parts.last!)
    }

    /// Japanese animation routes through AniList + AllManga instead of VidSrc.
    var isAnime: Bool {
        if type == .anime { return true }
        guard type == .movie || type == .series else { return false }
        let hasAnimation = genres.contains { $0.lowercased().contains("animation") }
        let isJapanese = originCountry.contains { $0.uppercased() == "JP" }
        return hasAnimation && isJapanese
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: MediaItem, rhs: MediaItem) -> Bool { lhs.id == rhs.id }
}

// MARK: - MediaCategory

struct MediaCategory: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var type: MediaType
    var items: [MediaItem]
    var description: String = ""
    var error: String?
}

// MARK: - Live TV

struct LiveTvEntry: Codable, Equatable, Identifiable, Hashable {
    var title: String
    var url: String
    var source: String
    var region: String = ""
    var language: String = ""
    var logoUrl: String?
    var headers: [String: String] = [:]

    var id: String { url }
    var isDirectStream: Bool { Self.directStream(url) }

    static func directStream(_ url: String) -> Bool {
        let lower = url.lowercased()
        let path = (URL(string: url)?.path ?? url).lowercased()
        return path.hasSuffix(".m3u8") || path.hasSuffix(".mpd") || path.hasSuffix(".mp4")
            || lower.contains(".m3u8?") || lower.contains(".mpd?") || lower.contains(".mp4?")
    }
}

struct LiveTvSource: Codable, Equatable, Identifiable {
    var id: String
    var name: String = "Live TV Source"
    var url: String
    var enabled: Bool = true
    var isDirectStream: Bool { LiveTvEntry.directStream(url) }
}

// MARK: - Playback source

enum PlaybackSourceKind: String, Codable { case embed, direct }

struct PlaybackSource: Identifiable, Equatable {
    var id: String
    var title: String
    var url: String
    var provider: String
    var kind: PlaybackSourceKind
    var quality: String = ""
    var headers: [String: String] = [:]
    var subtitleUrl: String = ""

    var isEmbed: Bool { kind == .embed }
    var isDirect: Bool { kind == .direct }
    var isDirectPlayable: Bool {
        let l = url.lowercased()
        return l.hasPrefix("http") &&
            (l.contains(".m3u8") || l.contains(".mpd") || l.contains(".mp4")
                || l.contains(".webm") || l.contains("googlevideo.com"))
    }
}

// MARK: - Trakt device code

struct TraktDeviceCode {
    var deviceCode: String
    var userCode: String
    var verificationUrl: String
    var expiresIn: Int
    var interval: Int
}

// MARK: - WatchProgress (Continue Watching)

struct WatchProgress: Codable, Equatable, Identifiable {
    var id: Int?
    var itemId: String
    var title: String
    var type: MediaType
    var posterPath: String?
    var backdropPath: String?
    var seasonNumber: Int?
    var episodeNumber: Int?
    var episodeTitle: String?
    var positionMs: Int
    var durationMs: Int
    var lastWatchedAt: Int          // epoch milliseconds

    var fraction: Double {
        durationMs <= 0 ? 0 : min(max(Double(positionMs) / Double(durationMs), 0), 1)
    }
    var posterUrl: String? { imageUrl(posterPath, size: "w342") }
    var backdropUrl: String? { imageUrl(backdropPath, size: "w780") }

    /// Stable key used to dedupe entries (item, or item+episode for series).
    var progressKey: String { itemId }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
