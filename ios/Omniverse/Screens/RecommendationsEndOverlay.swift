import SwiftUI

/// Full-screen "You're all caught up · Because you watched …" overlay shown when
/// a movie or the last episode of a show finishes and there's nothing left to
/// autoplay. Tapping a recommendation opens its detail screen.
struct RecommendationsEndOverlay: View {
    let showTitle: String
    let recommendations: [MediaItem]?
    let loading: Bool
    var onSelect: (MediaItem) -> Void
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("You're all caught up").font(.system(size: 26, weight: .black)).foregroundStyle(.white)
                        Text("Because you watched \(showTitle)")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white).frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }.buttonStyle(.plain)
                }

                if loading {
                    Spacer()
                    ProgressView().tint(LiquidColors.cyan).frame(maxWidth: .infinity)
                    Spacer()
                } else if let recs = recommendations, !recs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(recs) { rec in
                                MediaPosterCard(item: rec) { tapped in onSelect(tapped) }
                                    .frame(width: 132)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    Spacer()
                } else {
                    Spacer()
                    Text("No recommendations available.")
                        .font(.system(size: 15)).foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                    Spacer()
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 36)
        }
        .transition(.opacity)
    }
}
