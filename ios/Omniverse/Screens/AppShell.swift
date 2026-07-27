import SwiftUI

/// Root tabbed shell. Tab visibility is computed from credentials/settings,
/// mirroring app_shell.dart. Uses a floating glass tab bar (Apple-TV vibe)
/// that adapts to size class, with a left rail on wide/landscape layouts.
struct AppShell: View {
    @Environment(AppState.self) private var state
    @State private var activeTabId: String = "home"

    struct Tab: Identifiable {
        let id: String
        let title: String
        let icon: String
        let selectedIcon: String
    }

    private var tabs: [Tab] {
        var t: [Tab] = []
        if state.settings.showMoviesTv {
            t.append(Tab(id: "home", title: "Home", icon: "house", selectedIcon: "house.fill"))
            t.append(Tab(id: "movies", title: "Movies", icon: "film", selectedIcon: "film.fill"))
            t.append(Tab(id: "shows", title: "Shows", icon: "tv", selectedIcon: "tv.fill"))
        }
        if state.settings.showLiveTv {
            t.append(Tab(id: "livetv", title: "Live TV", icon: "play.tv", selectedIcon: "play.tv.fill"))
        }
        t.append(Tab(id: "search", title: "Search", icon: "magnifyingglass", selectedIcon: "magnifyingglass"))
        t.append(Tab(id: "settings", title: "Settings", icon: "gearshape", selectedIcon: "gearshape.fill"))
        return t
    }

    private var currentTabId: String {
        let available = tabs
        if available.contains(where: { $0.id == activeTabId }) {
            return activeTabId
        }
        return available.first?.id ?? "settings"
    }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 820
            let safeTabs = tabs
            let active = currentTabId
            ZStack(alignment: wide ? .top : .bottom) {
                LiquidBackdrop()
                screen(for: active)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    .padding(.top, (wide && active != "home") ? 70 : 0)
                    .animation(.spring(response: 0.38, dampingFraction: 0.80), value: active)

                if wide {
                    GlassTopBar(tabs: safeTabs, activeTabId: $activeTabId)
                        .padding(.top, 8)
                } else {
                    GlassTabBar(tabs: safeTabs, activeTabId: $activeTabId)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(LiquidColors.cyan)
        .overlay(alignment: .top) { MessageBanner() }
    }

    @ViewBuilder
    private func screen(for id: String) -> some View {
        switch id {
        case "home": HomeScreen()
        case "movies": HomeScreen()
        case "shows": HomeScreen()
        case "livetv": LiveTvScreen()
        case "search": SearchScreen()
        default: SettingsScreen()
        }
    }
}

/// Floating bottom glass tab bar (compact width).
struct GlassTabBar: View {
    let tabs: [AppShell.Tab]
    @Binding var activeTabId: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tabs) { tab in
                    let selected = tab.id == activeTabId
                    Button {
                        withAnimation(.spring(response: 0.40, dampingFraction: 0.78)) {
                            activeTabId = tab.id
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: selected ? tab.selectedIcon : tab.icon)
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 18)
                            if selected {
                                Text(tab.title)
                                    .font(.system(size: 13, weight: .heavy))
                                    .fixedSize()
                                    .transition(.opacity.combined(with: .scale))
                            }
                        }
                        .foregroundStyle(selected ? LiquidColors.ink : Color.white.opacity(0.75))
                        .padding(.horizontal, selected ? 16 : 12)
                        .frame(height: 42)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(LiquidColors.cyan)
                                    .shadow(color: LiquidColors.cyan.opacity(0.42), radius: 10, y: 3)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
        }
        .scrollIndicators(.hidden)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
        .shadow(color: .black.opacity(0.40), radius: 22, y: 10)
    }
}

/// Centered top navigation bar for iPad / landscape.
struct GlassTopBar: View {
    let tabs: [AppShell.Tab]
    @Binding var activeTabId: String

    var body: some View {
        HStack(spacing: 6) {
            Image("AppLogo")
                .resizable().aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.trailing, 6)

            ForEach(tabs) { tab in
                let selected = tab.id == activeTabId
                Button {
                    withAnimation(.spring(response: 0.40, dampingFraction: 0.78)) {
                        activeTabId = tab.id
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: selected ? tab.selectedIcon : tab.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 22)
                        if selected {
                            Text(tab.title)
                                .font(.system(size: 15, weight: .heavy))
                                .fixedSize()
                                .transition(.opacity.combined(with: .scale))
                        }
                    }
                    .foregroundStyle(selected ? LiquidColors.ink : Color.white.opacity(0.82))
                    .padding(.horizontal, selected ? 18 : 12)
                    .frame(height: 46)
                    .background {
                        if selected {
                            Capsule().fill(LiquidColors.cyan)
                                .shadow(color: LiquidColors.cyan.opacity(0.45), radius: 14, y: 4)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(
            LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0.08)],
                           startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
    }
}

/// Left glass rail (wide/landscape, Apple-TV sidebar feel).
/// Auto-expands between collapsed (icons only) and expanded (icon + label) on a
/// tap of the chevron, or on hover/focus; collapses otherwise. Smooth spring.
struct GlassRail: View {
    let tabs: [AppShell.Tab]
    @Binding var selection: Int
    @Environment(AppState.self) private var state

    @State private var pinned = false
    @State private var hovering = false

    private let collapsedWidth: CGFloat = 64
    private let expandedWidth: CGFloat = 240
    private var expanded: Bool { pinned || hovering }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Top: hamburger / chevron toggle.
            Button {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { pinned.toggle() }
            } label: {
                Image(systemName: expanded ? "chevron.left" : "line.3.horizontal")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 52, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 4)

            ForEach(Array(tabs.enumerated()), id: \.element.id) { i, tab in
                Button { withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { selection = i } } label: {
                    railRow(tab: tab, isSelected: i == selection)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Bottom: logo + (if Trakt) username, Apple-TV style.
            HStack(spacing: 12) {
                Image("AppLogo")
                    .resizable().aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                if expanded {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Omniverse")
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        if state.credentials.hasTraktUser && !state.credentials.traktUsername.isEmpty {
                            Text(state.credentials.traktUsername)
                                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                                .lineLimit(1)
                        }
                    }
                    .transition(.opacity)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 36)
            .padding(.leading, 10)
        }
        .frame(width: expanded ? expandedWidth : collapsedWidth, alignment: .leading)
        .padding(.vertical, 18)
        .padding(.horizontal, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .onHover { h in withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { hovering = h } }
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: expanded)
    }

    @ViewBuilder
    private func railRow(tab: AppShell.Tab, isSelected: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(isSelected ? LiquidColors.ink : Color.white.opacity(0.7))
                .frame(width: 52, height: 52)
            if expanded {
                Text(tab.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? LiquidColors.ink : Color.white.opacity(0.8))
                    .lineLimit(1)
                    .transition(.opacity)
                Spacer(minLength: 0)
            }
        }
        .padding(.trailing, expanded ? 12 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(LiquidColors.cyan)
                    .shadow(color: LiquidColors.cyan.opacity(0.5), radius: 12)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Transient status message toast bound to state.message.
struct MessageBanner: View {
    @Environment(AppState.self) private var state
    var body: some View {
        if let msg = state.message, !msg.isEmpty {
            Text(msg)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: msg) {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await MainActor.run { state.message = nil }
                }
        }
    }
}
