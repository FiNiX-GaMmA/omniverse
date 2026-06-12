import SwiftUI
import UIKit

/// Vidsrc embed domains, ported verbatim from `VidsrcRepository.embedDomains`.
private let vidsrcEmbedDomains = ["vidsrc-embed.ru", "vidsrc-embed.su", "vidsrcme.su", "vsrc.su"]

/// Subtitle languages, ported verbatim from `settings_screen.dart`.
private let subtitleLanguageOptions: [(code: String, name: String)] = [
    ("en", "English"), ("es", "Spanish"), ("fr", "French"), ("de", "German"),
    ("it", "Italian"), ("pt", "Portuguese"), ("ja", "Japanese"), ("ko", "Korean"),
    ("zh", "Chinese"), ("ar", "Arabic"), ("hi", "Hindi"),
]

/// Three tabs (API KEYS / PREFERENCES / CLOUD SYNC), a fixed SAVE ALL CHANGES
/// button, secret fields with eye-toggle + copy, Trakt / AniList connect, and the
/// server-less cross-device Sync QR (show / scan) per SYNC_SPEC.md.
struct SettingsScreen: View {
    @Environment(AppState.self) private var state

    private enum Tab: Int, CaseIterable { case apiKeys, preferences, cloudSync
        var title: String {
            switch self {
            case .apiKeys: return "API KEYS"
            case .preferences: return "PREFERENCES"
            case .cloudSync: return "CLOUD SYNC"
            }
        }
    }
    @State private var tab: Tab = .apiKeys

    // API keys
    @State private var tmdb = ""
    @State private var tvdb = ""
    @State private var tvdbPin = ""
    @State private var traktId = ""
    @State private var traktSecret = ""
    @State private var pixeldrainApiKey = ""
    @State private var anilistAccessToken = ""

    // Preferences
    @State private var language = ""
    @State private var region = ""
    @State private var subtitleUrl = ""
    @State private var subtitleLanguage = "en"
    @State private var vidsrcDomain = "vidsrc-embed.ru"
    @State private var includeAdult = false
    @State private var tvMode = false
    @State private var preferDubbedAnime = false
    @State private var showMoviesTv = true
    @State private var showAnime = true
    @State private var showLiveTv = true

    @State private var seeded = false
    @State private var localMessage: String?

    // Sync QR
    @State private var showSyncQR = false
    @State private var showScanner = false
    @State private var syncString = ""

    // Manual "Sync Now"
    @State private var syncing = false
    // Manual "Restore from Cloud"
    @State private var restoring = false

    private var statusMessage: String? { localMessage ?? state.message }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            ScrollView {
                switch tab {
                case .apiKeys: apiKeysTab
                case .preferences: preferencesTab
                case .cloudSync: cloudSyncTab
                }
            }
            .scrollIndicators(.hidden)
            saveButton
        }
        .navigationTitle("Settings")
        .liquidScaffold()
        .onAppear(perform: seed)
        .sheet(isPresented: $showSyncQR) { SyncQRSheet() }
        .sheet(isPresented: $showScanner) {
            SyncScannerSheet { handleScanned($0) }
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.rawValue) { t in
                Button { tab = t } label: {
                    VStack(spacing: 8) {
                        Text(t.title)
                            .font(.system(size: 14, weight: .black))
                            .kerning(0.5)
                            .foregroundStyle(tab == t ? .white : .white.opacity(0.6))
                        Rectangle()
                            .fill(tab == t ? LiquidColors.cyan : .clear)
                            .frame(height: 3)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Tab 1: API keys

    private var apiKeysTab: some View {
        VStack(spacing: 24) {
            infoPanel("Live & Secret API keys can be managed securely. All credentials, secret tokens, and application identifiers are encrypted locally and stored within your device's system keychain.")
            section("Secret API Credentials") {
                SecretField(text: $tmdb, label: "TheMovieDB (TMDB) token", hint: "TMDB API key or v4 bearer token", onCopy: copy)
                SecretField(text: $tvdb, label: "TVDB v4 API key", hint: "E.g., tvdb_api_key_xxxxxxxx", onCopy: copy)
                SecretField(text: $tvdbPin, label: "TVDB Subscriber PIN (optional)", hint: "Enter your custom subscriber pin", onCopy: copy)
                SecretField(text: $pixeldrainApiKey, label: "Pixeldrain API key", hint: "Used for secure One Pace video streams", onCopy: copy)
                SecretField(text: $anilistAccessToken, label: "AniList Access Token", hint: "Required for real-time completed scrobbling", onCopy: copy)
            }
            section("Trakt Developer Client Keys") {
                SecretField(text: $traktId, label: "Trakt Client ID", hint: "Used to authorize Trakt.tv account syncing", onCopy: copy)
                SecretField(text: $traktSecret, label: "Trakt Client Secret", hint: "Secure Trakt app authorization secret", onCopy: copy)
            }
        }
        .padding(EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24))
    }

    // MARK: - Tab 2: Preferences

    private var preferencesTab: some View {
        VStack(spacing: 24) {
            section("Discovery preferences") {
                HStack(spacing: 16) {
                    LabeledField(label: "Language", text: $language)
                    LabeledField(label: "Region", text: $region)
                }
                .padding(.bottom, 4)
                PickerField(label: "Preferred Vidsrc server", selection: $vidsrcDomain,
                            options: vidsrcEmbedDomains.map { ($0, $0) })
            }
            section("Subtitle configurations") {
                PickerField(label: "Subtitle language", selection: $subtitleLanguage,
                            options: subtitleLanguageOptions.map { ($0.code, $0.name) })
                LabeledField(label: "Default subtitle URL", text: $subtitleUrl, hint: "https://example.com/subtitles.vtt")
            }
            section("Display & Content Toggles") {
                ToggleRow("Show Movies & TV shows", $showMoviesTv)
                ToggleRow("Show Anime list", $showAnime)
                ToggleRow("Enable Live TV channels", $showLiveTv)
                ToggleRow("Include Adult content", $includeAdult)
                ToggleRow("Enable TV / Landscape Mode", $tvMode)
                ToggleRow("Prefer Dubbed Anime", $preferDubbedAnime)
            }
        }
        .padding(EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24))
    }

    // MARK: - Tab 3: Cloud sync

    private var cloudSyncTab: some View {
        VStack(spacing: 24) {
            infoPanel("Connect accounts to sync progress and watchlists. Your watch progress, preferences, and keys are automatically synchronized in real-time across all your devices in the background.")

            syncCard(
                title: "Trakt.tv Sync Integration",
                isConnected: state.credentials.hasTraktUser,
                statusText: state.credentials.hasTraktUser
                    ? (state.credentials.traktUsername.isEmpty ? "Connected to Trakt" : "Connected as: \(state.credentials.traktUsername)")
                    : "Trakt disconnected (Sync disabled)",
                iconName: "heart.circle.fill",
                iconColor: .red
            ) {
                glassChip(state.credentials.hasTraktUser ? "Refresh Login" : "Connect Trakt",
                          system: "person.crop.circle", loading: state.traktConnecting) { connectTrakt() }
                if state.credentials.hasTraktUser {
                    glassChip("Disconnect", system: "xmark.circle") { state.disconnectTrakt() }
                }
            }

            syncCard(
                title: "Cross-Device Sign In",
                isConnected: state.credentials.hasTraktUser,
                statusText: "Move every service + your preferences to another device with a QR. No server.",
                iconName: "qrcode.viewfinder",
                iconColor: LiquidColors.cyan
            ) {
                glassChip("Show Sync QR", system: "qrcode") {
                    syncString = state.buildSyncString()
                    showSyncQR = true
                }
                glassChip("Scan Sync QR", system: "camera") { showScanner = true }
            }

            syncCard(
                title: "AniList Sync Integration",
                isConnected: state.credentials.hasAnilist,
                statusText: state.credentials.hasAnilist ? "Connected to AniList (Sync Active)" : "AniList disconnected (Sync disabled)",
                iconName: "play.circle.fill",
                iconColor: .blue
            ) {
                glassChip(state.credentials.hasAnilist ? "Refresh Login" : "Connect AniList", system: "person.crop.circle") {
                    if let url = URL(string: "https://anilist.co/api/v2/oauth/authorize?client_id=14187&response_type=token") {
                        UIApplication.shared.open(url)
                    }
                }
                if state.credentials.hasAnilist {
                    glassChip("Disconnect", system: "xmark.circle") {
                        var c = state.credentials; c.anilistAccessToken = ""
                        Task { await state.saveCredentials(c) }
                    }
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(LiquidColors.rose)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            Text("Trakt Redirect URI: omniplay://trakt/oauth\nAniList Redirect URI: omniplay://anilist/oauth")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                syncNowButton
                restoreButton
            }
        }
        .padding(EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24))
    }

    /// Manual "Sync Now" at the end of the Cloud Sync tab. Triggers an immediate
    /// background sync and shows a brief confirmation.
    private var syncNowButton: some View {
        Button {
            guard !syncing else { return }
            syncing = true
            Task {
                await state.syncNow()
                syncing = false
                localMessage = "Sync complete."
            }
        } label: {
            HStack(spacing: 8) {
                if syncing {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 16, weight: .semibold))
                }
                Text(syncing ? "Syncing..." : "Sync Now").font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(syncing)
    }

    /// "Restore from Cloud" — pulls the Trakt-backed settings + credentials backup
    /// and re-seeds the form. Mirrors the "Sync Now" button's spinner + confirmation.
    private var restoreButton: some View {
        Button {
            guard !restoring else { return }
            restoring = true
            Task {
                do {
                    try await state.restoreSettingsFromTrakt()
                    seeded = false
                    seed()
                    localMessage = "Restored from cloud."
                } catch {
                    localMessage = "Restore failed. Connect Trakt and sync first."
                }
                restoring = false
            }
        } label: {
            HStack(spacing: 8) {
                if restoring {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: "icloud.and.arrow.down").font(.system(size: 16, weight: .semibold))
                }
                Text(restoring ? "Restoring..." : "Restore from Cloud").font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(restoring)
    }

    // MARK: - Save button

    private var saveButton: some View {
        Button { Task { await save() } } label: {
            Label("SAVE ALL CHANGES", systemImage: "checkmark")
                .font(.system(size: 15, weight: .black))
                .kerning(0.5)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(LiquidColors.cyan, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(EdgeInsets(top: 12, leading: 24, bottom: 24, trailing: 24))
    }

    // MARK: - Reusable building blocks

    private func section<C: View>(_ title: String, @ViewBuilder content: @escaping () -> C) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func infoPanel(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill").font(.system(size: 18)).foregroundStyle(LiquidColors.cyan)
            Text(text).font(.system(size: 13)).foregroundStyle(.white.opacity(0.7)).lineSpacing(3)
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }

    private func syncCard<C: View>(title: String, isConnected: Bool, statusText: String,
                                   iconName: String, iconColor: Color,
                                   @ViewBuilder actions: @escaping () -> C) -> some View {
        GlassPanel(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: iconName).font(.system(size: 28)).foregroundStyle(iconColor)
                    Text(title).font(.system(size: 16, weight: .black)).foregroundStyle(.white)
                }
                HStack(spacing: 8) {
                    Image(systemName: isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 16)).foregroundStyle(isConnected ? LiquidColors.cyan : .white.opacity(0.3))
                    Text(statusText)
                        .font(.system(size: 13, weight: isConnected ? .bold : .regular))
                        .foregroundStyle(isConnected ? .white : .white.opacity(0.38))
                }
                Divider().overlay(Color.white.opacity(0.1))
                FlowChips { actions() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func glassChip(_ label: String, system: String, loading: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if loading {
                    ProgressView().controlSize(.mini).tint(.white)
                } else {
                    Image(systemName: system).font(.system(size: 14, weight: .semibold))
                }
                Text(label).font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(loading)
    }

    // MARK: - Actions

    private func seed() {
        guard !seeded else { return }
        tmdb = state.credentials.tmdbToken
        tvdb = state.credentials.tvdbApiKey
        tvdbPin = state.credentials.tvdbPin
        traktId = state.credentials.traktClientId
        traktSecret = state.credentials.traktClientSecret
        pixeldrainApiKey = state.credentials.pixeldrainApiKey
        anilistAccessToken = state.credentials.anilistAccessToken
        language = state.settings.language
        region = state.settings.region
        subtitleUrl = state.settings.subtitleUrl
        subtitleLanguage = state.settings.subtitleLanguage.trimmed.isEmpty ? "en" : state.settings.subtitleLanguage.trimmed
        vidsrcDomain = vidsrcEmbedDomains.contains(state.settings.vidsrcDomain) ? state.settings.vidsrcDomain : vidsrcEmbedDomains[0]
        includeAdult = state.settings.includeAdult
        tvMode = state.settings.tvMode
        preferDubbedAnime = state.settings.preferDubbedAnime
        showMoviesTv = state.settings.showMoviesTv
        showAnime = state.settings.showAnime
        showLiveTv = state.settings.showLiveTv
        seeded = true
    }

    private func copy(_ text: String) {
        let t = text.trimmed
        guard !t.isEmpty else { return }
        UIPasteboard.general.string = t
        localMessage = "Copied key to clipboard!"
    }

    @MainActor
    private func save() async {
        var c = state.credentials
        c.tmdbToken = tmdb
        c.tvdbApiKey = tvdb
        c.tvdbPin = tvdbPin
        c.traktClientId = traktId
        c.traktClientSecret = traktSecret
        c.pixeldrainApiKey = pixeldrainApiKey
        c.anilistAccessToken = anilistAccessToken
        await state.saveCredentials(c)

        var s = state.settings
        s.language = language.trimmed.isEmpty ? "en-US" : language.trimmed
        s.region = region.trimmed.isEmpty ? "US" : region.trimmed.uppercased()
        s.includeAdult = includeAdult
        s.tvMode = tvMode
        s.vidsrcDomain = vidsrcDomain
        s.subtitleUrl = subtitleUrl.trimmed
        s.subtitleLanguage = subtitleLanguage.trimmed.isEmpty ? "en" : subtitleLanguage.trimmed
        s.preferDubbedAnime = preferDubbedAnime
        s.showMoviesTv = showMoviesTv
        s.showAnime = showAnime
        s.showLiveTv = showLiveTv
        await state.saveSettings(s)

        localMessage = "Saved. Refreshing rows with the new settings."
    }

    private func connectTrakt() {
        Task {
            await save()
            if let url = state.startTraktBrowserAuth() {
                let opened = await UIApplication.shared.open(url)
                localMessage = opened
                    ? "Sign in to Trakt in the browser. Omniverse will reconnect automatically."
                    : "Could not open Trakt sign in."
            } else {
                localMessage = "Could not open Trakt sign in."
            }
        }
    }

    /// Handles a scanned/pasted Sync QR via AppState (http(s) opens externally,
    /// OMNIVERSE-SYNC1 restores creds + settings).
    private func handleScanned(_ scanned: String) {
        Task {
            let ok = await state.applySyncString(scanned)
            if ok {
                seeded = false
                seed()
                localMessage = "Signed in from Sync QR!"
            }
        }
    }
}

// MARK: - Field components

/// Secret text field with an eye toggle and a copy button (parity with `_SecretField`).
struct SecretField: View {
    @Binding var text: String
    let label: String
    var hint: String = ""
    var onCopy: (String) -> Void
    @State private var obscure = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Group {
                        if obscure {
                            SecureField("", text: $text, prompt: Text(hint).foregroundColor(.white.opacity(0.4)))
                        } else {
                            TextField("", text: $text, prompt: Text(hint).foregroundColor(.white.opacity(0.4)))
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(.white)
                    Button { obscure.toggle() } label: {
                        Image(systemName: obscure ? "eye.slash" : "eye").font(.system(size: 18)).foregroundStyle(.white.opacity(0.7))
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.vertical, 12)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.3), lineWidth: 1))

                Button { onCopy(text) } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 18)).foregroundStyle(.white.opacity(0.7))
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            }
        }
        .padding(.bottom, 16)
    }
}

/// Plain labeled text field (outline style, parity with Material `OutlineInputBorder`).
struct LabeledField: View {
    let label: String
    @Binding var text: String
    var hint: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
            TextField("", text: $text, prompt: Text(hint).foregroundColor(.white.opacity(0.4)))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 12)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
        }
    }
}

/// Dropdown picker rendered as a labeled Menu (parity with `DropdownButtonFormField`).
struct PickerField: View {
    let label: String
    @Binding var selection: String
    let options: [(value: String, label: String)]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
            Menu {
                ForEach(options, id: \.value) { opt in
                    Button(opt.label) { selection = opt.value }
                }
            } label: {
                HStack {
                    Text(options.first { $0.value == selection }?.label ?? selection).foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 12).padding(.vertical, 12)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
            }
        }
        .padding(.bottom, 4)
    }
}

/// Switch row (parity with `SwitchListTile`).
struct ToggleRow: View {
    let title: String
    @Binding var value: Bool
    init(_ title: String, _ value: Binding<Bool>) { self.title = title; self._value = value }
    var body: some View {
        Toggle(isOn: $value) {
            Text(title).font(.system(size: 15)).foregroundStyle(.white)
        }
        .tint(LiquidColors.cyan)
        .padding(.vertical, 4)
    }
}

/// Simple wrapping chip layout (replacement for Flutter `Wrap`).
struct FlowChips<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        // iOS 17: a wrapping HStack via a Layout is overkill here; the chip
        // count is small, so a lazy grid with adaptive sizing wraps cleanly.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { content() }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) { content() }
            }
        }
    }
}
