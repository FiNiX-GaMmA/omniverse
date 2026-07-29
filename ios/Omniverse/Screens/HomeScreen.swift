import SwiftUI

struct HomeScreen: View {
    var filterMode: String = "home"
    @Environment(AppState.self) private var state
    @State private var path = NavigationPath()
    @State private var player: PlayerRoute?
    @State private var web: WebRoute?
    @State private var vidsrc: VidsrcRoute?
    @State private var selectedStudio: String? = nil
    @State private var resumeTarget: ResumeTarget?

    private var filteredPicks: [MediaItem] {
        switch filterMode {
        case "movies":
            return state.heroPicks.filter { $0.type == .movie }
        case "shows":
            return state.heroPicks.filter { $0.type == .series }
        default:
            return state.heroPicks
        }
    }

    private var continueWatchingFilter: MediaType? {
        switch filterMode {
        case "movies": return .movie
        case "shows": return .series
        default: return nil
        }
    }

    @ViewBuilder
    private var tabHeaderBadge: some View {
        if filterMode == "movies" {
            HStack(spacing: 8) {
                Image(systemName: "film.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(LiquidColors.cyan)
                Text("MOVIES CATALOGUE")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .kerning(1.2)
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 8)
        } else if filterMode == "shows" {
            HStack(spacing: 8) {
                Image(systemName: "tv.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(LiquidColors.cyan)
                Text("TV SERIES CATALOGUE")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .kerning(1.2)
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 8)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geo in
                let wide = geo.size.width >= 900
                let portrait = geo.size.height > geo.size.width
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        tabHeaderBadge
                        HeroCarousel(picks: filteredPicks.isEmpty ? state.heroPicks : filteredPicks, wide: wide, portrait: portrait) { path.append($0) }
                            .frame(height: heroHeight(geo))
                        ContinueWatchingRow(filter: continueWatchingFilter, onResume: { entry in resumeTarget = ResumeTarget(entry: entry) })
                        StudiosRow { studioName in
                            selectedStudio = studioName.lowercased()
                        }
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
                             subtitleUrl: r.subtitleUrl, startPositionMs: r.startPositionMs, aniSkipEpisode: r.aniSkipEpisode,
                             onRequestClose: { item, episode in
                                 guard let item else { return }
                                 state.setDetailEpisodeFocus(item: item, episode: episode)
                                 path.append(item)
                             })
            }
            .fullScreenCover(item: $web) { r in
                WebEmbedPlayerScreen(title: r.title, url: r.url, headers: r.headers, item: r.item, episode: r.episode,
                                     onRequestClose: { item, episode in
                                         guard let item else { return }
                                         state.setDetailEpisodeFocus(item: item, episode: episode)
                                         path.append(item)
                                     })
            }
            .fullScreenCover(item: $vidsrc) { r in
                VidsrcResolveScreen(item: r.item, title: r.title, embedUrls: r.embedUrls, episode: r.episode,
                                    onRequestClose: { item, episode in
                                        state.setDetailEpisodeFocus(item: item, episode: episode)
                                        path.append(item)
                                    })
            }
            .fullScreenCover(isPresented: Binding(
                get: { selectedStudio != nil },
                set: { if !$0 { selectedStudio = nil } }
            )) {
                if let studio = selectedStudio {
                    StudioDetailsSheet(
                        studio: studio,
                        onClose: { selectedStudio = nil },
                        onItemSelect: { item in
                            selectedStudio = nil
                            path.append(item)
                        }
                    )
                }
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
                if urls.isEmpty { web = WebRoute(title: src.title, url: src.url, headers: src.headers, item: item, episode: episode) }
                else { vidsrc = VidsrcRoute(item: item, title: src.title, embedUrls: urls, episode: episode) }
            } else if src.isEmbed {
                web = WebRoute(title: src.title, url: src.url, headers: src.headers, item: item, episode: episode)
            } else {
                player = PlayerRoute(title: item.title, url: src.url, headers: src.headers, item: item,
                                     episode: episode, subtitleUrl: src.subtitleUrl, startPositionMs: startPositionMs,
                                     aniSkipEpisode: state.aniSkipEpisodeFor(item: item, episode: episode))
            }
        } catch { path.append(item) }
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
        if w >= 900 {
            return min(w * 0.70, h * 0.72)
        }
        if w > h {
            return min(w * 9.0 / 16.0, h * 0.86)
        }
        return min(w * 1.42, h * 0.68)
    }

    // MARK: - Display category shaping (ported from home_screen.dart)

    private var displayCategories: [MediaCategory] {
        let movieCat = state.categories.first { $0.id == "trending_movies" || $0.id == "trakt_trending_movies" }
        let seriesCat = state.categories.first { $0.id == "trending_series" || $0.id == "trakt_trending_series" }
        let movies = movieCat?.items ?? [], series = seriesCat?.items ?? []

        if filterMode == "movies" {
            var out: [MediaCategory] = []
            if !movies.isEmpty {
                out.append(MediaCategory(id: "top_10_trending_movies", title: "Top 10 Movies", type: .movie, items: Array(movies.prefix(10)), description: "Top trending feature films this week"))
                out.append(MediaCategory(id: "trending_movies_all", title: "Popular Movies", type: .movie, items: movies, description: "Popular movies to stream now"))
            }
            for genre in ["Action", "Comedy", "Drama", "Science Fiction", "Animation", "Horror", "Mystery"] {
                var seen = Set<String>(); var picks: [MediaItem] = []
                for item in movies where item.genres.contains(genre) {
                    if seen.insert(item.id).inserted { picks.append(item) }
                }
                if picks.count >= 2 {
                    out.append(MediaCategory(id: "movie_genre_\(genre.lowercased().replacingOccurrences(of: " ", with: "_"))",
                                             title: "Trending \(genre) Movies", type: .movie, items: Array(picks.prefix(15)),
                                             description: "Popular \(genre) feature films"))
                }
            }
            if out.isEmpty {
                return state.categories.map { cat in
                    MediaCategory(id: cat.id, title: cat.title, type: .movie, items: cat.items.filter { $0.type == .movie }, description: cat.description)
                }.filter { !$0.items.isEmpty }
            }
            return out
        } else if filterMode == "shows" {
            var out: [MediaCategory] = []
            if !series.isEmpty {
                out.append(MediaCategory(id: "top_10_trending_series", title: "Top 10 TV Shows", type: .series, items: Array(series.prefix(10)), description: "Top trending series this week"))
                out.append(MediaCategory(id: "trending_series_all", title: "Popular Series", type: .series, items: series, description: "Popular TV shows to binge now"))
            }
            for genre in ["Action", "Comedy", "Drama", "Science Fiction", "Animation", "Horror", "Mystery"] {
                var seen = Set<String>(); var picks: [MediaItem] = []
                for item in series where item.genres.contains(genre) {
                    if seen.insert(item.id).inserted { picks.append(item) }
                }
                if picks.count >= 2 {
                    out.append(MediaCategory(id: "series_genre_\(genre.lowercased().replacingOccurrences(of: " ", with: "_"))",
                                             title: "Trending \(genre) Series", type: .series, items: Array(picks.prefix(15)),
                                             description: "Popular \(genre) television series"))
                }
            }
            if out.isEmpty {
                return state.categories.map { cat in
                    MediaCategory(id: cat.id, title: cat.title, type: .series, items: cat.items.filter { $0.type == .series }, description: cat.description)
                }.filter { !$0.items.isEmpty }
            }
            return out
        }

        // Home mode (mixed feed)
        var out: [MediaCategory] = []
        var mi = 0, si = 0
        func roundRobin(limit: Int) -> [MediaItem] {
            var r: [MediaItem] = []
            while r.count < limit && (mi < movies.count || si < series.count) {
                if mi < movies.count { r.append(movies[mi]); mi += 1; if r.count >= limit { break } }
                if si < series.count { r.append(series[si]); si += 1; if r.count >= limit { break } }
            }
            return r
        }
        let top10 = roundRobin(limit: 10)
        if !top10.isEmpty {
            out.append(MediaCategory(id: "top_10_trending", title: "Top 10 Trending", type: .movie, items: top10,
                                     description: "The most watched movies and TV shows this week"))
        }
        if !movies.isEmpty { out.append(MediaCategory(id: "top_10_trending_movies", title: "Top 10 Trending Movies", type: .movie, items: Array(movies.prefix(10)))) }
        if !series.isEmpty { out.append(MediaCategory(id: "top_10_trending_series", title: "Top 10 Trending TV Shows", type: .series, items: Array(series.prefix(10)))) }
        let trending = roundRobin(limit: 40)
        if !trending.isEmpty {
            out.append(MediaCategory(id: "trending_all", title: "Trending", type: .movie, items: trending,
                                     description: "Popular movies and TV shows this week"))
        }
        // Genre rows
        let allItems = movies + series
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

                VStack {
                    HStack {
                        Text("OMNIVERSE")
                            .font(.system(size: 15, weight: .black))
                            .kerning(2.2)
                            .foregroundStyle(.white)
                        Spacer()
                        Text("FEATURED")
                            .font(.system(size: 9, weight: .heavy))
                            .kerning(1.1)
                            .foregroundStyle(.white.opacity(0.88))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.black.opacity(0.42), in: Capsule())
                            .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                    }
                    .padding(.horizontal, wide ? 54 : 18)
                    .padding(.top, 14)
                    Spacer()
                }
                .allowsHitTesting(false)

                // Stable metadata overlay for the current item (hit-testable so the
                // portrait Play button works; the rest of the banner still taps through).
                heroMeta(limited[safeIdx])
                    .padding(.bottom, 48)
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

    /// Prefer cinematic backdrop art on every phone orientation, matching the
    /// desktop hero. Poster artwork remains a safe fallback for sparse metadata.
    private func heroImageURL(_ item: MediaItem, box: CGSize) -> String? {
        item.heroBackdropUrl ?? item.backdropUrl
            ?? imageUrl(item.posterPath, size: "original") ?? item.posterUrl
    }

    @ViewBuilder
    private func heroImage(_ item: MediaItem, box: CGSize) -> some View {
        let url = heroImageURL(item, box: box)
        ZStack {
            LiquidColors.ink
            heroAsync(url, fill: true)
            LinearGradient(
                colors: [.black.opacity(portrait ? 0.12 : 0.72), .clear, .black.opacity(0.10)],
                startPoint: .leading, endPoint: .trailing
            )
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

    /// Stable, honest metadata overlay. The CTA opens details rather than
    /// pretending to start playback before a source has been selected.
    @ViewBuilder
    private func heroMeta(_ item: MediaItem) -> some View {
        let ratingPart = item.rating > 0 ? "★ \(String(format: "%.1f", item.rating)) • " : ""
        let metaText = "\(ratingPart)\(item.type.label)\(item.genres.isEmpty ? "" : " • " + item.genres.prefix(2).joined(separator: " • "))"
        VStack(alignment: .leading, spacing: 9) {
            Text(item.title)
                .font(.system(size: wide ? 46 : 31, weight: .black))
                .foregroundStyle(.white).lineLimit(2)
                .multilineTextAlignment(.leading)
                .shadow(color: .black.opacity(0.75), radius: 8, y: 2)
            if !item.overview.isEmpty {
                Text(item.overview)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(2)
                    .lineSpacing(3)
                    .frame(maxWidth: wide ? 620 : 330, alignment: .leading)
            }
            Text(metaText)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .shadow(color: .black.opacity(0.85), radius: 6, y: 1)
            Button { onSelect(item) } label: {
                Label("View details", systemImage: "info.circle.fill")
                    .font(.system(size: 14, weight: .heavy)).foregroundStyle(.black)
                    .padding(.vertical, 12).padding(.horizontal, 22)
                    .background(Capsule().fill(.white))
            }
            .buttonStyle(.plain)
            .padding(.top, 3)
            .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
        }
        .padding(.horizontal, wide ? 54 : 20)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                Text("Continue Watching").font(.system(size: 20, weight: .black)).tracking(-0.3).foregroundStyle(.white)
                    .padding(.horizontal, 18)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(entries) { entry in continueCard(entry) }
                    }.padding(.horizontal, 18)
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
                        .frame(width: 242, height: 136).clipped()
                    LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                    Image(systemName: "play.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(.black.opacity(0.52), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.30), lineWidth: 1))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    GeometryReader { g in
                        Capsule().fill(LiquidColors.cyan)
                            .frame(width: g.size.width * entry.fraction, height: 4)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }.frame(width: 242, height: 136)
                }
                .frame(width: 242, height: 136)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text(entry.title).font(.system(size: 14, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                Text(subtitle(entry)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            .frame(width: 242)
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

// ==============================================================================
// SwiftUI Studios Rail (Disney+, Netflix, HBO, Apple, Marvel, Pixar)
// ==============================================================================
struct StudioCard: View {
    let name: String
    let logoUrl: String
    let gradient: LinearGradient
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                AsyncImage(url: URL(string: logoUrl)) { phase in
                    if let img = phase.image {
                        img.resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Color.white.opacity(0.06)
                    }
                }
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text(name)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(width: 132, height: 64, alignment: .leading)
            .background(gradient)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 6, y: 4)
            .scaleEffect(hovered ? 1.04 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: hovered)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

struct StudiosRow: View {
    let onSelected: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WATCH BY STUDIO")
                .font(.system(size: 20, weight: .black))
                .tracking(-0.3)
                .foregroundStyle(.white)
                .padding(.horizontal, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    StudioCard(name: "Netflix", logoUrl: "https://image.tmdb.org/t/p/w154/pbpMk2JmcoNnQwx5JGpXngfoWtp.jpg", gradient: LinearGradient(colors: [Color(hex: 0x1f0808), Color(hex: 0x7c0e0e)], startPoint: .topLeading, endPoint: .bottomTrailing)) {
                        onSelected("Netflix")
                    }
                    StudioCard(name: "Prime Video", logoUrl: "https://image.tmdb.org/t/p/w154/pvske1MyAoymrs5bguRfVqYiM9a.jpg", gradient: LinearGradient(colors: [Color(hex: 0x1A233A), Color(hex: 0x0D1424)], startPoint: .topLeading, endPoint: .bottomTrailing)) {
                        onSelected("Prime")
                    }
                    StudioCard(name: "Disney+", logoUrl: "https://image.tmdb.org/t/p/w154/97yvRBw1GzX7fXprcF80er19ot.jpg", gradient: LinearGradient(colors: [Color(hex: 0x0d1b3e), Color(hex: 0x15327a)], startPoint: .topLeading, endPoint: .bottomTrailing)) {
                        onSelected("Disney")
                    }
                    StudioCard(name: "Apple TV+", logoUrl: "https://image.tmdb.org/t/p/w154/SPnB1qiCkYfirS2it3hZORwGVn.jpg", gradient: LinearGradient(colors: [Color(hex: 0x0e0e0e), Color(hex: 0x2a2a2a)], startPoint: .topLeading, endPoint: .bottomTrailing)) {
                        onSelected("Appletvplus")
                    }
                    StudioCard(name: "Hulu", logoUrl: "https://image.tmdb.org/t/p/w154/bxBlRPEPpMVDc4jMhSrTf2339DW.jpg", gradient: LinearGradient(colors: [Color(hex: 0x051E14), Color(hex: 0x020905)], startPoint: .topLeading, endPoint: .bottomTrailing)) {
                        onSelected("Hulu")
                    }
                    StudioCard(name: "HBO Max", logoUrl: "https://image.tmdb.org/t/p/w154/jbe4gVSfRlbPTdESXhEKpornsfu.jpg", gradient: LinearGradient(colors: [Color(hex: 0x18052b), Color(hex: 0x4c0e82)], startPoint: .topLeading, endPoint: .bottomTrailing)) {
                        onSelected("Hbo")
                    }
                    StudioCard(name: "Paramount+", logoUrl: "https://image.tmdb.org/t/p/w154/fts6X10Jn4QT0X6ac3udKEn2tJA.jpg", gradient: LinearGradient(colors: [Color(hex: 0x001D40), Color(hex: 0x000E24)], startPoint: .topLeading, endPoint: .bottomTrailing)) {
                        onSelected("Paramount")
                    }
                    StudioCard(name: "Peacock", logoUrl: "https://image.tmdb.org/t/p/w154/2aGrp1xw3qhwCYvNGAJZPdjfeeX.jpg", gradient: LinearGradient(colors: [Color(hex: 0x0D0D14), Color(hex: 0x1B1B2A)], startPoint: .topLeading, endPoint: .bottomTrailing)) {
                        onSelected("Peacock")
                    }
                    StudioCard(name: "Crunchyroll", logoUrl: "https://image.tmdb.org/t/p/w154/fzN5Jok5Ig1eJ7gyNGoMhnLSCfh.jpg", gradient: LinearGradient(colors: [Color(hex: 0xF47521), Color(hex: 0x5E2700)], startPoint: .topLeading, endPoint: .bottomTrailing)) {
                        onSelected("Crunchyroll")
                    }
                    StudioCard(name: "AMC+", logoUrl: "https://image.tmdb.org/t/p/w154/ovmu6uot1XVvsemM2dDySXLiX57.jpg", gradient: LinearGradient(colors: [Color(hex: 0x221414), Color(hex: 0x080303)], startPoint: .topLeading, endPoint: .bottomTrailing)) {
                        onSelected("Amcplus")
                    }
                }
                .padding(.horizontal, 18)
            }
        }
        .padding(.vertical, 16)
    }
}

// ==============================================================================
// SwiftUI Studio Details Page (Vertical category grids, logo headers)
// ==============================================================================
struct StudioDetailsSheet: View {
    let studio: String
    let onClose: () -> Void
    let onItemSelect: (MediaItem) -> Void

    @Environment(AppState.self) private var state
    @State private var movies: [MediaItem] = []
    @State private var tvShows: [MediaItem] = []
    @State private var loading = true

    var displayName: String {
        switch studio.lowercased() {
        case "netflix": return "Netflix"
        case "prime": return "Prime Video"
        case "disney": return "Disney+"
        case "appletvplus", "apple": return "Apple TV+"
        case "hulu": return "Hulu"
        case "hbo": return "HBO Max"
        case "paramount": return "Paramount+"
        case "peacock": return "Peacock Premium"
        case "crunchyroll": return "Crunchyroll"
        case "amcplus": return "AMC+"
        default: return studio.capitalized
        }
    }

    var logoUrl: String {
        switch studio.lowercased() {
        case "netflix": return "https://image.tmdb.org/t/p/w154/pbpMk2JmcoNnQwx5JGpXngfoWtp.jpg"
        case "prime": return "https://image.tmdb.org/t/p/w154/pvske1MyAoymrs5bguRfVqYiM9a.jpg"
        case "disney": return "https://image.tmdb.org/t/p/w154/97yvRBw1GzX7fXprcF80er19ot.jpg"
        case "appletvplus", "apple": return "https://image.tmdb.org/t/p/w154/SPnB1qiCkYfirS2it3hZORwGVn.jpg"
        case "hulu": return "https://image.tmdb.org/t/p/w154/bxBlRPEPpMVDc4jMhSrTf2339DW.jpg"
        case "hbo": return "https://image.tmdb.org/t/p/w154/jbe4gVSfRlbPTdESXhEKpornsfu.jpg"
        case "paramount": return "https://image.tmdb.org/t/p/w154/fts6X10Jn4QT0X6ac3udKEn2tJA.jpg"
        case "peacock": return "https://image.tmdb.org/t/p/w154/2aGrp1xw3qhwCYvNGAJZPdjfeeX.jpg"
        case "crunchyroll": return "https://image.tmdb.org/t/p/w154/fzN5Jok5Ig1eJ7gyNGoMhnLSCfh.jpg"
        case "amcplus": return "https://image.tmdb.org/t/p/w154/ovmu6uot1XVvsemM2dDySXLiX57.jpg"
        default: return ""
        }
    }

    var body: some View {
        ZStack {
            Color(hex: 0x0c0f14).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack(spacing: 16) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)

                    if !logoUrl.isEmpty {
                        AsyncImage(url: URL(string: logoUrl)) { phase in
                            if let img = phase.image {
                                img.resizable().aspectRatio(contentMode: .fit)
                            } else {
                                Text(displayName).font(.system(size: 22, weight: .black)).foregroundStyle(.white)
                            }
                        }
                        .frame(height: 40)
                    } else {
                        Text(displayName)
                            .font(.system(size: 24, weight: .black))
                            .foregroundStyle(.white)
                    }

                    Spacer()
                }
                .padding(.horizontal, 24).padding(.vertical, 16)

                if loading {
                    Spacer()
                    ProgressView().tint(LiquidColors.cyan)
                    Spacer()
                } else if movies.isEmpty && tvShows.isEmpty {
                    Spacer()
                    Text("No content available for this studio.")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            if !movies.isEmpty {
                                CategoryRow(
                                    category: MediaCategory(id: "\(studio)_movies", title: "Trending Movies", type: .movie, items: movies),
                                    wide: false,
                                    onItem: onItemSelect
                                )
                            }
                            if !tvShows.isEmpty {
                                CategoryRow(
                                    category: MediaCategory(id: "\(studio)_tv", title: "Trending Shows", type: .series, items: tvShows),
                                    wide: false,
                                    onItem: onItemSelect
                                )
                            }
                        }
                        .padding(.vertical, 16)
                    }
                }
            }
        }
        .task {
            movies = await state.fetchStudioMovies(studio)
            tvShows = await state.fetchStudioTVShows(studio)
            loading = false
        }
    }
}
