import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class AppState {
    // Stores
    let credentialsStore = CredentialsStore()
    let settingsStore = UserSettingsStore()
    var repos: Repositories

    // State (mirrors OmniverseState fields)
    var settings = UserSettings()
    var credentials = ApiCredentials()
    var categories: [MediaCategory] = []
    var animeCategories: [MediaCategory] = []
    var liveTv: [LiveTvEntry] = []
    var liveTvSources: [LiveTvSource] = []
    var watchlist: Set<String> = []
    var watchHistory: [WatchProgress] = []
    private var heroPicksCache: [MediaItem] = []

    var initialized = false
    var loading = false
    var traktConnecting = false
    var pendingTraktState: String?
    var message: String?

    var isScanningLiveTv = false
    var liveTvScanProgress: Double = 0
    var hasScannedLiveTv = false

    var needsSetup: Bool { !credentials.hasTmdb }

    private var playbackTimer: Timer?

    init(repos: Repositories = .live()) { self.repos = repos }

    // MARK: - Lifecycle

    func initialize() async {
        settings = settingsStore.loadSettings()
        credentials = credentialsStore.load()
        liveTvSources = settingsStore.loadLiveTvSources()
        watchlist = settingsStore.loadWatchlist()
        let cachedCategories = settingsStore.loadCachedCategories()
        let cachedLiveTv = settingsStore.loadCachedLiveTv()
        if !cachedCategories.isEmpty { categories = cachedCategories }
        liveTv = cachedLiveTv
        hasScannedLiveTv = !liveTv.isEmpty
        watchHistory = settingsStore.loadWatchHistory()
        initialized = true

        // Silent refresh only if cache older than 6 hours.
        let last = settingsStore.lastRefreshedTime()
        let diff = Int(Date().timeIntervalSince1970 * 1000) - last
        if diff >= 6 * 3600 * 1000 {
            Task { await refreshAll(isManual: false) }
        } else {
            Task { await refreshTraktWatchlist() }
        }

        // Pull API keys + settings saved by other devices on the same Trakt
        // account, so they propagate automatically on launch.
        Task { await pullRemoteSettingsSilently() }

        // Periodic full bidirectional sync every 20s while foreground.
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.credentials.hasTraktUser, self.initialized else { return }
                await self.syncNow()
            }
        }
    }

    // MARK: - Refresh

    func refreshAll(isManual: Bool = true) async {
        if isManual { loading = true; message = nil }
        await refreshCategories()
        await refreshAnime()
        await refreshTraktWatchlist()
        settingsStore.setLastRefreshedTime(Int(Date().timeIntervalSince1970 * 1000))
        clearHeroCache()
        if isManual { loading = false }
    }

    func refreshCategories() async {
        var next: [MediaCategory] = []
        var notices: [String] = []
        do {
            let tmdb = try await repos.tmdb.fetchLandingCategories(credentials: credentials, settings: settings)
            let loaded = nonEmptyCategories(tmdb)
            next.append(contentsOf: loaded)
            if loaded.isEmpty, let e = categoryErrorMessage(tmdb, "TMDB") { notices.append(e) }
        } catch { notices.append(safeRefreshMessage("TMDB", error)) }

        do {
            let trakt = try await repos.trakt.fetchDiscoveryCategories(credentials)
            let enriched = await enrichMetadataCategories(trakt.filter { $0.id.hasPrefix("trakt_") }, maxItems: 12)
            next.append(contentsOf: nonEmptyCategories(enriched))
        } catch { notices.append(safeRefreshMessage("Trakt", error)) }

        let vid = await repos.vidsrc.fetchLatestCategories()
        let enrichedVid = await enrichMetadataCategories(vid, maxItems: 10)
        if !next.isEmpty || categories.isEmpty { next.append(contentsOf: nonEmptyCategories(enrichedVid)) }

        if !next.isEmpty {
            categories = next
            settingsStore.saveCachedCategories(categories)
        } else if !categories.isEmpty && notices.isEmpty {
            notices.append("Showing cached rows.")
        }
        if let first = notices.first { message = first }
    }

    func refreshAnime() async {
        do { animeCategories = try await repos.anime.fetchAnimeCategories() }
        catch { message = "Could not refresh anime rows: \(error)" }
    }

    func refreshTraktWatchlist() async {
        guard credentials.hasTraktUser else { return }
        do {
            try await refreshTraktCredentialsIfNeeded()
            let items = try await repos.trakt.fetchWatchlist(credentials)
            var next = watchlist
            for item in items { next.formUnion(watchlistKeys(item)) }
            watchlist = next
            settingsStore.saveWatchlist(next)
        } catch { message = "Could not sync Trakt watchlist: \(error)" }
        await refreshTraktPlayback()
    }

    func refreshTraktPlayback() async {
        guard credentials.hasTraktUser else { return }
        do {
            try await refreshTraktCredentialsIfNeeded()
            await syncWatchHistoryFromTrakt()
            let remote = await repos.trakt.fetchPlaybackProgress(credentials)
            if !remote.isEmpty { mergeProgress(remote, preferRemoteTime: false) }
        } catch { /* keep local */ }
    }

    // MARK: - Watch history

    private func mergeProgress(_ incoming: [WatchProgress], preferRemoteTime: Bool) {
        var byKey: [String: WatchProgress] = [:]
        for e in watchHistory { byKey[e.progressKey] = e }
        for e in incoming {
            if let local = byKey[e.progressKey], local.lastWatchedAt >= e.lastWatchedAt {
                continue
            }
            if let local = byKey[e.progressKey] {
                var merged = e
                merged.posterPath = e.posterPath ?? local.posterPath
                merged.backdropPath = e.backdropPath ?? local.backdropPath
                byKey[e.progressKey] = merged
            } else {
                byKey[e.progressKey] = e
            }
        }
        watchHistory = Array(byKey.values).sorted { $0.lastWatchedAt > $1.lastWatchedAt }.prefix(30).map { $0 }
        settingsStore.saveWatchHistory(watchHistory)
    }

    func recordProgress(item: MediaItem, positionMs: Int, durationMs: Int, episode: MediaEpisode?) async {
        guard durationMs > 0 else { return }
        let fraction = Double(positionMs) / Double(durationMs)
        if positionMs < 5000 || fraction >= 0.95 {
            if fraction >= 0.95 { removeProgressEntry(item, episode) }
            return
        }
        let entry = WatchProgress(
            id: nil, itemId: item.id, title: item.title, type: item.type,
            posterPath: item.posterPath, backdropPath: item.backdropPath,
            seasonNumber: episode?.seasonNumber, episodeNumber: episode?.episodeNumber,
            episodeTitle: episode?.title, positionMs: positionMs, durationMs: durationMs,
            lastWatchedAt: Int(Date().timeIntervalSince1970 * 1000))
        var next = [entry]
        next.append(contentsOf: watchHistory.filter { $0.progressKey != entry.progressKey })
        watchHistory = Array(next.prefix(30))
        settingsStore.saveWatchHistory(watchHistory)
    }

    private func removeProgressEntry(_ item: MediaItem, _ episode: MediaEpisode?) {
        let next = watchHistory.filter { $0.progressKey != item.id }
        guard next.count != watchHistory.count else { return }
        watchHistory = next
        settingsStore.saveWatchHistory(watchHistory)
    }

    func dismissProgress(_ entry: WatchProgress) async {
        watchHistory = watchHistory.filter { $0.itemId != entry.itemId }
        settingsStore.saveWatchHistory(watchHistory)
        if credentials.hasTraktUser {
            try? await refreshTraktCredentialsIfNeeded()
            if let id = entry.id { try? await repos.trakt.deletePlaybackProgress(credentials, playbackId: id) }
            else {
                let remote = await repos.trakt.fetchPlaybackProgress(credentials)
                for r in remote where r.itemId == entry.itemId { if let id = r.id { try? await repos.trakt.deletePlaybackProgress(credentials, playbackId: id) } }
            }
            Task { try? await syncSettingsToTrakt() }
        }
    }

    var continueWatching: [WatchProgress] { watchHistory.sorted { $0.lastWatchedAt > $1.lastWatchedAt } }

    func syncWatchHistoryFromTrakt() async {
        guard credentials.hasTraktUser else { return }
        guard let payload = await repos.trakt.fetchRemoteSettings(credentials)?.trimmed, !payload.isEmpty,
              let data = Data(base64Encoded: payload),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = obj["watch_history"] as? [[String: Any]] else { return }
        let restored = raw.compactMap { WatchProgress.fromJSON($0) }
        mergeProgress(restored, preferRemoteTime: true)
    }

    // MARK: - Trakt backup/restore (Base64(JSON), parity with app_state.dart)

    func syncSettingsToTrakt(silent: Bool = false) async throws {
        guard credentials.hasTraktUser else { throw NSError(domain: "trakt", code: 1, userInfo: [NSLocalizedDescriptionKey: "Trakt not connected."]) }
        try await refreshTraktCredentialsIfNeeded()
        let payload: [String: Any] = [
            "version": 1,
            "tmdb_token": credentials.tmdbToken,
            "tvdb_api_key": credentials.tvdbApiKey,
            "tvdb_pin": credentials.tvdbPin,
            "pixeldrain_api_key": credentials.pixeldrainApiKey,
            "anilist_access_token": credentials.anilistAccessToken,
            "trakt_client_id": credentials.traktClientId,
            "trakt_client_secret": credentials.traktClientSecret,
            "settings": settings.toJSON(),
            "watch_history": watchHistory.map { $0.toJSON() },
        ]
        let json = try JSONSerialization.data(withJSONObject: payload)
        let b64 = json.base64EncodedString()
        try await repos.trakt.saveRemoteSettings(credentials, payload: b64)
        if !silent { message = "All settings and API keys successfully synced to Trakt!" }
    }

    /// Full bidirectional background sync: pull the cloud backup + Trakt
    /// watchlist/playback (merging newest-wins), then push the merged local
    /// state back. Runs periodically + on foreground/background transitions so
    /// watchlist, watch time, last-watched episode and API keys stay in lockstep
    /// across devices. Silent (no toasts).
    func syncNow() async {
        guard credentials.hasTraktUser else { return }
        do { try await refreshTraktCredentialsIfNeeded() } catch { return }
        await pullRemoteSettingsSilently()   // keys + settings
        await refreshTraktWatchlist()         // watchlist + playback + watch history merge
        try? await syncSettingsToTrakt(silent: true)  // push merged backup
    }

    func restoreSettingsFromTrakt() async throws {
        guard credentials.hasTraktUser else { throw NSError(domain: "trakt", code: 1) }
        try await refreshTraktCredentialsIfNeeded()
        guard let payload = await repos.trakt.fetchRemoteSettings(credentials)?.trimmed, !payload.isEmpty,
              let data = Data(base64Encoded: payload),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "trakt", code: 2, userInfo: [NSLocalizedDescriptionKey: "No backup settings found."])
        }
        var c = credentials
        if let v = obj["tmdb_token"] as? String { c.tmdbToken = v }
        if let v = obj["tvdb_api_key"] as? String { c.tvdbApiKey = v }
        if let v = obj["tvdb_pin"] as? String { c.tvdbPin = v }
        if let v = obj["pixeldrain_api_key"] as? String { c.pixeldrainApiKey = v }
        if let v = obj["anilist_access_token"] as? String { c.anilistAccessToken = v }
        await saveCredentials(c)
        if let s = obj["settings"] as? [String: Any] { await saveSettings(UserSettings.fromJSON(s)) }
        if let raw = obj["watch_history"] as? [[String: Any]] {
            mergeProgress(raw.compactMap { WatchProgress.fromJSON($0) }, preferRemoteTime: true)
        }
        message = "All settings and API keys successfully restored from Trakt!"
    }

    // MARK: - Cross-device sync (server-less QR, see SYNC_SPEC.md)

    /// Applies a scanned/pasted sync string. Returns true if it was a sync payload
    /// that was merged + persisted. If it's an http(s) URL, opens it externally and
    /// returns false. Returns false for anything unrecognised.
    func applySyncString(_ s: String) async -> Bool {
        let text = s.trimmed
        guard !text.isEmpty else { return false }

        if text.hasPrefix("http://") || text.hasPrefix("https://"), let url = URL(string: text) {
            await UIApplication.shared.open(url)
            message = "Opening activation link..."
            return false
        }

        guard let parsed = SyncPayload.parseSyncString(text) else {
            message = "Could not read that Sync QR."
            return false
        }

        // Merge only present (non-empty) fields onto the current credentials.
        var c = credentials
        let p = parsed.credentials
        if !p.traktAccessToken.trimmed.isEmpty { c.traktAccessToken = p.traktAccessToken }
        if !p.traktRefreshToken.trimmed.isEmpty { c.traktRefreshToken = p.traktRefreshToken }
        if p.traktTokenExpiresAt != 0 { c.traktTokenExpiresAt = p.traktTokenExpiresAt }
        if !p.traktUsername.trimmed.isEmpty { c.traktUsername = p.traktUsername }
        if !p.traktClientId.trimmed.isEmpty { c.traktClientId = p.traktClientId }
        if !p.traktClientSecret.trimmed.isEmpty { c.traktClientSecret = p.traktClientSecret }
        if !p.tmdbToken.trimmed.isEmpty { c.tmdbToken = p.tmdbToken }
        if !p.tvdbApiKey.trimmed.isEmpty { c.tvdbApiKey = p.tvdbApiKey }
        if !p.tvdbPin.trimmed.isEmpty { c.tvdbPin = p.tvdbPin }
        if !p.pixeldrainApiKey.trimmed.isEmpty { c.pixeldrainApiKey = p.pixeldrainApiKey }
        if !p.anilistAccessToken.trimmed.isEmpty { c.anilistAccessToken = p.anilistAccessToken }

        // Persist credentials directly (avoid saveCredentials' Trakt-key-change
        // reset, which would wipe the tokens we just received).
        credentials = c
        credentialsStore.save(c)
        if let s = parsed.settings {
            settings = s
            settingsStore.saveSettings(s)
        }
        message = "Signed in from Sync QR."
        await refreshAll(isManual: false)
        if credentials.hasTraktUser { await refreshTraktWatchlist() }
        return true
    }

    /// The full sync string for this device (for "Show Sync QR").
    func buildSyncString() -> String {
        SyncPayload.buildSyncString(credentials: credentials, settings: settings)
    }

    /// Silently pull the latest API keys + settings from the Trakt-backed cloud
    /// backup (the "Omniverse Sync" list) so they propagate across devices.
    /// Last-write-wins; does not re-upload (avoids loops).
    func pullRemoteSettingsSilently() async {
        guard credentials.hasTraktUser else { return }
        do { try await refreshTraktCredentialsIfNeeded() } catch { return }
        guard let payload = await repos.trakt.fetchRemoteSettings(credentials)?.trimmed, !payload.isEmpty,
              let data = Data(base64Encoded: payload),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        var c = credentials
        if let v = obj["tmdb_token"] as? String, !v.isEmpty { c.tmdbToken = v }
        if let v = obj["tvdb_api_key"] as? String, !v.isEmpty { c.tvdbApiKey = v }
        if let v = obj["tvdb_pin"] as? String { c.tvdbPin = v }
        if let v = obj["pixeldrain_api_key"] as? String, !v.isEmpty { c.pixeldrainApiKey = v }
        if let v = obj["anilist_access_token"] as? String, !v.isEmpty { c.anilistAccessToken = v }
        if let v = obj["trakt_client_id"] as? String, !v.isEmpty { c.traktClientId = v }
        if let v = obj["trakt_client_secret"] as? String, !v.isEmpty { c.traktClientSecret = v }
        let changed = c != credentials
        credentials = c
        credentialsStore.save(c)
        if let s = obj["settings"] as? [String: Any] {
            settings = UserSettings.fromJSON(s); settingsStore.saveSettings(settings)
        }
        if changed { await refreshAll(isManual: false) }
    }

    // MARK: - Credentials / settings

    func saveCredentials(_ next: ApiCredentials) async {
        var n = next
        let changed = n.traktClientId.trimmed != credentials.traktClientId.trimmed
            || n.traktClientSecret.trimmed != credentials.traktClientSecret.trimmed
        if changed { n.traktAccessToken = ""; n.traktRefreshToken = ""; n.traktTokenExpiresAt = 0; n.traktUsername = "" }
        credentials = n
        credentialsStore.save(n)
        if credentials.hasTraktUser { Task { try? await syncSettingsToTrakt() } }
        await refreshAll()
    }

    func saveSettings(_ next: UserSettings) async {
        settings = next
        settingsStore.saveSettings(next)
        if credentials.hasTraktUser { Task { try? await syncSettingsToTrakt() } }
        await refreshAll()
    }

    // MARK: - Search / details / playback

    func searchMedia(_ query: String) async -> [MediaItem] {
        await repos.tmdb.searchMulti(query, credentials: credentials, settings: settings)
    }

    func detailsFor(_ item: MediaItem) async -> MediaItem {
        if item.type == .anime || item.isAnime {
            if let hydrated = await repos.anime.findByTitle(item.title) {
                var h = hydrated
                h.tmdbId = item.tmdbId ?? hydrated.tmdbId
                h.tvdbId = item.tvdbId ?? hydrated.tvdbId
                h.imdbId = item.imdbId ?? hydrated.imdbId
                h.traktId = item.traktId ?? hydrated.traktId
                return h
            }
            if item.type == .anime && !item.seasons.isEmpty { return item }
        }
        let detailed = await repos.tmdb.fetchDetails(item, credentials: credentials, settings: settings) ?? item
        let enriched = await repos.tvdb.enrichDetails(detailed, credentials: credentials)
        if enriched.isAnime && enriched.type != .anime, let anilist = await repos.anime.findByTitle(enriched.title) {
            var a = anilist
            a.tmdbId = enriched.tmdbId; a.tvdbId = enriched.tvdbId
            a.imdbId = enriched.imdbId; a.traktId = enriched.traktId
            return a
        }
        return enriched
    }

    func seasonEpisodesFor(_ item: MediaItem, seasonNumber: Int) async -> [MediaEpisode] {
        if item.type == .anime {
            var eps = await repos.anime.fetchEpisodes(item, seasonNumber: seasonNumber)
            if item.tmdbId != nil {
                let tmdbEps = await repos.tmdb.fetchSeasonEpisodes(item, seasonNumber: seasonNumber, credentials: credentials, settings: settings)
                if !tmdbEps.isEmpty {
                    let byNum = Dictionary(tmdbEps.map { ($0.episodeNumber, $0) }, uniquingKeysWith: { a, _ in a })
                    eps = eps.map { ep in
                        if let t = byNum[ep.episodeNumber], let still = t.stillPath, (ep.stillPath ?? "").isEmpty {
                            var e = ep; e.stillPath = still; return e
                        }
                        return ep
                    }
                }
            }
            return eps
        }
        let eps = await repos.tmdb.fetchSeasonEpisodes(item, seasonNumber: seasonNumber, credentials: credentials, settings: settings)
        if !eps.isEmpty || !credentials.hasTvdb { return eps }
        return await repos.tvdb.fetchSeasonEpisodes(item, seasonNumber: seasonNumber, credentials: credentials)
    }

    func playbackSourcesFor(_ item: MediaItem, episode: MediaEpisode? = nil, overrides: PlaybackOverrides = .init()) async throws -> [PlaybackSource] {
        let effective = settings.applying(overrides)
        if item.type == .anime {
            let target = episode ?? item.episodes.first ?? MediaEpisode(seasonNumber: 1, episodeNumber: 1, title: "Episode 1")
            return [try await repos.anime.resolveSource(item: item, episode: target, settings: effective)]
        }
        return repos.vidsrc.sourcesFor(item, settings: effective, episode: episode)
    }

    // MARK: - Recommendations

    /// "Because you watched ..." recommendations shown on the end-of-show screen
    /// when there are no more episodes/seasons to autoplay. Anime resolve through
    /// AniList, One Pace maps to One Piece (id 21), movies/TV use TMDB.
    func recommendationsFor(_ item: MediaItem?) async -> [MediaItem] {
        guard let item else { return [] }
        if item.title == "One Pace" {
            return await repos.anime.recommendations(anilistId: 21)
        }
        if item.type == .anime || item.isAnime, let anilistId = item.anilistId {
            let recs = await repos.anime.recommendations(anilistId: anilistId)
            if !recs.isEmpty { return recs }
        }
        if item.tmdbId != nil {
            return await repos.tmdb.fetchRecommendations(item, credentials: credentials, settings: settings)
        }
        return []
    }

    // MARK: - Watchlist

    func isInWatchlist(_ item: MediaItem) -> Bool { !watchlistKeys(item).isDisjoint(with: watchlist) }

    func toggleWatchlist(_ item: MediaItem) async {
        let wasSaved = isInWatchlist(item)
        let keys = watchlistKeys(item)
        do {
            if credentials.hasTraktUser && item.type != .liveTv {
                try await refreshTraktCredentialsIfNeeded()
                try await repos.trakt.setWatchlistItem(credentials, item, add: !wasSaved)
            }
            var next = watchlist
            if wasSaved { keys.forEach { next.remove($0) } } else { next.formUnion(keys) }
            watchlist = next
            settingsStore.saveWatchlist(next)
            if credentials.hasTraktUser && item.type != .liveTv {
                message = wasSaved ? "Removed from Trakt watchlist." : "Added to Trakt watchlist."
            }
        } catch { message = "Could not sync Trakt watchlist: \(error)" }
    }

    private func watchlistKeys(_ item: MediaItem) -> Set<String> {
        var typeNames: Set<String> = [item.type.rawValue]
        if [.anime, .series, .movie].contains(item.type) { typeNames.formUnion(["anime", "series", "movie"]) }
        let imdb = item.imdbId?.trimmed ?? ""
        var keys: Set<String> = [item.id]
        for name in typeNames {
            if let t = item.traktId { keys.insert("trakt:\(name):\(t)") }
            if let t = item.tmdbId { keys.insert("tmdb:\(name):\(t)") }
            if let t = item.tvdbId { keys.insert("tvdb:\(name):\(t)") }
            if !imdb.isEmpty { keys.insert("imdb:\(name):\(imdb)") }
        }
        return keys
    }

    // MARK: - Scrobble

    func startTraktPlayback(_ item: MediaItem, _ progress: Double, episode: MediaEpisode?) async {
        await sendScrobble(item) { try await self.repos.trakt.startScrobble($0, item, episode: episode, progress: progress) }
    }
    func pauseTraktPlayback(_ item: MediaItem, _ progress: Double, episode: MediaEpisode?) async {
        await sendScrobble(item) { try await self.repos.trakt.pauseScrobble($0, item, episode: episode, progress: progress) }
    }
    func stopTraktPlayback(_ item: MediaItem, _ progress: Double, episode: MediaEpisode?) async {
        await sendScrobble(item) { try await self.repos.trakt.stopScrobble($0, item, episode: episode, progress: progress) }
        if credentials.hasAnilist, let episode {
            let isAnime = item.type == .anime || item.isAnime || item.title == "One Pace"
            let anilistId = item.title == "One Pace" ? 21 : item.anilistId
            if isAnime, let anilistId {
                try? await repos.anime.updateAniListProgress(accessToken: credentials.anilistAccessToken, mediaId: anilistId, progress: episode.episodeNumber, status: "CURRENT")
            }
        }
    }
    private func sendScrobble(_ item: MediaItem, _ send: @escaping (ApiCredentials) async throws -> Void) async {
        guard credentials.hasTraktUser, item.type != .liveTv else { return }
        do { try await refreshTraktCredentialsIfNeeded(); try await send(credentials) }
        catch { message = "Could not update Trakt playback: \(error)" }
    }

    private func refreshTraktCredentialsIfNeeded() async throws {
        let next = try await repos.trakt.ensureFreshAccessToken(credentials)
        guard next != credentials else { return }
        credentials = next
        credentialsStore.save(next)
    }

    // MARK: - Trakt connect

    func startTraktBrowserAuth() -> URL? {
        pendingTraktState = randomState()
        traktConnecting = true
        message = "Opening Trakt sign in..."
        return repos.trakt.buildOAuthAuthorizeUri(credentials, state: pendingTraktState!)
    }

    func disconnectTrakt() {
        pendingTraktState = nil; traktConnecting = false
        credentials.traktAccessToken = ""; credentials.traktRefreshToken = ""
        credentials.traktTokenExpiresAt = 0; credentials.traktUsername = ""
        credentialsStore.save(credentials)
        message = "Trakt disconnected."
    }

    func handleIncomingURL(_ url: URL) async {
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        // AniList token (fragment)
        if url.scheme == "omniplay" && url.host == "anilist" && url.path == "/oauth" {
            let frag = comps?.fragment ?? comps?.query ?? ""
            let params = Dictionary(uniqueKeysWithValues: frag.split(separator: "&").compactMap { pair -> (String, String)? in
                let kv = pair.split(separator: "=", maxSplits: 1); guard kv.count == 2 else { return nil }
                return (String(kv[0]), String(kv[1]))
            })
            if let token = params["access_token"], !token.isEmpty {
                credentials.anilistAccessToken = token
                await saveCredentials(credentials)
                message = "AniList connected successfully!"
            }
            return
        }
        guard url.scheme == "omniplay", url.host == "trakt", url.path == "/oauth" else { return }
        let q = comps?.queryItems ?? []
        if let code = q.first(where: { $0.name == "code" })?.value, !code.isEmpty {
            do {
                let next = try await repos.trakt.exchangeAuthorizationCode(credentials, code: code)
                await saveTraktConnection(next)
            } catch { traktConnecting = false; message = "Trakt sign in failed: \(error)" }
        }
    }

    private func saveTraktConnection(_ next: ApiCredentials) async {
        var withProfile = next
        if let p = try? await repos.trakt.fetchUserSettings(next) { withProfile = p }
        credentials = withProfile
        credentialsStore.save(withProfile)
        pendingTraktState = nil; traktConnecting = false
        // Auto-restore backup on first login.
        if let payload = await repos.trakt.fetchRemoteSettings(withProfile)?.trimmed, !payload.isEmpty,
           let data = Data(base64Encoded: payload),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var c = withProfile
            if let v = obj["tmdb_token"] as? String { c.tmdbToken = v }
            if let v = obj["tvdb_api_key"] as? String { c.tvdbApiKey = v }
            if let v = obj["tvdb_pin"] as? String { c.tvdbPin = v }
            if let v = obj["pixeldrain_api_key"] as? String { c.pixeldrainApiKey = v }
            if let v = obj["anilist_access_token"] as? String { c.anilistAccessToken = v }
            credentials = c; credentialsStore.save(c)
            if let s = obj["settings"] as? [String: Any] { settings = UserSettings.fromJSON(s); settingsStore.saveSettings(settings) }
            if let raw = obj["watch_history"] as? [[String: Any]] { mergeProgress(raw.compactMap { WatchProgress.fromJSON($0) }, preferRemoteTime: true) }
        }
        message = withProfile.traktUsername.isEmpty ? "Trakt connected." : "Trakt connected as \(withProfile.traktUsername)."
        await refreshTraktWatchlist()
    }

    // MARK: - Hero picks

    func clearHeroCache() { heroPicksCache = [] }

    var heroPicks: [MediaItem] {
        if !heroPicksCache.isEmpty { return heroPicksCache }
        guard !categories.isEmpty else { return [] }
        // Dedupe by CONTENT, not just the source-specific id — the same title
        // arrives from TMDB/Trakt/VidSrc with different ids, so keying on id let
        // duplicates through. Key on type + tmdbId/imdbId/title instead.
        var byKey: [String: MediaItem] = [:]
        for c in categories where c.type != .liveTv && c.type != .anime {
            for item in c.items where !item.isAnime {
                let key = "\(item.type.rawValue):" + (item.tmdbId.map(String.init) ?? item.imdbId ?? item.title.lowercased())
                if byKey[key] == nil { byKey[key] = item }
            }
        }
        let withBackdrops = byKey.values.filter { $0.heroBackdropUrl != nil && !$0.overview.isEmpty }
        let pool = (withBackdrops.isEmpty ? byKey.values.filter { $0.posterUrl != nil || $0.backdropUrl != nil } : withBackdrops)
            .sorted { heroScore($0) > heroScore($1) }
        let candidates = Array(pool.prefix(25)).shuffled()
        heroPicksCache = Array(candidates.prefix(10))
        return heroPicksCache
    }
    private func heroScore(_ item: MediaItem) -> Double {
        let voteWeight = log(Double(max(item.voteCount, 1)) + 1)
        return item.rating * voteWeight + (item.heroBackdropUrl != nil ? 4 : 0)
    }

    // MARK: - Helpers

    private func nonEmptyCategories(_ cats: [MediaCategory]) -> [MediaCategory] {
        cats.map { c in
            var n = c; n.items = c.items.filter { $0.posterPath != nil || $0.backdropPath != nil }; return n
        }.filter { !$0.items.isEmpty }
    }
    private func enrichMetadataCategories(_ cats: [MediaCategory], maxItems: Int) async -> [MediaCategory] {
        guard credentials.hasTmdb else { return cats }
        var out: [MediaCategory] = []
        for c in cats {
            var items: [MediaItem] = []
            for (i, item) in c.items.enumerated() {
                if i < maxItems && canEnrich(item) {
                    items.append(await repos.tmdb.fetchDetails(item, credentials: credentials, settings: settings) ?? item)
                } else { items.append(item) }
            }
            var n = c; n.items = items; out.append(n)
        }
        return out
    }
    private func canEnrich(_ item: MediaItem) -> Bool {
        guard item.tmdbId != nil, item.type != .liveTv else { return false }
        return item.posterPath == nil || item.backdropPath == nil || item.overview.isEmpty || item.voteCount == 0
    }
    private func categoryErrorMessage(_ cats: [MediaCategory], _ service: String) -> String? {
        for c in cats { if let e = c.error, !e.isEmpty { return e } }
        return cats.isEmpty ? "\(service) did not return rows. Showing cached rows." : nil
    }
    private func safeRefreshMessage(_ service: String, _ error: Error) -> String {
        let t = "\(error)"
        if t.contains("401") || t.contains("403") { return "\(service) rejected the saved credentials. Check Settings." }
        if t.contains("429") { return "\(service) rate-limited this refresh. Showing cached rows." }
        if t.contains("timed out") || t.contains("unreachable") || t.contains("network") { return "\(service) is temporarily unreachable. Showing cached rows." }
        return "\(service) refresh failed. Showing cached rows."
    }
    private func randomState() -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<32).map { _ in chars.randomElement()! })
    }
}

// JSON conversion helpers for the Trakt backup payload.
extension UserSettings {
    func toJSON() -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(self))) as? [String: Any] ?? [:]
    }
    static func fromJSON(_ json: [String: Any]) -> UserSettings {
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let s = try? JSONDecoder().decode(UserSettings.self, from: data) else { return UserSettings() }
        return s
    }
}
extension WatchProgress {
    func toJSON() -> [String: Any] {
        var j: [String: Any] = [
            "itemId": itemId, "title": title, "type": type.rawValue,
            "positionMs": positionMs, "durationMs": durationMs, "lastWatchedAt": lastWatchedAt,
        ]
        if let id { j["id"] = id }
        if let posterPath { j["posterPath"] = posterPath }
        if let backdropPath { j["backdropPath"] = backdropPath }
        if let seasonNumber { j["seasonNumber"] = seasonNumber }
        if let episodeNumber { j["episodeNumber"] = episodeNumber }
        if let episodeTitle { j["episodeTitle"] = episodeTitle }
        return j
    }
    static func fromJSON(_ j: [String: Any]) -> WatchProgress? {
        guard let itemId = j["itemId"] as? String else { return nil }
        return WatchProgress(
            id: j["id"] as? Int, itemId: itemId,
            title: j["title"] as? String ?? "Untitled",
            type: MediaType(rawValue: j["type"] as? String ?? "movie") ?? .movie,
            posterPath: j["posterPath"] as? String, backdropPath: j["backdropPath"] as? String,
            seasonNumber: j["seasonNumber"] as? Int, episodeNumber: j["episodeNumber"] as? Int,
            episodeTitle: j["episodeTitle"] as? String,
            positionMs: j["positionMs"] as? Int ?? 0, durationMs: j["durationMs"] as? Int ?? 0,
            lastWatchedAt: j["lastWatchedAt"] as? Int ?? Int(Date().timeIntervalSince1970 * 1000))
    }
}
