import SwiftUI

/// Faithful port of `live_tv_screen.dart` + the live-TV scan pipeline from
/// `app_state.dart` (`startLiveTvScan`). Scanning is manual; the iptv-org
/// channels.json + streams.json join, the 21 prebuilt m3u playlists, the
/// yarrlist directory, and tv247.biz are aggregated, HEAD-probed, deduped, and
/// grouped by category. Direct streams open in PlayerScreen; page URLs open in
/// WebEmbedPlayerScreen with a Referer header.
struct LiveTvScreen: View {
    @Environment(AppState.self) private var state

    @State private var scanProgress: Double = 0
    @State private var scanning = false
    @State private var scanTask: Task<Void, Never>?

    // Playback presentation
    @State private var directEntry: LiveTvEntry?
    @State private var embedEntry: LiveTvEntry?

    private var entries: [LiveTvEntry] {
        state.liveTv.filter { $0.url.lowercased().contains(".m3u8") || $0.url.contains("tv247.biz") }
    }

    var body: some View {
        Group {
            if scanning || state.isScanningLiveTv {
                scanningView
            } else if !state.hasScannedLiveTv || entries.isEmpty {
                scanPrompt
            } else {
                channelList
            }
        }
        .liquidScaffold()
        .fullScreenCover(item: $directEntry) { entry in
            PlayerScreen(title: entry.title, url: entry.url, headers: entry.headers,
                         item: nil, episode: nil, subtitleUrl: "", startPositionMs: 0, aniSkipEpisode: nil)
        }
        .fullScreenCover(item: $embedEntry) { entry in
            let referer = entry.headers["Referer"] ?? "https://tv247.biz/"
            WebEmbedPlayerScreen(title: entry.title, url: entry.url, headers: ["Referer": referer], item: nil)
        }
    }

    // MARK: - States

    private var scanPrompt: some View {
        let country = state.settings.liveTvCountry
        let countryName = country.lowercased() == "all" ? "Global" : country.uppercased()
        return VStack(spacing: 0) {
            Circle()
                .fill(LiquidColors.cyan.opacity(0.12))
                .overlay(Circle().strokeBorder(LiquidColors.cyan.opacity(0.28), lineWidth: 2))
                .frame(width: 120, height: 120)
                .overlay(Image(systemName: "tv").font(.system(size: 64)).foregroundStyle(LiquidColors.cyan))
                .padding(.bottom, 24)
            Text("IPTV Channel Scanner").font(.system(size: 28, weight: .black)).foregroundStyle(.white)
                .padding(.bottom, 8)
            Text("Scan and verify active Live TV streams for country: \(countryName)\n(Configurable in Settings)")
                .font(.system(size: 15)).foregroundStyle(.white.opacity(0.6)).lineSpacing(2)
                .multilineTextAlignment(.center)
                .padding(.bottom, 28)
            Button { startScan() } label: {
                Label("Start Channel Scan", systemImage: "play.circle.fill")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 24).padding(.vertical, 14)
                    .background(LiquidColors.cyan.opacity(0.24), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scanningView: some View {
        VStack(spacing: 0) {
            ProgressView().controlSize(.large).tint(LiquidColors.cyan).padding(.bottom, 28)
            Text("Scanning Frequencies...").font(.system(size: 22, weight: .black)).foregroundStyle(.white).padding(.bottom, 10)
            Text("Probing stream links in parallel with high-speed HEAD checks.\nFiltering active, responsive, and working feeds...")
                .font(.system(size: 15)).foregroundStyle(.white.opacity(0.6)).lineSpacing(2)
                .multilineTextAlignment(.center)
                .padding(.bottom, 28)
            ProgressView(value: max(0, min(1, scanProgress)))
                .progressViewStyle(.linear)
                .tint(LiquidColors.cyan)
                .frame(width: 320)
                .padding(.bottom, 12)
            Text("\(Int(scanProgress * 100))% Complete")
                .font(.system(size: 17, weight: .bold)).foregroundStyle(LiquidColors.cyan)
                .padding(.bottom, 28)
            Button { cancelScan() } label: {
                Label("Cancel Scan", systemImage: "xmark.circle").font(.system(size: 15, weight: .semibold)).foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var channelList: some View {
        let grouped = groupByCategory(entries)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: 16)
                ForEach(grouped, id: \.key) { group in
                    LiveTvCategoryRow(title: group.key, entries: group.value) { entry in
                        openPlayer(entry)
                    }
                }
                Color.clear.frame(height: 54)
            }
        }
        .scrollIndicators(.hidden)
        .refreshable { await runScan() }
    }

    // MARK: - Grouping (parity with _groupByCategory / _categoriesFor)

    private func groupByCategory(_ list: [LiveTvEntry]) -> [(key: String, value: [LiveTvEntry])] {
        var grouped: [String: [LiveTvEntry]] = [:]
        for entry in list {
            for cat in categoriesFor(entry) { grouped[cat, default: []].append(entry) }
        }
        let preferred = ["News", "Entertainment", "Movies", "Sports", "Music"]
        let sortedKeys = grouped.keys.sorted { a, b in
            let ai = preferred.firstIndex(of: a)
            let bi = preferred.firstIndex(of: b)
            if ai != nil || bi != nil { return (ai ?? 999) < (bi ?? 999) }
            return a < b
        }
        return sortedKeys.map { key in
            (key, grouped[key]!.sorted { $0.title < $1.title })
        }
    }

    private func openPlayer(_ entry: LiveTvEntry) {
        if entry.url.contains("embed") || entry.url.contains("tv247.biz") {
            embedEntry = entry
        } else {
            directEntry = entry
        }
    }

    // MARK: - Scan driver

    private func startScan() { scanTask = Task { await runScan() } }

    private func cancelScan() {
        scanning = false
        state.isScanningLiveTv = false
        scanTask?.cancel()
    }

    @MainActor
    private func runScan() async {
        scanning = true
        state.isScanningLiveTv = true
        scanProgress = 0
        state.liveTvScanProgress = 0
        defer {
            scanning = false
            state.isScanningLiveTv = false
        }

        var parsed: [LiveTvEntry] = []

        // 1) iptv-org channels.json + streams.json join.
        parsed.append(contentsOf: await fetchIptvOrgApi())

        // 2) 21 prebuilt iptv-org m3u playlists.
        parsed.append(contentsOf: await fetchM3uPlaylists())

        // 3) Yarrlist directory playlists.
        if let yarrlistEntries = try? await state.repos.yarrlist.fetchLiveTvDirectory() {
            let lists: [[LiveTvEntry]] = await withTaskGroup(of: [LiveTvEntry].self) { group in
                for entry in yarrlistEntries {
                    let u = entry.url
                    if u.hasSuffix(".m3u") || u.hasSuffix(".m3u8") || u.contains("get.php") || u.contains("m3u") {
                        group.addTask {
                            let source = LiveTvSource(id: "iptv-yarrlist-\(u.hashValue)", name: entry.title, url: u, enabled: true)
                            return (try? await state.repos.liveTv.fetchSource(source)) ?? []
                        }
                    }
                }
                var acc: [[LiveTvEntry]] = []
                for await r in group { acc.append(r) }
                return acc
            }
            for res in lists where !res.isEmpty {
                parsed.append(contentsOf: res)
            }
        }

        let pool = dedupe(parsed)

        let tv247 = await fetchTv247Channels()

        if pool.isEmpty && tv247.isEmpty {
            state.hasScannedLiveTv = false
            state.message = "Scan complete. No channels found."
            return
        }

        // 3) HEAD-probe in chunks of 25 with progress.
        var working: [LiveTvEntry] = []
        let total = pool.count
        let chunkSize = 25
        var i = 0
        while i < total {
            if Task.isCancelled || !state.isScanningLiveTv { break }
            let chunk = Array(pool[i..<min(i + chunkSize, total)])
            let results: [LiveTvEntry?] = await withTaskGroup(of: LiveTvEntry?.self) { group in
                for entry in chunk {
                    group.addTask { await headOk(entry) ? entry : nil }
                }
                var acc: [LiveTvEntry?] = []
                for await r in group { acc.append(r) }
                return acc
            }
            working.append(contentsOf: results.compactMap { $0 })
            i += chunkSize
            scanProgress = Double(min(i, total)) / Double(total)
            state.liveTvScanProgress = scanProgress
        }

        if !working.isEmpty || !tv247.isEmpty {
            let finalChannels = await filterWorkingChannels(working)
            var merged = finalChannels + tv247
            merged.sort { a, b in
                if a.region != b.region { return a.region < b.region }
                return a.title < b.title
            }
            state.liveTv = merged
            state.hasScannedLiveTv = true
            state.message = "Scan complete! Found \(merged.count) active channels."
        } else {
            state.hasScannedLiveTv = false
            state.message = "Scan complete. None of the scanned channels responded."
        }
    }

    // MARK: - iptv-org API (channels.json + streams.json)

    private func fetchIptvOrgApi() async -> [LiveTvEntry] {
        guard let chURL = URL(string: "https://iptv-org.github.io/api/channels.json"),
              let stURL = URL(string: "https://iptv-org.github.io/api/streams.json") else { return [] }
        async let chResp = try? Http.shared.request(chURL, timeout: 15)
        async let stResp = try? Http.shared.request(stURL, timeout: 15)
        guard let ch = await chResp, let st = await stResp, ch.ok, st.ok,
              let channels = (try? ch.json()) as? [Any],
              let streams = (try? st.json()) as? [Any] else { return [] }

        var channelMap: [String: [String: Any]] = [:]
        for case let item as [String: Any] in channels {
            if let id = item["id"] as? String { channelMap[id] = item }
        }

        var out: [LiveTvEntry] = []
        for case let stream as [String: Any] in streams {
            guard let channelId = stream["channel"] as? String,
                  let url = stream["url"] as? String,
                  url.lowercased().contains(".m3u8") else { continue }
            let info = channelMap[channelId]
            let languages = (info?["languages"] as? [Any])?.compactMap { $0 as? String } ?? []
            let hasTarget = languages.contains("eng") || languages.contains("hin") || languages.contains("ben")
            guard hasTarget else { continue }

            let title = (info?["name"] as? String) ?? channelId
            let logoUrl = "https://iptv-org.github.io/api/logos/\(channelId).png"
            let categories = (info?["categories"] as? [Any])?.compactMap { $0 as? String } ?? []

            let lowerTitle = title.lowercased()
            let isWestBengal = languages.contains("ben")
                || lowerTitle.contains("bengal") || lowerTitle.contains("kolkata") || lowerTitle.contains("bangla")

            var finalCategories: [String] = []
            if isWestBengal { finalCategories.append("West Bengal / Bangla") }
            if !categories.isEmpty { finalCategories.append(contentsOf: categories) }
            else if !isWestBengal { finalCategories.append("General") }

            let genreString = finalCategories.map { $0.trimmed }.filter { !$0.isEmpty }.joined(separator: ";")

            var headers: [String: String] = [:]
            if let ref = stream["http_referrer"] as? String, !ref.isEmpty { headers["Referer"] = ref }
            if let ua = stream["user_agent"] as? String, !ua.isEmpty { headers["User-Agent"] = ua }
            else { headers["User-Agent"] = chromeUA }

            out.append(LiveTvEntry(title: title, url: url, source: "iptv-org",
                                   region: genreString.isEmpty ? "General" : genreString,
                                   language: "", logoUrl: logoUrl, headers: headers))
        }
        return out
    }

    // MARK: - 21 prebuilt m3u playlists

    private let m3uPlaylistUrls = [
        // Free-TV/IPTV curated playlist (https://github.com/Free-TV/IPTV) — primary.
        "https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8",
        "https://iptv-org.github.io/iptv/languages/eng.m3u",
        "https://iptv-org.github.io/iptv/countries/in.m3u",
        "https://iptv-org.github.io/iptv/countries/us.m3u",
        "https://iptv-org.github.io/iptv/countries/gb.m3u",
        "https://iptv-org.github.io/iptv/categories/news.m3u",
        "https://iptv-org.github.io/iptv/categories/movies.m3u",
        "https://iptv-org.github.io/iptv/categories/sports.m3u",
        "https://iptv-org.github.io/iptv/categories/entertainment.m3u",
        "https://iptv-org.github.io/iptv/categories/music.m3u",
        "https://iptv-org.github.io/iptv/categories/kids.m3u",
        "https://iptv-org.github.io/iptv/categories/documentary.m3u",
        "https://iptv-org.github.io/iptv/categories/comedy.m3u",
        "https://iptv-org.github.io/iptv/categories/education.m3u",
        "https://iptv-org.github.io/iptv/categories/lifestyle.m3u",
        "https://iptv-org.github.io/iptv/categories/local.m3u",
        "https://iptv-org.github.io/iptv/categories/travel.m3u",
        "https://iptv-org.github.io/iptv/categories/weather.m3u",
        "https://iptv-org.github.io/iptv/categories/animation.m3u",
        "https://iptv-org.github.io/iptv/categories/drama.m3u",
        "https://iptv-org.github.io/iptv/categories/family.m3u",
        "https://iptv-org.github.io/iptv/categories/sci-fi.m3u",
    ]

    private func fetchM3uPlaylists() async -> [LiveTvEntry] {
        let lists: [[LiveTvEntry]] = await withTaskGroup(of: [LiveTvEntry].self) { group in
            for url in m3uPlaylistUrls {
                group.addTask {
                    guard let u = URL(string: url),
                          let resp = try? await Http.shared.request(u, timeout: 10), resp.ok else { return [] }
                    let entries = parseM3u(resp.bodyString, baseUrl: url, sourceLabel: "IPTV Org M3U")
                    guard !entries.isEmpty else { return [] }
                    let isEng = url.contains("languages/eng") || url.contains("countries/us") || url.contains("countries/gb")
                    let isIndia = url.contains("countries/in")
                    return entries.map { e in
                        var n = e
                        n.language = isEng ? "eng" : (isIndia ? "hin;ben;eng" : e.language)
                        return n
                    }
                }
            }
            var acc: [[LiveTvEntry]] = []
            for await r in group { acc.append(r) }
            return acc
        }

        var out: [LiveTvEntry] = []
        for res in lists where !res.isEmpty {
            let filtered = res.filter { entry in
                let t = entry.title.lowercased()
                let isBengali = t.contains("bangla") || t.contains("bengal") || t.contains("kolkata")
                    || t.contains("jalsha") || t.contains("aath") || t.contains("ananda")
                let isHindi = t.contains("star plus") || t.contains("sony sab") || t.contains("zee tv")
                    || t.contains("colors") || t.contains("dangal") || t.contains("aaj tak") || t.contains("news18 india")
                let lang = entry.language.lowercased()
                let src = entry.source.lowercased()
                return lang.contains("eng") || lang.contains("hin") || lang.contains("ben")
                    || isBengali || isHindi
                    || src.contains("india") || src.contains("us") || src.contains("uk") || src.contains("gb")
            }
            out.append(contentsOf: filtered)
        }
        return out
    }

    // MARK: - tv247.biz scrape (anchors + custom embeds)

    private func fetchTv247Channels() async -> [LiveTvEntry] {
        var entries: [LiveTvEntry] = []
        if let url = URL(string: "https://tv247.biz/tv-channels"),
           let resp = try? await Http.shared.request(url, timeout: 15), resp.ok {
            let html = resp.bodyString
            // Extract anchors: href + visible text.
            let anchorRegex = try? NSRegularExpression(pattern: "<a[^>]*href=\"([^\"]*)\"[^>]*>(.*?)</a>", options: [.dotMatchesLineSeparators, .caseInsensitive])
            let slugRegex = try? NSRegularExpression(pattern: "/tv/([^/]+)/?")
            let range = NSRange(html.startIndex..., in: html)
            anchorRegex?.enumerateMatches(in: html, range: range) { match, _, _ in
                guard let match,
                      let hrefR = Range(match.range(at: 1), in: html),
                      let textR = Range(match.range(at: 2), in: html) else { return }
                let href = String(html[hrefR]).trimmed
                let text = stripTags(String(html[textR])).trimmed
                guard !text.isEmpty, !href.isEmpty else { return }
                let hrefRange = NSRange(href.startIndex..., in: href)
                guard let sm = slugRegex?.firstMatch(in: href, range: hrefRange),
                      let slugR = Range(sm.range(at: 1), in: href) else { return }
                let slug = String(href[slugR])
                // Category derivation from the surrounding DOM isn't available without
                // a full HTML parser; default to "US Channels" (the Dart default).
                let category = "US Channels"
                let lc = category.lowercased()
                let keep = lc.contains("us") || lc.contains("india") || lc.contains("ind") || lc.contains("sport")
                guard keep, !slug.contains("chat"), !slug.contains("tv-channels") else { return }
                let mainPageUrl = "https://tv247.biz/tv/\(slug)/"
                entries.append(LiveTvEntry(title: text, url: mainPageUrl, source: "tv247.biz",
                                           region: category, language: "",
                                           logoUrl: "https://raw.githubusercontent.com/m3u8playlist/tvlogo/master/logo/\(slug.replacingOccurrences(of: "-", with: "")).png",
                                           headers: [:]))
            }
        }

        // Custom embeds (verbatim).
        let customEmbeds: [(String, String)] = [
            ("Star Sports Hindi", "https://tv247.biz/tv/star-sports-hindi/"),
            ("Sony Ten 1", "https://tv247.biz/tv/sony-ten-1/"),
        ]
        for emb in customEmbeds where !entries.contains(where: { $0.url == emb.1 }) {
            entries.append(LiveTvEntry(title: emb.0, url: emb.1, source: "tv247.biz", region: "Sports Channels",
                                       language: "",
                                       logoUrl: "https://raw.githubusercontent.com/m3u8playlist/tvlogo/master/logo/\(emb.0.lowercased().replacingOccurrences(of: " ", with: "")).png",
                                       headers: [:]))
        }
        return entries
    }

    // MARK: - Dedupe + working filter (parity with app_state helpers)

    private func dedupe(_ list: [LiveTvEntry]) -> [LiveTvEntry] {
        var seen = Set<String>()
        var result: [LiveTvEntry] = []
        for e in list {
            let key = e.url.trimmed.lowercased()
            if key.isEmpty || !seen.insert(key).inserted { continue }
            result.append(e)
        }
        return result
    }

    private func filterWorkingChannels(_ list: [LiveTvEntry]) async -> [LiveTvEntry] {
        let urlDeduped = dedupe(list)
        var grouped: [String: [LiveTvEntry]] = [:]
        for e in urlDeduped {
            let key = e.title.trimmed.lowercased()
            if key.isEmpty { continue }
            grouped[key, default: []].append(e)
        }
        var result: [LiveTvEntry] = []
        var duplicateOptionLists: [[LiveTvEntry]] = []
        for (_, options) in grouped {
            if options.count == 1 { result.append(options[0]) }
            else { duplicateOptionLists.append(options) }
        }
        if !duplicateOptionLists.isEmpty {
            let resolved: [LiveTvEntry] = await withTaskGroup(of: LiveTvEntry.self) { group in
                for options in duplicateOptionLists {
                    group.addTask { await findFirstWorkingStream(options) }
                }
                var acc: [LiveTvEntry] = []
                for await r in group { acc.append(r) }
                return acc
            }
            result.append(contentsOf: resolved)
        }
        return result
    }

    private func findFirstWorkingStream(_ options: [LiveTvEntry]) async -> LiveTvEntry {
        for entry in options where await headOk(entry) { return entry }
        return options[0]
    }

    /// HEAD probe with a 1.2s timeout; 2xx/3xx counts as working.
    private func headOk(_ entry: LiveTvEntry) async -> Bool {
        guard let url = URL(string: entry.url) else { return false }
        guard let resp = try? await Http.shared.request(url, method: "HEAD", headers: entry.headers, timeout: 1.2) else { return false }
        return resp.status >= 200 && resp.status < 400
    }
}

// MARK: - M3U parsing (parity with LiveTvSourceRepository.parseM3u)

private let chromeUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

private func parseM3u(_ content: String, baseUrl: String, sourceLabel: String) -> [LiveTvEntry] {
    guard content.trimmingCharacters(in: .whitespaces).hasPrefix("#EXTM3U") || content.contains("#EXTINF") else { return [] }
    var entries: [LiveTvEntry] = []
    var pendingTitle: String?
    var pendingLogo: String?
    var pendingGroup = ""
    var pendingHeaders: [String: String] = [:]

    for raw in content.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
        let line = String(raw).trimmed
        if line.isEmpty || line == "#EXTM3U" { continue }
        if line.hasPrefix("#EXTINF") {
            pendingTitle = titleFromExtInf(line)
            pendingLogo = attribute(line, "tvg-logo")
            pendingGroup = attribute(line, "group-title") ?? ""
            pendingHeaders.removeAll()
            if let ua = attribute(line, "http-user-agent"), !ua.isEmpty { pendingHeaders["User-Agent"] = ua }
            else { pendingHeaders["User-Agent"] = chromeUA }
            if let ref = attribute(line, "http-referrer"), !ref.isEmpty { pendingHeaders["Referer"] = ref }
            continue
        }
        if line.hasPrefix("#EXTVLCOPT:") {
            let option = String(line.dropFirst("#EXTVLCOPT:".count))
            guard let eq = option.firstIndex(of: "=") else { continue }
            let name = String(option[..<eq]).trimmed.lowercased()
            let value = String(option[option.index(after: eq)...]).trimmed
            if name == "http-user-agent", !value.isEmpty { pendingHeaders["User-Agent"] = value }
            else if name == "http-referrer", !value.isEmpty { pendingHeaders["Referer"] = value }
            continue
        }
        if line.hasPrefix("#") { continue }
        let url = resolveURL(line, base: baseUrl)
        let title = (pendingTitle?.isEmpty == false) ? pendingTitle! : (URL(string: url)?.host ?? "Live channel")
        entries.append(LiveTvEntry(title: title, url: url, source: sourceLabel,
                                   region: pendingGroup, language: "", logoUrl: pendingLogo, headers: pendingHeaders))
        pendingTitle = nil; pendingLogo = nil; pendingGroup = ""; pendingHeaders.removeAll()
    }
    return entries
}

private func titleFromExtInf(_ line: String) -> String {
    if let comma = line.lastIndex(of: ","), comma != line.index(before: line.endIndex) {
        return String(line[line.index(after: comma)...]).trimmed
    }
    return attribute(line, "tvg-name") ?? "Live channel"
}

private func attribute(_ line: String, _ name: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: "\(name)=\"([^\"]*)\"") else { return nil }
    let range = NSRange(line.startIndex..., in: line)
    guard let m = regex.firstMatch(in: line, range: range), let r = Range(m.range(at: 1), in: line) else { return nil }
    return String(line[r]).trimmed
}

private func resolveURL(_ link: String, base: String) -> String {
    if link.hasPrefix("http") { return link }
    if let baseURL = URL(string: base), let resolved = URL(string: link, relativeTo: baseURL) {
        return resolved.absoluteString
    }
    return link
}

private func stripTags(_ s: String) -> String {
    s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
}

// MARK: - Category helpers (parity with _categoriesFor / _formatCategory)

private func categoriesFor(_ entry: LiveTvEntry) -> [String] {
    let values = Set(entry.region.split(separator: ";")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
        .map(formatCategory)).sorted()
    return values.isEmpty ? ["Unknown"] : values
}

private func formatCategory(_ value: String) -> String {
    let normalized = value.lowercased() == "undefined" ? "unknown" : value
    return normalized.split(whereSeparator: { $0 == " " || $0 == "_" || $0 == "-" })
        .filter { !$0.isEmpty }
        .map { $0.prefix(1).uppercased() + String($0.dropFirst()) }
        .joined(separator: " ")
}

// MARK: - Category row + card

private struct LiveTvCategoryRow: View {
    let title: String
    let entries: [LiveTvEntry]
    let onSelected: (LiveTvEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 19, weight: .black)).foregroundStyle(.white).lineLimit(1)
                Image(systemName: "chevron.right").font(.system(size: 16, weight: .bold)).foregroundStyle(.white.opacity(0.82))
                Spacer()
                Text("\(entries.count)").font(.system(size: 15, weight: .bold)).foregroundStyle(.white.opacity(0.58))
            }
            .padding(.trailing, 28)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(entries) { entry in
                        Button { onSelected(entry) } label: { LiveTvCard(entry: entry) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 28)
            }
        }
        .padding(EdgeInsets(top: 18, leading: 28, bottom: 0, trailing: 0))
    }
}

private struct LiveTvCard: View {
    let entry: LiveTvEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.12), LiquidColors.deepTeal.opacity(0.2), Color.black.opacity(0.5)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                ChannelLogo(entry: entry, size: 92)
                VStack {
                    HStack {
                        Spacer()
                        GlassCapsule(padding: EdgeInsets(top: 5, leading: 9, bottom: 5, trailing: 9)) {
                            Image(systemName: "play.fill").font(.system(size: 15)).foregroundStyle(.white)
                        }
                    }
                    Spacer()
                }
                .padding(12)
            }
            .frame(width: 176, height: 130)
            Text(entry.title).font(.system(size: 14, weight: .bold)).foregroundStyle(.white).lineLimit(1)
            Text(categoriesFor(entry).joined(separator: " • ")).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
        }
        .frame(width: 176, alignment: .leading)
    }
}

/// Channel logo with a fallback chain (parity with `_ChannelLogo`), advancing
/// through candidate URLs on load failure.
private struct ChannelLogo: View {
    let entry: LiveTvEntry
    let size: CGFloat
    @State private var index = 0

    private var logoUrls: [String] {
        let title = entry.title
        let slug = title.lowercased().replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)
        let cleanName = title.lowercased().replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
        let originalSlug = title.replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-zA-Z0-9-]", with: "", options: .regularExpression)
        let originalCleanName = title.replacingOccurrences(of: "[^a-zA-Z0-9]", with: "", options: .regularExpression)
        var logoId = slug
        if let logo = entry.logoUrl,
           let r = try? NSRegularExpression(pattern: "api/logos/(.*?)\\.png"),
           let m = r.firstMatch(in: logo, range: NSRange(logo.startIndex..., in: logo)),
           let g = Range(m.range(at: 1), in: logo) { logoId = String(logo[g]) }
        let firstChar = slug.first.map(String.init)?.lowercased() ?? "a"
        let doubleChar = firstChar.range(of: "[a-z]", options: .regularExpression) != nil ? "\(firstChar)\(firstChar)" : "aa"
        var urls: [String] = []
        if let logo = entry.logoUrl, !logo.isEmpty { urls.append(logo) }
        urls += [
            "https://iptv-org.github.io/api/logos/\(logoId).png",
            "https://www.lyngsat.com/logo/tv/\(doubleChar)/\(slug).png",
            "https://www.lyngsat.com/logo/tv/\(doubleChar)/\(slug).gif",
            "https://www.lyngsat.com/logo/tv/\(doubleChar)/\(slug).jpg",
            "https://www.lyngsat.com/logo/tv/\(doubleChar)/\(cleanName).png",
            "https://raw.githubusercontent.com/m3u8playlist/tvlogo/master/logo/\(slug).png",
            "https://raw.githubusercontent.com/m3u8playlist/tvlogo/master/logo/\(cleanName).png",
            "https://raw.githubusercontent.com/m3u8playlist/tvlogo/master/logo/\(originalSlug).png",
            "https://raw.githubusercontent.com/m3u8playlist/tvlogo/master/logo/\(originalCleanName).png",
            "https://raw.githubusercontent.com/msolihinam/tv/main/logo/\(slug).png",
            "https://raw.githubusercontent.com/msolihinam/tv/main/logo/\(cleanName).png",
            "https://raw.githubusercontent.com/msolihinam/tv/main/logo/\(originalSlug).png",
            "https://raw.githubusercontent.com/msolihinam/tv/main/logo/\(originalCleanName).png",
            "https://raw.githubusercontent.com/Sppotato/Sppotato.github.io/master/logo/\(logoId).png",
        ]
        return urls
    }

    var body: some View {
        let urls = logoUrls
        Group {
            if index >= urls.count {
                RoundedRectangle(cornerRadius: size * 0.24)
                    .fill(Color.white.opacity(0.1))
                    .overlay(Image(systemName: "tv").foregroundStyle(.white.opacity(0.7)))
            } else if let url = URL(string: urls[index]) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFit().padding(size * 0.12)
                    case .failure:
                        Color.clear.onAppear { index += 1 }
                    case .empty: ProgressView().tint(LiquidColors.cyan)
                    @unknown default: EmptyView()
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: size * 0.24))
        .overlay(RoundedRectangle(cornerRadius: size * 0.24).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }
}
