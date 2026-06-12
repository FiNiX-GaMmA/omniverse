import Foundation

/// TheTVDB v4 client. Ported from tvdb_repository.dart.
final class TvdbRepository: TvdbRepositoryProtocol {

    private let base = URL(string: "https://api4.thetvdb.com/v4/")!

    // Token cache (valid ~28 days). Serialised through an actor.
    private actor TokenStore {
        var token: String?
        var expiresAt: Date?

        func current() -> String? {
            if let token, let expiresAt, Date() < expiresAt { return token }
            return nil
        }
        func set(_ token: String) {
            self.token = token
            self.expiresAt = Date().addingTimeInterval(28 * 24 * 60 * 60)
        }
    }
    private let tokens = TokenStore()

    func validate(_ credentials: ApiCredentials) async -> Bool {
        if !credentials.hasTvdb { return false }
        do {
            _ = try await ensureToken(credentials)
            return true
        } catch {
            return false
        }
    }

    func enrichDetails(_ item: MediaItem, credentials: ApiCredentials) async -> MediaItem {
        if !credentials.hasTvdb || item.type == .liveTv { return item }
        do {
            let token = try await ensureToken(credentials)
            let tvdbId: Int
            if let existing = item.tvdbId { tvdbId = existing }
            else if let found = await findTvdbId(item, token) { tvdbId = found }
            else { return item }
            let path = item.type == .movie ? "movies/\(tvdbId)/extended" : "series/\(tvdbId)/extended"
            let response = try await Http.shared.request(base.appendingPathComponent(path),
                                                          headers: authHeaders(token), timeout: 12)
            if response.status >= 400 {
                var copy = item
                copy.tvdbId = tvdbId
                return copy
            }
            guard let data = response.jsonObject().obj("data") else {
                var copy = item
                copy.tvdbId = tvdbId
                return copy
            }
            return mergeExtended(item, data, tvdbId)
        } catch {
            return item
        }
    }

    func fetchSeasonEpisodes(_ item: MediaItem, seasonNumber: Int, credentials: ApiCredentials) async -> [MediaEpisode] {
        if !credentials.hasTvdb || item.type != .series { return [] }
        do {
            let token = try await ensureToken(credentials)
            let tvdbId: Int
            if let existing = item.tvdbId { tvdbId = existing }
            else if let found = await findTvdbId(item, token) { tvdbId = found }
            else { return [] }
            let response = try await Http.shared.request(
                base.appendingPathComponent("series/\(tvdbId)/episodes/default/eng"),
                headers: authHeaders(token), timeout: 12)
            if response.status >= 400 { return [] }
            guard let data = response.jsonObject().obj("data"),
                  let episodes = data.arr("episodes") else { return [] }
            return episodes
                .compactMap { $0 as? [String: Any] }
                .filter { $0.int("seasonNumber") == seasonNumber }
                .map { episode in
                    MediaEpisode(
                        seasonNumber: episode.int("seasonNumber") ?? seasonNumber,
                        episodeNumber: episode.int("number") ?? 0,
                        title: episode.str("name") ?? "Episode",
                        overview: episode.str("overview") ?? "",
                        airDate: episode.str("aired") ?? episode.str("firstAired") ?? "",
                        runtimeMinutes: episode.int("runtime"),
                        stillPath: episode.str("image")
                    )
                }
                .filter { $0.episodeNumber > 0 }
        } catch {
            return []
        }
    }

    // MARK: Token

    private func ensureToken(_ credentials: ApiCredentials) async throws -> String {
        if let cached = await tokens.current() { return cached }
        var payload: [String: Any] = ["apikey": credentials.tvdbApiKey.trimmed]
        if !credentials.tvdbPin.trimmed.isEmpty {
            payload["pin"] = credentials.tvdbPin.trimmed
        }
        let response = try await Http.shared.postJSON(base.appendingPathComponent("login"),
                                                      json: payload, timeout: 12)
        if response.status >= 400 {
            throw TvdbError.message("TVDB returned \(response.status)")
        }
        guard let token = response.jsonObject().obj("data")?.str("token"), !token.isEmpty else {
            throw TvdbError.message("TVDB login response did not include token.")
        }
        await tokens.set(token)
        return token
    }

    // MARK: Remote id lookup

    private func findTvdbId(_ item: MediaItem, _ token: String) async -> Int? {
        var remoteIds: [String] = []
        if let imdb = item.imdbId?.trimmed, !imdb.isEmpty { remoteIds.append(imdb) }
        if let tmdbId = item.tmdbId { remoteIds.append(String(tmdbId)) }

        for remoteId in remoteIds {
            guard let response = try? await Http.shared.request(
                base.appendingPathComponent("search/remoteid/\(remoteId)"),
                headers: authHeaders(token), timeout: 12) else { continue }
            if response.status >= 400 { continue }
            guard let data = response.jsonObject().arr("data") else { continue }
            for result in data.compactMap({ $0 as? [String: Any] }) {
                let type = (result.str("type") ?? "").lowercased()
                let typeMatches =
                    (item.type == .movie && type.contains("movie")) ||
                    ((item.type == .series || item.type == .anime) && type.contains("series"))
                if !typeMatches && !type.isEmpty { continue }
                if let tvdbId = result.int("tvdb_id") ?? result.int("id") { return tvdbId }
            }
        }
        return nil
    }

    // MARK: Merge

    private func mergeExtended(_ item: MediaItem, _ data: [String: Any], _ tvdbId: Int) -> MediaItem {
        let genres = (data.arr("genres") ?? [])
            .compactMap { $0 as? [String: Any] }
            .compactMap { $0.str("name") }
            .filter { !$0.isEmpty }
        let artworks = (data.arr("artworks") ?? []).compactMap { $0 as? [String: Any] }
        let poster = item.posterPath ?? data.str("image")
        let backdrop = item.backdropPath ?? bestArtwork(artworks)

        var copy = item
        copy.overview = item.overview.isEmpty ? (data.str("overview") ?? "") : item.overview
        copy.posterPath = poster
        copy.backdropPath = backdrop
        copy.genres = item.genres.isEmpty ? genres : item.genres
        copy.runtimeMinutes = item.runtimeMinutes ?? data.int("averageRuntime") ?? data.int("runtime")
        copy.tvdbId = tvdbId
        return copy
    }

    private func bestArtwork(_ artworks: [[String: Any]]) -> String? {
        for artwork in artworks {
            if let image = artwork.str("image"), !image.isEmpty { return image }
        }
        return nil
    }

    private func authHeaders(_ token: String) -> [String: String] {
        ["Authorization": "Bearer \(token)", "Accept": "application/json"]
    }
}

private enum TvdbError: Error { case message(String) }
