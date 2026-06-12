import Foundation

/// Resolves the *next* thing to play when an episode finishes, ported from the
/// Flutter `_autoplayNextEpisode` / `_nextEpisodeFor` logic. Series and anime
/// roll into the next episode; the last episode of a season rolls into episode 1
/// of the next season. One Pace has its own arc/season resolution. Movies and
/// Live TV never autoplay. Returns `nil` when there is nothing more to play, in
/// which case the host shows recommendations instead.
enum AutoplayResolver {
    enum Next {
        case player(PlayerRoute)   // a direct stream — swap the player in place
        case vidsrc(VidsrcRoute)   // a VidSrc embed — present the resolve screen
    }

    @MainActor
    static func resolveNext(item: MediaItem?, episode: MediaEpisode?, appState: AppState) async -> Next? {
        guard let item, let current = episode else { return nil }
        guard item.type != .movie, item.type != .liveTv else { return nil }

        if item.title == "One Pace" {
            return await resolveNextOnePace(current: current, appState: appState)
        }

        guard let next = nextEpisodeFor(item, current) else { return nil }

        let sources = (try? await appState.playbackSourcesFor(item, episode: next)) ?? []
        if let direct = sources.first(where: { $0.isDirect }) {
            return .player(PlayerRoute(
                title: "\(item.title) • \(direct.title)", url: direct.url, headers: direct.headers,
                item: item, episode: next, subtitleUrl: direct.subtitleUrl,
                startPositionMs: nil, aniSkipEpisode: nil))
        }
        // Series fall back to the VidSrc embed resolver, same as a manual play.
        if item.type == .series,
           let embed = sources.first(where: { $0.isEmbed && $0.provider == "VidSrc" }) {
            let urls = VidsrcExtractor().embedUrlsFor(
                item: item, episode: next, preferredDomain: appState.settings.vidsrcDomain,
                subtitleUrl: appState.settings.subtitleUrl, subtitleLanguage: appState.settings.subtitleLanguage)
            if !urls.isEmpty {
                return .vidsrc(VidsrcRoute(item: item, title: embed.title, embedUrls: urls, episode: next))
            }
        }
        return nil
    }

    /// Next episode on the current season, or episode 1 of the next season when
    /// the current season is exhausted. `nil` once the show is over.
    static func nextEpisodeFor(_ item: MediaItem, _ current: MediaEpisode) -> MediaEpisode? {
        let season = item.seasons.first { $0.seasonNumber == current.seasonNumber }
        var maxEp = season?.episodeCount ?? item.episodes.count
        if maxEp <= 0 { maxEp = 9999 }
        let nextNumber = current.episodeNumber + 1
        if nextNumber > maxEp {
            let nextSeasonNumber = current.seasonNumber + 1
            if item.seasons.contains(where: { $0.seasonNumber == nextSeasonNumber }) {
                return MediaEpisode(seasonNumber: nextSeasonNumber, episodeNumber: 1, title: "Episode 1")
            }
            return nil
        }
        return MediaEpisode(seasonNumber: current.seasonNumber, episodeNumber: nextNumber,
                            title: "Episode \(nextNumber)")
    }

    /// One Pace: try the next episode in the current arc, then episode 1 of the
    /// next arc/season. `OnePaceResolver.resolveForResume` throws when an episode
    /// or season doesn't exist, which we use to detect the rollover boundary.
    @MainActor
    private static func resolveNextOnePace(current: MediaEpisode, appState: AppState) async -> Next? {
        let apiKey = appState.credentials.pixeldrainApiKey.trimmed
        func route(_ r: OnePaceResolver.Resolved) -> Next {
            .player(PlayerRoute(title: r.title, url: r.url, headers: [:], item: r.item,
                                episode: r.episode, subtitleUrl: r.subtitleUrl,
                                startPositionMs: 0, aniSkipEpisode: r.aniSkipEpisode))
        }
        if let r = try? await OnePaceResolver.resolveForResume(
            seasonNumber: current.seasonNumber, episodeNumber: current.episodeNumber + 1, apiKey: apiKey) {
            return route(r)
        }
        if let r = try? await OnePaceResolver.resolveForResume(
            seasonNumber: current.seasonNumber + 1, episodeNumber: 1, apiKey: apiKey) {
            return route(r)
        }
        return nil
    }
}
