import Foundation

// Repository protocols — the contract the concrete implementations conform to.
// Faithful to the Dart repositories in ../lib/src/repositories.

protocol TmdbRepositoryProtocol {
    func fetchLandingCategories(credentials: ApiCredentials, settings: UserSettings) async throws -> [MediaCategory]
    func fetchDetails(_ item: MediaItem, credentials: ApiCredentials, settings: UserSettings) async -> MediaItem?
    func searchMulti(_ query: String, credentials: ApiCredentials, settings: UserSettings) async -> [MediaItem]
    func fetchSeasonEpisodes(_ item: MediaItem, seasonNumber: Int, credentials: ApiCredentials, settings: UserSettings) async -> [MediaEpisode]
    func fetchRecommendations(_ item: MediaItem, credentials: ApiCredentials, settings: UserSettings) async -> [MediaItem]
}

protocol TvdbRepositoryProtocol {
    func validate(_ credentials: ApiCredentials) async -> Bool
    func enrichDetails(_ item: MediaItem, credentials: ApiCredentials) async -> MediaItem
    func fetchSeasonEpisodes(_ item: MediaItem, seasonNumber: Int, credentials: ApiCredentials) async -> [MediaEpisode]
}

protocol TraktRepositoryProtocol {
    func fetchUserSettings(_ c: ApiCredentials) async throws -> ApiCredentials
    func fetchDiscoveryCategories(_ c: ApiCredentials) async throws -> [MediaCategory]
    func fetchWatchlist(_ c: ApiCredentials) async throws -> [MediaItem]
    func setWatchlistItem(_ c: ApiCredentials, _ item: MediaItem, add: Bool) async throws
    func fetchPlaybackProgress(_ c: ApiCredentials) async -> [WatchProgress]
    func deletePlaybackProgress(_ c: ApiCredentials, playbackId: Int) async throws
    func startScrobble(_ c: ApiCredentials, _ item: MediaItem, episode: MediaEpisode?, progress: Double) async throws
    func pauseScrobble(_ c: ApiCredentials, _ item: MediaItem, episode: MediaEpisode?, progress: Double) async throws
    func stopScrobble(_ c: ApiCredentials, _ item: MediaItem, episode: MediaEpisode?, progress: Double) async throws
    func fetchRemoteSettings(_ c: ApiCredentials) async -> String?
    func saveRemoteSettings(_ c: ApiCredentials, payload: String) async throws
    func ensureFreshAccessToken(_ c: ApiCredentials) async throws -> ApiCredentials
    func buildOAuthAuthorizeUri(_ c: ApiCredentials, state: String) -> URL?
    func exchangeAuthorizationCode(_ c: ApiCredentials, code: String) async throws -> ApiCredentials
    func startDeviceAuth(_ c: ApiCredentials) async throws -> TraktDeviceCode
    func completeDeviceAuth(_ c: ApiCredentials, _ code: TraktDeviceCode) async throws -> ApiCredentials
}

protocol VidsrcRepositoryProtocol {
    func sourcesFor(_ item: MediaItem, settings: UserSettings, episode: MediaEpisode?) -> [PlaybackSource]
    func fetchLatestCategories() async -> [MediaCategory]
}

protocol AnimeRepositoryProtocol {
    func fetchAnimeCategories() async throws -> [MediaCategory]
    func findByTitle(_ title: String) async -> MediaItem?
    func fetchEpisodes(_ item: MediaItem, seasonNumber: Int) async -> [MediaEpisode]
    func resolveSource(item: MediaItem, episode: MediaEpisode, settings: UserSettings) async throws -> PlaybackSource
    func updateAniListProgress(accessToken: String, mediaId: Int, progress: Int, status: String) async throws
    func recommendations(anilistId: Int) async -> [MediaItem]
}

protocol LiveTvRepositoryProtocol {
    func fetchSource(_ source: LiveTvSource) async throws -> [LiveTvEntry]
}

protocol YarrlistRepositoryProtocol {
    func fetchLiveTvDirectory() async throws -> [LiveTvEntry]
    func fetchMoviesTvDirectory() async throws -> [LiveTvEntry]
}

/// Bundle of all repositories, injected into AppState.
struct Repositories {
    var tmdb: TmdbRepositoryProtocol
    var tvdb: TvdbRepositoryProtocol
    var trakt: TraktRepositoryProtocol
    var vidsrc: VidsrcRepositoryProtocol
    var anime: AnimeRepositoryProtocol
    var liveTv: LiveTvRepositoryProtocol
    var yarrlist: YarrlistRepositoryProtocol

    static func live() -> Repositories {
        Repositories(
            tmdb: TmdbRepository(),
            tvdb: TvdbRepository(),
            trakt: TraktRepository(),
            vidsrc: VidsrcRepository(),
            anime: AnimeRepository(),
            liveTv: LiveTvRepository(),
            yarrlist: YarrlistRepository()
        )
    }
}
