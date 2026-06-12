import SwiftUI

// One Pace data models, shared constants, and the network/parse/resolve logic
// now live in `OnePaceResolver.swift` so both this screen and HomeScreen's
// Continue Watching resume path can share them.

/// Faithful port of `one_pace_screen.dart`.
/// Scrapes onepace.net's Next.js payload for arcs/playlist groups, lists episodes
/// from pixeldrain.net/api/list/{id}, and plays via Pixeldrain (with gamedrive
/// bypass proxy) into PlayerScreen with AniSkip episode mapping (One Piece id 21).
struct OnePaceScreen: View {
    @Environment(AppState.self) private var state

    @State private var loadingArcs = true
    @State private var error: String?
    @State private var arcs: [OnePaceArc] = []
    @State private var selectedArc: OnePaceArc?
    @State private var selectedSeasonNumber = 1
    @State private var selectedPlaylistGroupIndex = 0
    @State private var selectedSubLanguageCode = "en"

    @State private var loadingEpisodes = false
    @State private var episodes: [OnePaceEpisode] = []
    @State private var episodesError: String?

    @State private var repoFolders = onePaceRepoFoldersDefault

    @State private var resolvingSubtitles = false
    @State private var pendingPlayer: PendingPlayer?

    @State private var showSeasonPicker = false
    @State private var showAudioPicker = false
    @State private var showSubtitlePicker = false

    private struct PendingPlayer: Identifiable {
        let id = UUID()
        let title: String
        let url: String
        let subtitleUrl: String
        let item: MediaItem
        let episode: MediaEpisode
        let aniSkipEpisode: Int
    }

    var body: some View {
        Group {
            if loadingArcs {
                ProgressView().tint(LiquidColors.cyan).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if error != nil {
                errorView
            } else {
                content
            }
        }
        .liquidScaffold()
        .task { await loadArcs() }
        .overlay { if resolvingSubtitles { resolvingOverlay } }
        .fullScreenCover(item: $pendingPlayer) { p in
            PlayerScreen(title: p.title, url: p.url, headers: [:], item: p.item, episode: p.episode,
                         subtitleUrl: p.subtitleUrl, startPositionMs: 0, aniSkipEpisode: p.aniSkipEpisode)
        }
        .confirmationDialog("Select One Pace Arc / Season", isPresented: $showSeasonPicker, titleVisibility: .visible) {
            ForEach(Array(arcs.enumerated()), id: \.offset) { idx, arc in
                Button("Season \(idx + 1): \(arc.title)") { selectSeason(idx + 1) }
            }
        }
        .confirmationDialog("Select Audio Track & Version", isPresented: $showAudioPicker, titleVisibility: .visible) {
            if let arc = selectedArc {
                ForEach(Array(arc.playlistGroups.enumerated()), id: \.offset) { idx, pg in
                    Button(audioGroupLabel(pg)) {
                        selectedPlaylistGroupIndex = idx
                        Task { await loadEpisodes() }
                    }
                }
            }
        }
        .confirmationDialog("Select Subtitle Language", isPresented: $showSubtitlePicker, titleVisibility: .visible) {
            ForEach(onePaceSubLanguages, id: \.code) { lang in
                Button(lang.name) { selectedSubLanguageCode = lang.code }
            }
        }
    }

    private var errorView: some View {
        VStack(spacing: 16) {
            Text("Failed to load One Pace details").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
            Button("Retry") { Task { await loadArcs() } }.buttonStyle(.borderedProminent).tint(LiquidColors.cyan)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resolvingOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView().tint(LiquidColors.cyan)
                Text("Resolving Subtitles...").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
            }
            .padding(24)
            .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    @ViewBuilder private var content: some View {
        let arc = selectedArc ?? arcs.first
        GeometryReader { geo in
            let wide = geo.size.width >= 900
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let arc {
                        heroSection(arc: arc, wide: wide)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 32)
                        if let arc { seasonSelector(arc) }
                        Color.clear.frame(height: 8)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 24) { audioSelector; subtitleSelector }
                            VStack(alignment: .leading, spacing: 12) { audioSelector; subtitleSelector }
                        }
                        Color.clear.frame(height: 20)
                        episodesSection
                        Color.clear.frame(height: 48)
                    }
                    .padding(.horizontal, wide ? 54 : 26)
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Hero

    private func heroSection(arc: OnePaceArc, wide: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            PosterImage(url: arc.backdropUrl.isEmpty ? nil : arc.backdropUrl, fallbackSystemName: "film")
                .frame(maxWidth: .infinity)
                .frame(height: wide ? 520 : 640)
                .clipped()
            LinearGradient(colors: [Color.black.opacity(0.27), Color.black], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("ONE PACE").font(.system(size: 11, weight: .black)).kerning(1.2).foregroundStyle(.black)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(LiquidColors.cyan, in: RoundedRectangle(cornerRadius: 4))
                    Text("Season \(selectedSeasonNumber) • \(episodes.count) Episodes")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.7))
                }
                Text(arc.title).font(.system(size: wide ? 46 : 32, weight: .black)).foregroundStyle(.white)
                Text(arc.description).font(.system(size: 15)).foregroundStyle(.white.opacity(0.85)).lineLimit(3).lineSpacing(3)
                    .frame(maxWidth: 640, alignment: .leading)
                Text("Chapters Covered: \(arc.chapters)  •  Anime Episodes Covered: \(arc.animeEpisodes)")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.54))
                if !episodes.isEmpty {
                    Button { play(episodes[0]) } label: {
                        Label("Play S1E1", systemImage: "play.fill")
                            .font(.system(size: 15, weight: .bold)).foregroundStyle(.black)
                            .padding(.horizontal, 24).padding(.vertical, 12)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
            }
            .frame(height: wide ? 520 : 640, alignment: .bottomLeading)
            .padding(.horizontal, wide ? 54 : 26)
            .padding(.bottom, 24)
        }
        .frame(height: wide ? 520 : 640)
        .clipped()
    }

    // MARK: - Selectors

    private func seasonSelector(_ arc: OnePaceArc) -> some View {
        Button { showSeasonPicker = true } label: {
            HStack(spacing: 8) {
                Text("\(arc.title) (Season \(selectedSeasonNumber))").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                Image(systemName: "chevron.down").font(.system(size: 18)).foregroundStyle(.white.opacity(0.7))
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var audioSelector: some View {
        if let arc = selectedArc, !arc.playlistGroups.isEmpty {
            let idx = min(max(0, selectedPlaylistGroupIndex), arc.playlistGroups.count - 1)
            Button { showAudioPicker = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "speaker.wave.2").font(.system(size: 16)).foregroundStyle(.white.opacity(0.7))
                    Text(audioGroupLabel(arc.playlistGroups[idx])).font(.system(size: 15, weight: .bold)).foregroundStyle(.white.opacity(0.7))
                    Image(systemName: "chevron.down").font(.system(size: 12)).foregroundStyle(.white.opacity(0.54))
                }
                .padding(.vertical, 6).padding(.horizontal, 8)
            }
            .buttonStyle(.plain)
        }
    }

    private var subtitleSelector: some View {
        let label = onePaceSubLanguages.first { $0.code == selectedSubLanguageCode }?.name ?? "English"
        return Button { showSubtitlePicker = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "captions.bubble").font(.system(size: 16)).foregroundStyle(.white.opacity(0.7))
                Text("Subs: \(label)").font(.system(size: 15, weight: .bold)).foregroundStyle(.white.opacity(0.7))
                Image(systemName: "chevron.down").font(.system(size: 12)).foregroundStyle(.white.opacity(0.54))
            }
            .padding(.vertical, 6).padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Episodes rail

    @ViewBuilder private var episodesSection: some View {
        if loadingEpisodes {
            ProgressView().tint(LiquidColors.cyan).frame(maxWidth: .infinity).padding(.vertical, 48)
        } else if let episodesError {
            Text("Error loading episodes: \(episodesError)").font(.system(size: 14)).foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity).padding(.vertical, 48)
        } else if episodes.isEmpty {
            Text("No episodes listed in this quality / category.").font(.system(size: 14)).foregroundStyle(.white.opacity(0.54))
                .padding(.vertical, 32)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(episodes) { ep in
                        Button { play(ep) } label: { episodeCard(ep) }.buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 180)
        }
    }

    private func episodeCard(_ ep: OnePaceEpisode) -> some View {
        ZStack(alignment: .bottomLeading) {
            PosterImage(url: "https://pixeldrain.net/api/file/\(ep.id)/thumbnail", fallbackSystemName: "play.circle.fill")
                .frame(width: 250, height: 180).clipped()
            LinearGradient(colors: [.clear, Color.black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text("EPISODE \(ep.episodeNumber)").font(.system(size: 10, weight: .black)).kerning(1.1).foregroundStyle(LiquidColors.cyan)
                Text(ep.cleanTitle).font(.system(size: 13, weight: .bold)).foregroundStyle(.white).lineLimit(2)
                Text("\(ep.size / (1024 * 1024)) MB").font(.system(size: 10)).foregroundStyle(.white.opacity(0.54))
            }
            .padding(12)
        }
        .frame(width: 250, height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Loading

    @MainActor
    private func loadArcs() async {
        guard loadingArcs || arcs.isEmpty else { return }
        loadingArcs = true
        error = nil
        repoFolders = await OnePaceResolver.loadRepoFolders()
        do {
            let fetched = try await OnePaceResolver.fetchArcs()
            arcs = fetched
            loadingArcs = false
            if !fetched.isEmpty {
                // Resume from watch history if present.
                if let active = state.continueWatching.first(where: { $0.itemId == "anilist:anime:21" }),
                   let season = active.seasonNumber, season >= 1, season <= fetched.count {
                    selectedSeasonNumber = season
                } else {
                    selectedSeasonNumber = 1
                }
                selectedArc = fetched[selectedSeasonNumber - 1]
                selectedPlaylistGroupIndex = 0
                await loadEpisodes()
            }
        } catch {
            loadingArcs = false
            self.error = "\(error)"
        }
    }

    private func selectSeason(_ season: Int) {
        selectedSeasonNumber = season
        selectedArc = arcs[season - 1]
        selectedPlaylistGroupIndex = 0
        Task { await loadEpisodes() }
    }

    @MainActor
    private func loadEpisodes() async {
        guard let arc = selectedArc else { return }
        loadingEpisodes = true
        episodesError = nil
        episodes = []
        do {
            guard !arc.playlistGroups.isEmpty else { throw OnePaceError.message("No streamable playlist groups found for this arc.") }
            if selectedPlaylistGroupIndex >= arc.playlistGroups.count { selectedPlaylistGroupIndex = 0 }
            let pg = arc.playlistGroups[selectedPlaylistGroupIndex]
            guard !pg.playlists.isEmpty, let listId = OnePaceResolver.bestListId(in: pg) else {
                throw OnePaceError.message("No playlists available inside this audio track.")
            }
            let eps = try await OnePaceResolver.fetchEpisodes(listId: listId)
            episodes = eps
            loadingEpisodes = false
        } catch {
            loadingEpisodes = false
            episodesError = "\(error)"
        }
    }

    // MARK: - Play

    private func play(_ episode: OnePaceEpisode) {
        guard let arc = selectedArc else { return }
        resolvingSubtitles = true
        Task {
            let subUrl = (try? await OnePaceResolver.resolveSubtitleUrl(
                arcTitle: arc.title, epNum: episode.episodeNumber,
                langCode: selectedSubLanguageCode, repoFolders: repoFolders)) ?? ""

            let apiKey = state.credentials.pixeldrainApiKey.trimmed
            let fileUrl = await OnePaceResolver.streamUrl(fileId: episode.id, apiKey: apiKey)

            let resolved = OnePaceResolver.makeResolved(
                arc: arc, seasonNumber: selectedSeasonNumber, episode: episode,
                totalEpisodes: episodes.count, subtitleUrl: subUrl, streamUrl: fileUrl)

            resolvingSubtitles = false
            pendingPlayer = PendingPlayer(
                title: resolved.title, url: resolved.url, subtitleUrl: resolved.subtitleUrl,
                item: resolved.item, episode: resolved.episode, aniSkipEpisode: resolved.aniSkipEpisode)
        }
    }

    // MARK: - Audio group label (parity with _getAudioGroupLabel)

    private func audioGroupLabel(_ pg: OnePacePlaylistGroup) -> String {
        OnePaceResolver.audioGroupLabel(pg)
    }
}
