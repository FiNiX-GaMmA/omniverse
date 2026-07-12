import SwiftUI
import WebKit

struct MediaDetailScreen: View {
    let item: MediaItem
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var detailed: MediaItem?
    @State private var loading = true
    @State private var selectedSeason: Int = 1
    @State private var episodes: [MediaEpisode] = []
    @State private var loadingEpisodes = false
    @State private var loadingStreams = false

    // Source selection + playback presentation
    @State private var sources: [PlaybackSource] = []
    @State private var showSourceSheet = false
    @State private var sheetTitle = ""
    @State private var pendingEpisode: MediaEpisode?
    @State private var player: PlayerRoute?
    @State private var overviewExpanded = false
    @State private var webEmbed: WebRoute?
    @State private var vidsrc: VidsrcRoute?
    @State private var captcha: CaptchaRoute?

    private var current: MediaItem { detailed ?? item }
    private var isSeries: Bool { current.type == .series || current.type == .anime }

    var body: some View {
        content
            .task { await load() }
        .fullScreenCover(item: $player) { r in
            PlayerScreen(title: r.title, url: r.url, headers: r.headers, item: r.item, episode: r.episode,
                         subtitleUrl: r.subtitleUrl, startPositionMs: r.startPositionMs, aniSkipEpisode: r.aniSkipEpisode)
        }
        .fullScreenCover(item: $webEmbed) { r in
            WebEmbedPlayerScreen(title: r.title, url: r.url, headers: r.headers, item: r.item)
        }
        .fullScreenCover(item: $vidsrc) { r in
            VidsrcResolveScreen(item: r.item, title: r.title, embedUrls: r.embedUrls, episode: r.episode)
        }
        .fullScreenCover(item: $captcha) { r in
            CaptchaResolveScreen(url: r.url) {
                captcha = nil
                r.onSolved()
            }
        }
        .sheet(isPresented: $showSourceSheet) { sourceSheet }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroSection
                if isSeries {
                    seasonSelector
                    episodeRail
                }
                Color.clear.frame(height: 80)
            }
        }
        .scrollIndicators(.hidden)
        .liquidScaffold()
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white).frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }.buttonStyle(.plain).padding(.leading, 16).padding(.top, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Hero

    private var heroSection: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 900
            ZStack(alignment: .bottomLeading) {
                PosterImage(url: current.heroBackdropUrl ?? current.backdropUrl ?? current.posterUrl)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                LinearGradient(colors: [.black.opacity(0.6), .black.opacity(0.08), .black.opacity(0.93)],
                               startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 12) {
                    Text(current.title).font(.system(size: wide ? 44 : 30, weight: .black)).foregroundStyle(.white).lineLimit(2)
                    Text("\(current.type.label)\(current.genres.isEmpty ? "" : " • " + current.genres.prefix(3).joined(separator: " • "))")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.72))
                    if !current.overview.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(current.overview)
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.82))
                                .lineLimit(overviewExpanded ? 20 : 3)
                                .lineSpacing(4)

                            if current.overview.count > 150 {
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        overviewExpanded.toggle()
                                    }
                                } label: {
                                    Text(overviewExpanded ? "Read Less" : "Read More")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(LiquidColors.cyan)
                                        .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    badges
                    actions
                }
                .padding(.horizontal, wide ? 54 : 26).padding(.bottom, 30)
                .frame(maxWidth: 720, alignment: .leading)
            }
        }
        .frame(height: 720)
    }

    private var badges: some View {
        HStack(spacing: 8) {
            badge(String((current.releaseDate.split(separator: "-").first).map(String.init) ?? "2025"))
            if let r = current.runtimeMinutes { badge("\(r) min") }
            if current.rating > 0 { badge(String(format: "★ %.1f", current.rating)) }
            badge("CC"); badge("AD")
        }
    }
    private func badge(_ t: String) -> some View {
        Text(t).font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.24), lineWidth: 0.5))
    }

    private var actions: some View {
        HStack(spacing: 14) {
            Button { Task { await onPrimary() } } label: {
                HStack { if loadingStreams { ProgressView().tint(.black) } else { Image(systemName: "play.fill") }; Text(primaryLabel) }
                    .font(.system(size: 16, weight: .heavy)).foregroundStyle(.black)
                    .padding(.vertical, 14).padding(.horizontal, 26)
                    .background(Capsule().fill(.white))
            }.buttonStyle(.plain).disabled(loadingStreams)
            Button { Task { await state.toggleWatchlist(current) } } label: {
                Image(systemName: state.isInWatchlist(current) ? "checkmark" : "plus")
                    .font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 56, height: 56).background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1))
            }.buttonStyle(.plain)
        }
    }

    private var primaryLabel: String {
        let prog = state.continueWatching.first { $0.itemId == current.id }
        if let p = prog {
            if let s = p.seasonNumber, let e = p.episodeNumber { return "Resume S\(s)E\(e)" }
            return "Resume"
        }
        return isSeries ? "Play First Episode" : "Play"
    }

    // MARK: Season + episodes (with 50-ep/100-ep virtual chunking)

    private var expandedSeasons: [MediaSeason] {
        var out: [MediaSeason] = []
        let limit = current.type == .anime ? 100 : 50
        for s in current.seasons {
            let total = max(s.episodeCount, current.episodes.filter { $0.seasonNumber == s.seasonNumber }.count)
            if total > limit {
                let chunks = Int(ceil(Double(total) / Double(limit)))
                for i in 0..<chunks {
                    let start = i * limit + 1, end = min(total, (i + 1) * limit)
                    out.append(MediaSeason(seasonNumber: s.seasonNumber * 1000 + i, name: "\(s.name) (Part \(i + 1))", episodeCount: end - start + 1))
                }
            } else { out.append(s) }
        }
        return out
    }

    private var seasonSelector: some View {
        Menu {
            ForEach(expandedSeasons, id: \.seasonNumber) { s in
                Button(s.name) { selectedSeason = s.seasonNumber; Task { await loadEpisodes() } }
            }
        } label: {
            HStack {
                Text(expandedSeasons.first { $0.seasonNumber == selectedSeason }?.name ?? "Season")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                Image(systemName: "chevron.down").font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .padding(.horizontal, 26).padding(.top, 10)
    }

    private var episodeRail: some View {
        Group {
            if loadingEpisodes { ProgressView().tint(LiquidColors.cyan).frame(height: 150).frame(maxWidth: .infinity) }
            else if episodes.isEmpty { Text("No episodes loaded for this season.").font(.system(size: 13)).foregroundStyle(.white.opacity(0.6)).padding(26) }
            else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 14) {
                            ForEach(episodes) { ep in
                                episodeCard(ep)
                                    .id(ep.episodeNumber)
                            }
                        }.padding(.horizontal, 26)
                    }
                    .onAppear {
                        if let prog = state.continueWatching.first(where: { $0.itemId == current.id }),
                           let epNum = prog.episodeNumber {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation {
                                    proxy.scrollTo(epNum, anchor: .center)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, 14)
    }

    private func episodeCard(_ ep: MediaEpisode) -> some View {
        Button { Task { await openEpisodeSources(ep) } } label: {
            VStack(alignment: .leading, spacing: 6) {
                PosterImage(url: ep.stillUrl, fallbackSystemName: "play.rectangle")
                    .aspectRatio(16/9, contentMode: .fill).frame(width: 280, height: 158).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text("EPISODE \(ep.episodeNumber)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                Text(ep.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                if !ep.overview.isEmpty { Text(ep.overview).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(2) }
            }.frame(width: 280)
        }.buttonStyle(.plain)
    }

    // MARK: Loading

    private func load() async {
        loading = true
        detailed = await state.detailsFor(item)
        loading = false
        if isSeries {
            var targetSeason = expandedSeasons.first(where: { $0.seasonNumber > 0 })?.seasonNumber
                ?? expandedSeasons.first?.seasonNumber ?? 1
            
            if let prog = state.continueWatching.first(where: { $0.itemId == current.id }) {
                let progEpNum = prog.episodeNumber
                let progSeasonNum = prog.seasonNumber
                
                if let progSeasonNum {
                    if expandedSeasons.contains(where: { $0.seasonNumber == progSeasonNum }) {
                        targetSeason = progSeasonNum
                    } else if progSeasonNum < 1000, let progEpNum {
                        let limit = current.type == .anime ? 100 : 50
                        let chunkIndex = (progEpNum - 1) / limit
                        let virtualSeason = progSeasonNum * 1000 + chunkIndex
                        if expandedSeasons.contains(where: { $0.seasonNumber == virtualSeason }) {
                            targetSeason = virtualSeason
                        }
                    }
                }
            }
            
            selectedSeason = targetSeason
            await loadEpisodes()
        }
    }

    private func loadEpisodes() async {
        loadingEpisodes = true; defer { loadingEpisodes = false }
        let season = selectedSeason
        if season >= 1000 {
            let original = season / 1000, chunk = season % 1000
            var full = current.episodes.first?.seasonNumber == original ? current.episodes : await state.seasonEpisodesFor(current, seasonNumber: original)
            let limit = current.type == .anime ? 100 : 50
            let start = chunk * limit, end = min(full.count, (chunk + 1) * limit)
            if start < end { full = Array(full[start..<end]) } else { full = [] }
            episodes = full.map { var e = $0; e.seasonNumber = season; return e }
        } else {
            episodes = await state.seasonEpisodesFor(current, seasonNumber: season)
        }
    }

    // MARK: Source selection + dispatch (parity with _openPlaybackSource)

    private func onPrimary() async {
        if isSeries {
            let target = episodes.first ?? current.episodes.first
            if let target { await openEpisodeSources(target) }
        } else {
            await openMovieSources()
        }
    }

    private func openMovieSources() async {
        loadingStreams = true; defer { loadingStreams = false }
        do {
            let s = try await state.playbackSourcesFor(current)
            if s.isEmpty { state.message = "No playable sources found."; return }
            sources = s; sheetTitle = current.title; pendingEpisode = nil
            try? await maybeAutoOpen(s, episode: nil) { showSourceSheet = true }
        } catch {
            handleSourceError(error) { await openMovieSources() }
        }
    }

    private func openEpisodeSources(_ ep: MediaEpisode) async {
        loadingStreams = true; defer { loadingStreams = false }
        do {
            let s = try await state.playbackSourcesFor(current, episode: ep)
            if s.isEmpty { state.message = "No playable sources found."; return }
            sources = s; sheetTitle = "\(current.title) S\(ep.seasonNumber)E\(ep.episodeNumber)"; pendingEpisode = ep
            try? await maybeAutoOpen(s, episode: ep) { showSourceSheet = true }
        } catch {
            handleSourceError(error) { await openEpisodeSources(ep) }
        }
    }

    /// Shared error handling for source loading. If AllAnime asked for a captcha,
    /// present the WebView and retry the same request once it's solved; otherwise
    /// surface the message. `retry` re-runs the exact call that failed.
    private func handleSourceError(_ error: Error, retry: @escaping () async -> Void) {
        if case AnimeRepository.AnimeError.captchaRequired(let urlStr) = error,
           let url = URL(string: urlStr) {
            captcha = CaptchaRoute(url: url) { Task { await retry() } }
            return
        }
        state.message = "Could not load sources: \(error)"
    }

    /// One-click preferred-server bypass + single-direct-anime auto open.
    private func maybeAutoOpen(_ s: [PlaybackSource], episode: MediaEpisode?, fallback: () -> Void) async throws {
        let domain = state.settings.vidsrcDomain.trimmed
        if !domain.isEmpty, let match = s.first(where: { $0.url.contains(domain) }) {
            openSource(match, episode: episode); return
        }
        if current.type == .anime, s.count == 1, s[0].isDirect { openSource(s[0], episode: episode); return }
        fallback()
    }

    private var sourceSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(sheetTitle).font(.system(size: 20, weight: .black)).foregroundStyle(.white)
            ForEach(sources) { src in
                Button { showSourceSheet = false; openSource(src, episode: pendingEpisode) } label: {
                    HStack {
                        Image(systemName: src.isEmbed ? "rectangle.stack" : "play.circle").foregroundStyle(LiquidColors.cyan)
                        VStack(alignment: .leading) {
                            Text(src.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                            Text("\(src.provider) • \(src.quality)").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer(); Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.4))
                    }
                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }.buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(20)
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
    }

    private func openSource(_ source: PlaybackSource, episode: MediaEpisode?) {
        // Movies/TV: stub progress so it appears in Continue Watching.
        if current.type != .anime && current.title != "One Pace" {
            Task { await state.recordProgress(item: current, positionMs: 10000, durationMs: 3600000, episode: episode) }
        }
        let resume = state.continueWatching.first { $0.itemId == current.id && $0.episodeNumber == episode?.episodeNumber }?.positionMs

        if source.isEmbed && source.provider == "VidSrc" {
            let extractor = VidsrcExtractor()
            let urls = extractor.embedUrlsFor(item: current, episode: episode,
                                              preferredDomain: state.settings.vidsrcDomain,
                                              subtitleUrl: state.settings.subtitleUrl,
                                              subtitleLanguage: state.settings.subtitleLanguage)
            if urls.isEmpty { webEmbed = WebRoute(title: source.title, url: source.url, headers: source.headers, item: current) }
            else { vidsrc = VidsrcRoute(item: current, title: source.title, embedUrls: urls, episode: episode) }
        } else if source.isEmbed {
            webEmbed = WebRoute(title: source.title, url: source.url, headers: source.headers, item: current)
        } else {
            player = PlayerRoute(title: "\(current.title) • \(source.title)", url: source.url, headers: source.headers,
                                 item: current, episode: episode, subtitleUrl: source.subtitleUrl, startPositionMs: resume, aniSkipEpisode: nil)
        }
    }
}

// Identifiable route payloads for fullScreenCover.
struct PlayerRoute: Identifiable { let id = UUID(); let title: String; let url: String; let headers: [String:String]; let item: MediaItem?; let episode: MediaEpisode?; let subtitleUrl: String; let startPositionMs: Int?; let aniSkipEpisode: Int? }
struct WebRoute: Identifiable { let id = UUID(); let title: String; let url: String; let headers: [String:String]; let item: MediaItem? }
struct VidsrcRoute: Identifiable { let id = UUID(); let item: MediaItem; let title: String; let embedUrls: [URL]; let episode: MediaEpisode? }
struct CaptchaRoute: Identifiable { let id = UUID(); let url: URL; let onSolved: () -> Void }

// MARK: - Captcha resolution

/// Full-screen WebView shown when AllAnime answers `NEED_CAPTCHA`.
///
/// The user solves the captcha on the AllAnime site inside a real WebView. The
/// cookies WebKit banks are then copied into `HTTPCookieStorage.shared` — the
/// same jar `Http.shared`'s URLSession attaches to outgoing requests — so the
/// retried source call carries the freshly authenticated session. The session
/// lives until AllAnime issues another `NEED_CAPTCHA`, at which point this
/// screen is shown again.
///
/// Lives in this file (rather than its own) because the build machine has no
/// XcodeGen: the committed .xcodeproj only compiles files it already lists, so a
/// standalone new file wouldn't be picked up.
struct CaptchaResolveScreen: View {
    let url: URL
    /// Called once cookies have been synced. The caller dismisses and retries.
    let onSolved: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial, in: Circle())
                }.buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Verify to continue")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    Text("Solve the check, then tap Done")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Button {
                    CaptchaCookieSync.syncToSharedStorage { onSolved() }
                } label: {
                    Text("Done")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(.black)
                        .padding(.horizontal, 22).padding(.vertical, 10)
                        .background(.white, in: Capsule())
                }.buttonStyle(.plain)
            }
            .padding(16)

            CaptchaWebView(url: url)
        }
        .background(Color.black.ignoresSafeArea())
    }
}

/// Thin WKWebView wrapper using the default (persistent) data store so its
/// cookies can be copied into `HTTPCookieStorage.shared`.
private struct CaptchaWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        cfg.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: cfg)
        webView.customUserAgent =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 " +
            "(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// Copies every cookie WebKit currently holds into the shared HTTP cookie jar
/// used by `Http.shared`. It's domain-agnostic on purpose: whatever cookie the
/// captcha flow set (e.g. a `.allanime.day` session) is carried over, and
/// URLSession sends only the ones matching each request host.
enum CaptchaCookieSync {
    static func syncToSharedStorage(_ completion: @escaping () -> Void) {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            for cookie in cookies { HTTPCookieStorage.shared.setCookie(cookie) }
            DispatchQueue.main.async { completion() }
        }
    }
}
