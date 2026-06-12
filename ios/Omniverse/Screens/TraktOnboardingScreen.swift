import SwiftUI
import UIKit

/// Welcome glass card; optional Client ID + Secret fields when no Trakt app is
/// configured; connect via external browser; prominent camera "Scan Sync QR"
/// for instant cross-device sign-in (see SYNC_SPEC.md).
struct TraktOnboardingScreen: View {
    @Environment(AppState.self) private var state

    @State private var clientId = ""
    @State private var clientSecret = ""
    @State private var errorMessage: String?
    @State private var showScanner = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x041517), LiquidColors.ink, Color(hex: 0x13060E)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                GlassPanel(cornerRadius: 28, padding: 0) {
                    VStack(spacing: 0) {
                        // Trakt logo circle
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.15))
                                .overlay(Circle().strokeBorder(Color.red.opacity(0.4), lineWidth: 1.5))
                                .frame(width: 80, height: 80)
                            Image(systemName: "heart.circle.fill").font(.system(size: 48)).foregroundStyle(.red)
                        }
                        .padding(.bottom, 24)

                        Text("Welcome to Omniverse")
                            .font(.system(size: 28, weight: .black))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 12)

                        Text("To open the application, please connect your Trakt.tv account. This will automatically restore all your saved watchlists, API keys, preferences, and real-time play progress from other logged-in devices!")
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineSpacing(3)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 24)

                        if !state.credentials.hasTraktApp {
                            VStack(spacing: 12) {
                                TextField("", text: $clientId, prompt: Text("Trakt Client ID").foregroundColor(.white.opacity(0.4)))
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12).padding(.vertical, 12)
                                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                                SecureField("", text: $clientSecret, prompt: Text("Trakt Client Secret").foregroundColor(.white.opacity(0.4)))
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12).padding(.vertical, 12)
                                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                            }
                            .padding(.bottom, 24)
                        }

                        if state.traktConnecting {
                            VStack(spacing: 16) {
                                ProgressView().tint(.red)
                                Text("Connecting to Trakt...").font(.system(size: 15, weight: .bold)).foregroundStyle(.white.opacity(0.7))
                            }
                        } else {
                            // Primary: instant cross-device sign-in via camera.
                            Button { showScanner = true } label: {
                                Label("Scan Sync QR", systemImage: "qrcode.viewfinder")
                                    .font(.system(size: 16, weight: .black))
                                    .foregroundStyle(LiquidColors.ink)
                                    .padding(.horizontal, 32).padding(.vertical, 16)
                                    .frame(maxWidth: .infinity)
                                    .background(LiquidColors.cyan, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                                    .shadow(color: LiquidColors.cyan.opacity(0.5), radius: 16)
                            }
                            .buttonStyle(.plain)
                            .padding(.bottom, 12)

                            Text("or sign in directly")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.4))
                                .padding(.bottom, 12)

                            Button { connect() } label: {
                                Label("Connect Trakt.tv Account", systemImage: "person.crop.circle.fill")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 32).padding(.vertical, 16)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.red, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 13)).foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.top, 16)
                        }

                        if let msg = state.message, msg.contains("Trakt") {
                            Text(msg)
                                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.54))
                                .multilineTextAlignment(.center)
                                .padding(.top, 16)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 36)
                    .frame(maxWidth: 480)
                }
                .padding(28)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .tint(LiquidColors.cyan)
        .sheet(isPresented: $showScanner) {
            SyncScannerSheet { restoreFromQR($0) }
        }
    }

    private func connect() {
        errorMessage = nil
        Task {
            if state.credentials.traktClientId.trimmed.isEmpty && clientId.trimmed.isEmpty {
                errorMessage = "Please enter your Trakt Client ID."
                return
            }
            if !clientId.trimmed.isEmpty {
                var c = state.credentials
                c.traktClientId = clientId.trimmed
                c.traktClientSecret = clientSecret.trimmed
                await state.saveCredentials(c)
            }
            guard let url = state.startTraktBrowserAuth() else {
                errorMessage = "Could not open Trakt sign in."
                return
            }
            let opened = await UIApplication.shared.open(url)
            if !opened { errorMessage = "Could not open Trakt sign in." }
        }
    }

    /// OMNIVERSE-SYNC1 payload → restore full Trakt + API credentials and settings.
    /// On success the onboarding gate passes (Trakt tokens restored) and the view dismisses.
    private func restoreFromQR(_ scanned: String) {
        errorMessage = nil
        Task {
            let ok = await state.applySyncString(scanned)
            if ok {
                await state.refreshTraktPlayback()
            } else if !scanned.trimmed.hasPrefix("http") {
                errorMessage = "Could not restore credentials from scanned QR code."
            }
        }
    }
}
