import SwiftUI
import UIKit

/// Welcome glass card with editable Client ID + Secret fields; connects via an
/// external browser; prominent camera "Scan Sync QR"
/// for instant cross-device sign-in (see SYNC_SPEC.md).
struct TraktOnboardingScreen: View {
    @Environment(AppState.self) private var state

    @State private var clientId = ""
    @State private var clientSecret = ""
    @State private var errorMessage: String?
    @State private var showScanner = false
    @State private var showPairingQR = false
    @State private var pairingID = ""
    @State private var secretKey = ""
    @State private var isPairing = false

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

                        if !pairingID.isEmpty {
                            Text("Already signed in on another device? Scan this QR code with its camera scanner (Settings > Scan Sync QR) to sync instantly! Or use the options below.")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineSpacing(3)
                                .multilineTextAlignment(.center)
                                .padding(.bottom, 16)

                            if let qrImg = SyncPayload.qrImage(from: "OMNIVERSE-PAIR1:\(pairingID):\(secretKey)") {
                                Image(uiImage: qrImg)
                                    .resizable()
                                    .interpolation(.none)
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 220, height: 250)
                                    .padding(12)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
                                    .padding(.bottom, 24)
                            }
                        } else {
                            Text("To open the application, please connect your Trakt.tv account. This will automatically restore all your saved watchlists, API keys, preferences, and real-time play progress from other logged-in devices!")
                                .font(.system(size: 15))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineSpacing(3)
                                .multilineTextAlignment(.center)
                                .padding(.bottom, 24)
                        }

                        VStack(spacing: 12) {
                            Text("Trakt Developer Credentials")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                            Text("Paste the Client ID and Client Secret from Trakt API Applications. You can replace them here if Trakt rejects either value.")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.62))
                                .multilineTextAlignment(.center)
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

                        if state.traktConnecting {
                            VStack(spacing: 16) {
                                ProgressView().tint(.red)
                                Text("Connecting to Trakt...").font(.system(size: 15, weight: .bold)).foregroundStyle(.white.opacity(0.7))
                            }
                        } else {
                            // Primary: scan the sync QR of another device (camera).
                            Button { showScanner = true } label: {
                                Label("Scan Another Sync QR Instead", systemImage: "qrcode.viewfinder")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 32).padding(.vertical, 16)
                                    .frame(maxWidth: .infinity)
                                    .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.white.opacity(0.15), lineWidth: 1.5))
                                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
        .onAppear {
            clientId = state.credentials.traktClientId
            clientSecret = state.credentials.traktClientSecret
            // Automatically initialize low-density pairing QR on launch
            startPairingPoll()
        }
        .onDisappear {
            isPairing = false
        }
    }

    private func startPairingPoll() {
        Task {
            let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
            let id = "omni_pair_" + String((0..<12).map { _ in chars.randomElement()! })
            let key = String((0..<16).map { _ in chars.randomElement()! })

            pairingID = id
            secretKey = key
            isPairing = true

            // Poll the ntfy.sh topic for remote scan confirmation
            while isPairing {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard isPairing else { break }

                guard let url = URL(string: "https://ntfy.sh/\(id)/json?poll=1") else { continue }
                if let resp = try? await Http.shared.request(url), resp.ok {
                    // Parse NDJSON lines from ntfy response
                    let lines = resp.bodyString.components(separatedBy: "\n").filter { !$0.trimmed.isEmpty }
                    for line in lines {
                        guard let data = line.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let event = obj["event"] as? String, event == "message",
                              let encryptedPayload = (obj["message"] as? String)?.trimmed,
                              !encryptedPayload.isEmpty && encryptedPayload != "WAITING" else { continue }

                        isPairing = false
                        if let decrypted = SimpleAES.decrypt(encryptedPayload, key: secretKey) {
                            let ok = await state.applySyncString(decrypted)
                            if ok {
                                showPairingQR = false
                                await state.refreshTraktPlayback()
                            }
                        }
                        break
                    }
                }
            }
        }
    }

    private func connect() {
        errorMessage = nil
        Task {
            let normalizedClientId = clientId.normalizedTraktCredential
            let normalizedClientSecret = clientSecret.normalizedTraktCredential
            if normalizedClientId.isEmpty {
                errorMessage = "Please enter your Trakt Client ID."
                return
            }
            var c = state.credentials
            c.traktClientId = normalizedClientId
            c.traktClientSecret = normalizedClientSecret
            await state.saveCredentials(c)
            guard let url = await state.startTraktBrowserAuth() else {
                errorMessage = state.message ?? "Could not open Trakt sign in."
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
