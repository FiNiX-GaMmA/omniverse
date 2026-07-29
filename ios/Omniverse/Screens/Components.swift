import SwiftUI

/// Cached async network image with a glassy gradient placeholder + fallback.
struct PosterImage: View {
    let url: String?
    var fallbackSystemName: String = "film"
    var contentMode: ContentMode = .fill

    var body: some View {
        let placeholder = LinearGradient(
            colors: [LiquidColors.deepTeal.opacity(0.86), LiquidColors.dusk.opacity(0.92)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
        ZStack {
            placeholder
            if let url, let u = URL(string: url) {
                AsyncImage(url: u, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(contentMode: contentMode)
                    case .failure:
                        Image(systemName: fallbackSystemName).font(.system(size: 38)).foregroundStyle(.white.opacity(0.5))
                    case .empty:
                        ProgressView().tint(LiquidColors.cyan)
                    @unknown default: EmptyView()
                    }
                }
            } else {
                Image(systemName: fallbackSystemName).font(.system(size: 38)).foregroundStyle(.white.opacity(0.4))
            }
        }
    }
}

/// 2:3 poster card used in rows + grids.
struct MediaPosterCard: View {
    let item: MediaItem
    var wide: Bool = false
    var onTap: (MediaItem) -> Void

    var body: some View {
        let width: CGFloat = wide ? 168 : 126
        Button { onTap(item) } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomLeading) {
                    PosterImage(url: item.posterUrl ?? item.backdropUrl)
                        .aspectRatio(2/3, contentMode: .fill)
                    LinearGradient(
                        stops: [.init(color: .clear, location: 0.48),
                                .init(color: .black.opacity(0.76), location: 1)],
                        startPoint: .top, endPoint: .bottom
                    )
                    Text(item.type.label.uppercased())
                        .font(.system(size: 9, weight: .heavy))
                        .kerning(0.7)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(9)
                }
                .frame(width: width, height: width * 1.5)
                .overlay(alignment: .topTrailing) {
                    if item.rating > 0 {
                        Text(String(format: "★ %.1f", item.rating))
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(.black.opacity(0.62), in: Capsule())
                            .padding(8)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.13), lineWidth: 1))
                .shadow(color: .black.opacity(0.40), radius: 15, y: 9)
                Text(item.title).font(.system(size: 14, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                Text(subtitle).font(.system(size: 10)).foregroundStyle(.white.opacity(0.52)).lineLimit(1)
            }
            .frame(width: width)
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        let g = item.genres.prefix(2).joined(separator: " • ")
        return g.isEmpty ? item.type.label : "\(item.type.label) • \(g)"
    }
}

/// Top-10 card with the giant gradient rank number behind the poster.
struct Top10MediaCard: View {
    let item: MediaItem
    let rank: Int
    var wide: Bool = false
    var onTap: (MediaItem) -> Void

    var body: some View {
        let cardWidth: CGFloat = wide ? 168 : 126
        let total = cardWidth + (wide ? 50 : 36)
        ZStack(alignment: .bottomLeading) {
            Text("\(rank)")
                .font(.system(size: wide ? 170 : 124, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [Color.white.opacity(0.34), Color.white.opacity(0.02)],
                                   startPoint: .top, endPoint: .bottom))
                .offset(x: wide ? -10 : -8, y: 18)
                .allowsHitTesting(false)
            HStack { Spacer()
                MediaPosterCard(item: item, wide: wide, onTap: onTap)
            }
        }
        .frame(width: total, alignment: .bottomLeading)
    }
}

/// Horizontal category rail with a tappable header.
struct CategoryRow: View {
    let category: MediaCategory
    var wide: Bool = false
    var onItem: (MediaItem) -> Void
    var onHeader: ((MediaCategory) -> Void)? = nil



    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { onHeader?(category) } label: {
                HStack(spacing: 6) {
                    Text(category.title).font(.system(size: 20, weight: .black)).tracking(-0.3).foregroundStyle(.white)
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundStyle(.white.opacity(0.82))
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, wide ? 54 : 18)
            if wide && !category.description.isEmpty {
                Text(category.description).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
                    .padding(.horizontal, 54)
            }
            if let e = category.error, !e.isEmpty {
                Text(e).font(.system(size: 12)).foregroundStyle(LiquidColors.rose.opacity(0.9))
                    .padding(.horizontal, wide ? 54 : 18)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(category.items) { item in
                        MediaPosterCard(item: item, wide: wide, onTap: onItem)
                    }
                }
                .padding(.horizontal, wide ? 54 : 18)
            }
        }
        .padding(.top, 18)
    }
}
