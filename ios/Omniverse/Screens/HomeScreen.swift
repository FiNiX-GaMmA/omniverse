import SwiftUI

struct HomeScreen: View {
    @Environment(AppState.self) private var state
    @State private var path = NavigationPath()
    // Playback presentation hoisted to screen level so Continue Watching can
    // open the player reliably (a nested fullScreenCover inside the lazy row
    // does not present).
    @State private var player: PlayerRoute?
    @State private var web: WebRoute?
    @State private var vidsrc: VidsrcRoute?
    // Continue Watching: tapping a card opens a glass bottom sheet that surfaces
    // the title/progress and gates resolution behind explicit Resume buttons.
    // Wrapped so the sheet has a stable identity (WatchProgress.id can be nil).
    @State private var resumeTarget: ResumeTarget?

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geo in
                let wide = geo.size.width >= 900
                let portrait = geo.size.height > geo.size.width
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        HeroCarousel(picks: state.heroPicks, wide: wide, portrait: portrait) { path.append($0) }
                            .frame(height: heroHeight(geo))
                        ContinueWatchingRow(filter: nil, onResume: { entry in resumeTarget = ResumeTarget(entry: entry) })
                        ForEach(displayCategories) { cat in
                            CategoryRow(category: cat, wide: wide, onItem: { path.append($0) })
                        }
                        Color.clear.frame(height: 110)
                    }
                }
                .scrollIndicators(.hidden)
                .refreshable { await state.refreshAll() }
            }
            .navigationDestination(for: MediaItem.self) { MediaDetailScreen(item: $0) }
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(item: $player) { r in
                PlayerScreen(title: r.title, url: r.url, headers: r.headers, item: r.item, episode: r.episode,
                             subtitleUrl: r.subtitleUrl, startPositionMs: r.startPositionMs, aniSkipEpisode: r.aniSkipEpisode)
            }
            .fullScreenCover(item: $web) { r in
                WebEmbedPlayerScreen(title: r.title, url: r.url, headers: r.headers, item: r.item)
            }
            .fullScreenCover(item: $vidsrc) { r in
                VidsrcResolveScreen(item: r.item, title: r.title, embedUrls: r.embedUrls, episode: r.episode)
            }
            .sheet(item: $resumeTarget) { target in
                let entry = target.entry
                ResumeSheet(
                    entry: entry,
                    onResume: { fromStart in
                        await resume(entry, fromBeginning: fromStart)
                        resumeTarget = nil
                    },
                    onDetails: {
                        let item = continueItem(entry)
                        resumeTarget = nil
                        path.append(item)
                    }
                )
                .presentationDetents([.height(340)])
                .presentationBackground(.clear)
            }
        }
        .liquidScaffold()
    }

    /// Resume a Continue Watching entry directly into the player (never metadata).
    /// `fromBeginning` forces a start position of 0 (the sheet's "Play from
    /// beginning" action); otherwise resumes at the saved position.
    private func resume(_ entry: WatchProgress, fromBeginning: Bool = false) async {
        let startPositionMs = fromBeginning ? 0 : entry.positionMs
        let item = continueItem(entry)
        // One Pace: resolve the arc/episode (same path OnePaceScreen uses) and
        // play directly, rather than opening the metadata/detail screen. Only
        // fall back to the One Pace browse screen if resolution fails.
        if entry.title == "One Pace"
            || entry.itemId.hasPrefix("onepace:")
            || entry.itemId.hasPrefix("anilist:anime:21") {
            await resumeOnePace(entry, fallbackItem: item, startPositionMs: startPositionMs)
            return
        }
        let episode = continueEpisode(entry)
        do {
            let sources = try await state.playbackSourcesFor(item, episode: episode)
            guard let src = sources.first(where: { $0.isDirect || $0.provider == "VidSrc" }) ?? sources.first else {
                path.append(item); return
            }
            if src.isEmbed && src.provider == "VidSrc" {
                let urls = VidsrcExtractor().embedUrlsFor(item: item, episode: episode,
                                                          preferredDomain: state.settings.vidsrcDomain,
                                                          subtitleUrl: state.settings.subtitleUrl,
                                                          subtitleLanguage: state.settings.subtitleLanguage)
                if urls.isEmpty { web = WebRoute(title: src.title, url: src.url, headers: src.headers, item: item) }
                else { vidsrc = VidsrcRoute(item: item, title: src.title, embedUrls: urls, episode: episode) }
            } else if src.isEmbed {
                web = WebRoute(title: src.title, url: src.url, headers: src.headers, item: item)
            } else {
                player = PlayerRoute(title: item.title, url: src.url, headers: src.headers, item: item,
                                     episode: episode, subtitleUrl: src.subtitleUrl, startPositionMs: startPositionMs, aniSkipEpisode: nil)
            }
        } catch { path.append(item) }
    }

    /// Resolves the One Pace arc + episode for a Continue Watching entry and
    /// opens the player at the saved position. Falls back to the One Pace browse
    /// screen only if resolution fails. Mirrors OnePaceScreen's play() path.
    private func resumeOnePace(_ entry: WatchProgress, fallbackItem: MediaItem, startPositionMs: Int) async {
        let season = entry.seasonNumber ?? 1
        let episodeNumber = entry.episodeNumber ?? 1
        let apiKey = state.credentials.pixeldrainApiKey.trimmed
        do {
            let resolved = try await OnePaceResolver.resolveForResume(
                seasonNumber: season, episodeNumber: episodeNumber, apiKey: apiKey)
            player = PlayerRoute(
                title: resolved.title, url: resolved.url, headers: [:],
                item: resolved.item, episode: resolved.episode,
                subtitleUrl: resolved.subtitleUrl, startPositionMs: startPositionMs,
                aniSkipEpisode: resolved.aniSkipEpisode)
        } catch {
            // Could not resolve — open the One Pace browse screen instead.
            path.append(fallbackItem)
        }
    }

    private func continueItem(_ e: WatchProgress) -> MediaItem {
        var item = MediaItem(id: e.itemId, type: e.type, title: e.title, posterPath: e.posterPath, backdropPath: e.backdropPath)
        let parts = e.itemId.split(separator: ":").map(String.init)
        if parts.count >= 3 {
            if parts[0] == "tmdb", let id = Int(parts[2]) { item.tmdbId = id }
            if parts[0] == "trakt", let id = Int(parts[2]) { item.traktId = id }
        }
        return item
    }
    private func continueEpisode(_ e: WatchProgress) -> MediaEpisode? {
        guard let s = e.seasonNumber, let ep = e.episodeNumber else { return nil }
        return MediaEpisode(seasonNumber: s, episodeNumber: ep, title: e.episodeTitle ?? "Episode")
    }

    private func heroHeight(_ geo: GeometryProxy) -> CGFloat {
        let w = geo.size.width, h = geo.size.height
        // Hero banner enlarged by 20% over the previous sizing.
        if w > h {
            // Landscape: a large 16:9 widescreen banner (matches the 16:9 backdrop).
            return min(w * 9.0 / 16.0, h * 0.86) * 1.2
        }
        // Portrait: a moderate poster area that shows the WHOLE poster scaled-to-fit
        // (no cropping); side margins are filled with a blurred copy of the poster.
        return min(w * 1.5, h * 0.6) * 1.2
    }

    // MARK: - Display category shaping (ported from home_screen.dart)

    private var displayCategories: [MediaCategory] {
        let movieCat = state.categories.first { $0.id == "trending_movies" || $0.id == "trakt_trending_movies" }
        let seriesCat = state.categories.first { $0.id == "trending_series" || $0.id == "trakt_trending_series" }
        let animeCat = state.animeCategories.first { $0.id == "anime_trending" || $0.title.lowercased().contains("trending") }
        let movies = movieCat?.items ?? [], series = seriesCat?.items ?? [], anime = animeCat?.items ?? []

        var out: [MediaCategory] = []
        var mi = 0, si = 0, ai = 0
        func roundRobin(limit: Int) -> [MediaItem] {
            var r: [MediaItem] = []
            while r.count < limit && (mi < movies.count || si < series.count || ai < anime.count) {
                if mi < movies.count { r.append(movies[mi]); mi += 1; if r.count >= limit { break } }
                if si < series.count { r.append(series[si]); si += 1; if r.count >= limit { break } }
                if ai < anime.count { r.append(anime[ai]); ai += 1; if r.count >= limit { break } }
            }
            return r
        }
        let top10 = roundRobin(limit: 10)
        if !top10.isEmpty {
            out.append(MediaCategory(id: "top_10_trending", title: "Top 10 Trending", type: .movie, items: top10,
                                     description: "The most watched movies, TV shows, and anime this week"))
        }
        if !movies.isEmpty { out.append(MediaCategory(id: "top_10_trending_movies", title: "Top 10 Trending Movies", type: .movie, items: Array(movies.prefix(10)))) }
        if !series.isEmpty { out.append(MediaCategory(id: "top_10_trending_series", title: "Top 10 Trending TV Shows", type: .series, items: Array(series.prefix(10)))) }
        if !anime.isEmpty { out.append(MediaCategory(id: "top_10_trending_anime", title: "Top 10 Trending Anime", type: .anime, items: Array(anime.prefix(10)))) }
        let trending = roundRobin(limit: 40)
        if !trending.isEmpty {
            out.append(MediaCategory(id: "trending_all", title: "Trending", type: .movie, items: trending,
                                     description: "Popular movies, TV shows, and anime this week"))
        }
        // Genre rows
        let allItems = movies + anime + series
        for genre in ["Action", "Comedy", "Drama", "Science Fiction", "Animation", "Horror", "Mystery"] {
            var seen = Set<String>(); var picks: [MediaItem] = []
            for item in allItems where item.genres.contains(genre) {
                if seen.insert(item.id).inserted { picks.append(item) }
            }
            if picks.count >= 4 {
                out.append(MediaCategory(id: "genre_\(genre.lowercased().replacingOccurrences(of: " ", with: "_"))",
                                         title: "Trending \(genre)", type: .movie, items: Array(picks.prefix(15)),
                                         description: "Popular \(genre) titles to watch this week"))
            }
        }
        // Fall back to raw categories if shaping produced nothing yet.
        if out.isEmpty { return state.categories }
        return out
    }
}

/// Auto-advancing hero carousel (6s), responsive height handled by parent.
struct HeroCarousel: View {
    let picks: [MediaItem]
    var wide: Bool
    var portrait: Bool
    var onSelect: (MediaItem) -> Void
    @Environment(AppState.self) private var state
    @State private var index = 0
    private let timer = Timer.publish(every: 6, on: .main, in: .common).autoconnect()

    var body: some View {
        if picks.isEmpty {
            ZStack {
                LinearGradient(colors: [LiquidColors.dusk, LiquidColors.deepTeal], startPoint: .top, endPoint: .bottom)
                VStack(spacing: 12) {
                    Text("Omniverse").font(.system(size: 34, weight: .black)).foregroundStyle(.white)
                    Text(state.needsSetup ? "Add your TMDB key in Settings to fill this carousel." : "Refreshing the carousel...")
                        .font(.system(size: 14)).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
                }.padding()
            }
        } else {
            let limited = Array(picks.prefix(10))
            GeometryReader { geo in
            let safeIdx = min(index, max(0, limited.count - 1))
            ZStack(alignment: .bottom) {
                // Only the IMAGES live inside the paged TabView. The metadata is a
                // separate, stable overlay (below) bound to the current index, so
                // page transitions can never push it around / behind the rows.
                TabView(selection: $index) {
                    ForEach(Array(limited.enumerated()), id: \.element.id) { i, item in
                        heroImage(item, box: geo.size).tag(i)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(item) }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .id(Int(geo.size.width))   // re-snap on rotation
                .onReceive(timer) { _ in
                    guard !limited.isEmpty else { return }
                    withAnimation(.easeOut(duration: 0.65)) { index = (index + 1) % limited.count }
                }

                // Bottom dissolve across the whole carousel (keeps metadata legible
                // and melts the banner into the rows below).
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.55),
                        .init(color: LiquidColors.ink.opacity(0.85), location: 0.9),
                        .init(color: LiquidColors.ink, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .allowsHitTesting(false)

                // Stable metadata overlay for the current item (hit-testable so the
                // portrait Play button works; the rest of the banner still taps through).
                heroMeta(limited[safeIdx])
                    .padding(.bottom, 44)
                    .animation(.easeInOut(duration: 0.3), value: safeIdx)

                // Dots
                HStack(spacing: 6) {
                    ForEach(0..<limited.count, id: \.self) { i in
                        Capsule().fill(i == index ? LiquidColors.cyan : Color.white.opacity(0.36))
                            .frame(width: i == index ? 30 : 8, height: 8)
                            .animation(.easeOut(duration: 0.25), value: index)
                    }
                }
                .padding(.bottom, 14)
            }
            .onChange(of: geo.size.width) { _, _ in if index >= limited.count { index = 0 } }
            }
        }
    }

    /// The banner image for a page. Portrait shows the WHOLE poster (scaled to
    /// fit, no crop) over a blurred copy of itself (so margins aren't hard bars);
    /// landscape fills with the 16:9 backdrop.
    /// Pick the HD image whose native aspect best FILLS the box, so it fills
    /// cleanly (no blur bars, minimal crop). The portrait box is wider-than-tall
    /// on iPad (so a 16:9 backdrop fits) but tall on phones (so a poster fits) —
    /// choose by the box's actual aspect ratio. Landscape always uses the backdrop.
    private func heroImageURL(_ item: MediaItem, box: CGSize) -> String? {
        if portrait {
            let boxAspect = box.width / max(box.height, 1)
            if boxAspect >= 1.0 {
                return item.heroBackdropUrl ?? item.backdropUrl ?? imageUrl(item.posterPath, size: "original") ?? item.posterUrl
            }
            return imageUrl(item.posterPath, size: "original") ?? item.heroBackdropUrl ?? item.backdropUrl ?? item.posterUrl
        }
        return item.heroBackdropUrl ?? item.backdropUrl ?? item.posterUrl
    }

    @ViewBuilder
    private func heroImage(_ item: MediaItem, box: CGSize) -> some View {
        let url = heroImageURL(item, box: box)
        ZStack {
            LiquidColors.ink
            if portrait {
                // FIT the whole image (no crop) over a blurred copy so any margins
                // are a soft blur rather than hard bars.
                heroAsync(url, fill: true).blur(radius: 32).opacity(0.6)
                heroAsync(url, fill: false)
            } else {
                heroAsync(url, fill: true)   // landscape fills the 16:9 frame
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    @ViewBuilder
    private func heroAsync(_ url: String?, fill: Bool) -> some View {
        AsyncImage(url: URL(string: url ?? ""), transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
            if let img = phase.image {
                img.resizable().aspectRatio(contentMode: fill ? .fill : .fit)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Stable metadata overlay (name in landscape only; rating + metadata always),
    /// centered in portrait / bottom-left in landscape.
    @ViewBuilder
    private func heroMeta(_ item: MediaItem) -> some View {
        let ratingPart = item.rating > 0 ? "★ \(String(format: "%.1f", item.rating)) • " : ""
        let metaText = "\(ratingPart)\(item.type.label)\(item.genres.isEmpty ? "" : " • " + item.genres.prefix(2).joined(separator: " • "))"
        VStack(alignment: portrait ? .center : .leading, spacing: 8) {
            // Title shown in both orientations now (centered in portrait).
            Text(item.title)
                .font(.system(size: wide ? 46 : 32, weight: .black))
                .foregroundStyle(.white).lineLimit(2)
                .multilineTextAlignment(portrait ? .center : .leading)
                .shadow(color: .black.opacity(0.75), radius: 8, y: 2)
            Text(metaText)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(2)
                .multilineTextAlignment(portrait ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
                .shadow(color: .black.opacity(0.85), radius: 6, y: 1)
            // Portrait gets a centered Play button (opens the title to play).
            if portrait {
                Button { onSelect(item) } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.system(size: 16, weight: .heavy)).foregroundStyle(.black)
                        .padding(.vertical, 12).padding(.horizontal, 32)
                        .background(Capsule().fill(.white))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
                .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: portrait ? .center : .leading)
    }
}

/// Continue Watching rail (mirrors continue_watching_row.dart).
struct ContinueWatchingRow: View {
    var filter: MediaType?
    /// Tapping a card resumes playback (handled at the screen level).
    var onResume: (WatchProgress) -> Void
    @Environment(AppState.self) private var state

    private var entries: [WatchProgress] {
        var seen = Set<String>()
        return state.continueWatching.filter { p in
            guard p.type != .liveTv else { return false }
            if let f = filter, p.type != f { return false }
            return seen.insert(p.itemId).inserted
        }
    }

    var body: some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Continue Watching").font(.system(size: 19, weight: .black)).foregroundStyle(.white)
                    .padding(.horizontal, 28)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(entries) { entry in continueCard(entry) }
                    }.padding(.horizontal, 28)
                }
            }
            .padding(.top, 18)
        }
    }

    @ViewBuilder
    private func continueCard(_ entry: WatchProgress) -> some View {
        Button { onResume(entry) } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottom) {
                    PosterImage(url: entry.backdropUrl ?? entry.posterUrl, fallbackSystemName: "play.rectangle")
                        .aspectRatio(16/9, contentMode: .fill)
                        .frame(width: 270, height: 152).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    GeometryReader { g in
                        Capsule().fill(LiquidColors.cyan)
                            .frame(width: g.size.width * entry.fraction, height: 4)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }.frame(width: 270, height: 152)
                }
                Text(entry.title).font(.system(size: 14, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                Text(subtitle(entry)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            .frame(width: 270)
        }.buttonStyle(.plain)
    }

    private func subtitle(_ e: WatchProgress) -> String {
        if let s = e.seasonNumber, let ep = e.episodeNumber { return "S\(s)E\(ep)" }
        return e.type.label
    }
}

/// Identity wrapper so the resume sheet presents reliably even when the
/// underlying `WatchProgress.id` (DB row id) is nil.
private struct ResumeTarget: Identifiable {
    let entry: WatchProgress
    var id: String { entry.progressKey }
}

/// Glass bottom sheet shown when a Continue Watching card is tapped. Surfaces
/// the artwork, title and progress, and gates the (potentially slow) source
/// resolution behind explicit Resume / Play-from-beginning buttons, showing a
/// "Resolving…" spinner in place of the buttons while it works.
private struct ResumeSheet: View {
    let entry: WatchProgress
    /// Resolves the source and opens the player; `fromBeginning` starts at 0.
    let onResume: (_ fromBeginning: Bool) async -> Void
    let onDetails: () -> Void

    @State private var resolving = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            GlassPanel(cornerRadius: 28, opacity: 0.16, borderOpacity: 0.24, padding: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 14) {
                        PosterImage(url: entry.backdropUrl ?? entry.posterUrl, fallbackSystemName: "play.rectangle")
                            .aspectRatio(16/9, contentMode: .fill)
                            .frame(width: 132, height: 74).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.title)
                                .font(.system(size: 17, weight: .black)).foregroundStyle(.white)
                                .lineLimit(2)
                            Text(detailLine)
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.66))
                                .lineLimit(1)
                            ProgressView(value: entry.fraction)
                                .tint(LiquidColors.cyan)
                                .padding(.top, 2)
                        }
                        Spacer(minLength: 0)
                    }

                    if resolving {
                        HStack(spacing: 10) {
                            ProgressView().tint(LiquidColors.cyan)
                            Text("Resolving…").font(.system(size: 15, weight: .bold)).foregroundStyle(.white.opacity(0.82))
                            Spacer()
                        }
                        .frame(height: 54)
                    } else {
                        VStack(spacing: 10) {
                            Button {
                                Task { resolving = true; await onResume(false) }
                            } label: { Label("Resume", systemImage: "play.fill") }
                                .buttonStyle(AccentButtonStyle())

                            Button {
                                Task { resolving = true; await onResume(true) }
                            } label: { Label("Play from beginning", systemImage: "arrow.counterclockwise") }
                                .buttonStyle(AccentButtonStyle(filled: false))

                            Button(action: onDetails) {
                                Label("Details", systemImage: "info.circle")
                            }
                                .buttonStyle(AccentButtonStyle(filled: false))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private var detailLine: String {
        var parts: [String] = []
        if let s = entry.seasonNumber, let ep = entry.episodeNumber { parts.append("S\(s)E\(ep)") }
        else { parts.append(entry.type.label) }
        let pct = Int((entry.fraction * 100).rounded())
        if pct > 0 { parts.append("\(pct)% watched") }
        return parts.joined(separator: " • ")
    }
}
