import SwiftUI

/// Root tabbed shell. Tab visibility is computed from credentials/settings,
/// mirroring app_shell.dart. Uses a floating glass tab bar (Apple-TV vibe)
/// that adapts to size class, with a left rail on wide/landscape layouts.
struct AppShell: View {
    @Environment(AppState.self) private var state
    @State private var selection = 0

    struct Tab: Identifiable {
        let id: String
        let title: String
        let icon: String
        let selectedIcon: String
    }

    private var tabs: [Tab] {
        var t: [Tab] = []
        if state.settings.showMoviesTv && state.credentials.hasTmdb {
            t.append(Tab(id: "home", title: "Home", icon: "house", selectedIcon: "house.fill"))
        }
        if state.credentials.hasPixeldrain {
            t.append(Tab(id: "onepace", title: "One Pace", icon: "play.circle", selectedIcon: "play.circle.fill"))
        }
        if state.settings.showLiveTv {
            t.append(Tab(id: "livetv", title: "LiveTV", icon: "tv", selectedIcon: "tv.fill"))
        }
        t.append(Tab(id: "settings", title: "Settings", icon: "gearshape", selectedIcon: "gearshape.fill"))
        if state.credentials.hasTmdb {
            t.append(Tab(id: "search", title: "Search", icon: "magnifyingglass", selectedIcon: "magnifyingglass"))
        }
        return t
    }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 820
            let safeTabs = tabs
            let idx = min(selection, max(0, safeTabs.count - 1))
            let activeId = safeTabs.isEmpty ? "settings" : safeTabs[idx].id
            ZStack(alignment: wide ? .top : .bottom) {
                LiquidBackdrop()
                // Home stays full-bleed so the glass top bar floats over the hero
                // (Apple glass look). Other screens get a top inset so their
                // headers/content aren't covered by the floating bar.
                screen(for: activeId)
                    .padding(.top, (wide && activeId != "home") ? 70 : 0)

                if wide {
                    GlassTopBar(tabs: safeTabs, selection: $selection)
                        .padding(.top, 8)
                } else {
                    GlassTabBar(tabs: safeTabs, selection: $selection)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 8)
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
        case "onepace": OnePaceScreen()
        case "livetv": LiveTvScreen()
        case "search": SearchScreen()
        default: SettingsScreen()
        }
    }
}

/// Floating bottom glass tab bar (compact width).
struct GlassTabBar: View {
    let tabs: [AppShell.Tab]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { i, tab in
                Button { withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { selection = i } } label: {
                    VStack(spacing: 3) {
                        Image(systemName: i == selection ? tab.selectedIcon : tab.icon)
                            .font(.system(size: 20, weight: .semibold))
                        Text(tab.title).font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(i == selection ? LiquidColors.cyan : Color.white.opacity(0.62))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        if i == selection {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(LiquidColors.cyan.opacity(0.16))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 22, y: 10)
    }
}

/// Apple-TV style centered top navigation bar for iPad / landscape.
/// Uniform centered icons floating in a vivid liquid-glass capsule; the selected
/// tab "blows up" into a cyan pill that reveals its label with a spring.
struct GlassTopBar: View {
    let tabs: [AppShell.Tab]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 6) {
            Image("AppLogo")
                .resizable().aspectRatio(contentMode: .fit)
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.trailing, 6)

            ForEach(Array(tabs.enumerated()), id: \.element.id) { i, tab in
                let selected = i == selection
                Button {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { selection = i }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: selected ? tab.selectedIcon : tab.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 22)            // uniform icon column
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
