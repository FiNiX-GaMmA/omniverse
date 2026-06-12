import Foundation

// MARK: - One Pace shared models

/// Shared One Pace data models + resolution logic, used by both `OnePaceScreen`
/// (browse/play) and `HomeScreen` (Continue Watching → resume playback).
/// Faithful port of `one_pace_screen.dart`.

struct OnePaceArc: Identifiable {
    let title: String
    let slug: String
    let description: String
    let chapters: String
    let animeEpisodes: String
    let backdropUrl: String
    let playlistGroups: [OnePacePlaylistGroup]
    var id: String { slug.isEmpty ? title : slug }
}

struct OnePacePlaylistGroup {
    let sub: String
    let dub: String
    let playlists: [OnePacePlaylist]
}

struct OnePacePlaylist {
    let id: String
    let resolution: Int
}

struct OnePaceEpisode: Identifiable {
    let id: String
    let name: String
    let size: Int
    let episodeNumber: Int
    let cleanTitle: String
}

enum OnePaceError: Error, CustomStringConvertible {
    case message(String)
    var description: String { if case .message(let m) = self { return m }; return "One Pace error" }
}

/// 14 subtitle languages, ported verbatim from `one_pace_screen.dart` `_subLanguages`.
let onePaceSubLanguages: [(code: String, name: String)] = [
    ("en", "English"),
    ("en cc", "English (CC)"),
    ("alternate en", "English (Alternate)"),
    ("ar", "Arabic (العربية)"),
    ("de", "German (Deutsch)"),
    ("es", "Spanish (Español)"),
    ("fr", "French (Français)"),
    ("it", "Italian (Italiano)"),
    ("pt", "Portuguese (Português)"),
    ("ru", "Russian (Русский)"),
    ("tr", "Turkish (Türkçe)"),
    ("cs", "Czech (Čeština)"),
    ("fi", "Finnish (Suomi)"),
    ("pl", "Polish (Polski)"),
]

/// Default One Pace subtitle repo folders, ported verbatim (refreshed live on load).
let onePaceRepoFoldersDefault = [
    "00 Cover Stories and Specials", "01 Romance Dawn", "02 Orange Town", "03 Syrup Village",
    "04 Gaimon", "05 Baratie", "06 Arlong Park", "07 Loguetown", "08 Reverse Mountain",
    "09 Whisky Peak", "10 Little Garden", "11 Drum Island", "12 Alabasta", "13 Jaya",
    "14 Skypiea", "16 Water Seven", "17 Enies Lobby", "19 Thriller Bark", "22 Impel Down",
    "23 Marineford", "24 Post War", "25 Return to Sabaody", "26 Fishman Island", "27 Punk Hazard",
    "28 Dressrosa", "29 Zou", "30 Whole Cake Island", "31 Reverie", "32 Wano", "33 Egghead",
]

// MARK: - Resolver

/// Stateless One Pace resolution shared by the browse screen and the Home
/// "Continue Watching" resume path. All methods are faithful ports of the
/// corresponding logic in `one_pace_screen.dart`.
enum OnePaceResolver {

    /// Fully-resolved playback target for a One Pace episode, ready to feed
    /// straight into `PlayerScreen`.
    struct Resolved {
        let title: String
        let url: String
        let subtitleUrl: String
        let item: MediaItem
        let episode: MediaEpisode
        let aniSkipEpisode: Int
    }

    // MARK: Arcs

    static func fetchArcs() async throws -> [OnePaceArc] {
        guard let url = URL(string: "https://onepace.net/en/watch") else { throw OnePaceError.message("Bad URL") }
        let resp = try await Http.shared.request(url, headers: ["User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"])
        guard resp.ok else { throw OnePaceError.message("Failed to load One Pace website: \(resp.status)") }
        let html = resp.bodyString

        // Find the self.__next_f.push([1,"..."]) block containing "playlistGroups".
        guard let regex = try? NSRegularExpression(pattern: "self\\.__next_f\\.push\\(\\[1,\"(.*?)\"\\]\\)", options: [.dotMatchesLineSeparators]) else {
            throw OnePaceError.message("Could not parse One Pace data block.")
        }
        let range = NSRange(html.startIndex..., in: html)
        var targetBlock: String?
        regex.enumerateMatches(in: html, range: range) { match, _, stop in
            guard let match, let r = Range(match.range(at: 1), in: html) else { return }
            let group = String(html[r])
            if group.contains("playlistGroups") { targetBlock = group; stop.pointee = true }
        }
        guard let block = targetBlock else { throw OnePaceError.message("Could not parse One Pace data block.") }

        let unescaped = unescapeNextJsString(block)
        var idx = unescaped.range(of: "{\"timeline\"")?.lowerBound
        if idx == nil { idx = unescaped.range(of: "{\"data\"")?.lowerBound }
        guard let startIdx = idx else { throw OnePaceError.message("Could not unescape data block.") }

        let jsonChunk = extractBalancedJson(unescaped, from: startIdx)
        guard let jsonData = jsonChunk.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw OnePaceError.message("Could not decode One Pace JSON.")
        }
        let data = (decoded["data"] as? [String: Any]) ?? decoded
        guard let timeline = data["timeline"] as? [String: Any],
              let segments = timeline["segments"] as? [Any] else { throw OnePaceError.message("No timeline segments.") }

        var result: [OnePaceArc] = []
        for case let seg as [String: Any] in segments {
            let title = seg["title"] as? String ?? ""
            let slug = seg["slug"] as? String ?? ""
            let description = seg["description"] as? String ?? ""
            let chapters = seg["chapters"] as? String ?? ""
            let animeEpisodes = seg["episodes"] as? String ?? ""

            var backdropUrl = ""
            if let backdrops = seg["backdrops"] as? [Any],
               let first = backdrops.first as? [String: Any],
               let src = first["src"] as? String, !src.isEmpty {
                backdropUrl = src.hasPrefix("http") ? src : "https://onepace.net\(src)"
            }

            var groups: [OnePacePlaylistGroup] = []
            if let playlistGroups = seg["playlistGroups"] as? [Any] {
                for case let pg as [String: Any] in playlistGroups {
                    let sub = pg["sub"] as? String ?? ""
                    let dub = pg["dub"] as? String ?? ""
                    var playlists: [OnePacePlaylist] = []
                    if let lists = pg["playlists"] as? [Any] {
                        for case let pl as [String: Any] in lists {
                            let id = pl["id"] as? String ?? ""
                            let res = (pl["resolution"] as? Int) ?? Int((pl["resolution"] as? Double) ?? 0)
                            playlists.append(OnePacePlaylist(id: id, resolution: res))
                        }
                    }
                    groups.append(OnePacePlaylistGroup(sub: sub, dub: dub, playlists: playlists))
                }
            }
            result.append(OnePaceArc(title: title, slug: slug, description: description,
                                     chapters: chapters, animeEpisodes: animeEpisodes,
                                     backdropUrl: backdropUrl, playlistGroups: groups))
        }
        return result
    }

    // MARK: Episodes

    static func fetchEpisodes(listId: String) async throws -> [OnePaceEpisode] {
        guard let url = URL(string: "https://pixeldrain.net/api/list/\(listId)") else { throw OnePaceError.message("Bad list id") }
        let resp = try await Http.shared.request(url)
        guard resp.ok else { throw OnePaceError.message("Failed to load Pixeldrain server files") }
        guard let files = resp.jsonObject().arr("files") else { return [] }

        var episodes: [OnePaceEpisode] = []
        for (i, f) in files.enumerated() {
            guard let file = f as? [String: Any] else { continue }
            let id = file["id"] as? String ?? ""
            let name = file["name"] as? String ?? ""
            let size = (file["size"] as? Int) ?? Int((file["size"] as? Double) ?? 0)

            // Clean title: strip [One Pace], [bracketed] tags, .mp4.
            var clean = name
            clean = clean.replacingOccurrences(of: "\\[One\\s+Pace\\]", with: "", options: [.regularExpression, .caseInsensitive])
            clean = clean.replacingOccurrences(of: "\\[[a-zA-Z0-9\\s-]+\\]", with: "", options: .regularExpression)
            clean = clean.replacingOccurrences(of: "\\.mp4$", with: "", options: [.regularExpression, .caseInsensitive])
            clean = clean.trimmed
            if clean.hasPrefix("]") { clean = String(clean.dropFirst()).trimmed }

            episodes.append(OnePaceEpisode(id: id, name: name, size: size, episodeNumber: i + 1,
                                           cleanTitle: clean.isEmpty ? "Episode \(i + 1)" : clean))
        }
        return episodes
    }

    /// Picks the playlist group's best (highest-resolution) list id for the
    /// chosen audio track. Mirrors `loadEpisodes` selection in the Dart screen.
    static func bestListId(in pg: OnePacePlaylistGroup) -> String? {
        pg.playlists.sorted { $0.resolution > $1.resolution }.first?.id
    }

    /// Index of the English-subbed (Japanese audio) playlist group, else 0.
    /// Used by the resume path to prefer the English-sub track.
    static func preferredEnglishSubGroupIndex(_ arc: OnePaceArc) -> Int {
        if let idx = arc.playlistGroups.firstIndex(where: { $0.sub.lowercased() == "en" && $0.dub.lowercased() == "ja" }) {
            return idx
        }
        if let idx = arc.playlistGroups.firstIndex(where: { $0.sub.lowercased() == "en" }) {
            return idx
        }
        return 0
    }

    // MARK: Subtitles (HEAD-probes the one-pace-public-subtitles repo)

    static func loadRepoFolders() async -> [String] {
        guard let url = URL(string: "https://api.github.com/repos/one-pace/one-pace-public-subtitles/contents/main"),
              let resp = try? await Http.shared.request(url, headers: ["User-Agent": "Mozilla/5.0"], timeout: 3), resp.ok,
              let data = (try? resp.json()) as? [Any] else { return onePaceRepoFoldersDefault }
        let live = data.compactMap { item -> String? in
            guard let m = item as? [String: Any], (m["type"] as? String) == "dir" else { return nil }
            return m["name"] as? String
        }
        return live.isEmpty ? onePaceRepoFoldersDefault : live
    }

    static func resolveSubtitleUrl(arcTitle: String, epNum: Int, langCode: String,
                                   repoFolders: [String]) async throws -> String {
        let episodePadded = String(format: "%02d", epNum)
        let normalizedArc = arcTitle.lowercased().replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)

        func normalize(_ s: String) -> String { s.lowercased().replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression) }

        var matchedFolder: String?
        for folder in repoFolders {
            let nf = normalize(folder)
            if nf.contains(normalizedArc) || normalizedArc.contains(nf) { matchedFolder = folder; break }
        }
        if matchedFolder == nil, let firstWord = arcTitle.split(separator: " ").first {
            let fw = normalize(String(firstWord))
            for folder in repoFolders where normalize(folder).contains(fw) { matchedFolder = folder; break }
        }
        guard let folder = matchedFolder else { return "" }

        let encodedFolder = folder.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? folder
        func candidate(_ suffix: String) -> String {
            "https://raw.githubusercontent.com/one-pace/one-pace-public-subtitles/main/main/\(encodedFolder)/\(episodePadded)/\(normalizedArc)%20\(episodePadded)%20\(suffix.replacingOccurrences(of: " ", with: "%20")).ass"
        }
        let candidates = [candidate(langCode), candidate("en"), candidate("en cc")]
        for url in candidates {
            if let u = URL(string: url), let resp = try? await Http.shared.request(u, method: "HEAD", timeout: 1), resp.status == 200 {
                return url
            }
        }
        return candidate(langCode)
    }

    // MARK: Stream URL (GameDrive bypass proxy, with direct fallback)

    /// Builds the primary stream URL for a Pixeldrain file id: the GameDrive
    /// bypass proxy when reachable (~2s), otherwise the direct pixeldrain.net
    /// URL + API key. Parity with the Dart `play()` URL construction.
    static func streamUrl(fileId: String, apiKey: String) async -> String {
        let direct = "https://pixeldrain.net/api/file/\(fileId)" + (apiKey.isEmpty ? "" : "?api_key=\(apiKey)")

        // GameDrive userscript bypass (faster Pixeldrain loading): fetch the
        // proxy list and use the first *reachable* proxy, like the userscript
        // does. Falls back to the direct Pixeldrain URL (+api_key) if none work.
        guard let proxyURL = URL(string: "https://pixeldrain-bypass.gamedrive.org/api/proxy.json"),
              let resp = try? await Http.shared.request(proxyURL, timeout: 2), resp.ok,
              let proxies = resp.jsonObject().arr("proxies")?.compactMap({ $0 as? String }) else { return direct }
        for raw in proxies.prefix(3) {
            let p = raw.trimmed
            guard !p.isEmpty else { continue }
            let clean = p.hasPrefix("http") ? p : "https://\(p)"
            let normalized = clean.hasSuffix("/") ? clean : "\(clean)/"
            let candidate = "\(normalized)\(fileId)"
            if let u = URL(string: candidate),
               let head = try? await Http.shared.request(u, method: "HEAD", timeout: 1.5), head.status < 500 {
                return candidate
            }
        }
        return direct
    }

    // MARK: AniSkip mapping

    /// Maps a One Pace episode index to the equivalent original One Piece anime
    /// episode for AniSkip (parity with `_getMappedAnimeEpisode`).
    static func mappedAnimeEpisode(_ episodesStr: String, epIndex: Int, totalEpisodes: Int) -> Int {
        var epNumbers: [Int] = []
        for part in episodesStr.split(separator: ",") {
            let clean = part.trimmingCharacters(in: .whitespaces)
            if clean.contains("-") {
                let rangeParts = clean.split(separator: "-")
                if rangeParts.count == 2, let start = Int(rangeParts[0].trimmingCharacters(in: .whitespaces)), let end = Int(rangeParts[1].trimmingCharacters(in: .whitespaces)) {
                    epNumbers.append(contentsOf: stride(from: start, through: end, by: 1))
                }
            } else if let val = Int(clean) {
                epNumbers.append(val)
            }
        }
        if epNumbers.isEmpty { return 1 }
        if totalEpisodes <= 1 { return epNumbers.first! }
        let ratio = Double(epIndex - 1) / Double(totalEpisodes - 1)
        let targetIndex = min(max(Int((ratio * Double(epNumbers.count - 1)).rounded()), 0), epNumbers.count - 1)
        return epNumbers[targetIndex]
    }

    // MARK: Audio group label (parity with _getAudioGroupLabel)

    static func audioGroupLabel(_ pg: OnePacePlaylistGroup) -> String {
        let sub = pg.sub.lowercased()
        let dub = pg.dub.lowercased()
        if sub == "en" && dub == "ja" { return "Japanese Audio (English Subs)" }
        if sub == "en" && dub == "en" { return "English Dub (with Closed Captions)" }
        if dub == "en" { return "English Dub (No Subs)" }
        let subLabel = sub == "$undefined" ? "No Subs" : "\(sub.uppercased()) Subs"
        let dubLabel = "\(dub.uppercased()) Audio"
        return "\(dubLabel) (\(subLabel))"
    }

    // MARK: Build the PlayerScreen-ready target

    /// Builds the dummy `MediaItem` / `MediaEpisode` and final resolved target for
    /// a chosen arc + episode. Faithful to the Dart `play()` construction.
    static func makeResolved(arc: OnePaceArc, seasonNumber: Int, episode: OnePaceEpisode,
                             totalEpisodes: Int, subtitleUrl: String, streamUrl: String) -> Resolved {
        let dummyItem = MediaItem(
            id: "onepace:anime:21",
            type: .series,
            title: "One Pace",
            overview: arc.description,
            posterPath: "/k73H7nbaGo76tH7nI1gG6P3g6W4Z.jpg",
            backdropPath: arc.backdropUrl.replacingOccurrences(of: "https://onepace.net", with: ""),
            genres: ["Action", "Adventure", "Animation", "Fantasy", "Comedy"])

        let mapped = mappedAnimeEpisode(arc.animeEpisodes, epIndex: episode.episodeNumber, totalEpisodes: totalEpisodes)

        let playerEpisode = MediaEpisode(
            seasonNumber: seasonNumber,
            episodeNumber: episode.episodeNumber,
            title: episode.cleanTitle,
            overview: "Covered Manga Chapters: \(arc.chapters)\nCovered Anime Episodes: \(arc.animeEpisodes)")

        return Resolved(
            title: "One Pace • \(arc.title) • \(episode.cleanTitle)",
            url: streamUrl, subtitleUrl: subtitleUrl, item: dummyItem,
            episode: playerEpisode, aniSkipEpisode: mapped)
    }

    /// End-to-end resolution for the Continue Watching resume path: fetch arcs,
    /// pick the arc for `seasonNumber`, pick the English-sub (else first) track,
    /// fetch episodes, find the episode by number, resolve the subtitle, build the
    /// GameDrive-primary stream URL, and return a `Resolved` target. Throws if any
    /// required step fails so the caller can fall back to opening the One Pace
    /// screen.
    static func resolveForResume(seasonNumber: Int, episodeNumber: Int, apiKey: String,
                                 subLanguageCode: String = "en") async throws -> Resolved {
        let arcs = try await fetchArcs()
        guard seasonNumber >= 1, seasonNumber <= arcs.count else {
            throw OnePaceError.message("Season \(seasonNumber) out of range.")
        }
        let arc = arcs[seasonNumber - 1]
        guard !arc.playlistGroups.isEmpty else { throw OnePaceError.message("No playlist groups for arc.") }

        let groupIndex = preferredEnglishSubGroupIndex(arc)
        let pg = arc.playlistGroups[groupIndex]
        guard let listId = bestListId(in: pg) else { throw OnePaceError.message("No playlists in track.") }

        let episodes = try await fetchEpisodes(listId: listId)
        guard let episode = episodes.first(where: { $0.episodeNumber == episodeNumber }) else {
            throw OnePaceError.message("Episode \(episodeNumber) not found.")
        }

        let repoFolders = await loadRepoFolders()
        let subUrl = (try? await resolveSubtitleUrl(arcTitle: arc.title, epNum: episode.episodeNumber,
                                                    langCode: subLanguageCode, repoFolders: repoFolders)) ?? ""
        let url = await streamUrl(fileId: episode.id, apiKey: apiKey)

        return makeResolved(arc: arc, seasonNumber: seasonNumber, episode: episode,
                            totalEpisodes: episodes.count, subtitleUrl: subUrl, streamUrl: url)
    }

    // MARK: String helpers

    static func unescapeNextJsString(_ escaped: String) -> String {
        escaped
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\r", with: "\r")
            .replacingOccurrences(of: "\\t", with: "\t")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    static func extractBalancedJson(_ text: String, from startIdx: String.Index) -> String {
        var balance = 0
        var i = startIdx
        while i < text.endIndex {
            let c = text[i]
            if c == "{" { balance += 1 }
            else if c == "}" {
                balance -= 1
                if balance == 0 { return String(text[startIdx...i]) }
            }
            i = text.index(after: i)
        }
        return String(text[startIdx...])
    }
}
