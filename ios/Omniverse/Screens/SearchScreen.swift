import SwiftUI

/// Faithful port of `search_screen.dart`.
/// Autofocus field, 320ms debounce, multi-source search, grid of poster cards,
/// navigation to MediaDetailScreen via NavigationStack.
struct SearchScreen: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var currentQuery = ""
    @State private var loading = false
    @State private var error: String?
    @State private var results: [MediaItem] = []
    @State private var requestId = 0
    @State private var debounceTask: Task<Void, Never>?
    @State private var path = NavigationPath()
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                searchBar
                if loading {
                    ProgressView()
                        .tint(LiquidColors.cyan)
                        .padding(24)
                }
                if !loading, let error, results.isEmpty {
                    Text(error)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 28)
                        .padding(.bottom, 12)
                }
                if results.isEmpty {
                    emptyHints
                } else {
                    resultsGrid
                }
                Spacer(minLength: 0)
            }
            .navigationDestination(for: MediaItem.self) { MediaDetailScreen(item: $0) }
            .toolbar(.hidden, for: .navigationBar)
        }
        .liquidScaffold()
        .onAppear { fieldFocused = true }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            GlassCapsule(padding: EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 8)) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 18)).foregroundStyle(.white.opacity(0.7))
                    TextField("", text: $query, prompt: Text("Search movies and TV shows").foregroundColor(.white.opacity(0.54)))
                        .focused($fieldFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .foregroundStyle(.white)
                        .font(.system(size: 17, weight: .semibold))
                        .tint(LiquidColors.cyan)
                        .onChange(of: query) { _, value in onChanged(value) }
                        .onSubmit { run(query.trimmed) }
                    if !query.isEmpty {
                        Button {
                            query = ""
                            onChanged("")
                        } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: - Results grid

    private var resultsGrid: some View {
        GeometryReader { geo in
            let count = columns(for: geo.size.width)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: count), spacing: 18) {
                    ForEach(results) { item in
                        Button { path.append(item) } label: { GridPoster(item: item) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(EdgeInsets(top: 8, leading: 16, bottom: 32, trailing: 16))
            }
            .scrollIndicators(.hidden)
        }
    }

    private func columns(for width: CGFloat) -> Int {
        if width >= 1200 { return 6 }
        if width >= 900 { return 5 }
        if width >= 600 { return 4 }
        return 3
    }

    // MARK: - Empty hints

    @ViewBuilder private var emptyHints: some View {
        if currentQuery.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Search Anything in Omniverse")
                    .font(.system(size: 19, weight: .black))
                    .foregroundStyle(.white)
                Text("Type a movie, TV show, or anime title. We search Omniverse for matches and open the same detail screen as the home rows — sources included.")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 8, leading: 28, bottom: 0, trailing: 28))
        }
    }

    // MARK: - Debounce + run

    private func onChanged(_ value: String) {
        debounceTask?.cancel()
        let trimmed = value.trimmed
        if trimmed.isEmpty {
            currentQuery = ""
            results = []
            loading = false
            error = nil
            return
        }
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 320_000_000)
            if Task.isCancelled { return }
            await runSearch(trimmed)
        }
    }

    private func run(_ q: String) { Task { await runSearch(q) } }

    @MainActor
    private func runSearch(_ q: String) async {
        let trimmed = q.trimmed
        guard !trimmed.isEmpty else { return }
        requestId += 1
        let id = requestId
        currentQuery = trimmed
        loading = true
        error = nil

        guard state.credentials.hasTmdb else {
            if id != requestId { return }
            loading = false
            error = "Add your TMDB API key in Settings to enable search."
            results = []
            return
        }
        let items = await state.searchMedia(trimmed)
        if id != requestId { return }
        loading = false
        results = items
        error = items.isEmpty ? "No matches for \"\(trimmed)\"." : nil
    }
}

/// Grid poster (2:3) sized to fill its grid cell.
private struct GridPoster: View {
    let item: MediaItem
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PosterImage(url: item.posterUrl ?? item.backdropUrl)
                .aspectRatio(2/3, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.36), radius: 14, y: 8)
            Text(item.title).font(.system(size: 13, weight: .bold)).foregroundStyle(.white).lineLimit(1)
        }
    }
}
